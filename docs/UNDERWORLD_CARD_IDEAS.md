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

Attach one finished Underworld card (Veyr or Malachar) to ChatGPT with each prompt: a new character's
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
Using this exact style, a hunched old gravekeeper with a long grey beard, a battered top hat and a patched black coat, leaning on a rusted shovel in a fog-filled graveyard at night. Behind him a skeleton claws its way out of a freshly dug grave, purple soulfire leaking from the cracked earth. He holds up a hanging lantern burning with violet flame. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 2. Lenore, the Grave Bride

**Brawler · Authority 4 · Uncommon · 1600 / 400**

> This card is UNDEAD. / Once per turn, when another of your characters is KO'd: Give one of your other
> UNDERWORLD characters UNDEAD.

Forge: Always → UNDEAD. Second effect: When another of your characters is KO'd → Give UNDEAD, Who: One
other ally, clan Underworld, once per turn.

```
Using this exact style, a pale undead bride in a torn, rotting wedding dress and a long tattered veil, her skin cracked with glowing violet veins, holding a bouquet of withered black roses that drip purple light. She drifts above a broken chapel aisle lined with toppled gravestones, wisps of souls circling her. Her eyes glow electric purple and blood-red tears run down her cheeks. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 3. The Mortician

**Brawler · Authority 4 · Uncommon · 1300 / 1300**

> ACTIVATE (once per turn), sacrifice another of your characters: Draw 2 cards.

Forge: Activate → Draw cards (2). Cost: Sacrifice another of your characters. Once per turn. (Good with
Skeleton tokens: free bodies to sacrifice.)

```
Using this exact style, a tall, gaunt undertaker in a pinstriped black suit, rubber apron and long leather gloves, a stitched-on smile and round tinted spectacles glowing violet. He stands over a steel embalming table in a dingy basement morgue, holding a scalpel and a toe tag, jars of glowing purple fluid on the shelves and a body bag twitching behind him. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 4. Doctor Morbus

**Brawler · Authority 3 · Uncommon · 1100 / 600**

> When deployed: Give one enemy character POISON 200.

Forge: When deployed → POISON, Who: One enemy, amount 200.

```
Using this exact style, a sinister plague doctor in a long black leather coat and a cracked bone-white beaked mask, glowing purple eyes behind round glass lenses, holding a smoking censer that leaks violet poison fog. Rats scurry around his boots on a rain-slick alley street, and red lanterns glow in the fog behind him. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 5. Ossian, the Bone Thief

**Brawler · Authority 5 · Rare · 1900 / 500**

> When deployed: Put a character with 4 or less Authority from your opponent's Gutter onto your side of
> the field.

Forge: When deployed → Gutter to the field, from the opponent's Gutter, Authority up to 4.

```
Using this exact style, a wiry grave robber with a hooded, ragged cloak stitched from burial shrouds, a skull-faced mask and long bony fingers, dragging a sack bulging with stolen bones over his shoulder. He crouches on top of a cracked crypt at night, a ghostly figure rising from the sack on a thread of violet soulfire. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 6. Hollow Wraith

**Brawler · Authority 6 · Rare · 2600 / 0**

> This card is UNDEAD. / This card can't be attacked while you have another character that can be.

Forge: Always → UNDEAD. Second effect: Always → Can't be attacked (elusive).

```
Using this exact style, a towering hooded wraith with no face, only an empty black void and two burning violet eyes, its tattered robes dissolving into purple smoke at the edges. Skeletal hands hold a long rusted scythe with chains wrapped around the shaft. It floats over a misty cemetery, half see-through, gravestones visible through its body. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
```

## 7. Mortivar — The Bone Colossus (Legendary)

**Heavy · Authority 9 · Legendary · 3600 / 2600 · tribute 2**

> When deployed: Give your other UNDERWORLD characters UNDEAD. / This card gains +200 ATK for each
> UNDERWORLD character in your Gutter (up to 10).

Forge: When deployed → Give UNDEAD, Who: All other allies, clan Underworld. Second effect: Always → Change
ATK / DEF, This card, ATK 200, How many times: For each card in your Gutter, Count only (clan) Underworld,
Count only (kind) Characters only, At most 10.

```
Using this exact style, a colossal giant built from thousands of fused bones and skulls, a ribcage chest with a burning violet soulfire heart inside it, a crown of horns and spinal columns, chains hanging from its arms. It rises out of a collapsing mass grave in the middle of a ruined city street, tiny skeletons climbing over its shoulders, hellfire bursting from the cracks in the ground. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character filling the frame from a low angle. No text, no border, no card frame.
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
Using this exact style, a small, cheeky skeleton kid with a cracked skull, a backwards baseball cap and an oversized hoodie, grinning wide and waving a rib bone like a sword. Little violet flames flicker in his eye sockets. Two smaller skeletons peek out from behind a tombstone next to him in a graveyard alley at night. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024, the character centred with space around the edges. No text, no border, no card frame.
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
Using this exact style, a ritual circle carved into a cracked graveyard floor at night, glowing violet runes, candles of purple flame around the edge. In the middle, skeletal arms and a hooded corpse burst up out of the ground in a column of purple hellfire, gravestones toppling outward. No people besides the rising dead. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
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
Using this exact style, a field of crooked gravestones under a blood-red moon, the ground split with glowing purple cracks, and a crowd of grinning skeletons pulling themselves up out of the earth at once, bony hands everywhere, bits of dirt and purple embers flying. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
```

## 14. Soul Toll

**Hustle · Authority 4 · Rare**

> Drain 200 Morale for each card in your Gutter (up to 10).

Forge: Drain Morale, amount 200, How many times: For each card in your Gutter, At most 10.

```
Using this exact style, a ghostly ferryman's skeletal hand held out, palm up, collecting glowing coins that are actually tiny screaming souls. Behind it a dark river of purple light flows under a crumbling stone bridge, streams of souls being pulled from the far bank toward the hand. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
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
Using this exact style, a crowd of skeletons and ghosts dancing wildly in a ruined ballroom, a skeleton band playing a broken piano and a violin, chandeliers burning with violet flame, tattered party streamers and purple confetti made of embers. The dancers' bones glow purple at the joints. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
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
Using this exact style, dozens of grey, rotting hands bursting out of a cracked alley street and grabbing the legs of a stumbling shadowy brawler, dragging him down. Purple light glows from the cracks, rain bounces off the pavement, and blood-red neon signs reflect in the puddles. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
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
Using this exact style, a frightened street fighter standing in a dark apartment hallway, surrounded by pale ghostly faces with wide open mouths emerging from the walls, their wailing shown as rippling violet sound waves. The light bulb overhead flickers purple, and black handprints cover the peeling wallpaper. Underworld colours: deep violet and electric-purple hellfire, blood-red embers and glowing cracks, bone white and charcoal black. Square 1024x1024. No text, no border, no card frame.
```

---

## One gap worth a new Forge effect

Underworld has no way to fill its **own** Gutter on purpose (the Forge's "Mill" only mills the opponent).
A "Send the top N cards of your deck to your Gutter" effect would make Veyr's Awaken (10 Gutter cards),
Malachar and Soul Toll much more reliable. It's a rules change (both engines), so it isn't used above.
