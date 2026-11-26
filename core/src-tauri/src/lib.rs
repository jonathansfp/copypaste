//! CopyPaste for Windows and Linux: shared core (Rust + system webview).
//! The native code of each system lives in `windows/` and `linux/` at the root of the repository.

mod actions;
mod ai;
mod capture;
mod dictation;
mod local;
mod history;
mod i18n;
mod platform;
mod recorder;
mod settings;
mod tray;
mod ui;
mod updates;

use serde::Serialize;
use std::collections::BTreeMap;
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::http::{Response, StatusCode};
use tauri::ipc::{InvokeBody, Request};
use tauri::{AppHandle, Emitter, Manager, RunEvent, State, WindowEvent};

use history::{ClipSig, ClipView, History};
use i18n::t;
use settings::Settings;

/// Voluntary donation key (Pix) to support the project.
pub const PIX_KEY: &str = "586cb2d1-8a6e-4bed-8cdb-1f413e8f3e38";

pub struct Paths {
    pub data: PathBuf,
    pub settings: PathBuf,
    pub pins: PathBuf,
    pub ai_keys: PathBuf,
}

pub struct AppState {
    pub settings: Mutex<Settings>,
    pub history: Mutex<History>,
    pub history_dirty: AtomicBool,
    /// A single clipboard for the whole app: on Linux the copied content lives as long as it does.
    pub clipboard: Mutex<Option<arboard::Clipboard>>,
    pub sig: Mutex<ClipSig>,
    pub frozen: Mutex<Option<capture::Frozen>>,
    pub recorder: Mutex<Option<recorder::Recording>>,
    pub hotkey_errors: Mutex<BTreeMap<String, String>>,
    pub toast_gen: AtomicU64,
    pub editor_gen: AtomicU64,
    pub editor_shown: AtomicBool,
    pub pin_seq: AtomicU64,
    /// provider → API key of the user's own AI.
    pub ai_keys: Mutex<BTreeMap<String, String>>,
    pub paths: Paths,
}

