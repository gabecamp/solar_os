"""The 16 encounter portraits, painted with paint_lib (see paint_portraits.py).

Each function paints one subject onto a fresh 192x192 Canvas and returns it
with the box (x, y, size) that the "close" view zooms into (usually the head).
Coordinates are in the 192 master; light comes from the upper left. Tones are
kept light with strong shading on purpose: the screen is 1-bit, so a form
reads by its lit side going white and its shadow side going black.
"""
import math

from paint_lib import (Canvas, blur, ellipse, poly, stroke, tapered, union, cut,
                       SIZE)
import numpy as np


# -- shared parts ------------------------------------------------------------

def leg(c, hip, knee, hock, paw, tone, seed, w=(14, 10, 7), fur=True):
    """A jointed animal leg: thigh, shin, cannon, paw."""
    m = union(tapered([hip, knee], w[0], w[1]), tapered([knee, hock], w[1], w[2]),
              tapered([hock, paw], w[2], w[2] - 1))
    c.body(m, tone, soft=4, seed=seed)
    if fur:
        c.hatch(m, 95, 0.4, 3.2, 5, seed=seed + 50)
    c.body(ellipse(paw[0] - 2, paw[1] + 1, w[2] * 0.8, w[2] * 0.45), tone * 0.5, soft=2, seed=seed + 1)


def eye(c, x, y, rx=3.5, ry=2.8, white=True, look=(0, 0)):
    """Eye: white, dark iris, a catchlight, and a dark upper lid line."""
    if white:
        c.flat(ellipse(x, y, rx * 1.15, ry * 1.1), 1.0)
    c.flat(ellipse(x + look[0], y + look[1], rx * 0.6, rx * 0.6), 0.0)
    c.flat(ellipse(x + look[0] - rx * 0.25, y + look[1] - ry * 0.3, 0.9, 0.9), 1.0)
    if white:
        c.darken(stroke([(x - rx * 1.2, y - ry * 0.6), (x, y - ry * 1.15), (x + rx * 1.2, y - ry * 0.6)], 1.3, False), 0.9)


def human_head(c, cx, cy, s=1.0, tone=0.93, seed=1, jaw=1.0, hair="short",
               hair_tone=0.22, mouth=True, brows=True):
    """Face-on head: skull, jaw, ears, cheekbones, nose, brows, lips and hair.
    Returns the eye line y. hair: short, long, bun, hood, bald."""
    if hair == "long":   # hair behind the head falls to the shoulders
        back = poly([(cx - 26 * s, cy - 10 * s), (cx + 26 * s, cy - 10 * s),
                     (cx + 30 * s, cy + 44 * s), (cx - 30 * s, cy + 44 * s)])
        c.body(back, hair_tone, soft=5, seed=seed + 9)
        c.hatch(back, 90, 0.35, 3, 8, seed=seed + 10, light=True)
    head = union(ellipse(cx, cy, 21 * s, 26 * s),
                 ellipse(cx, cy + 12 * s, 16.5 * s * jaw, 17 * s))
    ears = union(ellipse(cx - 21 * s, cy + 3 * s, 4 * s, 7 * s), ellipse(cx + 21 * s, cy + 3 * s, 4 * s, 7 * s))
    c.body(ears, tone * 0.92, soft=2, seed=seed)
    # skin: gentler light than cloth/fur so a face stays pale in 1-bit
    c.body(head, tone, soft=9 * s, seed=seed + 1, ambient=0.3, gain=1.2, contrast=1.1)
    ey = cy - 1 * s
    # sockets, cheekbones, the hollow under them
    for sgn in (-1, 1):
        c.darken(blur(ellipse(cx + sgn * 9 * s, ey, 7.5 * s, 4.5 * s), 2.2 * s), 0.35)
        c.lighten(blur(ellipse(cx + sgn * 12 * s, ey + 9 * s, 5 * s, 3 * s), 2 * s), 0.35)
        c.darken(blur(ellipse(cx + sgn * 13 * s, ey + 17 * s, 4 * s, 6 * s), 3 * s), 0.18)
    # nose: bridge highlight, shadowed side, nostrils
    c.lighten(blur(stroke([(cx - 1 * s, ey + 2 * s), (cx - 1 * s, ey + 11 * s)], 2 * s), 1), 0.4)
    c.darken(blur(poly([(cx + 1 * s, ey + 2 * s), (cx + 5 * s, ey + 14 * s), (cx + 1 * s, ey + 14 * s)]), 1.2 * s), 0.35)
    c.darken(blur(ellipse(cx - 3 * s, ey + 15 * s, 1.8 * s, 1.1 * s), 0.6), 0.7)
    c.darken(blur(ellipse(cx + 3 * s, ey + 15 * s, 1.8 * s, 1.1 * s), 0.6), 0.7)
    if mouth:
        c.darken(blur(stroke([(cx - 7 * s, ey + 22 * s), (cx, ey + 23 * s), (cx + 7 * s, ey + 22 * s)], 1.4 * s), 0.6), 0.75)
        c.darken(blur(ellipse(cx, ey + 26 * s, 5 * s, 1.5 * s), 1), 0.25)   # under the lower lip
    if brows:
        for sgn in (-1, 1):
            c.darken(blur(stroke([(cx + sgn * 4 * s, ey - 6 * s), (cx + sgn * 14 * s, ey - 8 * s)], 2.4 * s), 0.5), 0.9)
    top = cy - 26 * s
    if hair in ("short", "long", "bun"):
        cap = cut(ellipse(cx, cy - 8 * s, 23 * s, 21 * s), ellipse(cx, cy + 4 * s, 20 * s, 21 * s))
        sides = union(poly([(cx - 22 * s, cy - 10 * s), (cx - 16 * s, cy - 10 * s), (cx - 19 * s, cy + 4 * s),
                            (cx - 23 * s, cy + 2 * s)]),
                      poly([(cx + 22 * s, cy - 10 * s), (cx + 16 * s, cy - 10 * s), (cx + 19 * s, cy + 4 * s),
                            (cx + 23 * s, cy + 2 * s)]))
        hmask = union(cap, sides)
        c.body(hmask, hair_tone, soft=4, spec=0.25, seed=seed + 11)
        c.hatch(hmask, 75, 0.45 if hair_tone < 0.5 else 0.3, 2.6, 6 * s, seed=seed + 12,
                light=hair_tone < 0.5)
        if hair == "bun":
            b = ellipse(cx, top - 4 * s, 11 * s, 9 * s)
            c.body(b, hair_tone, soft=4, seed=seed + 13)
            c.hatch(b, 20, 0.3, 2.6, 5 * s, seed=seed + 14, light=hair_tone < 0.5)
    return ey


