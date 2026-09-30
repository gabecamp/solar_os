-- Regression tests for the bugs listed in HANDOFF.md "Where We Are" 17-20,
-- plus the stack-merging / bag-full rules added while fixing them.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, L, rows_pos = dofile("lib_layout.lua")

local function fresh()
    local g = Game.new()
    g.player.q, g.player.r = 0, 0
    return g
end
local function find(list, item)
    for i, s in ipairs(list) do if s.item == item then return i, s end end
end

-- Run the real main loop (wasteland_run.lua) against a scripted key list.
-- nil entries are idle getch timeouts. Returns refresh count, keys handled,
-- and every string drawn with gfx.text.
local function run_loop(keys, n)
    local i, handled, texts = 0, 0, {}
    local saved_getch, saved_exit, saved_text = gfx.getch, fake.should_exit, gfx.text
    gfx.getch = function()
        i = i + 1
        if i > n then return 113 end   -- Q
        if keys[i] ~= nil then handled = handled + 1 end
        return keys[i]
    end
    fake.should_exit = function() return i > n + 5 end
    gfx.text = function(x, y, s) texts[#texts + 1] = s end
    REFRESH_COUNT = 0
    dofile("wasteland_run.lua")
    gfx.getch, fake.should_exit, gfx.text = saved_getch, saved_exit, saved_text
    return REFRESH_COUNT, handled, texts
end
local function drew(texts, needle)
    for _, s in ipairs(texts) do if s:find(needle, 1, true) then return true end end
    return false
end

print("[17] E on the inventory screen eats/drinks the item under the cursor")
-- spawn ground: rock, cloth_scrap, canned_beans, water_bottle -> cursor 4 is water
local _, _, texts = run_loop({105, 115, 115, 115, 101}, 5)
assert(drew(texts, "Consumed Water Bottle."), "E did not consume the water bottle")
assert(drew(texts, "Up/Dn Enter:move E:eat/drink I:map"), "inventory hint should mention E")
local _, _, texts2 = run_loop({105, 101}, 2)   -- cursor 1 = rock
assert(drew(texts2, "Rock isn't edible/drinkable."), "E on a rock should say so")
print("    OK")

print("[18] consuming takes ONE unit; the stack goes only when empty")
local g = fresh()
local idx, stack = find(g:ground_list(), "water_bottle")
assert(stack.qty == 2)
g.player.needs.thirst = 10
g:try_consume("ground", idx)
assert(g.player.needs.thirst == 60, "one bottle is +50 thirst")
local _, left = find(g:ground_list(), "water_bottle")
assert(left and left.qty == 1, "one bottle should be left")
g:try_consume("ground", idx)
assert(find(g:ground_list(), "water_bottle") == nil, "empty stack should be removed")
assert(g.player.needs.thirst == 100)
print("    OK")

print("[19] the loop redraws only after a key, never while idle")
local keys = {}
for k = 1, 200 do keys[k] = (k % 50 == 0) and 100 or nil end   -- 4 keys in 200 polls
local refreshes, handled = run_loop(keys, 200)
print(("    %d refreshes for %d keys over 200 polls (+1 initial frame, +1 for the quit key)")
      :format(refreshes, handled))
assert(refreshes <= handled + 2, "idle polls are redrawing")
print("    OK")

print("[20] every bag stack (cap " .. L.BACKPACK_CAP .. ") is drawn and selectable")
g = fresh()
g.player.inventory = {}
local ids = {"rock", "cloth_scrap", "canned_beans", "water_bottle", "tshirt", "jeans", "boots", "cap", "gloves"}
for k = 1, L.BACKPACK_CAP do g.player.inventory[k] = {item = ids[(k - 1) % #ids + 1], qty = 1} end
g:draw_inventory(300, 400)
local INV_ROWS, INV_POS = rows_pos()
local bag = 0
for k, row in ipairs(INV_ROWS) do
    if row[1] == "inventory" and INV_POS[k] and INV_POS[k].x then bag = bag + 1 end
end
assert(bag == L.BACKPACK_CAP, ("drew %d of %d bag cells"):format(bag, L.BACKPACK_CAP))
print("    OK")

print("[+] same items merge into one stack; full bag rejects new stacks in place")
g = fresh()
g.player.inventory = {{item = "rock", qty = 1}}
local ri = find(g:ground_list(), "rock")
g:try_transfer({"ground", ri}, {"inventory"})
assert(#g.player.inventory == 1 and g.player.inventory[1].qty == 2, "rocks should merge")
g.player.inventory = {}
for k = 1, L.BACKPACK_CAP do g.player.inventory[k] = {item = "rock", qty = 1} end
local before = {}
for k, s in ipairs(g:ground_list()) do before[k] = s.item end
local bi = find(g:ground_list(), "canned_beans")
g:try_transfer({"ground", bi}, {"inventory"})
assert(#g.player.inventory == L.BACKPACK_CAP)
for k, s in ipairs(g:ground_list()) do
    assert(s.item == before[k], "rejected move must restore the ground order")
end
print("    OK")

print("[+] equipping over an occupied slot with a full bag drops the old item")
g = fresh()
g.player.equipped.head = "cap"
g.player.inventory = {}
for k = 1, L.BACKPACK_CAP - 1 do g.player.inventory[k] = {item = "rock", qty = k} end
g.player.inventory[L.BACKPACK_CAP] = {item = "cap", qty = 1}  -- a second cap; bag is full
-- equipping it frees its cell, so the old cap goes back to the bag (merging)
g:try_transfer({"inventory", L.BACKPACK_CAP}, {"equip", "head"})
assert(g.player.equipped.head == "cap")
local _, caps = find(g.player.inventory, "cap")
assert(caps and caps.qty == 1, "old cap should be back in the bag")
-- now fill the bag with distinct stacks and equip gloves from the ground:
-- the old gloves have nowhere to go but the ground
g.player.equipped.hands = "gloves"
g.player.inventory = {}
for k = 1, L.BACKPACK_CAP do g.player.inventory[k] = {item = "x" .. k, qty = 1} end
table.insert(g:ground_list(), {item = "gloves", qty = 1})
local ground_before = #g:ground_list()
g:try_transfer({"ground", ground_before}, {"equip", "hands"})
assert(g.player.equipped.hands == "gloves")
assert(#g.player.inventory == L.BACKPACK_CAP, "bag must not exceed its cap")
local _, gl = find(g:ground_list(), "gloves")
assert(gl and gl.qty == 1, "old gloves should land on the ground")
print("    OK")

print("[+] every body slot has an item, and every wearable not worn at the start spawns")
local Game2, ITEM_DB, EQUIP_SLOTS = dofile("lib_only.lua")
for _, slot in ipairs(EQUIP_SLOTS) do
    local found
    for id, def in pairs(ITEM_DB) do if def.slot == slot then found = id end end
    assert(found, "no item fits the " .. slot .. " slot")
    assert(ITEM_DB[found].wear, found .. " has no look on the doll")
end
for seed_try = 1, 5 do
    g = Game2.new()
    local start = {}
    for _, item in pairs(g.player.equipped) do start[item] = true end
    local seen = {}
    for key, pile in pairs(g.ground) do
        assert(g.tiles[key] ~= "water", "loot on an impassable tile")
        for _, st in ipairs(pile) do seen[st.item] = true end
    end
    for id, def in pairs(ITEM_DB) do
        if def.slot and not start[id] then assert(seen[id], id .. " never spawns") end
    end
end
print("    OK")

print("\nREGRESSION TESTS PASSED")
