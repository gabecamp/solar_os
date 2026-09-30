-- Saving and continuing: round trip, the save format, older SolarOS without
-- write_file, death deleting the save, bad save files, and the title screen
-- through the real main loop.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, S = dofile("lib_save.lua")
local PATH = "/sd/wasteland/save.lua"

local function same(a, b, where)
    if type(a) ~= "table" or type(b) ~= "table" then
        assert(a == b, where .. ": " .. tostring(a) .. " ~= " .. tostring(b))
        return
    end
    for k, v in pairs(a) do same(v, b[k], where .. "." .. tostring(k)) end
    for k in pairs(b) do assert(a[k] ~= nil, where .. "." .. tostring(k) .. " extra") end
end

local function played_game()
    local g = Game.new()
    g:start_game()
    for _ = 1, 6 do g:move_dir(1, 0); g:tick() end
    g:rest(); g:tick()
    g:scavenge(); g:tick()
    g:push_log('A "quoted" line\nwith a newline and \\ backslash')
    g.player.health = g.player.health - 0.25   -- a float must survive too
    return g
end

print("1. save, read back, load into a fresh game: same world and survivor")
FAKE_FILES, FAKE_DIRS = {}, {}
local g = played_game()
assert(g.player.hours > 0, "time passed")
assert(g:save())
assert(FAKE_FILES[PATH], "written to <mount>/wasteland/save.lua")
local data = Game.read_save()
assert(data, "read back")
local g2 = Game.new()
g2:load_state(data)
same(g2.tiles, g.tiles, "tiles")
for _, f in ipairs(S.SAVE.fields) do
    if f ~= "log" then same(g2[f], g[f], f) end
end
-- the log keeps 3 lines: the welcome pushes the oldest out
assert(g2.log[#g2.log - 1] == g.log[#g.log], "last saved log line kept, escapes intact")
assert(next(g2.player.visible), "sight recomputed on load")
local keep_visible = g.player.visible
g.player.visible, g2.player.visible = nil, nil
same(g2.player, g.player, "player")
g.player.visible = keep_visible
assert(g2.screen == "map")
assert(g2.log[#g2.log]:match("^Welcome back"), "welcome line")
print("   " .. #FAKE_FILES[PATH] .. " bytes")

print("2. the file is plain data, stable, and well under the 64 KiB read limit")
local text = g:save_state()
assert(text == g:save_state(), "same state, same text (sorted keys)")
assert(#text < 32768, "save is " .. #text .. " bytes")
assert(not text:find("function"), "no code in the save")

print("3. autosave only after time passes, only on map/inventory/craft")
FAKE_FILES, FAKE_DIRS = {}, {}
g = played_game()
g:autosave()
assert(FAKE_FILES[PATH], "time passed -> saved")
FAKE_FILES[PATH] = nil
g:autosave()
assert(not FAKE_FILES[PATH], "nothing changed -> no write")
g.player.hours = g.player.hours + 1
g.screen = "encounter"
g:autosave()
assert(not FAKE_FILES[PATH], "not mid-encounter")
g.screen = "inventory"
g:autosave()
assert(FAKE_FILES[PATH], "back at rest -> saved")

print("4. older SolarOS without write_file: no save, no errors, no title screen")
FAKE_FILES, FAKE_DIRS = {}, {}
local write = fake.storage.write_file
fake.storage.write_file = nil
g = played_game()
local ok, why = g:save()
assert(not ok and why:match("can't write"), tostring(why))
g:autosave()
assert(next(FAKE_FILES) == nil)
fake.storage.write_file = write

print("5. a failed write logs once and play goes on")
FAKE_FILES, FAKE_DIRS = {}, {}
fake.storage.write_file = function() error("card full") end
g = played_game()
g:autosave()
assert(g.log[#g.log] == "Couldn't save: card full", g.log[#g.log])
g:push_log("later")
g.player.hours = g.player.hours + 1
g:autosave()
assert(g.log[#g.log] == "later", "warned only once")
fake.storage.write_file = write

print("6. death deletes the save")
FAKE_FILES, FAKE_DIRS = {}, {}
g = played_game()
assert(g:save() and FAKE_FILES[PATH])
g.player.health = 0
g:check_death("test")
assert(g.screen == "dead" and not FAKE_FILES[PATH], "save removed")

print("7. bad files are ignored: garbage, code, wrong version, missing world")
FAKE_DIRS["/sd/wasteland"] = true
for _, bad in ipairs({"", "not lua at all {{{", "os.exit()", "(function() return {} end)()",
                      "{version=99,player={},world_seed=1}", "{version=1,player={}}",
                      "{version=1,world_seed=1,player=print}"}) do
    FAKE_FILES[PATH] = bad
    assert(Game.read_save() == nil, "accepted: " .. bad)
end
FAKE_FILES[PATH] = nil
assert(Game.read_save() == nil, "no file")

print("8. main loop: quit saves, the next start offers Continue and restores the run")
local function run(keys)
    local i, texts = 0, {}
    gfx.getch = function() i = i + 1; return keys[i] end
    fake.should_exit = function() return i > #keys + 2 end
    gfx.text = function(_, _, s) texts[#texts + 1] = s end
    dofile("wasteland_run.lua")
    return table.concat(texts, "\n")
end
FAKE_FILES, FAKE_DIRS = {}, {}
run({10, 100, 100, 32, 113})              -- creator, move, move, rest, quit
local first = FAKE_FILES[PATH]
assert(first, "quit saved the run")
local shown = run({113})                  -- start again: title screen, quit
assert(shown:find("Continue", 1, true), "title offers Continue")
assert(FAKE_FILES[PATH] == first, "quitting from the title leaves the save alone")
shown = run({10, 113})                    -- Continue, then quit
assert(shown:find("Welcome back", 1, true), "continued")
local again = Game.read_save()
same(again.player.q, Game.read_save().player.q, "q")
assert(again.player.hours == load("return " .. first, "=f", "t", {})().player.hours,
       "same run carried on")
shown = run({115, 10, 113})               -- New survivor: the creator
assert(shown:find("Continue", 1, true))
FAKE_FILES, FAKE_DIRS = {}, {}
shown = run({113})
assert(not shown:find("Continue", 1, true), "no save, no title")

print("SAVE TESTS PASSED")
