-- Radiation and anomaly fields: generation, dose, armor, decay, sickness,
-- Anti-Rad/Vodka, the Geiger counter (reading, map marks, HUD), artifacts
-- in fields, bolts, dying of it, and saving what you measured.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, R = dofile("lib_rad.lua")
local RAD = R.RAD

local function key(q, r) return q .. "," .. r end
local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function dist(q, r) return (math.abs(q) + math.abs(r) + math.abs(q + r)) // 2 end
local function is_artifact(item) return R.ITEM_DB[item].artifact ~= nil end

print("1. 40 worlds: " .. RAD.fields .. " fields each, away from the start, an artifact at every center")
for seed = 1, 40 do
    local s = seed * 977 % 32768
    local tiles, ground, _, rad = R.generate_world(s)
    local centers = 0
    for k, level in pairs(rad) do
        assert(tiles[k], "rad on a hex that isn't there")
        assert(level >= 1 and level <= 3)
        local q, r = parse(k)
        assert(dist(q, r) >= 2, "seed " .. s .. ": hot hex " .. k .. " near the start")
        if level == 3 then
            centers = centers + 1
            local has = false
            for _, st in ipairs(ground[k] or {}) do has = has or is_artifact(st.item) end
            assert(has, "seed " .. s .. ": no artifact at the center " .. k)
        end
    end
    assert(centers == RAD.fields, "seed " .. s .. ": " .. centers .. " centers")
    local _, _, _, again = R.generate_world(s)
    for k, v in pairs(rad) do assert(again[k] == v, "same seed, same fields") end
end

-- a started game standing on a hex of the given level
local function game_on(level)
    local g = Game.new()
    g:start_game()
    for k, l in pairs(g.rad) do
        if l == level and g.tiles[k] ~= "water" then
            g.player.q, g.player.r = parse(k)
            g.ticked_hour = g.player.hours
            return g
        end
    end
    error("no hex at level " .. level)
end
local function pass_hours(g, n)
    g.player.hours = g.player.hours + n
    g:tick()
end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end

print("2. dose per hour by level, felt without a Geiger counter")
for level = 1, 3 do
    local g = game_on(level)
    pass_hours(g, 2)
    assert(g.player.rads == 2 * RAD.dose[level], "level " .. level .. ": " .. g.player.rads)
    assert(g.rad_known[key(g.player.q, g.player.r)] == level, "a dose marks the hex")
    assert(has_log(g, "skin prickles"))
end

print("3. a gas mask halves it")
local g = game_on(3)
g.player.equipped.eyes = "gasmask"
pass_hours(g, 2)
assert(g.player.rads == RAD.dose[3], tostring(g.player.rads))

print("4. rads fade away from the fields; clean hexes cost nothing")
g = game_on(1)
g.player.q, g.player.r = 0, 0
g.player.rads = 10
pass_hours(g, 4)
assert(g.player.rads == 10 - 4 * RAD.decay)

print("5. sickness stages: HP and rest per hour, conditions, panel, log")
g = game_on(1)
g.player.q, g.player.r = 0, 0
g.player.rads = RAD.stages[2].at + 5
g.player.needs.rest = 80
local hp = g.player.health
local st = RAD.stages[2]
g:rad_hour()
assert(g.player.health == hp - st.hurt and g.player.needs.rest == 80 - st.tire)
assert(g:current_conditions():find(st.name, 1, true), g:current_conditions())
assert(g:rad_text() == st.name, "no Geiger: the panel shows the stage")
g = game_on(3)
g.player.rads = RAD.stages[1].at - 1
pass_hours(g, 1)
assert(has_log(g, RAD.stages[1].name), "stage change is logged")

