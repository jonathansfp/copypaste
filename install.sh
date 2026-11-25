#!/bin/bash
# Compila, instala em /Applications e abre o CopyPaste.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill -x CopyPaste 2>/dev/null || true
sleep 0.5
rm -rf /Applications/CopyPaste.app
cp -R build/CopyPaste.app /Applications/
open /Applications/CopyPaste.app
echo "✅ Instalado em /Applications/CopyPaste.app"
