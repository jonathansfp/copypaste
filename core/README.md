# ⚙️ Núcleo compartilhado (Windows e Linux)

App [Tauri 2](https://tauri.app): o backend em **Rust** cuida da captura, da área de transferência, dos atalhos e da gravação. A interface (`ui/`) é HTML + canvas, sem framework e sem bundler, e roda no WebView do sistema: WebView2 no Windows, WebKitGTK no Linux. O executável tem poucos MB e não carrega um Chromium próprio.

O código específico de cada sistema fica fora daqui, em [`../windows`](../windows/README.md) e [`../linux`](../linux/README.md). `src-tauri/src/platform.rs` escolhe um dos dois na compilação.

```
core/
├── ui/                       Interface (abre direto do disco, sem build)
│   ├── editor.html, js/editor.js     Captura, escolha da área de gravação e quadro (tela cheia)
│   ├── js/shapes.js                  Motor vetorial: formas, traço à mão, setas, rótulos, desfoque (porte do Mac)
│   ├── history.html, js/history.js   Painel do histórico
│   ├── settings.html, js/settings.js Configurações, gravador de atalhos e Pix
│   └── toast.html, pin.html, recbar.html
└── src-tauri/src/
    ├── lib.rs        Estado, comandos IPC, protocolo cpframe://, inicialização
    ├── capture.rs    Congela o monitor sob o mouse, lista janelas, finaliza (copiar/salvar/fixar/OCR)
    ├── recorder.rs   Gravação: quadros da xcap → ffmpeg (H.264 + AAC) em ritmo constante
    ├── history.rs    Histórico: vigia a área de transferência, classifica e salva
    ├── actions.rs    Atalhos globais e argumentos de linha de comando
    ├── ui.rs         Janelas (pré-criadas ocultas para abrir na hora), toast, imagem fixada
    ├── tray.rs       Ícone e menu perto do relógio
    ├── settings.rs   Preferências
    └── platform.rs   → windows/ ou linux/
```

## Por que é rápido

- **Janelas prontas:** o histórico e o editor são criados ocultos ao iniciar. O atalho só posiciona e mostra a janela.
- **Sem codificar a tela congelada:** o protocolo `cpframe://` entrega os pixels RGBA brutos, que viram um `ImageBitmap` na GPU sem passar por PNG.
- **A janela só aparece quando a imagem já está desenhada**, sem flash da captura anterior.
- **Exportação nítida:** o recorte e as anotações são desenhados na resolução física do monitor (`escala = pixels da tela / largura CSS`).
- **Histórico barato:** no Windows, a área de transferência só é lida quando o contador de mudanças do sistema avança.

## Desenvolver

```bash
cd core
npm install
npx tauri dev        # abre o app com recarga
npx tauri build      # instaladores em ../target/release/bundle/
```

No Mac, `tauri dev` também funciona, para testar a interface. Para uso diário no Mac, use o app nativo de [`../macos`](../macos).

Para verificar a compilação para Windows a partir de outro sistema: `CP_CROSS_CHECK=1 cargo check --target x86_64-pc-windows-msvc`.
