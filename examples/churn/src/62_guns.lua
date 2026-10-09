-- ---------------------------------------------------------------------
-- Ranged weapons: the rare handguns (and the quiet bow and sling), plus
-- the Elder Sign (numbers in CHURN.guns, items in 08_data_churn).
--
-- A gun or bow in a hand, with its rounds anywhere in reach, adds "Shoot"
-- to a fight at any range; each shot uses one. Guns are loud (more
-- encounters for a few hours; animals may bolt), they wear a little each
-- shot and a worn gun jams more (Clean Guns: gunsmithing). The Marsh
-- Revolver hits hardest and takes something from you every time.
-- self.gun_wear = {gun -> %}, self.noise_until = hour (saved).
-- ---------------------------------------------------------------------

-- The ranged weapon in your hands with ammo for it: item, its shoot table.
function Game:shooter()
    for _, slot in ipairs({"rhand", "lhand"}) do
        local item = self.player.equipped[slot]
        local sh = item and ITEM_DB[item].shoot
        if sh and self:count_item(sh.ammo) > 0 then return item, sh end
    end
end

function Game:gun_wear_of(item)
    return (self.gun_wear or {})[item] or 100
end

-- Jam chance: the gun's own, plus more as it wears.
function Game:jam_chance(item)
    local sh = ITEM_DB[item].shoot
    if sh.jam == 0 then return 0 end
    return sh.jam + (100 - self:gun_wear_of(item)) // CHURN.guns.jam_per_wear
end

function Game:shoot_chance(item)
    local p, e, G = self.player, self.enc, CHURN.guns
    return G.shoot_hit + 8 * (p.attrs.Perception - 3) + (e.aim or 0) + self:skill_bonus("fight") + self:beast_bonus()
        + ITEM_DB[item].shoot.hit - (e.range == "far" and G.far_penalty or 0)
end

-- Extra fight options: Shoot, and the Elder Sign against what walks at night.
function Game:ranged_options(o, e)
    local item = self:shooter()
    if item then
        local ammo = ITEM_DB[item].shoot.ammo
        table.insert(o, 1, {("Shoot (%s, %d)"):format(ITEM_DB[item].name, math.min(99, self:count_item(ammo))),
                            "shoot"})
    end
    return self:sign_options(o, e)
end

function Game:sign_options(o, e)
    if (e.def.kind == "horror" or e.def.dark) and self:count_item("elder_sign") > 0 then
        table.insert(o, 1, {"Raise the Elder Sign", "elder"})
    end
    return o
end

