"""Procedural hex overworld generation."""

import random
from constants import TERRAIN_WEIGHTS, GRID_RADIUS


def weighted_terrain_choice():
    terrains = list(TERRAIN_WEIGHTS.keys())
    weights = list(TERRAIN_WEIGHTS.values())
    return random.choices(terrains, weights=weights, k=1)[0]


def generate_map(radius=GRID_RADIUS):
    tiles = {}
    for q in range(-radius, radius + 1):
        for r in range(-radius, radius + 1):
            if -radius <= -q - r <= radius:
                tiles[(q, r)] = weighted_terrain_choice()
    tiles[(0, 0)] = "plains"  # guarantee a safe start tile
    return tiles


def generate_ground_items(tiles):
    """Scatter a starter loot pile at the spawn tile. Keyed same as tiles."""
    ground = {
        (0, 0): [
            {"item_id": "rock", "qty": 1},
            {"item_id": "cloth_scrap", "qty": 2},
            {"item_id": "newspaper", "qty": 1},
            {"item_id": "canned_beans", "qty": 1},
            {"item_id": "water_bottle", "qty": 2},
        ]
    }
    return ground