/// Small diagnostic log (data/diagnostico.log), capped at 200 KB.
pub fn diag(app: &AppHandle, msg: &str) {
    let Some(state) = app.try_state::<AppState>() else { return };
    let file = state.paths.data.join("diagnostico.log");
    if std::fs::metadata(&file).map(|m| m.len() > 200_000).unwrap_or(false) {
        let _ = std::fs::remove_file(&file);
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&file) {
        let _ = writeln!(f, "{} {msg}", chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f"));
    }
}

pub fn set_clipboard_text(app: &AppHandle, text: &str) -> Result<(), String> {
    let state = app.state::<AppState>();
    state.sig.lock().unwrap().last_hash = history::hash_text(text);
    let mut cb = state.clipboard.lock().unwrap();
    let cb = cb.as_mut().ok_or(t("área de transferência indisponível"))?;
    cb.set_text(text.to_string()).map_err(|e| e.to_string())
}

pub fn set_clipboard_image(app: &AppHandle, w: usize, h: usize, rgba: Vec<u8>) -> Result<(), String> {
    let state = app.state::<AppState>();
    let mut cb = state.clipboard.lock().unwrap();
    let cb = cb.as_mut().ok_or(t("área de transferência indisponível"))?;
    cb.set_image(arboard::ImageData { width: w, height: h, bytes: rgba.into() }).map_err(|e| e.to_string())
}

// ───────────────────────────── Commands ─────────────────────────────

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SettingsView {
    settings: Settings,
    errors: BTreeMap<String, String>,
    defaults: BTreeMap<String, String>,
    system: String,
    notes: Vec<String>,
    version: String,
    pix_key: String,
    ffmpeg: bool,
    ai_connected: Vec<String>,
    local: local::Status,
}

#[tauri::command]
fn get_settings(app: AppHandle, state: State<AppState>) -> SettingsView {
    SettingsView {
        settings: state.settings.lock().unwrap().clone(),
        errors: state.hotkey_errors.lock().unwrap().clone(),
        defaults: settings::ACTIONS.iter().map(|a| (a.to_string(), settings::default_hotkey(a).to_string())).collect(),
        system: platform::SYSTEM.into(),
        notes: platform::notes().iter().map(|n| t(n).to_string()).collect(),
        version: app.package_info().version.to_string(),
        pix_key: PIX_KEY.into(),
        ffmpeg: recorder::find_ffmpeg().is_some(),
        ai_connected: state.ai_keys.lock().unwrap().keys().cloned().collect(),
        local: local::status(&app),
    }
}

#[tauri::command]
fn save_settings(app: AppHandle, state: State<AppState>, settings: Settings) -> BTreeMap<String, String> {
    let autostart = settings.autostart;
    let language_changed = {
        let mut s = state.settings.lock().unwrap();
        let changed = s.language != settings.language;
        // Model lists are kept by the app (ai_connect), not by the settings page.
        let (lists, stt) = (s.ai_model_lists.clone(), s.ai_stt_lists.clone());
        *s = settings;
        s.ai_model_lists = lists;
        s.ai_stt_lists = stt;
        s.history_limit = s.history_limit.clamp(20, 5000);
        s.record_fps = s.record_fps.clamp(10, 60);
        if !["auto", "pt", "en", "es"].contains(&s.language.as_str()) {
            s.language = "auto".into();
        }
        s.save(&state.paths.settings);
        let limit = s.history_limit;
        state.history.lock().unwrap().trim(limit);
        if changed {
            i18n::set(&s.language);
        }
        changed
    };
    if language_changed {
        // Open pages redraw themselves in the new language (the tray menu is rebuilt below).
        ui::retitle(&app);
        let _ = app.emit("language-changed", i18n::current());
    }
    apply_autostart(&app, autostart);
    let errors = actions::register_all(&app);
    tray::refresh(&app);
    errors
}

fn apply_autostart(app: &AppHandle, on: bool) {
    // In development on the Mac it never touches login items.
    if cfg!(target_os = "macos") {
        return;
    }
    use tauri_plugin_autostart::ManagerExt;
    let al = app.autolaunch();
    let enabled = al.is_enabled().unwrap_or(false);
    if on && !enabled {
        let _ = al.enable();
    } else if !on && enabled {
        let _ = al.disable();
    }
}

/// Language of the interface in use: "pt", "en" or "es".
#[tauri::command]
fn get_language() -> &'static str {
    i18n::current()
}

#[tauri::command]
fn suspend_hotkeys(app: AppHandle) {
    actions::suspend(&app);
}

#[tauri::command]
fn resume_hotkeys(app: AppHandle) -> BTreeMap<String, String> {
    actions::register_all(&app)
}

#[tauri::command]
fn history_list(state: State<AppState>) -> Vec<ClipView> {
    state.history.lock().unwrap().views()
}

/// Puts the item in the clipboard and, if `paste`, pastes it into the app that was in front.
#[tauri::command]
async fn history_use(app: AppHandle, id: String, paste: bool) -> Result<String, String> {
    let state = app.state::<AppState>();
    let item = state.history.lock().unwrap().items.iter().find(|i| i.id == id).cloned().ok_or(t("item não encontrado"))?;
    if let Some(text) = &item.text {
        set_clipboard_text(&app, text)?;
    } else if let Some(file) = &item.image {
        let path = state.history.lock().unwrap().images.join(file);
        let img = image::open(&path).map_err(|e| e.to_string())?.to_rgba8();
        state.sig.lock().unwrap().last_hash = item.hash.clone();
        set_clipboard_image(&app, img.width() as usize, img.height() as usize, img.into_raw())?;
    }
    {
        let mut h = state.history.lock().unwrap();
        if let Some(pos) = h.items.iter().position(|i| i.id == id) {
            let mut it = h.items.remove(pos);
            it.date = history::now_ms();
            it.uses += 1;
            h.items.insert(0, it);
        }
    }
    state.history_dirty.store(true, Ordering::SeqCst);
    let _ = app.emit("history-changed", ());
    ui::hide_history(&app);
    if paste {
        if let Err(msg) = platform::restore_and_paste() {
            ui::toast(&app, &i18n::msg(&msg));
            return Ok("copied".into());
        }
        return Ok("pasted".into());
    }
    ui::toast(&app, t("Copiado"));
    Ok("copied".into())
}

