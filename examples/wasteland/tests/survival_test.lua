-- Water and the survival loop: bottles as containers, filling at rivers,
-- drinking from them, boiling, rain, getting sick, spoilage, and hunger and
-- thirst that hurt.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()

local Game, S = dofile("lib_survive.lua")
local SURVIVE, ITEM_DB = S.SURVIVE, S.ITEM_DB

local function key(q, r) return q .. "," .. r end
local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function fresh()
    local g = Game.new()
    g:start_game()
    g.rad = {}                       -- keep radiation out of these numbers
    g.player.q, g.player.r = 0, 0
    g.ticked_hour = g.player.hours
    return g
end
local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    for slot, it in pairs(g.player.equipped) do if it == item then n = n + 1 end end
    return n
end
local function inv_index(g, item)
    for i, s in ipairs(g.player.inventory) do if s.item == item then return i end end
end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end
-- a passable hex next to water that isn't a ford, so filling works
local function by_water(g)
    for k, t in pairs(g.tiles) do
        if t == "plains" or t == "forest" or t == "hills" then
            local q, r = parse(k)
            for _, d in ipairs({{1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1}}) do
                if g.tiles[key(q + d[1], r + d[2])] == "water" then return q, r end
            end
        end
    end
end
local function no_sickness(f)
    local saved = {}
    for id, def in pairs(ITEM_DB) do saved[id] = def.sick; def.sick = nil end
    f()
    for id, v in pairs(saved) do ITEM_DB[id].sick = v end
end

print("1. drinking leaves the empty bottle: in the bag, or in the hand that held it")
no_sickness(function()
    local g = fresh()
    g.player.inventory = {{item = "water_bottle", qty = 2}}
    g:use_item("inventory", 1)
    assert(count(g, "water_bottle") == 1 and count(g, "empty_bottle") == 1)
    g.player.inventory = {}
    g.player.equipped.rhand = "water_bottle"
    g:use_item("equip", "rhand")
    assert(g.player.equipped.rhand == "empty_bottle")
end)

print("2. E on the map: nothing away from water; fills every empty by a river")
local g = fresh()
g.player.q, g.player.r = 0, 0
local near = g:near_water()
if not near then
    g:water_action()
    assert(has_log(g, "No water"))