def human_body(c, cx, top, w, tone, seed, bottom=SIZE, tex=0.0):
    """Shoulders and chest, cropped by the frame bottom: the trapezius slopes
    down from the neck to rounded deltoids, so the neck reads short."""
    torso = union(
        poly([(cx - w, bottom), (cx - w, top + 26), (cx - w + 6, top + 13), (cx - 15, top + 3),
              (cx - 8, top), (cx + 8, top), (cx + 15, top + 3), (cx + w - 6, top + 13),
              (cx + w, top + 26), (cx + w, bottom)]),
        ellipse(cx - w + 9, top + 22, 11, 13), ellipse(cx + w - 9, top + 22, 11, 13))
    c.body(torso, tone, soft=12, tex=tex, tex_scale=8, grit=0.05, seed=seed)
    # where the arms meet the chest
    for sgn in (-1, 1):
        c.darken(blur(stroke([(cx + sgn * (w - 18), top + 30), (cx + sgn * (w - 16), top + 60)], 2), 2), 0.3)
    return torso


# -- animals -------------------------------------------------------------------

def jawhound():
    """Fallback only: art/jawhound.jpg (the user's picture) replaces this."""
    c = Canvas()
    c.ground_shadow(104, 172, 72, 8)
    fur = 0.62
    leg(c, (136, 112), (140, 136), (134, 152), (136, 168), fur * 0.7, 30)
    leg(c, (76, 112), (70, 134), (74, 152), (70, 168), fur * 0.7, 31)
    body = poly([(60, 96), (80, 84), (120, 82), (150, 86), (166, 96), (166, 112),
                 (150, 122), (126, 118), (104, 116), (86, 124), (66, 120), (56, 108)])
    c.body(body, fur, soft=12, seed=32)
    c.hatch(body, 170, 0.5, 3.2, 6, seed=132)
    for i in range(5):                      # starved: ribs show
        x = 90 + i * 8
        c.darken(blur(stroke([(x, 94), (x + 4, 114)], 2), 1.2), 0.35)
    c.body(tapered([(164, 96), (178, 80), (182, 62)], 8, 3), fur, soft=3, grit=0.1, seed=33)
    leg(c, (150, 110), (156, 136), (150, 152), (152, 170), fur, 34)
    leg(c, (86, 114), (82, 138), (86, 154), (84, 170), fur, 35)
    # neck + head, held low
    neck = tapered([(74, 96), (54, 84), (42, 78)], 28, 22)
    c.body(neck, fur, soft=8, seed=36)
    c.hatch(neck, 150, 0.5, 3.2, 6, seed=136)
    skull = union(ellipse(40, 72, 17, 14, -8), poly([(28, 64), (6, 72), (8, 80), (30, 82)]))
    c.body(skull, fur, soft=6, grit=0.08, seed=37)
    c.body(union(poly([(44, 60), (56, 40), (56, 64)]), poly([(34, 60), (38, 42), (46, 58)])),
           fur * 0.8, soft=3, seed=38)
    c.flat(ellipse(8, 74, 3.5, 3), 0.05)   # nose
    # three lower jaws, wet and dark inside, each lined with teeth
    c.darken(blur(ellipse(26, 90, 12, 10), 3), 0.8)
    for tip, root, w in (((4, 90), (28, 84), 8), ((10, 110), (30, 90), 9), ((30, 118), (36, 92), 8)):
        c.body(tapered([root, tip], w, 4), 0.55, soft=3, spec=0.8, shine=12, seed=39)
        for k in range(1, 6):
            t = k / 6
            x = root[0] + (tip[0] - root[0]) * t
            y = root[1] + (tip[1] - root[1]) * t
            c.flat(poly([(x - 1.6, y - 1.5), (x + 1.6, y - 1.5), (x, y - 5)]), 1.0)
    eye(c, 36, 68, 4, 3, white=False)
    c.outline(0.9)
    return c, (0, 30, 96)


def boar():
    """A boar with no hide: bare wet muscle, tusks, tiny eyes."""
    c = Canvas()
    c.ground_shadow(96, 170, 76, 9)
    meat = 0.55
    leg(c, (132, 124), (138, 144), (134, 158), (136, 170), meat * 0.7, 40, w=(20, 14, 9), fur=False)
    leg(c, (66, 124), (60, 144), (64, 158), (60, 170), meat * 0.7, 41, w=(20, 14, 9), fur=False)
    body = union(ellipse(108, 104, 64, 36, -4), ellipse(62, 102, 34, 36))
    c.body(body, meat, soft=14, spec=0.9, shine=10, grit=0.05, seed=42)
    # muscle bands: dark seams with a wet highlight beside each
    for x0, y0, x1, y1 in ((60, 74, 86, 136), (86, 70, 104, 138), (112, 72, 124, 138),
                           (138, 76, 146, 134), (150, 84, 164, 126)):
        c.darken(blur(stroke([(x0, y0), ((x0 + x1) / 2 + 6, (y0 + y1) / 2), (x1, y1)], 2.2), 1.3), 0.6)
        c.lighten(blur(stroke([(x0 + 4, y0 + 4), ((x0 + x1) / 2 + 10, (y0 + y1) / 2), (x1 + 4, y1 - 4)], 1.2), 1), 0.5)
    leg(c, (146, 126), (152, 148), (146, 160), (150, 172), meat, 43, w=(20, 14, 9), fur=False)
    leg(c, (80, 128), (74, 148), (78, 160), (74, 172), meat, 44, w=(20, 14, 9), fur=False)
    # head: heavy wedge down to a flat snout
    head = poly([(52, 76), (30, 84), (12, 104), (10, 124), (26, 128), (46, 118), (60, 112)])
    c.body(head, meat, soft=8, spec=0.8, shine=10, seed=45)
    c.body(ellipse(12, 116, 7, 10), 0.45, soft=3, seed=46)
    c.flat(union(ellipse(10, 112, 1.6, 2.4), ellipse(10, 121, 1.6, 2.4)), 0.02)
    c.body(tapered([(24, 122), (18, 110), (22, 98)], 5, 2), 0.95, soft=2, spec=0.4, seed=47)  # tusk
    c.body(poly([(44, 80), (54, 64), (58, 82)]), meat * 0.8, soft=3, seed=48)                  # ear
    eye(c, 36, 94, 2.8, 2.2, white=False)
    c.outline(0.9)
    return c, (0, 50, 80)