#[tauri::command]
fn history_pin(app: AppHandle, state: State<AppState>, id: String) {
    if let Some(i) = state.history.lock().unwrap().items.iter_mut().find(|i| i.id == id) {
        i.pinned = !i.pinned;
    }
    state.history_dirty.store(true, Ordering::SeqCst);
    let _ = app.emit("history-changed", ());
}

#[tauri::command]
fn history_delete(app: AppHandle, state: State<AppState>, id: String) {
    state.history.lock().unwrap().remove(&id);
    state.history_dirty.store(true, Ordering::SeqCst);
    let _ = app.emit("history-changed", ());
}

#[tauri::command]
fn history_clear(app: AppHandle, state: State<AppState>, keep_pinned: bool) {
    state.history.lock().unwrap().clear(keep_pinned);
    state.sig.lock().unwrap().last_hash.clear();
    state.history_dirty.store(true, Ordering::SeqCst);
    let _ = app.emit("history-changed", ());
}

#[tauri::command]
fn hide_history(app: AppHandle) {
    ui::hide_history(&app);
}

/// The editor sends the final PNG as the raw body; the action goes in the `x-action` header.
#[tauri::command]
async fn editor_finish(app: AppHandle, request: Request<'_>) -> Result<String, String> {
    let InvokeBody::Raw(png) = request.body() else { return Err(t("corpo inválido").into()) };
    let h = request.headers();
    let action = h.get("x-action").and_then(|v| v.to_str().ok()).unwrap_or("copy").to_string();
    let num = |k: &str| h.get(k).and_then(|v| v.to_str().ok()).and_then(|v| v.parse::<f64>().ok());
    let pin_at = match (num("x-pin-x"), num("x-pin-y")) {
        (Some(x), Some(y)) => Some((x, y)),
        _ => None,
    };
    let keep = h.get("x-keep").and_then(|v| v.to_str().ok()) == Some("1");
    let png = png.clone();
    let res = capture::finish(&app, &action, png, pin_at, keep).map_err(|e| i18n::msg(&e));
    if let Err(e) = &res {
        ui::toast(&app, e);
    }
    res
}

#[tauri::command]
fn editor_ready(app: AppHandle) {
    capture::reveal_editor(&app);
}

#[tauri::command]
fn editor_close(app: AppHandle) {
    capture::hide_editor(&app);
}

#[tauri::command]
fn start_recording(app: AppHandle, x: u32, y: u32, w: u32, h: u32, mic: bool, system_audio: bool) -> Result<(), String> {
    capture::hide_editor(&app);
    {
        let state = app.state::<AppState>();
        let mut s = state.settings.lock().unwrap();
        if s.record_mic != mic || s.record_system_audio != system_audio {
            s.record_mic = mic;
            s.record_system_audio = system_audio;
            s.save(&state.paths.settings);
        }
    }
    let r = recorder::start(&app, x, y, w, h, mic, system_audio);
    if let Err(e) = &r {
        ui::toast(&app, e);
    }
    r
}

#[tauri::command]
fn stop_recording(app: AppHandle) {
    recorder::stop(&app);
}

#[tauri::command]
fn recording_elapsed(state: State<AppState>) -> f64 {
    state.recorder.lock().unwrap().as_ref().map(|r| r.started.elapsed().as_secs_f64()).unwrap_or(-1.0)
}

#[tauri::command]
fn copy_text(app: AppHandle, text: String, toast: Option<String>) -> Result<(), String> {
    set_clipboard_text(&app, &text)?;
    if let Some(t) = toast {
        ui::toast(&app, &t);
    }
    Ok(())
}

