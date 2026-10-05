
-- Equip slots sit ON the body part they dress, NEO Scavenger style: a box over
-- the head, the face, the torso, the legs, a hand... sized to that part, with
-- the worn item painted onto the body and its icon drawn inside the box.
-- {x, y, w, h} authored against the figure at center x 150 / head top y 72,
-- then shifted with it (BODY_DX/BODY_DY below). Boxes never touch each other.
local EQUIP_RECT = {
    head   = {139,  64, 22, 18},   -- top of the head (a hat sits here)
    ears   = {118,  84, 20, 18},   -- against the side of the head
    eyes   = {140,  84, 20, 18},   -- the face
    neck   = {140, 105, 20, 18},   -- throat / collar
    jacket = {116, 126, 68, 38},   -- chest and shoulders
    shirt  = {124, 167, 52, 22},   -- belly
    belt   = {124, 192, 52, 17},   -- the waist
    hands  = { 73, 212, 22, 22},   -- gloves: the left forearm and hand
    wrists = {205, 212, 22, 22},   -- the right wrist
    lhand  = { 70, 236, 24, 24},   -- held in the left hand (anything)
    rhand  = {206, 236, 24, 24},   -- held in the right hand (anything)
    back   = {230, 118, 40, 40},   -- worn on the back, drawn beside the shoulder
    pants  = {122, 212, 56, 52},   -- hips and legs
    feet   = {120, 267, 60, 20},   -- both feet
}
-- shown inside an empty slot; the long form when it fits the box
local EQUIP_NAME = {head = "Head", ears = "Ears", eyes = "Eyes", neck = "Neck",
                    jacket = "Jacket", shirt = "Shirt", hands = "Gloves",
                    wrists = "Wrists", pants = "Pants", feet = "Feet",
                    lhand = "L Hand", rhand = "R Hand", back = "Back", belt = "Belt"}
local EQUIP_ABBR = {head = "Hd", ears = "Ea", eyes = "Ey", neck = "Nk", jacket = "Jk",
                    shirt = "Sh", hands = "Gl", wrists = "Wr", pants = "Pt", feet = "Ft",
                    lhand = "LH", rhand = "RH", back = "Bk", belt = "Bt"}
-- where the doll sits on the 400x300 screen: the left column, head at the top
local BODY_DX, BODY_DY = -66, -46
for _, r in pairs(EQUIP_RECT) do r[1], r[2] = r[1] + BODY_DX, r[2] + BODY_DY end

-- right column (from INV_COL_X): ground grid, bag grid with its name and
-- fill count above it, then what the cursor is on
local INV_COL_X = 212
local GROUND_GRID_COLS = 5
local GROUND_GRID_ROWS = 2   -- visible rows; the grid scrolls to follow the cursor
local GROUND_CELL, GROUND_GAP = 30, 2
local GROUND_Y = 32
-- bag: up to BACKPACK_CAP cells, all visible (with a bag on, your pockets
-- start a row of their own, framed in gray)
local BACKPACK_COLS = 8
local BACKPACK_CELL, BACKPACK_GAP = 20, 2
local BACKPACK_Y = 114
local BAG_LABEL_Y = BACKPACK_Y - 5
local CURSOR_DESC_Y = 210
local CONDITIONS_Y = 264     -- full width, under the doll
-- log lines sit on the last lines of the reported screen height
local INV_LOG_LINES = 2

local function item_abbr(item_id)
    return ITEM_DB[item_id].name:sub(1, 1)
end

