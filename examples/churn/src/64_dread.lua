-- ---------------------------------------------------------------------
-- Dread (numbers in CHURN.dread): what the Churn does to your mind, 0..100
-- on the player (p.dread, saved with the player). Horrors, emissions, the
-- dead, the dark and the wrong voices on the radio raise it. It fades on its
-- own (by day -0.75 an hour, at night a quarter of that, more at camp), and
-- faster with a rest (-3, by a fire -10, in your bed -20), the dog at your
-- side, a tape, vodka and a sedative.
--   Uneasy (35+): only the label.
--   Dread (60+): the Churn whispers in the log as you walk.
--   70+: now and then something is there that isn't - one action and it's gone.
--   Terror (85+): sleep does you half the good.
-- ---------------------------------------------------------------------

function Game:dread(n)
    local p = self.player
    p.dread = math.max(0, math.min(100, (p.dread or 0) + n))
end

-- The tier's name ("Uneasy"...), or nil below the first.
function Game:dread_name()
    local name
    for _, t in ipairs(CHURN.dread.tiers) do
        if (self.player.dread or 0) >= t[1] then name = t[2] end
    end
    return name
end

-- One hour (from tick): the dark gets in. Otherwise the mind settles on its
-- own, by day faster than at night (a light or a fire at night counts), and
-- faster at camp; the dog helps too.
function Game:dread_hour(hour)
    local D = CHURN.dread
    local night = self:is_night(hour)
    if night and not self:has_light() and not self:fire_at(hour) and not self:at_base() then
        self:dread(D.dark_hour)
    else
        self:dread(night and D.night_ease or D.day_ease)
    end
    if self:dog_with_you() and hour % D.dog_hours == 0 then self:dread(-1) end
    if self:at_base() then self:dread(D.camp_hour) end
end

-- After a move (from try_move): a whisper, or a phantom. True if a phantom
-- encounter started.
function Game:dread_move()
    local D, d = CHURN.dread, self.player.dread or 0
    if d >= 70 and self:roll(D.phantom) then
        local base = NIGHT.horrors[self:rand(#NIGHT.horrors) + 1]
        local def = {}
        for k, v in pairs(base) do def[k] = v end
        def.phantom = true
        self:start_encounter(def)
        return true
    end
    if d >= 60 and self:roll(D.whisper) then
        self:push_log(D.lines[self:rand(#D.lines) + 1])
    end
    return false
end

-- Any action against a phantom: there's nothing there.
function Game:phantom_gone()
    self:dread(-5)
    self:enc_say("You blink. There's nothing there. There was never anything there.")
    self:end_encounter("It was nothing. Was it?")
end
