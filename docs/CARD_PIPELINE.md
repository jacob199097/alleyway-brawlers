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
  by the game and the server;
- copies the card images to `assets/cards/` and `godot/assets/cards/`;
- regenerates `godot/data/cards.json`.

The Forge is the source of truth: a card deleted in the Forge is removed on the next import.
Character roles follow the class rules, and the importer enforces them:

- **Striver**: the only role with levels (Lv.1 to Lv.3). It promotes into the card set in "Promotes to".
- **Brawler**: standalone, always level 1, never promotes. Usually cheap, low-Authority cards.
- **Heavy**: standalone, always level 1, high Authority. Playing one sacrifices 1-3 of your characters on
  the field (the Forge's **Sacrifices**, next to Role; `tributeCost` in the game), and the Heavy takes one
  of their lanes.

Any other character can be deployed in an empty lane, or over one of your own characters (not a leader
or one in STASIS): that one goes to the Gutter (not a KO), so a full front row never locks your hand.

Keyword effects are effect blocks in the Forge. Each keyword has its own colour on the card, and in the game
hovering it shows what it does. The game's copy of the colours and meanings is `godot/scripts/keywords.gd`;
keep it in step with `EFFECT_KEYWORDS` in the Forge.

| Keyword | Effect block | What it does |
|---|---|---|
| POISON X | `poison` | At the start of its owner's next 3 turns, it loses X ATK (until it leaves the field). |
| BURN X | `burn` | At the start of its owner's next 3 turns, its owner loses X Morale. |
| BLEED X | `bleed` | After every brawl it is in, it loses X ATK and X DEF (until it leaves the field). |
| SHOCK X | `shock` | Downs it if X is at least its DEF; otherwise -X DEF this turn. |
| FREEZE | `freeze` | Switched to DEF; can't attack or change position until its owner's next turn ends. |
| STASIS | `stasis` | Nebula only. Until its owner's next turn ends: can't attack, be attacked or be targeted, its effects are off, and it doesn't block direct attacks. |
| STUN | `stun` | Can't attack during its owner's next turn. |
| SHIELD | `shield` | The next time it would be defeated, it isn't. |
| PIERCE | `pierce` | Beating a DEF or Downed character also costs the opponent the difference in Morale. |
| DRAIN X / HEAL X | `drain` / `heal` | Take X Morale from the opponent / gain X Morale. |
| SUPPRESS X | `suppress` | Militia only. It loses X ATK and can't attack until the end of its owner's next turn. |

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
`assets/<clan>_booster.png` (for example `nebula_booster.png`) when that file exists.

**Players get the new cards automatically.** When the game starts it compares its cards with
the server (`/api/content/manifest`) and downloads only new or changed card data and images,
with a download screen. No new build is needed for card changes; only code changes need one.

## Game versions and updates
`shared/game_version.json` holds `latest` (the newest version), `minimum` (older versions must update
before playing online) and `patchBase` (the oldest full build that can update itself in place).
Card changes need none of this: the game downloads new cards by itself.

**Small update (code and scenes only), the usual case.** Players get it inside the game: at start-up it
downloads the patch (a few hundred KB), checks it and restarts into it.

1. Raise `config/version` in `godot/project.godot` and `latest` in `shared/game_version.json` to the
   same number. Leave `minimum` and `patchBase` alone, unless old versions must stop playing online.
   Add what changed to the top of `godot/data/patch_notes.json`: players see it once ("What's new").
2. `node tools/make_patch.mjs <Godot console exe>` writes `builds/AlleywayBrawlers-<version>-patch.pck`.
3. Commit and push, then `node tools/deploy.mjs --patch` (see Deploying), or by hand: copy the patch
   into `downloads/` on the server, then pull and restart there:

       scp builds/AlleywayBrawlers-<version>-patch.pck jacob199097@192.168.0.200:/opt/Turf_War/downloads/

A patch can't change project settings (`project.godot`), the autoload list, add `class_name` scripts
(use `preload` instead). New or changed art and audio in `assets/` do ship in patches (only what changed
since the patchBase build). The Patch preset must export everything the full build does: a file it
leaves out is written into the patch as deleted (0.9.7 to 0.9.8 lost the menu art that way), and
`make_patch` refuses a patch that deletes files.

**Full build.** Raise the version in both files and set `minimum` and `patchBase` to it. Export the
"Windows Desktop" preset to `builds/windows_<version>/AlleywayBrawlers.exe` (keep it: `make_patch`
builds later patches as just the changes against it), zip that exe as
`builds/AlleywayBrawlers-<version>-windows.zip` and copy it into `downloads/` on the server. `https://<server>/download` serves the newest zip, and the
game links there when it can't patch itself (set `CLIENT_DOWNLOAD_URL` in `backend/.env` to link
somewhere else).

    scp builds/AlleywayBrawlers-<version>-windows.zip jacob199097@192.168.0.200:/opt/Turf_War/downloads/