def crows():
    """Dozens of crows grown into one body; every head turns to you."""
    c = Canvas()
    c.ground_shadow(96, 178, 74, 8)
    mass = union(ellipse(96, 132, 66, 42), ellipse(66, 110, 34, 30), ellipse(128, 106, 36, 32),
                 ellipse(96, 94, 30, 26))
    c.body(mass, 0.42, soft=14, spec=0.7, shine=12, seed=50)
    c.hatch(mass, 200, 0.55, 3.0, 7, seed=150)
    c.hatch(mass, 200, 0.35, 5.0, 5, seed=151, light=True)
    for pts in (((36, 124), (4, 92), (0, 130)), ((154, 112), (190, 84), (192, 124)),
                ((64, 164), (30, 184), (74, 180))):
        w = poly(pts)
        c.body(w, 0.35, soft=4, spec=0.5, seed=52)
        c.hatch(w, 30, 0.6, 3.0, 9, seed=153)
    # heads on stubby necks, each turned to the viewer, heavy beaks
    heads = [(62, 86, 0), (96, 70, 0), (130, 82, 0), (42, 116, -20), (154, 110, 20), (80, 108, -8),
             (114, 108, 8), (64, 142, -10), (128, 140, 10), (96, 128, 0)]
    for i, (x, y, tilt) in enumerate(heads):
        h = ellipse(x, y, 11, 10)
        c.body(h, 0.34, soft=4, spec=0.8, shine=14, seed=53 + i)
        beak = poly([(x - 4, y + 3), (x + 4, y + 3), (x + tilt * 0.2, y + 16)])
        c.body(beak, 0.72, soft=1.5, spec=0.6, seed=70 + i)
        c.darken(stroke([(x - 2, y + 7), (x + 2, y + 7)], 0.8), 0.6)
        for sgn in (-1, 1):
            c.flat(ellipse(x + sgn * 5, y - 1, 2.4, 2.4), 1.0)
            c.flat(ellipse(x + sgn * 5, y - 1, 1.1, 1.1), 0.0)
    c.outline(0.9)
    return c, (46, 40, 100)


def stag():
    """Fallback only: art/stag.jpg (the user's picture) replaces this."""
    c = Canvas()
    c.ground_shadow(104, 176, 74, 8)
    hide = 0.66
    body = union(ellipse(112, 104, 50, 26, -4), ellipse(74, 100, 26, 28), ellipse(150, 104, 22, 24))
    # seven legs: three far (darker), four near
    for i, x in enumerate((96, 126, 152)):
        leg(c, (x, 116), (x + 4, 140), (x - 2, 158), (x, 174), hide * 0.65, 60 + i, w=(11, 8, 5))
    c.body(body, hide, soft=12, seed=64)
    c.hatch(body, 175, 0.35, 3.5, 7, seed=164)
    c.darken(blur(ellipse(112, 118, 40, 8), 5), 0.35)          # belly shadow
    for i, x in enumerate((70, 88, 138, 160)):
        leg(c, (x, 120), (x + (5 if i % 2 else -4), 144), (x, 160), (x + 2, 176), hide, 65 + i, w=(12, 9, 5))
    c.body(tapered([(66, 92), (52, 70), (44, 56)], 24, 16), hide, soft=7, grit=0.08, seed=70)
    head = union(ellipse(42, 50, 14, 12), poly([(34, 46), (12, 60), (14, 68), (36, 60)]))
    c.body(head, hide, soft=5, grit=0.06, seed=71)
    c.flat(ellipse(14, 64, 3, 2.5), 0.05)
    # antlers curling back and down into the skull
    for sgn in (-1, 1):
        a = [(44 + sgn * 4, 40), (58 + sgn * 6, 22), (80, 20 + sgn * 4), (84, 38), (62, 46)]
        c.body(tapered(a, 6, 3), 0.8, soft=2, spec=0.3, seed=72)
        c.body(tapered([(58 + sgn * 6, 22), (54 + sgn * 10, 8)], 4, 2), 0.8, soft=2, seed=73)
    c.darken(blur(ellipse(60, 46, 5, 4), 2), 0.7)               # where the antler bores in
    # a human eye: white, iris, lid
    c.flat(ellipse(34, 50, 5, 3.4), 0.95)
    c.flat(ellipse(33, 50, 2.6, 2.6), 0.15)
    c.flat(ellipse(33, 50, 1.2, 1.2), 0.0)
    c.darken(blur(stroke([(29, 47), (39, 46)], 1.5), 0.7), 0.7)
    c.outline(0.9)
    return c, (0, 4, 96)


# -- mutants -------------------------------------------------------------------

