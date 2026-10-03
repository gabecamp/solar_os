-- Balance simulator: a bot plays whole runs with the real game code and we
-- count how they end. Not part of the game or the test suite.
--
--   cd examples/churn/tests && lua5.4 ../tools/balance_sim.lua [runs] [first_seed]
--
-- The bot plays like a careful human who knows the rules but not the map:
-- keeps drinking and eating, bandages, takes anti-rad, wears what it finds,
-- holds its best weapon, fights only when armed well enough (else hides or
-- runs), pays bandits when it can, shelters from emissions in ruins, sells
-- its finds for a permit (or keeps 3 artifacts) and walks out the
-- Checkpoint once it knows where it is. It skips anomaly puzzles. It reads
-- books, plays tapes and pairs drives, studies once before a rest at a fire
-- it makes (NO_STUDY=1 turns all that off), and crafts what it learns.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()

local src = io.open(os.getenv("CHURN_FILE") or "../churn.lua"):read("a")   -- (try variants)
local lib = src:sub(1, src:find("-- Main loop", 1, true) - 1) .. [[
return Game, {ITEM_DB = ITEM_DB, KEY = KEY, TERRAIN = TERRAIN, AXIAL_DIRS = AXIAL_DIRS,
              TRADE = TRADE, GOAL = GOAL, RECIPES = RECIPES, RAD = RAD, WORLD = WORLD,
              apply_awake_hours = apply_awake_hours, CHURN = CHURN}
]]
local Game, D = load(lib, "=churn")()
local ITEM_DB, KEY, TERRAIN = D.ITEM_DB, D.KEY, D.TERRAIN

local RUNS = tonumber(arg[1]) or 200
local FIRST = tonumber(arg[2]) or 1
local LEVEL = arg[3] or "normal"   -- easy / normal / hard
local MAX_HOURS = 24 * 30
local NO_STUDY = os.getenv("NO_STUDY")   -- (set: the bot never studies, reads or plays tapes)

local function key(q, r) return q .. "," .. r end
-- an hour that passes with nothing done still costs food, water and rest
local function wait_hour(g)
    g.player.hours = g.player.hours + 1
    D.apply_awake_hours(g.player, 1)
end
local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end

