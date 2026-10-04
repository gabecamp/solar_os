#!/usr/bin/env python3
"""Paint the encounter portraits and bake them into src/81_portrait_data.lua.

    python3 tools/paint_portraits.py            # paint, dither, write the Lua part + previews
    python3 tools/paint_portraits.py jawhound   # just one subject (previews only)

For each subject in portraits.SUBJECTS this makes three 1-bit views:
  near  - the whole painting at 96x96
  far   - the whole painting at 48x48 (seen from across the field)
  close - the subject's "close" box zoomed to 96x96 (its head/face)
dithered with Floyd-Steinberg (black dots = drawn pixels). Each view is cut
into 32x32 tiles packed like gfx.sprite wants (rows of 4 bytes, least
significant bit = leftmost pixel, 128 bytes per tile) and stored as raw bytes.
Also stored: "marks", points on the subject where wounds show when it's hurt.
Previews (grayscale master + the three dithered views) go to
previews/portraits/.
"""
import pathlib
import random
import zlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import portraits  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
# sorts before 66_portraits.lua (which reads PORTRAIT_DATA) and before the
# encounter screen in 70_draw_screens.lua (which draws them)
OUT_LUA = ROOT / "src" / "65_portrait_data.lua"
ART = ROOT / "art"   # optional art/<subject>.png|jpg replaces the painted version
PREVIEWS = ROOT / "previews" / "portraits"
TILE = 32


def tone_curve(img, gamma=1.0, lo=0.0, hi=1.0):
    a = np.asarray(img, np.float32) / 255.0
    a = np.clip((a - lo) / (hi - lo), 0, 1) ** gamma
    return Image.fromarray(np.uint8(a * 255), "L")


BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 + 1 / 32


def dither(gray, lo=0.15, hi=0.85, gamma=0.8):
    """Contrast-stretch, then ordered (Bayer 4x4) dither to 1-bit. Returns a
    bool array, True = black (drawn). At 96 px, ordered dither gives clean
    regular tones (like the firmware's own LIGHT/DARK) where error diffusion
    turned faces and fur into noise."""
    a = np.asarray(gray, np.float32) / 255.0
    a = np.clip((a - lo) / (hi - lo), 0, 1) ** gamma
    h, w = a.shape
    t = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    return a <= t


def views(canvas, close_box, near_box=None):
    """near_box (x, y, size): a tighter crop for the near view (people: head
    and shoulders, so a face gets more than a quarter of the frame)."""
    master = canvas if isinstance(canvas, Image.Image) else canvas.image()
    if near_box:
        nx, ny, ns = near_box
        near = master.crop((nx, ny, nx + ns, ny + ns)).resize((96, 96), Image.LANCZOS)
    else:
        near = master.resize((96, 96), Image.LANCZOS)
    far = tone_curve(master.resize((48, 48), Image.LANCZOS), gamma=1.15)
    x, y, s = close_box
    close = master.crop((x, y, x + s, y + s)).resize((96, 96), Image.LANCZOS)
    return master, {"near": dither(near), "far": dither(far), "close": dither(close)}, \
        {"near": near, "far": far, "close": close}