function Game:current_conditions()
    -- Only conditions we actually track - nothing fabricated (no injury/
    -- temperature model exists yet, so none are listed here).
    local list = {}
    if self.player.equipped.feet == nil then table.insert(list, "Barefoot") end
    if (self.player.cold_hours or 0) > 0 then table.insert(list, "Cold") end
    if self.player.needs.hunger <= 0 then table.insert(list, "Starving") end
    if self.player.needs.thirst <= 0 then table.insert(list, "Dehydrated") end
    if self.player.needs.rest <= 0 then table.insert(list, "Exhausted") end
    if self.player.injuries.bleeding then table.insert(list, "Bleeding") end
    if self.player.injuries.wounded_hours > 0 then table.insert(list, "Wounded") end
    if self.player.health < 50 then table.insert(list, "Hurt") end
    local _, worst = self:most_worn(1)
    if worst and worst <= 0 then table.insert(list, "Torn clothes") end
    if (self.player.sick_hours or 0) > 0 then table.insert(list, "Sick") end
    local rad_stage = RAD.stages[self:rad_stage()]
    if rad_stage then table.insert(list, self:can_measure() and rad_stage.name or rad_stage.feel) end
    if #list == 0 then return "Conditions: none" end
    local text = table.concat(list, ", ")
    -- all four at once don't fit after the prefix (mono 12 is ~7px/char)
    if (12 + #text) * 7 > 392 then return text end
    return "Conditions: " .. text
end

function Game:draw_slot_box(x, y, w, h, stack, is_cursor, is_selected, pocket)
    if stack and stack.item then
        gfx.color(gfx.LIGHT)
        gfx.fill_rect(x, y, w, h)
        gfx.color(gfx.BLACK)
        local sprite = SPRITES[stack.item]
        if sprite and draw_sprite then
            -- center the 16x16 icon in the slot (// keeps coordinates integers)
            draw_sprite(x + (w - SPRITE_W) // 2, y + (h - SPRITE_H) // 2,
                        SPRITE_W, SPRITE_H, sprite)
        else
            gfx.font(gfx.FONT_MONO_12)
            gfx.text(x + 3, y + h - 5, item_abbr(stack.item))
        end
        if stack.qty and stack.qty > 1 then
            gfx.font(gfx.FONT_MONO_12)
            -- bottom-right corner, right-aligned (mono 12 is ~7px per char), so
            -- it stays clear of the centered 16x16 icon and inside the box
            local qty_text = tostring(stack.qty)
            if #qty_text > 2 or (#qty_text > 1 and w < 24) then   -- (on paper, so it reads over the icon)
                gfx.color(gfx.WHITE)
                gfx.fill_rect(x + w - 3 - 7 * #qty_text, y + h - 11, 7 * #qty_text + 2, 10)
                gfx.color(gfx.BLACK)
            end
            gfx.text(x + w - 2 - 7 * #qty_text, y + h - 2, qty_text)
        end
    end
    gfx.color(pocket and gfx.DARK or gfx.BLACK)   -- (a pocket: a gray frame)
    gfx.rect(x, y, w, h)
    gfx.color(gfx.BLACK)
    if is_selected then
        gfx.rect(x - 2, y - 2, w + 4, h + 4)
    elseif is_cursor then
        gfx.rect(x - 1, y - 1, w + 2, h + 2)
    end
end

-- ---------------------------------------------------------------------
-- Paperdoll silhouette
--
-- gfx has no polygon fill, so the body is described as polygons (points are
-- offsets from the body's center line), rasterized ONCE at load into
-- horizontal blocks (runs of identical rows merged into one tall rect), and
-- drawn with fill_rect. Drawing the union in black expanded by 1px and then in
-- gray at true size gives a clean 1px outline around the whole figure, so
-- overlapping parts (arm meeting torso) don't leave internal seams.
-- ---------------------------------------------------------------------

local BODY_CX = 150 + BODY_DX
-- The figure is authored in the coordinates below (head top at y 117, feet at
-- 289) and scaled by BODY_SCALE about its top, landing at BODY_Y0.
local BODY_SCALE, BODY_SRC_Y0, BODY_Y0 = 1.25, 117, 72 + BODY_DY
local BODY_TOP = BODY_Y0
local BODY_BOTTOM = BODY_Y0 + math.ceil((289 - BODY_SRC_Y0) * BODY_SCALE)   -- exclusive

-- The polygons and the rasterizer only run here, once, so they live in a
-- do-block: the bundle is one Lua chunk with a 200-local limit, and only
-- the finished blocks are needed afterwards.
local BODY_BLOCKS, PART_BLOCKS = nil, {}
do
    local function mirror_x(pts)
        local out = {}
        for i = 1, #pts, 2 do
            out[i] = -pts[i]
            out[i + 1] = pts[i + 1]
        end
        return out
    end

    -- Build a full polygon from its right half (listed top to bottom, starting and
    -- ending on the center line) by appending the mirrored points in reverse.
    local function symmetric(right)
        local pts = {}
        for i = 1, #right do pts[i] = right[i] end
        for i = #right - 1, 1, -2 do
            pts[#pts + 1] = -right[i]
            pts[#pts + 1] = right[i + 1]
        end
        return pts
    end

    local function ellipse_points(cy, rx, ry, n)
        local pts = {}
        for i = 0, n - 1 do
            local a = 2 * math.pi * i / n
            pts[#pts + 1] = rx * math.cos(a)
            pts[#pts + 1] = cy + ry * math.sin(a)
        end
        return pts
    end

    local BODY_POLYGONS = {}
    local BODY_PART
    local function add_body_polygon(pts)
        local out = {}
        for i = 1, #pts, 2 do
            out[i] = pts[i] * BODY_SCALE
            out[i + 1] = BODY_Y0 + (pts[i + 1] - BODY_SRC_Y0) * BODY_SCALE
        end
        BODY_POLYGONS[#BODY_POLYGONS + 1] = out
    end

    -- head (which part each polygon is: BODY_PART[i], used to paint worn clothes)
    BODY_PART = {}
    local function add_part(part, pts)
        add_body_polygon(pts)
        BODY_PART[#BODY_POLYGONS] = part
    end
    add_part("head", ellipse_points(130, 11, 13, 28))
    -- neck, sloped shoulders, tapered torso down to the hips
    add_part("torso", symmetric({
        0, 139,  4, 139,  4, 146,  14, 148,  27, 151,  31, 156,  30, 164,
        25, 170,  22, 182,  19, 200,  21, 214,  23, 226,  0, 226,
    }))
    -- arms hang slightly away from the body and end in hands
    local ARM = {
        30, 151,  38, 154,  42, 175,  46, 195,  50, 215,  53, 230,
        56, 238,  56, 246,  52, 250,  48, 246,  47, 238,  47, 230,
        43, 215,  37, 195,  31, 178,  27, 166,  28, 158,
    }
    add_part("arms", ARM)
    add_part("arms", mirror_x(ARM))
    -- legs: thigh, knee, calf, ankle, and a foot angled outward
    local LEG = {
        1, 224,  23, 224,  22, 240,  20, 254,  18, 266,  15, 278,
        20, 284,  21, 288,  3, 288,  3, 282,  5, 270,  4, 254,  2, 240,
    }
    add_part("legs", LEG)
    add_part("legs", mirror_x(LEG))

    -- x-intervals [a, b) covered by one polygon on the pixel row whose center is yc
    local function polygon_row_spans(pts, yc)
        local xs = {}
        local n = #pts // 2
        for i = 1, n do
            local j = i % n + 1
            local x1, y1 = pts[2 * i - 1], pts[2 * i]
            local x2, y2 = pts[2 * j - 1], pts[2 * j]
            if y1 ~= y2 and ((y1 <= yc and yc < y2) or (y2 <= yc and yc < y1)) then
                xs[#xs + 1] = x1 + (yc - y1) * (x2 - x1) / (y2 - y1)
            end
        end
        table.sort(xs)
        local spans = {}
        for k = 1, #xs - 1, 2 do
            -- Pixel i is covered when its center (i + 0.5) lies strictly inside the
            -- edges. Strict on BOTH sides so an edge landing exactly on a pixel
            -- center is treated the same left and right - keeps the figure symmetric.
            local a = math.floor(BODY_CX + xs[k] - 0.5) + 1
            local b = math.ceil(BODY_CX + xs[k + 1] - 0.5)
            if b > a then spans[#spans + 1] = {a, b} end
        end
        return spans
    end

    -- part: only that body part's polygons (nil = the whole figure)
    local function build_body_blocks(part)
        local blocks, prev_key = {}, nil
        for y = BODY_TOP, BODY_BOTTOM - 1 do
            local all = {}
            for i, poly in ipairs(BODY_POLYGONS) do
                if part == nil or BODY_PART[i] == part then
                    for _, sp in ipairs(polygon_row_spans(poly, y + 0.5)) do
                        all[#all + 1] = sp
                    end
                end
            end
            table.sort(all, function(p, q) return p[1] < q[1] end)
            local merged = {}
            for _, sp in ipairs(all) do
                local last = merged[#merged]
                if last and sp[1] <= last[2] then
                    if sp[2] > last[2] then last[2] = sp[2] end
                else
                    merged[#merged + 1] = {sp[1], sp[2]}
                end
            end
            local parts = {}
            for _, m in ipairs(merged) do parts[#parts + 1] = m[1] .. "," .. m[2] end
            local key = table.concat(parts, ";")
            if key ~= "" and key == prev_key then
                blocks[#blocks].h = blocks[#blocks].h + 1
            elseif key ~= "" then
                blocks[#blocks + 1] = {y = y, h = 1, spans = merged}
            end
            prev_key = key
        end
        return blocks
    end

    BODY_BLOCKS = build_body_blocks()
    for _, part in ipairs({"head", "torso", "arms", "legs"}) do
        PART_BLOCKS[part] = build_body_blocks(part)
    end
end

local function body_row(src_y)
    return BODY_Y0 + math.floor((src_y - BODY_SRC_Y0) * BODY_SCALE + 0.5)
end

-- fill_rect cut to clip = {x0, y0, x1, y1} (exclusive), or plain without one:
-- the cursor-only redraw repaints just the doll under one slot.
local function fill_clipped(clip, x, y, w, h)
    if clip then
        local x0, y0 = math.max(x, clip[1]), math.max(y, clip[2])
        local x1, y1 = math.min(x + w, clip[3]), math.min(y + h, clip[4])
        if x1 <= x0 or y1 <= y0 then return end
        x, y, w, h = x0, y0, x1 - x0, y1 - y0
    end
    gfx.fill_rect(x, y, w, h)
end

-- Holes in a torn piece: 2x2 spots on a staggered grid (every 5 rows, 6
-- columns, alternate rows shifted 3), fixed to the screen so the holes line
-- up across body parts; in `hole_color` (the body shows through).
function Game.punch_holes(clip, x, y, w, h, hole_color, color)
    gfx.color(hole_color)
    local row = (y + 4) // 5
    for yy = row * 5, y + h - 2, 5 do
        local shift = (yy // 5) % 2 * 3
        local first = x + (shift - x) % 6
        for xx = first, x + w - 2, 6 do fill_clipped(clip, xx, yy, 2, 2) end
    end
    gfx.color(color)
end

-- Paint one body part between two authored rows (clothing on the doll).
-- inner/outer (optional, authored units) keep only the pixels whose distance
-- from the center line is in [inner, outer), on both sides. torn: with holes.
local function paint_part(part, src_y0, src_y1, color, inner, outer, clip, torn)
    local y0, y1 = body_row(src_y0), body_row(src_y1)
    local hole = color == gfx.LIGHT and gfx.WHITE or gfx.LIGHT
    local bands
    if outer then
        local i = math.floor(inner * BODY_SCALE + 0.5)
        local o = math.floor(outer * BODY_SCALE + 0.5)
        bands = {{BODY_CX - o, BODY_CX - i}, {BODY_CX + i, BODY_CX + o}}
    end
    gfx.color(color)
    for _, b in ipairs(PART_BLOCKS[part]) do
        local top, bottom = math.max(b.y, y0), math.min(b.y + b.h, y1)
        if bottom > top then
            for _, sp in ipairs(b.spans) do
                if bands then
                    for _, band in ipairs(bands) do
                        local a, z = math.max(sp[1], band[1]), math.min(sp[2], band[2])
                        if z > a then
                            fill_clipped(clip, a, top, z - a, bottom - top)
                            if torn then Game.punch_holes(clip, a, top, z - a, bottom - top, hole, color) end
                        end
                    end
                else
                    fill_clipped(clip, sp[1], top, sp[2] - sp[1], bottom - top)
                    if torn then Game.punch_holes(clip, sp[1], top, sp[2] - sp[1], bottom - top, hole, color) end
                end
            end
        end
    end
end

-- Draw order for painting worn items: under-layers before over-layers.
-- Held items (lhand/rhand) are never painted on, only shown in their box.
local WEAR_ORDER = {"shirt", "pants", "belt", "jacket", "back", "feet", "hands", "head", "neck",
                    "wrists", "eyes", "ears"}

-- clip (optional): only repaint inside {x0, y0, x1, y1}, on white.
function Game:draw_silhouette(clip)
    if clip then
        gfx.color(gfx.WHITE)
        gfx.fill_rect(clip[1], clip[2], clip[3] - clip[1], clip[4] - clip[2])
    end
    -- pass 1: outline (every block grown by 1px, black)
    gfx.color(gfx.BLACK)
    for _, b in ipairs(BODY_BLOCKS) do
        for _, sp in ipairs(b.spans) do
            fill_clipped(clip, sp[1] - 1, b.y - 1, sp[2] - sp[1] + 2, b.h + 2)
        end
    end
    -- pass 2: body fill at true size
    gfx.color(gfx.LIGHT)
    for _, b in ipairs(BODY_BLOCKS) do
        for _, sp in ipairs(b.spans) do
            fill_clipped(clip, sp[1], b.y, sp[2] - sp[1], b.h)
        end
    end
    -- pass 3: worn clothes painted onto the body, inner layers first
    for _, slot in ipairs(WEAR_ORDER) do
        local item = self.player.equipped[slot]
        local wear = item and ITEM_DB[item].wear
        if wear then
            local torn = self:torn(slot)
            for _, w in ipairs(wear) do
                paint_part(w[1], w[2], w[3], gfx[w[4]], w[5], w[6], clip, torn)
            end
        end
    end
end

-- A slot's frame on the doll (the cursor gets a solid one): one rect in
-- dark gray, which the 1-bit panel dithers into a broken line. (It was
-- drawn as 2px dashes - ~30 line calls a slot, most of the bag screen's
-- draw time on the device.)
local function dashed_rect(x, y, w, h)
    gfx.color(gfx.DARK)
    gfx.rect(x, y, w, h)
    gfx.color(gfx.BLACK)
end

local HALO = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}

-- One paperdoll slot, framed by a dashed outline over the body part. Worn:
-- the clothes are already painted on the doll (draw_silhouette); the item's
-- icon sits on top. Empty: the slot's name on a small white tag so it reads
-- on the dithered gray.
function Game:draw_equip_slot(slot, x, y, w, h, is_cursor, is_selected)
    local item = self.player.equipped[slot]
    gfx.font(gfx.FONT_MONO_12)
    if item then
        -- the item sits on the (painted) body: black icon with a 1px white
        -- halo so it reads on any fill, inside the slot's dashed frame
        local sprite = SPRITES[item]
        local sx, sy = x + (w - SPRITE_W) // 2, y + (h - SPRITE_H) // 2
        if sprite and draw_sprite then
            gfx.color(gfx.WHITE)
            for _, d in ipairs(HALO) do
                draw_sprite(sx + d[1], sy + d[2], SPRITE_W, SPRITE_H, sprite)
            end
            gfx.color(gfx.BLACK)
            draw_sprite(sx, sy, SPRITE_W, SPRITE_H, sprite)
        else
            gfx.color(gfx.WHITE)
            gfx.fill_rect(sx + 3, sy + 2, 11, 13)
            gfx.color(gfx.BLACK)
            gfx.text(sx + 5, sy + 12, item_abbr(item))
        end
        gfx.color(gfx.BLACK)
        dashed_rect(x, y, w, h)
    else
        local label = EQUIP_NAME[slot]
        if 7 * #label + 4 > w then label = EQUIP_ABBR[slot] end
        local tw = 7 * #label
        local tx, ty = x + (w - tw) // 2, y + h // 2 + 4
        gfx.color(gfx.WHITE)
        gfx.fill_rect(tx - 1, ty - 9, tw + 2, 11)
        gfx.color(gfx.BLACK)
        gfx.text(tx, ty, label)
        dashed_rect(x, y, w, h)
    end
    if is_selected or is_cursor then
        -- white inner line keeps the cursor visible over black clothes
        gfx.color(gfx.WHITE)
        gfx.rect(x, y, w, h)
    end
    gfx.color(gfx.BLACK)
    if is_selected then
        gfx.rect(x - 2, y - 2, w + 4, h + 4)
        gfx.rect(x - 1, y - 1, w + 2, h + 2)
    elseif is_cursor then
        gfx.rect(x - 1, y - 1, w + 2, h + 2)
    end
end

-- What the cursor is on, e.g. "Head: Cap" or "Bag: Rock x3".
function Game:cursor_description()
    local row = INV_ROWS[self.inv_cursor]
    if not row then return "" end
    local kind, key = row[1], row[2]
    local stack = self:get_stack(kind, key)
    local where = kind == "ground" and ((self:at_base() and self:base_has("box")) and "Box" or "Ground") or kind == "inventory" and "Bag"
        or EQUIP_NAME[key]
    if not stack then return where .. ": empty" end
    local text = where .. ": " .. ITEM_DB[stack.item].name
    if stack.qty > 1 then text = text .. " x" .. stack.qty end
    return text .. Game.cond_text(stack.cond)
end

-- Which ground stack starts the visible window: scrolled so the cursor is
-- in view when it is on the ground grid.
function Game:ground_scroll(n_ground)
    local off = self.ground_off or 0
    if self.inv_cursor <= n_ground then
        local crow = (self.inv_cursor - 1) // GROUND_GRID_COLS
        local first = off // GROUND_GRID_COLS
        if crow < first then
            off = crow * GROUND_GRID_COLS
        elseif crow >= first + GROUND_GRID_ROWS then
            off = (crow - GROUND_GRID_ROWS + 1) * GROUND_GRID_COLS
        end
    end
    local total_rows = (n_ground + GROUND_GRID_COLS - 1) // GROUND_GRID_COLS
    return math.max(0, math.min(off, (total_rows - GROUND_GRID_ROWS) * GROUND_GRID_COLS))
end

-- Where cursor row i sits on screen ({x, y, w, h}). A ground cell scrolled
-- out of view has none drawn: it gets the spot it would have in the grid.
function Game:inv_row_pos(i)
    local pos, row = INV_POS[i], INV_ROWS[i]
    if pos or not row or row[1] ~= "ground" then return pos end
    local k = row[2] - (self.ground_off or 0) - 1
    return {x = INV_COL_X + 2 + k % GROUND_GRID_COLS * (GROUND_CELL + GROUND_GAP),
            y = GROUND_Y + k // GROUND_GRID_COLS * (GROUND_CELL + GROUND_GAP), w = GROUND_CELL, h = GROUND_CELL}
end

-- Arrow keys on the bag screen: the cursor goes to the nearest cell or slot
-- that way (dx, dy = -1/0/1), across the ground, the doll and the bag.
-- Nothing further that way: it wraps round to the far side.
function Game:inv_move(dx, dy)
    local cur = self.inv_cursor
    local row = INV_ROWS[cur]
    if not row then return end
    -- the ground grid scrolls: step through it by index first
    if row[1] == "ground" then
        local n, cols, i = 0, GROUND_GRID_COLS, row[2]
        for _, r in ipairs(INV_ROWS) do if r[1] == "ground" then n = n + 1 end end
        local t = i + dx + dy * cols
        if dx ~= 0 and (t - 1) // cols ~= (i - 1) // cols then t = nil end
        if dy > 0 and t and t > n and (n - 1) // cols > (i - 1) // cols then t = n end
        if t and t >= 1 and t <= n then
            self.inv_cursor = t   -- (ground rows come first: row index == ground index)
            return
        end
    end
    local p = self:inv_row_pos(cur)
    if not p then return end
    local cx, cy = p.x + p.w / 2, p.y + p.h / 2
    local best, best_score, wrap, wrap_score
    for i = 1, #INV_ROWS do
        local q = i ~= cur and INV_POS[i]
        if q then
            local vx, vy = q.x + q.w / 2 - cx, q.y + q.h / 2 - cy
            local along, across = vx * dx + vy * dy, math.abs(dx ~= 0 and vy or vx)
            if along > 0 and across <= 2 * along then   -- (roughly that way: within ~63 degrees)
                local score = along + 2 * across
                if not best_score or score < best_score then best, best_score = i, score end
            elseif along <= 0 then   -- the far side, as level as can be
                local score = 2 * across + along
                if not wrap_score or score < wrap_score then wrap, wrap_score = i, score end
            end
        end
    end
    self.inv_cursor = best or wrap or cur
end

-- X on the bag screen: what the cursor is on goes on the ground.
function Game:inv_drop()
    local row = INV_ROWS[self.inv_cursor]
    if not row or row[1] == "ground" or not self:get_stack(row[1], row[2]) then return false end
    self.inv_selected = nil
    return self:try_transfer({row[1], row[2]}, {"ground"})
end

-- Everything the bag screen shows except where the cursor is: when only the
-- cursor moved, the screen is patched instead of redrawn.
function Game:inv_signature()
    local p, out = self.player, {self:current_conditions(), table.concat(self:inv_stats_lines(), "|"),
                                 self.ground_off or 0, self:bag_capacity(),
                                 (self:at_base() and self:base_has("box")) and "box" or "ground"}
    for _, list in ipairs({self:ground_list(), p.inventory}) do
        for _, s in ipairs(list) do out[#out + 1] = s.item .. "x" .. s.qty end
        out[#out + 1] = "|"
    end
    for _, slot in ipairs(EQUIP_SLOTS) do out[#out + 1] = p.equipped[slot] or "-" end
    local sel = self.inv_selected
    out[#out + 1] = sel and (sel[1] .. ":" .. sel[2]) or "-"
    for _, line in ipairs(self.log) do out[#out + 1] = line end
    return table.concat(out, "\n")
end

-- Your numbers, under the cursor's lines: "Hunger 70 Thirst 60" and
-- "HP 85 Rest 80 Warm 3/5". Warmth is what you wear / what the weather,
-- season and night ask for (cold_need); by a fire or in your bedroll it
-- reads "fire" or "bed". Both lines fit the column at 3-digit values.
function Game:inv_stats_lines()
    local p = self.player
    local warm = self:fire_at(p.hours) and "fire" or self:bed_here() and "bed"
        or (self:warmth() .. "/" .. self:cold_need())
    return {("Hunger %d Thirst %d"):format(math.floor(p.needs.hunger), math.floor(p.needs.thirst)),
            ("HP %d Rest %d Warm %s"):format(math.floor(p.health), math.floor(p.needs.rest), warm)}
end

-- An item's numbers, short: "Warm 3, +2 cells", "12 dmg, close, bleed 30%",
-- "Hunger +40". nil when it has none. (Radiation only shows as a number
-- once you can measure it.)
function Game:item_stats(item)
    local d, out = ITEM_DB[item], {}
    local function add(s) out[#out + 1] = s end
    if (d.warmth or 0) > 0 then add("Warm " .. d.warmth) end
    if d.bag_cells then add(d.bag_cells .. " bag cells") end
    local cells = (d.pocket_cells or 0) + (d.belt_cells or 0)
    if cells > 0 then add("+" .. cells .. (cells > 1 and " cells" or " cell")) end
    if d.rad_armor then add(self:can_measure() and ("rads x" .. d.rad_armor) or "filters air") end
    if d.fx and d.fx.mp then add(d.fx.mp .. " MP") end
    if d.light then add("light") end
    if d.fish_bonus then add("fish +" .. d.fish_bonus .. "%") end
    if d.shoot then
        add("shot " .. d.shoot.dmg .. " dmg")
    elseif d.weapon then
        add(d.weapon.dmg .. " dmg, " .. (d.weapon.thrown and "thrown" or d.weapon.reach))
        if (d.weapon.bleed or 0) > 0 then add("bleed " .. d.weapon.bleed .. "%") end
    end
    for _, need in ipairs({"hunger", "thirst", "rest", "rads"}) do
        local v = d.consumable and d.consumable[need]
        if v and (need ~= "rads" or self:can_measure()) then
            add(need:sub(1, 1):upper() .. need:sub(2) .. " " .. (v > 0 and "+" or "") .. v)
        end
    end
    if #out == 0 then return nil end
    return table.concat(out, ", ")
end

-- What the cursor is on, its numbers and what it does, under the bag (at
-- most three lines), then your own numbers.
function Game:draw_inv_desc(w, clear)
    local top = CURSOR_DESC_Y - 7
    if clear then
        gfx.color(gfx.WHITE)
        gfx.fill_rect(INV_COL_X, top - 10, w - INV_COL_X, CONDITIONS_Y - top)
    end
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    local max_chars = (w - INV_COL_X - 2) // 7
    local row = INV_ROWS[self.inv_cursor]
    local stack = row and self:get_stack(row[1], row[2])
    local lines = wrap(self:cursor_description(), max_chars)
    if row and row[1] == "inventory" and not stack then   -- (an empty cell: where the cells come from)
        for _, l in ipairs(wrap(self:bag_sum_text(), max_chars)) do lines[#lines + 1] = l end
    elseif stack then
        for _, text in ipairs({self:item_stats(stack.item) or false, ITEM_DB[stack.item].desc or false}) do
            if text then
                for _, l in ipairs(wrap(text, max_chars)) do lines[#lines + 1] = l end
            end
        end
    end
    for i = 1, math.min(3, #lines) do
        gfx.text(INV_COL_X, top + 12 * (i - 1), lines[i]:sub(1, max_chars))
    end
    -- your numbers, above the conditions (here because the erase above reaches them)
    for i, line in ipairs(self:inv_stats_lines()) do
        gfx.text(INV_COL_X, CONDITIONS_Y - 25 + 12 * (i - 1), line:sub(1, max_chars))
    end
end

-- The doll's pixels on the 1px ring just outside a slot, as runs
-- {color, x, y, w, h}: draw_silhouette is run once into a recorder (so it is
-- exactly what a full redraw paints there) and cached until the clothes change.
-- Cached drawings of the doll for what you wear now (reset when it changes).
function Game:doll_cache()
    local worn = {}   -- (only what is painted on the doll: not what's in your hands)
    for _, s in ipairs(WEAR_ORDER) do   -- (a torn piece looks different: "!")
        worn[#worn + 1] = (self.player.equipped[s] or "-") .. (self:torn(s) and "!" or "")
    end
    worn = table.concat(worn, ",")
    if not (self.ring_cache and self.ring_cache.worn == worn) then self.ring_cache = {worn = worn} end
    return self.ring_cache
end

-- The whole doll as 1-bit bitmap tiles, one set per color: {color, x, y,
-- w, h, data}. draw_silhouette's ~500-800 rects are replayed once into bit
-- planes and cut into 32x32 tiles (128 bytes, gfx.bitmap's limit); the
-- firmware dithers a bitmap exactly like a fill_rect of the same color, so
-- ~60-80 calls draw the same picture.
function Game:doll_tiles()
    local cache = self:doll_cache()
    if cache.tiles then return cache.tiles end
    local x0, y0, x1, y1 = 1e9, BODY_TOP - 1, -1e9, BODY_BOTTOM + 1
    for _, b in ipairs(BODY_BLOCKS) do
        for _, sp in ipairs(b.spans) do
            x0, x1 = math.min(x0, sp[1] - 1), math.max(x1, sp[2] + 1)
        end
    end
    local bw, rows = x1 - x0, y1 - y0
    -- The doll is painted into one bit plane per color: per row, (bw + 63)
    -- // 64 integers of 64 pixels (bit 0 = leftmost). A later color clears
    -- the others' bits, as paint would. A few KB, where a table per pixel
    -- made ~0.6 MB of garbage on every change of clothes.
    local words = (bw + 63) // 64
    local planes = {}
    local real_color, real_fill, pen = gfx.color, gfx.fill_rect, gfx.WHITE
    gfx.color = function(c) pen = c end
    gfx.fill_rect = function(x, y, w, h)
        local a, z = math.max(x, x0) - x0, math.min(x + w, x1) - x0   -- columns [a, z)
        local top, bottom = math.max(y, y0) - y0, math.min(y + h, y1) - y0
        if z <= a or bottom <= top then return end
        if pen ~= gfx.WHITE and not planes[pen] then
            local p = {}
            for i = 1, rows * words do p[i] = 0 end
            planes[pen] = p
        end
        for k = a // 64, (z - 1) // 64 do
            local lo, hi = math.max(a, k * 64) - k * 64, math.min(z, k * 64 + 64) - k * 64
            local mask = (hi - lo == 64) and -1 or (((1 << (hi - lo)) - 1) << lo)
            for r = top, bottom - 1 do
                local i = r * words + k + 1
                for c, p in pairs(planes) do
                    if c == pen then p[i] = p[i] | mask else p[i] = p[i] & ~mask end
                end
            end
        end
    end
    local ok, err = pcall(self.draw_silhouette, self)
    gfx.color, gfx.fill_rect = real_color, real_fill
    if not ok then error(err) end
    local tiles, bytes = {}, {}   -- (one byte buffer for every tile)
    for _, c in ipairs({gfx.BLACK, gfx.DARK, gfx.LIGHT}) do
        local p = planes[c]
        if p then
            for ty = y0, y1 - 1, 32 do
                for tx = x0, x1 - 1, 32 do
                    local w, h = math.min(32, x1 - tx), math.min(32, y1 - ty)
                    local n, any = 0, false
                    for yy = ty, ty + h - 1 do
                        local base = (yy - y0) * words + 1
                        for bx = 0, (w + 7) // 8 - 1 do
                            local b = tx - x0 + bx * 8          -- first column of this byte
                            local k, off = b // 64, b % 64
                            local v = (p[base + k] >> off) & 0xFF
                            if off > 56 and k + 1 < words then v = v | ((p[base + k + 1] << (64 - off)) & 0xFF) end
                            local left = w - bx * 8               -- columns of the tile still in this byte
                            if left < 8 then v = v & ((1 << left) - 1) end
                            if v ~= 0 then any = true end
                            n = n + 1
                            bytes[n] = v
                        end
                    end
                    if any then tiles[#tiles + 1] = {c, tx, ty, w, h, string.char(table.unpack(bytes, 1, n))} end
                end
            end
        end
    end
    cache.tiles = tiles
    return tiles
end

-- The doll: bitmap tiles when the firmware has them, else the rects.
function Game:draw_doll()
    if not draw_sprite then return self:draw_silhouette() end
    local pen
    for _, t in ipairs(self:doll_tiles()) do
        if t[1] ~= pen then
            pen = t[1]
            gfx.color(pen)
        end
        draw_sprite(t[2], t[3], t[4], t[5], t[6])
    end
end

function Game:doll_ring(slot, pos)
    local cache = self:doll_cache()
    if cache[slot] then return cache[slot] end
    local x0, y0, x1, y1 = pos.x - 1, pos.y - 1, pos.x + pos.w, pos.y + pos.h
    -- the ring as four lines of pixels: {x, y, dx, dy, length}
    local lines = {{x0, y0, 1, 0, x1 - x0 + 1}, {x0, y1, 1, 0, x1 - x0 + 1},
                   {x0, y0 + 1, 0, 1, y1 - y0 - 1}, {x1, y0 + 1, 0, 1, y1 - y0 - 1}}
    local px = {{}, {}, {}, {}}
    local real_color, real_fill, pen = gfx.color, gfx.fill_rect, gfx.WHITE
    gfx.color = function(c) pen = c end
    gfx.fill_rect = function(x, y, w, h)
        for i, l in ipairs(lines) do
            local lx, ly = l[1], l[2]
            if l[3] == 1 then      -- a row: the part of [x, x+w) on it
                if ly >= y and ly < y + h then
                    for xx = math.max(x, lx), math.min(x + w, lx + l[5]) - 1 do px[i][xx - lx + 1] = pen end
                end
            elseif lx >= x and lx < x + w then
                for yy = math.max(y, ly), math.min(y + h, ly + l[5]) - 1 do px[i][yy - ly + 1] = pen end
            end
        end
    end
    local ok, err = pcall(self.draw_silhouette, self, {x0, y0, x1 + 1, y1 + 1})
    gfx.color, gfx.fill_rect = real_color, real_fill
    if not ok then error(err) end
    -- run-length: one rect per stretch of one color
    local runs = {}
    for i, l in ipairs(lines) do
        local start, color = 1, px[i][1]
        for k = 2, l[5] + 1 do
            if k > l[5] or px[i][k] ~= color then
                local n = k - start
                local x, y = l[1] + l[3] * (start - 1), l[2] + l[4] * (start - 1)
                runs[#runs + 1] = {color, x, y, l[3] == 1 and n or 1, l[3] == 1 and 1 or n}
                start, color = k, px[i][k]
            end
        end
    end
    cache[slot] = runs
    return runs
end

-- One cell or slot again (on top of what is there), with the cursor or not.
function Game:redraw_inv_row(i, erase)
    local row, pos = INV_ROWS[i], INV_POS[i]
    if not (row and pos) then return end
    local sel = self.inv_selected
    sel = sel ~= nil and sel[1] == row[1] and sel[2] == row[2]
    if row[1] == "equip" then
        if erase then
            -- the cursor's rect is the 1px ring just outside the slot (its
            -- own frame is redrawn below): put the doll's pixels back there
            for _, run in ipairs(self:doll_ring(row[2], pos)) do
                gfx.color(run[1])
                gfx.fill_rect(run[2], run[3], run[4], run[5])
            end
        end
        self:draw_equip_slot(row[2], pos.x, pos.y, pos.w, pos.h, i == self.inv_cursor, sel)
    else
        if erase then
            gfx.color(gfx.WHITE)
            gfx.fill_rect(pos.x - 2, pos.y - 2, pos.w + 4, pos.h + 4)
        end
        self:draw_slot_box(pos.x, pos.y, pos.w, pos.h, self:get_stack(row[1], row[2]),
                           i == self.inv_cursor, sel, pos.pocket)
    end
end

-- Only the cursor moved: redraw the cell it left, the one it's on, and the
-- description (~50 draw calls instead of ~850 for the whole screen).
function Game:move_inv_cursor_drawn(old, w)
    self:redraw_inv_row(old, true)
    self:redraw_inv_row(self.inv_cursor, true)
    -- an erase can clip the selected cell's outline (it may be the cell just
    -- left): draw it again on top, last
    local sel = self.inv_selected
    if sel then
        for i, row in ipairs(INV_ROWS) do
            if row[1] == sel[1] and row[2] == sel[2] then
                self:redraw_inv_row(i, false)
            end
        end
    end
    self:draw_inv_desc(w, true)
    -- the cells' erase boxes reach the labels' descenders: write them again
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    for _, l in ipairs(self.inv_labels or {}) do gfx.text(INV_COL_X, l[1], l[2]) end
    self.inv_drawn.cursor = self.inv_cursor
    gfx.refresh()
end

function Game:draw_inventory(w, h)
    -- cursor-only change (the screen on the panel is this one, unchanged)
    local drawn = self.inv_drawn
    if drawn and INV_ROWS and #INV_ROWS > 0 then
        self.inv_cursor = math.max(1, math.min(self.inv_cursor, #INV_ROWS))
        if self:ground_scroll(#self:ground_list() + 1) == (self.ground_off or 0)
            and self:inv_signature() == drawn.sig then
            if drawn.cursor ~= self.inv_cursor then self:move_inv_cursor_drawn(drawn.cursor, w) end
            return
        end
    end
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(4, 12, "Arrows Enter:move E:use X:drop C:craft I:map H:help")

    INV_ROWS = {}
    INV_POS = {}

    local function add_row(kind, key, x, y, w2, h2)
        table.insert(INV_ROWS, {kind, key})
        -- no x: selectable but scrolled out of view, so it gets no position
        INV_POS[#INV_ROWS] = x and {x = x, y = y, w = w2, h = h2} or nil
    end

    -- ground items grid. Every ground stack is a cursor row (ground rows come
    -- first, so cursor index == ground index), but only GROUND_GRID_ROWS rows
    -- of cells fit above the paperdoll: scroll the window to keep the cursor
    -- in view and give off-screen stacks no position.
    local ground = self:ground_list()
    -- one extra, empty cell after the last stack: somewhere to drop things
    local n_ground = #ground + 1
    local per_page = GROUND_GRID_COLS * GROUND_GRID_ROWS
    local off = self:ground_scroll(n_ground)
    self.ground_off = off
    local label = (self:at_base() and self:base_has("box")) and "Stash box" or "Ground"
    if #ground > per_page then
        label = label .. " " .. (off + 1) .. "-" .. math.min(#ground, off + per_page)
            .. "/" .. #ground
    end
    gfx.text(INV_COL_X, GROUND_Y - 5, label)
    self.inv_labels = {{GROUND_Y - 5, label}}
    for i = 1, n_ground do
        if i > off and i <= off + per_page then
            local col = (i - off - 1) % GROUND_GRID_COLS
            local row = (i - off - 1) // GROUND_GRID_COLS
            local x = INV_COL_X + 2 + col * (GROUND_CELL + GROUND_GAP)
            local y = GROUND_Y + row * (GROUND_CELL + GROUND_GAP)
            add_row("ground", i, x, y, GROUND_CELL, GROUND_CELL)
        else
            add_row("ground", i)
        end
    end

    -- equipped slots (positioned near the body, not listed)
    for _, slot in ipairs(EQUIP_SLOTS) do
        local r = EQUIP_RECT[slot]
        add_row("equip", slot, r[1], r[2], r[3], r[4])
    end

    -- bag: one cell per unit of capacity. Every stack is a row, plus the
    -- first empty cell (a drop target); the other empty cells are just drawn.
    local capacity = self:bag_capacity()
    local n_inv = #self.player.inventory
    -- with a bag on, the last `pockets` cells are your clothes' pockets: they
    -- start a row of their own when the rows allow
    local back = self.player.equipped.back
    local pockets = back and math.min(self:pocket_cells(), capacity) or 0
    local n_bag = capacity - pockets
    local rows_of = function(n) return (n + BACKPACK_COLS - 1) // BACKPACK_COLS end
    local skip = 0
    if pockets > 0 and n_inv <= capacity and rows_of(n_bag) + rows_of(pockets) <= BACKPACK_CAP // BACKPACK_COLS then
        skip = rows_of(n_bag) * BACKPACK_COLS - n_bag
    end
    local function bag_cell(i)
        local k = i > n_bag and i - 1 + skip or i - 1
        return INV_COL_X + 2 + k % BACKPACK_COLS * (BACKPACK_CELL + BACKPACK_GAP),
               BACKPACK_Y + k // BACKPACK_COLS * (BACKPACK_CELL + BACKPACK_GAP)
    end
    -- (every cell is a row: the cursor can reach any pocket, and an empty
    -- one takes what you drop on it)
    for i = 1, math.min(math.max(n_inv, capacity), BACKPACK_CAP) do
        local x, y = bag_cell(i)
        add_row("inventory", i, x, y, BACKPACK_CELL, BACKPACK_CELL)
        INV_POS[#INV_ROWS].pocket = i > n_bag and i <= capacity
    end

    self.inv_cursor = math.max(1, math.min(self.inv_cursor, #INV_ROWS))

    -- draw ground + backpack cells
    for i, row in ipairs(INV_ROWS) do
        if (row[1] == "ground" or row[1] == "inventory") and INV_POS[i] then
            local pos = INV_POS[i]
            local stack = self:get_stack(row[1], row[2])
            self:draw_slot_box(pos.x, pos.y, pos.w, pos.h, stack,
                i == self.inv_cursor,
                self.inv_selected and self.inv_selected[1] == row[1] and self.inv_selected[2] == row[2],
                pos.pocket)
        end
    end

    gfx.color(gfx.BLACK)
    gfx.text(4, CONDITIONS_Y, self:current_conditions())

    -- silhouette + equip slots
    self:draw_doll()
    for i, row in ipairs(INV_ROWS) do
        if row[1] == "equip" then
            local pos = INV_POS[i]
            self:draw_equip_slot(row[2], pos.x, pos.y, pos.w, pos.h,
                i == self.inv_cursor,
                self.inv_selected and self.inv_selected[1] == row[1] and self.inv_selected[2] == row[2])
        end
    end

    -- what the cursor is on, under the bag
    self:draw_inv_desc(w, false)

    local bag_label = (back and ITEM_DB[back].name or "Pockets") .. " " .. n_inv .. "/" .. capacity
        .. (pockets > 0 and (" " .. pockets .. " pocket" .. (pockets > 1 and "s" or "")) or "")
    gfx.text(INV_COL_X, BAG_LABEL_Y, bag_label)
    self.inv_labels[2] = {BAG_LABEL_Y, bag_label}

    -- log: the newest INV_LOG_LINES lines, the last one at h - 8
    local ly = h - 8 - 12 * (INV_LOG_LINES - 1)
    local start_i = math.max(1, #self.log - INV_LOG_LINES + 1)
    for i = start_i, #self.log do
        gfx.text(4, ly, self.log[i])
        ly = ly + 12
    end

    self.inv_drawn = {sig = self:inv_signature(), cursor = self.inv_cursor}
    gfx.refresh()
end

