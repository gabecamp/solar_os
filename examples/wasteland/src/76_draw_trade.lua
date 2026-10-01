-- ---------------------------------------------------------------------
-- Trade, Checkpoint and ending screens
-- ---------------------------------------------------------------------

local TRADE_UI = {rows = 12, row_h = 14, top = 50, col_x = {mine = 6, theirs = 204}, col_w = 190,
                  gate_intro = "Concrete blocks, razor wire, a tower whose searchlight never "
                      .. "switches off. A sergeant in a gas mask watches you come. 'Nobody "
                      .. "leaves the Zone without paper. Or without paying.'",
                  ending = {
                      permit = "The sergeant reads the permit twice, stamps it without looking "
                          .. "at you and lifts the barrier. On the far side the grass is only "
                          .. "grass. Behind you something vast and patient hums, and you know "
                          .. "you will dream of it every night.",
                      bribe = "The guards weigh the artifacts in their gloved hands. One of "
                          .. "them starts to cry and doesn't know why. They wave you through "
                          .. "without a word, and the barrier drops behind you like a closing eye.",
                  }}

function Game:draw_trade(w, h)
    local u, L = self.trade_ui, TRADE_UI
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Trader")
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(110, 16, ("They ask x%.1f value"):format(TRADE.markup))
    for _, col in ipairs({"mine", "theirs"}) do
        local x = L.col_x[col]
        local rows = self:trade_rows(col)
        local pick = col == "mine" and u.give or u.get
        gfx.color(gfx.BLACK)
        gfx.text(x, 36, col == "mine" and "Your bag  (you give)" or "Trader  (you take)")
        local c = u.cursor[col]
        local first = math.max(1, c - L.rows + 1)
        for i = first, math.min(#rows, first + L.rows - 1) do
            local s = rows[i]
            local y = L.top + (i - first) * L.row_h
            local n = pick[s.item]
            local text = ("%-13s x%-2d %3d%s"):format(ITEM_DB[s.item].name:sub(1, 13), s.qty,
                                                    Game.item_value(s.item), n and (" +" .. n) or "")
            if i == c and col == u.col then
                gfx.color(gfx.BLACK)
                gfx.fill_rect(x - 2, y - 11, L.col_w, L.row_h)
                gfx.color(gfx.WHITE)
            elseif i == c then
                gfx.color(gfx.BLACK)
                gfx.rect(x - 2, y - 11, L.col_w, L.row_h)
            end
            gfx.text(x, y, text)
            gfx.color(gfx.BLACK)
        end
        if #rows == 0 then gfx.text(x, L.top, "(nothing)") end
    end
    gfx.color(gfx.BLACK)
    gfx.line(200, 26, 200, L.top + L.rows * L.row_h - 10)
    local give, ask = self:trade_totals()
    gfx.text(6, 234, ("You give %d   They ask %d"):format(give, ask))
    gfx.text(6, 252, u.msg or "")
    gfx.text(6, h - 8, "Arrows Enter:+1 E:-1 T:deal O:work Q:leave")
    gfx.refresh()
end

function Game:draw_gate(w, h)
    local u = self.gate_ui
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 22, "The Checkpoint")
    gfx.font(gfx.FONT_MONO_12)
    local y = 48
    for _, line in ipairs(wrap(TRADE_UI.gate_intro, 54)) do
        gfx.text(6, y, line)
        y = y + 14
    end
    y = y + 16
    for i, opt in ipairs(u.opts) do
        if i == u.cursor then
            gfx.fill_rect(4, y - 11, 240, 15)
            gfx.color(gfx.WHITE)
        end
        gfx.text(10, y, opt[1])
        gfx.color(gfx.BLACK)
        y = y + 20
    end
    if #u.opts == 1 then
        gfx.text(6, y + 10, ("You need a Zone Permit or %d artifacts."):format(GOAL.bribe))
    end
    gfx.text(6, h - 8, "Up/Dn pick  Enter choose  Q back")
    gfx.refresh()
end

function Game:draw_ending(w, h)
    local e = self.ending
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 30, "You left the Zone.")
    gfx.font(gfx.FONT_MONO_12)
    local y = 60
    local text = (TRADE_UI.ending[e.how] or "") .. (e.lore and (" " .. e.lore) or "")
    for _, line in ipairs(wrap(text, 54)) do
        gfx.text(6, y, line)
        y = y + 14
    end
    y = y + 14
    gfx.text(6, y, ("Day %d. %d hours in the Zone."):format(e.day, e.hours))
    gfx.text(6, y + 16, ("Artifacts carried out: %d"):format(e.artifacts))
    gfx.text(6, h - 8, "Enter: new survivor  Q: quit")
    gfx.refresh()
end
