# Audio: what to generate, and the prompts

Every sound, music track and ambience in the game is a file in `assets/sfx`, found by its name.
Right now the new ones are stand-ins made in code (`tools/render_audio.mjs`, the `.wav` files).
To replace one:

1. Generate it from the prompt below (music: Suno or Udio, instrumental; everything else:
   ElevenLabs Sound Effects).
2. Name it exactly as listed (`music_duel.mp3`, `amb_crowd.mp3`, `phase_brawl.mp3`...). Several
   takes of a sound? Number them (`neon_buzz_1.mp3`, `neon_buzz_2.mp3`): the game picks one at
   random each time. Two duel tracks (`music_duel_1.mp3`, `music_duel_2.mp3`) work the same way.
3. Put it in `assets/sfx`, delete the stand-in `.wav` of that name, then `node tools/deploy.mjs`.
   Players download it the next time they start the game: no new build.

Any of `.mp3`, `.ogg` or `.wav` works. Trim silence off the start of short sounds.

## Music (Suno / Udio, instrumental)

The duel music sits under a lot of sound effects, so it should drive without crowding them: no
vocals, not much high melody. Music loops as a whole track, so pick takes without a long fade-in.
Suno: put the style line in "Style of Music", turn on Instrumental, aim for 2 to 3 minutes.

| File | When it plays | Style / prompt |
|---|---|---|
| `music_menu` | Main menu and every menu screen | `dark synthwave, cyberpunk, gritty hip-hop drums, deep analog bass, moody neon pads, memorable lead hook, confident and cool, night city, 90 bpm, instrumental, loopable` |
| `music_duel` | Duels (and Free-for-all), most of the match | `darksynth, cyberpunk battle tension, pulsing sequenced bass, tight electronic drums, sparse arpeggios, minimal melody, steady build, background game soundtrack, 105 bpm, instrumental, loopable` |
| `music_duel_tense` | When someone is down to a third of their Morale | `aggressive darksynth, cyberpunk final battle, distorted driving bass, pounding drums, urgent arpeggios, high stakes, relentless energy, 130 bpm, instrumental, loopable` |
| `music_victory` | A win (5 to 8 seconds) | `short triumphant victory fanfare, synth brass and big drum hit, cyberpunk, ends on a held major chord, 6 seconds` (or cut the first seconds of a longer take) |
| `music_defeat` | A loss (5 to 8 seconds) | `short somber defeat sting, dark descending synth, heavy low hit, ends on a low drone, cyberpunk, 6 seconds` |

## Ambience (ElevenLabs Sound Effects, loops)

20 to 22 seconds each; turn on Loop if it's offered, so they repeat without a bump. These play
quietly under everything.

| File | Where | Prompt |
|---|---|---|
| `amb_city_rain` | Duels: the street around the mat | `Steady night rain in a city alley, rain on puddles and metal fire escapes, water dripping from gutters, distant traffic hissing on wet roads, very faint far-off siren, no thunder, no voices, calm and immersive` |
| `amb_crowd` | Finding a match, the Free-for-all lobby, Rock Paper Scissors | `A crowd of 40 people murmuring in a rainy alley at night, waiting for a street fight to start, indistinct chatter, an occasional distant laugh or shout, no clear words, light rain` |
| `amb_rooftop` | Fight Mode (the rooftop over the city) | `Wind gusting across a city rooftop at night, light rain ticking on metal vents and a water tower, distant city hum far below, an occasional far-off car horn` |

## Sound effects (ElevenLabs Sound Effects)

### New sounds

| File | When | Length | Prompt |
|---|---|---|---|
| `neon_buzz` (make 3) | A neon light on the mat stutters | 0.5 to 1 s | `A failing neon tube flickering, electrical buzz and crackle cutting in and out` |
| `phase_deployment` | The Deployment phase starts | 1 to 2 s | `Short dark synth swell, cinematic interface stinger for a card game, rising, futuristic` |
| `phase_brawl` | The Brawl phase starts | 1 to 2 s | `Boxing bell dinging twice over a deep cinematic impact boom, a street fight begins` |
| `phase_regroup` | The Regroup phase starts | 1 s | `Soft reversed whoosh settling into a calm low synth tone, interface transition` |
| `turn_yours` | Your turn starts | 1 s | `Bright confident two-note synth chime rising, your turn notification, futuristic card game` |
| `turn_theirs` | An opponent's turn starts | 1 s | `Dark low two-note synth chime falling, opponent's turn notification` |
| `hover` | The pointer goes over a button | 0.1 s | `Very soft short digital tick, interface hover` |
| `click` | A button is pressed | 0.1 s | `Crisp short interface button click, futuristic, satisfying` |
| `error` | A move isn't allowed | 0.3 s | `Short low double buzz, interface error, denied` |
| `karat` | Karat earned (results screen) | 0.5 s | `A few gold coins clinking, reward` |

### Sounds still made in code (wanted)

| File | When | Length | Prompt |
|---|---|---|---|
| `effect` | A card effect triggers | 0.5 s | `Magical sparkle chime, a card ability activates, futuristic` |
| `promote` | A promotion, level up, achievement | 1 s | `Power-up: rising synth with sparkle, a character evolves` |
| `whoosh` | Cards flying, screen changes | 0.4 s | `Fast whoosh of a card flying through the air` |
| `riser` | Build-up before big moments | 0.5 s | `Short tension riser, rising whoosh before an impact` |
| `heartbeat` | Low Morale | 1 s | `One heavy heartbeat thump, low health tension` |
| `gunshot` | Militia's attacks | 0.4 s | `Single pistol shot echoing in an alley` |
| `lockon` | Militia's airdrop targets a lane | 0.6 s | `Military targeting reticle locking on, quick radar beeps` |
| `airdrop` | Militia's airdrop lands | 2 s | `A jet roaring overhead, then a heavy crate landing with a thud` |
| `tear` | Shop: swiping across a pack (plays over and over) | 0.15 s | `Foil wrapper crinkling as it tears, short` |
| `burst` | Shop: the pack bursts open | 1 s | `A card pack bursting open, foil burst with a sparkle` |
| `charge` | Shop: before the burst and a Rare reveal | 1.2 s | `Energy charging up, rising anticipation riser` |
| `shimmer` | Shop: an Uncommon turns over | 0.8 s | `Light magical shimmer sparkle` |
| `reveal_rare` | Shop: a Rare turns over | 1.2 s | `Bright bell chime reveal, a rare item` |
| `reveal_epic` | Shop: an Epic turns over | 1.5 s | `Epic synth chord hit, purple magic reveal` |
| `reveal_legendary` | Shop: a Legendary turns over | 2.5 s | `Legendary reveal fanfare, golden choir and synth brass hit` |
| `new_card` | Shop: NEW on a card | 0.5 s | `Pleasant short ding, a new item` |

### Already recorded (keep)

`draw`, `set`, `flip`, `slam`, `heavy`, `hit`, `damage`, `down`, `ko`, `boom`, `ambush`, `laser`,
`laser_beam`, `pack_open`, `shuffle` (Kenney, CC0).

## Remaking the stand-ins

`node tools/render_audio.mjs` renders every stand-in again (or `node tools/render_audio.mjs
amb_crowd` just one). It skips any sound that already has a real recording (`.ogg` or `.mp3`).
