#!/bin/bash
# Compila e monta build/CopyPaste.app
set -euo pipefail
cd "$(dirname "$0")"
APP=CopyPaste
# Usa o Xcode (necessário para os macros do SwiftUI) mesmo que o xcode-select aponte para as Command Line Tools.
if [ -d /Applications/Xcode.app ]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi

# Binário universal: funciona em Mac com chip Apple (M1/M2/M3…) e em Mac Intel.
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP"

[ -f Resources/AppIcon.icns ] || ./scripts/make_icon.sh

OUT="build/$APP.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
# Assina com um certificado estável (Apple Development do Xcode) quando existir: assim as permissões
# de Gravação de Tela / Acessibilidade continuam valendo depois de recompilar. Sem certificado, usa ad-hoc
# (o macOS então pede as permissões de novo a cada nova compilação). Dá para forçar com SIGN_IDENTITY=...
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --sign "$IDENTITY" --identifier local.copypaste.app \
    --entitlements Resources/CopyPaste.entitlements "$OUT"
  echo "🔏 Assinado com: $IDENTITY"
else
  codesign --force --sign - --identifier local.copypaste.app "$OUT"
  echo "⚠️  Assinatura ad-hoc: o macOS vai pedir as permissões de novo após cada compilação"
fi
echo "✅ $OUT pronto"
