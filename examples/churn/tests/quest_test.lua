-- Quests: the trader's fetch, den and drive jobs, Anna's supply and notes
-- jobs, Karl's dog, the Peddler's swap, a drive's crate, dead churners.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KEY, QUESTS, CHURN = H.KEY, H.QUESTS, H.CHURN

local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function fresh()
    local g = Game.new()
    g:start_game()
    g.ticked_hour = g.player.hours
    g.karl_next = 1e9
    return g
end
local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    for _, s in ipairs(g:ground_list()) do if s.item == item then n = n + s.qty end end
    return n
end
local function at_trader(g)
    g.player.q, g.player.r = parse(g.sites.trader)
    g:open_trade()
end
local function job(g, kind)   -- ask the trader until he offers this kind
    for i = 1, 50 do
        g.quest = nil
        g.seed = i * 977
        g:trade_key(KEY.O)
        if g.quest and g.quest.kind == kind then return end
    end
    error("never offered " .. kind)
end

print("1. fetch: O asks for work; bring an artifact back for a reward")
local g = fresh()
at_trader(g)
job(g, "fetch")
assert(g:quest_text():find("artifact", 1, true))
assert(table.concat(g:journal_lines(), " "):find("Quest - Trader", 1, true))
g:trade_key(KEY.O)
assert(g.trade_ui.msg:find("waiting", 1, true) and g.quest)
g.player.inventory = {{item = "weeping_stone", qty = 1}}
g:trade_key(KEY.O)
assert(not g.quest and g:artifact_count() == 0 and count(g, "antirad") >= 2)
assert(g.quests_done == 1)

print("2. den: a marked hex; walking in starts a big fight; the kill pays")
g = fresh()
at_trader(g)
job(g, "den")
local key = g.quest.target
assert(key and g.player.explored[key])
g:trade_key(KEY.Q)
local q, r = parse(key)
g.player.q, g.player.r = q + 1, r
if not g.tiles[g.player.q .. "," .. g.player.r] then g.player.q, g.player.r = q - 1, r end
g.player.mp = 5
g:try_move(q, r)
assert(g.screen == "encounter" and g.enc.def.den, "a den fight")
assert(not g.enc.def.flees_at, "it won't run from its den")
g.player.inventory = {}
g.enc.hp = 1
g:enc_hit(5, nil, "test")
assert(not g.quest, "den cleared")
assert(count(g, "multitool") + count(g, "gasmask") + count(g, "machete") + count(g, "antirad") >= 1)

print("3. Anna: an unhurt call offers the job for free; bandages hand it in, even while she's busy")
g = fresh()
g.player.inventory = {{item = "lora_radio", qty = 1}}
g:open_radio()
local charge = g.radio.charge
local function anna_job(g3, kind)   -- call her until she offers this kind
    for i = 1, 50 do
        g3.quest, g3.seed = nil, i * 131
        g3:radio_call(2)
        if g3.quest and g3.quest.kind == kind then return end
    end
    error("Anna never offered " .. kind)
end
anna_job(g, "supply")
assert(g.quest and g.quest.kind == "supply" and g.radio.charge == charge, "free offer")
g.radio.next.anna = g.player.hours + 50
g.player.inventory[#g.player.inventory + 1] = {item = "bandage", qty = 2}
g:radio_call(2)
assert(not g.quest and count(g, "bandage") == 0 and count(g, "medkit") == 1)
g.player.health, g.player.injuries.bleeding = 40, true
for i, s in ipairs(g.player.inventory) do if s.item == "medkit" then g:use_item("inventory", i) break end end
assert(g.player.health == 80 and not g.player.injuries.bleeding)

print("4. Karl: after a right answer he asks you to find his dog by the river")
g = fresh()
g.karl_next = 0
g:start_karl()
g:encounter_action("answer_" .. g.enc.riddle.right)
assert(g.quest and g.quest.kind == "dog" and g.quest.target)
local dq, dr = parse(g.quest.target)
assert(g.tiles[g.quest.target] and g.player.explored[g.quest.target])
g.enc, g.screen = nil, "map"
g.player.q, g.player.r = dq, dr
assert(not g:quest_arrive() and not g.quest, "found her")

print("5. one quest at a time; saved")
g = fresh()
at_trader(g)
job(g, "fetch")
g.quest = {kind = "den", giver = "Trader", target = "1,1"}
g:trade_key(KEY.O)
assert(g.trade_ui.msg:find("first", 1, true))
FAKE_FILES, FAKE_DIRS = {}, {}
g.screen = "map"
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.quest and g2.quest.target == "1,1")

