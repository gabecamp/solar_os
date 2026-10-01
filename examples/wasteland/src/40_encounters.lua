-- -- encounters -----------------------------------------------------------

local ENC_COLS = 55            -- mono 12 is ~7 px/char: 55 chars fit 400 px
-- the intro shares its lines with the 96 px portrait in the top-right corner
local ENC_INTRO_COLS = (400 - 12 - 104) // 7
local ENC_MSG_LINES = 4

-- 0..n-1 from the LCG's high bits
function Game:rand(n)
    self.seed = rand_next(self.seed)
    return self.seed * n // 32768
end

function Game:roll(pct)
    return self:rand(100) < pct
end

function Game:maybe_encounter(terrain_id)
    if (self.enc_cooldown or 0) > 0 then
        self.enc_cooldown = self.enc_cooldown - 1
        return
    end
    if self:maybe_karl("move") or self:maybe_dog() then return end
    local chance = FIGHT.ENCOUNTER_CHANCE[terrain_id]
    if chance then chance = chance * self:diff("encounter") end
    if chance and self:is_night() then chance = chance * WORLD.night_encounters end
    if chance and self:roll(chance * self.player.encounter_mult) then self:start_encounter(self:pick_encounter()) end
end

-- A kind by ENCOUNTER_KINDS weight (skipping kinds with no entries), then
-- one of its entries at random.
function Game:pick_encounter()
    local kinds = {}
    for _, k in ipairs(ENCOUNTER_KINDS) do
        if ENCOUNTERS_BY_KIND[k[1]] then kinds[#kinds + 1] = k end
    end
    local kind
    self.seed, kind = weighted_pick(self.seed, kinds)
    local list = ENCOUNTERS_BY_KIND[kind]
    return list[self:rand(#list) + 1]
end

function Game:start_encounter(def)
    self.enc = {def = def, hp = def.hp, range = def.start or "far", msg = {},
                intro = wrap(def.intro, ENC_INTRO_COLS), cursor = 1, aim = 0,
                demanding = def.kind == "bandit"}
    if def.kind == "bandit" then self:enc_say(def.demand) end
    self.screen = "encounter"
end

function Game:enc_say(text)
    for _, line in ipairs(wrap(text, ENC_COLS)) do table.insert(self.enc.msg, line) end
    while #self.enc.msg > ENC_MSG_LINES do table.remove(self.enc.msg, 1) end
end

function Game:end_encounter(summary)
    self.enc.over = true
    self.enc_cooldown = FIGHT.ENCOUNTER_COOLDOWN
    if summary then self:push_log(summary) end
end

-- The weapon in your hands (right first), its name and slot; fists if none.
function Game:weapon()
    for _, slot in ipairs({"rhand", "lhand"}) do
        local item = self.player.equipped[slot]
        if item and ITEM_DB[item].weapon then return ITEM_DB[item].weapon, ITEM_DB[item].name, slot end
    end
    return FISTS, "Fists"
end

function Game:thrown_slot()
    for _, slot in ipairs({"rhand", "lhand"}) do
        local item = self.player.equipped[slot]
        if item and ITEM_DB[item].weapon and ITEM_DB[item].weapon.thrown then return slot end
    end
end

-- First food/drink in the bag, for paying off bandits.
function Game:food_index()
    for i, stack in ipairs(self.player.inventory) do
        if ITEM_DB[stack.item].consumable then return i end
    end
end

function Game:enemy_condition()
    local f = self.enc.hp / self.enc.def.hp
    if f > 0.75 then return "unhurt" elseif f > 0.4 then return "hurt" end
    return "badly hurt"
end

-- What you can do now, as {label, action}.
function Game:encounter_options()
    local e = self.enc
    if e.over then return {{"Continue", "leave"}} end
    local kind = e.def.kind
    if kind == "helper" then return {{"Talk", "talk"}, {"Walk on", "leave_quietly"}} end
    if kind == "anomaly" then return {{"Investigate", "investigate"}, {"Walk away", "leave_quietly"}} end
    if kind == "dog" then
        local o = {}
        if self:dog_food() then o[1] = {"Offer it food", "tame"} end
        o[#o + 1] = {"Leave it", "leave_quietly"}
        return o
    end
    if kind == "riddle" then
        local o = {}
        for i, answer in ipairs(e.riddle.answers) do o[i] = {answer, "answer_" .. i} end
        o[#o + 1] = {"Walk away", "leave_quietly"}
        return o
    end
    if e.demanding then
        local o = {}
        if self:food_index() then o[#o + 1] = {"Give them some food", "give"} end
        o[#o + 1] = {"Refuse", "refuse"}
        o[#o + 1] = {"Run for it", "flee"}
        return o
    end
    local o = {}
    local w, wname = self:weapon()
    if e.range == "far" then
        o[#o + 1] = {"Approach", "approach"}
    elseif e.range == "near" then
        if w.reach == "near" then o[#o + 1] = {"Attack (" .. wname .. ")", "attack"} end
        o[#o + 1] = {"Close in", "approach"}
    else
        o[#o + 1] = {"Attack (" .. wname .. ")", "attack"}
    end
    local ts = self:thrown_slot()
    if ts and e.range ~= "close" then
        o[#o + 1] = {"Throw the " .. ITEM_DB[self.player.equipped[ts]].name:lower(), "throw"}
    end
    if e.range ~= "far" then o[#o + 1] = {"Back off", "back"} end
    if not e.seen then o[#o + 1] = {"Watch it", "watch"} end
    if e.range == "far" then o[#o + 1] = {"Hide", "hide"} end
    if kind == "mutant" and not e.talked then o[#o + 1] = {"Talk", "talk"} end
    o[#o + 1] = {"Flee", "flee"}
    return o
end

function Game:enemy_dies()
    local e = self.enc
    e.outcome = "dead"            -- the portrait shows it
    local found = {}
    for _ = 1, e.def.loot_rolls or 1 do
        local item
        self.seed, item = weighted_pick(self.seed, e.def.loot)
        if item ~= "nothing" then
            self:put_stack("ground", nil, {item = item, qty = 1})
            found[#found + 1] = ITEM_DB[item].name
        end
    end
    self:sfx("kill")
    self:enc_say("The " .. e.def.who .. " goes still.")
    if #found > 0 then self:enc_say("Left behind: " .. table.concat(found, ", ") .. ".") end
    self:end_encounter("You killed the " .. e.def.who .. ".")
end

-- The other side's turn: bleed, flee when beaten, close in, or strike.
function Game:enemy_turn()
    local e, p, d = self.enc, self.player, self.enc.def
    if e.over or self.screen ~= "encounter" then return end
    if e.bleeding then
        e.hp = e.hp - FIGHT.ENEMY_BLEED_DMG
        if e.hp <= 0 then return self:enemy_dies() end
    end
    if d.flees_at and e.hp <= d.flees_at and self:roll(FIGHT.ENEMY_FLEE_CHANCE) then
        self:enc_say("The " .. d.who .. " breaks away and flees.")
        e.outcome = "fled"
        return self:end_encounter("The " .. d.who .. " fled.")
    end
    if self:dog_turn() then return end
    if e.range ~= "close" then
        if self:roll(FIGHT.ADVANCE_CHANCE + 10 * (d.speed - p.attrs.Speed)) then
            e.range = CLOSER[e.range]
            self:enc_say("The " .. d.who .. " closes in.")
        else
            self:enc_say("The " .. d.who .. " circles, watching you.")
        end
        return
    end
    if not self:roll(d.hit - FIGHT.ENEMY_DODGE * (p.attrs.Speed - 3)) then
        self:enc_say("The " .. d.who .. " lunges and misses.")
        return
    end
    local dmg = d.dmg[1] + self:rand(d.dmg[2] - d.dmg[1] + 1)
    if self:dog_guard(dmg) then return end
    p.health = clamp(p.health - dmg)
    self:sfx("hurt")
    local text = "The " .. d.who .. " hits you (-" .. dmg .. " HP)."
    if d.bleed and d.bleed > 0 and not p.injuries.bleeding and self:roll(d.bleed) then
        p.injuries.bleeding = true
        text = text .. " You're bleeding."
    end
    if dmg >= FIGHT.WOUND_DAMAGE and p.injuries.wounded_hours == 0 then
        p.injuries.wounded_hours = WOUND_REST_HOURS
        text = text .. " It leaves a deep wound."
    end
    self:enc_say(text)
    self:check_death("Killed by the " .. d.who .. ".")   -- "who", not "name": "The Fused"
end

function Game:enc_hit(dmg, bleed, how)
    local e = self.enc
    e.hp = e.hp - dmg
    if e.hp > 0 then self:sfx("hit") end
    local text = how .. " (-" .. dmg .. ")."
    if bleed and self:roll(bleed) and not e.bleeding then
        e.bleeding = true
        text = text .. " It's bleeding."
    end
    self:enc_say(text)
    if e.hp <= 0 then self:enemy_dies() end
end

function Game:helper_talk()
    local p, d = self.player, self.enc.def
    if d.help == "medic" then
        p.injuries.bleeding = false
        p.injuries.wounded_hours = p.injuries.wounded_hours // 2
        p.health = clamp(p.health + 25)
        self:put_stack("ground", nil, {item = "cloth_scrap", qty = 2})
        self:enc_say("She cleans and binds your hurts without a word, and leaves you "
            .. "two clean strips of cloth. (+25 HP)")
        self:end_encounter("The medic patched you up.")
    else
        for key in pairs(self.tiles) do
            local q, r = key:match("(-?%d+),(-?%d+)")
            if axial_distance(p.q, p.r, tonumber(q), tonumber(r)) <= 3 then p.explored[key] = true end
        end
        self:put_stack("ground", nil, {item = "water_bottle", qty = 1})
        self:enc_say("He draws the land around you in the dirt and hands you a bottle of "
            .. "clean water. 'Stay off the roads at night.'")
        self:end_encounter("The wanderer shared water and directions.")
        if not self:hear_of_exit("The wanderer") and self:learn_site("trader") then
            self:push_log("The wanderer: a trader in the town, " .. self:site_bearing("trader") .. ".")
        end
    end
end

function Game:encounter_action(action)
    local e, p = self.enc, self.player
    e.msg = {}
    if action == "tame" then return self:dog_tame() end
    local answer = action:match("^answer_(%d)$")
    if answer then return self:karl_answer(tonumber(answer)) end
    if action == "investigate" then
        return self:start_puzzle()
    elseif action == "leave" or action == "leave_quietly" then
        if action == "leave_quietly" then
            self.enc_cooldown = FIGHT.ENCOUNTER_COOLDOWN
            self:push_log("You nod and walk on.")
        end
        self.enc = nil
        self.screen = "map"
        return
    elseif action == "talk" then
        if e.def.kind == "helper" then return self:helper_talk() end
        e.talked = true
        self:enc_say(e.def.talk)
    elseif action == "give" then
        local i = self:food_index()
        local stack = p.inventory[i]
        local name = ITEM_DB[stack.item].name
        stack.qty = stack.qty - 1
        if stack.qty <= 0 then table.remove(p.inventory, i) end
        self:enc_say("They take the " .. name:lower() .. " and back off into the ruins.")
        return self:end_encounter("You paid the " .. e.def.who .. " off.")
    elseif action == "refuse" then
        e.demanding = false
        self:enc_say("'Wrong answer.'")
    elseif action == "approach" then
        e.range = CLOSER[e.range]
        self:enc_say("You move in. Range: " .. RANGE_NAME[e.range] .. ".")
    elseif action == "back" then
        e.range = FARTHER[e.range]
        self:enc_say("You back away. Range: " .. RANGE_NAME[e.range] .. ".")
    elseif action == "attack" then
        local w, wname = self:weapon()
        local hit = FIGHT.PLAYER_HIT + 8 * (p.attrs.Speed - 3) + e.aim
        e.aim = 0
        if self:roll(hit) then
            local dmg = math.max(1, w.dmg - self:rand(w.dmg // 4 + 1) + 2 * (p.attrs.Strength - 3))
            self:enc_hit(dmg, w.bleed, "You hit the " .. e.def.who .. " (" .. wname:lower() .. ")")
        else
            self:sfx("miss")
            self:enc_say("You swing at the " .. e.def.who .. " and miss.")
        end
    elseif action == "throw" then
        local slot = self:thrown_slot()
        local item = p.equipped[slot]
        local w = ITEM_DB[item].weapon
        p.equipped[slot] = nil
        recompute_stats(p)
        self:put_stack("ground", nil, {item = item, qty = 1})
        if self:roll(FIGHT.THROW_HIT + 8 * (p.attrs.Perception - 3) + e.aim) then
            self:enc_hit(w.dmg, w.bleed, "Your " .. ITEM_DB[item].name:lower() .. " strikes the " .. e.def.who)
        else
            self:enc_say("Your " .. ITEM_DB[item].name:lower() .. " sails wide.")
        end
        e.aim = 0
    elseif action == "watch" then
        if self:roll(FIGHT.WATCH_CHANCE + 10 * (p.attrs.Perception - 3)) then
            e.seen = true
            e.aim = FIGHT.WATCH_AIM
            self:enc_say("You study how it moves. It looks " .. self:enemy_condition()
                .. ", and you see an opening.")
        else
            self:enc_say("You can't make out much.")
        end
    elseif action == "hide" then
        local chance = FIGHT.HIDE_CHANCE + 10 * (p.attrs.Perception - 3) + self:dog_bonus()
        if e.def.kind == "animal" then chance = chance - 10 end
        if self:roll(chance) then
            self:enc_say("You drop into cover and keep very still. It passes you by.")
            return self:end_encounter("You hid from the " .. e.def.who .. ".")
        end
        self:enc_say("It has seen where you went.")
    elseif action == "flee" then
        if self:roll(FIGHT.FLEE_CHANCE[e.range] + 10 * (p.attrs.Speed - e.def.speed) + self:dog_bonus()) then
            p.mp = p.mp - 1
            self:enc_say("You run until your lungs burn. It doesn't follow. (-1 MP)")
            return self:end_encounter("You ran from the " .. e.def.who .. ".")
        end
        self:enc_say("You try to run, but it cuts you off.")
    end
    if not e.over then self:enemy_turn() end
end

-- -- anomaly puzzles ---------------------------------------------------------

local function bolt_neighbors(c)
    local out, row, col = {}, (c - 1) // BOLT_N, (c - 1) % BOLT_N
    if row > 0 then out[#out + 1] = c - BOLT_N end
    if row < BOLT_N - 1 then out[#out + 1] = c + BOLT_N end
    if col > 0 then out[#out + 1] = c - 1 end
    if col < BOLT_N - 1 then out[#out + 1] = c + 1 end
    return out
end

-- the cell one step from c in a direction (nil off the grid)
local function bolt_step(c, dir)
    local row, col = (c - 1) // BOLT_N, (c - 1) % BOLT_N
    if dir == "up" and row > 0 then return c - BOLT_N end
    if dir == "down" and row < BOLT_N - 1 then return c + BOLT_N end
    if dir == "left" and col > 0 then return c - 1 end
    if dir == "right" and col < BOLT_N - 1 then return c + 1 end
end

local function bolt_path_exists(haz)
    local seen, queue, head = {[BOLT_START] = true}, {BOLT_START}, 1
    while queue[head] do
        local c = queue[head]
        head = head + 1
        if c == BOLT_GOAL then return true end
        for _, n in ipairs(bolt_neighbors(c)) do
            if not haz[n] and not seen[n] then
                seen[n] = true
                queue[#queue + 1] = n
            end
        end
    end
    return false
end

local function bolt_count(haz, c)
    local n = 0
    for _, nb in ipairs(bolt_neighbors(c)) do if haz[nb] then n = n + 1 end end
    return n
end

function Game:start_puzzle()
    local per = self.player.attrs.Perception
    local kind = ({"bolts", "sequence", "runes"})[self:rand(3) + 1]
    local z = {kind = kind, msg = ""}
    if kind == "bolts" then
        repeat
            z.haz = {}
            local placed = 0
            while placed < BOLT_HAZARDS do
                local c = self:rand(BOLT_N * BOLT_N) + 1
                if c ~= BOLT_START and c ~= BOLT_GOAL and not z.haz[c] then
                    z.haz[c] = true
                    placed = placed + 1
                end
            end
        until bolt_path_exists(z.haz)
        z.pos, z.visited, z.revealed = BOLT_START, {[BOLT_START] = true}, {}
        z.bolts = math.max(1, BOLTS + per - 3) + (self:carrying("bolts") and RAD.bolts_bonus or 0)
    elseif kind == "sequence" then
        z.round = 1
        self:new_sequence(z)
    else
        z.target = {}
        for i = 1, RUNE_N do z.target[i] = self:rand(4) end
        repeat
            z.cur, z.scramble = {}, {}
            for i = 1, RUNE_N do z.cur[i] = z.target[i] end
            for k = 1, RUNE_SCRAMBLE do
                local i = self:rand(RUNE_N) + 1
                z.scramble[k] = i
                -- a press turns rune i and its neighbours forward; scramble backward
                for j = math.max(1, i - 1), math.min(RUNE_N, i + 1) do z.cur[j] = (z.cur[j] + 3) % 4 end
            end
            local same = true
            for i = 1, RUNE_N do if z.cur[i] ~= z.target[i] then same = false end end
        until not same
        z.moves = math.max(RUNE_SCRAMBLE, RUNE_MOVES + per - 3)
    end
    self.puz = z
    self.screen = "puzzle"
end

function Game:new_sequence(z)
    z.seq, z.typed, z.showing = {}, 0, true
    for i = 1, SEQ_LENGTHS[z.round] do z.seq[i] = self:rand(4) + 1 end
end

-- Leave the anomaly: success may leave an artifact, failure hurts.
function Game:finish_puzzle(result)
    local p, who = self.player, self.enc.def.who
    self.enc, self.puz = nil, nil
    self.enc_cooldown = FIGHT.ENCOUNTER_COOLDOWN
    self.screen = "map"
    if result == "backed_off" then
        self:push_log("You back away from the " .. who .. ".")
    elseif result == "solved" then
        if self:roll(ARTIFACT_CHANCE + 5 * (p.attrs.Perception - 3)) then
            local id = ARTIFACTS[self:rand(#ARTIFACTS) + 1]
            self:put_stack("ground", nil, {item = id, qty = 1})
            self:push_log("The " .. who .. " fades. It left something:")
            self:push_log(ITEM_DB[id].name .. ". (I to pick it up)")
        else
            self:push_log("The " .. who .. " fades. Nothing remains.")
        end
    else
        local r = self:rand(3)
        if r == 0 then
            local dmg = 10 + self:rand(16)
            p.health = clamp(p.health - dmg)
            self:push_log("The " .. who .. " tears at you. (-" .. dmg .. " HP)")
        elseif r == 1 then
            p.injuries.bleeding = true
            self:push_log("Your nose and ears begin to bleed.")
        else
            local hours = 4 + self:rand(5)
            p.hours = p.hours + hours
            apply_awake_hours(p, hours)
            self:push_log("You come to. The sun has moved. (" .. hours .. "h lost)")
        end
        self:check_death("Taken by the " .. who .. ".")
    end
end

function Game:puzzle_key(key)
    local z = self.puz
    if key == gfx.KEY_ESCAPE or key == KEY.Q then return self:finish_puzzle("backed_off") end
    local dir = (key == gfx.KEY_UP or key == KEY.W) and "up"
        or (key == gfx.KEY_DOWN or key == KEY.S) and "down"
        or (key == gfx.KEY_LEFT or key == KEY.A) and "left"
        or (key == gfx.KEY_RIGHT or key == KEY.D) and "right"
    if z.kind == "bolts" then
        if key == KEY.T then
            z.aiming = z.bolts > 0 and not z.aiming
            z.msg = z.aiming and "Throw which way?" or (z.bolts > 0 and "" or "No bolts left.")
            return
        end
        if not dir then return end
        local c = bolt_step(z.pos, dir)
        if not c then return end
        if z.aiming then
            z.aiming = false
            z.bolts = z.bolts - 1
            z.revealed[c] = true
            z.msg = z.haz[c] and "The bolt is snatched from the air and crushed."
                or "The bolt lands and lies still."
            return
        end
        if z.haz[c] then return self:finish_puzzle("failed") end
        z.pos, z.visited[c], z.msg = c, true, ""
        if c == BOLT_GOAL then return self:finish_puzzle("solved") end
    elseif z.kind == "sequence" then
        if z.showing then
            z.showing = false
            return
        end
        if key < 49 or key > 52 then return end
        if key - 48 ~= z.seq[z.typed + 1] then return self:finish_puzzle("failed") end
        z.typed = z.typed + 1
        if z.typed == #z.seq then
            z.round = z.round + 1
            if z.round > #SEQ_LENGTHS then return self:finish_puzzle("solved") end
            self:new_sequence(z)
        end
    else
        if key < 49 or key >= 49 + RUNE_N then return end
        local i = key - 48
        for j = math.max(1, i - 1), math.min(RUNE_N, i + 1) do z.cur[j] = (z.cur[j] + 1) % 4 end
        z.moves = z.moves - 1
        local done = true
        for k = 1, RUNE_N do if z.cur[k] ~= z.target[k] then done = false end end
        if done then return self:finish_puzzle("solved") end
        if z.moves <= 0 then return self:finish_puzzle("failed") end
    end
end

function Game:encounter_key(key)
    local opts = self:encounter_options()
    local e = self.enc
    local pick
    if key >= 49 and key < 49 + #opts then          -- '1'..
        pick = key - 48
    elseif key == gfx.KEY_UP or key == KEY.W then
        e.cursor = math.max(1, e.cursor - 1)
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        e.cursor = math.min(#opts, e.cursor + 1)
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        pick = e.cursor
    end
    if pick and opts[pick] then
        e.cursor = 1
        self:encounter_action(opts[pick][2])
    end
end

