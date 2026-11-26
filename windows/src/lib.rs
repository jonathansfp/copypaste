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

/// Saves the window in front (before showing the history panel). Our own windows and the taskbar
/// (opening from the tray icon) are skipped, so the paste goes back to the app the person was using.
pub fn remember_foreground() {
    #[cfg(windows)]
    unsafe {
        use windows::Win32::UI::WindowsAndMessaging::{GetClassNameW, GetForegroundWindow, GetWindowThreadProcessId};
        let h = GetForegroundWindow();
        if h.0.is_null() {
            return;
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(h, Some(&mut pid));
        if pid == std::process::id() {
            return;
        }
        let mut buf = [0u16; 64];
        let n = GetClassNameW(h, &mut buf).max(0) as usize;
        let class = String::from_utf16_lossy(&buf[..n]);
        if ["Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow", "TopLevelWindowForOverflowXamlIsland"].contains(&class.as_str()) {
            return;
        }
        PREVIOUS.store(h.0 as isize, Ordering::SeqCst);
    }
}

#[cfg(windows)]
unsafe fn key_input(vk: windows::Win32::UI::Input::KeyboardAndMouse::VIRTUAL_KEY, up: bool) -> windows::Win32::UI::Input::KeyboardAndMouse::INPUT {
    use windows::Win32::UI::Input::KeyboardAndMouse::*;
    // Scan code too: some apps (games, remote desktops, Electron) ignore virtual-key-only input.
    let scan = MapVirtualKeyW(vk.0 as u32, MAPVK_VK_TO_VSC) as u16;
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT { wVk: vk, wScan: scan, dwFlags: if up { KEYEVENTF_KEYUP } else { KEYBD_EVENT_FLAGS(0) }, time: 0, dwExtraInfo: 0 },
        },
    }
}

/// Sends `ctrl + letter`, first releasing modifiers that are still held (from the shortcut).
#[cfg(windows)]
unsafe fn send_ctrl(letter: windows::Win32::UI::Input::KeyboardAndMouse::VIRTUAL_KEY) -> bool {
    use windows::Win32::UI::Input::KeyboardAndMouse::*;
    // Give the person a moment to let go of the keys; then release whatever is still down.
    for _ in 0..40 {
        if [VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN].iter().all(|k| (GetAsyncKeyState(k.0 as i32) as u16) & 0x8000 == 0) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let mut inputs = vec![];
    for k in [VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN] {
        if (GetAsyncKeyState(k.0 as i32) as u16) & 0x8000 != 0 {
            inputs.push(key_input(k, true));
        }
    }
    inputs.extend([key_input(VK_CONTROL, false), key_input(letter, false), key_input(letter, true), key_input(VK_CONTROL, true)]);
    SendInput(&inputs, std::mem::size_of::<INPUT>() as i32) as usize == inputs.len()
}

/// Puts `hwnd` in front. Windows only lets the foreground app change the foreground, so the input
/// of this thread is attached to the current foreground window's thread while switching.
#[cfg(windows)]
unsafe fn bring_to_front(hwnd: HWND) -> bool {
    use windows::Win32::System::Threading::{AttachThreadInput, GetCurrentThreadId};
    use windows::Win32::UI::WindowsAndMessaging::*;
    let fg = GetForegroundWindow();
    if fg == hwnd {
        return true;
    }
    let me = GetCurrentThreadId();
    let other = GetWindowThreadProcessId(fg, None);
    let attached = other != 0 && other != me && AttachThreadInput(me, other, true).as_bool();
    if IsIconic(hwnd).as_bool() {
        let _ = ShowWindow(hwnd, SW_RESTORE);
    }
    let _ = BringWindowToTop(hwnd);
    let _ = SetForegroundWindow(hwnd);
    if attached {
        let _ = AttachThreadInput(me, other, false);
    }
    for _ in 0..25 {
        if GetForegroundWindow() == hwnd {
            return true;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    false
}

/// Sends Ctrl+C to the window in front (copies the selected text, for voice commands).
pub fn copy_selection() -> Result<(), String> {
    #[cfg(windows)]
    unsafe {
        use windows::Win32::UI::Input::KeyboardAndMouse::VK_C;
        if !send_ctrl(VK_C) {
            return Err("o Windows bloqueou o Ctrl+C".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    Err("indisponível".into())
}

/// Brings the previous window back to the front and sends Ctrl+V.
pub fn restore_and_paste() -> Result<(), String> {
    #[cfg(windows)]
    unsafe {
        use windows::Win32::UI::Input::KeyboardAndMouse::VK_V;
        use windows::Win32::UI::WindowsAndMessaging::IsWindow;
        let prev = HWND(PREVIOUS.load(Ordering::SeqCst) as *mut c_void);
        if !prev.0.is_null() && IsWindow(Some(prev)).as_bool() {
            bring_to_front(prev);
            // The app needs a moment to give the keyboard focus back to its text field.
            std::thread::sleep(std::time::Duration::from_millis(60));
        }
        if !send_ctrl(VK_V) {
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
