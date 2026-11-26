//! Icon next to the clock (Windows) / in the panel (Linux) with the app menu.

use tauri::menu::{Menu, MenuBuilder, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager, Wry};

use crate::i18n::t;
use crate::{actions, recorder, AppState, PIX_KEY};

fn item(app: &AppHandle, id: &str, text: &str, accel: Option<String>) -> tauri::Result<MenuItem<Wry>> {
    // The shortcut appears to the right of the item (only as a hint: the global one is registered elsewhere).
    let accel = accel.filter(|a| !a.is_empty());
    MenuItem::with_id(app, id, text, true, accel.as_deref()).or_else(|_| MenuItem::with_id(app, id, text, true, None::<&str>))
}

fn build_menu(app: &AppHandle) -> tauri::Result<Menu<Wry>> {
    let s = app.state::<AppState>().settings.lock().unwrap().clone();
    let hk = |a: &str| s.hotkeys.get(a).cloned();
    let recording = recorder::is_recording(app);
    let mut m = MenuBuilder::new(app);
    if recording {
        m = m.item(&item(app, "record", t("■ Parar gravação"), hk("record"))?).item(&PredefinedMenuItem::separator(app)?);
    }
    m = m
        .item(&item(app, "clipboard", t("Abrir histórico"), hk("clipboard"))?)
        .item(&PredefinedMenuItem::separator(app)?)
        .item(&item(app, "captureArea", t("Capturar área ou janela"), hk("captureArea"))?)
        .item(&item(app, "captureScreen", t("Capturar tela inteira"), hk("captureScreen"))?)
        .item(&item(app, "board", t("Modo apresentação (quadro)"), hk("board"))?);
    if !recording {
        m = m.item(&item(app, "record", t("Gravar tela…"), hk("record"))?);
    }
    m = m
        .item(&item(app, "dictate", t("Ditado por voz"), hk("dictate"))?)
        .item(&item(app, "voiceCommand", t("Comando de voz"), hk("voiceCommand"))?);
    m.item(&PredefinedMenuItem::separator(app)?)
        .item(&MenuItem::with_id(app, "pause", t(if s.paused { "Retomar histórico" } else { "Pausar histórico" }), true, None::<&str>)?)
        .item(&MenuItem::with_id(app, "settings", t("Configurações…"), true, None::<&str>)?)
        .item(&MenuItem::with_id(app, "updates", t("Verificar atualizações…"), true, None::<&str>)?)
        .item(&MenuItem::with_id(app, "donate", t("Doar via Pix ♥"), true, None::<&str>)?)
        .item(&PredefinedMenuItem::separator(app)?)
        .item(&MenuItem::with_id(app, "quit", t("Sair do CopyPaste"), true, None::<&str>)?)
        .build()
}

pub fn create(app: &AppHandle) -> tauri::Result<()> {
    let menu = build_menu(app)?;
    let mut b = TrayIconBuilder::with_id("main")
        .tooltip("CopyPaste")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, ev| {
            let id = ev.id().as_ref().to_string();
            match id.as_str() {
                "quit" => app.exit(0),
                "settings" => crate::ui::open_settings(app, None),
                "updates" => {
                    let app = app.clone();
                    std::thread::spawn(move || crate::updates::check(&app, true));
                }
                "donate" => {
                    let _ = crate::set_clipboard_text(app, PIX_KEY);
                    crate::ui::open_settings(app, Some("apoie"));
                    crate::ui::toast(app, t("Chave Pix copiada — obrigado pelo apoio! ♥"));
                }
                "pause" => {
                    let st = app.state::<AppState>();
                    let paused = {
                        let mut s = st.settings.lock().unwrap();
                        s.paused = !s.paused;
                        s.save(&st.paths.settings);
                        s.paused
                    };
                    crate::ui::toast(app, t(if paused { "Histórico pausado" } else { "Histórico retomado" }));
                    refresh(app);
                }
                other => actions::run(app, other),
            }
        })
        .on_tray_icon_event(|tray, ev| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = ev {
                crate::ui::toggle_history(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        b = b.icon(icon.clone());
    }
    b.build(app)?;
    Ok(())
}

/// Rebuilds the menu (recording state, shortcuts, pause).
pub fn refresh(app: &AppHandle) {
    let app2 = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let (Some(tray), Ok(menu)) = (app2.tray_by_id("main"), build_menu(&app2)) {
            let _ = tray.set_menu(Some(menu));
            let tip = if recorder::is_recording(&app2) { t("CopyPaste — gravando") } else { "CopyPaste" };
            let _ = tray.set_tooltip(Some(tip));
        }
    });
}
