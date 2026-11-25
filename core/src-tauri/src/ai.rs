//! Connections to the user's own AI (Claude, GPT, Gemini, DeepSeek, Grok): model lists, text and transcription.
//! Plain HTTPS calls with the user's key; CopyPaste has no server in between.

use base64::Engine;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::Path;
use std::time::Duration;

pub const PROVIDERS: [&str; 5] = ["claude", "openai", "gemini", "deepseek", "grok"];

pub fn name(p: &str) -> &'static str {
    match p {
        "claude" => "Claude",
        "openai" => "GPT",
        "gemini" => "Gemini",
        "deepseek" => "DeepSeek",
        "grok" => "Grok",
        _ => "IA",
    }
}

fn chat_base(p: &str) -> Option<&'static str> {
    match p {
        "openai" => Some("https://api.openai.com/v1"),
        "deepseek" => Some("https://api.deepseek.com"),
        "grok" => Some("https://api.x.ai/v1"),
        _ => None,
    }
}

const ANTHROPIC_VERSION: &str = "2026-10-21";
/// Claude models that accept the server-side fallback beta.
const CLAUDE_FALLBACK: [&str; 5] = ["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"];

// ───────────────────────────── Keys ─────────────────────────────

/// Keys live in `ai-keys.json` in the config folder, readable only by the user (0600 on Linux).
pub fn load_keys(path: &Path) -> BTreeMap<String, String> {
    std::fs::read(path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

pub fn save_keys(path: &Path, keys: &BTreeMap<String, String>) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let Ok(b) = serde_json::to_vec(keys) else { return };
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).write(true).truncate(true).mode(0o600).open(path) {
            let _ = f.write_all(&b);
        }
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    }
    #[cfg(not(unix))]
    {
        let _ = std::fs::write(path, b);
    }
}

// ───────────────────────────── HTTP ─────────────────────────────

fn agent() -> ureq::Agent {
    let b = ureq::AgentBuilder::new().timeout_connect(Duration::from_secs(15)).timeout(Duration::from_secs(120));
    #[cfg(not(target_os = "linux"))]
    let b = match native_tls::TlsConnector::new() {
        Ok(c) => b.tls_connector(std::sync::Arc::new(c)),
        Err(_) => b,
    };
    b.build()
}

fn friendly(p: &str, status: u16, body: &str) -> String {
    let detail = serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|v| {
            v.pointer("/error/message")
                .or_else(|| v.pointer("/error"))
                .or_else(|| v.pointer("/message"))
                .and_then(|m| m.as_str().map(String::from))
        })
        .unwrap_or_default();
    let n = name(p);
    let base = match status {
        401 | 403 => format!("{n}: chave inválida ou sem permissão."),
        402 => format!("{n}: sem saldo ou créditos na conta."),
        404 => format!("{n}: modelo não encontrado. Atualize a lista de modelos."),
        429 => format!("{n}: limite de uso atingido ou sem créditos. Tente de novo em instantes."),
        500..=599 => format!("{n} está instável agora. Tente de novo em instantes."),
        _ => format!("{n} recusou o pedido (erro {status})."),
    };
    if detail.is_empty() || matches!(status, 401 | 403) {
        base
    } else {
        format!("{base} {}", detail.chars().take(160).collect::<String>())
    }
}

fn read(p: &str, r: Result<ureq::Response, ureq::Error>) -> Result<Value, String> {
    match r {
        Ok(resp) => resp.into_json::<Value>().map_err(|e| format!("{}: resposta inválida ({e})", name(p))),
        Err(ureq::Error::Status(code, resp)) => Err(friendly(p, code, &resp.into_string().unwrap_or_default())),
        Err(e) => Err(format!("Sem conexão com {}: {e}", name(p))),
    }
}

// ───────────────────────────── Models ─────────────────────────────

pub struct ModelList {
    pub chat: Vec<String>,
    pub transcription: Vec<String>,
}

