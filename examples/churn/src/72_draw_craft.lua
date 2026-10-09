-- ---------------------------------------------------------------------
-- Crafting screen (400x300): known recipes on the left, the selected one's
-- needs on the right (have/need for each input), then the log and keys.
-- ---------------------------------------------------------------------

local CRAFT_UI = {list_y = 38, row_h = 15, detail_x = 196}   -- one local: see the 200-local note in 35_crafting

function Game:draw_craft(w, h)
    local list = self:known_recipes()
    local c = self.craft_ui
    c.cursor = math.max(1, math.min(c.cursor, #list))
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    local camp = self.camps[hex_key(self.player.q, self.player.r)]
    local fire = self:fire_here()
        and (camp and camp.until_hour > self.player.hours and ("Fire: " .. (camp.until_hour - self.player.hours) .. "h left") or "Fire burning") or "No fire here"
    Game.ui_title(w, "Crafting", fire)

    -- the list: a mark for what you can make right now. It scrolls: only
    -- `rows` fit above the log, so the window follows the cursor.
    local rows = (h - 64 - CRAFT_UI.list_y) // CRAFT_UI.row_h
    local first = math.max(1, math.min(c.cursor - rows + 1, #list - rows + 1))
    for i, r in ipairs(list) do
      if i >= first and i < first + rows then
        local y = CRAFT_UI.list_y + (i - first) * CRAFT_UI.row_h
        local ready = self:craft_blocker(r) == nil
        if i == c.cursor then
            gfx.fill_rect(4, y - 11, CRAFT_UI.detail_x - 12, CRAFT_UI.row_h - 1)
            gfx.color(gfx.WHITE)
        end
        gfx.text(8, y, (ready and "+ " or "  ") .. r.name)
        gfx.color(gfx.BLACK)
      end
    end
    if first > 1 then gfx.text(CRAFT_UI.detail_x - 20, CRAFT_UI.list_y, "^") end
    if first + rows <= #list then
        gfx.text(CRAFT_UI.detail_x - 20, CRAFT_UI.list_y + (rows - 1) * CRAFT_UI.row_h, "v")
    end
    local unknown = 0
    for _, rr in ipairs(RECIPES) do if not self.known[rr.id] then unknown = unknown + 1 end end
    local ly = CRAFT_UI.list_y + math.min(#list, rows) * CRAFT_UI.row_h + 8
    if unknown > 0 and ly + 13 < h - 64 then
        gfx.text(8, ly, unknown .. " more unknown:")
        gfx.text(8, ly + 13, "study, read, listen")
    end
    gfx.line(CRAFT_UI.detail_x - 4, 26, CRAFT_UI.detail_x - 4, h - 60)

    -- the selected recipe
    local r = list[c.cursor]
    if r then
        local x, y = CRAFT_UI.detail_x + 4, CRAFT_UI.list_y
        local icon = r.out and SPRITES[r.out[1]]
        if icon and draw_sprite then
            draw_sprite(w - 26, y - 12, SPRITE_W, SPRITE_H, icon)
        end
        gfx.text(x, y, r.out and ("Makes: " .. ITEM_DB[r.out[1]].name .. (r.out[2] > 1 and (" x" .. r.out[2]) or ""))
            or (r.study and self:study_text(r.study))
            or (r.clean and "Cleans your guns: less jamming")
            or (r.base == "claim" and "Makes this ruin your camp")
            or (r.base and ("Builds at your camp"))
            or (r.mend and self:mend_text())
            or (r.burn and ("Lights a small fire (" .. r.burn .. "h)"))
            or "Builds a campfire here")
        -- what it makes: its numbers, then what it's for (three lines at most)
        local cols = (w - x - 6) // 7
        if r.out then
            local d, lines = ITEM_DB[r.out[1]], {}
            for _, text in ipairs({self:item_stats(r.out[1]) or false, d.desc or false}) do
                if text then for _, l in ipairs(wrap(text, cols)) do lines[#lines + 1] = l end end
            end
            for i = 1, math.min(3, #lines) do gfx.text(x, y + 13 * i, lines[i]) end
            y = y + 13 * math.min(3, #lines)
        end
        y = y + 18
        if r.study then   -- research: the topic's book doubles it
            local book = Game.topic_def(r.study).book
            local have = self:count_item(book) > 0
            gfx.text(x, y, "Book: " .. ITEM_DB[book].name)
            y = y + 13
            gfx.text(x + 7, y, have and "in reach: x2 points" or "(would double it)")
        else
            gfx.text(x, y, "Uses:")
        end
        for _, iq in ipairs(Game.recipe_inputs(r)) do
            y = y + 13
            local have = self:count_item(iq[1])
            gfx.text(x + 7, y, Game.input_name(iq[1]) .. " " .. math.min(have, 99) .. "/" .. iq[2]
                .. (have >= iq[2] and "" or "  x"))
        end
        for _, tool in ipairs(r.tools or {}) do
            y = y + 13
            gfx.text(x, y, "Tool: " .. Game.input_name(tool) .. (self:count_item(tool) > 0 and "" or "  x"))
        end
        if r.fire then
            y = y + 13
            gfx.text(x, y, "Needs a fire" .. (self:fire_here() and "" or "  x"))
        end
        y = y + 18
        gfx.text(x, y, "Takes " .. self:craft_hours(r) .. "h")
        if r.repair then   -- repairs can fail (and burn a part)
            y = y + 14
            gfx.text(x, y, "Chance " .. self:repair_chance(r.repair) .. "% (Perception)")
        elseif r.chance then
            y = y + 14
            gfx.text(x, y, "Chance " .. self:craft_chance(r) .. "% (Perception)")
        end
        y = y + 18
        local why = self:craft_blocker(r)
        for i, line in ipairs(wrap(why or "Ready: Enter to make it.", cols)) do
            if y + (i - 1) * 13 < h - 56 then gfx.text(x, y + (i - 1) * 13, line) end
        end
    end

    -- log and keys
    gfx.line(6, h - 52, w - 6, h - 52)
    local start_i = math.max(1, #self.log - 1)
    local yy = h - 36
    for i = start_i, #self.log do
        gfx.text(6, yy, self.log[i])
        yy = yy + 13
    end
    Game.ui_keys(w, h, "Up/Dn pick  Enter make  C/Esc back  Q quit")
    gfx.refresh()
end
