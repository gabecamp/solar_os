-- Crafting: recipes are well-formed, making something uses exactly its
-- inputs (from bag, hands and ground) and keeps its tools, fire recipes need
-- a lit campfire, unknown recipes wait for Scrawled Notes, time is charged,
-- and C works from the real main loop.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, C = dofile("lib_crafting.lua")

local function fresh()
    local g = Game.new()
    g:start_game()
    g.player.inventory = {}
    g.ground[g.player.q .. "," .. g.player.r] = {}
    g.player.equipped.lhand, g.player.equipped.rhand = nil, nil
    return g
end
local function find(g, id)
    for _, r in ipairs(C.RECIPES) do if r.id == id then return r end end
    error("no recipe " .. id)
end
local function bag_count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    return n
end

print("1. every recipe uses real items, has an icon for what it makes, and some start known")
local known, unknown = 0, 0
for _, r in ipairs(C.RECIPES) do
    for item, qty in pairs(r.inputs) do
        assert(C.ITEM_DB[item], r.id .. ": unknown input " .. item)
        assert(math.type(qty) == "integer" and qty > 0)
    end
    for _, t in ipairs(r.tools or {}) do assert(C.ITEM_DB[t], r.id .. ": unknown tool " .. t) end
    assert(r.out or r.place or r.base or r.mend, r.id .. " makes nothing")
    if r.out then
        assert(C.ITEM_DB[r.out[1]] and C.SPRITES[r.out[1]], r.id .. ": output has no item/icon")
    end
    assert(r.hours and r.hours > 0)
    if r.known then known = known + 1 else unknown = unknown + 1 end
end
assert(known > 0 and unknown > 0)
print("   OK (" .. known .. " known at start, " .. unknown .. " to learn)")

print("2. making a torch uses exactly one stick and one cloth, from wherever they are")
local g = fresh()
g.player.inventory = {{item = "stick", qty = 2}}
g.player.equipped.rhand = "cloth_scrap"
local hours, hunger = g.player.hours, g.player.needs.hunger
assert(g:craft(find(g, "torch")))
assert(bag_count(g, "stick") == 1 and g.player.equipped.rhand == nil)
assert(bag_count(g, "torch") == 1)
assert(g.player.hours == hours + 1 and g.player.needs.hunger < hunger, "crafting takes time")
print("   OK")

print("3. ground is used before the bag; a missing input is refused and nothing is used")
g = fresh()
g.player.inventory = {{item = "cloth_scrap", qty = 1}}
table.insert(g:ground_list(), {item = "cloth_scrap", qty = 1})
assert(g:craft(find(g, "bandage")))
assert(#g:ground_list() == 0 and bag_count(g, "cloth_scrap") == 0 and bag_count(g, "bandage") == 1)
local before = g.player.hours
assert(not g:craft(find(g, "bandage")), "no cloth left")
assert(g.player.hours == before, "a refused craft takes no time")
print("   OK")

print("4. tools stay; unknown recipes wait for notes; notes teach them")
g = fresh()
g.player.inventory = {{item = "stick", qty = 1}, {item = "rope", qty = 1}, {item = "knife", qty = 1}}
assert(not g:craft(find(g, "spear")), "spear isn't known yet")
g.known.spear = true
assert(g:craft(find(g, "spear")))
assert(bag_count(g, "knife") == 1, "the knife is a tool, not used up")
assert(bag_count(g, "spear") == 1 and bag_count(g, "stick") == 0 and bag_count(g, "rope") == 0)
g = fresh()
g.sites_known.checkpoint = true   -- otherwise some notes sketch the way out instead
local n_before = #g:known_recipes()
g.player.inventory = {{item = "scrawled_notes", qty = 2}}
g:use_item("inventory", 1)
-- a note teaches one recipe, or (1 in 4) marks a stash instead
assert(#g:known_recipes() == n_before + 1 or (#g:known_recipes() == n_before and next(g.stashes)),
       "notes teach one recipe")
assert(bag_count(g, "scrawled_notes") == 1, "and are used up")
for _ = 1, 40 do g:read_notes() end   -- some mark stashes instead
assert(#g:known_recipes() == #C.RECIPES, "enough notes teach everything")
assert(g:read_notes() and next(g.stashes), "then the notes mark stashes instead")
print("   OK")

print("5. campfire: built on the tile, cooking needs it, it burns out")
g = fresh()
g.player.inventory = {{item = "strange_meat", qty = 1}}
assert(not g:craft(find(g, "cook")), "no fire yet")
g.player.inventory = {{item = "stick", qty = 3}, {item = "rock", qty = 1}, {item = "strange_meat", qty = 1}}
assert(g:craft(find(g, "campfire")) and g:fire_here())
assert(not g:craft(find(g, "campfire")), "one fire per tile")
assert(g:craft(find(g, "cook")) and bag_count(g, "cooked_meat") == 1)
g.player.hours = g.player.hours + C.RECIPES.campfire_hours
assert(not g:fire_here(), "the fire burns out")
print("   OK")

print("6. a bandage stops bleeding and heals")
g = fresh()
g.player.injuries.bleeding, g.player.health = true, 50
g.player.inventory = {{item = "bandage", qty = 1}}
g:use_item("inventory", 1)
assert(not g.player.injuries.bleeding and g.player.health == 65 and #g.player.inventory == 0)
print("   OK")

print("7. sticks and notes can be found by scavenging")
local seen = {}
for _, t in pairs(C.SCAVENGE_LOOT) do for _, e in ipairs(t) do seen[e[1]] = true end end
assert(seen.stick and seen.scrawled_notes)
print("   OK")

print("8. C opens crafting from the map, Enter makes a torch, the screen fits")
local keys = {}
for k = 1, 14 do keys[k] = 115 end
keys[15] = 10                    -- creator: down to Start, Enter
keys[16] = C.KEY.C               -- map: crafting
keys[17] = 10                    -- make the first recipe (Torch)
keys[18] = C.KEY.C               -- back to the map
local i, texts = 0, {}
local saved_getch, saved_exit, saved_text = gfx.getch, fake.should_exit, gfx.text
gfx.getch = function() i = i + 1; if i > #keys then return 113 end; return keys[i] end
fake.should_exit = function() return i > #keys + 5 end
gfx.text = function(x, y, s)
    texts[#texts + 1] = s
    assert(x >= 0 and x + 7 * #s <= 400 + 7, "text runs off the screen: " .. s)
end
dofile("wasteland_run.lua")
gfx.getch, fake.should_exit, gfx.text = saved_getch, saved_exit, saved_text
local saw_screen, saw_result = false, false
for _, s in ipairs(texts) do
    if s == "Crafting" then saw_screen = true end
    if s:find("Made Torch", 1, true) or s:find("Need 1 Stick", 1, true) then saw_result = true end
end
assert(saw_screen, "C should open the crafting screen")
assert(saw_result, "Enter should try to make the torch")
print("   OK")

print("\nCRAFTING TESTS PASSED")
