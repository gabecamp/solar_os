-- ---------------------------------------------------------------------
-- Game object (holds everything one screen/session needs)
-- ---------------------------------------------------------------------

local Game = {}
Game.__index = Game

-- "q,r" (a tile key, hex_key) back to two numbers.
function Game.key_qr(key)
    local q, r = key:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end

function Game.new()
    local self = setmetatable({}, Game)
    -- The SolarOS Lua runtime does not load the `os` library, so seed from
    -- uptime instead; the constant is only a fallback for other hosts.
    local seed = 12345
    local clock = solaros.time and solaros.time.uptime_ms
    if clock then
        seed = math.floor(clock()) % 32768
    elseif os and os.time then
        seed = os.time() % 32768
    end
    self.world_seed = seed       -- the map is rebuilt from this when a save is loaded
    -- this run, for the records (two runs can share a world seed)
    self.run_id = seed .. "-" .. math.random(1, 1000000000)
    self.tiles, self.ground, seed, self.rad, self.sites = generate_world(seed)
    self.extras = Game.place_extras(self.tiles, self.sites, self.rad, self.world_seed)
    for _, d in ipairs(self.extras.drops) do
        self.ground[d.key] = self.ground[d.key] or {}
        table.insert(self.ground[d.key], {item = d.item, qty = 1})
    end
    self.ferry_trader = Game.starting_stock("ferry")
    self.peddler = Game.starting_stock("peddler")
    self.little = Game.new_little()
    self.story = Game.new_story()
    self.trader = {stock = {}, restocked = 0}   -- what the trader has now (it changes as you trade)
    for _, st in ipairs(TRADE.stock) do
        self.trader.stock[#self.trader.stock + 1] = {item = st[1], qty = st[2]}
    end
    self.sites_known = {}        -- site name -> true once you know where it is
    self.stashes = {}            -- tile key -> true: a stash a note told you about
    self.snares = {}             -- tile key -> {set = hour}: snares you've set
    self.next_emission = RAD.emission.first
    self.rad_known = {}          -- tile key -> rad level you've measured or felt there
    self.skills = {}             -- skill -> XP (src/55_skills.lua)
    self.stats = {}              -- this run's counts (src/56_records.lua)
    self.seed = seed             -- RNG state for scavenging
    self.weather_seed = seed     -- fixed per world: weather is rolled from it (Game:weather)
    self.scavenged = {}          -- tile key -> searches used
    self.camps = {}              -- tile key -> {until_hour} while a campfire burns
    self.known = {}              -- recipe id -> true once you know how to make it
    for _, r in ipairs(RECIPES) do
        if r.known then self.known[r.id] = true end
    end
    self.craft_ui = {cursor = 1, back = "map"}   -- crafting screen state (not "craft": that is the method)
    self.player = new_player()
    self.difficulty = "normal"
    self.player.diff_drain = DIFFICULTY.normal.drain   -- (set_difficulty changes it)
    recompute_stats(self.player)
    self:refresh_view()
    self.screen = "creator"      -- "creator", then "map" or "inventory"
    self.creator_cursor = 1      -- rows: attributes, then traits
    self.creator_msg = nil
    self.log = {"You wake with nothing. Not even shoes."}
    self.inv_cursor = 1
    self.inv_selected = nil      -- {"ground"|"inventory"|"equip", key}
    self.quit = false
    return self
end

-- A difficulty multiplier (DIFFICULTY in 05_data_world); Normal is all 1.
function Game:diff(key)
    return DIFFICULTY[self.difficulty or "normal"][key]
end

function Game:set_difficulty(id)
    self.difficulty = id
    self.player.diff_drain = DIFFICULTY[id].drain
    recompute_stats(self.player)
end

-- Leave the creator: apply the chosen stats and start on the map.
function Game:start_game()
    if trait_points_left(self.player.traits) < 0 then
        self.creator_msg = "Too many trait points spent."
        return false
    end
    local p = self.player
    Game.ART_TILES = {}   -- (the title screens' pictures, cut into tiles: not needed in play)
    recompute_stats(p)
    p.mp = p.max_mp
    p.explored = {}
    self:refresh_view()
    self.screen = "map"
    self:queue_scene("wake")
    return true
end

-- Health at 0 ends the run: the death screen, then a new character.
function Game:check_death(cause)
    if self.player.health > 0 then return false end
    self.screen = "dead"
    self:sfx("death")
    Game.delete_save()           -- one life: a dead survivor can't be continued
    self.death_cause = cause
    self:record_run(nil, cause)
    return true
end

function Game:push_log(text)
    table.insert(self.log, text)
    while #self.log > 3 do table.remove(self.log, 1) end
end

-- -- movement / rest --------------------------------------------------

function Game:try_move(q, r)
    local p = self.player
    local key = hex_key(q, r)
    local terrain_id = self.tiles[key]
    if not terrain_id then return end
    local found = false
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        if n[1] == q and n[2] == r then found = true end
    end
    if not found then return end
    local terrain = TERRAIN[terrain_id]
    if not terrain.passable then
        self:push_log("Can't cross " .. terrain.name .. ".")
        return
    end
    if p.mp <= 0 then
        self:push_log("Out of movement. Rest first.")
        return
    end
    p.mp = p.mp - terrain.cost
    p.q, p.r = q, r
    p.hours = p.hours + terrain.cost
    apply_awake_hours(p, terrain.cost)
    self:refresh_view()
    self:push_log("Moved to " .. terrain.name .. " (" .. terrain.cost .. " MP)")
    local pile = self.ground[key]
    if pile and #pile > 0 then self:push_log("Something is here. (I to look)") end
    if p.needs.hunger <= 0 then self:push_log("You are starving!") end
    if p.needs.thirst <= 0 then self:push_log("You are dehydrated!") end
    self:find_stash()
    self:check_snare()
    if not self:check_death("You bled out.") and not self:arrive_site() and not self:quest_arrive()
        and not self:little_arrive() then
        self:maybe_encounter(terrain_id)
    end
end

-- The map's movement keys. Hexes have six neighbors and there are four
-- arrows, so Up/Down only lean (self.move_lean = -1 up, 1 down) and the next
-- Left/Right steps that way: Up then Left = up-left, Down then Right =
-- down-right; Left/Right alone go west/east. True if the key was used; any
-- other key drops the lean (the caller handles it).
function Game:map_dir_key(key)
    if key == gfx.KEY_UP or key == KEY.W then
        self.move_lean = -1
        return true
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        self.move_lean = 1
        return true
    end
    local dx = (key == gfx.KEY_LEFT or key == KEY.A) and -1
        or (key == gfx.KEY_RIGHT or key == KEY.D) and 1 or nil
    local lean = self.move_lean
    self.move_lean = nil
    if not dx then return false end
    self:move_dir(dx, lean or 0)
    return true
end

function Game:move_dir(dq, dr)
    local p = self.player
    -- pick the neighbor whose pixel-space direction best matches (dq,dr)
    local px, py = axial_to_pixel(p.q, p.r, HEX_SIZE)
    local best, best_dot = nil, -math.huge
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        local nx, ny = axial_to_pixel(n[1], n[2], HEX_SIZE)
        local vx, vy = nx - px, ny - py
        local len = math.sqrt(vx * vx + vy * vy)
        if len == 0 then len = 1 end
        local dot = (vx / len) * dq + (vy / len) * dr
        if dot > best_dot then best_dot, best = dot, n end
    end
    if best then self:try_move(best[1], best[2]) end
end

function Game:scavenge_left()
    local key = hex_key(self.player.q, self.player.r)
    return SCAVENGE_TRIES - (self.scavenged[key] or 0)
end

-- Search the current tile: costs MP and hours like moving, rolls the
-- terrain's loot table, and drops what turns up on the ground here.
function Game:scavenge()
    local p = self.player
    local key = hex_key(p.q, p.r)
    local loot = SCAVENGE_LOOT[self.tiles[key]]
    if not loot then
        self:push_log("Nothing to search here.")
        return
    end
    if self:scavenge_left() <= 0 then
        self:push_log("This area is picked clean.")
        return
    end
    if p.mp <= 0 then
        self:push_log("Too tired to search. Rest first.")
        return
    end
    p.mp = p.mp - SCAVENGE_HOURS
    p.hours = p.hours + SCAVENGE_HOURS
    apply_awake_hours(p, SCAVENGE_HOURS)
    self.scavenged[key] = (self.scavenged[key] or 0) + 1
    if p.scav_hurt > 0 then
        p.health = clamp(p.health - p.scav_hurt)
        self:push_log("The star in your hand drinks from you. (-" .. p.scav_hurt .. " HP)")
    end

    -- Perception: fewer dud rolls (and, via scav_rolls, more of them)
    local table_ = {}
    for i, entry in ipairs(loot) do
        local w = entry[2]
        if entry[1] == "nothing" then
            w = math.max(1, w * (7 - p.attrs.Perception) // 4)
            w = math.max(1, w * (100 - self:skill_bonus("scav")) // 100)
        end
        local food = ITEM_DB[entry[1]] and ITEM_DB[entry[1]].consumable
        if food and food.hunger and food.hunger > 0 then
            w = math.max(1, math.floor(w * self:diff("food") * self:season().food + 0.5))
        end
        table_[i] = {entry[1], w}
    end
    local found = {}
    for _ = 1, p.scav_rolls do
        local item
        self.seed, item = weighted_pick(self.seed, table_)
        if item ~= "nothing" then
            self:put_stack("ground", nil, {item = item, qty = 1})
            found[#found + 1] = ITEM_DB[item].name
        end
    end
    self:skill_xp("scav", SKILLS.xp.search + SKILLS.xp.find * #found)
    self:stat("searches")
    if #found == 0 then
        self:push_log("Searched " .. SCAVENGE_HOURS .. "h. Found nothing.")
    else
        self:push_log("Found: " .. table.concat(found, ", ") .. ".")
        self:push_log("Press I to pick it up.")
    end
    self:scavenge_field()
    self:pick_crate(key)
    self:find_corpse(key)
    if p.needs.hunger <= 0 then self:push_log("You are starving!") end
    if p.needs.thirst <= 0 then self:push_log("You are dehydrated!") end
    self:check_death(p.scav_hurt > 0 and "The Hollow Star emptied you." or "You bled out.")
end

function Game:rest()
    local p = self.player
    local cap = effective_max_mp(p)
    if p.mp >= cap then
        self:push_log("Already rested.")
        return
    end
    local fire, bed = self:fire_here(), self:bed_here()
    p.hours = p.hours + REST_HOURS
    apply_rest_hours(p, REST_HOURS)
    if fire then   -- a campfire: warm, and better sleep
        p.needs.rest = clamp(p.needs.rest + REST_HOURS * (100 / 6) * WORLD.fire_rest_bonus)
    end
    if bed then    -- your own bedroll at camp
        p.needs.rest = clamp(p.needs.rest + REST_HOURS * (100 / 6) * BASE.bed_rest_bonus)
    end
    p.mp = effective_max_mp(p)
    self:refresh_view()
    self:push_log("Rested " .. REST_HOURS .. "h" .. (bed and " in your bedroll." or fire and " by the fire." or "."))
    if self:weather() == "Rain" then self:rain_fill() end
    if p.injuries.bleeding then self:push_log("You're still bleeding. Bandage it (E on cloth).") end
    self:check_death("You bled out in your sleep.")
end

-- -- inventory transfer -------------------------------------------------

function Game:ground_list()
    local key = hex_key(self.player.q, self.player.r)
    self.ground[key] = self.ground[key] or {}
    return self.ground[key]
end

function Game:get_stack(kind, k)
    if kind == "ground" then
        return self:ground_list()[k]
    elseif kind == "inventory" then
        return self.player.inventory[k]
    elseif kind == "equip" then
        local item = self.player.equipped[k]
        return item and {item = item, qty = 1, cond = self:stack_cond(k)} or nil
    end
end

-- What the worn piece's condition becomes on a stack (nil when as new).
function Game:stack_cond(slot)
    local c = (self.player.wear or {})[slot]
    if c and c < 100 then return c end
    return nil
end

function Game:remove_stack(kind, k)
    if kind == "ground" then
        return table.remove(self:ground_list(), k)
    elseif kind == "inventory" then
        return table.remove(self.player.inventory, k)
    elseif kind == "equip" then
        local item = self.player.equipped[k]
        local cond = self:stack_cond(k)
        self.player.equipped[k] = nil
        if self.player.wear then self.player.wear[k] = nil end
        return item and {item = item, qty = 1, cond = cond} or nil
    end
end

-- Add stack to list, merging into an existing stack of the same item so the
-- same thing never takes two cells. Returns false (list untouched) when a new
-- stack is needed and the list already holds `cap` stacks.
local function add_to_list(list, stack, cap)
    for _, s in ipairs(list) do
        if s.item == stack.item and s.cond == stack.cond then   -- (worn and new don't stack)
            s.qty = s.qty + stack.qty
            return true
        end
    end
    if cap and #list >= cap then return false end
    table.insert(list, stack)
    return true
end

-- Bag cells available now: the worn bag (or bare pockets) plus Strength and
-- Pack Mule, within what the screen can show.
function Game:bag_capacity()
    local p = self.player
    -- a bag on your back (else what you can carry in your arms), plus the
    -- pockets in what you wear and the pouches on your belt
    -- (torn clothes hold half)
    local function cells(slot, n)
        return self:torn(slot) and n // 2 or n
    end
    local bag = p.equipped.back and cells("back", ITEM_DB[p.equipped.back].bag_cells or 0) or POCKET_CELLS
    for slot, item in pairs(p.equipped) do
        local def = ITEM_DB[item]
        bag = bag + cells(slot, (def.pocket_cells or 0) + (def.belt_cells or 0))
    end
    return math.max(2, math.min(BACKPACK_CAP, bag + (p.bag_bonus or 0)))
end

function Game:put_stack(kind, k, stack)
    if kind == "ground" then
        add_to_list(self:ground_list(), stack)
        return true
    elseif kind == "inventory" then
        if not add_to_list(self.player.inventory, stack, self:bag_capacity()) then
            self:push_log("Bag full.")
            return false
        end
        return true
    elseif kind == "equip" then
        local def = ITEM_DB[stack.item]
        if def.slot ~= k and not HOLD_SLOTS[k] then
            self:push_log(def.name .. " can't go in " .. k .. ".")
            return false
        end
        local current = self.player.equipped[k]
        self.player.wear = self.player.wear or {}
        if current then
            local old = {item = current, qty = 1, cond = self:stack_cond(k)}
            if not add_to_list(self.player.inventory, old, self:bag_capacity()) then
                add_to_list(self:ground_list(), old)
                self:push_log("Bag full: " .. ITEM_DB[current].name .. " dropped.")
            end
        end
        self.player.equipped[k] = stack.item
        self.player.wear[k] = stack.cond
        -- equipping takes one; anything else in the stack goes to the bag
        if stack.qty > 1 then
            local rest = {item = stack.item, qty = stack.qty - 1, cond = stack.cond}
            if not add_to_list(self.player.inventory, rest, self:bag_capacity()) then
                add_to_list(self:ground_list(), rest)
            end
        end
        return true
    end
end

local function copy_stacks(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = {item = s.item, qty = s.qty, cond = s.cond} end
    return out
end

-- Move a stack. Returns true when it moved. A move that would leave more
-- stacks in the bag than it can hold (e.g. taking off a full backpack) is
-- undone as a whole.
function Game:try_transfer(source, dest)
    local s_kind, s_key = source[1], source[2]
    local d_kind, d_key = dest[1], dest[2]
    if s_kind == d_kind and s_key == d_key then return false end
    local p = self.player
    local saved_inv, saved_ground = copy_stacks(p.inventory), copy_stacks(self:ground_list())
    local saved_eq, saved_wear = {}, {}
    for slot, item in pairs(p.equipped) do saved_eq[slot] = item end
    for slot, c in pairs(p.wear or {}) do saved_wear[slot] = c end
    local cap_before = self:bag_capacity()

    local stack = self:remove_stack(s_kind, s_key)
    if not stack then return false end
    local ok = self:put_stack(d_kind, d_key, stack)
    -- too full only if this move made it so (more stacks, or a smaller bag):
    -- a bag that shrank on its own (torn) can still be emptied
    local cap = self:bag_capacity()
    if ok and #p.inventory > cap and (#p.inventory > #saved_inv or cap < cap_before) then
        self:push_log("Bag too small - empty it first.")
        ok = false
    end
    if not ok then
        p.inventory, p.equipped, p.wear = saved_inv, saved_eq, saved_wear
        self.ground[hex_key(p.q, p.r)] = saved_ground
        return false
    end
    recompute_stats(p)   -- held artifacts change stats
    self:push_log("Moved " .. ITEM_DB[stack.item].name .. ".")
    return true
end

function Game:try_consume(kind, k)
    local stack = self:get_stack(kind, k)
    if not stack then return end
    self:apply_item_names()
    local def = ITEM_DB[stack.item]
    if not def.consumable then
        self:push_log(def.name .. " isn't edible/drinkable.")
        return
    end
    for need, amount in pairs(def.consumable) do
        if need == "rads" then
            self.player.rads = math.max(0, (self.player.rads or 0) + amount)
        else
            self.player.needs[need] = clamp(self.player.needs[need] + amount)
        end
    end
    -- one unit per use; the stack only disappears when it runs out
    stack.qty = stack.qty - 1
    if stack.qty <= 0 then
        self:remove_stack(kind, k)
    end
    self:push_log("Consumed " .. def.name .. ".")
    self:after_consume(def, kind, k)
end

-- Use up one of the stack at kind/k (it goes when it runs out).
function Game:use_one(kind, k, stack)
    stack.qty = stack.qty - 1
    if stack.qty <= 0 then self:remove_stack(kind, k) end
end

-- E on the inventory screen: the obvious thing for the item under the cursor.
-- Food/drink is eaten, gear is worn, anything else goes to a free hand; on a
-- body slot it takes the item off (held food is eaten instead).
function Game:use_item(kind, k)
    local stack = self:get_stack(kind, k)
    if not stack then return end
    local def = ITEM_DB[stack.item]
    local p = self.player
    if stack.item == "lore_page" then
        if self:read_lore() then self:use_one(kind, k, stack) end
        return
    end
    if self:use_churn_item(kind, k, stack) then return end   -- books, tapes, wards... (59_research)
    if def.trinket then
        if self:little_spot(hex_key(p.q, p.r)) == "cairn" then
            if kind == "inventory" then self:offer_trinket(stack.item) end
        else
            self:push_log("It's a toy. Someone small would love it. (Leave it at a cairn.)")
        end
        return
    end
    if stack.item == "medkit" then
        p.injuries.bleeding = false
        p.injuries.wounded_hours = math.max(0, p.injuries.wounded_hours - 12)
        p.health = clamp(p.health + 40)
        self:use_one(kind, k, stack)
        self:push_log("You patch yourself up properly. (+40 HP)")
        return
    end
    if stack.item == "bandage" then
        p.injuries.bleeding = false
        p.health = clamp(p.health + 15)
        self:use_one(kind, k, stack)
        self:push_log("You bandage yourself up. (+15 HP)")
        return
    end
    if stack.item == "battery_cell" and self:carrying("lora_radio") then
        if self:charge_radio() then self:use_one(kind, k, stack) end   -- a full radio keeps the cell
        return
    end
    if stack.item == "snare" then
        if self:set_snare() then
            self:use_one(kind, k, stack)
        end
        return
    end
    if stack.item == "splint" then
        if p.injuries.wounded_hours <= 0 then
            self:push_log("No wound to splint.")
            return
        end
        p.injuries.wounded_hours = math.max(0, p.injuries.wounded_hours - 12)
        self:use_one(kind, k, stack)
        self:push_log("You splint the wound. It'll mend sooner.")
        return
    end
    if stack.item == "scrawled_notes" then
        if self:read_notes() then
            self:use_one(kind, k, stack)
        end
        return
    end
    if stack.item == "cloth_scrap" and p.injuries.bleeding then
        p.injuries.bleeding = false
        self:use_one(kind, k, stack)
        self:push_log("You bind the wound. The bleeding stops.")
        return
    end
    if kind == "equip" then
        if def.consumable and HOLD_SLOTS[k] then
            self:try_consume(kind, k)
        else
            self:try_transfer({kind, k}, {"inventory"})
        end
    elseif def.consumable then
        self:try_consume(kind, k)
    elseif def.slot then
        self:try_transfer({kind, k}, {"equip", def.slot})
    else
        local hand = (not p.equipped.rhand and "rhand") or (not p.equipped.lhand and "lhand") or "rhand"
        self:try_transfer({kind, k}, {"equip", hand})
    end
end

