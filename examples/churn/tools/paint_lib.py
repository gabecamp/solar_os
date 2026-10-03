"""Tiny painting engine for the encounter portraits (runs on a PC, not the device).

Every creature is built from shapes (ellipses, polygons, thick strokes). Each
shape is shaded as if it were a soft 3D volume: its mask is blurred into a
height field, the height field's slope gives a surface normal, and the normal
is lit from the upper left (plus optional wet-looking specular and a noise
texture for skin/fur). Painting happens in grayscale at 192x192; the portrait
builder downsamples and dithers the result to 1-bit for the RLCD.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 192          # master canvas
SS = 2              # supersampling for anti-aliased masks
LIGHT = np.array([-0.55, -0.75, 0.65])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0.0, 0.0, 1.0])
HALF = HALF / np.linalg.norm(HALF)


def _blank_mask():
    return Image.new("L", (SIZE * SS, SIZE * SS), 0)


def _finish_mask(img):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(img, dtype=np.float32) / 255.0


def _s(pts):
    return [(x * SS, y * SS) for x, y in pts]


def ellipse(cx, cy, rx, ry, rot=0.0):
    """Mask of an ellipse (rot in degrees)."""
    pts = []
    for i in range(64):
        a = 2 * math.pi * i / 64
        x, y = rx * math.cos(a), ry * math.sin(a)
        r = math.radians(rot)
        pts.append((cx + x * math.cos(r) - y * math.sin(r), cy + x * math.sin(r) + y * math.cos(r)))
    return poly(pts)


def poly(pts):
    img = _blank_mask()
    ImageDraw.Draw(img).polygon(_s(pts), fill=255)
    return _finish_mask(img)


def stroke(pts, width, round_caps=True):
    """Mask of a thick polyline (limbs, antlers, tails)."""
    img = _blank_mask()
    d = ImageDraw.Draw(img)
    sp = _s(pts)
    d.line(sp, fill=255, width=int(width * SS), joint="curve")
    if round_caps:
        r = width * SS / 2
        for x, y in (sp[0], sp[-1]):
            d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return _finish_mask(img)


def tapered(pts, w0, w1):
    """A limb that narrows from w0 to w1 along the polyline."""
    m = np.zeros((SIZE, SIZE), np.float32)
    n = len(pts) - 1
    for i in range(n):
        t = i / max(1, n - 1) if n > 1 else 0
        w = w0 + (w1 - w0) * (i + 0.5) / n
        m = np.maximum(m, stroke([pts[i], pts[i + 1]], w))
    return m


def union(*masks):
    out = np.zeros((SIZE, SIZE), np.float32)
    for m in masks:
        out = np.maximum(out, m)
    return out


def cut(a, b):
    return np.clip(a - b, 0, 1)


def blur(arr, r):
    img = Image.fromarray(np.uint8(np.clip(arr, 0, 1) * 255))
    img = img.filter(ImageFilter.GaussianBlur(r))
    return np.asarray(img, dtype=np.float32) / 255.0


def noise(scale, seed):
    """Smooth value noise in 0..1 (feature size ~scale px)."""
    rng = np.random.default_rng(seed)
    n = max(2, SIZE // max(1, scale) + 2)
    small = Image.fromarray(np.uint8(rng.random((n, n)) * 255))
    big = small.resize((SIZE, SIZE), Image.BICUBIC)
    return np.asarray(big, dtype=np.float32) / 255.0


def grain(seed, amount=1.0):
    """Fine pixel-level grain -1..1 (fur, grit)."""
    rng = np.random.default_rng(seed)
    return (rng.random((SIZE, SIZE)).astype(np.float32) * 2 - 1) * amount


class Canvas:
    def __init__(self, bg=1.0):
        self.lum = np.full((SIZE, SIZE), bg, np.float32)
        self.alpha = np.zeros((SIZE, SIZE), np.float32)   # what counts as "the creature"

    def _over(self, layer, m, solid=True):
        self.lum = self.lum * (1 - m) + layer * m
        if solid:
            self.alpha = np.maximum(self.alpha, m)

    def body(self, mask, tone, soft=7.0, bulge=16.0, spec=0.0, shine=18.0,
             tex=0.0, tex_scale=6, grit=0.0, seed=1, ambient=0.05, gain=1.55,
             contrast=1.6, occl=0.35, solid=True):
        """A shaded volume. tone = albedo 0 (black) .. 1 (white).

        Strong light/shadow separation on purpose: the RLCD is 1-bit, so a
        form only reads if its lit side dithers near-white and its shadow
        side near-black; mid-gray everywhere turns into noise."""
        h = blur(mask, soft)
        gy, gx = np.gradient(h * bulge)
        nx, ny, nz = -gx, -gy, np.ones_like(h)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / ln, ny / ln, nz / ln
        diff = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
        # the facing-the-light core of a form goes bright, the turning-away
        # side falls off fast into shadow (engraving-like, reads in 1-bit)
        shade = np.clip(ambient + gain * diff, 0, 1) ** contrast
        # occlusion: edges and thin parts are darker than the core of a form
        shade = shade * ((1 - occl) + occl * np.clip(h * 1.6, 0, 1))
        alb = np.full_like(h, tone)
        if tex:
            alb = alb + (noise(tex_scale, seed) - 0.5) * tex
        if grit:
            alb = alb + grain(seed + 7, grit)
        layer = alb * shade
        if spec:
            s = np.clip(nx * HALF[0] + ny * HALF[1] + nz * HALF[2], 0, 1) ** shine
            layer = layer + spec * s
        self._over(np.clip(layer, 0, 1), mask, solid)

    def flat(self, mask, tone, solid=True):
        self._over(np.full((SIZE, SIZE), tone, np.float32), mask, solid)

    def darken(self, mask, amount):
        """Multiply shadow over existing paint (crevices, cast shadows)."""
        self.lum = self.lum * (1 - amount * mask)

    def lighten(self, mask, amount):
        self.lum = self.lum + (1 - self.lum) * amount * mask

    def ground_shadow(self, cx, cy, rx, ry, amount=0.35):
        self.darken(blur(ellipse(cx, cy, rx, ry), 6), amount)

    def hatch(self, mask, angle, amount=0.45, spacing=4.0, length=5.0, seed=1, light=False):
        """Short strokes following a direction inside a mask: fur, grass,
        feathers, fabric grain. They read in 1-bit where noise does not."""
        import random
        rng = random.Random(seed)
        a = math.radians(angle)
        dx, dy = math.cos(a) * length, math.sin(a) * length
        ys, xs = np.nonzero(mask > 0.5)
        if len(xs) == 0:
            return
        n = int(len(xs) / (spacing * spacing))
        strokes = np.zeros((SIZE, SIZE), np.float32)
        for _ in range(n):
            i = rng.randrange(len(xs))
            x, y = xs[i] + rng.random(), ys[i] + rng.random()
            j = rng.uniform(-0.35, 0.35)
            strokes = np.maximum(strokes, stroke([(x, y), (x + dx + j * dy, y + dy - j * dx)], 0.8, False))
        strokes *= mask
        if light:
            self.lighten(strokes, amount)
        else:
            self.darken(strokes, amount)

    def outline(self, amount=0.75, width=1):
        """Dark rim around the whole figure so it separates from white."""
        a = (self.alpha > 0.5).astype(np.float32)
        img = Image.fromarray(np.uint8(a * 255))
        er = np.asarray(img.filter(ImageFilter.MinFilter(1 + 2 * width)), np.float32) / 255
        edge = np.clip(a - er, 0, 1)
        self.darken(edge, amount)

    def image(self):
        return Image.fromarray(np.uint8(np.clip(self.lum, 0, 1) * 255), "L")
