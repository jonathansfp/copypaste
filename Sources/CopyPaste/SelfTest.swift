import AppKit

/// `CopyPaste --selftest <arquivo.png>`: desenha todas as formas e grava um PNG (verificação visual rápida).
enum SelfTest {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let size = CGSize(width: 1200, height: 760)
        let scale: CGFloat = 2

        // Fundo "capturado" sintético para testar o desfoque.
        let baseW = Int(size.width * scale), baseH = Int(size.height * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bctx = CGContext(data: nil, width: baseW, height: baseH, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        for y in stride(from: 0, to: baseH, by: 24) {
            for x in stride(from: 0, to: baseW, by: 24) {
                bctx.setFillColor(NSColor(hue: CGFloat((x + y) % 360) / 360, saturation: 0.5, brightness: 0.95, alpha: 1).cgColor)
                bctx.fill(CGRect(x: x, y: y, width: 24, height: 24))
            }
        }
        let env = RenderEnv()
        env.baseImage = bctx.makeImage()
        env.imageScale = scale

        var shapes: [Shape] = []
        func add(_ k: ShapeKind, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, sketchy: Bool = false,
                 fill: FillMode = .none, color: NSColor = .systemRed, text: String = "") {
            var st = ShapeStyle()
            st.color = color; st.sketchy = sketchy; st.fill = fill; st.width = 3
            var s = Shape(kind: k, points: [CGPoint(x: x, y: y), CGPoint(x: x + w, y: y + h)], style: st)
            s.text = text
            shapes.append(s)
        }
        add(.rect, 30, 30, 160, 100, text: "Retângulo")
        add(.ellipse, 220, 30, 160, 100, fill: .soft, color: .systemBlue, text: "Elipse")
        add(.diamond, 410, 20, 160, 120, sketchy: true, color: .systemPurple, text: "Decisão?")
        add(.cylinder, 600, 20, 110, 130, color: .systemGreen, text: "DB")
        add(.cloud, 740, 30, 180, 110, sketchy: true, color: .systemTeal, text: "API")
        add(.sticky, 950, 20, 200, 150, color: .systemYellow, text: "Nota adesiva com texto quebrando linha")
        add(.person, 60, 200, 60, 110, sketchy: true, color: .black)
        add(.bubble, 150, 190, 200, 110, color: .systemOrange, text: "Olá!")
        add(.browser, 380, 190, 300, 200, color: .systemIndigo, text: "Janela")
        add(.phone, 710, 190, 110, 220, color: .darkGray)
        add(.star, 850, 200, 80, 80, fill: .solid, color: .systemYellow)
        add(.check, 960, 210, 60, 60, color: .systemGreen)
        add(.cross, 1050, 210, 60, 60, color: .systemRed)
        add(.rect, 30, 440, 220, 120, sketchy: true, fill: .solid, color: .systemBlue, text: "Sólido à mão")
        add(.arrow, 280, 460, 220, 60, color: .systemRed)
        add(.arrow, 280, 540, 220, 0, sketchy: true, color: .systemBlue)
        add(.doubleArrow, 280, 600, 220, 40, color: .systemGreen)
        add(.line, 280, 680, 220, -20, color: .black)
        add(.blur, 540, 440, 240, 140)
        add(.image, 0, 0, 0, 0) ; shapes.removeLast()
        var pen = Shape(kind: .pen, points: (0..<40).map { CGPoint(x: 820 + CGFloat($0) * 8, y: 480 + sin(CGFloat($0) / 4) * 40) }, style: ShapeStyle())
        pen.style.color = .systemPink
        shapes.append(pen)
        var hl = Shape(kind: .highlighter, points: [CGPoint(x: 820, y: 600), CGPoint(x: 1150, y: 600)], style: ShapeStyle())
        hl.style.color = .systemYellow
        shapes.append(hl)
        for (n, x) in [(1, 830.0), (2, 900.0), (3, 970.0)] {
            var s = Shape(kind: .step, points: [CGPoint(x: x, y: 680)], style: ShapeStyle())
            s.number = n
            shapes.append(s)
        }
        var t = Shape(kind: .text, points: [CGPoint(x: 30, y: 600)], style: ShapeStyle())
        t.text = "Texto nítido — Manuscrita"
        t.style.font = .hand; t.style.fontSize = 30; t.style.color = .black
        shapes.append(t)
        var t2 = Shape(kind: .text, points: [CGPoint(x: 30, y: 680)], style: ShapeStyle())
        t2.text = "Etiqueta com fundo"
        t2.style.fill = .solid; t2.style.color = .systemRed; t2.style.fontSize = 22
        shapes.append(t2)

        let w = Int(size.width * scale), h = Int(size.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(NSColor(white: 0.985, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ShapeRenderer.draw(shapes, env: env)
        // Hit tests básicos
        let hits = [shapes[0].hitTest(CGPoint(x: 30, y: 80)), shapes[14].hitTest(CGPoint(x: 390, y: 490)),
                    !shapes[0].hitTest(CGPoint(x: 110, y: 80))]
        NSGraphicsContext.restoreGraphicsState()
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: out)
        print("selftest: \(shapes.count) formas, hitTests=\(hits) → \(out.path)")

        // Desfazer/refazer
        let m = CanvasModel()
        m.checkpoint(); m.shapes.append(shapes[0])
        m.checkpoint(); m.shapes.append(shapes[1])
        m.undo()
        let u1 = m.shapes.count
        m.redo()
        print("selftest: undo→\(u1) redo→\(m.shapes.count)")
        exit(0)
    }
}
