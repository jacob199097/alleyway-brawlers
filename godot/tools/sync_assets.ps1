# Copies the art and audio the Godot client uses from assets/ (the master copy) into godot/assets.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File godot/tools/sync_assets.ps1
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot '..\..\assets'
$dst = Join-Path $PSScriptRoot '..\assets'

foreach ($dir in 'cards', 'ranks') {
    New-Item -ItemType Directory -Force (Join-Path $dst $dir) | Out-Null
    Copy-Item (Join-Path $src "$dir\*.png") (Join-Path $dst $dir) -Force
}
# Everything at the top level except the unused frame art and the menu video (Godot can't play mp4)
Get-ChildItem $src -File | Where-Object { $_.Extension -in '.png', '.mp3' -and $_.Name -ne 'Cropped_Frame.png' } |
    Copy-Item -Destination $dst -Force
Write-Host "Assets synced to $((Resolve-Path $dst).Path)"
