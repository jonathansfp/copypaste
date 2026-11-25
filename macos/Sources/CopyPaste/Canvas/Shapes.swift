import AppKit

// MARK: - Model

enum ShapeKind: String, CaseIterable {
    case pen, highlighter, line, arrow, doubleArrow
    case rect, ellipse, diamond, text, step, sticky, blur, image
    // Componentes da biblioteca (estilo Excalidraw)
    case cylinder, person, cloud, bubble, star, check, cross, browser, phone

    var label: String {
        switch self {
        case .pen: return "Caneta"
        case .highlighter: return "Marca-texto"
        case .line: return "Linha"
        case .arrow: return "Seta"
        case .doubleArrow: return "Seta dupla"
        case .rect: return "Retângulo"
        case .ellipse: return "Elipse"
        case .diamond: return "Losango"
        case .text: return "Texto"
        case .step: return "Passo numerado"
        case .sticky: return "Nota adesiva"
        case .blur: return "Desfocar / ocultar"
        case .image: return "Imagem"
        case .cylinder: return "Banco de dados"
        case .person: return "Pessoa"
        case .cloud: return "Nuvem"
        case .bubble: return "Balão de fala"
        case .star: return "Estrela"
        case .check: return "Certo"
        case .cross: return "Errado"
        case .browser: return "Janela / navegador"
        case .phone: return "Celular"
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .doubleArrow: return "arrow.left.and.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .diamond: return "diamond"
        case .text: return "textformat"
        case .step: return "1.circle"
        case .sticky: return "note.text"
        case .blur: return "eye.slash"
        case .image: return "photo"
        case .cylinder: return "cylinder"
        case .person: return "figure.stand"
        case .cloud: return "cloud"
        case .bubble: return "bubble.left"
        case .star: return "star"
        case .check: return "checkmark"
        case .cross: return "xmark"
        case .browser: return "macwindow"
        case .phone: return "iphone"
        }
    }

    static let library: [ShapeKind] = [.sticky, .cylinder, .person, .cloud, .bubble, .browser, .phone, .star, .check, .cross, .doubleArrow]

    var isLinear: Bool { self == .line || self == .arrow || self == .doubleArrow }
    var isFreehand: Bool { self == .pen || self == .highlighter }
    var isPoint: Bool { self == .step || self == .text }
    var isBox: Bool { !isLinear && !isFreehand && !isPoint }
    /// Box shapes that can carry a centered label (double-click to edit).
    var acceptsLabel: Bool { [.rect, .ellipse, .diamond, .sticky, .cylinder, .cloud, .bubble, .browser, .phone].contains(self) }
}

enum Tool: Hashable {
    case select, eraser, laser
    case draw(ShapeKind)

    var label: String {
        switch self {
        case .select: return "Selecionar e mover"
        case .eraser: return "Borracha"
        case .laser: return "Laser (apresentação)"
        case .draw(let k): return k.label
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .eraser: return "eraser"
        case .laser: return "light.max"
        case .draw(let k): return k.symbol
        }
    }

    var key: String? {
        switch self {
        case .select: return "V"
        case .eraser: return "E"
        case .laser: return "K"
        case .draw(let k):
            switch k {
            case .pen: return "P"
            case .highlighter: return "H"
            case .line: return "L"
            case .arrow: return "A"
            case .rect: return "R"
            case .ellipse: return "O"
            case .diamond: return "D"
            case .text: return "T"
            case .step: return "N"
            case .sticky: return "S"
            case .blur: return "B"
            default: return nil
            }
        }
    }
}

enum FillMode: Int, CaseIterable { case none, soft, solid }

enum FontChoice: String, CaseIterable, Identifiable {
    case system, rounded, hand, serif, mono
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sistema"
        case .rounded: return "Arredondada"
        case .hand: return "Manuscrita"
        case .serif: return "Serifada"
        case .mono: return "Código"
        }
    }

    func font(size: CGFloat, bold: Bool = false) -> NSFont {
        let weight: NSFont.Weight = bold ? .bold : .semibold
        switch self {
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
            return base
        case .hand:
            return NSFont(name: bold ? "ChalkboardSE-Bold" : "ChalkboardSE-Regular", size: size)
                ?? NSFont(name: "Noteworthy-Bold", size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
            return base
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .medium)
        }
    }
}

