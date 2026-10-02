-- ---------------------------------------------------------------------
-- More people to trade with: the Ferry Post and the Peddler
--
-- Game.place_extras(tiles, sites, rad, world_seed) adds the newer world
-- features AFTER generate_world, from a seed stream of their own, so a
-- world made before them (an old save) keeps every tile and site it had:
--   the Ferry Post (sites.ferry): a few ruins by the water, far from the
--     town; Mother Okun trades there (self.ferry_trader, saved).
--   the old starting clothes (extras.drops): lying a few hexes from the
--     start, since you start with nothing.
--   the Peddler's round (extras.route): TRADE.route_n stops around the map;
--     he stays TRADE.stay hours at each, so where he is comes from the
--     clock (nothing to save but his stock, self.peddler).
-- Later features add their own pieces to `extras` the same way.
-- ---------------------------------------------------------------------

local function parse_key(key)
    local q, r = key:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end

function Game.place_extras(tiles, sites, rad, world_seed)
    local seed = (world_seed * 48271 + 12345) % 2147483647
    local function roll(n)
        seed = rand_next(seed)
        return seed % n
    end
    local keys = {}
    for key in pairs(tiles) do keys[#keys + 1] = key end
    table.sort(keys)
    local taken = {}
    for _, key in pairs(sites) do taken[key] = true end
    taken[hex_key(0, 0)] = true
    local extras = {}

    -- the Ferry Post: a dry, cool hex next to the water, far from the town
    local tq, tr = parse_key(sites.trader)
    local F = TRADE.ferry
    local function by_water(q, r)
        for _, d in ipairs(AXIAL_DIRS) do
            if tiles[hex_key(q + d[1], r + d[2])] == "water" then return true end
        end
        return false
    end
    for _, min_town in ipairs({F.min_from_town, F.min_from_town - 3}) do
        local options = {}
        for _, key in ipairs(keys) do
            local q, r = parse_key(key)
            if tiles[key] ~= "water" and not taken[key] and not rad[key]
                and axial_distance(q, r, tq, tr) >= min_town
                and axial_distance(0, 0, q, r) >= F.min_from_start and by_water(q, r) then
                options[#options + 1] = key
            end
        end
        if #options > 0 then
            local key = options[roll(#options) + 1]
            sites.ferry, taken[key] = key, true
            tiles[key] = "ruins"
            local q, r = parse_key(key)
            local placed = 0
            for _, d in ipairs(AXIAL_DIRS) do
                local nk = hex_key(q + d[1], r + d[2])
                if placed < F.ruins and tiles[nk] and tiles[nk] ~= "water" and not taken[nk] then
                    tiles[nk] = "ruins"
                    placed = placed + 1
                end
            end
            break
        end
    end

    -- the Peddler's round: one stop per slice of the compass, in order
    local route = {}
    for i = 0, TRADE.route_n - 1 do
        local options = {}
        for _, key in ipairs(keys) do
            local q, r = parse_key(key)
            local d = axial_distance(0, 0, q, r)
            if TERRAIN[tiles[key]].passable and not taken[key] and d >= 3 and d < GRID_RADIUS then
                local x, y = axial_to_pixel(q, r, 1)
                local slice = math.floor((math.atan(y, x) + math.pi) / (2 * math.pi) * TRADE.route_n)
                if slice % TRADE.route_n == i then options[#options + 1] = key end
            end
        end
        if #options > 0 then route[#route + 1] = options[roll(#options) + 1] end
    end
    extras.route = route

    -- the Little Ones: warrens in the woods and hills, cairns near them
    local warrens, cairns = {}, {}
    local spots = {}
    for _, key in ipairs(keys) do
        local q, r = parse_key(key)
        if (tiles[key] == "forest" or tiles[key] == "hills") and not taken[key]
            and axial_distance(0, 0, q, r) >= LITTLE.min_from_start then
            spots[#spots + 1] = key
        end
    end
    for _ = 1, 60 do
        if #warrens >= LITTLE.warrens or #spots == 0 then break end
        local key = spots[roll(#spots) + 1]
        local ok = not taken[key]
        local kq, kr = parse_key(key)
        for _, w in ipairs(warrens) do
            local wq, wr = parse_key(w)
            if axial_distance(wq, wr, kq, kr) < 5 then ok = false end   -- spread them out
        end
        if ok then warrens[#warrens + 1], taken[key] = key, true end
    end
    for i = 1, (#warrens > 0 and LITTLE.cairns or 0) do
        local wq, wr = parse_key(warrens[(i - 1) % #warrens + 1])
        local options = {}
        for _, key in ipairs(keys) do
            local q, r = parse_key(key)
            local d = axial_distance(q, r, wq, wr)
            if TERRAIN[tiles[key]].passable and not taken[key] and d >= LITTLE.cairn_near and d <= LITTLE.cairn_far then
                options[#options + 1] = key
            end
        end
        if #options > 0 then
            local key = options[roll(#options) + 1]
            cairns[#cairns + 1], taken[key] = key, true
        end
    end
    extras.warrens, extras.cairns = warrens, cairns

    -- the old quarry and the Institute's gate (the storyline): hills, far
    -- from both towns
    local towns = {sites.trader, sites.ferry}
    for _, min_d in ipairs({QUESTS.story.min_from_towns, 5}) do
        local options = {}
        for _, key in ipairs(keys) do
            local q, r = parse_key(key)
            local far = axial_distance(0, 0, q, r) >= 5
            for _, t in pairs(towns) do
                local a, b = parse_key(t)
                if axial_distance(q, r, a, b) < min_d then far = false end
            end
            if tiles[key] == "hills" and not taken[key] and not rad[key] and far then
                options[#options + 1] = key
            end
        end
        if #options > 0 then
            local key = options[roll(#options) + 1]
            sites.quarry, taken[key] = key, true
            break
        end
    end

    -- the clothes you used to start in, left lying around instead (a new
    -- game puts them on the ground: Game.new)
    local drops, options = {}, {}
    for _, key in ipairs(keys) do
        local q, r = parse_key(key)
        local d = axial_distance(0, 0, q, r)
        if TERRAIN[tiles[key]].passable and not taken[key] and d >= 2 and d <= 6 then
            options[#options + 1] = key
        end
    end
    for _, item in ipairs(START_FINDS) do
        if #options == 0 then break end
        local key = table.remove(options, roll(#options) + 1)
        drops[#drops + 1], taken[key] = {key = key, item = item}, true
    end
    extras.drops = drops
    return extras
end

-- -- the Peddler -----------------------------------------------------------

-- Where he is now (or at `hours`): a stop on his round.
function Game:peddler_key(hours)
    local route = self.extras and self.extras.route or {}
    if #route == 0 then return nil end
    return route[((hours or self.player.hours) // TRADE.stay) % #route + 1]
end

-- Seeing him puts him in the journal (called from spot_sites).
function Game:spot_peddler()
    local key = self:peddler_key()
    if key and self.player.visible[key] then
        local pd = self.peddler
        if pd.seen_key ~= key then
            self:push_log("A man pushing a rattling handcart: the Peddler, " .. self:bearing_to(key) .. ".")
        end
        pd.seen_key, pd.seen_hour = key, self.player.hours
    end
end

-- -- everyone's stock ------------------------------------------------------

-- A trader's stock and restock clock: "town", "ferry" or "peddler".
function Game:trade_state(who)
    if who == "ferry" then return self.ferry_trader end
    if who == "peddler" then return self.peddler end
    return self.trader
end

-- Fill up what sold since the last visit.
function Game:restock(who)
    local t, p = self:trade_state(who), self.player
    local cfg = TRADE.people[who] or {}
    local hours = cfg.restock_hours or TRADE.restock_hours
    local list, n = cfg.restock or TRADE.restock, cfg.restock_n or TRADE.restock_n
    while p.hours - t.restocked >= hours do
        t.restocked = t.restocked + hours
        for _ = 1, n do
            add_to_list(t.stock, {item = list[self:rand(#list) + 1], qty = 1})
        end
    end
end

-- A fresh stock list from TRADE.people[who].stock.
function Game.starting_stock(who)
    local out = {}
    for _, st in ipairs(TRADE.people[who].stock) do out[#out + 1] = {item = st[1], qty = st[2]} end
    return {stock = out, restocked = 0}
end

-- Mother Okun's job (O on her screen): three fish, any kind.
function Game:ferry_work()
    local u, q = self.trade_ui, self.quest
    local fish = self:count_item("raw_fish") + self:count_item("cooked_fish")
    if q and q.kind == "fish" then
        if fish < QUESTS.fish.need then
            u.msg = ("'Three fish. You've got %d.'"):format(fish)
            return
        end
        local left = QUESTS.fish.need
        for _, item in ipairs({"raw_fish", "cooked_fish"}) do
            local n = math.min(left, self:count_item(item))
            if n > 0 then self:take_items(item, n); left = left - n end
        end
        self:give_reward(QUESTS.fish.reward, "Mother Okun weighs them in her hands:")
        u.msg = "'They'll row tomorrow. Here.'"
        return
    end
    if q then
        u.msg = "'You've work already. Finish it.'"
        return
    end
    self.quest = {kind = "fish", giver = "Mother Okun"}
    u.msg = QUESTS.fish.offer
    self:push_log("Quest: " .. self:quest_text())
end