-- BFS over passable hexes from you; returns the first step toward the
-- nearest hex for which want(key) is true, and the distance.
local function step_toward(g, want, through_hot)
    local p = g.player
    local start = key(p.q, p.r)
    local prev, queue, i = {[start] = false}, {start}, 1
    while queue[i] do
        local k = queue[i]; i = i + 1
        if k ~= start and want(k) then
            local steps = 0
            while prev[k] ~= start do k = prev[k]; steps = steps + 1 end
            return k, steps + 1
        end
        local q, r = parse(k)
        for _, d in ipairs(D.AXIAL_DIRS) do
            local nk = key(q + d[1], r + d[2])
            -- like a person: once a hex is known to be hot, go around it
            if prev[nk] == nil and g.tiles[nk] and TERRAIN[g.tiles[nk]].passable
                and (through_hot or ((g.rad_known[nk] or 0) == 0 and not FELT[nk]) or want(nk)) then
                prev[nk] = k
                queue[#queue + 1] = nk
            end
        end
    end
end

local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    for _, slot in ipairs({"lhand", "rhand"}) do if g.player.equipped[slot] == item then n = n + 1 end end
    return n
end
local function inv_index(g, item)
    for i, s in ipairs(g.player.inventory) do if s.item == item then return i end end
end
local function use(g, item)
    local i = inv_index(g, item)
    if i then g:use_item("inventory", i); return true end
    for _, slot in ipairs({"lhand", "rhand"}) do
        if g.player.equipped[slot] == item then g:use_item("equip", slot); return true end
    end
    return false
end
local function recipe(id)
    for _, r in ipairs(D.RECIPES) do if r.id == id then return r end end
end
local function try_craft(g, id)
    local r = recipe(id)
    if r and g.known[id] and not g:craft_blocker(r) then return g:craft(r) end
end

-- Learning: the first read of each book, a tape while the player has
-- charge, a drive while the radio does; and at a fire (made if need be)
-- before resting, one study session: the useful topics first, gunsmithing
-- once there's something to study it from.
local STUDY_ORDER = {"bushcraft", "medicine", "rags", "gunsmithing", "tinkering", "chemistry"}
local function learn(g, stats)
    if NO_STUDY then return end
    local p = g.player
    for _, s in ipairs(p.inventory) do
        if ITEM_DB[s.item].book and not (g.books_read or {})[s.item] then use(g, s.item); break end
    end
    if count(g, "cassette_player") > 0 then
        if not (g.tapedeck and g.tapedeck.charge > 0) and count(g, "battery_cell") > 0 then
            use(g, "battery_cell")
        end
        if g.tapedeck and g.tapedeck.charge > 0 then
            for tape in pairs(D.CHURN.tapes) do
                if count(g, tape) > 0 then use(g, tape); break end
            end
        end
    end
    if count(g, "usb_drive") > 0 and g:carrying("lora_radio") and g.radio and g.radio.charge > 1 then
        use(g, "usb_drive")
    end
end
local function study(g, stats)
    if NO_STUDY then return end
    local p = g.player
    if p.needs.hunger < 35 or p.needs.thirst < 35 or p.health < 40 then return end
    if not (g:fire_here() or g:at_base()) then
        if g:count_item("@heat") == 0 then try_craft(g, "fire_drill") end
        local _ = try_craft(g, "small_fire") or try_craft(g, "campfire")
    end
    for _, t in ipairs(STUDY_ORDER) do
        if g:topic_next(t) and not g:study_blocker(t) then
            g:study(t)
            stats.studied = stats.studied + 1
            return true
        end
    end
end

-- Keep alive and kitted out.
local KEEP = {water_bottle = true, dirty_water = true, empty_bottle = true, canned_beans = true,
              jerky = true, cooked_meat = true, berries = true, strange_meat = true,
              bandage = true, cloth_scrap = true, antirad = true, splint = true, permit = true,
              stick = true, rock = true, geiger = true,
              fire_drill = true, matches = true, lighter = true, newspaper = true}
-- How good a piece of clothing is (warmth and room): the real thing beats
-- its makeshift version.
local function wear_score(item)
    local def = item and ITEM_DB[item]
    if not def then return -1 end
    return (def.warmth or 0) + (def.bag_cells or 0) + (def.pocket_cells or 0) + (def.belt_cells or 0)
        + (def.ragged_of and 0 or 0.5)
end
local function better_than_worn(g, item)
    local slot = ITEM_DB[item].slot
    if not slot or slot == "lhand" or slot == "rhand" then return false end
    return wear_score(item) > wear_score(g.player.equipped[slot])
end
-- You start with nothing: makeshift clothes for the empty slots, a shirt and
-- a bag first; the rest only with this much cloth (2 left for bandages).
local RAGS = {{"shirt", "rag_shirt"}, {"back", "sack_pack"}, {"back", "bindle"},
              {"pants", "rag_trousers", 2}, {"jacket", "patch_coat", 4}, {"feet", "foot_wraps", 3},
              {"head", "rag_hood", 4}, {"neck", "rag_scarf", 4}}

-- Worth picking up (the bot ignores junk).
local function worth(g, item)
    local def = ITEM_DB[item]
    if item == "rotten_meat" then return false end
    if item == "rock" then return count(g, "rock") == 0 end
    if item == "stick" then return count(g, "stick") < (NO_STUDY and 3 or 5) end
    if def.slot then return count(g, item) == 0 and better_than_worn(g, item) end
    -- tech and its parts only while there's room to spare (food comes first)
    if Game.item_value(item) >= 5 and not (def.consumable or def.artifact or def.weapon)
        and #g.player.inventory > g:bag_capacity() - 4 then
        return false
    end
    return def.consumable or def.artifact or KEEP[item] or def.weapon or Game.item_value(item) >= 5
end
local function pile_worth(g, k)
    for _, st in ipairs(g.ground[k] or {}) do if worth(g, st.item) then return true end end
    return false
end

local function upkeep(g, stats)
    local p = g.player
    learn(g, stats)
    if p.injuries.bleeding or p.injuries.wounded_hours > 12 then
        if count(g, "stitches") == 0 then try_craft(g, "stitches") end
        use(g, "stitches")
    end
    if p.injuries.bleeding then
        local _ = use(g, "bandage") or use(g, "cloth_scrap") or try_craft(g, "bandage")
    end
    if p.injuries.wounded_hours > 12 then use(g, "splint") end
    if (p.rads or 0) >= 45 then local _ = use(g, "antirad") or use(g, "vodka") end
    for _ = 1, 3 do
        if p.needs.thirst >= 55 then break end
        if not use(g, "water_bottle") then
            if count(g, "dirty_water") > 0 then
                local _ = try_craft(g, "boil") or try_craft(g, "filter")
                    or (p.needs.thirst < 20 and use(g, "dirty_water"))
            end
            break
        end
    end
    for _ = 1, 3 do
        if p.needs.hunger >= 55 then break end
        if g:fire_here() then try_craft(g, "cook") end
        local ate = false
        for _, food in ipairs({"cooked_meat", "canned_beans", "jerky", "berries"}) do
            if not ate and use(g, food) then ate = true end
        end
        if not ate and p.needs.hunger < 25 then ate = use(g, "strange_meat") end
        if not ate and p.needs.hunger < 10 then ate = use(g, "rotten_meat") end
        if not ate then break end
    end
    if g:near_water() and count(g, "empty_bottle") > 0 then g:water_action() end
    -- a full bag: drop the least useful thing (never food, water, meds,
    -- artifacts, the permit or a better weapon than the one in hand)
    if #p.inventory >= g:bag_capacity() then
        local worst, worst_v
        for i, st in ipairs(p.inventory) do
            local def = ITEM_DB[st.item]
            if not KEEP[st.item] and not def.consumable and not def.artifact then
                local v = Game.item_value(st.item) * st.qty
                if not worst or v < worst_v then worst, worst_v = i, v end
            end
        end
        if worst then g:try_transfer({"inventory", worst}, {"ground"}) end
    end
    -- patch what's wearing thin (keeping cloth for bandages)
    local _, worst = g:most_worn(40)
    if worst and count(g, "cloth_scrap") >= 3 then try_craft(g, "patch") end
    -- dress: makeshift clothes for empty slots, then put on anything better
    -- lying here, straight from the ground
    for _, rag in ipairs(RAGS) do
        if not p.equipped[rag[1]] and count(g, "cloth_scrap") >= (rag[3] or 0) then
            try_craft(g, rag[2])
        end
    end
    for i = #g:ground_list(), 1, -1 do
        local s = g:ground_list()[i]
        if s and better_than_worn(g, s.item) then
            g:try_transfer({"ground", i}, {"equip", ITEM_DB[s.item].slot})
        end
    end
    -- pick up everything that fits (useful things first)
    local ground = g:ground_list()
    for i = #ground, 1, -1 do
        local s = ground[i]
        if s and worth(g, s.item) then
            if ITEM_DB[s.item].artifact then stats.artifacts = stats.artifacts + s.qty end
            g:try_transfer({"ground", i}, {"inventory"})
        end
    end
    -- wear into empty slots; hold the best weapon
    for i = #p.inventory, 1, -1 do
        local s = p.inventory[i]
        local slot = s and ITEM_DB[s.item].slot
        if slot and better_than_worn(g, s.item) then g:try_transfer({"inventory", i}, {"equip", slot}) end
    end
    -- leave behind clothes you've outgrown (rags swapped for the real thing)
    for i = #p.inventory, 1, -1 do
        local s = p.inventory[i]
        local slot = ITEM_DB[s.item].slot
        if slot and slot ~= "lhand" and slot ~= "rhand" and not ITEM_DB[s.item].weapon
            and not better_than_worn(g, s.item) then
            g:try_transfer({"inventory", i}, {"ground"})
        end
    end
    local best, best_i = g:weapon().dmg, nil
    for i, s in ipairs(p.inventory) do
        local w = ITEM_DB[s.item].weapon
        if w and w.dmg > best then best, best_i = w.dmg, i end
    end
    if best_i then g:try_transfer({"inventory", best_i}, {"equip", "rhand"}) end
    for _, w in ipairs({"spear", "stone_knife", "glass_shiv", "shiv"}) do
        if g:weapon().dmg < 9 then try_craft(g, w) end
    end
    if not p.equipped.feet or p.equipped.feet == "foot_wraps" then try_craft(g, "rag_shoes") end
    if g:fire_here() and count(g, "cooked_meat") >= 2 then try_craft(g, "smoked_meat") end
    if count(g, "scrawled_notes") > 0 then use(g, "scrawled_notes") end
    if count(g, "rope") > 0 and not p.equipped.belt then try_craft(g, "rope_belt") end
    -- cold at night: a fire
    if (p.cold_hours or 0) > 0 and not g:fire_here() then try_craft(g, "campfire") end
end

local function encounter(g, stats)
    local e = g.enc
    local kind = e.def.kind
    stats.enc[kind] = (stats.enc[kind] or 0) + 1
    local hp0 = g.player.health
    for _ = 1, 60 do
        if g.screen == "puzzle" then g:puzzle_key(KEY.Q) end
        if g.screen ~= "encounter" or not g.enc then break end
        e = g.enc
        local opts, have = g:encounter_options(), {}
        for _, o in ipairs(opts) do have[o[2]] = true end
        local act
        if have.leave and e.over then act = "leave"
        elseif kind == "helper" then act = "talk"
        elseif kind == "anomaly" then act = "leave_quietly"
        elseif kind == "riddle" then act = "answer_" .. (g:rand(3) + 1)   -- Karl: it guesses
        elseif kind == "dog" then act = have.tame and "tame" or "leave_quietly"
        elseif kind == "horror" then act = have.look_away and "look_away" or "cover"
        elseif kind == "little" then act = have.offer_little and "offer_little" or "watch_little"
        elseif have.give then act = "give"
        else
            local armed = g:weapon().dmg >= 12 or have.shoot
            local fight = (armed or e.def.hp <= 25) and g.player.health > 35
            if fight then
                act = have.shoot and "shoot" or have.attack and "attack"
                    or have.approach and "approach" or "flee"
            else
                act = have.hide and "hide" or "flee"
            end
        end
        g:encounter_action(act)
        if g.screen == "dead" then break end
    end
    if g.screen == "encounter" then g.enc = nil; g.screen = "map" end
    stats.enc_hp = stats.enc_hp + math.max(0, hp0 - g.player.health)
end

-- Sell what isn't needed (and artifacts beyond the bribe) for the permit.
-- What the bot could offer for the permit right now.
local function offer_value(g)
    local offer = 0
    for _, s in ipairs(g.player.inventory) do
        if not KEEP[s.item] then offer = offer + Game.item_value(s.item) * s.qty end
    end
    return offer
end
local function trader_has_permit(g)
    for _, s in ipairs(g.trader.stock) do if s.item == "permit" then return true end end
end

local function trade(g)
    g:open_trade()
    local u = g.trade_ui
    local permit_ask = math.ceil(Game.item_value("permit") * D.TRADE.people.town.markup)
    local offer, give = 0, {}
    for _, s in ipairs(g.player.inventory) do
        if not KEEP[s.item] then
            give[s.item] = s.qty
            offer = offer + Game.item_value(s.item) * s.qty
        end
    end
    local has_permit = false
    for _, s in ipairs(g.trader.stock) do has_permit = has_permit or s.item == "permit" end
    if has_permit and offer >= permit_ask and g:artifact_count() < D.GOAL.bribe + 2 then
        u.give, u.get = give, {permit = 1}
        g:make_deal()
    elseif count(g, "water_bottle") + count(g, "canned_beans") < 2 then
        -- buy food and water with junk
        local get = {}
        for _, it in ipairs({"water_bottle", "canned_beans"}) do get[it] = 1 end
        u.give, u.get = give, get
        if select(1, g:trade_totals()) >= select(2, g:trade_totals()) then g:make_deal() end
    end
    g.screen = "map"
end

-- Hexes where the bot felt sick (without a Geiger it can't see radiation;
-- like a player, it remembers where it felt bad and keeps away).
FELT = {}

local function play(seed)
    FELT = {}
    fake.time.uptime_ms = function() return seed end
    local g = Game.new()
    g:set_difficulty(LEVEL)
    g:start_game()
    local p = g.player
    local stats = {enc = {}, enc_hp = 0, artifacts = 0, max_rads = 0, traded = false,
                   studied = 0, known_at = {}}
    for _ = 1, 4000 do
        if g.screen == "dead" or g.screen == "ending" or p.hours > MAX_HOURS then break end
        if g.screen == "encounter" then encounter(g, stats)
        elseif g.screen == "puzzle" then g:puzzle_key(KEY.Q)
        else
            g.screen = "map"
            upkeep(g, stats)
            local here = key(p.q, p.r)
            local site = g:site_here()
            local can_exit = count(g, "permit") > 0 or g:artifact_count() >= D.GOAL.bribe
            if site == "checkpoint" and can_exit then
                g:open_gate(); g:gate_key(KEY.ENTER)
            else
                local permit_ask = math.ceil(Game.item_value("permit") * D.TRADE.people.town.markup)
                local can_buy = trader_has_permit(g) and offer_value(g) >= permit_ask
                if site == "trader" and (not stats.traded or can_buy) then
                    trade(g); stats.traded = true
                end
                -- a cairn and a toy in the bag: leave it (the Little Ones)
                if g:little_spot(here) == "cairn" and g:first_trinket() then g:offer_trinket() end
                local target
                local emit = g:emission_text()
                -- a storm: get under cover (any terrain that isn't open), then wait it out
                local storm = g:weather() == "Storm"
                local open = D.WORLD.storm.open
                if emit and not D.RAD.emission.shelter[g.tiles[here]] then
                    target = function(k) return g.tiles[k] == "ruins" end
                elseif storm and open[g.tiles[here]] then
                    target = function(k) return not open[g.tiles[k]] end
                elseif can_exit and g.sites_known.checkpoint then
                    target = function(k) return k == g.sites.checkpoint end
                elseif g.sites_known.trader and (not stats.traded or can_buy) and count(g, "permit") == 0 then
                    target = function(k) return k == g.sites.trader end
                elseif p.needs.thirst < 40 and count(g, "water_bottle") == 0 then
                    target = function(k)
                        if g.tiles[k] == "ford" then return true end
                        local q, r = parse(k)
                        for _, d in ipairs(D.AXIAL_DIRS) do
                            if g.tiles[key(q + d[1], r + d[2])] == "water" then return true end
                        end
                    end
                else
                    -- head for a far unexplored hex (like a person picking a
                    -- direction), picking up visible loot on the way
                    if not stats.goal or p.explored[stats.goal] then
                        local options = {}
                        for k, t in pairs(g.tiles) do
                            if not p.explored[k] and TERRAIN[t].passable then options[#options + 1] = k end
                        end
                        table.sort(options)
                        stats.goal = #options > 0 and options[g:rand(#options) + 1] or nil
                    end
                    target = function(k)
                        -- an artifact in a field is worth a dash in while your rads are low
                        -- once it knows the way out, it goes back for artifacts it has seen
                        local hunting = g.sites_known.checkpoint and g:artifact_count() < D.GOAL.bribe
                        local seen = p.visible[k] or (hunting and p.explored[k])
                        if not (k ~= here and seen and pile_worth(g, k)) then return k == stats.goal end
                        return (g.rad[k] or 0) < 3 or (p.rads or 0) < (hunting and 40 or 25)
                    end
                end
                if (emit and D.RAD.emission.shelter[g.tiles[here]]) or (storm and not open[g.tiles[here]]) then
                    local h = p.hours
                    g:rest()
                    if p.hours == h then wait_hour(g) end
                elseif p.mp <= 0 then
                    local h = p.hours
                    study(g, stats)
                    g:rest()
                    if p.hours == h then wait_hour(g) end
                elseif g:scavenge_left() > 0   -- finds land on the ground: a full bag doesn't stop you
                    and (g.tiles[here] == "ruins" or p.needs.hunger < 60) then
                    g:scavenge()
                else
                    local step = step_toward(g, target) or step_toward(g, target, true)
                    local h = p.hours
                    if step then
                        local q, r = parse(step)
                        g:try_move(q, r)
                    else
                        g:rest()
                    end
                    if p.hours == h and g.screen == "map" then wait_hour(g) end   -- wait
                end
            end
            local rads_before = p.rads or 0
            if g.screen ~= "dead" then g:tick() end
            for _, d in ipairs({3, 7, 14}) do
                if not stats.known_at[d] and p.hours >= d * 24 then
                    local n = 0
                    for _ in pairs(g.known) do n = n + 1 end
                    stats.known_at[d] = n
                end
            end
            if (p.rads or 0) > rads_before then FELT[key(p.q, p.r)] = true end
        end
        stats.max_rads = math.max(stats.max_rads, p.rads or 0)
    end
    stats.hours = p.hours
    if g.screen == "ending" then stats.result = "escaped (" .. g.ending.how .. ")"
    elseif g.screen == "dead" then stats.result = g.death_cause or "dead"
    else stats.result = "alive at the cap" end
    stats.found_trader = g.sites_known.trader
    return stats
end

-- run them
local results, hours, enc, enc_hp, arts, rads, traders = {}, {}, {}, 0, 0, 0, 0
local known_sum, known_n, studied = {}, {}, 0
for i = 0, RUNS - 1 do
    local s = play((FIRST + i * 7919) % 32768)
    results[s.result] = (results[s.result] or 0) + 1
    hours[#hours + 1] = s.hours
    for k, v in pairs(s.enc) do enc[k] = (enc[k] or 0) + v end
    enc_hp, arts, rads = enc_hp + s.enc_hp, arts + s.artifacts, rads + s.max_rads
    if s.found_trader then traders = traders + 1 end
    studied = studied + s.studied
    for d, n in pairs(s.known_at) do
        known_sum[d], known_n[d] = (known_sum[d] or 0) + n, (known_n[d] or 0) + 1
    end
end
table.sort(hours)
local function pct(n) return ("%5.1f%%"):format(100 * n / RUNS) end
print(("%d runs (seeds from %d), %s"):format(RUNS, FIRST, LEVEL))
print("how runs ended:")
local keys = {}
for k in pairs(results) do keys[#keys + 1] = k end
table.sort(keys, function(a, b) return results[a] > results[b] end)
for _, k in ipairs(keys) do print(("  %s  %s"):format(pct(results[k]), k)) end
print(("days survived: median %.1f, 25%% %.1f, 75%% %.1f"):format(
    hours[RUNS // 2 + 1] / 24, hours[RUNS // 4 + 1] / 24, hours[3 * RUNS // 4 + 1] / 24))
local total_enc = 0
for _, v in pairs(enc) do total_enc = total_enc + v end
print(("encounters per run %.1f (per day %.2f); HP lost to them per run %.0f"):format(
    total_enc / RUNS, total_enc / (RUNS * hours[RUNS // 2 + 1] / 24), enc_hp / RUNS))
for k, v in pairs(enc) do print(("  %-8s %.1f per run"):format(k, v / RUNS)) end
print(("artifacts picked up per run %.1f; peak rads per run %.0f; found the trader %s"):format(
    arts / RUNS, rads / RUNS, pct(traders)))
local function known(d) return known_n[d] and known_sum[d] / known_n[d] or 0 end
print(("recipes known (of the living): day 3 %.1f, day 7 %.1f, day 14 %.1f; study sessions per run %.1f"):format(
    known(3), known(7), known(14), studied / RUNS))
