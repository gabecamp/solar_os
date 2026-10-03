-- ---------------------------------------------------------------------
-- Quests: small jobs from the people of the Churn (texts and numbers in
-- QUESTS). One at a time: self.quest = {kind, giver, target, ...} (saved).
--   fetch  (the trader, O on the trade screen): bring an artifact back.
--   den    (the trader): kill the beast in a den a few hexes away.
--   drive  (the trader): bring a USB drive back.
--   supply (Anna, on the radio): have bandages on you when you call her.
--   notes  (Anna): the Surgeon's Notes, the same way.
--   crate  (a USB drive's map): an Institute crate; Lockpicks open it.
--   smoked (Mother Okun), sinew (Karl, on the radio): the new loot.
-- Some jobs have a deadline (QUESTS.due); each job done or lapsed moves your
-- standing with its giver (self.rep, QUESTS.rep), which changes prices,
-- Anna's wait and Karl's riddles.
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
    self:rep_change(self.quest and self.quest.giver, 1)
    self.quest = nil
    self.quests_done = (self.quests_done or 0) + 1
end

-- A passable, non-site hex at distance near..far from you (or from the hex
-- `around`), optionally by water.
function Game:quest_spot(near, far, by_water, around)
    local p, taken, spots = self.player, {}, {}
    local oq, orr = p.q, p.r
    if around then oq, orr = Game.key_qr(around) end
    for _, k in pairs(self.sites) do taken[k] = true end
    if self.base then taken[self.base.key] = true end
    for key, t in pairs(self.tiles) do
        local q, r = Game.key_qr(key)
        local d = axial_distance(oq, orr, q, r)
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
        self:set_quest({kind = "fetch", giver = "Trader"})
        u.msg = QUESTS.fetch.offer
    elseif pick == 1 then
        self:set_quest({kind = "drive", giver = "Trader"})
        u.msg = QUESTS.drive.offer
    else
        local key = self:quest_spot(QUESTS.den.near, QUESTS.den.far)
        if not key then u.msg = "'Nothing today.'"; return end
        self:set_quest({kind = "den", giver = "Trader", target = key})
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
    if q.kind == "crate" or q.kind == "deep_crate" then return self:open_quest_crate() end
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
    local due = ""
    if q.due then
        local left = math.max(0, q.due - self.player.hours)
        due = left >= 24 and (" (%dd left)"):format(left // 24) or (" (%dh left)"):format(left)
    end
    return q.giver .. ": " .. QUESTS[q.kind].journal .. where .. due
end

-- A new job, with its deadline if the kind has one.
function Game:set_quest(q)
    local hours = QUESTS.due[q.kind]
    if hours then q.due = self.player.hours + hours end
    self.quest = q
    return q
end

-- From tick: a job past its deadline lapses (and the giver remembers).
function Game:quest_tick()
    local q = self.quest
    if not (q and q.due and self.player.hours > q.due) then return end
    self.quest = nil
    self:rep_change(q.giver, -1)
    self:push_log(QUESTS.lapsed[q.giver] or (q.giver .. " stopped waiting for you."))
end

-- -- standing --------------------------------------------------------------

function Game:rep_of(id)
    return (self.rep or {})[id] or 0
end

function Game:rep_change(giver, d)
    local R = QUESTS.rep
    local id = giver and R.giver[giver]
    if not id then return end
    self.rep = self.rep or {}
    self.rep[id] = math.max(R.min, math.min(R.max, self:rep_of(id) + d))
end

-- A trader's markup after your standing with them (who: "town", "ferry"...).
function Game:markup_for(who, markup)
    local R = QUESTS.rep
    local id = R.trade[who]
    if not id then return markup end
    return math.max(R.floor, markup * (1 - R.price * self:rep_of(id)))
end

-- "Standing: Trader +2  Okun -1" for the journal (nil while all are 0).
function Game:rep_text()
    local R, parts = QUESTS.rep, {}
    for _, id in ipairs(R.order) do
        local n = self:rep_of(id)
        if n ~= 0 then parts[#parts + 1] = ("%s %+d"):format(R.names[id], n) end
    end
    return #parts > 0 and ("Standing: " .. table.concat(parts, "  ")) or nil
end

-- -- Karl's job, on the radio ----------------------------------------------

-- His sinew is in your bag (he answers even before his wait is up).
function Game:karl_ready()
    local q, need = self.quest, QUESTS.sinew.need
    return q ~= nil and q.kind == "sinew" and self:count_item(need[1]) >= need[2]
end

-- A call to Karl: hands in his job, or now and then offers it. True if
-- that was the call (the forecast is skipped).
function Game:karl_radio_work()
    local S = QUESTS.sinew
    if self:karl_ready() then
        self:take_items(S.need[1], S.need[2])
        local first = not self.karl_lure
        self.karl_lure = true
        self:give_reward(first and S.reward or S.again, "A runner from Karl:")
        self:radio_say(S.thanks)
        return true
    end
    if not self.quest and self:rand(2) == 0 then
        self:set_quest({kind = "sinew", giver = "Karl"})
        self:radio_say(S.offer)
        self:push_log("Quest: " .. self:quest_text())
        return true
    end
    return false
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
-- The first one holds a map to a CLEARANCE crate by the quarry; that one an
-- Institute Pass (self.inst_chain: 1 = map found, 2 = opened).
function Game:open_quest_crate()
    local C, kind = QUESTS.crate, self.quest.kind
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
    self:note_find(hex_key(self.player.q, self.player.r), "crate",
                   kind == "deep_crate" and "The CLEARANCE crate" or "An Institute crate", found)
    if kind == "deep_crate" then
        self.inst_chain = 2
        if not self:give_pass(nil, QUESTS.deep_crate.pass) then
            self:put_stack("ground", nil, {item = "antirad", qty = 2})
        end
    elseif (self.inst_chain or 0) == 0 and self.sites.quarry then
        local D = QUESTS.deep_crate
        local key = self:quest_spot(D.near, D.far, false, self.sites.quarry)
        if key then
            self.inst_chain = 1
            self.quest = {kind = "deep_crate", giver = "A second map", target = key}
            self.player.explored[key] = true
            self:push_log(D.found .. " (" .. self:bearing_to(key) .. ")")
        end
    end
    return false
end
