#!/bin/bash
# Gera dist/CopyPaste-<versão>.dmg (arrastar para Aplicativos) e um .zip.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
mkdir -p dist
STAGE=$(mktemp -d)
cp -R build/CopyPaste.app "$STAGE/"
ln -s /Applications "$STAGE/Aplicativos"
cat > "$STAGE/LEIA-ME.txt" <<'TXT'
Instalação do CopyPaste
1. Arraste o CopyPaste para a pasta Aplicativos.
2. Na primeira vez, clique com o botão direito no CopyPaste > Abrir > Abrir
   (o app não é assinado pela Apple, então o macOS pede essa confirmação).
   Se aparecer "está danificado", rode no Terminal:
   xattr -dr com.apple.quarantine /Applications/CopyPaste.app
3. Libere em Ajustes do Sistema > Privacidade e Segurança > Acessibilidade
   para ele conseguir colar sozinho.
Atalho padrão: ⇧⌘V
TXT
DMG="dist/CopyPaste-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "CopyPaste" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
ditto -c -k --keepParent build/CopyPaste.app "dist/CopyPaste-$VERSION.zip"
echo "✅ $DMG"
echo "✅ dist/CopyPaste-$VERSION.zip"
