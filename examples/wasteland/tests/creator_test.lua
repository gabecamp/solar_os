-- Character creator: point-buy and trait-budget rules, derived stats, and the
-- creator screen driven through the real main loop.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, C = dofile("lib_creator.lua")
local UP, DOWN, LEFT, RIGHT = gfx.KEY_UP, gfx.KEY_DOWN, gfx.KEY_LEFT, gfx.KEY_RIGHT
local SPACE, ENTER = 32, 10

local function press(g, ...)
    for _, k in ipairs({...}) do g:creator_key(k) end
end

print("1. a new game starts on the creator with a valid default build")
local g = Game.new()
assert(g.screen == "creator")
assert(C.attr_points_left(g.player.attrs) == 0 and C.trait_points_left(g.player.traits) == 5,
       "5 trait points to spend at the start")
assert(g.player.max_mp == 2 and g.player.sight == 2 and g.player.scav_rolls == 2)
print("   OK")

print("2. attributes: points move between stats, stay in 1..6, never overspend")
press(g, RIGHT)                                   -- Strength up with 0 points left
assert(g.player.attrs.Strength == 3 and g.creator_msg, "no points: refused with a message")
press(g, LEFT, LEFT)                              -- Strength 3 -> 1, frees 2
press(g, DOWN, DOWN, RIGHT, RIGHT, RIGHT)         -- Perception 3 -> 5 (third press refused)
assert(g.player.attrs.Strength == 1 and g.player.attrs.Perception == 5)
assert(C.attr_points_left(g.player.attrs) == 0)
press(g, UP, UP, LEFT, LEFT, LEFT)                -- can't go below 1
assert(g.player.attrs.Strength == C.ATTR_MIN)
assert(g.player.sight == 3 and g.player.scav_rolls == 3 and g.player.bag_bonus == -2,
       "Perception 5: sight 3, 3 finds; Strength 1: -2 bag cells")
print("   OK")

print("3. traits: positives spend, negatives give back; start refused below 0")
g = Game.new()
local quick = #C.ATTRIBUTES + 1                   -- first trait row
g.creator_cursor = quick
press(g, SPACE, DOWN, SPACE)                      -- Quick + Hawk-Eyed (-6 of 5)
assert(C.trait_points_left(g.player.traits) == -1 and g.player.max_mp == 3)
press(g, ENTER)
assert(g.screen == "creator", "must not start with trait points below 0")
g.creator_cursor = #C.ATTRIBUTES + 6              -- Asthmatic (+3)
press(g, SPACE)
assert(C.trait_points_left(g.player.traits) == 2 and g.player.max_mp == 2)
press(g, SPACE)                                   -- toggling off works too
assert(not g.player.traits.Asthmatic)
print("   OK")

print("4. every trait changes a derived stat (no labels with nothing behind them)")
for _, t in ipairs(C.TRAITS) do
    local p1, p2 = Game.new().player, Game.new().player
    p2.traits[t.name] = true
    C.recompute_stats(p2)
    local changed = false
    for _, k in ipairs({"max_mp", "sight", "scav_rolls", "bag_bonus", "hunger_mult", "rest_gain_mult"}) do
        if p1[k] ~= p2[k] then changed = true end
    end
    assert(changed, t.name .. " does nothing")
end
print("   OK")

print("5. starting applies the build: MP full, sight used for the fog")
g = Game.new()
g.creator_cursor = 3                              -- Perception
g.player.attrs.Strength = 1                       -- free 2 points
press(g, RIGHT, RIGHT, ENTER)
assert(g.screen == "map" and g.player.sight == 3 and g.player.mp == g.player.max_mp)
local far = 0
for key in pairs(g.player.visible) do far = far + 1 end
assert(far == 37, "sight 3 on the hex grid shows 37 tiles, got " .. far)
print("   OK")

print("6. the real main loop: creator first, Enter starts, the map follows")
local i, texts = 0, {}
local keys = {DOWN, DOWN, RIGHT, ENTER}           -- try raising Perception, then start
local saved_getch, saved_exit, saved_text = gfx.getch, fake.should_exit, gfx.text
gfx.getch = function() i = i + 1; if i > #keys then return 113 end; return keys[i] end
fake.should_exit = function() return i > #keys + 5 end
gfx.text = function(x, y, s) texts[#texts + 1] = s end
dofile("wasteland_run.lua")
gfx.getch, fake.should_exit, gfx.text = saved_getch, saved_exit, saved_text
local saw_creator, saw_map = false, false
for _, s in ipairs(texts) do
    if s == "Create your survivor" then saw_creator = true end
    if s:find("F:search", 1, true) then saw_map = true end
end
assert(saw_creator and saw_map, "creator then map")
print("   OK")

print("\nCREATOR TESTS PASSED")
