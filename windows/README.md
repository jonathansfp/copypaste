# 🪟 CopyPaste para Windows

Código nativo do Windows usado pelo núcleo compartilhado em [`../core`](../core/README.md). O app final é gerado a partir daqui.

## Baixar

- [**CopyPaste-Windows-Setup.exe**](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Windows-Setup.exe): instalador para o usuário atual, sem precisar de administrador.
- [CopyPaste-Windows.msi](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Windows.msi): para implantar em várias máquinas.
- [CopyPaste-Windows-Portable.zip](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Windows-Portable.zip): só o `CopyPaste.exe`. Requer o WebView2, que já vem no Windows 10 atualizado e no 11.

Na primeira execução, o SmartScreen pode mostrar "O Windows protegeu o computador". Clique em **Mais informações** e depois em **Executar assim mesmo**.

## O que este código faz (`src/lib.rs`)

| Função | Como |
|---|---|
| Colar no app anterior | Guarda a janela em primeiro plano (`GetForegroundWindow`), devolve o foco a ela e envia `Ctrl+V` com `SendInput` |
| Detectar cópias sem gastar CPU | `GetClipboardSequenceNumber`: o histórico só lê a área de transferência quando ela muda |
| OCR | `Windows.Media.Ocr`, embutido no Windows 10/11, offline, nos idiomas do seu perfil |
| Barra de gravação invisível no vídeo | `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` |
| Áudio da gravação | Lista os dispositivos DirectShow do ffmpeg, escolhe o microfone e, se existir, a "Mixagem estéreo" para o áudio do sistema |
| Sem janela de console | `CREATE_NO_WINDOW` ao chamar o ffmpeg |
| Comando de voz sobre a seleção | Envia `Ctrl+C` com `SendInput` para ler o texto selecionado |

**Ditado por voz:** o microfone é lido pelo WASAPI (`cpal`, no núcleo), a transcrição e o ajuste do texto usam a **IA local** (Gemma 4 E2B no llama.cpp, baixada em *Configurações*, grátis e offline) ou a IA que você conectar (Claude, GPT, Gemini, DeepSeek ou Grok) em *Configurações › IA e ditado*. As chaves ficam em `%APPDATA%\io.github.jonathansfp.copypaste\ai-keys.json`, só no seu computador.

## Compilar

Requisitos: [Rust](https://rustup.rs) (com o Visual Studio Build Tools, C++), [Node.js](https://nodejs.org) 18+.

```powershell
winget install Rustlang.Rustup OpenJS.NodeJS.LTS Microsoft.VisualStudio.2022.BuildTools
.\windows\build.ps1
```

Saída em `target\release\bundle\nsis\` (instalador `.exe`), `target\release\bundle\msi\` e `target\release\copypaste.exe` (portátil).

Para desenvolver com recarga: `cd core && npm install && npx tauri dev`.

## Gravação de tela

A gravação usa o **ffmpeg** (grátis). Instale uma vez:

```powershell
winget install Gyan.FFmpeg
```

O CopyPaste também procura o ffmpeg em `%LOCALAPPDATA%\Microsoft\WinGet\Links`, no Scoop, no Chocolatey, em `C:\ffmpeg\bin` e ao lado do `CopyPaste.exe`.

Para gravar o **áudio do sistema**, ative a "Mixagem estéreo": *Configurações › Som › Mais configurações de som › Gravação › botão direito › Mostrar dispositivos desativados › Mixagem estéreo › Ativar*. Ou instale um cabo de áudio virtual.

## Solução de problemas

- **`PrtSc` abre a Ferramenta de Captura do Windows:** desligue em *Configurações › Acessibilidade › Teclado › "Usar a tecla Print Screen para abrir a captura de tela"*, ou escolha outro atalho no CopyPaste.
- **Não cola em um programa aberto como administrador:** o Windows bloqueia o envio de teclas de um app comum para um app elevado. O item fica copiado; cole com `Ctrl+V`.
- **Log:** `%APPDATA%\io.github.jonathansfp.copypaste\diagnostico.log` (e `gravacao.log` para a gravação).
