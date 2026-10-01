-- Memory and draw-call check, run under the fake solaros (tests/solaros.lua).
--   cd tests && lua5.4 ../tools/perf_check.lua [max_heap_kb] [max_calls]
-- Prints heap use (after load, after a new game, peak over a random run)
-- and gfx calls per frame for every screen. With limits given, exits 1 when
-- a number goes over (run_tests.sh uses this as a regression guard).
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local MAX_HEAP, MAX_CALLS = tonumber(arg[1]), tonumber(arg[2])
-- the fake records every sprite call for the tests; don't let that count here
SPRITE_CALLS = setmetatable({}, {__newindex = function() end})

-- the fake's argument checks build a table per call; for measuring the
-- game's own garbage, swap them for no-ops (the tests keep the checks)
for _, name in ipairs({"fill_rect", "line", "rect", "text", "sprite", "bitmap", "pixel",
                       "circle", "fill_circle", "color", "font", "clear", "refresh"}) do
    if gfx[name] then gfx[name] = function() end end
end

-- count every gfx call
local calls = 0
for name, fn in pairs(gfx) do
    if type(fn) == "function" and name ~= "begin" and name ~= "size" and name ~= "getch" then
        gfx[name] = function(...) calls = calls + 1; return fn(...) end
    end
end

collectgarbage("collect")
local base = collectgarbage("count")
local src = io.open("../wasteland.lua"):read("a")
local size_kb = #src / 1024
local lib = src:sub(1, src:find("-- Main loop", 1, true) - 1) .. "\nreturn Game, KEY\n"
src = nil
local Game, KEY = load(lib, "=wasteland")()
lib = nil
collectgarbage("collect")
local loaded = collectgarbage("count") - base

local g = Game.new()
g:start_game()
collectgarbage("collect")
local with_game = collectgarbage("count") - base

-- each screen, one frame
local frames = {}
local function frame(name, draw)
    calls = 0
    draw()
    frames[#frames + 1] = {name, calls}
end
g.player.hours = 0
frame("map (day)", function() g:draw_map(400, 300) end)
g.player.hours = 14
g:refresh_view()
frame("map (night)", function() g:draw_map(400, 300) end)
for k in pairs(g.tiles) do g.player.explored[k] = true end
frame("map (all explored)", function() g:draw_map(400, 300) end)
frame("inventory", function() g:draw_inventory(400, 300) end)
g:open_crafting()
frame("crafting", function() g:draw_craft(400, 300) end)
g.screen = "map"
g:start_encounter(g:pick_encounter())
frame("encounter", function() g:draw_encounter(400, 300) end)
g.enc, g.screen = nil, "map"
frame("journal", function() g:draw_journal(400, 300) end)
frame("help", function() g:draw_help(400, 300) end)
g.player.q, g.player.r = g.sites.trader:match("(-?%d+),(-?%d+)")
g.player.q, g.player.r = tonumber(g.player.q), tonumber(g.player.r)
g:open_trade()
frame("trade", function() g:draw_trade(400, 300) end)
g.player.inventory[#g.player.inventory + 1] = {item = "lora_radio", qty = 1}
g:open_radio()
frame("radio", function() g:draw_radio(400, 300) end)

-- a random run: peak heap while playing
local peak = with_game
local g2 = Game.new()
g2:start_game()
local keys = {119, 97, 115, 100, 32, 102, 105, 10, 101, 99, 103, 106, 113, 0x80, 0x81, 0x82, 0x83}
local seed = 7
for _ = 1, 600 do
    seed = (seed * 1103515245 + 12345) % 2147483648
    local k = keys[seed % #keys + 1]
    if g2.screen == "map" then
        if k == 119 then g2:move_dir(0, -1) elseif k == 115 then g2:move_dir(0, 1)
        elseif k == 97 then g2:move_dir(-1, 0) elseif k == 100 then g2:move_dir(1, 0)
        elseif k == 32 then g2:rest() elseif k == 102 then g2:scavenge() elseif k == 103 then g2:gather() end
        g2:tick()
        g2:draw_map(400, 300)
    elseif g2.screen == "encounter" then
        g2:encounter_action(g2:encounter_options()[1][2])
        if g2.screen == "encounter" then g2:draw_encounter(400, 300) end
    elseif g2.screen == "puzzle" then
        g2:puzzle_key(KEY.Q)
    elseif g2.screen == "dead" or g2.screen == "ending" then
        g2 = Game.new(); g2:start_game()
    else
        g2.screen = "map"
    end
    if _ % 25 == 0 then   -- what's really live (garbage collected)
        collectgarbage("collect")
        peak = math.max(peak, collectgarbage("count") - base)
    end
end
collectgarbage("collect")

print(("bundle %d KB; heap: code+data %d KB, + a game %d KB, live peak while playing %d KB")
    :format(math.floor(size_kb), math.floor(loaded), math.floor(with_game), math.floor(peak)))
-- garbage made per frame (the collector has to clean this up on the device)
local function garbage(draw)
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    draw()
    local made = collectgarbage("count") - before
    collectgarbage("restart")
    return made
end
print(("garbage per frame: map %.1f KB, inventory %.1f KB, encounter %.1f KB"):format(
    garbage(function() g:draw_map(400, 300) end), garbage(function() g:draw_inventory(400, 300) end),
    garbage(function() g2:draw_map(400, 300) end)))
local worst = 0
for _, f in ipairs(frames) do
    print(("  %-20s %5d gfx calls"):format(f[1], f[2]))
    worst = math.max(worst, f[2])
end
local bad = false
if MAX_HEAP and peak > MAX_HEAP then print(("FAIL: peak heap %d KB > %d"):format(peak, MAX_HEAP)); bad = true end
if MAX_CALLS and worst > MAX_CALLS then print(("FAIL: a frame took %d calls > %d"):format(worst, MAX_CALLS)); bad = true end
if bad then os.exit(1) end
