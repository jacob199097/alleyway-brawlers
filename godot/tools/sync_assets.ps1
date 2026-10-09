# Copies the art and audio the Godot client uses from client/assets into godot/assets.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File godot/tools/sync_assets.ps1
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot '..\..\client\assets'
$dst = Join-Path $PSScriptRoot '..\assets'

New-Item -ItemType Directory -Force (Join-Path $dst 'cards') | Out-Null
Copy-Item (Join-Path $src 'cards\*.png') (Join-Path $dst 'cards') -Force
foreach ($f in 'card_back.png', 'duel_background.png', 'profile_001.png', 'profile_002.png', 'duel_theme.mp3') {
    Copy-Item (Join-Path $src $f) $dst -Force
}
Write-Host "Assets synced to $((Resolve-Path $dst).Path)"
