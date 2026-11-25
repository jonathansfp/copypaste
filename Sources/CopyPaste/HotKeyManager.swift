import AppKit
import Carbon

/// Everything that can be bound to a global shortcut.
enum HotKeyAction: String, CaseIterable, Identifiable {
    case clipboard, captureArea, captureScreen, board, record

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clipboard: return "Abrir histórico de cópias"
        case .captureArea: return "Capturar área ou janela"
        case .captureScreen: return "Capturar tela inteira"
        case .board: return "Modo apresentação (quadro)"
        case .record: return "Gravar tela (iniciar / parar)"
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: return "list.clipboard"
        case .captureArea: return "viewfinder"
        case .captureScreen: return "macwindow"
        case .board: return "pencil.and.scribble"
        case .record: return "record.circle"
        }
    }

    fileprivate var hotKeyID: UInt32 { UInt32(Self.allCases.firstIndex(of: self)! + 1) }

    var defaultHotKey: HotKey? {
        switch self {
        case .clipboard: return HotKey(code: kVK_ANSI_V, mods: cmdKey | shiftKey, display: "⇧⌘V")
        case .captureArea: return HotKey(code: kVK_ANSI_1, mods: cmdKey | shiftKey, display: "⇧⌘1")
        case .captureScreen: return HotKey(code: kVK_ANSI_2, mods: cmdKey | shiftKey, display: "⇧⌘2")
        case .board: return HotKey(code: kVK_ANSI_D, mods: cmdKey | shiftKey | optionKey, display: "⌥⇧⌘D")
        case .record: return HotKey(code: kVK_ANSI_R, mods: cmdKey | shiftKey | optionKey, display: "⌥⇧⌘R")
        }
    }
}

struct HotKey: Codable, Equatable {
    var code: Int
    var mods: Int
    var display: String
}

/// Global hotkeys via Carbon (works without Accessibility permission).
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    var handlers: [HotKeyAction: @MainActor () -> Void] = [:]
    /// Actions whose shortcut could not be registered (usually taken by another app).
    @Published private(set) var failed: Set<HotKeyAction> = []

    private var refs: [HotKeyAction: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    func registerFromSettings() {
        HotKeyAction.allCases.forEach(register)
    }

    func register(_ action: HotKeyAction) {
        unregister(action)
        installHandlerIfNeeded()
        guard let hk = AppSettings.shared.hotKey(for: action) else {
            failed.remove(action)
            return
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4350_5354), id: action.hotKeyID) // "CPST"
        let status = RegisterEventHotKey(UInt32(hk.code), UInt32(hk.mods), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[action] = ref
            failed.remove(action)
            Diag.log("atalho registrado: \(action.rawValue) = \(hk.display) (code \(hk.code), mods \(hk.mods))")
        } else {
            failed.insert(action)
            Diag.log("FALHA ao registrar atalho \(action.rawValue) = \(hk.display) (code \(hk.code)): status \(status)")
        }
    }

    func unregister(_ action: HotKeyAction) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    func unregisterAll() {
        HotKeyAction.allCases.forEach(unregister)
    }

    @MainActor fileprivate func fire(_ id: UInt32) {
        guard let action = HotKeyAction.allCases.first(where: { $0.hotKeyID == id }) else { return }
        Diag.log("atalho disparado: \(action.rawValue)")
        handlers[action]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard err == noErr else { return noErr }
            let id = hk.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyManager.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
