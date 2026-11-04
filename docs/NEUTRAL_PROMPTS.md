# Neutral cards: the first 20, and their art prompts

Neutral cards belong to no clan and go in any deck, next to the leader's clan's cards (a deck holds
only its leader's clan and Neutral cards). They have no leader, starter, booster or deck box: they drop
from every clan's packs (about 1 card in 5), use the generic AlleyWay Brawlers card back
(`assets/card_back_neutral.png`) and the steel Neutral frame, and fight like the street (a streetlamp
summon, a comic-book POW! attack, a cartoon knockout).

All 20 are in **Card Forge 2** (NEUT-001 to NEUT-020, tagged In progress until their art is in). Each one
already has its look and scene filled in, so the Forge's Art prompt panel writes a prompt too. Every effect
uses blocks other cards already use. In 3000 CPU games (`node tools/balance.mjs --extra <catalog>`) they
came out a little weaker than clan cards, as intended: impact −5 to +5. The Legendary, Mack, was +9.

Neutral cards have no keywords of their own and use none of the clans' (STASIS, SUPPRESS, STOKE,
LOADED DICE, UNDEAD...). They do plain things any gang would: draw, Morale, DOWN, BOUNTY, GUARD.

## Using the prompts (ChatGPT)

- Attach one or two finished cards from any clan as the style reference. The reference is for style only.
- Every Neutral picture keeps the same colours: charcoal and steel grey with rain-slick asphalt and
  grimy brick, warm sodium-orange streetlight, a few red and teal neon signs, steam and puddle reflections.
- Square pictures (1024 × 1024): the Forge crops them into the art window.

| # | Card | Type | Auth | Rarity | ATK / DEF | Effect |
|---|---|---|---|---|---|---|
| 001 | Street Rat | Brawler | 1 | 1 | 500 / 200 | When KO'd: draw 1 |
| 002 | Corner Lookout | Brawler | 2 | 2 | 400 / 700 | Your opponent's cards are MARKED |
| 003 | Doorman | Brawler | 2 | 1 | 600 / 1300 | GUARD (must be attacked first) |
| 004 | Back-Alley Medic | Brawler | 2 | 1 | 400 / 900 | When deployed: HEAL 900 |
| 005 | Pickpocket | Brawler | 2 | 2 | 800 / 500 | When deployed: draw 2, discard 1 |
| 006 | Crowbar Carl | Brawler | 3 | 1 | 1500 / 1000 | (none: big stats) |
| 007 | Getaway Driver | Brawler | 3 | 2 | 1300 / 600 | Can't be attacked while you have another character that can be |
| 008 | Bare-Knuckle Bruno | Brawler | 4 | 2 | 1800 / 900 | When it attacks: +400 ATK for the brawl |
| 009 | The Fixer | Brawler | 4 | 3 | 1200 / 1300 | When deployed: search your deck for a card of 4 Authority or less |
| 010 | Loan Shark | Brawler | 4 | 3 | 1500 / 1100 | When deployed: BOUNTY 2 on an enemy |
| 011 | Dirty Cop | Brawler | 5 | 3 | 1900 / 1700 | When deployed: an enemy to DEF |
| 012 | The Enforcer | Heavy (1 sacrifice) | 7 | 4 | 2800 / 2500 | When deployed: DOWN an enemy |
| 013 | Mack "Undisputed" Malone | Heavy (1 sacrifice) | 8 | 5 | 3200 / 2800 | PIERCE; once per turn, after a KO it attacks again |
| 014 | Cheap Shot | Hustle | 1 | 1 | - | One of yours +500 ATK this turn |
| 015 | Word on the Street | Hustle | 2 | 2 | - | Draw 2 |
| 016 | Patch Job | Hustle | 1 | 1 | - | HEAL 800 |
| 017 | Scatter! | Hustle | 3 | 3 | - | Return an enemy character to its owner's hand |
| 018 | Brass Knuckles | Hustle (Equip) | 2 | 2 | - | The equipped character +500 ATK |
| 019 | Dirty Trick | Ambush | 2 | 1 | - | The attacker loses 700 ATK for the brawl |
| 020 | Sucker Punch | Ambush | 3 | 3 | - | DOWN the attacker and negate the attack |

Every prompt starts the same way and ends with the same colours; only the middle changes:

> Using the same artstyle as the reference image. Take only the art style: don't reuse the reference's
> character, pose, clothes or props. **[the picture]** Colour scheme: charcoal and steel grey, rain-slick
> asphalt and grimy brick, warm sodium-orange streetlight, a few red and teal neon signs, steam and puddle
> reflections. Square card art, no text.

