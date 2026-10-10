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
  `alleyway-backend` systemd service, public at https://alleywaybrawlers.duckdns.org (Apache proxy).
  It is the authority for auth, economy, matches (online and CPU) and decks.
  Never move reward/currency/card logic into the client.
  Crafting (Dust) and achievements live in `backend/economy/`. Database changes go in a `db/migrate_*.sql`
  file (idempotent) listed in `db/migrate.js`, which applies them when the server starts.
- New cards come from the Card Forge: `node tools/import_forge.mjs <zip>`, then on the server
  `node backend/scripts/sync_cards.mjs` (see `docs/CARD_PIPELINE.md`). Clans come from the card data
  (`shared/clans.js`): no code names a clan. `node tools/balance.mjs` reports how each card does.
- Rules changes go in both engines; re-run `godot/tests/export_golden.gd` + `shared/duel/engine.test.mjs`.
- Code is edited on both the PC and the server: `git pull` before starting, push when done.
  `node tools/deploy.mjs` pulls + restarts the server over SSH (host `alleyway`, see "Deploying" in
  `docs/CARD_PIPELINE.md`); every push runs the tests (`.github/workflows/tests.yml`).
- Game updates: small code updates ship as patches (`tools/make_patch.mjs`, `godot/scripts/patcher.gd`,
  which must stay the first autoload); see "Game versions and updates" in `docs/CARD_PIPELINE.md`.
