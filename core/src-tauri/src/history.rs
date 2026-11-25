//! Copy history: watches the clipboard, classifies what was copied and saves it to disk.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};

use crate::{platform, AppState};

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ClipItem {
    pub id: String,
    /// text, link, color, code, image
    pub kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image: Option<String>,
    #[serde(default)]
    pub width: u32,
    #[serde(default)]
    pub height: u32,
    pub first: i64,
    pub date: i64,
    #[serde(default = "one")]
    pub uses: u32,
    #[serde(default)]
    pub pinned: bool,
    pub hash: String,
}

fn one() -> u32 {
    1
}

/// What the panel receives: long text goes truncated (the full text stays here).
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ClipView {
    pub id: String,
    pub kind: String,
    pub text: Option<String>,
    pub chars: usize,
    pub image: Option<String>,
    pub width: u32,
    pub height: u32,
    pub date: i64,
    pub uses: u32,
    pub pinned: bool,
}

pub struct History {
    pub items: Vec<ClipItem>,
    file: PathBuf,
    pub images: PathBuf,
}

pub fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

pub fn hash_text(t: &str) -> String {
    let d = Sha256::digest(t.as_bytes());
    d.iter().take(12).map(|b| format!("{b:02x}")).collect()
}

/// Quick hash of an image: size + 1 sample out of every 509 bytes (enough to tell copies apart).
pub fn hash_image(w: usize, h: usize, bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update((w as u64).to_le_bytes());
    hasher.update((h as u64).to_le_bytes());
    for chunk in bytes.chunks(509) {
        hasher.update(&chunk[..chunk.len().min(4)]);
    }
    let d = hasher.finalize();
    format!("img{}", d.iter().take(12).map(|b| format!("{b:02x}")).collect::<String>())
}

pub fn classify(t: &str) -> &'static str {
    let s = t.trim();
    let single = !s.contains('\n');
    if single && !s.contains(' ') {
        let lower = s.to_lowercase();
        if lower.starts_with("http://") || lower.starts_with("https://") || lower.starts_with("www.") || lower.starts_with("ftp://") {
            return "link";
        }
        let hex = s.strip_prefix('#').unwrap_or("");
        if !hex.is_empty() && [3, 4, 6, 8].contains(&hex.len()) && hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return "color";
        }
    }
    if single && (s.starts_with("rgb(") || s.starts_with("rgba(") || s.starts_with("hsl(")) && s.ends_with(')') {
        return "color";
    }
    let lines: Vec<&str> = s.lines().collect();
    if lines.len() >= 2 {
        let codey = lines
            .iter()
            .filter(|l| {
                let l = l.trim_end();
                l.ends_with('{') || l.ends_with('}') || l.ends_with(';') || l.ends_with(')') || l.starts_with("    ") || l.starts_with('\t')
                    || l.trim_start().starts_with("//") || l.trim_start().starts_with("def ") || l.trim_start().starts_with("fn ")
                    || l.trim_start().starts_with("import ") || l.trim_start().starts_with('<')
            })
            .count();
        if codey * 2 >= lines.len() {
            return "code";
        }
    }
    "text"
}

impl History {
    pub fn load(data_dir: &Path) -> History {
        let file = data_dir.join("history.json");
        let images = data_dir.join("images");
        let _ = std::fs::create_dir_all(&images);
        let items = std::fs::read(&file).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        History { items, file, images }
    }

    pub fn save(&self) {
        let tmp = self.file.with_extension("json.tmp");
        if let Ok(b) = serde_json::to_vec(&self.items) {
            if std::fs::write(&tmp, b).is_ok() {
                let _ = std::fs::rename(&tmp, &self.file);
            }
        }
    }

    pub fn views(&self) -> Vec<ClipView> {
        self.items
            .iter()
            .map(|i| {
                let text = i.text.as_ref().map(|t| if t.len() > 4000 { t.chars().take(4000).collect() } else { t.clone() });
                ClipView {
                    id: i.id.clone(),
                    kind: i.kind.clone(),
                    chars: i.text.as_ref().map(|t| t.chars().count()).unwrap_or(0),
                    text,
                    image: i.image.clone(),
                    width: i.width,
                    height: i.height,
                    date: i.date,
                    uses: i.uses,
                    pinned: i.pinned,
                }
            })
            .collect()
    }

    /// Moves an existing item to the top or creates a new one. Returns true if it changed.
    pub fn touch_or_insert(&mut self, item: ClipItem, limit: usize) -> bool {
        if let Some(pos) = self.items.iter().position(|i| i.hash == item.hash) {
            let mut existing = self.items.remove(pos);
            existing.date = item.date;
            existing.uses += 1;
            self.items.insert(0, existing);
            if let Some(img) = &item.image {
                let _ = std::fs::remove_file(self.images.join(img));
            }
        } else {
            self.items.insert(0, item);
        }
        self.trim(limit);
        true
    }

