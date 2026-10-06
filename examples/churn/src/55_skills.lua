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
    local h = r.hours
    if self:skill_level("tinker") >= SKILLS.fast_craft then h = h - 1 end
    if self:at_base() and self:base_has("bench") and not r.base then h = h - BASE.bench_hours end
    return math.max(1, h)
end

-- +% on fiddly work (guns, repairs) at the camp's workbench.
function Game:bench_bonus()
    return self:at_base() and self:base_has("bench") and BASE.bench_chance or 0
end

-- "Scav 2  Fish 1  Fight 3  Tinker 0" (journal).
function Game:skills_line()
    local parts = {}
    for _, name in ipairs(SKILLS.order) do
        parts[#parts + 1] = SKILLS.name[name] .. " " .. self:skill_level(name)
    end
    return "Skills: " .. table.concat(parts, "  ")
end

-- ---------------------------------------------------------------------
-- The skills page (K in the journal): each skill's level, XP and bonus,
-- then the recipes you know. Up/Down scroll when it's longer than the
-- screen; any other key goes back to the journal.
-- ---------------------------------------------------------------------

function Game:skills_page_lines()
    if self.page == "finds" then return self:finds_lines() end
    if self.page == "map" then return self:map_wall_lines() end
    if self.page == "bestiary" then return self:bestiary_lines() end
    local lines = {"Skill               Lv  XP       Bonus"}
    for _, name in ipairs(SKILLS.order) do
        local level, xp = self:skill_level(name), (self.skills or {})[name] or 0
        local next_xp = SKILLS.levels[level + 1]
        local bonus = SKILLS.what[name]:format(self:skill_bonus(name))
        if name == "tinker" and level >= SKILLS.fast_craft then bonus = bonus .. ", -1h craft" end
        lines[#lines + 1] = ("%-19s %d   %-8s %s"):format(SKILLS.long[name], level,
            next_xp and (xp .. "/" .. next_xp) or (xp .. " max"), bonus)
    end
    lines[#lines + 1] = ("Levels: %s XP. Tinker %d: craft 1h faster."):format(
        table.concat(SKILLS.levels, "/"), SKILLS.fast_craft)
    lines[#lines + 1] = ""
    local names = {}
    for _, r in ipairs(RECIPES) do
        if self.known[r.id] then names[#names + 1] = r.name end
    end
    lines[#lines + 1] = ("Recipes known: %d of %d"):format(#names, #RECIPES)
    for _, l in ipairs(wrap(#names > 0 and table.concat(names, ", ") or "None yet.", 55)) do
        lines[#lines + 1] = l
    end
    if #names < #RECIPES then lines[#lines + 1] = "Learn more: study, read notes, listen to tapes." end
    return lines
end

function Game:open_skills()
    self.skills_off, self.page = 0, nil
    self.screen = "skills"
end

function Game.skills_fit(h) return (h - 24 - 40) // 14 + 1 end

function Game:skills_key(key, h)
    local max_off = math.max(0, #self:skills_page_lines() - Game.skills_fit(h or 300))
    if key == gfx.KEY_UP or key == KEY.W then
        self.skills_off = math.max(0, (self.skills_off or 0) - 3)
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        self.skills_off = math.min(max_off, (self.skills_off or 0) + 3)
    else
        self.screen = self.skills_back or "journal"
        self.skills_back = nil
    end
end

function Game:draw_skills(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    Game.ui_title(w, ({finds = "Finds", map = "Map wall", bestiary = "Bestiary"})[self.page] or "Skills and recipes")
    local lines, fit = self:skills_page_lines(), Game.skills_fit(h)
    local off = math.max(0, math.min(self.skills_off or 0, #lines - fit))
    local y = 40
    for i = off + 1, math.min(#lines, off + fit) do
        gfx.text(6, y, lines[i])
        y = y + 14
    end
    Game.ui_keys(w, h, #lines > fit and "Up/Dn scroll  any key: back" or "Any key: back")
    gfx.refresh()
end
