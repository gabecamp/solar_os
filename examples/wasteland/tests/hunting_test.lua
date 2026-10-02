-- Hunting, fishing and snares.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local HUNT = H.HUNT

local function key(q, r) return q .. "," .. r end
local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function fresh()
    local g = Game.new()
    g:start_game()
    g.ticked_hour = g.player.hours
    return g
end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end
local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    return n
end
-- a hex of `terrain`, next to water or not
local function find(g, terrain, by_water)
    for k, t in pairs(g.tiles) do
        if t == terrain then
            g.player.q, g.player.r = parse(k)
            if g:near_water() == by_water then return k end
        end
    end
    error("no " .. terrain .. (by_water and " by water" or ""))
end

print("1. G away from water hunts: 1 MP and " .. HUNT.hunt_hours .. "h, maybe an animal you've studied")
local g = fresh()
find(g, "forest", false)
local saved = HUNT.hunt_chance
HUNT.hunt_chance = 0
local mp, hours = g.player.mp, g.player.hours
g:gather()
assert(g.player.mp == mp - 1 and g.player.hours == hours + HUNT.hunt_hours)
assert(has_log(g, "old prints") and g.screen == "map")
HUNT.hunt_chance = 1000
g:gather()
HUNT.hunt_chance = saved
assert(g.screen == "encounter" and g.enc.def.kind == "animal")
assert(g.enc.seen and g.enc.aim == H.FIGHT.WATCH_AIM, "you found it first")

print("2. out of MP, nothing; water without a rod says so")
g = fresh()
g.player.mp = 0
g:gather()
assert(has_log(g, "Too tired"))
g = fresh()
find(g, "ford", true)
g:gather()
assert(has_log(g, "No rod"))

print("3. fishing with a rod by water")
g = fresh()
find(g, "plains", true)
g.player.inventory = {{item = "fishing_rod", qty = 1}}
g.karl_next = 1e9   -- Karl can turn up while you fish; not in this test
saved = HUNT.fish_chance
HUNT.fish_chance = 1000
hours = g.player.hours
g:gather()
HUNT.fish_chance = saved
assert(count(g, "raw_fish") == 1 and g.player.hours == hours + HUNT.fish_hours)
assert(g.screen == "map", "fishing never starts a fight")

print("4. snares: set with E, empty at first, catch over time")
g = fresh()
local k = find(g, "forest", false)
g.player.inventory = {{item = "snare", qty = 2}}
g:use_item("inventory", 1)
assert(g.snares[k] and count(g, "snare") == 1)
g:use_item("inventory", 1)
assert(has_log(g, "already a snare") and count(g, "snare") == 1)
g:check_snare()
assert(has_log(g, "snare is empty"), "no time passed")
g.player.hours = g.player.hours + 500
g:check_snare()
assert(has_log(g, "two%-headed hare"))
local meat = 0
for _, s in ipairs(g:ground_list()) do if s.item == HUNT.snare_catch[1] then meat = meat + s.qty end end
assert(meat >= HUNT.snare_catch[2])
assert(g.snares[k].set == g.player.hours, "reset after a catch")
g = fresh()
find(g, "ford", true)
g.player.inventory = {{item = "snare", qty = 1}}
g:use_item("inventory", 1)
assert(count(g, "snare") == 1 and has_log(g, "Nothing would walk"))

print("5. recipes known, items drawn, fish cooks at a fire")
g = fresh()
for _, id in ipairs({"fishing_rod", "snare", "cook_fish"}) do assert(g.known[id], id) end
for _, id in ipairs({"fishing_rod", "snare", "raw_fish", "cooked_fish"}) do assert(H.SPRITES[id], id) end
local cook
for _, r in ipairs(H.RECIPES) do if r.id == "cook_fish" then cook = r end end
g.player.inventory = {{item = "raw_fish", qty = 1}}
g.camps[key(g.player.q, g.player.r)] = {until_hour = g.player.hours + 5}
assert(g:craft(cook) and count(g, "cooked_fish") == 1)

print("6. snares are saved")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
k = find(g, "forest", false)
g.snares[k] = {set = 3}
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.snares[k] and g2.snares[k].set == 3)

print("HUNTING TESTS PASSED")