    pub fn trim(&mut self, limit: usize) {
        let mut unpinned = 0;
        let mut removed = vec![];
        self.items.retain(|i| {
            if i.pinned {
                return true;
            }
            unpinned += 1;
            if unpinned > limit {
                removed.push(i.image.clone());
                false
            } else {
                true
            }
        });
        for img in removed.into_iter().flatten() {
            let _ = std::fs::remove_file(self.images.join(img));
        }
    }

    pub fn remove(&mut self, id: &str) {
        if let Some(pos) = self.items.iter().position(|i| i.id == id) {
            let it = self.items.remove(pos);
            if let Some(img) = it.image {
                let _ = std::fs::remove_file(self.images.join(img));
            }
        }
    }

    pub fn clear(&mut self, keep_pinned: bool) {
        let images = self.images.clone();
        self.items.retain(|i| {
            let keep = keep_pinned && i.pinned;
            if !keep {
                if let Some(img) = &i.image {
                    let _ = std::fs::remove_file(images.join(img));
                }
            }
            keep
        });
    }
}

/// Signature of what is in the clipboard, so it is not read or saved twice.
#[derive(Default)]
pub struct ClipSig {
    pub last_hash: String,
    pub last_count: Option<u64>,
}

/// Thread that watches the clipboard. On Windows it uses the change counter (almost zero cost);
/// on Linux it reads the content periodically.
pub fn start_watcher(app: AppHandle) {
    let app2 = app.clone();
    std::thread::spawn(move || {
        let mut tick: u64 = 0;
        loop {
            std::thread::sleep(Duration::from_millis(400));
            tick += 1;
            let state = app.state::<AppState>();
            if state.settings.lock().unwrap().paused {
                continue;
            }
            let count = platform::clipboard_change_count();
            if let Some(c) = count {
                let mut sig = state.sig.lock().unwrap();
                if sig.last_count == Some(c) {
                    continue;
                }
                sig.last_count = Some(c);
            }
            let check_images = count.is_some() || tick % 2 == 0;
            if let Some(item) = read_clipboard(&app, check_images) {
                let limit = state.settings.lock().unwrap().history_limit;
                state.history.lock().unwrap().touch_or_insert(item, limit);
                state.history_dirty.store(true, Ordering::SeqCst);
                let _ = app.emit("history-changed", ());
            }
        }
    });

    // Saves to disk at most once per second.
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_millis(1000));
        let state = app2.state::<AppState>();
        if state.history_dirty.swap(false, Ordering::SeqCst) {
            state.history.lock().unwrap().save();
        }
    });
}

fn read_clipboard(app: &AppHandle, check_images: bool) -> Option<ClipItem> {
    let state = app.state::<AppState>();
    let (text, image) = {
        let mut cb = state.clipboard.lock().unwrap();
        let cb = cb.as_mut()?;
        let text = cb.get_text().ok().filter(|t| !t.trim().is_empty());
        let image = if text.is_none() && check_images { cb.get_image().ok() } else { None };
        (text, image)
    };
    let now = now_ms();
    if let Some(t) = text {
        let hash = hash_text(&t);
        {
            let mut sig = state.sig.lock().unwrap();
            if sig.last_hash == hash {
                return None;
            }
            sig.last_hash = hash.clone();
        }
        return Some(ClipItem {
            id: uuid::Uuid::new_v4().to_string(),
            kind: classify(&t).into(),
            text: Some(t),
            image: None,
            width: 0,
            height: 0,
            first: now,
            date: now,
            uses: 1,
            pinned: false,
            hash,
        });
    }
    let img = image?;
    if img.width == 0 || img.height == 0 {
        return None;
    }
    let hash = hash_image(img.width, img.height, &img.bytes);
    {
        let mut sig = state.sig.lock().unwrap();
        if sig.last_hash == hash {
            return None;
        }
        sig.last_hash = hash.clone();
    }
    let id = uuid::Uuid::new_v4().to_string();
    let file = format!("{id}.png");
    let dir = state.history.lock().unwrap().images.clone();
    let buf = image::RgbaImage::from_raw(img.width as u32, img.height as u32, img.bytes.into_owned())?;
    buf.save_with_format(dir.join(&file), image::ImageFormat::Png).ok()?;
    Some(ClipItem {
        id,
        kind: "image".into(),
        text: None,
        image: Some(file),
        width: img.width as u32,
        height: img.height as u32,
        first: now,
        date: now,
        uses: 1,
        pinned: false,
        hash,
    })
}
