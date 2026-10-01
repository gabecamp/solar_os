-- ---------------------------------------------------------------------
-- A dog companion (numbers in DOG, 05_data_world)
--
-- A rare stray turns up on plains/forest while you have no dog. Offer it
-- food to tame it (self.dog, saved). It warns you (better hiding and
-- running), bites in fights, sometimes takes a blow meant for you, and
-- eats from your bag once a day - after DOG.leave_after hungry days it
-- leaves. If it dies, it's gone.
-- ---------------------------------------------------------------------

function Game:maybe_dog()
    local p = self.player
    if self.dog or not DOG.terrain[self.tiles[hex_key(p.q, p.r)]] then return false end
    if not self:roll(DOG.chance) then return false end
    self:start_encounter({kind = "dog", name = "Stray Dog", art = "stray", who = "dog",
                          intro = DOG.intro, start = "near"})
    self:sfx("bark")
    return true
end

-- The first food in the bag the dog would eat (DOG.eats, in order).
function Game:dog_food()
    for _, item in ipairs(DOG.eats) do
        for i, s in ipairs(self.player.inventory) do
            if s.item == item then return i, item end
        end
    end
end

function Game:dog_tame()
    local i, item = self:dog_food()
    if not i then return end
    local s = self.player.inventory[i]
    s.qty = s.qty - 1
    if s.qty <= 0 then table.remove(self.player.inventory, i) end
    local meat = item:find("meat") or item:find("fish") or item == "jerky"
    if self:roll(DOG.tame + (meat and DOG.meat_bonus or 0)) then
        self.dog = {hp = DOG.hp, fed_hour = self.player.hours, hungry_days = 0}
        self:sfx("bark")
        self:enc_say("It wolfs down the " .. ITEM_DB[item].name:lower()
            .. ", then sits by your boot and looks up at you. You have a dog.")
        self:end_encounter("A stray dog follows you now.")
    else
        self:enc_say("It snatches the " .. ITEM_DB[item].name:lower() .. " and bolts into the grass.")
        self:end_encounter("The stray ran off with your food.")
    end
end

-- Hide/flee bonus while the dog is with you.
function Game:dog_bonus()
    return self.dog and DOG.warn_bonus or 0
end

-- In a fight, the dog's turn: maybe a bite. Returns true if the fight ended.
function Game:dog_turn()
    local e = self.enc
    if not self.dog or e.over or e.range ~= "close" then return false end
    if self:roll(DOG.bite_chance) then
        local dmg = DOG.bite[1] + self:rand(DOG.bite[2] - DOG.bite[1] + 1)
        self:enc_hit(dmg, nil, "Your dog bites the " .. e.def.who)
    end
    return e.over
end

-- The dog jumps in front of a blow. Returns true if it took it.
function Game:dog_guard(dmg)
    if not self.dog or not self:roll(DOG.guard) then return false end
    local dog = self.dog
    dog.hp = dog.hp - dmg
    if dog.hp <= 0 then
        self.dog = nil
        self:sfx("whine")
        self:enc_say("Your dog throws itself in the way. It doesn't get up.")
        self:push_log("Your dog died protecting you.")
    else
        self:enc_say(("Your dog takes the blow for you (-%d)."):format(dmg))
    end
    return true
end

-- One hour passing: a slow heal, and a meal once a day.
function Game:dog_hour(hour)
    local dog = self.dog
    if not dog then return end
    if hour % 6 == 0 and dog.hp < DOG.hp then dog.hp = dog.hp + 1 end
    if hour - dog.fed_hour < DOG.meal_hours then return end
    dog.fed_hour = hour
    local i, item = self:dog_food()
    if i then
        local s = self.player.inventory[i]
        s.qty = s.qty - 1
        if s.qty <= 0 then table.remove(self.player.inventory, i) end
        dog.hungry_days = 0
        self:push_log("Your dog eats the " .. ITEM_DB[item].name:lower() .. ".")
    else
        dog.hungry_days = dog.hungry_days + 1
        if dog.hungry_days >= DOG.leave_after then
            self.dog = nil
            self:sfx("whine")
            self:push_log("Your dog is gone. Too long without food.")
        else
            self:push_log("Your dog is hungry. Nothing in the bag it can eat.")
        end
    end
end
