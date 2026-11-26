//! Once a week, asks GitHub for the latest release; if there is a newer version, offers to download it.

use std::time::Duration;
use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_opener::OpenerExt;

use crate::AppState;

const API: &str = "https://api.github.com/repos/jonathansfp/copypaste/releases/latest";
const WEEK_MS: i64 = 7 * 24 * 3600 * 1000;

fn download_url() -> &'static str {
    if cfg!(windows) {
        "https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Windows-Setup.exe"
    } else {
        "https://jonathansfp.github.io/copypaste/#download"
    }
}

/// Checks at start-up if a week has passed, then every few hours while the app runs.
pub fn start(app: &AppHandle) {
    let app = app.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(20));
        let last = app.state::<AppState>().settings.lock().unwrap().last_update_check;
        if crate::history::now_ms() - last > WEEK_MS {
            check(&app, false);
        }
        std::thread::sleep(Duration::from_secs(6 * 3600));
    });
}

fn newer(a: &str, b: &str) -> bool {
    let pa: Vec<u64> = a.split('.').map(|x| x.parse().unwrap_or(0)).collect();
    let pb: Vec<u64> = b.split('.').map(|x| x.parse().unwrap_or(0)).collect();
    for i in 0..pa.len().max(pb.len()) {
        let (x, y) = (pa.get(i).copied().unwrap_or(0), pb.get(i).copied().unwrap_or(0));
        if x != y {
            return x > y;
        }
    }
    false
}

pub fn check(app: &AppHandle, manual: bool) {
    let current = app.package_info().version.to_string();
    let res = crate::ai::agent_builder()
        .timeout(Duration::from_secs(20))
        .build()
        .get(API)
        .set("Accept", "application/vnd.github+json")
        .set("User-Agent", "CopyPaste")
        .call()
        .ok()
        .and_then(|r| r.into_json::<serde_json::Value>().ok());
    let Some(tag) = res.as_ref().and_then(|v| v.get("tag_name")).and_then(|t| t.as_str()).map(|t| t.trim_start_matches(['v', 'V']).to_string()) else {
        crate::diag(app, "atualização: não consegui verificar");
        if manual {
            crate::ui::toast(app, "Não consegui verificar atualizações agora. Confira a internet.");
        }
        return;
    };
    {
        let st = app.state::<AppState>();
        let mut s = st.settings.lock().unwrap();
        s.last_update_check = crate::history::now_ms();
        s.save(&st.paths.settings);
    }
    crate::diag(app, &format!("atualização: atual {current}, mais recente {tag}"));
    if !newer(&tag, &current) {
        if manual {
            crate::ui::toast(app, &format!("Você já tem a versão mais recente ({current})"));
        }
        return;
    }
    let how = if cfg!(windows) {
        "Baixe o instalador e abra: ele substitui a versão atual e mantém o seu histórico e as configurações."
    } else {
        "Baixe o pacote do seu sistema (.deb, .rpm ou AppImage) e instale por cima: o histórico e as configurações são mantidos."
    };
    let app2 = app.clone();
    app.dialog()
        .message(format!("Você está na {current}. {how}"))
        .title(format!("Nova versão do CopyPaste: {tag}"))
        .kind(MessageDialogKind::Info)
        .buttons(MessageDialogButtons::OkCancelCustom("Baixar atualização".into(), "Depois".into()))
        .show(move |ok| {
            if ok {
                let _ = app2.opener().open_url(download_url(), None::<&str>);
            }
        });
}
