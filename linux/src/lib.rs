//! Native Linux code for CopyPaste (X11 and Wayland).
//!
//! Exposes the same small API as `copypaste-windows`. Helper tools (xdotool, wtype, ydotool,
//! tesseract, ffmpeg, pactl) are optional: whatever is missing is reported in Settings.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Mutex;

/// Name of the system, shown in the "About" tab.
pub const SYSTEM: &str = "Linux";

static PREVIOUS: Mutex<Option<String>> = Mutex::new(None);

/// Audio inputs for ffmpeg (PulseAudio / PipeWire), plus warnings to show the user.
pub struct AudioInputs {
    pub args: Vec<String>,
    pub count: usize,
    pub warnings: Vec<String>,
}

/// True in a Wayland session (GNOME and KDE by default on recent distros).
pub fn is_wayland() -> bool {
    std::env::var("XDG_SESSION_TYPE").map(|v| v == "wayland").unwrap_or(false)
        || std::env::var_os("WAYLAND_DISPLAY").is_some()
}

/// Runs the windows through XWayland: positioning, "always on top" and focus work
/// as they do on X11. Also avoids the WebKitGTK blank screen on some graphics drivers.
pub fn prepare_env() {
    // SAFETY: called at the very start of main, before any thread exists.
    unsafe {
        if is_wayland() && std::env::var_os("GDK_BACKEND").is_none() {
            std::env::set_var("GDK_BACKEND", "x11");
        }
        if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
            std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
        }
    }
}

fn has(tool: &str) -> bool {
    Command::new("sh")
        .args(["-c", &format!("command -v {tool}")])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run(cmd: &str, args: &[&str]) -> Result<String, String> {
    let o = Command::new(cmd).args(args).output().map_err(|e| format!("{cmd}: {e}"))?;
    if o.status.success() {
        Ok(String::from_utf8_lossy(&o.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&o.stderr).trim().to_string())
    }
}

/// Saves the active window (X11, with xdotool) to give focus back when pasting.
pub fn remember_foreground() {
    let id = if !is_wayland() && has("xdotool") { run("xdotool", &["getactivewindow"]).ok() } else { None };
    *PREVIOUS.lock().unwrap() = id;
}

/// Gives focus back to the previous window and sends Ctrl+V.
pub fn restore_and_paste() -> Result<(), String> {
    std::thread::sleep(std::time::Duration::from_millis(80));
    if !is_wayland() {
        if !has("xdotool") {
            return Err("Copiado! Para colar sozinho, instale o xdotool (sudo apt install xdotool).".into());
        }
        if let Some(id) = PREVIOUS.lock().unwrap().clone() {
            let _ = run("xdotool", &["windowactivate", "--sync", &id]);
        }
        return run("xdotool", &["key", "--clearmodifiers", "ctrl+v"]).map(|_| ());
    }
    if has("wtype") && run("wtype", &["-M", "ctrl", "-k", "v", "-m", "ctrl"]).is_ok() {
        return Ok(());
    }
    if has("ydotool") && run("ydotool", &["key", "29:1", "47:1", "47:0", "29:0"]).is_ok() {
        return Ok(());
    }
    Err("Copiado! No Wayland, para colar sozinho instale o wtype (KDE/Sway) ou o ydotool (GNOME).".into())
}

/// Linux has no cheap clipboard change counter: the core reads it periodically.
pub fn clipboard_change_count() -> Option<u64> {
    None
}

/// On Linux there is no way to keep a window out of capture.
pub fn exclude_from_capture(_hwnd: isize) {}

fn tesseract_langs() -> String {
    let available = run("tesseract", &["--list-langs"]).unwrap_or_default();
    let wanted: Vec<&str> = ["por", "eng", "spa"]
        .into_iter()
        .filter(|l| available.lines().any(|a| a.trim() == *l))
        .collect();
    if wanted.is_empty() { "eng".into() } else { wanted.join("+") }
}

/// OCR with Tesseract (local, no internet).
pub fn ocr_png(png: &[u8]) -> Result<String, String> {
    if !has("tesseract") {
        return Err("Para reconhecer texto, instale o Tesseract: sudo apt install tesseract-ocr tesseract-ocr-por".into());
    }
    let file = std::env::temp_dir().join(format!("copypaste-ocr-{}.png", std::process::id()));
    std::fs::write(&file, png).map_err(|e| e.to_string())?;
    let langs = tesseract_langs();
    let r = run("tesseract", &[file.to_str().unwrap_or_default(), "stdout", "-l", &langs]);
    let _ = std::fs::remove_file(&file);
    r
}

pub fn hide_console(_cmd: &mut Command) {}

pub fn ffmpeg_candidates() -> Vec<PathBuf> {
    vec![PathBuf::from("ffmpeg"), PathBuf::from("/usr/bin/ffmpeg"), PathBuf::from("/usr/local/bin/ffmpeg")]
}

pub fn ffmpeg_hint() -> &'static str {
    "Instale o ffmpeg e tente de novo: sudo apt install ffmpeg  (Fedora: sudo dnf install ffmpeg)"
}

/// Microphone = default PulseAudio/PipeWire input; system audio = "monitor" of the default output.
pub fn audio_inputs(_ffmpeg: &Path, mic: bool, system: bool) -> AudioInputs {
    let mut out = AudioInputs { args: vec![], count: 0, warnings: vec![] };
    if mic {
        out.args.extend(["-f", "pulse", "-i", "default"].map(String::from));
        out.count += 1;
    }
    if system {
        match run("pactl", &["get-default-sink"]) {
            Ok(sink) if !sink.is_empty() => {
                out.args.extend(["-f".into(), "pulse".into(), "-i".into(), format!("{sink}.monitor")]);
                out.count += 1;
            }
            _ => out.warnings.push("Áudio do sistema: instale o pactl (pulseaudio-utils) para gravá-lo.".into()),
        }
    }
    out
}

/// Missing tools and limits of the current session, shown in Settings.
pub fn notes() -> Vec<String> {
    let mut n = vec![];
    if is_wayland() {
        n.push("Sessão Wayland: se um atalho global não funcionar, crie um atalho do sistema que rode `copypaste --capture-area` (ou --capture-screen, --history, --board, --record).".into());
        if !has("wtype") && !has("ydotool") {
            n.push("Para colar sozinho no Wayland, instale o wtype (KDE/Sway) ou o ydotool (GNOME).".into());
        }
    } else if !has("xdotool") {
        n.push("Para colar sozinho, instale o xdotool: sudo apt install xdotool".into());
    }
    if !has("tesseract") {
        n.push("Para copiar texto de imagens (OCR), instale: sudo apt install tesseract-ocr tesseract-ocr-por".into());
    }
    if !has("ffmpeg") {
        n.push("Para gravar a tela, instale: sudo apt install ffmpeg".into());
    }
    n
}

pub fn reveal(path: &Path) {
    let target = if path.is_file() { path.parent().unwrap_or(path) } else { path };
    let _ = Command::new("xdg-open").arg(target).spawn();
}
