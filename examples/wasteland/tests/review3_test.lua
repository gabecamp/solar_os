-- Fixes from the third code review (b513be8..HEAD). One check per finding.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local ITEM_DB = H.ITEM_DB
local function fresh()
    local g = Game.new()
    g:start_game()
    g.player.q, g.player.r = 0, 0
    g.ground["0,0"] = {}
    return g
end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function logged(g, s)
    for _, l in ipairs(g.log) do if l:find(s, 1, true) then return true end end
    return false
end

print("1. a refused move keeps every piece's condition (worn and in the bag)")
local g = fresh()
g.player.equipped = {jacket = "jacket"}
g:wear_out("jacket", 200)
g.player.inventory = {}
for k = 1, g:bag_capacity() do g.player.inventory[k] = {item = "r" .. k, qty = 1} end
ITEM_DB.r1 = ITEM_DB.rock   -- (stand-ins, so names resolve)
for k = 1, 20 do ITEM_DB["r" .. k] = ITEM_DB.rock end
g.player.inventory[1] = {item = "tshirt", qty = 1, cond = 40}
assert(not g:try_transfer({"equip", "jacket"}, {"inventory"}), "the bag is full")
assert(g:torn("jacket"), "still torn, not mended by the rollback")
assert(g.player.inventory[1].cond == 40, "the bag's worn shirt is still worn")
print("   OK")

print("2. a bag that tore and shrank can still be emptied")
g = fresh()
g.player.equipped = {back = "sack_pack"}
g.player.inventory = {}
for k = 1, g:bag_capacity() do g.player.inventory[k] = {item = "r" .. k, qty = 1} end
g:wear_out("back", 200)
assert(#g.player.inventory > g:bag_capacity(), "over the shrunken size")
assert(g:try_transfer({"inventory", 1}, {"ground"}), "dropping one is allowed")
assert(not g:try_transfer({"ground", 1}, {"inventory"}), "but nothing more goes in")
print("   OK")

print("3. trade: worn and new pieces are separate rows; selling takes the worn first, at less")
g = fresh()
g.player.inventory = {{item = "jacket", qty = 1, cond = 0}, {item = "jacket", qty = 3}}
g:open_trade("town")
local u = g.trade_ui
u.cursor.mine = 2
for _ = 1, 4 do g:trade_key(10) end
assert(u.give.jacket == 4, "all four can be offered: " .. tostring(u.give.jacket))
local v = Game.item_value("jacket")
local give = g:trade_totals()
assert(give == 3 * v + math.floor(v * 25 / 100), "a torn one counts a quarter: " .. give)
u.give.jacket = 2
u.get = {cloth_scrap = 1}
assert(g:make_deal())
assert(g:count_item("jacket") == 2, "two sold")
for _, s in ipairs(g.player.inventory) do
    if s.item == "jacket" then assert(s.qty >= 0 and not s.cond, "the torn one is gone") end
end
print("   OK")

print("4. the Little Ones never hide the Institute pass")
assert(H.LITTLE.keep.institute_pass)
g = fresh()
g.little.n = 2
g.player.inventory = {{item = "institute_pass", qty = 1}}
for _ = 1, 30 do g:little_mischief(g.player.hours) end
assert(g:count_item("institute_pass") == 1)
print("   OK")

print("5. two runs on the same world seed are both counted")
FAKE_FILES, FAKE_DIRS = {}, {}
local a, b = fresh(), fresh()
a.world_seed, b.world_seed = 4321, 4321
assert(a.run_id ~= b.run_id, "different run ids")
local before = Game.records().runs
a.player.health = 0; a:check_death("Test.")
b.player.health = 0; b:check_death("Test.")
assert(Game.records().runs == before + 2, "both counted")
print("   OK")

print("6. trinkets aren't free to buy")
g = fresh()
g:open_trade("peddler")
g.trade_ui.get = {crayons = 2}
local _, ask = g:trade_totals()
assert(ask >= 2, "ask " .. ask)
assert(not g:make_deal(), "nothing offered: no deal")
print("   OK")

print("7. Anna's warning doesn't cost you her help")
local g3
repeat g3 = fresh() until g3.sites.quarry
g3.story.step = "quarry"
g3.radio = {charge = 5, next = {}}
g3.player.inventory = {{item = "lora_radio", qty = 1}}
g3.player.health = 50
g3:open_radio()
g3:radio_call(2)
assert(g3.player.health == 70, "healed: " .. g3.player.health)
assert(g3.story.warned)
local said = table.concat(g3.radio_ui.msg, " ")
assert(said:find("Don't go") and said:find("20 HP"), said)
print("   OK")

print("8. a long rest in a storm still warns you")
g = fresh()
g.weather = function() return "Storm" end
g.tiles["0,0"] = "plains"
g:tick()
g.player.hours = g.player.hours + 4
g:tick()
assert(logged(g, "storm is beating you down"), table.concat(g.log, " | "))
print("   OK")

print("9. listening at the Institute shows what you heard on the death screen")
g = fresh()
g:institute_action("listen_institute")
assert(g.screen == "dead" and g.death_note)
local texts = {}
local real = gfx.text
gfx.text = function(x, y, s) texts[#texts + 1] = s; assert(y <= 300 and x + #s * 7 <= 400, s) end
g:draw_dead(400, 300)
gfx.text = real
assert(table.concat(texts, " "):find("own name"), "the note is drawn")
print("   OK")

print("\nREVIEW 3 TESTS PASSED")
