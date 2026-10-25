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
- [ ] **Steam release.** `docs/DESKTOP_PLAN.md` still has the useful notes (use GodotSteam instead of
  steamworks.js). The game ships through Steam, so no Windows code signing or Apple Developer account
  is needed (games installed by Steam don't get the "unrecognised app" warnings).
- [x] **Controller support** (needed for Steam Deck). Done in 0.9.72: Xbox, PlayStation and Steam Deck
  controllers drive a pointer of their own (`godot/scripts/pad.gd`, made by `game.gd`), so every screen
  works with it like a mouse. The D-pad jumps between buttons and cards, A clicks or drags, X zooms, B / Start
  are Esc, Y is next phase, the right stick scrolls; listed in Settings → Controls (test: `tests/pad_smoke.tscn`).
  - [ ] Still to do: test on a real Steam Deck, and open Steam's on-screen keyboard for the login boxes
    (needs GodotSteam; for now Steam + X opens it).

## Game modes & content

- [ ] **Co-op boss mode (name TBD).** Two players team up against one CPU boss with fixed Morale
  (e.g. 10000). Several levels, short cutscenes and dialogue pop-ups mid-fight; beating a boss for the
  first time gives its prize card. Builds on the free-for-all seats in both engines, the CPU player
  (`DuelAI`) for the boss, and server-side rewards in `backend/economy/` (with a `db/migrate_*.sql`
  for "bosses beaten"). Name ideas: Turf Defense, Back Alley Bosses, Shakedown, Tag Team, Block Party.
- [ ] **Wildcard cards.** Frame, card back, booster, deck box, crest and effects (luck, DOUBLE OR
  NOTHING, LOADED DICE) are ready; the cards themselves are being made.
- [ ] **Re-import Continuous / Equip cards** through the Forge, so their effect text loses the old
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
- [ ] **Crash reports:** send Godot errors / crash logs to the server, so bugs on other players' PCs
  show up.

## Polish

- [ ] **Accessibility:** colour-blind-safe keyword colours and a text size option.
