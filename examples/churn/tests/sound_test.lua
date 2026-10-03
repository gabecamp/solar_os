-- Sound effects and mute.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")

local played = {}
fake.audio.tone_async = function(hz, ms, vol) played[#played + 1] = {hz, ms, vol} end

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end

print("1. every effect queues notes through tone_async")
local g = fresh()
for _, name in ipairs({"hit", "miss", "hurt", "kill", "geiger", "siren", "emission", "chime",
                       "gift", "death", "escape", "bark", "whine"}) do
    played = {}
    g:sfx(name)
    assert(#played > 0, name .. " played nothing")
    for _, n in ipairs(played) do
        assert(math.type(n[1]) == "integer" and math.type(n[2]) == "integer", name .. ": integer args")
    end
end

print("2. M mutes everything, and it's saved")
g:toggle_mute()
played = {}
g:sfx("hit")
assert(#played == 0 and g.muted)
FAKE_FILES, FAKE_DIRS = {}, {}
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.muted, "mute survives a reload")
g:toggle_mute()
g:sfx("hit")
assert(#played > 0 and not g.muted)

print("3. events make sounds: death, crafting, fights")
g = fresh()
g.player.health = 0
g:check_death("test")
assert(g.last_sfx == "death")
g = fresh()
g.player.inventory = {{item = "cloth_scrap", qty = 2}}
for k in pairs(g.ground) do g.ground[k] = {} end
local bandage
for _, r in ipairs(H.RECIPES) do if r.id == "bandage" then bandage = r end end
assert(g:craft(bandage) and g.last_sfx == "chime")

print("4. no audio at all: silent, no errors")
local saved = fake.audio
fake.audio = nil
g:sfx("hit")
fake.audio = saved

print("5. M is wired on the map")
local src = io.open("churn_run.lua"):read("a")
assert(src:find("game:toggle_mute()", 1, true))

print("SOUND TESTS PASSED")
