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
-- hexes are drawn as bitmap masks (fill, outline): set those apart too
local function is_mask(c)
    for _, m in pairs(HEX_MASKS) do
        for _, part in pairs(m) do
            for _, ch in ipairs(part) do if ch[5] == c.data then return true end end
        end
    end
    return false
end
local function drop_masks()
    local n = 0
    for i = #SPRITE_CALLS, 1, -1 do
        if is_mask(SPRITE_CALLS[i]) then table.remove(SPRITE_CALLS, i); n = n + 1 end
    end
    return n
end
SPRITE_CALLS = {}
g:draw_map(400, 300)
local masks_drawn = drop_masks()
assert(masks_drawn > 100, "the hexes are drawn with masks: " .. masks_drawn)
-- you are a stick figure (7x11) on a halo (9x13): set those two apart
local figure = {}
for i = #SPRITE_CALLS, 1, -1 do
    local c = SPRITE_CALLS[i]
    if (c.w == 7 and c.h == 11) or (c.w == 9 and c.h == 13) then
        figure[#figure + 1] = table.remove(SPRITE_CALLS, i)
    end
end
assert(#figure == 2, "the player is drawn as a figure and its halo")
for _, c in ipairs(figure) do
    assert(#c.data == ((c.w + 7) // 8) * c.h and c.x + c.w <= 256, "figure fits the map")
end
local tiles = 0; for _ in pairs(g.tiles) do tiles = tiles + 1 end
-- the world is bigger than the screen: only the hexes in the map window
-- around you are drawn (plus one glyph per legend entry), never all of them
local legend = #LEGEND_ORDER
local on_map = #SPRITE_CALLS - legend
assert(on_map > 40 and on_map < tiles - 1,
       ("the map window should show a screenful of the %d hexes, drew %d"):format(tiles, on_map))
for _, c in ipairs(SPRITE_CALLS) do
    assert(c.w == GW and c.h == GH and #c.data == 20, ("odd sprite %dx%d %d bytes"):format(c.w, c.h, #c.data))
    assert(c.x >= 0 and c.y >= 0 and c.x + c.w <= 400 and c.y + c.h <= 300, "glyph off screen")
end
local map_glyphs = 0
for _, c in ipairs(SPRITE_CALLS) do if c.x + c.w <= 256 then map_glyphs = map_glyphs + 1 end end
assert(map_glyphs == on_map, "every map glyph stays inside the map area (x < 256)")
print(("4. revealed map drew %d of %d hexes + %d legend glyphs, all inside the map window"):format(on_map, tiles, legend))

-- 5. fog: an unseen tile draws nothing; an explored-only tile draws a glyph
g = Game.new()
g.player.visible = {}; g.player.explored = {}
SPRITE_CALLS = {}
g:draw_map(400, 300)
drop_masks()
assert(#SPRITE_CALLS == #LEGEND_ORDER + 2, "with nothing seen only the legend (and you) should draw, got " .. #SPRITE_CALLS)
g.player.explored["1,0"] = true
SPRITE_CALLS = {}
g:draw_map(400, 300)
drop_masks()
assert(#SPRITE_CALLS == #LEGEND_ORDER + 3, "one remembered tile should add exactly one glyph")
print("5. unseen tiles draw no glyph; remembered tiles draw one")

-- 5b. the hex masks: within gfx.bitmap's 128 bytes, the fill sits inside the
--     outline, and the outline is the six edges (every row has its sides)
for _, size in ipairs({HEX_SIZE, HEX_SIZE - 3}) do
    local m = Game.hex_mask(size)
    local box = {1e9, 1e9, -1e9, -1e9}
    for _, part in pairs(m) do
        for _, ch in ipairs(part) do
            assert(#ch[5] == ((ch[3] + 7) // 8) * ch[4] and #ch[5] <= 128, "mask chunk too big")
        end
    end
    for _, ch in ipairs(m.outline) do
        box = {math.min(box[1], ch[1]), math.min(box[2], ch[2]),
               math.max(box[3], ch[1] + ch[3]), math.max(box[4], ch[2] + ch[4])}
    end
    assert(box[4] - box[2] == 2 * size + 1, "outline spans the hex's height")
    for _, ch in ipairs(m.fill) do
        assert(ch[1] > box[1] and ch[2] > box[2] and ch[1] + ch[3] < box[3] and ch[2] + ch[4] < box[4],
               "fill stays inside the outline")
    end
end
print("5b. hex masks fit gfx.bitmap and the fill stays inside the outline")

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

print("6. weather over the map: a tile per kind (and phase) that fits gfx.bitmap; drawn only")
print("   in its weather, inside the map, under the player figure")
local Wt = GLYPHS.WEATHER
for _, kind in ipairs({"Rain", "Storm", "Snow", "Fog"}) do
    for phase = 0, 3 do
        local t = GLYPHS.weather(kind, phase)
        assert(t and #t == (Wt.w // 8) * Wt.h and #t <= 128, kind)
    end
end
assert(GLYPHS.weather("Rain", 0) ~= GLYPHS.weather("Rain", 1), "the rain moves with the hour")
assert(GLYPHS.weather("Clear", 0) == nil and GLYPHS.weather("Overcast", 0) == nil)
local function weather_calls(kind)
    local g = Game.new(); g:start_game()
    g.weather = function() return kind end
    SPRITE_CALLS = {}
    g:draw_map(400, 300)
    local n, last_weather, figure_at = 0, 0, 0
    for i, c in ipairs(SPRITE_CALLS) do
        if c.w == Wt.w and c.h == Wt.h then
            n, last_weather = n + 1, i
            assert(c.x >= 0 and c.x + c.w <= MAP_W and c.y >= MAP_TOP and c.y + c.h <= MAP_BOTTOM, "inside the map")
        elseif c.w == 7 and c.h == 11 then figure_at = i end
    end
    return n, last_weather, figure_at
end
assert(weather_calls("Clear") == 0)
local n, last, fig = weather_calls("Storm")
assert(n == (MAP_W // Wt.w) * ((MAP_BOTTOM - MAP_TOP) // Wt.h), "tiles fill the map: " .. n)
assert(fig > last, "the player is drawn over the weather")
print("   OK")

print("\nGLYPH/LEGEND TESTS PASSED")
