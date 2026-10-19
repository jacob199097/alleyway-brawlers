# Militia: new card ideas

Militia has 21 deckable cards to Nebula's 25 and wins 45-47% of games against it with random decks
(`node tools/balance.mjs`); the starter decks are even. Its best cards (Bastion, The Colonel, False
Retreat, Checkpoint Zero, Tripwire) are the "go wide" ones, so these ideas deepen that plan and fill
what it lacks:

- **Authority 4-6:** nothing between Sergeant Ironwall (4) and Sarge (7).
- **A way to KO outright:** Nebula has Event Horizon.
- **A finisher:** a turn where going wide pays off.
- **An answer to Stasis:** Nebula's main weapon.
- **A second leader** and a **Legendary** (no clan has one yet).

Every effect below is buildable in the Card Forge today. Stats are starting points: press **Test this card** in the
Forge, then run `node tools/balance.mjs --vs militia,nebula` once they're in.

Rarity: 1 Common, 2 Uncommon, 3 Rare, 4 Epic, 5 Legendary.

| # | Card | Type | Auth | Rarity | ATK / DEF | Fills |
|---|---|---|---|---|---|---|
| 1 | Quartermaster Vance | Brawler | 5 | 2 | 1800 / 1600 | mid-curve, card draw |
| 2 | Doorkicker Diaz | Brawler | 5 | 1 | 2000 / 1000 | mid-curve, beats Ambushes |
| 3 | Mortar Team | Brawler | 4 | 2 | 1200 / 1400 | reach (Morale damage) |
| 4 | Rhodes, Tank Commander | Heavy | 6 | 3 | 2400 / 2300 | mid-curve Heavy, tempo |
| 5 | Private Cole (3 levels) | Striver | 1 / 4 / 7 | 1 | see below | a go-wide Striver line |
| 6 | Artillery Strike | Hustle | 3 | 3 | - | KO removal |
| 7 | Full Assault | Hustle | 4 | 3 | - | finisher |
| 8 | Smoke Screen | Ambush | 1 | 2 | - | protection |
| 9 | Signal Jammer | Hustle | 1 | 2 | - | answer to Stasis (CLEANSE) |
| 10 | Major Kestrel | Leader | 10 | 4 | 3000 / 2200 | second leader (aggro) |
| 11 | Warlord Brannigan | Heavy | 9 | 5 | 3400 / 3000 | Legendary |

---

## Art style (every prompt)

All prompts share the Militia look (General Graves, the pack and the deck box). If a result drifts,
attach General Graves's card as a style reference and add "in the same style as the attached card".
The Forge puts the frame, name and text on, so the art has none.

---

## 1. Quartermaster Vance

**Brawler · Authority 5 · Uncommon · 1800 / 1600**

> When deployed: If you control 2 or more other MILITIA characters, draw 1 card.

Forge: When deployed → Draw cards (1). Only if: You control 2+ other characters, clan Militia.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A heavyset, middle-aged quartermaster with a grey buzz cut and a thick moustache, sleeves rolled up on a woodland-camo shirt, a lime-green armband, a pencil behind his ear, checking a clipboard while leaning on a stack of olive-drab ammo crates and supply drums in a rain-soaked back alley at night, a tarp shelter strung overhead, a lime-green work lamp lighting the scene, a militia star stencilled on the crates. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 2. Doorkicker Diaz

**Brawler · Authority 5 · Common · 2000 / 1000**

> When this card attacks: Destroy one of your opponent's face-down cards.

Forge: When it attacks → Destroy back-row cards (1). Test it in the Forge: if Ambushes still spring
first, change it to "When deployed".

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A lean, fierce breacher in a woodland-camo combat vest and a black balaclava with a glowing lime-green visor strip, mid-kick, smashing a steel door off its hinges in a neon-lit alley at night, splinters and sparks flying, a breaching shotgun slung across his back, lime tactical tape on his boots. Dynamic low-angle action shot. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 3. Mortar Team

