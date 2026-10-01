-- ---------------------------------------------------------------------
-- Broken tech and the LoRa radio (numbers in TECH, 05_data_world)
--
-- Broken devices are very rare finds. While you carry one, the crafting
-- screen lists "Repair <device>": its parts and the device itself are the
-- inputs, a Multitool the tool. A repair takes hours and can fail - then a
-- part burns out and the device stays broken.
--   LoRa Radio: R on the map; each call costs a charge (Battery Cell: E to
--     recharge) and each voice needs time before it answers again.
--   Anomaly Detector: carried, it reads rads TECH.detector_range hexes out.
--   Headlamp: worn, light at night (ITEM_DB[..].light; see has_light).
-- self.radio = {charge, next = {channel id -> hour}} is saved.
-- ---------------------------------------------------------------------

-- Repair "recipes" for the broken devices you carry (crafting screen).
function Game:repair_recipes()
    local list = {}
    for _, fix in ipairs(TECH.repairs) do
        if self:count_item(fix.broken) > 0 then
            local inputs = {[fix.broken] = 1}
            for part, n in pairs(fix.parts) do inputs[part] = n end
            list[#list + 1] = {id = "repair_" .. fix.broken, name = "Repair " .. ITEM_DB[fix.out].name,
                               inputs = inputs, tools = {TECH.tool}, hours = TECH.repair_hours,
                               out = {fix.out, 1}, repair = fix}
        end
    end
    return list
end

function Game:repair_chance(fix)
    return math.max(5, math.min(95, fix.base + TECH.per_point * (self.player.attrs.Perception - 3)
                                    + self:skill_bonus("tinker")))
end

