-- Fixes from playtesting: the bag screen's arrow keys go across the grid
-- (and wrap), every pocket can be reached, X drops, dropping on a full cell
-- swaps; clothes cut into scraps; what you can make comes first; a fishing
-- rod on the ground still fishes; gear shows its numbers; rubles; the
-- records screen only lists what you've earned; a title tune.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, L, rows_pos = dofile("lib_layout.lua")
local KEY_X = 120

local function fresh()
    local g = Game.new()
    g:start_game()
    g.player.q, g.player.r = 0, 0
    g.ground["0,0"] = {}
    g.player.inventory = {}
    g.player.equipped.lhand, g.player.equipped.rhand = nil, nil
    g.screen = "inventory"
    return g
end
local function row_of(g, kind, key)
    local rows = rows_pos()
    for i, r in ipairs(rows) do if r[1] == kind and r[2] == key then return i end end
end
local function count(list, item)
    local n = 0
    for _, s in ipairs(list) do if s.item == item then n = n + s.qty end end
    return n
end

print("1. every bag cell is a cursor row, empty ones too")
local g = fresh()
g.player.equipped.back = "backpack"
g.player.inventory = {{item = "rock", qty = 1}}
g:draw_inventory(400, 300)
local cap = g:bag_capacity()
for k = 1, cap do assert(row_of(g, "inventory", k), "bag cell " .. k .. " of " .. cap) end

print("2. arrows move across the grids; off the end wraps round")
g.ground["0,0"] = {{item = "rock", qty = 1}, {item = "stick", qty = 1}, {item = "cap", qty = 1}}
g.inv_drawn = nil
g:draw_inventory(400, 300)
g.inv_cursor = row_of(g, "ground", 1)
g:inv_move(1, 0)
assert(g.inv_cursor == row_of(g, "ground", 2), "right: the next ground cell")
g:inv_move(-1, 0); g:inv_move(-1, 0)
local _, pos = rows_pos()
assert(rows_pos()[g.inv_cursor][1] == "equip", "left of the ground: the doll")
g.inv_cursor = row_of(g, "inventory", 1)
g:inv_move(1, 0)
assert(g.inv_cursor == row_of(g, "inventory", 2), "right in the bag")
g:inv_move(0, 1)
assert(g.inv_cursor == row_of(g, "inventory", 2 + L.BACKPACK_COLS), "down a bag row")
g.inv_cursor = row_of(g, "inventory", L.BACKPACK_COLS)   -- the bag's right edge
g:inv_move(1, 0)
local wrapped = pos[g.inv_cursor]
assert(wrapped and wrapped.x < L.INV_COL_X, "right off the edge wraps to the left side")
g.inv_cursor = row_of(g, "ground", 1)
g:inv_move(0, -1)
assert(pos[g.inv_cursor].y > L.GROUND_Y, "up off the top wraps to the bottom: " .. rows_pos()[g.inv_cursor][1] .. " " .. tostring(rows_pos()[g.inv_cursor][2]) .. " y " .. pos[g.inv_cursor].y)

