import AppKit
import SwiftUI
import Combine

enum BoardBackground: String, CaseIterable, Identifiable {
    case screen, white, dark, grid, chalk
    var id: String { rawValue }
    var label: String {
        switch self {
        case .screen: return "Sobre a tela (transparente)"
        case .white: return "Quadro branco"
        case .grid: return "Quadriculado"
        case .dark: return "Fundo escuro"
        case .chalk: return "Lousa verde"
        }
    }
    var symbol: String {
        switch self {
        case .screen: return "macwindow.on.rectangle"
        case .white: return "rectangle.fill"
        case .grid: return "grid"
        case .dark: return "rectangle.inset.filled"
        case .chalk: return "rectangle.fill"
        }
    }
    var color: NSColor? {
        switch self {
        case .screen: return nil
        case .white, .grid: return NSColor(white: 0.985, alpha: 1)
        case .dark: return NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        case .chalk: return NSColor(red: 0.12, green: 0.25, blue: 0.2, alpha: 1)
        }
    }
}

/// Presentation / whiteboard mode. Drawings are kept in memory between openings until cleared.
@MainActor
final class BoardController: ObservableObject {
    static let shared = BoardController()

    let model = CanvasModel()
    let ui = CanvasUIState()
    @Published var background: BoardBackground = .screen { didSet { window?.root.applyBackground() } }
    @Published var passthrough = false { didSet { applyPassthrough() } }
    @Published var toolbarHidden = false { didSet { window?.root.layoutToolbar() } }

    private var window: BoardWindow?
    private var pill: NSPanel?
    private var previousApp: NSRunningApplication?

    var isOpen: Bool { window != nil }

    private init() {
        model.tool = .draw(.pen)
        model.style.width = 4
        model.style.fontSize = 36
        model.style.color = .systemRed
    }

    func toggle() {
        if let _ = window {
            if passthrough { passthrough = false } else { close() }
        } else {
            open()
        }
    }

    func open(with image: NSImage? = nil) {
        if window == nil {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            let screen = ScreenGrabber.screenUnderMouse()
            let w = BoardWindow(screen: screen, controller: self)
            window = w
            w.orderFrontRegardless()
        }
        passthrough = false
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.root.canvas)
        if let image { window?.root.insertImage(image) }
    }

    func close() {
        window?.root.canvas.commitText()
        pill?.orderOut(nil)
        pill = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        passthrough = false
        if let app = previousApp { app.activate() }
        previousApp = nil
    }

    // MARK: Pass-through (interact with the apps below, drawings stay visible)

    private func applyPassthrough() {
        guard let w = window else { return }
        w.ignoresMouseEvents = passthrough
        w.root.layoutToolbar()
        if passthrough {
            w.root.canvas.commitText()
            showPill(on: w.screen ?? ScreenGrabber.screenUnderMouse())
            previousApp?.activate()
        } else {
            pill?.orderOut(nil)
            pill = nil
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
        }
    }

    private func showPill(on screen: NSScreen) {
        let view = HStack(spacing: 4) {
            Image(systemName: "hand.point.up.left").foregroundStyle(.white.opacity(0.7)).padding(.leading, 6)
            Text("Interagindo com a tela").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            IconButton(symbol: "pencil.tip", help: "Voltar a desenhar (\(AppSettings.shared.hotKey(for: .board)?.display ?? ""))") {
                BoardController.shared.passthrough = false
            }
            IconButton(symbol: "xmark", help: "Fechar o quadro") { BoardController.shared.close() }
        }
        .padding(4)
        .floatingBar()
        .fixedSize()
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 10,
                           width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar + 1
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.contentView = host
        p.orderFrontRegardless()
        pill = p
    }

    // MARK: Export

    func export(_ action: CaptureAction) {
        guard let w = window else { return }
        w.root.canvas.commitText()
        let screen = w.screen ?? ScreenGrabber.screenUnderMouse()
        Task { @MainActor in
            var base: CGImage?
            if background == .screen {
                if let d = try? await ScreenGrabber.display(for: screen) {
                    base = try? await ScreenGrabber.capture(display: d, screen: screen, excludingSelf: true)
                }
            }
            guard let image = w.root.render(base: base) else { return }
            switch action {
            case .copy:
                ImageOutput.copy(image); Toast.show("Quadro copiado")
            case .save:
                if let u = ImageOutput.saveToFolder(image) { Toast.show("Salvo: \(u.lastPathComponent)") }
            case .saveAs:
                w.orderOut(nil)
                ImageOutput.saveAs(image)
                w.orderFrontRegardless()
                w.makeKeyAndOrderFront(nil)
            case .pin:
                PinWindow.pin(image, at: CGRect(x: screen.frame.midX - image.size.width / 4, y: screen.frame.midY - image.size.height / 4,
                                                width: image.size.width / 2, height: image.size.height / 2))
            default: break
            }
        }
    }
}

