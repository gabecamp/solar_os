-- ---------------------------------------------------------------------
-- Updates on open. Leaving the splash, if Wi-Fi is already up, the game
-- reads tools/version.json from GitHub (a few bytes, a few seconds at
-- most). A newer build adds "Update to x.y.z" to the title menu; picking it
-- downloads churn.lua the way churn_update.lua does: to churn.lua.new, a
-- chunk at a time, checked, then swapped in (the old one kept as .bak).
-- The running game stays the old one until you start it again (two copies
-- don't fit in memory). No Wi-Fi, no HTTP, nowhere to write, or no
-- churn.lua found: no check, and nothing changes. The save isn't touched.
-- ---------------------------------------------------------------------

Game.UPDATE = {
    base = "https://raw.githubusercontent.com/gabecamp/solar_os/main/examples/churn/",
    file = "churn.lua", version_file = "tools/version.json",
    check_ms = 4000, get_ms = 20000, chunk = 32768,
}

-- "0.13.10" newer than "0.13.9"? (number by number)
function Game.version_newer(a, b)
    local x, y = {}, {}
    for n in tostring(a):gmatch("%d+") do x[#x + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do y[#y + 1] = tonumber(n) end
    for i = 1, math.max(#x, #y) do
        if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) > (y[i] or 0) end
    end
    return false
end

-- Where this game's churn.lua is (the updater's search), or nil.
function Game.update_target()
    local st = solaros.storage
    local ok, root = pcall(st.mount_point)
    if not ok or type(root) ~= "string" or root == "" then root = "/flash" end
    for _, p in ipairs({root .. "/churn.lua", "/sdcard/churn.lua", "/flash/churn.lua",
                        root .. "/lua/churn.lua", root .. "/apps/churn.lua", root .. "/games/churn.lua"}) do
        local found, yes = pcall(st.exists, p)
        if found and yes then return p end
    end
    return nil
end

-- Worth asking GitHub? HTTP streaming, a storage that can write and
-- rename, Wi-Fi already connected (never started from here), the game file.
function Game.update_possible()
    local http, st, wifi = solaros.http, solaros.storage, solaros.wifi
    if not (http and http.stream_open and st and st.write_file and st.rename) then return false end
    if wifi and wifi.status then
        local ok, s = pcall(wifi.status)
        if not (ok and type(s) == "table" and s.has_ip) then return false end
    end
    return Game.update_target() ~= nil
end

-- GET url, handing each piece of the body to on_data(piece, length).
-- Returns the Content-Length (-1 if none), or nil and why.
function Game.update_get(url, timeout_ms, on_data)
    local http, h, length = solaros.http, nil, -1
    local ok, err = pcall(function()
        h = http.stream_open("GET", url, nil, nil, timeout_ms, true)
        while true do
            local ev = http.stream_read(h, timeout_ms)
            if ev == nil then error("the server stopped answering", 0) end
            if ev.type == "response" then
                if (ev.status_code or 0) ~= 200 then error("the server said " .. tostring(ev.status_code), 0) end
                length = ev.content_length or -1
            elseif ev.type == "data" then
                on_data(ev.data, length)
            elseif ev.type == "complete" then
                return
            elseif ev.type == "error" then
                error("download error " .. tostring(ev.error_name or ev.error), 0)
            end
        end
    end)
    if h then pcall(http.stream_close, h) end
    if not ok then return nil, tostring(err) end
    return length
end

-- Once a start-up: is there a newer build? Sets self.update_avail.
function Game:update_check()
    if self.update_checked or not Game.update_possible() then return end
    self.update_checked = true
    local U, parts = Game.UPDATE, {}
    local len = Game.update_get(U.base .. U.version_file, U.check_ms, function(d) parts[#parts + 1] = d end)
    if not len then return end
    local text = table.concat(parts)
    local series, build = text:match('"series"%s*:%s*"([%d.]+)"'), text:match('"build"%s*:%s*(%d+)')
    if not (series and build) then return end
    local latest = series .. "." .. build
    if Game.version_newer(latest, Game.VERSION:match("^%S+")) then self.update_avail = latest end
end

-- The progress picture (art: tools/paint_reach.py -> 38_reach_art): a
-- rotten arm crawls out of the left edge after a crow, its claws closing
-- on it as the download ends. The tip of the claws is at x = reach_tip
-- in the arm's picture.
Game.UPDATE.reach_tip, Game.UPDATE.reach_y = 364, 64

function Game:draw_update_progress(w, h, got, length)
    local U = Game.UPDATE
    local frac = length > 0 and math.min(1, got / length) or 0
    gfx.clear(gfx.WHITE)
    Game.ui_title(w, "Updating The Churn", self.update_avail)
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(10, 48, "Downloading the new version...")
    local cx, y = w - 70, U.reach_y
    local tip = 24 + math.floor(frac * (cx + 6 - 24))
    gfx.color(gfx.BLACK)
    gfx.line(0, y + 62, w, y + 62)   -- the ground
    if draw_sprite and Game.ARM_ART then
        for _, t in ipairs(Game.art_tiles("CROW_ART")) do draw_sprite(cx + t.x, y + t.y, 32, 32, t.data) end
        local ox = tip - U.reach_tip
        for _, t in ipairs(Game.art_tiles("ARM_ART")) do
            if ox + t.x + 32 > 0 then draw_sprite(ox + t.x, y + t.y, 32, 32, t.data) end
        end
    else   -- (no bitmaps: a plain bar)
        Game.ui_bar(10, y + 20, w - 20, 14, frac)
    end
    gfx.text(10, y + 84, length > 0 and ("%d of %d KB"):format(got // 1024, length // 1024)
        or ("%d KB"):format(got // 1024))
    gfx.text(10, y + 112, "Your save is safe. Don't switch off.")
    gfx.refresh()
end

-- Download the new churn.lua and swap it in. Sets self.update_msg either way.
function Game:update_download()
    local U, st = Game.UPDATE, solaros.storage
    local w, h = gfx.size()
    local target = Game.update_target()
    if not target then
        self.update_msg = "Update failed: can't find churn.lua."
        return false
    end
    local new, bak = target .. ".new", target .. ".bak"
    local buf, n, buffered, got, shown = {}, 0, 0, 0, -U.chunk
    local function flush()
        if n == 0 then return end
        st.write_file(new, table.concat(buf, "", 1, n), true)
        buf, n, buffered = {}, 0, 0
    end
    self:draw_update_progress(w, h, 0, -1)
    local ok, err = pcall(function()
        pcall(st.remove, new)
        st.write_file(new, "")
        local len, why = Game.update_get(U.base .. U.file, U.get_ms, function(d, length)
            got, buffered, n = got + #d, buffered + #d, n + 1
            buf[n] = d
            if buffered >= U.chunk then flush() end
            if got - shown >= U.chunk then
                shown = got
                self:draw_update_progress(w, h, got, length)
            end
        end)
        if not len then error(why, 0) end
        flush()
        local size = got
        if st.stat then
            local sok, info = pcall(st.stat, new)
            if sok and type(info) == "table" and info.size then size = info.size end
        end
        if len > 0 and size ~= len then error(("only %d of %d KB arrived"):format(size // 1024, len // 1024), 0) end
        local head = st.read_file(new, 256) or ""
        if size < 100000 or not head:find("The Churn", 1, true) then error("that wasn't churn.lua", 0) end
        if st.exists(target) then
            pcall(st.remove, bak)
            st.rename(target, bak)
        end
        local swapped, why2 = pcall(st.rename, new, target)
        if not swapped then
            if st.exists(bak) then pcall(st.rename, bak, target) end
            error("couldn't put it in place: " .. tostring(why2), 0)
        end
    end)
    collectgarbage("collect")
    if not ok then
        pcall(st.remove, new)
        self.update_msg = "Update failed: " .. tostring(err) .. ". Nothing changed."
        return false
    end
    self.update_msg = "Updated to " .. self.update_avail .. ". Quit (Q) and start the game again."
    self.update_avail = nil
    return true
end
