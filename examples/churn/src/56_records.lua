-- ---------------------------------------------------------------------
-- Run stats, lifetime records and achievements
--
-- self.stats counts this run (saved with it): kills, searches, artifacts
-- found, fish caught, riddles answered, repairs, night horrors lived
-- through. The lifetime records live in their own file next to the save,
-- <mount>/churn/records.lua, written whenever a run ends or an
-- achievement unlocks, so deleting a save (death, escape) keeps them.
-- Without write_file they last until the app is closed.
-- R on the title, creator, death and ending screens shows them.
-- ---------------------------------------------------------------------

local RECORDS = {
    file = "records.lua",
    data = nil,   -- the loaded records (Game.records)
    -- id, name, what it takes, test(game, how): how = "permit"/"bribe" when escaping
    list = {
        {"first_steps", "First Steps", "Live to see day 2",
         function(g) return (g:clock()) >= 2 end},
        {"week", "Week in the Churn", "Live to see day 8",
         function(g) return (g:clock()) >= 8 end},
        {"out", "Out", "Leave the Churn alive", function(_, how) return how ~= nil end},
        {"paper", "Paper Trail", "Leave with a Churn Permit",
         function(_, how) return how == "permit" end},
        {"bribed", "Bribed", "Buy your way out", function(_, how) return how == "bribe" end},
        {"hardened", "Churn-Hardened", "Leave on Churn-Hardened",
         function(g, how) return how ~= nil and g.difficulty == "hard" end},
        {"dog", "Dog's Best Friend", "Tame a stray", function(g) return g.dog ~= nil end},
        {"karl", "Karl's Friend", "Answer Karl 3 riddles in a run",
         function(g) return g:stat_of("riddles") >= 3 end},
        {"archivist", "Archivist", "Read every torn page",
         function(g) return g:lore_count() >= #LORE.pages end},
        {"fixer", "Fixer", "Repair a broken device", function(g) return g:stat_of("repairs") >= 1 end},
        {"homeowner", "Homeowner", "Build all four camp parts",
         function(g)
             if not g.base then return false end
             for _, part in ipairs({"box", "bedroll", "barrel", "barricade"}) do   -- (the first four)
                 if not g.base.built[part] then return false end
             end
             return true
         end},
        {"quiet", "The Quiet", "Silence the Signal", function(_, how) return how == "quiet" end},
        {"night_owl", "Night Owl", "Live through 3 night horrors",
         function(g) return g:stat_of("horrors") >= 3 end},
    },
}

function Game:stat(name, n)
    self.stats = self.stats or {}
    self.stats[name] = (self.stats[name] or 0) + (n or 1)
end

function Game:stat_of(name)
    return (self.stats or {})[name] or 0
end

local function records_path()
    local dir = SAVE.path()
    return dir, dir and (dir .. "/" .. RECORDS.file)
end

-- The lifetime records, read from storage the first time.
function Game.records()
    if RECORDS.data then return RECORDS.data end
    local rec
    local storage = solaros.storage
    local _, path = records_path()
    if path and storage and storage.read_file then
        -- (or the old folder's, or the `.new` copy a cut-short save left)
        local text = SAVE.read_any(RECORDS.file, 16384, function(t) return t end)
        local ok = text ~= nil
        local chunk = ok and type(text) == "string" and text ~= "" and load("return " .. text, "=records", "t", {})
        local good, data = false, nil
        if chunk then good, data = pcall(chunk) end
        if good and type(data) == "table" then
            rec = data
        elseif ok and type(text) == "string" and text ~= "" then
            -- unreadable (cut short by a power loss?): keep a copy before the
            -- next write replaces it
            RECORDS.bad_text = text
        end
    end
    RECORDS.data = Game.clean_records(rec or {})
    return RECORDS.data
end

-- Whatever the file held, a records table the game can use: counts are
-- whole numbers >= 0, tables are tables, the best escape a real difficulty.
function Game.clean_records(rec)
    local function count(v)
        v = math.tointeger(tonumber(v) or 0) or 0
        return v > 0 and v or 0
    end
    local out = {runs = count(rec.runs), escapes = count(rec.escapes), kills = count(rec.kills),
                 longest = count(rec.longest), most_out = count(rec.most_out),
                 deaths = {}, achieved = {}, counted = {}}
    if type(rec.deaths) == "table" then
        for why, n in pairs(rec.deaths) do
            if type(why) == "string" and count(n) > 0 then out.deaths[why] = count(n) end
        end
    end
    if type(rec.achieved) == "table" then
        for id, on in pairs(rec.achieved) do
            if type(id) == "string" and on == true then out.achieved[id] = true end
        end
    end
    if type(rec.counted) == "table" then
        for _, id in ipairs(rec.counted) do
            if type(id) == "string" then out.counted[#out.counted + 1] = id end
        end
    end
    if type(rec.best_escape) == "string" and DIFFICULTY[rec.best_escape] then
        out.best_escape = rec.best_escape
    end
    -- what's left of your last body (64_legacy): stacks of real items only
    local leg = rec.legacy
    if type(leg) == "table" and type(leg.items) == "table" then
        local items = {}
        for _, s in ipairs(leg.items) do
            if type(s) == "table" and type(s.item) == "string" and ITEM_DB[s.item] and count(s.qty) > 0 then
                items[#items + 1] = {item = s.item, qty = count(s.qty)}
            end
        end
        if #items > 0 then
            out.legacy = {items = items, cause = type(leg.cause) == "string" and leg.cause or "You died.",
                          day = count(leg.day)}
        end
    end
    return out
end

-- Forget the loaded records (tests: read them back from storage).
function Game.reload_records()
    RECORDS.data = nil
end

function Game.write_records()
    if not SAVE.can_write() then return false end
    local dir, path = records_path()
    return pcall(function()
        if solaros.storage.makedirs then solaros.storage.makedirs(dir) end
        if RECORDS.bad_text then   -- the unreadable old file, kept once
            solaros.storage.write_file(dir .. "/records.bad.lua", RECORDS.bad_text)
            RECORDS.bad_text = nil
        end
        SAVE.write(path, table.concat(SAVE.serialize(Game.records(), {})))
    end)
end

-- Unlock what this run has earned (from tick, and when the run ends).
function Game:check_achievements(how, no_write)
    local rec, new = Game.records(), false
    for _, a in ipairs(RECORDS.list) do
        if not rec.achieved[a[1]] and a[4](self, how) then
            rec.achieved[a[1]] = true
            self.run_unlocked = (self.run_unlocked or 0) + 1
            self:push_log("Achievement: " .. a[2] .. "!")
            self:sfx("achieve")
            new = true
        end
    end
    if new and not no_write then Game.write_records() end
end

-- A run is over: how = "permit"/"bribe" for an escape, nil for a death.
function Game:record_run(how, cause)
    if self.run_recorded then return end
    self.run_recorded = true
    local rec, p, best = Game.records(), self.player, {}
    -- a run is counted once, even if its save survives and is continued
    local id = self.run_id or tostring(self.world_seed)   -- (saves from before run ids)
    for _, seen in ipairs(rec.counted) do
        if seen == id then return end
    end
    table.insert(rec.counted, id)
    while #rec.counted > 20 do table.remove(rec.counted, 1) end
    rec.runs = rec.runs + 1
    rec.kills = rec.kills + self:stat_of("kills")
    if p.hours > rec.longest then
        if rec.runs > 1 then best[#best + 1] = "longest run" end
        rec.longest = p.hours
    end
    if how then
        rec.escapes = rec.escapes + 1
        local out = self:artifact_count()
        if out > rec.most_out then
            if rec.most_out > 0 then best[#best + 1] = "most artifacts out" end
            rec.most_out = out
        end
        local order = {easy = 1, normal = 2, hard = 3}
        if (order[self.difficulty] or 0) > (order[rec.best_escape] or 0) then
            rec.best_escape = self.difficulty
        end
    else
        local why = cause or "Unknown"
        rec.deaths[why] = (rec.deaths[why] or 0) + 1
    end
    self.run_best = best
    self:check_achievements(how, true)
    Game.write_records()
end

-- A few lines for the death and ending screens.
function Game:run_summary()
    local p = self.player
    local day = self:clock()
    local seen = 0
    for _ in pairs(p.explored or {}) do seen = seen + 1 end
    local lines = {
        ("Day %d, %d hours. Kills %d. Hexes seen %d."):format(day, p.hours, self:stat_of("kills"), seen),
        ("Searches %d. Artifacts found %d. Fish %d. Pages %d."):format(self:stat_of("searches"),
            self:stat_of("artifacts"), self:stat_of("fish"), self:lore_count()),
    }
    if self.run_best and #self.run_best > 0 then
        lines[#lines + 1] = "New record: " .. table.concat(self.run_best, ", ") .. "!"
    end
    if (self.run_unlocked or 0) > 0 then
        lines[#lines + 1] = ("Achievements this run: %d. (R to see them)"):format(self.run_unlocked)
    end
    return lines
end

-- -- the records screen ---------------------------------------------------

function Game:open_records()
    self.records_back = self.screen
    self.screen = "records"
end

function Game:records_key()
    self.screen = self.records_back or "title"
end

function Game:records_lines()
    local rec = Game.records()
    local deaths, worst, worst_n = 0, nil, 0
    for why, n in pairs(rec.deaths) do
        deaths = deaths + n
        if n > worst_n or (n == worst_n and worst and why < worst) then worst, worst_n = why, n end
    end
    local lines = {
        ("Runs %d   Escapes %d   Deaths %d"):format(rec.runs, rec.escapes, deaths),
        ("Longest run %dh   Most artifacts out %d"):format(rec.longest, rec.most_out),
        ("Kills, all runs %d   Best escape: %s"):format(rec.kills,
            rec.best_escape and DIFFICULTY[rec.best_escape].short or "none"),
    }
    if worst then lines[#lines + 1] = "Most deaths: " .. worst end
    return lines
end

function Game:draw_records(w, h)
    local rec = Game.records()
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    Game.ui_title(w, "Records")
    local y = 40
    for _, line in ipairs(self:records_lines()) do
        gfx.text(6, y, line:sub(1, 56))
        y = y + 14
    end
    local got = 0
    for _, a in ipairs(RECORDS.list) do
        if rec.achieved[a[1]] then got = got + 1 end
    end
    y = y + 8
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, y, ("Achievements %d/%d"):format(got, #RECORDS.list))
    gfx.font(gfx.FONT_MONO_12)
    y = y + 18
    -- only the ones you've earned: the rest stay a surprise
    for _, a in ipairs(RECORDS.list) do
        if rec.achieved[a[1]] then
            gfx.text(6, y, a[2])
            gfx.text(170, y, a[3])
            y = y + 12
        end
    end
    if got == 0 then
        gfx.text(6, y, "None yet.")
        y = y + 12
    end
    if got < #RECORDS.list then
        gfx.text(6, y + 2, ("%d more to find."):format(#RECORDS.list - got))
    end
    if not SAVE.can_write() then gfx.text(6, h - 22, "(not saved: this SolarOS can't write files)") end
    Game.ui_keys(w, h, "Any key: back")
    gfx.refresh()
end
