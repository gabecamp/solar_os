-- ---------------------------------------------------------------------
-- The fishing minigame (G by water with a Fishing Rod; numbers in
-- HUNT.game, 05_data_world). Turn-based, so it plays the same on the
-- device as on a PC.
--
-- Bite: Space waits a beat and watches the float. It lies still, twitches
-- (a nibble), and at last goes under for one beat. Enter strikes: on the
-- plunge it hooks the fish; too early spooks them (a fresh wait, `spooks`
-- times at most), and waiting past the plunge loses the bait.
-- Fight: each turn the fish shows what it's doing, and you answer it:
--   pulls left/right: lean the other way (Right/Left) - it tires
--   dives:            give line (Down) - it tires, the line eases
--   rests:            reel (Up) - it comes in two lengths
-- Up reels any time (it comes in, but the line tightens); Down gives line
-- (it eases, but the fish gets further). A pull tightens the line each turn,
-- a rest eases it. Over the snap point the line breaks; slack too long and
-- it shakes the hook. Bring it in to the bank (distance 0) to land it.
-- self.fishing holds a session; it isn't saved (a quit mid-cast loses it).
-- ---------------------------------------------------------------------

function Game:fish_start()
    self:spend_hours(HUNT.fish_hours)
    self.fishing = {phase = "wait", spooked = 0, turn = 0, msg = "You cast. The float settles. (Space: wait)"}
    self:fish_new_wait()
    self.screen = "fishing"
end

-- A fresh run of beats before the bite: a few still or twitching, then the plunge.
function Game:fish_new_wait()
    local G, f = HUNT.game, self.fishing
    local n = G.wait[1] + self:rand(G.wait[2] - G.wait[1] + 1)
    f.beats, f.beat = {}, 1
    for i = 1, n - 1 do f.beats[i] = self:roll(G.twitch) and "twitch" or "still" end
    f.beats[n] = "plunge"
    f.float = "still"
end

