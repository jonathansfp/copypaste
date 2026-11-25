//! Global shortcuts and the actions they trigger (also reachable from the tray and the command line).

use std::collections::BTreeMap;
use tauri::{AppHandle, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

use crate::{capture, dictation, settings::ACTIONS, ui, AppState};

/// Runs an action. Capture work goes to a separate thread so the event loop never stalls.
pub fn run(app: &AppHandle, action: &str) {
    crate::diag(app, &format!("ação {action}"));
    match action {
        "clipboard" => ui::toggle_history(app),
        "dictate" => dictation::toggle(app, dictation::Mode::Dictate),
        "voiceCommand" => dictation::toggle(app, dictation::Mode::Command),
        "captureArea" | "captureScreen" | "board" | "record" => {
            let mode = match action {
                "captureArea" => "area",
                "captureScreen" => "screen",
                "board" => "board",
                _ => "record",
            };
            let app = app.clone();
            std::thread::spawn(move || capture::start(&app, mode));
        }
        _ => {}
    }
}

/// Command-line arguments (`copypaste --capture-area`): on Wayland, system shortcuts can call them.
pub fn from_args(app: &AppHandle, args: &[String]) -> bool {
    let map = [
        ("--history", "clipboard"),
        ("--capture-area", "captureArea"),
        ("--capture-screen", "captureScreen"),
        ("--board", "board"),
        ("--record", "record"),
        ("--dictate", "dictate"),
        ("--voice-command", "voiceCommand"),
    ];
    let mut any = false;
    for a in args {
        if let Some((_, action)) = map.iter().find(|(flag, _)| flag == a) {
            run(app, action);
            any = true;
        }
        if a == "--settings" {
            ui::open_settings(app, None);
            any = true;
        }
    }
    any
}

/// (Re)registers all shortcuts; returns the errors per action (shortcut in use by another app, etc.).
pub fn register_all(app: &AppHandle) -> BTreeMap<String, String> {
    let gs = app.global_shortcut();
    let _ = gs.unregister_all();
    let hotkeys = app.state::<AppState>().settings.lock().unwrap().hotkeys.clone();
    let mut errors = BTreeMap::new();
    for action in ACTIONS {
        let accel = hotkeys.get(action).cloned().unwrap_or_default();
        if accel.trim().is_empty() {
            continue;
        }
        let shortcut: Shortcut = match accel.parse() {
            Ok(s) => s,
            Err(e) => {
                errors.insert(action.to_string(), format!("Atalho inválido: {e}"));
                continue;
            }
        };
        let act = action.to_string();
        let res = gs.on_shortcut(shortcut, move |app, _sc, ev| {
            if ev.state == ShortcutState::Pressed {
                match act.as_str() {
                    "dictate" => dictation::key_down(app, dictation::Mode::Dictate),
                    "voiceCommand" => dictation::key_down(app, dictation::Mode::Command),
                    _ => run(app, &act),
                }
            } else if act == "dictate" {
                dictation::key_up(app, dictation::Mode::Dictate);
            } else if act == "voiceCommand" {
                dictation::key_up(app, dictation::Mode::Command);
            }
        });
        if let Err(e) = res {
            errors.insert(action.to_string(), format!("Não foi possível registrar (talvez outro app já use esse atalho): {e}"));
        }
    }
    *app.state::<AppState>().hotkey_errors.lock().unwrap() = errors.clone();
    errors
}

pub fn suspend(app: &AppHandle) {
    let _ = app.global_shortcut().unregister_all();
}
