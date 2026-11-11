# The website (alleywaybrawlers.com)

The game server sends the website too: the front page, the clans, every card, the Striver lines, How to
Play and the news. The pages are built from the game's own files when the server starts, so the site
can't drift from the game: a new card, clan, keyword or patch note shows up after the usual deploy.

| What | Where |
|---|---|
| The addresses (`/`, `/clans`, `/cards`, ...) and what a page may load | `backend/routes/site.js` |
| What the pages say and how they're laid out (HTML) | `backend/site/pages.js` |
| Reading the game's files: cards, clans, keywords, How to Play, patch notes | `backend/site/data.js` |
| Card art, emblems, packs made smaller for the web | `backend/site/images.js` |
| Styles, script, font, logo, icons, screenshots (served under `/site/`) | this folder |
| The test (every page, card and Striver line) | `node backend/site/site.test.cjs` |

## Working on it

`node tools/site_dev.mjs` then open http://localhost:3100: the same pages the server sends, with no
database and no game server. A change to `site.css` or `site.js` shows on reload; a change to
`backend/site/*.js` needs it restarted. Needs `npm install` in `backend/` once (for `sharp`, which
makes the small pictures; without it the pages still work, with full-size art).

To put a change live: commit, push, `node tools/deploy.mjs`.

## What comes from where

- **Cards, clans, Striver lines:** `shared/cards.js` and `shared/clans.js`. No page names a clan: a
  new clan gets its page, its colour and its place in the lists by itself.
- **How to Play, keywords, card terms:** the game's own text (`godot/scripts/ui/how_to_play.gd`,
  `godot/scripts/keywords.gd`). Change it there and both the game and the site change.
- **News:** `godot/data/patch_notes.json`.
- **Downloads:** the newest build of each platform in `downloads/` on the server. A platform with no
  build says "Not available yet".
- **Screenshots:** `shots/` and `shots/shots.json`, made by `node tools/site_shots.mjs <Godot exe>`
  (it runs the game's screenshot tour, about 15 minutes). Run it again when the game's look changes;
  `SHOTS` in that file picks the screenshots and their captions.
- **Card art:** `assets/cards/` and friends, resized the first time each picture is asked for and kept
  in `backend/.cache/site/` (not in git, safe to delete).

## Rules for this site

- **Nothing about players.** The pages read no database and show no accounts, ranks or leaderboard
  (the privacy policy says only other players see those).
- **No cookies, trackers or files from other sites.** The footer says so and the test checks it.
  Fonts and scripts live in this folder.
- **Visits are only counted.** `backend/site/visits.js` adds up, per day, the people, the pages and the
  sites that sent them (no cookies; a visitor is told apart by a code that changes daily and is never saved).
  See them at `/stats` (the browser asks for `SITE_STATS_PASSWORD` from `backend/.env`). The privacy
  policy describes it ("Our website"): change both together.
- **Say only what's true today.** The Alpha tag by the version (`STAGE` in `pages.js`) and the note by
  the downloads (`PRELAUNCH`: accounts will be reset at launch) go at launch (`docs/LAUNCH_CHECKLIST.md`).
  The store badges (`STORES`) say "Coming soon to" Steam and Google Play; once a store page is up, put
  its address there and the badge links to it ("Get it on"). The logos are the plain one-colour marks
  (`website/img/steam.svg`, `googleplay.svg`, from Simple Icons): Google's and Valve's official badges
  are only for a game that has its store page. No prices.
- **One address.** A page asked for through the server's other names (play., www., the DuckDNS one)
  is sent to `SITE_URL` (`.env`, default `https://alleywaybrawlers.com`). The game's own calls
  (`/api`, `/download`, the sockets) are never redirected.
