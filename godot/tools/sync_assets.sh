#!/bin/sh
# Copies the art and audio the Godot client uses from client/assets into godot/assets.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../../client/assets"
dst="$here/../assets"
mkdir -p "$dst/cards"
cp "$src"/cards/*.png "$dst/cards/"
for f in card_back.png duel_background.png profile_001.png profile_002.png duel_theme.mp3; do
    cp "$src/$f" "$dst/"
done
echo "Assets synced to $dst"
