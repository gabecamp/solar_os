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
    if self:at_base() and self:base_has("barricade") then return end   -- safe at camp
    if (self.enc_cooldown or 0) > 0 then
        self.enc_cooldown = self.enc_cooldown - 1
        return
    end
    if self:maybe_karl("move") or self:maybe_dog() or self:maybe_horror() then return end
    local chance = FIGHT.ENCOUNTER_CHANCE[terrain_id]
    if chance then chance = chance * self:diff("encounter") end
    if chance and self:is_night() then chance = chance * WORLD.night_encounters end
    if chance and self:weather() == "Storm" then chance = chance * WORLD.storm.encounters end
    if chance and self:roll(chance * self.player.encounter_mult * self:noise_mult()) then
        self:start_encounter(self:pick_encounter())
    end
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
    local def = list[self:rand(#list) + 1]
    if def.rare and not self:roll(def.rare) then return list[1] end
    return def
end

function Game:start_encounter(def)
    self.enc = {def = def, hp = def.hp, range = def.start or "far", msg = {},
                intro = wrap(def.intro, ENC_INTRO_COLS), cursor = 1, aim = 0,
                demanding = def.kind == "bandit"}
    if def.kind == "bandit" then self:enc_say(def.demand) end
    self:arm_enemy()
    self:maybe_parley()
    if self:placed_here("can_rattle") and self.enc.range ~= "far" then   -- the cans rang
        self.enc.range = "far"
        self:enc_say("The cans you strung up clatter. You're ready for it.")
    end
    if self:weather() == "Fog" then   -- it was on you before you saw it
        self.enc.fog = true
        if self.enc.range == "far" then self.enc.range = "near" end
    end
    self.screen = "encounter"
end

function Game:enc_say(text)
    for _, line in ipairs(wrap(text, ENC_COLS)) do table.insert(self.enc.msg, line) end
    while #self.enc.msg > ENC_MSG_LINES do table.remove(self.enc.msg, 1) end
end

function Game:end_encounter(summary)
    self.enc.over = true
    self.enc_cooldown = FIGHT.ENCOUNTER_COOLDOWN
    local d = self.enc.def
    if (d.kind == "horror" or d.dark) and self.player.health > 0 then self:stat("horrors") end
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
    if kind == "horror" then return self:sign_options(self:horror_options(e), e) end
    if kind == "little" then return self:little_options() end
    if kind == "institute" then return self:institute_options() end
    if kind == "dog" then
        local o = {}
        if self:dog_food() then o[1] = {"Offer it food", "tame"} end
        o[#o + 1] = {"Leave it", "leave_quietly"}
        return o
    end
    if kind == "riddle" then
        local o = {}
        for i, answer in ipairs(e.riddle.answers) do
            local wink = self.karl_hint or self:rep_of("karl") >= QUESTS.rep.karl_wink
            local hint = wink and i == e.riddle.right and "  (Karl winks)" or ""
            o[i] = {answer .. hint, "answer_" .. i}
        end
        o[#o + 1] = {"Walk away", "leave_quietly"}
        return o
    end
    if e.demanding then
        local o = {}
        if self:food_index() then o[#o + 1] = {"Give them some food", "give"} end
        if self:shooter() and not e.bluffed then o[#o + 1] = {"Show them your gun", "bluff"} end
        local pa = e.parley
        if pa and self:count_item(pa.want) > 0 then
            o[#o + 1] = {("Swap your %s for their %s"):format(ITEM_DB[pa.want].name:lower(),
                                                            ITEM_DB[pa.give].name:lower()), "swap"}
        end
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
    if e.range == "far" or (e.fog and e.range == "near") then o[#o + 1] = {"Hide", "hide"} end
    if kind == "mutant" and not e.talked then o[#o + 1] = {"Talk", "talk"} end
    o[#o + 1] = {"Flee", "flee"}
    return self:ranged_options(o, e)
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
    self:drop_enemy_gun(found)
    self:sfx("kill")
    self:skill_xp("fight", SKILLS.xp.kill)
    self:stat("kills")
    self:quest_kill()
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
    if self:little_turn() or self:dog_turn() or self:dark_flees() then return end
    if self:enemy_shoots() then return end
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
    self:enemy_hits(d.dmg, d.bleed, "The " .. d.who .. " hits you")
end

-- Damage from {lo, hi} (unless the dog takes it): a bleed % and a wound
-- when it's deep, and maybe death.
function Game:enemy_hits(range, bleed, how)
    local p, d = self.player, self.enc.def
    local dmg = range[1] + self:rand(range[2] - range[1] + 1)
    if self:dog_guard(dmg) then return end
    p.health = clamp(p.health - dmg)
    self:wear_hit()
    self:sfx("hurt")
    local text = how .. " (-" .. dmg .. " HP)."
    if bleed and bleed > 0 and not p.injuries.bleeding and self:roll(bleed) then
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
            local q, r = Game.key_qr(key)
            if axial_distance(p.q, p.r, q, r) <= 3 then p.explored[key] = true end
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
    if action:find("_little$") then return self:little_action(action) end
    if action:find("_institute$") then return self:institute_action(action) end
    if action == "elder" then return self:raise_sign() end
    if action == "look_away" or action == "speak" or action == "cover" or action == "follow" then
        return self:horror_action(action)
    end
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
    elseif action == "swap" then
        return self:parley_swap()
    elseif action == "bluff" then
        if self:bluff() then return end
    elseif action == "refuse" then
        e.demanding = false
        self:enc_say("'Wrong answer.'")
    elseif action == "approach" then
        e.range = CLOSER[e.range]
        self:enc_say("You move in. Range: " .. RANGE_NAME[e.range] .. ".")
    elseif action == "back" then
        e.range = FARTHER[e.range]
        self:enc_say("You back away. Range: " .. RANGE_NAME[e.range] .. ".")
    elseif action == "shoot" then
        self:shoot()
    elseif action == "attack" then
        local w, wname = self:weapon()
        local hit = FIGHT.PLAYER_HIT + 8 * (p.attrs.Speed - 3) + e.aim + self:skill_bonus("fight")
        e.aim = 0
        if self:roll(hit) then
            self:skill_xp("fight", SKILLS.xp.hit)
            local dmg = math.max(1, w.dmg - self:rand(w.dmg // 4 + 1) + 2 * (p.attrs.Strength - 3))
            dmg = self:dark_damage(dmg)
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
        if self:roll(FIGHT.THROW_HIT + 8 * (p.attrs.Perception - 3) + e.aim + self:skill_bonus("fight")) then
            self:skill_xp("fight", SKILLS.xp.hit)
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
            + (e.fog and WORLD.fog_hide or 0)
        if e.def.kind == "animal" then chance = chance - 10 end
        if self:roll(chance) then
            self:enc_say("You drop into cover and keep very still. It passes you by.")
            return self:end_encounter("You hid from the " .. e.def.who .. ".")
        end
        self:enc_say("It has seen where you went.")
    elseif action == "flee" then
        if self:roll(FIGHT.FLEE_CHANCE[e.range] + 10 * (p.attrs.Speed - e.def.speed) + self:dog_bonus()
                     + self:little_flee_bonus()) then
            p.mp = p.mp - 1
            self:enc_say("You run until your lungs burn. It doesn't follow. (-1 MP)")
            return self:end_encounter("You ran from the " .. e.def.who .. ".")
        end
        self:enc_say("You try to run, but it cuts you off.")
    end
    if not e.over then self:enemy_turn() end
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

