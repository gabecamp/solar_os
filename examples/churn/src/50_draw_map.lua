-- ---------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------

local function shade_color(name)
    return gfx[name]
end

-- gfx draw calls appear to require integer coordinates (fill_rect at least
-- throws on a float); our hex math is full of sqrt(3)/trig-derived floats,
-- so every computed coordinate gets rounded right before it reaches gfx.*.
local function rnd(v)
    return math.floor(v + 0.5)
end

-- Draw a terrain glyph centered on (cx, cy) in the given color.
local function draw_glyph(terrain_id, cx, cy, color)
    if not draw_sprite then return end
    gfx.color(color)
    draw_sprite(rnd(cx) - GLYPH_W // 2, rnd(cy) - GLYPH_H // 2, GLYPH_W, GLYPH_H, GLYPHS[terrain_id])
end

-- Map screen (400x300 landscape): the hex map in the left MAP_W pixels
-- between MAP_TOP and MAP_BOTTOM; the HUD and the terrain legend in a panel
-- to its right (from PANEL_X); the log and key hints across the bottom.
local MAP_W, MAP_TOP, MAP_BOTTOM = 256, 4, 236
local PANEL_X = 262
local LEGEND_Y = 148
local LEGEND_ORDER = {"plains", "forest", "hills", "ruins", "ford", "water"}

-- You, your Little Ones and your dog, at your hex's center.
function Game:draw_player_mark(px, py)
    -- you: a stick figure on a white halo, so it reads on dark tiles
    if draw_sprite then
        gfx.color(gfx.WHITE)
        draw_sprite(rnd(px) - 4, rnd(py) - 6, 9, 13, GLYPHS.player_halo)
        gfx.color(gfx.BLACK)
        draw_sprite(rnd(px) - 3, rnd(py) - 5, 7, 11, GLYPHS.player)
    else   -- no bitmaps on this board: a black block on a white halo
        gfx.color(gfx.WHITE)
        gfx.fill_rect(rnd(px) - 5, rnd(py) - 5, 10, 10)
        gfx.color(gfx.BLACK)
        gfx.fill_rect(rnd(px) - 3, rnd(py) - 3, 6, 6)
    end
    local n = self.little and self.little.n or 0
    if n > 0 then   -- your Little Ones: small heads trailing behind you
        for i = 1, n do
            local lx, ly = rnd(px) - 12 + (i - 1) * 4, rnd(py) + 6 + (i % 2) * 2
            gfx.color(gfx.WHITE)
            gfx.fill_rect(lx - 1, ly - 1, 5, 5)
            gfx.color(gfx.BLACK)
            gfx.fill_rect(lx, ly, 3, 3)
        end
    end
    if self.dog then   -- your dog at your heel: a small block with an ear
        gfx.color(gfx.WHITE)
        gfx.fill_rect(rnd(px) + 5, rnd(py) + 1, 8, 6)
        gfx.color(gfx.BLACK)
        gfx.fill_rect(rnd(px) + 6, rnd(py) + 3, 6, 3)
        gfx.fill_rect(rnd(px) + 10, rnd(py) + 1, 2, 2)
    end
end

-- Rain, storm, snow or fog over the map area (nothing on boards without
-- bitmaps, or in clear weather).
function Game:draw_weather()
    local kind = self:weather()
    local W = GLYPHS.WEATHER
    if not (draw_sprite and W[kind]) then return end
    gfx.color((W[kind].flake or W[kind].veil) and gfx.WHITE or gfx.BLACK)
    local tile = GLYPHS.weather(kind, self.player.hours)
    for y = MAP_TOP, MAP_BOTTOM - W.h, W.h do
        for x = 0, MAP_W - W.w, W.w do draw_sprite(x, y, W.w, W.h, tile) end
    end
end

function Game:draw_map(w, h)
    gfx.clear(gfx.WHITE)

    local p = self.player
    -- the camera: your hex sits in the middle of the map area
    local ppx, ppy = axial_to_pixel(p.q, p.r, HEX_SIZE)
    local origin_x = MAP_W // 2 - ppx
    local origin_y = (MAP_TOP + MAP_BOTTOM) // 2 - ppy

    -- HUD: the day on a black strip; the weather; bars for health and
    -- needs; movement as pips; then conditions, radiation, where to go
    gfx.font(gfx.FONT_MONO_12)
    local day, hour = self:clock()
    local pw = w - PANEL_X + 2
    gfx.color(gfx.BLACK)
    gfx.fill_rect(PANEL_X - 2, 0, pw, 18)
    gfx.color(gfx.WHITE)
    gfx.text(PANEL_X + 2, 13, ("Day %d  %02d:00"):format(day, hour))
    if self:is_night() then gfx.text(w - 6 - 7 * 5, 13, "Night") end
    gfx.color(gfx.BLACK)
    -- an emission coming (or raging) matters more than the weather
    gfx.text(PANEL_X, 32, self:emission_text() or self:weather_text(self:fire_here() and "  Fire" or nil))
    local bars = {{"HP", p.health}, {"Eat", p.needs.hunger}, {"Dri", p.needs.thirst}, {"Rst", p.needs.rest}}
    for i, b in ipairs(bars) do
        local y = 38 + (i - 1) * 13
        gfx.text(PANEL_X, y + 9, b[1])
        Game.ui_bar(PANEL_X + 24, y, 76, 10, b[2] / 100, b[2] >= 30)   -- (gray while fine, black when low)
        gfx.text(PANEL_X + 104, y + 9, tostring(math.floor(b[2])))
    end
    -- movement points as pips, then sight
    local y = 99
    gfx.text(PANEL_X, y, "MP")
    for i = 1, p.max_mp do
        local x = PANEL_X + 18 + (i - 1) * 10
        if i <= p.mp then gfx.fill_rect(x, y - 8, 8, 8) else gfx.rect(x, y - 8, 8, 8) end
    end
    gfx.text(PANEL_X + 24 + p.max_mp * 10, y, "Sight " .. (p.view_sight or p.sight))
    local scav = SCAVENGE_LOOT[self.tiles[hex_key(p.q, p.r)]]
        and (self:scavenge_left() .. "/" .. SCAVENGE_TRIES) or "-"
    local inj = {}
    if p.injuries.bleeding then inj[#inj + 1] = "BLEEDING" end
    if p.injuries.wounded_hours > 0 then inj[#inj + 1] = "Wounded" end
    if (p.cold_hours or 0) > 0 then inj[#inj + 1] = "COLD" end
    if (p.sick_hours or 0) > 0 then inj[#inj + 1] = "SICK" end
    inj[#inj + 1] = "Scav " .. scav
    gfx.text(PANEL_X, 113, table.concat(inj, " "))
    local rad_line = self:rad_text()
    if rad_line then gfx.text(PANEL_X, 127, rad_line) end
    local goal_line = self:goal_text()
    if goal_line then gfx.text(PANEL_X, 141, goal_line) end
    local site_at = {}
    for name, key in pairs(self.sites) do site_at[key] = name end
    if self.base then site_at[self.base.key] = "camp" end   -- drawn like a site
    local peddler = self:peddler_key()
    local little_at = {}   -- warrens and cairns you've found
    for _, kind in ipairs({"warrens", "cairns"}) do
        for _, k in ipairs((self.extras or {})[kind] or {}) do
            if self.little.seen[k] then little_at[k] = kind == "warrens" and "warren" or "cairn" end
        end
    end

    local reachable = {}
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        reachable[hex_key(n[1], n[2])] = true
    end

    -- only whole hexes inside the map area (the world is far bigger than
    -- the screen): walk the axial box around you instead of every tile
    local half_w = HEX_SIZE * SQRT3 / 2
    local span = math.floor(MAP_W / (2 * half_w)) + 2   -- an integer: keys are "q,r"
    local mark_x, mark_y   -- (you're drawn last, over the weather)
    for dr = -span, span do
      for dq = -span - 1, span + 1 do
        local q, r = p.q + dq, p.r + dr
        local key = hex_key(q, r)
        local terrain_id = self.tiles[key]
        local px, py = axial_to_pixel(q, r, HEX_SIZE)
        px, py = origin_x + px, origin_y + py
        if terrain_id and px - half_w >= 1 and px + half_w <= MAP_W - 1
            and py - HEX_SIZE >= MAP_TOP and py + HEX_SIZE <= MAP_BOTTOM then
            local terrain = TERRAIN[terrain_id]
            local is_player = (q == p.q and r == p.r)
            if p.visible[key] then
                self:draw_hex(px, py, shade_color(terrain.shade), gfx.BLACK)
                if reachable[key] and terrain.passable then
                    -- second, inner outline marks tiles you can step onto
                    self:draw_hex(px, py, nil, gfx.BLACK, HEX_SIZE - 3)
                end
                if not is_player then
                    draw_glyph(terrain_id, px, py, shade_color(terrain.ink))
                end
            elseif p.explored[key] then
                -- remembered but out of sight: faded outline and faded glyph,
                -- so you still remember what kind of ground it was
                self:draw_hex(px, py, nil, gfx.LIGHT)
                draw_glyph(terrain_id, px, py, gfx.LIGHT)
            end
            local pile = self.ground[key]
            if pile and #pile > 0 and (p.visible[key] or p.explored[key]) then
                -- something lies here: small boxed dot in the hex's upper right
                local mx, my = rnd(px) + 5, rnd(py) - 11
                gfx.color(gfx.WHITE)
                gfx.fill_rect(mx - 1, my - 1, 7, 7)
                gfx.color(gfx.BLACK)
                gfx.rect(mx - 1, my - 1, 7, 7)
                gfx.fill_rect(mx + 1, my + 1, 3, 3)
            end
            local site = site_at[key]
            if site and not is_player and (p.visible[key] or p.explored[key]) then
                -- the trader's stall / the Checkpoint, on a white patch
                gfx.color(gfx.WHITE)
                gfx.fill_rect(rnd(px) - 6, rnd(py) - 6, 12, 12)
                gfx.color(gfx.BLACK)
                gfx.rect(rnd(px) - 7, rnd(py) - 7, 14, 14)
                draw_glyph(site, px, py, gfx.BLACK)
            end
            local spot = little_at[key]
            if spot and not is_player and (p.visible[key] or p.explored[key]) then
                gfx.color(gfx.WHITE)
                gfx.fill_rect(rnd(px) - 6, rnd(py) - 6, 12, 12)
                draw_glyph(spot, px, py, gfx.BLACK)
            end
            if key == peddler and p.visible[key] and not is_player then
                -- the Peddler and his cart, on a white patch
                gfx.color(gfx.WHITE)
                gfx.fill_rect(rnd(px) - 6, rnd(py) - 6, 12, 12)
                draw_glyph("cart", px, py, gfx.BLACK)
            end
            if self.stashes[key] and (p.visible[key] or p.explored[key]) then
                -- a stash from the notes: an X in the lower right
                local sx, sy = rnd(px) + 4, rnd(py) + 3
                gfx.color(gfx.WHITE)
                gfx.fill_rect(sx - 1, sy - 1, 9, 9)
                gfx.color(gfx.BLACK)
                gfx.rect(sx - 1, sy - 1, 9, 9)
                gfx.line(sx + 1, sy + 1, sx + 5, sy + 5)
                gfx.line(sx + 5, sy + 1, sx + 1, sy + 5)
            end
            if self.snares[key] and (p.visible[key] or p.explored[key]) then
                -- your snare: a small loop at the bottom of the hex
                local sx, sy = rnd(px) - 3, rnd(py) + 6
                gfx.color(gfx.WHITE)
                gfx.fill_rect(sx - 1, sy - 1, 8, 8)
                gfx.color(gfx.BLACK)
                gfx.rect(sx, sy, 6, 6)
                gfx.line(sx + 3, sy + 6, sx + 3, sy + 8)
            end
            if self.quest and self.quest.target == key and (p.visible[key] or p.explored[key]) then
                -- a quest target: "!" in a box, lower right
                local qx, qy = rnd(px) + 4, rnd(py) + 2
                gfx.color(gfx.WHITE)
                gfx.fill_rect(qx - 1, qy - 1, 8, 10)
                gfx.color(gfx.BLACK)
                gfx.rect(qx - 1, qy - 1, 8, 10)
                gfx.fill_rect(qx + 2, qy + 1, 2, 4)
                gfx.fill_rect(qx + 2, qy + 6, 2, 2)
            end
            local hot = self.rad_known[key]
            if hot and hot > 0 and (p.visible[key] or p.explored[key]) then
                -- measured radiation: a trefoil in the upper left, inverted
                -- (white on black) when deadly
                local rx, ry = rnd(px) - 11, rnd(py) - 11
                gfx.color(hot >= 3 and gfx.BLACK or gfx.WHITE)
                gfx.fill_rect(rx - 1, ry - 1, 9, 9)
                gfx.color(gfx.BLACK)
                gfx.rect(rx - 1, ry - 1, 9, 9)
                gfx.color(hot >= 3 and gfx.WHITE or gfx.BLACK)
                draw_sprite(rx, ry, 7, 7, GLYPHS.rad)
            end
            local find = self.finds and self.finds[key]
            if find and (p.visible[key] or p.explored[key]) then
                -- a find (F in the journal): upper right; a grave cross for a
                -- dead churner, an open box for a crate
                -- (the crate is solid black with its lid open, unlike the other boxes)
                local fx, fy = rnd(px) + 4, rnd(py) - 11
                local crate = find.kind ~= "corpse"
                gfx.color(gfx.WHITE)
                gfx.rect(fx - 2, fy - 2, 11, 11)   -- (a white rim: it shows on dark hexes too)
                gfx.color(crate and gfx.BLACK or gfx.WHITE)
                gfx.fill_rect(fx - 1, fy - 1, 9, 9)
                gfx.color(gfx.BLACK)
                gfx.rect(fx - 1, fy - 1, 9, 9)
                if crate then
                    gfx.color(gfx.WHITE)
                    gfx.fill_rect(fx + 1, fy + 4, 5, 1)
                    gfx.line(fx + 1, fy + 2, fx + 5, fy)
                else
                    gfx.fill_rect(fx + 3, fy + 1, 1, 6)
                    gfx.fill_rect(fx + 1, fy + 2, 5, 1)
                end
            end
            local camp = self.camps[key]
            if camp and p.hours < camp.until_hour and (p.visible[key] or p.explored[key]) then
                -- a burning campfire, in the hex's lower left, on a white patch
                local fx, fy = rnd(px) - 12, rnd(py) + 1
                gfx.color(gfx.WHITE)
                gfx.fill_rect(fx - 1, fy - 1, GLYPH_W + 2, GLYPH_H + 2)
                gfx.color(gfx.BLACK)
                draw_sprite(fx, fy, GLYPH_W, GLYPH_H, GLYPHS.campfire)
            end
            if is_player then mark_x, mark_y = px, py end
        end
      end
    end
    self:draw_weather()
    if mark_x then self:draw_player_mark(mark_x, mark_y) end
    gfx.color(gfx.BLACK)
    gfx.rect(0, MAP_TOP - 2, MAP_W, MAP_BOTTOM - MAP_TOP + 4)   -- the map's frame

    self:draw_legend()

    -- log
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    local ly = h - 52
    for _, line in ipairs(self.log) do
        gfx.text(6, ly, line)
        ly = ly + 14
    end
    Game.ui_keys(w, h, self.move_lean
        and ((self.move_lean < 0 and "Up" or "Down") .. ": now Left or Right picks the side")
        or "Arrows Spc:rest F:search E:water I:bag H:help")

    gfx.refresh()
end

-- Terrain key: swatch (same fill + glyph as on the map), name, and what it
-- costs to cross. The tile you're standing on gets a second box.
function Game:draw_legend()
    local here = self.tiles[hex_key(self.player.q, self.player.r)]
    gfx.font(gfx.FONT_MONO_12)
    for i, terrain_id in ipairs(LEGEND_ORDER) do
        local t = TERRAIN[terrain_id]
        local x, y = PANEL_X + 2, LEGEND_Y + (i - 1) * 15

        local fill = shade_color(t.shade)
        if fill ~= gfx.WHITE then
            gfx.color(fill)
            gfx.fill_rect(x, y, 14, 14)
        end
        gfx.color(gfx.BLACK)
        gfx.rect(x, y, 14, 14)
        draw_glyph(terrain_id, x + 7, y + 7, shade_color(t.ink))

        gfx.color(gfx.BLACK)
        if terrain_id == here then
            gfx.rect(x - 2, y - 2, 18, 18)
        end
        local detail = t.passable and (t.cost .. " MP") or "impassable"
        gfx.text(x + 20, y + 11, t.name .. " " .. detail)
    end
end

-- Fill a pointy-top hexagon with horizontal 2px bands whose width follows the
-- hex outline (gfx has no polygon fill). Inset by 1px so the fill never spills
-- past the outline. Skipped for WHITE since the background is already white.
local function fill_hex(cx, cy, size, color)
    if color == gfx.WHITE then return end
    gfx.color(color)
    local half_w = size * SQRT3 / 2
    local step = 2
    for y0 = -size, size - step, step do
        local a = math.abs(y0 + step / 2)
        local hw
        if a <= size / 2 then
            hw = half_w
        else
            hw = half_w * (size - a) / (size / 2)
        end
        hw = hw - 1
        if hw >= 1 then
            gfx.fill_rect(rnd(cx - hw), rnd(cy + y0), rnd(2 * hw), step)
        end
    end
end

-- Unit hex corners (cos, sin of 60i-30 degrees), worked out once: the map
-- draws hundreds of hexes a frame and each new table is garbage to collect.
local HEX_CORNERS = {}
for i = 0, 6 do
    local angle = math.rad(60 * (i % 6) - 30)
    HEX_CORNERS[2 * i + 1], HEX_CORNERS[2 * i + 2] = math.cos(angle), math.sin(angle)
end

-- fill_color may be nil (outline only). size defaults to HEX_SIZE.
-- The hex drawn with rects and lines (the original way, kept for boards
-- without gfx.bitmap and as the source of the masks below).
local function draw_hex_lines(cx, cy, fill_color, outline_color, size)
    if fill_color then
        fill_hex(cx, cy, size, fill_color)
    end
    gfx.color(outline_color)
    local c = HEX_CORNERS
    for i = 0, 5 do
        gfx.line(rnd(cx + size * c[2 * i + 1]), rnd(cy + size * c[2 * i + 2]),
                 rnd(cx + size * c[2 * i + 3]), rnd(cy + size * c[2 * i + 4]))
    end
end

-- Hex masks: draw_hex_lines replayed once per size, at a whole-pixel
-- center, into 1-bit bitmaps of at most 128 bytes (gfx.bitmap's limit), so
-- a hex is ~5 draw calls instead of ~24 (16 fill bands + 6 lines). The
-- firmware dithers a bitmap like a fill_rect of the same color. Each mask
-- is a list of chunks {dx, dy, w, h, data} relative to the center.
HEX_MASKS = {}   -- (a global: the bundle's 200-local limit)
function Game.hex_mask(size)
    if HEX_MASKS[size] then return HEX_MASKS[size] end
    local layers, pen = {}, nil
    local function plot(x, y)
        local layer = layers[pen]
        layer.px[y * 1000 + x] = true
        layer.x0, layer.x1 = math.min(layer.x0, x), math.max(layer.x1, x)
        layer.y0, layer.y1 = math.min(layer.y0, y), math.max(layer.y1, y)
    end
    local real = {color = gfx.color, fill_rect = gfx.fill_rect, line = gfx.line}
    gfx.color = function(c)
        pen = c
        layers[c] = layers[c] or {px = {}, x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9}
    end
    gfx.fill_rect = function(x, y, w, h)
        for yy = y, y + h - 1 do for xx = x, x + w - 1 do plot(xx, yy) end end
    end
    gfx.line = function(x0, y0, x1, y1)   -- Bresenham, both ends included
        local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
        local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
        local err = dx + dy
        while true do
            plot(x0, y0)
            if x0 == x1 and y0 == y1 then break end
            local e2 = 2 * err
            if e2 >= dy then err = err + dy; x0 = x0 + sx end
            if e2 <= dx then err = err + dx; y0 = y0 + sy end
        end
    end
    -- the fill in BLACK, the outline in WHITE, just to tell them apart
    local ok, err = pcall(draw_hex_lines, 0, 0, gfx.BLACK, gfx.WHITE, size)
    gfx.color, gfx.fill_rect, gfx.line = real.color, real.fill_rect, real.line
    if not ok then error(err) end
    local function pack(layer)
        local chunks = {}
        if not layer or layer.x1 < layer.x0 then return chunks end   -- (nothing plotted)
        local w = layer.x1 - layer.x0 + 1
        local bpr = (w + 7) // 8
        local rows = 128 // bpr
        for top = layer.y0, layer.y1, rows do
            local h = math.min(rows, layer.y1 - top + 1)
            local bytes = {}
            for y = top, top + h - 1 do
                for b = 0, bpr - 1 do
                    local v = 0
                    for bit = 0, 7 do
                        local x = layer.x0 + b * 8 + bit
                        if b * 8 + bit < w and layer.px[y * 1000 + x] then v = v | (1 << bit) end
                    end
                    bytes[#bytes + 1] = string.char(v)
                end
            end
            chunks[#chunks + 1] = {layer.x0, top, w, h, table.concat(bytes)}
        end
        return chunks
    end
    HEX_MASKS[size] = {fill = pack(layers[gfx.BLACK]), outline = pack(layers[gfx.WHITE])}
    return HEX_MASKS[size]
end

local function draw_mask(chunks, cx, cy)
    for _, c in ipairs(chunks) do draw_sprite(cx + c[1], cy + c[2], c[3], c[4], c[5]) end
end

function Game:draw_hex(cx, cy, fill_color, outline_color, size)
    size = size or HEX_SIZE
    if not draw_sprite then return draw_hex_lines(cx, cy, fill_color, outline_color, size) end
    local mask, x, y = Game.hex_mask(size), rnd(cx), rnd(cy)
    if fill_color and fill_color ~= gfx.WHITE then
        gfx.color(fill_color)
        draw_mask(mask.fill, x, y)
    end
    gfx.color(outline_color)
    draw_mask(mask.outline, x, y)
end

local INV_ROWS = {}  -- rebuilt each draw: {kind, key, label} - only selectable item rows
local INV_POS = {}   -- rebuilt each draw: row_index -> {x, y, w, h} - where that row draws
