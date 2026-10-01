-- Weather and seasons: fog, storms, snow, the season cycle and its effects.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local WORLD = H.WORLD

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end
local function at_day(g, day) g.player.hours = (day - 1) * 24 end

print("1. seasons run 10 days each from Autumn, round and round")
local g = fresh()
for _, case in ipairs({{1, "Autumn"}, {10, "Autumn"}, {11, "Winter"}, {21, "Spring"},
                       {31, "Summer"}, {41, "Autumn"}}) do
    at_day(g, case[1])
    assert(g:season().name == case[2], case[1] .. ": " .. g:season().name)
end

print("2. each season's weather: no rain in winter (snow), no cold snaps or snow in summer")
local function tally(day0)
    local seen = {}
    for seed = 1, 40 do
        g.weather_seed = seed * 101
        for h = 0, 9 * 24, 6 do
            local w = g:weather((day0 - 1) * 24 + h)
            seen[w] = (seen[w] or 0) + 1
        end
    end
    return seen
end
local winter, summer = tally(11), tally(31)
assert(not winter.Rain and (winter.Snow or 0) > 0 and (winter["Cold snap"] or 0) > 0)
assert(not summer["Cold snap"] and not summer.Snow and (summer.Storm or 0) > 0)

print("3. the first morning is never stormy or foggy")
for seed = 1, 300 do
    g.weather_seed = seed
    for h = 0, WORLD.calm_start - 1 do
        local w = g:weather(h)
        assert(w ~= "Storm" and w ~= "Fog", "seed " .. seed .. " hour " .. h .. ": " .. w)
    end
end

print("4. fog: shorter sight; encounters start near, and Hide works there (+15%)")
g = fresh()
g.weather = function() return "Clear" end
g:refresh_view()
local clear_sight = g.player.view_sight
g.weather = function() return "Fog" end
g:refresh_view()
assert(g.player.view_sight == math.max(1, clear_sight - 1))
local far_one
for _, d in ipairs(H.ENCOUNTERS) do if d.start == "far" and d.kind == "animal" then far_one = d end end
g:start_encounter(far_one)
assert(g.enc.range == "near" and g.enc.fog)
local has_hide = false
for _, o in ipairs(g:encounter_options()) do if o[2] == "hide" then has_hide = true end end
assert(has_hide, "Hide offered in fog at near range")
local rolled
g.roll = function(self, pct) rolled = rolled or pct; return true end
g:encounter_action("hide")
local fog_pct = rolled
local g2 = fresh()
g2.weather = function() return "Clear" end
g2:start_encounter(far_one)
rolled = nil
g2.roll = function(self, pct) rolled = rolled or pct; return true end
g2:encounter_action("hide")
assert(fog_pct == rolled + WORLD.fog_hide, fog_pct .. " vs " .. rolled)

print("5. a storm in the open wears you down; cover stops it")
g = fresh()
g.weather = function() return "Storm" end
local key = g.player.q .. "," .. g.player.r
g.tiles[key] = "plains"
local rest0, hp0 = g.player.needs.rest, g.player.health
for h = 1, WORLD.storm.grace do g:storm_hour(h) end
assert(g.player.needs.rest == rest0 - WORLD.storm.grace * WORLD.storm.rest and g.player.health == hp0)
g:storm_hour(WORLD.storm.grace + 1)
assert(g.player.health == hp0 - WORLD.storm.hurt, "hurts after the grace hours")
assert(g:death_reason() == "The storm took you.")
g.tiles[key] = "ruins"
g:storm_hour(9)
assert(g.player.storm_hours == 0, "ruins are cover")
for _, t in ipairs({"hills", "forest"}) do
    g.tiles[key] = t
    assert(not g:storm_exposed(), t .. " is cover")
end

print("6. storms halve encounters; winter is colder; summer is thirsty; autumn has more food")
g = fresh()
local base = 0
g.roll = function(self, pct) base = pct; return false end
g.enc_cooldown = 0
g.weather = function() return "Clear" end
g:maybe_encounter("forest")
local clear_pct = base
g.weather = function() return "Storm" end
g:maybe_encounter("forest")
assert(base < clear_pct, "storm encounters " .. base .. " vs " .. clear_pct)
g = fresh()
g.weather = function() return "Overcast" end
at_day(g, 2)
local autumn_need = g:cold_need()
at_day(g, 12)
assert(g:cold_need() == autumn_need + WORLD.seasons[2].need)
at_day(g, 31)
g.ticked_hour = g.player.hours
g.player.needs.thirst = 80
g.player.hours = g.player.hours + 1
local before = g.player.needs.thirst
g:tick()
local summer_drop = before - g.player.needs.thirst
at_day(g, 22)
g.ticked_hour = g.player.hours
g.player.needs.thirst = 80
g.player.hours = g.player.hours + 1
g:tick()
assert(summer_drop > 80 - g.player.needs.thirst, "summer thirst")
assert(WORLD.seasons[1].food > WORLD.seasons[2].food)

print("7. the journal names the season and the weather")
g = fresh()
at_day(g, 14)
g.weather = function() return "Storm" end
local found
for _, l in ipairs(g:journal_lines()) do if l:find("^Winter, day 4 of 10%. Storm") then found = l end end
assert(found, "journal season line")
assert(g:weather_text() == "Win Storm")

print("WEATHER TESTS PASSED")
