-- ---------------------------------------------------------------------
-- Emissions and stashes
--
-- An emission (blowout) comes every few days (RAD.emission). Game:tick calls
-- emission_hour for every hour: a warning `warn` hours ahead, then `hours`
-- of it - off shelter terrain (ruins) it costs HP and adds rads. After it,
-- field centers without an artifact grow a new one. next_emission is saved.
--
-- Stashes: some scrawled notes mark a hidden pile of supplies a few hexes
-- away (mark_stash). It's drawn on the map until you step on it.
-- ---------------------------------------------------------------------

function Game:emission_hour(hour)
    local E, p = RAD.emission, self.player
    local start = self.next_emission
    if not start then return end
    self.emission_news = self.emission_news or {}
    if hour == start - E.warn then self.emission_news.warn = true end
    if hour >= start and hour < start + E.hours then
        if E.shelter[self.tiles[hex_key(p.q, p.r)]] or self:placed_here("tarp_shelter") then
            self.emission_news.sheltered = true
        else
            local harm = self:diff("emission")
            p.health = clamp(p.health - E.hurt / E.hours * harm)
            p.rads = math.min(RAD.max, (p.rads or 0) + E.rads / E.hours * self:rad_armor() * harm)
            self.emission_news.caught = true
        end
        if hour == start + E.hours - 1 then self:emission_ends() end
    end
end

function Game:emission_ends()
    local E = RAD.emission
    for key, level in pairs(self.rad or {}) do
        if level == 3 then
            local pile = self.ground[key] or {}
            local has = false
            for _, s in ipairs(pile) do has = has or ITEM_DB[s.item].artifact ~= nil end
            if not has then
                self.ground[key] = pile
                table.insert(pile, {item = ARTIFACTS[self:rand(#ARTIFACTS) + 1], qty = 1})
            end
        end
    end
    self.next_emission = self.next_emission + E.every[1] + self:rand(E.every[2] - E.every[1] + 1)
    self.emission_news = self.emission_news or {}
    self.emission_news.ended = true
end

function Game:emission_log()
    local n = self.emission_news
    self.emission_caught = n and n.caught
    if not n then return end
    if n.warn then self:sfx("siren"); self:queue_scene("first_emission") end
    if n.caught then self:sfx("emission"); self:dread(CHURN.dread.emission)
    elseif n.sheltered then self:sfx("emission_cover"); self:dread(CHURN.dread.sheltered) end
    if n.ended then self:sfx("emission_end") end
    if n.warn then
        self:push_log(("The sky bruises purple. Emission in %dh! Ruins/hills!"):format(RAD.emission.warn))
    end
    if n.caught then
        self:push_log("The EMISSION tears through you! Find cover!")
    elseif n.sheltered then
        self:push_log("The emission howls overhead. You hold on in cover.")
    end
    if n.ended then self:push_log("The emission passes. The fields glitter.") end
    self.emission_news = nil
end

-- Panel text while one is coming or raging.
function Game:emission_text()
    local start, now = self.next_emission, self.player.hours
    if not start then return nil end
    if now >= start and now < start + RAD.emission.hours then return "EMISSION!" end
    if start - now <= RAD.emission.warn and start > now then return "EMIT " .. (start - now) .. "h" end
end

-- A scrawled note marks a stash a few hexes away. Returns false if there's
-- nowhere to put one.
function Game:mark_stash()
    local p, S = self.player, RAD.stash
    local taken = {}
    for _, key in pairs(self.sites) do taken[key] = true end
    local spots = {}
    for key, t in pairs(self.tiles) do
        local q, r = Game.key_qr(key)
        local d = axial_distance(p.q, p.r, q, r)
        if TERRAIN[t].passable and d >= S.near and d <= S.far and not self.stashes[key]
            and not taken[key] then
            spots[#spots + 1] = key
        end
    end
    if #spots == 0 then return false end
    table.sort(spots)
    local key = spots[self:rand(#spots) + 1]
    self.ground[key] = self.ground[key] or {}
    for _ = 1, S.items do
        add_to_list(self.ground[key], {item = S.loot[self:rand(#S.loot) + 1], qty = 1})
    end
    self.stashes[key] = true
    p.explored[key] = true
    self:push_log("The notes mark a stash: " .. self:bearing_to(key) .. ".")
    return true
end

-- Stepping onto a stash you were told about.
function Game:find_stash()
    local key = hex_key(self.player.q, self.player.r)
    if self.stashes[key] then
        self.stashes[key] = nil
        self:push_log("You dig up the stash. (I to look)")
        self:sfx("chime")
    end
end
