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
ART = ROOT / "art"   # optional art/<subject>.png replaces the painted version
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
        canvas, close_box = fn()
        override = ART / f"{name}.png"
        if override.exists():
            # a supplied picture (drawing, photo, generated image): fit it on
            # white into the 192 master; keep the painted version's close box
            src = Image.open(override).convert("RGBA")
            src.thumbnail((192, 192), Image.LANCZOS)
            bg = Image.new("RGBA", (192, 192), (255, 255, 255, 255))
            bg.alpha_composite(src, ((192 - src.width) // 2, (192 - src.height) // 2))
            canvas = bg.convert("L")
            print("using", override.relative_to(ROOT), "for", name)
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
