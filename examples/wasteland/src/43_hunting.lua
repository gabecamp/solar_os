-- ---------------------------------------------------------------------
-- Hunting, fishing and snares (numbers in HUNT, 05_data)
--
-- G on the map: by open water (or on a ford) with a Fishing Rod you fish;
-- anywhere else you track game, and finding it starts an animal encounter
-- in which you've already studied it. E on a Snare sets it on your hex
-- (self.snares, saved); stepping back onto it collects whatever it caught
-- since, worked out then from the hours that passed.
-- ---------------------------------------------------------------------

function Game:gather()
    local p = self.player
    if p.mp <= 0 then
        self:push_log("Too tired. Rest first.")
        return
    end
    if self:near_water() and self:carrying("fishing_rod") then return self:fish() end
    local terrain = self.tiles[hex_key(p.q, p.r)]
    if not HUNT.snare_chance[terrain] then
        self:push_log(self:near_water() and "No rod to fish with. (C to make one)" or "No game here.")
        return
    end
    self:hunt()
end

-- Time passes as for a search: MP, hours, needs.
function Game:spend_hours(n)
    local p = self.player
    p.mp = p.mp - 1
    p.hours = p.hours + n
    apply_awake_hours(p, n)
end

function Game:fish()
    local p = self.player
    self:spend_hours(HUNT.fish_hours)
    if self:roll(HUNT.fish_chance + 5 * (p.attrs.Perception - 3) + self:fish_bonus()) then
        local fish = {item = "raw_fish", qty = 1}
        if not self:put_stack("inventory", nil, fish) then self:put_stack("ground", nil, fish) end
        self:push_log("A pale fish, too many eyes. Got it.")
    else
        self:push_log(("Fished %dh. Nothing bites."):format(HUNT.fish_hours))
    end
    self:maybe_karl("fish")
end

function Game:hunt()
    local p = self.player
    self:spend_hours(HUNT.hunt_hours)
    if not self:roll(HUNT.hunt_chance + 10 * (p.attrs.Perception - 3)) then
        self:push_log(("Tracked %dh. Nothing but old prints."):format(HUNT.hunt_hours))
        return
    end
    local animals = ENCOUNTERS_BY_KIND.animal
    self:start_encounter(animals[self:rand(#animals) + 1])
    -- you found it first: it hasn't seen you, and you've watched how it moves
    self.enc.seen, self.enc.aim = true, FIGHT.WATCH_AIM
    self:enc_say("You found its trail and crept up downwind. It hasn't seen you yet.")
end

-- E on a Snare. Returns true if it was set (the caller uses one up).
function Game:set_snare()
    local p = self.player
    local key = hex_key(p.q, p.r)
    if not HUNT.snare_chance[self.tiles[key]] then
        self:push_log("Nothing would walk into a snare here.")
        return false
    end
    if self.snares[key] then
        self:push_log("There's already a snare here.")
        return false
    end
    self.snares[key] = {set = p.hours}
    self:push_log("Snare set. Come back later.")
    return true
end

-- Stepping onto a hex with your snare.
function Game:check_snare()
    local p = self.player
    local key = hex_key(p.q, p.r)
    local snare = self.snares[key]
    if not snare then return end
    local hours = p.hours - snare.set
    local per_hour = (HUNT.snare_chance[self.tiles[key]] or 0) / 100
    local pct = math.floor(100 * (1 - (1 - per_hour) ^ hours))
    if hours > 0 and self:roll(pct) then
        self:put_stack("ground", nil, {item = HUNT.snare_catch[1], qty = HUNT.snare_catch[2]})
        snare.set = p.hours
        self:push_log("Your snare caught a two-headed hare. (I to take it)")
    else
        self:push_log("Your snare is empty.")
    end
end
