# Game sounds

Each sound is one or more recordings named `<sound>_1.ogg`, `<sound>_2.ogg`, ... (or just
`<sound>.ogg` / `.mp3` / `.wav`). The game picks one at random each time, so repeated sounds vary. A
sound with no file is synthesised by the game (`godot/scripts/sfx.gd`, the `_r_<sound>` recipes).
Music (`music_*`) and ambience loops (`amb_*`) live here too and are played by
`godot/scripts/audio/soundscape.gd` (`Game.sound`).

The `.wav` files are stand-ins made by `node tools/render_audio.mjs`: **docs/AUDIO_PROMPTS.md**
has the prompts to generate the real ones. Drop a generated file in with the same name, delete the
stand-in `.wav`, deploy.

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
| `pack_open` | Shop: the top of a pack rips off | recorded (2) |
| `shuffle` | a deck is shuffled | recorded |
| `music_menu` | menus (until there is one: `assets/main_menu_theme_loop.mp3`) | **wanted** |
| `music_duel` | duels | stand-in (.wav) |
| `music_duel_tense` | duels, once someone is down to a third of their Morale | stand-in (.wav) |
| `music_victory`, `music_defeat` | the end of a match (a sting; the menu music follows) | stand-in (.wav) |
| `amb_city_rain` | duels: rain and the city around the mat | stand-in (.wav) |
| `amb_crowd` | finding a match, the Free-for-all lobby, Rock Paper Scissors | stand-in (.wav) |
| `amb_rooftop` | Fight Mode | stand-in (.wav) |
| `neon_buzz` | a neon light on the duel mat stutters (from where it is) | stand-in (.wav, 3) |
| `phase_deployment`, `phase_brawl`, `phase_regroup` | each phase starts | stand-in (.wav) |
| `turn_yours`, `turn_theirs` | a turn starts | stand-in (.wav) |
| `hover`, `click`, `error` | buttons: pointer over, pressed; a move that isn't allowed | stand-in (.wav) |
| `karat` | Karat earned on the results screen | stand-in (.wav) |
| `gunshot` | Militia: each shot | **wanted** (synthesised) |
| `lockon` | Militia: the airdrop reticle locks onto a lane | **wanted** (synthesised radar beeps) |
| `airdrop` | Militia: a character is flown in and dropped (jet pass, then a thud) | **wanted** (synthesised) |
| `tear` | Shop: the foil crackling as the player swipes across a pack (played over and over) | **wanted** (synthesised) |
| `charge` | Shop: the build-up before a pack bursts and before a Rare or better turns over (played faster for shorter ones) | **wanted** (synthesised riser) |
| `burst` | Shop: the open pack bursts and the cards fly out | **wanted** (synthesised) |
| `shimmer` | Shop: an Uncommon turns over | **wanted** (synthesised sparkle) |
| `reveal_rare` | Shop: a Rare turns over | **wanted** (synthesised bells) |
| `reveal_epic` | Shop: an Epic turns over | **wanted** (synthesised chord) |
| `reveal_legendary` | Shop: a Legendary turns over | **wanted** (synthesised fanfare) |
| `new_card` | Shop: NEW on a card the player didn't have | **wanted** (synthesised ding) |
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
