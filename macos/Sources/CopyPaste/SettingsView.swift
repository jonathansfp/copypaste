import SwiftUI
import AppKit
import Combine

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store = ClipboardStore.shared
    @State private var axTrusted = PasteService.isTrusted
    @State private var loginStatus = LoginItem.statusText
    @State private var confirmClear = false
    @State private var screenTrusted = ScreenGrabber.hasPermission
    @ObservedObject private var hotkeys = HotKeyManager.shared
    @State private var language = AppLanguage.chosen
    @State private var languageChanged = false
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CopyPaste \(UpdateChecker.current)").font(.headline)
                        Text(L("Desenvolvido por Jonathan Felix · gratuito e de código aberto")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link("jonathansfp@gmail.com", destination: URL(string: "mailto:jonathansfp@gmail.com")!).font(.caption)
                }
            }
            Section(L("Geral")) {
                Picker(L("Idioma"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: language) { _, v in
                    AppLanguage.chosen = v
                    languageChanged = true
                }
                if languageChanged {
                    HStack {
                        Text(L("O novo idioma vale depois de reiniciar o CopyPaste."))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Reiniciar agora")) { Self.relaunch() }
                    }
                }
                Toggle(L("Abrir ao ligar o Mac"), isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { loginStatus = LoginItem.statusText }
                    }
                LabeledContent(L("Status do início automático")) {
                    Text(loginStatus).foregroundStyle(.secondary)
                }
                Picker(L("Duplo clique / ↩ no painel"), selection: $settings.doubleClickAction) {
                    ForEach(DoubleClickAction.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("Posição do painel"), selection: $settings.panelPosition) {
                    ForEach(PanelPosition.allCases) { Text($0.label).tag($0) }
                }
            }

            Section(L("Atalhos globais")) {
                ForEach(HotKeyAction.allCases) { action in
                    LabeledContent {
                        HotKeyRecorder(action: action)
                    } label: {
                        Label(action.label, systemImage: action.symbol)
                        if hotkeys.failed.contains(action) {
                            Text(L("Esse atalho já é usado por outro app. Escolha outro."))
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                Text(L("Clique no atalho e pressione a nova combinação. ⎋ cancela, ⌫ desativa."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Captura de tela")) {
                LabeledContent(L("Pasta para salvar")) {
                    HStack {
                        Text(settings.captureSaveDir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button(L("Alterar…")) { chooseFolder(\.captureSaveDir) }
                    }
                }
                Picker(L("Formato"), selection: $settings.captureFormat) {
                    ForEach(CaptureFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("↩ ou duplo clique na captura"), selection: $settings.captureEnterAction) {
                    ForEach(CaptureEnterAction.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("Mostrar lupa com coordenadas e cor do pixel"), isOn: $settings.captureMagnifier)
                Toggle(L("Destacar janelas ao passar o mouse (clique captura a janela)"), isOn: $settings.captureSnapWindows)
            }

            Section(L("Gravação de tela")) {
                LabeledContent(L("Pasta dos vídeos")) {
                    HStack {
                        Text(settings.recordDir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button(L("Alterar…")) { chooseFolder(\.recordDir) }
                    }
                }
                Toggle(L("Gravar o microfone"), isOn: $settings.recordMic)
                Toggle(L("Gravar o áudio do Mac (sons dos apps)"), isOn: $settings.recordSystemAudio)
                Toggle(L("Destacar os cliques do mouse"), isOn: $settings.recordShowClicks)
                Picker(L("Quadros por segundo"), selection: $settings.recordFPS) {
                    Text(L("24 (arquivo menor)")).tag(24)
                    Text(L("30 (recomendado)")).tag(30)
                    Text(L("60 (movimentos suaves)")).tag(60)
                }
                if !ScreenRecorder.isSupported {
                    Text(L("A gravação de tela requer macOS 15 ou mais recente.")).font(.caption).foregroundStyle(.orange)
                }
            }

            DictationSettingsSections()

            Section(L("Histórico")) {
                Picker(L("Guardar itens copiados por"), selection: $settings.retentionHours) {
                    ForEach(RetentionOption.all) { Text($0.label).tag($0.hours) }
                }
                Picker(L("Limite de itens"), selection: $settings.maxItems) {
                    ForEach([50, 100, 200, 500, 1000, 2000, 5000], id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle(L("Salvar imagens copiadas"), isOn: $settings.saveImages)
                Toggle(L("Pausar captura"), isOn: $store.paused)
                LabeledContent(L("Itens salvos")) {
                    HStack {
                        Text("\(store.items.count)").foregroundStyle(.secondary)
                        Button(L("Mostrar pasta")) { NSWorkspace.shared.open(store.baseDir) }
                        Button(L("Limpar histórico…"), role: .destructive) { confirmClear = true }
                    }
                }
                Text(L("Itens fixados nunca expiram nem são apagados ao limpar."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Permissões")) {
                LabeledContent(L("Acessibilidade (para colar automaticamente)")) {
                    if axTrusted {
                        Label(L("Permitido"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button(L("Permitir…")) {
                            PasteService.ensureAccessibility(prompt: true)
                            PasteService.openAccessibilitySettings()
                        }
                    }
                }
                if !axTrusted {
                    Text(L("Sem essa permissão o item é apenas copiado (vira o primeiro do ⌘V), mas não é colado sozinho."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent(L("Gravação de Tela (para capturar e gravar)")) {
                    if screenTrusted {
                        Label(L("Permitido"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button(L("Permitir…")) {
                            CGRequestScreenCaptureAccess()
                            ScreenGrabber.openSettings()
                        }
                    }
                }
                if !screenTrusted {
                    Text(L("Depois de permitir, feche e abra o CopyPaste para valer."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(L("Atalhos na captura e no quadro")) {
                shortcut("V P H L A R O D T N S B E K", L("Ferramentas (selecionar, caneta, marca-texto, linha, seta…)"))
                shortcut("1 … 9", L("Trocar cor"))
                shortcut(L("⇧ arrastando"), L("Linha a 45°, quadrado, círculo"))
                shortcut(L("⌥ arrastando"), L("Duplicar o item selecionado"))
                shortcut(L("Duplo clique"), L("Editar texto de um item"))
                shortcut("⌘Z / ⇧⌘Z", L("Desfazer / refazer"))
                shortcut("⌘C · ⌘S · ⇧⌘S", L("Copiar · salvar · salvar como"))
                shortcut("⌘T", L("Copiar o texto da captura (OCR)"))
                shortcut(L("⌘ arrastando"), L("Mover a área da captura"))
                shortcut(L("C (antes de selecionar)"), L("Copiar a cor do pixel"))
                shortcut(L("G · I · ⌘V (no quadro)"), L("Trocar fundo · interagir com a tela · colar imagem/texto"))
            }

            Section(L("Atalhos no painel")) {
                shortcut("↑ ↓", L("Navegar"))
                shortcut(L("↩ ou duplo clique"), L("Colar onde está o cursor"))
                shortcut(L("⌘↩ ou ⌘C"), L("Só copiar (vira o primeiro do ⌘V)"))
                shortcut("⌘1 … ⌘9", L("Colar o item da posição"))
                shortcut(L("Espaço"), L("Pré-visualizar"))
                shortcut("⇥ / ⇧⇥", L("Trocar filtro"))
                shortcut("⌘P", L("Fixar / desafixar"))
                shortcut("⌘⌫", L("Excluir item"))
                shortcut("⌘L", L("Abrir biblioteca"))
                shortcut("⎋", L("Fechar"))
            }

            Section(L("Apoie o projeto")) {
                Text(L("O CopyPaste é gratuito e de código aberto. Se ele te ajuda, considere uma doação via Pix — qualquer valor ajuda a manter o projeto."))
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent(L("Chave Pix")) {
                    HStack {
                        Text(Donation.pixKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Button(L("Copiar")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Donation.pixKey, forType: .string)
                            Toast.show(L("Chave Pix copiada — obrigado!"), symbol: "heart.fill")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 600)
        .onReceive(timer) { _ in
            axTrusted = PasteService.isTrusted
            screenTrusted = ScreenGrabber.hasPermission
        }
        .confirmationDialog(L("Apagar todo o histórico (exceto fixados)?"), isPresented: $confirmClear) {
            Button(L("Apagar"), role: .destructive) { store.clear(keepPinned: true) }
        }
    }

    private func shortcut(_ keys: String, _ what: String) -> some View {
        LabeledContent(what) {
            Text(keys).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}

struct HotKeyRecorder: View {
    let action: HotKeyAction
    @ObservedObject var settings = AppSettings.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    recording ? stop() : start()
                } label: {
                    Text(recording ? L("Pressione as teclas…") : (settings.hotKey(for: action)?.display ?? L("Desativado")))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(minWidth: 130)
                }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
                if recording {
                    Button(L("Cancelar")) { stop() }.buttonStyle(.borderless)
                } else if settings.hotKey(for: action) != action.defaultHotKey {
                    Button {
                        settings.setHotKey(action.defaultHotKey, for: action)
                    } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .help(L("Voltar ao padrão (%@)", action.defaultHotKey?.display ?? ""))
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        message = nil
        HotKeyManager.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil } // esc cancela
            if e.keyCode == 51 || e.keyCode == 117 { // ⌫ desativa
                settings.setHotKey(nil, for: action)
                stop()
                return nil
            }
            let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
            let isFKey = (96...122).contains(Int(e.keyCode)) || [105, 107, 113, 106, 64, 79, 80, 90].contains(Int(e.keyCode))
            guard isFKey || !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                message = L("Use ⌘, ⌥ ou ⌃ (ou uma tecla F)")
                return nil
            }
            let mods = KeyNames.carbonModifiers(from: flags)
            let display = KeyNames.display(keyCode: Int(e.keyCode), carbonModifiers: mods,
                                           characters: e.charactersIgnoringModifiers)
            let hk = HotKey(code: Int(e.keyCode), mods: mods, display: display)
            if let other = settings.conflict(for: hk, except: action) {
                // Troca: o outro atalho fica desativado.
                settings.setHotKey(nil, for: other)
                message = L("%@ estava em “%@”, que ficou sem atalho.", display, other.label)
            }
            settings.setHotKey(hk, for: action)
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if recording {
            recording = false
            HotKeyManager.shared.registerFromSettings()
        }
    }
}

extension SettingsView {
    /// Opens a new copy of the app once this one has quit (used after changing the language).
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    func chooseFolder(_ key: ReferenceWritableKeyPath<AppSettings, String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Escolher")
        panel.directoryURL = URL(fileURLWithPath: (settings[keyPath: key] as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            settings[keyPath: key] = url.path
        }
    }
}
