# Image prompts for the encounter portraits

Pictures saved here as `art/<name>.jpg` (or `.png`) replace the painted
portrait for that encounter. Then run:

```sh
python3 tools/paint_portraits.py   # converts art/ into the game's 1-bit portraits
python3 tools/build.py             # rebuilds churn.lua
```

Done so far: `jawhound.jpg`, `stag.jpg` (the user's own); `bandits.jpg` and
`fused.jpg` (Z-Image Turbo, seeds 1007/1004, first style); `boar.jpg`,
`crows.jpg`, `bloom.jpg`, `tollman.jpg`, `medic.jpg` (Z-Image Turbo, new
Cronenberg / S.T.A.L.K.E.R. / Lovecraft style, seeds 2101/2103/2106/2108/2109,
from the prompts below with the style blocks appended); `wanderer.jpg`
(seed 2110), `mouthless.jpg` (2111: the model still drew lips, so they are
sewn shut and the intro says so), and the anomalies `hollow.jpg` (2112),
`bell.jpg` (2113: the bell hangs over a pool; intro rewritten), `stars.jpg`
(2115), `stillness.jpg` (2116: the hand rises out of the ground; intro
rewritten) and `door.jpg` (2118, after 2117 showed day through the door).
`little.jpg` (the Little Ones) is the user's own picture. Every portrait
is done except Karl (the user's own photo, never generated).
The free Hugging Face GPU quota covers about 7 images before it runs out; it
refills over time.

Notes:
- The Fused: the model won't draw two bodies conjoined (seeds 2104, 2114 drew
  two separate people with bare ribcages), so the first-style `fused.jpg`
  stays. Next try: "Siamese twins, one shared torso".
- The Mouthless Man: the model wouldn't leave out the mouth (seeds 1005,
  1015), so he keeps his painted portrait for now. Wording to try next: "the
  skin of the lower face is stitched shut and healed into scar tissue", or an
  image editor to paint the mouth out.

**splash.png** (the start screen: a lone figure under a spiralling storm,
lightning and crows) and **title.png** (the title menu: a figure with a
backpack under a spiralling sky) are the user's own pictures.
`python3 tools/paint_title.py` bakes them (192x288, 1-bit; tone and an edge
crop per picture in its `PICTURES` list) into `src/69_title_art.lua`; run it
again after replacing either file.

**karl.jpg** (Karl, the riddling fisherman) will be the user's own photo of a
real person: no prompt, and never generated. Until it's added he shows a
placeholder smiley face (`karl()` in `tools/portraits.py`).

## Shared style (paste after every prompt)

The game's mood is three things at once, and every prompt should carry all of
them:
- **Cronenberg body horror:** flesh that has changed wrongly but plausibly:
  fused tissue, organs where they shouldn't be, wet sheen, veins, surgical
  seams, bone breaking through. Intimate and disgusting, not cartoon gore.
- **S.T.A.L.K.E.R. / Roadside Picnic:** a quiet, abandoned Eastern-European
  exclusion zone. Rusted Soviet-era junk, gas masks, patched military
  surplus, anomalies that break physics without spectacle.
- **Lovecraftian dread:** things that are wrong in ways the mind resists.
  Too many eyes, impossible geometry, a sense of something vast noticing you.

For **creatures**:

> Cronenberg-style body horror, Lovecraftian and wrong, a mutated creature
> from a S.T.A.L.K.E.R.-like exclusion zone. Photograph of a hyper-detailed
> practical-effects creature sculpture, full body, three-quarter side view,
> single subject centered, plain seamless white studio background, soft
> shadow under it, wet glossy mutated flesh, visible veins and fused tissue,
> strong clear silhouette, high contrast lighting, unsettling, no text, no
> frame.

For the **people**:

> A survivor of a S.T.A.L.K.E.R.-like exclusion zone, subtle Cronenberg body
> horror and Lovecraftian unease: something about them is quietly wrong.
> Realistic portrait photograph, head and shoulders to mid-chest, facing the
> camera slightly turned, plain seamless white studio background, hard side
> light, patched Soviet military surplus and gas-mask-era gear, grime and
> radiation-sick skin, haunted eyes, sharp focus on the face, no text.

For the **anomalies** (scenes, not creatures):

> A S.T.A.L.K.E.R. / Roadside Picnic zone anomaly with Lovecraftian cosmic
> dread: physics quietly broken in an ordinary place. Eerie realistic
> photograph, simple composition with one clear subject, flat empty
> grassland of an abandoned Soviet exclusion zone, rusted debris at the
> edges, pale overcast sky, high contrast, oppressive silence, no text.

## Why this style

The screen shows each picture at 96×96 in pure black and white.

- **One bold shape** on white reads well. Busy backgrounds, thin details and
  wide scenes turn into noise.
- **Faces and mouths** are what survive best, so keep them big.
- **Mid-tone colours** are the problem: the dog was dark red/green and needed
  brightening, the stag was pale pink and needed darkening. Either works;
  strong light and shadow on the subject helps most.
- **Square-ish framing:** very wide images get cropped. I set crop boxes per
  picture, but a subject that isn't stretched sideways gives the most detail.

## Creatures

**boar.jpg** (Skinless Boar):
A huge boar with no hide at all, only glistening red muscle, tendons and
gristle, heavy shoulders, cracked yellow tusks, small wet eyes, lifting its
snout to sniff.

