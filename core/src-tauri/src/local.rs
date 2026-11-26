//! Built-in AI that runs on the computer: Google's Gemma 4 E2B (text and audio) on llama.cpp.
//! Nothing is bundled in the installer: on the user's request it downloads the official llama.cpp
//! engine and the model, pinned to fixed versions and checked against their SHA-256. While in use, a
//! local server (`llama-server`, OpenAI-compatible) listens only on 127.0.0.1 and is stopped after
//! 10 minutes without use, giving the memory back.

use serde::Serialize;
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager};

use crate::i18n::{t, tf};
use crate::{platform, AppState};

pub const MODEL_NAME: &str = "Gemma 4 E2B";

struct Asset {
    url: &'static str,
    sha256: &'static str,
    size: u64,
    file: &'static str,
    label: &'static str,
}

#[cfg(windows)]
const RUNTIME: Asset = Asset {
    url: "https://github.com/ggml-org/llama.cpp/releases/download/b12751/llama-b12751-bin-win-cpu-x64.zip",
    sha256: "09c916f56fb8ba4758fcfb6ce4e88eb628180c8214342556d1dab27cef730b85",
    size: 25_238_820,
    file: "llama-runtime.zip",
    label: "motor llama.cpp",
};
#[cfg(target_os = "linux")]
const RUNTIME: Asset = Asset {
    url: "https://github.com/ggml-org/llama.cpp/releases/download/b12751/llama-b12751-bin-ubuntu-x64.tar.gz",
    sha256: "d0f565208f8b28b1129e95d723a05e58a6ec97c87f7ca933df8023fa60a274ea",
    size: 23_405_425,
    file: "llama-runtime.tar.gz",
    label: "motor llama.cpp",
};
#[cfg(target_os = "macos")]
const RUNTIME: Asset = Asset {
    url: "https://github.com/ggml-org/llama.cpp/releases/download/b12751/llama-b12751-bin-macos-arm64.tar.gz",
    sha256: "d6b2790ee9a8f528016976d8f23c0fcbd6310dd739538d0c00088805ef52a490",
    size: 16_840_406,
    file: "llama-runtime.tar.gz",
    label: "motor llama.cpp",
};

const MODEL: Asset = Asset {
    url: concat!("https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/0314792d7f1f7e229411f620751375812bb9faf2/", "gemma-4-E2B-it-Q4_K_M.gguf"),
    sha256: "740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8",
    size: 3_106_738_272,
    file: "gemma-4-E2B-it-Q4_K_M.gguf",
    label: "modelo Gemma 4",
};
const AUDIO: Asset = Asset {
    url: concat!("https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/0314792d7f1f7e229411f620751375812bb9faf2/", "mmproj-F16.gguf"),
    sha256: "140be8d7849741f88c50757d529b84373ee8e27052cc2236855b537f4a8215fa",
    size: 985_654_080,
    file: "mmproj-F16.gguf",
    label: "módulo de voz e imagem",
};

pub fn total_bytes() -> u64 {
    RUNTIME.size + MODEL.size + AUDIO.size
}

struct Server {
    child: Child,
    port: u16,
    ready: bool,
}

static SERVER: Mutex<Option<Server>> = Mutex::new(None);
static LAST_USE: Mutex<Option<Instant>> = Mutex::new(None);
static DOWNLOADING: AtomicBool = AtomicBool::new(false);
static CANCEL: AtomicBool = AtomicBool::new(false);
/// Serializes server start-ups (two requests at once must not launch two servers).
static STARTING: Mutex<()> = Mutex::new(());

pub fn dir(app: &AppHandle) -> PathBuf {
    app.state::<AppState>().paths.data.join("ia-local")
}

fn runtime_dir(app: &AppHandle) -> PathBuf {
    dir(app).join("llama-b12751")
}

fn has_file(app: &AppHandle, a: &Asset) -> bool {
    std::fs::metadata(dir(app).join(a.file)).map(|m| m.len() == a.size).unwrap_or(false)
}

fn find_server(root: &Path) -> Option<PathBuf> {
    let name = if cfg!(windows) { "llama-server.exe" } else { "llama-server" };
    let rd = std::fs::read_dir(root).ok()?;
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() {
            if let Some(f) = find_server(&p) {
                return Some(f);
            }
        } else if p.file_name().and_then(|n| n.to_str()) == Some(name) {
            return Some(p);
        }
    }
    None
}

pub fn is_installed(app: &AppHandle) -> bool {
    find_server(&runtime_dir(app)).is_some() && has_file(app, &MODEL) && has_file(app, &AUDIO)
}

fn disk_usage(p: &Path) -> u64 {
    let Ok(rd) = std::fs::read_dir(p) else { return 0 };
    rd.flatten()
        .map(|e| {
            let p = e.path();
            if p.is_dir() {
                disk_usage(&p)
            } else {
                e.metadata().map(|m| m.len()).unwrap_or(0)
            }
        })
        .sum()
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    installed: bool,
    downloading: bool,
    running: bool,
    total: u64,
    disk: u64,
    has_model: bool,
}