-- Line strength: where it snaps (Perception, Karl's gear).
function Game:fish_snap()
    local G = HUNT.game
    return G.snap + G.snap_per * (self.player.attrs.Perception - 3) + self:fish_bonus() // 2
end

-- The fish takes the hook: which one, and its fight.
function Game:fish_hook()
    local G, f = HUNT.game, self.fishing
    local pick = {}
    for i, d in ipairs(G.fish) do pick[i] = {i, d[3]} end
    local i
    self.seed, i = weighted_pick(self.seed, pick)
    local d = G.fish[i]
    -- skill: a tired fish from the start
    f.kind, f.phase = d, "fight"
    f.stamina = math.max(1, d[4] - self:skill_bonus("fish") // 5)
    f.dist, f.tension, f.slack, f.turn = d[5], G.tension, 0, 0
    f.act = self:fish_act()
    f.msg = "Hooked! " .. self:fish_act_text()
    self:sfx("hit")
end

function Game:fish_act()
    local f = self.fishing
    if f.stamina <= 0 then return "rest" end   -- worn out: it only drifts
    local act
    self.seed, act = weighted_pick(self.seed, HUNT.game.acts)
    return act
end

function Game:fish_act_text()
    local f = self.fishing
    return ({left = "It pulls hard to the left!", right = "It pulls hard to the right!",
             dive = "It dives for the bottom!", lunge = "It LUNGES! Give it line!",
             rest = f.stamina <= 0 and "It's spent. It drifts on the line." or "It rests, finning."})[f.act]
end

-- One key in a session. Returns nothing; self.fishing ends with fish_end.
function Game:fishing_key(key)
    local f = self.fishing
    if not f then self.screen = "map" return end
    if key == KEY.Q or key == gfx.KEY_ESCAPE then
        return self:fish_end(nil, "You reel in and pack up the rod.")
    end
    if f.phase == "done" then
        self.fishing = nil
        self.screen = "map"
        return
    end
    if f.phase == "wait" then return self:fish_wait_key(key) end
    self:fish_fight_key(key)
end

function Game:fish_wait_key(key)
    local G, f = HUNT.game, self.fishing
    local now = f.beats[f.beat]
    if key == KEY.ENTER or key == KEY.LF then
        if now == "plunge" then return self:fish_hook() end
        f.spooked = f.spooked + 1
        if f.spooked > G.spooks then
            return self:fish_end(nil, "You yank at nothing again. Every fish here has gone.")
        end
        self:fish_new_wait()
        f.msg = "You yank at nothing. The ripples spread. Wait..."
        return
    end
    if key ~= KEY.SPACE and key ~= gfx.KEY_DOWN and key ~= KEY.S then return end
    if now == "plunge" then
        return self:fish_end(nil, "The float pops back up. The bait's gone.")
    end
    f.beat = f.beat + 1
    f.float = f.beats[f.beat]
    f.msg = ({still = "The float rides the current.", twitch = "The float twitches...",
              plunge = "The float goes UNDER! (Enter: strike)"})[f.float]
end

function Game:fish_fight_key(key)
    local G, f = HUNT.game, self.fishing
    local act = f.act
    local move = (key == gfx.KEY_LEFT or key == KEY.A) and "left" or (key == gfx.KEY_RIGHT or key == KEY.D) and "right"
        or (key == gfx.KEY_UP or key == KEY.W) and "up" or (key == gfx.KEY_DOWN or key == KEY.S) and "down" or nil
    if not move then return end
    local said
    local pull = act == "left" or act == "right"
    if pull and move ~= "up" and move ~= "down" then
        if move ~= act then   -- leaning against it
            f.tension, f.stamina = f.tension + G.lean.tension, f.stamina - G.lean.tire
            said = "You lean into it. It's tiring."
        else                  -- with it: it runs
            f.tension, f.dist = f.tension + G.wrong.tension, f.dist + G.wrong.dist
            said = "Wrong way! It runs with the line."
        end
    elseif move == "up" then
        local r = act == "rest" and G.reel_rest or G.reel
        f.tension, f.dist = f.tension + r.tension, math.max(0, f.dist - r.dist)
        said = act == "rest" and "You reel it in while it rests." or "You reel against it. The line sings."
    elseif move == "down" then
        if act == "dive" or act == "lunge" then
            f.tension, f.stamina = f.tension + G.give_dive.tension, f.stamina - G.give_dive.tire
            said = "You give it line. It wears itself out going down."
        else
            f.tension, f.dist = f.tension + G.give.tension, f.dist + G.give.dist
            said = "You give it line. It eases, and it gets further away."
        end
    else
        said = "You hold the rod."
    end
    -- the fish's own pull (or a rest): never quite the same twice
    if act == "rest" then
        f.tension = f.tension - G.rest_ease
    elseif act == "lunge" then
        f.tension = f.tension + G.lunge
    else
        f.tension = f.tension + G.pull + G.pull_var[1] + self:rand(G.pull_var[2] - G.pull_var[1] + 1)
    end
    f.tension = math.max(0, f.tension)
    f.stamina = math.max(0, f.stamina)
    f.turn = f.turn + 1
    if f.tension >= self:fish_snap() then
        return self:fish_end(nil, "SNAP. The line parts and it's gone.")
    end
    f.slack = f.tension < G.slack and f.slack + 1 or 0
    if f.slack >= G.slack_turns then
        return self:fish_end(nil, "The line goes slack. It shook the hook.")
    end
    if f.dist <= 0 then return self:fish_land() end
    f.act = self:fish_act()
    f.msg = said .. " " .. self:fish_act_text()
end

-- On the bank: what it was.
function Game:fish_land()
    local G, f = HUNT.game, self.fishing
    local d = f.kind
    local item, qty
    if d[6] == "junk" then
        self.seed, item = weighted_pick(self.seed, G.junk)
        qty = 1
    else
        item, qty = d[6][1], d[6][2]
    end
    local stack = {item = item, qty = qty}
    if not self:put_stack("inventory", nil, stack) then self:put_stack("ground", nil, stack) end
    if d[6] ~= "junk" then
        self:skill_xp("fish", SKILLS.xp.catch * qty)
        self:stat("fish", qty)
    end
    self:sfx("chime")
    local got = ITEM_DB[item].name .. (qty > 1 and (" x" .. qty) or "")
    self:fish_end(true, ("Landed %s! (%s)"):format(d[2], got))
end

-- The session is over: the result line stays up until a key.
function Game:fish_end(caught, text)
    local f = self.fishing
    f.phase, f.msg, f.caught = "done", text, caught
    self:push_log(text:sub(1, 57))
    self:maybe_karl("fish")
    if self.screen ~= "fishing" then self.fishing = nil end   -- (Karl came up the bank)
end

-- -- the screen -----------------------------------------------------------

function Game:draw_fishing(w, h)
    local f = self.fishing
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    Game.ui_title(w, "Fishing")
    -- the water and the bank
    local top, bank_x = 60, 40
    gfx.color(gfx.LIGHT)
    gfx.fill_rect(bank_x, top, w - bank_x - 6, 140)
    gfx.color(gfx.DARK)
    gfx.fill_rect(bank_x, top + 100, w - bank_x - 6, 40)   -- the deep
    gfx.color(gfx.BLACK)
    gfx.line(bank_x, top, w - 6, top)
    gfx.fill_rect(6, top - 10, bank_x - 6, 150)             -- the bank
    -- the rod and the line to the float
    local rod_x, rod_y = bank_x - 4, top - 34
    gfx.line(14, top - 10, rod_x, rod_y)
    local G = HUNT.game
    local fx
    if f.phase == "fight" or (f.phase == "done" and f.kind) then
        local d = f.kind
        fx = bank_x + 10 + math.floor((w - bank_x - 40) * math.min(1, (f.dist or 0) / d[5]))
    else
        fx = w - 60
    end
    local fy = top + (f.float == "plunge" and 14 or f.float == "twitch" and 3 or 0)
    if f.phase == "fight" then fy = top + 30 end
    gfx.line(rod_x, rod_y, fx, fy)
    if f.phase ~= "fight" then   -- the float: a white ring with a black cap
        gfx.color(gfx.WHITE)
        gfx.fill_rect(fx - 4, fy - 4, 8, 8)
        gfx.color(gfx.BLACK)
        gfx.rect(fx - 4, fy - 4, 8, 8)
        gfx.fill_rect(fx - 2, fy - 10, 4, 6)
        if f.float == "twitch" then
            gfx.rect(fx - 9, fy + 2, 18, 3)
        elseif f.float == "plunge" then
            gfx.rect(fx - 14, top - 1, 28, 4)
            gfx.rect(fx - 20, top - 2, 40, 6)
        end
    else                         -- the fish on the line, and which way it goes
        gfx.fill_rect(fx - 10, fy - 3, 20, 7)
        gfx.fill_rect(f.act == "right" and fx - 13 or fx + 8, fy - 6, 5, 13)   -- (the tail: away from where it goes)
        local ax = f.act == "left" and -1 or f.act == "right" and 1 or 0
        if f.act == "lunge" then gfx.rect(fx - 16, fy - 10, 32, 20) end   -- (thrashing)
        if ax ~= 0 then
            local x0 = fx + ax * 18
            gfx.line(x0, fy, x0 + ax * 22, fy)
            gfx.line(x0 + ax * 22, fy, x0 + ax * 16, fy - 5)
            gfx.line(x0 + ax * 22, fy, x0 + ax * 16, fy + 5)
        elseif f.act == "dive" or f.act == "lunge" then
            gfx.line(fx, fy + 8, fx, fy + 40)
            gfx.line(fx, fy + 40, fx - 5, fy + 34)
            gfx.line(fx, fy + 40, fx + 5, fy + 34)
        end
    end
    -- the tension bar (the snap point marked), under the water
    local y = top + 152
    if f.phase == "fight" or (f.phase == "done" and f.tension) then
        local snap = self:fish_snap()
        local bw = w - 70
        gfx.text(6, y + 9, "Line")
        gfx.rect(50, y, bw, 12)
        gfx.fill_rect(50, y, math.floor(bw * math.min(1, f.tension / snap)), 12)
        gfx.color(gfx.DARK)
        gfx.fill_rect(50 + math.floor(bw * G.slack / snap), y - 3, 2, 18)   -- slack below this
        gfx.color(gfx.BLACK)
        gfx.text(50 + bw + 4, y + 9, "!")
        if f.phase == "fight" then
            gfx.text(6, y + 26, ("%d lengths out%s"):format(f.dist, f.stamina <= 0 and ", worn out" or ""))
        end
    end
    -- what's happening, and the keys
    local ly = y + 44
    for i, line in ipairs(wrap(f.msg or "", 55)) do
        if i <= 2 then gfx.text(6, ly + 13 * (i - 1), line) end
    end
    Game.ui_keys(w, h, f.phase == "wait" and "Space wait  Enter strike  Q stop"
        or f.phase == "fight" and "Lt/Rt lean  Up reel  Dn give line  Q cut"
        or "Any key: back")
    gfx.refresh()
end