// MARK: - Window

final class BoardWindow: NSWindow {
    let root: BoardRootView

    @MainActor
    init(screen: NSScreen, controller: BoardController) {
        root = BoardRootView(controller: controller, size: screen.frame.size)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        contentView = root
        root.frame = CGRect(origin: .zero, size: screen.frame.size)
        root.applyBackground()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class BoardRootView: NSView {
    unowned let controller: BoardController
    let canvas: BoardCanvasView
    private var toolbar: NSHostingView<BoardToolbar>!
    private var bag: Set<AnyCancellable> = []

    init(controller: BoardController, size: CGSize) {
        self.controller = controller
        canvas = BoardCanvasView(model: controller.model)
        super.init(frame: CGRect(origin: .zero, size: size))
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.controller = controller
        addSubview(canvas)
        toolbar = NSHostingView(rootView: BoardToolbar(controller: controller, model: controller.model, ui: controller.ui))
        addSubview(toolbar)
        controller.ui.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.layoutToolbar() } }.store(in: &bag)
        layoutToolbar()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        layoutToolbar()
    }

    func layoutToolbar() {
        guard let toolbar else { return }
        toolbar.isHidden = controller.passthrough
        let size = toolbar.fittingSize
        toolbar.frame = CGRect(x: (bounds.width - size.width) / 2, y: 12, width: size.width, height: size.height)
    }

    func applyBackground() {
        canvas.boardBackground = controller.background
        canvas.needsDisplay = true
    }

    func insertImage(_ image: NSImage) {
        var size = image.size
        let maxW = bounds.width * 0.7, maxH = bounds.height * 0.7
        let k = min(1, min(maxW / max(size.width, 1), maxH / max(size.height, 1)))
        size = CGSize(width: size.width * k, height: size.height * k)
        let o = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 + 20)
        var s = Shape(kind: .image, points: [o, CGPoint(x: o.x + size.width, y: o.y + size.height)], style: controller.model.style)
        s.image = image
        s.style.fill = .none
        controller.model.checkpoint()
        controller.model.shapes.append(s)
        controller.model.selection = [s.id]
        controller.model.tool = .select
    }

    func insertText(_ text: String) {
        var s = Shape(kind: .text, points: [CGPoint(x: bounds.midX - 200, y: bounds.midY)], style: controller.model.style)
        s.text = text
        controller.model.checkpoint()
        controller.model.shapes.append(s)
        controller.model.selection = [s.id]
        controller.model.tool = .select
    }

    /// Renders the whole board (background + drawings) at Retina resolution.
    func render(base: CGImage?) -> NSImage? {
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        if let base { ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        if base == nil { canvas.drawBoardBackground(in: bounds, forExport: true) }
        ShapeRenderer.draw(controller.model.shapes, env: canvas.env)
        NSGraphicsContext.restoreGraphicsState()
        guard let img = ctx.makeImage() else { return nil }
        return NSImage(cgImage: img, size: bounds.size)
    }
}

@MainActor
final class BoardCanvasView: CanvasView {
    weak var controller: BoardController?
    var boardBackground: BoardBackground = .screen

