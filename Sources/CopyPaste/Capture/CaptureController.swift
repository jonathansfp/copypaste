import AppKit
import SwiftUI

enum CaptureMode { case edit, record }

/// Owns the capture overlay. Created on demand and fully released when closed,
/// so nothing stays in memory between captures.
@MainActor
final class CaptureController {
    static let shared = CaptureController()

    private var windows: [CaptureWindow] = []
    private var previousApp: NSRunningApplication?
    private var starting = false
    var isActive: Bool { !windows.isEmpty || starting }

    func start(fullScreen: Bool = false, mode: CaptureMode = .edit) {
        Diag.log("captura: start fullScreen=\(fullScreen) ativo=\(isActive) permissão=\(CGPreflightScreenCaptureAccess())")
        guard !isActive else { return }
        guard ScreenGrabber.ensurePermission() else { Diag.log("captura: sem permissão de Gravação de Tela"); return }
        starting = true
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        let rects = AppSettings.shared.captureSnapWindows ? ScreenGrabber.windowRects() : []
        Task { @MainActor in
            defer { self.starting = false }
            do {
                let frozen = try await ScreenGrabber.captureAll()
                Diag.log("captura: \(frozen.count) tela(s) congelada(s)")
                self.present(frozen, windowRects: rects, fullScreen: fullScreen, mode: mode)
            } catch {
                Diag.log("captura: ERRO \(error) (\((error as NSError).domain) \((error as NSError).code))")
                Toast.show("Não foi possível capturar a tela. Verifique a permissão de Gravação de Tela.",
                           symbol: "exclamationmark.triangle", duration: 3.5)
            }
        }
    }

    private func present(_ frozen: [FrozenScreen], windowRects: [CGRect], fullScreen: Bool, mode: CaptureMode) {
        let mouseScreen = ScreenGrabber.screenUnderMouse()
        var key: CaptureWindow?
        for f in frozen {
            let sf = f.screen.frame
            let local = windowRects.compactMap { r -> CGRect? in
                let clipped = r.intersection(sf)
                guard !clipped.isNull, clipped.width > 30, clipped.height > 30 else { return nil }
                return CGRect(x: clipped.minX - sf.minX, y: sf.maxY - clipped.maxY, width: clipped.width, height: clipped.height)
            }
            let w = CaptureWindow(frozen: f, windowRects: local, mode: mode, controller: self)
            windows.append(w)
            w.orderFrontRegardless()
            if f.screen == mouseScreen { key = w }
        }
        NSApp.activate(ignoringOtherApps: true)
        let k = key ?? windows.first
        k?.makeKeyAndOrderFront(nil)
        if fullScreen { k?.root.selectWholeScreen() }
    }

    /// A selection started on one screen: the others drop theirs.
    func selectionStarted(in w: CaptureWindow) {
        for other in windows where other !== w { other.root.resetSelection() }
    }

    func finish() {
        let ws = windows
        windows = []
        for w in ws {
            w.orderOut(nil)
            w.root.teardown()
            w.contentView = nil
        }
        if let app = previousApp, !WindowManagerVisible.any {
            app.activate()
        }
        previousApp = nil
    }
}

enum WindowManagerVisible {
    /// True when one of our regular windows (library/settings/board) is on screen.
    @MainActor static var any: Bool {
        NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) } || BoardController.shared.isOpen
    }
}

// MARK: - Window

final class CaptureWindow: NSWindow {
    let root: CaptureRootView