**crows.jpg** (Knotted Crows):
Dozens of black crows grown together at the wings into one lumpy bush-shaped
body of feathers, many heads with beaks all turned toward the camera, beady
eyes, a few fused wings sticking out.

**fused.jpg** (The Fused):
Two gaunt people standing side by side, joined at the ribs by a stretched
bridge of shared skin, ragged clothes, heads turned toward each other,
whispering. *(People style.)*

**mouthless.jpg** (Mouthless Man):
A man in a rotted, torn raincoat. Where his mouth should be the skin has
healed over smooth. Wet gill slits in his neck flare open, staring eyes.
*(People style.)*

**bloom.jpg** (The Bloom):
A woman covered in soft, glossy pale-pink fleshy growths that swell like
bubbles over half her face and her body, one eye visible, a half smile.
*(People style.)*

## People

**bandits.jpg** (Road Bandits):
Two hooded road bandits stepping out from behind a rusted wrecked car, the
nearer one with a scarf over his face holding a knife low, the taller one
behind. *(People style, both figures.)*

**tollman.jpg** (Toll Man):
A thin man in a scuffed welding mask with a dark visor slit, tapping a lead
pipe against his leg, patched work jacket. *(People style.)*

**medic.jpg** (Old Medic):
An old woman with grey hair in a bun, clear kind eyes and steady hands, a
battered backpack with a red cross painted on it, waving you over.
*(People style; keep the cross in frame.)*

**wanderer.jpg** (Wanderer):
A bearded man in a wide-brimmed hat sitting by a small campfire, a walking
stick beside him, one open hand raised in greeting. *(People style, sitting,
with the fire in frame.)*

## Anomalies

**hollow.jpg** (The Humming Hollow):
A shallow dip in a grass field where the grass is pressed flat in a perfect
spiral, heat-shimmer distortion in the air above it, a crow at the edge
half-dissolving into nothing.

**bell.jpg** (The Drowned Bell):
The dark bronze crown of a huge church bell breaking up out of the ground in
an empty field, the earth around it rippling in rings like water.

**stars.jpg** (Wrong Stars):
Midday over a grass field, but one patch of the sky is pitch black and full
of strange stars forming an eye; a tiny lone figure on the horizon looking up.

**stillness.jpg** (The Stillness):
Birds frozen motionless in mid-flight above a field, dust hanging still in a
shaft of light, a hand reaching into the frame toward them.

**door.jpg** (The Door in the Field):
A lone wooden door frame standing in an empty field, no walls; through it you
see the same field at night, with a dark figure standing there waiting.

## The night things and the Institute (2026-10-03; all four done: the user's `institute.png`, `whisper.png`, `long_man.png`, `crawler.jpg` from these prompts)

The user's own pictures (`fused.jpg`, `stray.jpg`) set the look for these:
an old silver-gelatin photograph on a worn, yellowed print. Paste this after
each prompt:

> Aged black-and-white silver gelatin photograph, 1980s Soviet exclusion
> zone, worn yellowed print with chipped edges and dust specks, harsh
> on-camera flash, deep black shadows, high contrast, grainy, one large
> subject filling the middle of a square frame, unsettling and quiet,
> no text, no watermark.

**institute.jpg** (the quarry gate, and the Institute itself):
A massive rusted steel blast door set into the raw rock face of an abandoned
quarry, chained shut, a small card-reader slot beside it, an old stencilled
word above it faded to illegible, cracked concrete apron, a single bare bulb
burning over the door though there is no power anywhere, the rock around
the door stained in rings like ripples, the air in front of it faintly
warped. Square, the door filling the middle.

**whisper.jpg** (The Whisperers, from black water at night):
Night, a flash photograph of the black still surface of a pond in reeds,
three pale human faces just beneath the surface looking up, eyes open,
mouths parted as if speaking, their features slightly too smooth, the water
over them perfectly flat and glossy, black all around. The faces large and
close to the camera.

**long_man.jpg** (The Long Man, at the edge of your light):
Night, the edge of a flashlight beam in tall dry grass, a figure standing
far too tall and thin, arms hanging down past its knees, long coat or
something like one, no visible face, impossible to tell if it faces toward
or away, the light falling off before it reaches its head, black sky.
Full figure, centered, pale against black.

**crawler.jpg** (The Crawler, low in the grass):
Night, flash photograph close to the ground in flattened grass, a low wide
creature like a man-sized tick or crab made of pale wet human flesh, far
too many jointed legs, a cluster of many small human eyes catching the
flash, mandibles of finger bones, glistening. Three-quarter view, filling
the frame, black behind it.

**rivals.jpg** (optional: the Rival Churners, who borrow the bandits' picture):
Two exclusion-zone scavengers standing side by side, patched gas masks
pushed up on their heads, heavy canvas packs, a woman in front holding a
Tokarev pistol low and casual, both watching the camera warily. Waist up,
plain pale backdrop.

Karl is never generated here: `karl.png` is the user's own picture (2026-10-03).

## After adding a picture

If the picture differs from the game's description (like the Jawhound's eyes
and tendrils), say so and the intro text gets rewritten to match. Crop boxes
and tone settings for each picture live in `PHOTO` in
`tools/paint_portraits.py`.
