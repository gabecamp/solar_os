-- Regression tests for the 2026-10-01 code review findings.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local RAD, TECH, KEY = H.RAD, H.TECH, H.KEY

local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function fresh()
    local g = Game.new()
    g:start_game()
    g.ticked_hour = g.player.hours
    return g
end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end

print("1. an old save (no next_emission) still gets emissions")
FAKE_FILES, FAKE_DIRS = {}, {}
local g = fresh()
g.player.hours = 300
g.next_emission = nil
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.next_emission > 300, "rescheduled: " .. tostring(g2.next_emission))
g2.ticked_hour = g2.player.hours
for _ = 1, RAD.emission.every[1] + RAD.emission.hours + 1 do
    g2.player.needs.thirst, g2.player.needs.hunger, g2.player.health = 100, 100, 100
    g2.player.hours = g2.player.hours + 1
    g2:tick()
end
assert(g2.next_emission > 300 + RAD.emission.every[1], "and it came and moved on")

print("2. a failed snare check resets its clock (no re-rolling the same hours)")
g = fresh()
for k, t in pairs(g.tiles) do if t == "forest" then g.player.q, g.player.r = parse(k); break end end
local key = g.player.q .. "," .. g.player.r
g.snares[key] = {set = g.player.hours - 40}
local real = g.roll
g.roll = function() return false end
g:check_snare()
g.roll = real
assert(g.snares[key].set == g.player.hours)

print("3. a worn belt is painted on the doll")
local rects = 0
local real_fill = fake.gfx.fill_rect
g = fresh()
fake.gfx.fill_rect = function(...) rects = rects + 1; return real_fill(...) end
g:draw_silhouette()   -- (the doll the bag screen's tiles are cut from)
local without = rects
rects = 0
g.player.equipped.belt = "leather_belt"
g:draw_silhouette()
fake.gfx.fill_rect = real_fill
assert(rects > without, "belt adds paint")

print("4. a radio call to the trader that gives nothing costs nothing")
g = fresh()
g.player.inventory = {{item = "lora_radio", qty = 1}}
g:open_radio()
g:learn_site("trader"); g:learn_site("checkpoint")
g.mark_stash = function() return false end
local charge = g.radio.charge
g:radio_call(1)
assert(g.radio.charge == charge and not g.radio.next.trader)

print("5. a full radio keeps the battery cell")
g.radio.charge = TECH.radio_max
g.player.inventory[#g.player.inventory + 1] = {item = "battery_cell", qty = 1}
g:use_item("inventory", #g.player.inventory)
local cells = 0
for _, s in ipairs(g.player.inventory) do if s.item == "battery_cell" then cells = s.qty end end
assert(cells == 1 and has_log(g, "fully charged"))

print("6. with only the Anomaly Detector, nothing says Geiger")
g = fresh()
for k, l in pairs(g.rad) do if l == 2 then g.player.q, g.player.r = parse(k); break end end
g.player.inventory = {{item = "anomaly_detector", qty = 1}}
g.player.hours = g.player.hours + 1
g:tick()
assert(has_log(g, "Detector crackles") and not has_log(g, "Geiger"))
assert(g:rad_text():find("^Detect"))

print("7. Anna's channel stays open after you bring her the bandages")
g = fresh()
g.player.inventory = {{item = "lora_radio", qty = 1}, {item = "bandage", qty = 2}}
g:open_radio()
g.quest = {kind = "supply", giver = "Anna"}
g:radio_call(2)
assert(not g.quest and g.radio.next.anna == nil)

print("REVIEW FIX TESTS PASSED")
