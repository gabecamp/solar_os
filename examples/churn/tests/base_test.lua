-- A base: claiming a ruin, building on it, what each part does, saving.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")

local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function recipe(id) for _, r in ipairs(H.RECIPES) do if r.id == id then return r end end end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end
local function fresh()
    local g = Game.new()
    g:start_game()
    g.ticked_hour = g.player.hours
    for k in pairs(g.ground) do g.ground[k] = {} end
    return g
end
local function on(g, terrain)
    for k, t in pairs(g.tiles) do
        if t == terrain and k ~= g.sites.trader then g.player.q, g.player.r = parse(k); return k end
    end
end
local function stock(g, items)
    g.player.inventory = {}
    for item, n in pairs(items) do table.insert(g.player.inventory, {item = item, qty = n}) end
end
local LOTS = {rope = 9, scrap_metal = 20, cloth_scrap = 9, stick = 12, empty_bottle = 2}

print("1. claim: only a ruin; costs rope, scrap and time")
local g = fresh()
on(g, "plains")
stock(g, LOTS)
assert(g:craft_blocker(recipe("claim")):find("ruin"))
local key = on(g, "ruins")
local hours = g.player.hours
assert(g:craft(recipe("claim")))
assert(g.base and g.base.key == key and g:at_base() and g.player.hours == hours + 4)
assert(g:craft_blocker(recipe("claim")):find("already"))

print("2. building: only at camp, once each; the barrel needs the box")
for _, part in ipairs({"bedroll", "barrel", "barricade"}) do   -- (learned: Bushcraft, Tinkering)
    assert(g:craft_blocker(recipe(part)):find("know"), part)
    g.known[part] = true
end
assert(g:craft_blocker(recipe("barrel")):find("Stash box"))
assert(g:craft(recipe("box")) and g:base_has("box"))
assert(g:craft_blocker(recipe("box")) == "Already built.")
for _, part in ipairs({"bedroll", "barrel", "barricade"}) do assert(g:craft(recipe(part)), part) end
on(g, "plains")
stock(g, LOTS)
g.base.built.bedroll = nil
assert(g:craft_blocker(recipe("bedroll")):find("camp"))
g.base.built.bedroll = true
g.player.q, g.player.r = parse(key)

print("3. what it does: warm bedroll, better rest, no encounters, a stash box")
g.weather = function() return "Cold snap" end
assert(not g:is_cold(), "the bedroll keeps you warm")
g.player.needs.rest, g.player.mp = 10, 0
g:rest()
local bed_rest = g.player.needs.rest
assert(has_log(g, "bedroll"))
local g2 = fresh()
g2.player.needs.rest, g2.player.mp = 10, 0
g2:rest()
assert(bed_rest > g2.player.needs.rest, "rests better in the bedroll")
for _ = 1, 200 do
    g.enc_cooldown, g.karl_next = 0, 1e9
    g:maybe_encounter("ruins")
    assert(g.screen == "map", "an encounter at a barricaded camp")
end
local texts = {}
gfx.text = function(_, _, s) texts[#texts + 1] = s end
g:draw_inventory(400, 300)
assert(table.concat(texts, "\n"):find("Stash box", 1, true))

print("4. the rain barrel fills bottles into the box, up to a cap")
g.weather = function() return "Clear" end
g.ground[key] = {}
for _ = 1, 24 * 6 do
    g.player.needs.thirst, g.player.needs.hunger, g.player.health = 100, 100, 100
    g.player.hours = g.player.hours + 1
    g:tick()
end
local water = 0
for _, s in ipairs(g.ground[key]) do if s.item == "water_bottle" then water = s.qty end end
assert(water == 6, "barrel water " .. water)

print("5. the journal and the map show it; claiming elsewhere moves it; saved")
assert(table.concat(g:journal_lines(), " "):find("Camp: here", 1, true))
g:draw_map(400, 300)
local key2 = nil
for k, t in pairs(g.tiles) do if t == "ruins" and k ~= key and k ~= g.sites.trader then key2 = k end end
g.player.q, g.player.r = parse(key2)
stock(g, LOTS)
assert(g:craft(recipe("claim")) and g.base.key == key2 and next(g.base.built) == nil)
FAKE_FILES, FAKE_DIRS = {}, {}
g.base.built.box = true
assert(g:save())
local g3 = Game.new()
g3:load_state(Game.read_save())
assert(g3.base.key == key2 and g3.base.built.box)

print("BASE TESTS PASSED")
