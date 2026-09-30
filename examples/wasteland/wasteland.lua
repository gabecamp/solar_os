--[[
Wasteland Survivor - a NEO Scavenger-style hex survival game for SolarOS.

Written for a small monochrome/grayscale portrait display (designed and
tested against 300x400) with no polygon-fill primitive available - hex
tiles are drawn as outlines (gfx.line x6) with an optional gfx.fill_rect
bounding-box wash underneath for shading, rather than the isometric 3D
block look used in the desktop/Pi version of this game. That's a
deliberate simplification for this hardware, not a missing feature.

Controls:
  Arrows / WASD   - move on the map screen, move cursor on inventory screen
  Space           - rest (map screen)
  Enter / Space   - inventory: pick up the item under the cursor, then press
                    again on a ground cell, bag cell or body slot to move it
  E               - inventory: eat/drink ONE of the item under the cursor
  I               - toggle inventory screen
  Q / ESC         - quit

This is a single self-contained script, matching the SolarOS Playground
convention (see the bundled Snake example) - no extra require()s beyond
the built-in `solaros` module.
]]

local solaros = require("solaros")
local gfx = solaros.gfx
local audio = solaros.audio

-- ---------------------------------------------------------------------
-- Tunables
-- ---------------------------------------------------------------------

local GRID_RADIUS = 4
local HEX_SIZE = 16          -- center-to-corner, in pixels
local BASE_MAX_MP = 2
local BASE_SIGHT = 2
local REST_HOURS = 4
-- gfx.getch timeout. The screen is only redrawn after a key was handled, so
-- idle wakeups just check should_exit(); this only bounds how quickly a
-- quit request from the OS is noticed.
local POLL_MS = 250

local KEY_SPACE = 32
local KEY_ENTER = 13          -- SolarOS sends Enter as '\n' (KEY_LF); CR kept just in case
local KEY_LF = 10
local KEY_ESC = 27
local KEY_A, KEY_D, KEY_S, KEY_W = 97, 100, 115, 119
local KEY_E, KEY_I, KEY_Q = 101, 105, 113

-- Terrain: id -> {name, cost (MP + hours), passable, shade}
-- shade is one of gfx.WHITE / gfx.LIGHT / gfx.DARK / gfx.BLACK, used as
-- the tile's fill when it's currently visible. ink is the glyph color that
-- contrasts with that fill (white on the dark tiles, black on the light ones).
local TERRAIN = {
    plains = {name = "Plains", cost = 1, passable = true,  shade = "WHITE", ink = "BLACK"},
    forest = {name = "Forest", cost = 2, passable = true,  shade = "LIGHT", ink = "BLACK"},
    hills  = {name = "Hills",  cost = 2, passable = true,  shade = "DARK",  ink = "WHITE"},
    water  = {name = "Water",  cost = 0, passable = false, shade = "BLACK", ink = "WHITE"},
}
local TERRAIN_WEIGHTS = {
    {"plains", 45}, {"forest", 30}, {"hills", 18}, {"water", 7},
}

local BACKPACK_CAP = 16      -- stacks; the bag strip shows all of them

local EQUIP_SLOTS = {
    "head", "ears", "eyes", "neck", "shirt",
    "jacket", "hands", "wrists", "pants", "feet",
}

local ITEM_DB = {
    tshirt       = {name = "T-Shirt",      slot = "shirt", consumable = nil},
    jeans        = {name = "Jeans",        slot = "pants", consumable = nil},
    boots        = {name = "Boots",        slot = "feet",  consumable = nil},
    cap          = {name = "Cap",          slot = "head",  consumable = nil},
    gloves       = {name = "Gloves",       slot = "hands", consumable = nil},
    canned_beans = {name = "Canned Beans", slot = nil, consumable = {hunger = 40}},
    water_bottle = {name = "Water Bottle", slot = nil, consumable = {thirst = 50}},
    rock         = {name = "Rock",         slot = nil, consumable = nil},
    cloth_scrap  = {name = "Cloth Scrap",  slot = nil, consumable = nil},
}

-- ---------------------------------------------------------------------
-- Item sprites (16x16, 1-bit)
--
-- Authored as ASCII art ('#' = drawn pixel, '.' = transparent) and packed
-- once at load into the XBM layout gfx.sprite expects: rows of
-- (w + 7) // 8 bytes, least-significant bit = leftmost pixel. 16x16 is
-- 32 bytes, well under the 128-byte-per-call limit.
-- ---------------------------------------------------------------------

local SPRITE_W, SPRITE_H = 16, 16

