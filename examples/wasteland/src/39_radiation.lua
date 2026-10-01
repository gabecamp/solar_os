-- ---------------------------------------------------------------------
-- Radiation and anomaly fields
--
-- generate_world leaves self.rad (tile key -> level 1-3). Every hour on a
-- hot hex adds rads (Game:tick calls rad_hour); enough rads make you sick.
-- Anti-Rad and Vodka take rads off (consumable.rads). A carried Geiger
-- counter reads the hexes around you, marks them on the map (rad_known,
-- which is saved) and clicks; without one you only learn a hex was hot by
-- the dose you took there. All numbers are in RAD (05_data).
-- ---------------------------------------------------------------------

function Game:rad_at(q, r)
    return (self.rad and self.rad[hex_key(q, r)]) or 0
end

-- In the bag, in a hand or worn.
function Game:carrying(item)
    local p = self.player
    for _, item_here in pairs(p.equipped) do
        if item_here == item then return true end
    end
    for _, s in ipairs(p.inventory) do
        if s.item == item then return true end
    end
    return false
end

-- What worn gear lets through (1 = everything).
function Game:rad_armor()
    local through = 1
    for slot, item in pairs(self.player.equipped) do
        if not HOLD_SLOTS[slot] then through = through * (ITEM_DB[item].rad_armor or 1) end
    end
    return through
end

-- 0 = fine, else the index of the worst RAD.stages reached.
function Game:rad_stage()
    local rads, stage = self.player.rads or 0, 0
    for i, st in ipairs(RAD.stages) do
        if rads >= st.at then stage = i end
    end
    return stage
end

-- One hour at the current hex. Returns the dose taken.
function Game:rad_hour()
    local p = self.player
    local level = self:rad_at(p.q, p.r)
    local dose = 0
    if level > 0 then
        dose = RAD.dose[level] * self:rad_armor()
        p.rads = math.min(RAD.max, (p.rads or 0) + dose)
        self.rad_known[hex_key(p.q, p.r)] = level
    elseif (p.rads or 0) > 0 then
        p.rads = math.max(0, p.rads - RAD.decay)
    end
    local st = RAD.stages[self:rad_stage()]
    if st then
        p.health = clamp(p.health - st.hurt)
        p.needs.rest = clamp(p.needs.rest - st.tire)
    end
    return dose
end

-- The Geiger counter reads your hex and the ones next to it.
function Game:geiger_scan()
    if not self:carrying("geiger") then return end
    local p = self.player
    self.rad_known[hex_key(p.q, p.r)] = self:rad_at(p.q, p.r)
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        self.rad_known[hex_key(n[1], n[2])] = self:rad_at(n[1], n[2])
    end
end

-- Log lines (and clicks) for the hours tick just applied.
function Game:rad_news(dose, stage_before)
    local p = self.player
    local geiger = self:carrying("geiger")
    if dose > 0 then
        if geiger then
            self:push_log(("Geiger crackles: +%d rads (%d)."):format(math.floor(dose + 0.5),
                                                                   math.floor(p.rads)))
            self:sfx("geiger")
        else
            self:push_log("Your skin prickles. A metal taste.")
        end
    end
    local stage = self:rad_stage()
    if stage > stage_before then
        local st = RAD.stages[stage]
        self:push_log(st.name .. (st.hurt > 0 and (": -" .. st.hurt .. " HP/h. Anti-Rad!") or ": you feel weak."))
    elseif stage < stage_before and stage == 0 then
        self:push_log("The radiation sickness fades.")
    end
end

-- Map panel line: the Geiger reading, or just how sick you are.
function Game:rad_text()
    local p = self.player
    local rads = math.floor(p.rads or 0)
    if self:carrying("geiger") then
        return "Geiger " .. RAD.level_name[self:rad_at(p.q, p.r)] .. " Rad " .. rads
    end
    local st = RAD.stages[self:rad_stage()]
    return st and st.name or nil
end

-- A search on a hot hex can turn up an artifact.
function Game:scavenge_field()
    local p = self.player
    if self:rad_at(p.q, p.r) < 2 then return end
    if not self:roll(RAD.artifact_find) then return end
    local item = ARTIFACTS[self:rand(#ARTIFACTS) + 1]
    self:put_stack("ground", nil, {item = item, qty = 1})
    self:push_log("Something glints in the hot ground: " .. ITEM_DB[item].name .. ".")
end
