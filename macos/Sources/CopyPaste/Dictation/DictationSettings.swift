import Foundation

/// Who turns speech into text.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case apple, openai, gemini
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple (no Mac, grátis e offline)"
        case .openai: return "OpenAI (mais preciso, usa sua chave)"
        case .gemini: return "Gemini (usa sua chave)"
        }
    }
    var provider: AIProvider? {
        switch self {
        case .apple: return nil
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
            "dict.polish": "",
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
        connected = Set(AIProvider.allCases.filter { AIKeys.get($0) != nil })
        for p in AIProvider.allCases {
            chatModels[p] = d.stringArray(forKey: "ai.models.\(p.rawValue)") ?? []
            sttModels[p] = d.stringArray(forKey: "ai.sttModels.\(p.rawValue)") ?? []
        }
    }

    func model(for p: AIProvider) -> String? { d.string(forKey: "ai.model.\(p.rawValue)") }
    func setModel(_ m: String, for p: AIProvider) { d.set(m, forKey: "ai.model.\(p.rawValue)"); objectWillChange.send() }
    func sttModel(for p: AIProvider) -> String? { d.string(forKey: "ai.sttModel.\(p.rawValue)") }
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
        if polishProvider == nil { polishProvider = p }
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
        if polishProvider == p { polishProvider = connected.sorted { $0.rawValue < $1.rawValue }.first }
        if engine.provider == p { engine = .apple }
    }

    var termList: [String] {
        terms.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
