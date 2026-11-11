# Launch checklist

Everything that changes between the pre-launch test game and the real launch, in the order to do it.
Tick items off as you go. The steps that need a decision are marked **Decide**.

## Weeks before

- [ ] **Steam app.** Steamworks account, the App ID, the depot (`docs/STEAM.md` steps 1-5):
  - `APP_ID` in `godot/scripts/steam.gd`.
  - On the server, in `backend/.env`: `STEAM_APP_ID`, `STEAM_PUBLISHER_KEY`, and `STEAM_MTX_SANDBOX=true`
    for now.
  - Achievements uploaded (`node tools/steam_achievements.mjs --csv`), and Microtransactions switched on.
- [ ] **Store page** up as "Coming Soon" at least two weeks before release: capsule images, screenshots,
  the description and tags. Put its address in `STORES` in `backend/site/pages.js`: the website's Steam
  badge then links to it (the same for Google Play once that page is up).
- [ ] **Test build on Steam:** `node tools/steam_build.mjs <Godot console exe> --upload --live` puts it on
  the "beta" branch. Install it from Steam (a free key from Steamworks), sign in with Steam, buy
  Contraband in the sandbox, and try it on a Steam Deck if you can.
- [x] **Contact address:** `CONTACT_EMAIL=support@alleywaybrawlers.com` in `backend/.env` since 0.9.140
  (Cloudflare Email Routing forwards it to alleywaybrawlers@gmail.com; the website, privacy policy and terms show it).
- [ ] **Read `/privacy` and `/terms` once more:** they must match what the server stores.
- [ ] **Card payments outside Steam:** the server has a Stripe *test* key (`sk_test_…`), so no money can
  move. **Decide:** sell Contraband outside Steam at launch? If so, switch to the live key (`sk_live_…`).
  If not, leave it, and the Windows and Mac downloads stay free to play without a shop.
- [ ] **Auction house and Steam:** **Decide:** trade only from accounts linked to Steam? Set `REQUIRE_STEAM: true`
  in `backend/economy/auction_settings.js` only if Steam is the only way to get the game: email accounts from
  the Windows and Mac downloads couldn't trade then. Either way, a Steam account costs money if the game does,
  which makes throwaway accounts for moving cards expensive.
- [ ] **Server:** set `NODE_ENV=production` in `backend/.env`. Today it isn't set, which only matters for
  the developer free-purchase switch (`DEV_FREE_PURCHASES`), but production should say so.
- [ ] **Uptime:** the server is a home PC. A UPS (battery backup) and an uptime monitor (e.g. UptimeRobot,
  free) at least; a rented server before a big push.

## The wipe

Pre-launch accounts have had every clan's starter deck, test currency and lots of free packs. **Decide**
what to keep. My suggestion:

| Keep | Reset |
|---|---|
| Accounts: email or Steam login, name, avatar | Collections and decks: back to their chosen clan's starter |
| Friends and chat | Karat, Dust, packs, gifts in the mail |
| Anything bought with real money (none so far: Stripe has been in test mode) | Level, XP, rank and Rank Points (`backend/scripts/reset_progress.js` does these two) |
| | Achievements, quests, mastery, veteran cards, turf map, match history and replays |
| | The auction house: every auction and bid (the cards in running auctions go with the collections) |

A wipe script doesn't exist yet: once you've decided, I'll write one like `reset_progress.js`. It will
show what it would do first, and only change things with `--apply`.

- [ ] **Starter decks:** set `GIVE_ALL_STARTERS = false` in `backend/routes/onboarding.js`. New players then
  get only their chosen clan's starter, and the "Every starter deck, on the house" mail stops.

## The launch version: 1.0.0

Nothing is removed. The version numbers get *set*, on purpose, so that every launch player is on the
same build:

- [ ] `config/version` in `godot/project.godot`, and in `shared/game_version.json` set `latest`,
  `minimum`, `patchBase` and `macos.patchBase`, all to `1.0.0`.
  - **Minimum** 1.0.0: every pre-launch build (0.9.x) has to update before it can play online, so
    nobody plays launch players with old rules.
  - **patchBase** 1.0.0: later updates are made against the launch build, so they stay small.
- [ ] Patch notes for 1.0.0 at the top of `godot/data/patch_notes.json` (players see them once).
- [ ] The website: the Alpha tag by the version (`STAGE`) and the note under its download buttons (alpha,
  accounts reset at launch: `PRELAUNCH`), both in `backend/site/pages.js`. Change or empty them and fix the
  test that looks for them (`backend/site/site.test.cjs`). See `website/README.md`.
- [ ] Full builds: Windows (`builds/windows_1.0.0/`, zipped as `AlleywayBrawlers-1.0.0-windows.zip`),
  Mac (`node tools/build_mac.mjs <Godot>`) and Steam (`node tools/steam_build.mjs <Godot> --upload`).
  See "Game versions and updates" in `docs/CARD_PIPELINE.md`.

## Launch day, in order

1. [ ] Tell players the server is going down for the launch (the in-game mail, and wherever else they are).
2. [ ] Fresh backup, copied to the PC: `node tools/backup_db.mjs --now`. Check it arrived in
   `Documents\AlleywayBrawlers-backups`.
3. [ ] Push the launch code (starters off, 1.0.0), then `node tools/deploy.mjs --build --build-mac`.
4. [ ] End Season 0, before the wipe: `node backend/scripts/season.mjs end` to read what it will do, then
   `node backend/scripts/season.mjs end --apply --name "Season 1" --weeks 13`. Each Ranked player's Season 0
   reward is recorded (by the highest rank they reached) and claimed in the game after the launch. Put the Legend
   prize card's game ID in `SEASON_PRIZES[0]` (`shared/seasons.js`) when it's made: Legends who claim later still
   get it. **The wipe must keep `player_seasons` and `seasons`.**
   Then run the wipe on the server: first without `--apply` to read what it will do, then with it.
5. [ ] On the server, in `backend/.env`: `STEAM_MTX_SANDBOX=false` (real Steam purchases), and the live
   Stripe key if you decided to sell outside Steam. Then `node tools/deploy.mjs` to restart.
6. [ ] Steamworks: make the 1.0.0 build the default branch, then press Release.
7. [ ] Quick test with a fresh account:
   - Steam sign-in, plus an email account on the Windows download.
   - Pick a clan; the starter deck arrives (one clan only).
   - Open a pack, play a CPU match, and play an online match between two accounts.
   - One real Contraband purchase on Steam (refund it afterwards).
8. [ ] Watch for problems for the first few hours:
   - `node backend/scripts/client_errors.js` on the server: errors and crashes sent by players' games.
   - `node tools/deploy.mjs --logs`: the server's log.

## After launch

- **Steam updates aren't patches.** The Steam build doesn't patch itself in the game. Every update has to
  be uploaded to Steam too (`node tools/steam_build.mjs <Godot> --upload`), alongside the usual Windows
  and Mac patches.
- Card-only updates (Forge imports) still need no new build: the game downloads new cards at start-up,
  the Steam build included.
- Backups: the server makes one every night, and the PC copies them every day at noon (the "AlleywayBrawlers
  DB backup copy" task in Windows Task Scheduler). Restoring one: `pg_restore -d <empty database> <file>`.
- The auction house: every week or so, `node backend/scripts/auction_report.mjs` on the server lists sales that
  look like one person trading with their own accounts (the same IP address, or the same two players again and
  again). It only flags: look before acting, since two people in one home share an IP address.
