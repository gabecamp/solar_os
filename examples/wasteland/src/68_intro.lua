-- ---------------------------------------------------------------------
-- The intro: a splash on every launch ("THE CHURN" in big block letters,
-- a slowly turning eye, an epigraph), then the title menu, then - for a
-- new survivor - a short story crawl before the creator.
--   screen "intro" -> "title" -> "crawl" -> "creator"
-- The tests and the balance sim build games with Game.new() and never
-- pass through here; only the main loop does (Game:begin_intro).
-- ---------------------------------------------------------------------

Game.INTRO = {
    -- 5x7 block letters, "#" = filled
    glyphs = {
        T = {"#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."},
        H = {"#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"},
        E = {"#####", "#....", "#....", "####.", "#....", "#....", "#####"},
        C = {".####", "#....", "#....", "#....", "#....", "#....", ".####"},
        U = {"#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."},
        R = {"####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"},
        N = {"#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"},
    },
    title = "THE CHURN", cell = 5, eye_r = 44,
    epigraph = {"The land does not lie still. It turns over in its",
                "sleep, and what it turns up, it remembers."},
    -- New survivor: the story so far, a page at a time
    crawl = {
        {"THE INSTITUTE",
         "There was an Institute out by the old quarry. The town was told the hum "
         .. "was a transformer fault, and not to talk about the birds. Lorries came "
         .. "at night with crates that were warm to the touch. One of them, a "
         .. "driver swore, was singing."},
        {"THE FIRST EMISSION",
         "Then the sky over the quarry turned purple and breathed. Nobody outside "
         .. "lived. Those in the cellars came up two days later into fields that "
         .. "had changed: grass in spirals, dogs that came back wrong, roads that "
         .. "no longer went where they had gone."},
        {"THE CHURN",
         "The land began to turn. Not fast; the way a sleeper turns. Hills fold, "
         .. "rivers drift a field to the left, and what was buried comes up again: "
         .. "tins, tapes, guns, bones. The soldiers fenced it off and called it "
         .. "the Churn. They let no one out without paper."},
        {"YOU",
         "You wake in the grass with nothing. Not even shoes. Somewhere there is "
         .. "a Trader, and past him a Checkpoint. Learn what the dead knew - their "
         .. "books, their tapes, their drives - and walk out. Or stay, and be "
         .. "turned over with the rest."},
    },
}

-- Start-up from the main loop: the splash first, then the title menu.
function Game:begin_intro(saved)
    self.title_save = saved
    self.title_cursor = 1
    self.intro_phase = 0
    self.screen = "intro"
end

-- Big letters from runs of filled cells (one fill_rect per run).
function Game.draw_big_text(text, x, y, cell)
    local G = Game.INTRO.glyphs
    for i = 1, #text do
        local rows = G[text:sub(i, i)]
        if rows then
            for ry, row in ipairs(rows) do
                local start
                for cx = 1, #row + 1 do
                    local on = row:sub(cx, cx) == "#"
                    if on and not start then start = cx end
                    if not on and start then
                        gfx.fill_rect(x + (start - 1) * cell, y + (ry - 1) * cell, (cx - start) * cell, cell)
                        start = nil
                    end
                end
            end
        end
        x = x + 6 * cell
    end
end

-- The turning eye: three spiral arms around a pupil, rotated by phase.
function Game:draw_intro_eye(cx, cy, phase)
    local R = Game.INTRO.eye_r
    gfx.color(gfx.WHITE)
    gfx.fill_rect(cx - R - 2, cy - R - 2, 2 * R + 5, 2 * R + 5)
    gfx.color(gfx.BLACK)
    gfx.circle(cx, cy, R)
    for arm = 0, 2 do
        local px, py
        for s = 0, 14 do
            local t = s / 14
            local a = phase * 0.35 + arm * 2.094 + t * 4.2
            local r = 8 + t * (R - 10)
            local x, y = cx + math.floor(r * math.cos(a)), cy + math.floor(r * math.sin(a) * 0.8)
            if px then gfx.line(px, py, x, y) end
            px, py = x, y
        end
    end
    gfx.fill_circle(cx, cy, 6)
    gfx.color(gfx.WHITE)
    gfx.pixel(cx - 2, cy - 2)
    gfx.color(gfx.BLACK)
