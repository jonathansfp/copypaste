//! Screen capture: freezes the monitor under the mouse, opens the editor over it and finishes
//! (copy, save, pin, OCR) with the image the editor renders at native resolution.

use serde::Serialize;
use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Instant;
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize};

use crate::{platform, ui, AppState};

#[derive(Serialize, Clone, Debug)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

/// Frozen screen: RGBA pixels of the monitor at the moment of the shortcut.
pub struct Frozen {
    pub id: u64,
    pub mon_x: i32,
    pub mon_y: i32,
    pub width: u32,
    pub height: u32,
    pub rgba: Arc<Vec<u8>>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EditorOpen {
    pub mode: String,
    pub frame: u64,
    pub width: u32,
    pub height: u32,
    /// Windows on that monitor (in physical pixels, relative to the monitor), from front to back.
    pub windows: Vec<Rect>,
    pub magnifier: bool,
    pub enter_action: String,
    pub mic: bool,
    pub system_audio: bool,
}

/// mode: "area", "screen", "record" or "board".
pub fn start(app: &AppHandle, mode: &str) {
    let state = app.state::<AppState>();
    if state.recorder.lock().unwrap().is_some() && mode == "record" {
        crate::recorder::stop(app);
        return;
    }
    if let Some(ed) = app.get_webview_window("editor") {
        if ed.is_visible().unwrap_or(false) {
            // Shortcut pressed again with the editor open: in the board it closes, in the capture it does nothing.
            if mode == "board" {
                let _ = app.emit_to("editor", "editor-close-request", ());
            }
            return;
        }
    }
    let t0 = Instant::now();
    let cursor = app.cursor_position().unwrap_or(PhysicalPosition::new(0.0, 0.0));
    let monitor = match xcap::Monitor::from_point(cursor.x as i32, cursor.y as i32)
        .or_else(|_| xcap::Monitor::all().map_err(|e| e).and_then(|m| m.into_iter().next().ok_or(xcap::XCapError::new("sem monitor"))))
    {
        Ok(m) => m,
        Err(e) => {
            ui::toast(app, &format!("Não consegui acessar a tela: {e}"));
            return;
        }
    };
    let (mx, my) = (monitor.x().unwrap_or(0), monitor.y().unwrap_or(0));
    let image = match monitor.capture_image() {
        Ok(i) => i,
        Err(e) => {
            ui::toast(app, &format!("Falha ao capturar a tela: {e}"));
            return;
        }
    };
    let (w, h) = (image.width(), image.height());
    let settings = state.settings.lock().unwrap().clone();
    let windows = if settings.snap_windows && mode != "board" { window_rects(mx, my, w, h) } else { vec![] };
    let id = {
        let mut f = state.frozen.lock().unwrap();
        let id = f.as_ref().map(|f| f.id + 1).unwrap_or(1);
        *f = Some(Frozen { id, mon_x: mx, mon_y: my, width: w, height: h, rgba: Arc::new(image.into_raw()) });
        id
    };
    let payload = EditorOpen {
        mode: mode.into(),
        frame: id,
        width: w,
        height: h,
        windows,
        magnifier: settings.magnifier,
        enter_action: settings.capture_enter.clone(),
        mic: settings.record_mic,
        system_audio: settings.record_system_audio,
    };
    crate::diag(app, &format!("captura {mode}: {w}x{h} em {:?}", t0.elapsed()));
    show_editor(app, mx, my, w, h, payload);
}

fn window_rects(mx: i32, my: i32, w: u32, h: u32) -> Vec<Rect> {
    let me = std::process::id();
    let Ok(all) = xcap::Window::all() else { return vec![] };
    let mut out = vec![];
    for win in all {
        if win.is_minimized().unwrap_or(true) || win.pid().map(|p| p == me).unwrap_or(false) {
            continue;
        }
        let (Ok(x), Ok(y), Ok(ww), Ok(wh)) = (win.x(), win.y(), win.width(), win.height()) else { continue };
        if ww < 40 || wh < 30 {
            continue;
        }
        // Relative to the monitor and clipped to it.
        let (rx, ry) = ((x - mx) as f64, (y - my) as f64);
        let x0 = rx.max(0.0);
        let y0 = ry.max(0.0);
        let x1 = (rx + ww as f64).min(w as f64);
        let y1 = (ry + wh as f64).min(h as f64);
        if x1 - x0 < 30.0 || y1 - y0 < 30.0 {
            continue;
        }
        out.push(Rect { x: x0, y: y0, w: x1 - x0, h: y1 - y0 });
        if out.len() > 60 {
            break;
        }
    }
    out
}

fn show_editor(app: &AppHandle, mx: i32, my: i32, w: u32, h: u32, payload: EditorOpen) {
    let Some(ed) = app.get_webview_window("editor") else { return };
    let _ = ed.set_fullscreen(false);
    let _ = ed.set_position(PhysicalPosition::new(mx, my));
    let _ = ed.set_size(PhysicalSize::new(w, h));
    let state = app.state::<AppState>();
    let gen = state.editor_gen.fetch_add(1, Ordering::SeqCst) + 1;
    state.editor_shown.store(false, Ordering::SeqCst);
    let _ = ed.emit("editor-open", payload);
    // The editor asks to be shown once the frozen screen is drawn (no flash of the previous capture).
    // If it does not answer in time, it is shown anyway.
    let app = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(700));
        let state = app.state::<AppState>();
        if state.editor_gen.load(Ordering::SeqCst) == gen && !state.editor_shown.load(Ordering::SeqCst) {
            reveal_editor(&app);
        }
    });
}

