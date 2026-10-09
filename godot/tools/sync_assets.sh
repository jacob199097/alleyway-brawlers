#!/bin/sh
# Copies the art and audio the Godot client uses from client/assets into godot/assets.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../../client/assets"
dst="$here/../assets"
for dir in cards ranks; do
    mkdir -p "$dst/$dir"
    cp "$src/$dir"/*.png "$dst/$dir/"
done
# Everything at the top level except the unused frame art and the menu video (Godot can't play mp4)
for f in "$src"/*.png "$src"/*.mp3; do
    [ "$(basename "$f")" = "Cropped_Frame.png" ] || cp "$f" "$dst/"
done
echo "Assets synced to $dst"
