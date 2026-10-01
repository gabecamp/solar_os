-- ---------------------------------------------------------------------
-- Traders and the way out
--
-- self.sites (from generate_world): trader = the town's center hex,
-- checkpoint = an edge hex far from it. You learn where they are from the
-- trader (who tells you about the Checkpoint), the wanderer, scrawled notes
-- or by walking there (sites_known, saved); the panel then points the way.
-- T on the trader's hex opens barter (self.trader, saved); T at the
-- Checkpoint opens the gate: a Zone Permit or GOAL.bribe artifacts get you
-- out of the Zone, which ends the run.
-- ---------------------------------------------------------------------

function Game:site_here()
    local here = hex_key(self.player.q, self.player.r)
    for name, key in pairs(self.sites) do
        if key == here then return name end
    end
end

-- Returns true the first time.
function Game:learn_site(name)
    if self.sites_known[name] then return false end
    self.sites_known[name] = true
    self.player.explored[self.sites[name]] = true
    return true
end

-- "NE 9": compass direction (up = north) and hexes from you to a site.
function Game:site_bearing(name)
    return self:bearing_to(self.sites[name])
end

function Game:bearing_to(key)
    local p = self.player
    local q, r = key:match("(-?%d+),(-?%d+)")
    q, r = tonumber(q), tonumber(r)
    local d = axial_distance(p.q, p.r, q, r)
    if d == 0 then return "here" end
    local x0, y0 = axial_to_pixel(p.q, p.r, 1)
    local x1, y1 = axial_to_pixel(q, r, 1)
    local octant = math.floor(math.atan(y0 - y1, x1 - x0) / (math.pi / 4) + 0.5) % 8
    return ({"E", "NE", "N", "NW", "W", "SW", "S", "SE"})[octant + 1] .. " " .. d
end

-- Map panel line: where to go next.
function Game:goal_text()
    if self.sites_known.checkpoint then return "Exit " .. self:site_bearing("checkpoint") end
    if self.sites_known.trader then return "Trader " .. self:site_bearing("trader") end
end

-- Someone (or something) tells you where the way out is.
function Game:hear_of_exit(who)
    if self:learn_site("checkpoint") then
        self:push_log(who .. ": a checkpoint out of the Zone, " .. self:site_bearing("checkpoint") .. ".")
        return true
    end
    return false
end

-- A site you can see is a site you know (called from Game:tick).
function Game:spot_sites()
    if self:learn_site_seen("trader") then
        self:push_log("A trader's stall in the ruins, " .. self:site_bearing("trader") .. ".")
    end
    if self:learn_site_seen("checkpoint") then
        self:push_log("A guard tower on the horizon: the Checkpoint.")
    end
end

function Game:learn_site_seen(name)
    return self.player.visible[self.sites[name]] and self:learn_site(name)
end

-- After a move: sites are safe (no encounters) and announce themselves.
function Game:arrive_site()
    local site = self:site_here()
    if site == "trader" then
        self:learn_site("trader")
        self:push_log("A trader's stall behind a barricade. T to trade.")
        self:hear_of_exit("Trader")
        return true
    elseif site == "checkpoint" then
        self:learn_site("checkpoint")
        self:push_log("The Checkpoint. Guards watch from the tower. T.")
        return true
    end
    return false
end

-- T on the map.
function Game:site_action()
    local site = self:site_here()
    if site == "trader" then
        self:open_trade()
    elseif site == "checkpoint" then
        self:open_gate()
    else
        self:push_log("Nobody here. (T trades at a trader)")
    end
end

-- -- barter -------------------------------------------------------------

function Game.item_value(item)
    return TRADE.value[item] or 1
end

