//! App windows. The history and the editor are created hidden at startup (already loaded),
//! so they open instantly when the shortcut is pressed.

use serde::Serialize;
use std::path::Path;
use std::sync::atomic::Ordering;
use std::time::Duration;
use tauri::{AppHandle, Emitter, LogicalSize, Manager, PhysicalPosition, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

use crate::i18n::t;
use crate::{platform, AppState};

fn builder<'a>(app: &'a AppHandle, label: &str, url: &str) -> WebviewWindowBuilder<'a, tauri::Wry, AppHandle> {
    WebviewWindowBuilder::new(app, label, WebviewUrl::App(url.into()))
}

pub fn create_windows(app: &AppHandle) -> tauri::Result<()> {
    builder(app, "history", "history.html")
        .title("CopyPaste")
        .inner_size(720.0, 500.0)
        .decorations(false)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        .shadow(true)
        .build()?;
    builder(app, "editor", "editor.html")
        .title(t("CopyPaste — captura"))
        .decorations(false)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        .shadow(false)
        .build()?;
    builder(app, "dictation", "dictation.html")
        .title(t("CopyPaste — ditado"))
        .inner_size(360.0, 64.0)
        .decorations(false)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .transparent(true)
        .focused(false)
        .focusable(false)
        .visible(false)
        .shadow(false)
        .build()?;
    builder(app, "toast", "toast.html")
        .title("CopyPaste")
        .inner_size(440.0, 64.0)
        .decorations(false)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .transparent(true)
        .focused(false)
        .focusable(false)
        .visible(false)
        .shadow(false)
        .build()?;
    Ok(())
}

/// Monitor where the mouse is (for positioning popups).
fn monitor_under_mouse(app: &AppHandle) -> Option<tauri::Monitor> {
    let c = app.cursor_position().ok()?;
    app.monitor_from_point(c.x, c.y).ok().flatten().or_else(|| app.primary_monitor().ok().flatten())
}

fn center_on_monitor(app: &AppHandle, win: &WebviewWindow, y_ratio: f64) {
    let Some(m) = monitor_under_mouse(app) else { return };
    let (Ok(size), pos, msize) = (win.outer_size(), m.position(), m.size()) else { return };
    let x = pos.x + (msize.width as i32 - size.width as i32) / 2;
    let y = pos.y + ((msize.height as f64 - size.height as f64) * y_ratio) as i32;
    let _ = win.set_position(PhysicalPosition::new(x, y));
}

pub fn toggle_history(app: &AppHandle) {
    let Some(win) = app.get_webview_window("history") else { return };
    if win.is_visible().unwrap_or(false) {
        let _ = win.hide();
        return;
    }
    platform::remember_foreground();
    center_on_monitor(app, &win, 0.32);
    let _ = win.emit("history-open", ());
    let _ = win.show();
    let _ = win.set_focus();
}

/// Window titles in the current language (after the language changes).
pub fn retitle(app: &AppHandle) {
    for (label, win) in app.webview_windows() {
        let title = match label.as_str() {
            "editor" => t("CopyPaste — captura"),
            "dictation" => t("CopyPaste — ditado"),
            "settings" => t("CopyPaste — Configurações"),
            "recbar" => t("CopyPaste — gravando"),
            l if l.starts_with("pin-") => t("CopyPaste — imagem fixada"),
            _ => continue,
        };
        let _ = win.set_title(title);
    }
}

pub fn hide_history(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("history") {
        let _ = win.hide();
    }
}

pub fn open_settings(app: &AppHandle, tab: Option<&str>) {
    if let Some(win) = app.get_webview_window("settings") {
        let _ = win.emit("settings-tab", tab.unwrap_or(""));
        let _ = win.unminimize();
        let _ = win.show();
        let _ = win.set_focus();
        return;
    }
    let url = match tab {
        Some(t) => format!("settings.html#{t}"),
        None => "settings.html".into(),
    };
    let app = app.clone();
    // Windows are created outside the main thread (avoids blocking the event loop on Windows).
    std::thread::spawn(move || {
        let _ = builder(&app, "settings", &url)
            .title(t("CopyPaste — Configurações"))
            .inner_size(760.0, 680.0)
            .min_inner_size(640.0, 520.0)
            .center()
            .build();
    });
}

#[derive(Serialize, Clone)]
struct ToastMsg {
    text: String,
    path: Option<String>,
}

pub fn toast(app: &AppHandle, text: &str) {
    show_toast(app, text, None);
}

pub fn toast_path(app: &AppHandle, text: &str, path: &Path) {
    show_toast(app, text, Some(path.to_string_lossy().into_owned()));
}

