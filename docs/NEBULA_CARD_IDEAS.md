# Nebula: new card ideas

Nebula already wins 53-57% against Militia with random decks (`node tools/balance.mjs`), so these
aren't more power: they're new ways to play the clan's identity, cosmic control: **STASIS**,
bending the board, and Strivers that rise through the stars. Several use the newest Card Forge
blocks: top of the deck, exile, swap ATK / DEF, loot and BOUNTY.

Every effect below can be built in the Card Forge today. Stats are starting points: press **Test
this card** in the Forge, then run `node tools/balance.mjs` once they're in.

Rarity: 1 Common, 2 Uncommon, 3 Rare, 4 Epic, 5 Legendary.

| # | Card | Type | Auth | Rarity | ATK / DEF | The idea |
|---|---|---|---|---|---|---|
| 1 | Star Cartographer | Brawler | 2 | 1 | 600 / 1200 | loot: draw 2, keep the best |
| 2 | Gravity Inversion | Hustle | 2 | 2 | - | swap ATK and DEF: walls become glass |
| 3 | Black Hole | Hustle | 4 | 3 | - | top of the deck: send a threat back |
| 4 | Singularity | Hustle | 6 | 4 | - | exile: gone for good |
| 5 | Comet Hunter | Brawler | 3 | 2 | 1400 / 600 | BOUNTY: hunt one target |
| 6 | Time Warden | Brawler | 5 | 3 | 1500 / 2200 | STASIS payoff |
| 7 | Nova (3 levels) | Striver | 1 / 4 / 7 | 1 | see below | a Striver that grows by freezing |
| 8 | Event Echo | Ambush | 2 | 2 | - | an attacker sent back on top |
| 9 | Vey, the Starbound | Leader | 10 | 4 | 2800 / 2600 | second leader: tempo and cards |
| 10 | Eclipse, Devourer of Stars | Heavy | 9 | 5 | 3600 / 3400 | Legendary |

---

## Art style (every prompt)

All prompts share the Nebula look (the Archon, the pack, the deck box): deep black and violet
with iridescent purple and cyan, galaxies, cosmic dust, crystal shards. If a result drifts, attach
the Archon of Nebula's card as a style reference and add "in the same style as the attached card".
The Forge puts the frame, name and text on, so the art has none.

---

## 1. Star Cartographer

**Brawler · Authority 2 · Common · 600 / 1200**

> When deployed: Draw 2 cards, then discard 1 card.

Forge: When deployed → Loot, Draw 2, Then discard 1. One card ahead, and the worst of three gone.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan. A young cosmic navigator in a long violet coat with brass instruments clipped to her belt, standing on a rooftop at night unrolling a glowing star chart that floats in the air in front of her, constellations of cyan light connecting into a map of the neon city below, a swirling purple galaxy overhead. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 2. Gravity Inversion

**Hustle · Authority 2 · Uncommon**

> Swap the ATK and DEF of all enemy characters until the end of your turn.

Forge: Swap ATK and DEF, All enemies, Until the end of this turn. Their walls (high DEF, low ATK)
become easy targets for one turn, and their strikers can't hit back.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan. A city street turned upside down by a gravity wave: cars, dumpsters, rain and street fighters floating upward toward a swirling violet vortex in the sky, neon signs flipped and drifting, shards of purple light rippling through the air in a distortion ring. Dramatic low angle. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024. No text, no border, no card frame.
```

## 3. Black Hole

**Hustle · Authority 4 · Rare**

> Put one enemy character on top of its owner's deck.

Forge: Put on top of its deck, One enemy. Better than sending it to the hand: they draw it
again instead of a new card, and have to pay for it again.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan. A small black hole tearing open above a neon alley at night, its glowing violet accretion disc spinning, an enemy street fighter being stretched and pulled into it, debris, rain and light bending around the event horizon, cyan sparks streaming inward. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024. No text, no border, no card frame.
```

## 4. Singularity

**Hustle · Authority 6 · Epic**

> Remove one enemy character from the game.

