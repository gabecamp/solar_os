-- Health, injuries, weapons, and (later) encounters.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, E = dofile("lib_encounter.lua")
local ENTER = 10

local function fresh()
    local g = Game.new()
    g:start_game()
    g.player.q, g.player.r = 0, 0
    return g
end

print("1. health: starts full, bleeding drains it awake and asleep, rest heals")
local g = fresh()
local p = g.player
assert(p.health == E.MAX_HEALTH)
p.injuries.bleeding = true
p.mp = 0
g:rest()
assert(p.health == E.MAX_HEALTH - 4 * E.BLEED_PER_HOUR, "4h of rest while bleeding")
p.injuries.bleeding = false
p.health = 50
p.mp = 0
g:rest()
assert(p.health > 50, "rest heals when not bleeding")
print("   OK")

print("2. E on a cloth scrap while bleeding bandages (one scrap used)")
g = fresh(); p = g.player
p.injuries.bleeding = true
p.inventory = {{item = "cloth_scrap", qty = 2}}
g:use_item("inventory", 1)
assert(not p.injuries.bleeding and p.inventory[1].qty == 1)
g:use_item("inventory", 1)       -- not bleeding: goes to a hand like any other item
assert(p.equipped.rhand == "cloth_scrap")
print("   OK")

print("3. a wound costs 1 MP until enough rest")
g = fresh(); p = g.player
local full = E.effective_max_mp(p)
p.injuries.wounded_hours = E.WOUND_REST_HOURS
assert(E.effective_max_mp(p) == math.max(1, full - 1))
for _ = 1, E.WOUND_REST_HOURS // 4 do p.mp = 0; g:rest() end
assert(p.injuries.wounded_hours == 0 and E.effective_max_mp(p) == full)
print("   OK")

print("4. health 0: bleeding out ends on the death screen")
g = fresh(); p = g.player
p.health = 2; p.injuries.bleeding = true; p.mp = 0
g:rest()
assert(g.screen == "dead" and g.death_cause, "bled out while resting")
print("   OK")

print("5. weapons have sprites and sane stats")
local n = 0
for id, def in pairs(E.ITEM_DB) do
    if def.weapon then
        n = n + 1
        assert(def.weapon.dmg > 0 and (def.weapon.reach == "close" or def.weapon.reach == "near"), id)
    end
end
assert(n >= 4)
print("   OK")

local function def_named(name)
    for _, d in ipairs(E.ENCOUNTERS) do if d.name == name then return d end end
    error("no encounter " .. name)
end
local function act(g, action) g:encounter_action(action) end

print("6. encounter kinds follow the weights; helpers are rare")
g = fresh()
g.seed = 777
local counts, n = {}, 6000
for _ = 1, n do
    local d = g:pick_encounter()
    counts[d.kind] = (counts[d.kind] or 0) + 1
end
local total_w, present = 0, {}
for _, k in ipairs(E.ENCOUNTER_KINDS) do
    for _, d in ipairs(E.ENCOUNTERS) do if d.kind == k[1] then present[k[1]] = k[2] end end
end
for _, w in pairs(present) do total_w = total_w + w end
for kind, w in pairs(present) do
    local got, want = (counts[kind] or 0) / n, w / total_w
    print(("   %-7s %5.1f%%  (weight %4.1f%%)"):format(kind, got * 100, want * 100))
    assert(math.abs(got - want) < 0.02, kind .. " rate off")
end
assert(counts.helper and counts.helper / n < 0.06, "helpers must stay rare")

