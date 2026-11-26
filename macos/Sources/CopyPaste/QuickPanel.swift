import SwiftUI
import AppKit

// MARK: - Model

final class PanelModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { selectFirst() } } }
    @Published var filter: ClipKind? = nil { didSet { if filter != oldValue { selectFirst() } } }
    @Published var selectedID: UUID?
    @Published var previewing = false
    @Published var now = Date()
    @Published var focusToken = UUID()

    var results: [ClipItem] {
        ClipboardStore.shared.items.filter { item in
            (filter == nil || item.kind == filter) && item.matches(query)
        }
    }

    var selectedItem: ClipItem? {
        let r = results
        return r.first(where: { $0.id == selectedID }) ?? r.first
    }

    func reset() {
        query = ""
        filter = nil
        previewing = false
        now = Date()
        selectFirst()
        focusToken = UUID()
    }

    func selectFirst() {
        selectedID = results.first?.id
    }

    func move(_ delta: Int) {
        let r = results
        guard !r.isEmpty else { return }
        let idx = r.firstIndex(where: { $0.id == selectedID }) ?? 0
        let next = max(0, min(r.count - 1, idx + delta))
        selectedID = r[next].id
    }

    func cycleFilter(backwards: Bool) {
        let all: [ClipKind?] = [nil] + ClipKind.allCases.map { Optional($0) }
        let idx = all.firstIndex(where: { $0 == filter }) ?? 0
        let next = (idx + (backwards ? -1 : 1) + all.count) % all.count
        filter = all[next]
    }
}

// MARK: - Panel window

final class QuickPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        minSize = NSSize(width: 420, height: 320)
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()
    let model = PanelModel()
    private var panel: QuickPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let p = panel ?? makePanel()
        model.reset()
        position(p)
        p.makeKeyAndOrderFront(nil)
        installMonitor()
    }

    func hide() {
        removeMonitor()
        panel?.orderOut(nil)
    }

    /// Main action (double-click / ↩): paste or copy depending on settings.
    func activate(_ item: ClipItem) {
        if AppSettings.shared.doubleClickAction == .paste { paste(item) } else { copyOnly(item) }
    }

    func paste(_ item: ClipItem) {
        ClipboardStore.shared.copy(item)
        hide()
        guard PasteService.ensureAccessibility(prompt: true) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { PasteService.sendPaste() }
    }

    func copyOnly(_ item: ClipItem) {
        ClipboardStore.shared.copy(item)
        hide()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func makePanel() -> QuickPanel {
        let p = QuickPanel()
        p.delegate = self
        p.contentView = NSHostingView(rootView: QuickPanelView(model: model))
        if let saved = UserDefaults.standard.string(forKey: "panelSize") {
            let size = NSSizeFromString(saved)
            if size.width >= 420 && size.height >= 320 { p.setContentSize(size) }
        }
        panel = p
        return p
    }

    func windowDidResize(_ notification: Notification) {
        if let p = panel { UserDefaults.standard.set(NSStringFromSize(p.frame.size), forKey: "panelSize") }
    }

    private func position(_ p: NSPanel) {
        let size = p.frame.size
        let mode = AppSettings.shared.panelPosition
        let mouse = NSEvent.mouseLocation
        var anchor: NSRect? = nil
        if mode == .caret { anchor = PasteService.caretRect() }
        if anchor == nil && mode != .center { anchor = NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1) }

        let refPoint = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? mouse
        let screen = NSScreen.screens.first(where: { NSMouseInRect(refPoint, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame

        var origin: NSPoint
        if let a = anchor {
            origin = NSPoint(x: a.minX - 20, y: a.minY - size.height - 6)
            if origin.y < vf.minY { origin.y = a.maxY + 6 } // no room below: show above
        } else {
            origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2 + vf.height * 0.08)
        }
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        p.setFrameOrigin(origin)
    }

    // MARK: Keyboard

    private func installMonitor() {
        removeMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let p = self.panel, p.isKeyWindow else { return e }
            return self.handle(e)
        }
    }

    private func removeMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        let cmd = e.modifierFlags.contains(.command)
        switch e.keyCode {
        case 53: // esc
            if model.previewing { model.previewing = false } else { hide() }
            return nil
        case 125: model.move(1); return nil   // ↓
        case 126: model.move(-1); return nil  // ↑
        case 36, 76: // return
            if let item = model.selectedItem { cmd ? copyOnly(item) : paste(item) }
            return nil
        case 48: // tab
            model.cycleFilter(backwards: e.modifierFlags.contains(.shift))
            return nil
        case 49 where model.query.isEmpty && !cmd: // space
            if model.selectedItem != nil { model.previewing.toggle() }
            return nil
        case 51 where cmd: // ⌘⌫
            if let item = model.selectedItem {
                model.move(1)
                if model.selectedID == item.id { model.move(-1) }
                ClipboardStore.shared.delete(item)
                if model.selectedItem == nil { model.selectFirst() }
            }
            return nil
        default:
            break
        }
        if cmd, let ch = e.charactersIgnoringModifiers?.lowercased() {
            if let n = Int(ch), (1...9).contains(n) {
                let r = model.results
                if n - 1 < r.count { paste(r[n - 1]) }
                return nil
            }
            switch ch {
            case "c":
                if let item = model.selectedItem { copyOnly(item) }
                return nil
            case "p":
                if let item = model.selectedItem { ClipboardStore.shared.togglePin(item) }
                return nil
            case "l":
                hide(); WindowManager.shared.showLibrary()
                return nil
            case ",":
                hide(); WindowManager.shared.showSettings()
                return nil
            default:
                break
            }
        }
        return e
    }
}

