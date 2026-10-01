-- ---------------------------------------------------------------------
-- Night horrors (NIGHT in 05_data_world). Only after dark, never in the normal
-- encounter pick: maybe_horror runs on each move at night with its own
-- chance, halved by light in your hand or a fire on the hex, and never at a
-- camp with a bedroll.
--   The Long Man: look away (safe, costs rest), run, or speak to it.
--   The Crawler: a fight; without light your blows only half land, and a
--     torch at close range can drive it off.
--   The Whisperers: cover your ears, or follow the voice.
-- ---------------------------------------------------------------------

function Game:horror_chance()
    if not self:is_night() or self:bed_here() then return 0 end
    local chance = NIGHT.chance
    if self:has_light() then chance = chance / 2 end
    if self:fire_here() then chance = chance / 2 end
    return chance
end

function Game:maybe_horror()
    if not self:roll(self:horror_chance()) then return false end
    local def = NIGHT.horrors[self:rand(#NIGHT.horrors) + 1]
    self:start_encounter(def)
    self:sfx("emission")
    return true
end

-- Options for the two that don't fight.
function Game:horror_options(e)
    if e.def.horror == "long_man" then
        return {{"Look away", "look_away"}, {"Run", "flee"}, {"Speak to it", "speak"}}
    end
    return {{"Cover your ears", "cover"}, {"Follow the voice", "follow"}}
end

function Game:horror_action(action)
    local p, e = self.player, self.enc
    if action == "look_away" then
        p.needs.rest = clamp(p.needs.rest - NIGHT.dread_rest)
        self:enc_say("You stare at your boots until your eyes water. When you look up, the "
            .. "edge of the light is empty. You don't sleep well after that.")
        return self:end_encounter("It was gone when you looked up.")
    elseif action == "speak" then
        if self:roll(50) then
            local item = ARTIFACTS[self:rand(#ARTIFACTS) + 1]
            self:put_stack("ground", nil, {item = item, qty = 1})
            self:enc_say("It bends down, and down, and puts something in the grass at your feet. "
                .. "Then it isn't there.")
            return self:end_encounter("It left you a " .. ITEM_DB[item].name .. ".")
        end
        p.health = clamp(p.health - NIGHT.madness_hurt)
        self:enc_say("It answers. You don't remember what it said. Your nose is bleeding and "
            .. "your hands won't stop shaking. (-" .. NIGHT.madness_hurt .. " HP)")
        self:end_encounter("You spoke to it. You wish you hadn't.")
        return self:check_death("Something answered you in the dark.")
    elseif action == "cover" then
        p.needs.rest = clamp(p.needs.rest - NIGHT.whisper_rest)
        self:enc_say("You press your hands over your ears and hum until dawn. They know your "
            .. "name. They'll know it tomorrow too.")
        return self:end_encounter("You didn't listen to the river.")
    elseif action == "follow" then
        if self:roll(40 + 10 * (p.attrs.Perception - 3)) then
            self:mark_stash()
            self:enc_say("The voice leads you along the bank to a drowned man's pack. When you "
                .. "turn, the water is just water.")
            return self:end_encounter("The voices showed you something.")
        end
        p.health = clamp(p.health - NIGHT.follow_hurt)
        self:enc_say("You're waist-deep before you wake. Cold hands let go of your ankles. "
            .. "(-" .. NIGHT.follow_hurt .. " HP)")
        self:end_encounter("You nearly walked into the river.")
        return self:check_death("The river kept you.")
    end
end

-- The Crawler: blows in the dark only half land.
function Game:dark_damage(dmg)
    local e = self.enc
    if e and e.def.dark and not self:has_light() then return math.max(1, dmg // 2) end
    return dmg
end

-- The Crawler hates light: a torch at close range may drive it off.
function Game:dark_flees()
    local e = self.enc
    if not (e and e.def.dark and self:has_light() and e.range == "close") then return false end
    if not self:roll(NIGHT.light_drives_off) then return false end
    self:enc_say("You thrust the light at it. It shrieks and pours away into the dark.")
    e.outcome = "fled"
    self:end_encounter("The light drove it off.")
    return true
end
