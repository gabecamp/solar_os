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
    tiles[hex_key(0, 0)] = "plains"

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
    for _, item in ipairs({"canned_beans", "canned_beans", "water_bottle",
                           "water_bottle", "water_bottle", "cloth_scrap"}) do
        drop(item, 1)
    end
    return tiles, ground, seed
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
    player.hunger_mult = fx.hunger
    player.rest_gain_mult = fx.rest_gain
    player.rest_drain_mult = (1 - 0.1 * (a.Endurance - 3)) * fx.rest_drain
    player.thirst_mult = fx.thirst
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

local function update_visibility(player, tiles)
    player.visible = {}
    for key in pairs(tiles) do
        local q, r = key:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        if axial_distance(player.q, player.r, q, r) <= player.sight then
            player.visible[key] = true
            player.explored[key] = true
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