pub fn status(app: &AppHandle) -> Status {
    Status {
        installed: is_installed(app),
        downloading: DOWNLOADING.load(Ordering::SeqCst),
        running: SERVER.lock().unwrap().as_ref().map(|s| s.ready).unwrap_or(false),
        total: total_bytes(),
        disk: disk_usage(&dir(app)),
        has_model: has_file(app, &MODEL) && has_file(app, &AUDIO),
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct Progress {
    progress: f64,
    label: String,
    error: Option<String>,
    done: bool,
}

fn emit(app: &AppHandle, progress: f64, label: &str, error: Option<String>, done: bool) {
    let _ = app.emit("local-progress", Progress { progress, label: label.into(), error, done });
}

// ───────────────────────────── Install ─────────────────────────────

pub fn install(app: &AppHandle) {
    if DOWNLOADING.swap(true, Ordering::SeqCst) {
        return;
    }
    CANCEL.store(false, Ordering::SeqCst);
    let app = app.clone();
    std::thread::spawn(move || {
        let res = install_blocking(&app);
        DOWNLOADING.store(false, Ordering::SeqCst);
        match res {
            Ok(()) => {
                crate::diag(&app, "IA local instalada");
                emit(&app, 1.0, t("Pronta"), None, true);
            }
            Err(e) => {
                crate::diag(&app, &format!("IA local: {e}"));
                emit(&app, 0.0, "", Some(e), true);
            }
        }
    });
}

pub fn cancel_install() {
    CANCEL.store(true, Ordering::SeqCst);
}

fn install_blocking(app: &AppHandle) -> Result<(), String> {
    let d = dir(app);
    std::fs::create_dir_all(&d).map_err(|e| e.to_string())?;
    let total = total_bytes() as f64;
    let mut done: u64 = 0;
    for a in [&RUNTIME, &MODEL, &AUDIO] {
        let dest = d.join(a.file);
        if a.file != RUNTIME.file && has_file(app, a) {
            done += a.size;
            continue;
        }
        download(app, a, &dest, done, total)?;
        done += a.size;
    }
    // Unpacks the engine (tar handles .tar.gz and, on Windows 10+, .zip).
    let rt = runtime_dir(app);
    let _ = std::fs::remove_dir_all(&rt);
    std::fs::create_dir_all(&rt).map_err(|e| e.to_string())?;
    let archive = d.join(RUNTIME.file);
    let mut cmd = Command::new("tar");
    cmd.arg(if cfg!(windows) { "-xf" } else { "-xzf" }).arg(&archive).arg("-C").arg(&rt);
    platform::hide_console(&mut cmd);
    let ok = cmd.status().map(|s| s.success()).unwrap_or(false);
    let _ = std::fs::remove_file(&archive);
    if !ok || find_server(&rt).is_none() {
        return Err(t("Não consegui instalar o motor da IA local.").into());
    }
    #[cfg(unix)]
    if let Some(bin) = find_server(&rt) {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755));
    }
    // Becomes the default while no other AI is active.
    let st = app.state::<AppState>();
    let mut s = st.settings.lock().unwrap();
    let keys = st.ai_keys.lock().unwrap();
    if !keys.contains_key(&s.dict_polish) {
        s.dict_polish = "local".into();
    }
    if !keys.contains_key(&s.dict_engine) {
        s.dict_engine = "local".into();
    }
    s.save(&st.paths.settings);
    Ok(())
}

fn download(app: &AppHandle, a: &Asset, dest: &Path, base: u64, total: f64) -> Result<(), String> {
    let resp = crate::ai::agent_builder()
        .timeout_connect(Duration::from_secs(20))
        .timeout_read(Duration::from_secs(60))
        .build()
        .get(a.url)
        .call()
        .map_err(|e| tf("O download de {} falhou: {}", &[&t(a.label), &e]))?;
    let part = dest.with_extension("part");
    let mut out = std::fs::File::create(&part).map_err(|e| e.to_string())?;
    let mut reader = resp.into_reader();
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    let mut got: u64 = 0;
    let mut last = Instant::now();
    loop {
        if CANCEL.load(Ordering::SeqCst) {
            drop(out);
            let _ = std::fs::remove_file(&part);
            return Err(t("Download cancelado.").into());
        }
        let n = reader.read(&mut buf).map_err(|e| tf("O download parou: {}", &[&e]))?;
        if n == 0 {
            break;
        }
        out.write_all(&buf[..n]).map_err(|e| tf("Sem espaço em disco? {}", &[&e]))?;
        hasher.update(&buf[..n]);
        got += n as u64;
        if last.elapsed() > Duration::from_millis(250) {
            last = Instant::now();
            emit(app, (base + got) as f64 / total, &tf("Baixando {}…", &[&t(a.label)]), None, false);
        }
    }
    drop(out);
    let hash: String = hasher.finalize().iter().map(|b| format!("{b:02x}")).collect();
    if got != a.size || hash != a.sha256 {
        let _ = std::fs::remove_file(&part);
        return Err(tf("O arquivo {} chegou incompleto ou corrompido. Tente de novo.", &[&t(a.label)]));
    }
    let _ = std::fs::remove_file(dest);
    std::fs::rename(&part, dest).map_err(|e| e.to_string())
}