-- Called by Game:craft for a repair recipe (after craft_blocker passed).
function Game:repair(r)
    local p, fix, hours = self.player, r.repair, self:craft_hours(r)
    p.hours = p.hours + hours
    apply_awake_hours(p, hours)
    local chance = self:repair_chance(fix)
    self:skill_xp("tinker", SKILLS.xp.repair)
    if self:roll(chance) then
        self:skill_xp("tinker", SKILLS.xp.repaired)
        self:stat("repairs")
        for _, iq in ipairs(Game.recipe_inputs(r)) do self:take_items(iq[1], iq[2]) end
        local stack = {item = fix.out, qty = 1}
        if not self:put_stack("inventory", nil, stack) then self:put_stack("ground", nil, stack) end
        if fix.out == "lora_radio" and not self.radio then
            self.radio = {charge = TECH.radio_start, next = {}}
        end
        self:sfx("gift")
        self:push_log("It hums back to life: " .. ITEM_DB[fix.out].name .. "!")
    else
        local parts = {}
        for part in pairs(fix.parts) do parts[#parts + 1] = part end
        table.sort(parts)
        local lost = parts[self:rand(#parts) + 1]
        self:take_items(lost, 1)
        self:sfx("miss")
        self:push_log("It sparks and dies again. Lost a " .. ITEM_DB[lost].name .. ".")
    end
    return true
end

-- E on a Battery Cell while you have the radio.
function Game:charge_radio()
    if not (self:carrying("lora_radio") and self.radio) then return false end
    if self.radio.charge >= TECH.radio_max then
        self:push_log("The radio is fully charged already.")
        return false
    end
    self.radio.charge = TECH.radio_max
    self:push_log("The radio's charge light goes green. (" .. TECH.radio_max .. " calls)")
    return true
end

-- R on the map.
function Game:open_radio()
    if not self:carrying("lora_radio") then
        self:push_log("You have no working radio.")
        return
    end
    self.radio = self.radio or {charge = TECH.radio_start, next = {}}
    self.radio_ui = {cursor = 1, msg = {"Static. Pick a frequency."}}
    self.screen = "radio"
end

function Game:radio_say(text)
    self.radio_ui.msg = wrap(text, 54)
end

-- The nearest pile with an artifact in it, as a tile key (or nil).
function Game:nearest_artifact()
    local p, best, best_d = self.player, nil, nil
    for key, pile in pairs(self.ground) do
        for _, s in ipairs(pile) do
            if ITEM_DB[s.item].artifact then
                local q, r = key:match("(-?%d+),(-?%d+)")
                local d = axial_distance(p.q, p.r, tonumber(q), tonumber(r))
                if d > 0 and (not best or d < best_d or (d == best_d and key < best)) then
                    best, best_d = key, d
                end
            end
        end
    end
    return best
end

-- Each voice. Returns true if the call went through (it costs a charge).
local RADIO = {}
function RADIO.trader(self)
    self:learn_site("trader")
    local told = self:hear_of_exit("Trader")
    local parcel = self:mark_stash()
    if not (told or parcel) then
        self:radio_say("'Trader here. Nothing for you today, friend. Try me later.'")
        return false
    end
    self:radio_say("'Trader here. "
        .. (parcel and "Left a parcel for you, friend. Bearing's in your notes." or "")
        .. (told and " And the way out's open, if you've got paper.'" or "'"))
    return true
end
function RADIO.anna(self)
    local work = self:anna_work()
    if work == "offered" then return false end   -- free: she only asked
    if work then return work end
    local p = self.player
    if p.health >= MAX_HEALTH and not p.injuries.bleeding and p.injuries.wounded_hours == 0 then
        self:radio_say("Anna: 'You sound fine, love. Call me when it hurts.'")
        return false
    end
    p.health = clamp(p.health + 20)
    p.injuries.bleeding = false
    p.injuries.wounded_hours = math.max(0, p.injuries.wounded_hours - 12)
    self:radio_say("Anna talks you through it, calm and slow: press here, tie that, breathe. "
        .. "(+20 HP, bleeding stopped)")
    return true
end
function RADIO.karl(self)
    local hours = (self.next_emission or 0) - self.player.hours
    local when = hours > 0 and ("Next blowout in about " .. hours .. "h.") or "Blowout's overdue."
    self.karl_hint = true
    self:radio_say("'Karl here. With a K. Fish bite at dusk, son. " .. when
        .. " And next time we meet, I'll go easy on you.' (a hint on his next riddle)")
    return true
end
function RADIO.signal(self)
    local p = self.player
    if not self.signal_page then   -- the first time, it reads you something
        self.signal_page = true
        self:read_lore("The Signal")
    end
    p.rads = math.min(RAD.max, (p.rads or 0) + TECH.signal_rads)
    self:sfx("emission")
    local key = self:nearest_artifact()
    if not key then
        self:radio_say("Numbers, read by a voice that isn't a voice. Then your own name. Nothing else.")
        return true
    end
    p.explored[key] = true
    self:radio_say("Numbers, read by a voice that isn't a voice. You understand them: something "
        .. "waits " .. self:bearing_to(key) .. ". Your teeth ache."
        .. (self:can_measure() and (" (+" .. TECH.signal_rads .. " rads)") or ""))
    return true
end

function Game:radio_call(i)
    local ch, r = TECH.channels[i], self.radio
    if not ch then return end
    local wait = (r.next[ch.id] or 0) - self.player.hours
    if ch.id == "anna" and self:anna_ready() then wait = 0 end   -- she always takes the bandages
    if wait > 0 then
        self:radio_say(ch.name .. ": no answer. Try again in " .. wait .. "h.")
    elseif r.charge <= 0 then
        self:radio_say("Dead air. The radio needs a Battery Cell (E on one).")
    else
        local answered = RADIO[ch.id](self)
        if answered then
            r.charge = r.charge - 1
            -- "open": the voice stays reachable (Anna after you bring her bandages)
            r.next[ch.id] = answered ~= "open" and (self.player.hours + ch.cooldown) or nil
        end
    end
end

function Game:radio_key(key)
    local u = self.radio_ui
    if key == KEY.Q or key == gfx.KEY_ESCAPE or key == KEY.R then
        self.screen = "map"
    elseif key == gfx.KEY_UP or key == KEY.W then
        u.cursor = math.max(1, u.cursor - 1)
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        u.cursor = math.min(#TECH.channels, u.cursor + 1)
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        self:radio_call(u.cursor)
    end
end

function Game:draw_radio(w, h)
    local u, r = self.radio_ui, self.radio
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "LoRa Radio")
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(220, 16, ("Charge %d/%d"):format(r.charge, TECH.radio_max))
    gfx.line(6, 22, w - 6, 22)
    for i, ch in ipairs(TECH.channels) do
        local y = 44 + (i - 1) * 18
        local wait = (r.next[ch.id] or 0) - self.player.hours
        local status = wait > 0 and (wait .. "h") or "ready"
        if i == u.cursor then
            gfx.fill_rect(4, y - 12, w - 8, 16)
            gfx.color(gfx.WHITE)
        end
        gfx.text(10, y, ch.name)
        gfx.text(300, y, status)
        gfx.color(gfx.BLACK)
    end
    gfx.line(6, 126, w - 6, 126)
    for i, line in ipairs(u.msg) do gfx.text(6, 132 + 14 * i, line) end
    gfx.text(6, h - 8, "Up/Dn pick  Enter call  Q back")
    gfx.refresh()
end