**Brawler · Authority 4 · Uncommon · 1200 / 1400**

> ACTIVATE (once per turn, this card can't attack this turn): Your opponent loses 400 Morale.

Forge: Activate, cost "This card can't attack this turn" → Morale damage (400), once per turn.
(Morale starts at 6000: about a sixth of it in four turns, a slow pressure card.)

```
Trading card illustration for "Alleyway Brawlers", Militia clan. Two militia soldiers in woodland-camo ponchos crouched behind sandbags on a rain-slick rooftop at night, one dropping a shell into a battered mortar tube, the other covering his ears and pointing at the neon city skyline, a bright lime-green muzzle flash lighting their faces, smoke curling into the rain. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the subject centred with space around the edges. No text, no border, no card frame.
```

## 4. Rhodes, Tank Commander

**Heavy · Authority 6 · Rare · 2400 / 2300**

> When deployed: If you control 2 or more other MILITIA characters, DOWN one enemy character.

Forge: When deployed → DOWN, One enemy. Only if: You control 2+ other characters, clan Militia.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A broad-shouldered tank commander with a scarred jaw and a black beret with a green star badge, standing up out of the hatch of a rusted, graffiti-covered armoured truck converted into a makeshift tank, one fist raised to signal the advance, headlights and lime-green running lights cutting through the rain, a burning barricade being crushed under the treads in a narrow city street at night. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the subject centred with space around the edges. No text, no border, no card frame.
```

## 5. Private Cole (Striver, 3 levels)

The same name on all three cards, each promoting into the next (like Kade).

| Level | Auth | ATK / DEF | Effect |
|---|---|---|---|
| 1 | 1 | 600 / 600 | At the end of your turn: If you control 3 or more MILITIA characters, PROMOTE this card. |
| 2 | 4 | 1600 / 1300 | At the end of your turn: If you control 3 or more MILITIA characters, PROMOTE this card. |
| 3 | 7 | 2600 / 2200 | Your other MILITIA characters gain +200 ATK. |

Forge: At the end of your turn → PROMOTE. Only if: You control 3+ characters, clan Militia. Level 3:
Always (passive) → Change ATK +200, All other allies, clan Militia.

**Level 1**
```
Trading card illustration for "Alleyway Brawlers", Militia clan. A nervous young recruit, barely an adult, in an oversized woodland-camo jacket and a dented helmet, gripping a rifle too big for him, standing guard in a rainy alley at night under a flickering lime-green neon sign, older militia soldiers blurred in the background. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

**Level 2**
```
Trading card illustration for "Alleyway Brawlers", Militia clan. The same young soldier, now battle-hardened: a fitted woodland-camo jacket with a lime-green sergeant's stripe, a scar across one cheek, helmet strapped tight, advancing confidently through a smoky street at night with a squad behind him, rifle at the ready. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

**Level 3**
```
Trading card illustration for "Alleyway Brawlers", Militia clan. The same soldier as a veteran captain: a long woodland-camo coat, a black beret with a green star badge, a glowing lime-green eyepiece, standing on top of a barricade of crates and a burnt-out car, rallying a crowd of militia soldiers below with a raised fist, a tattered camo flag with a winged lime star behind him, the neon city burning in the background. Heroic low-angle shot. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 6. Artillery Strike

**Hustle · Authority 3 · Rare**

> If you control 3 or more MILITIA characters: KO one enemy character.

Forge: KO, One enemy. Only if: You control 3+ characters, clan Militia. (Event Horizon does this with
no condition; the condition is the price of matching it.)

```
Trading card illustration for "Alleyway Brawlers", Militia clan. An artillery shell screaming down out of a stormy night sky onto a neon-lit city street, the moment of impact: a huge lime-green and orange explosion tearing up the asphalt, shattered neon signs, debris and rain blasted outward, the silhouette of an enemy fighter thrown back by the blast. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo tones with neon lime-green accents. Square 1024x1024. No text, no border, no card frame.
```

## 7. Full Assault

**Hustle · Authority 4 · Rare**

> Your MILITIA characters gain +500 ATK until end of turn.

Forge: Change ATK +500, All allies, clan Militia, Until end of turn. With 4 characters out that's
+2000 ATK across the board: the turn going wide pays off.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A full militia charge down a rain-soaked alley at night: a wave of soldiers in woodland camo with lime-green armbands surging toward the viewer, shouting, weapons raised, a tattered camo flag with a winged lime star carried at the front, flares burning lime green overhead, puddles exploding under their boots. Epic wide-angle action shot. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024. No text, no border, no card frame.
```

## 8. Smoke Screen

**Ambush · Authority 1 · Uncommon**

> When an enemy attacks one of your MILITIA characters: Stun the attacker, and one of your MILITIA
> characters gains SHIELD.

Forge: Stun, The attacker. Shield, One other ally, clan Militia. (Stun doesn't stop this attack, so
give the Shield to the character being attacked: it survives, and the attacker sits out next turn.)

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A smoke grenade bursting in a narrow alley at night, thick billowing lime-green smoke filling the street, the silhouettes of militia soldiers slipping away into it, an enemy fighter coughing and shielding his eyes, neon signs glowing through the haze, rain falling through the smoke. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents. Square 1024x1024. No text, no border, no card frame.
```

## 9. Signal Jammer

**Hustle · Authority 1 · Uncommon**

> CLEANSE your MILITIA characters. Draw 1 card.

Forge: CLEANSE, All other allies, clan Militia; then Draw cards (1). CLEANSE takes away STASIS,
FREEZE, STUN, SUPPRESS, SILENCE, POISON, BURN, BLEED and BOUNTY, and is the one effect that can reach
a character in STASIS.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A grizzled militia radio operator in a woodland-camo jacket and headphones, hunched over a battered field radio covered in duct tape and antennas, cranking a dial, a crackling lime-green electric pulse bursting outward from the antenna and shattering floating purple cosmic energy chains in the air around him, rain on a rooftop at night. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents against shards of violet cosmic energy. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 10. Major Kestrel (leader)

**Leader · Authority 10 · Epic · 3000 / 2200 · Influence 4000**

> While this leader is Dormant, at the start of your turn: One of your MILITIA characters gains
> +500 ATK until end of turn.
> Once per turn, when this leader is attacked while Dormant: DOWN the attacker.
> AWAKEN: When your Authority reaches 9, this leader may take the field.

The aggressive Militia leader: General Graves rewards a wide board, Kestrel pushes one attacker each
turn and punishes attacks on her.

```
Trading card illustration for "Alleyway Brawlers", Militia clan leader. A sharp-eyed female militia major in her forties with a silver undercut and a hawk tattoo on her neck, a fitted olive-drab officer's coat with lime-green epaulettes, a black beret with a green star badge, one hand on a holstered sidearm, a real hawk perched on her raised leather-gloved forearm, standing on a rooftop ledge above a rain-soaked neon city at night, searchlights sweeping behind her, a tattered camo flag with a winged lime star rippling in the wind. Commanding, heroic composition. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 11. Warlord Brannigan (Legendary)

**Heavy · Authority 9 · Legendary · 3400 / 3000**

> When deployed: Put a MILITIA Brawler with 4 or less Authority from your deck onto the field.
> Your other MILITIA characters gain +200 ATK and +200 DEF.

Forge: When deployed → Deck to the field (character, Brawler, clan Militia, Authority 4 or less).
Always (passive) → Change ATK +200 and DEF +200, All other allies, clan Militia.

```
Trading card illustration for "Alleyway Brawlers", Militia clan, legendary card. A towering, battle-scarred warlord in heavy improvised armour plates bolted over a woodland-camo greatcoat, a huge grey beard, a glowing lime-green cybernetic eye, a massive belt-fed machine gun resting on one shoulder, seated on a throne built from ammo crates, sandbags and a wrecked armoured truck, his militia army kneeling in ranks before him with lime-green flares, a giant tattered camo flag with a winged lime star hanging behind, the neon city burning in the distance under a stormy sky. Epic, grand composition with dramatic lime-green rim lighting. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

---

## Also worth a look

- **Improvised Armor** is played in only 43% of the games it's drawn in (impact -3.3): drop it to
  Authority 0 or let it also draw a card when played.
- **Rook, Mule and Lance** hover around zero impact: +200 ATK each would make them pull their weight.

---

# More Militia ideas: the Line

Militia wins by having **more bodies than you can handle**. Its cards care about how many
Militia it controls, who stands next to whom, and reinforcements arriving from the deck. It
shells you from behind the line (Mortar Team) and gets stronger as it fills the board. Nebula wants
a small board, so every card here pushes the other way: more characters, and rewards for keeping
them.

These also fix two current problems:

- **Heavies stuck in hand.** Brannigan, Rhodes, the Colonel and Sarge sit there because Militia runs
  out of tributes. Conscript tokens are free tributes.
- **Militia trails 46-47%,** so these are tuned a little generous.

| # | Card | Type | Auth | Rarity | ATK / DEF | Role |
|---|---|---|---|---|---|---|
| 12 | Conscript | Token | - | - | 500 / 500 | the bodies everything else makes |
| 13 | Drill Sergeant Hollis | Brawler | 3 | 2 | 1100 / 1500 | makes Conscripts |
| 14 | Reinforcements Inbound | Hustle | 3 | 3 | - | an instant line |
| 15 | Forward Observer | Brawler | 2 | 1 | 600 / 900 | artillery that scales with width |
| 16 | Next in Line | Ambush | 2 | 2 | - | a fallen soldier is replaced |
| 17 | Shield Wall | Ambush | 2 | 3 | - | the whole line hits back |
| 18 | Chain of Command | Hustle (Continuous) | 2 | 3 | - | cards for going wide |
| 19 | "Big Bertha" Siege Gun | Heavy | 7 | 4 | 2400 / 3200 | turns bodies into Morale damage |

## 12. Conscript (Token)

**Token · 500 / 500 · no effect**

Made in the Forge as a **Token card**, so it never goes in a deck. It's a body to fill a lane,
stand next to someone for adjacency bonuses, or be a tribute for a Heavy.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A nervous young conscript in an oversized helmet and a mismatched camo jacket two sizes too big, clutching an old rifle, a lime-green armband tied on crooked, standing in line in a rain-soaked back alley at night with blurred silhouettes of other recruits behind him. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 13. Drill Sergeant Hollis

**Brawler · Authority 3 · Uncommon · 1100 / 1500**

> When deployed: Create a Conscript token in ATK position.
> At the end of your turn: If you control 2 or fewer characters, create a Conscript token.

Forge: When deployed → Token (Conscript, 1); At the end of your turn → Token (Conscript, 1), Only if:
You control 1 or fewer other characters. Two bodies for 3 Authority, and he keeps refilling a thin line.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A barrel-chested drill sergeant with a shaved head, a campaign hat and a scarred jaw, mid-shout with a whistle in one fist, pointing a row of rookie recruits into formation in a flooded back alley at night, a lime-green floodlight behind him, rain bouncing off his shoulders. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 14. Reinforcements Inbound

**Hustle · Authority 3 · Rare**

> Create 2 Conscript tokens. If your Morale is 3000 or less, create 3 instead.

Forge: Token (Conscript, 2); a second Token (Conscript, 1), Only if: Your Morale is 3000 or less.
Gives Brannigan or the Colonel their tributes in one card. It's also the comeback card, and it
pairs with General Graves waking at low Morale.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A battered troop truck skidding to a stop at the mouth of a neon-lit alley at night, its tailgate dropping as a squad of militia fighters in camo and lime-green armbands leap out into the rain, a flare burning lime green in the sky above. Dramatic low angle. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024. No text, no border, no card frame.
```

## 15. Forward Observer

**Brawler · Authority 2 · Common · 600 / 900**

> ACTIVATE (once per turn, this card can't attack this turn): Your opponent loses 200 Morale for
> each other MILITIA character you control.

Forge: Activate (cost: can't attack this turn) → Damage (200), per: your other characters, clan
Militia. Weak alone, but with four friends it's an 800-a-turn spotter for the guns.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A lean scout lying flat on a wet rooftop ledge at night, binoculars raised, a radio handset pressed to her ear, a lime-green laser designator beam cutting through the rain toward a distant neon street, camo netting over her back. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 16. Next in Line

**Ambush · Authority 2 · Uncommon**

> When an enemy attacks one of your MILITIA characters: Put a MILITIA Brawler with 3 or less
> Authority from your deck onto the field in ATK position. Create a Conscript token.

Forge: Ambush, when an enemy attacks one of your characters (clan Militia) → Call (Brawler, Militia,
max Authority 3); Token (Conscript, 1). False Retreat's little brother: the line never gets thinner.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. Over the shoulder of a fallen militia fighter in the rain, a fresh fighter in camo and a lime-green armband steps forward out of the smoke to take his place in the line, more silhouettes stepping up behind, a burning barrel lighting the alley. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024. No text, no border, no card frame.
```

## 17. Shield Wall

**Ambush · Authority 2 · Rare**

> When an enemy attacks one of your MILITIA characters: If you control 3 or more MILITIA
> characters, your MILITIA characters gain +600 ATK and +600 DEF until the end of the turn.

Forge: Ambush, when an enemy attacks one of your characters (clan Militia) → Buff (+600 / +600), All
your characters (clan Militia), Until the end of this turn; Only if: You control 3+ characters,
clan Militia. One attack into a full line turns the whole formation around.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A row of militia fighters locking riot shields together across a narrow alley at night, the shields spray-painted with lime-green stars, rain and sparks bouncing off them as a blast of violet energy slams into the wall, boots braced in the puddles. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024. No text, no border, no card frame.
```

## 18. Chain of Command

**Hustle · Continuous · Authority 2 · Rare**

> CONTINUOUS Once per turn, when you deploy a MILITIA character: Draw 1 card.

Forge: Hustle, Continuous; Once per turn, when you deploy a character (clan Militia) → Draw cards (1).
Going wide costs Militia its hand. This refills it every turn the line grows.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A war table in a bunker lit by a hanging lime-green lamp: a city map covered in pins and string, radio sets crackling, a commander's gloved hand pushing a small tin soldier into place while orders on folded papers stack up beside it, rain streaking the slit window. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024. No text, no border, no card frame.
```

## 19. "Big Bertha" Siege Gun

**Heavy · Authority 7 · Epic · 2400 / 3200 · Sacrifice 1**

> ACTIVATE (once per turn, sacrifice one of your other characters): Your opponent loses 1200 Morale.
> Your opponent must attack this card first if it is standing.

Forge: Activate (cost: sacrifice) → Damage (1200); Always → Guard. Feed it Conscripts and it
finishes games from behind the line. Its Guard makes the opponent take on the big wall before
the gun.

```
Trading card illustration for "Alleyway Brawlers", Militia clan. A huge rusted artillery cannon bolted onto the back of a scrap-armoured truck in a ruined street at night, its barrel recoiling as it fires a shell trailing lime-green fire over the neon skyline, crew members in camo covering their ears, shell casings and rain everywhere. Epic low angle. Style: bold comic-book ink linework with cel shading, gritty grunge texture, olive drab, black and woodland camo with neon lime-green accents, rain streaks and drifting embers. Square 1024x1024, centred with space around the edges. No text, no border, no card frame.
```