struct ShapeStyle {
    var color: NSColor = .systemRed
    var width: CGFloat = 4
    var fill: FillMode = .none
    var dashed = false
    var sketchy = false
    var font: FontChoice = .system
    var fontSize: CGFloat = 26
}

struct Shape: Identifiable {
    var id = UUID()
    var kind: ShapeKind
    /// pen: path · linear: [start, end] · box: [corner, corner] · point: [origin]
    var points: [CGPoint]
    var style: ShapeStyle
    var text = ""
    var number = 0
    var image: NSImage?
    var seed = UInt64.random(in: 1...UInt64.max)

    var rect: CGRect {
        guard let a = points.first else { return .zero }
        let b = points.last ?? a
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var stepRadius: CGFloat { 11 + style.width * 2.2 }

    var textSize: CGSize {
        let s = ShapeRenderer.textAttributed(self).size()
        return CGSize(width: ceil(max(s.width, style.fontSize * 0.5)), height: ceil(max(s.height, style.fontSize * 1.2)))
    }

    /// Visual bounds (used for selection, hit testing and dirty rects).
    var bounds: CGRect {
        switch kind {
        case .text:
            let o = points.first ?? .zero
            let pad: CGFloat = style.fill == .none ? 0 : 8
            return CGRect(origin: o, size: textSize).insetBy(dx: -pad, dy: -pad / 2)
        case .step:
            let c = points.first ?? .zero
            let r = stepRadius
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case .pen, .highlighter:
            guard let f = points.first else { return .zero }
            var minX = f.x, minY = f.y, maxX = f.x, maxY = f.y
            for p in points { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
            let w = kind == .highlighter ? style.width * 3 : style.width
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -w, dy: -w)
        case .line, .arrow, .doubleArrow:
            return rect.insetBy(dx: -(style.width * 4 + 6), dy: -(style.width * 4 + 6))
        default:
            return rect.insetBy(dx: -style.width - 2, dy: -style.width - 2)
        }
    }

    mutating func offset(dx: CGFloat, dy: CGFloat) {
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat = 6) -> Bool {
        switch kind {
        case .text, .step, .sticky, .blur, .image, .browser, .phone:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .pen, .highlighter, .line, .arrow, .doubleArrow, .check, .cross, .person:
            let path = ShapeRenderer.outline(self)
            let w = (kind == .highlighter ? style.width * 3 : style.width) + tolerance * 2
            return path.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(p)
        default:
            let path = ShapeRenderer.outline(self)
            if style.fill != .none || !text.isEmpty, path.contains(p) { return true }
            return path.copy(strokingWithWidth: style.width + tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(p)
        }
    }
}

// MARK: - Rendering

/// What a renderer needs besides the shapes: the frozen screenshot (for blur) and its pixel scale.
final class RenderEnv {
    var baseImage: CGImage?
    /// Base image pixels per canvas point.
    var imageScale: CGFloat = 1
    /// Offset of the canvas origin inside the base image, in points.
    var imageOrigin: CGPoint = .zero
    private var blurCache: [String: NSImage] = [:]
    private static let ci = CIContext(options: [.cacheIntermediates: false])

    func pixelated(_ r: CGRect) -> NSImage? {
        guard let base = baseImage, r.width >= 2, r.height >= 2 else { return nil }
        let key = "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"
        if let hit = blurCache[key] { return hit }
        let px = CGRect(x: (r.minX + imageOrigin.x) * imageScale, y: (r.minY + imageOrigin.y) * imageScale,
                        width: r.width * imageScale, height: r.height * imageScale).integral
        guard let crop = base.cropping(to: px) else { return nil }
        let input = CIImage(cgImage: crop)
        let block = max(10, min(r.width, r.height) / 9) * imageScale
        let filter = CIFilter(name: "CIPixellate")!
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(block, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: input.extent.midX, y: input.extent.midY), forKey: kCIInputCenterKey)
        guard let out = filter.outputImage?.cropped(to: input.extent),
              let cg = Self.ci.createCGImage(out, from: input.extent) else { return nil }
        let img = NSImage(cgImage: cg, size: r.size)
        if blurCache.count > 40 { blurCache.removeAll() }
        blurCache[key] = img
        return img
    }
}

enum ShapeRenderer {
    static func draw(_ shapes: [Shape], env: RenderEnv?) {
        for s in shapes { draw(s, env: env) }
    }

