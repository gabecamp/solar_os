-- ---------------------------------------------------------------------
-- What's left of you (numbers in CHURN.legacy). When you die, what you
-- carried and wore is written to the records (rec.legacy: the stacks, the
-- cause, the day), so it outlives the save. In your next world something
-- wears it: The Risen waits CHURN.legacy.near..far hexes from where you
-- start, on the map from the first day, and fights with the best weapon you
-- had. Kill it and everything drops at your feet; the records forget it.
-- Run from it and it waits. A newer death replaces an older one.
-- self.legacy = {key} (saved): where it waits in this world.
-- ---------------------------------------------------------------------

-- At death (check_death): keep what you had for next time.
function Game:save_legacy(cause)
    local p, items = self.player, {}
    local function add(item, qty)
        if #items < CHURN.legacy.max_stacks then items[#items + 1] = {item = item, qty = qty} end
    end
    for _, s in ipairs(p.inventory) do add(s.item, s.qty) end
    for _, slot in ipairs(EQUIP_SLOTS) do
        if p.equipped[slot] then add(p.equipped[slot], 1) end
    end
    if #items == 0 then return end
    local rec = Game.records()
    rec.legacy = {items = items, cause = cause or "You died.", day = (self:clock())}
end

-- A new run: if a body is waiting, put it somewhere near.
function Game:place_legacy()
    local leg = Game.records().legacy
    if not leg then return end
    local key = self:quest_spot(CHURN.legacy.near, CHURN.legacy.far, false)
    if not key then return end
    self.legacy = {key = key}
    self.player.explored[key] = true
    self:note_find(key, "corpse", "What's left of you", {})
end

-- Its fight: your gear, your best weapon.
function Game:legacy_def()
    local L, leg = CHURN.legacy, Game.records().legacy
    local best = 8
    for _, s in ipairs(leg.items) do
        local def = ITEM_DB[s.item]
        local w = def and (def.shoot and def.shoot.dmg or def.weapon and def.weapon.dmg)
        if w and w > best then best = w end
    end
    return {kind = "mutant", legacy = true, name = "The Risen", who = L.who, art = L.art,
            intro = L.intro:format(leg.cause:gsub("%.$", "")), talk = L.talk,
            hp = math.min(L.hp_max, L.hp + L.hp_per * #leg.items), dmg = {best - 2, best + 6},
            hit = 55, speed = 2, bleed = 20, start = "near", loot = {{"nothing", 1}}, loot_rolls = 0}
end

-- Stepping onto its hex (from try_move).
function Game:legacy_arrive()
    local leg = self.legacy
    if not (leg and leg.key == hex_key(self.player.q, self.player.r) and Game.records().legacy) then
        return false
    end
    self:start_encounter(self:legacy_def())
    self:dread(CHURN.dread.risen)
    self:sfx("emission")
    return true
end

-- It's down (from enemy_dies): your things, back.
function Game:legacy_dies()
    local rec = Game.records()
    local found = {}
    for _, s in ipairs(rec.legacy and rec.legacy.items or {}) do
        if ITEM_DB[s.item] then
            self:put_stack("ground", nil, {item = s.item, qty = s.qty})
            found[#found + 1] = ITEM_DB[s.item].name
        end
    end
    rec.legacy = nil
    self.legacy = nil
    Game.write_records()
    self:enc_say("It folds up like an empty coat. Everything you had is here.")
    if #found > 0 then self:enc_say("Yours again: " .. table.concat(found, ", ") .. ".") end
    if self.finds then self.finds[hex_key(self.player.q, self.player.r)] = nil end
end

-- The journal line.
function Game:legacy_text()
    if not (self.legacy and Game.records().legacy) then return nil end
    return "What's left of you walks the Churn: " .. self:bearing_to(self.legacy.key) .. "."
end
