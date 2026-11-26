import Foundation

/// Who turns speech into text.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case apple, local, openai, gemini
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple (no Mac, grátis e offline)"
        case .local: return "IA local Gemma 4 (no Mac, grátis e offline)"
        case .openai: return "OpenAI (mais preciso, usa sua chave)"
        case .gemini: return "Gemini (usa sua chave)"
        }
    }
    var provider: AIProvider? {
        switch self {
        case .apple: return nil
        case .local: return .local
        case .openai: return .openai
        case .gemini: return .gemini
        }
    }
}

/// How much the AI reworks what was said.
enum DictationStyle: String, CaseIterable, Identifiable {
    case natural, formal, casual, literal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .natural: return "Natural: limpo, com o seu jeito de falar"
        case .formal: return "Formal: e-mails e documentos"
        case .casual: return "Descontraído: chats e mensagens"
        case .literal: return "Literal: só a transcrição, sem IA"
        }
    }
    var instruction: String {
        switch self {
        case .natural: return "Mantenha o jeito e o vocabulário da pessoa; só deixe o texto limpo e bem pontuado."
        case .formal: return "Use um tom profissional e claro, adequado a e-mails e documentos, sem mudar o sentido."
        case .casual: return "Use um tom leve de conversa, adequado a chats; pode manter expressões informais."
        case .literal: return ""
        }
    }
}

struct DictationLanguage: Identifiable, Hashable {
    let code: String
    let label: String
    var id: String { code }

    static let all: [DictationLanguage] = [
        .init(code: "pt-BR", label: "Português (Brasil)"),
        .init(code: "pt-PT", label: "Português (Portugal)"),
        .init(code: "en-US", label: "Inglês (EUA)"),
        .init(code: "es-ES", label: "Espanhol"),
        .init(code: "fr-FR", label: "Francês"),
        .init(code: "it-IT", label: "Italiano"),
        .init(code: "de-DE", label: "Alemão"),
        .init(code: "auto", label: "Detectar automaticamente (OpenAI/Gemini)"),
    ]
}

/// Preferences of the voice dictation and of the connected AIs.
final class DictationSettings: ObservableObject {
    static let shared = DictationSettings()
    private let d = UserDefaults.standard

    @Published var engine: TranscriptionEngine { didSet { d.set(engine.rawValue, forKey: "dict.engine") } }
    @Published var language: String { didSet { d.set(language, forKey: "dict.language") } }
    @Published var style: DictationStyle { didSet { d.set(style.rawValue, forKey: "dict.style") } }
    /// AI that cleans up the text (nil = no cleanup).
    @Published var polishProvider: AIProvider? { didSet { d.set(polishProvider?.rawValue ?? "", forKey: "dict.polish") } }
    @Published var terms: String { didSet { d.set(terms, forKey: "dict.terms") } }
    @Published var sounds: Bool { didSet { d.set(sounds, forKey: "dict.sounds") } }
    @Published var useAppContext: Bool { didSet { d.set(useAppContext, forKey: "dict.appContext") } }

    /// Providers with a saved key; bumped when a key changes so views refresh.
    @Published private(set) var connected: Set<AIProvider> = []
    @Published private(set) var chatModels: [AIProvider: [String]] = [:]
    @Published private(set) var sttModels: [AIProvider: [String]] = [:]

