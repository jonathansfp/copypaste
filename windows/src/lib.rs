//! Native Windows code for CopyPaste.
//!
//! Exposes the same small API as `copypaste-linux`, so the shared core (`core/`) calls
//! `platform::*` without knowing which system it is running on.

use std::ffi::c_void;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicIsize, Ordering};

#[cfg(windows)]
use windows::Win32::Foundation::HWND;

/// Name of the system, shown in the "About" tab.
pub const SYSTEM: &str = "Windows";

/// Window that was in front before CopyPaste opened its panel: the paste goes back to it.
static PREVIOUS: AtomicIsize = AtomicIsize::new(0);

/// Audio inputs for ffmpeg (`-f dshow -i audio=...`), plus warnings to show the user.
pub struct AudioInputs {
    pub args: Vec<String>,
    pub count: usize,
    pub warnings: Vec<String>,
}

/// Adjusts the process environment before the window system starts.
pub fn prepare_env() {}

/// Saves the window in front (before showing the history panel).
pub fn remember_foreground() {
    #[cfg(windows)]
    unsafe {
        let h = windows::Win32::UI::WindowsAndMessaging::GetForegroundWindow();
        PREVIOUS.store(h.0 as isize, Ordering::SeqCst);
    }
}

/// Brings the previous window back to the front and sends Ctrl+V.
pub fn restore_and_paste() -> Result<(), String> {
    #[cfg(windows)]
    unsafe {
        use windows::Win32::UI::Input::KeyboardAndMouse::*;
        use windows::Win32::UI::WindowsAndMessaging::SetForegroundWindow;

        let prev = PREVIOUS.load(Ordering::SeqCst);
        if prev != 0 {
            let _ = SetForegroundWindow(HWND(prev as *mut c_void));
            std::thread::sleep(std::time::Duration::from_millis(70));
        }
        fn key(vk: VIRTUAL_KEY, up: bool) -> INPUT {
            INPUT {
                r#type: INPUT_KEYBOARD,
                Anonymous: INPUT_0 {
                    ki: KEYBDINPUT {
                        wVk: vk,
                        wScan: 0,
                        dwFlags: if up { KEYEVENTF_KEYUP } else { KEYBD_EVENT_FLAGS(0) },
                        time: 0,
                        dwExtraInfo: 0,
                    },
                },
            }
        }
        // Releases modifiers that may still be held from the shortcut, then presses Ctrl+V.
        let inputs = [
            key(VK_SHIFT, true),
            key(VK_MENU, true),
            key(VK_LWIN, true),
            key(VK_CONTROL, false),
            key(VK_V, false),
            key(VK_V, true),
            key(VK_CONTROL, true),
        ];
        let sent = SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
        if sent as usize != inputs.len() {
            return Err("O Windows bloqueou o envio do Ctrl+V (janela de administrador?). O item ficou copiado: cole com Ctrl+V.".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    Err("indisponível".into())
}

/// Clipboard change counter (cheap): lets the core read the clipboard only when it changes.
pub fn clipboard_change_count() -> Option<u64> {
    #[cfg(windows)]
    unsafe {
        return Some(windows::Win32::System::DataExchange::GetClipboardSequenceNumber() as u64);
    }
    #[cfg(not(windows))]
    None
}

/// Keeps a window out of screenshots and recordings (the recording bar, for example).
pub fn exclude_from_capture(hwnd: isize) {
    #[cfg(windows)]
    unsafe {
        use windows::Win32::UI::WindowsAndMessaging::{SetWindowDisplayAffinity, WDA_EXCLUDEFROMCAPTURE};
        let _ = SetWindowDisplayAffinity(HWND(hwnd as *mut c_void), WDA_EXCLUDEFROMCAPTURE);
    }
    #[cfg(not(windows))]
    let _ = hwnd;
}

/// Reads the text in a PNG image with the OCR built into Windows 10/11 (no internet needed).
pub fn ocr_png(png: &[u8]) -> Result<String, String> {
    #[cfg(windows)]
    {
        ocr_impl(png).map_err(|e| format!("OCR do Windows falhou: {e}"))
    }
    #[cfg(not(windows))]
    {
        let _ = png;
        Err("indisponível".into())
    }
}

#[cfg(windows)]
fn ocr_impl(png: &[u8]) -> windows::core::Result<String> {
    use windows::Graphics::Imaging::BitmapDecoder;
    use windows::Media::Ocr::OcrEngine;
    use windows::Storage::Streams::{DataWriter, InMemoryRandomAccessStream};
    use windows::Win32::System::WinRT::{RO_INIT_MULTITHREADED, RoInitialize};

    unsafe {
        let _ = RoInitialize(RO_INIT_MULTITHREADED);
    }
    let stream = InMemoryRandomAccessStream::new()?;
    let writer = DataWriter::CreateDataWriter(&stream)?;
    writer.WriteBytes(png)?;
    writer.StoreAsync()?.join()?;
    writer.FlushAsync()?.join()?;
    writer.DetachStream()?;
    stream.Seek(0)?;
    let decoder = BitmapDecoder::CreateAsync(&stream)?.join()?;
    let bitmap = decoder.GetSoftwareBitmapAsync()?.join()?;
    let engine = OcrEngine::TryCreateFromUserProfileLanguages()?;
    let result = engine.RecognizeAsync(&bitmap)?.join()?;
    let mut lines = Vec::new();
    for line in result.Lines()? {
        lines.push(line.Text()?.to_string());
    }
    Ok(lines.join("\n"))
}

/// Keeps ffmpeg from opening a console window.
pub fn hide_console(cmd: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    #[cfg(not(windows))]
    let _ = cmd;
}

/// Places where ffmpeg usually is on Windows (winget, scoop, chocolatey, next to the app).
pub fn ffmpeg_candidates() -> Vec<PathBuf> {
    let mut v = vec![PathBuf::from("ffmpeg")];
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            v.push(dir.join("ffmpeg.exe"));
        }
    }
    if let Some(local) = std::env::var_os("LOCALAPPDATA") {
        let local = PathBuf::from(local);
        v.push(local.join("Microsoft").join("WinGet").join("Links").join("ffmpeg.exe"));
    }
    if let Some(home) = std::env::var_os("USERPROFILE") {
        v.push(PathBuf::from(home).join("scoop").join("shims").join("ffmpeg.exe"));
    }
    v.push(PathBuf::from(r"C:\ProgramData\chocolatey\bin\ffmpeg.exe"));
    v.push(PathBuf::from(r"C:\ffmpeg\bin\ffmpeg.exe"));
    v
}

/// How to install ffmpeg on this system.
pub fn ffmpeg_hint() -> &'static str {
    "Instale o ffmpeg (grátis) e tente de novo: abra o Terminal e rode  winget install Gyan.FFmpeg"
}

