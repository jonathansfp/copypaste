import AppKit
import Carbon
import ServiceManagement

enum DoubleClickAction: String, CaseIterable, Identifiable {
    case paste, copy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .paste: return L("Colar direto onde está o cursor")
        case .copy: return L("Apenas copiar (vira o primeiro do ⌘V)")
        }
    }
}

enum PanelPosition: String, CaseIterable, Identifiable {
    case caret, mouse, center
    var id: String { rawValue }
    var label: String {
        switch self {
        case .caret: return L("Junto ao cursor de texto")
        case .mouse: return L("Junto ao ponteiro do mouse")
        case .center: return L("Centro da tela")
        }
    }
}

struct RetentionOption: Identifiable, Hashable {
    let hours: Int
    let label: String
    var id: Int { hours }

    static let all: [RetentionOption] = [
        .init(hours: 1, label: L("1 hora")),
        .init(hours: 12, label: L("12 horas")),
        .init(hours: 24, label: L("1 dia")),
        .init(hours: 24 * 7, label: L("7 dias")),
        .init(hours: 24 * 30, label: L("30 dias")),
        .init(hours: 24 * 90, label: L("90 dias")),
        .init(hours: 24 * 365, label: L("1 ano")),
        .init(hours: 0, label: L("Para sempre")),
    ]
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published private(set) var hotKeys: [HotKeyAction: HotKey] = [:]
    var hotKeyDisplay: String { hotKeys[.clipboard]?.display ?? "—" }

    // Captura
    @Published var captureSaveDir: String { didSet { d.set(captureSaveDir, forKey: "captureSaveDir") } }
    @Published var captureFormat: CaptureFormat { didSet { d.set(captureFormat.rawValue, forKey: "captureFormat") } }
    @Published var captureEnterAction: CaptureEnterAction { didSet { d.set(captureEnterAction.rawValue, forKey: "captureEnterAction") } }
    @Published var captureMagnifier: Bool { didSet { d.set(captureMagnifier, forKey: "captureMagnifier") } }
    @Published var captureSnapWindows: Bool { didSet { d.set(captureSnapWindows, forKey: "captureSnapWindows") } }

    // Gravação
    @Published var recordDir: String { didSet { d.set(recordDir, forKey: "recordDir") } }
    @Published var recordMic: Bool { didSet { d.set(recordMic, forKey: "recordMic") } }
    @Published var recordSystemAudio: Bool { didSet { d.set(recordSystemAudio, forKey: "recordSystemAudio") } }
    @Published var recordFPS: Int { didSet { d.set(recordFPS, forKey: "recordFPS") } }
    @Published var recordShowClicks: Bool { didSet { d.set(recordShowClicks, forKey: "recordShowClicks") } }

    @Published var retentionHours: Int {
        didSet { d.set(retentionHours, forKey: "retentionHours"); ClipboardStore.shared.enforceLimits() }
    }
    @Published var maxItems: Int {
        didSet { d.set(maxItems, forKey: "maxItems"); ClipboardStore.shared.enforceLimits() }
    }
    @Published var saveImages: Bool { didSet { d.set(saveImages, forKey: "saveImages") } }
    @Published var doubleClickAction: DoubleClickAction { didSet { d.set(doubleClickAction.rawValue, forKey: "doubleClickAction") } }
    @Published var panelPosition: PanelPosition { didSet { d.set(panelPosition.rawValue, forKey: "panelPosition") } }
    @Published var launchAtLogin: Bool {
        didSet {
            d.set(launchAtLogin, forKey: "launchAtLogin")
            LoginItem.set(launchAtLogin)
        }
    }

