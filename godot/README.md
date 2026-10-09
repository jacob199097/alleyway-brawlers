# Alleyway Brawlers: Godot client

The desktop client in Godot 4.7. It is a port of the Phaser client in `client/`, with all the
menus and the duel. It talks to the same backend, and the server stays in charge of accounts,
currency, cards, decks and match rewards.

## First-time setup
1. Copy the art and audio in from `client/assets`. They are gitignored here, so the art is
   not stored in git twice.
   ```
   powershell -ExecutionPolicy Bypass -File godot/tools/sync_assets.ps1
   ```
   On Linux, run `sh godot/tools/sync_assets.sh` instead.
2. Open Godot. Click **Import**, choose `godot/project.godot`, then press **F5** to play.
3. The default server is `http://192.168.0.200:3000`. To change it, open **Settings → Server**
   on the login screen. For friends on a VPN such as Tailscale, use the server PC's VPN address.

If a card changes in `shared/cards.js`, regenerate the card data with
`node godot/tools/export_cards.mjs`.

## Screens
| Screen | What it does |
|---|---|
| Login | Log in, register or reset your password. **Play Offline** gives CPU duels with the starter deck; nothing is saved. |
| Clan select | Choose your starting clan on first login. The server seeds your starter inventory and deck. |
| Main menu | The player bar shows your level, XP, currencies and unread mail. It also has quests (with Claim buttons), Fight, Deck Editor, Card Library, Shop, Profile and Social. **Esc** opens Settings. |
| Fight mode | Casual, Ranked (from level 5) or VS CPU. Every mode uses your saved active deck, which must have 40 cards. |
| Rock-paper-scissors | Decides who goes first. The winner picks. |
| Duel | Uses your deck, leader and promoted forms, and opens a server match session. |
| Post-match | Shows the result, stats, the MVP card, and the rewards from the server. |
| Shop | Card packs with a pack-opening reveal. Rarer cards get more build-up. Contraband bundles are on their own screen. |
| Deck builder | Click or drag cards in and out. Also handles filters, search, the leader slot, several decks and the active deck. |
| Card library | Shows your collection, or every card in the game, with filters and a detail panel. |
| Profile, Mailbox, Social | Avatar and stats; read and delete mail; friends, requests and chat history. |
| Settings | Volume, window mode, resolution, v-sync, FPS cap, FPS counter, and the server address. |

Right-click any card to zoom it. Live chat and challenges need the realtime connection, which
arrives with online play.

## Duel controls
| Action | Input |
|---|---|
| See a card's details | Hover over it |
| Play a card | Click it in your hand for options, or drag it onto a slot |
| Attack | In the Brawl phase, click a glowing character, then click a target. When the enemy front row is empty, attack directly, or click their dormant leader to hit its Influence |
| Character actions | Click your character to change its position, promote it (Maya) or use its ability (Maya Lv.3) |
| Card prompts | Effects that say "you may" or "choose" open a panel. Click an option, or click a highlighted card |
| Next phase | **Space** / **Enter**, or the button on the right |
| Cancel | Right-click |
| Menu (settings, leave duel) | **Esc** |
| Fullscreen | **F11** |

## How it is built
| Path | What it does |
|---|---|
| `scripts/api.gd` | Server requests (`Api.request(method, path, body)`). |
| `scripts/game.gd` | The signed-in player, screen changes, settings, menu music, and loading your deck for a duel. |
| `scripts/ui/` | Shared look (`UI`), the card tile used in grids, and the card zoom. |
| `scripts/screens/` | One script per menu screen. The matching scenes are in `scenes/`. |
| `scripts/duel/duel_state.gd` | The rules, as pure data. Actions go in as dictionaries and every change comes out as an event. These could later run on the server unchanged. |
| `scripts/duel/duel_ai.gd` | The CPU player. It picks one action at a time. |
| `scripts/duel/duel.gd` | The duel screen. It plays each event as an animation. |
| `scripts/sfx.gd` | Sound effects. They are generated in code until real files are added to `assets/sfx/<name>.wav` or `.ogg`. |
| `data/cards.json` | Card data, exported from `shared/cards.js`. |

## Tests
Replace `godot` with the path to the console exe.
```
godot --headless --path godot --script res://tests/sim.gd                # 200 CPU-vs-CPU games on the rules
godot --headless --fixed-fps 60 --path godot res://tests/ui_smoke.tscn   # clicks through summon, attack and prompts
godot --path godot -- --autoplay                                         # the CPU plays both sides
```
To try the menus without the real server, there is a fake server that keeps its data in
memory. Start it, then run the screenshot tour, or point **Settings → Server** at
`http://127.0.0.1:3999` and log in with any email and password.
```
node godot/tests/mock_server.mjs
godot --path godot res://tests/screens_tour.tscn -- <folder for screenshots>
```

## Notes
- Cards use the compatibility renderer, with mipmaps and BC7 compression on import, so card art
  stays sharp at any size.
- On this AMD PC, launching Godot from a script crashes the OpenGL driver. Add
  `--rendering-driver opengl3_angle` when recording frames from the command line.
  The editor and normal play are not affected.
