# Underworld: cards still needed

Underworld has 11 base characters, 3 Strivers (Dredge, Vespera, Malachar), a leader (Veyr) and the
Skeleton token. It has **no Hustles or Ambushes**. The other clans have about 21 base characters,
6 Striver lines, 6–7 Hustles and 3–4 Ambushes each, which is what a 40-card starter deck needs.

| | Underworld now | Other clans | Ideas below |
|---|---|---|---|
| Base characters | 11 | 20–22 | +10 (3 of them new Strivers) |
| Striver lines (LV2/LV3 cards) | 3 (6 cards) | 6 (12 cards) | +3 lines (6 cards) |
| Hustles | 0 | 6–7 | +7 |
| Ambushes | 0 | 3–4 | +4 |
| Legendary | none | 1 each | +1 (Mortivar) |

The Authority curve also has gaps at 3, 5 and 6, and only one Uncommon (Sable). The ideas fill those
and lean into the clan's plan: **tokens, UNDEAD, and a big Gutter** (Veyr awakens at 10 Gutter cards,
Malachar grows with it).

Every effect is buildable in the Card Forge today. Stats are starting points: press **Test this card**
in the Forge, then run `node tools/balance.mjs` once they're in.

Rarity: 1 Common, 2 Uncommon, 3 Rare, 4 Epic, 5 Legendary.

## Fix first (in the Forge)

- **UNDE-018 "New Card"** is an empty draft (LV1, 1000/1000, no effect or art). Use it for one of the
  cards below, or delete it.
- **Vespera LV3 (UNDE-020)** has no effect. Suggestion, a Soul Weaver who stitches souls back:
  > When deployed: Put an UNDERWORLD character from your Gutter onto the field. / Once per turn, when
  > another of your characters is KO'd: Draw 1 card.
- **Two old Skeleton tokens (UNDE-003, UNDE-004, status "idea")** share their codes with Dredge LV1
  and LV2. They're left over from merging the Skeletons into UNDE-002 (which has the art variants).
  Delete them.

## Summary

| # | Card | Type | Auth | Rarity | ATK / DEF |
|---|---|---|---|---|---|
| 1 | Gravekeeper Mott | Brawler | 3 | Common | 1200 / 600 |
| 2 | Lenore, the Grave Bride | Brawler | 4 | Uncommon | 1600 / 400 |
| 3 | The Mortician | Brawler | 4 | Uncommon | 1300 / 1300 |
| 4 | Doctor Morbus | Brawler | 3 | Uncommon | 1100 / 600 |
| 5 | Ossian, the Bone Thief | Brawler | 5 | Rare | 1900 / 500 |
| 6 | Hollow Wraith | Brawler | 6 | Rare | 2600 / 0 |
| 7 | Mortivar — The Bone Colossus | Heavy | 9 | Legendary | 3600 / 2600 |
| 8 | Bonesy (3 levels) | Striver | 1 / 4 / 7 | Common | 300/0 · 1600/400 · 2400/800 |
| 9 | Wick (3 levels) | Striver | 1 / 4 / 7 | Uncommon | 400/300 · 1200/1400 · 2200/2200 |
| 10 | Morrow (3 levels) | Striver | 2 / 5 / 8 | Rare | 900/0 · 2100/0 · 3100/0 |
| 11 | Raise the Dead | Hustle | 3 | Uncommon | – |
| 12 | Grave Robbing | Hustle | 1 | Common | – |
| 13 | Bone Harvest | Hustle | 2 | Common | – |
| 14 | Soul Toll | Hustle | 4 | Rare | – |
| 15 | Last Rites | Hustle | 5 | Rare | – |
| 16 | Danse Macabre | Continuous Hustle | 3 | Uncommon | – |
| 17 | Chains of the Damned | Equip | 2 | Uncommon | – |
| 18 | Grasping Hands | Ambush | 2 | Common | – |
| 19 | Death's Embrace | Ambush | 3 | Uncommon | – |
| 20 | Open Grave | Ambush | 4 | Rare | – |
| 21 | Haunting | Continuous Ambush | 3 | Rare | – |

---

## Art style (every prompt)

