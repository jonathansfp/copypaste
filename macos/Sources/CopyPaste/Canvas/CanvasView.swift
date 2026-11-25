import AppKit
import Combine

/// Interactive vector canvas: draws, selects, moves, resizes and edits text of `CanvasModel` shapes.
/// Flipped (top-left origin), so it lines up with screenshots and text layout.
class CanvasView: NSView, NSTextViewDelegate {
    let model: CanvasModel
    let env = RenderEnv()
    /// Shapes are drawn and created only inside this rect (`nil` = whole view).
    var drawingArea: CGRect? { didSet { window?.invalidateCursorRects(for: self) } }
    /// Owner gets every key first; return true when handled.
    var onKey: ((NSEvent) -> Bool)?
    var onDoubleClickEmpty: (() -> Void)?

    private var bag: Set<AnyCancellable> = []

    // Interaction state
    private enum Drag {
        case none
        case creating(Shape)
        case moving(start: CGPoint, original: [UUID: [CGPoint]])
        case resizing(id: UUID, handle: Int, original: Shape)
        case marquee(start: CGPoint, current: CGPoint)
        case erasing
        case laser
    }
    private var drag: Drag = .none
    private var didCheckpoint = false
    private var editor: CanvasTextView?
    private(set) var editingID: UUID?
    private var laserPoints: [(CGPoint, CFTimeInterval)] = []
    private var laserTimer: Timer?

