# AlleyWay Brawlers

- `godot/` — the game: a Godot 4.7 desktop client (menus, duel, tutorial). See `godot/README.md`.
  Windows builds go to `builds/` (export preset "Windows Desktop").
- `assets/` — master copy of all art and audio. Godot copies it in with `godot/tools/sync_assets`;
  the server serves card images, card backs and sounds (`assets/sfx`, see its README) to the game, which
  downloads new or changed ones at start-up (no new build needed).
- `shared/` — card catalogue (`cards.js` + generated `cards_forge.js`), the server's copy of the rules
  (`duel/DuelState.js`, must match `godot/scripts/duel/duel_state.gd`; the golden test checks) and the
  server CPU (`duel/DuelAI.js`, matches `duel_ai.gd`). `game_version.json` = latest/minimum game version.
- `backend/` — Node/Express/Socket.io + Postgres. Runs on the Linux server (192.168.0.200) as the
  `alleyway-backend` systemd service, public at https://play.alleywaybrawlers.com (Apache proxy; the older https://alleywaybrawlers.duckdns.org
  still works: builds before 0.9.140 call it).
  It is the authority for auth, economy, matches (online and CPU) and decks.
  Never move reward/currency/card logic into the client.
  Pre-launch, every player gets every clan's starter deck (`GIVE_ALL_STARTERS` in `backend/routes/onboarding.js`):
  turn it off for the launch wipe.
  Crafting (Dust), achievements, the daily reward and the leaderboard live in `backend/economy/`. The privacy
  policy and terms are pages on the server (`backend/routes/legal.js`): keep them true to what the server stores. Database changes go in a `db/migrate_*.sql`
  file (idempotent) listed in `db/migrate.js`, which applies them when the server starts.
- New cards come from the Card Forge (or Card Forge 2, more art storage, numbers from 501): `node tools/import_forge.mjs <zip>`, then on the server
  `node backend/scripts/sync_cards.mjs` (see `docs/CARD_PIPELINE.md`). Clans come from the card data
  (`shared/clans.js`): no code names a clan, except Neutral (`NEUTRAL`: cards for any deck, no clan of their own;
  a deck holds its leader's clan and Neutral cards only). `node tools/balance.mjs` reports how each card does.
- Rules changes go in both engines; re-run `godot/tests/export_golden.gd` + `shared/duel/engine.test.mjs`.
- Code is edited on both the PC and the server: `git pull` before starting, push when done.
  `node tools/deploy.mjs` pulls + restarts the server over SSH (host `alleyway`, see "Deploying" in
  `docs/CARD_PIPELINE.md`); every push runs the tests (`.github/workflows/tests.yml`).
- Game updates: small code updates ship as patches (`tools/make_patch.mjs`, `godot/scripts/patcher.gd`,
  which must stay the first autoload); see "Game versions and updates" in `docs/CARD_PIPELINE.md`.
  The Mac build (`tools/build_mac.mjs`) gets its own patch each update too: `make_patch.mjs <godot> --macos`.
- Turf Defense (2 players vs a clan boss): bosses, levels, lines and rewards in `godot/data/bosses.json`
  (the server reads it via `shared/turf.js`); matches `backend/socket/coopMatch.js`, rewards `backend/economy/turf.js`.
- Ranked seasons: `backend/economy/seasons.js` (numbers in `season_settings.js`, each season's Legend prize card in
  `shared/seasons.js`), `godot/scripts/ui/seasons.gd`. Rewards go by the highest rank reached, claimed in the game; a new
  season drops every rank two. Season 0 runs until launch. End one with `node backend/scripts/season.mjs end --apply`.
- The turf map (weekly clan control of districts = the arenas) is `backend/economy/territory.js` + `screens/territory.gd`;
  veteran cards (card XP per card → a bronze / chrome / gold frame, card.gdshader) are `backend/economy/veterans.js`.
- The auction house (players sell cards for Karat): `backend/economy/auction.js` + `screens/auction_house.gd`, every number
  (price floors and ceilings, fees, level / account-age limits) in `backend/economy/auction_settings.js`. Sales that look like one
  person trading with their own accounts get flagged: `node backend/scripts/auction_report.mjs` on the server.
  Rank emblems made in ChatGPT come in with `godot/tools/import_rank_icons.gd`.
- Steam (`docs/STEAM.md`): GodotSteam in `godot/addons/godotsteam`, `godot/scripts/steam.gd` (on only in the "Windows Steam"
  export, feature `steam`, or with `--steam`); server `backend/routes/steam.js`; `tools/steam_build.mjs` builds and uploads.
- Android (`docs/ANDROID.md`): `node tools/build_android.mjs <godot>` (lighter pictures, from a copy in `builds/android_project/`),
  `node tools/deploy.mjs --build-android`; touch controls in `godot/scripts/touch.gd`, `Game.mobile()` for phone-only behaviour,
  no black bars via `godot/scripts/widescreen.gd` (the 1920×1080 frame centred, `Game.wide.margin`). Android gets its own
  patch each update too: `make_patch.mjs <godot> --android`.
- The website (https://alleywaybrawlers.com, `website/README.md`): the game server sends it too. Addresses in `backend/routes/site.js`,
  pages in `backend/site/pages.js`, built from the game's own files (`backend/site/data.js`: cards, clans, keywords, How to Play,
  patch notes), so it names no clan and needs no upkeep for new cards. Styles, script and screenshots in `website/`
  (`tools/site_shots.mjs` retakes the screenshots); `node tools/site_dev.mjs` runs it on the PC; test `backend/site/site.test.cjs`.
  It shows nothing about players and loads no cookies, trackers or files from other sites: keep it so. Visits are counted as
  daily totals only (`backend/site/visits.js`), shown at `/stats` behind `SITE_STATS_PASSWORD` in the server's .env.
- `docs/LAUNCH_CHECKLIST.md` — what changes at launch (the wipe, starters off, 1.0.0, Steam live), in order.
- `docs/ROADMAP.md` — the to do / eventually list: bigger features parked for later (not started).
