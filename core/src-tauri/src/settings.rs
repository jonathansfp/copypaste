use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// Actions that can have a global shortcut.
pub const ACTIONS: [&str; 5] = ["clipboard", "captureArea", "captureScreen", "board", "record"];

pub fn default_hotkey(action: &str) -> &'static str {
    match action {
        "clipboard" => "Ctrl+Shift+V",
        "captureArea" => "PrintScreen",
        "captureScreen" => "Shift+PrintScreen",
        "board" => "Ctrl+Shift+D",
        "record" => "Ctrl+Shift+R",
        _ => "",
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    /// action → accelerator ("Ctrl+Shift+V"); empty = disabled.
    pub hotkeys: BTreeMap<String, String>,
    pub capture_dir: String,
    /// "png" or "jpg".
    pub capture_format: String,
    /// What Enter does in the capture: "copy", "save" or "copyAndSave".
    pub capture_enter: String,
    pub magnifier: bool,
    pub snap_windows: bool,
    pub record_dir: String,
    pub record_mic: bool,
    pub record_system_audio: bool,
    pub record_fps: u32,
    pub history_limit: usize,
    /// Enter / double click in the history pastes into the previous app (otherwise only copies).
    pub paste_on_select: bool,
    pub paused: bool,
    pub autostart: bool,
    pub first_run_done: bool,
}

fn user_dir(base: Option<PathBuf>, fallback: &str) -> String {
    base.or_else(|| std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).map(|h| PathBuf::from(h).join(fallback)))
        .unwrap_or_else(|| PathBuf::from("."))
        .join("CopyPaste")
        .to_string_lossy()
        .into_owned()
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            hotkeys: ACTIONS.iter().map(|a| (a.to_string(), default_hotkey(a).to_string())).collect(),
            capture_dir: user_dir(picture_dir(), "Pictures"),
            capture_format: "png".into(),
            capture_enter: "copy".into(),
            magnifier: true,
            snap_windows: true,
            record_dir: user_dir(video_dir(), "Videos"),
            record_mic: false,
            record_system_audio: false,
            record_fps: 30,
            history_limit: 500,
            paste_on_select: true,
            paused: false,
            autostart: true,
            first_run_done: false,
        }
    }
}

fn picture_dir() -> Option<PathBuf> {
    xdg_or_home("XDG_PICTURES_DIR", "Pictures")
}
fn video_dir() -> Option<PathBuf> {
    xdg_or_home("XDG_VIDEOS_DIR", if cfg!(target_os = "macos") { "Movies" } else { "Videos" })
}

/// Uses the system folders (`~/Imagens` on a Linux in Portuguese, via `user-dirs.dirs`).
fn xdg_or_home(var: &str, folder: &str) -> Option<PathBuf> {
    let home = PathBuf::from(std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" })?);
    if cfg!(target_os = "linux") {
        if let Ok(conf) = std::fs::read_to_string(home.join(".config/user-dirs.dirs")) {
            for line in conf.lines() {
                if let Some(v) = line.strip_prefix(&format!("{var}=")) {
                    let v = v.trim_matches('"').replace("$HOME", &home.to_string_lossy());
                    return Some(PathBuf::from(v));
                }
            }
        }
    }
    Some(home.join(folder))
}

impl Settings {
    pub fn load(path: &Path) -> Settings {
        let mut s: Settings = std::fs::read(path)
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        for a in ACTIONS {
            s.hotkeys.entry(a.to_string()).or_insert_with(|| default_hotkey(a).to_string());
        }
        s.record_fps = s.record_fps.clamp(10, 60);
        s.history_limit = s.history_limit.clamp(20, 5000);
        s
    }

    pub fn save(&self, path: &Path) {
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(b) = serde_json::to_vec_pretty(self) {
            let _ = std::fs::write(path, b);
        }
    }
}
