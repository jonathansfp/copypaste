# 🍎 CopyPaste para macOS

App 100% nativo em Swift (AppKit + SwiftUI + ScreenCaptureKit), sem dependências. A documentação completa (recursos, atalhos, permissões, assinatura, arquitetura e solução de problemas) está no [README principal](../README.md).

## Baixar

[**CopyPaste-macOS.dmg**](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-macOS.dmg) (macOS 14+, Apple Silicon e Intel)

## Compilar

```bash
cd macos
./build.sh     # build/CopyPaste.app (universal)
./install.sh   # compila, instala em /Applications e abre
./package.sh   # dist/CopyPaste-<versão>.dmg e .zip
```

**Ditado por voz:** código em `Sources/CopyPaste/Dictation/`: `AIProviders.swift` (Claude, OpenAI, Gemini, DeepSeek e Grok via HTTPS, chaves no Porta-chaves), `DictationController.swift` (microfone, transcrição da Apple ou da nuvem, ajuste pela IA, colagem e a pílula flutuante) `DictationSettingsView.swift` e `LocalAI.swift` (IA local: baixa o llama.cpp e o Gemma 4 E2B fixados e conferidos por SHA-256, e roda o `llama-server` só em 127.0.0.1). `UpdateChecker.swift` procura novas versões uma vez por semana.

Requer o Xcode 15+. Com um certificado Apple Development no Keychain, o `build.sh` assina com ele, e as permissões de Gravação de Tela e Acessibilidade continuam valendo entre compilações.