    static func textAttributed(_ s: Shape, centered: Bool = false) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = centered ? .center : .left
        para.lineBreakMode = .byWordWrapping
        var color = s.style.color
        if s.kind == .text, s.style.fill == .solid { color = contrastText(on: s.style.color) }
        if s.kind == .sticky { color = NSColor(white: 0.12, alpha: 1) }
        let shadow: NSShadow? = nil
        var attrs: [NSAttributedString.Key: Any] = [
            .font: s.style.font.font(size: s.style.fontSize),
            .foregroundColor: color,
            .paragraphStyle: para,
        ]
        if let shadow { attrs[.shadow] = shadow }
        return NSAttributedString(string: s.text.isEmpty && s.kind == .text ? " " : s.text, attributes: attrs)
    }

    static func contrastText(on c: NSColor) -> NSColor {
        let rgb = c.usingColorSpace(.sRGB) ?? c
        let lum = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return lum > 0.6 ? NSColor(white: 0.1, alpha: 1) : .white
    }

    static func draw(_ s: Shape, env: RenderEnv?) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let st = s.style
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(st.width)
        ctx.setStrokeColor(st.color.cgColor)
        if st.dashed { ctx.setLineDash(phase: 0, lengths: [st.width * 2.5, st.width * 2.2]) }

