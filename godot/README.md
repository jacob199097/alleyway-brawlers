# Alleyway Brawlers: Godot client (trial)

A trial port of the duel to Godot 4.7, to compare with the Phaser client in `client/`.
It has the desktop duel board only, against the CPU, using the starter test decks.
There are no menus and no server connection yet.

## First-time setup
1. Copy the art and audio in from `client/assets`. They are gitignored here, so the art is
   not stored in git twice.
   ```
   powershell -ExecutionPolicy Bypass -File godot/tools/sync_assets.ps1
   ```
   On Linux, run `sh godot/tools/sync_assets.sh` instead.
2. Open Godot. Click **Import**, choose `godot/project.godot`, then press **F5** to play.

If a card changes in `shared/cards.js`, regenerate the card data with
`node godot/tools/export_cards.mjs`.

## Controls
| Action | Input |
|---|---|
| See a card's details | Hover over it |
| Play a card | Click it in your hand for options, or drag it onto a slot |
| Attack | In the Brawl phase, click a glowing character, then click a target |
| Next phase | **Space** / **Enter**, or the button on the right |
| Cancel | Right-click |
| Menu | **Esc** |
| Fullscreen | **F11** |

## How it is built
| Path | What it does |
|---|---|
| `scripts/duel/duel_state.gd` | The rules, as pure data. Actions go in as dictionaries and every change comes out as an event. These could later run on the server unchanged. |
| `scripts/duel/duel_ai.gd` | The CPU player. It picks one action at a time. |
| `scripts/duel/duel.gd` | The duel screen. It plays each event as an animation: draw flights, summon slams, attack lunges, K.O. shatters, promotion light columns, effect call-outs and turn banners. |
| `scripts/duel/card_view.gd` | One card on screen: art, flip, glow and the ATK/DEF badge. |
| `scripts/sfx.gd` | Sound effects. They are generated in code until real files are added to `assets/sfx/<name>.wav` or `.ogg`. |
| `scenes/duel.tscn` | The screen layout. Panels can be moved and resized in the editor. |
| `data/cards.json` | Card data, exported from `shared/cards.js`. |

## Tests
These run with no window. Replace `godot` with the path to the console exe.
```
godot --headless --path godot --script res://tests/sim.gd                # 200 CPU-vs-CPU games on the rules
godot --headless --fixed-fps 60 --path godot res://tests/ui_smoke.tscn   # clicks through summon + attack
```
Autoplay, where the CPU plays both sides, is useful for checking animations:
```
godot --path godot -- --autoplay
```

## Notes
- Cards use the compatibility renderer, with mipmaps and BC7 compression on import, so card art
  stays sharp at any size.
- On this AMD PC, launching Godot from a script crashes the OpenGL driver. Add
  `--rendering-driver opengl3_angle` when recording frames from the command line.
  The editor and normal play are not affected.
