# Card art that drifted from the house style: what to redo, and the prompt

The house style (most cards in every clan): bold comic-book ink linework with cel shading, gritty grunge
texture, heavy black outlines and inked shadows, rugged faces drawn like a Western graphic novel, the
character big in the frame, and the clan's own colours. Good examples: Sarge, Static and Johnson
(Militia), Mickey Dukes (Wildcard), Noctra and Widow Thorne (Underworld), Gasoline Gus (Arsonists),
Mutiny Mags and Barnacle Bess (Pirates), every Neutral card.

The outliers drift two ways: **too anime** (big glossy eyes, smooth skin, pretty-boy faces, clean flat
shading) or **too painterly** (soft realistic brushwork, no ink lines, small figure in a wide sunset
landscape, muddy colours).

## The outliers

Found by looking at all 314 cards' art side by side (November 2026). "Refs" are on-style cards to attach
as style references: same clan, so the colours stay right.

### Redo these first (clearly off)

| Card | What's wrong | Refs |
|---|---|---|
| Militia: **Lance LV3** | painterly sunset, small soft figure | Lance LV2 (the character), Sarge, Johnson |
| Militia: **Deadwood LV1, LV2, LV3** | realistic painting, muddy, no ink lines, figure lost in the landscape | Briar (also a sniper), Static |
| Militia: **Bastion LV1** | soft realistic face and brushwork | Sarge, Doorkicker Diaz |
| Wildcard: **Lucky Lou LV1, LV2, LV3** | anime boy: big eyes, smooth face | Mickey Dukes LV1, Dice Delgado LV1 |
| Wildcard: **Tommy Reed LV1, LV2, LV3** | clean manhwa pretty-boy, flat shading | Mickey Dukes LV2, Odds-On Otis |
| Wildcard: **Vincent Vale** (leader) | anime face and white hair, too clean | Mickey Dukes LV1, Garrison |
| Underworld: **Wick LV1, LV2, LV3** | anime girl with huge glossy eyes | Noctra, Widow Thorne |
| Underworld: **Wisp, the Lost Soul** | chibi anime ghost | Noctra, Wick LV1 once redone |
| Nebula: **Vesper - Void Dancer** | anime heroine | Vael LV1, Herald of the Horizon |
| Nebula: **Time Dilation** | anime heroine | Vael LV1, Atlas LV1 |
| Arsonists: **Haze LV1** | realistic painted sunset landscape, no ink | Gasoline Gus, Blaze Maddox LV1 |

### Worth a look (milder)

- Wildcard: **Roberto**, **Jennifer - The Croupier**, **Penny Harlow LV1-3**: a bit anime in the face.
- Arsonists: **Kindle LV1-3**: cartoony grin, though inked. **Haze LV2**: soft, painterly smoke.
- Militia: **Mary LV1-3**: brown, candle-lit and painterly. **False Retreat** and **Checkpoint Zero**:
  so dark there's no clear subject.
- Pirates: **Fogbank Finn**: smoother and softer than the rest of the crew.
- Wildcard: **Johnny Deuce, Roxy "Jackpot" Ramos, Monte Silva**: on-style, but red on red, so the
  figure gets lost. Ask for "a clear dark silhouette against the red, gold rim light on the figure".

Not outliers, but different: Nebula's first 40 cards (Kade to Black Hole) are a cleaner, flatter comic
style than its later cards and the other clans. They match each other, so they read as a set. Redo them
only if you want one style across the whole game.

## The prompt

Attach, in this order:

1. **The card to redo.** The art alone: open the card in its Forge and press **Download this card's
   art** under the preview (or use the card PNG).
2. **Two style references** from the table above (card PNGs are fine).

Then paste this, with the clan's colours filled in from the list below:

> Using the same artstyle as the reference images, redraw the first image so it matches them.
>
> The first image is the picture to redo: keep its character, face shape, hair, outfit, pose, props
> and setting, and keep the framing. The other images are style references only: take their art
> style, not their characters, poses, clothes or props.
>
> The style: bold comic-book ink linework with cel shading, gritty grunge texture. Heavy black
> outlines, inked shadows and hatching, worn and grimy surfaces, rugged realistic proportions, faces
> drawn like a Western graphic novel. Not anime: no big glossy eyes, no smooth airbrushed skin, no
> soft painterly blur. The character fills the frame.
>
> Colours: [the clan's colours].
>
> A landscape picture (4:3) of the artwork only: no card frame, border, text or logo.

**For a Striver line**, redo the lowest level first. For the levels above it, attach the new picture
as the first image (not the old one) and start with: "The same character, now [what changes at
this level, from the old card]..." followed by the style part of the prompt. Lance only needs LV3:
attach Lance LV2 as the character, plus one style reference.

**If it comes back still too smooth:** "Rougher: thicker black ink lines, more hatching and grime,
less smoothing on the skin and face."
**If the colours drift** (a reference's light bleeds in): "Keep only the [clan] colours: [the
colours]. No [the wrong colour] light anywhere."

### Clan colours

- **Militia:** olive drab, black and woodland camo with neon lime-green accents, rain streaks and
  drifting embers, a neon-lit city at night.
- **Wildcard:** deep black and casino red with gleaming gold and hot-magenta neon accents, scattered
  playing cards, poker chips and dice, smoky back-room haze.
- **Underworld:** deep black and violet with blood-red cracks and sickly purple flames, skulls,
  chains, gravestones and gothic ruins, drifting ghostly mist.
- **Nebula:** deep black and violet with iridescent purple and cyan glow, scattered stars and cosmic
  dust.
- **Arsonists:** deep black and charcoal with blazing orange and ember-red fire, glowing embers,
  drifting ash and thick smoke.
- **Pirates:** deep navy night sea and black water, sea-teal and verdigris green, rusted iron orange,
  glints of brass and gold, harbour fog, cold teal moonlight and warm sodium-orange dock lamps, no
  purple or magenta light.

## Getting the new art in

Upload it to the card in its Forge (Militia, Wildcard, Underworld, Nebula, Arsonists: Card Forge;
Pirates and Neutral: Card Forge 2). New art goes through the Real-ESRGAN smoother before export, like
every card. Then export and import as usual (`docs/CARD_PIPELINE.md`). Art-only changes need no game
update: the game downloads the new card images at start-up.