/// Shows the editor (called by the page when it is ready).
pub fn reveal_editor(app: &AppHandle) {
    let state = app.state::<AppState>();
    if state.editor_shown.swap(true, Ordering::SeqCst) {
        return;
    }
    let Some(ed) = app.get_webview_window("editor") else { return };
    let _ = ed.show();
    #[cfg(not(target_os = "macos"))]
    let _ = ed.set_fullscreen(true);
    let _ = ed.set_always_on_top(true);
    let _ = ed.set_focus();
}

pub fn hide_editor(app: &AppHandle) {
    app.state::<AppState>().editor_shown.store(true, Ordering::SeqCst);
    if let Some(ed) = app.get_webview_window("editor") {
        let _ = ed.hide();
        #[cfg(not(target_os = "macos"))]
        let _ = ed.set_fullscreen(false);
    }
}

/// Response of the `cpframe://` protocol at `/frame/<id>`: raw RGBA (fastest path, nothing to encode).
pub fn frame_bytes(app: &AppHandle) -> Option<(u32, u32, Arc<Vec<u8>>)> {
    let state = app.state::<AppState>();
    let f = state.frozen.lock().unwrap();
    f.as_ref().map(|f| (f.width, f.height, f.rgba.clone()))
}

pub fn file_name(ext: &str) -> String {
    format!("Captura {}.{ext}", chrono::Local::now().format("%Y-%m-%d às %H.%M.%S"))
}

fn encode(png: &[u8], format: &str) -> Result<(Vec<u8>, &'static str), String> {
    if format == "jpg" {
        let img = image::load_from_memory(png).map_err(|e| e.to_string())?.to_rgb8();
        let mut out = vec![];
        let mut enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 92);
        enc.encode_image(&img).map_err(|e| e.to_string())?;
        Ok((out, "jpg"))
    } else {
        Ok((png.to_vec(), "png"))
    }
}

pub fn save_to_folder(app: &AppHandle, png: &[u8]) -> Result<PathBuf, String> {
    let s = app.state::<AppState>().settings.lock().unwrap().clone();
    let dir = PathBuf::from(&s.capture_dir);
    std::fs::create_dir_all(&dir).map_err(|e| format!("Não consegui criar {}: {e}", dir.display()))?;
    let (bytes, ext) = encode(png, &s.capture_format)?;
    let path = dir.join(file_name(ext));
    std::fs::write(&path, bytes).map_err(|e| e.to_string())?;
    Ok(path)
}

pub fn copy_png(app: &AppHandle, png: &[u8]) -> Result<(), String> {
    let img = image::load_from_memory(png).map_err(|e| e.to_string())?.to_rgba8();
    let (w, h) = (img.width() as usize, img.height() as usize);
    crate::set_clipboard_image(app, w, h, img.into_raw())
}

/// Finishes the capture with the PNG rendered by the editor.
pub fn finish(app: &AppHandle, action: &str, png: Vec<u8>, pin_at: Option<(f64, f64)>, keep: bool) -> Result<String, String> {
    if !keep || action == "saveAs" {
        hide_editor(app);
    }
    match action {
        "copy" => {
            copy_png(app, &png)?;
            ui::toast(app, "Captura copiada");
            Ok("ok".into())
        }
        "save" => {
            let p = save_to_folder(app, &png)?;
            ui::toast_path(app, "Captura salva", &p);
            Ok(p.to_string_lossy().into())
        }
        "copyAndSave" => {
            copy_png(app, &png)?;
            let p = save_to_folder(app, &png)?;
            ui::toast_path(app, "Copiada e salva", &p);
            Ok(p.to_string_lossy().into())
        }
        "saveAs" => {
            use tauri_plugin_dialog::DialogExt;
            let s = app.state::<AppState>().settings.lock().unwrap().clone();
            let ext = if s.capture_format == "jpg" { "jpg" } else { "png" };
            let picked = app
                .dialog()
                .file()
                .set_title("Salvar captura")
                .set_directory(&s.capture_dir)
                .set_file_name(file_name(ext))
                .add_filter("PNG", &["png"])
                .add_filter("JPEG", &["jpg", "jpeg"])
                .blocking_save_file();
            if keep {
                // Board: comes back after the dialog.
                app.state::<AppState>().editor_shown.store(false, Ordering::SeqCst);
                reveal_editor(app);
            }
            let Some(path) = picked.and_then(|p| p.into_path().ok()) else { return Ok("cancel".into()) };
            let is_jpg = path.extension().map(|e| e.eq_ignore_ascii_case("jpg") || e.eq_ignore_ascii_case("jpeg")).unwrap_or(false);
            let (bytes, _) = encode(&png, if is_jpg { "jpg" } else { "png" })?;
            std::fs::write(&path, bytes).map_err(|e| e.to_string())?;
            ui::toast_path(app, "Captura salva", &path);
            Ok(path.to_string_lossy().into())
        }
        "pin" => {
            ui::open_pin(app, png, pin_at);
            Ok("ok".into())
        }
        "ocr" => {
            let text = platform::ocr_png(&png)?;
            let text = text.trim().to_string();
            if text.is_empty() {
                ui::toast(app, "Nenhum texto encontrado na área");
            } else {
                crate::set_clipboard_text(app, &text)?;
                ui::toast(app, &format!("Texto copiado ({} caracteres)", text.chars().count()));
            }
            Ok(text)
        }
        other => Err(format!("ação desconhecida: {other}")),
    }
}
