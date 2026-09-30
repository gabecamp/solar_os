"""
Character creation data.

Attributes: a small NEO Scavenger-style point-buy across four stats.
Traits: a Project Zomboid-style budget — positive traits COST points,
negative traits GRANT points, and the character must end with a
non-negative point total to be confirmable.

Both feed into derived Player stats (max_mp, sight) via `effects` dicts
that get summed and applied in player.py.
"""

ATTRIBUTES = ["Strength", "Speed", "Perception", "Endurance"]
ATTRIBUTE_MIN = 1
ATTRIBUTE_MAX = 6
ATTRIBUTE_DEFAULT = 3
ATTRIBUTE_POINTS_TOTAL = 12  # exactly enough for 4 attributes at default 3

# Each trait: name, type ("positive"/"negative"), cost (points spent if
# positive, points granted if negative), a short description, and an
# `effects` dict of derived-stat deltas applied to the Player.
TRAITS = [
    # -- positive (cost points) --
    {"name": "Quick", "type": "positive", "cost": 3,
     "desc": "+1 Movement Point per turn.", "effects": {"max_mp": 1}},
    {"name": "Hawk-Eyed", "type": "positive", "cost": 3,
     "desc": "+1 Sight radius.", "effects": {"sight": 1}},
    {"name": "Fast Healer", "type": "positive", "cost": 2,
     "desc": "Heals injuries faster.", "effects": {}},
    {"name": "Iron Gut", "type": "positive", "cost": 2,
     "desc": "Resistant to bad food and illness.", "effects": {}},
    {"name": "Pack Mule", "type": "positive", "cost": 2,
     "desc": "Can carry more weight before being encumbered.", "effects": {}},
    {"name": "Thick Skinned", "type": "positive", "cost": 2,
     "desc": "Takes less injury from physical harm.", "effects": {}},

    # -- negative (grant points) --
    {"name": "Asthmatic", "type": "negative", "cost": 3,
     "desc": "-1 Movement Point per turn.", "effects": {"max_mp": -1}},
    {"name": "Near-Sighted", "type": "negative", "cost": 3,
     "desc": "-1 Sight radius.", "effects": {"sight": -1}},
    {"name": "Slow Metabolism", "type": "negative", "cost": 2,
     "desc": "Hunger drains faster.", "effects": {}},
    {"name": "Clumsy", "type": "negative", "cost": 2,
     "desc": "More prone to accidents and injury.", "effects": {}},
    {"name": "Prone to Illness", "type": "negative", "cost": 3,
     "desc": "Weaker immune system.", "effects": {}},
    {"name": "Insomniac", "type": "negative", "cost": 2,
     "desc": "Resting restores fewer movement points.", "effects": {}},
]

POSITIVE_TRAITS = [t for t in TRAITS if t["type"] == "positive"]
NEGATIVE_TRAITS = [t for t in TRAITS if t["type"] == "negative"]
