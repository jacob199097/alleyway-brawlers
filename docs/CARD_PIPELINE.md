# From the Card Forge to the game

Cards are designed in the Card Forge (https://claude.ai/artifact/4DxkURVx8VNZJDMVWMTzCY):
art, stats, text and **effects** (the game rules). Getting them into the game takes three steps.

## 1. Export from the Forge
Press **Export all**. You get `alleyway-cards.zip` with `card_catalog.json` and `cards/<game id>.png`.

## 2. Import on the PC
```
node tools/import_forge.mjs path/to/alleyway-cards.zip
```
This:
- writes `shared/cards_forge.js`, which is merged into the card catalogue (`shared/cards.js`) used
  by both game clients and the server;
- copies the card images to `client/assets/cards/` and `godot/assets/cards/`;
- regenerates `godot/data/cards.json`.

The Forge is the source of truth: a card deleted in the Forge is removed on the next import.
The importer warns about problems such as a missing image, a "promotes to" card that isn't in the
export, or two cards with the same name. The server needs unique names, so add "Lv.2" and so on.

Then commit and push.

## 3. Update the server
```
git pull
node backend/scripts/sync_cards.mjs
sudo systemctl restart alleyway-backend
```
`sync_cards` adds or updates the Forge cards in the database (matched by game ID), so they can
drop from packs, be collected and go into decks. A new clan becomes a pack type, and the shop
offers its pack once the clan has at least 3 cards. Pack art comes from
`client/assets/<clan>_booster.png` (for example `nebula_booster.png`) when that file exists.

**Players get the new cards automatically.** When the game starts it compares its cards with
the server (`/api/content/manifest`) and downloads only new or changed card data and images,
with a download screen. No new build is needed for card changes; only code changes need one.

## Game versions
`shared/game_version.json` holds `latest` (the newest Windows build) and `minimum` (older builds
must update before playing online). When you ship a build with code changes, raise the version in
`godot/project.godot` (`config/version`) and in that file. Put the download link in the server's
`backend/.env` as `CLIENT_DOWNLOAD_URL=...`; the game offers it when an update is available or
required.

## Effects
Each effect is one building block. Both rules engines run them the same way (`duel_state.gd` and
`shared/duel/DuelState.js`; the golden test checks they match).

| Field | Options |
|---|---|
| **When** | When deployed · When it attacks · When it KOs a character · When it Downs a character · At the start of your turn · Always (passive) |
| **Do** | Change ATK / DEF · DOWN an enemy · Draw cards · Opponent discards · Morale damage · Gain Morale · PROMOTE this card · Attack again |
| **Who** (ATK/DEF changes, DOWN) | This card · One other ally (you choose) · All other allies · One enemy (you choose) · All enemies |
| **For how long** (ATK/DEF changes) | Until end of turn · Until the end of the opponent's next turn. An attack bonus on itself lasts for that Brawl; a passive bonus lasts while its condition holds. |
| **Only if** | Always · The target is in DEF · The target is Downed · You control N+ other allies · Next to an ally · An enemy is Downed |
| **Clan filter** | Limits who it affects or counts to one clan |

A card can have several effects. Tick **Write the card's effect text from these effects** and
the Forge writes the rules text for you, so it always matches what the card does.

A leader's **passive** effects apply while it's Dormant.

Something that can't be built from these blocks needs code: add a new block in both engines, or
a hand-written effect key (the way the placeholder Lions cards work).
