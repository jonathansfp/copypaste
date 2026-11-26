import AppKit
import SwiftUI
import Combine

enum BoardBackground: String, CaseIterable, Identifiable {
    case screen, white, dark, grid, chalk
    var id: String { rawValue }
    var label: String {
        switch self {
        case .screen: return L("Sobre a tela (transparente)")
        case .white: return L("Quadro branco")
        case .grid: return L("Quadriculado")
        case .dark: return L("Fundo escuro")
        case .chalk: return L("Lousa verde")
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
    /// Barra na vertical (presa numa lateral) ou horizontal. Lembrado entre aberturas.
    @Published var toolbarVertical = UserDefaults.standard.bool(forKey: "boardToolbarVertical") {
        didSet {
            UserDefaults.standard.set(toolbarVertical, forKey: "boardToolbarVertical")
            DispatchQueue.main.async { self.window?.root.layoutToolbar() }
        }
    }
    /// Posição escolhida pelo usuário (canto superior esquerdo, coordenadas da tela). nil = padrão.
    var toolbarOrigin: CGPoint? {
        get {
            guard let s = UserDefaults.standard.string(forKey: "boardToolbarOrigin") else { return nil }
            let p = NSPointFromString(s)
            return p == .zero ? nil : p
        }
        set {
            if let p = newValue { UserDefaults.standard.set(NSStringFromPoint(p), forKey: "boardToolbarOrigin") }
            else { UserDefaults.standard.removeObject(forKey: "boardToolbarOrigin") }
        }
    }

    func resetToolbarPosition() {
        toolbarOrigin = nil
        toolbarVertical = false
        window?.root.layoutToolbar()
    }

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
            Text(L("Interagindo com a tela")).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            IconButton(symbol: "pencil.tip", help: L("Voltar a desenhar (%@)", AppSettings.shared.hotKey(for: .board)?.display ?? "")) {
                BoardController.shared.passthrough = false
            }
            IconButton(symbol: "xmark", help: L("Fechar o quadro")) { BoardController.shared.close() }
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

    /// Desenha o quadro como imagem, com a tela de fundo quando o fundo é "Tela".
    private func renderBoard(_ done: @escaping @MainActor (NSImage, BoardWindow, NSScreen) -> Void) {
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
            done(image, w, screen)
        }
    }

    func export(_ action: CaptureAction) {
        renderBoard { image, w, screen in
            switch action {
            case .copy:
                ImageOutput.copy(image); Toast.show(L("Quadro copiado"))
            case .save:
                if let u = ImageOutput.saveToFolder(image) { Toast.show(L("Salvo: %@", u.lastPathComponent)) }
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

    /// Abre o menu de compartilhar do macOS (AirDrop, Mensagens, Mail…) com o quadro como PNG.
    func share() {
        renderBoard { [weak self] image, w, _ in self?.share(image, from: w) }
    }

    private func share(_ image: NSImage, from w: BoardWindow) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyPaste-Quadro", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(ImageOutput.fileName(prefix: L("Quadro"), ext: "png"))
        guard let d = ImageOutput.data(image, format: .png), (try? d.write(to: url)) != nil else { return }
        w.makeKeyAndOrderFront(nil)
        let anchor = w.root.shareAnchor
        NSSharingServicePicker(items: [url]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: toolbarVertical ? .maxX : .maxY)
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
        toolbar.rootView.onDrag = { [weak self] t, ended in self?.dragToolbar(by: t, ended: ended) }
        toolbar.rootView.panelOnLeading = { [weak self] in self?.toolbarOnRightHalf ?? false }
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

    /// Altura da área do notch/câmera (0 em telas sem notch).
    private var safeTop: CGFloat {
        guard let screen = window?.screen else { return 0 }
        return max(screen.safeAreaInsets.top, 0)
    }

    private var dragStart: CGPoint?

    func layoutToolbar() {
        guard let toolbar else { return }
        toolbar.isHidden = controller.passthrough
        let size = toolbar.fittingSize
        let origin = controller.toolbarOrigin ?? defaultToolbarOrigin(size)
        toolbar.frame = CGRect(origin: clampToolbar(origin, size: size), size: size)
    }

    private func defaultToolbarOrigin(_ size: CGSize) -> CGPoint {
        if controller.toolbarVertical {
            return CGPoint(x: 12, y: max(safeTop + 12, (bounds.height - size.height) / 2))
        }
        return CGPoint(x: (bounds.width - size.width) / 2, y: safeTop + 10)
    }

    /// Mantém a barra inteira na tela e sempre abaixo do notch.
    private func clampToolbar(_ p: CGPoint, size: CGSize) -> CGPoint {
        let minY = safeTop + 6
        return CGPoint(x: min(max(4, p.x), max(4, bounds.width - size.width - 4)),
                       y: min(max(minY, p.y), max(minY, bounds.height - size.height - 4)))
    }

    /// Chamado pela alça da barra enquanto arrasta.
    func dragToolbar(by t: CGSize, ended: Bool) {
        guard let toolbar else { return }
        let start = dragStart ?? toolbar.frame.origin
        dragStart = start
        let size = toolbar.frame.size
        let p = clampToolbar(CGPoint(x: start.x + t.width, y: start.y + t.height), size: size)
        toolbar.setFrameOrigin(p)
        guard ended else { return }
        dragStart = nil

        // Encaixe: perto das laterais vira vertical; perto do topo/base volta a ser horizontal.
        let edge: CGFloat = 70
        let nearLeft = p.x < edge, nearRight = p.x + size.width > bounds.width - edge
        let nearTop = p.y < safeTop + edge, nearBottom = p.y + size.height > bounds.height - edge
        var vertical = controller.toolbarVertical
        if (nearLeft || nearRight) && !(nearTop || nearBottom) { vertical = true }
        else if (nearTop || nearBottom) && !(nearLeft || nearRight) { vertical = false }

        if vertical != controller.toolbarVertical {
            controller.toolbarVertical = vertical
            toolbar.layoutSubtreeIfNeeded()
        }
        let newSize = toolbar.fittingSize
        var o = p
        if vertical {
            if nearLeft { o.x = 8 } else if nearRight { o.x = bounds.width - newSize.width - 8 }
            o.y = min(o.y, bounds.height - newSize.height - 4)
        } else {
            if nearTop { o.y = safeTop + 10 } else if nearBottom { o.y = bounds.height - newSize.height - 8 }
            o.x = min(max(4, o.x + size.width / 2 - newSize.width / 2), bounds.width - newSize.width - 4)
        }
        controller.toolbarOrigin = clampToolbar(o, size: newSize)
        layoutToolbar()
    }

    /// A barra fica na metade direita da tela? (o painel de estilo abre para o lado de dentro).
    /// Ponto de onde sai o menu de compartilhar: a própria barra.
    var shareAnchor: NSView { toolbar }

    var toolbarOnRightHalf: Bool { (toolbar?.frame.midX ?? 0) > bounds.midX }

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
        if flags == [.command, .shift], chars == "e" { controller.share(); return true }
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
        Toast.show(L("Seleção copiada como imagem"))
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
    /// Recebe o deslocamento do arraste da alça (coordenadas da janela, y para baixo).
    var onDrag: (CGSize, Bool) -> Void = { _, _ in }
    var panelOnLeading: () -> Bool = { false }

    private let tools: [Tool] = [.select, .draw(.pen), .draw(.highlighter), .laser, .draw(.line), .draw(.arrow),
                                 .draw(.rect), .draw(.ellipse), .draw(.diamond), .draw(.text), .draw(.sticky), .draw(.step)]

    private var vertical: Bool { controller.toolbarVertical }

    var body: some View {
        Group {
            if vertical {
                HStack(alignment: .top, spacing: 6) {
                    if ui.showStyle && panelOnLeading() { StylePanel(model: model) }
                    bar
                    if ui.showStyle && !panelOnLeading() { StylePanel(model: model) }
                }
            } else {
                VStack(spacing: 6) {
                    bar
                    if ui.showStyle { StylePanel(model: model, columns: 12) }
                }
            }
        }
        .fixedSize()
    }

    private var bar: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            grip
            ForEach(tools, id: \.self) { ToolButton(model: model, tool: $0) }
            LibraryMenu(model: model)
            ToolButton(model: model, tool: .eraser)
            separator
            StyleToggle(model: model, ui: ui)
            IconButton(symbol: "arrow.uturn.backward", help: L("Desfazer (⌘Z)"), disabled: !model.canUndo) { model.undo() }
            IconButton(symbol: "arrow.uturn.forward", help: L("Refazer (⇧⌘Z)"), disabled: !model.canRedo) { model.redo() }
            separator
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
            .help(L("Fundo (G)"))
            IconButton(symbol: "hand.point.up.left", help: L("Interagir com os apps sem apagar o desenho (I)")) {
                controller.passthrough = true
            }
            separator
            IconButton(symbol: "doc.on.doc", help: L("Copiar o quadro como imagem (⌘C) — depois é só colar no chat ou e-mail")) { controller.export(.copy) }
            IconButton(symbol: "square.and.arrow.down", help: L("Salvar o quadro na pasta (⌘S)")) { controller.export(.save) }
            IconButton(symbol: "square.and.arrow.up", help: L("Enviar: AirDrop, Mensagens, Mail… (⇧⌘E)")) { controller.share() }
            Menu {
                Button(L("Salvar como… (⇧⌘S)")) { controller.export(.saveAs) }
                Button(L("Fixar na tela")) { controller.export(.pin) }
                Divider()
                Button(L("Gravar a tela com o quadro")) { ScreenRecorder.shared.toggleFromHotKey() }
                Divider()
                Button(vertical ? L("Barra na horizontal") : L("Barra na vertical")) { controller.toolbarVertical.toggle() }
                Button(L("Barra na posição padrão")) { controller.resetToolbarPosition() }
                Divider()
                Button(L("Apagar tudo"), role: .destructive) { model.clear() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(L("Mais: salvar como, fixar, gravar, posição da barra, limpar"))
            IconButton(symbol: "xmark", help: L("Fechar quadro (⎋) — o desenho fica guardado")) { controller.close() }
        }
        .padding(4)
        .floatingBar()
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.18))
            .frame(width: vertical ? 22 : 1, height: vertical ? 1 : 20)
            .padding(vertical ? .vertical : .horizontal, 4)
    }

    /// Alça para arrastar a barra. Perto das laterais ela fica vertical; duplo clique volta ao padrão.
    private var grip: some View {
        Image(systemName: vertical ? "line.3.horizontal" : "line.3.horizontal")
            .rotationEffect(.degrees(vertical ? 0 : 90))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: vertical ? 30 : 16, height: vertical ? 16 : 30)
            .contentShape(Rectangle())
            .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in NSCursor.closedHand.set(); onDrag(v.translation, false) }
                    .onEnded { v in NSCursor.openHand.set(); onDrag(v.translation, true) }
            )
            .onTapGesture(count: 2) { controller.resetToolbarPosition() }
            .help(L("Arraste para mover a barra. Solte numa lateral para deixá-la na vertical. Duplo clique: posição padrão."))
    }
}
