-- Quests: the trader's fetch and den jobs, Anna's supply job, Karl's dog.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KEY, QUESTS = H.KEY, H.QUESTS

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
g:radio_call(2)
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

print("QUEST TESTS PASSED")
