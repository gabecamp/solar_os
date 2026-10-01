-- The help screen (H) and the device info page (V).
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KEY = H.KEY

local texts = {}
gfx.text = function(_, _, s) texts[#texts + 1] = s end

print("1. H opens help from the map and goes back where it came from")
local g = Game.new()
g:start_game()
g:open_help()
assert(g.screen == "help")
g:draw_help(400, 300)
local all = table.concat(texts, "\n")
for _, k in ipairs({"F search", "E water", "T trade", "G hunt", "Enter +1"}) do
    assert(all:find(k, 1, true), "help doesn't mention " .. k)
end
g:help_key(KEY.Q)
assert(g.screen == "map")
g.screen = "inventory"
g:open_help()
g:help_key(KEY.SPACE)
assert(g.screen == "inventory")

print("2. V shows device info: version, memory, save support")
g.screen = "map"
g:open_help()
g:help_key(KEY.V)
assert(g.screen == "info")
texts = {}
g:draw_info(400, 300)
all = table.concat(texts, "\n")
assert(all:find("Game " .. Game.VERSION, 1, true) and all:find("KB", 1, true))
assert(all:find("Can save: yes", 1, true), "the fake has write_file")
fake.storage.write_file, saved = nil, fake.storage.write_file
texts = {}
g:draw_info(400, 300)
assert(table.concat(texts, "\n"):find("Can save: no", 1, true))
g:help_key(KEY.Q)
assert(g.screen == "map")

print("3. H is wired into the main loop")
local src = io.open("wasteland_run.lua"):read("a")
assert(src:find("game:open_help()", 1, true) and src:find("game:gather()", 1, true))

print("HELP TESTS PASSED")
