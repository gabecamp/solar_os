"""
Shared constants for the game: screen/UI layout, terrain data, colors,
and gameplay tuning numbers. Nothing in here should import from any
other module in this project (keeps it dependency-free / easy to tweak).
"""

SCREEN_W, SCREEN_H = 1024, 600
FPS = 30
FONT_NAME = None  # default pygame font

SAVE_FILE = "savegame.json"

# -- hex grid / map ----------------------------------------------------------

HEX_SIZE = 25              # "radius" of a hex, center to corner (pre-squash)
GRID_RADIUS = 7              # hex grid extends this many tiles from center (0,0,0)

ISO_Y_SCALE = 0.58           # vertical squash factor for the isometric look
TILE_DEPTH = 10              # how "tall" each tile block appears (px)

# Terrain types: name -> (color, move_cost, passable)
# move_cost doubles as both movement-point cost AND in-game hours spent.
TERRAIN = {
    "plains":   ((150, 190, 90),  1, True),
    "forest":   ((60, 110, 60),   2, True),
    "hills":    ((150, 140, 100), 2, True),
    "swamp":    ((90, 100, 70),   3, True),
    "water":    ((70, 110, 170),  0, False),
    "ruins":    ((120, 110, 120), 2, True),
}
TERRAIN_WEIGHTS = {
    "plains": 40, "forest": 25, "hills": 15, "swamp": 8, "water": 7, "ruins": 5,
}

BG_COLOR = (10, 10, 10)
GRID_LINE_COLOR = (10, 10, 12)
PLAYER_COLOR = (230, 60, 60)
HOVER_COLOR = (255, 255, 255)
REACHABLE_COLOR = (255, 220, 100)
NO_MP_COLOR = (110, 110, 110)

# -- movement / fog of war ----------------------------------------------------

BASE_MAX_MOVEMENT_POINTS = 2
REST_HOURS = 4

BASE_SIGHT = 2
FOG_UNSEEN_COLOR = (8, 8, 10)
EXPLORED_SHADE = 0.4

# -- UI panel layout (used by the overworld screen) --------------------------

LEFT_PANEL_W = 220
RIGHT_PANEL_W = 150
BOTTOM_PANEL_H = 165
PANEL_BG = (18, 18, 18)
PANEL_BORDER = (60, 60, 60)
BAR_BG = (35, 35, 35)
BAR_FILL = (70, 190, 70)
BAR_BORDER = (90, 90, 90)
TEXT_COLOR = (220, 220, 220)
DIM_TEXT = (150, 150, 150)

ACTION_BUTTONS = [
    ("RUN",         (190, 60, 60)),
    ("HIDE",        (150, 140, 120)),
    ("HIDE TRACKS", (200, 130, 30)),
    ("SPY",         (140, 90, 190)),
    ("SCAVENGE",    (60, 140, 190)),
]

ICON_BUTTONS = ["CHAR", "MEDIC", "CAMP", "VEHICLE"]

NEEDS = [
    "Sated hunger",
    "Slaked thirst",
    "Well-rested",
    "Unburdened",
    "Comfortable",
    "Outdoor Temp",
    "Unhurt",
]

# -- shared UI colors (menu / character creator) ------------------------------

MENU_BG = (14, 14, 16)
TITLE_COLOR = (230, 230, 230)
BUTTON_BG = (35, 35, 35)
BUTTON_BG_HOVER = (55, 55, 55)
BUTTON_BORDER = (90, 90, 90)
BUTTON_DISABLED = (25, 25, 25)
ACCENT_COLOR = (90, 170, 90)
WARN_COLOR = (200, 90, 90)
