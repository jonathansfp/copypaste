#!/bin/bash
# Compila o CopyPaste para Linux e gera AppImage, .deb e .rpm.
# Uso (na raiz do repositório):  ./linux/build.sh          (instala as dependências com --deps)
set -euo pipefail
cd "$(dirname "$0")/../core"

if [ "${1:-}" = "--deps" ]; then
  if command -v apt-get >/dev/null; then
    sudo apt-get update
    sudo apt-get install -y libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev patchelf \
      libxdo-dev libxcb1-dev libxcb-randr0-dev libxrandr-dev libdbus-1-dev libpipewire-0.3-dev libspa-0.2-dev \
      libwayland-dev libegl1-mesa-dev libgbm-dev libdrm-dev clang libclang-dev libssl-dev libasound2-dev build-essential file rpm curl
  elif command -v dnf >/dev/null; then
    sudo dnf install -y webkit2gtk4.1-devel libappindicator-gtk3-devel librsvg2-devel libxdo-devel libxcb-devel \
      libXrandr-devel dbus-devel pipewire-devel wayland-devel mesa-libEGL-devel mesa-libgbm-devel libdrm-devel \
      clang clang-devel openssl-devel alsa-lib-devel rpm-build file curl
  else
    echo "Instale manualmente as dependências equivalentes às do Ubuntu (veja linux/README.md)."
  fi
fi

for tool in cargo npm; do
  command -v $tool >/dev/null || { echo "Falta '$tool'. Rust: https://rustup.rs · Node.js 18+: https://nodejs.org"; exit 1; }
done

npm ci
npx tauri build

echo
echo "✅ Pronto:"
ls -1 ../target/release/bundle/appimage/*.AppImage ../target/release/bundle/deb/*.deb ../target/release/bundle/rpm/*.rpm 2>/dev/null | sed 's/^/   /'
echo
echo "Extras recomendados: sudo apt install xdotool ffmpeg tesseract-ocr tesseract-ocr-por"
