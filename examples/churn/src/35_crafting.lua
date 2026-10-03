-- ---------------------------------------------------------------------
-- Crafting and campfires
--
-- Inputs come from your bag, your hands and the ground where you stand
-- (NEO Scavenger style). A recipe's inputs are used up; its tools only have
-- to be there. Crafting takes hours, and hours drain your needs.
-- ---------------------------------------------------------------------

-- A property input ("@sharp"): its CHURN.props entry, else nil.
function Game.prop_of(item)
    return item:sub(1, 1) == "@" and CHURN.props[item:sub(2)] or nil
end

-- What the crafting screen calls an input: an item's name, or a property's.
function Game.input_name(item)
    local prop = Game.prop_of(item)
    return prop and prop.name or ITEM_DB[item].name
end

-- How many of an item (or of anything with a property) you can reach right now.
function Game:count_item(item)
    local prop = Game.prop_of(item)
    if prop then
        local n = 0
        for _, id in ipairs(prop.items) do n = n + self:count_item(id) end
        return n
    end
    local n = 0
    for _, s in ipairs(self.player.inventory) do
        if s.item == item then n = n + s.qty end
    end
    for _, s in ipairs(self:ground_list()) do
        if s.item == item then n = n + s.qty end
    end
    for _, slot in ipairs({"rhand", "lhand"}) do
        if self.player.equipped[slot] == item then n = n + 1 end
    end
    return n
end

