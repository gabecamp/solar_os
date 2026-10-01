-- ---------------------------------------------------------------------
-- Anomaly puzzles (bolt field, sequence, runes): started by an anomaly
-- encounter's Probe, keys routed here by encounter_key. Numbers in
-- 07_data_encounters (ANOMALIES, BOLT_*, SEQ_LENGTHS, RUNE_*).
-- ---------------------------------------------------------------------

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