    private init() {
        d.register(defaults: [
            "dict.engine": TranscriptionEngine.apple.rawValue,
            "dict.language": "pt-BR",
            "dict.style": DictationStyle.natural.rawValue,
            "dict.polish": AIProvider.local.rawValue,
            "dict.terms": "",
            "dict.sounds": true,
            "dict.appContext": true,
        ])
        engine = TranscriptionEngine(rawValue: d.string(forKey: "dict.engine") ?? "") ?? .apple
        language = d.string(forKey: "dict.language") ?? "pt-BR"
        style = DictationStyle(rawValue: d.string(forKey: "dict.style") ?? "") ?? .natural
        polishProvider = AIProvider(rawValue: d.string(forKey: "dict.polish") ?? "")
        terms = d.string(forKey: "dict.terms") ?? ""
        sounds = d.bool(forKey: "dict.sounds")
        useAppContext = d.bool(forKey: "dict.appContext")
        connected = Set(AIProvider.cloud.filter { AIKeys.get($0) != nil })
        for p in AIProvider.cloud {
            // Older versions kept transcription-only models in the text list (Gemini "…-transcribe").
            chatModels[p] = (d.stringArray(forKey: "ai.models.\(p.rawValue)") ?? []).filter { AIClient.isTextModel(p, $0) }
            sttModels[p] = d.stringArray(forKey: "ai.sttModels.\(p.rawValue)") ?? []
            if let m = model(for: p), !AIClient.isTextModel(p, m) {
                d.removeObject(forKey: "ai.model.\(p.rawValue)")
                if let better = AIClient.preferredChatModel(p, from: chatModels[p] ?? []) { d.set(better, forKey: "ai.model.\(p.rawValue)") }
            }
        }
        // 1.3.0 picked gemini-flash-latest automatically; Flash-Lite answers much faster for dictation.
        if !d.bool(forKey: "ai.migrated.geminiLite"), model(for: .gemini) == "gemini-flash-latest",
           chatModels[.gemini]?.contains("gemini-flash-lite-latest") == true {
            d.set("gemini-flash-lite-latest", forKey: "ai.model.gemini")
        }
        d.set(true, forKey: "ai.migrated.geminiLite")
        chatModels[.local] = [LocalAI.modelName]
        sttModels[.local] = [LocalAI.modelName]
    }

    /// Cloud AIs with a key, plus the local AI once downloaded.
    var available: [AIProvider] {
        AIProvider.allCases.filter { $0 == .local ? LocalAI.installedOnDisk : connected.contains($0) }
    }

    /// The AI that cleans up the text: the one chosen, or the local AI when nothing else is active.
    var effectivePolish: AIProvider? {
        if let p = polishProvider, p == .local ? LocalAI.installedOnDisk : connected.contains(p) { return p }
        if polishProvider == .local || polishProvider == nil, LocalAI.installedOnDisk { return .local }
        return nil
    }

    func model(for p: AIProvider) -> String? {
        p == .local ? LocalAI.modelName : d.string(forKey: "ai.model.\(p.rawValue)")
    }
    func setModel(_ m: String, for p: AIProvider) { d.set(m, forKey: "ai.model.\(p.rawValue)"); objectWillChange.send() }
    func sttModel(for p: AIProvider) -> String? {
        p == .local ? LocalAI.modelName : d.string(forKey: "ai.sttModel.\(p.rawValue)")
    }
    func setSttModel(_ m: String, for p: AIProvider) { d.set(m, forKey: "ai.sttModel.\(p.rawValue)"); objectWillChange.send() }

    /// Validates the key by listing the provider's models, then stores it in the Keychain.
    @MainActor
    func connect(_ p: AIProvider, key raw: String) async throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError(message: "Cole a chave da API.") }
        let list = try await AIClient.listModels(p, key: key)
        guard !list.chat.isEmpty else { throw AIError(message: "A chave funciona, mas nenhum modelo de texto está disponível nela.") }
        AIKeys.set(key, for: p)
        storeModels(list, for: p)
        connected.insert(p)
        // The local AI is the default only while no AI of the user's own is connected.
        if polishProvider == nil || polishProvider == .local { polishProvider = p }
    }

    /// Re-reads the model list with the saved key (models change over time).
    @MainActor
    func refreshModels(_ p: AIProvider) async throws {
        guard let key = AIKeys.get(p) else { return }
        storeModels(try await AIClient.listModels(p, key: key), for: p)
    }

    private func storeModels(_ list: AIClient.ModelList, for p: AIProvider) {
        let chat = list.chat.sorted()
        let stt = list.transcription.sorted()
        chatModels[p] = chat
        sttModels[p] = stt
        d.set(chat, forKey: "ai.models.\(p.rawValue)")
        d.set(stt, forKey: "ai.sttModels.\(p.rawValue)")
        if model(for: p).map({ !chat.contains($0) }) ?? true, let m = AIClient.preferredChatModel(p, from: chat) {
            setModel(m, for: p)
        }
        if p.canTranscribe, sttModel(for: p).map({ !stt.contains($0) }) ?? true,
           let m = AIClient.preferredTranscriptionModel(p, from: stt) {
            setSttModel(m, for: p)
        }
    }

    func disconnect(_ p: AIProvider) {
        AIKeys.set(nil, for: p)
        connected.remove(p)
        if polishProvider == p { polishProvider = connected.sorted { $0.rawValue < $1.rawValue }.first ?? .local }
        if engine.provider == p { engine = .apple }
    }

    var termList: [String] {
        terms.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
