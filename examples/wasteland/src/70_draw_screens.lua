-- ---------------------------------------------------------------------
-- Character creator screen
-- rows 1..#ATTRIBUTES are attributes, the rest are TRAITS in order
-- ---------------------------------------------------------------------

local CREATOR_ROWS = #ATTRIBUTES + #TRAITS
-- attributes in the left column, traits in the right (from CREATOR_TRAIT_X),
-- the highlighted row's description and the resulting build below both
local CREATOR_ATTR_Y, CREATOR_TRAIT_Y, CREATOR_ROW_H = 52, 52, 14
local CREATOR_TRAIT_X = 200

function Game:creator_key(key)
    local p = self.player
    local row = self.creator_cursor
    self.creator_msg = nil
    if key == gfx.KEY_UP or key == KEY_W then
        self.creator_cursor = math.max(1, row - 1)
    elseif key == gfx.KEY_DOWN or key == KEY_S then
        self.creator_cursor = math.min(CREATOR_ROWS, row + 1)
    elseif (key == gfx.KEY_LEFT or key == KEY_A or key == gfx.KEY_RIGHT or key == KEY_D)
        and row <= #ATTRIBUTES then
        local name = ATTRIBUTES[row]
        local up = key == gfx.KEY_RIGHT or key == KEY_D
        if up and p.attrs[name] < ATTR_MAX and attr_points_left(p.attrs) > 0 then
            p.attrs[name] = p.attrs[name] + 1
        elseif up and attr_points_left(p.attrs) <= 0 then
            self.creator_msg = "No points left: lower another first."
        elseif not up and p.attrs[name] > ATTR_MIN then
            p.attrs[name] = p.attrs[name] - 1
        end
        recompute_stats(p)
    elseif key == KEY_SPACE and row > #ATTRIBUTES then
        local t = TRAITS[row - #ATTRIBUTES]
        p.traits[t.name] = not p.traits[t.name] or nil
        recompute_stats(p)
    elseif key == KEY_ENTER or key == KEY_LF then
        self:start_game()
    end
end

function Game:draw_creator(w, h)
    local p = self.player
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Create your survivor")
    gfx.font(gfx.FONT_MONO_12)

    gfx.text(6, 36, "Attributes  left " .. attr_points_left(p.attrs))
    for i, name in ipairs(ATTRIBUTES) do
        local y = CREATOR_ATTR_Y + (i - 1) * CREATOR_ROW_H
        local v = p.attrs[name]
        gfx.text(6, y, (self.creator_cursor == i and ">" or " ") .. name)
        for c = 1, ATTR_MAX do
            local cx = 100 + (c - 1) * 12
            if c <= v then gfx.fill_rect(cx, y - 9, 10, 9) else gfx.rect(cx, y - 9, 10, 9) end
        end
        gfx.text(176, y, tostring(v))
    end

    local tleft = trait_points_left(p.traits)
    gfx.text(CREATOR_TRAIT_X, CREATOR_TRAIT_Y - 16, "Traits  left " .. tleft)
    for i, t in ipairs(TRAITS) do
        local row = #ATTRIBUTES + i
        local y = CREATOR_TRAIT_Y + (i - 1) * CREATOR_ROW_H
        local mark = p.traits[t.name] and "[x] " or "[ ] "
        gfx.text(CREATOR_TRAIT_X, y, (self.creator_cursor == row and ">" or " ") .. mark .. t.name)
        -- what it does to the budget: positives spend, negatives give
        local cost = (t.cost > 0 and "-" or "+") .. math.abs(t.cost)
        gfx.text(w - 6 - 7 * #cost, y, cost)
    end

    -- the highlighted row explained, then the build it gives
    local y = CREATOR_TRAIT_Y + #TRAITS * CREATOR_ROW_H + 6
    gfx.line(6, y - 10, w - 6, y - 10)
    local row = self.creator_cursor
    local desc = row <= #ATTRIBUTES and ATTR_DESC[ATTRIBUTES[row]]
        or TRAITS[row - #ATTRIBUTES].desc
    gfx.text(6, y + 4, desc)
    local bag = ITEM_DB.backpack.bag_cells + p.bag_bonus
    gfx.text(6, y + 20, "MP " .. p.max_mp .. " Sight " .. p.sight .. " Finds " .. p.scav_rolls
        .. " Duds " .. dud_percent(p.attrs.Perception) .. "%")
    gfx.text(6, y + 34, "Bag " .. math.max(2, math.min(BACKPACK_CAP, bag)) .. " cells (backpack)")
    if self.creator_msg then
        gfx.text(6, y + 50, self.creator_msg)
    elseif tleft < 0 then
        gfx.text(6, y + 50, "Trait points below 0: can't start.")
    end

    gfx.text(6, h - 20, "Up/Dn row  L/R attribute")
    gfx.text(6, h - 8, "Spc trait  Enter start  Q quit")
    gfx.refresh()
end

-- Encounter screen: name, description, what just happened, status, and the
-- numbered choices (at most 7 rows fit above the bottom edge).
function Game:draw_encounter(w, h)
    local e, p = self.enc, self.player
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, e.def.name)
    gfx.font(gfx.FONT_MONO_12)
    for i, line in ipairs(e.intro) do gfx.text(6, 22 + 13 * i, line) end
    self:draw_portrait(e, w - 102, 18)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    gfx.line(6, 114, w - 108, 114)
    for i, line in ipairs(e.msg) do gfx.text(6, 116 + 13 * i, line) end
    local status = "You " .. math.floor(p.health) .. " HP"
    if p.injuries.bleeding then status = status .. " bleeding" end
    if e.def.hp then
        status = "Range " .. RANGE_NAME[e.range] .. "   " .. status
            .. "   It: " .. (e.seen and self:enemy_condition() or "?")
    end
    gfx.text(6, 186, status)
    gfx.line(6, 192, w - 6, 192)
    for i, o in ipairs(self:encounter_options()) do
        gfx.text(6, 194 + 13 * i, (i == e.cursor and ">" or " ") .. i .. " " .. o[1])
    end
    gfx.refresh()
end

-- A rune: a box with a needle pointing up/right/down/left (0-3).
local function draw_rune(x, y, size, dir)
    gfx.rect(x, y, size, size)
    local cx, cy, r = x + size // 2, y + size // 2, size // 2 - 4
    local dx, dy = ({0, 1, 0, -1})[dir + 1], ({-1, 0, 1, 0})[dir + 1]
    gfx.fill_rect(cx - 2, cy - 2, 5, 5)
    for t = -1, 1 do
        gfx.line(cx + t * dy, cy + t * dx, cx + dx * r + t * dy, cy + dy * r + t * dx)
    end
end

function Game:draw_puzzle(w, h)
    local z = self.puz
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, self.enc.def.name)
    gfx.font(gfx.FONT_MONO_12)
    if z.kind == "bolts" then
        gfx.text(6, 34, "Your detector clicks once for each deadly spot")
        gfx.text(6, 47, "next to you. Reach the glint at the top.")
        local cell = 32
        local x0, y0 = (w - cell * BOLT_N) // 2, 58
        for c = 1, BOLT_N * BOLT_N do
            local x = x0 + ((c - 1) % BOLT_N) * cell
            local y = y0 + ((c - 1) // BOLT_N) * cell
            gfx.color(gfx.BLACK)
            gfx.rect(x, y, cell + 1, cell + 1)
            if z.revealed[c] and z.haz[c] then
                gfx.color(gfx.DARK)
                gfx.fill_rect(x + 2, y + 2, cell - 3, cell - 3)
            elseif z.visited[c] and c ~= z.pos then
                gfx.text(x + 13, y + 21, tostring(bolt_count(z.haz, c)))
            elseif z.revealed[c] then
                gfx.fill_rect(x + 14, y + 14, 5, 5)
            end
            if c == BOLT_GOAL then
                gfx.color(gfx.BLACK)
                gfx.rect(x + 8, y + 8, 17, 17)
                gfx.rect(x + 12, y + 12, 9, 9)
            end
        end
        local px = x0 + ((z.pos - 1) % BOLT_N) * cell
        local py = y0 + ((z.pos - 1) // BOLT_N) * cell
        gfx.color(gfx.BLACK)
        gfx.fill_rect(px + 6, py + 6, cell - 11, cell - 11)
        gfx.color(gfx.WHITE)
        gfx.text(px + 13, py + 21, tostring(bolt_count(z.haz, z.pos)))
        gfx.color(gfx.BLACK)
        gfx.text(6, 238, "Bolts: " .. z.bolts .. (z.aiming and "   (aiming)" or ""))
        gfx.text(6, 254, z.msg)
        gfx.text(6, h - 8, "Arrows move  T+arrow throw a bolt  Esc back away")
    elseif z.kind == "sequence" then
        gfx.text(6, 34, z.showing and "The signs burn in this order. Remember them."
            or "Press the keys for the signs, in order.")
        gfx.text(6, 47, "Round " .. z.round .. " of " .. #SEQ_LENGTHS)
        local n, box = #z.seq, 30
        local x0 = (w - n * (box + 6)) // 2
        for i = 1, n do
            local x = x0 + (i - 1) * (box + 6)
            gfx.rect(x, 80, box, box)
            local shown = z.showing and z.seq[i] or (i <= z.typed and z.seq[i])
            if shown then
                draw_sprite(x + 7, 87, 16, 16, SIGILS[shown])
            else
                gfx.text(x + 12, 100, "?")
            end
        end
        gfx.text(6, 150, "The signs and their keys:")
        for i = 1, 4 do
            local x = 60 + (i - 1) * 80
            gfx.rect(x, 162, 30, 30)
            draw_sprite(x + 7, 169, 16, 16, SIGILS[i])
            gfx.text(x + 12, 208, tostring(i))
        end
        gfx.text(6, h - 8, z.showing and "Any key: hide them   Esc back away" or "Keys 1-4   Esc back away")
    else
        gfx.text(6, 34, "Runes are cut into the stone. Pressing one turns")
        gfx.text(6, 47, "it and its neighbours. Match the carving above.")
        local size, gap = 40, 12
        local x0 = (w - RUNE_N * size - (RUNE_N - 1) * gap) // 2
        gfx.text(6, 72, "Carving:")
        for i = 1, RUNE_N do draw_rune(x0 + (i - 1) * (size + gap), 80, size, z.target[i]) end
        gfx.text(6, 150, "Stone:")
        for i = 1, RUNE_N do
            local x = x0 + (i - 1) * (size + gap)
            draw_rune(x, 158, size, z.cur[i])
            gfx.text(x + 17, 214, tostring(i))
        end
        gfx.text(6, 244, "Presses left: " .. z.moves)
        gfx.text(6, h - 8, "Keys 1-" .. RUNE_N .. "   Esc back away")
    end
    gfx.refresh()
end

function Game:draw_dead(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 40, "You are dead.")
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(6, 70, self.death_cause or "")
    gfx.text(6, 90, "You lasted " .. self.player.hours .. " hours in the wasteland.")
    gfx.text(6, h - 8, "Enter: new survivor  Q: quit")
    gfx.refresh()
end

