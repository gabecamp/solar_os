-- ---------------------------------------------------------------------
-- Water and the survival loop
--
-- Bottles are containers (ITEM_DB[..].empty): drinking leaves an Empty
-- Bottle where the full one was. E on the map by a river or on a ford fills
-- every empty bottle you carry with Dirty Water, or with none you drink
-- straight from it. Resting in the rain fills them clean; the Boil Water
-- recipe cleans dirty water at a fire. Some food and water can make you
-- sick (ITEM_DB[..].sick), meat goes bad (perish), and at 0 thirst or
-- hunger you lose HP every hour. Numbers are in SURVIVE (05_data_world).
-- ---------------------------------------------------------------------

-- After eating/drinking one unit of def (the stack was at kind/k):
-- the empty container, and maybe sickness.
function Game:after_consume(def, kind, k)
    local p = self.player
    if def.empty then
        local empty = {item = def.empty, qty = 1}
        if kind == "equip" and p.equipped[k] == nil then
            p.equipped[k] = def.empty                       -- still in your hand
        elseif not self:put_stack("inventory", nil, empty) then
            self:put_stack("ground", nil, empty)
        end
    end
    if def.sick and self:roll(def.sick) then self:make_sick() end
end

function Game:make_sick()
    local p = self.player
    local lo, hi = SURVIVE.sick_hours[1], SURVIVE.sick_hours[2]
    p.sick_hours = math.max(p.sick_hours or 0, lo + self:rand(hi - lo + 1))
    self:push_log("Your gut twists. You're sick. (" .. p.sick_hours .. "h)")
end

-- On a ford, or next to open water.
function Game:near_water()
    local p = self.player
    if self.tiles[hex_key(p.q, p.r)] == "ford" then return true end
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        if self.tiles[hex_key(n[1], n[2])] == "water" then return true end
    end
    return false
end

-- Turn every carried empty bottle into `into`. Returns how many.
function Game:fill_bottles(into)
    local p = self.player
    local n = 0
    for slot, item in pairs(p.equipped) do
        if item == "empty_bottle" then p.equipped[slot] = into; n = n + 1 end
    end
    for i = #p.inventory, 1, -1 do
        local s = p.inventory[i]
        if s.item == "empty_bottle" then
            n = n + s.qty
            local qty = s.qty
            table.remove(p.inventory, i)
            -- merges into an existing stack or takes the freed cell, so it fits
            self:put_stack("inventory", nil, {item = into, qty = qty})
        end
    end
    return n
end

-- E on the map.
function Game:water_action()
    local p = self.player
    if not self:near_water() then
        self:push_log("No water here. Find a river or a ford.")
        return
    end
    local n = self:fill_bottles("dirty_water")
    if n > 0 then
        self:push_log(("Filled %d bottle%s. Boil it before drinking."):format(n, n > 1 and "s" or ""))
        return
    end
    p.needs.thirst = clamp(p.needs.thirst + SURVIVE.drink_here)
    p.hours = p.hours + SURVIVE.drink_hours
    apply_awake_hours(p, SURVIVE.drink_hours)
    self:push_log("You drink from the river. It tastes of iron.")
    local risk = ITEM_DB.dirty_water.sick
    if risk and self:roll(risk) then self:make_sick() end
end

-- Resting in the rain: empty bottles fill clean.
function Game:rain_fill()
    local n = self:fill_bottles("water_bottle")
    if n > 0 then self:push_log(("The rain filled %d bottle%s."):format(n, n > 1 and "s" or "")) end
end

-- n units of a stack go bad.
function Game:spoil(stack, per, n)
    stack.qty = stack.qty - n
    local rot = {item = per.into, qty = n}
    if not self:put_stack("inventory", nil, rot) then self:put_stack("ground", nil, rot) end
    self.spoiled = self.spoiled or {}
    self.spoiled[ITEM_DB[stack.item].name] = true
end

-- One hour: sickness, hunger and thirst damage, food going bad.
function Game:survive_hour()
    local p = self.player
    local hurt = 0
    if (p.sick_hours or 0) > 0 then
        local s = SURVIVE.sick
        p.sick_hours = p.sick_hours - 1
        p.needs.thirst = clamp(p.needs.thirst - s.thirst)
        p.needs.hunger = clamp(p.needs.hunger - s.hunger)
        p.needs.rest = clamp(p.needs.rest - s.rest)
        hurt = hurt + s.hurt
        if p.sick_hours == 0 then self:push_log("The sickness passes.") end
    end
    if p.injuries.bleeding then
        p.injuries.bleed_hours = (p.injuries.bleed_hours or 0) + 1
        if p.injuries.bleed_hours >= SURVIVE.clot_hours then
            p.injuries.bleeding = false
            self:push_log("The bleeding slows, then stops.")
        end
    else
        p.injuries.bleed_hours = 0
    end
    if p.needs.thirst <= 0 then hurt = hurt + SURVIVE.thirst_hurt end
    if p.needs.hunger <= 0 then hurt = hurt + SURVIVE.hunger_hurt end
    p.health = clamp(p.health - hurt)

    for i = #p.inventory, 1, -1 do
        local s = p.inventory[i]
        local per = ITEM_DB[s.item].perish
        if per then
            local n = 0   -- each unit: a 1-in-hours chance
            for _ = 1, s.qty do
                if self:rand(per.hours) == 0 then n = n + 1 end
            end
            if n > 0 then
                self:spoil(s, per, n)
                if s.qty <= 0 then table.remove(p.inventory, i) end
            end
        end
    end
    for slot, item in pairs(p.equipped) do
        local per = ITEM_DB[item].perish
        if per and self:rand(per.hours) == 0 then
            p.equipped[slot] = per.into
            self.spoiled = self.spoiled or {}
            self.spoiled[ITEM_DB[item].name] = true
        end
    end
end

function Game:survive_news()
    if not self.spoiled then return end
    local names = {}
    for name in pairs(self.spoiled) do names[#names + 1] = name end
    table.sort(names)
    self:push_log(table.concat(names, ", ") .. " went bad.")
    self.spoiled = nil
end

-- What killed you, when it happened with time passing.
function Game:death_reason()
    local p = self.player
    if self.emission_caught then return "The emission took you." end
    if (p.storm_hours or 0) > WORLD.storm.grace then return "The storm took you." end
    if (p.cold_hours or 0) > WORLD.cold_grace then return "You froze to death." end
    if self:rad_stage() >= 2 then
        return self:can_measure() and "Radiation sickness took you." or "A wasting sickness took you."
    end
    if (p.sick_hours or 0) > 0 then return "The sickness took you." end
    if p.needs.thirst <= 0 then return "You died of thirst." end
    if p.needs.hunger <= 0 then return "You starved." end
    return "Your body gave out."
end
