# AlleyWay Brawlers — Desktop (Steam) Plan

## Context
The game is a Phaser 3 + Vite web client (`client/`) built for mobile landscape: a fixed
844×390 logical canvas, `Phaser.Scale.FIT`, touch-first input. The backend (`backend/`) runs on a
separate Linux server and is authoritative for auth, economy, matches and decks. **Don't move game
rules or rewards into the client.**

Goal: ship a native Windows desktop build on Steam with real desktop features: windowed/borderless/
fullscreen, resolution, render quality, v-sync and FPS cap, mouse/keyboard, Steam login, Steam
purchases and achievements. The **web/mobile build must keep working** from the same client code.

Decision: **wrap the existing Phaser client in Electron**. Don't rewrite in another engine. Use
`steamworks.js` for Steam. Electron's bundled Chromium gives consistent WebGL across PCs and works
with the Steam overlay.

## Architecture

```
desktop/                    ← new Electron app (own package.json)
  main.js                   ← BrowserWindow, display modes, Chromium flags, Steam init, IPC
  preload.js                ← contextBridge → window.desktop (no nodeIntegration in renderer)
  settings.js               ← read/write settings.json in app.getPath('userData')
  steam.js                  ← steamworks.js wrapper (auth ticket, overlay, achievements, MTX)
  electron-builder.yml      ← Windows installer + Steam depot output
client/
  utils/Platform.js         ← isDesktop = !!window.desktop; API_BASE; apiFetch()
  utils/SettingsManager.js  ← extended: display settings, desktop persistence via window.desktop
  scenes/SettingsScene.js   ← new Display/Graphics tabs (desktop only)
```

- The renderer loads the **Vite production build** (`client/` → `dist/`). Serve it through a custom
  `app://` protocol (`protocol.handle`), not `file://`, so the origin is stable (keeps
  `localStorage`) and video/audio autoplay works.
- In dev, Electron loads `http://localhost:5173` so Vite hot reload still works.
- Security: `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`. Only expose
  narrow, typed functions through `preload.js`.

## Phase 1 — Electron shell (first milestone)
1. **Single API base.** Add `client/utils/Platform.js` exporting `API_BASE`, taken from
   `import.meta.env.VITE_SERVER_URL` with `''` as the default for web, and `apiFetch(path, opts)`.
   It should attach the auth header from the registry/localStorage token. Replace all
   `fetch('/api/...')` calls (30 calls across 14 files: `grep -rn "fetch(['\`]/api" client`).
   `network/SocketClient.js` already uses `VITE_SERVER_URL`; use `API_BASE` there as well.
2. Create `desktop/` with Electron + electron-builder. Scripts: `npm run dev` (Electron →
   Vite dev server) and `npm run build` (build client, package app).
3. Desktop-specific behaviour, branched on `isDesktop`:
   - Remove the mobile meta and touch tweaks only when on desktop (`touch-action`, orientation).
   - Keep `disableContextMenu`, and use right-click for card zoom (Phase 4).
4. **Done when:** an installed `.exe` launches, logs in against the server, plays a solo match
   and gets rewards. The web build (`npm run dev` in `client/`) still works unchanged.

## Phase 2 — Display & graphics settings (native features)
Extend `client/utils/SettingsManager.js`. It already has `bgmVolume`, `sfxVolume` and `quality`
presets with `resolutionScale`, `antialias` and `roundPixels`. Persist through
`window.desktop.settings.get/set` on desktop and keep `localStorage` on web. The main process reads
`settings.json` **before** creating the window, because some options only apply at launch.

| Setting | Values | How it's applied | Live / restart |
|---|---|---|---|
| Display mode | Windowed · Borderless · Fullscreen | `BrowserWindow`: `setFullScreen`, or frameless and sized to `screen.getDisplayMatching().bounds` for borderless | Live |
| Resolution (window size) | List from the current monitor, e.g. 1280×720, 1600×900, 1920×1080, 2560×1440, native | `win.setContentSize(w, h)` + center. In fullscreen/borderless it uses the monitor's native size | Live |
| Monitor | Displays from `screen.getAllDisplays()` | Move window bounds onto that display | Live |
| Render scale | 50 / 75 / 100 / 150 / 200 % | Internal canvas size relative to the window. Replaces the current `resolutionScale`. Above 100% supersamples (sharper text and art on 1440p/4K) | Live (resize the game canvas) |
| Quality preset | Low · Medium · High · Custom | Sets render scale, antialias, post-FX (blur in `PostMatchScene`/`DuelScene`), video menu background (`VideoBackgroundScene` → static image on Low), particle density | Live, except antialias |
| Anti-aliasing | On · Off | Phaser `antialias` / WebGL context | **Restart** (shown in the UI) |
| V-sync | On · Off | Off = launch Chromium with `--disable-gpu-vsync` and `--disable-frame-rate-limit` (`app.commandLine.appendSwitch`, before `app.ready`) | **Restart** |
| FPS cap | 30 · 60 · 120 · 144 · 165 · 240 · Unlimited | Phaser `fps: { limit }` (Phaser ≥ 3.60). Most useful with v-sync off | Live (re-apply to `game.loop`) |
| Show FPS | On · Off | Small overlay that reads `game.loop.actualFps` | Live |
| Pause when unfocused | On · Off | `blur`/`focus` → `game.loop.sleep()`/`wake()` and mute | Live |

