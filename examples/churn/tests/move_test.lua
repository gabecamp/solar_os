-- Hex movement from the keys: Left/Right step west/east; Up/Down lean and
-- the next Left/Right takes the diagonal (Game:map_dir_key).
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KEY = H.KEY
local UP, DOWN, LEFT, RIGHT = gfx.KEY_UP, gfx.KEY_DOWN, gfx.KEY_LEFT, gfx.KEY_RIGHT

-- A game standing on open plains, every neighbor passable, rested.
local function open_ground()
    local g = Game.new()
    g:start_game()
    for dq = -2, 2 do for dr = -2, 2 do g.tiles[dq .. "," .. dr] = "plains" end end
    g.player.q, g.player.r = 0, 0
    g.enc_cooldown = 99    -- (no encounter interrupts a step)
    g.scene_queue = {}
    return g
end
local function after(keys)
    local g = open_ground()
    for _, k in ipairs(keys) do g.player.mp = g.player.max_mp; g:map_dir_key(k) end
    return g.player.q, g.player.r
end
local function same(q, r, want)
    return q == want[1] and r == want[2]
end

print("1. all six neighbors from the arrows (pointy-top hexes)")
local cases = {
    {"Left",       {LEFT},        {-1, 0}},
    {"Right",      {RIGHT},       {1, 0}},
    {"Up+Left",    {UP, LEFT},    {0, -1}},
    {"Up+Right",   {UP, RIGHT},   {1, -1}},
    {"Down+Left",  {DOWN, LEFT},  {-1, 1}},
    {"Down+Right", {DOWN, RIGHT}, {0, 1}},
}
local seen = {}
for _, c in ipairs(cases) do
    local q, r = after(c[2])
    assert(same(q, r, c[3]), ("%s went to %d,%d"):format(c[1], q, r))
    seen[q .. "," .. r] = true
end
local n = 0; for _ in pairs(seen) do n = n + 1 end
assert(n == 6, "six different neighbors")
-- WASD the same
local q, r = after({KEY.W, KEY.D})
assert(same(q, r, {1, -1}), "W then D")
print("   OK")

print("2. Up or Down alone doesn't move; a second one switches; other keys drop it")
local g = open_ground()
assert(g:map_dir_key(UP) and g.player.q == 0 and g.player.r == 0 and g.move_lean == -1)
g:map_dir_key(DOWN)
assert(g.move_lean == 1)
assert(not g:map_dir_key(KEY.F) and g.move_lean == nil, "F drops the lean")
g:map_dir_key(LEFT)
assert(g.player.q == -1 and g.player.r == 0, "then Left is plain west")
print("   OK")

print("3. the real main loop: after Up the hint line asks for Left or Right")
local texts = {}
local keys = {10, 10, 27, 10, 32, UP}   -- creator, past the wake scene, then Up
local i = 0
local saved_getch, saved_exit, saved_text = gfx.getch, fake.should_exit, gfx.text
gfx.getch = function() i = i + 1; if i > #keys then return 113 end; return keys[i] end
fake.should_exit = function() return i > #keys + 3 end
gfx.text = function(x, y, s) texts[#texts + 1] = s end
dofile("churn_run.lua")
gfx.getch, fake.should_exit, gfx.text = saved_getch, saved_exit, saved_text
local hinted = false
for _, s in ipairs(texts) do if s:find("Left or Right picks", 1, true) then hinted = true end end
assert(hinted, "the hint line shows the lean")
print("   OK")

print("\nMOVE TESTS PASSED")
