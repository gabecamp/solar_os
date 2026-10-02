-- The storyline: the quarry, the pass, the Institute and the Quiet.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local QUESTS, KEY = H.QUESTS, H.KEY
local ST = QUESTS.story

local runs = 0
local function fresh()
    local g = Game.new()
    g:start_game()
    runs = runs + 1
    g.world_seed = 7000 + runs
    return g
end
local function stand(g, key)
    local q, r = key:match("(-?%d+),(-?%d+)")
    g.player.q, g.player.r = tonumber(q), tonumber(r)
end
local function dist(a, b)
    local aq, ar = a:match("(-?%d+),(-?%d+)")
    local bq, br = b:match("(-?%d+),(-?%d+)")
    aq, ar, bq, br = tonumber(aq), tonumber(ar), tonumber(bq), tonumber(br)
    return math.max(math.abs(aq - bq), math.abs(ar - br), math.abs(aq + ar - bq - br))
end

print("1. most worlds have the quarry: in the hills, away from the towns")
local placed = 0
for i = 1, 40 do
    local s = i * 613 % 32768
    local tiles, _, _, rad, sites = H.generate_world(s)
    Game.place_extras(tiles, sites, rad, s)
    if sites.quarry then
        placed = placed + 1
        assert(tiles[sites.quarry] == "hills" and not rad[sites.quarry])
        assert(dist(sites.quarry, sites.trader) >= 5)
    end
end
assert(placed >= 36, "quarries: " .. placed)

local g
repeat g = fresh() until g.sites.quarry

print("2. six torn pages start it; so do two calls to the Signal")
g.lore_read = {true, true, true, true, true}
g:story_check()
assert(not g.story.step)
g.lore_read[6] = true
g:story_check()
assert(g.story.step == "quarry" and g.sites_known.quarry)
assert(g:story_text():find("old quarry", 1, true))
local g2
repeat g2 = fresh() until g2.sites.quarry
g2.radio = {charge = 5, next = {}}
g2.player.inventory = {{item = "lora_radio", qty = 1}}
g2:open_radio()
for _ = 1, ST.signal_calls do
    g2.radio.next = {}
    g2:radio_call(4)   -- (the Signal)
end
g2:story_check()
assert(g2.story.step == "quarry", "the Signal started it")

print("3. the quarry gate is sealed without a pass")
stand(g, g.sites.quarry)
g:arrive_site()
assert(g.story.step == "gate")
g:site_action()
assert(g.screen ~= "encounter" and g.log[#g.log]:find("pass"))

print("4. Karl gives his son's pass for a right answer")
g.screen = "map"
g:start_karl()
g:karl_answer(g.enc.riddle.right)
assert(g:count_item("institute_pass") == 1 and g.story.step == "source" and g.story.pass)

print("5. ...or Anna sends hers, if you did her bandage job; otherwise she only warns you")
local g3
repeat g3 = fresh() until g3.sites.quarry
g3.story.step = "gate"
g3.radio = {charge = 5, next = {}}
g3.player.inventory = {{item = "lora_radio", qty = 1}}
g3:open_radio()
g3:radio_call(2)
assert(g3.story.warned and g3:count_item("institute_pass") == 0)
g3.story.anna = true
g3.radio.next = {}
g3:radio_call(2)
assert(g3:count_item("institute_pass") == 1 and g3.story.step == "source")

print("6. the Institute: no Multitool, no shutting it down; a failed try costs rads and time")
g.screen = "map"
stand(g, g.sites.quarry)
g:site_action()
assert(g.screen == "encounter" and g.enc.def.kind == "institute")
g:encounter_action("shut_institute")
assert(g.screen == "encounter" and not g.enc.over, "needs a Multitool")
g.player.inventory[#g.player.inventory + 1] = {item = "multitool", qty = 1}
local rads = g.player.rads or 0
g.roll = function() return false end
g:encounter_action("shut_institute")
assert(g.enc.over and (g.player.rads or 0) == rads + ST.fail_rads and g.story.retry_at)
g:encounter_action("leave")
g:site_action()
assert(g.screen ~= "encounter", "not before retry_at")

print("7. shut it down: the Quiet, an escape, its own achievement")
FAKE_FILES["/sd/wasteland/records.lua"] = nil
Game.reload_records()
g.player.hours = g.story.retry_at
g:site_action()
g.roll = function() return true end
g:encounter_action("shut_institute")
assert(g.screen == "ending" and g.ending.how == "quiet")
assert(Game.records().achieved.quiet and Game.records().escapes == 1)
g:draw_ending(400, 300)

print("8. or listen to it: every page, and you join the count")
local g4
repeat g4 = fresh() until g4.sites.quarry
g4.story.step, g4.story.pass = "source", true
g4.player.inventory = {{item = "institute_pass", qty = 1}}
stand(g4, g4.sites.quarry)
g4:site_action()
g4:encounter_action("listen_institute")
assert(g4.screen == "dead" and g4.death_cause == "You joined the count.")
assert(g4:lore_count() == #LORE.pages)

print("9. saved")
local g5
repeat g5 = fresh() until g5.sites.quarry
g5.story = {calls = 1, step = "gate", anna = true, warned = true}
assert(g5:save())
local g6 = Game.new()
g6:load_state(Game.read_save())
assert(g6.story.step == "gate" and g6.story.anna and g6.story.calls == 1)

print("STORY TESTS PASSED")
