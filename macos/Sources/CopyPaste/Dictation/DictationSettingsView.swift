import SwiftUI
import AppKit

/// "Ditado por voz" and "Conexões de IA" sections of the settings window.
struct DictationSettingsSections: View {
    @ObservedObject var dict = DictationSettings.shared
    @ObservedObject private var hotkeys = AppSettings.shared
    @ObservedObject private var local = LocalAI.shared

    var body: some View {
        Section("Ditado por voz") {
            Text("Segure \(hotkeys.hotKey(for: .dictate)?.display ?? "o atalho do ditado") e fale; solte para o texto aparecer onde está o cursor, em qualquer app. Um toque rápido deixa ouvindo até o próximo toque. Com texto selecionado, \(hotkeys.hotKey(for: .voiceCommand)?.display ?? "o atalho do comando de voz") aplica o que você pedir (\"traduza para inglês\", \"deixe mais formal\").")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Transcrição", selection: $dict.engine) {
                ForEach(TranscriptionEngine.allCases) { e in
                    Text(e.label).tag(e)
                }
            }
            if let p = dict.engine.provider, !dict.available.contains(p) {
                Text(p == .local ? "Baixe a IA local abaixo para usar essa transcrição." : "Conecte o \(p.name) abaixo para usar essa transcrição.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Picker("Idioma", selection: $dict.language) {
                ForEach(DictationLanguage.all) { Text($0.label).tag($0.code) }
            }
            Picker("IA que ajusta o texto", selection: $dict.polishProvider) {
                Text("Nenhuma (texto como foi transcrito)").tag(AIProvider?.none)
                ForEach(AIProvider.allCases.filter { $0 == .local || dict.connected.contains($0) }) { p in
                    Text(p == .local && !local.isInstalled ? "\(p.name) — baixar abaixo" : p.name).tag(AIProvider?.some(p))
                }
            }
            if dict.effectivePolish == nil {
                Text("Baixe a IA local (grátis) ou conecte uma IA abaixo para tirar vícios de fala, pontuar e formatar o texto automaticamente.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Estilo", selection: $dict.style) {
                ForEach(DictationStyle.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Adaptar o tom ao app em uso (nome do app vai para a IA)", isOn: $dict.useAppContext)
            Toggle("Sons ao começar e terminar", isOn: $dict.sounds)
            VStack(alignment: .leading, spacing: 4) {
                Text("Vocabulário (nomes, siglas e termos, separados por vírgula)")
                TextField("", text: $dict.terms, prompt: Text("Ex.: CopyPaste, Kubernetes, Dra. Ana Souza"), axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
            }
        }

        Section {
            LocalAIRow(local: local)
        } header: {
            Text("IA local (padrão, grátis e offline)")
        } footer: {
            Text("O Gemma 4 E2B, do Google, roda no próprio Mac pelo llama.cpp: transcreve e ajusta o texto sem internet e sem chave. É usado quando nenhuma outra IA está ativa. Precisa de uns 4 GB de disco e de memória enquanto está em uso; libera a memória após 10 minutos parado.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            ForEach(AIProvider.cloud) { p in
                AIConnectionRow(provider: p, dict: dict)
            }
        } header: {
            Text("Conexões de IA")
        } footer: {
            Text("Use a sua própria chave de API: o CopyPaste não tem servidor e não cobra nada. A chave fica no Porta-chaves do Mac, e o áudio e o texto vão direto do seu Mac para a IA escolhida, cobrados na sua conta dela. Com a transcrição da Apple e sem IA, nada sai do Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AIConnectionRow: View {
    let provider: AIProvider
    @ObservedObject var dict: DictationSettings
    @State private var key = ""
    @State private var busy = false
    @State private var error: String?
    @State private var editing = false

    private var isConnected: Bool { dict.connected.contains(provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.name).fontWeight(.medium)
                if provider.canTranscribe {
                    Text("texto e voz").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
                if isConnected && !editing {
                    Label("Conectado", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                    Button("Remover", role: .destructive) { dict.disconnect(provider) }
                } else {
                    Link("Obter chave", destination: provider.keyURL).font(.callout)
                }
            }
            if !isConnected || editing {
                HStack {
                    SecureField("", text: $key, prompt: Text(provider.keyPlaceholder))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(connect)
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Conectar", action: connect).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if isConnected && !editing {
                let models = dict.chatModels[provider] ?? []
                if !models.isEmpty {
                    Picker("Modelo de texto", selection: Binding(
                        get: { dict.model(for: provider) ?? models.first ?? "" },
                        set: { dict.setModel($0, for: provider) })) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                }
                let stt = dict.sttModels[provider] ?? []
                if provider.canTranscribe, !stt.isEmpty {
                    Picker("Modelo de transcrição", selection: Binding(
                        get: { dict.sttModel(for: provider) ?? stt.first ?? "" },
                        set: { dict.setSttModel($0, for: provider) })) {
                        ForEach(stt, id: \.self) { Text($0).tag($0) }
                    }
                }
                Button("Atualizar lista de modelos") {
                    Task {
                        do { try await dict.refreshModels(provider); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private func connect() {
        let k = key
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await dict.connect(provider, key: k)
                key = ""
                editing = false
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct LocalAIRow: View {
    @ObservedObject var local: LocalAI

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Gemma 4 E2B").fontWeight(.medium)
                Text("texto e voz").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                Spacer()
                switch local.state {
                case .installed:
                    Label(local.running ? "Pronta · carregada" : "Pronta", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                    Button("Remover", role: .destructive) { local.remove() }
                case .downloading:
                    Button("Cancelar") { local.cancelInstall() }
                case .notInstalled, .failed:
                    Button(local.hasModelFiles ? "Instalar (≈ 17 MB)" : "Baixar (≈ \(Self.gb(LocalAI.totalBytes)))") { local.install() }
                        .buttonStyle(.borderedProminent)
                }
            }
            switch local.state {
            case .downloading(let p, let label):
                ProgressView(value: p) {
                    Text(label).font(.caption)
                } currentValueLabel: {
                    Text("\(Int(p * 100))% de \(Self.gb(LocalAI.totalBytes))").font(.caption).foregroundStyle(.secondary)
                }
            case .failed(let msg):
                Text(msg).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            case .installed:
                HStack {
                    Text("Usando \(Self.gb(local.diskUsage)) em ~/Library/Application Support/CopyPaste/IA local")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if local.testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Testar") { Task { await local.selfTest() } }.font(.caption)
                    }
                }
                if let r = local.testResult {
                    Text(r).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            case .notInstalled:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    static func gb(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
