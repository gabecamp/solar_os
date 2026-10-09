#!/usr/bin/env python3
"""Paint the update screen's progress picture - a rotten arm crawling out of
the left edge after a crow - into the GENERATED part src/38_reach_art.lua.

    python3 tools/paint_reach.py      # then: python3 tools/build.py

Drawn here in code (no source image): shapes at 4x on a white canvas, gray
for rotting flesh, then shrunk and ordered-dithered to 1-bit like the
portraits. White is transparent when drawn (bitmaps only set black), so
the arm can slide over the screen. Game.ARM_ART is 384x64 (long enough to reach in from the edge), Game.CROW_ART
64x64, both 32x32 tiles of raw bytes (src/38_update.lua draws them).
Previews: previews/reach_arm.png and previews/reach_crow.png.
"""
import math
import pathlib
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from paint_portraits import dither, pack_tiles  # noqa: E402
from paint_title import lua_bytes  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "38_reach_art.lua"
S = 4                      # drawn at 4x, then shrunk
BLACK, ROT, BRUISE, BONE, WHITE = 0, 90, 150, 235, 255


def ragged(points, rnd, amp):
    """Jitter a polygon's points (torn skin)."""
    return [(x + rnd.uniform(-amp, amp), y + rnd.uniform(-amp, amp)) for x, y in points]


