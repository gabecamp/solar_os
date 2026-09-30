"""
Item definitions and equip-slot layout.

Items are plain dicts looked up by id in ITEM_DB — keeps save/load trivial
(inventory & ground items just store {"item_id": ..., "qty": ...}).
"""

EQUIP_SLOTS = [
    "head", "ears", "eyes", "neck", "shirt",
    "jacket", "hands", "wrists", "pants", "feet",
]

# name, equip slot (None = not wearable), weight, consumable need-restore
# effects (None = not consumable), and a placeholder icon color.
ITEM_DB = {
    "tshirt":       {"name": "T-Shirt",      "slot": "shirt",  "weight": 0.3, "consumable": None, "color": (90, 110, 150)},
    "jacket":       {"name": "Jacket",       "slot": "jacket", "weight": 1.0, "consumable": None, "color": (80, 70, 60)},
    "jeans":        {"name": "Jeans",        "slot": "pants",  "weight": 0.6, "consumable": None, "color": (70, 80, 110)},
    "boots":        {"name": "Boots",        "slot": "feet",   "weight": 1.2, "consumable": None, "color": (120, 80, 40)},
    "cap":          {"name": "Cap",          "slot": "head",   "weight": 0.2, "consumable": None, "color": (60, 60, 60)},
    "earplugs":     {"name": "Earplugs",     "slot": "ears",   "weight": 0.05, "consumable": None, "color": (200, 200, 180)},
    "glasses":      {"name": "Glasses",      "slot": "eyes",   "weight": 0.1, "consumable": None, "color": (180, 180, 190)},
    "necklace":     {"name": "Necklace",     "slot": "neck",   "weight": 0.1, "consumable": None, "color": (200, 180, 90)},
    "gloves":       {"name": "Gloves",       "slot": "hands",  "weight": 0.3, "consumable": None, "color": (90, 70, 60)},
    "watch":        {"name": "Watch",        "slot": "wrists", "weight": 0.1, "consumable": None, "color": (150, 150, 150)},

    "canned_beans": {"name": "Canned Beans", "slot": None, "weight": 0.4,
                      "consumable": {"Sated hunger": 40}, "color": (150, 120, 60)},
    "water_bottle": {"name": "Water Bottle", "slot": None, "weight": 0.5,
                      "consumable": {"Slaked thirst": 50}, "color": (90, 140, 190)},
    "rock":         {"name": "Rock",         "slot": None, "weight": 0.5, "consumable": None, "color": (110, 110, 110)},
    "cloth_scrap":  {"name": "Cloth Scrap",  "slot": None, "weight": 0.1, "consumable": None, "color": (180, 170, 150)},
    "newspaper":    {"name": "Newspaper",    "slot": None, "weight": 0.1, "consumable": None, "color": (200, 200, 190)},
}

BACKPACK_CAPACITY = 24  # max distinct item stacks the player can carry
