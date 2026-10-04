-- Skills: XP from each action, levels at the thresholds, each bonus, saving.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local SKILLS, HUNT, TECH = H.SKILLS, H.HUNT, H.TECH

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end

print("1. levels at the thresholds, 0 to 5")
local g = fresh()
assert(g:skill_level("scav") == 0 and g:skill_bonus("scav") == 0)
for i, need in ipairs(SKILLS.levels) do
    g.skills.scav = need - 1
    assert(g:skill_level("scav") == i - 1)
    g.skills.scav = need
    assert(g:skill_level("scav") == i)
end
g.skills.scav = 9999
assert(g:skill_level("scav") == 5 and g:skill_bonus("scav") == 5 * SKILLS.bonus.scav)

print("2. a level-up logs a line and plays a sound")
g = fresh()
g.skills.fight = SKILLS.levels[1] - 1
g:skill_xp("fight", 1)
assert(g.log[#g.log]:find("Fighting improves to 1", 1, true), g.log[#g.log])
assert(g.last_sfx == "level")

print("3. searching earns scav XP (+1, +1 per find)")
g = fresh()
local key = g.player.q .. "," .. g.player.r
local found_xp = false
for _ = 1, 30 do
    g.scavenged = {}
    g.player.mp, g.player.health = 5, 100
    g.ground = {}
    local before = g.skills.scav or 0
    local n, drop = 0, g.drop_found   -- (finds counted as they drop: a pile of rubles is one)
    g.drop_found = function(self, ...) n = n + 1; return drop(self, ...) end
    g:scavenge()
    g.drop_found = nil
    local gained = (g.skills.scav or 0) - before
    assert(gained == SKILLS.xp.search + SKILLS.xp.find * n, gained .. " for " .. n)
    if n > 0 then found_xp = true end
end
assert(found_xp, "never found anything in 30 searches")

print("4. scav levels cut the dud weight")
local function dud_share(level)
    local s = fresh()
    local duds, n = 0, 3000
    for _ = 1, n do
        s.skills.scav = level > 0 and SKILLS.levels[level] or 0   -- (searching earns XP)
        s.scavenged, s.ground = {}, {}
        s.player.mp, s.player.health = 5, 100
        s.player.needs = {hunger = 100, thirst = 100, rest = 100}
        local k = s.player.q .. "," .. s.player.r
        s:scavenge()
        if #(s.ground[k] or {}) == 0 then duds = duds + 1 end
    end
    return duds / n
end
local d0, d5 = dud_share(0), dud_share(5)
print(("   empty searches: level 0 %.2f, level 5 %.2f"):format(d0, d5))
assert(d5 < d0, "level 5 should find more")

print("5. a catch and a found trail earn fish XP (empty casts don't); the bonus raises the odds")
g = fresh()
g.maybe_karl = function() end   -- (it rolls too)
local rolled
local real_roll = g.roll
g.roll = function(self, pct) rolled = pct; return false end
g:fish()
assert((g.skills.fish or 0) == 0, "an empty cast earns nothing")
local base_fish = rolled
g.skills.fish = SKILLS.levels[2]
g:fish()
assert(rolled == base_fish + 2 * SKILLS.bonus.fish, rolled .. " vs " .. base_fish)
g.skills.fish = 0
g:hunt()
assert(g.skills.fish == 0, "old prints earn nothing")
local base_hunt = rolled
g.skills.fish = SKILLS.levels[1]
g:hunt()
assert(rolled == base_hunt + SKILLS.bonus.fish)
g.skills.fish = 0
g.roll = function(self, pct) rolled = pct; return true end
g:fish()
assert(g.skills.fish == SKILLS.xp.catch, "a catch")
g.skills.fish = 0
g:hunt()
assert(g.skills.fish == SKILLS.xp.hunt, "a found trail")
g.enc = nil
g.screen = "map"
g.roll = real_roll

print("6. fights: hits and kills earn fight XP; the bonus raises the hit chance")
g = fresh()
g.roll = function(self, pct) rolled = pct; return true end
g:hunt()                       -- starts a fight with an animal
assert(g.enc, "hunt found nothing")
g.skills.fight = 0
g.enc.range = "close"
g.enc.aim = 0
g.enc.hp = 999
g:encounter_action("attack")
assert(g.skills.fight == SKILLS.xp.hit, tostring(g.skills.fight))
local base_hit = rolled
g.skills.fight = SKILLS.levels[3]
g.enc.aim = 0
local xp = g.skills.fight
g:encounter_action("attack")
-- the roll was the player's hit (the enemy's turn came after)
assert(g.skills.fight >= xp + SKILLS.xp.hit)
g.enc.hp = 1
xp = g.skills.fight
g.enc.aim = 0
g:encounter_action("attack")
assert(g.skills.fight == xp + SKILLS.xp.hit + SKILLS.xp.kill, "kill XP")
g.roll = real_roll

print("7. hit chance includes the fight bonus")
g = fresh()
g.roll = function(self, pct) if not rolled then rolled = pct end; return false end
g:hunt()
g.roll = function(self, pct) return true end
g:hunt()
g.enc.range, g.enc.aim, g.enc.hp = "close", 0, 999
local first
g.roll = function(self, pct) first = first or pct; return false end
g:encounter_action("attack")
local p0 = first
first = nil
g.skills.fight = SKILLS.levels[2]
g.enc.aim = 0
g:encounter_action("attack")
assert(first == p0 + 2 * SKILLS.bonus.fight, first .. " vs " .. p0)
g.roll = real_roll

print("8. crafting earns tinker XP; tinker 3 is an hour quicker")
g = fresh()
local spear   -- (a recipe over an hour, so the tinker hour shows)
for _, r in ipairs(H.RECIPES) do if r.out and r.out[1] == "spear" then spear = r end end
assert(spear and spear.hours > 1)
g.known[spear.id] = true
g.player.inventory = {}
-- (a shaft and a sharp edge: a stick and a knife)
g.player.inventory = {{item = "stick", qty = 2}, {item = "knife", qty = 1}}
local h0 = g.player.hours
assert(g:craft(spear))
assert(g.skills.tinker == SKILLS.xp.craft)
assert(g.player.hours - h0 == spear.hours)
g.skills.tinker = SKILLS.levels[SKILLS.fast_craft]
assert(g:craft_hours(spear) == math.max(1, spear.hours - 1))
assert(g:craft_hours({hours = 1}) == 1, "never under an hour")
h0 = g.player.hours
assert(g:craft(spear))
assert(g.player.hours - h0 == g:craft_hours(spear))

print("9. repairs: +2 an attempt, +3 more on success; tinker adds to the chance")
g = fresh()
local fix = TECH.repairs[1]
local c0 = g:repair_chance(fix)
g.skills.tinker = SKILLS.levels[2]
assert(g:repair_chance(fix) == math.min(95, c0 + 2 * SKILLS.bonus.tinker))
g.skills.tinker = 0
local inv = {{item = fix.broken, qty = 1}, {item = TECH.tool, qty = 1}}
for part, n in pairs(fix.parts) do inv[#inv + 1] = {item = part, qty = n * 2} end
g.player.inventory = inv
local r = g:repair_recipes()[1]
g.roll = function() return false end
g:craft(r)
assert(g.skills.tinker == SKILLS.xp.repair, tostring(g.skills.tinker))
g.roll = function() return true end
g:craft(r)
assert(g.skills.tinker == 2 * SKILLS.xp.repair + SKILLS.xp.repaired)
g.roll = real_roll

print("10. the journal shows the skills line")
g = fresh()
g.skills = {scav = SKILLS.levels[2], fight = SKILLS.levels[3]}
local line
for _, l in ipairs(g:journal_lines()) do if l:find("^Skills:") then line = l end end
assert(line == "Skills: Scav 2  Fish 0  Fight 3  Tinker 0", tostring(line))

print("11. skills are saved")
g = fresh()
g.skills = {scav = 12, tinker = 60}
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.skills.scav == 12 and g2.skills.tinker == 60 and g2:skill_level("tinker") == 3)

print("skills_test: ok")
