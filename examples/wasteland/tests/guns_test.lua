-- Handguns (src/62_guns.lua): assembled from a frame and parts (it can
-- fail), shot at any range with their own rounds, loud, wearing and
-- jamming, cleaned with oil; the bow and sling are quiet. The Elder Sign
-- sends a horror away.
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
    g.player.equipped = {back = "backpack"}
    return g
end
local function recipe(id)
    for _, r in ipairs(C.RECIPES) do if r.id == id then return r end end
    error("no recipe " .. id)
end
local function give(g, item, n) table.insert(g.player.inventory, {item = item, qty = n or 1}) end
local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    for _, s in ipairs(g:ground_list()) do if s.item == item then n = n + s.qty end end
    return n
end
local BEAST = {kind = "animal", name = "Boar", who = "boar", hp = 400, dmg = {1, 1}, hit = 0,
               speed = 1, start = "far", intro = "x", loot = {{"nothing", 1}}}

print("1. every gun has a sprite, rounds that exist, and a way to get it")
local guns = {"pm_pistol", "nagant", "tokarev", "inst_sidearm", "marsh_revolver"}
for _, id in ipairs(guns) do
    local def = C.ITEM_DB[id]
    assert(def.shoot and C.ITEM_DB[def.shoot.ammo] and C.SPRITES[id] and C.SPRITES[def.shoot.ammo], id)
end
for _, id in ipairs({"frame_pm", "frame_nagant", "frame_tt", "frame_inst", "gun_slide", "gun_barrel",
                     "gun_spring", "firing_pin", "magazine", "cylinder"}) do
    assert(C.ITEM_DB[id] and C.SPRITES[id], id)
end
local relic = false
for _, id in ipairs(C.TECH.world_items) do relic = relic or id == "marsh_revolver" end
assert(relic, "one Marsh Revolver lies in the world")
print("   OK")

print("2. assembly: learned, needs gun tools, can fail and break a part")
local g = fresh()
local pm = recipe("assemble_pm")
for item, n in pairs(pm.inputs) do give(g, item, n) end
assert(g:craft_blocker(pm):find("know"))
g.known.assemble_pm = true
assert(g:craft_blocker(pm):find("gun tools"))
give(g, "multitool")
assert(g:craft_blocker(pm) == nil)
g.roll = function() return false end   -- it fails
assert(g:craft(pm))
assert(count(g, "pm_pistol") == 0 and count(g, "frame_pm") == 1, "the frame survives a failure")
local missing = 0
for item in pairs(pm.inputs) do if count(g, item) == 0 then missing = missing + 1 end end
assert(missing == 1, "one part broke")
for item in pairs(pm.inputs) do if count(g, item) == 0 then give(g, item) end end
g.roll = function() return true end
assert(g:craft(pm) and count(g, "pm_pistol") == 1 and count(g, "frame_pm") == 0)
assert(g:craft_chance(pm) >= 5 and g:craft_chance(pm) <= 95)
print("   OK")

print("3. shooting: at far range, one round a shot, loud")
g = fresh()
g.player.equipped.rhand = "pm_pistol"
g:start_encounter(BEAST)
local function has_opt(id)
    for _, o in ipairs(g:encounter_options()) do if o[2] == id then return o[1] end end
end
assert(not has_opt("shoot"), "no rounds, no shot")
give(g, "r9x18", 3)
assert(has_opt("shoot") and has_opt("shoot"):find("3"), "Shoot shows the rounds")
g.roll = function(_, pct) return pct > 30 end   -- hits (45% at far), never jams (<10%)
local hp = g.enc.hp
g:encounter_action("shoot")
assert(g.enc.hp < hp and count(g, "r9x18") == 2, "a hit, a round gone")
assert(g.noise_until and g.noise_until > g.player.hours and g:noise_mult() > 1, "gunshots carry")
assert(g:gun_wear_of("pm_pistol") == 100 - C.CHURN.guns.wear_per_shot, "a gun wears")
print("   OK")

print("4. jams: worse as it wears; the Nagant never jams; cleaning restores it")
g.gun_wear.pm_pistol = 20
assert(g:jam_chance("pm_pistol") > C.ITEM_DB.pm_pistol.shoot.jam)
assert(g:jam_chance("nagant") == 0)
g.roll = function() return true end   -- everything happens: it jams
hp = g.enc.hp
g:encounter_action("shoot")
assert(g.enc.hp == hp and count(g, "r9x18") == 1, "jammed: the round is lost")
g.enc = nil
g.screen = "map"
g.known.clean_gun = true
assert(g:craft_blocker(recipe("clean_gun")):find("Need"))
give(g, "gun_oil"); give(g, "cloth_scrap")
assert(g:craft(recipe("clean_gun")) and g:gun_wear_of("pm_pistol") == 100)
print("   OK")

print("5. the bow is quiet; the sling hurls rocks")
g = fresh()
g.player.equipped.rhand = "bow"
give(g, "arrow", 2)
g:start_encounter(BEAST)
g.roll = function(_, pct) return pct > 30 end
g:encounter_action("shoot")
assert(count(g, "arrow") == 1 and not g.noise_until, "quiet")
g = fresh()
g.player.equipped.lhand = "sling"
give(g, "rock", 2)
g:start_encounter(BEAST)
for _, o in ipairs(g:encounter_options()) do if o[2] == "shoot" then assert(o[1]:find("Sling")) end end
print("   OK")

print("6. the Marsh Revolver costs you")
g = fresh()
g.player.equipped.rhand = "marsh_revolver"
give(g, "r38", 2)
g:start_encounter(BEAST)
local rest = g.player.needs.rest
g.roll = function(_, pct) return pct > 30 end
g:encounter_action("shoot")
assert(g.player.needs.rest == rest - C.ITEM_DB.marsh_revolver.shoot.curse)
print("   OK")

print("7. the Elder Sign: only against horrors and the dark, and it crumbles")
g = fresh()
give(g, "elder_sign")
g:start_encounter(BEAST)
for _, o in ipairs(g:encounter_options()) do assert(o[2] ~= "elder", "not for a boar") end
g.enc = nil
g:start_encounter({kind = "horror", horror = "long_man", name = "The Long Man", who = "long man",
                   start = "far", speed = 3, intro = "x"})
local opts = g:encounter_options()
assert(opts[1][2] == "elder")
g:encounter_action("elder")
assert(g.enc.over and count(g, "elder_sign") == 0)
print("   OK")

print("8. reloading makes rounds from brass, powder and lead")
g = fresh()
g.known.reload_9x18 = true
give(g, "brass", 3); give(g, "gunpowder"); give(g, "lead_scrap"); give(g, "gunsmith_kit")
assert(g:craft(recipe("reload_9x18")) and count(g, "r9x18") == 3 and count(g, "gunsmith_kit") == 1)
print("   OK")

print("\nGUNS TESTS PASSED")
