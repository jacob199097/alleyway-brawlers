# Copies the art and audio the Godot client uses from assets/ (the master copy) into godot/assets.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File godot/tools/sync_assets.ps1
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot '..\..\assets'
$dst = Join-Path $PSScriptRoot '..\assets'

foreach ($dir in 'cards', 'ranks', 'levels', 'emblems') {
    New-Item -ItemType Directory -Force (Join-Path $dst $dir) | Out-Null
    Copy-Item (Join-Path $src "$dir\*.png") (Join-Path $dst $dir) -Force
}
# Level profile pictures (assets\avatars), once there are any
if (Get-ChildItem (Join-Path $src 'avatars\*.png') -ErrorAction SilentlyContinue) {
    New-Item -ItemType Directory -Force (Join-Path $dst 'avatars') | Out-Null
    Copy-Item (Join-Path $src 'avatars\*.png') (Join-Path $dst 'avatars') -Force
}
New-Item -ItemType Directory -Force (Join-Path $dst 'sfx') | Out-Null
Copy-Item (Join-Path $src 'sfx\*') (Join-Path $dst 'sfx') -Include '*.ogg', '*.wav', '*.mp3' -Force
# The big backdrops (arenas, turf map) are .jpg, imported lossy (WebP) rather than VRAM-compressed:
# a few MB each in the game and its patches instead of ~13
foreach ($f in Get-ChildItem (Join-Path $src '*.jpg')) {
    Copy-Item $f.FullName $dst -Force
    $imp = Join-Path $dst ($f.Name + '.import')
    if (-not (Test-Path $imp)) {
        [IO.File]::WriteAllText($imp, "[remap]`n`nimporter=`"texture`"`ntype=`"CompressedTexture2D`"`n`n[params]`n`ncompress/mode=1`ncompress/lossy_quality=0.9`nmipmaps/generate=true`n")
    }
}
# Everything at the top level except the unused frame art and the menu video (Godot can't play mp4)
Get-ChildItem $src -File | Where-Object { $_.Extension -in '.png', '.mp3' -and $_.Name -ne 'Cropped_Frame.png' } |
    Copy-Item -Destination $dst -Force
Write-Host "Assets synced to $((Resolve-Path $dst).Path)"
