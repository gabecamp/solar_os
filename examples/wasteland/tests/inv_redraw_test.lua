-- The bag screen patches itself when only the cursor moves. This rasterizes
-- every draw call into a pixel canvas and checks that, after any sequence of
-- cursor moves, the patched screen is exactly what a full redraw draws.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local W, Hh = 400, 300
local canvas, color = {}, "W"
local calls = 0
local function put(x, y, v)
    if x >= 0 and x < W and y >= 0 and y < Hh then canvas[y * W + x] = v end
end
local function fill(x, y, w, h, v)
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do put(xx, yy, v) end end
end
local names = {}
for k, v in pairs(gfx) do if type(v) == "number" then names[v] = k end end
gfx.clear = function() calls = calls + 1; canvas = {} end
gfx.color = function(c) calls = calls + 1; color = names[c] or tostring(c) end
gfx.font = function() calls = calls + 1 end
gfx.refresh = function() calls = calls + 1 end
gfx.fill_rect = function(x, y, w, h) calls = calls + 1; fill(x, y, w, h, color) end
gfx.rect = function(x, y, w, h)
    calls = calls + 1
    fill(x, y, w, 1, color); fill(x, y + h - 1, w, 1, color)
    fill(x, y, 1, h, color); fill(x + w - 1, y, 1, h, color)
end
gfx.line = function(x1, y1, x2, y2)
    calls = calls + 1
    fill(math.min(x1, x2), math.min(y1, y2), math.abs(x2 - x1) + 1, math.abs(y2 - y1) + 1, color)
end
gfx.text = function(x, y, s)
    calls = calls + 1
    for i = 1, #s do fill(x + (i - 1) * 7, y - 10, 7, 11, color .. s:sub(i, i)) end
end
gfx.sprite = function(x, y, w, h, data)
    calls = calls + 1
    local stride = (w + 7) // 8
    for row = 0, h - 1 do
        for col = 0, w - 1 do
            local byte = data:byte(row * stride + col // 8 + 1)
            if byte & (1 << (col % 8)) ~= 0 then put(x + col, y + row, color) end
        end
    end
end

-- (loaded after the canvas is in place: the game keeps its own reference
-- to gfx.sprite from load time)
local Game, H = dofile("lib_hunt.lua")
local KEY = H.KEY

local function snapshot()
    local copy = {}
    for k, v in pairs(canvas) do copy[k] = v end
    return copy
end
local function same(a, b)
    for k, v in pairs(a) do if b[k] ~= v and not (v == "WHITE" and b[k] == nil) then return false, k end end
    for k, v in pairs(b) do if a[k] ~= v and not (v == "WHITE" and a[k] == nil) then return false, k end end
    return true
end
local function full_draw(g)
    local saved = g.inv_drawn
    g.inv_drawn = nil
    canvas = {}
    g:draw_inventory(W, Hh)
    local s = snapshot()
    g.inv_drawn = saved
    return s
end

local function check_moves(g, label, keys)
    canvas = {}
    g.inv_drawn = nil
    g:draw_inventory(W, Hh)
    local patched_calls, worst = 0, 0
    for n, key in ipairs(keys) do
        if key == "up" then
            g.inv_cursor = math.max(1, g.inv_cursor - 1)
        else
            g.inv_cursor = math.min(#H.inv_rows(), g.inv_cursor + 1)
        end
        calls = 0
        g:draw_inventory(W, Hh)
        worst = math.max(worst, calls)
        local patched = snapshot()
        local scrolled = g.inv_drawn and g.inv_drawn.cursor ~= g.inv_cursor
        local whole = full_draw(g)
        local ok, at = same(patched, whole)
        if not ok then
            error(("%s: move %d (cursor %d) differs at x %d y %d: %s vs %s"):format(label, n,
                g.inv_cursor, at % W, at // W, tostring(patched[at]), tostring(whole[at])))
        end
        canvas = patched
    end
    print(("   %s: %d moves match a full redraw; worst move %d draw calls"):format(label, #keys, worst))
    return worst
end

local function walk(n)
    local keys = {}
    for i = 1, n do keys[i] = "down" end
    for i = 1, n do keys[#keys + 1] = "up" end
    return keys
end

print("1. a fresh survivor: every cell, slot and back again")
local g = Game.new()
g:start_game()
g.screen = "inventory"
g.inv_cursor = 1
local worst = check_moves(g, "fresh", walk(40))
assert(worst < 120, "a cursor move should be cheap: " .. worst)

print("2. worn gear, a full bag, a selected item, and enough on the ground to scroll")
g.player.equipped.head = "cap"
g.player.equipped.jacket = "jacket"
g.player.equipped.pants = g.player.equipped.pants or "jeans"
g.player.equipped.rhand = "knife"
g.player.inventory = {}
for i = 1, 8 do g.player.inventory[i] = {item = (i % 2 == 0) and "rock" or "stick", qty = i} end
local key = g.player.q .. "," .. g.player.r
g.ground[key] = {}
for i = 1, 14 do g.ground[key][i] = {item = "cloth_scrap", qty = i} end
g.inv_cursor = 1
g.inv_selected = {"inventory", 2}
check_moves(g, "busy", walk(45))
g.inv_selected = {"equip", "jacket"}
check_moves(g, "slot selected", walk(45))

print("3. a change other than the cursor redraws everything")
g.inv_drawn = nil
canvas = {}
g:draw_inventory(W, Hh)
g:push_log("Something happened.")
calls = 0
g:draw_inventory(W, Hh)
assert(calls > 300, "a new log line must redraw the screen: " .. calls)

print("4. nothing changed: nothing is drawn")
calls = 0
g:draw_inventory(W, Hh)
assert(calls == 0, tostring(calls))

print("5. another screen in between forgets the patched state")
g.inv_drawn = {sig = "x", cursor = 1}
local main = io.open("../src/90_main.lua"):read("a")
assert(main:find('if game.screen ~= "inventory" then game.inv_drawn = nil end', 1, true))

print("6. the doll drawn as bitmap tiles is the rect doll, pixel for pixel")
local outfits = {
    {},
    {head = "cap", jacket = "jacket", pants = "jeans", feet = "boots"},
    {shirt = "tshirt", pants = "jeans", belt = "leather_belt", hands = "gloves", eyes = "sunglasses",
     ears = "earmuffs", neck = "scarf", wrists = "bracers", back = "backpack"},
}
for n, outfit in ipairs(outfits) do
    g = Game.new()
    g:start_game()
    g.player.equipped = {}
    for slot, item in pairs(outfit) do g.player.equipped[slot] = item end
    canvas = {}
    g:draw_silhouette()
    local rects = snapshot()
    canvas = {}
    calls = 0
    g:draw_doll()
    local tiled_calls = calls
    local ok, at = same(rects, snapshot())
    assert(ok, ("outfit %d differs at x %d y %d"):format(n, (at or 0) % W, (at or 0) // W))
    for _, tile in ipairs(g:doll_tiles()) do
        assert(#tile[6] == ((tile[4] + 7) // 8) * tile[5] and #tile[6] <= 128, "tile too big")
    end
    print(("   outfit %d: %d calls for the tiled doll"):format(n, tiled_calls))
    assert(tiled_calls < 120, tostring(tiled_calls))
end
local first = g:doll_tiles()
assert(g:doll_tiles() == first, "cached while the clothes stay the same")
g.player.equipped.head = "cap"
assert(g:doll_tiles() ~= first, "rebuilt when they change")

print("INVENTORY REDRAW TESTS PASSED")
