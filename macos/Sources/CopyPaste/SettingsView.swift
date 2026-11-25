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
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Geral") {
                Toggle("Abrir ao ligar o Mac", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { loginStatus = LoginItem.statusText }
                    }
                LabeledContent("Status do início automático") {
                    Text(loginStatus).foregroundStyle(.secondary)
                }
                Picker("Duplo clique / ↩ no painel", selection: $settings.doubleClickAction) {
                    ForEach(DoubleClickAction.allCases) { Text($0.label).tag($0) }
                }
                Picker("Posição do painel", selection: $settings.panelPosition) {
                    ForEach(PanelPosition.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Atalhos globais") {
                ForEach(HotKeyAction.allCases) { action in
                    LabeledContent {
                        HotKeyRecorder(action: action)
                    } label: {
                        Label(action.label, systemImage: action.symbol)
                        if hotkeys.failed.contains(action) {
                            Text("Esse atalho já é usado por outro app. Escolha outro.")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                Text("Clique no atalho e pressione a nova combinação. ⎋ cancela, ⌫ desativa.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Captura de tela") {
                LabeledContent("Pasta para salvar") {
                    HStack {
                        Text(settings.captureSaveDir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Alterar…") { chooseFolder(\.captureSaveDir) }
                    }
                }
                Picker("Formato", selection: $settings.captureFormat) {
                    ForEach(CaptureFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker("↩ ou duplo clique na captura", selection: $settings.captureEnterAction) {
                    ForEach(CaptureEnterAction.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Mostrar lupa com coordenadas e cor do pixel", isOn: $settings.captureMagnifier)
                Toggle("Destacar janelas ao passar o mouse (clique captura a janela)", isOn: $settings.captureSnapWindows)
            }

            Section("Gravação de tela") {
                LabeledContent("Pasta dos vídeos") {
                    HStack {
                        Text(settings.recordDir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Alterar…") { chooseFolder(\.recordDir) }
                    }
                }
                Toggle("Gravar o microfone", isOn: $settings.recordMic)
                Toggle("Gravar o áudio do Mac (sons dos apps)", isOn: $settings.recordSystemAudio)
                Toggle("Destacar os cliques do mouse", isOn: $settings.recordShowClicks)
                Picker("Quadros por segundo", selection: $settings.recordFPS) {
                    Text("24 (arquivo menor)").tag(24)
                    Text("30 (recomendado)").tag(30)
                    Text("60 (movimentos suaves)").tag(60)
                }
                if !ScreenRecorder.isSupported {
                    Text("A gravação de tela requer macOS 15 ou mais recente.").font(.caption).foregroundStyle(.orange)
                }
            }

            DictationSettingsSections()

            Section("Histórico") {
                Picker("Guardar itens copiados por", selection: $settings.retentionHours) {
                    ForEach(RetentionOption.all) { Text($0.label).tag($0.hours) }
                }
                Picker("Limite de itens", selection: $settings.maxItems) {
                    ForEach([50, 100, 200, 500, 1000, 2000, 5000], id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Salvar imagens copiadas", isOn: $settings.saveImages)
                Toggle("Pausar captura", isOn: $store.paused)
                LabeledContent("Itens salvos") {
                    HStack {
                        Text("\(store.items.count)").foregroundStyle(.secondary)
                        Button("Mostrar pasta") { NSWorkspace.shared.open(store.baseDir) }
                        Button("Limpar histórico…", role: .destructive) { confirmClear = true }
                    }
                }
                Text("Itens fixados nunca expiram nem são apagados ao limpar.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissões") {
                LabeledContent("Acessibilidade (para colar automaticamente)") {
                    if axTrusted {
                        Label("Permitido", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Permitir…") {
                            PasteService.ensureAccessibility(prompt: true)
                            PasteService.openAccessibilitySettings()
                        }
                    }
                }
                if !axTrusted {
                    Text("Sem essa permissão o item é apenas copiado (vira o primeiro do ⌘V), mas não é colado sozinho.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Gravação de Tela (para capturar e gravar)") {
                    if screenTrusted {
                        Label("Permitido", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Permitir…") {
                            CGRequestScreenCaptureAccess()
                            ScreenGrabber.openSettings()
                        }
                    }
                }
                if !screenTrusted {
                    Text("Depois de permitir, feche e abra o CopyPaste para valer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Atalhos na captura e no quadro") {
                shortcut("V P H L A R O D T N S B E K", "Ferramentas (selecionar, caneta, marca-texto, linha, seta…)")
                shortcut("1 … 9", "Trocar cor")
                shortcut("⇧ arrastando", "Linha a 45°, quadrado, círculo")
                shortcut("⌥ arrastando", "Duplicar o item selecionado")
                shortcut("Duplo clique", "Editar texto de um item")
                shortcut("⌘Z / ⇧⌘Z", "Desfazer / refazer")
                shortcut("⌘C · ⌘S · ⇧⌘S", "Copiar · salvar · salvar como")
                shortcut("⌘T", "Copiar o texto da captura (OCR)")
                shortcut("⌘ arrastando", "Mover a área da captura")
                shortcut("C (antes de selecionar)", "Copiar a cor do pixel")
                shortcut("G · I · ⌘V (no quadro)", "Trocar fundo · interagir com a tela · colar imagem/texto")
            }

            Section("Atalhos no painel") {
                shortcut("↑ ↓", "Navegar")
                shortcut("↩ ou duplo clique", "Colar onde está o cursor")
                shortcut("⌘↩ ou ⌘C", "Só copiar (vira o primeiro do ⌘V)")
                shortcut("⌘1 … ⌘9", "Colar o item da posição")
                shortcut("Espaço", "Pré-visualizar")
                shortcut("⇥ / ⇧⇥", "Trocar filtro")
                shortcut("⌘P", "Fixar / desafixar")
                shortcut("⌘⌫", "Excluir item")
                shortcut("⌘L", "Abrir biblioteca")
                shortcut("⎋", "Fechar")
            }

            Section("Apoie o projeto") {
                Text("O CopyPaste é gratuito e de código aberto. Se ele te ajuda, considere uma doação via Pix — qualquer valor ajuda a manter o projeto.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Chave Pix") {
                    HStack {
                        Text(Donation.pixKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Button("Copiar") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Donation.pixKey, forType: .string)
                            Toast.show("Chave Pix copiada — obrigado!", symbol: "heart.fill")
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
        .confirmationDialog("Apagar todo o histórico (exceto fixados)?", isPresented: $confirmClear) {
            Button("Apagar", role: .destructive) { store.clear(keepPinned: true) }
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
                    Text(recording ? "Pressione as teclas…" : (settings.hotKey(for: action)?.display ?? "Desativado"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(minWidth: 130)
                }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
                if recording {
                    Button("Cancelar") { stop() }.buttonStyle(.borderless)
                } else if settings.hotKey(for: action) != action.defaultHotKey {
                    Button {
                        settings.setHotKey(action.defaultHotKey, for: action)
                    } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .help("Voltar ao padrão (\(action.defaultHotKey?.display ?? ""))")
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
                message = "Use ⌘, ⌥ ou ⌃ (ou uma tecla F)"
                return nil
            }
            let mods = KeyNames.carbonModifiers(from: flags)
            let display = KeyNames.display(keyCode: Int(e.keyCode), carbonModifiers: mods,
                                           characters: e.charactersIgnoringModifiers)
            let hk = HotKey(code: Int(e.keyCode), mods: mods, display: display)
            if let other = settings.conflict(for: hk, except: action) {
                // Troca: o outro atalho fica desativado.
                settings.setHotKey(nil, for: other)
                message = "\(display) estava em “\(other.label)”, que ficou sem atalho."
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
    func chooseFolder(_ key: ReferenceWritableKeyPath<AppSettings, String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Escolher"
        panel.directoryURL = URL(fileURLWithPath: (settings[keyPath: key] as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            settings[keyPath: key] = url.path
        }
    }
}