def arm():
    W, H = 384 * S, 64 * S
    img = Image.new("L", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    rnd = random.Random(7)
    L = 298                 # the wrist, in final pixels
    wrist_x, mid = L * S, 36 * S

    # the forearm: thick at the left edge, thin at the wrist, sagging a little
    top, bot = [], []
    for i in range(0, 61):
        t = i / 60
        x = t * wrist_x
        half = (15 - 7 * t * t) * S
        y = mid + math.sin(t * math.pi * 2) * 2.5 * S
        top.append((x, y - half))
        bot.append((x, y + half))
    outline = ragged(top, rnd, 1.2 * S) + ragged(bot[::-1], rnd, 1.6 * S)
    d.polygon(outline, fill=BLACK)
    inner = ragged([(x, y + 2.5 * S) for x, y in top], rnd, 1.0 * S) + \
        ragged([(x, y - 2.5 * S) for x, y in bot[::-1]], rnd, 1.0 * S)
    d.polygon(inner, fill=ROT)
    # bruised, sloughing patches and black rot holes
    for _ in range(22):
        cx, cy = rnd.uniform(4, L - 20) * S, mid + rnd.uniform(-8, 8) * S
        r = rnd.uniform(2, 5) * S
        d.ellipse((cx - r, cy - r * 0.7, cx + r, cy + r * 0.7), fill=BRUISE)
    for _ in range(28):
        cx, cy = rnd.uniform(4, L - 10) * S, mid + rnd.uniform(-9, 9) * S
        r = rnd.uniform(0.8, 2.2) * S
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=BLACK)
    # torn open: the bone shows through, from mid-arm to the wrist
    gx0, gx1 = (L - 100) * S, (L - 20) * S
    d.polygon(ragged([(gx0, mid - 6 * S), (gx1, mid - 4 * S), (gx1 + 6 * S, mid + 1 * S),
                      (gx1, mid + 5 * S), (gx0 + 8 * S, mid + 6 * S), (gx0 - 4 * S, mid)], rnd, 1.5 * S),
              fill=BLACK)
    d.line((gx0 + 2 * S, mid - 1 * S, gx1 + 4 * S, mid), fill=BONE, width=int(3.2 * S))
    for kx in (gx0 + 2 * S, gx1 + 4 * S):   # the knobs at the bone's ends
        d.ellipse((kx - 3 * S, mid - 3.5 * S, kx + 3 * S, mid + 2.5 * S), fill=BONE, outline=BLACK, width=S)
    for _ in range(5):   # sinew strands across the gap
        x = rnd.uniform(gx0 + 8 * S, gx1 - 6 * S)
        d.line((x, mid - 5 * S, x + rnd.uniform(-4, 4) * S, mid + 5 * S), fill=BLACK, width=S)
    # skin hanging off the underside, dripping
    for _ in range(14):
        x = rnd.uniform(10, L - 10) * S
        y0 = bot[min(60, int(x / wrist_x * 60))][1] - S
        ln = rnd.uniform(4, 11) * S
        d.line((x, y0, x + rnd.uniform(-2, 2) * S, y0 + ln), fill=BLACK, width=int(1.4 * S))
        d.ellipse((x - 1.2 * S, y0 + ln - S, x + 1.6 * S, y0 + ln + 1.8 * S), fill=BLACK)

    # the hand: a broad palm, a thumb hooked up, four long fingers curling
    # to grab, each with swollen knuckles and a cracked claw
    px, py = wrist_x + 16 * S, mid
    d.polygon(ragged([(wrist_x - 4 * S, py - 8 * S), (px + 4 * S, py - 11 * S), (px + 8 * S, py - 2 * S),
                      (px + 5 * S, py + 10 * S), (wrist_x - 4 * S, py + 8 * S)], rnd, 0.8 * S), fill=BLACK)
    d.ellipse((wrist_x + 2 * S, py - 5 * S, px + 1 * S, py + 5 * S), fill=ROT)
    fingers = ((px - 6 * S, py - 9 * S, -62, 22, 10),          # the thumb
               (px + 5 * S, py - 8 * S, -22, 34, 9), (px + 7 * S, py - 2 * S, -6, 40, 9),
               (px + 6 * S, py + 4 * S, 9, 38, 10), (px + 3 * S, py + 9 * S, 24, 30, 12))
    for x, y, ang, length, curl in fingers:
        a = math.radians(ang)
        joints = [(x, y)]
        seg = length / 3
        for k in range(3):
            a += math.radians(curl)
            x, y = x + math.cos(a) * seg * S, y + math.sin(a) * seg * S
            joints.append((x, y))
        for k, ((x0, y0), (x1, y1)) in enumerate(zip(joints, joints[1:])):
            d.line((x0, y0, x1, y1), fill=BLACK, width=int((4.6 - 0.8 * k) * S))
        for jx, jy in joints[1:-1]:
            d.ellipse((jx - 2.8 * S, jy - 2.8 * S, jx + 2.8 * S, jy + 2.8 * S), fill=BLACK)
            d.ellipse((jx - 0.9 * S, jy - 0.9 * S, jx + 0.9 * S, jy + 0.9 * S), fill=BONE)
        (x0, y0), (x1, y1) = joints[-2], joints[-1]
        ux, uy = x1 - x0, y1 - y0
        n = math.hypot(ux, uy)
        ux, uy = ux / n, uy / n
        a2 = math.atan2(uy, ux) + math.radians(30)   # the claw hooks down
        tip = (x1 + math.cos(a2) * 7 * S, y1 + math.sin(a2) * 7 * S)
        d.polygon([(x1 - uy * 2 * S, y1 + ux * 2 * S), (x1 + uy * 2 * S, y1 - ux * 2 * S), tip], fill=BLACK)
    # flies
    for _ in range(9):
        fx, fy = rnd.uniform(20, L - 10) * S, rnd.uniform(3, 14) * S
        d.ellipse((fx - S, fy - S * 0.7, fx + S, fy + S * 0.7), fill=BLACK)
        d.line((fx - 2 * S, fy - 1.5 * S, fx, fy), fill=BLACK, width=max(1, S // 2))
    return img


def crow():
    W = H = 64 * S
    img = Image.new("L", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    rnd = random.Random(3)
    # the body, leaning forward (it faces left, toward the hand)
    d.ellipse((14 * S, 22 * S, 50 * S, 46 * S), fill=BLACK)
    d.polygon(ragged([(44 * S, 30 * S), (62 * S, 44 * S), (60 * S, 48 * S), (40 * S, 42 * S)], rnd, S),
              fill=BLACK)                                         # the tail
    d.ellipse((8 * S, 12 * S, 26 * S, 30 * S), fill=BLACK)         # the head
    for i in range(7):                                             # hackles, ruffled
        a = math.radians(200 + i * 22)
        cx, cy = 18 * S + math.cos(a) * 9 * S, 21 * S + math.sin(a) * 9 * S
        d.polygon([(cx, cy), (cx + math.cos(a) * 4 * S - 2 * S, cy + math.sin(a) * 4 * S),
                   (cx + 2 * S, cy + S)], fill=BLACK)
    d.polygon([(10 * S, 18 * S), (-1 * S, 23 * S), (11 * S, 25 * S)], fill=BLACK)   # the beak, open
    d.line((1 * S, 23 * S, 10 * S, 22 * S), fill=WHITE, width=S)
    d.ellipse((13 * S, 16 * S, 18 * S, 21 * S), fill=WHITE)        # the eye, watching
    d.ellipse((14 * S, 17 * S, 16.5 * S, 19.5 * S), fill=BLACK)
    # the wing: ragged feathers, a few pale edges
    feathers = [(20 * S, 26 * S)]
    for i in range(8):
        x = 24 * S + i * 3.6 * S
        feathers += [(x, 40 * S + rnd.uniform(0, 3) * S), (x + 1.8 * S, 36 * S)]
    feathers += [(54 * S, 34 * S), (40 * S, 25 * S)]
    d.polygon(feathers, fill=BLACK)
    for i in range(4):
        x = 27 * S + i * 6 * S
        d.line((x, 30 * S, x + 5 * S, 38 * S), fill=BRUISE, width=S)
    # legs and claws on the ground
    for lx in (26 * S, 33 * S):
        d.line((lx, 44 * S, lx - 2 * S, 58 * S), fill=BLACK, width=int(1.6 * S))
        for dx in (-5, -1, 3):
            d.line((lx - 2 * S, 58 * S, lx - 2 * S + dx * S, 61 * S), fill=BLACK, width=S)
    return img


def bake(img, name, w, h):
    small = img.resize((w, h), Image.LANCZOS)
    bits = dither(small, lo=0.08, hi=0.96, gamma=0.9)
    Image.fromarray(np.uint8(~bits) * 255, "L").resize((w * 3, h * 3), Image.NEAREST) \
        .save(ROOT / "previews" / ("reach_%s.png" % name))
    data, tw, th = pack_tiles(bits)
    print("%s: %d bytes, %d%% ink" % (name, len(data), int(bits.mean() * 100)))
    return lua_bytes(data), tw, th


def main():
    lines = ["-- GENERATED by tools/paint_reach.py - do not edit. The update screen's",
             "-- progress picture: an arm (384x64) reaching for a crow (64x64), 1-bit,",
             "-- tiles of 32x32 (128 bytes each, row-major, LSB = leftmost pixel)."]
    for field, name, img, w, h in (("ARM_ART", "arm", arm(), 384, 64), ("CROW_ART", "crow", crow(), 64, 64)):
        lit, tw, th = bake(img, name, w, h)
        lines += ["Game.%s = {w = %d, h = %d, tw = %d, th = %d," % (field, w, h, tw, th),
                  "    data = %s}" % lit]
    OUT.write_text("\n".join(lines) + "\n")
    print("wrote", OUT.name)


if __name__ == "__main__":
    main()