Each prompt has its own setting, camera angle and twist, so the set doesn't all look like the same graveyard. Attach one finished Underworld card (Veyr or Malachar) to ChatGPT with each prompt: a new character's
first prompt starts "Using this exact style"; a Striver's later levels start "The same character, but
now…" with the previous level attached. The Forge adds the frame, name and text, so the art has none.

Underworld colours, in every prompt: **deep violet and electric-purple hellfire, blood-red embers and
glowing cracks, bone white and charcoal black.**

---

## 1. Gravekeeper Mott

**Brawler · Authority 3 · Common · 1200 / 600**

> When deployed: Deploy a Skeleton token in ATK position.

Forge: When deployed → Deploy tokens (Skeleton, 1).

```
Using this exact style, seen from the bottom of a freshly dug grave looking straight up: a hunched old gravekeeper with a long grey beard, battered top hat and patched black coat stands at the edge, silhouetted against a huge blood-red moon, a shovel over his shoulder and a swinging lantern of violet flame lighting his wrinkled grin from below. A skeletal hand grips the edge of the grave right beside the viewer. Beyond the cemetery railings, a city skyline glows with purple neon. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 2. Lenore, the Grave Bride

**Brawler · Authority 4 · Uncommon · 1600 / 400**

> This card is UNDEAD. / Once per turn, when another of your characters is KO'd: Give one of your other
> UNDERWORLD characters UNDEAD.

Forge: Always → UNDEAD. Second effect: When another of your characters is KO'd → Give UNDEAD, Who: One
other ally, clan Underworld, once per turn.

```
Using this exact style, a tilted, dreamlike view of a derelict hotel ballroom flooded ankle-deep with black water: a pale undead bride spins mid-dance, her torn wedding dress and long veil billowing into violet smoke, withered black rose petals turning to ash around her. A cracked wall mirror behind her shows her reflection as the living, smiling bride she once was. Her skin is cracked with glowing purple veins, blood-red tears on her cheeks, a broken chandelier hanging crooked above. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 3. The Mortician

**Brawler · Authority 4 · Uncommon · 1300 / 1300**

> ACTIVATE (once per turn), sacrifice another of your characters: Draw 2 cards.

Forge: Activate → Draw cards (2). Cost: Sacrifice another of your characters. Once per turn. (Good with
Skeleton tokens: free bodies to sacrifice.)

```
Using this exact style, a tight three-quarter close-up in the back room of an all-night funeral parlour under a single flickering fluorescent tube: a gaunt undertaker in a pinstriped waistcoat, rubber apron and round tinted spectacles reflecting violet light, calmly stitching a body under a white sheet with thread that glows purple. A neat steel tray of tools sits beside him, and the corpse's hand has just twitched and gripped his sleeve. He is smiling. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 4. Doctor Morbus

**Brawler · Authority 3 · Uncommon · 1100 / 600**

> When deployed: Give one enemy character POISON 200.

Forge: When deployed → POISON, Who: One enemy, amount 200.

```
Using this exact style, a symmetrical one-point view down an abandoned subway platform at night: a plague doctor in a long black leather coat and cracked bone-white beaked mask walks out of the train tunnel toward the viewer, swinging a smoking censer. Violet poison fog rolls off the tracks around his boots, a river of rats pours along the platform edge, and the cracked tiled walls are lit by one blood-red emergency light. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 5. Ossian, the Bone Thief

**Brawler · Authority 5 · Rare · 1900 / 500**

> When deployed: Put a character with 4 or less Authority from your opponent's Gutter onto your side of
> the field.

Forge: When deployed → Gutter to the field, from the opponent's Gutter, Authority up to 4.

```
Using this exact style, an action shot in pouring rain: a wiry grave robber in a hooded cloak stitched from burial shrouds and a skull-faced mask leaps between the rooftops of two city mausoleums, mid-air, a bulging sack of stolen bones over his shoulder. A ghostly prisoner is half-pulled out of the sack on a violet chain, clawing to get free. Lightning in purple and red behind him, motion streaks in the rain. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 6. Hollow Wraith

**Brawler · Authority 6 · Rare · 2600 / 0**

> This card is UNDEAD. / This card can't be attacked while you have another character that can be.

Forge: Always → UNDEAD. Second effect: Always → Can't be attacked (elusive).

```
Using this exact style, an empty laundromat at three in the morning, one strip light flickering: a towering hooded wraith glides silently along the row of washing machines, half see-through, its tattered robes trailing like wet sheets and melting into purple smoke. Its face is an empty black void with two burning violet eyes, mirrored in every round machine door. Skeletal hands rest on a long rusted scythe wrapped in chains. Lonely, quiet and eerie. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 7. Mortivar — The Bone Colossus (Legendary)

