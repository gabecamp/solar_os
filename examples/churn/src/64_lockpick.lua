-- ---------------------------------------------------------------------
-- Lockpicking (numbers in CHURN.pick, 08_data_churn): every locked crate is
-- a small game now. Pins, one at a time, left to right. Up raises the pin a
-- notch, Down lowers it, Enter tries to set it. At the right height you
-- may feel it give - or feel nothing. One notch too far, or Enter at the
-- wrong height, strains the pick and drops the pin; strain it too often and
-- it snaps. Q backs off and leaves the crate locked for another try.
-- self.lock = {pins, i, h, strain, set, msg, done} (not saved).
-- done(game) runs when the last pin sets.
-- ---------------------------------------------------------------------

function Game:lock_start(npins, done, back)
    local P = CHURN.pick
    local pins = {}
    for i = 1, npins do pins[i] = 1 + self:rand(P.height) end
    self.lock = {pins = pins, i = 1, h = 0, strain = 0, done = done, back = back or "map",
                 msg = "You slide the pick in. Up raises the first pin."}
    self.screen = "lockpick"
end

function Game:lock_hint_chance()
    local P = CHURN.pick
    return P.hint + P.hint_per * (self.player.attrs.Perception - 3) + self:skill_bonus("tinker")
end

function Game:lock_strain(text)
    local L = self.lock
    L.strain, L.h = L.strain + 1, 0
    if L.strain >= CHURN.pick.strain_max then
        self:take_items("lockpicks", 1)
        self:sfx("miss")
        self:push_log("The pick snaps in the lock. The crate stays shut.")
        L.msg, L.over = "SNAP. The pick breaks off in the lock. (any key)", true
        return
    end
    L.msg = text .. " The pin drops."
end

function Game:lockpick_key(key)
    local L = self.lock
    if not L then self.screen = "map" return end
    if L.over then
        self.lock = nil
        self.screen = L.back
        return
    end
    if key == KEY.Q or key == gfx.KEY_ESCAPE then
        self:push_log("You leave the lock for now. Come back to try again.")
        self.lock = nil
        self.screen = L.back
        return
    end
    local target = L.pins[L.i]
    if key == gfx.KEY_UP or key == KEY.W then
        L.h = L.h + 1
        if L.h > target then
            return self:lock_strain("Too far - the spring bites back.")
        end
        L.msg = (L.h == target and self:roll(self:lock_hint_chance())) and "Something gives, just slightly."
            or ("Notch " .. L.h .. ". Nothing.")
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        L.h = math.max(0, L.h - 1)
        L.msg = "You ease it down. Notch " .. L.h .. "."
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        if L.h ~= target then return self:lock_strain("It slips.") end
        self:sfx("hit")
        L.i, L.h = L.i + 1, 0
        if L.i > #L.pins then
            self:skill_xp("tinker", SKILLS.xp.repair)
            self:sfx("gift")
            L.msg, L.over = "Click. The lock turns. (any key)", true
            L.done(self)
            return
        end
        L.msg = "Click. Pin " .. (L.i - 1) .. " is set. On to the next."
    end
end

function Game:draw_lockpick(w, h)
    local L, P = self.lock, CHURN.pick
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Picking the lock")
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(w - 6 - 7 * 12, 16, ("Strain %d/%d"):format(L.strain, P.strain_max))
    -- the lock: a shear line across, a column per pin
    local x0, base, notch, col = 60, 200, 22, 46
    local top = base - P.height * notch
    gfx.rect(x0 - 10, top - 30, col * #L.pins + 10, P.height * notch + 50)
    for i = 1, #L.pins do
        local x = x0 + (i - 1) * col
        local hh = i < L.i and L.pins[i] or i == L.i and L.h or 0
        gfx.color(gfx.LIGHT)
        gfx.fill_rect(x, top, 24, P.height * notch)
        gfx.color(gfx.BLACK)
        gfx.fill_rect(x + 4, base - hh * notch - 30, 16, 30)   -- the pin
        if i < L.i then gfx.text(x + 4, base + 13, "set") end  -- (under its column)
        if i == L.i then gfx.rect(x - 3, top - 3, 30, P.height * notch + 6) end
    end
    -- the pick, under the current pin
    local px = x0 + (L.i - 1) * col + 12
    if L.i <= #L.pins then gfx.line(20, base + 12, px, base - L.h * notch + 2) end
    for i, line in ipairs(wrap(L.msg or "", 55)) do
        if i <= 3 then gfx.text(6, 250 + 13 * (i - 1), line) end
    end
    gfx.text(6, h - 8, L.over and "Any key: back" or "Up/Dn move pin  Enter set  Q leave it")
    gfx.refresh()
end
