-- Belts, the new weapons and loot, and scarcer scavenging.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, C = dofile("lib_crafting.lua")

local function fresh()
    local g = dofile("kit.lua")(Game.new())   -- a bag to craft into
    g:start_game()
    return g
end
local function find(g, id)
    for _, r in ipairs(C.RECIPES) do if r.id == id then return r end end
end
local function bag_count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    return n
end

print("1. a belt adds bag cells; E puts it in the empty belt slot")
local g = fresh()
local cap = g:bag_capacity()
g.player.inventory = {{item = "leather_belt", qty = 1}}
g:use_item("inventory", 1)
assert(g.player.equipped.belt == "leather_belt", tostring(g.player.equipped.belt))
assert(g:bag_capacity() == cap + 2)
g.player.equipped.belt = "rope_belt"
assert(g:bag_capacity() == cap + 1)

print("2. the Rope Belt and Shiv are learned (Tailoring, Tinkering), like the heavier weapons")
g = fresh()
assert(not g.known.rope_belt and not g.known.shiv)
assert(not g.known.machete and not g.known.spiked_club and not g.known.pipe_spear)
g.known.rope_belt, g.known.shiv = true, true
g.player.inventory = {{item = "rope", qty = 1}, {item = "cloth_scrap", qty = 1}}
assert(g:craft(find(g, "rope_belt")) and bag_count(g, "rope_belt") == 1)
g.player.inventory = {{item = "scrap_metal", qty = 1}, {item = "cloth_scrap", qty = 1}}
assert(g:craft(find(g, "shiv")) and bag_count(g, "shiv") == 1)

print("3. machete needs a rock to sharpen on; the others upgrade what you have")
g = fresh()
g.known.machete, g.known.spiked_club, g.known.pipe_spear = true, true, true
g:ground_list()
for k in pairs(g.ground) do g.ground[k] = {} end
g.player.inventory = {{item = "scrap_metal", qty = 3}, {item = "stick", qty = 1}, {item = "rope", qty = 2}}
assert(not g:craft(find(g, "machete")), "no rock")
table.insert(g.player.inventory, {item = "rock", qty = 1})
assert(g:craft(find(g, "machete")) and bag_count(g, "machete") == 1 and bag_count(g, "rock") == 1)
g.player.inventory = {{item = "stone_club", qty = 1}, {item = "scrap_metal", qty = 1}}
assert(g:craft(find(g, "spiked_club")) and bag_count(g, "spiked_club") == 1)
g.player.inventory = {{item = "pipe", qty = 1}, {item = "knife", qty = 1}, {item = "rope", qty = 1}}
assert(g:craft(find(g, "pipe_spear")) and bag_count(g, "pipe_spear") == 1)
for _, id in ipairs({"shiv", "machete", "spiked_club", "pipe_spear"}) do
    local w = C.ITEM_DB[id].weapon
    assert(w and w.dmg > 0 and C.SPRITES[id], id)
end

-- (40% until the empty start: cloth for makeshift clothes took some of the
-- dud weight)
print("4. loot is scarcer: at Perception 3 at least 35% of search rolls are duds")
for terrain, table_ in pairs(C.SCAVENGE_LOOT) do
    local total, dud = 0, 0
    for _, e in ipairs(table_) do
        total = total + e[2]
        -- (a trinket is no use to you: it counts with the duds)
        if e[1] == "nothing" or (C.ITEM_DB[e[1]] and C.ITEM_DB[e[1]].trinket) then dud = dud + e[2] end
        assert(e[1] == "nothing" or C.ITEM_DB[e[1]], terrain .. ": " .. e[1])
    end
    assert(dud / total >= 0.35, terrain .. " duds " .. dud .. "/" .. total)
end

print("GEAR TESTS PASSED")
