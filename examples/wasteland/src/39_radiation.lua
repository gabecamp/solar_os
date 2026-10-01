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
        dose = RAD.dose[level] * self:rad_armor() * self:diff("rad")
        p.rads = math.min(RAD.max, (p.rads or 0) + dose)
        -- only a counter puts it on the map; otherwise you just felt something
        if self:can_measure() then self.rad_known[hex_key(p.q, p.r)] = level end
        self.dose_level = math.max(self.dose_level or 0, level)
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

-- A Geiger counter (or the Anomaly Detector) tells you what's going on.
-- Without one, radiation only shows as symptoms.
function Game:can_measure()
    return self:carrying("geiger") or self:carrying("anomaly_detector")
end

-- Items whose real name or description would give radiation away show a
-- vague one until you can measure it (vague_name / vague_desc in ITEM_DB).
-- ITEM_DB is edited in place so every screen and log line follows; runs
-- from tick (every key) and refresh_view.
function Game:apply_item_names()
    local measured = self:can_measure()
    for _, def in pairs(ITEM_DB) do
        if def.vague_name or def.vague_desc then
            def.real_name = def.real_name or def.name
            def.real_desc = def.real_desc or def.desc
            def.name = measured and def.real_name or (def.vague_name or def.real_name)
            def.desc = measured and def.real_desc or (def.vague_desc or def.real_desc)
        end
    end
end

-- The Geiger counter reads your hex and the ones next to it.
function Game:geiger_scan()
    local p = self.player
    if self:carrying("anomaly_detector") then   -- reads further than a Geiger counter
        local range = TECH.detector_range
        for dq = -range, range do
            for dr = math.max(-range, -dq - range), math.min(range, -dq + range) do
                local key = hex_key(p.q + dq, p.r + dr)
                if self.tiles[key] then self.rad_known[key] = self:rad_at(p.q + dq, p.r + dr) end
            end
        end
        return
    end
    if not self:carrying("geiger") then return end
    local here = hex_key(p.q, p.r)
    self.rad_known[here] = self:rad_at(p.q, p.r)
    local near = 0
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        local level = self:rad_at(n[1], n[2])
        self.rad_known[hex_key(n[1], n[2])] = level
        near = math.max(near, level)
    end
    -- clean here but hot next door: the counter ticks faster (once per hex)
    if self.rad_known[here] == 0 and near > 0 and self.geiger_ticked ~= here then
        self.geiger_ticked = here
        self:sfx("geiger")
        self:push_log("The Geiger ticks faster. Something hot nearby.")
    end
end

-- Log lines (and clicks) for the hours tick just applied.
function Game:rad_news(dose, stage_before)
    local p = self.player
    local measured = self:can_measure()
    local level = self.dose_level or 0
    self.dose_level = nil
    if dose > 0 then
        if measured then
            self:push_log(("%s crackles: +%d rads (%d)."):format(
                self:carrying("geiger") and "Geiger" or "Detector",
                math.floor(dose + 0.5), math.floor(p.rads)))
            self:sfx("geiger")
        else
            self:push_log(RAD.feel[math.max(1, level)])   -- a feeling, not a reading
        end
    end
    local stage = self:rad_stage()
    if stage > stage_before then
        local st = RAD.stages[stage]
        if measured then
            self:push_log(st.name .. (st.hurt > 0 and (": -" .. st.hurt .. " HP/h. Anti-Rad!") or ": you feel weak."))
        else
            self:push_log(st.onset)
        end
    elseif stage < stage_before and stage == 0 then
        self:push_log(measured and "The radiation sickness fades." or "You feel more like yourself.")
    end
end

-- Map panel line: the Geiger reading, or just how sick you are.
function Game:rad_text()
    local p = self.player
    local rads = math.floor(p.rads or 0)
    if self:can_measure() then
        return (self:carrying("geiger") and "Geiger " or "Detect ")
            .. RAD.level_name[self:rad_at(p.q, p.r)] .. " Rad " .. rads
    end
    local st = RAD.stages[self:rad_stage()]
    if not st then return nil end
    return self:can_measure() and st.name or st.feel
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