-- Use up qty of an item: the ground first, then the bag, your hands last
-- (so a weapon you're holding is the last thing to go).
function Game:take_items(item, qty)
    local prop = Game.prop_of(item)
    if prop then   -- the cheapest things with the property first
        for _, id in ipairs(prop.items) do
            local take = math.min(qty, self:count_item(id))
            if take > 0 then
                self:take_items(id, take)
                qty = qty - take
            end
        end
        return qty == 0
    end
    local function from_list(list)
        local i = 1
        while qty > 0 and i <= #list do
            local s = list[i]
            if s.item == item then
                local take = math.min(qty, s.qty)
                s.qty, qty = s.qty - take, qty - take
                if s.qty <= 0 then table.remove(list, i) else i = i + 1 end
            else
                i = i + 1
            end
        end
    end
    from_list(self:ground_list())
    from_list(self.player.inventory)
    for _, slot in ipairs({"rhand", "lhand"}) do
        if qty > 0 and self.player.equipped[slot] == item then
            self.player.equipped[slot] = nil
            qty = qty - 1
        end
    end
    return qty == 0
end

function Game:fire_here()
    local camp = self.camps[hex_key(self.player.q, self.player.r)]
    return camp ~= nil and self.player.hours < camp.until_hour
end

-- Any gun or bow you can reach (for Clean Guns).
function Game:guns_in_reach()
    local list = {}
    for id, def in pairs(ITEM_DB) do
        if def.shoot and not def.shoot.quiet and self:count_item(id) > 0 then list[#list + 1] = id end
    end
    table.sort(list)
    return list
end

-- The recipe's inputs in a fixed order (pairs() order isn't stable).
-- (A field, not a top-level local: the bundled file is one Lua chunk and
-- a chunk may have at most 200 locals.)
function Game.recipe_inputs(r)
    local list = {}
    for item, qty in pairs(r.inputs) do list[#list + 1] = {item, qty} end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    return list
end

-- nil if you can make it now, else the reason you can't.
function Game:craft_blocker(r)
    if not (r.repair or r.study or self.known[r.id]) then return "You don't know how to make that." end
    if r.study then return self:study_blocker(r.study) end
    if r.base then
        local why = self:base_blocker(r)
        if why then return why end
    end
    for _, iq in ipairs(Game.recipe_inputs(r)) do
        if self:count_item(iq[1]) < iq[2] then
            return "Need " .. iq[2] .. " " .. Game.input_name(iq[1]) .. "."
        end
    end
    for _, tool in ipairs(r.tools or {}) do
        if self:count_item(tool) < 1 then return "Need a " .. Game.input_name(tool) .. " to work with." end
    end
    if r.fire and not self:fire_here() then return "Needs a fire. Build a campfire here." end
    if r.place == "campfire" and self:fire_here() then return "A fire already burns here." end
    if r.mend and not self:most_worn(90) then return "Nothing you wear needs mending." end
    if r.clean and #self:guns_in_reach() == 0 then return "No gun here to clean." end
    return nil
end

function Game:craft(r)
    local why = self:craft_blocker(r)
    if why then
        self:push_log(why)
        return false
    end
    if r.repair then return self:repair(r) end
    if r.study then return self:study(r.study) end
    if r.base then return self:build_base(r) end
    local p, hours = self.player, self:craft_hours(r)
    if r.chance then   -- fiddly work (a gun): it can fail and break a part
        local chance = self:craft_chance(r)
        p.hours = p.hours + hours
        apply_awake_hours(p, hours)
        self:skill_xp("tinker", SKILLS.xp.repair)
        if not self:roll(chance) then
            local parts = {}
            for _, iq in ipairs(Game.recipe_inputs(r)) do
                if not iq[1]:find("^frame_") then parts[#parts + 1] = iq[1] end
            end
            local lost = parts[self:rand(#parts) + 1]
            self:take_items(lost, 1)
            self:sfx("miss")
            self:push_log("It won't go together. The " .. ITEM_DB[lost].name:lower() .. " is ruined.")
            return true
        end
        hours = 0
    end
    for _, iq in ipairs(Game.recipe_inputs(r)) do self:take_items(iq[1], iq[2]) end
    p.hours = p.hours + hours
    apply_awake_hours(p, hours)
    self:skill_xp("tinker", SKILLS.xp.craft)
    self:sfx("chime")
    if r.mend then
        local slot = self:most_worn(90)
        p.wear[slot] = math.min(100, p.wear[slot] + WORLD.wear.mend)
        self:push_log(("You patch your %s (%d%%)."):format(ITEM_DB[p.equipped[slot]].name:lower(), math.floor(p.wear[slot])))
    elseif r.place == "campfire" then
        local burn = r.burn or RECIPES.campfire_hours
        self.camps[hex_key(p.q, p.r)] = {until_hour = p.hours + burn}
        self:push_log("You build " .. (r.burn and "a small fire" or "a campfire") .. ". It will burn " .. burn .. "h.")
    elseif r.clean then
        self.gun_wear = self.gun_wear or {}
        for _, id in ipairs(self:guns_in_reach()) do self.gun_wear[id] = 100 end
        self:push_log("You strip, oil and wipe every gun you have. They shine.")
    else
        local stack = {item = r.out[1], qty = r.out[2]}
        if not self:put_stack("inventory", nil, stack) then
            self:put_stack("ground", nil, stack)
            self:push_log("Made " .. r.name .. " (left on the ground).")
        else
            self:push_log("Made " .. r.name .. ".")
        end
    end
    self:check_death("You bled out.")
    return true
end

-- Assembly odds (a recipe with `chance`): Perception and tinkering.
function Game:craft_chance(r)
    return math.max(5, math.min(95, r.chance + TECH.per_point * (self.player.attrs.Perception - 3)
                                    + self:skill_bonus("tinker")))
end

-- Scrawled Notes: learn a recipe you don't know yet (the notes are used up).
function Game:read_notes()
    local unknown = {}
    for _, r in ipairs(RECIPES) do
        if not self.known[r.id] then unknown[#unknown + 1] = r end
    end
    -- some notes (and all of them once you know every recipe) sketch the way out
    if not self.sites_known.checkpoint and (#unknown == 0 or self:rand(3) == 0) then
        return self:hear_of_exit("A sketch in the notes")
    end
    -- others mark a stash (and once you know every recipe, all of them do)
    if #unknown == 0 or self:rand(4) == 0 then
        if self:mark_stash() then return true end
    end
    if #unknown == 0 then
        self:push_log("Nothing in these notes you don't already know.")
        return false
    end
    local r = unknown[self:rand(#unknown) + 1]
    self.known[r.id] = true
    self:push_log("You puzzle out the notes: how to make " .. r.name .. ".")
    return true
end

function Game:known_recipes()
    local list = {}
    for _, r in ipairs(RECIPES) do
        if self.known[r.id] then list[#list + 1] = r end
    end
    for _, r in ipairs(self:repair_recipes()) do list[#list + 1] = r end   -- broken tech you carry
    for _, r in ipairs(self:study_recipes()) do list[#list + 1] = r end    -- research (59_research)
    return list
end

function Game:open_crafting()
    self.craft_ui.back = self.screen
    self.craft_ui.cursor = math.min(self.craft_ui.cursor, #self:known_recipes())
    self.screen = "craft"
end

function Game:craft_key(key)
    local list = self:known_recipes()
    local c = self.craft_ui
    if key == gfx.KEY_UP or key == KEY.W then
        c.cursor = math.max(1, c.cursor - 1)
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        c.cursor = math.min(#list, c.cursor + 1)
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        if list[c.cursor] then self:craft(list[c.cursor]) end
    elseif key == KEY.C or key == gfx.KEY_ESCAPE or key == KEY.I then
        self.screen = c.back == "craft" and "map" or c.back
    end
end