        switch s.kind {
        case .blur:
            if let img = env?.pixelated(s.rect) {
                img.draw(in: s.rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                ctx.setFillColor(NSColor(white: 0.5, alpha: 0.92).cgColor)
                ctx.fill(s.rect)
            }
        case .image:
            s.image?.draw(in: s.rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if st.width > 0 && st.fill != .none {
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.stroke(s.rect)
            }
        case .text:
            drawText(s, ctx: ctx)
        case .step:
            let c = s.points.first ?? .zero
            let r = s.stepRadius
            let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setFillColor(st.color.cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let str = NSAttributedString(string: "\(s.number)", attributes: [
                .font: NSFont.systemFont(ofSize: r * 1.05, weight: .bold),
                .foregroundColor: contrastText(on: st.color), .paragraphStyle: para,
            ])
            let h = str.size().height
            str.draw(in: CGRect(x: circle.minX, y: c.y - h / 2, width: circle.width, height: h))
        case .highlighter:
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(st.color.withAlphaComponent(0.42).cgColor)
            ctx.setLineWidth(st.width * 3)
            ctx.setLineCap(.butt)
            ctx.addPath(outline(s))
            ctx.strokePath()
        case .pen:
            if st.sketchy {
                strokeRough(outline(s), seed: s.seed, width: st.width, ctx: ctx, passes: 1)
            } else {
                ctx.addPath(outline(s))
                ctx.strokePath()
            }
        case .arrow, .doubleArrow, .line:
            drawLinear(s, ctx: ctx)
        default:
            drawBox(s, ctx: ctx)
        }
    }

    // MARK: Text

    private static func drawText(_ s: Shape, ctx: CGContext) {
        let o = s.points.first ?? .zero
        let size = s.textSize
        if s.style.fill != .none {
            let bg = CGRect(origin: o, size: size).insetBy(dx: -8, dy: -4)
            let path = CGPath(roundedRect: bg, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.setFillColor(s.style.fill == .solid ? s.style.color.cgColor
                             : NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        } else {
            // Contorno sutil para o texto continuar legível sobre qualquer fundo.
            ctx.setShadow(offset: .zero, blur: 3, color: ShapeRenderer.contrastText(on: s.style.color).withAlphaComponent(0.55).cgColor)
        }
        textAttributed(s).draw(in: CGRect(origin: o, size: CGSize(width: size.width + 2, height: size.height)))
    }

    // MARK: Linear

    private static func drawLinear(_ s: Shape, ctx: CGContext) {
        guard s.points.count >= 2 else { return }
        let a = s.points[0], b = s.points[s.points.count - 1]
        let st = s.style
        let head = max(12, st.width * 3.6)
        let len = hypot(b.x - a.x, b.y - a.y)
        let ang = atan2(b.y - a.y, b.x - a.x)
        let sharp = !st.sketchy && s.kind != .line

        // Shaft is shortened under filled heads so the round cap does not poke through.
        var start = a, end = b
        if sharp && len > head {
            end = CGPoint(x: b.x - cos(ang) * head * 0.6, y: b.y - sin(ang) * head * 0.6)
            if s.kind == .doubleArrow { start = CGPoint(x: a.x + cos(ang) * head * 0.6, y: a.y + sin(ang) * head * 0.6) }
        }
        let shaft = CGMutablePath()
        shaft.move(to: start)
        shaft.addLine(to: end)
        if st.sketchy {
            strokeRough(shaft, seed: s.seed, width: st.width, ctx: ctx)
        } else {
            ctx.addPath(shaft)
            ctx.strokePath()
        }
        guard s.kind != .line else { return }
        ctx.setLineDash(phase: 0, lengths: [])
        func headPath(at tip: CGPoint, angle: CGFloat) -> CGPath {
            let p = CGMutablePath()
            let spread: CGFloat = .pi / 7
            p.move(to: CGPoint(x: tip.x - cos(angle - spread) * head, y: tip.y - sin(angle - spread) * head))
            p.addLine(to: tip)
            p.addLine(to: CGPoint(x: tip.x - cos(angle + spread) * head, y: tip.y - sin(angle + spread) * head))
            if sharp { p.closeSubpath() }
            return p
        }
        var heads = [headPath(at: b, angle: ang)]
        if s.kind == .doubleArrow { heads.append(headPath(at: a, angle: ang + .pi)) }
        for h in heads {
            if sharp {
                ctx.setFillColor(st.color.cgColor)
                ctx.addPath(h)
                ctx.drawPath(using: .fillStroke)
            } else {
                strokeRough(h, seed: s.seed &+ 7, width: st.width, ctx: ctx)
            }
        }
    }

    // MARK: Boxes

    private static func drawBox(_ s: Shape, ctx: CGContext) {
        let st = s.style
        let r = s.rect
        guard r.width > 0.5 || r.height > 0.5 else { return }
        let path = outline(s)

        var fillColor: NSColor?
        switch st.fill {
        case .none: fillColor = s.kind == .sticky ? st.color.blended(withFraction: 0.72, of: .white) : nil
        case .soft: fillColor = st.color.withAlphaComponent(0.18)
        case .solid: fillColor = s.kind == .sticky ? st.color.blended(withFraction: 0.45, of: .white) : st.color
        }
        if s.kind == .sticky {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: NSColor.black.withAlphaComponent(0.25).cgColor)
            ctx.setFillColor((fillColor ?? .systemYellow).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        } else if let f = fillColor, ![.check, .cross, .person].contains(s.kind) {
            ctx.setFillColor(f.cgColor)
            ctx.addPath(fillOutline(s) ?? path)
            ctx.fillPath()
        }

        if s.kind != .sticky {
            if st.sketchy {
                strokeRough(path, seed: s.seed, width: st.width, ctx: ctx)
            } else {
                ctx.addPath(path)
                ctx.strokePath()
            }
        }

        if s.kind.acceptsLabel, !s.text.isEmpty {
            let inner = labelRect(s)
            var label = s
            if st.fill == .solid, s.kind != .sticky { label.style.color = contrastText(on: st.color) }
            else if s.kind != .sticky { label.style.color = st.color }
            let str = textAttributed(label, centered: true)
            let h = str.boundingRect(with: CGSize(width: inner.width, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            str.draw(with: CGRect(x: inner.minX, y: inner.midY - h / 2, width: inner.width, height: h + 2),
                     options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    /// Area where a box label is laid out.
    static func labelRect(_ s: Shape) -> CGRect {
        let r = s.rect
        switch s.kind {
        case .diamond: return r.insetBy(dx: r.width * 0.12, dy: r.height * 0.2)
        case .ellipse, .cloud: return r.insetBy(dx: r.width * 0.15, dy: r.height * 0.15)
        case .cylinder: return CGRect(x: r.minX + 8, y: r.minY + min(r.height * 0.25, r.width * 0.2), width: r.width - 16, height: r.height * 0.7)
        case .bubble: return CGRect(x: r.minX + 10, y: r.minY + 6, width: r.width - 20, height: r.height * 0.78 - 12)
        case .browser: return CGRect(x: r.minX + 10, y: r.minY + 30, width: r.width - 20, height: r.height - 40)
        case .phone: return r.insetBy(dx: r.width * 0.12, dy: r.height * 0.12)
        default: return r.insetBy(dx: 10, dy: 8)
        }
    }

    private static func fillOutline(_ s: Shape) -> CGPath? {
        let r = s.rect
        switch s.kind {
        case .browser, .phone:
            return CGPath(roundedRect: r, cornerWidth: s.kind == .phone ? min(r.width, r.height) * 0.14 : 8,
                          cornerHeight: s.kind == .phone ? min(r.width, r.height) * 0.14 : 8, transform: nil)
        case .cylinder:
            let ry = min(r.height * 0.15, r.width * 0.18)
            let p = CGMutablePath()
            p.addRect(CGRect(x: r.minX, y: r.minY + ry, width: r.width, height: r.height - ry * 2))
            p.addEllipse(in: CGRect(x: r.minX, y: r.minY, width: r.width, height: ry * 2))
            p.addEllipse(in: CGRect(x: r.minX, y: r.maxY - ry * 2, width: r.width, height: ry * 2))
            return p
        default: return nil
        }
    }

    /// Geometry of a shape (used for stroke, fill and hit testing).
    static func outline(_ s: Shape) -> CGPath {
        let r = s.rect
        let p = CGMutablePath()
        switch s.kind {
        case .pen, .highlighter:
            smoothPath(s.points, into: p)
        case .line, .arrow, .doubleArrow:
            if let a = s.points.first, let b = s.points.last { p.move(to: a); p.addLine(to: b) }
        case .rect, .blur, .image, .text, .step:
            let cr = s.style.sketchy ? 0 : min(8, min(r.width, r.height) / 5)
            p.addRoundedRect(in: r, cornerWidth: cr, cornerHeight: cr)
        case .sticky:
            p.addRoundedRect(in: r, cornerWidth: 3, cornerHeight: 3)
        case .ellipse:
            p.addEllipse(in: r)
        case .diamond:
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
        case .cylinder:
            let ry = min(r.height * 0.15, r.width * 0.18)
            p.addEllipse(in: CGRect(x: r.minX, y: r.minY, width: r.width, height: ry * 2))
            p.move(to: CGPoint(x: r.minX, y: r.minY + ry))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - ry))
            p.addArc(center: CGPoint(x: r.midX, y: r.maxY - ry), radius: 1, startAngle: .pi, endAngle: 0, clockwise: true,
                     transform: CGAffineTransform(translationX: r.midX, y: r.maxY - ry).scaledBy(x: r.width / 2, y: ry)
                        .translatedBy(x: -r.midX, y: -(r.maxY - ry)))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + ry))
        case .person:
            let head = min(r.width, r.height) * 0.22
            let hc = CGPoint(x: r.midX, y: r.minY + head)
            p.addEllipse(in: CGRect(x: hc.x - head, y: hc.y - head, width: head * 2, height: head * 2))
            let neck = CGPoint(x: r.midX, y: r.minY + head * 2)
            let hip = CGPoint(x: r.midX, y: r.minY + r.height * 0.66)
            p.move(to: neck); p.addLine(to: hip)
            p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.42))
            p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.36))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.minY + r.height * 0.42))
            p.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.maxY)); p.addLine(to: hip)
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.2, y: r.maxY))
        case .cloud:
            let w = r.width, h = r.height
            p.move(to: CGPoint(x: r.minX + w * 0.2, y: r.maxY - h * 0.08))
            p.addCurve(to: CGPoint(x: r.minX + w * 0.12, y: r.minY + h * 0.45),
                       control1: CGPoint(x: r.minX - w * 0.05, y: r.maxY - h * 0.1), control2: CGPoint(x: r.minX - w * 0.02, y: r.minY + h * 0.5))
            p.addCurve(to: CGPoint(x: r.minX + w * 0.42, y: r.minY + h * 0.14),
                       control1: CGPoint(x: r.minX + w * 0.1, y: r.minY + h * 0.18), control2: CGPoint(x: r.minX + w * 0.3, y: r.minY + h * 0.08))
            p.addCurve(to: CGPoint(x: r.minX + w * 0.8, y: r.minY + h * 0.3),
                       control1: CGPoint(x: r.minX + w * 0.52, y: r.minY - h * 0.08), control2: CGPoint(x: r.minX + w * 0.8, y: r.minY + h * 0.02))
            p.addCurve(to: CGPoint(x: r.minX + w * 0.86, y: r.maxY - h * 0.08),
                       control1: CGPoint(x: r.maxX + w * 0.04, y: r.minY + h * 0.32), control2: CGPoint(x: r.maxX + w * 0.08, y: r.maxY - h * 0.12))
            p.closeSubpath()
        case .bubble:
            let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.78)
            let cr = min(14, min(body.width, body.height) / 4)
            p.move(to: CGPoint(x: body.minX + cr, y: body.minY))
            p.addLine(to: CGPoint(x: body.maxX - cr, y: body.minY))
            p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: cr)
            p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: cr)
            p.addLine(to: CGPoint(x: body.minX + body.width * 0.34, y: body.maxY))
            p.addLine(to: CGPoint(x: body.minX + body.width * 0.16, y: r.maxY))
            p.addLine(to: CGPoint(x: body.minX + body.width * 0.2, y: body.maxY))
            p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.minY), radius: cr)
            p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: cr)
            p.closeSubpath()
        case .star:
            let c = CGPoint(x: r.midX, y: r.midY)
            for i in 0..<10 {
                let rad = (i % 2 == 0 ? 1.0 : 0.42)
                let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let pt = CGPoint(x: c.x + cos(a) * r.width / 2 * rad, y: c.y + sin(a) * r.height / 2 * rad)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        case .check:
            p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        case .cross:
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        case .browser:
            p.addRoundedRect(in: r, cornerWidth: 8, cornerHeight: 8)
            p.move(to: CGPoint(x: r.minX, y: r.minY + 22)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 22))
            for i in 0..<3 {
                p.addEllipse(in: CGRect(x: r.minX + 9 + CGFloat(i) * 12, y: r.minY + 7, width: 7, height: 7))
            }
        case .phone:
            let cr = min(r.width, r.height) * 0.14
            p.addRoundedRect(in: r, cornerWidth: cr, cornerHeight: cr)
            let notchW = r.width * 0.3
            p.addRoundedRect(in: CGRect(x: r.midX - notchW / 2, y: r.minY + r.height * 0.03, width: notchW, height: max(4, r.height * 0.025)),
                             cornerWidth: 3, cornerHeight: 3)
        }
        return p
    }

    /// Smooth freehand stroke through midpoints (quadratic curves).
    static func smoothPath(_ pts: [CGPoint], into p: CGMutablePath) {
        guard let first = pts.first else { return }
        p.move(to: first)
        if pts.count < 3 {
            pts.dropFirst().forEach { p.addLine(to: $0) }
            if pts.count == 1 { p.addLine(to: CGPoint(x: first.x + 0.01, y: first.y)) }
            return
        }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i])
        }
        p.addLine(to: pts[pts.count - 1])
    }

    // MARK: Hand-drawn ("sketchy") stroke

    /// Flattens the path, jitters it with a stable seed and strokes it twice, like a marker drawn by hand.
    static func strokeRough(_ path: CGPath, seed: UInt64, width: CGFloat, ctx: CGContext, passes: Int = 2) {
        var rng = SeededRNG(seed: seed)
        let amp = 0.9 + width * 0.35
        for subpath in flatten(path, step: 14) {
            for pass in 0..<passes {
                var pts = subpath.points.map { pt in
                    CGPoint(x: pt.x + CGFloat.random(in: -amp...amp, using: &rng),
                            y: pt.y + CGFloat.random(in: -amp...amp, using: &rng))
                }
                if subpath.closed, pass == 1, pts.count > 2 {
                    // Overshoot a little past the start, like a real pen.
                    pts.append(pts[1])
                }
                let p = CGMutablePath()
                catmullRom(pts, closed: subpath.closed && pass == 0, into: p)
                ctx.setLineWidth(pass == 0 ? width : max(1, width * 0.7))
                ctx.addPath(p)
                ctx.strokePath()
            }
        }
    }

    /// Point on a quadratic Bézier (split up so the compiler type-checks it quickly).
    private static func quadPoint(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt: CGFloat = 1 - t
        let k0: CGFloat = mt * mt, k1: CGFloat = 2 * mt * t, k2: CGFloat = t * t
        let x: CGFloat = k0 * a.x + k1 * c.x + k2 * b.x
        let y: CGFloat = k0 * a.y + k1 * c.y + k2 * b.y
        return CGPoint(x: x, y: y)
    }

    /// Point on a cubic Bézier.
    private static func cubicPoint(_ a: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt: CGFloat = 1 - t
        let k0: CGFloat = mt * mt * mt, k1: CGFloat = 3 * mt * mt * t
        let k2: CGFloat = 3 * mt * t * t, k3: CGFloat = t * t * t
        let x: CGFloat = k0 * a.x + k1 * c1.x + k2 * c2.x + k3 * b.x
        let y: CGFloat = k0 * a.y + k1 * c1.y + k2 * c2.y + k3 * b.y
        return CGPoint(x: x, y: y)
    }

    private struct Polyline { var points: [CGPoint]; var closed: Bool }

    private static func flatten(_ path: CGPath, step: CGFloat) -> [Polyline] {
        var out: [Polyline] = []
        var cur: [CGPoint] = []
        var start = CGPoint.zero, last = CGPoint.zero
        func addSeg(to b: CGPoint) {
            let d = hypot(b.x - last.x, b.y - last.y)
            let n = max(1, Int(d / step))
            for i in 1...n {
                let t = CGFloat(i) / CGFloat(n)
                cur.append(CGPoint(x: last.x + (b.x - last.x) * t, y: last.y + (b.y - last.y) * t))
            }
            last = b
        }
        func finish(closed: Bool) {
            if cur.count > 1 { out.append(Polyline(points: cur, closed: closed)) }
            cur = []
        }
        path.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint:
                finish(closed: false)
                start = e.points[0]; last = start; cur = [start]
            case .addLineToPoint:
                addSeg(to: e.points[0])
            case .addQuadCurveToPoint:
                let c = e.points[0], b = e.points[1], a = last
                let n = max(4, Int((hypot(c.x - a.x, c.y - a.y) + hypot(b.x - c.x, b.y - c.y)) / step))
                for i in 1...n { cur.append(quadPoint(a, c, b, CGFloat(i) / CGFloat(n))) }
                last = b
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], b = e.points[2], a = last
                let d1: CGFloat = hypot(c1.x - a.x, c1.y - a.y)
                let d2: CGFloat = hypot(c2.x - c1.x, c2.y - c1.y)
                let d3: CGFloat = hypot(b.x - c2.x, b.y - c2.y)
                let n = max(4, Int((d1 + d2 + d3) / step))
                for i in 1...n { cur.append(cubicPoint(a, c1, c2, b, CGFloat(i) / CGFloat(n))) }
                last = b
            case .closeSubpath:
                if hypot(start.x - last.x, start.y - last.y) > 0.5 { addSeg(to: start) }
                finish(closed: true)
                last = start
            @unknown default:
                break
            }
        }
        finish(closed: false)
        return out
    }

    private static func catmullRom(_ pts: [CGPoint], closed: Bool, into p: CGMutablePath) {
        guard pts.count > 1 else { return }
        p.move(to: pts[0])
        let n = pts.count
        for i in 0..<(n - 1) {
            let p0 = i > 0 ? pts[i - 1] : (closed ? pts[n - 1] : pts[i])
            let p1 = pts[i], p2 = pts[i + 1]
            let p3 = i + 2 < n ? pts[i + 2] : (closed ? pts[(i + 2) % n] : p2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
}

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
