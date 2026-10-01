-- Emissions, stashes, the splint and filtering water.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, R = dofile("lib_rad.lua")
local RAD = R.RAD
local E = RAD.emission

local function key(q, r) return q .. "," .. r end
local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function fresh()
    local g = Game.new()
    g:start_game()
    -- dressed warm enough for any weather, so the cold doesn't blur the numbers
    for slot, item in pairs({jacket = "jacket", head = "cap", hands = "gloves", neck = "scarf"}) do
        g.player.equipped[slot] = item
    end
    g.ticked_hour = g.player.hours
    return g
end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end
local function stand_on(g, terrain)
    for k, t in pairs(g.tiles) do
        if t == terrain and not (g.rad[k]) then g.player.q, g.player.r = parse(k); return end
    end
    error("no " .. terrain)
end
local function to_hour(g, h)   -- let time pass up to hour h, with needs kept up
    while g.player.hours < h do
        g.player.needs.thirst, g.player.needs.hunger, g.player.needs.rest = 100, 100, 100
        g.player.hours = g.player.hours + 1
        g:tick()
    end
end

print("1. the warning comes " .. E.warn .. "h ahead and shows on the panel")
local g = fresh()
stand_on(g, "ruins")
to_hour(g, E.first - E.warn + 1)   -- the hour starting at first-warn has passed
assert(has_log(g, "Emission in"), "warned")
assert(g:emission_text() == "EMIT " .. (E.warn - 1) .. "h", tostring(g:emission_text()))

print("2. sheltered in ruins it passes you by")
local hp, rads = g.player.health, g.player.rads or 0
to_hour(g, E.first + E.hours)
assert(g.player.health >= hp and (g.player.rads or 0) <= rads, "ruins shelter you")
assert(has_log(g, "emission passes"))
assert(g.next_emission >= E.first + E.every[1] and g.next_emission <= E.first + E.every[2])

print("3. caught in the open: HP and rads, and it can kill")
g = fresh()
stand_on(g, "plains")
to_hour(g, E.first - 1)
hp, rads = g.player.health, g.player.rads or 0
to_hour(g, E.first + E.hours)
assert(g.player.health <= hp - E.hurt + 1, hp .. " -> " .. g.player.health)
assert((g.player.rads or 0) >= rads + E.rads - 5)
g = fresh()
stand_on(g, "plains")
to_hour(g, E.first)
g.player.health = 5
to_hour(g, E.first + 1)
assert(g.screen == "dead" and g.death_cause:find("emission"), tostring(g.death_cause))

print("4. afterwards every field center has an artifact again")
g = fresh()
stand_on(g, "ruins")
for k, l in pairs(g.rad) do if l == 3 then g.ground[k] = {} end end
to_hour(g, E.first + E.hours)
for k, l in pairs(g.rad) do
    if l == 3 then
        local has = false
        for _, s in ipairs(g.ground[k] or {}) do has = has or R.ITEM_DB[s.item].artifact ~= nil end
        assert(has, "no artifact regrown at " .. k)
    end
end

print("5. a stash from the notes: on the map, then dug up")
g = fresh()
g.player.q, g.player.r = 0, 0
assert(g:mark_stash())
local sk = next(g.stashes)
local q, r = parse(sk)
local d = (math.abs(q) + math.abs(r) + math.abs(q + r)) // 2
assert(d >= RAD.stash.near and d <= RAD.stash.far)
assert(#g.ground[sk] >= 1 and g.player.explored[sk])
assert(has_log(g, "mark a stash"))
g.player.q, g.player.r = q, r
g:find_stash()
assert(next(g.stashes) == nil and has_log(g, "dig up the stash"))

print("6. the splint shortens a wound; filtering water needs no fire")
g = fresh()
g.player.injuries.wounded_hours = 20
g.player.inventory = {{item = "splint", qty = 1}}
g:use_item("inventory", 1)
assert(g.player.injuries.wounded_hours == 8 and #g.player.inventory == 0)
g.player.inventory = {{item = "dirty_water", qty = 1}, {item = "cloth_scrap", qty = 1}}
local filter
for _, rr in ipairs(g:known_recipes()) do if rr.id == "filter" then filter = rr end end
assert(filter and g:craft(filter))
local clean = false   -- (the cloth may come off the ground: inputs use the ground first)
for _, st in ipairs(g.player.inventory) do clean = clean or st.item == "water_bottle" end
assert(clean)

print("7. saved: when the next emission comes, and the stashes")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
g.next_emission = 123
g.player.q, g.player.r = 0, 0
g:mark_stash()
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.next_emission == 123 and next(g2.stashes) == next(g.stashes))

print("EVENTS TESTS PASSED")