end

function Game:draw_intro(w, h)
    local I = Game.INTRO
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    local tw = (#I.title * 6 - 1) * I.cell
    Game.draw_big_text(I.title, (w - tw) // 2, 18, I.cell)
    self:draw_intro_eye(w // 2, 120, self.intro_phase or 0)
    gfx.font(gfx.FONT_MONO_12)
    for i, line in ipairs(I.epigraph) do
        gfx.text((w - #line * 7) // 2, 196 + (i - 1) * 16, line)
    end
    self:draw_intro_prompt(w, h)
    gfx.refresh()
end

function Game:draw_intro_prompt(w, h)
    local text = "- press any key -"
    gfx.color(gfx.WHITE)
    gfx.fill_rect(0, h - 40, w, 20)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    if (self.intro_phase or 0) % 4 ~= 3 then gfx.text((w - #text * 7) // 2, h - 26, text) end
end

-- An idle poll on the splash: turn the eye a little (only it is redrawn).
function Game:intro_tick(w, h)
    self.intro_phase = (self.intro_phase or 0) + 1
    self:draw_intro_eye(w // 2, 120, self.intro_phase)
    self:draw_intro_prompt(w, h)
    gfx.refresh()
end

function Game:intro_key(key)
    if key == KEY.Q then
        self.quit = true
    else
        self.screen = "title"
    end
end

-- The title menu: Continue (with a save), New survivor.
function Game:title_rows()
    local rows = {}
    local d = self.title_save
    if d then
        rows[#rows + 1] = {("Continue  (day %d, %d HP)"):format(
            (WORLD.start_hour + d.player.hours) // 24 + 1, math.floor(d.player.health or 0)), "continue"}
    end
    rows[#rows + 1] = {"New survivor", "new"}
    return rows
end

function Game:draw_title(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    local I = Game.INTRO
    local tw = (#I.title * 6 - 1) * 3
    Game.draw_big_text(I.title, (w - tw) // 2, 40, 3)
    gfx.font(gfx.FONT_MONO_12)
    local sub = "a survival game"
    gfx.text((w - #sub * 7) // 2, 80, sub)
    for i, row in ipairs(self:title_rows()) do
        local y = 130 + (i - 1) * 24
        if i == self.title_cursor then
            gfx.fill_rect(w // 2 - 110, y - 13, 220, 18)
            gfx.color(gfx.WHITE)
        end
        gfx.text(w // 2 - 100, y, row[1])
        gfx.color(gfx.BLACK)
    end
    gfx.text(6, h - 8, "Up/Dn pick  Enter choose  R records  Q quit")
    gfx.refresh()
end

function Game:title_key(key)
    local rows = self:title_rows()
    if key == gfx.KEY_UP or key == KEY.W then
        self.title_cursor = math.max(1, self.title_cursor - 1)
    elseif key == gfx.KEY_DOWN or key == KEY.S then
        self.title_cursor = math.min(#rows, self.title_cursor + 1)
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        local pick = rows[self.title_cursor] or rows[#rows]
        if pick[2] == "continue" then
            self:load_state(self.title_save)
        else
            self.crawl_page = 1
            self.screen = "crawl"
        end
        self.title_save = nil
    end
end

function Game:draw_crawl(w, h)
    local page = Game.INTRO.crawl[self.crawl_page or 1]
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(14, 40, page[1])
    gfx.font(gfx.FONT_MONO_12)
    local y = 74
    for _, line in ipairs(wrap(page[2], 52)) do
        gfx.text(14, y, line)
        y = y + 18
    end
    gfx.text(w - 60, 22, ("%d/%d"):format(self.crawl_page or 1, #Game.INTRO.crawl))
    gfx.text(6, h - 8, "Enter: on   Esc: skip")
    gfx.refresh()
end

function Game:crawl_key(key)
    if key == gfx.KEY_ESCAPE or key == KEY.Q then
        self.screen = "creator"
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE or key == gfx.KEY_RIGHT or key == KEY.D then
        self.crawl_page = (self.crawl_page or 1) + 1
        if self.crawl_page > #Game.INTRO.crawl then self.screen = "creator" end
    end
end
