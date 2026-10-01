-- ---------------------------------------------------------------------
-- A base: claim a ruin, then build on it (recipes with `base`, in RECIPES)
--
-- self.base = {key, built = {box, bedroll, barrel, barricade}} (saved).
-- The base hex's ground is your Stash box; the Bedroll keeps you warm and
-- rests you better there; the Rain Barrel fills water bottles into the box;
-- the Barricade stops encounters starting on the hex. Numbers in BASE.
-- ---------------------------------------------------------------------

function Game:at_base()
    return self.base ~= nil and self.base.key == hex_key(self.player.q, self.player.r)
end

function Game:base_has(part)
    return self.base ~= nil and self.base.built[part] == true
end

-- Why a base recipe can't be built here (nil if it can).
function Game:base_blocker(r)
    if r.base == "claim" then
        if self.tiles[hex_key(self.player.q, self.player.r)] ~= "ruins" then
            return "Only a ruin will do for a camp."
        end
        if self:at_base() then return "This is already your camp." end
        return nil
    end
    if not self:at_base() then return "Build it at your camp." end
    if self:base_has(r.base) then return "Already built." end
    if r.needs and not self:base_has(r.needs) then
        return "Needs a " .. BASE.names[r.needs] .. " first."
    end
    return nil
end

-- Called by Game:craft for a base recipe (after craft_blocker passed).
function Game:build_base(r)
    local p = self.player
    for _, iq in ipairs(Game.recipe_inputs(r)) do self:take_items(iq[1], iq[2]) end
    p.hours = p.hours + r.hours
    apply_awake_hours(p, r.hours)
    self:sfx("chime")
    if r.base == "claim" then
        local moved = self.base ~= nil
        self.base = {key = hex_key(p.q, p.r), built = {}, barrel_hour = p.hours}
        self:push_log(moved and "You move your camp to this ruin." or "You make this ruin your camp.")
    else
        self.base.built[r.base] = true
        self:push_log("Built: " .. BASE.names[r.base] .. ".")
    end
    return true
end

-- Your bedroll, here: warm, and better rest.
function Game:bed_here()
    return self:at_base() and self:base_has("bedroll")
end

-- One hour: the rain barrel fills a bottle every BASE.barrel_hours (two in
-- rain) into the stash box, up to BASE.barrel_max.
function Game:base_hour(hour)
    local b = self.base
    if not (b and b.built.barrel and b.built.box) then return end
    if hour - (b.barrel_hour or hour) < BASE.barrel_hours then return end
    b.barrel_hour = hour
    local pile = self.ground[b.key] or {}
    self.ground[b.key] = pile
    local have = 0
    for _, s in ipairs(pile) do if s.item == "water_bottle" then have = have + s.qty end end
    local add = math.min(self:weather(hour) == "Rain" and 2 or 1, BASE.barrel_max - have)
    if add > 0 then add_to_list(pile, {item = "water_bottle", qty = add}) end
end

-- What the journal says about it.
function Game:base_text()
    if not self.base then return nil end
    local parts = {}
    for _, part in ipairs(BASE.order) do
        if self.base.built[part] then parts[#parts + 1] = BASE.names[part] end
    end
    local where = self:at_base() and "here" or self:bearing_to(self.base.key)
    return "Camp: " .. where .. (#parts > 0 and (". " .. table.concat(parts, ", ") .. ".") or ".")
end
