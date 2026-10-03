-- Karl (K-A-R-L), the riddling fisherman.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KARL, ITEM_DB = H.KARL, H.ITEM_DB

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
local function place(g, by_water)
    for k, t in pairs(g.tiles) do
        if t == "plains" or t == "ford" then
            g.player.q, g.player.r = parse(k)
            if g:near_water() == by_water then return k end
        end
    end
    error("no spot")
end
local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    for _, it in pairs(g.player.equipped) do if it == item then n = n + 1 end end
    return n
end
local function meet(g)
    g.karl_next = 0
    g:start_karl()
    return g.enc
end

print("1. never away from water; about " .. KARL.chance .. "% per move by it")
local g = fresh()
place(g, false)
for _ = 1, 500 do
    g.karl_next = 0
    assert(not g:maybe_karl("move"), "Karl away from water")
end
place(g, true)
local met, n = 0, 4000
for _ = 1, n do
    g.karl_next = 0
    if g:maybe_karl("move") then met = met + 1; g.enc, g.screen = nil, "map" end
end
print(("   met %d of %d moves by water (%.1f%%)"):format(met, n, 100 * met / n))
assert(math.abs(100 * met / n - KARL.chance) < 1.5)

print("2. once met, not again for " .. KARL.cooldown .. "h")
g = fresh()
place(g, true)
meet(g)
g.enc, g.screen = nil, "map"
for _ = 1, 300 do assert(not g:maybe_karl("fish"), "too soon") end
g.player.hours = g.player.hours + KARL.cooldown
local again = false
for _ = 1, 300 do
    if g:maybe_karl("fish") then again = true; break end
end
assert(again, "back after the cooldown")

print("3. he's clearly KARL, with his portrait and the riddle shown")
g = fresh()
place(g, true)
local e = meet(g)
assert(g.screen == "encounter" and e.def.name == "Karl" and e.def.kind == "riddle")
assert(KARL.intro:find("KARL", 1, true) and KARL.intro:find("Karl. With a K", 1, true))
assert(H.PORTRAIT_DATA.karl, "his portrait exists")
assert(table.concat(e.msg, " "):find("Karl: '", 1, true))
local opts = g:encounter_options()
assert(#opts == 4 and opts[4][2] == "leave_quietly")
g:draw_encounter(400, 300)

print("4. the right answer gets a gift; a wrong one gets a laugh")
g = fresh()
place(g, true)
g.player.inventory = {}
e = meet(g)
g:encounter_action("answer_" .. e.riddle.right)
assert(e.over and #g.player.inventory == 1, "a gift")
local gift = g.player.inventory[1].item
local ok = false
for _, it in ipairs(KARL.rewards) do ok = ok or it == gift end
assert(ok, gift)
g = fresh()
place(g, true)
g.player.inventory = {}
e = meet(g)
g:encounter_action("answer_" .. (e.riddle.right % 3 + 1))
assert(e.over and #g.player.inventory == 0)
local said = table.concat(e.msg, " ")
assert(said:find("river keeps its secrets", 1, true))

print("5. every riddle's right answer is right after shuffling; riddles don't repeat")
g = fresh()
place(g, true)
local asked = {}
for _ = 1, #KARL.riddles do
    e = meet(g)
    local said = table.concat(e.msg, " ")   -- long riddles wrap onto two lines
    local right, q
    for _, r in ipairs(KARL.riddles) do
        if said:gsub("%s+", " "):find(r.q, 1, true) then right, q = r.a[1], r.q end
    end
    assert(q, "riddle not shown: " .. said)
    assert(not asked[q], "repeated before all were asked")
    asked[q] = true
    assert(e.riddle.answers[e.riddle.right] == right)
    g.enc, g.screen = nil, "map"
end
e = meet(g)   -- all asked: they start over
assert(e.riddle)

print("6. gear only once; Pilk can repeat")
g = fresh()
local got = {}
for _ = 1, 60 do
    local item = g:karl_reward()
    if ITEM_DB[item].slot or ITEM_DB[item].fish_bonus then
        assert(not got[item], item .. " given twice")
        got[item] = true
    end
end
assert(got.karls_hat and got.karls_waders and got.lucky_lure)

print("7. Karl's gear helps you fish; Pilk is Pepsi and milk")
g = fresh()
assert(g:fish_bonus() == 0)
g.player.equipped.head, g.player.equipped.feet = "karls_hat", "karls_waders"
g.player.inventory = {{item = "lucky_lure", qty = 1}}
assert(g:fish_bonus() == 35)
assert(ITEM_DB.pilk.desc:find("Pepsi and milk", 1, true))
g.player.needs.thirst, g.player.needs.rest = 20, 20
g.player.inventory = {{item = "pilk", qty = 1}}
g:use_item("inventory", 1)
assert(g.player.needs.thirst == 60 and g.player.needs.rest == 35)
for _, id in ipairs({"pilk", "lucky_lure", "karls_waders", "karls_hat"}) do
    assert(H.SPRITES[id], id .. " sprite")
end

print("8. saved: what he asked, what he gave, when he's back")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
place(g, true)
meet(g)
g:karl_reward()
g.enc, g.screen = nil, "map"
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.karl_next == g.karl_next and next(g2.karl_asked) and next(g2.karl_gave))

print("KARL TESTS PASSED")
