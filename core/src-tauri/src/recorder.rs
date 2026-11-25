//! Screen recording: the capture library delivers frames (DXGI on Windows, PipeWire on Wayland,
//! X11 on Xorg) and ffmpeg encodes H.264 + AAC. Frames enter at a constant rate, so the audio
//! stays in sync even when the screen does not change.

use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager};

use crate::{platform, ui, AppState};

pub struct Recording {
    pub stop: Arc<AtomicBool>,
    pub started: Instant,
    pub path: PathBuf,
}

pub fn find_ffmpeg() -> Option<PathBuf> {
    for c in platform::ffmpeg_candidates() {
        let mut cmd = Command::new(&c);
        cmd.arg("-version").stdout(Stdio::null()).stderr(Stdio::null());
        platform::hide_console(&mut cmd);
        if cmd.status().map(|s| s.success()).unwrap_or(false) {
            return Some(c);
        }
    }
    None
}

pub fn is_recording(app: &AppHandle) -> bool {
    app.state::<AppState>().recorder.lock().unwrap().is_some()
}

/// Region in physical pixels, relative to the frozen monitor.
pub fn start(app: &AppHandle, x: u32, y: u32, w: u32, h: u32, mic: bool, system_audio: bool) -> Result<(), String> {
    let state = app.state::<AppState>();
    if state.recorder.lock().unwrap().is_some() {
        return Err("Já existe uma gravação em andamento.".into());
    }
    let ffmpeg = find_ffmpeg().ok_or_else(|| platform::ffmpeg_hint().to_string())?;
    let (mon_x, mon_y) = {
        let f = state.frozen.lock().unwrap();
        let f = f.as_ref().ok_or("Nenhuma tela selecionada")?;
        (f.mon_x, f.mon_y)
    };
    // The monitor is opened again inside the capture thread (on Windows it cannot change threads).
    xcap::Monitor::from_point(mon_x + 1, mon_y + 1).map_err(|e| e.to_string())?;
    // H.264 (yuv420p) needs even dimensions.
    let (w, h) = (w.max(16) & !1, h.max(16) & !1);
    let settings = state.settings.lock().unwrap().clone();
    let fps = settings.record_fps.clamp(10, 60);
    let dir = PathBuf::from(&settings.record_dir);
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let path = dir.join(format!("Gravação {}.mp4", chrono::Local::now().format("%Y-%m-%d às %H.%M.%S")));

    let audio = platform::audio_inputs(&ffmpeg, mic, system_audio);
    let mut args: Vec<String> = vec![
        "-y", "-hide_banner", "-loglevel", "error", "-thread_queue_size", "64", "-f", "rawvideo", "-pix_fmt", "rgba",
    ]
    .into_iter()
    .map(String::from)
    .collect();
    args.extend(["-s".into(), format!("{w}x{h}"), "-framerate".into(), fps.to_string(), "-i".into(), "pipe:0".into()]);
    for a in &audio.args {
        if a == "-f" {
            args.extend(["-thread_queue_size".into(), "1024".into()]);
        }
        args.push(a.clone());
    }
    args.extend(["-map".into(), "0:v".into()]);
    match audio.count {
        0 => {}
        1 => args.extend(["-map".into(), "1:a".into()]),
        n => {
            let inputs: String = (1..=n).map(|i| format!("[{i}:a]")).collect();
            args.extend(["-filter_complex".into(), format!("{inputs}amix=inputs={n}:duration=longest[a]"), "-map".into(), "[a]".into()]);
        }
    }
    args.extend(
        ["-c:v", "libx264", "-preset", "veryfast", "-crf", "21", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart"]
            .map(String::from),
    );
    args.push(path.to_string_lossy().into_owned());

    let log_path = state.paths.data.join("gravacao.log");
    let log = std::fs::File::create(&log_path).map_err(|e| e.to_string())?;
    let mut cmd = Command::new(&ffmpeg);
    cmd.args(&args).stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::from(log));
    platform::hide_console(&mut cmd);
    let mut child = cmd.spawn().map_err(|e| format!("Não consegui iniciar o ffmpeg: {e}"))?;
    let mut stdin = child.stdin.take().ok_or("ffmpeg sem entrada")?;

    let stop = Arc::new(AtomicBool::new(false));
    let latest: Arc<Mutex<Option<(u32, u32, Vec<u8>)>>> = Arc::new(Mutex::new(None));

    // Frame source.
    let draw_cursor = cfg!(windows) || x11_session();
    {
        let stop = stop.clone();
        let latest = latest.clone();
        let app = app.clone();
        std::thread::spawn(move || {
            let Ok(monitor) = xcap::Monitor::from_point(mon_x + 1, mon_y + 1) else {
                let _ = app.emit("record-error", "Monitor não encontrado");
                return;
            };
            if x11_session() {
                // X11: direct copy of the region, at the chosen rate.
                let interval = Duration::from_secs_f64(1.0 / fps as f64);
                while !stop.load(Ordering::SeqCst) {
                    let t = Instant::now();
                    if let Ok(img) = monitor.capture_region(x, y, w, h) {
                        let (iw, ih) = (img.width(), img.height());
                        *latest.lock().unwrap() = Some((iw, ih, img.into_raw()));
                    }
                    if let Some(rest) = interval.checked_sub(t.elapsed()) {
                        std::thread::sleep(rest);
                    }
                }
                return;
            }
            match monitor.video_recorder() {
                Ok((rec, rx)) => {
                    if rec.start().is_err() {
                        let _ = app.emit("record-error", "Não consegui iniciar a captura de vídeo");
                        return;
                    }
                    while !stop.load(Ordering::SeqCst) {
                        if let Ok(frame) = rx.recv_timeout(Duration::from_millis(200)) {
                            let cropped = crop(&frame.raw, frame.width, frame.height, x, y, w, h);
                            *latest.lock().unwrap() = Some((w, h, cropped));
                            // Drains frames that piled up (PipeWire delivers without waiting).
                            while rx.try_recv().is_ok() {}
                        }
                    }
                    let _ = rec.stop();
                }
                Err(e) => {
                    let _ = app.emit("record-error", e.to_string());
                }
            }
        });
    }

    // Writer at constant rate: repeats the last frame when the screen does not change.
    {
        let stop = stop.clone();
        let latest = latest.clone();
        let app = app.clone();
        let path = path.clone();
        std::thread::spawn(move || {
            let interval = Duration::from_secs_f64(1.0 / fps as f64);
            let mut begin = Instant::now();
            let mut written: u64 = 0;
            let mut last: Option<Vec<u8>> = None;
            let mut ok = true;
            while !stop.load(Ordering::SeqCst) {
                if last.is_some() {
                    let due = begin + interval * (written as u32 + 1);
                    if let Some(rest) = due.checked_duration_since(Instant::now()) {
                        std::thread::sleep(rest);
                    }
                } else {
                    std::thread::sleep(Duration::from_millis(5));
                    begin = Instant::now();
                }
                if let Some((fw, fh, raw)) = latest.lock().unwrap().take() {
                    let mut buf = if fw == w && fh == h { raw } else { crop(&raw, fw, fh, 0, 0, w, h) };
                    if draw_cursor {
                        if let Ok(c) = app.cursor_position() {
                            paint_cursor(&mut buf, w, h, c.x as i32 - mon_x - x as i32, c.y as i32 - mon_y - y as i32);
                        }
                    }
                    last = Some(buf);
                }
                let Some(frame) = &last else {
                    // Still waiting for the first frame: keeps the clock at zero.
                    continue;
                };
                // Late? Writes the missing frames so the duration matches the real time.
                let behind = ((begin.elapsed().as_secs_f64() * fps as f64) as u64).saturating_sub(written).clamp(1, 5);
                for _ in 0..behind {
                    if stdin.write_all(frame).is_err() {
                        ok = false;
                        break;
                    }
                    written += 1;
                }
                if !ok {
                    break;
                }
            }
            drop(stdin);
            let status = child.wait();
            let success = ok && status.map(|s| s.success()).unwrap_or(false) && path.exists();
            app.state::<AppState>().recorder.lock().unwrap().take();
            ui::hide_recbar(&app);
            crate::tray::refresh(&app);
            if success {
                ui::toast_path(&app, "Gravação salva", &path);
                platform::reveal(&path);
            } else {
                let log = std::fs::read_to_string(app.state::<AppState>().paths.data.join("gravacao.log")).unwrap_or_default();
                let last_line = log.lines().last().unwrap_or("veja gravacao.log").to_string();
                ui::toast(&app, &format!("A gravação falhou: {last_line}"));
            }
        });
    }

    for w in &audio.warnings {
        ui::toast(app, w);
    }
    *state.recorder.lock().unwrap() = Some(Recording { stop, started: Instant::now(), path });
    ui::show_recbar(app, mon_x, mon_y, x, y, w, h);
    crate::tray::refresh(app);
    Ok(())
}

