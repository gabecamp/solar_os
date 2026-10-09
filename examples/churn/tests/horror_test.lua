-- Night horrors: only after dark; light, fire and camp; each one's choices.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local NIGHT = H.NIGHT

local function fresh(hour)
    local g = Game.new()
    g:start_game()
    g.player.hours = hour or 14   -- day 1 starts at 08:00, so 14h in = 22:00
    g.ticked_hour = g.player.hours
    g.karl_next = 1e9
    return g
end
local function with_roll(g, always, f)
    local real = g.roll
    g.roll = function() return always end
    f()
    g.roll = real
end
local function horror(g, which)
    for _, d in ipairs(NIGHT.horrors) do
        if d.art == which then g:start_encounter(d); return g.enc end
    end
end

print("1. only at night; light and fire halve it; never at a camp with a bedroll")
local g = fresh(2)
assert(not g:is_night() and g:horror_chance() == 0)
for _ = 1, 300 do assert(not g:maybe_horror()) end
g = fresh(14)
assert(g:is_night() and g:horror_chance() == NIGHT.chance)
g.player.equipped.rhand = "torch"
assert(g:horror_chance() == NIGHT.chance / 2)
g.camps[g.player.q .. "," .. g.player.r] = {until_hour = g.player.hours + 5}
assert(g:horror_chance() == NIGHT.chance / 4)
g.base = {key = g.player.q .. "," .. g.player.r, built = {bedroll = true}}
assert(g:horror_chance() == 0)
local n, g2 = 0, fresh(14)
for _ = 1, 4000 do
    if g2:maybe_horror() then n = n + 1; g2.enc, g2.screen = nil, "map" end
end
print(("   %d horrors in 4000 night moves"):format(n))
assert(n > 100 and n < 230)

print("2. the Long Man: looking away is safe but costs rest; speaking is a coin flip")
g = fresh(14)
horror(g, "long_man")
local opts = g:encounter_options()
assert(opts[1][2] == "look_away" and opts[3][2] == "speak")
g.player.needs.rest = 50
local hp = g.player.health
g:encounter_action("look_away")
assert(g.enc.over and g.player.health == hp and g.player.needs.rest == 50 - NIGHT.dread_rest)
g = fresh(14)
horror(g, "long_man")
with_roll(g, true, function() g:encounter_action("speak") end)
local gift = false
for _, s in ipairs(g:ground_list()) do gift = gift or H.ITEM_DB[s.item].artifact ~= nil end
assert(gift, "an artifact")
g = fresh(14)
horror(g, "long_man")
hp = g.player.health
with_roll(g, false, function() g:encounter_action("speak") end)
assert(g.player.health == hp - NIGHT.madness_hurt)

print("3. the Whisperers: cover your ears, or follow (a stash, or the river)")
g = fresh(14)
horror(g, "whisper")
g.player.needs.rest = 60
g:encounter_action("cover")
assert(g.player.needs.rest == 60 - NIGHT.whisper_rest)
g = fresh(14)
horror(g, "whisper")
with_roll(g, true, function() g:encounter_action("follow") end)
assert(next(g.stashes))
g = fresh(14)
horror(g, "whisper")
hp = g.player.health
with_roll(g, false, function() g:encounter_action("follow") end)
assert(g.player.health == hp - NIGHT.follow_hurt)

print("4. the Crawler: half damage without light; light can drive it off")
g = fresh(14)
horror(g, "crawler")
assert(g:dark_damage(12) == 6)
g.player.equipped.lhand = "torch"
assert(g:dark_damage(12) == 12)
g.enc.range = "close"
with_roll(g, true, function() g:enemy_turn() end)
assert(g.enc.over and g.enc.outcome == "fled")

print("5. portraits exist")
for _, d in ipairs(NIGHT.horrors) do assert(H.PORTRAIT_DATA[d.art], d.art) end

print("HORROR TESTS PASSED")