def fused():
    """Two people walking as one, joined at the ribs by shared skin."""
    c = Canvas()
    c.ground_shadow(96, 184, 80, 6)
    for i, cx in enumerate((62, 130)):
        human_body(c, cx, 88, 34, 0.5, 80 + i, tex=0.15)
    # the bridge of skin between them, stretched and veined
    bridge = poly([(92, 118), (100, 112), (106, 118), (104, 160), (94, 164), (88, 158)])
    c.body(bridge, 0.80, soft=5, spec=0.3, seed=83)
    for y in (126, 140, 152):
        c.darken(blur(stroke([(90, y), (98, y - 3), (104, y)], 1), 0.8), 0.5)
    # heads turned toward each other, whispering
    for i, (cx, look) in enumerate(((62, 2), (130, -2))):
        c.body(tapered([(cx, 94), (cx, 80)], 20, 18), 0.78, soft=4, seed=84 + i)
        ey = human_head(c, cx, 58, 0.95, seed=86 + i * 5, hair="short")
        eye(c, cx - 8, ey, 3.4, 2.4, look=(look, 0))
        eye(c, cx + 8, ey, 3.4, 2.4, look=(look, 0))
    c.outline(0.9)
    return c, (48, 22, 96), (22, 12, 148)


def mouthless():
    """A man in a rotted raincoat; his mouth has healed over; gills in his neck."""
    c = Canvas()
    coat = human_body(c, 96, 112, 78, 0.55, 20, tex=0.2)
    for x0, x1 in ((50, 58), (142, 134), (92, 96)):
        c.darken(blur(stroke([(x0, 128), (x1, 192)], 2.5), 1.5), 0.5)      # creases
    c.darken(blur(poly([(60, 150), (70, 160), (62, 176)]), 2), 0.6)       # rot holes
    c.darken(blur(ellipse(140, 170, 6, 4), 1.5), 0.6)
    c.body(tapered([(96, 130), (96, 96)], 40, 36), 0.80, soft=6, spec=0.25, seed=21)
    for i in range(3):   # wet slits in the neck, fluttering
        y = 110 + i * 8
        for sgn in (-1, 1):
            c.darken(blur(stroke([(96 + sgn * 14, y), (96 + sgn * 5, y + 3)], 2.2), 0.7), 0.9)
            c.lighten(stroke([(96 + sgn * 13, y + 2.5), (96 + sgn * 6, y + 5)], 1), 0.6)
    collar = union(poly([(56, 124), (92, 148), (76, 170), (48, 136)]),
                   poly([(136, 124), (100, 148), (116, 170), (144, 136)]))
    c.body(collar, 0.6, soft=4, grit=0.05, seed=22)
    ey = human_head(c, 96, 66, 1.25, seed=23, jaw=1.05, mouth=False, hair="short", hair_tone=0.3)
    eye(c, 85, ey, 4.4, 3, look=(0, 0))
    eye(c, 107, ey, 4.4, 3, look=(0, 0))
    # no mouth: smooth skin with a faint healed seam, and a shadow of a jaw
    c.lighten(blur(ellipse(96, ey + 28, 13, 6), 3), 0.35)
    c.darken(blur(stroke([(86, ey + 29), (106, ey + 28)], 1), 1.2), 0.2)
    c.outline(0.85)
    return c, (48, 20, 96), (24, 10, 144)


def bloom():
    """A woman covered in soft growths that swell as she breathes; half a face."""
    c = Canvas()
    body = human_body(c, 96, 106, 60, 0.32, 100)   # dark dress so the pale growths stand out
    ey = human_head(c, 96, 70, 1.1, seed=101, hair="long", hair_tone=0.2, mouth=False)
    eye(c, 86, ey, 4, 2.8, look=(1, 0))
    c.darken(blur(stroke([(82, ey + 25), (90, ey + 27), (97, ey + 25)], 1.4), 0.7), 0.75)  # half a smile
    # the growths: glossy pale spheres in clusters over the right half and body
    import random
    rng = random.Random(104)
    spots = [(112, 66, 14), (118, 84, 12), (106, 92, 9), (124, 60, 8), (110, 48, 9)]
    for _ in range(26):
        spots.append((rng.uniform(40, 160), rng.uniform(116, 188), rng.uniform(5, 13)))
    for i, (x, y, r) in enumerate(spots):
        if i >= 5 and body[int(min(191, y)), int(x)] < 0.5:
            continue
        c.darken(blur(ellipse(x + 2, y + 3, r, r * 0.9), 2), 0.4)        # contact shadow
        c.body(ellipse(x, y, r, r * 0.9), 0.93, soft=r * 0.5, spec=0.9, shine=20, seed=110 + i)
    c.outline(0.85)
    return c, (48, 26, 96), (24, 16, 144)


# -- people ----------------------------------------------------------------------

def bandits():
    """Two figures step out from behind a wrecked car, one with a knife held low."""
    c = Canvas()
    # the back figure, taller, hood up
    human_body(c, 132, 86, 32, 0.42, 120)
    c.body(ellipse(132, 58, 18, 22), 0.4, soft=6, seed=121)                 # hood
    c.body(ellipse(132, 64, 12, 15), 0.78, soft=5, seed=122)                # face in shadow
    c.darken(blur(ellipse(132, 52, 14, 8), 3), 0.6)
    eye(c, 127, 62, 2.6, 1.8)
    eye(c, 138, 62, 2.6, 1.8)
    # the front figure with a scarf over the face and a knife
    human_body(c, 70, 100, 36, 0.55, 123, tex=0.15)
    ey = human_head(c, 70, 72, 0.9, seed=124, hair="short", hair_tone=0.15)
    eye(c, 62, ey, 3.2, 2.4)
    eye(c, 78, ey, 3.2, 2.4)
    scarf = poly([(50, 80), (90, 80), (88, 98), (70, 104), (52, 98)])
    c.body(scarf, 0.3, soft=3, seed=129)
    c.hatch(scarf, 0, 0.4, 2.5, 6, seed=229, light=True)
    c.body(tapered([(100, 150), (116, 138)], 12, 9), 0.8, soft=3, seed=130)          # fist
    c.body(poly([(116, 134), (142, 118), (120, 140)]), 0.92, soft=1.5, spec=1.0, shine=30, seed=131)
    # the wreck in front: crumpled hood and a dead headlight
    car = poly([(0, 150), (40, 138), (150, 136), (192, 146), (192, 192), (0, 192)])
    c.body(car, 0.6, soft=10, spec=0.5, shine=8, grit=0.08, seed=132)
    c.darken(blur(stroke([(30, 156), (80, 150), (120, 160), (170, 152)], 2), 1.5), 0.7)
    c.body(ellipse(30, 170, 12, 8), 0.2, soft=3, seed=133)
    c.darken(blur(ellipse(120, 176, 30, 6), 3), 0.5)                        # rust stain
    c.outline(0.85)
    return c, (22, 30, 96), (8, 20, 164)


