-- Clothes wear out (WORLD.wear): with time, under blows and in storms; rags
-- twice as fast; torn clothes give no warmth and half their pockets until
-- you patch them (the "Patch clothes" recipe, 1 cloth).
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()

local Game, H = dofile("lib_hunt.lua")
local ITEM_DB, W = H.ITEM_DB, H.WORLD.wear
local function fresh()
    local g = Game.new()
    g:start_game()
    g.player.q, g.player.r = 0, 0
    return g
end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function patch_recipe()
    for _, r in ipairs(H.RECIPES) do if r.mend then return r end end
end

print("1. a day worn costs WORLD.wear.day; rags twice that; held things don't wear")
local g = fresh()
g.player.equipped = {shirt = "tshirt", pants = "rag_trousers", rhand = "knife", lhand = "jacket"}
g:wear_all(W.day)
assert(near(g:cond("shirt"), 100 - W.day) and near(g:cond("pants"), 100 - 2 * W.day))
assert(g:cond("rhand") == nil and g:cond("lhand") == nil, "hands don't wear")
g = fresh()
g.player.equipped = {shirt = "tshirt"}
g:tick()
g.player.hours = g.player.hours + 24
g:tick()
assert(g:cond("shirt") < 100, "time wears clothes (tick)")
print("   OK")

print("2. a blow lands on one worn piece; storms wear everything out in the open")
g = fresh()
g.player.equipped = {shirt = "tshirt"}
g:wear_hit()
assert(near(g:cond("shirt"), 100 - W.hit))
g.player.equipped.pants = "jeans"
g.weather = function() return "Storm" end
g.tiles["0,0"] = "plains"
g:storm_hour(g.player.hours)
assert(near(g:cond("pants"), 100 - W.storm), "exposed: worn")
g.tiles["0,0"] = "ruins"
g:storm_hour(g.player.hours)
assert(near(g:cond("pants"), 100 - W.storm), "sheltered: not worn")
print("   OK")

print("3. a fight wears what you have on")
g = fresh()
g.player.equipped = {shirt = "tshirt", pants = "jeans", feet = "boots"}
local def
for _, d in ipairs(H.ENCOUNTERS) do if d.name == "Jawhound" then def = d end end
g:start_encounter(def)
g.enc.range = "close"
local hp0 = g.player.health
for _ = 1, 40 do
    if g.screen ~= "encounter" or g.player.health < hp0 then break end
    g:encounter_action("watch")
end
assert(g.player.health < hp0, "it hit")
assert(g:cond("shirt") + g:cond("pants") + g:cond("feet") < 300, "the hit wore something")
print("   OK")

print("4. torn: no warmth, half the pockets, a log line and a condition")
g = fresh()
g.player.equipped = {shirt = "tshirt", pants = "jeans", back = "backpack"}
local warm, cap = g:warmth(), g:bag_capacity()
g:wear_out("pants", 200)
assert(g:torn("pants") and g:warmth() == warm - ITEM_DB.jeans.warmth)
assert(g:bag_capacity() == cap - ITEM_DB.jeans.pocket_cells + ITEM_DB.jeans.pocket_cells // 2)
assert(g.log[#g.log]:find("jeans tears"), g.log[#g.log])
assert(g:current_conditions():find("Torn clothes"))
g:wear_out("back", 200)
assert(g:bag_capacity() == ITEM_DB.backpack.bag_cells // 2 + ITEM_DB.jeans.pocket_cells // 2)
print("   OK")

print("5. Patch clothes mends the most worn piece for 1 cloth; blocked when nothing needs it")
g = fresh()
local r = patch_recipe()
assert(r and g.known[r.id])
g.player.equipped = {shirt = "tshirt", pants = "jeans"}
g.ground["0,0"] = {{item = "cloth_scrap", qty = 2}}
assert(g:craft_blocker(r) == "Nothing you wear needs mending.")
g:wear_out("shirt", 30); g:wear_out("pants", 100)
assert(g:craft(r))
assert(near(g:cond("pants"), W.mend) and near(g:cond("shirt"), 70), "the torn one first")
assert(g:count_item("cloth_scrap") == 1)
g:wear_out("shirt", 40.3)   -- (wear by the hour leaves fractions)
assert(g:mend_text():find("T%-Shirt 29%%") or g:mend_text():find("29%%"), g:mend_text())
assert(g:craft(r) and g.log[#g.log]:find("79%%"), g.log[#g.log])
print("   OK")

print("6. condition goes with the piece: off, on the ground, in the bag, on again")
g = fresh()
g.player.equipped = {shirt = "tshirt"}
g:wear_out("shirt", 40)
g.ground["0,0"] = {{item = "tshirt", qty = 1}}
assert(g:try_transfer({"equip", "shirt"}, {"ground"}))
local gr = g:ground_list()
assert(#gr == 2, "a worn shirt and a new one don't stack")
local wi
for i, s in ipairs(gr) do if s.cond then wi = i end end
assert(wi and near(gr[wi].cond, 60))
assert(g:try_transfer({"ground", wi}, {"inventory"}))
assert(near(g.player.inventory[1].cond, 60))
assert(g:try_transfer({"inventory", 1}, {"equip", "shirt"}))
assert(near(g:cond("shirt"), 60))
assert(g:cursor_description() ~= nil)
-- swapping: the new shirt goes on, the worn one comes off still worn
local ni
for i, s in ipairs(g:ground_list()) do if not s.cond then ni = i end end
assert(g:try_transfer({"ground", ni}, {"equip", "shirt"}))
assert(g:cond("shirt") == 100 and near(g.player.inventory[1].cond, 60))
print("   OK")

print("7. saved; an old save without wear loads as new")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
g.player.equipped = {shirt = "tshirt"}
g:wear_out("shirt", 25)
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(near(g2:cond("shirt"), 75))
g2.player.wear = nil
assert(g2:cond("shirt") == 100)
print("   OK")

print("\nWEAR TESTS PASSED")
