-- ---------------------------------------------------------------------
-- Research: how the Churn's recipes are learned (numbers in CHURN, 08).
--
-- Almost nothing is known at the start. Each recipe belongs to a topic
-- (Tailoring, Bushcraft, Medicine, Tinkering, Chemistry, Gunsmithing,
-- Warding) and a topic's recipes are learned in RECIPES order, by:
--   * studying at a fire or your camp (crafting screen, "Study: <topic>"):
--     hours for points, more with the topic's book in reach;
--   * reading a book (E): its topic's next recipe, the first time;
--   * playing a cassette (E, with a charged Cassette Player): one recipe
--     and a dead churner's voice;
--   * pairing a USB drive with the LoRa Radio (E): one or two recipes from
--     what's on it, sometimes a stash or the way out;
--   * Scrawled Notes, as before: a random recipe.
-- self.research = {topic -> points}, self.books_read = {book -> true},
-- self.tapedeck = {charge} (saved).
-- Also here: the other new things you use with E, and lockpicked crates.
-- ---------------------------------------------------------------------

function Game.topic_def(id)
    for _, t in ipairs(CHURN.topics) do if t.id == id then return t end end
end

-- The next recipe the topic would teach, and how many of it you know.
function Game:topic_next(topic)
    local known = 0
    for _, r in ipairs(RECIPES) do
        if r.topic == topic then
            if self.known[r.id] then known = known + 1 else return r, known end
        end
    end
    return nil, known
end

-- Points a topic needs for its next recipe.
function Game:topic_need(topic)
    local _, known = self:topic_next(topic)
    return CHURN.study.need + CHURN.study.need_step * known
end

-- Learn the topic's next recipe (nil if there's none left).
function Game:learn_next(topic, how)
    local r = self:topic_next(topic)
    if not r then return nil end
    self.known[r.id] = true
    self:stat("learned")
    self:push_log((how or "You work it out") .. ": " .. r.name .. ".")
    return r
end

-- "Study: <topic>" entries for the crafting screen (topics with something left).
function Game:study_recipes()
    local list = {}
    for _, t in ipairs(CHURN.topics) do
        if self:topic_next(t.id) then
            list[#list + 1] = {id = "study_" .. t.id, name = "Study: " .. t.name, inputs = {},
                               hours = CHURN.study.hours, study = t.id}
        end
    end
    return list
end

function Game:study_text(topic)
    self.research = self.research or {}
    local r = self:topic_next(topic)
    return ("Research %d/%d%s"):format(self.research[topic] or 0, self:topic_need(topic),
                                       r and "" or " (done)")
end

