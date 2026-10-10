# Alleyway Brawlers: Godot client

The game: a Godot 4.7 desktop client with all the menus, the duel and the tutorial. (It began as a
port of an earlier Phaser web client, since retired.) It talks to the game server in `backend/`,
which stays in charge of accounts, currency, cards, decks and match rewards.

## First-time setup
1. Copy the art and audio in from `assets/` (the master copy at the top of the repo). They are
   gitignored here, so the art isn't stored in git twice.
   ```
   powershell -ExecutionPolicy Bypass -File godot/tools/sync_assets.ps1
   ```
   On Linux, run `sh godot/tools/sync_assets.sh` instead.
2. Open Godot. Click **Import**, choose `godot/project.godot`, then press **F5** to play.
3. The default server is `https://alleywaybrawlers.duckdns.org` (the home server behind Apache, so
   friends can play from anywhere). To change it, open **Settings → Server** on the login screen;
   on the home network `http://192.168.0.200:3000` also works.

If a card changes in `shared/cards.js`, regenerate the card data with
`node godot/tools/export_cards.mjs`. Players don't need a new build for card changes: at start-up
the game downloads new or changed cards from the server (`scripts/content_sync.gd`, with a
download screen) and checks its version (see `docs/CARD_PIPELINE.md`).

## Screens
| Screen | What it does |
|---|---|
| Login | Log in, register or reset your password. **Play Offline** gives CPU duels with the starter deck; nothing is saved. |
| Clan select | Choose your starting clan on first login. The server seeds your starter inventory and deck. |
| Main menu | The player bar shows your level, XP, currencies and unread mail. It also has quests (with Claim buttons), Fight, Deck Editor, Card Library, Shop, Profile and Social. **Esc** opens Settings. |
| Fight mode | Casual, Ranked (from level 5) or VS CPU. Every mode uses your saved active deck, which must have 40 cards. **How to Play** starts the tutorial. |
| Tutorial | A guided first duel (`scripts/duel/tutorial.gd`): a coach panel teaches Authority, summoning, attacking, Downed and K.O., DEF cards, leaders and Direct Attacks, then you finish the match. It picks cheap cards from the current card data and switches their effects off. The main menu offers it once to new players. |
| Rock-paper-scissors | Decides who goes first. The winner picks. |
| Duel | Uses your deck, leader and promoted forms, and opens a server match session. |
| Post-match | Shows the result, stats, the MVP card, and the rewards from the server. |
| Shop | Card packs with a pack-opening reveal. Rarer cards get more build-up. Contraband bundles are on their own screen. |
| Deck builder | Click or drag cards in and out. Also handles filters, search, the leader slot, several decks and the active deck. |
| Card library | Shows your collection, or every card in the game, with filters and a detail panel. |
| Profile, Mailbox, Social | Avatar and stats; read and delete mail; friends, requests and chat history. |
| Settings | Volume, window mode, resolution, v-sync, FPS cap, FPS counter, and the server address. |

Right-click any card to zoom it.

## Online play
- **Casual Brawl** puts you in the online queue against another player. It uses your active
  deck and doesn't change Rank Points. You can also **Challenge** an online friend from Social.
  Live chat is there too.
- **VS CPU and Ranked run on the server too**, against a server-side CPU (`shared/duel/DuelAI.js`,
  a copy of `scripts/duel/duel_ai.gd`). The server sees the result, so it pays the rewards
  (up to 25 rewarded CPU matches a day). Only Ranked moves Rank Points. Offline play and the
  tutorial still run in the client and pay nothing. The old `/api/match/complete` route (a
  result the client reports) no longer pays rewards.
- **The server runs every online match.** `backend/socket/onlineMatch.js` uses
  `shared/duel/DuelState.js`, a JavaScript copy of `scripts/duel/duel_state.gd`. Clients only
  send moves. Each player gets the events they're allowed to see: not the opponent's hand, deck
  or face-down cards. The server records the result and pays the rewards.
- **Timeouts.** Whoever has to act has 90 seconds; after that the server makes a safe move for
  them. If a player disconnects, they have 45 seconds to come back before losing. Reconnecting
  resumes the match.
- `scripts/net.gd` is the realtime connection: a small Socket.io client over a WebSocket.
- If you change the rules in either engine, change the other too, then check they still match:
  ```
  godot --headless --path godot --script res://tests/export_golden.gd -- golden.json 100
  node shared/duel/engine.test.mjs golden.json   # also checks the server CPU picks the same moves
  ```

## Duel controls
| Action | Input |
|---|---|
| See a card's details | Hover over it |
| Play a card | Click it in your hand for options, or drag it onto a slot |
| Attack | In the Brawl phase, click a glowing character, then click a target: an enemy character, or their dormant leader (always allowed) to hit its Influence. When the enemy has no standing characters (none, or only Downed ones), you can also attack directly |
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
| `scripts/duel/card_view.gd` | One card on the board. It tilts in 3D toward the mouse and into its motion, recoils from hits, and flips over in 3D. |
| `scripts/duel/attack_arrow.gd` | The curved targeting arrow. |
| `shaders/card.gdshader` | 3D tilt, light sheen and holographic foil (Epic and Legendary) for every card, in the duel and the menus. |
| `shaders/post.gdshader` | Full-screen hit effects: shockwaves, colour split, impact frames, and the red low-Morale vignette. |
| `scripts/sfx.gd` | Sound effects. They are generated in code until real files are added to `assets/sfx/<name>.wav` or `.ogg`. |
| `data/cards.json` | Card data, exported from `shared/cards.js`. |

## Tests
Replace `godot` with the path to the console exe.
```
godot --headless --path godot --script res://tests/sim.gd                # 200 CPU-vs-CPU games on the rules
godot --headless --fixed-fps 60 --path godot res://tests/ui_smoke.tscn   # clicks through summon, attack and prompts
godot --path godot -- --autoplay                                         # the CPU plays both sides
godot --headless --fixed-fps 60 --path godot res://tests/tutorial_smoke.tscn  # plays the whole tutorial
```
To try the menus without the real server, there is a fake server that keeps its data in
memory. Start it, then run the screenshot tour, or point **Settings → Server** at
`http://127.0.0.1:3999` and log in with any email and password.
```
node godot/tests/mock_server.mjs
godot --path godot res://tests/screens_tour.tscn -- <folder for screenshots>
```
The fake server also runs the real online-match service. Two test players can queue and play
each other; add `--drop` to one to test reconnecting, or `--concede` to test conceding.
```
godot --headless --fixed-fps 60 --path godot res://tests/online_bot.tscn -- a@test http://127.0.0.1:3999 --autoplay
godot --headless --fixed-fps 60 --path godot res://tests/online_bot.tscn -- b@test http://127.0.0.1:3999 --autoplay
```

## Notes
- Cards use the compatibility renderer, with mipmaps and BC7 compression on import, so card art
  stays sharp at any size.
- On this AMD PC, launching Godot from a script crashes the OpenGL driver. Add
  `--rendering-driver opengl3_angle` when recording frames from the command line.
  The editor and normal play are not affected.