pub fn remove(app: &AppHandle) {
    stop();
    let _ = std::fs::remove_dir_all(dir(app));
    let st = app.state::<AppState>();
    let mut s = st.settings.lock().unwrap();
    if s.dict_polish == "local" {
        s.dict_polish = st.ai_keys.lock().unwrap().keys().next().cloned().unwrap_or_default();
    }
    s.save(&st.paths.settings);
}

// ───────────────────────────── Server ─────────────────────────────

/// Loads the model in the background (while the user is still talking).
pub fn prewarm(app: &AppHandle) {
    if !is_installed(app) {
        return;
    }
    let app = app.clone();
    std::thread::spawn(move || {
        let _ = ensure_running(&app);
    });
}

/// Base URL of the OpenAI-compatible API (`http://127.0.0.1:PORT/v1`), starting the server if needed.
pub fn ensure_running(app: &AppHandle) -> Result<String, String> {
    if !is_installed(app) {
        return Err(t("Baixe a IA local em Configurações › IA e ditado.").into());
    }
    *LAST_USE.lock().unwrap() = Some(Instant::now());
    let _guard = STARTING.lock().unwrap();
    {
        let mut g = SERVER.lock().unwrap();
        if let Some(s) = g.as_mut() {
            if matches!(s.child.try_wait(), Ok(None)) && s.ready {
                return Ok(format!("http://127.0.0.1:{}/v1", s.port));
            }
        }
    }
    stop();
    let bin = find_server(&runtime_dir(app)).ok_or(t("Motor da IA local não encontrado. Reinstale a IA local."))?;
    let port = std::net::TcpListener::bind("127.0.0.1:0").and_then(|l| l.local_addr()).map(|a| a.port()).unwrap_or(18765);
    let d = dir(app);
    let log = std::fs::File::create(d.join("servidor.log")).ok();
    let mut cmd = Command::new(&bin);
    cmd.current_dir(bin.parent().unwrap_or(&d))
        .arg("-m")
        .arg(d.join(MODEL.file))
        .arg("--mmproj")
        .arg(d.join(AUDIO.file))
        .args(["--host", "127.0.0.1", "--port", &port.to_string(), "-c", "8192", "-np", "1", "--no-webui", "--reasoning", "off"])
        .stdin(Stdio::null());
    if let Some(l) = log {
        if let Ok(l2) = l.try_clone() {
            cmd.stdout(l).stderr(l2);
        }
    }
    platform::hide_console(&mut cmd);
    let child = cmd.spawn().map_err(|e| tf("A IA local não conseguiu iniciar: {}", &[&e]))?;
    crate::diag(app, &format!("IA local: servidor na porta {port}"));
    *SERVER.lock().unwrap() = Some(Server { child, port, ready: false });
    let started = Instant::now();
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(2)).build();
    while started.elapsed() < Duration::from_secs(240) {
        {
            let mut g = SERVER.lock().unwrap();
            let Some(s) = g.as_mut() else { return Err(t("A IA local foi encerrada.").into()) };
            if !matches!(s.child.try_wait(), Ok(None)) {
                *g = None;
                return Err(tf("A IA local não conseguiu iniciar. {}", &[&log_tail(&d)]));
            }
        }
        if agent.get(&format!("http://127.0.0.1:{port}/health")).call().is_ok() {
            if let Some(s) = SERVER.lock().unwrap().as_mut() {
                s.ready = true;
            }
            start_idle_watch();
            return Ok(format!("http://127.0.0.1:{port}/v1"));
        }
        std::thread::sleep(Duration::from_millis(300));
    }
    stop();
    Err(t("A IA local demorou demais para carregar.").into())
}

pub fn touch() {
    *LAST_USE.lock().unwrap() = Some(Instant::now());
}

fn log_tail(d: &Path) -> String {
    let s = std::fs::read_to_string(d.join("servidor.log")).unwrap_or_default();
    let lines: Vec<&str> = s.lines().rev().take(3).collect();
    let t: String = lines.into_iter().rev().collect::<Vec<_>>().join(" ");
    t.chars().rev().take(240).collect::<String>().chars().rev().collect()
}

static WATCHING: AtomicBool = AtomicBool::new(false);

fn start_idle_watch() {
    if WATCHING.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(|| loop {
        std::thread::sleep(Duration::from_secs(60));
        let idle = LAST_USE.lock().unwrap().map(|t| t.elapsed() > Duration::from_secs(600)).unwrap_or(true);
        if idle && SERVER.lock().unwrap().is_some() {
            stop();
        }
    });
}

pub fn stop() {
    if let Some(mut s) = SERVER.lock().unwrap().take() {
        let _ = s.child.kill();
        let _ = s.child.wait();
    }
}