Forge: Exile (remove from the game), One enemy. It never reaches the Gutter, so nothing can bring
it back: strong, which is what Authority 6 pays for.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan. A single point of blinding white light collapsing at the centre of a vast swirling purple galaxy, everything around it — rooftops, rain, a fighter's silhouette — being erased into streaks of violet and cyan light, perfect silence and enormous scale. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024. No text, no border, no card frame.
```

## 5. Comet Hunter

**Brawler · Authority 3 · Uncommon · 1400 / 600**

> When deployed: Put a BOUNTY 2 on one enemy character.

Forge: When deployed → BOUNTY (2), One enemy. When that enemy is KO'd (by anything), you draw 2.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan. A lean bounty hunter in a dark violet duster and a glowing cyan visor, crouched on a ledge in the rain aiming a long rifle that trails comet light, a holographic wanted poster of the target floating beside her, a comet streaking across the purple night sky. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 6. Time Warden

**Brawler · Authority 5 · Rare · 1500 / 2200**

> When this card attacks a character in DEF position: Put one enemy character in STASIS.
> Once per turn, when an enemy character is KO'd: Draw 1 card.

Forge: When it attacks, Only if: other card is in DEF → STASIS, One enemy. Second effect: When an
enemy character is KO'd → Draw cards (1), Once per turn.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan. An armoured guardian in black and violet plate with a great clock-face of glowing cyan rings turning behind her, holding a staff that freezes falling rain in mid-air around her, frozen droplets glinting like stars, a neon city paused in time behind her. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 7. Nova (Striver, 3 levels)

| Level | Auth | ATK / DEF | Effect |
|---|---|---|---|
| 1 | 1 | 500 / 700 | Once per turn, when this card attacks: Put one enemy character in STASIS. If you do, PROMOTE this card. |
| 2 | 4 | 1500 / 1300 | Same as level 1. |
| 3 | 7 | 2600 / 2400 | This card can't be targeted by your opponent's effects. When deployed: Put all enemy characters in STASIS. |

Forge: When it attacks → STASIS, One enemy, Once per turn; then "If you do" → PROMOTE this card. Level 3: Always → Can't be targeted; When deployed → STASIS, All enemies.

**Level 1**
```
Trading card illustration for "Alleyway Brawlers", Nebula clan. A teenage street kid with a faint violet glow in her eyes and a hoodie covered in star patches, a small spark of purple starlight flickering between her fingers, standing in a rainy alley at night under a flickering neon sign. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

**Level 2**
```
Trading card illustration for "Alleyway Brawlers", Nebula clan. The same young woman, older and confident: a long violet coat over her hoodie, both hands wreathed in swirling purple starlight, freezing a falling enemy in mid-air inside a shell of crystal light, cosmic dust around her. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

**Level 3**
```
Trading card illustration for "Alleyway Brawlers", Nebula clan. The same woman reborn as a living star: floating above the city, hair and coat made of violet nebula clouds, a blazing white-violet nova bursting behind her, a ring of frozen enemies suspended in crystal light around her. Epic, radiant composition. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 8. Event Echo

**Ambush · Authority 2 · Uncommon**

> When an enemy attacks one of your NEBULA characters: Flip a coin. If heads, put the attacker on top of its owner's deck.

Forge: Ambush, springs for NEBULA characters → Put on top of its deck, the attacker, Luck: Flip a
coin. A gamble: half the time it's a clean answer that also costs them their next draw.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan. An attacking fighter mid-punch dissolving into a ripple of violet light, a faint echo of him already reappearing far away on top of a glowing deck of cards, a spinning coin of purple light hanging in the air between them. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024. No text, no border, no card frame.
```

## 9. Vey, the Starbound (leader)

**Leader · Authority 10 · Epic · 2800 / 2600 · Influence 3500**

> While this leader is Dormant, at the start of your turn: Draw 1 card, then discard 1 card.
> While this leader is Dormant, when your opponent deploys a character: Swap its ATK and DEF until the end of the next turn.
> AWAKEN: When your Gutter has 10 or more cards, this leader may take the field.

Forge: Leader; While Dormant at the start of your turn → Loot (1); While Dormant when your opponent
deploys → Swap ATK and DEF, One enemy, Until the end of the next turn. Awaken: Gutter has 10+.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan leader. A tall, serene figure in flowing white and violet robes woven with constellations, long silver hair drifting as if underwater, eyes glowing cyan, standing on a floating fragment of a shattered moon above the neon city, cards of starlight orbiting her like planets. Commanding, mystical composition. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 10. Eclipse, Devourer of Stars (Legendary)

**Heavy · Authority 9 · Legendary · 3600 / 3400 · Sacrifice 2**

> When deployed: Remove one enemy character from the game.
> When this card KOs a character: Put a BOUNTY 1 on one enemy character.
> This card has LIFESTEAL.

Forge: When deployed → Exile, One enemy; When it KOs a character → BOUNTY (1), One enemy; Always →
LIFESTEAL.

```
Trading card illustration for "Alleyway Brawlers", Nebula clan, legendary card. A colossal cosmic entity rising behind the city skyline, its body a dark silhouette swallowing the stars, a burning eclipse ring of violet and white fire for a face, enormous arms of nebula cloud reaching down between the towers, tiny fighters below looking up in awe, the Archon's crystal shards orbiting it. Epic, terrifying scale. Style: bold comic-book ink linework with cel shading, gritty grunge texture, deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic dust. Square 1024x1024, centred with space around the edges. No text, no border, no card frame.
```