print("7. text fits: intros <= 6 lines, every state has <= 7 options of <= 55 chars")
for _, d in ipairs(E.ENCOUNTERS) do
    local lines = E.wrap(d.intro, E.ENC_COLS)
    assert(#lines <= 6, d.name .. " intro is " .. #lines .. " lines")
    for _, l in ipairs(lines) do assert(#l <= E.ENC_COLS) end
    for _, range in ipairs({"far", "near", "close"}) do
        for _, hands in ipairs({{}, {rhand = "spear", lhand = "rock"}}) do
            g = fresh()
            g.player.equipped.rhand, g.player.equipped.lhand = hands.rhand, hands.lhand
            g:start_encounter(d)
            g.enc.range = range
            g.enc.demanding = false
            local opts = g:encounter_options()
            assert(#opts <= 7, d.name .. " at " .. range .. ": " .. #opts .. " options")
            for i, o in ipairs(opts) do assert(#(" " .. i .. " " .. o[1]) <= E.ENC_COLS) end
        end
    end
end
print("   OK")

print("8. fighting it out: wins drop loot, losses end on the death screen")
local wins, fled, deaths = 0, 0, 0
for seed = 1, 300 do
    g = fresh()
    g.seed = seed
    g.player.equipped.rhand = "pipe"
    g:start_encounter(def_named("Jawhound"))
    for _ = 1, 60 do
        if g.enc.over or g.screen ~= "encounter" then break end
        act(g, g.enc.range == "close" and "attack" or "approach")
    end
    if g.screen == "dead" then
        deaths = deaths + 1
    elseif g.enc.hp <= 0 then
        wins = wins + 1
    else
        assert(g.enc.over, "fight must end within 60 rounds")
        fled = fled + 1
    end
end
print(("   pipe vs jawhound x300: %d kills, %d fled, %d deaths"):format(wins, fled, deaths))
assert(wins > 150 and wins + fled + deaths == 300)

print("9. a fatal hit ends on the death screen with the killer named")
g = fresh()
g.player.health = 1
g:start_encounter(def_named("Skinless Boar"))
g.enc.range = "close"
for _ = 1, 50 do if g.screen == "encounter" then act(g, "watch") end end
assert(g.screen == "dead" and g.death_cause:find("Boar"), tostring(g.death_cause))
print("   OK")

print("10. fleeing costs 1 MP and Continue returns to the map")
local escaped = false
for seed = 1, 50 do
    g = fresh()
    g.seed = seed
    local mp = g.player.mp
    g:start_encounter(def_named("Crawling Stag"))
    act(g, "flee")
    if g.enc.over then
        assert(g.player.mp == mp - 1)
        act(g, "leave")
        assert(g.screen == "map" and g.enc == nil)
        escaped = true
        break
    end
end
assert(escaped)
print("   OK")

print("11. bandits: paying with food costs exactly one item and ends it")
g = fresh()
g.player.inventory = {{item = "rock", qty = 1}, {item = "canned_beans", qty = 2}}
g:start_encounter(def_named("Road Bandits"))
assert(g.enc.demanding and g:encounter_options()[1][2] == "give")
act(g, "give")
assert(g.player.inventory[2].qty == 1 and g.enc.over)
g = fresh()
g.player.inventory = {}
g:start_encounter(def_named("Toll Man"))
assert(g:encounter_options()[1][2] == "refuse", "no food: no give option")
act(g, "refuse")
assert(not g.enc.demanding)
print("   OK")

print("12. helpers: the medic stops bleeding and heals; the wanderer maps the area")
g = fresh()
g.player.health = 40; g.player.injuries.bleeding = true
g:start_encounter(def_named("Old Medic"))
act(g, "talk")
assert(g.player.health == 65 and not g.player.injuries.bleeding and g.enc.over)
g = fresh()
local before = 0; for _ in pairs(g.player.explored) do before = before + 1 end
g:start_encounter(def_named("Wanderer"))
act(g, "talk")
local after = 0; for _ in pairs(g.player.explored) do after = after + 1 end
assert(after > before)
print("   OK")

print("13. moves trigger encounters at roughly the terrain rate, with a cooldown")
g = fresh()
g.seed = 4242
local started = 0
for _ = 1, 3000 do
    g:maybe_encounter("forest")
    if g.screen == "encounter" then
        started = started + 1
        g.screen, g.enc = "map", nil
        g.enc_cooldown = 2
    end
end
print(("   %d encounters in 3000 forest moves"):format(started))
assert(started > 200 and started < 450)
print("   OK")

print("\nENCOUNTER TESTS PASSED")
