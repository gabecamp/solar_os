-- You start with nothing; every piece of clothing has a makeshift version
-- you can craft from scraps, with less room (and no more warmth) than the
-- real thing. The old starting clothes lie a few hexes from the start.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()

local Game, C = dofile("lib_crafting.lua")
local ITEM_DB = C.ITEM_DB

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end
local function recipe(id)
    for _, r in ipairs(C.RECIPES) do if r.out and r.out[1] == id then return r end end
end
local function cells(def)
    return (def.bag_cells or 0) + (def.pocket_cells or 0) + (def.belt_cells or 0)
end

print("1. a new game: nothing worn, nothing carried, your arms hold 2")
local g = fresh()
assert(next(g.player.equipped) == nil, "nothing worn")
assert(#g.player.inventory == 0, "nothing carried")
assert(g:bag_capacity() == 2, "your arms hold 2")
print("   OK")

print("2. every piece of clothing has a crafted, known, poorer version")
local rag_of = {}
for id, def in pairs(ITEM_DB) do
    if def.ragged_of then
        local real = ITEM_DB[def.ragged_of]
        assert(real and real.slot == def.slot, id .. ": same slot as " .. def.ragged_of)
        assert(cells(def) < cells(real) or cells(real) == 0, id .. ": less room than " .. def.ragged_of)
        assert((def.warmth or 0) <= (real.warmth or 0), id .. ": no warmer than " .. def.ragged_of)
        local r = recipe(id)
        assert(r and g.known[r.id], id .. ": a recipe you know from the start")
        rag_of[def.ragged_of] = id
    end
end
local special = {karls_hat = true, karls_waders = true, headlamp = true}   -- gifts and tech
for id, def in pairs(ITEM_DB) do
    local hand = def.slot == "lhand" or def.slot == "rhand"
    if def.slot and not hand and not def.ragged_of and not special[id] then
        assert(rag_of[id], id .. " has no makeshift version")
    end
end
print("   OK")

print("3. ragged sprites: the real one with holes, still a valid 16x16")
for id, def in pairs(ITEM_DB) do
    if def.ragged_of and id ~= "rope_belt" then
        assert(C.SPRITES[id] and #C.SPRITES[id] <= 128, id .. " sprite")
        assert(C.SPRITES[id] ~= C.SPRITES[def.ragged_of], id .. " looks different")
    end
end
print("   OK")

print("4. crafting rags from the scraps at the start, and wearing them")
g = fresh()
g.player.q, g.player.r = 0, 0
g.ground["0,0"] = {{item = "cloth_scrap", qty = 6}, {item = "stick", qty = 1}}
assert(g:craft(recipe("bindle")))
local bi
for i, s in ipairs(g.player.inventory) do if s.item == "bindle" then bi = i end end
if not bi then   -- your arms may be full: it went to the ground
    for i, s in ipairs(g:ground_list()) do if s.item == "bindle" then bi = i end end
    assert(bi and g:try_transfer({"ground", bi}, {"equip", "back"}))
else
    assert(g:try_transfer({"inventory", bi}, {"equip", "back"}))
end
assert(g:bag_capacity() == ITEM_DB.bindle.bag_cells, "a bindle replaces your arms")
assert(g:craft(recipe("foot_wraps")))
for i, s in ipairs(g.player.inventory) do
    if s.item == "foot_wraps" then g:use_item("inventory", i) break end
end
assert(g.player.equipped.feet == "foot_wraps", "E wears them")
print("   OK")

print("5. the old starting clothes are lying near the start (not on it)")
for _ = 1, 10 do
    g = fresh()
    local found = {}
    for key, pile in pairs(g.ground) do
        for _, s in ipairs(pile) do
            if s.item == "tshirt" or s.item == "jeans" or s.item == "boots" or s.item == "backpack" then
                local q, r = key:match("(-?%d+),(-?%d+)")
                local d = math.max(math.abs(q), math.abs(r), math.abs(q + r))
                if d >= 2 and d <= 6 then found[s.item] = true end
            end
        end
    end
    assert(found.tshirt and found.jeans and found.boots and found.backpack, "old clothes near the start")
end
print("   OK")

print("6. a save keeps the empty start, and loading adds no second set of clothes")
local function count(game, item)
    local n = 0
    for _, pile in pairs(game.ground) do
        for _, s in ipairs(pile) do if s.item == item then n = n + s.qty end end
    end
    return n
end
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(next(g2.player.equipped) == nil and #g2.player.inventory == 0)
assert(count(g2, "tshirt") == count(g, "tshirt") and count(g2, "boots") == count(g, "boots"))
print("   OK")

print("\nRAGGED TESTS PASSED")
