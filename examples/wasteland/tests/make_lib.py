"""Generate the test-only copies of ../wasteland.lua that the tests load.

wasteland.lua is a script: everything before the '-- Main loop' marker defines
the game (Game class, item db, sprites, hex math...), everything after runs the
loop. The tests need the definitions WITHOUT the loop, so we cut at the marker
and append a `return` that exports the locals a given test wants.

Outputs (git-ignored, regenerated on every run):
  lib_only.lua       -> unit_test, sprite_test, bounds_test, body_test, render_scene
  lib_map.lua        -> glyph_test
  lib_layout.lua     -> bounds_test, regression_test (layout constants + INV_ROWS/INV_POS)
  lib_scavenge.lua   -> scavenge_test
  lib_creator.lua    -> creator_test, regression_test (stats, traits, slots)
  lib_encounter.lua  -> encounter_test, portrait_test (encounters and their art)
  lib_crafting.lua   -> crafting_test
  lib_world.lua      -> world_test
  lib_save.lua       -> save_test
  wasteland_run.lua  -> full copy, run under the fake solaros by run_tests.sh / soak
"""
import pathlib

here = pathlib.Path(__file__).resolve().parent
src = (here.parent / "wasteland.lua").read_text()
cut = src.index("-- Main loop")
lib = src[:cut]

(here / "lib_only.lua").write_text(
    lib + "\nreturn Game, ITEM_DB, EQUIP_SLOTS, TERRAIN, SPRITES, SPRITE_ART\n")
(here / "lib_map.lua").write_text(
    lib + "\nreturn Game, TERRAIN, GLYPHS, GLYPH_ART, GLYPH_W, GLYPH_H, "
          "LEGEND_ORDER, LEGEND_Y, MAP_TOP, HEX_SIZE, MAP_W, MAP_BOTTOM, PANEL_X\n")
# Layout constants as a table, so layout tests check the game's real numbers
# instead of copies that go stale.
(here / "lib_layout.lua").write_text(
    lib + "\nreturn Game, {EQUIP_SLOTS = EQUIP_SLOTS, EQUIP_RECT = EQUIP_RECT, "
          "BODY_BLOCKS = BODY_BLOCKS, PART_BLOCKS = PART_BLOCKS, "
          "GROUND_GRID_COLS = GROUND_GRID_COLS, GROUND_GRID_ROWS = GROUND_GRID_ROWS, "
          "GROUND_CELL = GROUND_CELL, GROUND_GAP = GROUND_GAP, GROUND_Y = GROUND_Y, "
          "BACKPACK_CAP = BACKPACK_CAP, BACKPACK_COLS = BACKPACK_COLS, "
          "BACKPACK_CELL = BACKPACK_CELL, BACKPACK_GAP = BACKPACK_GAP, "
          "BACKPACK_Y = BACKPACK_Y, CONDITIONS_Y = CONDITIONS_Y, "
          "BAG_LABEL_Y = BAG_LABEL_Y, INV_COL_X = INV_COL_X, CURSOR_DESC_Y = CURSOR_DESC_Y, INV_LOG_LINES = INV_LOG_LINES, "
          "BODY_CX = BODY_CX, BODY_TOP = BODY_TOP, BODY_BOTTOM = BODY_BOTTOM}, "
          "function() return INV_ROWS, INV_POS end\n")
(here / "lib_scavenge.lua").write_text(
    lib + "\nreturn Game, ITEM_DB, SCAVENGE_LOOT, SCAVENGE_TRIES, SCAVENGE_ROLLS, "
          "SCAVENGE_HOURS, TERRAIN\n")
(here / "lib_creator.lua").write_text(
    lib + "\nreturn Game, {ATTRIBUTES = ATTRIBUTES, TRAITS = TRAITS, ATTR_POINTS = ATTR_POINTS, "
          "ATTR_MIN = ATTR_MIN, ATTR_MAX = ATTR_MAX, recompute_stats = recompute_stats, "
          "trait_points_left = trait_points_left, attr_points_left = attr_points_left, "
          "dud_percent = dud_percent, ITEM_DB = ITEM_DB, HOLD_SLOTS = HOLD_SLOTS, "
          "POCKET_CELLS = POCKET_CELLS, BACKPACK_CAP = BACKPACK_CAP}\n")
(here / "lib_encounter.lua").write_text(
    lib + "\nreturn Game, {ITEM_DB = ITEM_DB, MAX_HEALTH = MAX_HEALTH, "
          "BLEED_PER_HOUR = BLEED_PER_HOUR, WOUND_REST_HOURS = WOUND_REST_HOURS, "
          "effective_max_mp = effective_max_mp, trait_points_left = trait_points_left, "
          "ENCOUNTERS = ENCOUNTERS, ENCOUNTER_KINDS = ENCOUNTER_KINDS, ENC_COLS = ENC_COLS, "
          "wrap = wrap, ARTIFACTS = ARTIFACTS, BOLT_N = BOLT_N, BOLT_START = BOLT_START, "
          "BOLT_GOAL = BOLT_GOAL, BOLT_HAZARDS = BOLT_HAZARDS, SEQ_LENGTHS = SEQ_LENGTHS, "
          "RUNE_N = RUNE_N, recompute_stats = recompute_stats, "
          "ENC_INTRO_COLS = ENC_INTRO_COLS, PORTRAIT_DATA = PORTRAIT_DATA, "
          "PORTRAIT_CACHE = PORTRAIT_CACHE, portrait_view = portrait_view, "
          "b64_decode = b64_decode, PORTRAIT_SIZE = PORTRAIT_SIZE}\n")
(here / "lib_crafting.lua").write_text(
    lib + "\nreturn Game, {RECIPES = RECIPES, ITEM_DB = ITEM_DB, SPRITES = SPRITES, "
          "SCAVENGE_LOOT = SCAVENGE_LOOT, KEY = KEY}\n")
(here / "lib_world.lua").write_text(
    lib + "\nreturn Game, {WORLD = WORLD, GRID_RADIUS = GRID_RADIUS, TERRAIN = TERRAIN, "
          "AXIAL_DIRS = AXIAL_DIRS, generate_world = generate_world, ITEM_DB = ITEM_DB, "
          "REST_HOURS = REST_HOURS}\n")
(here / "lib_save.lua").write_text(
    lib + "\nreturn Game, {SAVE = SAVE, KEY = KEY, generate_world = generate_world}\n")
(here / "wasteland_run.lua").write_text(src)
print("generated lib_*.lua, wasteland_run.lua")
