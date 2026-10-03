-- The journal (J): what you know, on one page that fits.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KEY = H.KEY

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end
local function text_of(g)
    return table.concat(g:journal_lines(), "\n")
end

print("1. a new run: the basics, and that the way out is unknown")
local g = fresh()
local t = text_of(g)
assert(t:find("Day 1", 1, true) and t:find("Normal", 1, true))
assert(t:find("way out: unknown", 1, true) and t:find("Artifacts: 0 of 3", 1, true))

print("2. everything you've learned shows up")
g:learn_site("trader"); g:learn_site("checkpoint")
g.player.q, g.player.r = 0, 0
g:mark_stash()
g.snares["1,0"] = {set = 0}
g.rad_known["2,0"] = 3
g.player.rads = 42
g.dog = {hp = 20, fed_hour = 0, hungry_days = 1}
g.player.inventory = {{item = "lora_radio", qty = 1}, {item = "permit", qty = 1}, {item = "geiger", qty = 1},
                      {item = "weeping_stone", qty = 2}}
g.radio = {charge = 4, next = {}}
t = text_of(g)
for _, want in ipairs({"Checkpoint: ", "Trader: ", "Stash: ", "Snare: ", "Hot hexes known: 1",
                       "Radiation: 42", "Your dog: 20/30 HP, hungry 1d", "Radio: 4/5",
                       "Churn Permit", "Artifacts: 2 of 3"}) do
    assert(t:find(want, 1, true), "missing: " .. want)
end

print("3. J opens it from the map and the bag; any key goes back; it fits")
for _, from in ipairs({"map", "inventory"}) do
    g.screen = from
    g:open_journal()
    assert(g.screen == "journal")
    local ys = {}
    gfx.text = function(_, y, s) ys[#ys + 1] = y end
    g:draw_journal(400, 300)
    for _, y in ipairs(ys) do assert(y <= 300, "off screen") end
    g:help_key(KEY.SPACE)
    assert(g.screen == from)
end
for i = 1, 30 do g.stashes[i .. ",1"] = true end   -- far too much to fit
local texts = {}
gfx.text = function(_, y, s) assert(y <= 300); texts[#texts + 1] = s end
g:draw_journal(400, 300)
assert(table.concat(texts, "\n"):find("more", 1, true), "a +n more line")
local src = io.open("churn_run.lua"):read("a")
assert(src:find("game:open_journal()", 1, true))

print("JOURNAL TESTS PASSED")
