-- The camp screen (src/51_base.lua): T at camp opens it; slots take only
-- what belongs; the fire pit burns its fuel, the pot cooks, the rack smokes;
-- wards wear out and keep visitors off; a pelt is a bed; the workbench's
-- tools count; snares and the berry patch fill the stash; raids while away
-- (stopped by the barricade, a lockbox or the dog); news when you're back;
-- moving camp leaves the old things behind; the map wall.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, L, rows_pos = dofile("lib_layout.lua")

local function camp(built)
    local g = Game.new()
    g:start_game()
    g.no_hints = true
    local key = g.player.q .. "," .. g.player.r
    g.tiles[key] = "ruins"
    g.ground[key] = {}
    g.player.inventory = {}
    g.player.equipped.back = "backpack"
    g.base = {key = key, built = built or {}, slots = {}, barrel_hour = g.player.hours}
    g.ticked_hour = g.player.hours
    if g.base.built.barricade then g.base.wall = 100 end
    return g, key
end
local function row_of(g, kind, key)
    for i, r in ipairs(rows_pos()) do if r[1] == kind and r[2] == key then return i end end
end
local function count(list, item)
    local n = 0
    for _, s in ipairs(list) do if s.item == item then n = n + s.qty end end
    return n
end
local function pass(g, hours)
    g.player.hours = g.player.hours + hours
    g:tick()
end

print("1. T at camp opens the camp screen: every slot is a cursor row; T again: the bag")
local g, key = camp({firepit = true})
g:site_action()
assert(g.screen == "inventory" and g.camp_view)
g:draw_inventory(400, 300)
for _, s in ipairs({"fire", "pot", "bed", "ward1", "ward3", "rack", "bench1", "shelf3", "wall", "map"}) do
    assert(row_of(g, "camp", s), "slot " .. s)
end
assert(not row_of(g, "equip", "head"), "no doll on the camp screen")

print("2. a slot takes only what belongs; one that isn't built takes nothing")
g.player.inventory = {{item = "stick", qty = 5}, {item = "knife", qty = 1}, {item = "raw_fish", qty = 2}}
assert(not g:try_transfer({"inventory", 2}, {"camp", "fire"}), "a knife isn't fuel")
assert(count(g.player.inventory, "knife") == 1)
assert(g:try_transfer({"inventory", 1}, {"camp", "fire"}))
assert(g:camp_stack("fire").qty == 5 and count(g.player.inventory, "stick") == 0)
assert(not g:try_transfer({"inventory", 2}, {"camp", "rack"}), "no drying rack built")

print("3. the fire pit burns its fuel and warms the hex; the pot cooks over it")
assert(g:fire_here(), "fuel in the pit: a fire")
local fish = 0
for i, s in ipairs(g.player.inventory) do if s.item == "raw_fish" then fish = i end end
assert(g:try_transfer({"inventory", fish}, {"camp", "pot"}))
pass(g, 3)
assert(g:camp_stack("pot").item == "cooked_fish" and g:camp_stack("pot").qty == 2, "cooked")
assert(g:camp_stack("fire").qty < 5, "fuel used")
pass(g, 40)
assert(g:camp_stack("fire") == nil and not g:fire_here(), "fuel gone, the fire's out")

print("4. the rack smokes meat in a day, fire or not")
g, key = camp({rack = true})
g.base.slots.rack = {item = "strange_meat", qty = 2}
pass(g, 23)
assert(g:camp_stack("rack").item == "strange_meat")
pass(g, 1)
assert(g:camp_stack("rack").item == "smoked_meat" and g:camp_stack("rack").qty == 2)

print("5. wards keep night visitors off and wear out")
g, key = camp({bedroll = true})
local bare = g:camp_visit_chance()
g.player.inventory = {{item = "salt_circle", qty = 2}}
assert(g:try_transfer({"inventory", 1}, {"camp", "ward1"}))
assert(g:camp_stack("ward1").qty == 1 and count(g.player.inventory, "salt_circle") == 1, "one a slot")
assert(g:camp_visit_chance() < bare)
pass(g, 24 * 6)
assert(g:camp_stack("ward1") == nil, "the salt circle wore out")