    private init() {
        d.register(defaults: [
            "hotKeyCode": kVK_ANSI_V,
            "hotKeyModifiers": cmdKey | shiftKey,
            "hotKeyDisplay": "⇧⌘V",
            "retentionHours": 24 * 30,
            "maxItems": 500,
            "saveImages": true,
            "doubleClickAction": DoubleClickAction.paste.rawValue,
            "panelPosition": PanelPosition.caret.rawValue,
            "launchAtLogin": false,
            "captureSaveDir": FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/CopyPaste").path,
            "captureFormat": CaptureFormat.png.rawValue,
            "captureEnterAction": CaptureEnterAction.copy.rawValue,
            "captureMagnifier": true,
            "captureSnapWindows": true,
            "recordDir": FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Movies/CopyPaste").path,
            "recordMic": true,
            "recordSystemAudio": true,
            "recordFPS": 30,
            "recordShowClicks": true,
        ])
        captureSaveDir = d.string(forKey: "captureSaveDir") ?? ""
        captureFormat = CaptureFormat(rawValue: d.string(forKey: "captureFormat") ?? "") ?? .png
        captureEnterAction = CaptureEnterAction(rawValue: d.string(forKey: "captureEnterAction") ?? "") ?? .copy
        captureMagnifier = d.bool(forKey: "captureMagnifier")
        captureSnapWindows = d.bool(forKey: "captureSnapWindows")
        recordDir = d.string(forKey: "recordDir") ?? ""
        recordMic = d.bool(forKey: "recordMic")
        recordSystemAudio = d.bool(forKey: "recordSystemAudio")
        recordFPS = d.integer(forKey: "recordFPS")
        recordShowClicks = d.bool(forKey: "recordShowClicks")
        retentionHours = d.integer(forKey: "retentionHours")
        maxItems = d.integer(forKey: "maxItems")
        saveImages = d.bool(forKey: "saveImages")
        doubleClickAction = DoubleClickAction(rawValue: d.string(forKey: "doubleClickAction") ?? "") ?? .paste
        panelPosition = PanelPosition(rawValue: d.string(forKey: "panelPosition") ?? "") ?? .caret
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        hotKeys = Self.loadHotKeys(d)
    }

    // MARK: Atalhos

    private static func loadHotKeys(_ d: UserDefaults) -> [HotKeyAction: HotKey] {
        var out: [HotKeyAction: HotKey] = [:]
        for a in HotKeyAction.allCases {
            let key = "hotkey.\(a.rawValue)"
            if let data = d.data(forKey: key) {
                // Data vazio = atalho desativado pelo usuário.
                if let hk = try? JSONDecoder().decode(HotKey.self, from: data) { out[a] = KeyNames.repaired(hk) }
            } else if a == .clipboard, d.object(forKey: "hotKeyCode") != nil {
                // Migração da versão 1.0, que só tinha o atalho do histórico.
                out[a] = HotKey(code: d.integer(forKey: "hotKeyCode"), mods: d.integer(forKey: "hotKeyModifiers"),
                                display: d.string(forKey: "hotKeyDisplay") ?? "⇧⌘V")
            } else {
                out[a] = a.defaultHotKey
            }
        }
        return out
    }

    func hotKey(for action: HotKeyAction) -> HotKey? { hotKeys[action] }

    /// `nil` desativa o atalho.
    func setHotKey(_ hk: HotKey?, for action: HotKeyAction) {
        hotKeys[action] = hk
        let data = hk.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        d.set(data, forKey: "hotkey.\(action.rawValue)")
        HotKeyManager.shared.register(action)
    }

    /// Outra ação que já usa esse atalho, se houver.
    func conflict(for hk: HotKey, except action: HotKeyAction) -> HotKeyAction? {
        hotKeys.first { $0.key != action && $0.value.code == hk.code && $0.value.mods == hk.mods }?.key
    }

    var captureSaveURL: URL { URL(fileURLWithPath: (captureSaveDir as NSString).expandingTildeInPath, isDirectory: true) }
    var recordURL: URL { URL(fileURLWithPath: (recordDir as NSString).expandingTildeInPath, isDirectory: true) }
}

