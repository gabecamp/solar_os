-- ---------------------------------------------------------------------
-- Time of day, weather, cold and light
--
-- The clock is derived from player.hours (see WORLD in 05_data). Weather is
-- rolled per WORLD.weather_block hours from the world's seed, so it needs no
-- state of its own. Game:tick() runs after every key: it walks the hours
-- that passed since the last tick and applies cold, then refreshes what you
-- can see (night shortens sight unless you hold a torch).
-- ---------------------------------------------------------------------

-- day (1..), hour (0..23) at `hours` into the run (default: now)
function Game:clock(hours)
    local total = WORLD.start_hour + (hours or self.player.hours)
    return total // 24 + 1, total % 24
end

function Game:is_night(hours)
    local _, hour = self:clock(hours)
    return hour >= WORLD.night_from or hour < WORLD.night_to
end

function Game:weather(hours)
    local block = (WORLD.start_hour + (hours or self.player.hours)) // WORLD.weather_block
    local s = (self.weather_seed + block * 7919) % 32768
    s = rand_next(rand_next(s))
    local _, kind = weighted_pick(s, WORLD.weather)
    return kind
end

-- Warmth from what you wear (not what you hold).
function Game:warmth()
    local total = 0
    for slot, item in pairs(self.player.equipped) do
        if not HOLD_SLOTS[slot] then total = total + (ITEM_DB[item].warmth or 0) end
    end
    return total
end

function Game:cold_need(hours)
    return WORLD.need[self:weather(hours)] + (self:is_night(hours) and WORLD.night_need or 0)
end

function Game:fire_at(hours)
    local camp = self.camps[hex_key(self.player.q, self.player.r)]
    return camp ~= nil and hours < camp.until_hour
end

function Game:is_cold(hours)
    hours = hours or self.player.hours
    return not self:fire_at(hours) and self:warmth() < self:cold_need(hours)
end

-- A lit torch in either hand.
function Game:has_light()
    local eq = self.player.equipped
    return eq.rhand == "torch" or eq.lhand == "torch"
end

-- Recompute what you can see: at night sight drops by one without light.
function Game:refresh_view()
    local p = self.player
    local dark = self:is_night() and not self:has_light()
    p.view_sight = math.max(1, p.sight - (dark and 1 or 0))
    update_visibility(p, self.tiles)
end

-- Apply the hours that passed since the last tick.
function Game:tick()
    local p = self.player
    self.ticked_hour = self.ticked_hour or p.hours
    local was_cold = (p.cold_hours or 0) > 0
    local rad_before, dose = self:rad_stage(), 0
    for hour = self.ticked_hour, p.hours - 1 do
        if self:is_cold(hour) then
            p.cold_hours = (p.cold_hours or 0) + 1
            p.needs.rest = clamp(p.needs.rest - WORLD.cold_rest_drain)
            if p.cold_hours > WORLD.cold_grace then
                p.health = clamp(p.health - WORLD.cold_hurt)
            end
        else
            p.cold_hours = 0
        end
        dose = dose + self:rad_hour()
    end
    self.ticked_hour = p.hours
    local cold = (p.cold_hours or 0) > 0
    if cold and not was_cold then
        self:push_log("You're cold. Wear warmer clothes or build a fire.")
    elseif cold and p.cold_hours == WORLD.cold_grace + 1 then
        self:push_log("The cold is getting into you. (-" .. WORLD.cold_hurt .. " HP/h)")
    end
    self:rad_news(dose, rad_before)
    self:geiger_scan()
    self:refresh_view()
    self:check_death(cold and "You froze to death." or "Radiation sickness took you.")
end
