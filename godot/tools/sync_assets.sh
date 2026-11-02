#!/bin/sh
# Copies the art and audio the Godot client uses from assets/ (the master copy) into godot/assets.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../../assets"
dst="$here/../assets"
for dir in cards ranks levels emblems; do
    mkdir -p "$dst/$dir"
    cp "$src/$dir"/*.png "$dst/$dir/"
done
# Level profile pictures (assets/avatars), once there are any
if ls "$src/avatars"/*.png >/dev/null 2>&1; then
    mkdir -p "$dst/avatars"
    cp "$src/avatars"/*.png "$dst/avatars/"
fi
mkdir -p "$dst/sfx"
for f in "$src/sfx"/*.ogg "$src/sfx"/*.wav "$src/sfx"/*.mp3; do
    if [ -e "$f" ]; then cp "$f" "$dst/sfx/"; fi
done
# Everything at the top level except the unused frame art and the menu video (Godot can't play mp4)
for f in "$src"/*.png "$src"/*.mp3; do
    [ "$(basename "$f")" = "Cropped_Frame.png" ] || cp "$f" "$dst/"
done
# The big backdrops (arenas, turf map) are .jpg, imported lossy (WebP) rather than VRAM-compressed:
# a few MB each in the game and its patches instead of ~13
for f in "$src"/*.jpg; do
    [ -e "$f" ] || continue
    cp "$f" "$dst/"
    imp="$dst/$(basename "$f").import"
    [ -e "$imp" ] || printf '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=1\ncompress/lossy_quality=0.9\nmipmaps/generate=true\n' > "$imp"
done
echo "Assets synced to $dst"
