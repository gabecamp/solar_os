--[[
Wasteland Survivor - a NEO Scavenger-style hex survival game for SolarOS.

Written for a small monochrome landscape display (400x300, the Waveshare
RLCD's logical size under SolarOS) with no polygon-fill primitive - hex
tiles are drawn as outlines (gfx.line x6) with an optional gfx.fill_rect
bounding-box wash underneath for shading, rather than the isometric 3D
block look used in the desktop/Pi version of this game. That's a
deliberate simplification for this hardware, not a missing feature.

Controls:
  Arrows / WASD   - move on the map screen; on the inventory screen any
                    direction steps the cursor (ground, body top-down, bag)
  Space           - rest (map screen)
  F               - scavenge the tile you're on (1 MP, 1 hour; finds go on
                    the ground here - open the inventory to pick them up)
  Enter / Space   - inventory: pick up the item under the cursor, then press
                    again on a ground cell, bag cell or body slot to move it
  E               - inventory: use the item under the cursor - eat/drink one,
                    wear it, hold it in a free hand, or take it off; on a
                    Cloth Scrap while bleeding: bandage the wound
  1-7 / Up,Dn,Enter - encounter screen: pick a choice (moving can run you
                    into animals, mutants, bandits or, rarely, a helper;
                    hold a weapon in a hand to fight with it)
  C               - map or inventory: crafting. Up/Dn pick a recipe, Enter
                    makes it (uses items from your bag, hands and the ground
                    here), C/Esc goes back. Scrawled Notes (E) teach recipes.
  I               - toggle inventory screen
  (time)          - the HUD shows day, hour and weather. Nights (20:00-06:00)
                    cut your sight unless you hold a Torch; rain, cold snaps
                    and nights chill you unless your clothes are warm enough
                    or you're by a campfire (build one with C)
  Q / ESC         - quit

A new game opens on the character creator: Up/Down pick a row, Left/Right
change an attribute, Space toggles a trait, Enter starts. You get 5 trait
points; negative traits give more. Health 0 ends the run (death screen,
Enter makes a new survivor).

This is a single self-contained script, matching the SolarOS Playground
convention (see the bundled Snake example) - no extra require()s beyond
the built-in `solaros` module.
]]

local solaros = require("solaros")
local gfx = solaros.gfx
local audio = solaros.audio