**Heavy · Authority 9 · Legendary · 3600 / 2600 · tribute 2**

> When deployed: Give your other UNDERWORLD characters UNDEAD. / This card gains +200 ATK for each
> UNDERWORLD character in your Gutter (up to 10).

Forge: When deployed → Give UNDEAD, Who: All other allies, clan Underworld. Second effect: Always → Change
ATK / DEF, This card, ATK 200, How many times: For each card in your Gutter, Count only (clan) Underworld,
Count only (kind) Characters only, At most 10.

```
Using this exact style, a worm's-eye view from street level as a colossal giant built from thousands of fused bones and skulls tears up through a collapsing city overpass, flipped taxis and cars falling around it. A burning violet soulfire heart blazes inside its ribcage chest, a crown of horns and spines crowns its skull, and one huge bony hand crushes a streetlamp. Tiny skeletons swarm over its shoulders, and hellfire bursts up through the cracked road. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

---

## 8. Bonesy (Striver, 3 levels): the Skeleton line

**LV1 Bonesy · Authority 1 · Common · 300 / 0**

> When deployed: Deploy a Skeleton token in ATK position. / At the end of your turn: If you control 3
> or more characters, PROMOTE this card.

**LV2 Bonesy — Rattling Knight · Authority 4 · 1600 / 400**

> This card is UNDEAD. / At the start of your turn: Deploy a Skeleton token in ATK position. / After this
> card attacks 2 times: PROMOTE this card.

**LV3 Bonesy — Lord of the Ossuary · Authority 7 · 2400 / 800**

> This card is UNDEAD. / This card gains +300 ATK for each of your other characters. / At the start of
> your turn: Deploy a Skeleton token in ATK position.

```
Using this exact style, a chain-link fenced basketball court at night under one buzzing floodlight: a small, cheeky skeleton kid in a backwards cap and an oversized hoodie dribbles a glowing purple skull like a basketball, mid-crossover, grinning wide with little violet flames in his eye sockets. Two smaller skeleton buddies cheer from the bench, one banging two bones together. Graffiti-style shapes (no lettering) on the court walls, purple smoke drifting. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

```
The same character, but now grown into a skeleton knight: taller, in rusted, mismatched armour plates bolted onto his bones, the hoodie torn into a cape, wielding a jagged bone sword and a shield made from a coffin lid. A small squad of skeleton soldiers marches behind him through purple fog. Same Underworld colours. Square 1024x1024. No text, no border, no card frame.
```

```
The same character, but now a towering skeleton lord on a throne made of stacked skulls in a vast underground ossuary, wearing a crown of bone spikes and a heavy cloak of chains, his eye sockets blazing with violet hellfire. An army of skeletons kneels before him, their eyes glowing purple. Same Underworld colours. Square 1024x1024. No text, no border, no card frame.
```

## 9. Wick (Striver, 3 levels): the Lantern line

**LV1 Wick · Authority 1 · Uncommon · 400 / 300**

> When this card is KO'd: Draw 1 card. / When another of your characters is KO'd: PROMOTE this card.

**LV2 Wick — The Lantern Wisp · Authority 4 · 1200 / 1400**

> When deployed: Return an UNDERWORLD character from your Gutter to your hand. / At the end of your
> turn: If your Gutter has 6 or more cards, PROMOTE this card.

**LV3 Wick — Soulfire Beacon · Authority 7 · 2200 / 2200**

> LIFESTEAL. / When an enemy character is KO'd: Drain 300 Morale.