#[tauri::command]
fn clipboard_text(state: State<AppState>) -> Option<String> {
    state.clipboard.lock().unwrap().as_mut()?.get_text().ok()
}

/// Image from the clipboard as PNG (empty if there is none): used to paste into the board.
#[tauri::command]
fn clipboard_image(state: State<AppState>) -> tauri::ipc::Response {
    let img = state.clipboard.lock().unwrap().as_mut().and_then(|c| c.get_image().ok());
    let mut out = vec![];
    if let Some(img) = img {
        if let Some(buf) = image::RgbaImage::from_raw(img.width as u32, img.height as u32, img.bytes.into_owned()) {
            let _ = buf.write_to(&mut std::io::Cursor::new(&mut out), image::ImageFormat::Png);
        }
    }
    tauri::ipc::Response::new(out)
}

#[tauri::command]
fn reveal(path: String) {
    platform::reveal(std::path::Path::new(&path));
}

#[tauri::command]
async fn choose_folder(app: AppHandle, current: String) -> Option<String> {
    use tauri_plugin_dialog::DialogExt;
    app.dialog()
        .file()
        .set_directory(current)
        .blocking_pick_folder()
        .and_then(|p| p.into_path().ok())
        .map(|p| p.to_string_lossy().into_owned())
}

#[tauri::command]
fn open_settings(app: AppHandle, tab: Option<String>) {
    ui::open_settings(&app, tab.as_deref());
}

#[tauri::command]
fn toast(app: AppHandle, text: String) {
    ui::toast(&app, &text);
}

/// Validates the key by listing the provider's models, then saves it (only on this computer).
#[tauri::command]
async fn ai_connect(app: AppHandle, provider: String, key: String) -> Result<Settings, String> {
    let key = key.trim().to_string();
    if !ai::PROVIDERS.contains(&provider.as_str()) {
        return Err(t("provedor desconhecido").into());
    }
    if key.is_empty() {
        return Err(t("Cole a chave da API.").into());
    }
    let p = provider.clone();
    let k = key.clone();
    let list = tauri::async_runtime::spawn_blocking(move || ai::list_models(&p, &k)).await.map_err(|e| e.to_string())??;
    if list.chat.is_empty() {
        return Err(t("A chave funciona, mas nenhum modelo de texto está disponível nela.").into());
    }
    let state = app.state::<AppState>();
    {
        let mut keys = state.ai_keys.lock().unwrap();
        keys.insert(provider.clone(), key);
        ai::save_keys(&state.paths.ai_keys, &keys);
    }
    let mut s = state.settings.lock().unwrap();
    if s.ai_models.get(&provider).map(|m| !list.chat.contains(m)).unwrap_or(true) {
        if let Some(m) = ai::preferred_chat(&provider, &list.chat) {
            s.ai_models.insert(provider.clone(), m);
        }
    }
    if s.ai_stt_models.get(&provider).map(|m| !list.transcription.contains(m)).unwrap_or(true) {
        if let Some(m) = ai::preferred_stt(&provider, &list.transcription) {
            s.ai_stt_models.insert(provider.clone(), m);
        }
    }
    s.ai_model_lists.insert(provider.clone(), list.chat);
    s.ai_stt_lists.insert(provider.clone(), list.transcription);
    // The local AI is the default only while no AI of the user's own is connected.
    if s.dict_polish.is_empty() || s.dict_polish == "local" {
        s.dict_polish = provider.clone();
    }
    let has_engine = state.ai_keys.lock().unwrap().contains_key(&s.dict_engine);
    if !has_engine && s.dict_engine != "local" && (provider == "openai" || provider == "gemini") {
        s.dict_engine = provider.clone();
    }
    s.save(&state.paths.settings);
    Ok(s.clone())
}

