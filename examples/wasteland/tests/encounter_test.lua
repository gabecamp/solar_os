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

-- anomalies ------------------------------------------------------------
local UP, DOWN, LEFT, RIGHT, ESC = gfx.KEY_UP, gfx.KEY_DOWN, gfx.KEY_LEFT, gfx.KEY_RIGHT, gfx.KEY_ESCAPE
local function puzzle(kind, seed)
    for s = seed or 1, (seed or 1) + 500 do
        local g2 = fresh()
        g2.seed = s
        g2:start_encounter(def_named("The Stillness"))
        act(g2, "investigate")
        if g2.puz.kind == kind then return g2 end
    end
    error("never rolled a " .. kind .. " puzzle")
end
-- shortest safe route through the bolt grid, as direction keys
local function safe_route(z)
    local N = E.BOLT_N
    local prev, queue, head = {[E.BOLT_START] = 0}, {E.BOLT_START}, 1
    while queue[head] do
        local c = queue[head]; head = head + 1
        local r, col = (c - 1) // N, (c - 1) % N
        for _, step in ipairs({{-N, UP, r > 0}, {N, DOWN, r < N - 1}, {-1, LEFT, col > 0}, {1, RIGHT, col < N - 1}}) do
            local n = c + step[1]
            if step[3] and not z.haz[n] and not prev[n] then prev[n] = {c, step[2]}; queue[#queue + 1] = n end
        end
    end
    local keys, c = {}, E.BOLT_GOAL
    while c ~= E.BOLT_START do table.insert(keys, 1, prev[c][2]); c = prev[c][1] end
    return keys
end
local function ground_has(g2, id)
    for _, st in ipairs(g2:ground_list()) do if st.item == id then return true end end
end
local function hurt(g2, hp, hours)
    return g2.player.health < hp or g2.player.injuries.bleeding or g2.player.hours > hours
end

print("14. bolts: every board is walkable, and walking the safe route solves it")
for s = 1, 60 do
    local g2 = puzzle("bolts", s * 7)
    local z = g2.puz
    local n = 0; for _ in pairs(z.haz) do n = n + 1 end
    assert(n == E.BOLT_HAZARDS and not z.haz[E.BOLT_START] and not z.haz[E.BOLT_GOAL])
    for _, k in ipairs(safe_route(z)) do g2:puzzle_key(k) end
    assert(g2.screen == "map" and g2.puz == nil, "reaching the glint solves it")
end
print("   OK")

print("15. bolts: a thrown bolt reveals a cell; stepping on a hazard fails and hurts")
local g2 = puzzle("bolts", 3)
local z = g2.puz
local bolts = z.bolts
g2:puzzle_key(116); g2:puzzle_key(UP)
assert(z.bolts == bolts - 1 and z.revealed[E.BOLT_START - E.BOLT_N] and z.pos == E.BOLT_START)
local hazard_dir
for s = 1, 500 do
    g2 = puzzle("bolts", s)
    for _, d in ipairs({{-E.BOLT_N, UP}, {-1, LEFT}, {1, RIGHT}}) do
        if g2.puz.haz[E.BOLT_START + d[1]] then hazard_dir = d[2] end
    end
    if hazard_dir then break end
end
local hp, hours = g2.player.health, g2.player.hours
g2:puzzle_key(hazard_dir)
assert(g2.screen ~= "puzzle" and hurt(g2, hp, hours))
print("   OK")

print("16. sequence: typing the signs in order solves it; a wrong sign fails")
g2 = puzzle("sequence")
for _ = 1, #E.SEQ_LENGTHS do
    local seq = g2.puz.seq
    g2:puzzle_key(32)                              -- hide the signs
    for _, sign in ipairs(seq) do g2:puzzle_key(48 + sign) end
end
assert(g2.screen == "map" and g2.puz == nil)
g2 = puzzle("sequence")
hp, hours = g2.player.health, g2.player.hours
g2:puzzle_key(32)
g2:puzzle_key(48 + (g2.puz.seq[1] % 4) + 1)
assert(g2.screen ~= "puzzle" and hurt(g2, hp, hours))
print("   OK")

print("17. runes: always scrambled, solvable within the presses; running out fails")
for s = 1, 60 do
    g2 = puzzle("runes", s * 5)
    z = g2.puz
    assert(#z.scramble <= z.moves)
    for _, i in ipairs(z.scramble) do g2:puzzle_key(48 + i) end
    assert(g2.screen == "map", "replaying the scramble solves it")
end
g2 = puzzle("runes")
hp, hours = g2.player.health, g2.player.hours
for _ = 1, 40 do if g2.screen == "puzzle" then g2:puzzle_key(49) end end
assert(g2.screen ~= "puzzle")
print("   OK")

print("18. Esc backs away with no harm; solved puzzles leave artifacts ~25% of the time")
g2 = puzzle("runes")
hp, hours = g2.player.health, g2.player.hours
g2:puzzle_key(ESC)
assert(g2.screen == "map" and not hurt(g2, hp, hours))
local got, tries = 0, 2000
for s = 1, tries do
    g2 = fresh(); g2.seed = s
    g2:start_encounter(def_named("Wrong Stars"))
    g2.puz = {kind = "runes"}
    g2.screen = "puzzle"
    g2:finish_puzzle("solved")
    for _, id in ipairs(E.ARTIFACTS) do if ground_has(g2, id) then got = got + 1 end end
end
print(("   artifacts: %.1f%%"):format(100 * got / tries))
assert(math.abs(got / tries - 0.25) < 0.03)

print("19. artifacts work while held and stop when put away")
g2 = fresh()
local p2 = g2.player
local mp0, sight0 = p2.max_mp, p2.sight
p2.inventory = {{item = "weeping_stone", qty = 1}, {item = "quiet_shell", qty = 1}}
g2:try_transfer({"inventory", 1}, {"equip", "rhand"})
assert(p2.max_mp == mp0 + 1 and p2.thirst_mult == 1.5)
g2:try_transfer({"equip", "rhand"}, {"inventory"})
assert(p2.max_mp == mp0 and p2.thirst_mult == 1)
g2:try_transfer({"inventory", 1}, {"equip", "lhand"})   -- the shell (now first)
assert(p2.encounter_mult == 0.5 and p2.sight == math.max(1, sight0 - 1))
g2 = fresh(); p2 = g2.player
p2.equipped.lhand = "flesh_knot"; E.recompute_stats(p2)
p2.health = 50
g2:try_move(1, 0); g2:try_move(0, 0); g2:try_move(-1, 0)
assert(p2.health > 50 or g2.screen == "encounter", "the knot heals while you walk")
g2 = fresh(); p2 = g2.player
p2.equipped.rhand = "hollow_star"; E.recompute_stats(p2)
g2.tiles["0,0"] = "plains"
g2:scavenge()
assert(p2.health == E.MAX_HEALTH - 3)
print("   OK")

print("\nENCOUNTER TESTS PASSED")