local SPRITE_ART = {
    tshirt = {
        "................",
        "..###......###..",
        ".####.####.####.",
        "################",
        "################",
        ".###.######.###.",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "................",
        "................",
    },
    jeans = {
        "................",
        "..############..",
        "..############..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "................",
    },
    boots = {
        "................",
        "...#####........",
        "...#####........",
        "...#####........",
        "...#####........",
        "...#####........",
        "...#####........",
        "...######.......",
        "...########.....",
        "...##########...",
        "..############..",
        "..#############.",
        "..#############.",
        "..#############.",
        "................",
        "................",
    },
    cap = {
        "................",
        "................",
        "................",
        "................",
        "....########....",
        "...##########...",
        "..############..",
        "..############..",
        "..############..",
        "..############..",
        "..#############.",
        "..##############",
        "......##########",
        "................",
        "................",
        "................",
    },
    gloves = {
        "................",
        "...##.##.##.##..",
        "...##.##.##.##..",
        "...##.##.##.##..",
        "...############.",
        "...############.",
        "...############.",
        "..#############.",
        ".##############.",
        ".#############..",
        "..############..",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "................",
    },
    canned_beans = {
        "................",
        "....########....",
        "...##########...",
        "...##########...",
        "...##########...",
        "...#........#...",
        "...#..####..#...",
        "...#.######.#...",
        "...#..####..#...",
        "...#........#...",
        "...##########...",
        "...##########...",
        "...##########...",
        "....########....",
        "................",
        "................",
    },
    water_bottle = {
        "................",
        "......####......",
        "......####......",
        "......####......",
        ".....######.....",
        "....########....",
        "....########....",
        "....#......#....",
        "....#......#....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "................",
    },
    rock = {
        "................",
        "................",
        "................",
        "................",
        "......####......",
        "....########....",
        "...##########...",
        "..###.########..",
        ".##############.",
        ".##############.",
        "################",
        "################",
        ".##############.",
        "..############..",
        "................",
        "................",
    },
    cloth_scrap = {
        "................",
        "..#######.......",
        ".#########......",
        ".##########.....",
        ".###########....",
        ".############...",
        "..############..",
        "..#####.#######.",
        "..#####.#######.",
        "...####.#######.",
        "...###..#######.",
        "....##..######..",
        ".....#...####...",
        "..........##....",
        "................",
        "................",
    },
}

