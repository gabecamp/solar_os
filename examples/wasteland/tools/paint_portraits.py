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
significant bit = leftmost pixel, 128 bytes per tile) and stored base64.
Also stored: "marks", points on the subject where wounds show when it's hurt.
Previews (grayscale master + the three dithered views) go to
previews/portraits/.
"""
import base64
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


def views(canvas, close_box):
    master = canvas if isinstance(canvas, Image.Image) else canvas.image()
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
}


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


def photo_view(gray, box, size, gamma, edge):
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
    bg = a > 0.86
    t = np.clip((a - 0.08) / (0.80 - 0.08), 0, 1) ** gamma
    e = np.asarray(src.filter(ImageFilter.FIND_EDGES), np.float32) / 255
    t = np.clip(t - edge * e * 2.0, 0, 1)
    t[bg] = 1
    small = Image.fromarray(np.uint8(t * 255)).resize((size, size), Image.LANCZOS)
    bits = np.asarray(small.convert("1"), dtype=bool) == False  # noqa: E712
    return small, bits


def photo_views(path, name):
    gray = Image.open(path).convert("L")
    cfg = PHOTO.get(name, {})
    whole = subject_bbox(gray)
    x0, y0, x1, y1 = whole
    guess_close = (x0, y0, x0 + (x1 - x0) // 2, y0 + (x1 - x0) // 2)
    gamma, edge = cfg.get("gamma", 0.5), cfg.get("edge", 0.5)
    grays, bits = {}, {}
    for v, size, default in (("near", 96, whole), ("far", 48, whole), ("close", 96, guess_close)):
        grays[v], bits[v] = photo_view(gray, cfg.get(v, default), size, gamma, edge)
    master = Image.new("L", (192, 192), 255)
    fit = gray.crop(cfg.get("far", whole))
    fit.thumbnail((192, 192), Image.LANCZOS)
    master.paste(fit, ((192 - fit.width) // 2, (192 - fit.height) // 2))
    return master, bits, grays


def lua_string(data):
    return '"' + base64.b64encode(data).decode() + '"'


def main():
    only = sys.argv[1:]
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    entries = []
    sheet_rows = []
    for name, fn in portraits.SUBJECTS.items():
        if only and name not in only:
            continue
        override = find_art(name)
        if override:
            master, bits, grays = photo_views(override, name)
            print("using", override.relative_to(ROOT), "for", name)
        else:
            canvas, close_box = fn()
            master, bits, grays = views(canvas, close_box)
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
           "-- (96x96 zoom on the face) 1-bit views as base64 32x32 sprite tiles\n"
           "-- (row-major, 128 bytes each, LSB = leftmost pixel), plus marks = x, y\n"
           "-- pairs on the subject where wounds show.\n"
           "local PORTRAIT_DATA = {\n" + "\n".join(entries) + "\n}\n")
    OUT_LUA.write_text(lua)
    print("wrote", OUT_LUA.relative_to(ROOT), f"({len(lua) // 1024} KB) and previews for", len(entries), "subjects")


if __name__ == "__main__":
    main()