#[tauri::command]
fn ai_disconnect(state: State<AppState>, provider: String) -> Settings {
    let mut keys = state.ai_keys.lock().unwrap();
    keys.remove(&provider);
    ai::save_keys(&state.paths.ai_keys, &keys);
    let mut s = state.settings.lock().unwrap();
    if s.dict_polish == provider {
        s.dict_polish = keys.keys().next().cloned().unwrap_or_else(|| "local".into());
    }
    s.save(&state.paths.settings);
    s.clone()
}

#[tauri::command]
fn local_status(app: AppHandle) -> local::Status {
    local::status(&app)
}

#[tauri::command]
fn local_install(app: AppHandle) {
    local::install(&app);
}

#[tauri::command]
fn local_cancel() {
    local::cancel_install();
}

#[tauri::command]
fn local_remove(app: AppHandle) -> Settings {
    local::remove(&app);
    app.state::<AppState>().settings.lock().unwrap().clone()
}

#[tauri::command]
fn check_updates(app: AppHandle) {
    std::thread::spawn(move || updates::check(&app, true));
}

#[tauri::command]
fn dictation_finish() {
    dictation::finish();
}

#[tauri::command]
fn dictation_cancel() {
    dictation::cancel();
}

#[tauri::command]
fn dictation_start(app: AppHandle, command: bool) {
    dictation::start(&app, if command { dictation::Mode::Command } else { dictation::Mode::Dictate }, false);
}

#[tauri::command]
fn log(app: AppHandle, msg: String) {
    diag(&app, &format!("[ui] {msg}"));
}

// ───────────────────────────── Protocol ─────────────────────────────

/// `cpframe://`: frozen screen (raw RGBA), history images and pinned images.
fn protocol(app: &AppHandle, path: &str) -> Response<Vec<u8>> {
    let not_found = || Response::builder().status(StatusCode::NOT_FOUND).header("Access-Control-Allow-Origin", "*").body(vec![]).unwrap();
    let safe = |name: &str| !name.is_empty() && !name.contains("..") && !name.contains('/') && !name.contains('\\');
    let state = app.state::<AppState>();
    if path.starts_with("/frame") {
        let Some((w, h, rgba)) = capture::frame_bytes(app) else { return not_found() };
        return Response::builder()
            .header("Content-Type", "application/octet-stream")
            .header("Access-Control-Allow-Origin", "*")
            .header("Access-Control-Expose-Headers", "x-width, x-height")
            .header("Cache-Control", "no-store")
            .header("x-width", w.to_string())
            .header("x-height", h.to_string())
            .body(rgba.as_ref().clone())
            .unwrap();
    }
    let file = if let Some(name) = path.strip_prefix("/img/") {
        safe(name).then(|| state.history.lock().unwrap().images.join(name))
    } else if let Some(name) = path.strip_prefix("/pin/") {
        safe(name).then(|| state.paths.pins.join(format!("{name}.png")))
    } else {
        None
    };
    match file.and_then(|f| std::fs::read(f).ok()) {
        Some(bytes) => Response::builder()
            .header("Content-Type", "image/png")
            .header("Access-Control-Allow-Origin", "*")
            .header("Cache-Control", "max-age=31536000")
            .body(bytes)
            .unwrap(),
        None => not_found(),
    }
}

// ───────────────────────────── App ─────────────────────────────

