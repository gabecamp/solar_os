-- ---------------------------------------------------------------------
-- Karl (K-A-R-L), the riddling fisherman. Numbers and riddles in KARL.
--
-- Rare, and only by water: maybe_karl runs on moves (from maybe_encounter)
-- and after fishing. He asks a riddle he hasn't asked yet (karl_asked);
-- a right answer gets one of KARL.rewards, worn/lure gear only once
-- (karl_gave). Either way he's gone for KARL.cooldown hours (karl_next).
-- His portrait is a placeholder smiley until art/karl.jpg is supplied.
-- ---------------------------------------------------------------------

function Game:maybe_karl(how)
    local p = self.player
    if not self:near_water() or p.hours < (self.karl_next or 0) then return false end
    if not self:roll(how == "fish" and KARL.fish_chance or KARL.chance) then return false end
    self:start_karl()
    return true
end

function Game:start_karl()
    self.karl_next = self.player.hours + KARL.cooldown
    self.karl_asked = self.karl_asked or {}
    local fresh = {}
    for i in ipairs(KARL.riddles) do
        if not self.karl_asked[i] then fresh[#fresh + 1] = i end
    end
    if #fresh == 0 then   -- he's asked them all: start over
        self.karl_asked = {}
        for i in ipairs(KARL.riddles) do fresh[#fresh + 1] = i end
    end
    local i = fresh[self:rand(#fresh) + 1]
    self.karl_asked[i] = true
    local riddle = KARL.riddles[i]
    -- shuffle the answers; remember where the right one (listed first) went
    local order = {1, 2, 3}
    for j = #order, 2, -1 do
        local k = self:rand(j) + 1
        order[j], order[k] = order[k], order[j]
    end
    local answers, right = {}, nil
    for slot, idx in ipairs(order) do
        answers[slot] = riddle.a[idx]
        if idx == 1 then right = slot end
    end
    self:start_encounter({kind = "riddle", name = "Karl", art = "karl", who = "Karl",
                          intro = KARL.intro, start = "near"})
    self.enc.riddle = {answers = answers, right = right}
    self:enc_say("Karl: '" .. riddle.q .. "'")
end

-- A reward Karl hasn't already given (gear only once; Pilk and rods repeat).
function Game:karl_reward()
    self.karl_gave = self.karl_gave or {}
    local pool = {}
    for _, item in ipairs(KARL.rewards) do
        local once = ITEM_DB[item].slot or ITEM_DB[item].fish_bonus
        if not (once and self.karl_gave[item]) then pool[#pool + 1] = item end
    end
    if #pool == 0 then pool = {"pilk"} end
    local item = pool[self:rand(#pool) + 1]
    self.karl_gave[item] = true
    return item
end

function Game:karl_answer(n)
    local e = self.enc
    if n == e.riddle.right then
        local item = self:karl_reward()
        local stack = {item = item, qty = 1}
        if not self:put_stack("inventory", nil, stack) then self:put_stack("ground", nil, stack) end
        local name = ITEM_DB[item].name
        self:enc_say("'Ha! Sharp one.' Karl hands you " .. (item == "pilk" and "a bottle of Pilk. "
            .. "'Pepsi and milk. Trust me.'" or "his " .. name .. "."))
        self:end_encounter("Karl gave you " .. name .. ".")
    else
        self:enc_say("Karl laughs. 'Wrong. The river keeps its secrets.' He wades off downstream.")
        self:end_encounter("Karl waded off, laughing.")
    end
end

-- Fishing bonus % from Karl's gear: worn items, and a carried lure.
function Game:fish_bonus()
    local p, bonus = self.player, 0
    for slot, item in pairs(p.equipped) do
        if not HOLD_SLOTS[slot] then bonus = bonus + (ITEM_DB[item].fish_bonus or 0) end
    end
    if self:carrying("lucky_lure") then bonus = bonus + ITEM_DB.lucky_lure.fish_bonus end
    return bonus
end