enum CaptureFormat: String, CaseIterable, Identifiable {
    case png, jpg
    var id: String { rawValue }
    var label: String { self == .png ? L("PNG (sem perda)") : L("JPG (arquivo menor)") }
}

enum CaptureEnterAction: String, CaseIterable, Identifiable {
    case copy, save, copyAndSave
    var id: String { rawValue }
    var label: String {
        switch self {
        case .copy: return L("Copiar")
        case .save: return L("Salvar na pasta")
        case .copyAndSave: return L("Copiar e salvar")
        }
    }
}

// MARK: - Launch at login

enum LoginItem {
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.copypaste.app.plist")
    }

    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            removeAgent()
        } catch {
            // Fallback for unsigned builds: a classic LaunchAgent.
            if on { writeAgent() } else { removeAgent() }
        }
    }

    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: return L("Ativo")
        case .requiresApproval: return L("Precisa aprovar em Ajustes do Sistema › Itens de Início")
        default:
            return FileManager.default.fileExists(atPath: agentURL.path) ? L("Ativo (LaunchAgent)") : L("Desativado")
        }
    }

    private static func writeAgent() {
        guard let exe = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": "local.copypaste.app",
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        try? FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        (plist as NSDictionary).write(to: agentURL, atomically: true)
    }

    private static func removeAgent() {
        try? FileManager.default.removeItem(at: agentURL)
    }
}

// MARK: - Key names

enum KeyNames {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return m
    }

    static func display(keyCode: Int, carbonModifiers m: Int, characters: String?) -> String {
        var s = ""
        if m & controlKey != 0 { s += "⌃" }
        if m & optionKey != 0 { s += "⌥" }
        if m & shiftKey != 0 { s += "⇧" }
        if m & cmdKey != 0 { s += "⌘" }
        return s + keyName(keyCode: keyCode, characters: characters)
    }

    static func keyName(keyCode: Int, characters: String?) -> String {
        if let name = special[keyCode] { return name }
        // Teclas de função/navegação mandam caracteres internos (U+F700…U+F8FF) que viram "?" na tela.
        if let c = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty,
           !c.unicodeScalars.contains(where: { (0xF700...0xF8FF).contains($0.value) || $0.properties.generalCategory == .control }) {
            return c.uppercased()
        }
        return L("Tecla %d", keyCode)
    }

    /// Nome legível para teclas que não têm um caractere imprimível.
    static let special: [Int: String] = [
        kVK_Space: L("Espaço"), kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ForwardDelete: "⌦", kVK_Help: "Help", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_ANSI_Keypad0: "Num 0", kVK_ANSI_Keypad1: "Num 1", kVK_ANSI_Keypad2: "Num 2", kVK_ANSI_Keypad3: "Num 3",
        kVK_ANSI_Keypad4: "Num 4", kVK_ANSI_Keypad5: "Num 5", kVK_ANSI_Keypad6: "Num 6", kVK_ANSI_Keypad7: "Num 7",
        kVK_ANSI_Keypad8: "Num 8", kVK_ANSI_Keypad9: "Num 9", kVK_ANSI_KeypadEnter: "Num ⌤",
        kVK_ANSI_KeypadClear: "Num ⌧", kVK_ANSI_KeypadPlus: "Num +", kVK_ANSI_KeypadMinus: "Num −",
        kVK_ANSI_KeypadMultiply: "Num ×", kVK_ANSI_KeypadDivide: "Num ÷", kVK_ANSI_KeypadEquals: "Num =",
        kVK_ANSI_KeypadDecimal: "Num ,",
    ]

    /// Corrige nomes gravados por versões que mostravam "?" para teclas especiais.
    static func repaired(_ hk: HotKey) -> HotKey {
        let bad = hk.display.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) || $0.value == 0xFFFD }
        guard bad || special[hk.code] != nil else { return hk }
        var fixed = hk
        fixed.display = display(keyCode: hk.code, carbonModifiers: hk.mods, characters: nil)
        return fixed
    }
}
