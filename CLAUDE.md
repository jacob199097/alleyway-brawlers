# AlleyWay Brawlers

- `client/` — Phaser 3 + Vite game client (web/mobile; desktop build planned via Electron).
- `godot/` — Godot 4.7 desktop client: menus + duel, same backend API (see `godot/README.md`); art is synced from
  `client/assets`, card data exported from `shared/cards.js`.
- `backend/` — Node/Express/Socket.io + Postgres. Runs on the Linux server (192.168.0.200) as the
  `alleyway-backend` systemd service; it is the authority for auth, economy, matches and decks.
  Never move reward/currency/card logic into the client.
- Desktop/Steam work follows `docs/DESKTOP_PLAN.md` — do phases in order; keep the web build working.
- Client talks to the server via `VITE_SERVER_URL` (e.g. `http://192.168.0.200:3000`).
- Code is edited on both the PC and the server: `git pull` before starting, push when done.
