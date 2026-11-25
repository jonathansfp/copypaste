//! Chooses the native code of each system: `windows/` or `linux/` at the root of the repository.
//! On macOS (development only, since the Mac has its own native app in `macos/`) a minimal stub is used.

#[cfg(windows)]
pub use copypaste_windows::*;

#[cfg(target_os = "linux")]
pub use copypaste_linux::*;

#[cfg(target_os = "macos")]
mod dev_stub {
    use std::path::{Path, PathBuf};
    use std::process::Command;

    pub const SYSTEM: &str = "macOS (desenvolvimento)";

    pub struct AudioInputs {
        pub args: Vec<String>,
        pub count: usize,
        pub warnings: Vec<String>,
    }

    pub fn prepare_env() {}
    pub fn remember_foreground() {}
    pub fn restore_and_paste() -> Result<(), String> {
        Err("Copiado! (colar automático só no Windows e no Linux; no Mac use o app nativo)".into())
    }
    pub fn copy_selection() -> Result<(), String> {
        Err("indisponível".into())
    }
    pub fn clipboard_change_count() -> Option<u64> {
        None
    }
    #[allow(dead_code)]
    pub fn exclude_from_capture(_hwnd: isize) {}
    pub fn ocr_png(_png: &[u8]) -> Result<String, String> {
        Err("OCR indisponível nesta versão de desenvolvimento.".into())
    }
    pub fn hide_console(_cmd: &mut Command) {}
    pub fn ffmpeg_candidates() -> Vec<PathBuf> {
        vec!["ffmpeg".into(), "/opt/homebrew/bin/ffmpeg".into(), "/usr/local/bin/ffmpeg".into()]
    }
    pub fn ffmpeg_hint() -> &'static str {
        "Instale o ffmpeg: brew install ffmpeg"
    }
    pub fn audio_inputs(_ffmpeg: &Path, _mic: bool, _system: bool) -> AudioInputs {
        AudioInputs { args: vec![], count: 0, warnings: vec![] }
    }
    pub fn notes() -> Vec<String> {
        vec!["Versão de desenvolvimento no macOS — para uso diário no Mac, use o app nativo da pasta macos/.".into()]
    }
    pub fn reveal(path: &Path) {
        let _ = Command::new("open").arg("-R").arg(path).spawn();
    }
}

#[cfg(target_os = "macos")]
pub use dev_stub::*;