print("3. X drops what the cursor is on; on the ground it does nothing")
g = fresh()
g.player.inventory = {{item = "knife", qty = 1}}
g:draw_inventory(400, 300)
g.inv_cursor = row_of(g, "inventory", 1)
assert(g:inv_drop())
assert(#g.player.inventory == 0 and count(g:ground_list(), "knife") == 1)
g.inv_cursor = row_of(g, "ground", 1)
assert(not g:inv_drop())

print("4. dropping on a cell that holds something else swaps; same thing stacks")
g = fresh()
g.player.inventory = {{item = "rock", qty = 1}, {item = "stick", qty = 2}}   -- pockets: full
g.ground["0,0"] = {{item = "knife", qty = 1}, {item = "stick", qty = 1}}
assert(g:try_transfer({"ground", 1}, {"inventory", 1}), "a full bag still swaps")
assert(g.player.inventory[1].item == "knife" and count(g:ground_list(), "rock") == 1)
assert(g:try_transfer({"ground", 1}, {"inventory", 2}), "onto its own kind: stacks")
assert(g.player.inventory[2].qty == 3)
assert(g:try_transfer({"inventory", 1}, {"inventory", 2}), "bag to bag: they trade places")
assert(g.player.inventory[1].item == "stick" and g.player.inventory[2].item == "knife")
g.player.equipped.head = "cap"
assert(g:try_transfer({"equip", "head"}, {"inventory", 1}), "off the body onto a full cell")
assert(g.player.equipped.head == nil and g.player.inventory[1].item == "cap")
assert(count(g:ground_list(), "stick") == 3, "no room in the bag: what was there goes down")

print("5. a sharp edge cuts clothes into cloth scraps; nothing you wear is cut")
g = fresh()
g.player.inventory = {{item = "jeans", qty = 1}, {item = "knife", qty = 1}}
local cut
for _, r in ipairs(g:known_recipes()) do if r.id == "cut_jeans" then cut = r end end
assert(cut and g:craft_blocker(cut) == nil, "Cut Up Jeans listed and ready")
assert(g:craft(cut))
assert(count(g.player.inventory, "cloth_scrap") == 3 and count(g.player.inventory, "jeans") == 0)
assert(count(g.player.inventory, "knife") == 1, "the knife is a tool: kept")
g.player.equipped.shirt = "tshirt"
for _, r in ipairs(g:known_recipes()) do assert(r.id ~= "cut_tshirt", "worn: not offered") end
g.player.inventory = {{item = "tshirt", qty = 1}}
for _, r in ipairs(g:known_recipes()) do
    if r.id == "cut_tshirt" then assert(g:craft_blocker(r):find("sharp"), "needs an edge") end
end

print("6. the crafting list: what you can make now comes first")
g = fresh()
g.ground["0,0"] = {{item = "cloth_scrap", qty = 2}}   -- bandage, rag shirt...
local list, seen_blocked = g:known_recipes(), false
for _, r in ipairs(list) do
    local ready = g:craft_blocker(r) == nil
    if not ready then seen_blocked = true end
    assert(not (ready and seen_blocked), r.name .. " is ready but listed after one that isn't")
end
assert(g:craft_blocker(list[1]) == nil, "the first one is ready")

print("7. a fishing rod on the ground fishes (G)")
g = fresh()
g.ground["0,0"] = {{item = "fishing_rod", qty = 1}}
g.near_water = function() return true end
local fished = false
g.fish = function() fished = true end
g:gather()
assert(fished, "G by water with the rod on the ground")

print("8. gear shows its numbers")
g = fresh()
assert(g:item_stats("jacket"):find("Warm 3") and g:item_stats("jacket"):find("+2 cells", 1, true))
assert(g:item_stats("knife"):find("12 dmg") and g:item_stats("knife"):find("bleed 30%", 1, true))
assert(g:item_stats("backpack"):find("10 bag cells"))
assert(g:item_stats("canned_beans"):find("Hunger %+40"))
assert(g:item_stats("rock"):find("thrown"))
assert(not g:item_stats("gasmask"):find("rads"), "no counter: radiation has no number")

print("9. rubles: found in piles, one row in the bag")
g = fresh()
local name = g:drop_found("rubles")
local n = count(g:ground_list(), "rubles")
assert(n >= 5 and n <= 25 and name:find("Rubles x"), name)

print("10. a title tune at start-up (unless sound was off)")
g = Game.new()
g:begin_intro(nil)
assert(g.last_sfx == "title")
g = Game.new()
g:begin_intro({muted = true})
assert(g.last_sfx == nil and g.muted)

print("11. the cassettes say so")
g = fresh()
g.player.inventory = {{item = "tape_cook", qty = 1}}
g:draw_inventory(400, 300)
g.inv_cursor = row_of(g, "inventory", 1)
assert(g:cursor_description():find("Cassette Tape: Day Forty", 1, true))

print("12. pockets count on top of any bag, and get a row of their own")
g = fresh()
local e = g.player.equipped
e.pants, e.jacket, e.belt = "jeans", "jacket", "leather_belt"   -- 6 pockets
assert(g:pocket_cells() == 6)
for _, b in ipairs({"backpack", "hide_pack", "travois", "hand_cart"}) do
    e.back = b
    local bag = ({backpack = 10, hide_pack = 12, travois = 14, hand_cart = 16})[b]
    assert(g:bag_capacity() == math.min(L.BACKPACK_CAP, bag + 6 + (g.player.bag_bonus or 0)),
           b .. ": " .. g:bag_capacity())
end
e.back = "backpack"
g.inv_drawn = nil
g:draw_inventory(400, 300)
local rows, pos = rows_pos()
local cap = g:bag_capacity()
local first_pocket = row_of(g, "inventory", cap - 5)
assert(pos[first_pocket].pocket and not pos[row_of(g, "inventory", cap - 6)].pocket)
assert(pos[first_pocket].x == pos[row_of(g, "inventory", 1)].x, "pockets start a row")
assert(pos[first_pocket].y > pos[row_of(g, "inventory", cap - 6)].y)

print("13. pants + a bindle = 7 at any Strength; an empty cell says how it adds up")
for str = 1, 3 do
    g = Game.new()
    g.player.attrs.Strength = str
    g:start_game()
    g.player.equipped.pants, g.player.equipped.back = "jeans", "bindle"
    assert(g:bag_capacity() == 7, "Strength " .. str .. ": " .. g:bag_capacity())
end
assert(g:bag_sum_text() == "Bindle 5 + pockets 2 = 7", g:bag_sum_text())
g.player.attrs.Strength = 5
g:set_difficulty(g.difficulty)   -- (recomputes the stats)
assert(g:bag_sum_text() == "Bindle 5 + pockets 2 + Strength 2 = 9", g:bag_sum_text())
g.player.inventory = {}
g.screen = "inventory"
g:draw_inventory(400, 300)
g.inv_cursor = row_of(g, "inventory", 1)
local said = {}
local text = gfx.text
gfx.text = function(x, y, s) said[#said + 1] = s end
g:draw_inv_desc(400, true)
gfx.text = text
assert(table.concat(said, "|"):find("Bindle 5 + pockets 2", 1, true), table.concat(said, "|"))

print("PLAYTEST TESTS PASSED")
