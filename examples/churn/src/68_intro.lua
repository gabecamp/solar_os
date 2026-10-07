-- ---------------------------------------------------------------------
-- The intro: a splash on every launch (its picture, "THE CHURN" in
-- big block letters, an epigraph), then the title menu, then - for a
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
    title = "THE CHURN", cell = 5,
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
    self.muted = saved and saved.muted or nil   -- (sound off last time: still off)
    self:sfx("title")
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

-- The title screens' pictures (art/splash.png -> Game.SPLASH_ART on the
-- start screen, art/title.png -> Game.TITLE_ART on the title menu; baked
-- into 69_title_art by tools/paint_title.py): non-blank tiles, decoded once.
Game.ART_TILES = {}
function Game.art_tiles(name)
    if Game.ART_TILES[name] then return Game.ART_TILES[name] end
    local A, tiles = Game[name], {}
    if A then
        local bytes, empty = A.data, string.rep("\0", 128)
        for ty = 0, A.th - 1 do
            for tx = 0, A.tw - 1 do
                local k = (ty * A.tw + tx) * 128
                local tile = bytes:sub(k + 1, k + 128)
                if tile ~= empty then tiles[#tiles + 1] = {x = tx * 32, y = ty * 32, data = tile} end
            end
        end
    end
    Game.ART_TILES[name] = tiles
    return tiles
end

function Game.draw_art(name, x, y)
    if not (draw_sprite and Game[name]) then return end   -- (no bitmaps: text only)
    gfx.color(gfx.BLACK)
    for _, t in ipairs(Game.art_tiles(name)) do draw_sprite(x + t.x, y + t.y, 32, 32, t.data) end
    gfx.rect(x - 1, y - 1, Game[name].w + 2, Game[name].h + 2)
end

-- The picture on the left; the right panel starts here.
Game.INTRO.panel = 204

function Game:draw_intro(w, h)
    local I, px = Game.INTRO, Game.INTRO.panel
    local mid = px + (w - px) // 2
    gfx.clear(gfx.WHITE)
    Game.draw_art("SPLASH_ART", 4, 6)
    gfx.color(gfx.BLACK)
    for i, word in ipairs({"THE", "CHURN"}) do
        Game.draw_big_text(word, mid - ((#word * 6 - 1) * I.cell) // 2, 28 + (i - 1) * 48, I.cell)
    end
    gfx.font(gfx.FONT_MONO_12)
    local y = 150
    for _, line in ipairs(wrap(table.concat(I.epigraph, " "), (w - px - 6) // 7)) do
        gfx.text(mid - (#line * 7) // 2, y, line)
        y = y + 16
    end
    self:draw_intro_prompt(w, h)
    gfx.refresh()
end

function Game:draw_intro_prompt(w, h)
    local text, px = "- press any key -", Game.INTRO.panel
    gfx.color(gfx.WHITE)
    gfx.fill_rect(px, h - 40, w - px, 20)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    if (self.intro_phase or 0) % 4 ~= 3 then
        gfx.text(px + (w - px - #text * 7) // 2, h - 26, text)
    end
end

-- An idle poll on the splash: the prompt blinks (only it is redrawn).
function Game:intro_tick(w, h)
    self.intro_phase = (self.intro_phase or 0) + 1
    self:draw_intro_prompt(w, h)
    gfx.refresh()
end

function Game:intro_key(key)
    if key == KEY.Q then
        self.quit = true
        return
    end
    if not self.update_checked and Game.update_possible() then   -- (38_update)
        local w, h = gfx.size()
        local px = Game.INTRO.panel
        gfx.color(gfx.WHITE)
        gfx.fill_rect(px, h - 40, w - px, 20)
        gfx.color(gfx.BLACK)
        gfx.font(gfx.FONT_MONO_12)
        gfx.text(px + 10, h - 26, "Checking for updates...")
        gfx.refresh()
        self:update_check()
    end
    self.screen = "title"
end

-- The title menu: Continue (with a save), New survivor.
function Game:title_rows()
    local rows = {}
    local d = self.title_save
    if d then
        rows[#rows + 1] = {("Continue (day %d, %d HP)"):format(
            (WORLD.start_hour + d.player.hours) // 24 + 1, math.floor(d.player.health or 0)), "continue"}
    end
    rows[#rows + 1] = {"New survivor", "new"}
    if self.update_avail then rows[#rows + 1] = {"Update to " .. self.update_avail, "update"} end
    return rows
end

function Game:draw_title(w, h)
    local I, px = Game.INTRO, Game.INTRO.panel
    local mid = px + (w - px) // 2
    gfx.clear(gfx.WHITE)
    Game.draw_art("TITLE_ART", 4, 6)
    gfx.color(gfx.BLACK)
    local tw = (#I.title * 6 - 1) * 3
    Game.draw_big_text(I.title, mid - tw // 2, 30, 3)
    gfx.font(gfx.FONT_MONO_12)
    local sub = "a survival game"
    gfx.text(mid - (#sub * 7) // 2, 70, sub)
    for i, row in ipairs(self:title_rows()) do
        local y = 120 + (i - 1) * 24
        if i == self.title_cursor then
            gfx.fill_rect(px, y - 13, w - px - 4, 18)
            gfx.color(gfx.WHITE)
        end
        gfx.text(px + 6, y, row[1])
        gfx.color(gfx.BLACK)
    end
    -- a newer version is out, or how the update went
    local note = self.update_msg or (self.update_avail and "A new version is out.")
    if note then
        local y = 120 + #self:title_rows() * 24 + 4
        for _, line in ipairs(wrap(note, (w - px - 10) // 7)) do
            if y < h - 34 then gfx.text(px + 6, y, line) end
            y = y + 13
        end
    end
    gfx.text(px + 6, h - 22, "Up/Dn pick  Enter go")
    gfx.text(px + 6, h - 8, "R records   Q quit")
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
        if pick[2] == "update" then
            self:update_download()
            self.title_cursor = 1
            return
        end
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
