-- Character creator: point-buy and trait-budget rules, derived stats, and the
-- whole flow through the real main loop (keys -> stats -> map HUD).
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, L = dofile("lib_layout.lua")

print("1. defaults: all attributes 3, nothing left to spend, no traits")
local g = Game.new()
local p = g.player
assert(g.screen == "creator")
assert(L.attr_points_left(p.attrs) == 0 and L.trait_budget(p.traits) == 0)
assert(p.max_mp == 2 and p.sight == 2 and p.scav_rolls == 2 and g:bag_capacity() == 12)
print("   OK")

print("2. point buy: raising needs freed points; stays within 1..6")
g.creator.cursor = 3                       -- Perception
g:creator_adjust(1)
assert(p.attrs.Perception == 3 and g.creator.msg, "raise with 0 points left must be refused")
g.creator.cursor = 1                       -- Strength
g:creator_adjust(-1); g:creator_adjust(-1); g:creator_adjust(-1)
assert(p.attrs.Strength == 1, "can't go below 1")
g.creator.cursor = 3
g:creator_adjust(1); g:creator_adjust(1); g:creator_adjust(1); g:creator_adjust(1)
assert(p.attrs.Perception == 5, "only the 2 freed points can be spent")
print("   OK")

print("3. derived stats follow the attributes")
assert(p.sight == 3 and p.scav_rolls == 3, "Perception 5: +1 sight, +1 find")
assert(g:bag_capacity() == 10, "Strength 1: backpack 12 - 2")
p.attrs.Speed, p.attrs.Endurance = 5, 6
L.recompute_stats(p)
assert(p.max_mp == 3, "Speed 5: +1 MP")
assert(math.abs(p.rest_drain_mult - 0.7) < 1e-9, "Endurance 6: rest drains 30% slower")
p.attrs.Speed, p.attrs.Endurance = 3, 3
L.recompute_stats(p)
print("   OK")

print("4. traits: budget, opposites exclude each other, effects apply")
local by_id = {}
for _, t in ipairs(L.TRAITS) do by_id[t.id] = t end
g:creator_toggle(by_id.quick)
assert(L.trait_budget(p.traits) == -3 and p.max_mp == 3)
assert(g:creator_start() == false and g.screen == "creator", "can't start overspent")
g:creator_toggle(by_id.asthmatic)          -- the opposite of Quick: replaces it
assert(not p.traits.quick and p.traits.asthmatic and p.max_mp == 1)
assert(L.trait_budget(p.traits) == 3)
g:creator_toggle(by_id.scrounger); g:creator_toggle(by_id.packmule)
assert(p.scav_rolls == 4 and g:bag_capacity() == 12, "Scrounger +1 find, Pack Mule +2 cells")
assert(L.trait_budget(p.traits) == -1)
g:creator_toggle(by_id.bigeater)
assert(p.hunger_mult == 1.25 and L.trait_budget(p.traits) == 1)
assert(g:creator_start() == true and g.screen == "map" and p.mp == p.max_mp)
print("   OK")

print("5. every trait does something (no labels with nothing behind them)")
for _, t in ipairs(L.TRAITS) do
    local q = Game.new().player
    local before = {q.max_mp, q.sight, q.scav_rolls, q.bonus_cells, q.hunger_mult, q.rest_gain_mult}
    q.traits[t.id] = true
    L.recompute_stats(q)
    local after = {q.max_mp, q.sight, q.scav_rolls, q.bonus_cells, q.hunger_mult, q.rest_gain_mult}
    local changed = false
    for k = 1, #before do if before[k] ~= after[k] then changed = true end end
    assert(changed, t.name .. " changes nothing")
end
print("   OK")

print("6. through the real main loop: lower Speed twice, raise Perception twice, start")
local keys = {115, 0x82, 0x82, 115, 0x83, 0x83}   -- Down, Left x2, Down, Right x2
for _ = 1, 12 do keys[#keys + 1] = 115 end        -- down to [ Start ]
keys[#keys + 1] = 10
local i, texts = 0, {}
local saved_getch, saved_exit, saved_text = gfx.getch, fake.should_exit, gfx.text
gfx.getch = function() i = i + 1; if i > #keys then return 113 end; return keys[i] end
fake.should_exit = function() return i > #keys + 5 end
gfx.text = function(x, y, s) texts[#texts + 1] = s end
dofile("wasteland_run.lua")
gfx.getch, fake.should_exit, gfx.text = saved_getch, saved_exit, saved_text
local function drew(needle)
    for _, s in ipairs(texts) do if s:find(needle, 1, true) then return true end end
end
assert(drew("MP 1  Sight 3  Finds 3  Bag 12"), "creator preview should show the new stats")
assert(drew("MP 1/1  Hrs 0  Sight 3"), "map HUD should use the chosen stats")
print("   OK")

print("\nCREATOR TESTS PASSED")