def tollman():
    """A thin man in a welding mask, tapping a lead pipe."""
    c = Canvas()
    human_body(c, 96, 104, 50, 0.45, 140, tex=0.2)
    c.body(tapered([(96, 118), (96, 90)], 20, 18), 0.78, soft=4, seed=141)
    # welding mask: a scuffed plate with a dark visor slit
    mask_ = union(poly([(66, 40), (126, 40), (132, 70), (124, 104), (96, 114), (68, 104), (60, 70)]))
    c.body(mask_, 0.62, soft=10, spec=0.6, shine=8, grit=0.1, seed=142)
    c.flat(poly([(72, 62), (120, 62), (118, 76), (74, 76)]), 0.03)
    c.lighten(stroke([(76, 65), (100, 65)], 1), 0.5)                          # glint on glass
    c.body(ellipse(96, 36, 26, 8), 0.5, soft=3, seed=143)                    # headband
    for x, y in ((74, 90), (116, 88), (92, 100)):
        c.darken(blur(ellipse(x, y, 4, 2), 1), 0.4)                           # dents
    # lead pipe across the body
    c.body(tapered([(30, 184), (150, 110)], 11, 11), 0.55, soft=4, spec=0.7, shine=10, seed=144)
    c.body(ellipse(150, 110, 7, 7), 0.3, soft=2, seed=145)
    c.body(union(ellipse(58, 166, 11, 9), ellipse(112, 136, 11, 9)), 0.78, soft=4, seed=146)   # hands
    c.outline(0.85)
    return c, (48, 26, 96), (24, 16, 144)


def medic():
    """An old woman, clear-eyed, a red cross painted on her pack."""
    c = Canvas()
    # pack strap and the pack behind the shoulder with a painted cross
    c.body(poly([(120, 80), (182, 80), (186, 170), (126, 176)]), 0.55, soft=8, grit=0.08, seed=150)
    c.flat(union(poly([(146, 104), (160, 104), (160, 144), (146, 144)]),
                 poly([(134, 118), (172, 118), (172, 130), (134, 130)])), 0.12)
    human_body(c, 84, 104, 58, 0.62, 151, tex=0.12)
    c.body(tapered([(114, 116), (100, 192)], 10, 10), 0.35, soft=3, seed=152)   # strap
    c.body(tapered([(84, 112), (84, 96)], 26, 24), 0.8, soft=4, seed=153)
    ey = human_head(c, 84, 70, 1.05, seed=154, hair="bun", hair_tone=0.88)   # grey hair in a bun
    eye(c, 75, ey, 3.6, 2.6)
    eye(c, 93, ey, 3.6, 2.6)
    for sgn in (-1, 1):   # crow's feet and smile lines
        c.darken(blur(stroke([(84 + sgn * 15, ey), (84 + sgn * 19, ey + 3)], 0.8), 0.6), 0.4)
        c.darken(blur(stroke([(84 + sgn * 8, ey + 14), (84 + sgn * 10, ey + 22)], 0.8), 0.7), 0.35)
    c.darken(blur(stroke([(77, ey + 23), (84, ey + 25), (91, ey + 23)], 1.3), 0.7), 0.6)
    c.outline(0.85)
    return c, (36, 22, 96), (26, 8, 164)   # wide enough for the cross on her pack


def wanderer():
    """A man with a walking stick sitting by a small fire, hand raised."""
    c = Canvas()
    c.ground_shadow(96, 178, 86, 8, 0.2)
    human_body(c, 84, 98, 44, 0.5, 160, bottom=176, tex=0.25)
    c.body(poly([(40, 176), (130, 176), (140, 186), (36, 186)]), 0.45, soft=4, seed=161)  # legs folded
    c.body(tapered([(150, 30), (138, 186)], 6, 6), 0.55, soft=2, grit=0.2, seed=162)       # stick
    c.body(tapered([(120, 120), (142, 96), (146, 80)], 12, 9), 0.5, soft=4, seed=163)     # raised arm
    c.body(ellipse(146, 74, 8, 9), 0.82, soft=3, seed=164)                                 # open hand
    c.body(tapered([(84, 104), (84, 90)], 22, 20), 0.78, soft=4, seed=165)
    ey = human_head(c, 84, 66, 0.95, seed=166, hair="bald", mouth=False)
    beard = poly([(64, 74), (104, 74), (100, 104), (84, 112), (68, 104)])
    c.body(beard, 0.4, soft=4, seed=167)
    c.hatch(beard, 95, 0.55, 2.2, 6, seed=267)
    c.hatch(beard, 95, 0.35, 3.0, 5, seed=268, light=True)
    c.body(union(ellipse(84, 44, 36, 7), ellipse(84, 36, 20, 12)), 0.3, soft=4, grit=0.1, seed=168)          # hat
    eye(c, 76, ey, 3, 2.2)
    eye(c, 92, ey, 3, 2.2)
    # the fire: bright tongues over dark sticks, lighting his near side
    c.body(union(stroke([(150, 180), (180, 168)], 5), stroke([(148, 168), (182, 182)], 5)), 0.2, soft=2, seed=169)
    flame = union(poly([(154, 170), (166, 128), (176, 170)]), poly([(160, 170), (172, 142), (180, 170)]))
    c.flat(blur(flame, 3), 0.98)
    c.lighten(blur(ellipse(150, 150, 50, 40), 18), 0.5)
    c.outline(0.8)
    return c, (36, 20, 96), (14, 10, 170)