function Game:study_blocker(topic)
    if not (self:fire_here() or self:at_base()) then return "Study by a fire or at your camp." end
    local t = Game.topic_def(topic)
    if t.needs then
        local have = false
        for _, id in ipairs(t.needs) do if self:count_item(id) > 0 then have = true end end
        if not have then
            local names = {}
            for i = 1, math.min(2, #t.needs) do names[i] = ITEM_DB[t.needs[i]].name end
            return "Nothing to study it from (" .. table.concat(names, ", ") .. "...)."
        end
    end
    return nil
end

-- Study points for one session.
function Game:study_points(topic)
    local S, t = CHURN.study, Game.topic_def(topic)
    local pts = math.max(1, S.base + S.per_point * (self.player.attrs.Perception - 3)
                            + self:skill_bonus("tinker") // 5)
    if t.book and self:count_item(t.book) > 0 then pts = pts * S.book_mult end
    return pts
end

function Game:study(topic)
    local p, t = self.player, Game.topic_def(topic)
    self.research = self.research or {}
    local hours = CHURN.study.hours
    p.hours = p.hours + hours
    apply_awake_hours(p, hours)
    if t.cost then p.needs.rest = math.max(0, p.needs.rest - t.cost) end
    local pts = self:study_points(topic)
    self.research[topic] = (self.research[topic] or 0) + pts
    self:skill_xp("tinker", SKILLS.xp.craft)
    local need = self:topic_need(topic)
    if self.research[topic] >= need then
        self.research[topic] = self.research[topic] - need
        self:sfx("gift")
        self:learn_next(topic, "Hours of " .. t.name:lower() .. " pay off")
    else
        self:push_log(("You study %s for %dh. (%d/%d)"):format(t.name:lower(), hours,
                                                              self.research[topic], need))
    end
    if t.cost then self:push_log("It leaves you hollow. (-" .. t.cost .. " rest)") end
    return true
end

-- E on a book: the first read of each book teaches its topic's next recipe
-- (later reads still give study points, at a fire or not).
function Game:read_book(item)
    local p, def = self.player, ITEM_DB[item]
    local topic, t = def.book, Game.topic_def(def.book)
    self.books_read = self.books_read or {}
    self.research = self.research or {}
    p.hours = p.hours + CHURN.study.read_hours
    apply_awake_hours(p, CHURN.study.read_hours)
    if t.cost then p.needs.rest = math.max(0, p.needs.rest - t.cost) end
    if not self.books_read[item] then
        self.books_read[item] = true
        if self:learn_next(topic, "From the " .. def.name) then return end
    end
    if not self:topic_next(topic) then
        self:push_log("You know everything in the " .. def.name .. ".")
        return
    end
    self.research[topic] = (self.research[topic] or 0) + CHURN.study.base
    self:push_log(("You reread the %s. (%s %d/%d)"):format(def.name, t.name, self.research[topic],
                                                         self:topic_need(topic)))
end

-- E on a cassette: needs a charged player in reach. The tape plays once.
function Game:play_tape(item)
    local tape = CHURN.tapes[item]
    if self:count_item("cassette_player") == 0 then
        self:push_log("You need a Cassette Player to hear it.")
        return false
    end
    self.tapedeck = self.tapedeck or {charge = 0}
    if self.tapedeck.charge <= 0 then
        self:push_log("The player is dead. A Battery Cell (E) would wake it.")
        return false
    end
    self:dread(CHURN.dread.tape)   -- (a human voice in the dark: it helps)
    self.tapedeck.charge = self.tapedeck.charge - 1
    if item == "tape_vesna" and not self.vesna then self.vesna = "heard" end   -- (find_corpse)
    local p = self.player
    p.hours = p.hours + CHURN.study.tape_hours
    apply_awake_hours(p, CHURN.study.tape_hours)
    self:push_log(tape.voice:sub(1, 60) .. "...")
    self.last_tape = tape.voice   -- (the journal shows it whole)
    if not self:learn_next(tape.topic, "From the tape") then
        self:push_log("Nothing on it you didn't know.")
    end
    if self:rand(3) == 0 then self:mark_stash() end
    return true
end

-- E on a USB drive: the radio reads it (a charge). Sometimes it fails.
function Game:pair_usb()
    if not (self:carrying("lora_radio") and self.radio) then
        self:push_log("Nothing to read it with. A LoRa Radio could.")
        return false
    end
    if self.radio.charge <= 0 then
        self:push_log("The radio has no charge to read it.")
        return false
    end
    self.radio.charge = self.radio.charge - 1
    local p = self.player
    p.hours = p.hours + CHURN.study.usb_hours
    apply_awake_hours(p, CHURN.study.usb_hours)
    if self:roll(CHURN.study.usb_fail - self:skill_bonus("tinker")) then
        self:push_log("The radio chokes on it: corrupt. Try again later.")
        return false
    end
    local topics = CHURN.usb_topics
    local learned = 0
    for _ = 1, 1 + self:rand(2) do
        local topic = topics[self:rand(#topics) + 1]
        if self:learn_next(topic, "Off the drive") then learned = learned + 1 end
    end
    if not self.sites_known.checkpoint and self:rand(3) == 0 then
        self:hear_of_exit("A map on the drive")
    elseif self:roll(QUESTS.crate.chance) and self:mark_crate() then
        -- (the crate is the job now)
    elseif self:rand(3) == 0 then
        self:mark_stash()
    elseif learned == 0 then
        self:push_log("Photos of a family. A field that isn't there any more.")
    end
    return true
end

-- E on a Battery Cell or Choir Cell: the radio first, then the tape player.
function Game:charge_tapedeck(full)
    if self:count_item("cassette_player") == 0 then return false end
    self.tapedeck = self.tapedeck or {charge = 0}
    if self.tapedeck.charge >= CHURN.study.tape_max then
        self:push_log("The cassette player is charged.")
        return false
    end
    self.tapedeck.charge = CHURN.study.tape_max
    self:push_log("The cassette player clicks and whirs. (" .. CHURN.study.tape_max .. " tapes)")
    return true
end

-- The new things E does; true if it handled the item.
function Game:use_churn_item(kind, k, stack)
    local p, item, def = self.player, stack.item, ITEM_DB[stack.item]
    local key = hex_key(p.q, p.r)
    if def.book then
        self:read_book(item)
    elseif CHURN.tapes[item] then
        if self:play_tape(item) then
            self:use_one(kind, k, stack)
            local blank = {item = "blank_tape", qty = 1}
            if not self:put_stack("inventory", nil, blank) then self:put_stack("ground", nil, blank) end
        end
    elseif item == "usb_drive" then
        if self:pair_usb() then self:use_one(kind, k, stack) end
    elseif item == "battery_cell" and self:count_item("cassette_player") > 0
           and not (self:carrying("lora_radio") and self.radio and self.radio.charge < TECH.radio_max) then
        if self:charge_tapedeck() then self:use_one(kind, k, stack) end
    elseif item == "choir_cell" then
        local any = false
        if self:carrying("lora_radio") and self.radio then self.radio.charge = TECH.radio_max; any = true end
        if self:charge_tapedeck() then any = true end
        if any then
            self:use_one(kind, k, stack)
            self:push_log("The Choir Cell sings, and everything you carry wakes.")
        else
            self:push_log("Nothing here to charge.")
        end
    elseif item == "stitches" then
        if not p.injuries.bleeding and p.injuries.wounded_hours <= 0 then
            self:push_log("No wound to stitch.")
            return true
        end
        p.injuries.bleeding = false
        p.injuries.wounded_hours = math.max(0, p.injuries.wounded_hours // 2 - 6)
        p.health = math.min(MAX_HEALTH, p.health + 10)
        self:use_one(kind, k, stack)
        self:push_log("You stitch it shut, teeth gritted. (+10 HP)")
    elseif item == "painkillers" then
        p.health = math.min(MAX_HEALTH, p.health + 12)
        self:use_one(kind, k, stack)
        self:push_log("The edges go soft. (+12 HP)")
    elseif item == "can_rattle" or item == "tarp_shelter" or item == "salt_circle" then
        self.placed = self.placed or {}
        self.placed[key] = self.placed[key] or {}
        if self.placed[key][item] then
            self:push_log("There's one here already.")
            return true
        end
        self.placed[key][item] = true
        self:use_one(kind, k, stack)
        self:push_log(({can_rattle = "You string the cans round the camp. Anything coming will ring them.",
                        tarp_shelter = "You pitch the lean-to. Cover from the weather, here.",
                        salt_circle = "You pour the circle unbroken. Here, the dark has to knock."})[item])
    else
        return false
    end
    return true
end

-- Something placed on this hex (E on a can rattle, lean-to, salt circle).
function Game:placed_here(item)
    local here = self.placed and self.placed[hex_key(self.player.q, self.player.r)]
    return here ~= nil and here[item] == true
end

-- F in ruins with Lockpicks: some hexes hide a locked crate (once a hex).
function Game:pick_crate(key)
    if self.tiles[key] ~= "ruins" or self:count_item("lockpicks") == 0 then return end
    self.crates = self.crates or {}
    if self.crates[key] == "locked" then   -- (one you left, or broke a pick on)
        return self:lock_start(CHURN.pick.pins, function(g) g:open_crate(key) end)
    end
    if self.crates[key] then return end
    self.crates[key] = true
    if not self:roll(CHURN.crate_chance + self:skill_bonus("scav")) then return end
    self.crates[key] = "locked"
    self:push_log("Under the rubble: a locked crate. You get out the picks.")
    self:lock_start(CHURN.pick.pins, function(g) g:open_crate(key) end)
end

-- The lock gave (64_lockpick): what's inside.
function Game:open_crate(key)
    self.crates[key] = true
    local found = {}
    for _ = 1, 2 do
        local item
        self.seed, item = weighted_pick(self.seed, CHURN.crate_loot)
        found[#found + 1] = self:drop_found(item)
    end
    self:push_log("You pick a locked crate: " .. table.concat(found, ", ") .. ".")
    self:note_find(key, "crate", "A locked crate", found)
end

-- F in ruins: now and then (CHURN.corpse.chance %, once a hex) a dead churner,
-- with what they carried for the Churn: tapes, books, drives, gun parts.
function Game:find_corpse(key)
    local C = CHURN.corpse
    if self.tiles[key] ~= "ruins" then return end
    self.crates = self.crates or {}
    local mark = C.prefix .. key
    if self.crates[mark] then return end
    local seeking = self.vesna == "heard"   -- (her tape: she's out there, up some stair)
    if not self:roll(C.chance * (seeking and CHURN.vesna.mult or 1)) then return end
    self.crates[mark] = true
    if seeking then return self:find_vesna(key) end
    local found = {}
    for _ = 1, 1 + self:rand(2) do
        local item
        self.seed, item = weighted_pick(self.seed, C.loot)
        found[#found + 1] = self:drop_found(item, C.rounds[item] and C.rounds[item] + self:rand(3))
    end
    self:dread(CHURN.dread.corpse)
    self:push_log(C.epitaphs[self:rand(#C.epitaphs) + 1])
    self:push_log("On them: " .. table.concat(found, ", ") .. ".")
    self:note_find(key, "corpse", "A dead churner", found)
end

-- The churner from the tape: what she took up the stairs.
function Game:find_vesna(key)
    self.vesna = "found"
    self:dread(CHURN.dread.vesna)
    self:queue_scene("vesna")
    local names = {}
    for _, it in ipairs(CHURN.vesna.loot) do
        self:put_stack("ground", nil, {item = it[1], qty = it[2]})
        names[#names + 1] = ITEM_DB[it[1]].name
    end
    self:push_log(CHURN.vesna.epitaph)
    self:push_log("On her: " .. table.concat(names, ", ") .. ".")
    self:note_find(key, "corpse", "Vesna, from the tape", names)
end

-- -- finds: dead churners and opened crates, on the map and the Finds page --
-- self.finds = {key -> {kind = "corpse"/"crate", label, day, what}} (saved).

function Game:note_find(key, kind, label, what)
    self.finds = self.finds or {}
    self.finds[key] = {kind = kind, label = label, day = (self:clock(self.player.hours)),
                       what = table.concat(what or {}, ", ")}
end

-- The Finds page (F in the journal): oldest first, where, and what was there.
function Game:finds_lines()
    local list = {}
    for key, f in pairs(self.finds or {}) do list[#list + 1] = {key = key, f = f} end
    table.sort(list, function(a, b)
        if a.f.day ~= b.f.day then return a.f.day < b.f.day end
        return a.key < b.key
    end)
    -- (every line wrapped to the page: 55 columns)
    if #list == 0 then return wrap("Nothing yet. Dead churners and the crates you open go here.", 55) end
    local lines = {}
    for _, e in ipairs(list) do
        local head = ("Day %d  %s, %s"):format(e.f.day, e.f.label, self:bearing_to(e.key))
        for _, l in ipairs(#head > 55 and wrap(head, 55) or {head}) do lines[#lines + 1] = l end
        if e.f.what ~= "" then
            for _, l in ipairs(wrap(e.f.what, 52)) do lines[#lines + 1] = "   " .. l end
        end
    end
    return lines
end

function Game:open_finds()
    self.skills_off, self.page = 0, "finds"
    self.screen = "skills"   -- (the same scrolling page)
end
