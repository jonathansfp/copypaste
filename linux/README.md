# 🐧 CopyPaste para Linux

Código nativo do Linux usado pelo núcleo compartilhado em [`../core`](../core/README.md). Funciona em **X11 e Wayland** (GNOME, KDE, Sway, Cinnamon, XFCE…).

## Baixar

- [**CopyPaste-Linux-x86_64.AppImage**](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Linux-x86_64.AppImage), para qualquer distro:
  ```bash
  chmod +x CopyPaste-Linux-x86_64.AppImage
  ./CopyPaste-Linux-x86_64.AppImage
  ```
- [CopyPaste-Linux-amd64.deb](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Linux-amd64.deb) (Ubuntu, Debian, Mint, Pop!_OS): `sudo apt install ./CopyPaste-Linux-amd64.deb`
- [CopyPaste-Linux-x86_64.rpm](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Linux-x86_64.rpm) (Fedora, openSUSE): `sudo dnf install ./CopyPaste-Linux-x86_64.rpm`

**Extras recomendados** (o app avisa em *Configurações › Início* o que faltar):

```bash
sudo apt install xdotool ffmpeg tesseract-ocr tesseract-ocr-por pulseaudio-utils
# Wayland: colar sozinho
sudo apt install wtype      # KDE, Sway, Hyprland
sudo apt install ydotool    # GNOME
```

## O que este código faz (`src/lib.rs`)

| Função | X11 | Wayland |
|---|---|---|
| Colar no app anterior | `xdotool windowactivate` + `key ctrl+v` | `wtype` ou `ydotool` |
| Janelas do app | nativas | via XWayland (`GDK_BACKEND=x11`), para posicionar e manter "sempre no topo" |
| Captura | X11 direto | portal / PipeWire (pela biblioteca `xcap`) |
| OCR | Tesseract (por + eng + spa, conforme instalado) | igual |
| Áudio da gravação | PulseAudio/PipeWire: `default` (microfone) e `<saída>.monitor` (sistema) | igual |
| Pastas padrão | lidas de `~/.config/user-dirs.dirs` (ex.: `~/Imagens/CopyPaste`) | igual |
| Comando de voz sobre a seleção | `xdotool key ctrl+c` | `wtype` ou `ydotool` |

**Ditado por voz:** o microfone é lido pelo ALSA/PipeWire (`cpal`, no núcleo), a transcrição e o ajuste do texto usam a **IA local** (Gemma 4 E2B no llama.cpp, baixada em *Configurações*, grátis e offline) ou a IA que você conectar (Claude, GPT, Gemini, DeepSeek ou Grok) em *Configurações › IA e ditado*. As chaves ficam em `~/.config/io.github.jonathansfp.copypaste/ai-keys.json`, com permissão só para o seu usuário (0600).

## Atalhos no Wayland

O Wayland não deixa apps registrarem atalhos globais. Se um atalho não responder, crie atalhos do sistema que chamem o CopyPaste. O app já aberto recebe o comando na hora:

| Comando | Ação |
|---|---|
| `copypaste --capture-area` | Capturar área ou janela |
| `copypaste --capture-screen` | Capturar a tela inteira |
| `copypaste --history` | Histórico de cópias |
| `copypaste --board` | Quadro de apresentação |
| `copypaste --record` | Iniciar/parar gravação |
| `copypaste --dictate` | Ditado por voz (de novo para terminar) |
| `copypaste --voice-command` | Comando de voz sobre o texto selecionado |

**GNOME:** *Configurações › Teclado › Atalhos de teclado › Ver e personalizar › Atalhos personalizados › +*.
**KDE:** *Configurações do sistema › Atalhos › Adicionar novo › Comando*.

(Com o AppImage, use o caminho completo do arquivo no lugar de `copypaste`.)

## Compilar

```bash
./linux/build.sh --deps   # instala as dependências (apt ou dnf) e compila
./linux/build.sh          # só compila
```

Requisitos: [Rust](https://rustup.rs) e [Node.js](https://nodejs.org) 18+. Saída em `target/release/bundle/{appimage,deb,rpm}/`.

Para desenvolver: `cd core && npm install && npx tauri dev`.

## Solução de problemas

- **Tela branca ao abrir janelas (drivers NVIDIA):** o app já define `WEBKIT_DISABLE_DMABUF_RENDERER=1`. Se ainda acontecer, rode com `WEBKIT_DISABLE_COMPOSITING_MODE=1 copypaste`.
- **Ícone não aparece no painel do GNOME:** instale a extensão *AppIndicator and KStatusNotifierItem Support*.
- **Log:** `~/.local/share/io.github.jonathansfp.copypaste/diagnostico.log` (e `gravacao.log` para a gravação).