# -- anomalies (whole scenes; no fight) ----------------------------------------------

def _field(c, horizon=120, tone=0.97, seed=200):
    """Pale ground from the horizon down: a hard horizon line, grass tufts
    that grow toward the viewer, and a slightly darker foreground."""
    g = poly([(0, horizon), (192, horizon), (192, 192), (0, 192)])
    c.flat(g, tone, solid=False)
    ramp = np.clip((np.arange(SIZE)[:, None] - horizon) / (192 - horizon), 0, 1) * np.ones((1, SIZE))
    c.darken(ramp * g, 0.18)
    c.darken(stroke([(0, horizon), (192, horizon)], 1.2, False), 0.8)
    import random
    rng = random.Random(seed)
    for _ in range(70):
        x, y = rng.uniform(0, 192), rng.uniform(horizon + 3, 192)
        hgt = 2 + (y - horizon) / 10
        for k in (-1, 0, 1):
            c.darken(stroke([(x, y), (x + k * hgt * 0.4, y - hgt)], 0.8, False), 0.7)


def hollow():
    """Grass pressed flat in a perfect spiral; the air above it hums."""
    c = Canvas()
    _field(c, 70, seed=201)
    c.darken(blur(ellipse(96, 140, 84, 36), 5), 0.35)
    pts = []
    for i in range(180):                       # the spiral, pressed into the dip
        a = i / 180 * 5.2 * math.pi
        r = 4 + i / 180 * 72
        pts.append((96 + r * math.cos(a), 140 + r * 0.42 * math.sin(a)))
    c.darken(blur(stroke(pts, 5), 1), 0.95)         # the pressed-down trench
    c.lighten(stroke([(x - 1, y - 1.5) for x, y in pts], 1.2), 0.9)
    for k in range(5):                         # heat-shimmer lines in the air
        y = 36 + k * 9
        wave = [(20 + x, y + 2.5 * math.sin(x / 7 + k)) for x in range(0, 152, 4)]
        c.darken(stroke(wave, 1.3), 0.9)
    # a crow at the edge, half folded into nothing
    crow = union(ellipse(160, 104, 9, 6), ellipse(152, 99, 4, 4), poly([(148, 99), (142, 101), (148, 102)]))
    c.body(cut(crow, poly([(162, 90), (180, 90), (180, 115), (158, 115)])), 0.2, soft=2, seed=202)
    for i in range(6):
        c.darken(stroke([(163 + i * 2.5, 100 + (i % 3)), (164 + i * 2.5, 102 + (i % 3))], 1), 0.8 - i * 0.1)
    return c, (48, 70, 96)


def bell():
    """A bell tolling under the ground; the earth ripples like water."""
    c = Canvas()
    _field(c, 60, 0.82, seed=210)
    for k in range(6):                         # ripple rings: a dark trough under a lit crest
        rx, ry = 56 + k * 14, 14 + k * 5
        c.darken(blur(ellipse(96, 138, rx + 3, ry + 2) - ellipse(96, 138, rx, ry), 1), 0.85)
    # the bell's crown breaking the surface
    c.darken(blur(ellipse(96, 136, 50, 12), 2), 0.95)             # the hole it rises from
    crown = union(poly([(52, 138), (64, 92), (96, 76), (128, 92), (140, 138)]), ellipse(96, 74, 11, 8))
    c.body(crown, 0.16, soft=12, spec=0.8, shine=22, seed=211)
    c.lighten(blur(stroke([(58, 122), (134, 122)], 2), 1), 0.6)   # the bell's bands
    c.lighten(blur(stroke([(64, 104), (128, 104)], 1.5), 1), 0.5)
    c.darken(blur(ellipse(96, 133, 30, 6), 2), 0.7)
    c.body(stroke([(88, 88), (96, 80), (104, 88)], 3.5), 0.5, soft=1.5, spec=0.6, seed=212)
    return c, (48, 70, 96)


def stars():
    """At midday a patch of sky goes black and fills with unnamed stars."""
    c = Canvas()
    _field(c, 132, 0.8, seed=220)
    hole = blur(ellipse(96, 62, 82, 58), 6)
    c.flat(hole, 0.0, solid=False)
    import random
    rng = random.Random(221)
    for _ in range(70):
        x, y = rng.gauss(96, 36), rng.gauss(62, 24)
        if hole[int(np.clip(y, 0, 191)), int(np.clip(x, 0, 191))] > 0.8:
            r = rng.choice((0.8, 0.8, 1.2, 2.0))
            c.flat(ellipse(x, y, r, r), 1.0, solid=False)
    # a constellation drawn as an eye, looking back down
    eye_pts = [(56 + i * 8, 64 - 14 * math.sin(i / 10 * math.pi)) for i in range(11)] + \
              [(136 - i * 8, 64 + 12 * math.sin(i / 10 * math.pi)) for i in range(11)]
    c.lighten(stroke(eye_pts, 0.8), 0.5)
    for x, y in eye_pts[::2]:
        c.flat(ellipse(x, y, 1.7, 1.7), 1.0, solid=False)
    c.flat(ellipse(96, 64, 6, 6), 1.0, solid=False)
    c.flat(ellipse(96, 64, 3, 3), 0.0, solid=False)
    # a small figure (you) on the horizon, looking up
    c.body(union(ellipse(150, 124, 3, 3.5), tapered([(150, 128), (150, 142)], 5, 4)), 0.1, soft=1, seed=222)
    return c, (48, 16, 96)