pub fn run() {
    platform::prepare_env();
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
            // A second launch: runs the action of the arguments or opens the settings.
            if !actions::from_args(app, &args) {
                ui::open_settings(app, None);
            }
        }))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--hidden"])))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .register_asynchronous_uri_scheme_protocol("cpframe", |ctx, request, responder| {
            let app = ctx.app_handle().clone();
            let path = request.uri().path().to_string();
            std::thread::spawn(move || responder.respond(protocol(&app, &path)));
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            get_language,
            suspend_hotkeys,
            resume_hotkeys,
            history_list,
            history_use,
            history_pin,
            history_delete,
            history_clear,
            hide_history,
            editor_finish,
            editor_ready,
            editor_close,
            start_recording,
            stop_recording,
            recording_elapsed,
            copy_text,
            clipboard_text,
            clipboard_image,
            reveal,
            choose_folder,
            open_settings,
            toast,
            log,
            ai_connect,
            ai_disconnect,
            dictation_finish,
            dictation_cancel,
            dictation_start,
            local_status,
            local_install,
            local_cancel,
            local_remove,
            check_updates,
        ])
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let handle = app.handle().clone();
            let config = app.path().app_config_dir()?;
            let data = app.path().app_data_dir()?;
            let pins = data.join("pins");
            std::fs::create_dir_all(&config)?;
            std::fs::create_dir_all(&pins)?;
            // Pinned images from previous sessions are temporary.
            if let Ok(rd) = std::fs::read_dir(&pins) {
                for e in rd.flatten() {
                    let _ = std::fs::remove_file(e.path());
                }
            }
            let settings_path = config.join("settings.json");
            let settings = Settings::load(&settings_path);
            i18n::set(&settings.language);
            let first_run = !settings.first_run_done;
            app.manage(AppState {
                settings: Mutex::new(settings),
                history: Mutex::new(History::load(&data)),
                history_dirty: AtomicBool::new(false),
                clipboard: Mutex::new(arboard::Clipboard::new().ok()),
                sig: Mutex::new(ClipSig::default()),
                frozen: Mutex::new(None),
                recorder: Mutex::new(None),
                hotkey_errors: Mutex::new(BTreeMap::new()),
                toast_gen: AtomicU64::new(0),
                editor_gen: AtomicU64::new(0),
                editor_shown: AtomicBool::new(true),
                pin_seq: AtomicU64::new(0),
                ai_keys: Mutex::new(ai::load_keys(&config.join("ai-keys.json"))),
                paths: Paths { data, settings: settings_path, pins, ai_keys: config.join("ai-keys.json") },
            });
            diag(&handle, &format!("início — {} v{}", platform::SYSTEM, handle.package_info().version));

            ui::create_windows(&handle)?;
            tray::create(&handle)?;
            history::start_watcher(handle.clone());
            let errors = actions::register_all(&handle);
            for (a, e) in &errors {
                diag(&handle, &format!("atalho {a}: {e}"));
            }

            let manual_pending = {
                let state = handle.state::<AppState>();
                let mut s = state.settings.lock().unwrap();
                let pending = !s.manual_shown;
                if pending {
                    s.manual_shown = true;
                    s.save(&state.paths.settings);
                }
                pending
            };
            if first_run {
                let state = handle.state::<AppState>();
                let autostart = {
                    let mut s = state.settings.lock().unwrap();
                    s.first_run_done = true;
                    s.save(&state.paths.settings);
                    s.autostart
                };
                apply_autostart(&handle, autostart);
                // On a fresh install the manual below takes the place of the welcome tab.
                if !manual_pending {
                    ui::open_settings(&handle, Some("inicio"));
                }
            }
            if manual_pending {
                // The manual opens once by itself, so everyone learns the shortcuts (also those updating).
                let h = handle.clone();
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_secs(2));
                    ui::open_settings(&h, Some("manual"));
                });
            }
            updates::start(&handle);
            let args: Vec<String> = std::env::args().skip(1).collect();
            actions::from_args(&handle, &args);
            Ok(())
        })
        .on_window_event(|win, ev| match (win.label(), ev) {
            ("history", WindowEvent::Focused(false)) => {
                let _ = win.hide();
            }
            ("history" | "editor" | "toast", WindowEvent::CloseRequested { api, .. }) => {
                api.prevent_close();
                let _ = win.hide();
            }
            _ => {}
        })
        .build(tauri::generate_context!())
        .expect("falha ao iniciar o CopyPaste");

    app.run(|_app, ev| {
        if let RunEvent::Exit = ev {
            local::stop();
        }
        // Keeps running in the tray when the last window closes; quits only from the menu.
        if let RunEvent::ExitRequested { api, code, .. } = ev {
            if code.is_none() {
                api.prevent_exit();
            }
        }
    });
}
