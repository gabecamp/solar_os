"""Save/load the whole game (player + map + ground items) to a JSON file."""

import json
import os
from constants import SAVE_FILE
from player import Player


def save_exists(path=SAVE_FILE):
    return os.path.isfile(path)


def save_game(player, tiles, ground_items, path=SAVE_FILE):
    data = {
        "player": player.to_dict(),
        "tiles": {f"{q},{r}": terrain for (q, r), terrain in tiles.items()},
        "ground_items": {f"{q},{r}": stacks for (q, r), stacks in ground_items.items()},
    }
    with open(path, "w") as f:
        json.dump(data, f)


def load_game(path=SAVE_FILE):
    """Returns (player, tiles, ground_items) or None if no save / unreadable."""
    if not save_exists(path):
        return None
    try:
        with open(path, "r") as f:
            data = json.load(f)
        player = Player.from_dict(data["player"])

        tiles = {}
        for key, terrain in data["tiles"].items():
            q_str, r_str = key.split(",")
            tiles[(int(q_str), int(r_str))] = terrain

        ground_items = {}
        for key, stacks in data.get("ground_items", {}).items():
            q_str, r_str = key.split(",")
            ground_items[(int(q_str), int(r_str))] = stacks

        return player, tiles, ground_items
    except (json.JSONDecodeError, KeyError, ValueError, OSError):
        return None