    @MainActor
    init(frozen: FrozenScreen, windowRects: [CGRect], mode: CaptureMode, controller: CaptureController) {
        root = CaptureRootView(frozen: frozen, windowRects: windowRects, mode: mode, controller: controller)
        super.init(contentRect: frozen.screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(frozen.screen.frame, display: false)
        level = .statusBar
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        contentView = root
        root.frame = CGRect(origin: .zero, size: frozen.screen.frame.size)
        makeFirstResponder(root.canvas)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Root view

@MainActor
final class CaptureRootView: NSView {
    let frozen: FrozenScreen
    let mode: CaptureMode
    unowned let controller: CaptureController
    let model = CanvasModel()
    let ui = CanvasUIState()
    let canvas: CaptureCanvasView
    private let imageView = NSView()
    private let magnifier = MagnifierView()
    private var toolsHost: NSHostingView<AnyView>?
    private var actionsHost: NSHostingView<AnyView>?
    private var styleObserver: Any?
    private var recordOptions = RecordOptions()

    init(frozen: FrozenScreen, windowRects: [CGRect], mode: CaptureMode, controller: CaptureController) {
        self.frozen = frozen
        self.mode = mode
        self.controller = controller
        canvas = CaptureCanvasView(model: model)
        super.init(frame: CGRect(origin: .zero, size: frozen.screen.frame.size))
        wantsLayer = true

        imageView.wantsLayer = true
        imageView.layer?.contents = frozen.image
        imageView.layer?.contentsGravity = .resize
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.windowRects = windowRects
        canvas.env.baseImage = frozen.image
        canvas.env.imageScale = frozen.scale
        canvas.root = self
        canvas.showsMagnifier = AppSettings.shared.captureMagnifier
        addSubview(canvas)

        magnifier.image = frozen.image
        magnifier.scale = frozen.scale
        magnifier.isHidden = true
        addSubview(magnifier)

        model.style.width = 4
        model.tool = .draw(.arrow)
        styleObserver = ui.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layoutBars() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func teardown() {
        styleObserver = nil
        imageView.layer?.contents = nil
        magnifier.image = nil
        canvas.env.baseImage = nil
    }

    func resetSelection() { canvas.resetSelection() }
    func selectWholeScreen() { canvas.selectWholeScreen() }

    // MARK: Magnifier

    func updateMagnifier(at p: CGPoint?) {
        guard let p, canvas.showsMagnifier else { magnifier.isHidden = true; return }
        magnifier.isHidden = false
        magnifier.focus = p
        let size = magnifier.frame.size
        var o = CGPoint(x: p.x + 24, y: p.y + 24)
        if o.x + size.width > bounds.maxX { o.x = p.x - 24 - size.width }
        if o.y + size.height > bounds.maxY { o.y = p.y - 24 - size.height }
        magnifier.setFrameOrigin(o)
        magnifier.needsDisplay = true
    }

    var colorUnderCursor: NSColor? { magnifier.pixelColor() }

    // MARK: Toolbars

    func selectionDidChange() {
        guard let sel = canvas.selection, canvas.phase == .editing else {
            toolsHost?.removeFromSuperview(); toolsHost = nil
            actionsHost?.removeFromSuperview(); actionsHost = nil
            return
        }
        _ = sel
        if toolsHost == nil, mode == .edit {
            let h = NSHostingView(rootView: AnyView(CaptureToolsBar(model: model, ui: ui)))
            addSubview(h)
            toolsHost = h
        }
        if actionsHost == nil {
            let view: AnyView = mode == .edit
                ? AnyView(CaptureActionsBar(root: self))
                : AnyView(RecordStartBar(root: self, options: recordOptions))
            let h = NSHostingView(rootView: view)
            addSubview(h)
            actionsHost = h
        }
        layoutBars()
    }

    func layoutBars() {
        guard let sel = canvas.selection else { return }
        let margin: CGFloat = 8
        if let t = toolsHost {
            let size = t.fittingSize
            var x = sel.maxX + margin
            if x + size.width > bounds.maxX - 4 { x = sel.minX - margin - size.width }
            if x < 4 { x = sel.maxX - size.width - margin }
            var y = sel.minY
            y = min(max(4, y), bounds.maxY - size.height - 4)
            t.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        }
        if let a = actionsHost {
            let size = a.fittingSize
            var x = sel.maxX - size.width
            x = min(max(4, x), bounds.maxX - size.width - 4)
            var y = sel.maxY + margin
            if y + size.height > bounds.maxY - 4 { y = sel.minY - margin - size.height }
            if y < 4 { y = sel.maxY - size.height - margin }
            a.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        }
    }

    // MARK: Output

    /// Final image: the frozen pixels of the selection with the annotations drawn as vectors on top.
    func render() -> NSImage? {
        canvas.commitText()
        guard let sel = canvas.selection, sel.width >= 1, sel.height >= 1 else { return nil }
        let scale = frozen.scale
        let px = CGRect(x: sel.minX * scale, y: sel.minY * scale, width: sel.width * scale, height: sel.height * scale).integral
        guard let crop = frozen.image.cropping(to: px) else { return nil }
        let w = crop.width, h = crop.height
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        if !model.shapes.isEmpty {
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: CGFloat(w) / sel.width, y: -CGFloat(h) / sel.height)
            ctx.translateBy(x: -sel.minX, y: -sel.minY)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            ShapeRenderer.draw(model.shapes, env: canvas.env)
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: sel.size)
    }

    /// Selection in global Cocoa screen coordinates.
    var selectionOnScreen: CGRect? {
        guard let sel = canvas.selection else { return nil }
        let sf = frozen.screen.frame
        return CGRect(x: sf.minX + sel.minX, y: sf.maxY - sel.maxY, width: sel.width, height: sel.height)
    }

    func perform(_ action: CaptureAction) {
        if action == .close { controller.finish(); return }
        if action == .record {
            startRecording()
            return
        }
        guard let image = render() else { return }
        let screenRect = selectionOnScreen
        controller.finish()
        switch action {
        case .copy:
            ImageOutput.copy(image)
            Toast.show("Captura copiada")
        case .save:
            if let url = ImageOutput.saveToFolder(image) { Toast.show("Salva: \(url.lastPathComponent)") }
        case .copyAndSave:
            ImageOutput.copy(image)
            if let url = ImageOutput.saveToFolder(image) { Toast.show("Copiada e salva: \(url.lastPathComponent)") }
        case .saveAs:
            DispatchQueue.main.async { ImageOutput.saveAs(image) }
        case .pin:
            PinWindow.pin(image, at: screenRect ?? CGRect(origin: .zero, size: image.size))
        case .board:
            BoardController.shared.open(with: image)
        case .ocr:
            Toast.show("Lendo texto…", symbol: "text.viewfinder", duration: 6)
            TextRecognizer.recognize(image) { text in
                if text.isEmpty {
                    Toast.show("Nenhum texto encontrado", symbol: "text.magnifyingglass")
                } else {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    let lines = text.components(separatedBy: "\n").count
                    Toast.show("Texto copiado (\(lines) \(lines == 1 ? "linha" : "linhas"))", symbol: "text.viewfinder")
                }
            }
        case .search:
            ImageOutput.copy(image)
            if let url = URL(string: "https://lens.google.com/") { NSWorkspace.shared.open(url) }
            Toast.show("Imagem copiada: cole (⌘V) no Google Lens", symbol: "magnifyingglass", duration: 3)
        case .close, .record:
            break
        }
    }

    func performEnter() {
        switch AppSettings.shared.captureEnterAction {
        case .copy: perform(.copy)
        case .save: perform(.save)
        case .copyAndSave: perform(.copyAndSave)
        }
    }

    private func startRecording() {
        guard let rect = selectionOnScreen else { return }
        let screen = frozen.screen
        let opts = recordOptions
        controller.finish()
        let full = canvas.selection.map { $0.size == bounds.size } ?? false
        ScreenRecorder.shared.start(screen: screen, rect: full ? nil : rect, mic: opts.mic, systemAudio: opts.systemAudio)
    }
}

enum CaptureAction { case copy, save, copyAndSave, saveAs, pin, board, ocr, search, record, close }

final class RecordOptions: ObservableObject {
    @Published var mic = AppSettings.shared.recordMic { didSet { AppSettings.shared.recordMic = mic } }
    @Published var systemAudio = AppSettings.shared.recordSystemAudio { didSet { AppSettings.shared.recordSystemAudio = systemAudio } }
}

// MARK: - Canvas with selection phase

@MainActor
final class CaptureCanvasView: CanvasView {
    enum Phase { case choosing, selecting, editing }

    weak var root: CaptureRootView?
    var windowRects: [CGRect] = []
    var showsMagnifier = true
    private(set) var phase: Phase = .choosing
    private(set) var selection: CGRect? {
        didSet { drawingArea = selection ?? CGRect(x: -10, y: -10, width: 1, height: 1) }
    }
    private var hoverWindow: CGRect?
    private var selStart: CGPoint = .zero
    private var resizingHandle: Int?
    private var resizeOrigin: CGRect = .zero
    private var movingSelectionFrom: CGPoint?
    private var tracking: NSTrackingArea?

    override init(model: CanvasModel) {
        super.init(model: model)
        drawingArea = CGRect(x: -10, y: -10, width: 1, height: 1)
        onKey = { [weak self] e in self?.captureKey(e) ?? false }
        onDoubleClickEmpty = { [weak self] in self?.root?.performEnter() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(t)
        tracking = t
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window {
            let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(p) { hover(p) }
        }
    }

    func resetSelection() {
        selection = nil
        phase = .choosing
        hoverWindow = nil
        model.shapes = []
        root?.selectionDidChange()
        root?.updateMagnifier(at: nil)
        needsDisplay = true
    }

    func selectWholeScreen() {
        root?.controller.selectionStarted(in: window as! CaptureWindow)
        selection = bounds
        phase = .editing
        root?.updateMagnifier(at: nil)
        root?.selectionDidChange()
        needsDisplay = true
    }

    // MARK: Drawing

    override func drawBackground(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dim = NSColor.black.withAlphaComponent(0.42).cgColor
        ctx.setFillColor(dim)
        let hole = selection ?? (phase == .choosing ? hoverWindow : nil)
        if let h = hole {
            ctx.addRect(bounds)
            ctx.addRect(h)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(bounds)
        }
    }

    override func drawOverlay(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let accent = NSColor.controlAccentColor
        if phase == .choosing, let h = hoverWindow, selection == nil {
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(h.insetBy(dx: 1.5, dy: 1.5))
            drawSizeLabel(for: h, hint: "Clique para capturar esta janela · arraste para escolher a área")
            return
        }
        guard let sel = selection else {
            if phase == .choosing { drawHint() }
            return
        }
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))
        ctx.setLineDash(phase: 0, lengths: [])
        if phase == .editing {
            for h in selectionHandles(sel) {
                let r = CGRect(x: h.x - 4, y: h.y - 4, width: 8, height: 8)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r)
                ctx.setStrokeColor(accent.cgColor)
                ctx.stroke(r)
            }
        }
        drawSizeLabel(for: sel, hint: nil)
    }

    private func drawSizeLabel(for r: CGRect, hint: String?) {
        guard let scale = root?.frozen.scale else { return }
        var text = "\(Int((r.width * scale).rounded())) × \(Int((r.height * scale).rounded()))"
        if let hint { text += "   ·   " + hint }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var o = CGPoint(x: r.minX, y: r.minY - size.height - 10)
        if o.y < 4 { o.y = r.minY + 6; o.x = r.minX + 6 }
        let bg = CGRect(x: o.x, y: o.y, width: size.width + 14, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
        str.draw(at: CGPoint(x: o.x + 7, y: o.y + 3))
    }

    private func drawHint() {
        let text = "Arraste para selecionar · clique numa janela · ⎋ cancela · C copia a cor do pixel"
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white,
        ])
        let s = str.size()
        let bg = CGRect(x: bounds.midX - s.width / 2 - 16, y: 60, width: s.width + 32, height: s.height + 14)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()
        str.draw(at: CGPoint(x: bg.minX + 16, y: bg.minY + 7))
    }

