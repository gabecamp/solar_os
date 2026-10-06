-- ---------------------------------------------------------------------
-- Scanning the band (the LoRa radio's last row; numbers in CHURN.scan).
-- A dial from low to high MHz: Left/Right turn it one MHz, Up/Down five.
-- Each day a few stations sit somewhere on it; the signal bar rises as you
-- come close, and Enter on the strongest listens (a charge). What they are:
--   stash - numbers that mark a stash on the map
--   body  - a churner calling for help from a ruin (you'll find them there)
--   site  - morse naming a place you didn't know yet
--   voice - something that shouldn't be on the air (dread)
-- A station heard is gone until tomorrow. self.scan = {day, stations} (saved).
-- ---------------------------------------------------------------------

-- Today's stations (made fresh each day).
function Game:scan_stations()
    local S, day = CHURN.scan, (self:clock())
    if self.scan and self.scan.day == day then return self.scan.stations end
    local list, used = {}, {}
    for _, f in ipairs(S.avoid) do used[f] = true end
    for _ = 1, S.n[1] + self:rand(S.n[2] - S.n[1] + 1) do
        local f
        repeat f = S.low + 2 + self:rand(S.high - S.low - 3) until not used[f]
        for d = -S.near, S.near do used[f + d] = true end   -- (never two on top of each other)
        local kind
        self.seed, kind = weighted_pick(self.seed, S.kinds)
        list[#list + 1] = {f = f, kind = kind}
    end
    self.scan = {day = day, stations = list}
    return list
end

-- How strong the nearest station is at frequency f: 0..near+1, and which.
function Game:scan_signal(f)
    local best, which = 0, nil
    for _, st in ipairs(self:scan_stations()) do
        local s = CHURN.scan.near + 1 - math.abs(st.f - f)
        if not st.heard and s > best then best, which = s, st end
    end
    return best, which
end

function Game:scan_start()
    self.radio_ui.scan = {f = CHURN.scan.low + (CHURN.scan.high - CHURN.scan.low) // 2,
                          msg = "Left/Right tune. Enter on a signal listens."}
end

function Game:scan_key(key)
    local u, S = self.radio_ui.scan, CHURN.scan
    if key == KEY.Q or key == gfx.KEY_ESCAPE then
        self.radio_ui.scan = nil
        return
    end
    local step = (key == gfx.KEY_LEFT or key == KEY.A) and -1 or (key == gfx.KEY_RIGHT or key == KEY.D) and 1
        or (key == gfx.KEY_DOWN or key == KEY.S) and -5 or (key == gfx.KEY_UP or key == KEY.W) and 5 or nil
    if step then
        u.f = math.max(S.low, math.min(S.high, u.f + step))
        local s = self:scan_signal(u.f)
        u.msg = s == 0 and S.static[self:rand(#S.static) + 1]
            or s > S.near and "A clear signal! (Enter: listen)" or "Something, faint. Closer..."
        return
    end
    if key ~= KEY.ENTER and key ~= KEY.LF and key ~= KEY.SPACE then return end
    local s, st = self:scan_signal(u.f)
    if s <= S.near then
        u.msg = "Nothing clear enough to listen to."
        return
    end
    if self.radio.charge <= 0 then
        u.msg = "Dead air. The radio needs a Battery Cell."
        return
    end
    if not (self:at_base() and self:camp_stack("mast")) then self.radio.charge = self.radio.charge - 1 end
    st.heard = true
    u.msg = self:scan_listen(st.kind)
end

-- What a station turns out to be.
function Game:scan_listen(kind)
    local S, p = CHURN.scan, self.player
    if kind == "site" then
        for _, site in ipairs({"quarry", "checkpoint", "ferry", "trader"}) do
            if self.sites[site] and self:learn_site(site) then
                self:push_log("Morse on the radio: a place, " .. self:site_bearing(site) .. ".")
                return S.site .. " (" .. site .. ", " .. self:site_bearing(site) .. ")"
            end
        end
        kind = "stash"   -- (you know them all: it's numbers after all)
    end
    if kind == "stash" then
        if self:mark_stash() then return S.numbers end
        return "Numbers, then a long tone. Whatever it marks, you've found."
    elseif kind == "body" then
        local key = self:quest_spot(3, 8, false)
        if not key then return "A voice, breaking up. Too far to make out." end
        self.radio_body = key
        p.explored[key] = true
        self:push_log("A call for help on the radio: " .. self:bearing_to(key) .. ".")
        return S.body .. " (" .. self:bearing_to(key) .. ")"
    end
    self:dread(CHURN.dread.voice)
    self:sfx("emission")
    return S.voice[self:rand(#S.voice) + 1]
end

function Game:draw_scan(w, h)
    local u, S = self.radio_ui.scan, CHURN.scan
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Scanning the band")
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(250, 16, ("Charge %d/%d"):format(self.radio.charge, TECH.radio_max))
    gfx.line(6, 22, w - 6, 22)
    -- the dial: ticks every 5 MHz, the needle at f
    local x0, x1, y = 20, w - 20, 90
    gfx.line(x0, y, x1, y)
    for f = S.low, S.high, 5 do
        local x = x0 + (x1 - x0) * (f - S.low) // (S.high - S.low)
        gfx.line(x, y - (f % 10 == 0 and 8 or 4), x, y)
        if f % 10 == 0 then gfx.text(x - 10, y + 16, tostring(f)) end
    end
    local nx = x0 + (x1 - x0) * (u.f - S.low) // (S.high - S.low)
    gfx.fill_rect(nx - 1, y - 24, 3, 30)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(w // 2 - 40, 50, u.f .. " MHz")
    gfx.font(gfx.FONT_MONO_12)
    -- the signal: a bar of five
    local s = self:scan_signal(u.f)
    gfx.text(20, 140, "Signal")
    for i = 1, S.near + 1 do
        local bx = 80 + (i - 1) * 22
        if i <= s then gfx.fill_rect(bx, 140 - 4 * i, 16, 4 * i) else gfx.rect(bx, 140 - 4 * i, 16, 4 * i) end
    end
    for i, line in ipairs(wrap(u.msg or "", 55)) do
        if i <= 4 then gfx.text(6, 180 + 14 * (i - 1), line) end
    end
    gfx.text(6, h - 8, "Lt/Rt tune  Up/Dn x5  Enter listen  Q back")
    gfx.refresh()
end

-- Stepping onto the hex a voice called from: too late, but what they had is yours.
function Game:scan_arrive()
    local key = hex_key(self.player.q, self.player.r)
    if self.radio_body ~= key then return false end
    self.radio_body = nil
    local C, found = CHURN.corpse, {}
    for _ = 1, 2 do
        local item
        self.seed, item = weighted_pick(self.seed, C.loot)
        found[#found + 1] = self:drop_found(item, C.rounds[item] and C.rounds[item] + self:rand(3))
    end
    self:dread(CHURN.dread.corpse)
    self:push_log("The one who called. The radio in their hand is still on.")
    self:push_log("On them: " .. table.concat(found, ", ") .. ".")
    self:note_find(key, "corpse", "The voice on the radio", found)
    return false
end
