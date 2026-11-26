//! Interface language: Portuguese (the strings in the code are the keys), English and Spanish.
//! The setting is "auto" (the system's language), "pt", "en" or "es"; anything not covered falls back
//! to English. Diagnostics (`crate::diag`) are never translated.

use std::fmt::Display;
use std::sync::atomic::{AtomicU8, Ordering};

const PT: u8 = 0;
const EN: u8 = 1;
const ES: u8 = 2;

static LANG: AtomicU8 = AtomicU8::new(PT);

/// The system's language among the supported ones ("pt", "en" or "es"); English otherwise.
pub fn system() -> &'static str {
    let loc = sys_locale::get_locale().unwrap_or_default().to_lowercase();
    match loc.get(..2) {
        Some("pt") => "pt",
        Some("es") => "es",
        _ => "en",
    }
}

/// Resolves a setting value ("auto", "pt", "en", "es") to a language code.
pub fn resolve(setting: &str) -> &'static str {
    match setting {
        "pt" => "pt",
        "en" => "en",
        "es" => "es",
        _ => system(),
    }
}

/// Sets the language used from now on (at start-up and when the setting changes).
pub fn set(setting: &str) {
    let code = match resolve(setting) {
        "en" => EN,
        "es" => ES,
        _ => PT,
    };
    LANG.store(code, Ordering::SeqCst);
}

/// The language in use: "pt", "en" or "es".
pub fn current() -> &'static str {
    match LANG.load(Ordering::SeqCst) {
        EN => "en",
        ES => "es",
        _ => "pt",
    }
}

/// Default dictation language for a fresh install, following the system's language.
pub fn default_dict_language() -> String {
    match system() {
        "pt" => "pt-BR",
        "es" => "es-ES",
        _ => "en-US",
    }
    .into()
}

/// Translation of an exact Portuguese string; the string itself when it is Portuguese or unknown.
pub fn t(pt: &str) -> &str {
    let lang = LANG.load(Ordering::SeqCst);
    if lang == PT {
        return pt;
    }
    match table(pt) {
        Some((en, es)) => {
            if lang == EN {
                en
            } else {
                es
            }
        }
        None => pt,
    }
}

/// Translates, then fills each `{}` in order with the values.
pub fn tf(pt: &str, args: &[&dyn Display]) -> String {
    let mut out = String::new();
    let mut parts = t(pt).split("{}");
    if let Some(first) = parts.next() {
        out.push_str(first);
    }
    for (i, part) in parts.enumerate() {
        if let Some(a) = args.get(i) {
            out.push_str(&a.to_string());
        }
        out.push_str(part);
    }
    out
}

/// For messages that arrive already built (from the native code of each system): the exact text, or
/// a known head before ": " followed by the untranslated detail.
pub fn msg(s: &str) -> String {
    if LANG.load(Ordering::SeqCst) == PT || table(s).is_some() {
        return t(s).to_string();
    }
    if let Some((head, rest)) = s.split_once(": ") {
        if table(head).is_some() {
            return format!("{}: {rest}", t(head));
        }
    }
    s.to_string()
}

