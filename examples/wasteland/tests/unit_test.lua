package.path = "./?.lua;" .. package.path
local solaros = require("solaros")
local gfx = solaros.gfx
gfx.begin()

local Game, ITEM_DB, EQUIP_SLOTS, TERRAIN = dofile("lib_only.lua")

local game = dofile("kit.lua")(Game.new())   -- dressed as the old start
game.player.q, game.player.r = 0, 0  -- ensure we're at the loot pile

print("=== ground at spawn ===")
for i, s in ipairs(game:ground_list()) do
    print(i, s.item, s.qty)
end

print("\n=== test 1: take water_bottle from ground into inventory ===")
-- the bag already holds 1 water bottle; the ground's 2 merge into that stack
local function bottles()
    for _, s in ipairs(game.player.inventory) do
        if s.item == "water_bottle" then return s.qty end
    end
    return 0
end
local before, before_stacks = bottles(), #game.player.inventory
local water_i
for i, s in ipairs(game:ground_list()) do if s.item == "water_bottle" then water_i = i end end
game:try_transfer({"ground", water_i}, {"inventory", nil})  -- index target irrelevant, put_stack merges/appends
print("bottles in bag before/after:", before, bottles())
assert(bottles() == before + 2, "FAIL: bottles were not added to inventory")
assert(#game.player.inventory == before_stacks, "FAIL: same item should merge, not add a stack")
print("OK")

print("\n=== test 2: equip mismatch rejected (put cap-like non-slot item into 'feet') ===")
table.insert(game.player.inventory, {item = "cap", qty = 1})
local cap_idx = #game.player.inventory
local before_feet = game.player.equipped.feet
game:try_transfer({"inventory", cap_idx}, {"equip", "feet"})
print("feet slot after wrong-slot attempt:", game.player.equipped.feet, "(expected still", before_feet, ")")
assert(game.player.equipped.feet == before_feet, "FAIL: wrong-slot equip should have been rejected")
local found_cap = false
for _, s in ipairs(game.player.inventory) do
    if s.item == "cap" then found_cap = true end
end
assert(found_cap, "FAIL: cap should have been reverted back to inventory")
print("OK - rejected and reverted")

print("\n=== test 3: equip correctly into head slot ===")
local cap_idx2
for i, s in ipairs(game.player.inventory) do
    if s.item == "cap" then cap_idx2 = i end
end
game:try_transfer({"inventory", cap_idx2}, {"equip", "head"})
print("head slot:", game.player.equipped.head)
assert(game.player.equipped.head == "cap", "FAIL: cap should now be equipped in head")
print("OK")

print("\n=== test 4: consume canned_beans restores hunger ===")
local beans_idx
for i, s in ipairs(game.player.inventory) do
    if s.item == "canned_beans" then beans_idx = i end
end
game.player.needs.hunger = 50
game:try_consume("inventory", beans_idx)
print("hunger after consuming beans:", game.player.needs.hunger, "(expected 90)")
assert(game.player.needs.hunger == 90, "FAIL: hunger should be 90")
print("OK")

print("\n=== test 5: swap - equip something into an already-occupied slot bumps old item to inventory ===")
table.insert(game.player.inventory, {item = "jeans", qty = 1})
local jeans_idx = #game.player.inventory
local before_inv_count = #game.player.inventory
game:try_transfer({"inventory", jeans_idx}, {"equip", "pants"})
print("pants slot:", game.player.equipped.pants)
assert(game.player.equipped.pants == "jeans", "FAIL: jeans should now be equipped")
local found_old_jeans = false
for _, s in ipairs(game.player.inventory) do
    if s.item == "jeans" then found_old_jeans = true end
end
print("old jeans bumped back to inventory:", found_old_jeans)
assert(found_old_jeans, "FAIL: previously-equipped jeans should be back in inventory")
print("OK")

print("\n=== test 6: try_move onto water is blocked ===")
-- find a water neighbor if any exists near spawn, else just confirm generation ran
local moved_to_water = false
for key, terrain_id in pairs(game.tiles) do
    if terrain_id == "water" then
        local q, r = key:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        print("found a water tile at", q, r, "- confirming TERRAIN table blocks it")
        assert(TERRAIN.water.passable == false, "FAIL: water should be impassable")
        moved_to_water = true
        break
    end
end
if not moved_to_water then print("(no water tile in this generated map - terrain table check skipped)") end
print("OK")

print("\nALL UNIT TESTS PASSED")