end
g.player.q, g.player.r = by_water(g)
assert(g:near_water())
g.player.inventory = {{item = "empty_bottle", qty = 2}, {item = "dirty_water", qty = 1}}
g.player.equipped.lhand = "empty_bottle"
local hours = g.player.hours
g:water_action()
assert(count(g, "dirty_water") == 4 and count(g, "empty_bottle") == 0)
assert(#g.player.inventory == 1, "merged into one stack")
assert(g.player.hours == hours, "filling is quick")

print("3. no bottles: drink straight from the river (an hour, maybe sick)")
no_sickness(function()
    g.player.inventory, g.player.equipped.lhand = {}, nil
    g.player.needs.thirst = 20
    g:water_action()
    assert(g.player.hours == hours + SURVIVE.drink_hours)
    assert(g.player.needs.thirst > 20 + SURVIVE.drink_here - 5)
end)

print("4. Boil Water at a fire makes it clean")
g = fresh()
local boil
for _, r in ipairs(S.RECIPES) do if r.id == "boil" then boil = r end end
assert(boil and boil.known and boil.fire)
g.player.inventory = {{item = "dirty_water", qty = 1}}
assert(not g:craft(boil), "needs a fire")
g.camps[key(0, 0)] = {until_hour = g.player.hours + 12}
assert(g:craft(boil))
assert(count(g, "water_bottle") == 1 and count(g, "dirty_water") == 0)

print("5. sickness: from risky food/water, costs needs and HP per hour, then passes")
g = fresh()
ITEM_DB.dirty_water.sick = 100
g.player.inventory = {{item = "dirty_water", qty = 1}}
g:use_item("inventory", 1)
ITEM_DB.dirty_water.sick = 40
local sick = g.player.sick_hours
assert(sick and sick >= SURVIVE.sick_hours[1] and sick <= SURVIVE.sick_hours[2], tostring(sick))
assert(g:current_conditions():find("Sick"))
local p = g.player
p.needs.thirst, p.needs.hunger, p.health = 90, 90, 100
g:survive_hour()
assert(p.needs.thirst == 90 - SURVIVE.sick.thirst and p.needs.hunger == 90 - SURVIVE.sick.hunger)
assert(p.health == 100 - SURVIVE.sick.hurt)
p.sick_hours = 1
g:survive_hour()
assert(p.sick_hours == 0 and has_log(g, "sickness passes"))
local rolls, n = 0, 400
local gg = fresh()   -- (one world; only the roll and the sickness are reset)
for _ = 1, n do
    gg.seed = rolls * 7 + _ * 131
    gg.player.sick_hours = 0
    gg.player.inventory = {{item = "rotten_meat", qty = 1}}
    gg:use_item("inventory", 1)
    if (gg.player.sick_hours or 0) > 0 then rolls = rolls + 1 end
end
print(("   rotten meat made you sick %d/%d times (%d%% set)"):format(rolls, n, ITEM_DB.rotten_meat.sick))
assert(math.abs(rolls / n * 100 - ITEM_DB.rotten_meat.sick) < 10)

print("6. at 0 thirst or hunger you lose HP each hour, and it can kill")
g = fresh()
p = g.player
p.needs.thirst, p.needs.hunger, p.health = 0, 50, 100
g:survive_hour()
assert(p.health == 100 - SURVIVE.thirst_hurt)
p.needs.hunger = 0
g:survive_hour()
assert(p.health == 100 - 2 * SURVIVE.thirst_hurt - SURVIVE.hunger_hurt)
p.health = 1
p.hours = p.hours + 1
g:tick()
assert(g.screen == "dead" and g.death_cause:find("thirst"), tostring(g.death_cause))

print("7. meat goes bad over time, in the bag and in a hand")
g = fresh()
p = g.player
p.inventory = {{item = "cooked_meat", qty = 10}}
p.equipped.rhand = "strange_meat"
p.needs.thirst, p.needs.hunger = 100, 100
for _ = 1, 72 do
    p.needs.thirst, p.needs.hunger, p.health = 100, 100, 100
    p.hours = p.hours + 1
    g:tick()
end
assert(count(g, "rotten_meat") >= 2, "rotten: " .. count(g, "rotten_meat"))
assert(count(g, "cooked_meat") + count(g, "rotten_meat") + count(g, "strange_meat") == 11,
       "nothing lost or made up")
assert(has_log(g, "went bad") or count(g, "rotten_meat") > 0)

print("8. resting in the rain fills empty bottles with clean water")
g = fresh()
g.weather = function() return "Rain" end
g.player.inventory = {{item = "empty_bottle", qty = 2}}
g.player.mp = 0
g:rest()
assert(count(g, "water_bottle") == 2 and has_log(g, "rain filled 2"))

print("9. new items have sprites; bottles turn up in loot; E is on the map")
for _, id in ipairs({"empty_bottle", "dirty_water", "rotten_meat"}) do
    assert(ITEM_DB[id] and S.SPRITES[id], id)
end
local loot = {}
for _, t in pairs(S.SCAVENGE_LOOT) do for _, e in ipairs(t) do loot[e[1]] = true end end
assert(loot.empty_bottle)
local src = io.open("wasteland_run.lua"):read("a")
assert(src:find("game:water_action()", 1, true) and src:find("E:water", 1, true))

print("10. bleeding clots on its own; a starving body doesn't heal while resting")
g = fresh()
g.player.injuries.bleeding = true
for _ = 1, SURVIVE.clot_hours do g:survive_hour() end
assert(not g.player.injuries.bleeding and has_log(g, "bleeding slows"))
g = fresh()
g.player.needs.hunger, g.player.health, g.player.mp = 0, 50, 0
g:rest()
assert(g.player.health == 50, "healed while starving: " .. g.player.health)
g.player.needs.hunger, g.player.mp = 80, 0
g:rest()
assert(g.player.health > 50, "fed: heals")

print("SURVIVAL TESTS PASSED")
