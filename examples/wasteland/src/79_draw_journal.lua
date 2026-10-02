-- ---------------------------------------------------------------------
-- Journal (J): one page of what you know, so you don't have to remember it.
-- ---------------------------------------------------------------------

function Game:open_journal()
    self.help_back = self.screen   -- shares help's "any key: back" (help_key)
    self.screen = "journal"
end

function Game:journal_lines()
    local p, lines = self.player, {}
    local function add(s) lines[#lines + 1] = s end
    local day, hour = self:clock()
    add(("Day %d, %02d:00. %d hours in the Zone. %s."):format(day, hour, p.hours,
        DIFFICULTY[self.difficulty or "normal"].name))
    add(self:skills_line())
    local worn, c = self:most_worn(100)
    if worn then
        add(("Most worn: %s,%s. C: Patch clothes."):format(ITEM_DB[self.player.equipped[worn]].name:lower(),
            Game.cond_text(c)))
    end
    local season, sday = self:season()
    local weather = self:weather()
    local advice = {Storm = " Find shelter: ruins, hills, trees.", Fog = " Sight is short.",
                    Snow = " Dress warm.", ["Cold snap"] = " Dress warm."}
    add(("%s, day %d of %d. %s.%s"):format(season.name, sday, WORLD.season_days, weather,
        advice[weather] or ""))
    -- the way out
    if self.sites_known.checkpoint then
        add("Checkpoint: " .. self:site_bearing("checkpoint") .. ". Needs a permit or "
            .. GOAL.bribe .. " artifacts.")
    else
        add("The way out: unknown. Find the trader, or read notes.")
    end
    if self.sites_known.trader then add("Trader: " .. self:site_bearing("trader") .. ".") end
    if self.sites_known.ferry then add("Ferry Post (Mother Okun): " .. self:site_bearing("ferry") .. ".") end
    for _, l in ipairs(self:little_lines()) do add(l) end
    local pd = self.peddler
    if pd and pd.seen_key then
        add(("Peddler: last seen %s, day %d."):format(self:bearing_to(pd.seen_key), (self:clock(pd.seen_hour))))
    end
    if self:lore_count() > 0 then
        add(("Pages read: %d/%d. L to reread them."):format(self:lore_count(), #LORE.pages))
    end
    local story = self:story_text()
    if story then add(story) end
    local quest = self:quest_text()
    if quest then add("Quest - " .. quest) end
    local camp = self:base_text()
    if camp then add(camp) end
    local permit = self:count_item("permit") > 0
    add(("Artifacts: %d of %d.%s"):format(self:artifact_count(), GOAL.bribe,
        permit and " You have a Zone Permit." or ""))
    -- places
    for key in pairs(self.stashes) do add("Stash: " .. self:bearing_to(key) .. ".") end
    for key, snare in pairs(self.snares) do
        add(("Snare: %s, set %dh ago."):format(self:bearing_to(key), p.hours - snare.set))
    end
    local hot, nearest, nearest_d = 0, nil, nil
    for key, level in pairs(self.rad_known) do
        if level > 0 then
            hot = hot + 1
            local q, r = Game.key_qr(key)
            local d = axial_distance(p.q, p.r, q, r)
            if not nearest or d < nearest_d then nearest, nearest_d = key, d end
        end
    end
    if hot > 0 then
        add(("Hot hexes known: %d. Nearest: %s."):format(hot, nearest_d == 0 and "here"
            or self:bearing_to(nearest)))
    end
    -- you, and who's with you
    if self:can_measure() and (p.rads or 0) > 0 then
        add(("Radiation: %d rads."):format(math.floor(p.rads)))
    elseif self:rad_stage() > 0 then
        add("You feel " .. RAD.stages[self:rad_stage()].feel:lower() .. ". Something is making you sick.")
    end
    local emit = self:emission_text()
    if emit then add("Emission: " .. emit .. ". Get to ruins or hills.") end
    if self.dog then
        local hungry = self.dog.hungry_days > 0 and (", hungry " .. self.dog.hungry_days .. "d") or ", fed"
        add(("Your dog: %d/%d HP%s."):format(self.dog.hp, DOG.hp, hungry))
    end
    if self.radio and self:carrying("lora_radio") then
        add(("Radio: %d/%d charge."):format(self.radio.charge, TECH.radio_max))
    end
    return lines
end

function Game:draw_journal(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Journal")
    gfx.font(gfx.FONT_MONO_12)
    local y, max_y = 40, h - 24
    local all = {}
    for _, line in ipairs(self:journal_lines()) do
        for _, part in ipairs(wrap(line, 55)) do all[#all + 1] = part end
    end
    local fit = (max_y - y) // 14 + 1
    for i, line in ipairs(all) do
        if i == fit and #all > fit then
            gfx.text(6, y, ("+%d more"):format(#all - fit + 1))
            break
        end
        gfx.text(6, y, line)
        y = y + 14
    end
    gfx.text(6, h - 8, self:lore_count() > 0 and "L: read pages   any key: back" or "Any key: back")
    gfx.refresh()
end
