# Alleyway Brawlers

A street-gang trading card game. The game is the Godot desktop client in `godot/`; the server is
`backend/`.

## Playing / developing the game
1. Copy the art in: `powershell -ExecutionPolicy Bypass -File godot/tools/sync_assets.ps1`
2. Open Godot 4.7, **Import** `godot/project.godot`, press **F5**.
3. The default server is https://alleywaybrawlers.duckdns.org (on the home network
   `http://192.168.0.200:3000` also works; change it in Settings → Server).

More in `godot/README.md`: screens, controls, tests, and online play.

## Building for Windows
In Godot: Project → Export → Windows Desktop, or from a terminal:
```
godot --headless --path godot --export-release "Windows Desktop" ../builds/windows/AlleywayBrawlers.exe
```
Zip `builds/windows/AlleywayBrawlers.exe` and share it. Card changes don't need a new build (the game
downloads them); code changes do: raise `config/version` in `godot/project.godot` and the versions in
`shared/game_version.json`.

## Server
Runs on the Linux server as the `alleyway-backend` service (`backend/`, Node + Postgres). After pulling:
```
git pull && sudo systemctl restart alleyway-backend
```
New cards from the Card Forge: see `docs/CARD_PIPELINE.md`.
