# Game sounds

Each sound is one or more recordings named `<sound>_1.ogg`, `<sound>_2.ogg`, ... (or just
`<sound>.ogg` / `.wav`). The game picks one at random each time, so repeated sounds vary. A sound
with no file is synthesised by the game (`godot/scripts/sfx.gd`, the `_r_<sound>` recipes).

**To add or replace a sound:** put the file(s) here, then `node tools/deploy.mjs`. Players download
new or changed sounds when the game starts (like card art), so no new build is needed. Run
`godot/tools/sync_assets` and `node godot/tools/export_cards.mjs` before the next full build so it
ships with them. Keep files short (most are under a second) and use `.ogg` for size.

## The sounds

| Sound | When it plays | Now |
|---|---|---|
| `draw` | drawing a card | recorded (4) |
| `set` | setting a card face down | recorded (4) |
| `flip` | a face-down card turns face up | recorded (4) |
| `slam` | a character is summoned | recorded (5) |
| `heavy` | a Heavy is summoned (Sacrifice) | recorded |
| `hit` | an attack lands | recorded (5) |
| `damage` | a player loses Morale | recorded (5) |
| `down` | a character goes Down | recorded (5) |
| `ko` | a character is KO'd | recorded (3) |
| `boom` | big impacts: Direct Attacks, leader hits | recorded |
| `ambush` | an Ambush springs | recorded (3) |
| `laser` | Nebula: the quick laser zaps | recorded (5) |
| `laser_beam` | Nebula: the held laser beam | recorded (5) |
| `pack_open` | a pack tears open in the Shop | recorded (2) |
| `shuffle` | a match starts | recorded |
| `gunshot` | Militia: each shot | **wanted** (synthesised) |
| `effect` | a card effect triggers | **wanted** (synthesised chime) |
| `promote` | a promotion, level up, achievement | **wanted** (synthesised) |
| `whoosh` | cards flying, screen changes | **wanted** (synthesised) |
| `riser` | build-up before big moments (leader awakening, Legendary pull) | **wanted** (synthesised) |
| `heartbeat` | low Morale | **wanted** (synthesised) |
| `phase` | the phase changes | **wanted** (synthesised blip) |
| `turn` | your turn starts | **wanted** (synthesised two-note chime) |
| `click` | buttons, counting numbers up | **wanted** (synthesised) |
| `victory` | you win | **wanted** (synthesised fanfare) |
| `defeat` | you lose | **wanted** (synthesised) |

A clan's attack can have its own sound like `laser` and `gunshot`; the clan's style lives in
`CLAN_STYLE` in `godot/scripts/duel/duel.gd`.

## Where the recordings come from

All current recordings are by Kenney (www.kenney.nl), released as CC0 (public domain): free to use
in a commercial game, no credit required. From the packs Casino Audio, Impact Sounds, RPG Audio and
Sci-Fi Sounds.

Good places for the wanted ones (check each sound's licence):
- Kenney: kenney.nl/assets (all CC0). Music Jingles and Interface Sounds suit `victory`, `defeat`,
  `click`, `turn`.
- Sonniss GDC bundles: sonniss.com/gameaudiogdc (royalty-free, commercial use, no credit needed);
  good for `gunshot` and `whoosh`.
- Freesound: freesound.org (filter by the CC0 licence).
- OpenGameArt: opengameart.org (filter by CC0).
