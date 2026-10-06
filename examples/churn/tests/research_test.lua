-- Research (src/59_research.lua): nothing beyond survival is known at the
-- start; studying at a fire or camp, books, cassettes and USB drives teach
-- a topic's recipes in order; it's all saved. Also the property inputs
-- (@sharp, @fire_container, @heat...) and the new things E does.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, C = dofile("lib_crafting.lua")

local function fresh()
    local g = Game.new()
    g:start_game()
    g.player.inventory = {}
    g.ground[g.player.q .. "," .. g.player.r] = {}
    g.player.equipped = {back = "backpack"}   -- (room in the bag)
    return g
end
local function recipe(id)
    for _, r in ipairs(C.RECIPES) do if r.id == id then return r end end
    error("no recipe " .. id)
end
local function has_log(g, s)
    for _, l in ipairs(g.log) do if l:find(s, 1, true) then return true end end
    return false
end
local function give(g, item, n) table.insert(g.player.inventory, {item = item, qty = n or 1}) end
local function bag_count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    return n
end
local function topic_count(topic)
    local n = 0
    for _, r in ipairs(C.RECIPES) do if r.topic == topic then n = n + 1 end end
    return n
end

print("1. only bare survival is known; every topic teaches something")
local g = fresh()
local known = 0
for _, r in ipairs(C.RECIPES) do if g.known[r.id] then known = known + 1 end end
assert(known <= 16, "too much known at the start: " .. known)   -- (16: the camp's fire pit)
for _, id in ipairs({"torch", "campfire", "bandage", "rag_shirt", "foot_wraps", "fire_drill"}) do
    assert(g.known[id], id .. " known")
end
for _, id in ipairs({"shiv", "spear", "rope", "machete", "bow", "assemble_pm", "elder_sign"}) do
    assert(not g.known[id], id .. " not known")
end
for _, t in ipairs(C.CHURN.topics) do
    assert(topic_count(t.id) >= 4, t.id .. " teaches too little")
    assert(C.ITEM_DB[t.book] and C.ITEM_DB[t.book].book == t.id, t.id .. ": its book")
    for _, id in ipairs(t.needs or {}) do assert(C.ITEM_DB[id], t.id .. " needs " .. id) end
end
for item, tape in pairs(C.CHURN.tapes) do
    assert(C.ITEM_DB[item] and C.SPRITES[item], item)
    local ok = false
    for _, t in ipairs(C.CHURN.topics) do ok = ok or t.id == tape.topic end
    assert(ok, item .. ": topic")
end
print("   OK (" .. known .. " known at the start)")

print("2. study: only by a fire or at camp; points, then the topic's next recipe")
g = fresh()
local study
for _, r in ipairs(g:known_recipes()) do if r.study == "bushcraft" then study = r end end
assert(study, "a Study entry on the crafting screen")
assert(g:craft_blocker(study):find("fire"), "no fire, no study")
g.camps[g.player.q .. "," .. g.player.r] = {until_hour = g.player.hours + 100}
assert(g:craft_blocker(study) == nil)
local first = g:topic_next("bushcraft")
local h0, sessions = g.player.hours, 0
while not g.known[first.id] and sessions < 10 do
    assert(g:craft(study))
    sessions = sessions + 1
end
assert(g.known[first.id], "studying teaches " .. first.id)
assert(g.player.hours == h0 + sessions * C.CHURN.study.hours, "study takes hours")
assert(sessions >= 2, "it takes more than one session")
assert(has_log(g, first.name))
-- a book in reach doubles the points
local p0 = g:study_points("bushcraft")
give(g, "book_field")
assert(g:study_points("bushcraft") == p0 * C.CHURN.study.book_mult)
print("   OK (" .. sessions .. " sessions for " .. first.name .. ")")

print("3. some topics need something to study from")
g = fresh()
g.camps[g.player.q .. "," .. g.player.r] = {until_hour = g.player.hours + 100}
assert(g:study_blocker("gunsmithing"):find("Nothing to study"))
assert(g:study_blocker("warding"):find("Nothing to study"))
give(g, "gun_barrel")
assert(g:study_blocker("gunsmithing") == nil, "a gun part will do")
give(g, "ichor")
local rest = g.player.needs.rest
local ward
for _, r in ipairs(g:known_recipes()) do if r.study == "warding" then ward = r end end
assert(g:craft(ward))
assert(g.player.needs.rest < rest - 10, "warding costs you")
print("   OK")

print("4. books: the first read teaches, later reads add points")
g = fresh()
give(g, "book_surgeon")
local med = g:topic_next("medicine")
g:use_item("inventory", 1)
assert(g.known[med.id] and bag_count(g, "book_surgeon") == 1, "a book isn't used up")
local med2 = g:topic_next("medicine")
g:use_item("inventory", 1)
assert(not g.known[med2.id] and (g.research.medicine or 0) > 0, "a reread only helps")
print("   OK")

print("5. cassettes: need a charged player; the tape plays once")
g = fresh()
give(g, "tape_gun")
g:use_item("inventory", 1)
assert(has_log(g, "Cassette Player") and bag_count(g, "tape_gun") == 1)
give(g, "cassette_player")
g:use_item("inventory", 1)
assert(has_log(g, "Battery Cell") and bag_count(g, "tape_gun") == 1, "a dead player")
give(g, "battery_cell")
g:use_item("inventory", 3)
assert(bag_count(g, "battery_cell") == 0 and g.tapedeck.charge == C.CHURN.study.tape_max)
local gun = g:topic_next("gunsmithing")
g:use_item("inventory", 1)
assert(g.known[gun.id], "the tape teaches " .. gun.id)
assert(bag_count(g, "tape_gun") == 0 and bag_count(g, "blank_tape") == 1)
assert(g.tapedeck.charge == C.CHURN.study.tape_max - 1)
print("   OK")

print("6. USB drives: the LoRa radio reads them for a charge")
g = fresh()
give(g, "usb_drive")
g:use_item("inventory", 1)
assert(has_log(g, "LoRa Radio") and bag_count(g, "usb_drive") == 1)
give(g, "lora_radio")
g.radio = {charge = 5, next = {}}
local before, tries = 0, 0
for _, r in ipairs(C.RECIPES) do if g.known[r.id] then before = before + 1 end end
while bag_count(g, "usb_drive") == 1 and tries < 20 do
    g:use_item("inventory", 1)
    tries = tries + 1
    g.radio.charge = 5
end
assert(bag_count(g, "usb_drive") == 0, "the drive was read")
local after = 0
for _, r in ipairs(C.RECIPES) do if g.known[r.id] then after = after + 1 end end
assert(after >= before, "it may teach")
g.radio.charge = 0
give(g, "usb_drive")
g:use_item("inventory", #g.player.inventory)
assert(has_log(g, "no charge"))
print("   OK")

print("7. properties: any sharp edge, the cheapest first; pots and heat")
g = fresh()
assert(Game.input_name("@sharp") == "sharp edge" and Game.input_name("rope") == "Rope")
give(g, "knife"); give(g, "glass_shard", 2)
assert(g:count_item("@sharp") == 3)
assert(g:take_items("@sharp", 1) and bag_count(g, "glass_shard") == 1 and bag_count(g, "knife") == 1,
       "the glass goes before the knife")
g = fresh()
g.known.stone_knife = true
give(g, "rock", 2)
assert(g:craft(recipe("stone_knife")) and bag_count(g, "stone_knife") == 1)
g = fresh()
give(g, "stick", 3); give(g, "rock", 1)
assert(g:craft_blocker(recipe("campfire")):find("heat source"))
give(g, "fire_drill")
assert(g:craft(recipe("campfire")) and g:fire_here() and bag_count(g, "fire_drill") == 1)
give(g, "dirty_water"); give(g, "empty_bottle")
assert(g:craft_blocker(recipe("boil")):find("fireproof pot"), "a plastic bottle melts")
give(g, "metal_pot")
assert(g:craft(recipe("boil")))
print("   OK")

print("8. small fire: one fuel, burns 4h")
g = fresh()
give(g, "newspaper"); give(g, "matches")
assert(g:craft(recipe("small_fire")))
local camp = g.camps[g.player.q .. "," .. g.player.r]
assert(camp.until_hour == g.player.hours + 4 and bag_count(g, "newspaper") == 0)
print("   OK")

print("9. placed things: rattle, lean-to, salt circle")
g = fresh()
give(g, "salt_circle"); give(g, "tarp_shelter"); give(g, "can_rattle")
g.is_night = function() return true end
local c0 = g:horror_chance()
g:use_item("inventory", 1)
assert(g:placed_here("salt_circle") and g:horror_chance() == c0 / 4)
g:use_item("inventory", 1)
assert(g:placed_here("tarp_shelter"))
g.weather = function() return "Storm" end
g.tiles[g.player.q .. "," .. g.player.r] = "plains"
assert(not g:storm_exposed(), "the lean-to keeps the storm off")
g:use_item("inventory", 1)
assert(g:placed_here("can_rattle"))
g:start_encounter({kind = "animal", name = "Jawhound", who = "jawhound", hp = 30, dmg = {6, 12},
                   hit = 60, speed = 4, start = "close", intro = "x", loot = {{"nothing", 1}}})
assert(g.enc.range == "far", "the cans gave you warning")
print("   OK")

print("10. bark tea settles sickness; worn fx: the travois slows you")
g = fresh()
g.player.sick_hours = 20
give(g, "bark_tea")
g:use_item("inventory", 1)
assert(g.player.sick_hours == 0)
local mp = g.player.max_mp
g.player.equipped.back = "travois"
g:set_difficulty(g.difficulty)   -- (recomputes the stats)
assert(g.player.max_mp == mp - 1, "a travois is heavy")
print("   OK")

print("11. lockpicks open some ruin crates, once per hex")
g = fresh()
give(g, "lockpicks")
local opened = 0
for k, t in pairs(g.tiles) do
    if t == "ruins" then
        g.player.q, g.player.r = Game.key_qr(k)
        local n = #g:ground_list()
        g:pick_crate(k)
        if #g:ground_list() > n then opened = opened + 1 end
        local m = #g:ground_list()
        g:pick_crate(k)
        assert(#g:ground_list() == m, "once per hex")
    end
end
assert(opened > 0, "some crates")
print("   OK (" .. opened .. " crates)")

print("12. research, books read, the tape deck and placed things are saved")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
g.research = {medicine = 5}
g.books_read = {book_lab = true}
g.tapedeck = {charge = 2}
g.placed = {["0,0"] = {salt_circle = true}}
g.gun_wear = {pm_pistol = 70}
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.research.medicine == 5 and g2.books_read.book_lab and g2.tapedeck.charge == 2)
assert(g2.placed["0,0"].salt_circle and g2.gun_wear.pm_pistol == 70)
print("   OK")

print("\nRESEARCH TESTS PASSED")
