-- Records: run stats, the lifetime records file, achievements, the screens.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KEY = H.KEY
local REC_PATH = "/sd/wasteland/records.lua"

local texts = {}
local real_text = gfx.text
gfx.text = function(x, y, s)
    assert(y <= 300 and y >= 0, "off screen: " .. s)
    assert(x + #s * 7 <= 400, "too wide: " .. s)
    texts[#texts + 1] = s
end
local function screen_text() local s = table.concat(texts, "\n"); texts = {}; return s end

local runs_made = 0
local function fresh()
    local g = Game.new()
    g:start_game()
    runs_made = runs_made + 1
    g.world_seed = 9000 + runs_made   -- (each a different run: one fake clock seeds them all alike)
    return g
end
local function achieved(id) return Game.records().achieved[id] == true end

print("1. stats count up: searches, kills, fish, riddles, repairs, artifacts")
local g = fresh()
g.player.mp = 5
g:scavenge()
assert(g:stat_of("searches") == 1)
g.roll = function() return true end
g.maybe_karl = function() end
g:fish()
assert(g:stat_of("fish") == 1)
g:hunt()
g.enc.range, g.enc.hp = "close", 1
g:encounter_action("attack")
assert(g:stat_of("kills") == 1, "kill counted")
g.screen = "map"
g.player.q, g.player.r = 0, 0
g.rad = {["0,0"] = 3}
g:scavenge_field()
assert(g:stat_of("artifacts") == 1)

print("2. stats are saved with the run")
g.stats.riddles = 2
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2:stat_of("riddles") == 2 and g2:stat_of("kills") == 1)

print("3. a death is recorded once, in the records file, and survives a new game")
Game.reload_records()
FAKE_FILES[REC_PATH] = nil
g = fresh()
g.stats = {kills = 4}
g.player.hours = 30
g.player.health = 0
assert(g:check_death("You starved."))
g:check_death("You starved.")       -- (a second call doesn't count twice)
assert(FAKE_FILES[REC_PATH], "records written")
assert(not FAKE_FILES["/sd/wasteland/save.lua"], "the save is gone, the records aren't")
Game.reload_records()
local rec = Game.records()
assert(rec.runs == 1 and rec.kills == 4 and rec.longest == 30 and rec.deaths["You starved."] == 1)
assert(achieved("first_steps"), "day 2 reached at 30 h")
assert(not achieved("week"))

print("4. the death screen shows the run summary")
g:draw_dead(400, 300)
local s = screen_text()
assert(s:find("Kills 4", 1, true) and s:find("R: records", 1, true), s)

print("5. an escape: Out, Paper Trail, records; a second run beats the longest")
g = fresh()
g.player.hours = 200
g.player.inventory = {{item = "permit", qty = 1}, {item = "weeping_stone", qty = 2}}
g:finish_run("permit")
assert(achieved("out") and achieved("paper") and achieved("week"))
assert(not achieved("bribed") and not achieved("hardened"))
rec = Game.records()
assert(rec.escapes == 1 and rec.runs == 2 and rec.longest == 200 and rec.best_escape == "normal")
assert(g.run_best[1] == "longest run")
g:draw_ending(400, 300)
s = screen_text()
assert(s:find("New record: longest run", 1, true) and s:find("Achievements this run", 1, true), s)

print("6. Bribed and Zone-Hardened")
g = fresh()
g.difficulty = "hard"
g.player.inventory = {{item = "weeping_stone", qty = 3}}
g:pay_bribe()
g:finish_run("bribe")
assert(achieved("bribed") and achieved("hardened") and Game.records().best_escape == "hard")

print("7. mid-run achievements unlock from tick, once, with a log line")
g = fresh()
g.dog = {hp = 30, fed_hour = 0, hungry_days = 0}
g.stats = {riddles = 3, repairs = 1, horrors = 3}
g.lore_read = {}
for i = 1, #LORE.pages do g.lore_read[i] = true end
g.base = {key = "0,0", built = {box = true, bedroll = true, barrel = true, barricade = true}}
g:tick()
for _, id in ipairs({"dog", "karl", "fixer", "night_owl", "archivist", "homeowner"}) do
    assert(achieved(id), id)
end
assert(g.last_sfx == "achieve")
local n = g.run_unlocked
g:tick()
assert(g.run_unlocked == n, "unlocked once")

print("8. horrors lived through are counted; other encounters aren't")
g = fresh()
local long_man, boar
for _, d in ipairs(H.NIGHT.horrors or {}) do if d.horror == "long_man" then long_man = d end end
assert(long_man, "no long man")
g:start_encounter(long_man)
g:end_encounter("gone")
assert(g:stat_of("horrors") == 1)
g:start_encounter({kind = "animal", who = "boar", name = "Boar", intro = "A boar.", hp = 10, start = "far"})
g:end_encounter("gone")
assert(g:stat_of("horrors") == 1)

print("9. the records screen: from the title, any key back; all fits")
g = Game.new()
g.screen = "title"
g:open_records()
assert(g.screen == "records")
g:draw_records(400, 300)
s = screen_text()
assert(s:find("Achievements 12/12", 1, true), s)
assert(s:find("[x] Night Owl", 1, true))
g:records_key(KEY.Q)
assert(g.screen == "title")

print("10. without write_file: records last the session, nothing breaks")
local write = fake.storage.write_file
fake.storage.write_file = nil
Game.reload_records()
FAKE_FILES[REC_PATH] = nil
g = fresh()
g.player.health = 0
g:check_death("You froze to death.")
assert(Game.records().runs == 1)
g:draw_records(400, 300)
assert(screen_text():find("not saved", 1, true))
fake.storage.write_file = write

print("RECORDS TESTS PASSED")
