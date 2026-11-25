import Foundation
import Security

/// AIs the user can connect with their own API key.
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude, openai, gemini, deepseek, grok

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        case .deepseek: return "DeepSeek"
        case .grok: return "Grok (xAI)"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "GPT"
        case .gemini: return "Gemini"
        case .deepseek: return "DeepSeek"
        case .grok: return "Grok"
        }
    }

    /// Where the user creates an API key.
    var keyURL: URL {
        switch self {
        case .claude: return URL(string: "https://platform.claude.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")!
        case .grok: return URL(string: "https://console.x.ai")!
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .openai: return "sk-…"
        case .gemini: return "AIza…"
        case .deepseek: return "sk-…"
        case .grok: return "xai-…"
        }
    }

    /// Can turn audio into text (Claude, DeepSeek and Grok only handle text here).
    var canTranscribe: Bool { self == .openai || self == .gemini }

    /// Base URL of the OpenAI-compatible chat API.
    fileprivate var chatBase: String? {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .deepseek: return "https://api.deepseek.com"
        case .grok: return "https://api.x.ai/v1"
        default: return nil
        }
    }
}

// MARK: - Keys (Keychain)

enum AIKeys {
    private static let service = "local.copypaste.ai"

    static func get(_ p: AIProvider) -> String? {
        var q = base(p)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    static func set(_ key: String?, for p: AIProvider) {
        SecItemDelete(base(p) as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var q = base(p)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        q[kSecAttrLabel as String] = "CopyPaste — chave \(p.shortName)"
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func base(_ p: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: p.rawValue]
    }
}

// MARK: - Client

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Minimal HTTP client for the five providers. Each user brings their own key.
enum AIClient {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 120
        return URLSession(configuration: c)
    }()

    private static let anthropicVersion = "2026-10-21"
    /// Claude models that accept the server-side fallback on a policy decline.
    private static let claudeFallbackModels: Set<String> = [
        "claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    // MARK: Models

    struct ModelList {
        var chat: [String]
        var transcription: [String]
    }

    /// Lists the models the key can use; also validates the key.
    static func listModels(_ p: AIProvider, key: String) async throws -> ModelList {
        switch p {
        case .claude:
            var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
            r.setValue(key, forHTTPHeaderField: "x-api-key")
            r.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            let json = try await send(r, p)
            let ids = (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            return ModelList(chat: ids, transcription: [])
        case .gemini:
            var r = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!)
            r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let json = try await send(r, p)
            let ids = (json["models"] as? [[String: Any]] ?? []).compactMap { m -> String? in
                guard let name = m["name"] as? String,
                      (m["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") else { return nil }
                let id = name.replacingOccurrences(of: "models/", with: "")
                let skip = ["embedding", "image", "tts", "live", "aqa", "veo", "imagen", "learnlm"]
                return id.hasPrefix("gemini") && !skip.contains(where: id.contains) ? id : nil
            }
            return ModelList(chat: ids, transcription: ids)
        case .openai, .deepseek, .grok:
            var r = URLRequest(url: URL(string: p.chatBase! + "/models")!)
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let json = try await send(r, p)
            let ids = (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            if p == .openai {
                let notChat = ["audio", "realtime", "tts", "transcribe", "whisper", "image", "embedding", "moderation",
                               "dall-e", "davinci", "babbage", "search", "computer-use", "codex", "sora", "instruct"]
                let chat = ids.filter { id in
                    (id.hasPrefix("gpt-") || id.hasPrefix("o") || id.hasPrefix("chatgpt")) && !notChat.contains(where: id.contains)
                }
                let stt = ids.filter { $0.contains("transcribe") || $0.hasPrefix("whisper") }
                return ModelList(chat: chat, transcription: stt)
            }
            let chat = ids.filter { !$0.contains("image") && !$0.contains("vision") && !$0.contains("embed") }
            return ModelList(chat: chat, transcription: [])
        }
    }

    /// Picks a sensible default: fast and capable enough for cleaning up dictated text.
    static func preferredChatModel(_ p: AIProvider, from ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        let sorted = ids.sorted(by: >)
        switch p {
        case .claude:
            return ids.first { $0 == "claude-opus-5-5" } ?? sorted.first { $0.hasPrefix("claude-opus") } ?? sorted.first
        case .openai:
            let undated = sorted.filter { $0.hasPrefix("gpt-") && $0.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) == nil }
            return undated.first { $0.hasSuffix("-mini") } ?? undated.first ?? sorted.first
        case .gemini:
            let stable = sorted.filter { !$0.contains("preview") && !$0.contains("exp") && !$0.contains("lite") }
            return stable.first { $0.contains("flash") } ?? sorted.first { $0.contains("flash") } ?? sorted.first
        case .deepseek:
            return ids.first { $0 == "deepseek-chat" } ?? sorted.first
        case .grok:
            let grok = sorted.filter { $0.hasPrefix("grok") }
            return grok.first { $0.contains("fast") } ?? grok.first { $0.contains("mini") } ?? grok.first ?? sorted.first
        }
    }

    static func preferredTranscriptionModel(_ p: AIProvider, from ids: [String]) -> String? {
        switch p {
        case .openai:
            let sorted = ids.sorted(by: >)
            return sorted.first { $0.contains("mini-transcribe") } ?? sorted.first { $0.contains("transcribe") }
                ?? ids.first { $0 == "whisper-1" } ?? sorted.first
        case .gemini:
            return preferredChatModel(.gemini, from: ids)
        default:
            return nil
        }
    }

    // MARK: Text

    /// One request, one answer: the system prompt plus the user's text.
    static func complete(_ p: AIProvider, key: String, model: String, system: String, user: String) async throws -> String {
        switch p {
        case .claude:
            var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue(key, forHTTPHeaderField: "x-api-key")
            r.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            var body: [String: Any] = [
                "model": model,
                "max_tokens": 16000,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
            // Newer models take an effort level; low keeps dictation fast.
            let effortModels = ["opus-5", "fable", "mythos", "sonnet-5", "haiku-5", "opus-4-8", "opus-4-7", "opus-4-6", "sonnet-4-6"]
            if effortModels.contains(where: model.contains) { body["output_config"] = ["effort": "low"] }
            if claudeFallbackModels.contains(model) {
                r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                body["fallbacks"] = "default"
            }
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json = try await send(r, p)
            if json["stop_reason"] as? String == "refusal" {
                throw AIError(message: "O Claude recusou este pedido.")
            }
            let text = (json["content"] as? [[String: Any]] ?? [])
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            return try nonEmpty(text, p)
        case .gemini:
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let body: [String: Any] = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": user]]]],
            ]
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            return try nonEmpty(geminiText(try await send(r, p)), p)
        case .openai, .deepseek, .grok:
            var r = URLRequest(url: URL(string: p.chatBase! + "/chat/completions")!)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": model,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            ]
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json = try await send(r, p)
            let msg = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
            return try nonEmpty(msg?["content"] as? String ?? "", p)
        }
    }

    // MARK: Audio

    /// Turns a WAV recording into text (OpenAI or Gemini).
    static func transcribe(_ p: AIProvider, key: String, model: String, wav: URL, language: String?, hint: String) async throws -> String {
        let audio = try Data(contentsOf: wav)
        switch p {
        case .openai:
            var r = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
            r.httpMethod = "POST"
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let boundary = "cp-\(UUID().uuidString)"
            r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
            var body = Data()
            func field(_ name: String, _ value: String) {
                body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
            }
            field("model", model)
            field("response_format", "json")
            if let language { field("language", language) }
            if !hint.isEmpty { field("prompt", hint) }
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ditado.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audio)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            r.httpBody = body
            let json = try await send(r, p)
            return (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .gemini:
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var prompt = "Transcreva este áudio exatamente como foi falado, no idioma falado, com pontuação. Responda somente com a transcrição, sem comentários. Se não houver fala, responda com uma string vazia."
            if !hint.isEmpty { prompt += " Palavras que podem aparecer: \(hint)." }
            let body: [String: Any] = [
                "contents": [["role": "user", "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "audio/wav", "data": audio.base64EncodedString()]],
                ]]],
            ]
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            return geminiText(try await send(r, p)).trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            throw AIError(message: "\(p.shortName) não transcreve áudio. Use a transcrição da Apple, do OpenAI ou do Gemini.")
        }
    }

    // MARK: Helpers

    private static func geminiText(_ json: [String: Any]) -> String {
        let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private static func nonEmpty(_ s: String, _ p: AIProvider) throws -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw AIError(message: "\(p.shortName) devolveu uma resposta vazia.") }
        return t
    }

    private static func send(_ r: URLRequest, _ p: AIProvider) async throws -> [String: Any] {
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await session.data(for: r)
        } catch let e as URLError where e.code == .timedOut {
            throw AIError(message: "\(p.shortName) demorou demais para responder.")
        } catch {
            throw AIError(message: "Sem conexão com \(p.shortName): \(error.localizedDescription)")
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(code) else {
            throw AIError(message: friendlyError(code: code, json: json, p))
        }
        return json
    }

    private static func friendlyError(code: Int, json: [String: Any], _ p: AIProvider) -> String {
        var detail = ""
        if let e = json["error"] as? [String: Any] { detail = e["message"] as? String ?? "" }
        else if let e = json["error"] as? String { detail = e }
        else if let m = json["message"] as? String { detail = m }
        switch code {
        case 401, 403: return "Chave do \(p.shortName) inválida ou sem permissão."
        case 402: return "Sem créditos na conta do \(p.shortName)."
        case 404: return "Modelo não encontrado no \(p.shortName). Escolha outro nas configurações."
        case 429: return "Limite de uso do \(p.shortName) atingido. Tente de novo em instantes ou confira seus créditos."
        default:
            let d = detail.isEmpty ? "" : ": \(detail.prefix(160))"
            return "\(p.shortName) respondeu com erro \(code)\(d)"
        }
    }
}
