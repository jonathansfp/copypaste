import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var recordBag: Set<AnyCancellable> = []
    private var recordTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppSettings.shared
        _ = DictationSettings.shared // also fixes models saved by older versions
        ClipboardStore.shared.start()
        HotKeyManager.shared.handlers = [
            .clipboard: { PanelController.shared.toggle() },
            .captureArea: { CaptureController.shared.start() },
            .captureScreen: { CaptureController.shared.start(fullScreen: true) },
            .board: { BoardController.shared.toggle() },
            .record: { ScreenRecorder.shared.toggleFromHotKey() },
            .dictate: { DictationController.shared.keyDown(.dictate) },
            .voiceCommand: { DictationController.shared.keyDown(.command) },
        ]
        HotKeyManager.shared.releaseHandlers = [
            .dictate: { DictationController.shared.keyUp(.dictate) },
            .voiceCommand: { DictationController.shared.keyUp(.command) },
        ]
        HotKeyManager.shared.registerFromSettings()
        setupStatusItem()
        UpdateChecker.start()
        ScreenRecorder.shared.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] on in self?.updateRecordingIndicator(on) }
            .store(in: &recordBag)

        let d = UserDefaults.standard
        if !d.bool(forKey: "didFirstRun") {
            d.set(true, forKey: "didFirstRun")
            AppSettings.shared.launchAtLogin = true
            WindowManager.shared.showSettings()
            PasteService.ensureAccessibility(prompt: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardStore.shared.saveNow()
        LocalAI.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showLibrary()
        return true
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "CopyPaste")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateRecordingIndicator(_ on: Bool) {
        guard let button = statusItem?.button else { return }
        recordTimer?.invalidate()
        recordTimer = nil
        if on {
            let img = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Gravando")?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            button.image = img
            button.imagePosition = .imageLeading
            statusItem.length = NSStatusItem.variableLength
            let tick: @MainActor () -> Void = { [weak self] in
                guard let start = ScreenRecorder.shared.startedAt else { return }
                let t = Int(Date().timeIntervalSince(start))
                self?.statusItem.button?.title = String(format: " %d:%02d", t / 60, t % 60)
            }
            tick()
            let timer = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
            RunLoop.main.add(timer, forMode: .common)
            recordTimer = timer
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "CopyPaste")
            button.image?.isTemplate = true
            statusItem.length = NSStatusItem.squareLength
        }
    }

    private func hotKeyItem(_ title: String, _ action: HotKeyAction, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
        if let hk = AppSettings.shared.hotKey(for: action) {
            let attr = NSMutableAttributedString(string: title + "   ")
            attr.append(NSAttributedString(string: hk.display, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = attr
        }
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = ClipboardStore.shared

        if ScreenRecorder.shared.isRecording {
            let stop = NSMenuItem(title: "Parar gravação", action: #selector(toggleRecording), keyEquivalent: "")
            stop.target = self
            stop.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
            menu.addItem(stop)
            menu.addItem(.separator())
        }
        menu.addItem(hotKeyItem("Capturar área ou janela", .captureArea, #selector(captureArea)))
        menu.addItem(hotKeyItem("Capturar tela inteira", .captureScreen, #selector(captureScreen)))
        menu.addItem(hotKeyItem("Modo apresentação (quadro)", .board, #selector(openBoard)))
        if !ScreenRecorder.shared.isRecording {
            menu.addItem(hotKeyItem("Gravar tela…", .record, #selector(toggleRecording)))
        }
        menu.addItem(hotKeyItem("Ditado por voz", .dictate, #selector(startDictation)))
        menu.addItem(hotKeyItem("Comando de voz", .voiceCommand, #selector(startVoiceCommand)))
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Abrir histórico   \(AppSettings.shared.hotKeyDisplay)",
                              action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(withTitle: "Biblioteca…", action: #selector(openLibrary), keyEquivalent: "l").target = self
        menu.addItem(.separator())

        let recent = store.items.prefix(8)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "Nada copiado ainda", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in recent {
                var title = item.title
                if title.count > 50 { title = String(title.prefix(50)) + "…" }
                let mi = NSMenuItem(title: title, action: #selector(copyRecent(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.id
                if let thumb = item.kind == .image ? ImageCache.shared.thumbnail(for: item, maxPixel: 80) : nil {
                    thumb.size = NSSize(width: 16, height: 16)
                    mi.image = thumb
                } else {
                    mi.image = NSImage(systemSymbolName: item.kind.symbol, accessibilityDescription: nil)
                }
                menu.addItem(mi)
            }
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pausar captura", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = store.paused ? .on : .off
        menu.addItem(pause)
        menu.addItem(withTitle: "Limpar histórico…", action: #selector(clearHistory), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Configurações…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Verificar atualizações…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Doar via Pix ♥", action: #selector(donatePix), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair do CopyPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func captureArea() { delayed { CaptureController.shared.start() } }
    @objc private func captureScreen() { delayed { CaptureController.shared.start(fullScreen: true) } }
    @objc private func openBoard() { delayed { BoardController.shared.open() } }
    @objc private func toggleRecording() { delayed { ScreenRecorder.shared.toggleFromHotKey() } }

    /// Lets the menu close before the screen is frozen.
    private func delayed(_ f: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: f)
    }

    @objc private func openPanel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { PanelController.shared.show() }
    }
    @objc private func openLibrary() { WindowManager.shared.showLibrary() }
    @objc private func openSettings() { WindowManager.shared.showSettings() }
    @objc private func checkUpdates() { Task { await UpdateChecker.check(manual: true) } }
    @objc private func startDictation() { DictationController.shared.start(.dictate) }
    @objc private func startVoiceCommand() { DictationController.shared.start(.command) }
    @objc private func donatePix() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Donation.pixKey, forType: .string)
        Toast.show("Chave Pix copiada — obrigado pelo apoio!", symbol: "heart.fill", duration: 2.6)
    }
    @objc private func togglePause() { ClipboardStore.shared.paused.toggle() }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = ClipboardStore.shared.items.first(where: { $0.id == id }) else { return }
        ClipboardStore.shared.copy(item)
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Apagar todo o histórico?"
        alert.informativeText = "Os itens fixados serão mantidos. Essa ação não pode ser desfeita."
        alert.addButton(withTitle: "Apagar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            ClipboardStore.shared.clear(keepPinned: true)
        }
    }
}

// MARK: - Windows

final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    private var library: NSWindow?
    private var settings: NSWindow?

    func showLibrary() {
        if library == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "CopyPaste"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: LibraryView())
            w.center()
            w.setFrameAutosaveName("CopyPasteLibrary")
            w.delegate = self
            library = w
        }
        present(library!)
    }

    func showSettings() {
        if settings == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Configurações do CopyPaste"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            w.delegate = self
            settings = w
        }
        present(settings!)
    }

    private func present(_ w: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let anyOpen = [self.library, self.settings].contains { $0?.isVisible == true }
            if !anyOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

/// Doação voluntária para apoiar o projeto.
enum Donation {
    static let pixKey = "586cb2d1-8a6e-4bed-8cdb-1f413e8f3e38"
}
