-- Quitting mid-run asks first (Q/Esc on the map or in the bag, Q in crafting):
-- Q, Y or Enter quits, any other key stays. Off a run (the splash, the title,
-- the creator, death, the ending) Q still quits at once.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game = dofile("lib_layout.lua")

-- the real main loop on scripted keys (as regression_test's run_loop): how
-- many keys it took before it stopped, and what it drew
local function run_loop(keys)
    local shifted = {10, 10, 27, 10, 32}   -- intro, New survivor, skip story, creator, wake scene
    for k, v in ipairs(keys) do shifted[k + 5] = v end
    local i, taken, texts = 0, 0, {}
    local saved_getch, saved_exit, saved_text = gfx.getch, fake.should_exit, gfx.text
    gfx.getch = function()
        i = i + 1
        taken = i
        return shifted[i]
    end
    fake.should_exit = function() return i > #shifted + 3 end
    gfx.text = function(x, y, s) texts[#texts + 1] = s end
    FAKE_FILES, FAKE_DIRS = {}, {}
    dofile("churn_run.lua")
    gfx.getch, fake.should_exit, gfx.text = saved_getch, saved_exit, saved_text
    return taken - 5, texts
end
local function drew(texts, needle)
    for _, s in ipairs(texts) do if s:find(needle, 1, true) then return true end end
    return false
end

print("1. Q on the map asks; Esc stays and play goes on; Q, Q quits; the run is saved")
local Q, ESC, ENTER, I, C = 113, 27, 10, 105, 99
local taken, texts = run_loop({Q, ESC, I, I, Q, Q, I, I, I})
assert(drew(texts, "Quit the game?"), "the prompt")
assert(taken == 6, "stopped right after Q, Q (took " .. taken .. ")")
assert(FAKE_FILES["/sd/churn/save.lua"], "saved on the way out")
print("   OK")

print("2. Esc on the map asks too; Enter quits; in the bag and in crafting the same")
taken = run_loop({ESC, ENTER, I, I})
assert(taken == 2, "Esc then Enter (took " .. taken .. ")")
taken = run_loop({I, Q, 32, Q, 121, I})
assert(taken == 5, "in the bag: Q asks, Space stays, Q then Y quits (took " .. taken .. ")")
taken = run_loop({C, Q, 32, Q, Q, I})
assert(taken == 5, "in crafting (took " .. taken .. ")")
print("   OK")

print("3. no time passes while it asks; a key that stays isn't acted on")
local g = Game.new()
g:start_game()
g.screen = "map"
local hours = g.player.hours
g:ask_quit()
assert(g.confirm_quit and not g.quit)
g:quit_confirm_key(32)                 -- Space: stay (not a rest)
assert(not g.confirm_quit and not g.quit and g.player.hours == hours)
g:ask_quit()
g:quit_confirm_key(121)   -- Y
assert(g.quit)
g:draw_quit_confirm(400, 300)
print("   OK")

print("4. off a run, Q quits at once (the splash)")
local taken0 = 0
do
    local keys, i = {Q, 10, 10}, 0
    local sg, se = gfx.getch, fake.should_exit
    gfx.getch = function() i = i + 1; taken0 = i; return keys[i] end
    fake.should_exit = function() return i > 6 end
    FAKE_FILES, FAKE_DIRS = {}, {}
    dofile("churn_run.lua")
    gfx.getch, fake.should_exit = sg, se
end
assert(taken0 == 1, "Q on the splash (took " .. taken0 .. ")")
print("   OK")

print("\nQUIT TESTS PASSED")
