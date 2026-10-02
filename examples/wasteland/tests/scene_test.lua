-- Story moments (QUESTS.scenes, src/67_scenes.lua): each once a run, shown
-- from the map by the main loop, any key back; saved; old saves replay none.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local S = H.QUESTS.scenes

print("1. every scene fits the screen (with its portrait, if any)")
local texts = {}
local real_text = gfx.text
gfx.text = function(x, y, s)
    assert(y >= 0 and y <= 300 and x + #s * 7 <= 400, "off screen: " .. s)
    texts[#texts + 1] = s
end
for _, id in ipairs(S.order) do
    local g = Game.new()
    g.scene, g.screen = id, "scene"
    texts = {}
    g:draw_scene(400, 300)
    assert(table.concat(texts, " "):find(S[id].title, 1, true), id)
    assert(#texts <= 12, id .. ": too long")
end
gfx.text = real_text
print("   OK")

print("2. each scene queues once; shown only from the map; any key back")
local g = Game.new()
g:start_game()
assert(g.scene_queue[1] == "wake", "waking up queues the first scene")
assert(not g:queue_scene("wake"), "only once")
g.screen = "inventory"
assert(not g:show_queued_scene(), "not over another screen")
g.screen = "map"
assert(g:show_queued_scene() and g.screen == "scene" and g.scene == "wake")
g:scene_key(32)
assert(g.screen == "map" and g.scene == nil)
print("   OK")

print("3. the moments: the first night, the first emission, a warren, the quarry")
g = Game.new(); g:start_game()
g.scene_queue = {}
g:tick()
g.player.hours = g.player.hours + 24
g:tick()
assert(g.scenes_seen.first_night, "a night passed")
g.emission_news = {warn = true}
g:emission_log()
assert(g.scenes_seen.first_emission)
local key = g.extras.warrens[1]
if key then
    g.player.visible[key] = true
    g:spot_little()
    assert(g.scenes_seen.little_ones)
end
if g.sites.quarry then
    g:quarry_arrive()
    assert(g.scenes_seen.the_gate)
end
print("   OK")

print("4. saved; an old save without it replays nothing")
FAKE_FILES, FAKE_DIRS = {}, {}
g = Game.new(); g:start_game()
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.scenes_seen.wake and not g2.scenes_seen.the_gate)
local data = Game.read_save()
data.scenes_seen = nil
g2 = Game.new()
g2:load_state(data)
for _, id in ipairs(S.order) do assert(not g2:queue_scene(id), id .. " replayed") end
print("   OK")

print("\nSCENE TESTS PASSED")