function Game:shoot()
    local p, e, G = self.player, self.enc, CHURN.guns
    local item, sh = self:shooter()
    if not item then return end
    local name = ITEM_DB[item].name
    self:take_items(sh.ammo, 1)
    if not sh.quiet then
        self.gun_wear = self.gun_wear or {}
        self.gun_wear[item] = math.max(0, self:gun_wear_of(item) - G.wear_per_shot)
        self.noise_until = p.hours + G.noise_hours
    end
    if sh.curse then
        p.needs.rest = math.max(0, p.needs.rest - sh.curse)
    end
    if self:roll(self:jam_chance(item)) then
        self:sfx("miss")
        self:enc_say("Click. The " .. name .. " jams, and you lose the round clearing it.")
        return
    end
    if self:roll(self:shoot_chance(item)) then
        self:skill_xp("fight", SKILLS.xp.hit)
        local dmg = math.max(1, sh.dmg - self:rand(sh.dmg // 4 + 1))
        e.aim = 0
        local how = sh.quiet and ("Your shot from the " .. name .. " strikes the " .. e.def.who)
                              or ("The " .. name .. " cracks. You hit the " .. e.def.who)
        self:enc_hit(dmg, sh.quiet and 15 or G.bleed, how)
        if sh.curse and not e.over then self:enc_say("Something in the dark counts the shot.") end
    else
        self:sfx("miss")
        e.aim = 0
        self:enc_say(sh.quiet and "Your shot goes wide." or ("The " .. name .. " cracks. You miss."))
    end
    if not e.over and not sh.quiet and e.def.kind == "animal" and self:roll(G.animal_flee) then
        self:enc_say("The noise is too much for the " .. e.def.who .. ". It bolts.")
        e.outcome = "fled"
        self:end_encounter("The " .. e.def.who .. " ran from the gunshot.")
    end
end

-- The Elder Sign: whatever it is, it can't stay where the sign is shown.
-- The sign crumbles.
function Game:raise_sign()
    self:take_items("elder_sign", 1)
    self:sfx("emission")
    self:enc_say("You hold up the scratched bone. The air folds around it, and the "
        .. Game.e_name(self.enc.def) .. " is simply not there any more. The bone crumbles to salt.")
    self.enc.outcome = "fled"
    return self:end_encounter("The Elder Sign sent it away.")
end

-- (a horror has no `who` sometimes; its name will do)
function Game.e_name(def)
    return def.who or def.name:lower()
end

-- Gunshots carry: encounters are likelier for a while after.
function Game:noise_mult()
    if self.noise_until and self.player.hours < self.noise_until then return CHURN.guns.noise_mult end
    return 1
end

-- -- armed enemies (CHURN.armed) -------------------------------------------

-- Some people carry a gun: e.gun = {item, rounds}.
function Game:arm_enemy()
    local e = self.enc
    local a = CHURN.armed[e.def.who]
    if not a or not self:roll(a.chance) then return end
    e.gun = {item = a.item, rounds = a.rounds[1] + self:rand(a.rounds[2] - a.rounds[1] + 1)}
    self:enc_say("The " .. e.def.who .. " carries a " .. ITEM_DB[a.item].name .. ".")
end

-- "PM", "Nagant", "Tokarev": for the fight's status line.
function Game:enemy_gun_name()
    local g = self.enc.gun
    return g and g.rounds > 0 and ITEM_DB[g.item].name:match("^%S+")
end

-- An armed enemy short of arm's reach shoots instead of closing in, while
-- its rounds last. Loud, like yours. True when it took its turn.
function Game:enemy_shoots()
    local e, p, A = self.enc, self.player, CHURN.armed
    local g = e.gun
    if not g or e.range == "close" or e.demanding then return false end
    if g.rounds <= 0 then
        if not g.empty then
            g.empty = true
            self:enc_say("The " .. e.def.who .. "'s gun clicks empty. It comes for you instead.")
            return true
        end
        return false
    end
    local a = A[e.def.who]
    g.rounds = g.rounds - 1
    self.noise_until = p.hours + CHURN.guns.noise_hours
    local hit = a.hit - FIGHT.ENEMY_DODGE * (p.attrs.Speed - 3)
        - (e.range == "far" and A.far_penalty or 0) - (e.fog and A.fog or 0)
    local gun = ITEM_DB[g.item].name
    if not self:roll(hit) then
        self:sfx("miss")
        self:enc_say("The " .. e.def.who .. "'s " .. gun .. " cracks. The shot goes past you.")
        return true
    end
    self:enemy_hits(a.dmg, CHURN.guns.bleed, "The " .. e.def.who .. " shoots you")
    return true
end

-- Your loaded gun against their demand: they back off (an end), or call it.
function Game:bluff()
    local e, A = self.enc, CHURN.armed
    e.bluffed = true
    if self:roll(e.gun and A.bluff or A.bluff_unarmed) then
        self:enc_say("You let them see the gun. A long look, then they back away into the ruins.")
        e.outcome = "fled"
        self:end_encounter("The " .. e.def.who .. " backed off from your gun.")
        return true
    end
    e.demanding = false
    self:enc_say("'You won't,' they say, and spread out.")
end

-- On a kill: its gun, and whatever it hadn't fired.
function Game:drop_enemy_gun(found)
    local g = self.enc.gun
    if not g then return end
    self:put_stack("ground", nil, {item = g.item, qty = 1})
    found[#found + 1] = ITEM_DB[g.item].name
    if g.rounds > 0 then
        local ammo = ITEM_DB[g.item].shoot.ammo
        self:put_stack("ground", nil, {item = ammo, qty = g.rounds})
        found[#found + 1] = g.rounds .. " " .. ITEM_DB[ammo].name:lower()
    end
end

-- Rival Churners who'd rather trade (CHURN.parley): one thing you carry that
-- they want, for one of theirs.
function Game:maybe_parley()
    local e, P = self.enc, CHURN.parley
    if e.def.who ~= "rival churner" or not self:roll(P.chance) then return end
    local want
    for _, id in ipairs(P.want) do
        if not want and self:count_item(id) > 0 then want = id end
    end
    if not want then return end
    local give
    self.seed, give = weighted_pick(self.seed, P.give)
    e.parley = {want = want, give = give}
    self:enc_say(P.say)
end

function Game:parley_swap()
    local e, P = self.enc, CHURN.parley
    local pa = e.parley
    self:take_items(pa.want, 1)
    local qty = (ITEM_DB[pa.give].desc or ""):find("^Ammo") and P.rounds or 1   -- (rounds come by the handful)
    self:put_stack("ground", nil, {item = pa.give, qty = qty})
    self:enc_say(P.done)
    e.outcome = "fled"
    return self:end_encounter("You traded with the rival churners: their "
        .. ITEM_DB[pa.give].name:lower() .. " is on the ground.")
end
