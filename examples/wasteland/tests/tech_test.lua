-- Broken tech: rare finds, repairs (and failures), the LoRa radio and its
-- voices, the Anomaly Detector, the Headlamp, the scrolling crafting list.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local TECH, ITEM_DB, KEY = H.TECH, H.ITEM_DB, H.KEY

local function fresh()
    local g = Game.new()
    g:start_game()
    g.ticked_hour = g.player.hours
    for k in pairs(g.ground) do g.ground[k] = {} end
    return g
end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end
local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    for _, it in pairs(g.player.equipped) do if it == item then n = n + 1 end end
    return n
end
local function with_roll(g, always, f)
    local real = g.roll
    g.roll = function() return always end
    f()
    g.roll = real
end
local function kit(g, fix)
    g.player.inventory = {{item = fix.broken, qty = 1}, {item = "multitool", qty = 1}}
    for part, n in pairs(fix.parts) do table.insert(g.player.inventory, {item = part, qty = n}) end
end
local function find(list, id) for _, r in ipairs(list) do if r.id == id then return r end end end

print("1. rare: broken tech only in ruins loot (weight 1), parts scattered, a radio in every world")
for _, fix in ipairs(TECH.repairs) do
    local w, total = 0, 0
    for _, e in ipairs(H.SCAVENGE_LOOT.ruins) do
        total = total + e[2]
        if e[1] == fix.broken then w = e[2] end
    end
    assert(w == 1 and total >= 70, fix.broken .. " " .. w .. "/" .. total)
    for _, item in ipairs({fix.broken, fix.out}) do assert(ITEM_DB[item] and H.SPRITES[item], item) end
end
local g = Game.new()
local radios = 0
for _, pile in pairs(g.ground) do
    for _, s in ipairs(pile) do if s.item == "broken_radio" then radios = radios + 1 end end
end
assert(radios >= 1)

print("2. repairs show on the crafting screen only while you carry the broken device")
g = fresh()
assert(not find(g:known_recipes(), "repair_broken_radio"))
kit(g, TECH.repairs[1])
local r = find(g:known_recipes(), "repair_broken_radio")
assert(r and r.repair and g:craft_blocker(r) == nil)
g.player.inventory[2] = {item = "rock", qty = 1}   -- no multitool
assert(g:craft_blocker(r):find("Multitool"))

print("3. success: the device works; failure: a part burns out, the device stays")
g = fresh()
kit(g, TECH.repairs[1])
local hours = g.player.hours
with_roll(g, false, function() g:craft(find(g:known_recipes(), "repair_broken_radio")) end)
assert(g.player.hours == hours + TECH.repair_hours and has_log(g, "sparks and dies"))
assert(count(g, "broken_radio") == 1 and count(g, "lora_radio") == 0)
local parts = 0
for part in pairs(TECH.repairs[1].parts) do parts = parts + count(g, part) end
assert(parts == 3, "one part lost")
kit(g, TECH.repairs[1])
with_roll(g, true, function() g:craft(find(g:known_recipes(), "repair_broken_radio")) end)
assert(count(g, "lora_radio") == 1 and count(g, "broken_radio") == 0 and count(g, "multitool") == 1)
assert(g.radio and g.radio.charge == TECH.radio_start)
print(("   chances at Perception 3: radio %d%%, detector %d%%, headlamp %d%%"):format(
    g:repair_chance(TECH.repairs[1]), g:repair_chance(TECH.repairs[2]), g:repair_chance(TECH.repairs[3])))
g.player.attrs.Perception = 6
assert(g:repair_chance(TECH.repairs[1]) == TECH.repairs[1].base + 3 * TECH.per_point)

print("4. the radio: R opens it, calls cost charge, voices need time, cells recharge")
g = fresh()
g:open_radio()
assert(g.screen == "map" and has_log(g, "no working radio"))
g.player.inventory = {{item = "lora_radio", qty = 1}}
g:open_radio()
assert(g.screen == "radio")
g:draw_radio(400, 300)
-- trader: a stash and the way out
g:radio_call(1)
assert(next(g.stashes) and g.sites_known.checkpoint and g.radio.charge == TECH.radio_start - 1)
g:radio_call(1)
assert(table.concat(g.radio_ui.msg, " "):find("no answer"), "cooldown")
-- anna: only when hurt
g.player.health = 100
g:radio_call(2)
assert(g.radio.charge == TECH.radio_start - 1, "a healthy call costs nothing")
g.player.health, g.player.injuries.bleeding = 50, true
g:radio_call(2)
assert(g.player.health == 70 and not g.player.injuries.bleeding)
-- karl: a hint on his next riddle
g:radio_call(3)
assert(g.karl_hint and g.radio.charge == 0)
g.radio.next.signal = nil
g:radio_call(4)
assert(table.concat(g.radio_ui.msg, " "):find("Dead air"), "no charge left")
g.player.inventory[#g.player.inventory + 1] = {item = "battery_cell", qty = 1}
g:use_item("inventory", #g.player.inventory)
assert(g.radio.charge == TECH.radio_max and count(g, "battery_cell") == 0)
-- the signal: rads, and the nearest artifact
local rads = g.player.rads or 0
local key = (g.player.q + 2) .. "," .. g.player.r
g.ground[key] = {{item = "weeping_stone", qty = 1}}
g:radio_call(4)
assert((g.player.rads or 0) == rads + TECH.signal_rads and g.player.explored[key])
g:radio_key(KEY.Q)
assert(g.screen == "map")

print("5. Karl's radio hint marks the right answer once")
g = fresh()
g.karl_hint = true
g:start_karl()
local opts = g:encounter_options()
assert(opts[g.enc.riddle.right][1]:find("Karl winks", 1, true))
g:encounter_action("answer_" .. g.enc.riddle.right)
assert(not g.karl_hint)

print("6. the Anomaly Detector reads 3 hexes out; the Headlamp lights the night")
g = fresh()
g.player.inventory = {{item = "anomaly_detector", qty = 1}}
g:geiger_scan()
local n = 0
for _ in pairs(g.rad_known) do n = n + 1 end
assert(n >= 30, "read " .. n .. " hexes")
g = fresh()
assert(not g:has_light())
g.player.equipped.head = "headlamp"
assert(g:has_light())

print("7. the crafting list scrolls when it's long")
g = fresh()
for _, rr in ipairs(H.RECIPES) do g.known[rr.id] = true end
g:open_crafting()
g.craft_ui.cursor = #g:known_recipes()
local texts = {}
local real = fake.gfx.text
fake.gfx.text = function(x, y, s) assert(y <= 300, "text off screen: " .. s); texts[#texts + 1] = s end
g:draw_craft(400, 300)
fake.gfx.text = real
local last = g:known_recipes()[#g:known_recipes()].name
local shown = false
for _, t in ipairs(texts) do shown = shown or t:find(last, 1, true) ~= nil end
assert(shown, "the selected (last) recipe is visible")

print("8. saved: the radio's charge and its voices' timers")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
g.radio = {charge = 2, next = {anna = 99}}
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.radio.charge == 2 and g2.radio.next.anna == 99)

print("TECH TESTS PASSED")
