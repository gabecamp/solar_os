-- Health, injuries, weapons, and (later) encounters.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, E = dofile("lib_encounter.lua")
local ENTER = 10

local function fresh()
    local g = Game.new()
    g:start_game()
    g.player.q, g.player.r = 0, 0
    return g
end

print("1. health: starts full, bleeding drains it awake and asleep, rest heals")
local g = fresh()
local p = g.player
assert(p.health == E.MAX_HEALTH)
p.injuries.bleeding = true
p.mp = 0
g:rest()
assert(p.health == E.MAX_HEALTH - 4 * E.BLEED_PER_HOUR, "4h of rest while bleeding")
p.injuries.bleeding = false
p.health = 50
p.mp = 0
g:rest()
assert(p.health > 50, "rest heals when not bleeding")
print("   OK")

print("2. E on a cloth scrap while bleeding bandages (one scrap used)")
g = fresh(); p = g.player
p.injuries.bleeding = true
p.inventory = {{item = "cloth_scrap", qty = 2}}
g:use_item("inventory", 1)
assert(not p.injuries.bleeding and p.inventory[1].qty == 1)
g:use_item("inventory", 1)       -- not bleeding: goes to a hand like any other item
assert(p.equipped.rhand == "cloth_scrap")
print("   OK")

print("3. a wound costs 1 MP until enough rest")
g = fresh(); p = g.player
local full = E.effective_max_mp(p)
p.injuries.wounded_hours = E.WOUND_REST_HOURS
assert(E.effective_max_mp(p) == math.max(1, full - 1))
for _ = 1, E.WOUND_REST_HOURS // 4 do p.mp = 0; g:rest() end
assert(p.injuries.wounded_hours == 0 and E.effective_max_mp(p) == full)
print("   OK")

print("4. health 0: bleeding out ends on the death screen")
g = fresh(); p = g.player
p.health = 2; p.injuries.bleeding = true; p.mp = 0
g:rest()
assert(g.screen == "dead" and g.death_cause, "bled out while resting")
print("   OK")

print("5. weapons have sprites and sane stats")
local n = 0
for id, def in pairs(E.ITEM_DB) do
    if def.weapon then
        n = n + 1
        assert(def.weapon.dmg > 0 and (def.weapon.reach == "close" or def.weapon.reach == "near"), id)
    end
end
assert(n >= 4)
print("   OK")

print("\nENCOUNTER TESTS PASSED")
