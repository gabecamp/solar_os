-- The bigger world: generation (rivers with fords, a town, everything
-- walkable reachable), the camera, day and night, light, weather, cold,
-- campfires and resting by them.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, W = dofile("lib_world.lua")

local function key(q, r) return q .. "," .. r end
local function reachable(tiles)
    local seen, queue, i = {["0,0"] = true}, {{0, 0}}, 1
    while queue[i] do
        local c = queue[i]; i = i + 1
        for _, d in ipairs(W.AXIAL_DIRS) do
            local k = key(c[1] + d[1], c[2] + d[2])
            if tiles[k] and not seen[k] and W.TERRAIN[tiles[k]].passable then
                seen[k] = true; queue[#queue + 1] = {c[1] + d[1], c[2] + d[2]}
            end
        end
    end
    return seen
end

print("1. 40 worlds: 469 hexes, rivers with fords, ruins, start on plains, all land reachable")
local totals = {water = 0, ford = 0, ruins = 0}
for seed = 1, 40 do
    local tiles = W.generate_world(seed * 811 % 32768)
    local n, counts = 0, {}
    for _, t in pairs(tiles) do n = n + 1; counts[t] = (counts[t] or 0) + 1 end
    assert(n == 3 * W.GRID_RADIUS * (W.GRID_RADIUS + 1) + 1, "hex count " .. n)
    assert(tiles["0,0"] == "plains")
    assert((counts.ford or 0) >= 1 and (counts.water or 0) >= 10, "seed " .. seed .. ": no river")
    assert((counts.ruins or 0) >= 5, "seed " .. seed .. ": too few ruins")
    local seen = reachable(tiles)
    for k, t in pairs(tiles) do
        assert(not W.TERRAIN[t].passable or seen[k], "seed " .. seed .. ": " .. k .. " cut off")
    end
    for t, c in pairs(counts) do if totals[t] then totals[t] = totals[t] + c end end
end
print(("   OK (avg per world: water %d, fords %d, ruins %d)"):format(
    totals.water // 40, totals.ford // 40, totals.ruins // 40))

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end

print("2. the camera follows you: far from the start you're still in the middle")
local g = fresh()
g.player.q, g.player.r = W.GRID_RADIUS - 1, 0
g:refresh_view()
SPRITE_CALLS = {}   -- (the fake records every sprite)
g:draw_map(400, 300)
local marker = false
for _, c in ipairs(SPRITE_CALLS) do   -- the 7x11 stick figure, centered
    if c.w == 7 and c.h == 11 and math.abs(c.x + 3 - 128) <= 1 and math.abs(c.y + 5 - 120) <= 1 then
        marker = true
    end
end
assert(marker, "the player's marker should be at the map's center")
print("   OK")

print("3. the clock: day 1 starts at 08:00; night from 20:00 costs sight unless you hold a torch")
g = fresh()
g.weather = function() return "Clear" end   -- (fog shortens sight too; that is weather_test's)
local d, hr = g:clock()
assert(d == 1 and hr == W.WORLD.start_hour)
local sight = g.player.view_sight
g.player.hours = W.WORLD.night_from - W.WORLD.start_hour
d, hr = g:clock()
assert(hr == W.WORLD.night_from and g:is_night())
g:refresh_view()
assert(g.player.view_sight == math.max(1, sight - 1), "night shortens sight")
g.player.equipped.rhand = "torch"
g:refresh_view()
assert(g.player.view_sight == sight, "a torch lights the way")
g.player.hours = 24
assert(not g:is_night() and select(1, g:clock()) == 2)
print("   OK")

print("4. weather follows the seed, holds for a block, and changes over days")
g = fresh()
local kinds = {}
for h = 0, 24 * 10 do kinds[g:weather(h)] = true end
local n = 0
for _ in pairs(kinds) do n = n + 1 end
assert(n >= 3, "ten days should see several kinds of weather")
local b = W.WORLD.weather_block
local start = (b - W.WORLD.start_hour % b) % b
assert(g:weather(start) == g:weather(start + b - 1), "weather holds for a block")
print("   OK (" .. n .. " kinds in ten days)")

print("5. cold: under-dressed at a cold night chills you; clothes or a fire keep you warm")
g = fresh()
local p = g.player
local night = W.WORLD.night_from - W.WORLD.start_hour
local cold_hour
-- a cold-snap night long enough for step 6 (grace hours + 2, all cold)
local span = W.WORLD.cold_grace + 2
for h = night, night + 24 * 60 do
    local ok = true
    for k = 0, span do
        if g:weather(h + k) ~= "Cold snap" or not g:is_night(h + k) then ok = false; break end
    end
    if ok then cold_hour = h; break end
end
assert(cold_hour, "no long cold-snap night in two months")
p.equipped = {}
assert(g:is_cold(cold_hour))
p.equipped = {jacket = "jacket", shirt = "tshirt", pants = "jeans", feet = "boots", head = "cap",
              neck = "scarf", ears = "earmuffs", hands = "gloves"}
assert(g:warmth() >= g:cold_need(cold_hour), "enough clothes beat the cold")
assert(not g:is_cold(cold_hour))
p.equipped = {}
g.camps[key(p.q, p.r)] = {until_hour = cold_hour + 1}
assert(not g:is_cold(cold_hour), "a fire keeps you warm")
assert(g:is_cold(cold_hour + 1), "until it burns out")
print("   OK")

print("6. tick: cold hours drain rest, and past the grace hours hurt")
g = fresh(); p = g.player
p.equipped = {}
g.ticked_hour = cold_hour
p.hours = cold_hour + W.WORLD.cold_grace + 2
local hp, rest = p.health, p.needs.rest
g:tick()
assert(p.needs.rest < rest and p.health == hp - 2 * W.WORLD.cold_hurt,
       ("rest %d->%d, hp %d->%d"):format(rest, p.needs.rest, hp, p.health))
g.camps[key(p.q, p.r)] = {until_hour = p.hours + 10}
hp = p.health
p.hours = p.hours + 3
g:tick()
assert(p.health == hp and (p.cold_hours or 0) == 0, "no cold by a fire")
print("   OK")

print("7. resting by a fire restores more")
local function rest_gain(with_fire)
    local g2 = fresh()
    g2.player.mp, g2.player.needs.rest = 0, 20
    if with_fire then g2.camps["0,0"] = {until_hour = 100} end
    g2:rest()
    return g2.player.needs.rest
end
assert(rest_gain(true) > rest_gain(false))
print("   OK")

print("8. clothes have warmth; the start outfit is enough for a clear night, not a cold snap")
local start = 0
for _, item in pairs(fresh().player.equipped) do start = start + (W.ITEM_DB[item].warmth or 0) end
assert(start >= W.WORLD.need.Clear + W.WORLD.night_need)
assert(start < W.WORLD.need["Cold snap"] + W.WORLD.night_need)
print("   OK")

print("\nWORLD TESTS PASSED")
