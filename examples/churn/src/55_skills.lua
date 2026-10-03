-- ---------------------------------------------------------------------
-- Skills that grow with use (numbers in SKILLS, 05_data_world)
--
-- self.skills = {skill -> XP} (saved). Doing a thing earns XP in its
-- skill (search, fish and hunt, fight, craft and repair); every threshold
-- in SKILLS.levels is a level, up to 5. Each level gives a small bonus
-- through skill_bonus at the place the roll is made: scavenge (fewer
-- duds), fish / hunt, attack / throw, repair_chance, and craft_hours.
-- ---------------------------------------------------------------------

function Game:skill_level(name)
    local xp, level = (self.skills or {})[name] or 0, 0
    for i, need in ipairs(SKILLS.levels) do
        if xp >= need then level = i end
    end
    return level
end

-- The skill's bonus in percent points (0 at level 0).
function Game:skill_bonus(name)
    return self:skill_level(name) * SKILLS.bonus[name]
end

function Game:skill_xp(name, n)
    self.skills = self.skills or {}
    local before = self:skill_level(name)
    self.skills[name] = (self.skills[name] or 0) + n
    local after = self:skill_level(name)
    if after > before then
        self:push_log(("%s improves to %d."):format(SKILLS.long[name], after))
        self:sfx("level")
    end
end

-- Hours a recipe takes: practised tinkerers are an hour quicker.
function Game:craft_hours(r)
    if self:skill_level("tinker") >= SKILLS.fast_craft then return math.max(1, r.hours - 1) end
    return r.hours
end

-- "Scav 2  Fish 1  Fight 3  Tinker 0" (journal).
function Game:skills_line()
    local parts = {}
    for _, name in ipairs(SKILLS.order) do
        parts[#parts + 1] = SKILLS.name[name] .. " " .. self:skill_level(name)
    end
    return "Skills: " .. table.concat(parts, "  ")
end
