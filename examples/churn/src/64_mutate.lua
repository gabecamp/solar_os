-- ---------------------------------------------------------------------
-- Mutations (numbers in CHURN.mutate): each radiation stage you reach for
-- the first time (Irradiated, Rad sick, Rad poisoned) offers two changes,
-- a gain and a cost each, or none (Refuse). The choice is for good, even
-- after the sickness fades. p.mutations[id] = true and p.mut_stage (the
-- highest stage already offered) are on the player, so they're saved; the
-- effects are added in recompute_stats (20_world), armor in enemy_hits and
-- night in refresh_view.
-- ---------------------------------------------------------------------

-- From the main loop (show_queued_scene): a choice is now on screen.
function Game:mutation_offer()
    local p = self.player
    if self.screen ~= "map" then return false end
    local stage = (p.mut_stage or 0) + 1
    if stage > #CHURN.mutate.stages or self:rad_stage() < stage then return false end
    self.mut = {stage = stage, cursor = 1}
    self.screen = "mutate"
    self:sfx("emission")
    return true
end

function Game:mutate_choose(i)
    local p, M = self.player, self.mut
    local opts = CHURN.mutate.stages[M.stage]
    p.mut_stage = M.stage
    if opts[i] then
        p.mutations = p.mutations or {}
        p.mutations[opts[i].id] = true
        recompute_stats(p)
        self:dread(CHURN.mutate.dread)
        self:push_log(("You change: %s. (%s; %s)"):format(opts[i].name, opts[i].gain, opts[i].cost))
    else
        self:push_log("You fight it, and your body keeps its shape. For now.")
    end
    self.mut = nil
    self.screen = "map"
end

function Game:mutate_key(key)
    local M = self.mut
    if not M then self.screen = "map" return end
    local n = #CHURN.mutate.stages[M.stage] + 1   -- (the last row: refuse)
    if key == gfx.KEY_UP or key == KEY.W then
        M.cursor = math.max(1, M.cursor - 1)
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        M.cursor = math.min(n, M.cursor + 1)
    elseif key >= 49 and key < 49 + n then
        self:mutate_choose(key - 48)
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        self:mutate_choose(M.cursor)
    end
end

function Game:draw_mutate(w, h)
    local M = self.mut
    local opts = CHURN.mutate.stages[M.stage]
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    Game.ui_title(w, "The Churn changes you", ("%d of %d"):format(M.stage, #CHURN.mutate.stages))
    gfx.font(gfx.FONT_MONO_12)
    local y = 40
    for _, l in ipairs(wrap(RAD.stages[M.stage].onset .. " Something in you settles into a new shape. "
            .. "Choose it, or fight it.", 55)) do
        gfx.text(8, y, l)
        y = y + 13
    end
    y = y + 8
    for i = 1, #opts + 1 do
        local o = opts[i]
        local bh = o and 52 or 22
        if i == M.cursor then
            gfx.fill_rect(4, y - 12, w - 8, bh)
            gfx.color(gfx.WHITE)
        else
            gfx.rect(4, y - 12, w - 8, bh)
        end
        if o then
            gfx.text(10, y, i .. "  " .. o.name)
            gfx.text(34, y + 15, "+ " .. o.gain)
            gfx.text(34, y + 28, "- " .. o.cost)
        else
            gfx.text(10, y, i .. "  Refuse. Stay as you are.")
        end
        gfx.color(gfx.BLACK)
        y = y + bh + 6
    end
    Game.ui_keys(w, h, "Up/Dn pick  Enter choose  1-3")
    gfx.refresh()
end

-- The status page's lines: each mutation you have and what it does.
function Game:mutation_lines()
    local out = {}
    for _, stage in ipairs(CHURN.mutate.stages) do
        for _, m in ipairs(stage) do
            if (self.player.mutations or {})[m.id] then
                for i, l in ipairs(wrap(("%s: %s; %s"):format(m.name, m.gain, m.cost), 53)) do
                    out[#out + 1] = (i == 1 and "  " or "    ") .. l
                end
            end
        end
    end
    return out
end