fn show_toast(app: &AppHandle, text: &str, path: Option<String>) {
    let Some(win) = app.get_webview_window("toast") else { return };
    let state = app.state::<AppState>();
    let gen = state.toast_gen.fetch_add(1, Ordering::SeqCst) + 1;
    let long = text.chars().count() > 60;
    let _ = win.set_size(LogicalSize::new(if long { 620.0 } else { 440.0 }, if long { 88.0 } else { 64.0 }));
    if let Some(m) = monitor_under_mouse(app) {
        if let Ok(size) = win.outer_size() {
            let x = m.position().x + (m.size().width as i32 - size.width as i32) / 2;
            let y = m.position().y + m.size().height as i32 - size.height as i32 - (90.0 * m.scale_factor()) as i32;
            let _ = win.set_position(PhysicalPosition::new(x, y));
        }
    }
    let _ = win.emit("toast", ToastMsg { text: text.into(), path });
    let _ = win.set_ignore_cursor_events(true);
    let _ = win.show();
    let app = app.clone();
    let secs = if long { 5.0 } else { 1.8 };
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs_f64(secs));
        if app.state::<AppState>().toast_gen.load(Ordering::SeqCst) == gen {
            if let Some(w) = app.get_webview_window("toast") {
                let _ = w.hide();
            }
        }
    });
}

/// Floating image ("pinned" on the screen), like a sticky note that stays above everything.
pub fn open_pin(app: &AppHandle, png: Vec<u8>, at: Option<(f64, f64)>) {
    let state = app.state::<AppState>();
    let n = state.pin_seq.fetch_add(1, Ordering::SeqCst) + 1;
    let file = state.paths.pins.join(format!("{n}.png"));
    if std::fs::write(&file, &png).is_err() {
        return;
    }
    let (w, h) = image::load_from_memory(&png).map(|i| (i.width() as f64, i.height() as f64)).unwrap_or((400.0, 300.0));
    let scale = monitor_under_mouse(app).map(|m| m.scale_factor()).unwrap_or(1.0);
    let (lw, lh) = ((w / scale).max(40.0), (h / scale).max(30.0));
    let app = app.clone();
    std::thread::spawn(move || {
        let mut b = builder(&app, &format!("pin-{n}"), &format!("pin.html?n={n}&w={lw}&h={lh}"))
            .title(t("CopyPaste — imagem fixada"))
            .inner_size(lw, lh)
            .decorations(false)
            .resizable(true)
            .always_on_top(true)
            .skip_taskbar(true)
            .transparent(true)
            .shadow(true);
        if let Some((x, y)) = at {
            b = b.position(x, y);
        }
        let _ = b.build();
    });
}

pub fn show_recbar(app: &AppHandle, mon_x: i32, mon_y: i32, x: u32, y: u32, w: u32, h: u32) {
    let app = app.clone();
    std::thread::spawn(move || {
        let win = match app.get_webview_window("recbar") {
            Some(w) => w,
            None => match builder(&app, "recbar", "recbar.html")
                .title(t("CopyPaste — gravando"))
                .inner_size(236.0, 44.0)
                .decorations(false)
                .resizable(false)
                .always_on_top(true)
                .skip_taskbar(true)
                .transparent(true)
                .focused(false)
                .shadow(false)
                .visible(false)
                .build()
            {
                Ok(w) => w,
                Err(_) => return,
            },
        };
        #[cfg(windows)]
        if let Ok(hwnd) = win.hwnd() {
            platform::exclude_from_capture(hwnd.0 as isize);
        }
        // Above the recorded area when there is room; otherwise below it, or in the top corner.
        let size = win.outer_size().unwrap_or(tauri::PhysicalSize::new(236, 44));
        let (bw, bh) = (size.width as i32, size.height as i32);
        let cx = mon_x + x as i32 + w as i32 / 2 - bw / 2;
        let above = mon_y + y as i32 - bh - 8;
        let mon_h = app
            .monitor_from_point(mon_x as f64 + 1.0, mon_y as f64 + 1.0)
            .ok()
            .flatten()
            .map(|m| m.size().height as i32)
            .unwrap_or(1080);
        let below = mon_y + (y + h) as i32 + 8;
        let pos = if y as i32 >= bh + 8 {
            PhysicalPosition::new(cx, above)
        } else if (y + h) as i32 + bh + 8 <= mon_h {
            PhysicalPosition::new(cx, below)
        } else {
            PhysicalPosition::new(mon_x + 12, mon_y + 12)
        };
        let _ = win.set_position(pos);
        let _ = win.emit("recbar-start", ());
        let _ = win.show();
    });
}

pub fn hide_recbar(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("recbar") {
        let _ = w.hide();
    }
}
