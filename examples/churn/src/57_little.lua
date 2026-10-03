-- ---------------------------------------------------------------------
-- The Little Ones (numbers in LITTLE, 05_data_world)
--
-- The Churn's children, grown small and grey and grinning. They live in
-- warrens in the woods and hills and are never hostile, only mischievous.
-- Trinkets (toys, crayons, buttons: worth nothing to anyone else) left at
-- their cairns befriend them; with enough gifts a troupe follows you from
-- a warren. self.little = {friend, n, mood, mood_hour, hidden, seen}
-- (saved). Warrens and cairns come from Game.place_extras (extras.warrens,
-- extras.cairns).
-- ---------------------------------------------------------------------

LITTLE.def = {kind = "little", name = "The Little Ones", art = "little",
              who = "little ones", intro = LITTLE.intro, start = "near", speed = 6}

function Game.new_little()
    return {friend = 0, n = 0, mood = 0, mood_hour = 0, seen = {}}
end

-- "warren", "cairn" or nil for a hex.
function Game:little_spot(key)
    local x = self.extras or {}
    for _, k in ipairs(x.warrens or {}) do if k == key then return "warren" end end
    for _, k in ipairs(x.cairns or {}) do if k == key then return "cairn" end end
    return nil
end

function Game:first_trinket()
    for _, s in ipairs(self.player.inventory) do
        if ITEM_DB[s.item].trinket then return s.item end
    end
    return nil
end