    private func selectionHandles(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    // MARK: Mouse

    private func rawPoint(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.maxX), y: min(max(p.y, 0), bounds.maxY))
    }

    private func hover(_ p: CGPoint) {
        if phase == .choosing {
            let w = windowRects.first { $0.contains(p) }
            if w != hoverWindow { hoverWindow = w; needsDisplay = true }
            root?.updateMagnifier(at: p)
        }
    }

    override func mouseMoved(with e: NSEvent) {
        let p = rawPoint(e)
        hover(p)
        if phase == .editing, let sel = selection {
            if selectionHandles(sel).contains(where: { hypot($0.x - p.x, $0.y - p.y) <= 7 }) {
                NSCursor.crosshair.set()
            }
        }
    }

    override func mouseExited(with e: NSEvent) { root?.updateMagnifier(at: nil) }

    override func rightMouseDown(with e: NSEvent) {
        if phase == .editing, model.shapes.isEmpty { resetSelection() } else if phase != .editing { root?.controller.finish() }
    }

    override func mouseDown(with e: NSEvent) {
        let p = rawPoint(e)
        window?.makeFirstResponder(self)
        switch phase {
        case .choosing:
            root?.controller.selectionStarted(in: window as! CaptureWindow)
            selStart = p
            phase = .selecting
        case .selecting:
            break
        case .editing:
            guard let sel = selection else { return }
            if let i = selectionHandles(sel).firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) <= 7 }) {
                commitText()
                resizingHandle = i
                resizeOrigin = sel
                return
            }
            if !sel.contains(p) {
                if model.shapes.isEmpty && !isEditingText {
                    // Start over with a new area.
                    selection = nil
                    root?.selectionDidChange()
                    selStart = p
                    phase = .selecting
                } else if e.modifierFlags.contains(.command) || model.tool == .select {
                    movingSelectionFrom = p
                } else {
                    commitText()
                }
                return
            }
            if e.modifierFlags.contains(.command), topShape(at: p) == nil {
                movingSelectionFrom = p
                return
            }
            super.mouseDown(with: e)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = rawPoint(e)
        switch phase {
        case .choosing:
            break
        case .selecting:
            var r = CGRect(x: min(selStart.x, p.x), y: min(selStart.y, p.y), width: abs(p.x - selStart.x), height: abs(p.y - selStart.y))
            if e.modifierFlags.contains(.shift) { let d = max(r.width, r.height); r.size = CGSize(width: d, height: d) }
            selection = r.width > 0 || r.height > 0 ? r.intersection(bounds) : nil
            root?.updateMagnifier(at: p)
            needsDisplay = true
        case .editing:
            if let h = resizingHandle {
                selection = resized(resizeOrigin, handle: h, to: p)
                root?.layoutBars()
                needsDisplay = true
            } else if let from = movingSelectionFrom, let sel = selection {
                var r = sel.offsetBy(dx: p.x - from.x, dy: p.y - from.y)
                r.origin.x = min(max(0, r.minX), bounds.maxX - r.width)
                r.origin.y = min(max(0, r.minY), bounds.maxY - r.height)
                let d = CGPoint(x: r.minX - sel.minX, y: r.minY - sel.minY)
                selection = r
                // Annotations travel with the area.
                if !model.shapes.isEmpty { model.shapes = model.shapes.map { var s = $0; s.offset(dx: d.x, dy: d.y); return s } }
                movingSelectionFrom = p
                root?.layoutBars()
                needsDisplay = true
            } else {
                super.mouseDragged(with: e)
            }
        }
    }

    override func mouseUp(with e: NSEvent) {
        switch phase {
        case .choosing:
            break
        case .selecting:
            if selection == nil || selection!.width < 4 || selection!.height < 4 {
                // A click: take the window under the pointer, or the whole screen.
                selection = hoverWindow ?? windowRects.first { $0.contains(selStart) } ?? bounds
            }
            phase = .editing
            root?.updateMagnifier(at: nil)
            root?.selectionDidChange()
            needsDisplay = true
        case .editing:
            if resizingHandle != nil || movingSelectionFrom != nil {
                resizingHandle = nil
                movingSelectionFrom = nil
                root?.layoutBars()
                return
            }
            super.mouseUp(with: e)
        }
    }

    private func resized(_ r: CGRect, handle: Int, to p: CGPoint) -> CGRect {
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
        let out = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: max(4, abs(maxX - minX)), height: max(4, abs(maxY - minY)))
        return out.intersection(bounds)
    }

    // MARK: Keys

    private func captureKey(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if e.keyCode == 53 { // esc
            if !model.selection.isEmpty { model.selection = []; return true }
            root?.perform(.close)
            return true
        }
        if phase != .editing {
            if chars == "c", flags.isEmpty, let c = root?.colorUnderCursor {
                let hex = MagnifierView.hex(c)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(hex, forType: .string)
                root?.perform(.close)
                Toast.show("Cor \(hex) copiada", symbol: "eyedropper")
                return true
            }
            if chars == "f" || e.keyCode == 36 { selectWholeScreen(); return true }
            if let w = window, let d = arrowNudge(e.keyCode) {
                // Move the pointer pixel by pixel for precise selection.
                let screenP = NSEvent.mouseLocation
                let target = CGPoint(x: screenP.x + d.x, y: screenP.y - d.y)
                let primaryH = NSScreen.screens.first?.frame.height ?? 0
                CGWarpMouseCursorPosition(CGPoint(x: target.x, y: primaryH - target.y))
                hover(convert(w.convertPoint(fromScreen: target), from: nil))
                return true
            }
            return false
        }
        if root?.mode == .record {
            if e.keyCode == 36 { root?.perform(.record); return true }
            return false
        }
        if isEditingText { return false }
        if e.keyCode == 36 || e.keyCode == 76 { root?.performEnter(); return true }
        if flags == .command {
            switch chars {
            case "c": root?.perform(model.selection.isEmpty ? .copy : .copy); return true
            case "s": root?.perform(.save); return true
            case "t": root?.perform(.ocr); return true
            default: break
            }
        }
        if flags == [.command, .shift], chars == "s" { root?.perform(.saveAs); return true }
        return false
    }

    private func arrowNudge(_ code: UInt16) -> CGPoint? {
        switch code {
        case 123: return CGPoint(x: -1, y: 0)
        case 124: return CGPoint(x: 1, y: 0)
        case 125: return CGPoint(x: 0, y: 1)
        case 126: return CGPoint(x: 0, y: -1)
        default: return nil
        }
    }
}

