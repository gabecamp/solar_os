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
local LEGEND_Y = 80
local LEGEND_ORDER = {"plains", "forest", "hills", "water"}

function Game:draw_map(w, h)
    gfx.clear(gfx.WHITE)

    local p = self.player
    local origin_x, origin_y = MAP_W // 2, (MAP_TOP + MAP_BOTTOM) // 2

    -- HUD
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    local scav = SCAVENGE_LOOT[self.tiles[hex_key(p.q, p.r)]]
        and (self:scavenge_left() .. "/" .. SCAVENGE_TRIES) or "-"
    gfx.text(PANEL_X, 14, "MP " .. math.max(p.mp, 0) .. "/" .. p.max_mp .. "  Hrs " .. p.hours)
    gfx.text(PANEL_X, 28, "Sight " .. p.sight .. " Scav " .. scav)
    gfx.text(PANEL_X, 42, "Hun " .. math.floor(p.needs.hunger)
        .. " Thi " .. math.floor(p.needs.thirst))
    gfx.text(PANEL_X, 56, "Rest " .. math.floor(p.needs.rest) .. "  HP " .. math.floor(p.health))
    local inj = {}
    if p.injuries.bleeding then inj[#inj + 1] = "BLEEDING" end
    if p.injuries.wounded_hours > 0 then inj[#inj + 1] = "Wounded" end
    if #inj > 0 then gfx.text(PANEL_X, 70, table.concat(inj, " ")) end

    local reachable = {}
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        reachable[hex_key(n[1], n[2])] = true
    end

    for key, terrain_id in pairs(self.tiles) do
        local q, r = key:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        local px, py = axial_to_pixel(q, r, HEX_SIZE)
        px, py = origin_x + px, origin_y + py
        if py > MAP_TOP and py < MAP_BOTTOM then
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
            if is_player then
                -- white halo keeps the marker visible on dark/black tiles
                gfx.color(gfx.WHITE)
                gfx.fill_rect(rnd(px) - 5, rnd(py) - 5, 10, 10)
                gfx.color(gfx.BLACK)
                gfx.fill_rect(rnd(px) - 3, rnd(py) - 3, 6, 6)
            end
        end
    end

    self:draw_legend()

    -- log
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    local ly = h - 52
    for _, line in ipairs(self.log) do
        gfx.text(6, ly, line)
        ly = ly + 14
    end
    gfx.text(6, h - 8, "Arrows Spc:rest F:scavenge I:inv Q:quit")

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