| # | The picture |
|---|---|
| 001 Street Rat | A scrawny teenage street kid in an oversized grey hoodie with the hood up, fingerless gloves, a split lip and a cheeky grin, crouched on top of an overflowing dumpster in a narrow alley, flicking a stolen coin, rats scurrying below. |
| 002 Corner Lookout | A lanky young woman with box braids tied up, a puffer vest, binoculars round her neck and a burner phone in hand, leaning over a rooftop ledge at night, looking down at the street through the binoculars, neon signs below. |
| 003 Doorman | A huge, calm bald man with a thick neck, black suit and bow tie, an earpiece and a velvet-rope post beside him, arms folded in front of a club door under a buzzing red neon sign, rain falling, a line of people behind the rope. |
| 004 Back-Alley Medic | A tired middle-aged woman with greying curls in a stained white coat over a band t-shirt, reading glasses, a duffel bag of medical supplies, stitching up a bruised fighter by the light of a bare bulb in a back room, bloody gauze on a crate. |
| 005 Pickpocket | A slick young man with a pencil moustache, a flat cap and a long trench coat lined with stolen wallets and watches, brushing past a stranger on a crowded night street, lifting a wallet with two fingers, winking at the viewer. |
| 006 Crowbar Carl | A stocky unshaven man in a dirty orange high-vis vest and ripped jeans, a heavy crowbar resting on his shoulder, standing in front of a chain-link fence he has just pried open, steam rising from a manhole behind him. |
| 007 Getaway Driver | A cool young woman with a sharp black bob, aviator sunglasses, a red racing jacket and driving gloves, leaning out of the window of a muscle car mid-drift around a street corner, tyre smoke and headlights. |
| 008 Bare-Knuckle Bruno | A scarred, broad-chested boxer with a crooked nose, slicked-back hair, a vest top and taped bare knuckles, throwing a huge haymaker inside a ring of shouting onlookers in an underground car park. |
| 009 The Fixer | A calm older man in a camel overcoat and a grey fedora, a neat white beard, a phone in each hand, sitting in a corner booth of an all-night diner, a ledger and a stack of envelopes on the table. |
| 010 Loan Shark | A smirking heavy-set man with a gold tooth, a loud striped suit, gold rings on every finger and a baseball bat, counting a thick wad of cash in a dim pawn shop, a ledger of names pinned to the wall behind him. |
| 011 Dirty Cop | A crooked police officer with a thick moustache, a loosened tie, an unbuttoned uniform shirt and a nightstick, pocketing an envelope of cash beside his patrol car, red and blue lights washing over a wet street. |
| 012 The Enforcer | A towering, silent man in a black leather coat and black turtleneck, a shaved head and a heavy chain wrapped round one fist, walking slowly out of thick fog under a single streetlight, smashed car windows either side of him. |
| 013 Mack "Undisputed" Malone | A legendary street champion in his forties, heavily muscled with a grey-streaked beard, a championship belt slung over one shoulder and an open denim jacket covered in fight patches, standing victorious on the roof of a wrecked car in the middle of a packed street fight, the crowd roaring, rain and a spotlight on him. |
| 014 Cheap Shot | A close-up of a fist in a knuckleduster driving into someone's ribs from behind, motion lines, a dropped bottle smashing. |
| 015 Word on the Street | Three shady figures whispering under a flickering streetlight beside a wall covered in torn posters and graffiti tags. |
| 016 Patch Job | A bruised hand wrapping duct tape round a bloody forearm, a first-aid kit and an ice pack on a car bonnet. |
| 017 Scatter! | A crowd of street fighters bolting in every direction down an alley as police searchlights sweep over them. |
| 018 Brass Knuckles | A pair of scratched brass knuckles on a wet bar counter, lit by a neon beer sign, a few drops of blood. |
| 019 Dirty Trick | A fighter flinging a handful of grit into an attacker's face mid-lunge, the attacker reeling back, dust in the air. |
| 020 Sucker Punch | A fist swinging out from behind a corner straight into a charging thug's jaw, the thug's feet leaving the ground. |

## The frame and the card back

Both are placeholders made from the game's own art: the frame is the Nebula frame in steel with the
AlleyWay Brawlers logo on the top-right plate where a clan's emblem would be (uploaded in Card Forge 2,
Settings → Clans → Neutral), and the back is asphalt, a steel border and the logo. To replace them with
ChatGPT versions:

- **Frame:** attach two clan frames (e.g. Nebula and Militia) and the logo (`assets/title_alleyway.png`)
  and ask: "Make a card frame in exactly the same layout and size as these (1024 × 1536, the same boxes
  in the same places, the art window and text box left empty), in brushed gunmetal and steel with rivets
  and scratches, silver trim instead of neon, and the attached logo small on the plate in the top-right
  corner where the clan emblem goes. No other text." Upload it in
  Card Forge 2 (Settings → Clans → Neutral → Replace card frame). Make the art window transparent or
  magenta, like the other frames.
- **Card back:** attach the logo (`assets/title_alleyway.png`) and a clan back, and ask: "A trading card
  back in the same size and style as this one (1024 × 1536), for cards of no clan: the attached logo in the
  middle under a single streetlight, wet asphalt, brick and a chain-link fence in charcoal and steel
  grey with warm orange light, a steel border. No other text." Save it as `assets/card_back_neutral.png`,
  commit and deploy: the server sends new backs to every game (no game update needed).