-- How many follow for this many gifts (0 before join_at).
function Game.troupe_size(friend)
    if friend < LITTLE.join_at then return 0 end
    return math.min(LITTLE.max, 1 + (friend - LITTLE.join_at) // LITTLE.per_extra)
end

-- One unit out of your bag (not the ground or your hands, unlike take_items).
function Game:take_from_bag(item)
    local inv = self.player.inventory
    for i, s in ipairs(inv) do
        if s.item == item then
            s.qty = s.qty - 1
            if s.qty <= 0 then table.remove(inv, i) end
            return true
        end
    end
    return false
end

-- A trinket given (at a cairn, or to them at a warren).
function Game:gift_little(item, points)
    local l = self.little
    self:take_from_bag(item)
    l.friend = l.friend + (points or 1)
    if l.n > 0 then
        l.mood = math.min(LITTLE.mood_max, l.mood + LITTLE.mood_per_gift)
        l.mood_hour = self.player.hours
        local more = Game.troupe_size(l.friend)
        if more > l.n then
            l.n = more
            self:push_log("Another Little One falls in behind you, grinning.")
        end
    end
end

-- E (or T) at a cairn: leave a trinket on the stones.
function Game:offer_trinket(item)
    item = item or self:first_trinket()
    if not item then
        self:push_log("Nothing to leave. They like toys.")
        return false
    end
    local name = ITEM_DB[item].name:lower()
    self:gift_little(item)
    self:push_log(("You set the %s on the stones. Something giggles in the grass."):format(name))
    self:sfx("chime")
    return true
end

function Game:little_join()
    local l = self.little
    l.n = Game.troupe_size(l.friend)
    l.mood, l.mood_hour = LITTLE.mood_start, self.player.hours
    self:sfx("gift")
    self:push_log(l.n == 1 and "A Little One creeps out of the burrow and follows you, giggling."
        or ("%d Little Ones tumble out of the burrow and follow you."):format(l.n))
end

-- Warrens and cairns in sight are remembered (from spot_sites).
function Game:spot_little()
    local l, vis = self.little, self.player.visible
    for _, kind in ipairs({"warrens", "cairns"}) do
        for _, k in ipairs((self.extras or {})[kind] or {}) do
            if vis[k] and not l.seen[k] then
                l.seen[k] = true
                if kind == "warrens" then self:queue_scene("little_ones") end
                self:push_log(kind == "warrens" and ("A burrow under a mound, " .. self:bearing_to(k) .. ". Giggling.")
                    or ("A little cairn of stones, " .. self:bearing_to(k) .. "."))
            end
        end
    end
end

-- After a move (from try_move). True if it started an encounter.
function Game:little_arrive()
    local key = hex_key(self.player.q, self.player.r)
    local spot = self:little_spot(key)
    if not spot then return false end
    local l = self.little
    l.seen[key] = true
    if spot == "warren" then self:queue_scene("little_ones") end
    if spot == "cairn" then
        self:push_log("A little cairn of stones, a shell on top. Toys left here are gone.")
        return false
    end
    if l.n > 0 then
        self:push_log("Your Little Ones dive into the burrow and tumble out again.")
        return false
    end
    if Game.troupe_size(l.friend) > 0 then
        self:little_join()
        return false
    end
    self:start_encounter(LITTLE.def)
    return true
end

-- -- what a following troupe gets up to ----------------------------------------

function Game:little_find(hour)
    local p = self.player
    local item
    if self:roll(LITTLE.find_trinket) then
        item = LITTLE.trinkets[self:rand(#LITTLE.trinkets) + 1]
    else
        local loot = SCAVENGE_LOOT[self.tiles[hex_key(p.q, p.r)]] or SCAVENGE_LOOT.plains
        local table_ = {}
        for _, e in ipairs(loot) do
            if e[1] ~= "nothing" then table_[#table_ + 1] = e end
        end
        self.seed, item = weighted_pick(self.seed, table_)
    end
    self:put_stack("ground", nil, {item = item, qty = 1})
    self:push_log("A Little One drops " .. ITEM_DB[item].name:lower() .. " at your feet and runs off giggling.")
end

-- Hide one small thing: only odds and ends - never what you eat or drink,
-- wear, heal with, work with, or what gets you out of the Churn.
function Game:little_mischief(hour)
    local p, l = self.player, self.little
    local options = {}
    for _, s in ipairs(p.inventory) do
        local def = ITEM_DB[s.item]
        if not def.artifact and not def.consumable and not def.slot and not LITTLE.keep[s.item] then
            options[#options + 1] = s.item
        end
    end
    if #options == 0 or l.hidden then return end
    local item = options[self:rand(#options) + 1]
    self:take_from_bag(item)
    if self:roll(LITTLE.back_chance) then
        local b = LITTLE.back_hours
        l.hidden = {item = item, back = hour + b[1] + self:rand(b[2] - b[1] + 1)}
    end
    self:push_log("Your " .. ITEM_DB[item].name:lower() .. " is gone. Giggling, somewhere close.")
end

-- One hour with the troupe (from tick).
function Game:little_hour(hour)
    local l, p = self.little, self.player
    if not l then return end
    if l.hidden and hour >= l.hidden.back then
        self:put_stack("ground", nil, {item = l.hidden.item, qty = 1})
        self:push_log("Your " .. ITEM_DB[l.hidden.item].name:lower() .. " is back, on the ground at your feet.")
        l.hidden = nil
    end
    if l.n <= 0 then return end
    if hour - l.mood_hour >= LITTLE.decay_hours then
        l.mood, l.mood_hour = l.mood - 1, hour
        if l.mood <= 0 then
            l.n, l.friend = 0, LITTLE.join_at - 1   -- one more gift wins them back
            self:push_log("Your Little Ones get bored of you and wander home.")
            return
        end
    end
    if hour % LITTLE.act_every ~= 0 then return end
    if self:roll(LITTLE.find) then
        self:little_find(hour)
    elseif self:roll(LITTLE.mischief) then
        self:little_mischief(hour)
    elseif self:is_night(hour) and self:roll(LITTLE.keep_awake) then
        p.needs.rest = clamp(p.needs.rest - LITTLE.awake_rest)
        self:push_log("The Little Ones giggle half the night away.")
    end
end

-- In a fight: they pelt it with stones (true if that killed it).
function Game:little_turn()
    local l, e = self.little, self.enc
    if not l or l.n <= 0 or e.over or e.def.kind == "horror" then return false end
    if not self:roll(LITTLE.pebble) then return false end
    local d, dmg = LITTLE.pebble_dmg, 0
    for _ = 1, l.n do dmg = dmg + d[1] + self:rand(d[2] - d[1] + 1) end
    e.hp = e.hp - dmg
    self:enc_say(("The Little Ones pelt the %s with stones (-%d)."):format(e.def.who, dmg))
    if e.hp <= 0 then
        self:enemy_dies()
        return true
    end
    return false
end

-- % added to running away: they make a racket; horrors they flee from with you.
function Game:little_flee_bonus()
    local l, e = self.little, self.enc
    if not l or l.n <= 0 then return 0 end
    return (e and e.def.kind == "horror") and LITTLE.horror_run or LITTLE.flee_bonus
end

-- -- meeting them at a warren (kind "little") --------------------------------

function Game:little_options()
    local o = {{"Watch them", "watch_little"}}
    if self:first_trinket() then o[#o + 1] = {"Offer a trinket", "offer_little"} end
    o[#o + 1] = {"Shoo them away", "shoo_little"}
    return o
end

function Game:little_action(action)
    local l = self.little
    if action == "watch_little" then
        self:enc_say("They watch you back. One waves. Another picks its teeth with a bird bone. "
            .. "Then they're gone.")
        return self:end_encounter("The Little Ones went back underground.")
    elseif action == "offer_little" then
        local item = self:first_trinket()
        self:gift_little(item, 2)
        self:enc_say("A small grey hand snatches the " .. ITEM_DB[item].name:lower()
            .. ". Delighted shrieking under the ground.")
        if l.n == 0 and Game.troupe_size(l.friend) > 0 then
            self:end_encounter()
            self:little_join()
            return
        end
        return self:end_encounter("The Little Ones liked that.")
    else   -- shoo: they take something and vanish
        local before = #self.player.inventory
        self:little_mischief(self.player.hours)
        self:enc_say(#self.player.inventory ~= before and "They scatter, and something of yours goes with them."
            or "They scatter, giggling.")
        return self:end_encounter("The Little Ones scattered.")
    end
end

-- Journal lines.
function Game:little_lines()
    local l, out = self.little, {}
    if not l then return out end
    local moods = {"sulky", "sulky", "restless", "restless", "content", "content", "happy",
                   "happy", "delighted", "delighted"}
    if l.n > 0 then
        out[1] = ("Little Ones: %d following, %s."):format(l.n, moods[math.max(1, math.min(10, l.mood))])
    elseif l.friend > 0 then
        out[1] = ("Little Ones: %d trinket%s given (%d befriends them)."):format(
            l.friend, l.friend == 1 and "" or "s", LITTLE.join_at)
    end
    local p, best, best_d = self.player, nil, nil
    for key in pairs(l.seen) do
        if self:little_spot(key) == "cairn" then
            local q, r = Game.key_qr(key)
            local d = axial_distance(p.q, p.r, q, r)
            if not best_d or d < best_d then best, best_d = key, d end
        end
    end
    if best then out[#out + 1] = "Nearest cairn: " .. self:bearing_to(best) .. "." end
    return out
end
