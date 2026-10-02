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
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Crafting")
    gfx.font(gfx.FONT_MONO_12)
    local camp = self.camps[hex_key(self.player.q, self.player.r)]
    local fire = self:fire_here()
        and ("Fire here: " .. (camp.until_hour - self.player.hours) .. "h left") or "No fire here"
    gfx.text(w - 6 - 7 * #fire, 16, fire)
    gfx.line(6, 22, w - 6, 22)

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
        gfx.text(8, ly + 13, "read Scrawled Notes")
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
        gfx.text(x, y, r.out and ("Makes: " .. ITEM_DB[r.out[1]].name)
            or (r.base == "claim" and "Makes this ruin your camp")
            or (r.base and ("Builds at your camp"))
            or (r.mend and self:mend_text())
            or "Builds a campfire here")
        y = y + 18
        gfx.text(x, y, "Uses:")
        for _, iq in ipairs(Game.recipe_inputs(r)) do
            y = y + 13
            local have = self:count_item(iq[1])
            gfx.text(x + 7, y, ITEM_DB[iq[1]].name .. " " .. math.min(have, 99) .. "/" .. iq[2]
                .. (have >= iq[2] and "" or "  x"))
        end
        for _, tool in ipairs(r.tools or {}) do
            y = y + 13
            gfx.text(x, y, "Tool: " .. ITEM_DB[tool].name .. (self:count_item(tool) > 0 and "" or "  x"))
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
        end
        y = y + 18
        local why = self:craft_blocker(r)
        for i, line in ipairs(wrap(why or "Ready: Enter to make it.", (w - x - 6) // 7)) do
            gfx.text(x, y + (i - 1) * 13, line)
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
    gfx.text(6, h - 6, "Up/Dn pick  Enter make  C/Esc back  Q quit")
    gfx.refresh()
end