pub fn list_models(p: &str, key: &str) -> Result<ModelList, String> {
    let a = agent();
    let (chat, stt): (Vec<String>, Vec<String>) = match p {
        "claude" => {
            let v = read(
                p,
                a.get("https://api.anthropic.com/v1/models?limit=100")
                    .set("x-api-key", key)
                    .set("anthropic-version", ANTHROPIC_VERSION)
                    .call(),
            )?;
            let ids = ids(&v, "/data", "id");
            (ids, vec![])
        }
        "gemini" => {
            let v = read(
                p,
                a.get("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200").set("x-goog-api-key", key).call(),
            )?;
            let mut chat = vec![];
            for m in v.get("models").and_then(|m| m.as_array()).into_iter().flatten() {
                let gen = m
                    .get("supportedGenerationMethods")
                    .and_then(|g| g.as_array())
                    .map(|g| g.iter().any(|x| x == "generateContent"))
                    .unwrap_or(false);
                let id = m.get("name").and_then(|n| n.as_str()).unwrap_or("").trim_start_matches("models/").to_string();
                let skip = ["embedding", "imagen", "veo", "tts", "image", "aqa", "learnlm"].iter().any(|w| id.contains(w));
                if gen && id.starts_with("gemini") && !skip {
                    chat.push(id);
                }
            }
            let stt = chat.clone();
            (chat, stt)
        }
        _ => {
            let base = chat_base(p).ok_or("provedor desconhecido")?;
            let v = read(p, a.get(&format!("{base}/models")).set("Authorization", &format!("Bearer {key}")).call())?;
            let all = ids(&v, "/data", "id");
            let stt: Vec<String> = all.iter().filter(|m| m.contains("transcribe") || m.starts_with("whisper")).cloned().collect();
            let skip = ["embedding", "tts", "whisper", "transcribe", "dall-e", "image", "moderation", "audio", "realtime", "search", "babbage", "davinci", "sora", "codex"];
            let chat = all.into_iter().filter(|m| !skip.iter().any(|w| m.contains(w))).collect();
            (chat, if p == "openai" { stt } else { vec![] })
        }
    };
    let mut chat = chat;
    let mut stt = stt;
    chat.sort();
    stt.sort();
    Ok(ModelList { chat, transcription: stt })
}

fn ids(v: &Value, ptr: &str, field: &str) -> Vec<String> {
    v.pointer(ptr)
        .and_then(|d| d.as_array())
        .map(|a| a.iter().filter_map(|m| m.get(field).and_then(|x| x.as_str()).map(String::from)).collect())
        .unwrap_or_default()
}

fn first_match(ids: &[String], prefs: &[&str]) -> Option<String> {
    for p in prefs {
        if let Some(m) = ids.iter().find(|m| m.as_str() == *p) {
            return Some(m.clone());
        }
    }
    for p in prefs {
        if let Some(m) = ids.iter().find(|m| m.starts_with(p)) {
            return Some(m.clone());
        }
    }
    None
}

/// A fast, capable default for cleaning up dictated text.
pub fn preferred_chat(p: &str, ids: &[String]) -> Option<String> {
    let prefs: &[&str] = match p {
        "claude" => &["claude-opus-5-5", "claude-sonnet-5-5", "claude-opus-5", "claude-haiku-5-5", "claude-sonnet"],
        "openai" => &["gpt-5-mini", "gpt-5.1-mini", "gpt-5", "gpt-4.1-mini", "gpt-4o-mini", "gpt-4o"],
        "gemini" => &["gemini-2.5-flash", "gemini-flash-latest", "gemini-2.0-flash", "gemini-3", "gemini"],
        "deepseek" => &["deepseek-chat", "deepseek"],
        "grok" => &["grok-4-fast", "grok-4", "grok-3-mini", "grok-3", "grok"],
        _ => &[],
    };
    first_match(ids, prefs).or_else(|| ids.first().cloned())
}

pub fn preferred_stt(p: &str, ids: &[String]) -> Option<String> {
    let prefs: &[&str] = match p {
        "openai" => &["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"],
        "gemini" => &["gemini-2.5-flash", "gemini-flash-latest", "gemini-2.0-flash", "gemini"],
        _ => &[],
    };
    first_match(ids, prefs).or_else(|| ids.first().cloned())
}

// ───────────────────────────── Text ─────────────────────────────

