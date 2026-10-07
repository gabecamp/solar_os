-- Lockpicking, scanning the band, dread, the bestiary, what's left of you,
-- and mutations (src/64_*.lua).
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game = dofile("lib_layout.lua")
local UP, DOWN, LEFT, RIGHT, ENTER, SPACE, Q = gfx.KEY_UP, gfx.KEY_DOWN, gfx.KEY_LEFT, gfx.KEY_RIGHT, 10, 32, 113

local function fresh()
    FAKE_FILES, FAKE_DIRS = {}, {}
    Game.reload_records()
    local g = Game.new()
    g:start_game()
    g.no_hints = true
    g.player.inventory = {}
    return g
end
local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    for _, s in ipairs(g:ground_list()) do if s.item == item then n = n + s.qty end end
    return n
end
local function has_log(g, pat)
    for _, l in ipairs(g.log) do if l:find(pat, 1, true) then return true end end
    return false
end

print("1. lockpicking: set every pin to open it; strain too often and the pick snaps")
local g = fresh()
local opened = false
g:lock_start(4, function() opened = true end)
assert(g.screen == "lockpick" and #g.lock.pins == 4)
local L = g.lock
while not L.over do
    for _ = 1, L.pins[L.i] do g:lockpick_key(UP) end
    g:lockpick_key(ENTER)
end
assert(opened and L.strain == 0)
g:lockpick_key(SPACE)
assert(g.screen == "map" and g.lock == nil)
g = fresh()
g.player.inventory = {{item = "lockpicks", qty = 2}}
opened = false
g:lock_start(4, function() opened = true end)
L = g.lock
for _ = 1, 3 do g:lockpick_key(ENTER) end   -- (at notch 0: it slips, three times)
assert(L.over and not opened and count(g, "lockpicks") == 1, "snapped: one pick gone")
g = fresh()
g:lock_start(4, function() end)
L = g.lock
L.pins[1] = 2
g:lockpick_key(UP); g:lockpick_key(UP); g:lockpick_key(UP)
assert(L.strain == 1 and L.h == 0, "past it: strain, the pin drops")
g:lockpick_key(Q)
assert(g.screen == "map" and has_log(g, "leave the lock"))

print("2. a ruin's locked crate waits for another try after a broken pick")
g = fresh()
local key = g.player.q .. "," .. g.player.r
g.tiles[key] = "ruins"
g.player.inventory = {{item = "lockpicks", qty = 3}}
g.roll = function() return true end
g:pick_crate(key)
assert(g.screen == "lockpick" and g.crates[key] == "locked")
g:lockpick_key(Q)
g:pick_crate(key)
assert(g.screen == "lockpick", "F again: back at the lock")

print("3. scanning: stations each day, a signal near them, listening costs a charge")
g = fresh()
g.player.inventory = {{item = "lora_radio", qty = 1}}
g:open_radio()
g.radio.charge = 5
local list = g:scan_stations()
assert(#list >= 2 and #list <= 3)
for _, st in ipairs(list) do assert(st.f ~= 433 and st.f >= 400 and st.f <= 470) end
g.radio_ui.cursor = 5
g:radio_key(ENTER)
assert(g.radio_ui.scan, "the last row scans")
local st = list[1]
g.radio_ui.scan.f = st.f - 3
g:radio_key(ENTER)
assert(g.radio.charge == 5, "too faint: nothing heard, nothing spent")
g.radio_ui.scan.f = st.f - 1
g:radio_key(RIGHT)
assert(g:scan_signal(g.radio_ui.scan.f) > 4)
g:radio_key(ENTER)
assert(g.radio.charge == 4 and st.heard)
for _, kind in ipairs({"stash", "site", "body", "voice"}) do
    local d0 = g.player.dread or 0
    local text = g:scan_listen(kind)
    assert(type(text) == "string" and #text > 0, kind)
    if kind == "voice" then assert(g.player.dread > d0, "a voice: dread") end
end
assert(g.radio_body, "a voice for help marks where")
g.player.q, g.player.r = Game.key_qr(g.radio_body)
g:scan_arrive()
assert(g.radio_body == nil and has_log(g, "The one who called"))
g.radio_ui.scan = g.radio_ui.scan or {f = 430}
g:radio_key(Q)
assert(g.radio_ui.scan == nil and g.screen == "radio", "Q: back to the channels")
g.scan.day = -1
assert(g:scan_stations() ~= list, "tomorrow, new stations")

print("4. dread: rises and eases; the tiers; phantoms vanish; terror spoils sleep")
g = fresh()
assert(g:dread_name() == nil)
g:dread(40)
assert(g:dread_name() == "Uneasy" and g:current_conditions():find("Uneasy"))
g:dread(50)
assert(g:dread_name() == "Terror")
g.player.mp, g.player.needs.rest = 0, 10
local before = g.player.needs.rest
g:rest()
local terror_gain = g.player.needs.rest - before
local g2 = fresh()
g2.player.mp, g2.player.needs.rest = 0, 10
g2:rest()
assert(terror_gain < g2.player.needs.rest - 10, "terror: half the sleep")
g.player.dread = 95
g.roll = function() return true end
assert(g:dread_move() and g.enc.def.phantom, "a phantom")
g:encounter_action("attack")
assert(g.enc.over and g.player.dread < 95, "nothing there")
assert((g.stats.horrors or 0) == 0, "a phantom is no horror lived through")
g.screen = "encounter"
g:encounter_key(13)   -- Continue (a playtest froze here: it vanished again and again)
assert(g.enc == nil and g.screen == "map", "Continue leaves a phantom")
g = fresh()
g.player.inventory = {{item = "vodka", qty = 1}}
g.player.dread = 50
g:try_consume("inventory", 1)
assert(g.player.dread == 40, "vodka eases it")

print("5. bestiary: seen, watched (to-hit bonus), killed; full pages sell")
g = fresh()
g:start_encounter({kind = "animal", name = "Jawhound", who = "jawhound", hp = 30, start = "close", intro = "x",
                   hit = 50, dmg = {1, 2}, speed = 3, bleed = 0, loot = {{"nothing", 1}}})
local page = g.bestiary.jawhound
assert(page and page.seen == 1 and g:beast_bonus() == 0)
g.roll = function() return true end
g:encounter_action("watch")
assert(page.watched and g:beast_bonus() == 10)
g:enemy_dies()
assert(page.killed == 1 and Game.beast_full(page))
local text = g:sell_bestiary()
assert(text:find("15 rubles") and count(g, "rubles") == 15)
assert(g:sell_bestiary():find("full page"), "sold once")
g.page = "bestiary"
assert(g:skills_page_lines()[1]:find("1 pages, 1 full"))

print("6. what's left of you: your gear waits in the next world; kill it, it's yours")
g = fresh()
g.player.inventory = {{item = "knife", qty = 1}, {item = "canned_beans", qty = 2}}
g.player.equipped.jacket = "jacket"
g.player.health = 0
assert(g:check_death("The cold took you."))
local rec = Game.records()
assert(rec.legacy and #rec.legacy.items == 3)
Game.reload_records()
assert(Game.records().legacy and Game.records().legacy.cause == "The cold took you.", "written to the records")
local g3 = Game.new()
g3:start_game()
g3.player.inventory = {}
assert(g3.legacy and g3.legacy.key, "placed in the new world")
assert(g3:legacy_text():find("What's left of you"))
g3.player.q, g3.player.r = Game.key_qr(g3.legacy.key)
assert(g3:legacy_arrive() and g3.enc.def.legacy, "it's there")
assert(g3.enc.def.dmg[1] >= 10, "your knife")
g3:enemy_dies()
assert(count(g3, "knife") == 1 and count(g3, "jacket") == 1 and count(g3, "canned_beans") == 2)
assert(Game.records().legacy == nil and g3.legacy == nil, "gone for good")
Game.reload_records()
assert(Game.records().legacy == nil)

print("7. mutations: each radiation stage offers a choice; gains and costs show in the stats")
g = fresh()
g.screen = "map"
assert(not g:mutation_offer(), "nothing while healthy")
g.player.rads = 35
assert(g:rad_stage() == 1 and g:mutation_offer() and g.screen == "mutate" and g.mut.stage == 1)
local thirst0, armor0 = g.player.thirst_mult, g.player.armor or 0
g:draw_mutate(400, 300)
g:mutate_key(DOWN); g:mutate_key(UP)
g:mutate_key(ENTER)   -- Thick Hide
assert(g.screen == "map" and g.player.mutations.hide and g.player.mut_stage == 1)
assert(g.player.armor == armor0 + 2 and g.player.thirst_mult > thirst0, "armor up, thirst up")
assert(has_log(g, "You change: Thick Hide"))
assert(not g:mutation_offer(), "stage 1 is spent, even if the sickness comes back")
g.player.health = 100
g.enc = {def = {kind = "beast", name = "x", who = "x", hp = 10, dmg = {2, 2}}, hp = 10, range = "close", msg = {}, intro = {}}
g.screen = "encounter"
g:enemy_hits({2, 2}, 0, "It hits you")
assert(g.player.health == 99, "a hit of 2 against armor 2 still costs 1: " .. g.player.health)
g.enc, g.screen = nil, "map"
-- the next stages, one at a time, even if the dose skipped one; Refuse keeps you as you are
g.player.rads = 90
assert(g:mutation_offer() and g.mut.stage == 2)
g:mutate_key(51)   -- 3: Refuse
assert(g.player.mut_stage == 2 and not g.player.mutations.cat and not g.player.mutations.bones)
assert(g:mutation_offer() and g.mut.stage == 3)
g:mutate_key(50)   -- 2: Second Stomach
assert(g.player.mutations.gut and not g:mutation_offer(), "all three offered")
-- night eyes lose nothing in the dark
g.player.mutations.cat = true
g:set_difficulty(g.difficulty)
g.player.hours = 23
g:refresh_view()
assert(g.player.view_sight == g.player.sight, "cat eyes: no sight lost at night")
-- the status page lists them
g.page = "status"
local lines = table.concat(g:status_lines(), "|")
assert(lines:find("Mutations", 1, true) and lines:find("Second Stomach", 1, true) and lines:find("Cat Eyes", 1, true))
-- saved with the player
FAKE_DIRS = {["/sd/churn"] = true}
assert(g:save())
local g4 = Game.new(); g4:start_game()
g4:load_state(Game.read_save())
assert(g4.player.mutations.gut and g4.player.mut_stage == 3, "mutations survive a save")

print("8. dread fades on its own: by day, faster with rest, faster still by a fire or in a bed")
local function after(setup, hours, rests)
    local gg = fresh()
    gg.player.dread = 80
    gg.player.hours, gg.ticked_hour = 0, 0   -- (08:00: the clock starts at 8)
    setup(gg)
    for _ = 1, rests do gg.player.mp = 0; gg:rest(); gg:tick() end
    if hours > 0 then gg.player.hours = gg.player.hours + hours; gg:tick() end
    return gg.player.dread
end
local D = 80
local walking = after(function() end, 12, 0)
assert(walking <= D - 8, "twelve hours of day: -0.75 an hour at least (" .. walking .. ")")
local resting = after(function() end, 0, 3)
assert(resting < D - 15, "three plain rests help (" .. resting .. ")")
local fire = after(function(gg) gg.camps[gg.player.q .. "," .. gg.player.r] = {until_hour = 999} end, 0, 3)
assert(fire < resting - 15, "a fire helps much more (" .. fire .. " vs " .. resting .. ")")
local night = fresh()
night.player.dread, night.player.hours, night.ticked_hour = 80, 14, 14   -- (22:00)
night.player.equipped.rhand = "torch"
night.player.hours = 20; night:tick()
assert(night.player.dread < 80, "a lit night still eases it a little")
local dark = fresh()
dark.player.dread, dark.player.hours, dark.ticked_hour = 50, 14, 14
dark.player.hours = 20; dark:tick()
assert(dark.player.dread > 50, "the dark still gets in")

print("MECHANICS TESTS PASSED")
