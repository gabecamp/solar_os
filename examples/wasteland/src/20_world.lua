-- ---------------------------------------------------------------------
-- Small deterministic RNG (avoids depending on math.randomseed behaving
-- a particular way on-device - same approach as the bundled Snake demo)
-- ---------------------------------------------------------------------

local function rand_next(seed)
    return (seed * 109 + 1021) % 32768
end

local function weighted_pick(seed, weights)
    seed = rand_next(seed)
    local total = 0
    for _, w in ipairs(weights) do total = total + w[2] end
    local roll = seed * total // 32768   -- high bits; the LCG's low bits cycle fast
    local acc = 0
    for _, w in ipairs(weights) do
        acc = acc + w[2]
        if roll < acc then return seed, w[1] end
    end
    return seed, weights[#weights][1]
end

-- ---------------------------------------------------------------------
-- Hex math (axial coordinates, pointy-top, flat 2D - no isometric squash)
-- ---------------------------------------------------------------------

local SQRT3 = math.sqrt(3)

local function axial_to_pixel(q, r, size)
    local x = size * (SQRT3 * q + SQRT3 / 2 * r)
    local y = size * (3 / 2 * r)
    return x, y
end

local function axial_round(qf, rf)
    local xf, zf = qf, rf
    local yf = -xf - zf
    local rx, ry, rz = math.floor(xf + 0.5), math.floor(yf + 0.5), math.floor(zf + 0.5)
    local dx, dy, dz = math.abs(rx - xf), math.abs(ry - yf), math.abs(rz - zf)
    if dx > dy and dx > dz then
        rx = -ry - rz
    elseif dy > dz then
        ry = -rx - rz
    else
        rz = -rx - ry
    end
    return rx, rz
end

local function pixel_to_axial(x, y, size)
    local qf = (SQRT3 / 3 * x - 1 / 3 * y) / size
    local rf = (2 / 3 * y) / size
    return axial_round(qf, rf)
end

local function axial_distance(aq, ar, bq, br)
    local ax, az = aq, ar
    local ay = -ax - az
    local bx, bz = bq, br
    local by = -bx - bz
    return math.max(math.abs(ax - bx), math.abs(ay - by), math.abs(az - bz))
end

local AXIAL_DIRS = {{1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1}}

local function hex_key(q, r) return q .. "," .. r end

local function neighbors(tiles, q, r)
    local result = {}
    for _, d in ipairs(AXIAL_DIRS) do
        local nq, nr = q + d[1], r + d[2]
        if tiles[hex_key(nq, nr)] then
            result[#result + 1] = {nq, nr}
        end
    end
    return result
end

-- ---------------------------------------------------------------------
-- World / player state
-- ---------------------------------------------------------------------

local function generate_world(seed)
    local tiles = {}
    for q = -GRID_RADIUS, GRID_RADIUS do
        for r = -GRID_RADIUS, GRID_RADIUS do
            if -GRID_RADIUS <= -q - r and -q - r <= GRID_RADIUS then
                local terrain
                seed, terrain = weighted_pick(seed, TERRAIN_WEIGHTS)
                tiles[hex_key(q, r)] = terrain
            end
        end
    end

    -- rivers: random walks from one edge toward the opposite one, each with
    -- two fords where it can be waded
    local R = GRID_RADIUS
    for _ = 1, WORLD.rivers do
        seed = rand_next(seed)
        local d = AXIAL_DIRS[seed % 6 + 1]
        local q, r = d[1] * R, d[2] * R
        local tq, tr = -q, -r
        local path = {}
        for _ = 1, 4 * R do
            if not tiles[hex_key(q, r)] then break end
            tiles[hex_key(q, r)] = "water"
            path[#path + 1] = {q, r}
            if q == tq and r == tr then break end
            -- step to a neighbor closer to the far edge, now and then sideways
            local best, options = axial_distance(q, r, tq, tr), {}
            for _, n in ipairs(AXIAL_DIRS) do
                local nq, nr = q + n[1], r + n[2]
                if tiles[hex_key(nq, nr)] and axial_distance(nq, nr, tq, tr) < best then
                    options[#options + 1] = {nq, nr}
                end
            end
            seed = rand_next(seed)
            if #options == 0 or seed % 7 == 0 then
                local n = AXIAL_DIRS[(seed // 7) % 6 + 1]
                if tiles[hex_key(q + n[1], r + n[2])] then options = {{q + n[1], r + n[2]}} end
            end
            if #options == 0 then break end
            local pick = options[(seed // 3) % #options + 1]
            q, r = pick[1], pick[2]
        end
        for _, f in ipairs({1 / 3, 2 / 3}) do
            local at = path[math.max(1, math.floor(#path * f))]
            if at then tiles[hex_key(at[1], at[2])] = "ford" end
        end
    end

    -- ruins: a town (a tight cluster) somewhere 5-9 hexes out, and wrecks
    local keys = {}
    for key in pairs(tiles) do keys[#keys + 1] = key end
    table.sort(keys)
    local function parse(key)
        local q, r = key:match("(-?%d+),(-?%d+)")
        return tonumber(q), tonumber(r)
    end
    local town
    for _ = 1, 200 do
        seed = rand_next(seed)
        local q, r = parse(keys[seed % #keys + 1])
        local dist = axial_distance(0, 0, q, r)
        if dist >= 5 and dist <= 9 then town = {q, r}; break end
    end
    if town then
        local placed = 0
        for ring = 0, 2 do
            for _, key in ipairs(keys) do
                local q, r = parse(key)
                if placed < WORLD.town_ruins and axial_distance(q, r, town[1], town[2]) == ring then
                    seed = rand_next(seed)
                    if ring < 2 or seed % 3 == 0 then
                        tiles[key] = "ruins"
                        placed = placed + 1
                    end
                end
            end
        end
    end
    for _ = 1, WORLD.lone_ruins do
        seed = rand_next(seed)
        local key = keys[seed % #keys + 1]
        local q, r = parse(key)
        if tiles[key] ~= "water" and axial_distance(0, 0, q, r) >= 3 then tiles[key] = "ruins" end
    end
    tiles[hex_key(0, 0)] = "plains"

    -- sites: the trader on the town's center, and the Checkpoint on the map's
    -- edge, at the edge hex farthest from the trader (the long way round)
    local sites = {}
    local trader = town and hex_key(town[1], town[2])
    for _, key in ipairs(keys) do
        if trader then break end
        if tiles[key] == "ruins" then trader = key end
    end
    trader = trader or hex_key(3, 0)
    tiles[trader] = "ruins"
    sites.trader = trader
    local tq, tr = parse(trader)
    local exit, exit_d
    for _, key in ipairs(keys) do
        local q, r = parse(key)
        if axial_distance(0, 0, q, r) == GRID_RADIUS and tiles[key] ~= "water" then
            local d = axial_distance(q, r, tq, tr)
            if not exit or d > exit_d then exit, exit_d = key, d end
        end
    end
    exit = exit or hex_key(GRID_RADIUS, 0)
    if tiles[exit] == "water" then tiles[exit] = "plains" end
    sites.checkpoint = exit

    -- every walkable hex must be reachable from the start: where water cuts
    -- some off, wade a line of fords from them back toward the start
    local function reachable()
        local seen, queue = {[hex_key(0, 0)] = true}, {{0, 0}}
        local i = 1
        while queue[i] do
            local cur = queue[i]; i = i + 1
            for _, n in ipairs(AXIAL_DIRS) do
                local nq, nr = cur[1] + n[1], cur[2] + n[2]
                local k = hex_key(nq, nr)
                if tiles[k] and not seen[k] and TERRAIN[tiles[k]].passable then
                    seen[k] = true
                    queue[#queue + 1] = {nq, nr}
                end
            end
        end
        return seen
    end
    for _ = 1, 50 do
        local seen, cut_off = reachable(), nil
        for _, key in ipairs(keys) do
            if TERRAIN[tiles[key]].passable and not seen[key] then cut_off = key; break end
        end
        if not cut_off then break end
        local q, r = parse(cut_off)
        local n = axial_distance(q, r, 0, 0)
        for step = 1, n do
            local lq, lr = axial_round(q + (0 - q) * step / n, r + (0 - r) * step / n)
            if tiles[hex_key(lq, lr)] == "water" then tiles[hex_key(lq, lr)] = "ford" end
        end
    end

    local ground = {}
    ground[hex_key(0, 0)] = {
        {item = "rock", qty = 1},
        {item = "cloth_scrap", qty = 2},
        {item = "canned_beans", qty = 1},
        {item = "water_bottle", qty = 2},
    }

    -- Scatter loot on other passable tiles: every wearable once, plus a few
    -- food/water caches. Keys are sorted so a seed always gives the same map.
    local spots = {}
    for key, terrain in pairs(tiles) do
        if TERRAIN[terrain].passable and key ~= hex_key(0, 0) then
            spots[#spots + 1] = key
        end
    end
    table.sort(spots)
    local function drop(item, qty)
        seed = rand_next(seed)
        local key = spots[seed % #spots + 1]
        ground[key] = ground[key] or {}
        for _, s in ipairs(ground[key]) do
            if s.item == item then s.qty = s.qty + qty; return end
        end
        table.insert(ground[key], {item = item, qty = qty})
    end
    for _, item in ipairs(WORLD_WEARABLES) do drop(item, 1) end
    for _ = 1, 2 do   -- food/water caches (loot is meant to be scarce)
        for _, item in ipairs({"canned_beans", "canned_beans", "water_bottle",
                               "water_bottle", "water_bottle", "cloth_scrap"}) do
            drop(item, 1)
        end
    end
    for _, item in ipairs(RAD.world_items) do drop(item, 1) end
    for _, item in ipairs(TECH.world_items) do drop(item, 1) end

    -- anomaly fields: hot spots of radiation, an artifact at each center.
    -- rad[key] = level 1-3 (see RAD); not saved, rebuilt from the seed.
    local rad = {}
    local fields = 0
    for _ = 1, 300 do
        if fields >= RAD.fields then break end
        seed = rand_next(seed)
        local center = spots[seed % #spots + 1]
        local cq, cr = parse(center)
        local clear = axial_distance(0, 0, cq, cr) >= RAD.min_dist and not rad[center]
        for _, site in pairs(sites) do
            local sq, sr = parse(site)
            if axial_distance(cq, cr, sq, sr) < RAD.min_dist then clear = false end
        end
        if clear then
            seed = rand_next(seed)
            local radius = 1 + seed % 2
            for _, key in ipairs(keys) do
                local q, r = parse(key)
                local d = axial_distance(q, r, cq, cr)
                if d <= radius then rad[key] = math.max(rad[key] or 0, 3 - d) end
            end
            seed = rand_next(seed)
            ground[center] = ground[center] or {}
            table.insert(ground[center], {item = ARTIFACTS[seed % #ARTIFACTS + 1], qty = 1})
            fields = fields + 1
        end
    end
    return tiles, ground, seed, rad, sites
end

-- ---------------------------------------------------------------------
-- Character: attributes (NEO Scavenger-style point buy) and traits (Project
-- Zomboid-style budget: positive traits cost points, negative ones give them
-- back, and you can only start with the balance at 0 or above). Only traits
-- that actually change something are offered.
-- ---------------------------------------------------------------------

local ATTRIBUTES = {"Strength", "Speed", "Perception", "Endurance"}
local ATTR_MIN, ATTR_MAX, ATTR_DEFAULT, ATTR_POINTS = 1, 6, 3, 12
local ATTR_DESC = {
    Strength   = "Strength: +1 bag cell per point over 3",
    Speed      = "Speed: +1 MP per 2 points over 3",
    Perception = "Perception: sight, finds, fewer duds",
    Endurance  = "Endurance: 10% slower tiring per point",
}

-- cost > 0 spends trait points, cost < 0 gives them. fx keys: mp, sight,
-- scav (finds per search), bag (cells), hunger / rest_gain (multipliers)
local TRAITS = {
    {name = "Quick",        cost = 3,  desc = "+1 movement point",        fx = {mp = 1}},
    {name = "Hawk-Eyed",    cost = 3,  desc = "+1 sight",                 fx = {sight = 1}},
    {name = "Scrounger",    cost = 2,  desc = "+1 find per search",       fx = {scav = 1}},
    {name = "Light Eater",  cost = 2,  desc = "Hunger drains 25% slower", fx = {hunger = 0.75}},
    {name = "Pack Mule",    cost = 2,  desc = "+2 bag cells",             fx = {bag = 2}},
    {name = "Asthmatic",    cost = -3, desc = "-1 movement point",        fx = {mp = -1}},
    {name = "Near-Sighted", cost = -3, desc = "-1 sight",                 fx = {sight = -1}},
    {name = "Careless",     cost = -2, desc = "-1 find per search",       fx = {scav = -1}},
    {name = "Big Eater",    cost = -2, desc = "Hunger drains 25% faster", fx = {hunger = 1.25}},
    {name = "Insomniac",    cost = -2, desc = "Resting restores 25% less", fx = {rest_gain = 0.75}},
}

local function default_attrs()
    local a = {}
    for _, name in ipairs(ATTRIBUTES) do a[name] = ATTR_DEFAULT end
    return a
end

local function attr_points_left(attrs)
    local used = 0
    for _, name in ipairs(ATTRIBUTES) do used = used + attrs[name] end
    return ATTR_POINTS - used
end

-- trait points left: everyone gets TRAIT_START_POINTS, negatives add more,
-- positives spend; must be >= 0 to start
local TRAIT_START_POINTS = 5
local function trait_points_left(traits)
    local left = TRAIT_START_POINTS
    for _, t in ipairs(TRAITS) do
        if traits[t.name] then left = left - t.cost end
    end
    return left
end

-- Derived stats from attributes + traits, stored on the player.
local FX_MULT = {hunger = true, rest_gain = true, thirst = true, rest_drain = true,
                 encounter = true}
local function recompute_stats(player)
    local a = player.attrs
    local fx = {mp = 0, sight = 0, scav = 0, bag = 0, heal = 0, scav_hurt = 0,
                hunger = 1, rest_gain = 1, thirst = 1, rest_drain = 1, encounter = 1}
    local function add(effects)
        for k, v in pairs(effects) do
            if FX_MULT[k] then fx[k] = fx[k] * v else fx[k] = fx[k] + v end
        end
    end
    for _, t in ipairs(TRAITS) do
        if player.traits[t.name] then add(t.fx) end
    end
    -- artifacts work while held
    for _, slot in ipairs({"lhand", "rhand"}) do
        local item = player.equipped[slot]
        if item and ITEM_DB[item].artifact then add(ITEM_DB[item].artifact) end
    end
    player.max_mp = math.max(1, BASE_MAX_MP + (a.Speed - 3) // 2 + fx.mp)
    player.sight = math.max(1, BASE_SIGHT + (a.Perception - 3) // 2 + fx.sight)
    player.scav_rolls = math.max(1, SCAVENGE_ROLLS + (a.Perception - 3) // 2 + fx.scav)
    player.bag_bonus = (a.Strength - 3) + fx.bag
    player.hunger_mult = fx.hunger * (player.diff_drain or 1)
    player.rest_gain_mult = fx.rest_gain
    player.rest_drain_mult = (1 - 0.1 * (a.Endurance - 3)) * fx.rest_drain
    player.thirst_mult = fx.thirst * (player.diff_drain or 1)
    player.heal_per_hour = fx.heal
    player.encounter_mult = fx.encounter
    player.scav_hurt = fx.scav_hurt
    if player.mp and player.mp > player.max_mp then player.mp = player.max_mp end
end

-- Perception scales how often a search roll comes up empty: 100% at 3,
-- 25% at 6, 150% at 1.
local function dud_percent(perception)
    return 100 * (7 - perception) // 4
end

local function new_player()
    return {
        q = 0, r = 0,
        max_mp = BASE_MAX_MP,
        mp = BASE_MAX_MP,
        sight = BASE_SIGHT,
        hours = 0,
        needs = {hunger = 100, thirst = 100, rest = 100},
        health = MAX_HEALTH,
        injuries = {bleeding = false, wounded_hours = 0},
        equipped = {shirt = "tshirt", pants = "jeans", feet = "boots", back = "backpack"},
        inventory = {
            {item = "water_bottle", qty = 1},
            {item = "canned_beans", qty = 1},
        },
        explored = {},
        visible = {},
        attrs = default_attrs(),
        traits = {},
    }
end

-- Only the hexes within sight are visited (the world has hundreds).
-- view_sight is sight after night/light (Game:refresh_view); sight otherwise.
local function update_visibility(player, tiles)
    player.visible = {}
    local s = player.view_sight or player.sight
    for dq = -s, s do
        for dr = math.max(-s, -dq - s), math.min(s, -dq + s) do
            local key = hex_key(player.q + dq, player.r + dr)
            if tiles[key] then
                player.visible[key] = true
                player.explored[key] = true
            end
        end
    end
end

local function clamp(v) return math.max(0, math.min(100, v)) end

-- Split text into lines of at most cols characters, breaking at spaces.
local function wrap(text, cols)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= cols then
            line = line .. " " .. word
        else
            lines[#lines + 1] = line
            line = word
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function apply_awake_hours(player, hours)
    player.needs.hunger = clamp(player.needs.hunger - hours * (100 / 72) * player.hunger_mult)
    player.needs.thirst = clamp(player.needs.thirst - hours * (100 / 48) * player.thirst_mult)
    player.needs.rest = clamp(player.needs.rest - hours * (100 / 18) * player.rest_drain_mult)
    player.health = clamp(player.health + hours * player.heal_per_hour)
    if player.injuries.bleeding then
        player.health = clamp(player.health - hours * BLEED_PER_HOUR)
    end
end

local function apply_rest_hours(player, hours)
    player.needs.hunger = clamp(player.needs.hunger - hours * (100 / 72) * 0.5 * player.hunger_mult)
    player.needs.thirst = clamp(player.needs.thirst - hours * (100 / 48) * 0.5 * player.thirst_mult)
    player.needs.rest = clamp(player.needs.rest + hours * (100 / 6) * player.rest_gain_mult)
    local inj = player.injuries
    if inj.bleeding then
        player.health = clamp(player.health - hours * BLEED_PER_HOUR)
    elseif player.needs.hunger <= 0 or player.needs.thirst <= 0 then
        -- a starving or parched body doesn't mend
        inj.wounded_hours = math.max(0, inj.wounded_hours - hours)
    else
        local heal = REST_HEAL_PER_HOUR * (1 + 0.1 * (player.attrs.Endurance - 3))
        player.health = clamp(player.health + hours * heal)
        inj.wounded_hours = math.max(0, inj.wounded_hours - hours)
    end
end

local function effective_max_mp(player)
    local penalty = 0
    if player.needs.hunger <= 0 then penalty = penalty + 1 end
    if player.needs.thirst <= 0 then penalty = penalty + 1 end
    if player.needs.rest <= 0 then penalty = penalty + 1 end
    if player.injuries.wounded_hours > 0 then penalty = penalty + 1 end
    return math.max(1, player.max_mp - penalty)
end

