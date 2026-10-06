-- ---------------------------------------------------------------------
-- Help (H) and device info (V on the help screen)
--
-- The map's hint line has room for only a few keys; H lists them all. The
-- info page is for testing on a new board: what the game sees of SolarOS.
-- ---------------------------------------------------------------------

Game.VERSION = "@VERSION@"   -- (tools/build.py puts the version here: tools/version.json)

local HELP = {
    {"MAP", "Lt/Rt step; Up/Dn then Lt/Rt: diagonal"},
    {"", "(WASD too)   Space rest 4h"},
    {"", "F search   E water: fill/drink   I bag"},
    {"", "T trade/Checkpoint   C craft   J journal"},
    {"", "G hunt, or fish   R radio   M sound"},
    {"BAG", "Arrows pick  Enter select, Enter move"},
    {"", "E use: eat, wear, read, play   X drop"},
    {"", "Drop on a full cell: they swap"},
    {"CRAFT", "Up/Dn pick  Enter make  C/Q back"},
    {"CAMP", "T at your camp: slots, stash; T bag/camp"},
    {"FISH", "Spc wait, Enter strike; Lt/Rt Up Dn fight"},
    {"TRADE", "Lt/Rt side  Enter +1  E -1  T deal  O work"},
    {"FIGHTS", "Up/Dn pick  Enter choose"},
    {"PUZZLE", "Arrows move  T+arrow throw  1-4 sigils"},
    {"", "Q backs away from a puzzle unharmed"},
    {"TIPS", "You know little: C, Study by a fire."},
    {"", "Clothes wear out: C, Patch clothes."},
    {"", "Emissions, storms: shelter in ruins/hills."},
    {"", "3 artifacts or a permit get you out."},
    {"", "Karl fishes rivers. Strays like food."},
    {"", "C in a ruin: claim it. Carry light at night."},
    {"", "Skills grow with use (J). R on the title: records."},
    {"", "Mother Okun trades by the river; a Peddler roams."},
    {"", "Traders deal in rubles. A knife cuts clothes up."},
    {"", "Leave toys at little cairns (E or T)."},
}

function Game:open_help()
    self.help_back = self.screen
    self.help_page = 1
    self.screen = "help"
end

-- The help rows on page n: the keys (1), the tips (2). They don't fit one screen.
function Game.help_rows(n)
    local out, tips = {}, false
    for _, row in ipairs(HELP) do
        if row[1] == "TIPS" then tips = true end
        if tips == (n == 2) then out[#out + 1] = row end
    end
    return out
end

function Game:help_key(key)   -- help, info and journal: any key goes back
    if self.screen == "journal" and key == KEY.L and self:lore_count() > 0 then
        return self:open_lore()
    end
    if self.screen == "journal" and key == KEY.K then return self:open_skills() end
    if self.screen == "journal" and key == KEY.F then return self:open_finds() end
    if self.screen == "journal" and key == KEY.B then return self:open_bestiary() end
    if self.screen == "help" and key == KEY.V then
        self.screen = "info"
    elseif self.screen == "help" and (self.help_page or 1) == 1
        and (key == gfx.KEY_DOWN or key == gfx.KEY_RIGHT or key == KEY.S or key == KEY.D) then
        self.help_page = 2
    elseif self.screen == "help" and self.help_page == 2
        and (key == gfx.KEY_UP or key == gfx.KEY_LEFT or key == KEY.W or key == KEY.A) then
        self.help_page = 1
    else
        self.screen = self.help_back or "map"
    end
end

function Game:draw_help(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    local page = self.help_page or 1
    gfx.text(6, 16, page == 1 and "Keys" or "Tips")
    gfx.font(gfx.FONT_MONO_12)
    local y = 36
    for _, row in ipairs(Game.help_rows(page)) do
        if page == 2 then   -- (no label column: the tips are long)
            gfx.text(6, y, row[2])
        else
            if row[1] ~= "" then y = y + 3 end
            gfx.text(6, y, row[1])
            gfx.text(62, y, row[2])
        end
        y = y + 15
    end
    gfx.text(6, h - 8, (page == 1 and "Dn: tips" or "Up: keys") .. "  any key: back  V: device info")
    gfx.refresh()
end

-- Every gfx call is an event the firmware drains 24 at a time, once per app
-- tick (25 ms by default): ~960 calls a second, so a 900-call screen took
-- most of a second to appear. solaros.tick_interval asks for faster ticks;
-- the main loop turns them on only while a frame is being drawn, so the
-- board idles as before. Firmware without it keeps the old speed.
Game.DRAW_TICK_MS = 2

function Game.draw_pump(on)
    local set = solaros.tick_interval
    if not set then return false end
    return (pcall(set, on and Game.DRAW_TICK_MS or 0))
end

-- What the game sees of the device, one line each.
function Game:device_lines()
    local st = solaros.storage
    local lines = {
        "Game " .. Game.VERSION,
        (_VERSION or "Lua ?") .. ", memory " .. math.floor(collectgarbage("count")) .. " KB",
        ("Screen %dx%d"):format(gfx.size()),
    }
    local clock = solaros.time and solaros.time.uptime_ms
    lines[#lines + 1] = "Uptime " .. (clock and (math.floor(clock() / 1000) .. " s") or "unknown")
    if st then
        local ok, root = pcall(function() return st.mount_point and st.mount_point() end)
        lines[#lines + 1] = "Storage " .. (ok and tostring(root) or "error: " .. tostring(root))
    else
        lines[#lines + 1] = "Storage: no solaros.storage"
    end
    lines[#lines + 1] = "Can save: " .. (SAVE.can_write() and "yes (write_file)" or "no (needs SolarOS 4.15.17+)")
    local _, path = SAVE.path()
    if path and st and st.exists then
        local ok, there = pcall(st.exists, path)
        lines[#lines + 1] = "Save " .. path .. ": " .. (ok and (there and "found" or "none") or "error")
    end
    lines[#lines + 1] = ("World seed %d, hour %d, %s"):format(self.world_seed or 0, self.player.hours,
        DIFFICULTY[self.difficulty or "normal"].name)
    lines[#lines + 1] = "Fast drawing: " .. (solaros.tick_interval
        and ("yes (" .. Game.DRAW_TICK_MS .. " ms ticks while drawing)") or "no (older firmware)")
    lines[#lines + 1] = "Audio: " .. ((solaros.audio and solaros.audio.tone) and "tone ok" or "none")
    return lines
end

function Game:draw_info(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Device info")
    gfx.font(gfx.FONT_MONO_12)
    local y = 40
    for _, line in ipairs(self:device_lines()) do
        gfx.text(6, y, line:sub(1, 56))
        y = y + 16
    end
    gfx.text(6, h - 8, "Any key: back")
    gfx.refresh()
end