    init(model: CanvasModel) {
        self.model = model
        super.init(frame: .zero)
        model.changed
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.needsDisplay = true }
            .store(in: &bag)
        model.$tool
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.commitText()
                self.window?.invalidateCursorRects(for: self)
            }
            .store(in: &bag)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var area: CGRect { drawingArea ?? bounds }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawBackground(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: area)
        for s in model.shapes {
            guard s.bounds.intersects(dirtyRect) else { continue }
            if s.id == editingID {
                if s.kind == .text { continue }
                var hidden = s; hidden.text = ""
                ShapeRenderer.draw(hidden, env: env)
            } else {
                ShapeRenderer.draw(s, env: env)
            }
        }
        if case .creating(let s) = drag { ShapeRenderer.draw(s, env: env) }
        drawLaser(ctx)
        ctx.restoreGState()
        drawSelection(ctx)
        drawOverlay(dirtyRect)
    }

    /// Subclass hooks.
    func drawBackground(_ dirtyRect: NSRect) {}
    func drawOverlay(_ dirtyRect: NSRect) {}

    private func drawSelection(_ ctx: CGContext) {
        let accent = NSColor.controlAccentColor
        if case .marquee(let a, let b) = drag {
            let r = rectFrom(a, b)
            ctx.setFillColor(accent.withAlphaComponent(0.08).cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(r)
        }
        guard model.tool == .select || !model.selection.isEmpty else { return }
        let sel = model.selectedShapes
        for s in sel {
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [5, 3])
            if s.kind.isLinear {
                ctx.setLineDash(phase: 0, lengths: [])
            } else {
                ctx.stroke(s.bounds.insetBy(dx: -3, dy: -3))
            }
            ctx.setLineDash(phase: 0, lengths: [])
            if sel.count == 1 {
                for h in handles(for: s) {
                    let r = CGRect(x: h.x - 5, y: h.y - 5, width: 10, height: 10)
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fillEllipse(in: r)
                    ctx.setStrokeColor(accent.cgColor)
                    ctx.strokeEllipse(in: r)
                }
            }
        }
    }

    private func drawLaser(_ ctx: CGContext) {
        guard laserPoints.count > 1 else { return }
        let now = CACurrentMediaTime()
        ctx.setLineCap(.round)
        for i in 1..<laserPoints.count {
            let age = now - laserPoints[i].1
            let alpha = max(0, 1 - age / 0.9)
            guard alpha > 0 else { continue }
            ctx.setShadow(offset: .zero, blur: 10, color: NSColor.systemRed.withAlphaComponent(alpha).cgColor)
            ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(6 * alpha + 2)
            ctx.move(to: laserPoints[i - 1].0)
            ctx.addLine(to: laserPoints[i].0)
            ctx.strokePath()
        }
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }

    // MARK: Handles

    /// Resize handles: corners/edges for boxes, endpoints for lines.
    private func handles(for s: Shape) -> [CGPoint] {
        if s.kind.isLinear { return [s.points.first!, s.points.last!] }
        guard s.kind.isBox else { return [] }
        let r = s.rect
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    private func handleHit(_ p: CGPoint) -> (Shape, Int)? {
        guard model.selection.count == 1, let s = model.selectedShapes.first else { return nil }
        for (i, h) in handles(for: s).enumerated() where hypot(h.x - p.x, h.y - p.y) <= 8 {
            return (s, i)
        }
        return nil
    }

    private func applyResize(_ o: Shape, handle: Int, to p: CGPoint, constrain: Bool) -> Shape {
        var s = o
        if o.kind.isLinear {
            var q = p
            let fixed = handle == 0 ? o.points.last! : o.points.first!
            if constrain { q = snap45(from: fixed, to: p) }
            s.points = handle == 0 ? [q, fixed] : [fixed, q]
            return s
        }
        var r = o.rect
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case 0: minX = p.x; minY = p.y
        case 1: minY = p.y
        case 2: maxX = p.x; minY = p.y
        case 3: maxX = p.x
        case 4: maxX = p.x; maxY = p.y
        case 5: maxY = p.y
        case 6: minX = p.x; maxY = p.y
        default: minX = p.x
        }
        r = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        if constrain || o.kind == .image, o.rect.height > 0 {
            let ratio = o.rect.width / o.rect.height
            r.size.height = r.width / ratio
        }
        s.points = [r.origin, CGPoint(x: r.maxX, y: r.maxY)]
        return s
    }

    // MARK: Mouse

    func point(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        let a = area
        return CGPoint(x: min(max(p.x, a.minX), a.maxX), y: min(max(p.y, a.minY), a.maxY))
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(e)
        commitText()
        didCheckpoint = false

        if e.clickCount == 2 {
            if let s = topShape(at: p), s.kind == .text || s.kind.acceptsLabel {
                beginEditing(s)
                return
            }
            if topShape(at: p) == nil { onDoubleClickEmpty?() }
        }

        if let (s, h) = handleHit(p) {
            drag = .resizing(id: s.id, handle: h, original: s)
            return
        }

        switch model.tool {
        case .select:
            if let s = topShape(at: p) {
                if e.modifierFlags.contains(.shift) {
                    if model.selection.contains(s.id) { model.selection.remove(s.id) } else { model.selection.insert(s.id) }
                } else if !model.selection.contains(s.id) {
                    model.selection = [s.id]
                }
                beginMove(at: p, duplicate: e.modifierFlags.contains(.option))
            } else {
                model.selection = []
                drag = .marquee(start: p, current: p)
            }
        case .eraser:
            drag = .erasing
            erase(at: p)
        case .laser:
            drag = .laser
            addLaser(p)
        case .draw(let kind):
            // Clicking an existing shape with a drawing tool still lets you grab it.
            if !model.selection.isEmpty, let s = topShape(at: p), model.selection.contains(s.id) {
                beginMove(at: p, duplicate: false)
                return
            }
            model.selection = []
            switch kind {
            case .step:
                model.checkpoint()
                var s = Shape(kind: .step, points: [p], style: model.style)
                s.number = model.nextStepNumber
                model.shapes.append(s)
            case .text:
                let s = Shape(kind: .text, points: [CGPoint(x: p.x, y: p.y - model.style.fontSize * 0.6)], style: model.style)
                model.checkpoint()
                model.shapes.append(s)
                beginEditing(s, isNew: true)
            default:
                drag = .creating(Shape(kind: kind, points: [p, p], style: model.style))
            }
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = point(e)
        let shift = e.modifierFlags.contains(.shift)
        switch drag {
        case .creating(var s):
            if s.kind.isFreehand {
                if let last = s.points.last, hypot(last.x - p.x, last.y - p.y) > 1.5 { s.points.append(p) }
                if s.points.count == 2, s.points[0] == s.points[1] { s.points.removeLast() }
            } else if s.kind.isLinear {
                s.points[1] = shift ? snap45(from: s.points[0], to: p) : p
            } else {
                var q = p
                if shift {
                    let a = s.points[0]
                    let d = max(abs(p.x - a.x), abs(p.y - a.y))
                    q = CGPoint(x: a.x + (p.x >= a.x ? d : -d), y: a.y + (p.y >= a.y ? d : -d))
                }
                s.points[1] = q
            }
            drag = .creating(s)
            needsDisplay = true
        case .moving(let start, let original):
            if !didCheckpoint { model.checkpoint(); didCheckpoint = true }
            var dx = p.x - start.x, dy = p.y - start.y
            if shift { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
            model.shapes = model.shapes.map { sh in
                guard let pts = original[sh.id] else { return sh }
                var c = sh
                c.points = pts.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                return c
            }
        case .resizing(let id, let handle, let original):
            if !didCheckpoint { model.checkpoint(); didCheckpoint = true }
            if let i = model.shapes.firstIndex(where: { $0.id == id }) {
                model.shapes[i] = applyResize(original, handle: handle, to: p, constrain: shift)
            }
        case .marquee(let a, _):
            drag = .marquee(start: a, current: p)
            let r = rectFrom(a, p)
            model.selection = Set(model.shapes.filter { r.intersects($0.bounds) }.map(\.id))
            needsDisplay = true
        case .erasing:
            erase(at: p)
        case .laser:
            addLaser(p)
        case .none:
            break
        }
    }

    override func mouseUp(with e: NSEvent) {
        defer { drag = .none; needsDisplay = true }
        guard case .creating(var s) = drag else { return }
        let r = s.rect
        if s.kind.isFreehand {
            guard !s.points.isEmpty else { return }
        } else if s.kind.isLinear {
            guard hypot(r.width, r.height) > 4 else { return }
        } else if r.width < 6 && r.height < 6 {
            // Simple click with a box tool: drop a default-size component.
            guard s.kind != .blur else { return }
            let size = defaultSize(for: s.kind)
            let o = s.points[0]
            s.points = [CGPoint(x: o.x - size.width / 2, y: o.y - size.height / 2),
                        CGPoint(x: o.x + size.width / 2, y: o.y + size.height / 2)]
        }
        model.checkpoint()
        model.shapes.append(s)
        if s.kind == .sticky || s.kind == .bubble { beginEditing(s) }
    }

    private func defaultSize(for k: ShapeKind) -> CGSize {
        switch k {
        case .sticky: return CGSize(width: 180, height: 150)
        case .person: return CGSize(width: 60, height: 110)
        case .phone: return CGSize(width: 120, height: 240)
        case .browser: return CGSize(width: 320, height: 210)
        case .check, .cross, .star: return CGSize(width: 60, height: 60)
        case .cylinder: return CGSize(width: 110, height: 130)
        case .bubble: return CGSize(width: 200, height: 110)
        default: return CGSize(width: 160, height: 100)
        }
    }

    private func beginMove(at p: CGPoint, duplicate: Bool) {
        if duplicate { model.duplicateSelection(); didCheckpoint = true }
        var original: [UUID: [CGPoint]] = [:]
        for s in model.selectedShapes { original[s.id] = s.points }
        drag = .moving(start: p, original: original)
    }

    private func erase(at p: CGPoint) {
        let hit = model.shapes.filter { $0.hitTest(p, tolerance: 8) }.map(\.id)
        guard !hit.isEmpty else { return }
        if !didCheckpoint { model.checkpoint(); didCheckpoint = true }
        model.shapes.removeAll { hit.contains($0.id) }
    }

    private func addLaser(_ p: CGPoint) {
        laserPoints.append((p, CACurrentMediaTime()))
        if laserTimer == nil {
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = CACurrentMediaTime()
                self.laserPoints.removeAll { now - $0.1 > 0.9 }
                self.needsDisplay = true
                if self.laserPoints.isEmpty { self.laserTimer?.invalidate(); self.laserTimer = nil }
            }
            RunLoop.main.add(t, forMode: .common)
            laserTimer = t
        }
    }

    func topShape(at p: CGPoint) -> Shape? {
        model.shapes.last { $0.hitTest(p) }
    }

    private func rectFrom(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func snap45(from a: CGPoint, to p: CGPoint) -> CGPoint {
        let ang = atan2(p.y - a.y, p.x - a.x)
        let snapped = (ang / (.pi / 4)).rounded() * (.pi / 4)
        let len = hypot(p.x - a.x, p.y - a.y)
        return CGPoint(x: a.x + cos(snapped) * len, y: a.y + sin(snapped) * len)
    }

    // MARK: Cursor

    override func resetCursorRects() {
        let cursor: NSCursor
        switch model.tool {
        case .select: cursor = .arrow
        case .draw(.text): cursor = .iBeam
        case .eraser: cursor = .disappearingItem
        default: cursor = .crosshair
        }
        addCursorRect(area, cursor: cursor)
    }

    // MARK: Keyboard

    override func keyDown(with e: NSEvent) {
        if onKey?(e) == true { return }
        if !handleCanvasKey(e) { super.keyDown(with: e) }
    }

    /// Shortcuts shared by every canvas. Returns true when handled.
    func handleCanvasKey(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command {
            switch chars {
            case "z": model.undo(); return true
            case "d": model.duplicateSelection(); return true
            case "a": model.selection = Set(model.shapes.map(\.id)); model.tool = .select; return true
            default: break
            }
        }
        if flags == [.command, .shift], chars == "z" { model.redo(); return true }
        if flags.isEmpty || flags == .shift {
            if e.keyCode == 51 || e.keyCode == 117 { model.deleteSelection(); return true } // ⌫ / ⌦
            if let n = Int(chars), (1...9).contains(n), flags.isEmpty {
                let color = CanvasModel.palette[n - 1]
                model.updateStyle { $0.color = color }
                return true
            }
            if let arrow = arrowDelta(e.keyCode), !model.selection.isEmpty {
                let step: CGFloat = flags == .shift ? 10 : 1
                model.checkpoint()
                for i in model.shapes.indices where model.selection.contains(model.shapes[i].id) {
                    model.shapes[i].offset(dx: arrow.x * step, dy: arrow.y * step)
                }
                return true
            }
            if flags.isEmpty, let t = CanvasView.allTools.first(where: { $0.key?.lowercased() == chars }) {
                model.tool = t
                return true
            }
        }
        return false
    }

    static let allTools: [Tool] = [.select, .eraser, .laser] + ShapeKind.allCases.map { .draw($0) }

    private func arrowDelta(_ code: UInt16) -> CGPoint? {
        switch code {
        case 123: return CGPoint(x: -1, y: 0)
        case 124: return CGPoint(x: 1, y: 0)
        case 125: return CGPoint(x: 0, y: 1)
        case 126: return CGPoint(x: 0, y: -1)
        default: return nil
        }
    }

    // MARK: Text editing

    var isEditingText: Bool { editor != nil }

    func beginEditing(_ s: Shape, isNew: Bool = false) {
        commitText()
        editingID = s.id
        model.selection = []
        let tv = CanvasTextView(frame: .zero)
        tv.delegate = self
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.importsGraphics = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.insertionPointColor = s.kind == .sticky ? .black : s.style.color
        let label = s.kind != .text
        var styleShape = s
        if label, s.style.fill == .solid, s.kind != .sticky { styleShape.style.color = ShapeRenderer.contrastText(on: s.style.color) }
        let attrs = ShapeRenderer.textAttributed(styleShape, centered: label)
            .attributes(at: 0, effectiveRange: nil)
        tv.typingAttributes = attrs
        tv.string = s.text
        tv.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: (tv.string as NSString).length))
        tv.onCommit = { [weak self] in self?.commitText() }
        if label {
            let r = ShapeRenderer.labelRect(s)
            tv.isHorizontallyResizable = false
            tv.textContainer?.widthTracksTextView = true
            tv.frame = CGRect(x: r.minX, y: r.midY - s.style.fontSize * 0.7, width: r.width, height: s.style.fontSize * 1.4)
            tv.labelBox = r
        } else {
            tv.isHorizontallyResizable = true
            tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            tv.frame = CGRect(origin: s.points[0], size: s.textSize)
        }
        tv.isVerticallyResizable = true
        addSubview(tv)
        editor = tv
        fitEditor()
        window?.makeFirstResponder(tv)
        tv.selectAll(nil)
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) { fitEditor() }

    private func fitEditor() {
        guard let tv = editor, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let lineH = (tv.typingAttributes[.font] as? NSFont).map { lm.defaultLineHeight(for: $0) } ?? 20
        if let box = tv.labelBox {
            let h = max(used.height, lineH)
            tv.frame = CGRect(x: box.minX, y: box.midY - h / 2, width: box.width, height: h)
        } else {
            tv.setFrameSize(CGSize(width: max(used.width + 4, 12), height: max(used.height, lineH)))
        }
    }

    func commitText() {
        guard let tv = editor, let id = editingID else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : tv.string
        editor = nil
        editingID = nil
        tv.removeFromSuperview()
        if let i = model.shapes.firstIndex(where: { $0.id == id }) {
            if model.shapes[i].text != text {
                model.checkpoint()
                if model.shapes[i].kind == .text && text.isEmpty {
                    model.shapes.remove(at: i)
                } else {
                    model.shapes[i].text = text
                }
            } else if model.shapes[i].kind == .text && text.isEmpty {
                model.shapes.remove(at: i)
            }
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}

/// Text view used for in-place editing. ⎋ or ⌘↩ finishes editing.
final class CanvasTextView: NSTextView {
    var onCommit: (() -> Void)?
    var labelBox: CGRect?

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 || (e.keyCode == 36 && e.modifierFlags.contains(.command)) {
            onCommit?()
            return
        }
        super.keyDown(with: e)
    }
}