```
Using this exact style, a small ghost girl made of pale smoke, a candle melted into the top of her head with a violet flame, carrying a little iron lantern full of tiny glowing souls. She peers shyly from behind a crooked gravestone, her lower body trailing into wisps, purple candlelight on the fog around her. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

```
The same character, but now an older, braver lantern spirit: taller, her candle flame now a crown of violet fire, holding a long shepherd's crook with the lantern hanging from it, leading a line of lost souls through a dark tunnel like glowing fireflies. Same Underworld colours. Square 1024x1024. No text, no border, no card frame.
```

```
The same character, but now a radiant soulfire beacon: a tall, glowing spirit queen floating above a cathedral of graves, a blazing violet flame where her head was, hundreds of souls spiralling up into her lantern, which now burns like a small sun. Blood-red sparks rain down around her. Same Underworld colours. Square 1024x1024. No text, no border, no card frame.
```

## 10. Morrow (Striver, 3 levels): the Risen Brawler line

**LV1 Morrow · Authority 2 · Rare · 900 / 0**

> This card is UNDEAD. / When this card Downs a character: PROMOTE this card.

**LV2 Morrow — The Risen Contender · Authority 5 · 2100 / 0**

> This card is UNDEAD. / Once per turn, when this card KOs a character: It can attack again. / After this
> card attacks 3 times: PROMOTE this card.

**LV3 Morrow — Undying Champion · Authority 8 · 3100 / 0**

> This card is UNDEAD. / This card attacks twice each turn.

```
Using this exact style, a zombie street boxer who died in the ring: grey rotting skin stitched together, taped-up fists, torn boxing shorts and a faded robe, one eye glowing violet. He climbs back up off the canvas of an abandoned underground fight ring, the crowd made of shadowy ghosts, purple hellfire leaking from his wounds. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

```
The same character, but now a hulking undead contender: bigger and stronger, chains wrapped around his fists like knuckledusters, a championship belt made of bone across his shoulder, mid-punch with a shockwave of purple fire. Same Underworld colours. Square 1024x1024. No text, no border, no card frame.
```

```
The same character, but now the undying champion: a giant, scarred undead fighter wreathed in violet hellfire, both fists blazing, a crown of thorns and a bone championship belt, standing over a broken ring with ghostly crowds roaring in the stands. Same Underworld colours. Square 1024x1024. No text, no border, no card frame.
```

---

## 11. Raise the Dead

**Hustle · Authority 3 · Uncommon**

> Put an UNDERWORLD character with 5 or less Authority from your Gutter onto the field.

Forge: Gutter to the field, clan Underworld, Authority up to 5.

```
Using this exact style, a low-angle street view in a rain-soaked back alley: a manhole cover blasts into the air on a pillar of violet hellfire, and a horde of skeletons and corpses claws its way up out of the sewer, one after another. Steel shutters, dumpsters and fire escapes line the alley, and the purple light floods every puddle. No living people. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 12. Grave Robbing

**Hustle · Authority 1 · Common**

> Return up to 2 UNDERWORLD characters from your Gutter to your hand.

Forge: Gutter to hand, amount 2, clan Underworld.

```
Using this exact style, a pair of gloved hands prying open a coffin in a freshly dug grave at night, a shovel stuck in the dirt pile, a lantern glowing violet beside it. From inside the coffin, purple light spills out and ghostly hands reach up for the lantern. Rain and fog. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
```

## 13. Bone Harvest

**Hustle · Authority 2 · Common**

> Deploy 2 Skeleton tokens in ATK position.

Forge: Deploy tokens (Skeleton, 2).

```
Using this exact style, an overgrown empty city lot under a huge orange-red harvest moon: rows of skeletons sprout from the dirt like crops, some only skulls poking up, some halfway out and stretching. A skeletal scarecrow with a rusted scythe stands watch over them, and a wheelbarrow piled with skulls sits at the end of a row. Tall apartment blocks loom behind a broken fence, violet mist drifting between the rows. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 14. Soul Toll

**Hustle · Authority 4 · Rare**

> Drain 200 Morale for each card in your Gutter (up to 10).

Forge: Drain Morale, amount 200, How many times: For each card in your Gutter, At most 10.

