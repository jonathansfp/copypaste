//! Once a week, asks GitHub for the latest release; if there is a newer version, offers to download it.

use std::time::Duration;
use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_opener::OpenerExt;

use crate::i18n::{t, tf};
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
            crate::ui::toast(app, t("Não consegui verificar atualizações agora. Confira a internet."));
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
            crate::ui::toast(app, &tf("Você já tem a versão mais recente ({})", &[&current]));
        }
        return;
    }
    let asset = res.as_ref().and_then(auto_asset);
    let how = if asset.is_some() {
        t("Clique em Atualizar agora: o CopyPaste baixa a nova versão, instala e abre de novo sozinho. O histórico e as configurações são mantidos.")
    } else if cfg!(windows) {
        t("Baixe o instalador e abra: ele substitui a versão atual e mantém o seu histórico e as configurações.")
    } else {
        t("Baixe o pacote do seu sistema (.deb, .rpm ou AppImage) e instale por cima: o histórico e as configurações são mantidos.")
    };
    let yes = if asset.is_some() { t("Atualizar agora") } else { t("Baixar atualização") };
    let app2 = app.clone();
    app.dialog()
        .message(tf("Você está na {}. {}", &[&current, &how]))
        .title(tf("Nova versão do CopyPaste: {}", &[&tag]))
        .kind(MessageDialogKind::Info)
        .buttons(MessageDialogButtons::OkCancelCustom(yes.into(), t("Depois").into()))
        .show(move |ok| {
            if !ok {
                return;
            }
            match asset {
                Some((url, size)) => {
                    std::thread::spawn(move || {
                        if let Err(e) = install(&app2, &url, size, &tag) {
                            crate::diag(&app2, &format!("atualização: falhou: {e}"));
                            crate::ui::toast(&app2, &tf("Não consegui atualizar sozinho ({}). Abrindo o download.", &[&e]));
                            let _ = app2.opener().open_url(download_url(), None::<&str>);
                        }
                    });
                }
                None => {
                    let _ = app2.opener().open_url(download_url(), None::<&str>);
                }
            }
        });
}

/// The release file this copy can install by itself: the Windows installer, or the AppImage when
/// running as one. `.deb`/`.rpm` need the system's package manager, so those go to the download page.
fn auto_asset(release: &serde_json::Value) -> Option<(String, u64)> {
    let want = if cfg!(windows) {
        "CopyPaste-Windows-Setup.exe"
    } else if cfg!(target_os = "linux") && std::env::var_os("APPIMAGE").is_some() {
        "CopyPaste-Linux-x86_64.AppImage"
    } else {
        return None;
    };
    release.get("assets")?.as_array()?.iter().find(|a| a["name"] == want).and_then(|a| {
        Some((a["browser_download_url"].as_str()?.to_string(), a["size"].as_u64().unwrap_or(0)))
    })
}

fn download(url: &str, size: u64, to: &std::path::Path) -> Result<(), String> {
    let resp = crate::ai::agent_builder()
        .timeout_connect(Duration::from_secs(20))
        .timeout(Duration::from_secs(900))
        .build()
        .get(url)
        .set("User-Agent", "CopyPaste")
        .call()
        .map_err(|e| e.to_string())?;
    let mut f = std::fs::File::create(to).map_err(|e| e.to_string())?;
    let n = std::io::copy(&mut resp.into_reader(), &mut f).map_err(|e| e.to_string())?;
    if size > 0 && n != size {
        let _ = std::fs::remove_file(to);
        return Err(t("o download veio incompleto").into());
    }
    Ok(())
}

fn install(app: &AppHandle, url: &str, size: u64, version: &str) -> Result<(), String> {
    crate::ui::toast(app, &tf("Baixando a atualização {}…", &[&version]));
    crate::diag(app, &format!("atualização: baixando {url}"));
    #[cfg(windows)]
    {
        let setup = std::env::temp_dir().join(format!("CopyPaste-{version}-Setup.exe"));
        download(url, size, &setup)?;
        // Passive install (progress bar only); /R opens the new version when it finishes.
        std::process::Command::new(&setup).args(["/P", "/UPDATE", "/R"]).spawn().map_err(|e| e.to_string())?;
        crate::diag(app, &format!("atualização: instalador {version} iniciado"));
        std::thread::sleep(Duration::from_millis(400));
        app.exit(0);
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let current = std::path::PathBuf::from(std::env::var_os("APPIMAGE").ok_or("APPIMAGE")?);
        let fresh = current.with_extension("new");
        download(url, size, &fresh)?;
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&fresh, std::fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
        std::fs::rename(&fresh, &current).map_err(|e| e.to_string())?;
        crate::diag(app, &format!("atualização: AppImage {version} instalada, reabrindo"));
        crate::ui::toast(app, &tf("Atualizando para a {} e reabrindo…", &[&version]));
        std::thread::sleep(Duration::from_millis(800));
        std::process::Command::new(&current).spawn().map_err(|e| e.to_string())?;
        app.exit(0);
        Ok(())
    }
}
