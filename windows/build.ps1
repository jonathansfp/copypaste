# Compila o CopyPaste para Windows e gera o instalador (.exe), o .msi e o executável portátil.
# Uso (PowerShell, na raiz do repositório):  .\windows\build.ps1
# Requisitos: Rust (https://rustup.rs) com o Visual Studio Build Tools (C++) e Node.js 18+.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\core")

foreach ($tool in "cargo", "npm") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "Falta '$tool'. Instale com:" -ForegroundColor Red
        Write-Host "  winget install Rustlang.Rustup OpenJS.NodeJS.LTS Microsoft.VisualStudio.2022.BuildTools"
        exit 1
    }
}

npm ci
npx tauri build

$bundle = Join-Path $PSScriptRoot "..\target\release\bundle"
Write-Host ""
Write-Host "Pronto:" -ForegroundColor Green
Get-ChildItem "$bundle\nsis\*.exe", "$bundle\msi\*.msi" | ForEach-Object { Write-Host "  $($_.FullName)" }
Write-Host "  $(Resolve-Path (Join-Path $PSScriptRoot '..\target\release\copypaste.exe'))  (portátil)"
Write-Host ""
Write-Host "Para gravar a tela, instale também o ffmpeg:  winget install Gyan.FFmpeg"