def stillness():
    """Birds hang motionless mid-flight; dust floats unmoving in the light."""
    c = Canvas()
    _field(c, 128, 0.86, seed=230)
    for x, y, s in ((50, 54, 1.0), (100, 38, 0.8), (140, 70, 1.1), (72, 92, 0.7), (160, 34, 0.6)):
        bird = union(ellipse(x, y, 6 * s, 3 * s), poly([(x - 2 * s, y), (x - 16 * s, y - 10 * s), (x - 18 * s, y - 4 * s)]),
                     poly([(x + 2 * s, y), (x + 16 * s, y - 10 * s), (x + 18 * s, y - 4 * s)]))
        c.body(bird, 0.25, soft=2, seed=int(x))
    import random
    rng = random.Random(231)
    for _ in range(60):   # motes in a shaft of light
        x, y = rng.uniform(60, 150), rng.uniform(20, 170)
        c.flat(ellipse(x, y, 0.9, 0.9), 0.1, solid=False)
    # your own hand reaching into it from below
    hand = union(tapered([(150, 192), (132, 150)], 22, 16), ellipse(128, 142, 11, 9),
                 tapered([(122, 138), (110, 120)], 5, 4), tapered([(128, 136), (122, 116)], 5, 4),
                 tapered([(134, 138), (132, 118)], 5, 4), tapered([(139, 142), (142, 126)], 4.5, 3.5),
                 tapered([(118, 148), (106, 140)], 5, 4))
    c.body(hand, 0.8, soft=5, seed=232)
    c.outline(0.8)
    return c, (72, 90, 96)


def door():
    """A door frame alone in a field; through it, night, and someone waiting."""
    c = Canvas()
    _field(c, 118, 0.82, seed=240)
    frame = cut(poly([(58, 26), (134, 26), (134, 150), (58, 150)]), poly([(68, 36), (124, 36), (124, 150), (68, 150)]))
    inside = poly([(68, 36), (124, 36), (124, 150), (68, 150)])
    c.flat(inside, 0.04)
    import random
    rng = random.Random(241)
    for _ in range(12):
        x, y = rng.uniform(72, 120), rng.uniform(40, 100)
        c.flat(ellipse(x, y, 0.8, 0.8), 1.0)
    c.flat(poly([(68, 118), (124, 118), (124, 150), (68, 150)]), 0.25)       # the night field
    fig = union(ellipse(98, 104, 4, 5), tapered([(98, 108), (98, 128)], 9, 7))
    c.flat(fig, 0.0)
    c.lighten(blur(ellipse(98, 104, 7, 7), 3) * inside, 0.25)
    c.flat(ellipse(96.5, 103.5, 0.8, 0.8), 1.0)
    c.flat(ellipse(99.5, 103.5, 0.8, 0.8), 1.0)
    c.body(frame, 0.72, soft=4, grit=0.12, seed=242)
    c.darken(blur(poly([(134, 150), (170, 160), (160, 166), (124, 152)]), 3), 0.45)   # its shadow
    c.outline(0.9)
    return c, (48, 30, 96)


def stray():
    """A thin stray mongrel, standing side-on, head turned to you, tail low."""
    c = Canvas()
    c.ground_shadow(100, 172, 70, 8)
    fur = 0.55
    leg(c, (132, 114), (136, 138), (132, 154), (134, 170), fur * 0.7, 70, w=(12, 9, 6))
    leg(c, (82, 114), (78, 136), (82, 154), (78, 170), fur * 0.7, 71, w=(12, 9, 6))
    body = poly([(66, 98), (86, 88), (122, 86), (148, 92), (156, 104), (150, 120),
                 (126, 120), (100, 118), (82, 122), (68, 116)])
    c.body(body, fur, soft=12, seed=72)
    c.hatch(body, 165, 0.45, 3.0, 6, seed=172)
    for i in range(4):                      # thin: ribs show
        x = 96 + i * 8
        c.darken(blur(stroke([(x, 96), (x + 3, 114)], 1.6), 1.2), 0.3)
    c.body(tapered([(154, 104), (170, 118), (176, 134)], 7, 3), fur, soft=3, seed=73)  # tail, low
    leg(c, (144, 114), (148, 138), (144, 154), (146, 170), fur, 74, w=(12, 9, 6))
    leg(c, (92, 116), (88, 138), (92, 154), (90, 170), fur, 75, w=(12, 9, 6))
    neck = tapered([(80, 98), (64, 82), (58, 72)], 24, 18)
    c.body(neck, fur, soft=8, seed=76)
    head = union(ellipse(56, 62, 18, 16), poly([(46, 62), (30, 70), (32, 80), (52, 78)]))
    c.body(head, fur * 1.15, soft=6, seed=77)
    c.body(poly([(60, 48), (70, 30), (72, 54)]), fur * 0.8, soft=3, seed=78)            # ear up
    c.body(tapered([(46, 50), (38, 46), (34, 60)], 8, 6), fur * 0.7, soft=3, seed=79)     # ear flopped
    c.flat(ellipse(31, 74, 4, 3.5), 0.05)                                                 # nose
    c.darken(blur(stroke([(34, 80), (46, 82)], 1.4), 0.8), 0.6)                           # mouth
    eye(c, 50, 60, 4, 3.4)
    eye(c, 62, 58, 3.4, 3)
    c.outline(0.9)
    return c, (16, 30, 96)


def _night(c):
    """Night: everything dark, a faint lighter haze low down."""
    c.flat(poly([(0, 0), (192, 0), (192, 192), (0, 192)]), 0.12)
    c.lighten(blur(ellipse(96, 190, 150, 100), 30), 0.5)


def long_man():
    """Someone at the edge of your light, far too tall and thin."""
    c = Canvas()
    _night(c)
    c.flat(tapered([(96, 190), (96, 40)], 10, 6), 0.0)                      # body, a pole
    c.flat(ellipse(96, 30, 9, 13), 0.0)                                     # head
    c.flat(tapered([(96, 70), (70, 130), (64, 176)], 4, 2), 0.0)            # arms too long
    c.flat(tapered([(96, 70), (122, 130), (128, 176)], 4, 2), 0.0)
    c.flat(ellipse(92, 28, 1.6, 1.2), 0.95)                                 # two pale eyes
    c.flat(ellipse(100, 28, 1.6, 1.2), 0.95)
    return c, (60, 8, 72)