If a patch ever stops the game from starting, the game notices on the next start, runs the full
build's own code instead and doesn't download that patch again.

## Deploying
`node tools/deploy.mjs` updates the server from the PC: it checks everything is pushed, pulls on the
server, restarts the backend and shows the log if that fails. Add `--patch` or `--build` to copy the
latest patch or full build into `downloads/` first, `--sync-cards` after importing Forge cards, or
`--logs` just to read the backend's log. It logs in with an SSH key, set up once:

1. On the PC (Command Prompt), make a key just for the server and an `alleyway` shortcut:

       ssh-keygen -t ed25519 -f %USERPROFILE%\.ssh\alleyway_server -N "" -C "alleyway deploy"
       (echo.& echo Host alleyway& echo     HostName 192.168.0.200& echo     User jacob199097& echo     IdentityFile ~/.ssh/alleyway_server& echo     IdentitiesOnly yes) >> %USERPROFILE%\.ssh\config

2. Put the key on the server (asks for the server password one last time):

       type %USERPROFILE%\.ssh\alleyway_server.pub | ssh jacob199097@192.168.0.200 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

3. On the server, let that user restart the backend without a password (and nothing else):

       echo 'jacob199097 ALL=(root) NOPASSWD: /usr/bin/systemctl restart alleyway-backend, /bin/systemctl restart alleyway-backend' | sudo tee /etc/sudoers.d/alleyway-deploy
       sudo chmod 440 /etc/sudoers.d/alleyway-deploy && sudo visudo -c

`ssh alleyway` should now log straight in. To undo: delete the line from `~/.ssh/authorized_keys` on
the server and `/etc/sudoers.d/alleyway-deploy`.

Every push also runs the tests on GitHub (`.github/workflows/tests.yml`; results on the repo's
Actions tab): the server tests, the golden test that both rules engines agree, and the Godot
smoke tests.

## Balance report
`node tools/balance.mjs --clan <clan> --games 5000` plays CPU-vs-CPU games with the real rules, each
player with a random legal deck of the clan's cards, and lists every card: how often it's drawn and
played, the win rate when drawn, and its **impact** (win rate when drawn minus when it stayed in the
deck): how much drawing it helps. It flags STRONG (+8 or more), WEAK (-5 or less) and STUCK IN HAND
(played in under a third of the games it was drawn, e.g. too expensive). `--html report.html` writes a
sortable page to share. 5000 games take about ten seconds. The numbers describe the cards as the CPU
plays them, so treat them as a pointer to cards worth a look, not a verdict.

**From real matches.** Every finished match (online and CPU) is stored in `match_stats`: each side's
clan, leader, deck, the cards drawn and played, and who won. `node tools/live_balance.mjs <dir>` runs
`backend/scripts/balance_dashboard.js` on the server and writes the numbers (clan win rates against
players and the CPU, leaders, each card's impact) as JSON files for the live balance dashboard (a
private claude.ai page: ask Claude to refresh it).

**Weekly challenge and clan mastery.** The challenge's rules twists are in `shared/challenges.js`
(both rules engines apply them); a new one each Monday, the first win of the week pays once
(`backend/economy/challenge.js`). Clan mastery levels, XP and rewards are in
`backend/economy/mastery.js`.