    override init(model: CanvasModel) {
        super.init(model: model)
        onKey = { [weak self] e in self?.boardKey(e) ?? false }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func drawBackground(_ dirtyRect: NSRect) {
        drawBoardBackground(in: dirtyRect, forExport: false)
    }

    func drawBoardBackground(in rect: CGRect, forExport: Bool) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let c = boardBackground.color {
            ctx.setFillColor(c.cgColor)
            ctx.fill(rect)
        } else if !forExport {
            // Almost invisible tint so the transparent window still receives clicks.
            ctx.setFillColor(NSColor(white: 0, alpha: 0.012).cgColor)
            ctx.fill(rect)
        }
        if boardBackground == .grid {
            ctx.setStrokeColor(NSColor(white: 0, alpha: 0.07).cgColor)
            ctx.setLineWidth(1)
            let step: CGFloat = 24
            var x = (rect.minX / step).rounded(.down) * step
            while x <= rect.maxX { ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
            var y = (rect.minY / step).rounded(.down) * step
            while y <= rect.maxY { ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
            ctx.strokePath()
        }
    }

    private func boardKey(_ e: NSEvent) -> Bool {
        guard let controller else { return false }
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if e.keyCode == 53 {
            if !model.selection.isEmpty { model.selection = []; return true }
            controller.close()
            return true
        }
        if isEditingText { return false }
        if flags == .command {
            switch chars {
            case "v": paste(); return true
            case "c":
                if model.selection.isEmpty { controller.export(.copy) } else { copySelection() }
                return true
            case "s": controller.export(.save); return true
            case "b": cycleBackground(); return true
            default: break
            }
        }
        if flags == [.command, .shift], chars == "s" { controller.export(.saveAs); return true }
        if flags.isEmpty, chars == "g" { cycleBackground(); return true }
        if flags.isEmpty, chars == "i" { controller.passthrough = true; return true }
        if flags.isEmpty, chars == "f" { model.bringToFront(); return true }
        return false
    }

    private func cycleBackground() {
        guard let controller else { return }
        let all = BoardBackground.allCases
        let i = all.firstIndex(of: controller.background) ?? 0
        controller.background = all[(i + 1) % all.count]
    }

    private func copySelection() {
        // Render just the selected shapes on transparent background.
        let sel = model.selectedShapes
        guard let first = sel.first else { return }
        let r = sel.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }.insetBy(dx: -6, dy: -6)
        let img = NSImage(size: r.size, flipped: true) { _ in
            NSGraphicsContext.current?.cgContext.translateBy(x: -r.minX, y: -r.minY)
            ShapeRenderer.draw(sel, env: self.env)
            return true
        }
        ImageOutput.copy(img)
        Toast.show("Seleção copiada como imagem")
    }

    private func paste() {
        let pb = NSPasteboard.general
        guard let root = superview as? BoardRootView else { return }
        if let img = NSImage(pasteboard: pb), pb.availableType(from: [.png, .tiff, .fileURL]) != nil,
           pb.string(forType: .string) == nil || pb.availableType(from: [.png, .tiff]) != nil {
            root.insertImage(img)
        } else if let s = pb.string(forType: .string), !s.isEmpty {
            root.insertText(s)
        }
    }
}

// MARK: - Toolbar

struct BoardToolbar: View {
    @ObservedObject var controller: BoardController
    @ObservedObject var model: CanvasModel
    @ObservedObject var ui: CanvasUIState

    private let tools: [Tool] = [.select, .draw(.pen), .draw(.highlighter), .laser, .draw(.line), .draw(.arrow),
                                 .draw(.rect), .draw(.ellipse), .draw(.diamond), .draw(.text), .draw(.sticky), .draw(.step)]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(tools, id: \.self) { ToolButton(model: model, tool: $0) }
                LibraryMenu(model: model)
                ToolButton(model: model, tool: .eraser)
                Divider().frame(height: 20).padding(.horizontal, 3)
                StyleToggle(model: model, ui: ui)
                IconButton(symbol: "arrow.uturn.backward", help: "Desfazer (⌘Z)", disabled: !model.canUndo) { model.undo() }
                IconButton(symbol: "arrow.uturn.forward", help: "Refazer (⇧⌘Z)", disabled: !model.canRedo) { model.redo() }
                Divider().frame(height: 20).padding(.horizontal, 3)
                Menu {
                    ForEach(BoardBackground.allCases) { b in
                        Button { controller.background = b } label: {
                            Label(b.label, systemImage: controller.background == b ? "checkmark" : b.symbol)
                        }
                    }
                } label: {
                    Image(systemName: controller.background.symbol).font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Fundo (G)")
                IconButton(symbol: "hand.point.up.left", help: "Interagir com os apps sem apagar o desenho (I)") {
                    controller.passthrough = true
                }
                Menu {
                    Button("Copiar imagem (⌘C)") { controller.export(.copy) }
                    Button("Salvar na pasta (⌘S)") { controller.export(.save) }
                    Button("Salvar como… (⇧⌘S)") { controller.export(.saveAs) }
                    Button("Fixar na tela") { controller.export(.pin) }
                    Divider()
                    Button("Gravar a tela com o quadro") { ScreenRecorder.shared.toggleFromHotKey() }
                    Divider()
                    Button("Apagar tudo", role: .destructive) { model.clear() }
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Exportar, gravar, limpar")
                IconButton(symbol: "xmark", help: "Fechar quadro (⎋) — o desenho fica guardado") { controller.close() }
            }
            .padding(4)
            .floatingBar()
            if ui.showStyle {
                StylePanel(model: model, columns: 12)
            }
        }
        .fixedSize()
    }
}