pub fn stop(app: &AppHandle) {
    if let Some(r) = app.state::<AppState>().recorder.lock().unwrap().as_ref() {
        r.stop.store(true, Ordering::SeqCst);
    }
}

fn x11_session() -> bool {
    #[cfg(target_os = "linux")]
    {
        !platform::is_wayland()
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
}

fn crop(raw: &[u8], fw: u32, fh: u32, x: u32, y: u32, w: u32, h: u32) -> Vec<u8> {
    let mut out = vec![0u8; (w * h * 4) as usize];
    let row = (w * 4) as usize;
    for r in 0..h {
        let sy = y + r;
        if sy >= fh {
            break;
        }
        let sx = x.min(fw);
        let avail = ((fw - sx).min(w) * 4) as usize;
        let src = ((sy * fw + sx) * 4) as usize;
        let dst = r as usize * row;
        if src + avail <= raw.len() {
            out[dst..dst + avail].copy_from_slice(&raw[src..src + avail]);
        }
    }
    out
}

/// Arrow cursor (1 = black, 2 = white), drawn because some capture APIs leave it out.
const CURSOR: [&str; 19] = [
    "2", "22", "212", "2112", "21112", "211112", "2111112", "21111112", "211111112", "2111111112", "21111111112",
    "211111222222", "2111212", "211221 2", "2122  212", "222   212", "2      212", "       222", "",
];

fn paint_cursor(buf: &mut [u8], w: u32, h: u32, cx: i32, cy: i32) {
    for (dy, line) in CURSOR.iter().enumerate() {
        for (dx, ch) in line.chars().enumerate() {
            let color: [u8; 4] = match ch {
                '1' => [0, 0, 0, 255],
                '2' => [255, 255, 255, 255],
                _ => continue,
            };
            let (px, py) = (cx + dx as i32, cy + dy as i32);
            if px < 0 || py < 0 || px >= w as i32 || py >= h as i32 {
                continue;
            }
            let i = ((py as u32 * w + px as u32) * 4) as usize;
            buf[i..i + 4].copy_from_slice(&color);
        }
    }
}