print("6. Anti-Rad and Vodka take rads off, never below 0")
g = game_on(1)
g.player.rads = 70
g.player.inventory = {{item = "antirad", qty = 1}, {item = "vodka", qty = 2}}
g:use_item("inventory", 1)
assert(g.player.rads == 20)
g:use_item("inventory", 1)   -- the vodka moved up
assert(g.player.rads == 0 and g.player.inventory[1].qty == 1)
g:use_item("inventory", 1)
assert(g.player.rads == 0)

print("7. Geiger counter: reads the hex and its neighbours, marks the map, clicks")
local clicks = 0
fake.audio.tone = function() clicks = clicks + 1 end
g = game_on(2)
g.player.inventory[#g.player.inventory + 1] = {item = "geiger", qty = 1}
pass_hours(g, 1)
assert(has_log(g, "Geiger crackles") and clicks >= 1, "clicks: " .. clicks)
local p = g.player
for _, d in ipairs({{0, 0}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1}}) do
    local k = key(p.q + d[1], p.r + d[2])
    if g.tiles[k] then assert(g.rad_known[k] == (g.rad[k] or 0), "read " .. k) end
end
assert(g:rad_text():match("^Geiger high Rad %d+$"), g:rad_text())
SPRITE_CALLS = {}
g:draw_map(400, 300)
local marks = 0
for _, c in ipairs(SPRITE_CALLS) do if c.w == 7 and c.data == R.GLYPHS.rad then marks = marks + 1 end end
assert(marks >= 1, "hot hexes marked on the map")

print("8. searching a level 2+ hex sometimes turns up an artifact (~" .. RAD.artifact_find .. "%)")
g = game_on(3)
local found, tries = 0, 400
for _ = 1, tries do
    g.ground[key(g.player.q, g.player.r)] = {}
    g:scavenge_field()
    for _, s in ipairs(g.ground[key(g.player.q, g.player.r)]) do
        if is_artifact(s.item) then found = found + 1 end
    end
end
assert(found > tries * RAD.artifact_find / 200 and found < tries * RAD.artifact_find * 2 / 100,
       "found " .. found)
g = game_on(1)
g.ground[key(g.player.q, g.player.r)] = {}
for _ = 1, 50 do g:scavenge_field() end
assert(#g.ground[key(g.player.q, g.player.r)] == 0, "nothing on level 1")

print("9. bolts in the bag: more throws in the bolts puzzle")
local function bolts_with(inv)
    for i = 1, 50 do
        local gg = game_on(1)
        gg.seed = i * 131   -- the puzzle kind is rolled from it
        gg.player.inventory = inv
        gg:start_puzzle()
        if gg.puz.kind == "bolts" then return gg.puz.bolts end
    end
end
assert(bolts_with({{item = "bolts", qty = 1}}) == bolts_with({}) + RAD.bolts_bonus)

print("10. radiation can kill")
g = game_on(3)
g.player.rads = RAD.max
g.player.health = 2
pass_hours(g, 1)
assert(g.screen == "dead" and g.death_cause:find("Radiation"), tostring(g.death_cause))

print("11. items: new ones have sprites and turn up in loot or the world")
for _, id in ipairs({"geiger", "gasmask", "antirad", "vodka", "bolts"}) do
    assert(R.ITEM_DB[id] and R.SPRITES[id], id)
end
local seen = {}
for _, t in pairs(R.SCAVENGE_LOOT) do for _, e in ipairs(t) do seen[e[1]] = true end end
for _, id in ipairs(RAD.world_items) do seen[id] = seen[id] or "world" end
for _, id in ipairs({"geiger", "gasmask", "antirad", "vodka", "bolts"}) do assert(seen[id], id) end

print("12. saved: rads and what you measured; the fields come back from the seed")
FAKE_FILES, FAKE_DIRS = {}, {}
g = game_on(2)
pass_hours(g, 1)
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.player.rads == g.player.rads)
for k, v in pairs(g.rad_known) do assert(g2.rad_known[k] == v) end
for k, v in pairs(g.rad) do assert(g2.rad[k] == v) end

print("RADIATION TESTS PASSED")
