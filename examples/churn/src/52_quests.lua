-- ---------------------------------------------------------------------
-- Quests: small jobs from the people of the Churn (texts and numbers in
-- QUESTS). One at a time: self.quest = {kind, giver, target, ...} (saved).
--   fetch  (the trader, O on the trade screen): bring an artifact back.
--   den    (the trader): kill the beast in a den a few hexes away.
--   drive  (the trader): bring a USB drive back.
--   supply (Anna, on the radio): have bandages on you when you call her.
--   notes  (Anna): the Surgeon's Notes, the same way.
--   crate  (a USB drive's map): an Institute crate; Lockpicks open it.
--   dog    (Karl, after a right answer): find his lost dog by the river.
-- Targets get a "!" on the map and a line in the journal.
-- ---------------------------------------------------------------------

function Game:give_reward(list, why)
    local names = {}
    for _, it in ipairs(list) do
        local stack = {item = it[1], qty = it[2] or 1}
        if not self:put_stack("inventory", nil, stack) then self:put_stack("ground", nil, stack) end
        names[#names + 1] = ITEM_DB[it[1]].name .. ((it[2] or 1) > 1 and (" x" .. it[2]) or "")
    end
    self:sfx("gift")
    self:push_log(why .. " " .. table.concat(names, ", ") .. ".")
    self.quest = nil
    self.quests_done = (self.quests_done or 0) + 1
end

-- A passable, non-site hex at distance near..far from you (optionally by water).
function Game:quest_spot(near, far, by_water)
    local p, taken, spots = self.player, {}, {}
    for _, k in pairs(self.sites) do taken[k] = true end
    if self.base then taken[self.base.key] = true end
    for key, t in pairs(self.tiles) do
        local q, r = Game.key_qr(key)
        local d = axial_distance(p.q, p.r, q, r)
        if TERRAIN[t].passable and d >= near and d <= far and not taken[key]
            and (self.rad[key] or 0) == 0 then
            if not by_water then
                spots[#spots + 1] = key
            else
                for _, n in ipairs(neighbors(self.tiles, q, r)) do
                    if self.tiles[hex_key(n[1], n[2])] == "water" then spots[#spots + 1] = key; break end
                end
            end
        end
    end
    if #spots == 0 then return nil end
    table.sort(spots)
    return spots[self:rand(#spots) + 1]
end

-- W on the trade screen: ask for work, or hand it in.
function Game:trader_work()
    local u, q = self.trade_ui, self.quest
    if q and q.kind == "drive" then
        if self:count_item("usb_drive") == 0 then
            u.msg = "'No drive, no deal.'"
            return
        end
        self:take_items("usb_drive", 1)
        local D = QUESTS.drive
        local reward = {D.reward[1], {D.part[self:rand(#D.part) + 1], 1}, D.reward[2]}
        self:give_reward(reward, "The trader pockets the drive. He pays:")
        u.msg = "'Bring me more if the Churn coughs them up.'"
        return
    end
    if q and q.kind == "fetch" then
        if self:artifact_count() == 0 then
            u.msg = "'Still waiting on that artifact.'"
            return
        end
        self:pay_artifacts(1)
        self:give_reward(QUESTS.fetch.reward, "The trader turns it over in his gloves. He pays:")
        u.msg = "'Good. Come back if you want more work.'"
        return
    end
    if q then
        u.msg = "'Finish the job you've got first.'"
        return
    end
    local pick = self:rand(3)
    if pick == 0 then
        self.quest = {kind = "fetch", giver = "Trader"}
        u.msg = QUESTS.fetch.offer
    elseif pick == 1 then
        self.quest = {kind = "drive", giver = "Trader"}
        u.msg = QUESTS.drive.offer
    else
        local key = self:quest_spot(QUESTS.den.near, QUESTS.den.far)
        if not key then u.msg = "'Nothing today.'"; return end
        self.quest = {kind = "den", giver = "Trader", target = key}
        self.player.explored[key] = true
        u.msg = QUESTS.den.offer .. " (" .. self:bearing_to(key) .. ")"
    end
    self:push_log("Quest: " .. self:quest_text())
end

-- Her job (bandages or the notes) is done and in your bag (she answers
-- even while busy).
function Game:anna_ready()
    local q = self.quest
    if not (q and (q.kind == "supply" or q.kind == "notes")) then return false end
    local need = QUESTS[q.kind].need
    return self:count_item(need[1]) >= need[2]
end

-- Anna's channel: hands in her supply job (true: the call is spent), or
-- offers one when you're not hurt (free, like any call she doesn't answer).
function Game:anna_work()
    local q = self.quest
    if q and (q.kind == "supply" or q.kind == "notes") then
        if not self:anna_ready() then return false end
        local need = QUESTS[q.kind].need
        self:take_items(need[1], need[2])
        if self.story then self.story.anna = true end   -- (she'll help you at the gate)
        self:give_reward(QUESTS[q.kind].reward, "Anna: 'Bless you.' A runner leaves a parcel:")
        self:radio_say(q.kind == "notes"
            and "Anna: 'His hand. I knew him. Now somebody here can learn it. I've sent you something.'"
            or "Anna: 'Bless you. The children here will sleep tonight. I've sent you something.'")
        return "open"   -- her channel stays open afterwards
    end
    local p = self.player
    local hurt = p.health < MAX_HEALTH or p.injuries.bleeding or p.injuries.wounded_hours > 0
    if not q and not hurt then
        local kind = self:rand(2) == 0 and "notes" or "supply"
        self.quest = {kind = kind, giver = "Anna"}
        self:radio_say(QUESTS[kind].offer)
        self:push_log("Quest: " .. self:quest_text())
        return "offered"
    end
    return false
end

-- Karl, after a right answer: his dog ran off.
function Game:karl_work()
    if self.quest then return end
    local key = self:quest_spot(QUESTS.dog.near, QUESTS.dog.far, true)
    if not key then return end
    self.quest = {kind = "dog", giver = "Karl", target = key}
    self.player.explored[key] = true
    self:enc_say(QUESTS.dog.offer .. " (" .. self:bearing_to(key) .. ")")
    self:push_log("Quest: " .. self:quest_text())
end

-- Stepping onto a quest target (from try_move). True if it started a fight.
function Game:quest_arrive()
    local q = self.quest
    if not (q and q.target == hex_key(self.player.q, self.player.r)) then return false end
    if q.kind == "dog" then
        local reward = {{"pilk", 2}}
        for _, item in ipairs({"karls_waders", "karls_hat"}) do
            if not (self.karl_gave and self.karl_gave[item]) and not self:carrying(item) then
                reward = {{item, 1}}
                self.karl_gave = self.karl_gave or {}
                self.karl_gave[item] = true
                break
            end
        end
        self:sfx("bark")
        self:give_reward(reward, "Karl's old dog limps out of the reeds and licks your hand. "
            .. "Karl will be glad. Tied to its collar:")
        return false
    end
    if q.kind == "crate" then return self:open_quest_crate() end
    if q.kind == "den" then
        local animals = ENCOUNTERS_BY_KIND.animal
        local base = animals[self:rand(#animals) + 1]
        local def = {}
        for k, v in pairs(base) do def[k] = v end
        def.hp = math.floor(base.hp * QUESTS.den.hp_mult)
        def.flees_at = nil
        def.den = true
        def.intro = "The den stinks of old blood. Something big is home. " .. base.intro
        self:start_encounter(def)
        return true
    end
    return false
end

-- When a den beast dies (from enemy_dies).
function Game:quest_kill()
    local q = self.quest
    if q and q.kind == "den" and self.enc and self.enc.def.den then
        local reward = {}
        for _, it in ipairs(QUESTS.den.reward) do
            if not self:carrying(it[1]) then reward[#reward + 1] = it end
        end
        if #reward == 0 then reward = {{"antirad", 2}} end
        self:give_reward({reward[1], {"canned_beans", 2}}, "The den is clear. The trader's payment:")
    end
end

function Game:quest_text()
    local q = self.quest
    if not q then return nil end
    local where = q.target and (" " .. self:bearing_to(q.target) .. ".") or ""
    return q.giver .. ": " .. QUESTS[q.kind].journal .. where
end

-- A drive's map (pair_usb): a locked Institute crate a few hexes off.
function Game:mark_crate()
    if self.quest then return false end
    local C = QUESTS.crate
    local key = self:quest_spot(C.near, C.far)
    if not key then return false end
    self.quest = {kind = "crate", giver = "A USB drive", target = key}
    self.player.explored[key] = true
    self:push_log("A map on the drive: an Institute crate, " .. self:bearing_to(key) .. ".")
    return true
end

-- Standing on the marked crate: Lockpicks open it (the job stays till then).
function Game:open_quest_crate()
    local C = QUESTS.crate
    if self:count_item("lockpicks") == 0 then
        self:push_log(C.locked)
        return false
    end
    local found = {}
    for _ = 1, C.rolls do
        local item
        self.seed, item = weighted_pick(self.seed, CHURN.crate_loot)
        self:put_stack("ground", nil, {item = item, qty = 1})
        found[#found + 1] = ITEM_DB[item].name
    end
    self:skill_xp("tinker", SKILLS.xp.repair)
    self.quest = nil
    self.quests_done = (self.quests_done or 0) + 1
    self:sfx("gift")
    self:push_log("The lock gives. Inside: " .. table.concat(found, ", ") .. ". (I to pick up)")
    return false
end
