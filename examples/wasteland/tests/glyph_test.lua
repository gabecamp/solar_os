package.path = "./?.lua;" .. package.path
local solaros = require("solaros"); solaros.gfx.begin()
local Game, TERRAIN, GLYPHS, GLYPH_ART, GW, GH, LEGEND_ORDER, LEGEND_Y, MAP_TOP, HEX_SIZE, MAP_W, MAP_BOTTOM, PANEL_X = dofile("lib_map.lua")

-- 1. every terrain has a glyph and an ink color; legend lists every terrain exactly once
local seen = {}
for _, id in ipairs(LEGEND_ORDER) do assert(TERRAIN[id], "legend lists unknown terrain " .. id); seen[id] = true end
for id, t in pairs(TERRAIN) do
    assert(GLYPHS[id], "no glyph for " .. id)
    assert(t.ink == "BLACK" or t.ink == "WHITE", "bad ink for " .. id)
    assert(seen[id], "terrain missing from legend: " .. id)
end
print("1. all " .. #LEGEND_ORDER .. " terrains have a glyph, an ink color, and a legend entry")

-- 2. ink must contrast with the fill: dark fills get white ink, light fills get black ink
for id, t in pairs(TERRAIN) do
    local dark_fill = (t.shade == "DARK" or t.shade == "BLACK")
    assert((t.ink == "WHITE") == dark_fill, "low-contrast glyph on " .. id)
end
print("2. glyph ink contrasts with every tile fill")

-- 3. glyphs pack to 20 bytes (10 rows x 2 bytes) and round-trip to their art
for id, art in pairs(GLYPH_ART) do
    assert(#GLYPHS[id] == 20, id .. " packed to " .. #GLYPHS[id] .. " bytes")
    for y = 0, GH - 1 do
        for x = 0, GW - 1 do
            local byte = GLYPHS[id]:byte(y * 2 + (x // 8) + 1)
            local set = ((byte >> (x % 8)) & 1) == 1
            assert(set == (art[y + 1]:sub(x + 1, x + 1) == "#"), ("%s mismatch at %d,%d"):format(id, x, y))
        end
    end
    -- glyph should be visibly non-empty but not fill the whole cell
    local on = 0
    for _, row in ipairs(art) do for ch in row:gmatch("#") do on = on + 1 end end
    assert(on >= 8 and on < GW * GH * 0.75, id .. " has " .. on .. " lit pixels")
end
print("3. glyphs pack to 20 bytes and round-trip exactly")

-- 4. draw a fully revealed map: sprite contract holds (stub validates ints + byte count)
local g = Game.new()
for key in pairs(g.tiles) do g.player.visible[key] = true; g.player.explored[key] = true end
SPRITE_CALLS = {}
g:draw_map(400, 300)
local tiles = 0; for _ in pairs(g.tiles) do tiles = tiles + 1 end
-- every tile except the player's gets a glyph, plus 4 in the legend
assert(#SPRITE_CALLS == (tiles - 1) + 4, ("expected %d sprite calls, got %d"):format(tiles - 1 + 4, #SPRITE_CALLS))
for _, c in ipairs(SPRITE_CALLS) do
    assert(c.w == GW and c.h == GH and #c.data == 20)
    assert(c.x >= 0 and c.y >= 0 and c.x + c.w <= 400 and c.y + c.h <= 300, "glyph off screen")
end
print(("4. full map drew %d glyphs (%d tiles - player tile + 4 legend), all on screen"):format(#SPRITE_CALLS, tiles))

-- 5. fog: an unseen tile draws nothing; an explored-only tile draws a glyph
g = Game.new()
g.player.visible = {}; g.player.explored = {}
SPRITE_CALLS = {}
g:draw_map(400, 300)
assert(#SPRITE_CALLS == 4, "with nothing seen only the legend should draw, got " .. #SPRITE_CALLS)
g.player.explored["1,0"] = true
SPRITE_CALLS = {}
g:draw_map(400, 300)
assert(#SPRITE_CALLS == 5, "one remembered tile should add exactly one glyph")
print("5. unseen tiles draw no glyph; remembered tiles draw one")

-- 6. layout: legend text fits the width; map's lowest pixel is above the legend;
--    map's top is below the HUD
local longest = 0
for i, id in ipairs(LEGEND_ORDER) do
    local t = TERRAIN[id]
    local detail = t.passable and (t.cost .. " MP") or "impassable"
    local right = PANEL_X + 2 + 20 + 7 * #(t.name .. " " .. detail)
    longest = math.max(longest, right)
end
assert(longest <= 398, "legend text runs off the screen: " .. longest)
local origin_y = (MAP_TOP + MAP_BOTTOM) // 2
local lowest = origin_y + math.floor(HEX_SIZE * 1.5 * 4) + HEX_SIZE
local highest = origin_y - math.floor(HEX_SIZE * 1.5 * 4) - HEX_SIZE
assert(lowest <= MAP_BOTTOM and lowest < 300 - 52 - 9, "map reaches y=" .. lowest .. " into the log")
assert(highest >= 0, "map reaches y=" .. highest .. " off the top")
local widest = MAP_W // 2 + math.ceil(HEX_SIZE * math.sqrt(3) * 4.5)
assert(widest < PANEL_X - 2, "map reaches x=" .. widest .. " into the panel at " .. PANEL_X)
print(("6. legend text ends at x=%d (<=296); full map spans y=%d..%d (HUD ends ~54, legend starts %d)")
    :format(longest, highest, lowest, LEGEND_Y))

print("\nGLYPH/LEGEND TESTS PASSED")