/// Lists the audio devices (DirectShow) and picks the microphone and, if it exists, "Stereo Mix" for system audio.
pub fn audio_inputs(ffmpeg: &Path, mic: bool, system: bool) -> AudioInputs {
    let mut out = AudioInputs { args: vec![], count: 0, warnings: vec![] };
    if !mic && !system {
        return out;
    }
    let mut cmd = Command::new(ffmpeg);
    cmd.args(["-hide_banner", "-list_devices", "true", "-f", "dshow", "-i", "dummy"]);
    hide_console(&mut cmd);
    let devices: Vec<String> = match cmd.output() {
        Ok(o) => String::from_utf8_lossy(&o.stderr)
            .lines()
            .filter(|l| l.contains("(audio)"))
            .filter_map(|l| {
                let a = l.find('"')?;
                let b = l[a + 1..].find('"')? + a + 1;
                Some(l[a + 1..b].to_string())
            })
            .collect(),
        Err(_) => vec![],
    };
    let is_loopback = |d: &str| {
        let d = d.to_lowercase();
        ["stereo mix", "mixagem est", "mezcla est", "what u hear", "cable output", "loopback"]
            .iter()
            .any(|k| d.contains(k))
    };
    if mic {
        match devices.iter().find(|d| !is_loopback(d)) {
            Some(d) => {
                out.args.extend(["-f".into(), "dshow".into(), "-i".into(), format!("audio={d}")]);
                out.count += 1;
            }
            None => out.warnings.push("Nenhum microfone encontrado.".into()),
        }
    }
    if system {
        match devices.iter().find(|d| is_loopback(d)) {
            Some(d) => {
                out.args.extend(["-f".into(), "dshow".into(), "-i".into(), format!("audio={d}")]);
                out.count += 1;
            }
            None => out.warnings.push(
                "Áudio do sistema: ative “Mixagem estéreo” em Configurações > Som > Mais configurações de som > Gravação (ou instale um cabo virtual).".into(),
            ),
        }
    }
    out
}

/// Notes about the environment (shown in Settings).
pub fn notes() -> Vec<String> {
    vec![]
}

/// Opens a folder or file in Explorer, selecting the file.
pub fn reveal(path: &Path) {
    let mut cmd = Command::new("explorer");
    if path.is_file() {
        cmd.arg(format!("/select,{}", path.display()));
    } else {
        cmd.arg(path);
    }
    let _ = cmd.spawn();
}
