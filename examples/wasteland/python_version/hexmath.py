"""
Hex math (axial coordinates, pointy-top hexes), with an isometric squash
applied only at the point of converting to screen pixels.
Reference: https://www.redblobgames.com/grids/hexagons/
"""

import math
from constants import ISO_Y_SCALE

AXIAL_DIRECTIONS = [
    (1, 0), (1, -1), (0, -1),
    (-1, 0), (-1, 1), (0, 1),
]


def axial_to_pixel(q, r, size):
    x = size * (math.sqrt(3) * q + math.sqrt(3) / 2 * r)
    y = size * (3 / 2 * r)
    return x, y


def axial_to_iso(q, r, size):
    x, y = axial_to_pixel(q, r, size)
    return x, y * ISO_Y_SCALE


def iso_to_axial(x, y, size):
    unsquashed_y = y / ISO_Y_SCALE
    return pixel_to_axial(x, unsquashed_y, size)


def pixel_to_axial(x, y, size):
    q = (math.sqrt(3) / 3 * x - 1 / 3 * y) / size
    r = (2 / 3 * y) / size
    return axial_round(q, r)


def axial_round(q, r):
    x, z = q, r
    y = -x - z
    rx, ry, rz = round(x), round(y), round(z)
    x_diff, y_diff, z_diff = abs(rx - x), abs(ry - y), abs(rz - z)
    if x_diff > y_diff and x_diff > z_diff:
        rx = -ry - rz
    elif y_diff > z_diff:
        ry = -rx - rz
    else:
        rz = -rx - ry
    return int(rx), int(rz)


def axial_distance(a, b):
    aq, ar = a
    bq, br = b
    ax, az = aq, ar
    ay = -ax - az
    bx, bz = bq, br
    by = -bx - bz
    return max(abs(ax - bx), abs(ay - by), abs(az - bz))


def hex_top_corners(cx, cy, size):
    corners = []
    for i in range(6):
        angle = math.pi / 180 * (60 * i - 30)
        ox = size * math.cos(angle)
        oy = size * math.sin(angle) * ISO_Y_SCALE
        corners.append((cx + ox, cy + oy))
    return corners


def shade(color, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in color)


def neighbors_of(pos, tiles):
    q, r = pos
    result = []
    for dq, dr in AXIAL_DIRECTIONS:
        n = (q + dq, r + dr)
        if n in tiles:
            result.append(n)
    return result