-- Pack one ASCII bitmap (w x h) into the binary string gfx.sprite wants.
-- Validates the art so a typo fails loudly at load instead of drawing garbage.
local function pack_bitmap(name, rows, w, h)
    assert(#rows == h, name .. ": bitmap needs " .. h .. " rows, got " .. #rows)
    local bytes_per_row = (w + 7) // 8
    local out = {}
    for y, row in ipairs(rows) do
        assert(#row == w, name .. ": row " .. y .. " is " .. #row .. " chars, need " .. w)
        for b = 0, bytes_per_row - 1 do
            local value = 0
            for bit = 0, 7 do
                local x = b * 8 + bit
                if x < w and row:sub(x + 1, x + 1) == "#" then
                    value = value | (1 << bit)
                end
            end
            out[#out + 1] = string.char(value)
        end
    end
    local packed = table.concat(out)
    assert(#packed == bytes_per_row * h and #packed <= 128, name .. ": bad packed size")
    return packed
end

local SPRITES = {}
for item_id, rows in pairs(SPRITE_ART) do
    SPRITES[item_id] = pack_bitmap(item_id, rows, SPRITE_W, SPRITE_H)
end

-- gfx.sprite is documented as an alias of gfx.bitmap; use whichever exists
-- so an older firmware without the alias still gets icons.
local draw_sprite = gfx.sprite or gfx.bitmap

-- ---------------------------------------------------------------------
-- Terrain glyphs (10x10): drawn in the middle of each map tile and in the
-- legend, so terrain can be told apart by shape and not only by gray level
-- (light vs dark gray dither to similar patterns on a 2-level display).
-- ---------------------------------------------------------------------

local GLYPH_W, GLYPH_H = 10, 10

local GLYPH_ART = {
    plains = {              -- tufts of grass
        "..........",
        "..........",
        "#.#.......",
        ".#....#.#.",
        ".......#..",
        "..........",
        "...#.#....",
        "....#.....",
        "..........",
        "..........",
    },
    forest = {              -- pine tree
        "..........",
        "....##....",
        "...####...",
        "..######..",
        "...####...",
        "..######..",
        ".########.",
        "....##....",
        "....##....",
        "..........",
    },
    hills = {               -- rising ground
        "..........",
        "..........",
        "..........",
        "....##....",
        "...####...",
        "..######..",
        ".########.",
        "##########",
        "..........",
        "..........",
    },
    water = {               -- two rows of waves
        "..........",
        "..........",
        ".##....##.",
        "#..#..#..#",
        "....##....",
        "..........",
        ".##....##.",
        "#..#..#..#",
        "....##....",
        "..........",
    },
}

local GLYPHS = {}
for terrain_id, rows in pairs(GLYPH_ART) do
    GLYPHS[terrain_id] = pack_bitmap("glyph:" .. terrain_id, rows, GLYPH_W, GLYPH_H)
end
for terrain_id in pairs(TERRAIN) do
    assert(GLYPHS[terrain_id], "terrain has no glyph: " .. terrain_id)
end

-- ---------------------------------------------------------------------
-- Small deterministic RNG (avoids depending on math.randomseed behaving
-- a particular way on-device - same approach as the bundled Snake demo)
-- ---------------------------------------------------------------------

local function rand_next(seed)
    return (seed * 109 + 1021) % 32768
end

local function weighted_pick(seed, weights)
    seed = rand_next(seed)
    local total = 0
    for _, w in ipairs(weights) do total = total + w[2] end
    local roll = seed % total
    local acc = 0
    for _, w in ipairs(weights) do
        acc = acc + w[2]
        if roll < acc then return seed, w[1] end
    end
    return seed, weights[#weights][1]
end

-- ---------------------------------------------------------------------
-- Hex math (axial coordinates, pointy-top, flat 2D - no isometric squash)
-- ---------------------------------------------------------------------

local SQRT3 = math.sqrt(3)

local function axial_to_pixel(q, r, size)
    local x = size * (SQRT3 * q + SQRT3 / 2 * r)
    local y = size * (3 / 2 * r)
    return x, y
end

local function axial_round(qf, rf)
    local xf, zf = qf, rf
    local yf = -xf - zf
    local rx, ry, rz = math.floor(xf + 0.5), math.floor(yf + 0.5), math.floor(zf + 0.5)
    local dx, dy, dz = math.abs(rx - xf), math.abs(ry - yf), math.abs(rz - zf)
    if dx > dy and dx > dz then
        rx = -ry - rz
    elseif dy > dz then
        ry = -rx - rz
    else
        rz = -rx - ry
    end
    return rx, rz
end

local function pixel_to_axial(x, y, size)
    local qf = (SQRT3 / 3 * x - 1 / 3 * y) / size
    local rf = (2 / 3 * y) / size
    return axial_round(qf, rf)
end

local function axial_distance(aq, ar, bq, br)
    local ax, az = aq, ar
    local ay = -ax - az
    local bx, bz = bq, br
    local by = -bx - bz
    return math.max(math.abs(ax - bx), math.abs(ay - by), math.abs(az - bz))
end

local AXIAL_DIRS = {{1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1}}

local function hex_key(q, r) return q .. "," .. r end

local function neighbors(tiles, q, r)
    local result = {}
    for _, d in ipairs(AXIAL_DIRS) do
        local nq, nr = q + d[1], r + d[2]
        if tiles[hex_key(nq, nr)] then
            result[#result + 1] = {nq, nr}
        end
    end
    return result
end

-- ---------------------------------------------------------------------
-- World / player state
-- ---------------------------------------------------------------------

local function generate_world(seed)
    local tiles = {}
    for q = -GRID_RADIUS, GRID_RADIUS do
        for r = -GRID_RADIUS, GRID_RADIUS do
            if -GRID_RADIUS <= -q - r and -q - r <= GRID_RADIUS then
                local terrain
                seed, terrain = weighted_pick(seed, TERRAIN_WEIGHTS)
                tiles[hex_key(q, r)] = terrain
            end
        end
    end
    tiles[hex_key(0, 0)] = "plains"

    local ground = {}
    ground[hex_key(0, 0)] = {
        {item = "rock", qty = 1},
        {item = "cloth_scrap", qty = 2},
        {item = "canned_beans", qty = 1},
        {item = "water_bottle", qty = 2},
    }
    return tiles, ground, seed
end

local function new_player()
    return {
        q = 0, r = 0,
        max_mp = BASE_MAX_MP,
        mp = BASE_MAX_MP,
        sight = BASE_SIGHT,
        hours = 0,
        needs = {hunger = 100, thirst = 100, rest = 100},
        equipped = {shirt = "tshirt", pants = "jeans", feet = "boots"},
        inventory = {
            {item = "water_bottle", qty = 1},
            {item = "canned_beans", qty = 1},
        },
        explored = {},
        visible = {},
    }
end

local function update_visibility(player, tiles)
    player.visible = {}
    for key in pairs(tiles) do
        local q, r = key:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        if axial_distance(player.q, player.r, q, r) <= player.sight then
            player.visible[key] = true
            player.explored[key] = true
        end
    end
end

local function clamp(v) return math.max(0, math.min(100, v)) end

local function apply_awake_hours(player, hours)
    player.needs.hunger = clamp(player.needs.hunger - hours * (100 / 72))
    player.needs.thirst = clamp(player.needs.thirst - hours * (100 / 48))
    player.needs.rest = clamp(player.needs.rest - hours * (100 / 18))
end

local function apply_rest_hours(player, hours)
    player.needs.hunger = clamp(player.needs.hunger - hours * (100 / 72) * 0.5)
    player.needs.thirst = clamp(player.needs.thirst - hours * (100 / 48) * 0.5)
    player.needs.rest = clamp(player.needs.rest + hours * (100 / 6))
end

local function effective_max_mp(player)
    local penalty = 0
    if player.needs.hunger <= 0 then penalty = penalty + 1 end
    if player.needs.thirst <= 0 then penalty = penalty + 1 end
    if player.needs.rest <= 0 then penalty = penalty + 1 end
    return math.max(1, player.max_mp - penalty)
end

-- ---------------------------------------------------------------------
-- Game object (holds everything one screen/session needs)
-- ---------------------------------------------------------------------

local Game = {}
Game.__index = Game

function Game.new()
    local self = setmetatable({}, Game)
    -- The SolarOS Lua runtime does not load the `os` library, so seed from
    -- uptime instead; the constant is only a fallback for other hosts.
    local seed = 12345
    local clock = solaros.time and solaros.time.uptime_ms
    if clock then
        seed = math.floor(clock()) % 32768
    elseif os and os.time then
        seed = os.time() % 32768
    end
    self.tiles, self.ground, seed = generate_world(seed)
    self.player = new_player()
    update_visibility(self.player, self.tiles)
    self.screen = "map"          -- "map" or "inventory"
    self.log = {"You wake up in the wasteland."}
    self.inv_cursor = 1
    self.inv_selected = nil      -- {"ground"|"inventory"|"equip", key}
    self.quit = false
    return self
end

function Game:push_log(text)
    table.insert(self.log, text)
    while #self.log > 3 do table.remove(self.log, 1) end
end

-- -- movement / rest --------------------------------------------------

function Game:try_move(q, r)
    local p = self.player
    local key = hex_key(q, r)
    local terrain_id = self.tiles[key]
    if not terrain_id then return end
    local found = false
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        if n[1] == q and n[2] == r then found = true end
    end
    if not found then return end
    local terrain = TERRAIN[terrain_id]
    if not terrain.passable then
        self:push_log("Can't cross " .. terrain.name .. ".")
        return
    end
    if p.mp <= 0 then
        self:push_log("Out of movement. Rest first.")
        return
    end
    p.mp = p.mp - terrain.cost
    p.q, p.r = q, r
    p.hours = p.hours + terrain.cost
    apply_awake_hours(p, terrain.cost)
    update_visibility(p, self.tiles)
    self:push_log("Moved to " .. terrain.name .. " (" .. terrain.cost .. " MP)")
    if p.needs.hunger <= 0 then self:push_log("You are starving!") end
    if p.needs.thirst <= 0 then self:push_log("You are dehydrated!") end
end

function Game:move_dir(dq, dr)
    local p = self.player
    -- pick the neighbor whose pixel-space direction best matches (dq,dr)
    local px, py = axial_to_pixel(p.q, p.r, HEX_SIZE)
    local best, best_dot = nil, -math.huge
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        local nx, ny = axial_to_pixel(n[1], n[2], HEX_SIZE)
        local vx, vy = nx - px, ny - py
        local len = math.sqrt(vx * vx + vy * vy)
        if len == 0 then len = 1 end
        local dot = (vx / len) * dq + (vy / len) * dr
        if dot > best_dot then best_dot, best = dot, n end
    end
    if best then self:try_move(best[1], best[2]) end
end

function Game:rest()
    local p = self.player
    local cap = effective_max_mp(p)
    if p.mp >= cap then
        self:push_log("Already rested.")
        return
    end
    p.hours = p.hours + REST_HOURS
    apply_rest_hours(p, REST_HOURS)
    p.mp = effective_max_mp(p)
    update_visibility(p, self.tiles)
    self:push_log("Rested " .. REST_HOURS .. "h.")
end

-- -- inventory transfer -------------------------------------------------

function Game:ground_list()
    local key = hex_key(self.player.q, self.player.r)
    self.ground[key] = self.ground[key] or {}
    return self.ground[key]
end

function Game:get_stack(kind, k)
    if kind == "ground" then
        return self:ground_list()[k]
    elseif kind == "inventory" then
        return self.player.inventory[k]
    elseif kind == "equip" then
        local item = self.player.equipped[k]
        return item and {item = item, qty = 1} or nil
    end
end

function Game:remove_stack(kind, k)
    if kind == "ground" then
        return table.remove(self:ground_list(), k)
    elseif kind == "inventory" then
        return table.remove(self.player.inventory, k)
    elseif kind == "equip" then
        local item = self.player.equipped[k]
        self.player.equipped[k] = nil
        return item and {item = item, qty = 1} or nil
    end
end

-- Add stack to list, merging into an existing stack of the same item so the
-- same thing never takes two cells. Returns false (list untouched) when a new
-- stack is needed and the list already holds `cap` stacks.
local function add_to_list(list, stack, cap)
    for _, s in ipairs(list) do
        if s.item == stack.item then
            s.qty = s.qty + stack.qty
            return true
        end
    end
    if cap and #list >= cap then return false end
    table.insert(list, stack)
    return true
end

function Game:put_stack(kind, k, stack)
    if kind == "ground" then
        add_to_list(self:ground_list(), stack)
        return true
    elseif kind == "inventory" then
        if not add_to_list(self.player.inventory, stack, BACKPACK_CAP) then
            self:push_log("Backpack full.")
            return false
        end
        return true
    elseif kind == "equip" then
        local def = ITEM_DB[stack.item]
        if def.slot ~= k then
            self:push_log(def.name .. " can't go in " .. k .. ".")
            return false
        end
        local current = self.player.equipped[k]
        if current then
            local old = {item = current, qty = 1}
            if not add_to_list(self.player.inventory, old, BACKPACK_CAP) then
                add_to_list(self:ground_list(), old)
                self:push_log("Bag full: " .. ITEM_DB[current].name .. " dropped.")
            end
        end
        self.player.equipped[k] = stack.item
        -- equipping takes one; anything else in the stack goes to the bag
        if stack.qty > 1 then
            local rest = {item = stack.item, qty = stack.qty - 1}
            if not add_to_list(self.player.inventory, rest, BACKPACK_CAP) then
                add_to_list(self:ground_list(), rest)
            end
        end
        return true
    end
end

-- Undo a remove_stack: put the stack back exactly where it came from.
function Game:restore_stack(kind, k, stack)
    if kind == "ground" then
        table.insert(self:ground_list(), k, stack)
    elseif kind == "inventory" then
        table.insert(self.player.inventory, k, stack)
    elseif kind == "equip" then
        self.player.equipped[k] = stack.item
    end
end

function Game:try_transfer(source, dest)
    local s_kind, s_key = source[1], source[2]
    local d_kind, d_key = dest[1], dest[2]
    if s_kind == d_kind and s_key == d_key then return end
    local stack = self:remove_stack(s_kind, s_key)
    if not stack then return end
    local ok = self:put_stack(d_kind, d_key, stack)
    if not ok then
        self:restore_stack(s_kind, s_key, stack)
    else
        self:push_log("Moved " .. ITEM_DB[stack.item].name .. ".")
    end
end

function Game:try_consume(kind, k)
    local stack = self:get_stack(kind, k)
    if not stack then return end
    local def = ITEM_DB[stack.item]
    if not def.consumable then
        self:push_log(def.name .. " isn't edible/drinkable.")
        return
    end
    for need, amount in pairs(def.consumable) do
        self.player.needs[need] = clamp(self.player.needs[need] + amount)
    end
    -- one unit per use; the stack only disappears when it runs out
    stack.qty = stack.qty - 1
    if stack.qty <= 0 then
        self:remove_stack(kind, k)
    end
    self:push_log("Consumed " .. def.name .. ".")
end

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

-- Vertical layout of the map screen (300x400): HUD text above MAP_TOP, the
-- hex map centered between MAP_TOP and the legend, then the legend (two rows
-- of 14px swatches), the message log, and the key hints on the last line.
local MAP_TOP = 58
local LEGEND_Y = 306
local LEGEND_ORDER = {"plains", "forest", "hills", "water"}

function Game:draw_map(w, h)
    gfx.clear(gfx.WHITE)

    local p = self.player
    local origin_x, origin_y = w // 2, (MAP_TOP + LEGEND_Y - 4) // 2

    -- HUD
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Wasteland Survivor")
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(6, 34, "MP " .. math.max(p.mp, 0) .. "/" .. p.max_mp
        .. "   Hrs " .. p.hours .. "   Sight " .. p.sight)
    gfx.text(6, 50, "Hun " .. math.floor(p.needs.hunger)
        .. " Thi " .. math.floor(p.needs.thirst)
        .. " Rst " .. math.floor(p.needs.rest))

    local reachable = {}
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        reachable[hex_key(n[1], n[2])] = true
    end

    for key, terrain_id in pairs(self.tiles) do
        local q, r = key:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        local px, py = axial_to_pixel(q, r, HEX_SIZE)
        px, py = origin_x + px, origin_y + py
        if px > -HEX_SIZE * 2 and px < w + HEX_SIZE * 2 and py > MAP_TOP and py < LEGEND_Y then
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
    gfx.text(6, h - 8, "Arrows move  Space rest  I inventory  Q quit")

    gfx.refresh()
end

-- Terrain key: swatch (same fill + glyph as on the map), name, and what it
-- costs to cross. The tile you're standing on gets a second box.
function Game:draw_legend()
    local here = self.tiles[hex_key(self.player.q, self.player.r)]
    gfx.font(gfx.FONT_MONO_12)
    for i, terrain_id in ipairs(LEGEND_ORDER) do
        local t = TERRAIN[terrain_id]
        local col, row = (i - 1) % 2, (i - 1) // 2
        local x, y = 6 + col * 150, LEGEND_Y + row * 16

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

-- Equip slots are positioned near their body region rather than listed
-- top-to-bottom, echoing the reference screenshot's paperdoll layout.
-- Screen is 300x400 - a narrow portrait target, so slots flank the
-- silhouette in two columns instead of surrounding it freely.
local EQUIP_COL_X = {head = 14, ears = 14, eyes = 14, neck = 14, shirt = 14,
                      jacket = 264, hands = 264, wrists = 264, pants = 264, feet = 264}
local EQUIP_ROW_Y = {head = 120, ears = 150, eyes = 180, neck = 210, shirt = 240,
                      jacket = 120, hands = 150, wrists = 180, pants = 210, feet = 240}
local EQUIP_ABBR = {head = "Hd", ears = "Ea", eyes = "Ey", neck = "Nk", shirt = "Sh",
                     jacket = "Ja", hands = "Hn", wrists = "Wr", pants = "Pt", feet = "Ft"}
local EQUIP_BOX = 22

local GROUND_GRID_COLS = 6
local GROUND_GRID_ROWS = 2   -- visible rows; the grid scrolls to follow the cursor
local GROUND_CELL, GROUND_GAP = 40, 3
local GROUND_Y = 32
-- bag: BACKPACK_CAP cells in two rows, all visible
local BACKPACK_COLS = 8
local BACKPACK_CELL, BACKPACK_GAP = 26, 2
local BACKPACK_Y = 318
local CONDITIONS_Y = 300
local INV_LOG_Y, INV_LOG_LINES = 385, 2

local function item_abbr(item_id)
    return ITEM_DB[item_id].name:sub(1, 1)
end

function Game:current_conditions()
    -- Only conditions we actually track - nothing fabricated (no injury/
    -- temperature model exists yet, so none are listed here).
    local list = {}
    if self.player.equipped.feet == nil then table.insert(list, "Barefoot") end
    if self.player.needs.hunger <= 0 then table.insert(list, "Starving") end
    if self.player.needs.thirst <= 0 then table.insert(list, "Dehydrated") end
    if self.player.needs.rest <= 0 then table.insert(list, "Exhausted") end
    if #list == 0 then return "Conditions: none" end
    local text = table.concat(list, ", ")
    -- all four at once don't fit after the prefix (mono 12 is ~7px/char)
    if (12 + #text) * 7 > 292 then return text end
    return "Conditions: " .. text
end

function Game:draw_slot_box(x, y, w, h, stack, is_cursor, is_selected)
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
            gfx.text(x + w - 2 - 7 * #qty_text, y + h - 2, qty_text)
        end
    end
    gfx.color(gfx.BLACK)
    gfx.rect(x, y, w, h)
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

local BODY_CX = 150
local BODY_TOP, BODY_BOTTOM = 117, 289   -- rows; bottom exclusive

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

-- head
BODY_POLYGONS[#BODY_POLYGONS + 1] = ellipse_points(128, 9, 11, 24)
-- neck, sloped shoulders, tapered torso down to the hips
BODY_POLYGONS[#BODY_POLYGONS + 1] = symmetric({
    0, 139,  4, 139,  4, 146,  14, 148,  27, 151,  31, 156,  30, 164,
    25, 170,  22, 182,  19, 200,  21, 214,  23, 226,  0, 226,
})
-- arms hang slightly away from the body and end in hands
local ARM = {
    30, 151,  38, 154,  42, 175,  46, 195,  50, 215,  53, 230,
    56, 238,  56, 246,  52, 250,  48, 246,  47, 238,  47, 230,
    43, 215,  37, 195,  31, 178,  27, 166,  28, 158,
}
BODY_POLYGONS[#BODY_POLYGONS + 1] = ARM
BODY_POLYGONS[#BODY_POLYGONS + 1] = mirror_x(ARM)
-- legs: thigh, knee, calf, ankle, and a foot angled outward
local LEG = {
    1, 224,  23, 224,  22, 240,  20, 254,  18, 266,  15, 278,
    20, 284,  21, 288,  3, 288,  3, 282,  5, 270,  4, 254,  2, 240,
}
BODY_POLYGONS[#BODY_POLYGONS + 1] = LEG
BODY_POLYGONS[#BODY_POLYGONS + 1] = mirror_x(LEG)

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

local function build_body_blocks()
    local blocks, prev_key = {}, nil
    for y = BODY_TOP, BODY_BOTTOM - 1 do
        local all = {}
        for _, poly in ipairs(BODY_POLYGONS) do
            for _, sp in ipairs(polygon_row_spans(poly, y + 0.5)) do
                all[#all + 1] = sp
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

local BODY_BLOCKS = build_body_blocks()

function Game:draw_silhouette()
    -- pass 1: outline (every block grown by 1px, black)
    gfx.color(gfx.BLACK)
    for _, b in ipairs(BODY_BLOCKS) do
        for _, sp in ipairs(b.spans) do
            gfx.fill_rect(sp[1] - 1, b.y - 1, sp[2] - sp[1] + 2, b.h + 2)
        end
    end
    -- pass 2: body fill at true size
    gfx.color(gfx.LIGHT)
    for _, b in ipairs(BODY_BLOCKS) do
        for _, sp in ipairs(b.spans) do
            gfx.fill_rect(sp[1], b.y, sp[2] - sp[1], b.h)
        end
    end
    -- waistband
    gfx.color(gfx.BLACK)
    gfx.line(BODY_CX - 18, 205, BODY_CX + 18, 205)
end

function Game:draw_inventory(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(4, 12, "Up/Dn Enter:move E:eat/drink I:map")

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
    local per_page = GROUND_GRID_COLS * GROUND_GRID_ROWS
    local off = self.ground_off or 0
    if self.inv_cursor <= #ground then
        local crow = (self.inv_cursor - 1) // GROUND_GRID_COLS
        local first = off // GROUND_GRID_COLS
        if crow < first then
            off = crow * GROUND_GRID_COLS
        elseif crow >= first + GROUND_GRID_ROWS then
            off = (crow - GROUND_GRID_ROWS + 1) * GROUND_GRID_COLS
        end
    end
    local total_rows = (#ground + GROUND_GRID_COLS - 1) // GROUND_GRID_COLS
    off = math.max(0, math.min(off, (total_rows - GROUND_GRID_ROWS) * GROUND_GRID_COLS))
    self.ground_off = off
    local label = "Items on the ground here"
    if #ground > per_page then
        label = label .. " " .. (off + 1) .. "-" .. math.min(#ground, off + per_page)
            .. "/" .. #ground
    end
    gfx.text(4, 26, label)
    for i, _ in ipairs(ground) do
        if i > off and i <= off + per_page then
            local col = (i - off - 1) % GROUND_GRID_COLS
            local row = (i - off - 1) // GROUND_GRID_COLS
            local x = 6 + col * (GROUND_CELL + GROUND_GAP)
            local y = GROUND_Y + row * (GROUND_CELL + GROUND_GAP)
            add_row("ground", i, x, y, GROUND_CELL, GROUND_CELL)
        else
            add_row("ground", i)
        end
    end

    -- equipped slots (positioned near the body, not listed)
    for _, slot in ipairs(EQUIP_SLOTS) do
        add_row("equip", slot, EQUIP_COL_X[slot], EQUIP_ROW_Y[slot], EQUIP_BOX, EQUIP_BOX)
    end

    -- backpack: two rows of cells
    for i, _ in ipairs(self.player.inventory) do
        local col = (i - 1) % BACKPACK_COLS
        local row = (i - 1) // BACKPACK_COLS
        local x = 6 + col * (BACKPACK_CELL + BACKPACK_GAP)
        local y = BACKPACK_Y + row * (BACKPACK_CELL + BACKPACK_GAP)
        add_row("inventory", i, x, y, BACKPACK_CELL, BACKPACK_CELL)
    end

    self.inv_cursor = math.max(1, math.min(self.inv_cursor, #INV_ROWS))

    -- draw ground + backpack cells
    for i, row in ipairs(INV_ROWS) do
        if (row[1] == "ground" or row[1] == "inventory") and INV_POS[i] then
            local pos = INV_POS[i]
            local stack = self:get_stack(row[1], row[2])
            self:draw_slot_box(pos.x, pos.y, pos.w, pos.h, stack,
                i == self.inv_cursor,
                self.inv_selected and self.inv_selected[1] == row[1] and self.inv_selected[2] == row[2])
        end
    end

    gfx.color(gfx.BLACK)
    gfx.text(4, CONDITIONS_Y, self:current_conditions())

    -- silhouette + equip slots
    self:draw_silhouette()
    for i, row in ipairs(INV_ROWS) do
        if row[1] == "equip" then
            local pos = INV_POS[i]
            local stack = self:get_stack(row[1], row[2])
            self:draw_slot_box(pos.x, pos.y, pos.w, pos.h, stack,
                i == self.inv_cursor,
                self.inv_selected and self.inv_selected[1] == row[1] and self.inv_selected[2] == row[2])
            gfx.color(gfx.BLACK)
            -- Label goes beside the box, on the side facing the silhouette.
            -- (Under the box it collided with the next slot: 30px spacing
            -- can't hold a 22px box plus a text line.) Mono 12 is ~7px/char.
            local abbr = EQUIP_ABBR[row[2]]
            if pos.x < 150 then
                gfx.text(pos.x + pos.w + 4, pos.y + 15, abbr)
            else
                gfx.text(pos.x - 4 - 7 * #abbr, pos.y + 15, abbr)
            end
        end
    end

    gfx.color(gfx.BLACK)
    gfx.text(6, BACKPACK_Y - 5, "Bag " .. #self.player.inventory .. "/" .. BACKPACK_CAP)

    -- log: the bag's second row ends at BACKPACK_Y + 54 = 372, so only the
    -- newest INV_LOG_LINES lines fit below it
    local ly = INV_LOG_Y
    local start_i = math.max(1, #self.log - INV_LOG_LINES + 1)
    for i = start_i, #self.log do
        gfx.text(4, ly, self.log[i])
        ly = ly + 12
    end

    gfx.refresh()
end

-- ---------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------

gfx.begin()

local ok, err = pcall(function()
    local game = Game.new()
    local w, h = gfx.size()

    local function handle_map_key(key)
        if key == gfx.KEY_ESCAPE or key == KEY_Q then
            game.quit = true
        elseif key == gfx.KEY_LEFT or key == KEY_A then
            game:move_dir(-1, 0)
        elseif key == gfx.KEY_RIGHT or key == KEY_D then
            game:move_dir(1, 0)
        elseif key == gfx.KEY_UP or key == KEY_W then
            game:move_dir(0, -1)
        elseif key == gfx.KEY_DOWN or key == KEY_S then
            game:move_dir(0, 1)
        elseif key == KEY_SPACE then
            game:rest()
        elseif key == KEY_I then
            game.screen = "inventory"
            game.inv_cursor = 1
            game.inv_selected = nil
        end
    end

    local function handle_inventory_key(key)
        if key == gfx.KEY_ESCAPE or key == KEY_Q then
            game.quit = true
        elseif key == KEY_I then
            game.screen = "map"
        elseif key == gfx.KEY_UP or key == KEY_W then
            game.inv_cursor = math.max(1, game.inv_cursor - 1)
        elseif key == gfx.KEY_DOWN or key == KEY_S then
            game.inv_cursor = math.min(#INV_ROWS, game.inv_cursor + 1)
        elseif key == KEY_E then
            local row = INV_ROWS[game.inv_cursor]
            if row then
                game:try_consume(row[1], row[2])
                -- the stack may be gone or shifted; don't keep a stale pick
                game.inv_selected = nil
            end
        elseif key == KEY_ENTER or key == KEY_LF or key == KEY_SPACE then
            local row = INV_ROWS[game.inv_cursor]
            if row then
                if game.inv_selected == nil then
                    if game:get_stack(row[1], row[2]) ~= nil then
                        game.inv_selected = {row[1], row[2]}
                    end
                else
                    game:try_transfer(game.inv_selected, {row[1], row[2]})
                    game.inv_selected = nil
                end
            end
        end
    end

    -- Redraw only after a key was handled: nothing changes on its own, and a
    -- full frame is hundreds of gfx calls plus a panel refresh.
    local dirty = true
    while not game.quit and not solaros.should_exit() do
        if dirty then
            if game.screen == "map" then
                game:draw_map(w, h)
            else
                game:draw_inventory(w, h)
            end
            dirty = false
        end

        local key = gfx.getch(POLL_MS)
        if key ~= nil then
            if game.screen == "map" then
                handle_map_key(key)
            else
                handle_inventory_key(key)
            end
            dirty = true
        end
    end
end)

-- Per SolarOS convention: cleanup must run even when drawing/logic fails,
-- and the error is re-raised afterward so it still surfaces (with a real
-- traceback) instead of being silently swallowed.
gfx["end"]()
if not ok then
    error(err)
end