// MARK: - Magnifier

final class MagnifierView: NSView {
    var image: CGImage?
    var scale: CGFloat = 2
    var focus: CGPoint = .zero
    private let zoomPixels = 15

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 132, height: 160))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var pixelRect: CGRect {
        let cx = Int(focus.x * scale), cy = Int(focus.y * scale)
        return CGRect(x: cx - zoomPixels / 2, y: cy - zoomPixels / 2, width: zoomPixels, height: zoomPixels)
    }

    func pixelColor() -> NSColor? {
        guard let image, let px = image.cropping(to: CGRect(x: Int(focus.x * scale), y: Int(focus.y * scale), width: 1, height: 1)) else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(px, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(srgbRed: CGFloat(data[0]) / 255, green: CGFloat(data[1]) / 255, blue: CGFloat(data[2]) / 255, alpha: 1)
    }

    static func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return String(format: "#%02X%02X%02X", Int(round(s.redComponent * 255)), Int(round(s.greenComponent * 255)), Int(round(s.blueComponent * 255)))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let box = CGRect(x: 0, y: 0, width: 132, height: 132)
        ctx.saveGState()
        let clip = CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(clip)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(box)
        if let crop = image.cropping(to: pixelRect) {
            ctx.interpolationQuality = .none
            // Flipped view: draw the image upside down so it appears upright.
            ctx.translateBy(x: 0, y: box.height)
            ctx.scaleBy(x: 1, y: -1)
            let cell = box.width / CGFloat(zoomPixels)
            let r = pixelRect
            let ox = r.minX < 0 ? -r.minX * cell : 0
            ctx.draw(crop, in: CGRect(x: ox, y: box.height - CGFloat(crop.height) * cell - (r.minY < 0 ? -r.minY * cell : 0),
                                      width: CGFloat(crop.width) * cell, height: CGFloat(crop.height) * cell))
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: 0, y: -box.height)
            // Center pixel frame
            let c = CGRect(x: CGFloat(zoomPixels / 2) * cell, y: CGFloat(zoomPixels / 2) * cell, width: cell, height: cell)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: c.midX, y: 0)); ctx.addLine(to: CGPoint(x: c.midX, y: c.minY))
            ctx.move(to: CGPoint(x: c.midX, y: c.maxY)); ctx.addLine(to: CGPoint(x: c.midX, y: box.maxY))
            ctx.move(to: CGPoint(x: 0, y: c.midY)); ctx.addLine(to: CGPoint(x: c.minX, y: c.midY))
            ctx.move(to: CGPoint(x: c.maxX, y: c.midY)); ctx.addLine(to: CGPoint(x: box.maxX, y: c.midY))
            ctx.strokePath()
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.stroke(c.insetBy(dx: -1, dy: -1))
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(c)
        }
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(clip)
        ctx.strokePath()

        let color = pixelColor()
        let label = "\(Int(focus.x * scale)), \(Int(focus.y * scale))   \(color.map(MagnifierView.hex) ?? "")"
        let str = NSAttributedString(string: label, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        let bg = CGRect(x: 0, y: 138, width: 132, height: 20)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
        if let color {
            color.setFill()
            NSBezierPath(roundedRect: CGRect(x: 6, y: 143, width: 10, height: 10), xRadius: 2, yRadius: 2).fill()
        }
        str.draw(at: CGPoint(x: 21, y: 141))
    }
}

