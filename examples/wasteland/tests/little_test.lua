-- The Little Ones: trinkets, cairns, warrens, the troupe and its mischief.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local LITTLE, ITEM_DB, KEY = H.LITTLE, H.ITEM_DB, H.KEY

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end
local function stand(g, key)
    local q, r = key:match("(-?%d+),(-?%d+)")
    g.player.q, g.player.r = tonumber(q), tonumber(r)
end

print("1. twelve trinkets: worthless to traders, no use but one")
assert(#LITTLE.trinkets == 12)
for _, t in ipairs(LITTLE.trinkets) do
    assert(ITEM_DB[t] and ITEM_DB[t].trinket and Game.item_value(t) == 0, t)
end
local g = fresh()
g.player.q, g.player.r = 0, 0
g.player.inventory = {{item = "crayons", qty = 1}}
g:use_item("inventory", 1)
assert(g:count_item("crayons") == 1 and g.log[#g.log]:find("cairn"), "E away from a cairn keeps it")

print("2. every world has warrens in the woods or hills, and cairns near them")
for i = 1, 20 do
    local s = i * 977 % 32768
    local tiles, _, _, rad, sites = H.generate_world(s)
    local x = Game.place_extras(tiles, sites, rad, s)
    assert(#x.warrens >= 1 and #x.cairns >= 1, "seed " .. s)
    for _, w in ipairs(x.warrens) do assert(tiles[w] == "forest" or tiles[w] == "hills") end
    for _, site in pairs(sites) do
        for _, k in ipairs(x.cairns) do assert(k ~= site) end
    end
end

print("3. a trinket left at a cairn (E or T) befriends them")
g = fresh()
local cairn = g.extras.cairns[1]
stand(g, cairn)
g.player.inventory = {{item = "crayons", qty = 1}, {item = "marble", qty = 1}}
g:use_item("inventory", 1)
assert(g.little.friend == 1 and g:count_item("crayons") == 0)
g:site_action()
assert(g.little.friend == 2 and g:count_item("marble") == 0, "T leaves one too")
g:site_action()
assert(g.little.friend == 2, "nothing left to give")

print("4. at three gifts, a warren gives you a troupe; more gifts, a bigger one")
g.player.inventory = {{item = "button", qty = 1}}
g:use_item("inventory", 1)
stand(g, g.extras.warrens[1])
assert(not g:little_arrive(), "no encounter: they come with you")
assert(g.little.n == 1 and g.little.mood == LITTLE.mood_start)
g.player.inventory = {{item = "toy_car", qty = 3}}
stand(g, cairn)
for _ = 1, 3 do g:offer_trinket() end
assert(g.little.n == 2, "six gifts: two of them")

print("5. a stranger at their warren: watch, gift (+2) or shoo (they take something)")
g = fresh()
stand(g, g.extras.warrens[1])
assert(g:little_arrive() and g.enc.def.kind == "little")
local opts = g:encounter_options()
assert(#opts == 2, "no trinket, no offer")
g.player.inventory = {{item = "jingle_bell", qty = 1}, {item = "rope", qty = 1}}
opts = g:encounter_options()
assert(#opts == 3 and opts[2][2] == "offer_little")
g:encounter_action("offer_little")
assert(g.little.friend == 2 and g.enc.over)
g:encounter_action("leave")
g:little_arrive()
g:encounter_action("shoo_little")
assert(g:count_item("rope") == 0, "they took the rope")

print("6. their mood sours without gifts; at zero they go home (one gift wins them back)")
g = fresh()
g.little = {friend = 3, n = 1, mood = 2, mood_hour = 0, seen = {}}
g.roll = function() return false end
g:little_hour(LITTLE.decay_hours)
assert(g.little.mood == 1 and g.little.n == 1)
g:little_hour(2 * LITTLE.decay_hours)
assert(g.little.n == 0 and g.little.friend == LITTLE.join_at - 1)

print("7. what they get up to: finds, hiding things (and giving some back), late giggles")
g = fresh()
g.little = {friend = 3, n = 2, mood = 9, mood_hour = 0, seen = {}}
local key = g.player.q .. "," .. g.player.r
g.ground[key] = {}
local rolls = {true}
g.roll = function() return table.remove(rolls, 1) or false end
g:little_hour(LITTLE.act_every)
assert(#g.ground[key] == 1, "a find on the ground")
-- mischief: never valuables, food or drink, medicine or tools
g.player.inventory = {{item = "weeping_stone", qty = 1}, {item = "permit", qty = 1},
                      {item = "canned_beans", qty = 1}, {item = "water_bottle", qty = 1},
                      {item = "bandage", qty = 1}, {item = "multitool", qty = 1}}
rolls = {false, true}
g:little_hour(2 * LITTLE.act_every)
assert(#g.player.inventory == 6, "nothing they may take")
g.player.inventory[#g.player.inventory + 1] = {item = "rope", qty = 1}
rolls = {false, true, true}   -- (no find, mischief, it comes back)
g:little_hour(3 * LITTLE.act_every)
assert(g:count_item("rope") == 0 and g.little.hidden and g.little.hidden.item == "rope")
g.ground[key] = {}
g:little_hour(g.little.hidden.back)
assert(#g.ground[key] == 1 and g.ground[key][1].item == "rope" and not g.little.hidden)
g.player.hours = 0
local night = 0
while not g:is_night(night) do night = night + 1 end
night = night + (LITTLE.act_every - night % LITTLE.act_every) % LITTLE.act_every
local rest = g.player.needs.rest
rolls = {false, false, true}
g:little_hour(night)
if g:is_night(night) then assert(g.player.needs.rest == rest - LITTLE.awake_rest) end

print("8. in a fight they pelt it, and they help you run (more from night horrors)")
g = fresh()
g.little = {friend = 6, n = 2, mood = 9, mood_hour = 0, seen = {}}
g:start_encounter(H.ENCOUNTERS[1])
local hp = g.enc.hp
g.roll = function() return true end
assert(not g:little_turn() and g.enc.hp < hp and g.enc.hp >= hp - 6)
assert(g:little_flee_bonus() == LITTLE.flee_bonus)
g.enc.def = {kind = "horror", who = "long man"}
assert(g:little_flee_bonus() == LITTLE.horror_run)

print("9. saved; a save from before them loads with none following")
g = fresh()
g.little = {friend = 4, n = 1, mood = 7, mood_hour = 3, seen = {[g.extras.cairns[1]] = true}}
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.little.n == 1 and g2.little.friend == 4 and g2.little.seen[g.extras.cairns[1]])
local data = Game.read_save()
data.little = nil
local g3 = Game.new()
g3:load_state(data)
assert(g3.little.n == 0 and g3.little.friend == 0)

print("10. the journal and the map show them")
local lines = table.concat(g2:journal_lines(), "\n")
assert(lines:find("Little Ones: 1 following", 1, true) and lines:find("Nearest cairn", 1, true))
g2:draw_map(400, 300)

print("LITTLE TESTS PASSED")