pub fn complete(p: &str, key: &str, model: &str, system: &str, user: &str) -> Result<String, String> {
    let a = agent();
    match p {
        "claude" => {
            let newer = !model.contains("claude-3") && !model.contains("claude-2");
            let mut body = json!({
                "model": model,
                "max_tokens": 16000,
                "system": system,
                "messages": [{"role": "user", "content": user}],
            });
            if newer && !model.contains("haiku") {
                body["output_config"] = json!({"effort": "low"});
            }
            let mut req = a
                .post("https://api.anthropic.com/v1/messages")
                .set("x-api-key", key)
                .set("anthropic-version", ANTHROPIC_VERSION)
                .set("content-type", "application/json");
            if CLAUDE_FALLBACK.contains(&model) {
                req = req.set("anthropic-beta", "server-side-fallback-2026-07-01");
                body["fallbacks"] = json!("default");
            }
            let v = read(p, req.send_json(body))?;
            if v.get("stop_reason").and_then(|s| s.as_str()) == Some("refusal") {
                return Err("Claude recusou ajustar esse texto.".into());
            }
            let text: String = v
                .get("content")
                .and_then(|c| c.as_array())
                .map(|c| c.iter().filter(|b| b["type"] == "text").filter_map(|b| b["text"].as_str()).collect())
                .unwrap_or_default();
            Ok(text)
        }
        "gemini" => {
            let body = json!({
                "system_instruction": {"parts": [{"text": system}]},
                "contents": [{"role": "user", "parts": [{"text": user}]}],
                "generationConfig": {"temperature": 0.2},
            });
            let url = format!("https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent");
            let v = read(p, a.post(&url).set("x-goog-api-key", key).send_json(body))?;
            Ok(gemini_text(&v))
        }
        _ => {
            let base = chat_base(p).ok_or("provedor desconhecido")?;
            let mut body = json!({
                "model": model,
                "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            });
            // Reasoning models only accept the default temperature.
            let reasoning = model.starts_with('o') || model.starts_with("gpt-5") || model.contains("reasoner");
            if !reasoning {
                body["temperature"] = json!(0.2);
            }
            let v = read(p, a.post(&format!("{base}/chat/completions")).set("Authorization", &format!("Bearer {key}")).send_json(body))?;
            Ok(v.pointer("/choices/0/message/content").and_then(|c| c.as_str()).unwrap_or("").to_string())
        }
    }
}

fn gemini_text(v: &Value) -> String {
    v.pointer("/candidates/0/content/parts")
        .and_then(|p| p.as_array())
        .map(|p| p.iter().filter_map(|x| x.get("text").and_then(|t| t.as_str())).collect())
        .unwrap_or_default()
}

// ───────────────────────────── Speech ─────────────────────────────

/// Transcribes a 16 kHz mono WAV with OpenAI or Gemini.
pub fn transcribe(p: &str, key: &str, model: &str, wav: &[u8], language: Option<&str>, hint: &str) -> Result<String, String> {
    let a = agent();
    match p {
        "openai" => {
            let boundary = format!("----copypaste{}", uuid::Uuid::new_v4().simple());
            let mut body: Vec<u8> = vec![];
            let mut field = |name: &str, value: &str| {
                body.extend_from_slice(format!("--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n").as_bytes());
            };
            field("model", model);
            field("response_format", "json");
            if let Some(l) = language {
                field("language", l);
            }
            if !hint.is_empty() {
                field("prompt", hint);
            }
            body.extend_from_slice(
                format!("--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ditado.wav\"\r\nContent-Type: audio/wav\r\n\r\n").as_bytes(),
            );
            body.extend_from_slice(wav);
            body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
            let v = read(
                p,
                a.post("https://api.openai.com/v1/audio/transcriptions")
                    .set("Authorization", &format!("Bearer {key}"))
                    .set("Content-Type", &format!("multipart/form-data; boundary={boundary}"))
                    .send_bytes(&body),
            )?;
            Ok(v.get("text").and_then(|t| t.as_str()).unwrap_or("").to_string())
        }
        "gemini" => {
            let mut prompt = String::from(
                "Transcreva exatamente o que é falado neste áudio, no idioma falado. Devolva somente a transcrição, sem comentários. Se não houver fala, devolva vazio.",
            );
            if let Some(l) = language {
                prompt.push_str(&format!(" Idioma esperado: {l}."));
            }
            if !hint.is_empty() {
                prompt.push_str(&format!(" Grafias corretas de termos que podem aparecer: {hint}."));
            }
            let body = json!({
                "contents": [{"role": "user", "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": "audio/wav", "data": base64::engine::general_purpose::STANDARD.encode(wav)}},
                ]}],
                "generationConfig": {"temperature": 0},
            });
            let url = format!("https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent");
            let v = read(p, a.post(&url).set("x-goog-api-key", key).send_json(body))?;
            Ok(gemini_text(&v))
        }
        _ => Err(format!("{} não transcreve áudio. Use OpenAI ou Gemini.", name(p))),
    }
}
