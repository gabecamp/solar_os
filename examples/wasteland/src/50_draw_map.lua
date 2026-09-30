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
local LEGEND_Y = 116
local LEGEND_ORDER = {"plains", "forest", "hills", "ruins", "ford", "water"}

function Game:draw_map(w, h)
    gfx.clear(gfx.WHITE)

    local p = self.player
    -- the camera: your hex sits in the middle of the map area
    local ppx, ppy = axial_to_pixel(p.q, p.r, HEX_SIZE)
    local origin_x = MAP_W // 2 - ppx
    local origin_y = (MAP_TOP + MAP_BOTTOM) // 2 - ppy

    -- HUD: time and weather, then movement, needs, health, conditions
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    local day, hour = self:clock()
    gfx.text(PANEL_X, 14, ("Day %d %02d:00%s"):format(day, hour, self:is_night() and " Night" or ""))
    gfx.text(PANEL_X, 28, self:weather() .. (self:fire_here() and "  Fire" or ""))
    local scav = SCAVENGE_LOOT[self.tiles[hex_key(p.q, p.r)]]
        and (self:scavenge_left() .. "/" .. SCAVENGE_TRIES) or "-"
    gfx.text(PANEL_X, 42, "MP " .. math.max(p.mp, 0) .. "/" .. p.max_mp
        .. " Sight " .. (p.view_sight or p.sight))
    gfx.text(PANEL_X, 56, "Hun " .. math.floor(p.needs.hunger)
        .. " Thi " .. math.floor(p.needs.thirst))
    gfx.text(PANEL_X, 70, "Rest " .. math.floor(p.needs.rest) .. "  HP " .. math.floor(p.health))
    local inj = {}
    if p.injuries.bleeding then inj[#inj + 1] = "BLEEDING" end
    if p.injuries.wounded_hours > 0 then inj[#inj + 1] = "Wounded" end
    if (p.cold_hours or 0) > 0 then inj[#inj + 1] = "COLD" end
    inj[#inj + 1] = "Scav " .. scav
    gfx.text(PANEL_X, 84, table.concat(inj, " "))
    local rad_line = self:rad_text()
    if rad_line then gfx.text(PANEL_X, 98, rad_line) end

    local reachable = {}
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        reachable[hex_key(n[1], n[2])] = true
    end

    -- only whole hexes inside the map area (the world is far bigger than
    -- the screen): walk the axial box around you instead of every tile
    local half_w = HEX_SIZE * SQRT3 / 2
    local span = math.floor(MAP_W / (2 * half_w)) + 2   -- an integer: keys are "q,r"
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
            local camp = self.camps[key]
            if camp and p.hours < camp.until_hour and (p.visible[key] or p.explored[key]) then
                -- a burning campfire, in the hex's lower left, on a white patch
                local fx, fy = rnd(px) - 12, rnd(py) + 1
                gfx.color(gfx.WHITE)
                gfx.fill_rect(fx - 1, fy - 1, GLYPH_W + 2, GLYPH_H + 2)
                gfx.color(gfx.BLACK)
                draw_sprite(fx, fy, GLYPH_W, GLYPH_H, GLYPHS.campfire)
            end
            if is_player then
                -- white halo keeps the marker visible on dark/black tiles
                gfx.color(gfx.WHITE)
                gfx.fill_rect(rnd(px) - 5, rnd(py) - 5, 10, 10)
                gfx.color(gfx.BLACK)
                gfx.fill_rect(rnd(px) - 3, rnd(py) - 3, 6, 6)
            end
        end
      end
    end
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
    gfx.text(6, h - 8, "Arrows Spc:rest F:scavenge C:craft I:inv Q:quit")

    gfx.refresh()
end

-- Terrain key: swatch (same fill + glyph as on the map), name, and what it
-- costs to cross. The tile you're standing on gets a second box.
function Game:draw_legend()
    local here = self.tiles[hex_key(self.player.q, self.player.r)]
    gfx.font(gfx.FONT_MONO_12)
    for i, terrain_id in ipairs(LEGEND_ORDER) do
        local t = TERRAIN[terrain_id]
        local x, y = PANEL_X + 2, LEGEND_Y + (i - 1) * 18

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

-- fill_color may be nil (outline only). size defaults to HEX_SIZE.
function Game:draw_hex(cx, cy, fill_color, outline_color, size)
    size = size or HEX_SIZE
    if fill_color then
        fill_hex(cx, cy, size, fill_color)
    end
    gfx.color(outline_color)
    local corners = {}
    for i = 0, 5 do
        local angle = math.rad(60 * i - 30)
        corners[i + 1] = {cx + size * math.cos(angle), cy + size * math.sin(angle)}
    end
    for i = 1, 6 do
        local a, b = corners[i], corners[i % 6 + 1]
        gfx.line(rnd(a[1]), rnd(a[2]), rnd(b[1]), rnd(b[2]))
    end
end

local INV_ROWS = {}  -- rebuilt each draw: {kind, key, label} - only selectable item rows
local INV_POS = {}   -- rebuilt each draw: row_index -> {x, y, w, h} - where that row draws
