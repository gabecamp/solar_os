-- Scavenging: loot tables are valid, a search costs MP + hours, finds land on
-- the ground here, tiles run dry, and the F key is wired on the map screen.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, ITEM_DB, LOOT, TRIES, ROLLS, HOURS, TERRAIN = dofile("lib_scavenge.lua")

print("1. every passable terrain has a loot table of real items")
for id, t in pairs(TERRAIN) do
    if t.passable then assert(LOOT[id], id .. " has no loot table") end
end
for terrain, table_ in pairs(LOOT) do
    for _, entry in ipairs(table_) do
        assert(entry[1] == "nothing" or ITEM_DB[entry[1]], terrain .. ": unknown item " .. entry[1])
        assert(math.type(entry[2]) == "integer" and entry[2] > 0)
    end
end
print("   OK")

local function fresh(terrain)
    local g = Game.new()
    g.player.q, g.player.r = 0, 0
    g.tiles["0,0"] = terrain
    g.ground["0,0"] = {}
    return g
end
local function count(list)
    local n = 0
    for _, s in ipairs(list) do n = n + s.qty end
    return n
end

print("2. a search costs " .. HOURS .. " MP and " .. HOURS .. "h, drops at most " .. ROLLS .. " items here")
local g = fresh("forest")
local mp, hrs, hunger = g.player.mp, g.player.hours, g.player.needs.hunger
g:scavenge()
assert(g.player.mp == mp - HOURS and g.player.hours == hrs + HOURS)
assert(g.player.needs.hunger < hunger, "searching should cost needs like walking")
assert(count(g:ground_list()) <= ROLLS)
assert(g:scavenge_left() == TRIES - 1)
print("   OK")

print("3. tiles run dry after " .. TRIES .. " searches; no MP means no search")
g = fresh("plains")
for _ = 1, TRIES do g.player.mp = 2; g:scavenge() end
local before = count(g:ground_list())
g.player.mp = 2
g:scavenge()
assert(g.player.mp == 2 and count(g:ground_list()) == before, "a picked-clean tile must not cost or give")
assert(g.log[#g.log] == "This area is picked clean.")
g = fresh("hills")
g.player.mp = 0
g:scavenge()
assert(g:scavenge_left() == TRIES and g.log[#g.log] == "Too tired to search. Rest first.")
print("   OK")

print("4. over many searches each terrain yields its own loot, and every entry turns up")
for terrain, table_ in pairs(LOOT) do
    local seen = {}
    local g2 = fresh(terrain)
    for _ = 1, 400 do
        g2.scavenged = {}
        g2.player.mp = 2
        g2:scavenge()
    end
    for _, s in ipairs(g2:ground_list()) do seen[s.item] = true end
    for _, entry in ipairs(table_) do
        if entry[1] ~= "nothing" then assert(seen[entry[1]], terrain .. " never gave " .. entry[1]) end
    end
    for item in pairs(seen) do
        local listed = false
        for _, entry in ipairs(table_) do if entry[1] == item then listed = true end end
        assert(listed, terrain .. " gave " .. item .. " which isn't in its table")
    end
end
print("   OK")

print("5. F on the map screen scavenges (real main loop)")
local i, texts = 0, {}
local keys = {102}
local saved_getch, saved_exit, saved_text = gfx.getch, fake.should_exit, gfx.text
gfx.getch = function() i = i + 1; if i > #keys then return 113 end; return keys[i] end
fake.should_exit = function() return i > #keys + 5 end
gfx.text = function(x, y, s) texts[#texts + 1] = s end
dofile("wasteland_run.lua")
gfx.getch, fake.should_exit, gfx.text = saved_getch, saved_exit, saved_text
local hit = false
for _, s in ipairs(texts) do
    if s:find("^Found") or s:find("Found nothing") then hit = true end
end
assert(hit, "F did not scavenge")
print("   OK")

print("\nSCAVENGE TESTS PASSED")
