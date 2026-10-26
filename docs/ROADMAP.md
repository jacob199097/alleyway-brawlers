# AlleyWay Brawlers — to do / eventually

Bigger features and ideas parked for later. Nothing here is being built yet: tick an item off (`[x]`)
when it ships, or delete it if it's dropped.

## Platforms

- [x] **Mac build (Apple Silicon / ARM).** Done in 0.9.69: a universal app (Apple Silicon + Intel) built
  from the PC (`tools/build_mac.mjs`), with its own patches and download, playing online with Windows
  (see "Mac build" in `docs/CARD_PIPELINE.md`).
- [ ] **Mobile version, with cross-play (PC, Mac and mobile in the same matches).** Cross-play mostly
  comes for free: the server already runs matches, decks and rewards for every player
  (`backend/socket/onlineMatch.js`), and every client speaks the same socket protocol. The work is in
  the game: Android / iOS exports, touch controls (drag to attack, long-press for the right-click
  zoom), layouts that fit phone screens, lighter assets, and store accounts (Google $25 once, Apple
  $99/yr). `shared/game_version.json` minimum-version checks need to cover each platform.
- [ ] **Steam release.** The integration is built (`docs/STEAM.md`): what is left is the Steamworks account,
  the App ID, achievements and keys there, and uploading. Older notes: `docs/DESKTOP_PLAN.md` (GodotSteam instead of
  steamworks.js). The game ships through Steam, so no Windows code signing or Apple Developer account
  is needed (games installed by Steam don't get the "unrecognised app" warnings).
- [x] **Controller support** (needed for Steam Deck). Done in 0.9.72: Xbox, PlayStation and Steam Deck
  controllers drive a pointer of their own (`godot/scripts/pad.gd`, made by `game.gd`), so every screen
  works with it like a mouse. The D-pad jumps between buttons and cards, A clicks or drags, X zooms, B / Start
  are Esc, Y is next phase, the right stick scrolls; listed in Settings → Controls (test: `tests/pad_smoke.tscn`).
  - [ ] Still to do: test on a real Steam Deck, and open Steam's on-screen keyboard for the login boxes
    (done: the Steam build brings up the Deck keyboard for text boxes; other builds: Steam + X).

## Game modes & content

- [x] **Co-op boss mode: Turf Defense** (0.9.81). Two players (quick match) against a clan boss: one per
  clan, three levels each (Street, Hard, Nightmare), phases as its Morale drops, an entrance cutscene,
  phase cutscenes and lines mid-fight, and its prize card on the first Street clear. Bosses and rewards:
  `godot/data/bosses.json`; server: `backend/socket/coopMatch.js`, `backend/economy/turf.js`.
  Later: boss-only cards and prize cards of their own (the prizes are the clan Legendaries for now),
  a boss music track (`assets/sfx/music_boss.mp3` is used when it exists), friend invites.
- [x] **Wildcard cards.** In the game (44 cards, with packs and a starter deck).
- [x] **Re-import Continuous / Equip cards** through the Forge, so their effect text loses the old
  "CONTINUOUS" / "EQUIP:" line (removed from the text box in Forge v84; it's on the type line).
- [ ] **How to Play / tutorial pages for newer mechanics:** luck, DOUBLE OR NOTHING, LOADED DICE,
  Equips, Strivers and evolution.
- [ ] **Ranked seasons:** a season reset with end-of-season rewards (ties in with the seasonal emails).

## Accounts & email

- [ ] **Branded emails that land in the inbox.** `backend/utils/mailer.js` sends plain inline-HTML
  emails over SMTP from a DuckDNS address. To stay out of spam: a domain of our own (a DuckDNS
  address can't carry the SPF / DKIM / DMARC records that prove an email is genuine) and a sending
  service such as Resend, Postmark or Brevo. Then branded templates (logo, colours, card art) for
  account activation, password reset, and season / content-drop news. News emails need an opt-in and
  an unsubscribe link.
- [x] **Privacy policy, terms and account deletion.** Done in 0.9.72: `/privacy`, `/terms` and
  `/delete-account` on the server (`backend/routes/legal.js`, contact address from `CONTACT_EMAIL` in
  `.env`); Settings → Account in the game links to them and deletes the account after the password
  (`backend/routes/account.js`, test `backend/routes/account.test.cjs`); registering says it agrees to them.
  - [ ] Still to do: a contact address of our own (`CONTACT_EMAIL`), and a lawyer's read before a store
    launch or taking payments at scale.

## Server & reliability

- [ ] **Database backups:** a nightly `pg_dump` copied off the server, so accounts and collections
  survive a disk failure. (There's no backup script in the repo yet.)
- [ ] **Hosting:** the server is a home machine behind DuckDNS. Before a wider or mobile launch, move
  to a small rented server (VPS), or at least add a battery backup (UPS) and an uptime monitor.
- [x] **Crash reports:** the game sends its errors and crashes to the server (`client_errors` table,
  `godot/scripts/error_report.gd`, `backend/routes/telemetry.js`).

## Polish

- [ ] **Accessibility:** colour-blind-safe keyword colours and a text size option.
