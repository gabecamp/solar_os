-- ---------------------------------------------------------------------
-- Traders and the way out
--
-- self.sites (from generate_world): trader = the town's center hex,
-- checkpoint = an edge hex far from it. You learn where they are from the
-- trader (who tells you about the Checkpoint), the wanderer, scrawled notes
-- or by walking there (sites_known, saved); the panel then points the way.
-- T on the trader's hex opens barter (self.trader, saved); T at the
-- Checkpoint opens the gate: a Churn Permit or GOAL.bribe artifacts get you
-- out of the Churn, which ends the run.
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
    local q, r = Game.key_qr(key)
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
        self:push_log(who .. ": a checkpoint out of the Churn, " .. self:site_bearing("checkpoint") .. ".")
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
    if self.sites.quarry and self:learn_site_seen("quarry") then
        self:push_log("A gate in the wall of the old quarry, " .. self:site_bearing("quarry") .. ".")
    end
    if self.sites.ferry and self:learn_site_seen("ferry") then
        self:push_log("A jetty and a few huts by the water: the Ferry Post, " .. self:site_bearing("ferry") .. ".")
    end
    self:spot_peddler()
    self:spot_little()
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
    elseif site == "quarry" then
        return self:quarry_arrive()
    elseif site == "ferry" then
        self:learn_site("ferry")
        self:push_log("The Ferry Post. Mother Okun trades from the jetty. T.")
        self:hear_of_exit("Mother Okun")
        return true
    end
    return false
end

-- T on the map.
function Game:site_action()
    local site = self:site_here()
    if site == "trader" then
        self:open_trade("town")
    elseif site == "ferry" then
        self:open_trade("ferry")
    elseif site == "quarry" then
        self:open_institute()
    elseif site == "checkpoint" then
        self:open_gate()
    elseif self:peddler_key() == hex_key(self.player.q, self.player.r) then
        self:open_trade("peddler")
    elseif self:little_spot(hex_key(self.player.q, self.player.r)) == "cairn" then
        self:offer_trinket()
    else
        self:push_log("Nobody here. (T trades at a trader)")
    end
end

-- -- barter -------------------------------------------------------------

function Game.item_value(item)
    if ITEM_DB[item] and ITEM_DB[item].trinket then return 0 end   -- toys: no use to grown-ups
    return TRADE.value[item] or 1
end

-- who: "town" (the trader), "ferry" (Mother Okun) or "peddler"
function Game:open_trade(who)
    who = who or "town"
    self:restock(who)
    self.trade_ui = {who = who, col = "mine", cursor = {mine = 1, theirs = 1}, give = {}, get = {},
                     msg = TRADE.people[who].hello or "Pick what you give and take, then T."}
    self.screen = "trade"
end

-- The one you're trading with now: their stock and their markup.
function Game:trade_partner()
    local who = self.trade_ui and self.trade_ui.who or "town"
    return self:trade_state(who), TRADE.people[who]
end

-- The two columns: your bag and the trader's stock.
function Game:trade_rows(col)
    return col == "mine" and self.player.inventory or self:trade_partner().stock
end

-- What you offer, and what the trader asks for what you picked.
-- The stacks of `item` in a list, most worn first (worn clothes are traded
-- away before good ones).
function Game.stacks_of(list, item)
    local out = {}
    for _, s in ipairs(list) do if s.item == item then out[#out + 1] = s end end
    table.sort(out, function(a, b) return (a.cond or 100) < (b.cond or 100) end)
    return out
end

-- What n units of item from a list are worth: worn clothes for less (a
-- torn piece a quarter).
function Game.units_value(list, item, n)
    local total = 0
    for _, s in ipairs(Game.stacks_of(list, item)) do
        local k = math.min(n, s.qty)
        total = total + k * math.floor(Game.item_value(item) * (25 + 0.75 * (s.cond or 100)) / 100)
        n = n - k
        if n <= 0 then break end
    end
    return total
end

function Game:trade_totals()
    local u = self.trade_ui
    local give, get = 0, 0
    for item, n in pairs(u.give) do give = give + Game.units_value(self.player.inventory, item, n) end
    -- (what you take costs at least 1 a unit: trinkets are worthless to sell)
    for item, n in pairs(u.get) do get = get + math.max(1, Game.item_value(item)) * n end
    local _, cfg = self:trade_partner()
    return give, math.ceil(get * self:markup_for(u.who or "town", cfg.markup))
end

-- Take n units of item out of a stack list (across stacks, most worn first).
local function take_units(list, item, n)
    for _, s in ipairs(Game.stacks_of(list, item)) do
        local k = math.min(n, s.qty)
        s.qty, n = s.qty - k, n - k
        if n <= 0 then break end
    end
    for i = #list, 1, -1 do
        if list[i].qty <= 0 then table.remove(list, i) end
    end
end

function Game:make_deal()
    local u, t = self.trade_ui, self:trade_partner()
    local give, ask = self:trade_totals()
    if next(u.get) == nil and next(u.give) == nil then
        u.msg = "Pick what to sell or take (Enter)."
        return false
    end
    if give < ask then   -- rubles in the bag make up the rest
        local spare = 0
        for _, s in ipairs(self.player.inventory) do
            if s.item == "rubles" then spare = spare + s.qty end
        end
        spare = spare - (u.give.rubles or 0)
        if spare < ask - give then
            u.msg = ("Not enough. They want %d, you have %d."):format(ask, give + spare)
            return false
        end
        u.give.rubles = (u.give.rubles or 0) + ask - give
        give = ask
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
    -- what they owe you back, in rubles
    local change = give - ask
    if change > 0 and not self:put_stack("inventory", nil, {item = "rubles", qty = change}) then
        self:put_stack("ground", nil, {item = "rubles", qty = change})
        dropped = true
    end
    u.give, u.get = {}, {}
    u.msg = (change > 0 and ("Deal. " .. change .. " rubles back.") or "Deal.")
        .. (dropped and " Bag full: some is on the ground." or "")
    self:push_log("You traded with " .. (u.who == "town" and "the trader" or TRADE.people[u.who].name) .. ".")
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
        local have = 0   -- (worn and new pieces of one item are separate rows)
        for _, s in ipairs(row and rows or {}) do if s.item == row.item then have = have + s.qty end end
        -- (money goes ten at a time)
        local step = row and row.item == "rubles" and 10 or 1
        if row and (pick[row.item] or 0) < have then pick[row.item] = math.min(have, (pick[row.item] or 0) + step) end
    elseif key == KEY.E then
        if row and pick[row.item] then
            pick[row.item] = pick[row.item] > 1 and pick[row.item] - 1 or nil
        end
    elseif key == KEY.T then
        self:make_deal()
    elseif key == KEY.O then   -- (W is "up" here)
        if u.who == "ferry" then self:ferry_work()
        elseif u.who == "town" then self:trader_work()
        elseif u.who == "peddler" then self:peddler_swap()
        else u.msg = "'Work? I'm a peddler. I peddle.'" end
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
    if self:count_item("permit") > 0 then opts[#opts + 1] = {"Show the Churn Permit", "permit"} end
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

-- Out of the Churn: the run is over (and so is its save).
function Game:finish_run(how)
    self.ending = {how = how, day = (self:clock()), hours = self.player.hours,
                   artifacts = self:artifact_count(),
                   lore = how ~= "quiet" and self:lore_ending_line() or nil}   -- (the Quiet says it all)
    self.screen = "ending"
    self:sfx("escape")
    self:record_run(how)
    Game.delete_save()
end
