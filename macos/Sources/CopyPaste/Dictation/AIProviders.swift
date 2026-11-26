import Foundation
import Security

/// AIs the user can connect with their own API key, plus the built-in local AI.
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude, openai, gemini, deepseek, grok, local

    var id: String { rawValue }

    /// The ones that need an API key.
    static let cloud: [AIProvider] = [.claude, .openai, .gemini, .deepseek, .grok]

    var name: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        case .deepseek: return "DeepSeek"
        case .grok: return "Grok (xAI)"
        case .local: return "IA local (Gemma 4, no Mac)"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "GPT"
        case .gemini: return "Gemini"
        case .deepseek: return "DeepSeek"
        case .grok: return "Grok"
        case .local: return "IA local"
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
        case .local: return URL(string: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF")!
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .openai: return "sk-…"
        case .gemini: return "AIza…"
        case .deepseek: return "sk-…"
        case .grok: return "xai-…"
        case .local: return ""
        }
    }

    /// Can turn audio into text (Claude, DeepSeek and Grok only handle text here).
    var canTranscribe: Bool { self == .openai || self == .gemini || self == .local }

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
        // The local AI needs no key: it is "connected" once downloaded.
        if p == .local { return LocalAI.installedOnDisk ? "local" : nil }
        var q = base(p)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    static func set(_ key: String?, for p: AIProvider) {
        guard p != .local else { return }
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
        case .local:
            return ModelList(chat: [LocalAI.modelName], transcription: [LocalAI.modelName])
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
                let skip = ["embedding", "image", "tts", "live", "aqa", "veo", "imagen", "learnlm", "robotics", "computer-use", "native-audio"]
                return id.hasPrefix("gemini") && !skip.contains(where: id.contains) ? id : nil
            }
            // Transcription-only models ("…-transcribe") reject system instructions: they never clean up text.
            let chat = ids.filter { isTextModel(.gemini, $0) }
            return ModelList(chat: chat, transcription: ids)
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

    /// Whether a model id is meant for text (not transcription, speech, images…).
    static func isTextModel(_ p: AIProvider, _ id: String) -> Bool {
        let notText = ["transcribe", "tts", "audio", "realtime", "live", "image", "embedding", "whisper", "moderation",
                       "robotics", "computer-use", "veo", "imagen", "aqa", "banana"]
        return !notText.contains(where: id.contains)
    }

    /// Version number in a model id ("gemini-3.5-flash" → 3.5), to pick the newest.
    private static func version(_ id: String) -> Double {
        guard let r = id.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return 0 }
        return Double(id[r]) ?? 0
    }

    /// Picks a sensible default: fast and capable enough for cleaning up dictated text.
    static func preferredChatModel(_ p: AIProvider, from all: [String]) -> String? {
        let ids = all.filter { isTextModel(p, $0) }
        guard !ids.isEmpty else { return nil }
        let sorted = ids.sorted(by: >)
        switch p {
        case .local:
            return ids.first
        case .claude:
            return ids.first { $0 == "claude-opus-5-5" } ?? sorted.first { $0.hasPrefix("claude-opus") } ?? sorted.first
        case .openai:
            let undated = sorted.filter { $0.hasPrefix("gpt-") && $0.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) == nil }
            return undated.first { $0.hasSuffix("-mini") } ?? undated.first ?? sorted.first
        case .gemini:
            // Flash-Lite is the fastest and is plenty for cleaning up dictated text; the "latest" aliases follow new releases.
            if let alias = ids.first(where: { $0 == "gemini-flash-lite-latest" }) { return alias }
            if let alias = ids.first(where: { $0 == "gemini-flash-latest" }) { return alias }
            let byVersion = ids.sorted { version($0) > version($1) }
            let stable = byVersion.filter { !$0.contains("preview") && !$0.contains("exp") && !$0.contains("lite") && !$0.contains("latest") }
            return stable.first { $0.contains("flash") } ?? byVersion.first { $0.contains("flash") }
                ?? stable.first ?? byVersion.first
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
            let sorted = ids.sorted { version($0) > version($1) }
            return sorted.first { $0.contains("transcribe") } ?? preferredChatModel(.gemini, from: ids)
        case .local:
            return LocalAI.modelName
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
            func request(separateSystem: Bool, thinking: Bool = true) throws -> URLRequest {
                var r = URLRequest(url: url)
                r.httpMethod = "POST"
                r.timeoutInterval = 30
                r.setValue("application/json", forHTTPHeaderField: "content-type")
                r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                var config: [String: Any] = ["temperature": 0.2]
                // Cleaning up dictation needs no "thinking": it only makes the answer slow.
                if thinking { config["thinkingConfig"] = geminiThinkingOff(model) }
                var body: [String: Any] = ["generationConfig": config]
                if separateSystem {
                    body["systemInstruction"] = ["parts": [["text": system]]]
                    body["contents"] = [["role": "user", "parts": [["text": user]]]]
                } else {
                    body["contents"] = [["role": "user", "parts": [["text": system + "\n\n" + user]]]]
                }
                r.httpBody = try JSONSerialization.data(withJSONObject: body)
                return r
            }
            var separate = true, thinking = true
            for _ in 0..<3 {
                do {
                    return try nonEmpty(geminiText(try await send(try request(separateSystem: separate, thinking: thinking), p)), p)
                } catch let e as AIError where thinking && e.message.localizedCaseInsensitiveContains("thinking") {
                    thinking = false // the model does not take this thinking setting
                } catch let e as AIError where separate && e.message.localizedCaseInsensitiveContains("instruction") {
                    separate = false // some models (Gemma, transcription) take no system instruction: send it inline
                }
            }
            return try nonEmpty(geminiText(try await send(try request(separateSystem: false, thinking: false), p)), p)
        case .local:
            let base = try await LocalAI.shared.ensureRunning()
            var r = URLRequest(url: base.appendingPathComponent("chat/completions"))
            r.httpMethod = "POST"
            r.timeoutInterval = 120
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            let body: [String: Any] = [
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
                "temperature": 0.2,
                "chat_template_kwargs": ["enable_thinking": false],
            ]
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json = try await send(r, p)
            await LocalAI.shared.touch()
            let msg = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
            return try nonEmpty(msg?["content"] as? String ?? "", p)
        case .openai, .deepseek, .grok:
            var r = URLRequest(url: URL(string: p.chatBase! + "/chat/completions")!)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            r.timeoutInterval = 30
            var body: [String: Any] = [
                "model": model,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            ]
            // Reasoning models: as little reasoning as possible, so dictation stays fast.
            if p == .openai, model.hasPrefix("gpt-5") || model.hasPrefix("o") {
                body["reasoning_effort"] = model.hasPrefix("gpt-5") ? "minimal" : "low"
            }
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json: [String: Any]
            do {
                json = try await send(r, p)
            } catch let e as AIError where body["reasoning_effort"] != nil && e.message.localizedCaseInsensitiveContains("reasoning") {
                body["reasoning_effort"] = nil
                r.httpBody = try JSONSerialization.data(withJSONObject: body)
                json = try await send(r, p)
            }
            let msg = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
            return try nonEmpty(msg?["content"] as? String ?? "", p)
        }
    }

    // MARK: Audio

    /// Turns a WAV recording into text (OpenAI or Gemini).
    static func transcribe(_ p: AIProvider, key: String, model: String, wav: URL, language: String?, hint: String) async throws -> String {
        let audio = try Data(contentsOf: wav)
        switch p {
        case .openai, .local:
            let url: URL
            if p == .local {
                url = try await LocalAI.shared.ensureRunning().appendingPathComponent("audio/transcriptions")
            } else {
                url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
            }
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.timeoutInterval = 180
            if p == .openai { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            let boundary = "cp-\(UUID().uuidString)"
            r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
            var body = Data()
            func field(_ name: String, _ value: String) {
                body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
            }
            field("model", model)
            field("response_format", "json")
            if let language { field("language", language) }
            if p == .local {
                // In llama.cpp the prompt replaces the instruction, so it must still ask for a transcription.
                if !hint.isEmpty { field("prompt", "Transcreva o áudio exatamente como foi falado. Grafias corretas de termos que podem aparecer: \(hint).") }
            } else if !hint.isEmpty {
                field("prompt", hint)
            }
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ditado.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audio)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            r.httpBody = body
            let json = try await send(r, p)
            if p == .local { await LocalAI.shared.touch() }
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

    /// The lowest thinking setting each Gemini generation accepts.
    private static func geminiThinkingOff(_ model: String) -> [String: Any] {
        if model.contains("2.5") || model.contains("2.0") {
            return ["thinkingBudget": model.contains("pro") ? 128 : 0]
        }
        return ["thinkingLevel": "minimal"]
    }

    private static func geminiText(_ json: [String: Any]) -> String {
        let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private static func nonEmpty(_ s: String, _ p: AIProvider) throws -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw AIError(message: "\(p.shortName) devolveu uma resposta vazia.") }
        return t
    }

    private static func send(_ r: URLRequest, _ p: AIProvider, retry: Bool = true) async throws -> [String: Any] {
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
            // Momentary overload or a per-minute limit: one quick retry before giving up.
            if retry, code == 429 || code == 503 || code == 529 {
                let wait = Double((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after") ?? "") ?? 2
                try await Task.sleep(nanoseconds: UInt64(min(max(wait, 1), 5) * 1_000_000_000))
                return try await send(r, p, retry: false)
            }
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
        case 429:
            let quota = detail.localizedCaseInsensitiveContains("quota") || detail.localizedCaseInsensitiveContains("billing")
                || detail.localizedCaseInsensitiveContains("credit")
            return quota
                ? "Cota do \(p.shortName) esgotada (\(detail.prefix(120))). Confira o plano ou os créditos da sua conta."
                : "Limite por minuto do \(p.shortName) atingido. Espere alguns segundos e tente de novo."
        default:
            let d = detail.isEmpty ? "" : ": \(detail.prefix(160))"
            return "\(p.shortName) respondeu com erro \(code)\(d)"
        }
    }
}