def pack_tiles(bits):
    """bool HxW (multiples of... padded to 32) -> bytes of 32x32 tiles, row-major tiles."""
    h, w = bits.shape
    th, tw = -(-h // TILE), -(-w // TILE)
    pad = np.zeros((th * TILE, tw * TILE), bool)
    pad[:h, :w] = bits
    out = bytearray()
    for ty in range(th):
        for tx in range(tw):
            tile = pad[ty * TILE:(ty + 1) * TILE, tx * TILE:(tx + 1) * TILE]
            for row in tile:
                for b in range(TILE // 8):
                    v = 0
                    for bit in range(8):
                        if row[b * 8 + bit]:
                            v |= 1 << bit
                    out.append(v)
    return bytes(out), tw, th


def wound_marks(bits, seed, n=14):
    """Points on the subject (black-ish areas) where wounds appear, most
    telling first; spread out so each new mark lands somewhere new."""
    h, w = bits.shape
    ys, xs = np.nonzero(bits)
    rng = random.Random(seed)
    cand = list(zip(xs.tolist(), ys.tolist()))
    rng.shuffle(cand)
    # prefer the middle of the figure (vertically central band)
    cand.sort(key=lambda p: abs(p[1] - h * 0.55) + rng.random() * h * 0.3)
    picked = []
    for x, y in cand:
        if 3 <= x < w - 4 and 3 <= y < h - 4 and all(abs(x - a) + abs(y - b) > w // 8 for a, b in picked):
            picked.append((x, y))
        if len(picked) == n:
            break
    return picked


# Supplied pictures (art/<subject>.jpg|.png) - photos, renders, drawings.
# Boxes are in the source image's pixels: far = the whole creature, near =
# head and front (a portrait crop, bigger in the frame), close = the face.
# gamma < 1 lifts the mid-tones so a dark subject doesn't dither to a black
# mass; edge darkens outlines so it keeps its shape. Anything left out is
# guessed from the subject's bounding box.
PHOTO = {
    "jawhound": {"far": (200, 30, 1235, 740), "near": (190, 190, 870, 750),
                 "close": (270, 260, 600, 590), "gamma": 0.42, "edge": 0.5},
    # a pale subject: no mid-tone lift (gamma 1), stronger edges; close is
    # the head with its hand-antlers (the face alone blurs at 96 px)
    "stag": {"far": (285, 25, 1215, 735), "near": (560, 20, 1230, 740),
             "close": (860, 10, 1230, 480), "gamma": 1.0, "edge": 0.8},
    # generated with Z-Image Turbo (Hugging Face) from art/PROMPTS.md; their
    # backgrounds are light gray, not white, hence bg 0.78 where it shows
    "boar": {"far": (60, 150, 960, 960), "near": (480, 150, 960, 720),
             "close": (560, 230, 960, 630), "gamma": 0.85, "edge": 0.7},
    "crows": {"far": (130, 50, 920, 990), "near": (140, 50, 910, 700),
              "close": (300, 180, 760, 620), "gamma": 0.35, "edge": 0.7},
    # the user's own picture (2026-10-03, 768x768): the pair on a pale gray
    # backdrop in a worn print border (kept out of every crop); close = both faces
    "fused": {"far": (48, 52, 736, 740), "near": (90, 52, 690, 652),
              "close": (150, 60, 610, 520), "gamma": 0.75, "edge": 0.6, "bg": 0.80},
    "bloom": {"far": (0, 40, 1024, 1024), "near": (220, 40, 880, 760),
              "close": (320, 60, 780, 640), "gamma": 1.4, "edge": 0.8},
    # 2026-10-01, seeds 2101/2103/2106/2108/2109 (boar, crows, bloom, tollman,
    # medic): white backgrounds, so the default bg level
    "tollman": {"far": (40, 60, 1000, 1024), "near": (150, 60, 900, 810),
                "close": (380, 80, 760, 560), "gamma": 0.6, "edge": 0.6},
    "medic": {"far": (0, 60, 1024, 1024), "near": (120, 60, 960, 900),
              "close": (360, 80, 720, 580), "gamma": 1.3, "edge": 0.8},
    "bandits": {"far": (0, 95, 1024, 1024), "near": (220, 80, 860, 760),
                "close": (440, 90, 740, 390), "gamma": 0.5, "edge": 0.5, "bg": 0.78},
    # 2026-10-02, seeds 2110/2111 (wanderer, mouthless) and the anomalies
    # 2112/2113/2115/2116/2118 (hollow, bell, stars, stillness, door). Helpers
    # and anomalies only show "near". Scenes have grass and sky, not a white
    # backdrop: `levels` narrows the tone range so the grass pattern (the
    # hollow's spiral) survives the dither.
    "wanderer": {"far": (100, 40, 920, 1024), "near": (120, 40, 900, 820),
                 "close": (380, 60, 680, 360), "gamma": 1.0, "edge": 0.6},
    "mouthless": {"far": (0, 40, 1024, 1024), "near": (200, 40, 820, 760),
                  "close": (330, 170, 700, 560), "gamma": 1.0, "edge": 0.6},
    "hollow": {"near": (170, 470, 850, 800), "gamma": 0.8, "edge": 0.4,
               "levels": (0.30, 0.75), "bg": 0.95},
    "bell": {"near": (120, 200, 960, 900), "gamma": 1.0, "edge": 0.6},
    "stars": {"near": (140, 160, 880, 740), "gamma": 1.0, "edge": 0.6},
    "stillness": {"near": (260, 170, 800, 800), "gamma": 0.8, "edge": 0.9,
                  "levels": (0.20, 0.75), "bg": 0.90},
    "door": {"near": (240, 100, 780, 960), "gamma": 0.8, "edge": 0.8,
             "levels": (0.05, 0.70)},
    # the user's own picture (2026-10-02): a pale child on a mid-gray backdrop
    # (~0.75), so a low bg cutoff; her face is nearly as pale, the eyes carry it
    "little": {"far": (0, 20, 512, 768), "near": (60, 30, 470, 500),
               "close": (150, 90, 400, 340), "gamma": 1.0, "edge": 0.9,
               "levels": (0.15, 0.70), "bg": 0.72},
    # the user's own picture (2026-10-03, 512x768, from the PROMPTS prompt):
    # the chained steel door in the quarry wall with its bulb and card slot; a
    # painting in browns and grays, so levels spread it; square crops
    "institute": {"far": (0, 60, 512, 572), "near": (10, 100, 502, 592),
                  "close": (70, 180, 430, 540), "gamma": 1.0, "edge": 0.6, "rust": 2.0,
                  "levels": (0.11, 0.26), "bg": 0.99},
    # the user's own picture (2026-10-03, 768x768): a dark many-legged thing
    # hung with root-like strands, two glowing eyes, on a pale ground
    "crawler": {"far": (36, 30, 740, 734), "near": (70, 10, 710, 650),
                "close": (270, 40, 490, 260), "gamma": 0.7, "edge": 0.5, "bg": 0.80},
    # Karl: the user's own picture (2026-10-03, 1024x1536, never generated):
    # bucket hat with lures, waders, rod, a string of many-eyed fish, a river
    # at dusk behind; square crops on the man, the scene kept pale behind him
    "karl": {"far": (60, 40, 1000, 980), "near": (260, 50, 740, 530),
             "close": (340, 90, 610, 360), "gamma": 0.9, "edge": 0.9,
             "levels": (0.14, 0.68), "bg": 0.99},
    # the user's own picture (2026-10-03, 512x768): the Rival Churners, two
    # in full gas masks with packs and guns, on a pale print
    "rivals": {"far": (0, 60, 512, 572), "near": (16, 36, 496, 516),
               "close": (90, 40, 490, 440), "gamma": 1.0, "edge": 0.8,
               "levels": (0.18, 0.72), "bg": 0.82},
    # the user's own picture (2026-10-03, 768x768): a gaunt, bowed figure in a
    # pale shaft of light, the print's edges burnt orange: a negative rust
    # turns the orange white so the burns don't dither into black blotches
    "long_man": {"far": (75, 70, 735, 730), "near": (180, 50, 580, 450),
                 "close": (240, 70, 420, 250), "gamma": 1.0, "edge": 0.6,
                 "rust": -1.5, "bg": 0.80},
    # the user's own picture (2026-10-03, 512x768): three pale faces looking
    # up out of black water under reeds. Pale on black, the reverse of the
    # rest: bg off (it would wipe the faces); close = the nearest face
    "whisper": {"far": (0, 200, 512, 712), "near": (78, 300, 498, 720),
                "close": (90, 530, 290, 730), "gamma": 1.4, "edge": 0.6,
                "levels": (0.14, 0.95), "bg": 1.01},
    # the user's own picture (2026-10-03, 512x768): the stray in dry scrub,
    # inside a yellowed print border; a scene, not a backdrop, so levels keep
    # the scrub and a dark dog gets its mid-tones lifted
    "stray": {"far": (24, 150, 488, 744), "near": (60, 200, 470, 640),
              "close": (170, 220, 430, 500), "gamma": 1.0, "edge": 0.7,
              "levels": (0.12, 0.60), "bg": 0.70},
    # the user's (2026-10-04, 1216x912): Vesna dead in a school corridor, gas
    # mask on, picks by her hand, a door at the end. near = her and the
    # corridor (the scene shows near); close = the mask and her chest
    "vesna": {"far": (0, 0, 1216, 912), "near": (100, 1, 1010, 911),
              "close": (100, 400, 560, 800), "gamma": 0.9, "edge": 0.7,
              "levels": (0.06, 0.34), "bg": 0.95, "rust": -1.5},   # (dark: narrow levels; her khaki lifted off the floor)
}


# Story moments (src/67_scenes.lua, draw_ending): no painted fallback, so
# each is baked only when art/<name>.png|jpg exists.
PHOTO_ONLY = ("vesna", "ending_permit", "ending_bribe", "ending_quiet")


def find_art(name):
    for ext in ("png", "jpg", "jpeg"):
        path = ART / f"{name}.{ext}"
        if path.exists():
            return path
    return None


def subject_bbox(gray, bg=0.86):
    a = np.asarray(gray, np.float32) / 255
    ys, xs = np.nonzero(a < bg)
    if len(xs) == 0:
        return (0, 0, gray.width, gray.height)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def photo_view(gray, box, size, gamma, edge, bg_level=0.86, levels=(0.08, 0.80)):
    """One view of a supplied picture: square crop on white, smoothed (a
    median filter flattens fine texture that would dither into noise),
    levels + gamma, dark edges, background forced white, then Floyd-Steinberg
    (error diffusion keeps a photo's detail better than ordered dither)."""
    from PIL import ImageFilter
    x0, y0, x1, y1 = box
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sq = Image.new("L", (side, side), 255)
    sq.paste(gray, (-(cx - side // 2), -(cy - side // 2)))
    src = sq.resize((size * 3, size * 3), Image.LANCZOS).filter(ImageFilter.MedianFilter(5))
    a = np.asarray(src, np.float32) / 255
    bg = a > bg_level   # anything this light counts as background (forced white)
    lo, hi = levels   # the tone range stretched to black..white (scenes: narrower)
    t = np.clip((a - lo) / (hi - lo), 0, 1) ** gamma
    e = np.asarray(src.filter(ImageFilter.FIND_EDGES), np.float32) / 255
    t = np.clip(t - edge * e * 2.0, 0, 1)
    t[bg] = 1
    small = Image.fromarray(np.uint8(t * 255)).resize((size, size), Image.LANCZOS)
    bits = np.asarray(small.convert("1"), dtype=bool) == False  # noqa: E712
    return small, bits


def rust_gray(img, k):
    """Grayscale where rust (red over blue) reads darker by k per level of
    red-minus-blue: for pictures whose subject and ground are the same
    brightness but not the same colour (the Institute's door on its rock).
    A negative k lightens it instead (the Long Man's burnt orange edges)."""
    r, _, b = img.convert("RGB").split()
    gray = np.asarray(img.convert("L"), dtype=np.float32)
    rust = np.clip(np.asarray(r, dtype=np.float32) - np.asarray(b, dtype=np.float32), 0, 255)
    return Image.fromarray(np.clip(gray - k * rust, 0, 255).astype(np.uint8))


def photo_views(path, name):
    cfg = PHOTO.get(name, {})
    gray = Image.open(path).convert("L")
    if cfg.get("rust"):
        gray = rust_gray(Image.open(path), cfg["rust"])
    whole = subject_bbox(gray)
    x0, y0, x1, y1 = whole
    guess_close = (x0, y0, x0 + (x1 - x0) // 2, y0 + (x1 - x0) // 2)
    gamma, edge = cfg.get("gamma", 0.5), cfg.get("edge", 0.5)
    grays, bits = {}, {}
    for v, size, default in (("near", 96, whole), ("far", 48, whole), ("close", 96, guess_close)):
        grays[v], bits[v] = photo_view(gray, cfg.get(v, default), size, gamma, edge,
                                       cfg.get("bg", 0.86), cfg.get("levels", (0.08, 0.80)))
    master = Image.new("L", (192, 192), 255)
    fit = gray.crop(cfg.get("far", whole))
    fit.thumbnail((192, 192), Image.LANCZOS)
    master.paste(fit, ((192 - fit.width) // 2, (192 - fit.height) // 2))
    return master, bits, grays


def lua_string(data):
    """A Lua string literal holding these raw bytes (printable ASCII as is,
    the rest as \\ddd): a quarter smaller in memory than base64, and no
    decoding at run time."""
    out = []
    for b in data:
        if 32 <= b < 127 and b not in (34, 92):
            out.append(chr(b))
        else:
            out.append("\\%03d" % b)
    return '"' + "".join(out) + '"'


def main():
    only = sys.argv[1:]
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    entries = []
    sheet_rows = []
    subjects = dict(portraits.SUBJECTS)
    for name in PHOTO_ONLY:   # (story pictures: in the game only once the user supplies them)
        if find_art(name):
            subjects[name] = None
    for name, fn in subjects.items():
        if only and name not in only:
            continue
        override = find_art(name)
        if override:
            master, bits, grays = photo_views(override, name)
            print("using", override.relative_to(ROOT), "for", name)
        else:
            painted = fn()
            master, bits, grays = views(*painted)
        master.save(PREVIEWS / f"{name}_master.png")
        row = Image.new("L", (192 + 96 * 2 + 48 + 40, 192), 255)
        row.paste(master, (0, 0))
        for i, v in enumerate(("near", "close")):
            img = Image.fromarray(np.uint8(~bits[v]) * 255, "L")
            img.save(PREVIEWS / f"{name}_{v}.png")
            row.paste(img, (200 + i * 104, 0))
        far = Image.fromarray(np.uint8(~bits["far"]) * 255, "L")
        far.save(PREVIEWS / f"{name}_far.png")
        row.paste(far, (200 + 2 * 104, 48))
        sheet_rows.append(row)
        fields = []
        for v in ("near", "far", "close"):
            data, tw, th = pack_tiles(bits[v])
            marks = wound_marks(bits[v], zlib.crc32((name + v).encode()))
            flat = ", ".join(f"{x}, {y}" for x, y in marks)
            fields.append(f"        {v} = {{w = {bits[v].shape[1]}, h = {bits[v].shape[0]}, "
                          f"tw = {tw}, th = {th},\n            marks = {{{flat}}},\n"
                          f"            data = {lua_string(data)}}},")
        entries.append(f"    {name} = {{\n" + "\n".join(fields) + "\n    },")
    if sheet_rows:
        sheet = Image.new("L", (sheet_rows[0].width, 200 * len(sheet_rows)), 255)
        for i, r in enumerate(sheet_rows):
            sheet.paste(r, (0, i * 200))
        sheet.save(PREVIEWS / "contact_sheet.png")
    if only:
        print("previews only (subset):", ", ".join(only))
        return
    lua = ("-- GENERATED by tools/paint_portraits.py - do not edit; repaint instead.\n"
           "-- Encounter portraits: per subject, near (96x96), far (48x48) and close\n"
           "-- (96x96 zoom on the face) 1-bit views as raw-byte 32x32 sprite tiles\n"
           "-- (row-major, 128 bytes each, LSB = leftmost pixel), plus marks = x, y\n"
           "-- pairs on the subject where wounds show.\n"
           "local PORTRAIT_DATA = {\n" + "\n".join(entries) + "\n}\n")
    OUT_LUA.write_text(lua)
    print("wrote", OUT_LUA.relative_to(ROOT), f"({len(lua) // 1024} KB) and previews for", len(entries), "subjects")


if __name__ == "__main__":
    main()