// MARK: - Views

struct QuickPanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store = ClipboardStore.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            searchBar
            chips
            Divider().opacity(0.5)
            ZStack {
                list(results)
                if results.isEmpty { emptyState }
                if model.previewing, let item = model.selectedItem {
                    previewOverlay(item)
                }
            }
            Divider().opacity(0.5)
            footer(results.count)
        }
        .background(VisualEffect(material: .popover).ignoresSafeArea())
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _, _ in searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(.secondary)
            TextField(L("Buscar no histórico…"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            chip(L("Tudo"), nil)
            ForEach(ClipKind.allCases) { k in chip(k.label, k) }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func chip(_ title: String, _ kind: ClipKind?) -> some View {
        let on = model.filter == kind
        return Button { model.filter = kind } label: {
            Text(title)
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.6) : .clear))
                .foregroundStyle(on ? Color.accentColor : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    private func list(_ results: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                        PanelRow(item: item, index: idx, selected: item.id == (model.selectedID ?? results.first?.id),
                                 now: model.now)
                            .id(item.id)
                            .onTapGesture(count: 2) { PanelController.shared.activate(item) }
                            .simultaneousGesture(TapGesture().onEnded { model.selectedID = item.id })
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard").font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(store.items.isEmpty ? L("Nada copiado ainda") : L("Nenhum resultado"))
                .foregroundStyle(.secondary)
        }
    }

    private func previewOverlay(_ item: ClipItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                ClipThumb(item: item, size: 22)
                Text(item.title).font(.headline).lineLimit(1)
                Spacer()
                Text(L("Espaço para fechar")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ClipPreview(item: item).padding(8)
        }
        .background(VisualEffect(material: .windowBackground, blending: .withinWindow))
    }

    private func footer(_ count: Int) -> some View {
        HStack(spacing: 14) {
            Text(L("%d de %d itens", count, store.items.count))
            Spacer()
            Text(L("↩ Colar"))
            Text(L("⌘↩ Copiar"))
            Text(L("Espaço Prévia"))
            Button { PanelController.shared.hide(); WindowManager.shared.showLibrary() } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .help(L("Abrir biblioteca (⌘L)"))
            Button { PanelController.shared.hide(); WindowManager.shared.showSettings() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help(L("Configurações (⌘,)"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

struct PanelRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let now: Date
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            ClipThumb(item: item, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if item.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                }
                AppSourceLabel(item: item, now: now)
            }
            Spacer(minLength: 8)
            if hover || selected {
                actions
            } else if index < 9 {
                Text("⌘\(index + 1)").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.16) : (hover ? Color.primary.opacity(0.05) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { ClipboardStore.shared.togglePin(item) } label: {
                Image(systemName: item.pinned ? "pin.slash" : "pin")
            }
            .help(item.pinned ? L("Desafixar (⌘P)") : L("Fixar (⌘P)"))
            Button { PanelController.shared.copyOnly(item) } label: {
                Image(systemName: "doc.on.doc")
            }
            .help(L("Copiar sem colar — vira o primeiro do ⌘V (⌘↩)"))
            Menu {
                Button(L("Colar")) { PanelController.shared.paste(item) }
                Button(L("Copiar")) { PanelController.shared.copyOnly(item) }
                Button(item.pinned ? L("Desafixar") : L("Fixar")) { ClipboardStore.shared.togglePin(item) }
                Divider()
                Button(L("Excluir"), role: .destructive) { ClipboardStore.shared.delete(item) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }
}
