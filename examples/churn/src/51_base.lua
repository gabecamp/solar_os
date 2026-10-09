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
    local p, hours = self.player, self:craft_hours(r)
    for _, iq in ipairs(Game.recipe_inputs(r)) do self:take_items(iq[1], iq[2]) end
    p.hours = p.hours + hours
    apply_awake_hours(p, hours)
    self:skill_xp("tinker", SKILLS.xp.craft)
    self:sfx("chime")
    if r.base == "claim" then
        local old = self.base
        if old then   -- one camp: what was in the old one's slots stays in its stash
            local pile = self:camp_pile()
            for _, st in pairs(old.slots or {}) do add_to_list(pile, {item = st.item, qty = st.qty}) end
            if self.dog then self.dog.at_camp = nil end
        end
        self.base = {key = hex_key(p.q, p.r), built = {}, barrel_hour = p.hours, slots = {}}
        self:push_log(old and "You move your camp here. The old one's things stay behind."
            or "You make this ruin your camp. T: the camp.")
    else
        self.base.built[r.base] = true
        if r.base == "barricade" then self.base.wall = BASE.wall_hp end
        self:push_log("Built: " .. BASE.names[r.base] .. ".")
    end
    return true
end

-- Your bedroll, here: warm, and better rest.
function Game:bed_here()
    return self:at_base() and (self:base_has("bedroll") or self:camp_stack("bed") ~= nil)
end

-- One hour: the rain barrel fills a bottle every BASE.barrel_hours (two in
-- rain) into the stash box, up to BASE.barrel_max.
function Game:base_hour(hour)
    local b = self.base
    if not b then return end
    self:camp_hour(hour)
    if not (b.built.barrel and b.built.box) then return end
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

-- ---------------------------------------------------------------------
-- The camp screen: slots (BASE.slots) that hold things and work while you
-- are away. self.base.slots = {slot id -> stack}; a stack in the pot or on
-- the rack keeps its hours in .t, a ward its days left in .left. Other
-- camp state on self.base: fire_until (hour the fire pit burns to), wall
-- (barricade condition), news (what happened while you were away),
-- day (last day ticked). All saved with self.base.
-- ---------------------------------------------------------------------

function Game.camp_slot(id)
    for _, s in ipairs(BASE.slots) do
        if s[1] == id then return s end
    end
end

-- Things that are tools somewhere in the recipes (the workbench takes them).
function Game.is_tool(item)
    if not Game.tool_set then
        local set = {[TECH.tool] = true}
        for _, r in ipairs(RECIPES) do
            for _, t in ipairs(r.tools or {}) do
                local prop = Game.prop_of(t)
                for _, id in ipairs(prop and prop.items or {t}) do set[id] = true end
            end
        end
        Game.tool_set = set
    end
    return Game.tool_set[item] == true
end

-- Does camp slot `slot` (a BASE.slots row) take this item?
function Game.camp_takes(slot, item)
    local kind, def = slot[4], ITEM_DB[item]
    if kind == "info" then return false end
    if kind == "light" then return def.light == true or item == "torch" end
    if kind == "tool" then return Game.is_tool(item) end
    if kind == "shelf" then return def.artifact ~= nil or def.trinket ~= nil end
    return BASE.takes[kind] ~= nil and BASE.takes[kind][item] ~= nil
end

-- nil if the slot can be used now, else why not.
function Game:camp_slot_blocker(slot)
    if slot[5] and not self:base_has(slot[5]) then
        return "Build a " .. BASE.names[slot[5]]:lower() .. " first (C)."
    end
    if slot[1] == "dog" and not self.dog then return "No dog to bed down." end
    return nil
end

function Game:camp_stack(id)
    local b = self.base
    return b and b.slots and b.slots[id] or nil
end