```
Using this exact style, a toll booth on a long foggy bridge over a river of glowing purple light: a skeletal attendant in a peaked cap leans out of the booth with an open bony palm, collecting coins that are tiny screaming souls. The barrier arm is a giant bone. A queue of pale ghost cars and ghostly figures stretches back into the fog, waiting to pay. Moody and quiet, one red lamp on the booth. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 15. Last Rites

**Hustle · Authority 5 · Rare**

> If your Gutter has 8 or more cards: KO one enemy character.

Forge: KO, Who: One enemy. Only if: Your Gutter has 8+ cards.

```
Using this exact style, a hooded priest of the dead silhouetted against a blood-red moon, raising a black bell that rings out a shockwave of violet energy. In front of him a shadowy figure crumbles into ash and purple embers, its soul being pulled away in a ribbon of light. Ruined church arches frame the scene. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
```

## 16. Danse Macabre

**Continuous Hustle · Authority 3 · Uncommon**

> Your UNDERWORLD characters gain +300 ATK.

Forge: Continuous Hustle. Always → Change ATK / DEF, Who: All allies, clan Underworld, ATK 300.

```
Using this exact style, a packed underground nightclub: a skeleton DJ in headphones works the decks, a dance floor of skeletons and ghosts mid-move below him, under a mirror ball shaped like a skull that scatters violet and blood-red laser beams through the smoke. Bones glow purple at every joint, and a ghost couple twirls through a pillar in the foreground. Loud, wild and fun. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 17. Chains of the Damned

**Equip · Authority 2 · Uncommon**

> The equipped character gains +500 ATK and has LIFESTEAL.

Forge: Equip. Always → Change ATK / DEF (ATK 500); second effect: Always → LIFESTEAL.

```
Using this exact style, a set of heavy black iron chains wrapped around a clenched fist, the links etched with glowing violet runes, hooks and broken shackles hanging from them. Purple hellfire crawls along the chains and souls are being dragged along the links. Dark stone background with red embers. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
```

## 18. Grasping Hands

**Ambush · Authority 2 · Common**

> When one of your characters is attacked: DOWN the attacker.

Forge: Ambush. When it's attacked → DOWN, Who: The attacker.

```
Using this exact style, looking straight down the spiral of a run-down tenement stairwell: a shadowy street fighter flees down the stairs as grey, rotting hands burst up out of every step and through the bannisters, grabbing at his ankles and coat. Purple light glows through the cracks in the steps, one bare bulb swings overhead, and peeling paint hangs from the walls. Dizzying, claustrophobic. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

## 19. Death's Embrace

**Ambush · Authority 3 · Uncommon**

> When one of your characters is attacked: Give your UNDERWORLD characters UNDEAD.

Forge: Ambush. When it's attacked → Give UNDEAD, Who: All allies, clan Underworld.

```
Using this exact style, a huge shadowy figure of Death with wide, tattered wings wrapping its arms protectively around a group of undead fighters, violet soulfire flowing from its embrace into their bodies. Its face is a cracked skull with glowing purple eyes. A graveyard at night behind them. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
```

## 20. Open Grave

**Ambush · Authority 4 · Rare**

> When one of your characters is attacked: Put the attacker on top of its owner's deck.

Forge: Ambush. When it's attacked → Put on top of its deck, Who: The attacker.

```
Using this exact style, the ground of a cemetery suddenly opening into a deep, glowing grave beneath a charging shadowy attacker, who falls backwards into a pit of purple hellfire. Gravestones tilt over the edge and dirt crumbles in. Seen from above, dramatic angle. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
```

## 21. Haunting

**Continuous Ambush · Authority 3 · Rare**

> Once per turn, when your opponent deploys a character: SILENCE that character until the end of your
> next turn.

Forge: Continuous Ambush. When your opponent deploys a character → SILENCE, Who: That character (the one
just deployed), once per turn.

```
Using this exact style, a cramped apartment living room at night: a pale ghost face with a wide open, wailing mouth pushes out through the screen of an old boxy television, the screen's static glowing violet. A tough-looking street fighter in a jacket stumbles backwards over a toppled chair, terrified. Family photos on the wall have the faces scratched out, and black handprints creep across the peeling wallpaper. Underworld colours: deep violet and electric-purple hellfire, blood-red accents, bone white and charcoal black. Square 1024x1024. No text, letters or signs anywhere, no border, no card frame.
```

---

## One gap worth a new Forge effect

Underworld has no way to fill its **own** Gutter on purpose (the Forge's "Mill" only mills the opponent).
A "Send the top N cards of your deck to your Gutter" effect would make Veyr's Awaken (10 Gutter cards),
Malachar and Soul Toll much more reliable. It's a rules change (both engines), so it isn't used above.