print("6. drive: the trader wants a USB drive; pays rounds, a gun part and food")
g = fresh()
at_trader(g)
job(g, "drive")
assert(g.trade_ui.msg == QUESTS.drive.offer and g:quest_text():find("USB drive"))
g:trade_key(KEY.O)
assert(g.quest and g.trade_ui.msg:find("No drive"))
g.player.inventory = {{item = "usb_drive", qty = 1}}
g:trade_key(KEY.O)
assert(not g.quest and count(g, "usb_drive") == 0 and count(g, "r9x18") == 6)
assert(count(g, "gun_barrel") + count(g, "firing_pin") == 1 and count(g, "canned_beans") >= 2)

print("7. notes: Anna wants the Surgeon's Notes; a medkit and a suture kit")
g = fresh()
g.player.inventory = {{item = "lora_radio", qty = 1}}
g:open_radio()
anna_job(g, "notes")
assert(g:quest_text():find("Surgeon's Notes"))
assert(not g:anna_ready())
g.radio.next.anna = g.player.hours + 50
g.player.inventory[#g.player.inventory + 1] = {item = "book_surgeon", qty = 1}
assert(g:anna_ready())
g:radio_call(2)
assert(not g.quest and count(g, "book_surgeon") == 0 and count(g, "medkit") == 1 and count(g, "stitches") == 1)

print("8. swap: a voiced tape for an Elder Sign at the Peddler's cart, once a stop")
g = fresh()
local pk = g:peddler_key()
g.player.q, g.player.r = parse(pk)
g:open_trade("peddler")
assert(g.trade_ui.who == "peddler", tostring(g.trade_ui.who))
g.player.inventory = {{item = "blank_tape", qty = 1}}
g:trade_key(KEY.O)
assert(g.trade_ui.msg == QUESTS.swap.none and count(g, "elder_sign") == 0, "a blank won't do")
g.player.inventory = {{item = "tape_choir", qty = 1}, {item = "tape_cook", qty = 1}}
g:trade_key(KEY.O)
assert(count(g, "elder_sign") == 1 and count(g, "tape_choir") + count(g, "tape_cook") == 1)
g:trade_key(KEY.O)
assert(g.trade_ui.msg == QUESTS.swap.done and count(g, "elder_sign") == 1, "once a stop")
g.player.hours = g.player.hours + H.TRADE.stay
g:trade_key(KEY.O)
assert(count(g, "elder_sign") == 2, "the next stop, again")

print("9. crate: a drive's map marks an Institute crate; Lockpicks open it")
g = fresh()
local marked = false
for i = 1, 60 do
    g.quest, g.seed = nil, i * 37
    g.player.inventory = {{item = "lora_radio", qty = 1}, {item = "usb_drive", qty = 1}}
    g.sites_known.checkpoint = true
    g:open_radio(); g.screen = "map"
    g.radio.charge = 3
    g:use_item("inventory", 2)
    if g.quest and g.quest.kind == "crate" then marked = true; break end
end
assert(marked, "a drive marks a crate sometimes")
local key = g.quest.target
assert(g.player.explored[key] and g:quest_text():find("Institute crate"))
g.player.q, g.player.r = parse(key)
g.player.inventory = {}
local n0 = #g:ground_list()
assert(not g:quest_arrive() and g.quest, "locked: the job stays")
g.player.inventory = {{item = "lockpicks", qty = 1}}
g:quest_arrive()
assert(#g:ground_list() >= n0 + 1, "opened")
-- the first one holds a map to a CLEARANCE crate by the quarry; that one, the pass
assert(g.quest and g.quest.kind == "deep_crate" and g.inst_chain == 1, "a second map")
local dk = g.quest.target
local qq, qr = parse(g.sites.quarry)
local dq, dr = parse(dk)
assert((math.abs(dq - qq) + math.abs(dr - qr) + math.abs(dq + dr - qq - qr)) // 2 <= QUESTS.deep_crate.far)
assert(g:quest_text():find("CLEARANCE"))
g.player.q, g.player.r = dq, dr
g:quest_arrive()
assert(not g.quest and g.inst_chain == 2 and count(g, "institute_pass") == 1, "the pass")
assert(g.story.pass, "the story knows")
-- a pass already in hand: the crate has something else instead
g.story.pass, g.inst_chain = true, 1
g.quest = {kind = "deep_crate", giver = "A second map", target = dk}
g:quest_arrive()
assert(count(g, "institute_pass") == 1 and count(g, "antirad") >= 2)
-- and a later Institute crate doesn't start the chain again
g.quest = {kind = "crate", giver = "A USB drive", target = dk}
g:quest_arrive()
assert(not g.quest, "once a run")

print("10. dead churners: rare (~3% of ruins searches), once a hex, saved")
local found, tries = 0, 0
g = fresh()
for k, t in pairs(g.tiles) do
    if t == "ruins" then
        for s = 1, 40 do
            g.crates = {}
            g.seed = s * 7919 + tries
            tries = tries + 1
            local n = #g:ground_list()
            g:find_corpse(k)
            if g.crates[CHURN.corpse.prefix .. k] then
                found = found + 1
                assert(#g:ground_list() > n, "they carried something")
                local m = #g:ground_list()
                g.seed = 1
                for _ = 1, 50 do g:find_corpse(k) end
                assert(#g:ground_list() == m, "once a hex")
            end
            g.ground = {}
        end
    end
end
print(("   %d of %d searches: %.1f%%"):format(found, tries, 100 * found / tries))
assert(found / tries > 0.015 and found / tries < 0.05)
for _, x in ipairs(CHURN.corpse.loot) do assert(H.ITEM_DB[x[1]], x[1]) end
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
g.crates = {[CHURN.corpse.prefix .. "1,1"] = true}
g.peddler.swapped = 7
g.player.hours = g.player.hours + 1
assert(g:save())
g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.crates[CHURN.corpse.prefix .. "1,1"] and g2.peddler.swapped == 7)

print("11. Vesna: her tape, then her body (dead churners likelier till you find her)")
g = fresh()
g.player.inventory = {{item = "cassette_player", qty = 1}, {item = "tape_vesna", qty = 1}}
g.tapedeck = {charge = 2}
g:use_item("inventory", 2)
assert(g.vesna == "heard" and count(g, "blank_tape") == 1)
local ruin
for k, t in pairs(g.tiles) do if t == "ruins" then ruin = k break end end
g.player.q, g.player.r = parse(ruin)
local hits = 0
for sd = 1, 400 do
    g.seed, g.crates, g.vesna = sd * 13, {}, "heard"
    g.ground = {}
    g:find_corpse(ruin)
    if g.vesna == "found" then hits = hits + 1 end
end
print(("   found her in %.1f%% of searches (dead churners: %d%% x %d)"):format(
    hits / 4, CHURN.corpse.chance, CHURN.vesna.mult))
assert(hits > 400 * 0.06 and hits < 400 * 0.2)
g.seed, g.crates, g.vesna, g.ground = 1, {}, "heard", {}
for sd = 1, 500 do
    g.seed, g.crates = sd, {}
    g:find_corpse(ruin)
    if g.vesna == "found" then break end
end
assert(g.vesna == "found" and count(g, "lockpicks") == 1)
local said = false
for _, l in ipairs(g.log) do said = said or l:find("Vesna", 1, true) ~= nil end
assert(said, "her epitaph")
FAKE_FILES, FAKE_DIRS = {}, {}
g.player.hours = g.player.hours + 1
assert(g:save())
g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.vesna == "found")

print("12. Rival Churners sometimes trade: one of yours for one of theirs, and they go")
local rival
for _, d in ipairs(H.ENCOUNTERS) do if d.who == "rival churner" then rival = d end end
local offered, n = 0, 300
for sd = 1, n do
    g = fresh()
    g.seed = sd * 29
    g.player.inventory = {{item = "canned_beans", qty = 2}}
    g:start_encounter(rival)
    if g.enc.parley then offered = offered + 1 end
end
print(("   offered in %d%% of meetings"):format(offered * 100 // n))
assert(offered > n * 0.25 and offered < n * 0.45)
g = fresh()
g.player.inventory, g.ground = {}, {}   -- (the start pile is in reach too)
for sd = 1, 50 do g.seed = sd; g:start_encounter(rival); assert(not g.enc.parley, "nothing they want: no offer") end
g.player.inventory = {{item = "canned_beans", qty = 2}}
for sd = 1, 200 do
    g.seed = sd
    g:start_encounter(rival)
    if g.enc.parley then break end
end
local give = g.enc.parley.give
local swap
for _, o in ipairs(g:encounter_options()) do if o[2] == "swap" then swap = o[1] end end
assert(swap and swap:find("canned beans"), tostring(swap))
g:encounter_action("swap")
assert(g.enc.over and count(g, "canned_beans") == 1 and count(g, give) >= 1)

print("13. deadlines: trader and ferry jobs lapse, and the giver remembers")
g = fresh()
at_trader(g)
job(g, "fetch")
assert(g.quest.due == g.player.hours + QUESTS.due.fetch and g:quest_text():find("4d left"), g:quest_text())
g.player.hours = g.quest.due + 1
g:tick()
assert(not g.quest and g:rep_of("trader") == -1, "lapsed")
local lapsed = false
for _, l in ipairs(g.log) do lapsed = lapsed or l:find("someone else", 1, true) ~= nil end
assert(lapsed)
g.quest = nil
at_trader(g)
job(g, "drive")
g.player.inventory = {{item = "usb_drive", qty = 1}}
g:trade_key(KEY.O)
assert(not g.quest and g:rep_of("trader") == 0, "a job done: back to even")
assert(g:rep_text() == nil, "nothing to show at 0")

print("14. standing: cheaper trades, Anna answers sooner, Karl winks")
g = fresh()
at_trader(g)
g.trade_ui.get = {antirad = 1}
local _, ask0 = g:trade_totals()
g.rep = {trader = 5, anna = 3, karl = 2}
local _, ask5 = g:trade_totals()
assert(ask5 < ask0, ("%d < %d"):format(ask5, ask0))
assert(g:markup_for("town", 1.5) >= QUESTS.rep.floor and g:markup_for("peddler", 1.4) == 1.4)
assert(g:rep_text() == "Standing: Trader +5  Anna +3  Karl +2", g:rep_text())
local anna
for _, ch in ipairs(H.TECH.channels) do if ch.id == "anna" then anna = ch end end
assert(g:channel_wait(anna) == anna.cooldown // 2 and g:channel_wait({id = "trader", cooldown = 72}) == 72)
g.karl_next = 0
g:start_karl()
local winked = false
for _, o in ipairs(g:encounter_options()) do winked = winked or o[1]:find("winks", 1, true) ~= nil end
assert(winked, "Karl winks at a friend")
g.rep = {trader = 99}
g:rep_change("Trader", 1)
assert(g:rep_of("trader") == QUESTS.rep.max)

print("15. Mother Okun wants smoked meat; Karl wants sinew (on the radio)")
g = fresh()
g.player.q, g.player.r = parse(g.sites.ferry)
local got
for i = 1, 40 do
    g.quest, g.seed = nil, i * 53
    g:open_trade("ferry")
    g:trade_key(KEY.O)
    if g.quest.kind == "smoked" then got = true break end
end
assert(got and g.quest.due)
g:trade_key(KEY.O)
assert(g.quest and g.trade_ui.msg:find("got 0"))
g.player.inventory = {{item = "smoked_meat", qty = 2}}
g:trade_key(KEY.O)
assert(not g.quest and count(g, "fishing_rod") == 1 and g:rep_of("okun") == 1)
g = fresh()
g.player.inventory = {{item = "lora_radio", qty = 1}}
g:open_radio()
local offered_k
for i = 1, 40 do
    g.quest, g.seed, g.radio.next.karl, g.radio.charge = nil, i * 7, nil, 3
    g:radio_call(3)
    if g.quest and g.quest.kind == "sinew" then offered_k = true break end
end
assert(offered_k and g:quest_text():find("433"))
g.radio.next.karl = g.player.hours + 40
g.player.inventory[#g.player.inventory + 1] = {item = "sinew", qty = 2}
g:radio_call(3)
assert(not g.quest and count(g, "lucky_lure") == 1 and g:rep_of("karl") == 1, "handed in while he's busy")
FAKE_FILES, FAKE_DIRS = {}, {}
g.player.hours = g.player.hours + 1
assert(g:save())
g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.rep.karl == 1 and g2.karl_lure)

print("16. finds: dead churners and opened crates go on the map and the Finds page")
g = fresh()
assert(g:finds_lines()[1]:find("Nothing yet"))
local ruin2
for k, t in pairs(g.tiles) do if t == "ruins" then ruin2 = k break end end
g.player.q, g.player.r = parse(ruin2)
for sd = 1, 600 do
    g.seed, g.crates = sd, {}
    g:find_corpse(ruin2)
    if g.finds and g.finds[ruin2] then break end
end
assert(g.finds[ruin2].kind == "corpse" and g.finds[ruin2].what ~= "")
g.player.inventory = {{item = "lockpicks", qty = 1}}
local cq, cr = parse(ruin2)
local crate_key
for _, d in ipairs({{1, 0}, {0, 1}, {-1, 1}, {-1, 0}, {0, -1}, {1, -1}}) do
    local k = (cq + d[1]) .. "," .. (cr + d[2])
    if g.tiles[k] then crate_key = k break end
end
g.tiles[crate_key] = "ruins"
g.player.q, g.player.r = parse(crate_key)
for sd = 1, 200 do
    g.seed, g.crates = sd, {}
    g:pick_crate(crate_key)
    if g.finds[crate_key] then break end
end
assert(g.finds[crate_key] and g.finds[crate_key].kind == "crate")
local lines = g:finds_lines()
assert(lines[1]:find("^Day %d+  ") and #lines >= 3, table.concat(lines, "|"))
g.screen = "journal"
g:help_key(KEY.F)
assert(g.screen == "skills" and g.page == "finds")
g:draw_skills(400, 300)
g:help_key(KEY.ENTER); g.screen = "journal"
g:help_key(KEY.K)
assert(g.page == nil, "K is the skills page again")
g.player.explored[ruin2], g.player.explored[crate_key] = true, true
g.screen = "map"
g:draw_map(400, 300)
FAKE_FILES, FAKE_DIRS = {}, {}
g.player.hours = g.player.hours + 1
assert(g:save())
g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.finds[ruin2].kind == "corpse" and g2.finds[crate_key].kind == "crate")

print("17. first-day tips: each once a run, one a tick, saved")
g = fresh()
g.hints, g.log = {}, {}
g.player.needs.hunger, g.player.needs.thirst = 30, 30
g:hint_tick()
local tips = 0
for _, l in ipairs(g.log) do if l:find("^Tip: ") then tips = tips + 1 end end
assert(tips == 1, "one a tick")
g:hint_tick()
assert(g.hints.thirsty and g.hints.hungry, "the next one, next tick")
g:hint_tick(); g:hint_tick()
for _, h in ipairs(Game.HINTS) do assert(#h[2] <= 57, h[1] .. " is too long for the log") end
FAKE_FILES, FAKE_DIRS = {}, {}
g.player.hours = g.player.hours + 1
assert(g:save())
g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.hints.thirsty and g2.hints.hungry)
g2.log = {}
g2.player.needs.hunger, g2.player.needs.thirst = 30, 30
g2:hint_tick()
for _, l in ipairs(g2.log) do assert(not l:find("hungry", 1, true), "not twice") end

print("QUEST TESTS PASSED")
