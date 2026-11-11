# AlleyWay Brawlers — to do / eventually

Bigger features and ideas parked for later. Nothing here is being built yet: tick an item off (`[x]`)
when it ships, or delete it if it's dropped.

## Platforms

- [x] **Mac build (Apple Silicon / ARM).** Done in 0.9.69: a universal app (Apple Silicon + Intel) built
  from the PC (`tools/build_mac.mjs`), with its own patches and download, playing online with Windows
  (see "Mac build" in `docs/CARD_PIPELINE.md`).
- [ ] **Mobile version, with cross-play (PC, Mac and mobile in the same matches).** Started
  2026-11-10: the Android APK builds and plays online with everyone else (`docs/ANDROID.md`: touch
  controls, lighter pictures, its own download and version check). 0.9.138: no black bars, landscape
  only, bigger text and touch targets, Android patches. Left: layouts made for phones, Google Play
  (AAB, Play Billing for Contraband), and iOS (a Mac and Apple's $99/yr).
- [ ] **Steam release.** Step by step: `docs/LAUNCH_CHECKLIST.md`. The integration is built (`docs/STEAM.md`): what is left is the Steamworks account,
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
- [x] **How to Play pages for every keyword and mechanic** (0.9.120): KEYWORDS and CARD TERMS in How to Play,
  a page each with real cards that use it (`godot/scripts/ui/how_to_play.gd`).
- [ ] **Ranked seasons:** a season reset with end-of-season rewards (ties in with the seasonal emails).

## Accounts & email

- [ ] **Branded emails that land in the inbox.**
  - [x] A domain of our own and a sending service: since 0.9.140 the server sends through Brevo
    (`SMTP_*` in `backend/.env`) as support@alleywaybrawlers.com, with DKIM and DMARC on the domain.
    Mail to support@ is forwarded to alleywaybrawlers@gmail.com by Cloudflare Email Routing.
  - [ ] Branded templates (logo, colours, card art) for account activation and password reset:
    `backend/utils/mailer.js` still sends plain inline HTML.
  - [ ] Season / content-drop news emails: they need an opt-in and an unsubscribe link.
- [x] **Privacy policy, terms and account deletion.** Done in 0.9.72: `/privacy`, `/terms` and
  `/delete-account` on the server (`backend/routes/legal.js`, contact address from `CONTACT_EMAIL` in
  `.env`); Settings → Account in the game links to them and deletes the account after the password
  (`backend/routes/account.js`, test `backend/routes/account.test.cjs`); registering says it agrees to them.
  - [x] A contact address of our own: support@alleywaybrawlers.com (`CONTACT_EMAIL`).
  - [ ] Still to do: a lawyer's read before a store launch or taking payments at scale.

## Server & reliability

- [x] **Database backups:** nightly at 3:30 on the server (`backend/scripts/backup_db.sh`, cron; the newest
  14 kept in `~/backups`). `node tools/backup_db.mjs` copies them to the PC.
  Copied to the PC every day at noon (Windows Task Scheduler: "AlleywayBrawlers DB backup copy", to
  `DocumentsAlleywayBrawlers-backups`).
- [ ] **Hosting:** the server is a home machine (play.alleywaybrawlers.com, which points at its DuckDNS name). Before a wider or mobile launch, move
  to a small rented server (VPS), or at least add a battery backup (UPS) and an uptime monitor.
- [x] **Crash reports:** the game sends its errors and crashes to the server (`client_errors` table,
  `godot/scripts/error_report.gd`, `backend/routes/telemetry.js`).

## Polish

- [x] **Accessibility (0.9.141):** Settings → Accessibility: Text Size (`UI.text_size`: reading text and
  small print, headings stay), Colour-Blind Colours (`Keywords.color`: keywords by what they do in
  Okabe-Ito colours, stat changes blue ▲ / orange ▼), with the colour-blind symbols, photosensitive mode
  and screen shake. `screens_tour.gd --access` shoots the screens with them off and on.
  - [ ] Still open: the card pictures' own text (baked into the art by the Card Forge) keeps its colours
    and size; a bigger Text Size makes the duel's card panel scroll sooner (the zoom shows all).
