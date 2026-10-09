-- ---------------------------------------------------------------------
-- The status page (P on the map or the bag): you, in numbers - health and
-- needs, warmth, rads, dread and carrying, each condition you have and
-- what it is doing to you, then your attributes and traits. It's a page of the
-- scrolling screen the skills use (self.page = "status").
-- ---------------------------------------------------------------------

function Game:open_status()
    self.skills_back = self.screen
    self.skills_off, self.page = 0, "status"
    self.screen = "skills"
end

-- One line per condition: "Name: what it does". Names as current_conditions.
function Game:condition_lines()
    local p, out = self.player, {}
    local function add(name, what) out[#out + 1] = name .. ": " .. what end
    if p.equipped.feet == nil then add("Barefoot", "no warmth on your feet") end
    if (p.cold_hours or 0) > 0 then
        add("Cold", (p.cold_hours > WORLD.cold_grace and "hurts and tires you" or "tires you; it hurts after "
            .. WORLD.cold_grace .. "h") .. " (" .. p.cold_hours .. "h)")
    end
    if p.needs.hunger <= 0 then add("Starving", "hurts each hour, -1 MP, no healing") end
    if p.needs.thirst <= 0 then add("Dehydrated", "hurts each hour, -1 MP, no healing") end
    if p.needs.rest <= 0 then add("Exhausted", "-1 MP. Sleep (Space)") end
    if p.injuries.bleeding then add("Bleeding", "hurts each hour. E on cloth binds it") end
    if p.injuries.wounded_hours > 0 then add("Wounded", "-1 MP for " .. p.injuries.wounded_hours .. "h") end
    if p.health < 50 then add("Hurt", "under half health. Rest to heal") end
    local _, worst = self:most_worn(1)
    if worst and worst <= 0 then add("Torn clothes", "half the warmth and pockets. Patch them") end
    if (p.sick_hours or 0) > 0 then add("Sick", "drains food, drink, rest, health (" .. p.sick_hours .. "h)") end
    local st = RAD.stages[self:rad_stage()]
    if st then
        add(self:can_measure() and st.name or st.feel,
            st.hurt > 0 and "hurts and tires you each hour" or "tires you faster")
    end
    local dread = self:dread_name()
    if dread then
        local d = p.dread or 0
        add(dread, d >= 85 and "sleep does half the good; you see things"
            or d >= 70 and "the Churn whispers; you see things"
            or d >= 60 and "the Churn whispers as you walk" or "a fire, a tape or vodka eases it")
    end
    return out
end

function Game:status_lines()
    local p, lines = self.player, {}
    local function add(s) lines[#lines + 1] = s end
    local n = p.needs
    add(("Health %d/%d   MP %d/%d   Sight %d"):format(math.floor(p.health), MAX_HEALTH, p.mp,
        effective_max_mp(p), p.view_sight or p.sight))
    add(("Food %d   Drink %d   Rest %d   (of 100)"):format(math.floor(n.hunger), math.floor(n.thirst),
        math.floor(n.rest)))
    local warm = self:fire_at(p.hours) and "by a fire" or self:bed_here() and "in your bed"
        or (self:warmth() .. ", you need " .. self:cold_need())
    add("Warmth " .. warm)
    add(self:can_measure() and ("Rads %d of %d"):format(math.floor(p.rads or 0), RAD.max)
        or "Rads: no Geiger counter to tell")
    add(("Dread %d of 100"):format(math.floor(p.dread or 0)))
    for _, l in ipairs(wrap("Carrying: " .. self:bag_sum_text(), 55)) do add(l) end
    add("")
    local conds = self:condition_lines()
    add(#conds > 0 and "Conditions" or "Conditions: none")
    for _, c in ipairs(conds) do
        for i, l in ipairs(wrap(c, 53)) do add((i == 1 and "  " or "    ") .. l) end
    end
    add("")
    add("Attributes")
    for _, name in ipairs(ATTRIBUTES) do
        add(("  %-11s %d  %s"):format(name, p.attrs[name], ATTR_DESC[name]:match(":%s*(.*)")))
    end
    local any = false
    for _, t in ipairs(TRAITS) do
        if p.traits[t.name] then
            if not any then add("Traits") end
            any = true
            add(("  %-13s %s"):format(t.name, t.desc))
        end
    end
    local muts = self:mutation_lines()
    if #muts > 0 then
        add("Mutations")
        for _, l in ipairs(muts) do add(l) end
    end
    return lines
end
