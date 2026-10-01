-- ---------------------------------------------------------------------
-- Help (H) and device info (V on the help screen)
--
-- The map's hint line has room for only a few keys; H lists them all. The
-- info page is for testing on a new board: what the game sees of SolarOS.
-- ---------------------------------------------------------------------

Game.VERSION = "0.10 (2026-10-01)"

local HELP = {
    {"MAP", "Arrows/WASD move    Space rest 4h"},
    {"", "F search   E water: fill/drink   I bag"},
    {"", "T trade/Checkpoint   C craft   J journal"},
    {"", "G hunt, or fish   R radio   M sound"},
    {"BAG", "Arrows pick  Enter select, Enter move"},
    {"", "E use: eat, drink, wear, read, set snare"},
    {"CRAFT", "Up/Dn pick  Enter make  C/Q back"},
    {"TRADE", "Lt/Rt side  Enter +1  E -1  T deal  O work"},
    {"FIGHTS", "Up/Dn pick  Enter choose"},
    {"PUZZLE", "Arrows move  T+arrow throw  1-4 sigils"},
    {"", "Q backs away from a puzzle unharmed"},
    {"TIPS", "Shelter in ruins/hills from emissions."},
    {"", "3 artifacts or a permit get you out."},
    {"", "Karl fishes rivers. Strays like food."},
    {"", "C in a ruin: claim it as your camp."},
}

function Game:open_help()
    self.help_back = self.screen
    self.screen = "help"
end

function Game:help_key(key)   -- help, info and journal: any key goes back
    if self.screen == "help" and key == KEY.V then
        self.screen = "info"
    else
        self.screen = self.help_back or "map"
    end
end

function Game:draw_help(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Keys")
    gfx.font(gfx.FONT_MONO_12)
    local y = 36
    for _, row in ipairs(HELP) do
        if row[1] ~= "" then y = y + 3 end
        gfx.text(6, y, row[1])
        gfx.text(62, y, row[2])
        y = y + 15
    end
    gfx.text(6, h - 8, "Any key: back   V: device info")
    gfx.refresh()
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
    lines[#lines + 1] = "Can save: " .. (SAVE.can_write() and "yes (write_file)" or "no (needs the firmware patch)")
    local _, path = SAVE.path()
    if path and st and st.exists then
        local ok, there = pcall(st.exists, path)
        lines[#lines + 1] = "Save " .. path .. ": " .. (ok and (there and "found" or "none") or "error")
    end
    lines[#lines + 1] = ("World seed %d, hour %d, %s"):format(self.world_seed or 0, self.player.hours,
        DIFFICULTY[self.difficulty or "normal"].name)
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
