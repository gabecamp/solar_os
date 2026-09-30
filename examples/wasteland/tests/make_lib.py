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
          "LEGEND_ORDER, LEGEND_Y, MAP_TOP, HEX_SIZE\n")
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
          "INV_LOG_LINES = INV_LOG_LINES, INV_LOG_BOTTOM = INV_LOG_BOTTOM, "
          "INV_LOG_STEP = INV_LOG_STEP, POCKET_CELLS = POCKET_CELLS, "
          "HAND_SLOTS = HAND_SLOTS, recompute_stats = recompute_stats, "
          "TRAITS = TRAITS, ATTRIBUTES = ATTRIBUTES, ITEM_DB = ITEM_DB, "
          "attr_points_left = attr_points_left, trait_budget = trait_budget, "
          "CREATOR_ROWS = CREATOR_ROWS, "
          "BODY_CX = BODY_CX, BODY_TOP = BODY_TOP, BODY_BOTTOM = BODY_BOTTOM}, "
          "function() return INV_ROWS, INV_POS end\n")
(here / "lib_scavenge.lua").write_text(
    lib + "\nreturn Game, ITEM_DB, SCAVENGE_LOOT, SCAVENGE_TRIES, SCAVENGE_ROLLS, "
          "SCAVENGE_HOURS, TERRAIN\n")
(here / "wasteland_run.lua").write_text(src)
print("generated lib_*.lua, wasteland_run.lua")
