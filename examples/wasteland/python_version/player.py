"""Player state: identity, attributes/traits, derived stats, needs, gear, position."""

from constants import BASE_MAX_MOVEMENT_POINTS, BASE_SIGHT, NEEDS
from traits import ATTRIBUTES, ATTRIBUTE_DEFAULT
from items import EQUIP_SLOTS


class Player:
    def __init__(self, name="Survivor", attributes=None, trait_names=None):
        self.name = name
        self.attributes = attributes or {a: ATTRIBUTE_DEFAULT for a in ATTRIBUTES}
        self.trait_names = trait_names or []

        # Derived stats — recomputed from attributes + traits.
        self.max_mp = BASE_MAX_MOVEMENT_POINTS
        self.sight = BASE_SIGHT
        self.recompute_derived_stats()

        # Run state
        self.mp = self.max_mp
        self.game_hours = 0.0
        self.money = 0.0
        self.needs = {n: 100 for n in NEEDS}

        self.player_pos = (0, 0)
        self.explored = set()
        self.visible = set()

        # Gear: equipped[slot] -> item_id or None; inventory is a simple
        # list of {"item_id": ..., "qty": ...} stacks (the backpack).
        self.equipped = {slot: None for slot in EQUIP_SLOTS}
        self.equipped["shirt"] = "tshirt"
        self.equipped["pants"] = "jeans"
        self.equipped["feet"] = "boots"
        self.inventory = [
            {"item_id": "water_bottle", "qty": 1},
            {"item_id": "canned_beans", "qty": 1},
        ]

    def recompute_derived_stats(self):
        from traits import TRAITS  # local import avoids a circular-ish surprise

        max_mp = BASE_MAX_MOVEMENT_POINTS + (self.attributes.get("Speed", ATTRIBUTE_DEFAULT) - ATTRIBUTE_DEFAULT) // 2
        sight = BASE_SIGHT + (self.attributes.get("Perception", ATTRIBUTE_DEFAULT) - ATTRIBUTE_DEFAULT) // 2

        by_name = {t["name"]: t for t in TRAITS}
        for tname in self.trait_names:
            trait = by_name.get(tname)
            if not trait:
                continue
            max_mp += trait["effects"].get("max_mp", 0)
            sight += trait["effects"].get("sight", 0)

        self.max_mp = max(1, max_mp)
        self.sight = max(1, sight)

    def effective_max_mp(self):
        """Movement points available this rest, penalized by critical needs."""
        from needs import NEED_HUNGER, NEED_THIRST, NEED_REST
        penalty = sum(1 for n in (NEED_HUNGER, NEED_THIRST, NEED_REST) if self.needs[n] <= 0)
        return max(1, self.max_mp - penalty)

    def to_dict(self):
        return {
            "name": self.name,
            "attributes": self.attributes,
            "trait_names": self.trait_names,
            "max_mp": self.max_mp,
            "sight": self.sight,
            "mp": self.mp,
            "game_hours": self.game_hours,
            "money": self.money,
            "needs": self.needs,
            "player_pos": list(self.player_pos),
            "explored": [list(p) for p in self.explored],
            "equipped": self.equipped,
            "inventory": self.inventory,
        }

    @classmethod
    def from_dict(cls, data):
        p = cls(name=data["name"], attributes=data["attributes"], trait_names=data["trait_names"])
        p.max_mp = data.get("max_mp", p.max_mp)
        p.sight = data.get("sight", p.sight)
        p.mp = data.get("mp", p.max_mp)
        p.game_hours = data.get("game_hours", 0.0)
        p.money = data.get("money", 0.0)
        p.needs = data.get("needs", p.needs)
        p.player_pos = tuple(data.get("player_pos", (0, 0)))
        p.explored = {tuple(x) for x in data.get("explored", [])}
        p.equipped = data.get("equipped", p.equipped)
        p.inventory = data.get("inventory", p.inventory)
        return p