UI: add Display and Graphics sections to `SettingsScene`, hidden on web. Settings marked
"Restart" show "Restart required" and an **Apply & Restart** button
(`app.relaunch(); app.exit()`). Add a **Revert in 10s** confirmation when the display mode or
resolution changes, like native games do.

**Done when:** each setting persists across launches, and v-sync off shows FPS above the
monitor's refresh rate with the cap set to Unlimited.

## Phase 3 — 16:9 layout
The canvas is fixed at 844×390 (about 19.5:9), and 28 files hard-code `const W = 844, H = 390`.
- **3a (quick, ships first):** keep 844×390 logical, letterboxed on 16:9 screens, and rely on
  Phase 2 render scale for sharp output at high resolutions. Add a themed letterbox background
  instead of black bars.
- **3b (proper):** on desktop, use a 16:9 logical resolution (1920×1080, or 1280×720 with
  render scale). Move layout off hard-coded pixels to a shared `client/utils/Layout.js` (W, H,
  safe areas, anchors), one scene at a time: Main Menu → Duel → Deck Builder → Shop → the rest.
  `DuelScene.js` (~6k lines) is the biggest. Keep both aspect ratios working through `Layout`
  instead of forking scenes.

## Phase 4 — Mouse & keyboard
- Hover: card highlight and tooltip. Right-click or hold to zoom a card (`utils/CardZoom.js`).
- Shortcuts: Space/Enter = next phase, Esc = pause/settings menu, 1–9 = select a hand card,
  F11 = toggle fullscreen, Tab = show the graveyard/zone tooltip. Make them rebindable later.
- Show a cursor theme. Hide touch-only hints on desktop.

## Phase 5 — Steam integration (`desktop/steam.js`, `steamworks.js`)
1. **Login with Steam.** The client calls `getAuthTicketForWebApi('alleyway')` and posts it to a new
   `POST /api/auth/steam`. The server verifies it with
   `ISteamUserAuth/AuthenticateUserTicket` using the publisher Web API key (in `.env`), then finds
   or creates the player by `steam_id` (new column, unique) and returns the normal JWT. Players
   skip email and password on Steam. Optionally let existing email accounts link a Steam account.
2. **Purchases.** Steam requires Steam Microtransactions for in-game purchases (no Stripe in the
   Steam build). Add `POST /api/shop/steam/init`, where the server calls
   `ISteamMicroTxn/InitTxn` with a server-side bundle price, and
   `POST /api/shop/steam/finalize` (`FinalizeTxn`). Grant once per order id through the existing
   `payment_grants` table. Reuse `CONTRABAND_BUNDLES` in `backend/routes/shop.js`.
3. **Achievements.** The server decides when one is earned (first win, levels, packs opened) and
   tells the client, and the client calls `activateAchievement`. Never unlock purely on the client.
4. Steam overlay: needs a WebGL canvas and the window not to be transparent. Test Shift+Tab.
5. Steam Cloud isn't needed, because progress lives on the server. Only `settings.json` could sync.

## Phase 6 — Server & release readiness
- **Public server address.** `192.168.0.200` is LAN-only. Put the backend behind a domain with
  HTTPS, e.g. a Cloudflare Tunnel (no port forwarding) or a VPS. Set `VITE_SERVER_URL` for the
  desktop build, and update `APP_BASE_URL`/`APP_CLIENT_URL` in `backend/.env`.
- Lock CORS (`backend/server.js` uses `cors()` and Socket.io `origin: '*'`) to the web origin and
  the `app://` origin.
- Multiplayer: `MatchmakingScene` isn't reachable from any menu, and the server doesn't track
  hands or draw order (only per-match deck pools). Make it server-authoritative before you enable
  online play.
- Builds: electron-builder `nsis` installer for testing, plus the unpacked directory for the
  Steam depot (SteamPipe). Code-sign the exe to avoid SmartScreen warnings.

## Verification
- Web: `cd client && npm run dev` still plays end-to-end.
- Desktop dev: `cd desktop && npm run dev` opens the game and hot-reloads.
- Desktop build: install the `.exe` on a clean Windows machine, log in, play a solo match, open a
  pack, and change every Display/Graphics setting (relaunch to confirm it persists).
- V-sync/FPS: with v-sync Off and the cap at Unlimited, the FPS overlay goes above the monitor
  refresh rate. With v-sync On it matches the refresh rate.
- Steam (Phase 5): run with `steam_appid.txt` and the Steam client open. Check the overlay with
  Shift+Tab, Steam login, and a sandbox microtransaction.
