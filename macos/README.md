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

Requer o Xcode 15+. Com um certificado Apple Development no Keychain, o `build.sh` assina com ele, e as permissões de Gravação de Tela e Acessibilidade continuam valendo entre compilações.