def crawler():
    """A low many-limbed shape on the ground, eyes catching the light."""
    c = Canvas()
    _night(c)
    body = ellipse(96, 140, 46, 16)
    c.flat(body, 0.03)
    for i in range(6):
        x = 58 + i * 15
        c.flat(tapered([(x, 140), (x - 12, 120), (x - 18, 162)], 4, 2), 0.03)
    for x in (70, 80, 92, 104, 116):
        c.flat(ellipse(x, 132, 2.2, 1.6), 0.97)
    return c, (40, 96, 112)


def whisper():
    """Pale faces under black water, mouths open."""
    c = Canvas()
    _night(c)
    c.flat(poly([(0, 110), (192, 110), (192, 192), (0, 192)]), 0.02)       # the river
    for x, y in ((50, 140), (96, 128), (142, 146)):
        c.body(ellipse(x, y, 13, 16), 0.55, soft=5, seed=x)
        c.flat(ellipse(x - 5, y - 3, 2, 2.5), 0.02)
        c.flat(ellipse(x + 5, y - 3, 2, 2.5), 0.02)
        c.flat(ellipse(x, y + 7, 3, 4), 0.02)
    c.darken(blur(poly([(0, 150), (192, 150), (192, 192), (0, 192)]), 8), 0.6)
    return c, (60, 96, 80)


def karl():
    """Karl the fisherman: a PLACEHOLDER smiley face. Karl is a real person;
    the user will supply art/karl.jpg, which replaces this automatically."""
    c = Canvas()
    face = ellipse(96, 96, 72, 72)
    c.flat(face, 0.97)
    c.darken(stroke([(96 + 72 * np.cos(a), 96 + 72 * np.sin(a)) for a in np.linspace(0, 2 * np.pi, 64)], 5, False), 0.9)
    c.flat(ellipse(70, 74, 9, 13), 0.05)                       # eyes
    c.flat(ellipse(122, 74, 9, 13), 0.05)
    smile = [(96 + 44 * np.cos(a), 104 + 36 * np.sin(a)) for a in np.linspace(0.2 * np.pi, 0.8 * np.pi, 24)]
    c.darken(stroke(smile, 6), 0.95)                           # the smile
    return c, (24, 24, 144)


def little():
    """The Little Ones: a small grey child-thing, huge head and eyes, a grin
    of too many small teeth, ears like a bat's; two more peeking behind."""
    c = Canvas()
    c.ground_shadow(96, 178, 60, 8)
    grey = 0.62
    for x, y, s in ((40, 120, 0.55), (156, 116, 0.5)):          # two peeking behind
        c.body(ellipse(x, y, 22 * s * 1.6, 20 * s * 1.6), grey * 0.8, soft=6, seed=int(x))
        eye(c, x - 7 * s * 1.6, y - 2, 4, 3.4)
        eye(c, x + 7 * s * 1.6, y - 2, 4, 3.4)
    c.body(poly([(70, 120), (122, 120), (132, 176), (60, 176)]), grey, soft=8, seed=91)   # small body
    c.body(tapered([(74, 128), (56, 150), (54, 168)], 10, 7), grey, soft=4, seed=92)       # arms
    c.body(tapered([(118, 128), (136, 148), (140, 166)], 10, 7), grey, soft=4, seed=93)
    c.body(poly([(46, 70), (14, 40), (40, 92)]), grey * 0.9, soft=4, seed=94)              # bat ears
    c.body(poly([(146, 70), (178, 40), (152, 92)]), grey * 0.9, soft=4, seed=95)
    head = ellipse(96, 84, 56, 50)
    c.body(head, grey * 1.1, soft=10, seed=96)
    eye(c, 74, 78, 13, 11)                                      # big wet eyes
    eye(c, 118, 78, 13, 11)
    grin = poly([(62, 104), (130, 104), (118, 122), (74, 122)])
    c.flat(grin, 0.05)
    for i in range(9):                                          # little teeth
        x = 66 + i * 7.5
        c.flat(poly([(x, 104), (x + 5, 104), (x + 2.5, 111)]), 0.98)
        c.flat(poly([(x + 3, 122), (x + 8, 122), (x + 5.5, 116)]), 0.98)
    c.outline(0.9)
    return c, (30, 30, 132)


def institute():
    """The Institute: a stair going down into the dark, a doorway full of
    light at the bottom, the hum drawn as rings in the air."""
    c = Canvas()
    c.flat(poly([(0, 0), (192, 0), (192, 192), (0, 192)]), 0.1)
    for i in range(7):                                         # steps, nearest lowest
        y = 186 - i * 14
        w = 92 - i * 9
        c.flat(poly([(96 - w, y), (96 + w, y), (96 + w - 6, y - 8), (96 - w + 6, y - 8)]), 0.22 + i * 0.03)
    c.lighten(blur(ellipse(96, 66, 46, 50), 14), 0.6)          # the glow spilling out
    c.flat(poly([(72, 26), (120, 26), (120, 94), (72, 94)]), 0.96)   # the doorway
    c.flat(poly([(78, 32), (114, 32), (114, 94), (78, 94)]), 1.0)
    for r in (58, 72, 86):                                      # the hum, rings in the air
        ring = [(96 + r * np.cos(a), 60 + r * 0.8 * np.sin(a)) for a in np.linspace(0, 2 * np.pi, 72)]
        c.lighten(stroke(ring, 1.2, False), 0.35)
    c.darken(poly([(92, 70), (100, 70), (102, 94), (90, 94)]), 0.8)   # someone standing in it
    c.darken(ellipse(96, 64, 5, 6), 0.8)
    return c, (24, 16, 144)


SUBJECTS = {
    "jawhound": jawhound, "boar": boar, "crows": crows, "stag": stag,
    "fused": fused, "mouthless": mouthless, "bloom": bloom,
    "bandits": bandits, "rivals": bandits, "tollman": tollman, "medic": medic, "wanderer": wanderer,
    "karl": karl, "stray": stray, "little": little, "institute": institute,
    "long_man": long_man, "crawler": crawler, "whisper": whisper,
    "hollow": hollow, "bell": bell, "stars": stars, "stillness": stillness, "door": door,
}
