# Image prompts for the encounter portraits

Pictures saved here as `art/<name>.jpg` (or `.png`) replace the painted
portrait for that encounter. Then run:

```sh
python3 tools/paint_portraits.py   # converts art/ into the game's 1-bit portraits
python3 tools/build.py             # rebuilds wasteland.lua
```

Done so far: `jawhound.jpg`, `stag.jpg`.

## Shared style (paste after every prompt)

> Photograph of a hyper-detailed practical-effects creature sculpture, full
> body, three-quarter side view, single subject centered, plain seamless white
> studio background, soft shadow under it, wet glossy flesh, strong clear
> silhouette, high contrast lighting, no text, no frame.

For the **people**, use this instead:

> Realistic portrait photograph, head and shoulders to mid-chest, facing the
> camera slightly turned, plain seamless white studio background, hard side
> light, gritty post-apocalyptic wear, sharp focus on the face, no text.

For the **anomalies** (scenes, not creatures):

> Eerie realistic photograph, simple composition with one clear subject, flat
> empty grassland, pale overcast sky, high contrast, no text.

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

## After adding a picture

If the picture differs from the game's description (like the Jawhound's eyes
and tendrils), say so and the intro text gets rewritten to match. Crop boxes
and tone settings for each picture live in `PHOTO` in
`tools/paint_portraits.py`.
