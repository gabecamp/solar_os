-- Fixes from the second code review (skills, records, the speed work).
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local REC = "/sd/wasteland/records.lua"

-- 1. a board without gfx.bitmap / gfx.sprite still shows you on the map
do
    local sprite, bitmap = gfx.sprite, gfx.bitmap
    gfx.sprite, gfx.bitmap = nil, nil
    local Game = dofile("lib_hunt.lua")   -- (captures the missing bitmap call)
    gfx.sprite, gfx.bitmap = sprite, bitmap
    local g = Game.new()
    g:start_game()
    local marker = false
    local real = gfx.fill_rect
    gfx.fill_rect = function(x, y, w, h)
        if w == 6 and h == 6 and math.abs(x + 3 - 128) <= 1 and math.abs(y + 3 - 120) <= 1 then marker = true end
        return real(x, y, w, h)
    end
    g:draw_map(400, 300)
    gfx.fill_rect = real
    assert(marker, "the player's block marker is drawn without bitmaps")
    print("1. no bitmaps: the player is still on the map")
end

local Game, H = dofile("lib_hunt.lua")
local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end

print("2. a cut-short records file is kept aside, not wiped")
FAKE_FILES[REC] = "{runs = 7, escapes = 2, ach"
Game.reload_records()
local rec = Game.records()
assert(rec.runs == 0 and rec.achieved and rec.deaths and rec.counted)
assert(Game.write_records())
assert(FAKE_FILES["/sd/wasteland/records.bad.lua"] == "{runs = 7, escapes = 2, ach", "the old file kept")

print("3. a records file with wrong types doesn't crash anything")
FAKE_FILES[REC] = '{runs = "3", achieved = 1, best_escape = "insane", deaths = {x = 0, y = "2"}, kills = -4}'
Game.reload_records()
rec = Game.records()
assert(rec.runs == 3 and rec.kills == 0 and rec.best_escape == nil and next(rec.achieved) == nil)
assert(rec.deaths.y == 2 and rec.deaths.x == nil)
local g = fresh()
g:tick()                      -- (checks achievements)
g:records_lines()
g:draw_records(400, 300)

print("4. a run is counted once, even when its save is continued")
FAKE_FILES[REC] = nil
Game.reload_records()
g = fresh()
g.player.health = 0
g:check_death("You starved.")
local again = Game.new()
again.world_seed = g.world_seed   -- (the same run, continued from a save that wasn't deleted)
again:start_game()
again.player.health = 0
again:check_death("You starved.")
assert(Game.records().runs == 1, "counted twice")

print("5. a run's end writes the records once")
FAKE_FILES[REC] = nil
Game.reload_records()
local writes = 0
local real_write = fake.storage.write_file
fake.storage.write_file = function(path, data) if path == REC then writes = writes + 1 end return real_write(path, data) end
g = fresh()
g.player.hours = 30            -- First Steps unlocks at the end
g.player.health = 0
g:check_death("You starved.")
fake.storage.write_file = real_write
assert(writes == 1, "wrote " .. writes .. " times")

print("6. a hex mask with nothing in it is empty, not endless")
local m = Game.hex_mask(1)
assert(#m.fill == 0)

print("7. something in your hand doesn't rebuild the doll")
g = fresh()
local tiles = g:doll_tiles()
g.player.equipped.rhand = "knife"
assert(g:doll_tiles() == tiles, "rebuilt for a held item")
g.player.equipped.head = "cap"
assert(g:doll_tiles() ~= tiles, "not rebuilt for a worn one")

print("8. the main loop turns the fast event pump off before gfx.end, even after an error")
local main = io.open("../src/90_main.lua"):read("a")
local off, fin = main:find("Game.draw_pump(false)\ngfx[\"end\"]()", 1, true)
assert(off, "draw_pump(false) right before gfx.end")

print("REVIEW 2 TESTS PASSED")
