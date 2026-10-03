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
assert(not g.quest and #g:ground_list() >= n0 + 1, "opened")

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

print("QUEST TESTS PASSED")
