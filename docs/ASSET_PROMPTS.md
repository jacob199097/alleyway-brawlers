# Art that would polish the game (with prompts)

Everything here has a place waiting for it: drop the file in `assets/` (the name and size below)
and the game uses it; until then it uses what it has now. Sounds are in `docs/AUDIO_PROMPTS.md`.

Every prompt ends with the game's look. If a result drifts, attach the Archon of Nebula's or
General Graves's card as a style reference and add "in the same style as the attached card".

**Style (the end of every prompt):** `Style: bold comic-book ink linework with cel shading, gritty
grunge texture, rain-soaked cyberpunk city at night, neon magenta, teal and violet light, like a
collectible trading-card game.`

In order of how much they'd add:

| # | What | File | Size | Where it shows |
|---|---|---|---|---|
| 1 | Game icon | `godot/icon.png` (+ `.ico`) | 1024 × 1024 | the .exe, taskbar and window (now Godot's robot) |
| 2 | Clan emblems | `assets/emblems/<clan>.png` | 512 × 512, transparent | clan mastery on the results screen |
| 3 | Achievement icons | `assets/achievement_trophy.png`, `assets/achievement_locked.png` | 256 × 256, transparent | achievements list and unlock banners (now 🏆 / 🔒) |
| 4 | Screen backgrounds | `assets/bg_<screen>.png` | 2816 × 1536 (16:9) | that screen instead of the alley |
| 5 | A new clan's kit | see below | | every clan you add |

---

## 1. Game icon

Needs a full build (it's a project setting): send it over and it goes in with the next one.

```
App icon for the street-fighting trading card game "Alleyway Brawlers": a clenched fist wrapped in a torn neon-magenta hand wrap, bursting through a playing card, sparks and rain, a glowing teal outline, on a dark rounded-square background with a subtle brick texture. Bold, simple and readable at small sizes, centred, no text. Style: bold comic-book ink linework with cel shading, gritty grunge texture, neon magenta and teal light. Square 1024x1024.
```

## 2. Clan emblems

One per clan, the crest from its pack (the same symbol, on its own). Transparent background.

**Militia** (`assets/emblems/militia.png`)
```
A military crest emblem for the Militia clan: a five-pointed star between two spread wings, stencilled, glowing neon lime green over olive-drab metal with scratches and rivets, a thin camo ring around it. Centred, symmetrical, no text, transparent background. Style: bold comic-book ink linework with cel shading, gritty grunge texture. Square 512x512.
```

**Nebula** (`assets/emblems/nebula.png`)
```
A cosmic crest emblem for the Nebula clan: a four-pointed compass star circled by a tilted planet ring, glowing violet and cyan, crystal shards and stardust around it, set on a dark disc of swirling purple galaxy. Centred, symmetrical, no text, transparent background. Style: bold comic-book ink linework with cel shading, gritty grunge texture. Square 512x512.
```

**Any new clan** (fill in the brackets)
```
A crest emblem for the [CLAN NAME] clan: [ITS SYMBOL, e.g. "a pair of dice showing two sevens inside a horseshoe"], glowing neon [CLAN COLOUR], [ITS MATERIAL, e.g. "on a cracked gold casino chip"]. Centred, symmetrical, no text, transparent background. Style: bold comic-book ink linework with cel shading, gritty grunge texture. Square 512x512.
```

## 3. Achievement icons

**Unlocked** (`assets/achievement_trophy.png`)
```
A street-style trophy icon: a battered gold trophy cup made from a boxing glove on a stack of poker chips, glowing warm gold, a neon magenta rim light, sparkles. Centred, no text, transparent background. Style: bold comic-book ink linework with cel shading, gritty grunge texture. Square 256x256.
```

**Locked** (`assets/achievement_locked.png`)
```
A locked achievement icon: a heavy steel padlock with a chain wrapped around it, dull grey-blue metal with rust and scratches, a faint teal glow in the keyhole. Centred, no text, transparent background. Style: bold comic-book ink linework with cel shading, gritty grunge texture. Square 256x256.
```

## 4. Screen backgrounds

Each screen has panels over most of it, so the art needs a calm, darker middle and edges, no
characters in front and no words. The game darkens it and adds rain and embers.

| File | Screen | Idea |
|---|---|---|
| `bg_shop.png` | Card packs | a back-alley black-market stall |
| `bg_card_library.png` | Card Library | a collector's hideout full of framed cards |
| `bg_deck_builder.png` | Deck Builder | a workbench with cards spread out |
| `bg_achievements.png` | Achievements | a trophy wall in a gang's clubhouse |
| `bg_social.png` | Social Club | a dim underground bar |

**Shop**
```
Wide background art for a game menu: a back-alley black-market stall at night under a tarp, crates of foil-wrapped card packs and glowing contraband briefcases on shelves, a hand-painted price board with no readable words, string lights and a buzzing neon sign with no letters, rain dripping from the tarp, the centre of the image dark and open. No characters, no text. Style: bold comic-book ink linework with cel shading, gritty grunge texture, rain-soaked cyberpunk city at night, neon magenta, teal and violet light. Landscape 16:9, 2816x1536.
```

**Card Library**
```
Wide background art for a game menu: a cramped collector's hideout above the city at night, walls covered floor to ceiling with framed trading cards and binders, a glowing display case, a big rain-streaked window with neon city light behind, the centre of the image dark and calm. No characters, no text. Style: bold comic-book ink linework with cel shading, gritty grunge texture, rain-soaked cyberpunk city at night, neon magenta, teal and violet light. Landscape 16:9, 2816x1536.
```

**Deck Builder**
```
Wide background art for a game menu: a gang's workbench seen from above at a slight angle, scattered trading cards, a desk lamp throwing a warm pool of light, coffee cups, a cracked phone, a knife pinning a card to the wood, neon light from a window at the edges, the centre of the table clear and in shadow. No characters, no text. Style: bold comic-book ink linework with cel shading, gritty grunge texture, rain-soaked cyberpunk city at night, neon magenta, teal and violet light. Landscape 16:9, 2816x1536.
```

**Achievements**
```
Wide background art for a game menu: the trophy wall of a street gang's clubhouse, battered trophies, championship belts, framed photos with no faces, medals and spray-painted tally marks on brick, dim spotlights from above, the centre of the image dark and calm. No characters, no text. Style: bold comic-book ink linework with cel shading, gritty grunge texture, rain-soaked cyberpunk city at night, neon magenta, teal and violet light. Landscape 16:9, 2816x1536.
```

**Social Club**
```
Wide background art for a game menu: a dim underground bar at night, booths with torn leather seats, a pool table under a hanging lamp, a jukebox glowing magenta, neon tubes along the ceiling with no letters, haze in the air, the centre of the room dark and open. No characters, no text. Style: bold comic-book ink linework with cel shading, gritty grunge texture, rain-soaked cyberpunk city at night, neon magenta, teal and violet light. Landscape 16:9, 2816x1536.
```

## 5. A new clan's kit

What each new clan needs (the game shows it as soon as the file is there; until then it uses the
clan leader's card or the default back):

| File | Size | Prompt |
|---|---|---|
| `assets/<clan>_booster.png` | 600 × 800 (3:4) | copy the Militia pack prompt in `docs/MILITIA_PACK_PROMPTS.md`, swap the leader, colours and clan name |
| `assets/<clan>_deckbox.png` | 512 × 512 | the same file's deck box prompt, swapped the same way |
| `assets/<clan>_deck.png` | 512 × 512 | the clan's leader standing tall on its home turf (its tile on the Choose Your Clan screen) |
| `assets/card_back_<clan tag>.png` | 1054 × 1492 | below |
| `assets/emblems/<clan>.png` | 512 × 512 | section 2 |

**Card back**
```
The back of a trading card for the [CLAN NAME] clan of "Alleyway Brawlers": a symmetrical design with the clan's crest ([ITS SYMBOL]) glowing at the centre, an ornate frame of [ITS MATERIAL AND PATTERN, e.g. "green felt and gold casino trim"], neon [CLAN COLOUR] accents, the same design top and bottom. Full bleed to the edges, no text. Style: bold comic-book ink linework with cel shading, gritty grunge texture. Portrait, 1054x1492.
```

For the **luck clan**, a theme that fits its coin flips and dice: an underground casino. Gold and
emerald, green felt, poker chips, dice and horseshoes, a leader like a slick card sharp in a
velvet suit.