-- Put a stack in a camp slot (the camp side of put_stack): what was there
-- (another thing) and anything over the slot's limit go to the bag, or the
-- ground when it's full. False when it doesn't belong there.
function Game:camp_put(id, stack)
    local slot = Game.camp_slot(id)
    local why = slot and (self:camp_slot_blocker(slot)
        or (not Game.camp_takes(slot, stack.item) and (ITEM_DB[stack.item].name .. " doesn't go there.")))
    if not slot or why then
        self:push_log(why or "Not here.")
        return false
    end
    local b = self.base
    b.slots = b.slots or {}
    local spill = {}
    local here = b.slots[id]
    if here and here.item ~= stack.item then
        spill[#spill + 1] = here
        here = nil
    end
    local qty = stack.qty + (here and here.qty or 0)
    local max = slot[6] or qty
    b.slots[id] = {item = stack.item, qty = math.min(qty, max), t = here and here.t,
                   left = here and here.left or BASE.takes.ward[stack.item]}
    if qty > max then spill[#spill + 1] = {item = stack.item, qty = qty - max, cond = stack.cond} end
    for _, s in ipairs(spill) do
        s = {item = s.item, qty = s.qty, cond = s.cond}
        if not add_to_list(self.player.inventory, s, self:bag_capacity()) then add_to_list(self:ground_list(), s) end
    end
    if slot[4] == "ward" and not here then self:push_log("You set the " .. ITEM_DB[stack.item].name:lower() .. " at the edge of camp.") end
    return true
end

function Game:camp_remove(id)
    local b = self.base
    local s = b and b.slots and b.slots[id]
    if not s then return nil end
    b.slots[id] = nil
    return {item = s.item, qty = s.qty}
end

-- -- what the slots do ---------------------------------------------------

-- The fire pit: lit while it has fuel or a piece is still burning.
function Game:camp_fire(hours)
    local b = self.base
    if not (b and b.built.firepit) then return false end
    return (b.fire_until or 0) > hours or self:camp_stack("fire") ~= nil
end

function Game:camp_wards()
    local n = 0
    for _, id in ipairs({"ward1", "ward2", "ward3"}) do
        if self:camp_stack(id) then n = n + 1 end
    end
    return n
end

function Game:camp_count(kind)   -- trinkets or artifacts on the shelf
    local n = 0
    for _, id in ipairs({"shelf1", "shelf2", "shelf3"}) do
        local s = self:camp_stack(id)
        if s and ITEM_DB[s.item][kind] then n = n + 1 end
    end
    return n
end

function Game:dog_at_camp()
    return self.dog ~= nil and self.dog.at_camp == true
end

-- The dog is with you (not left at camp).
function Game:dog_with_you()
    return self.dog ~= nil and not self.dog.at_camp
end

-- The barricade stands (built and not broken down).
function Game:wall_up()
    local b = self.base
    return b ~= nil and b.built.barricade == true and (b.wall or BASE.wall_hp) > 0
end

-- Something that happened at camp: in the log if you're there, else kept
-- for when you come back.
function Game:camp_news(text)
    if self:at_base() then
        self:push_log(text)
        return
    end
    local b = self.base
    b.news = b.news or {}
    if #b.news < BASE.news_max then b.news[#b.news + 1] = text end
end

-- Back at camp: what happened while you were away.
function Game:camp_arrive()
    local b = self.base
    if not (b and self:at_base()) then return end
    if b.news then
        for _, line in ipairs(b.news) do self:push_log(line) end
        b.news = nil
    end
    if self:dog_at_camp() then self:push_log("Your dog runs out to meet you.") end
end

-- The camp's stash (its ground, the stash box).
function Game:camp_pile()
    local b = self.base
    self.ground[b.key] = self.ground[b.key] or {}
    return self.ground[b.key]
end

-- One hour at camp (from base_hour).
function Game:camp_hour(hour)
    local b = self.base
    b.slots = b.slots or {}
    local sl = b.slots
    -- the fire pit eats its fuel a piece at a time
    if b.built.firepit and sl.fire and (b.fire_until or 0) <= hour then
        b.fire_until = hour + BASE.takes.fuel[sl.fire.item]
        sl.fire.qty = sl.fire.qty - 1
        if sl.fire.qty <= 0 then sl.fire = nil end
    end
    -- the pot cooks over it; the rack smokes, fire or not
    local pot = sl.pot
    if pot and BASE.takes.cook[pot.item] and self:camp_fire(hour) then
        pot.t = (pot.t or 0) + 1
        if pot.t >= BASE.cook_hours then
            sl.pot = {item = BASE.takes.cook[pot.item], qty = pot.qty}
            self:camp_news("The pot at camp is done: " .. ITEM_DB[sl.pot.item].name:lower() .. ".")
        end
    end
    local rack = sl.rack
    if rack and BASE.takes.smoke[rack.item] then
        rack.t = (rack.t or 0) + 1
        if rack.t >= BASE.smoke_hours then
            sl.rack = {item = BASE.takes.smoke[rack.item], qty = rack.qty}
            self:camp_news("On the rack at camp: " .. rack.qty .. " smoked meat.")
        end
    end
    -- the radio mast tops up a radio you have with you at camp
    if sl.mast and self.radio and self:at_base() and self:carrying("lora_radio")
        and hour % BASE.mast_charge_hours == 0 and self.radio.charge < TECH.radio_max then
        self.radio.charge = self.radio.charge + 1
    end
    if hour % 24 == 6 then self:camp_day(hour) end
end

-- Once a day at dawn: wards wear, snares, the berry patch, the Little Ones,
-- the weather on the barricade, and a raid while you're away.
function Game:camp_day(hour)
    local b, sl = self.base, self.base.slots
    local pile = self:camp_pile()
    for _, id in ipairs({"ward1", "ward2", "ward3"}) do
        local w = sl[id]
        if w then
            w.left = (w.left or 1) - 1
            if w.left <= 0 then
                sl[id] = nil
                self:camp_news("A ward at camp has worn out: " .. ITEM_DB[w.item].name:lower() .. ".")
            end
        end
    end
    if sl.trap then
        local caught, broke = 0, 0
        for _ = 1, sl.trap.qty do
            if self:roll(BASE.trap_catch) then caught = caught + 1 end
            if self:roll(BASE.trap_break) then broke = broke + 1 end
        end
        if caught > 0 then
            add_to_list(pile, {item = "strange_meat", qty = caught})
            self:camp_news("The snare line caught something: " .. caught .. " meat in the stash.")
        end
        sl.trap.qty = sl.trap.qty - broke
        if sl.trap.qty <= 0 then sl.trap = nil end
    end
    if sl.plot and b.built.garden then
        add_to_list(pile, {item = "berries", qty = math.max(1, sl.plot.qty // BASE.plot_per)})
    end
    if self:camp_count("trinket") > 0 and self:roll(BASE.gift) then
        local item = LITTLE.trinkets[self:rand(#LITTLE.trinkets) + 1]
        if self:roll(50) then item = ({"berries", "cloth_scrap", "stick", "button"})[self:rand(4) + 1] end
        add_to_list(pile, {item = item, qty = 1})
        self:camp_news("Small footprints round the shelf. The Little Ones left a " .. ITEM_DB[item].name:lower() .. ".")
    end
    if b.built.barricade and self:weather(hour) == "Storm" then self:wall_hit(BASE.wall_storm, "The storm battered") end
    if not self:at_base() then self:camp_raid() end
end

function Game:wall_hit(n, how)
    local b = self.base
    b.wall = math.max(0, (b.wall or BASE.wall_hp) - n)
    self:camp_news(how .. " the barricade" .. (b.wall == 0 and ": it's down." or (" (" .. b.wall .. "%).")))
end

-- % a raid comes today (you away).
function Game:raid_chance()
    if self:dog_at_camp() then return 0 end
    local c = BASE.raid - BASE.raid_ward * self:camp_wards() - BASE.raid_shelf * self:camp_count("artifact")
    if self:camp_stack("light") then c = c - BASE.raid_light end
    return math.max(0, c)
end

function Game:camp_raid()
    if not self:roll(self:raid_chance()) then return end
    if self:wall_up() then
        local w = BASE.wall_raid
        return self:wall_hit(w[1] + self:rand(w[2] - w[1] + 1), "Someone tried")
    end
    local b, sl = self.base, self.base.slots
    local gone = {}
    for _, id in ipairs({"pot", "rack"}) do   -- (food left out goes first)
        if sl[id] then gone[#gone + 1] = ITEM_DB[sl[id].item].name:lower(); sl[id] = nil end
    end
    local pile = self:camp_pile()
    local take = b.built.lockbox and 0 or b.built.box and 1 or 2
    for _ = 1, take do
        if #pile == 0 then break end
        local i = self:rand(#pile) + 1
        gone[#gone + 1] = ITEM_DB[pile[i].item].name:lower()
        pile[i].qty = pile[i].qty - 1
        if pile[i].qty <= 0 then table.remove(pile, i) end
    end
    self:camp_news(#gone > 0 and ("Someone's been through your camp. Gone: " .. table.concat(gone, ", ") .. ".")
        or "Someone's been through your camp, and found nothing worth taking.")
end

-- After a night's rest at camp: something may come to the edge of the light.
function Game:camp_visit_chance()
    local c = BASE.visit
    c = c * BASE.ward_mult ^ self:camp_wards()
    if self:camp_stack("light") then c = c * BASE.light_mult end
    if self:camp_stack("bed") then c = c * BASE.pelt_mult end
    c = c * BASE.shelf_mult ^ self:camp_count("artifact")
    if self:dog_at_camp() or self:dog_with_you() then c = c / 2 end
    return c
end

function Game:camp_night()
    if not (self:at_base() and self:is_night()) then return false end
    if not self:roll(self:camp_visit_chance()) then return false end
    local def = NIGHT.horrors[self:rand(#NIGHT.horrors) + 1]
    self:start_encounter(def)
    self:sfx("emission")
    self:enc_say("You wake. Something stands at the edge of the camp's light.")
    return true
end

-- E on a camp slot.
function Game:camp_action(id)
    local b = self.base
    if id == "wall" then
        if not b.built.barricade then return self:push_log("Build a barricade first (C).") end
        if (b.wall or BASE.wall_hp) >= BASE.wall_hp then return self:push_log("The barricade is sound.") end
        local fix = self:count_item("scrap_metal") > 0 and {"scrap_metal", 1} or self:count_item("stick") >= 2 and {"stick", 2}
        if not fix then return self:push_log("Mending needs scrap metal, or 2 sticks.") end
        self:take_items(fix[1], fix[2])
        self.player.hours = self.player.hours + 1
        apply_awake_hours(self.player, 1)
        b.wall = math.min(BASE.wall_hp, (b.wall or BASE.wall_hp) + BASE.mend)
        return self:push_log("You shore up the barricade (" .. b.wall .. "%).")
    elseif id == "dog" then
        if not self.dog then return self:push_log("No dog to bed down.") end
        if self:dog_at_camp() then
            self.dog.at_camp = nil
            return self:push_log("You whistle. Your dog comes along.")
        end
        if not self:camp_stack("dog") then return self:push_log("Give it something to lie on first.") end
        self.dog.at_camp = true
        return self:push_log("Your dog circles its bed and lies down. It'll guard the camp.")
    elseif id == "map" then
        if not b.built.mapwall then return self:push_log("Build a map wall first (C).") end
        self.skills_off, self.page = 0, "map"
        self.skills_back = "inventory"
        self.screen = "skills"
        return
    end
    local s = self:camp_stack(id)
    if s then return self:push_log(self:camp_slot_text(id)) end
    local slot = Game.camp_slot(id)
    self:push_log(slot and (self:camp_slot_blocker(slot) or (slot[3] .. ": empty.")) or "")
end

-- One line on what a slot is doing (the screen, under the cursor).
function Game:camp_slot_text(id)
    local b, s = self.base, self:camp_stack(id)
    local slot = Game.camp_slot(id)
    local why = self:camp_slot_blocker(slot)
    if id == "barrel" then
        if why then return why end
        local n = 0
        for _, st in ipairs(self:camp_pile()) do if st.item == "water_bottle" then n = n + st.qty end end
        return n .. " bottles in the stash. Fills one a " .. BASE.barrel_hours .. "h, two in rain."
    elseif id == "wall" then
        if why then return why end
        local hp = b.wall or BASE.wall_hp
        if hp <= 0 then return "Down. E: mend it (scrap metal, or 2 sticks)." end
        return ("Holding at %d%%: stops raids.%s"):format(hp, hp < BASE.wall_hp and " E: mend." or "")
    elseif id == "box" then
        return b.built.lockbox and "Lockbox: raiders can't touch the stash."
            or b.built.box and "Stash box: a raid takes 1 thing at most. A lockbox: none."
            or "No box: a raid takes 2 things. Build one (C)."
    elseif id == "map" then
        return why or "E: the map wall - every place you know."
    end
    if why then return why end
    local kind = slot[4]
    if not s then
        return ({fuel = "Sticks, branches, newspaper, charcoal: it burns while fed.",
                 cook = "Raw meat, fish or dirty water: cooks over the fire.",
                 bedding = "A pelt or tarp: better rest, a warmer night.",
                 dogbed = "Cloth or hide. Then E: the dog stays and guards.",
                 light = "A glow jar, candle or torch: keeps the dark back.",
                 mast = "An antenna: free calls here, and a slow recharge.",
                 ward = "Salt circle, candle, rattle, charm, sign: wards the camp.",
                 smoke = "Meat or fish: smoked in a day, keeps for ever.",
                 trap = "Snares (3): meat in the stash most mornings.",
                 plot = "Berries to plant: more berries every morning.",
                 tool = "A tool left here counts when you craft at camp.",
                 shelf = "An artifact (wards) or a toy (the Little Ones)."})[kind] or ""
    end
    if kind == "fuel" then
        local left = math.max(0, (b.fire_until or 0) - self.player.hours)
        return ("Burning: %dh, and %d %s to go."):format(left, s.qty, ITEM_DB[s.item].name:lower())
    elseif kind == "cook" then return ("Cooking: %d of %dh."):format(s.t or 0, BASE.cook_hours)
    elseif kind == "smoke" then return ("Smoking: %d of %dh."):format(s.t or 0, BASE.smoke_hours)
    elseif kind == "ward" then return ("Holds %d more day%s."):format(s.left or 1, (s.left or 1) == 1 and "" or "s")
    elseif kind == "dogbed" then return self:dog_at_camp() and "Your dog guards the camp. E: call it." or "E: tell your dog to stay."
    end
    return ""
end

-- The line under the camp screen.
function Game:camp_summary()
    local b, p = self.base, self.player
    local parts = {}
    if b.built.firepit then
        parts[#parts + 1] = self:camp_fire(p.hours) and ("Fire " .. math.max(0, (b.fire_until or 0) - p.hours) .. "h") or "Fire out"
    end
    parts[#parts + 1] = "Wards " .. self:camp_wards()
    if b.built.barricade then parts[#parts + 1] = "Wall " .. (b.wall or BASE.wall_hp) .. "%" end
    if self:dog_at_camp() then parts[#parts + 1] = "Dog" end
    return table.concat(parts, "  ")
end

-- Every place you know, for the map wall.
function Game:map_wall_lines()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add("Camp: here.")
    for _, site in ipairs({{"trader", "Trader"}, {"ferry", "Ferry Post"}, {"checkpoint", "Checkpoint"},
                           {"quarry", "The quarry (Institute)"}}) do
        if self.sites_known[site[1]] and self.sites[site[1]] then add(site[2] .. ": " .. self:site_bearing(site[1]) .. ".") end
    end
    local pd = self.peddler
    if pd and pd.seen_key then add("Peddler, last seen: " .. self:bearing_to(pd.seen_key) .. ".") end
    for key in pairs(self.stashes or {}) do add("Stash: " .. self:bearing_to(key) .. ".") end
    for key in pairs(self.snares or {}) do add("Snare: " .. self:bearing_to(key) .. ".") end
    for _, l in ipairs(self:little_lines()) do add(l) end
    if next(self.finds or {}) then
        add("")
        for _, l in ipairs(self:finds_lines()) do add(l) end
    end
    local out = {}
    for _, l in ipairs(lines) do
        for _, w in ipairs(#l > 55 and wrap(l, 55) or {l}) do out[#out + 1] = w end
    end
    return out
end

-- T on the map at camp, or T on the bag screen there: the camp screen.
function Game:open_camp()
    self.screen = "inventory"
    self.camp_view = true
    self.inv_cursor = 1
    self.inv_selected = nil
end