fn table(pt: &str) -> Option<(&'static str, &'static str)> {
    Some(match pt {
        // ── tray ──
        "■ Parar gravação" => ("■ Stop recording", "■ Detener grabación"),
        "Abrir histórico" => ("Open history", "Abrir historial"),
        "Capturar área ou janela" => ("Capture area or window", "Capturar área o ventana"),
        "Capturar tela inteira" => ("Capture full screen", "Capturar pantalla completa"),
        "Modo apresentação (quadro)" => ("Presentation mode (board)", "Modo presentación (pizarra)"),
        "Gravar tela…" => ("Record screen…", "Grabar pantalla…"),
        "Ditado por voz" => ("Voice dictation", "Dictado por voz"),
        "Comando de voz" => ("Voice command", "Comando de voz"),
        "Retomar histórico" => ("Resume history", "Reanudar historial"),
        "Pausar histórico" => ("Pause history", "Pausar historial"),
        "Como usar…" => ("How to use…", "Cómo usar…"),
        "Configurações…" => ("Settings…", "Configuración…"),
        "Verificar atualizações…" => ("Check for updates…", "Buscar actualizaciones…"),
        "Doar via Pix ♥" => ("Donate via Pix ♥", "Donar vía Pix ♥"),
        "Sair do CopyPaste" => ("Quit CopyPaste", "Salir de CopyPaste"),
        "Chave Pix copiada — obrigado pelo apoio! ♥" => ("Pix key copied — thanks for your support! ♥", "Clave Pix copiada — ¡gracias por tu apoyo! ♥"),
        "Histórico pausado" => ("History paused", "Historial en pausa"),
        "Histórico retomado" => ("History resumed", "Historial reanudado"),
        "CopyPaste — gravando" => ("CopyPaste — recording", "CopyPaste — grabando"),

        // ── window titles ──
        "CopyPaste — captura" => ("CopyPaste — capture", "CopyPaste — captura"),
        "CopyPaste — ditado" => ("CopyPaste — dictation", "CopyPaste — dictado"),
        "CopyPaste — Configurações" => ("CopyPaste — Settings", "CopyPaste — Configuración"),
        "CopyPaste — imagem fixada" => ("CopyPaste — pinned image", "CopyPaste — imagen fijada"),

        // ── updates ──
        "Não consegui verificar atualizações agora. Confira a internet." => (
            "Couldn't check for updates right now. Check your internet connection.",
            "No se pudieron buscar actualizaciones ahora. Revisa tu conexión a internet.",
        ),
        "Você já tem a versão mais recente ({})" => ("You already have the latest version ({})", "Ya tienes la versión más reciente ({})"),
        "Baixe o instalador e abra: ele substitui a versão atual e mantém o seu histórico e as configurações." => (
            "Download the installer and open it: it replaces the current version and keeps your history and settings.",
            "Descarga el instalador y ábrelo: reemplaza la versión actual y conserva tu historial y tu configuración.",
        ),
        "Baixe o pacote do seu sistema (.deb, .rpm ou AppImage) e instale por cima: o histórico e as configurações são mantidos." => (
            "Download the package for your system (.deb, .rpm or AppImage) and install it over the current one: your history and settings are kept.",
            "Descarga el paquete de tu sistema (.deb, .rpm o AppImage) e instálalo encima: el historial y la configuración se conservan.",
        ),
        "Você está na {}. {}" => ("You have version {}. {}", "Tienes la versión {}. {}"),
        "Nova versão do CopyPaste: {}" => ("New version of CopyPaste: {}", "Nueva versión de CopyPaste: {}"),
        "Baixar atualização" => ("Download update", "Descargar actualización"),
        "Depois" => ("Later", "Más tarde"),

        // ── general ──
        "área de transferência indisponível" => ("clipboard unavailable", "portapapeles no disponible"),
        "item não encontrado" => ("item not found", "elemento no encontrado"),
        "Copiado" => ("Copied", "Copiado"),
        "corpo inválido" => ("invalid body", "cuerpo no válido"),
        "provedor desconhecido" => ("unknown provider", "proveedor desconocido"),
        "Cole a chave da API." => ("Paste the API key.", "Pega la clave de API."),
        "A chave funciona, mas nenhum modelo de texto está disponível nela." => (
            "The key works, but no text model is available with it.",
            "La clave funciona, pero no tiene ningún modelo de texto disponible.",
        ),
        "Atalho inválido: {}" => ("Invalid shortcut: {}", "Atajo no válido: {}"),
        "Não foi possível registrar (talvez outro app já use esse atalho): {}" => (
            "Couldn't register it (another app may already use this shortcut): {}",
            "No se pudo registrar (quizá otra app ya usa este atajo): {}",
        ),

        // ── capture ──
        "Não consegui acessar a tela: {}" => ("Couldn't access the screen: {}", "No se pudo acceder a la pantalla: {}"),
        "Falha ao capturar a tela: {}" => ("Screen capture failed: {}", "Error al capturar la pantalla: {}"),
        "sem monitor" => ("no monitor", "sin monitor"),
        "Captura %Y-%m-%d às %H.%M.%S" => ("Screenshot %Y-%m-%d at %H.%M.%S", "Captura %Y-%m-%d a las %H.%M.%S"),
        "Não consegui criar {}: {}" => ("Couldn't create {}: {}", "No se pudo crear {}: {}"),
        "Quadro salvo" => ("Board saved", "Pizarra guardada"),
        "Captura salva" => ("Screenshot saved", "Captura guardada"),
        "Quadro copiado — cole no chat ou e-mail" => ("Board copied — paste it into a chat or email", "Pizarra copiada — pégala en un chat o correo"),
        "Captura copiada" => ("Screenshot copied", "Captura copiada"),
        "Copiada e salva" => ("Copied and saved", "Copiada y guardada"),
        "Salvar captura" => ("Save screenshot", "Guardar captura"),
        "Nenhum texto encontrado na área" => ("No text found in the area", "No se encontró texto en el área"),
        "Texto copiado ({} caracteres)" => ("Text copied ({} characters)", "Texto copiado ({} caracteres)"),
        "ação desconhecida: {}" => ("unknown action: {}", "acción desconocida: {}"),

        // ── recording ──
        "Já existe uma gravação em andamento." => ("A recording is already in progress.", "Ya hay una grabación en curso."),
        "Nenhuma tela selecionada" => ("No screen selected", "No hay ninguna pantalla seleccionada"),
        "Gravação %Y-%m-%d às %H.%M.%S" => ("Recording %Y-%m-%d at %H.%M.%S", "Grabación %Y-%m-%d a las %H.%M.%S"),
        "Não consegui iniciar o ffmpeg: {}" => ("Couldn't start ffmpeg: {}", "No se pudo iniciar ffmpeg: {}"),
        "ffmpeg sem entrada" => ("ffmpeg has no input", "ffmpeg sin entrada"),
        "Monitor não encontrado" => ("Monitor not found", "No se encontró el monitor"),
        "Não consegui iniciar a captura de vídeo" => ("Couldn't start the video capture", "No se pudo iniciar la captura de video"),
        "Gravação salva" => ("Recording saved", "Grabación guardada"),
        "veja gravacao.log" => ("see gravacao.log", "consulta gravacao.log"),
        "A gravação falhou: {}" => ("Recording failed: {}", "La grabación falló: {}"),

        // ── dictation ──
        "Para ditar, baixe a IA local (grátis) ou conecte a OpenAI ou o Gemini em Configurações › IA e ditado." => (
            "To dictate, download the local AI (free) or connect OpenAI or Gemini in Settings › AI and dictation.",
            "Para dictar, descarga la IA local (gratis) o conecta OpenAI o Gemini en Configuración › IA y dictado.",
        ),
        "Para comandos de voz, baixe a IA local ou conecte uma IA em Configurações › IA e ditado." => (
            "For voice commands, download the local AI or connect an AI in Settings › AI and dictation.",
            "Para comandos de voz, descarga la IA local o conecta una IA en Configuración › IA y dictado.",
        ),
        "Não ouvi nada. Fale mais perto do microfone." => ("I didn't hear anything. Speak closer to the microphone.", "No oí nada. Habla más cerca del micrófono."),
        "Nenhum microfone encontrado." => ("No microphone found.", "No se encontró ningún micrófono."),
        "Não consegui abrir o microfone: {}" => ("Couldn't open the microphone: {}", "No se pudo abrir el micrófono: {}"),
        "Formato de áudio do microfone não suportado: {}" => ("Unsupported microphone audio format: {}", "Formato de audio del micrófono no compatible: {}"),
        "Transcrevendo no computador…" => ("Transcribing on this computer…", "Transcribiendo en el equipo…"),
        "Transcrevendo…" => ("Transcribing…", "Transcribiendo…"),
        "Conecte a chave do {}." => ("Connect your {} key.", "Conecta tu clave de {}."),
        "Conecte uma IA para usar comandos de voz." => ("Connect an AI to use voice commands.", "Conecta una IA para usar comandos de voz."),
        "Escolha o modelo da IA em Configurações › IA e ditado." => ("Choose the AI model in Settings › AI and dictation.", "Elige el modelo de IA en Configuración › IA y dictado."),
        "{} está escrevendo…" => ("{} is writing…", "{} está escribiendo…"),
        "Ajustando com {}…" => ("Polishing with {}…", "Ajustando con {}…"),
        "{} Colei o texto sem ajuste." => ("{} Pasted the text without polishing.", "{} Pegué el texto sin ajustar."),
        "Não consegui copiar o texto: {}" => ("Couldn't copy the text: {}", "No se pudo copiar el texto: {}"),

        // ── AI ──
        "IA local" => ("Local AI", "IA local"),
        "IA" => ("AI", "IA"),
        "{}: chave inválida ou sem permissão." => ("{}: invalid key or no permission.", "{}: clave no válida o sin permiso."),
        "{}: sem saldo ou créditos na conta." => ("{}: no balance or credits in the account.", "{}: sin saldo ni créditos en la cuenta."),
        "{}: modelo não encontrado. Atualize a lista de modelos." => ("{}: model not found. Refresh the model list.", "{}: modelo no encontrado. Actualiza la lista de modelos."),
        "{}: cota esgotada. Confira o plano ou os créditos da sua conta." => (
            "{}: quota exhausted. Check your account's plan or credits.",
            "{}: cuota agotada. Revisa el plan o los créditos de tu cuenta.",
        ),
        "{}: limite por minuto atingido. Espere alguns segundos e tente de novo." => (
            "{}: per-minute limit reached. Wait a few seconds and try again.",
            "{}: se alcanzó el límite por minuto. Espera unos segundos y vuelve a intentarlo.",
        ),
        "{} está instável agora. Tente de novo em instantes." => ("{} is unstable right now. Try again in a moment.", "{} está inestable ahora. Vuelve a intentarlo en un momento."),
        "{} recusou o pedido (erro {})." => ("{} rejected the request (error {}).", "{} rechazó la solicitud (error {})."),
        "{}: resposta inválida ({})" => ("{}: invalid response ({})", "{}: respuesta no válida ({})"),
        "{} demorou demais para responder." => ("{} took too long to respond.", "{} tardó demasiado en responder."),
        "Sem conexão com {}: {}" => ("No connection to {}: {}", "Sin conexión con {}: {}"),
        "Claude recusou ajustar esse texto." => ("Claude declined to polish this text.", "Claude se negó a ajustar este texto."),
        "{} não transcreve áudio. Use a IA local, a OpenAI ou o Gemini." => (
            "{} doesn't transcribe audio. Use the local AI, OpenAI or Gemini.",
            "{} no transcribe audio. Usa la IA local, OpenAI o Gemini.",
        ),

        // ── local AI ──
        "motor llama.cpp" => ("llama.cpp engine", "motor llama.cpp"),
        "modelo Gemma 4" => ("Gemma 4 model", "modelo Gemma 4"),
        "módulo de voz e imagem" => ("voice and image module", "módulo de voz e imagen"),
        "Pronta" => ("Ready", "Lista"),
        "Não consegui instalar o motor da IA local." => ("Couldn't install the local AI engine.", "No se pudo instalar el motor de la IA local."),
        "O download de {} falhou: {}" => ("The {} download failed: {}", "La descarga del {} falló: {}"),
        "Download cancelado." => ("Download canceled.", "Descarga cancelada."),
        "O download parou: {}" => ("The download stopped: {}", "La descarga se detuvo: {}"),
        "Sem espaço em disco? {}" => ("Out of disk space? {}", "¿Sin espacio en disco? {}"),
        "Baixando {}…" => ("Downloading the {}…", "Descargando el {}…"),
        "O arquivo {} chegou incompleto ou corrompido. Tente de novo." => (
            "The {} arrived incomplete or corrupted. Try again.",
            "El {} llegó incompleto o dañado. Vuelve a intentarlo.",
        ),
        "Baixe a IA local em Configurações › IA e ditado." => ("Download the local AI in Settings › AI and dictation.", "Descarga la IA local en Configuración › IA y dictado."),
        "Motor da IA local não encontrado. Reinstale a IA local." => ("Local AI engine not found. Reinstall the local AI.", "No se encontró el motor de la IA local. Reinstala la IA local."),
        "A IA local não conseguiu iniciar: {}" => ("The local AI couldn't start: {}", "La IA local no pudo iniciarse: {}"),
        "A IA local foi encerrada." => ("The local AI was shut down.", "La IA local se cerró."),
        "A IA local não conseguiu iniciar. {}" => ("The local AI couldn't start. {}", "La IA local no pudo iniciarse. {}"),
        "A IA local demorou demais para carregar." => ("The local AI took too long to load.", "La IA local tardó demasiado en cargar."),

        // ── native code of each system (windows/, linux/ and the macOS stub) ──
        "O Windows bloqueou o envio do Ctrl+V (janela de administrador?). O item ficou copiado: cole com Ctrl+V." => (
            "Windows blocked sending Ctrl+V (administrator window?). The item is copied: paste it with Ctrl+V.",
            "Windows bloqueó el envío de Ctrl+V (¿ventana de administrador?). El elemento quedó copiado: pégalo con Ctrl+V.",
        ),
        "OCR do Windows falhou" => ("Windows OCR failed", "El OCR de Windows falló"),
        "Instale o ffmpeg (grátis) e tente de novo: abra o Terminal e rode  winget install Gyan.FFmpeg" => (
            "Install ffmpeg (free) and try again: open Terminal and run  winget install Gyan.FFmpeg",
            "Instala ffmpeg (gratis) y vuelve a intentarlo: abre la Terminal y ejecuta  winget install Gyan.FFmpeg",
        ),
        "Áudio do sistema: ative “Mixagem estéreo” em Configurações > Som > Mais configurações de som > Gravação (ou instale um cabo virtual)." => (
            "System audio: enable “Stereo Mix” in Settings > Sound > More sound settings > Recording (or install a virtual cable).",
            "Audio del sistema: activa “Mezcla estéreo” en Configuración > Sonido > Más opciones de sonido > Grabar (o instala un cable virtual).",
        ),
        "Copiado! Para colar sozinho, instale o xdotool (sudo apt install xdotool)." => (
            "Copied! To paste automatically, install xdotool (sudo apt install xdotool).",
            "¡Copiado! Para pegar automáticamente, instala xdotool (sudo apt install xdotool).",
        ),
        "Copiado! No Wayland, para colar sozinho instale o wtype (KDE/Sway) ou o ydotool (GNOME)." => (
            "Copied! On Wayland, to paste automatically install wtype (KDE/Sway) or ydotool (GNOME).",
            "¡Copiado! En Wayland, para pegar automáticamente instala wtype (KDE/Sway) o ydotool (GNOME).",
        ),
        "Para reconhecer texto, instale o Tesseract: sudo apt install tesseract-ocr tesseract-ocr-por" => (
            "To recognize text, install Tesseract: sudo apt install tesseract-ocr tesseract-ocr-eng",
            "Para reconocer texto, instala Tesseract: sudo apt install tesseract-ocr tesseract-ocr-spa",
        ),
        "Instale o ffmpeg e tente de novo: sudo apt install ffmpeg  (Fedora: sudo dnf install ffmpeg)" => (
            "Install ffmpeg and try again: sudo apt install ffmpeg  (Fedora: sudo dnf install ffmpeg)",
            "Instala ffmpeg y vuelve a intentarlo: sudo apt install ffmpeg  (Fedora: sudo dnf install ffmpeg)",
        ),
        "Áudio do sistema: instale o pactl (pulseaudio-utils) para gravá-lo." => (
            "System audio: install pactl (pulseaudio-utils) to record it.",
            "Audio del sistema: instala pactl (pulseaudio-utils) para grabarlo.",
        ),
        "Sessão Wayland: se um atalho global não funcionar, crie um atalho do sistema que rode `copypaste --capture-area` (ou --capture-screen, --history, --board, --record)." => (
            "Wayland session: if a global shortcut doesn't work, create a system shortcut that runs `copypaste --capture-area` (or --capture-screen, --history, --board, --record).",
            "Sesión Wayland: si un atajo global no funciona, crea un atajo del sistema que ejecute `copypaste --capture-area` (o --capture-screen, --history, --board, --record).",
        ),
        "Para colar sozinho no Wayland, instale o wtype (KDE/Sway) ou o ydotool (GNOME)." => (
            "To paste automatically on Wayland, install wtype (KDE/Sway) or ydotool (GNOME).",
            "Para pegar automáticamente en Wayland, instala wtype (KDE/Sway) o ydotool (GNOME).",
        ),
        "Para colar sozinho, instale o xdotool: sudo apt install xdotool" => (
            "To paste automatically, install xdotool: sudo apt install xdotool",
            "Para pegar automáticamente, instala xdotool: sudo apt install xdotool",
        ),
        "Para copiar texto de imagens (OCR), instale: sudo apt install tesseract-ocr tesseract-ocr-por" => (
            "To copy text from images (OCR), install: sudo apt install tesseract-ocr tesseract-ocr-eng",
            "Para copiar texto de imágenes (OCR), instala: sudo apt install tesseract-ocr tesseract-ocr-spa",
        ),
        "Para gravar a tela, instale: sudo apt install ffmpeg" => ("To record the screen, install: sudo apt install ffmpeg", "Para grabar la pantalla, instala: sudo apt install ffmpeg"),
        "Copiado! (colar automático só no Windows e no Linux; no Mac use o app nativo)" => (
            "Copied! (automatic paste only on Windows and Linux; on the Mac use the native app)",
            "¡Copiado! (pegar automáticamente solo en Windows y Linux; en el Mac usa la app nativa)",
        ),
        "OCR indisponível nesta versão de desenvolvimento." => ("OCR is unavailable in this development version.", "El OCR no está disponible en esta versión de desarrollo."),
        "Instale o ffmpeg: brew install ffmpeg" => ("Install ffmpeg: brew install ffmpeg", "Instala ffmpeg: brew install ffmpeg"),
        "Versão de desenvolvimento no macOS — para uso diário no Mac, use o app nativo da pasta macos/." => (
            "Development version on macOS — for daily use on the Mac, use the native app in the macos/ folder.",
            "Versión de desarrollo en macOS — para el uso diario en el Mac, usa la app nativa de la carpeta macos/.",
        ),
        _ => return None,
    })
}