// MARK: - Bars

struct CaptureToolsBar: View {
    @ObservedObject var model: CanvasModel
    @ObservedObject var ui: CanvasUIState

    private let tools: [Tool] = [.select, .draw(.pen), .draw(.highlighter), .draw(.line), .draw(.arrow), .draw(.rect),
                                 .draw(.ellipse), .draw(.text), .draw(.step), .draw(.blur), .eraser]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if ui.showStyle { StylePanel(model: model) }
            VStack(spacing: 2) {
                ForEach(tools, id: \.self) { ToolButton(model: model, tool: $0) }
                LibraryMenu(model: model)
                Divider().frame(width: 22).padding(.vertical, 3)
                StyleToggle(model: model, ui: ui)
                IconButton(symbol: "arrow.uturn.backward", help: "Desfazer (⌘Z)", disabled: !model.canUndo) { model.undo() }
                IconButton(symbol: "arrow.uturn.forward", help: "Refazer (⇧⌘Z)", disabled: !model.canRedo) { model.redo() }
            }
            .padding(4)
            .floatingBar()
        }
        .fixedSize()
    }
}

struct CaptureActionsBar: View {
    let root: CaptureRootView

    var body: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "text.viewfinder", help: "Copiar o texto da imagem (OCR) — ⌘T") { root.perform(.ocr) }
            IconButton(symbol: "magnifyingglass", help: "Pesquisar imagem (Google Lens)") { root.perform(.search) }
            IconButton(symbol: "pin", help: "Fixar na tela (fica por cima das janelas)") { root.perform(.pin) }
            IconButton(symbol: "rectangle.on.rectangle.angled", help: "Abrir no quadro de apresentação") { root.perform(.board) }
            IconButton(symbol: "record.circle", help: "Gravar vídeo desta área", tint: .red) { root.perform(.record) }
            Divider().frame(height: 20).padding(.horizontal, 3)
            IconButton(symbol: "square.and.arrow.down.on.square", help: "Salvar como… (⇧⌘S)") { root.perform(.saveAs) }
            IconButton(symbol: "square.and.arrow.down", help: "Salvar na pasta (⌘S)") { root.perform(.save) }
            IconButton(symbol: "doc.on.doc", help: "Copiar (⌘C ou ↩)") { root.perform(.copy) }
            IconButton(symbol: "xmark", help: "Fechar (⎋)") { root.perform(.close) }
        }
        .padding(4)
        .floatingBar()
        .fixedSize()
    }
}

struct RecordStartBar: View {
    let root: CaptureRootView
    @ObservedObject var options: RecordOptions

    var body: some View {
        HStack(spacing: 6) {
            Toggle(isOn: $options.mic) { Label("Microfone", systemImage: "mic") }
                .toggleStyle(.button)
            Toggle(isOn: $options.systemAudio) { Label("Áudio do Mac", systemImage: "speaker.wave.2") }
                .toggleStyle(.button)
            Button {
                root.perform(.record)
            } label: {
                Label("Gravar", systemImage: "record.circle.fill").foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut(.defaultAction)
            IconButton(symbol: "xmark", help: "Cancelar (⎋)") { root.perform(.close) }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(6)
        .floatingBar()
        .fixedSize()
    }
}
