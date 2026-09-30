"""
Needs system. Ties hunger/thirst/rest to the hours the player has spent
moving vs. resting. Values are clamped 0-100; hitting 0 on any of the
three costs the player movement points (see Player.effective_max_mp).
"""

NEED_HUNGER = "Sated hunger"
NEED_THIRST = "Slaked thirst"
NEED_REST = "Well-rested"

# Roughly: empty from full over N hours of being awake and active.
HUNGER_DRAIN_PER_HOUR = 100 / 72   # ~3 days
THIRST_DRAIN_PER_HOUR = 100 / 48   # ~2 days
REST_DRAIN_PER_HOUR = 100 / 18     # ~18 waking hours
REST_GAIN_PER_HOUR = 100 / 6       # a 6h rest fully restores


def _clamp(v):
    return max(0, min(100, v))


def apply_awake_hours(player, hours):
    n = player.needs
    n[NEED_HUNGER] = _clamp(n[NEED_HUNGER] - HUNGER_DRAIN_PER_HOUR * hours)
    n[NEED_THIRST] = _clamp(n[NEED_THIRST] - THIRST_DRAIN_PER_HOUR * hours)
    n[NEED_REST] = _clamp(n[NEED_REST] - REST_DRAIN_PER_HOUR * hours)


def apply_rest_hours(player, hours):
    n = player.needs
    # still get hungry/thirsty while resting, just more slowly
    n[NEED_HUNGER] = _clamp(n[NEED_HUNGER] - HUNGER_DRAIN_PER_HOUR * hours * 0.5)
    n[NEED_THIRST] = _clamp(n[NEED_THIRST] - THIRST_DRAIN_PER_HOUR * hours * 0.5)
    n[NEED_REST] = _clamp(n[NEED_REST] + REST_GAIN_PER_HOUR * hours)


def critical_warnings(player):
    n = player.needs
    warnings = []
    if n[NEED_HUNGER] <= 0:
        warnings.append("You are starving!")
    if n[NEED_THIRST] <= 0:
        warnings.append("You are dehydrated!")
    if n[NEED_REST] <= 0:
        warnings.append("You are exhausted!")
    return warnings