`--vs nebula,militia` plays one clan against the other and prints the matchup. Add `--starters` to give
both players their clan's starter deck (`shared/clans.js`, what new players get): check it after
changing a clan's cards or its starter, and keep the starters near 50% against each other. Random
decks can hide a weak starter (Militia's built starter lost ~70% until it was hand-picked).
Players who already have an account get a new or changed starter with
`node backend/scripts/give_starter.js nebula militia --add` on the server: a dry run listing what each
player gets; `--apply` does it (cards topped up, a `<Clan> Starter` deck added, a mail). Their own
`<Clan> Starter` decks stay as they are unless `--refresh` (the dry run shows if they were changed).

## Effects
Each effect is one building block. Both rules engines run them the same way (`duel_state.gd` and
`shared/duel/DuelState.js`; the golden test checks they match).

| Field | Options |
|---|---|
| **When** | When deployed · When it attacks · When it's attacked · When it KOs a character · When it Downs a character · When it hits directly · When it's Downed · When it's KO'd · When you deploy another character · At the start of your turn · At the end of your turn · Always (passive) · When another of your characters is KO'd · **Activate** (the player uses it from the card on their turn: click the card, then ACTIVATE; once per turn) · When an enemy character is KO'd · At the end of your opponent's turn · When another of your characters is attacked |
| **Do** | Change ATK / DEF · DOWN · KO · Stand up (un-Down) · Return to hand · Force into DEF · Stun (can't attack next turn) · Shield (ignore the next defeat) · Pierce (beating a DEF card still costs Morale) · Draw cards · Search your deck · Recover from the Gutter · Opponent discards · Mill the opponent's deck · Morale damage · Gain Morale · Drain Morale · Gain Authority · PROMOTE this card · Attack again · Let allies that already attacked attack again · Force into ATK (a face-up enemy in DEF) · SUPPRESS · Deploy tokens (copies of a character marked **Token**, which is only ever made by effects: never in packs, decks or the Card Library, and vanishes when it leaves the field) · Deck to the field (call in: a character from your deck, with the same filters as search) · Loot (draw N, then discard N) · Put on top of its owner's deck · Exile (removed from the game: not to the Gutter, no KO effects) · Swap ATK and DEF (for a turn, the next, or for good) · BOUNTY X (when it's KO'd, whoever put the bounty on it draws X) · Always (passive): LIFESTEAL (the Morale it takes in a brawl, you gain) |
| **Who** | This card · One other ally (you choose) · All other allies · One enemy (you choose) · All enemies · All characters (yours and every opponent's; a character's own effect leaves itself out: "DOWN all other characters") · The attacker (for "When it's attacked") |
| **For how long** (ATK/DEF changes) | Until end of turn · Until the end of the opponent's next turn · Permanently (while it stays on the field: "When it KOs a character: +200 ATK permanently" grows with every KO). A change to itself when attacking or attacked lasts for that Brawl; a passive one lasts while its condition holds. |
| **Activate cost** | None · Pay N Authority · Pay N Morale · Discard N cards · Sacrifice another of your characters · This card can't attack this turn. The CPU uses Activate abilities too, but never sacrifices. |
| **Card kind** (search, recover) | Any card · Character · Hustle · Ambush |
| **Only if** | Always · The other card is in DEF / Downed / ATK · You control N+ / N or fewer other characters · You control no other characters · Next to an ally · An enemy is Downed · Your hand has N or fewer cards · Your Morale is N or less · The opponent's Morale is N or less · The opponent controls N+ characters · Your Gutter has N+ cards · Your leader is Dormant · This card is in DEF / ATK position · The opponent controls N or fewer characters · It is turn N or later · Your deck has N or fewer cards · You control a Downed character · Your hand has N+ cards. Counting conditions (characters, Next to, Downed, Gutter, hand) can count only one clan (`if_clan`): "If you control 2 or more MILITIA characters" |
| **Clan filter** | Limits who it affects or counts, what search/recover finds, or which deployed allies trigger it |

**Hustles and Ambushes** have no "When": a Hustle does all of its effects when it's played; an Ambush is
set face-down and, when an enemy attacks one of your characters, you may spring it and all of its
effects happen. An Ambush that changes the attacker's ATK changes it for that Brawl, and if it Downs,
removes or puts the attacker in Stasis the attack stops. (The Forge hides the options that need a card on
the field: "This card", Pierce, PROMOTE, Attack again, once per turn.)

**Clans** need no code: every card carries its clan's name and colour from the Forge, and any clan with
enough cards for a 40-card deck (`shared/clans.js`) can be picked by new players, gets a starter deck
built from its cards, is played by the CPU, and shows in the shop, Deck Builder and Card Library. Art
for the clan screen, Deck Builder and shop: `assets/<clan>_deck.png`, `assets/<clan>_deckbox.png`
(512×512) and `assets/<clan>_booster.png` (600×800); until then the clan's leader, or its card back,
stands in. They ship with the game, so new art goes out in a patch. A clan's card back is `assets/card_back_<clan tag>.png`; to make it move, add the clan to
`BACK_STYLES` in `godot/scripts/card_db.gd` ("galaxy": Nebula's turning swirl, "radar": Militia's sweep), and give its
characters their own attack, summon or KO animation in `CLAN_STYLE` in `godot/scripts/duel/duel.gd`. Card names don't have to be unique: a Striver's levels can
all be called "Kade" (cards are matched by game ID).
| **Once per turn** | The effect works only the first time it triggers each turn |
| **For each** | Multiplies the numbers (ATK/DEF, Morale, cards...) by a count: your other characters (one clan or any), enemies, Downed enemies, cards in your Gutter or hand, or the pips on a die rolled for it; optionally at most N. With nothing to count the effect does nothing |
| **Luck** | A coin flip (happens on heads) or a die roll (happens on N or more, 1-6) decides whether the effect happens; or it follows the last flip or roll ("If heads / If tails", no roll of its own, same trigger). Not on Always (passive) effects. Both engines roll with the same generator (`_luckGate`), from the match seed, so replays repeat; the game shows the coin or die |
| **Choose one** | "Or the next effect": the player picks one of the two (same trigger). The game shows each option's text (`label`, written by the Forge) |
| **If you do** | "If you do" on an effect (`if_done`): it happens only if the effect above did something, e.g. "Destroy one of your opponent's face-down cards. If you do, PROMOTE this card." Not if there was nothing to hit or the player skipped the target. Same trigger as the effect above; the engines attach it to that effect as its `then` |
| **Kind** (Hustle, Ambush) | Normal (used once) · **Continuous** (stays face-up in the back row; an Ambush once sprung: its "always" effects reach all your characters or all enemies, its triggers fire, until destroyed) · **Equip** (a Hustle attached to one of your characters, or an enemy: its "while equipped" effects are that character's; it goes to the Gutter when the character leaves). "Destroy back-row cards" removes them |
| **Targets** | A card effect that picks one character always asks (even from one) and can be skipped; Hustles can't be played, Ambushes sprung or abilities activated when none of their effects would do anything. A Downed character's effects don't work, and Downed characters are in DEF. A search or call that looks through your deck shows the player the cards to pick from, and shuffles the deck afterwards |

**Test this card** (in the Forge, under the effects) plays 200 CPU games with the card as it is in
the editor, by the game's own rules: how often it is drawn and played, its impact on the win rate,
how often its effects happen, and any rules errors. The rules come from `engine.js`, published with
the Forge and built from `shared/` by `node tools/build_engine_bundle.mjs engine.js`: after a rules
change, rebuild it and publish the Forge again with it.

A card can have several effects. Tick **Write the card's effect text from these effects** and
the Forge writes the rules text for you, so it always matches what the card does.

A leader's **passive** effects apply while it's Dormant.

Something that can't be built from these blocks needs code: add a new block in both engines, or
a hand-written effect key (the way the placeholder Lions cards work).