print("6. a pelt in the bed slot is a bed (warm, better rest)")
g, key = camp({})
assert(not g:bed_here())
g.base.slots.bed = {item = "jawhound_pelt", qty = 1}
assert(g:bed_here())

print("7. tools on the workbench count at camp; crafting there is an hour faster")
g, key = camp({bench = true})
g.base.slots.bench1 = {item = "pliers", qty = 1}
assert(g:count_item("pliers") == 1)
local r = {hours = 3}
assert(g:craft_hours(r) == 2)
g.player.q = g.player.q + 50   -- (away from camp: the bench isn't in reach)
assert(g:count_item("pliers") == 0)

print("8. snares and the berry patch fill the stash each morning")
g, key = camp({garden = true})
g.base.slots.trap = {item = "snare", qty = 3}
g.base.slots.plot = {item = "berries", qty = 4}
g.roll = function() return true end
g.player.hours = g.player.hours - g.player.hours % 24 + 5
g.ticked_hour = g.player.hours
pass(g, 2)   -- (past 06:00)
assert(count(g.ground[key], "strange_meat") == 3 and count(g.ground[key], "berries") == 2)

print("9. raids while you're away: the barricade takes it; else the stash loses things")
g, key = camp({box = true, barricade = true})
g.ground[key] = {{item = "rope", qty = 3}}
g.roll = function() return true end
g.player.q = g.player.q + 50
g:camp_day(g.player.hours)
assert(g.base.wall < 100 and count(g.ground[key], "rope") == 3, "the wall held")
g.base.wall = 0
g:camp_day(g.player.hours)
assert(count(g.ground[key], "rope") == 2, "the box: one thing at most")
g.base.built.lockbox = true
g:camp_day(g.player.hours)
assert(count(g.ground[key], "rope") == 2, "a lockbox: nothing")
g.dog = {hp = 10, fed_hour = g.player.hours, hungry_days = 0, at_camp = true}
assert(g:raid_chance() == 0, "the dog guards")
assert(not g:dog_with_you())

print("10. back at camp: the news")
g.player.q = g.player.q - 50
g:camp_arrive()
local all = table.concat(g.log, "|")
assert(all:find("barricade") or all:find("camp"), all)
assert(g.base.news == nil)

print("11. mending the barricade; telling the dog to stay")
g, key = camp({barricade = true})
g.base.wall = 30
g.player.inventory = {{item = "scrap_metal", qty = 1}}
g:camp_action("wall")
assert(g.base.wall == 70 and count(g.player.inventory, "scrap_metal") == 0)
g.dog = {hp = 10, fed_hour = g.player.hours, hungry_days = 0}
g:camp_action("dog")
assert(not g:dog_at_camp(), "no bed for it yet")
g.base.slots.dog = {item = "cloth_scrap", qty = 1}
g:camp_action("dog")
assert(g:dog_at_camp())
g:camp_action("dog")
assert(g:dog_with_you())

print("12. one camp: claiming another leaves the old slots' things in its stash")
g, key = camp({})
g.base.slots.shelf1 = {item = "toy_car", qty = 1}
local old_key = key
g.player.q = g.player.q + 3
g.tiles[g.player.q .. "," .. g.player.r] = "ruins"
g:build_base({base = "claim", hours = 1, inputs = {}})
assert(g.base.key ~= old_key and next(g.base.slots) == nil)
assert(count(g.ground[old_key], "toy_car") == 1)

print("13. the map wall lists what you know")
g, key = camp({mapwall = true})
g:camp_action("map")
assert(g.screen == "skills" and g.page == "map")
assert(g:skills_page_lines()[1] == "Camp: here.")
g:skills_key(gfx.KEY_ESCAPE)
assert(g.screen == "inventory", "back to the camp")

print("CAMP TESTS PASSED")