function Game:open_trade()
    local t, p = self.trader, self.player
    while p.hours - t.restocked >= TRADE.restock_hours do
        t.restocked = t.restocked + TRADE.restock_hours
        for _ = 1, TRADE.restock_n do
            add_to_list(t.stock, {item = TRADE.restock[self:rand(#TRADE.restock) + 1], qty = 1})
        end
    end
    self.trade_ui = {col = "mine", cursor = {mine = 1, theirs = 1}, give = {}, get = {},
                     msg = "Pick what you give and take, then T."}
    self.screen = "trade"
end

-- The two columns: your bag and the trader's stock.
function Game:trade_rows(col)
    return col == "mine" and self.player.inventory or self.trader.stock
end

-- What you offer, and what the trader asks for what you picked.
function Game:trade_totals()
    local u = self.trade_ui
    local give, get = 0, 0
    for item, n in pairs(u.give) do give = give + Game.item_value(item) * n end
    for item, n in pairs(u.get) do get = get + Game.item_value(item) * n end
    return give, math.ceil(get * TRADE.markup)
end

-- Take n units of item out of a stack list.
local function take_units(list, item, n)
    for i, s in ipairs(list) do
        if s.item == item then
            s.qty = s.qty - n
            if s.qty <= 0 then table.remove(list, i) end
            return
        end
    end
end

function Game:make_deal()
    local u, t = self.trade_ui, self.trader
    local give, ask = self:trade_totals()
    if next(u.get) == nil then
        u.msg = "Pick something to take (Right, Enter)."
        return false
    end
    if give < ask then
        u.msg = ("Not enough. They want %d, you offer %d."):format(ask, give)
        return false
    end
    for item, n in pairs(u.give) do
        take_units(self.player.inventory, item, n)
        add_to_list(t.stock, {item = item, qty = n})
    end
    local dropped = false
    for item, n in pairs(u.get) do
        take_units(t.stock, item, n)
        if not self:put_stack("inventory", nil, {item = item, qty = n}) then
            self:put_stack("ground", nil, {item = item, qty = n})
            dropped = true
        end
    end
    u.give, u.get = {}, {}
    u.msg = dropped and "Deal. Your bag is full: some is on the ground." or "Deal."
    self:push_log("You traded with the trader.")
    for col, c in pairs(u.cursor) do
        u.cursor[col] = math.max(1, math.min(c, #self:trade_rows(col)))
    end
    return true
end

function Game:trade_key(key)
    local u = self.trade_ui
    local rows = self:trade_rows(u.col)
    local c = u.cursor[u.col]
    local pick = u.col == "mine" and u.give or u.get
    local row = rows[c]
    if key == KEY.Q or key == gfx.KEY_ESCAPE then
        self.trade_ui = nil
        self.screen = "map"
    elseif key == gfx.KEY_UP or key == KEY.W then
        u.cursor[u.col] = math.max(1, c - 1)
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        u.cursor[u.col] = math.max(1, math.min(#rows, c + 1))
    elseif key == gfx.KEY_LEFT or key == KEY.A then
        u.col = "mine"
    elseif key == gfx.KEY_RIGHT or key == KEY.D then
        u.col = "theirs"
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        if row and (pick[row.item] or 0) < row.qty then pick[row.item] = (pick[row.item] or 0) + 1 end
    elseif key == KEY.E then
        if row and pick[row.item] then
            pick[row.item] = pick[row.item] > 1 and pick[row.item] - 1 or nil
        end
    elseif key == KEY.T then
        self:make_deal()
    elseif key == KEY.O then   -- (W is "up" here)
        self:trader_work()
    end
end

-- -- the Checkpoint and the end ---------------------------------------------

-- Artifacts in your bag and hands.
function Game:artifact_count()
    local p, n = self.player, 0
    for _, s in ipairs(p.inventory) do
        if ITEM_DB[s.item].artifact then n = n + s.qty end
    end
    for _, slot in ipairs({"lhand", "rhand"}) do
        local item = p.equipped[slot]
        if item and ITEM_DB[item].artifact then n = n + 1 end
    end
    return n
end

function Game:open_gate()
    local opts = {}
    if self:count_item("permit") > 0 then opts[#opts + 1] = {"Show the Zone Permit", "permit"} end
    if self:artifact_count() >= GOAL.bribe then
        opts[#opts + 1] = {("Offer %d artifacts"):format(GOAL.bribe), "bribe"}
    end
    opts[#opts + 1] = {"Walk away", "leave"}
    self.gate_ui = {cursor = 1, opts = opts}
    self.screen = "gate"
end

function Game:pay_bribe()
    self:pay_artifacts(GOAL.bribe)
end

-- Hand over n artifacts: from the bag first, then your hands.
function Game:pay_artifacts(n)
    local p, left = self.player, n
    for i = #p.inventory, 1, -1 do
        local s = p.inventory[i]
        if left > 0 and ITEM_DB[s.item].artifact then
            local n = math.min(left, s.qty)
            left = left - n
            s.qty = s.qty - n
            if s.qty <= 0 then table.remove(p.inventory, i) end
        end
    end
    for _, slot in ipairs({"lhand", "rhand"}) do
        local item = p.equipped[slot]
        if left > 0 and item and ITEM_DB[item].artifact then
            p.equipped[slot] = nil
            left = left - 1
        end
    end
    recompute_stats(p)
end

function Game:gate_key(key)
    local u = self.gate_ui
    if key == KEY.Q or key == gfx.KEY_ESCAPE then
        self.screen = "map"
    elseif key == gfx.KEY_UP or key == KEY.W then
        u.cursor = math.max(1, u.cursor - 1)
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        u.cursor = math.min(#u.opts, u.cursor + 1)
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        local choice = u.opts[u.cursor][2]
        if choice == "leave" then
            self:push_log("You step back from the barrier.")
            self.screen = "map"
        else
            if choice == "bribe" then self:pay_bribe() end
            self:finish_run(choice)
        end
    end
end

-- Out of the Zone: the run is over (and so is its save).
function Game:finish_run(how)
    self.ending = {how = how, day = (self:clock()), hours = self.player.hours,
                   artifacts = self:artifact_count()}
    self.screen = "ending"
    self:sfx("escape")
    Game.delete_save()
end
