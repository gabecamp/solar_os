-- ---------------------------------------------------------------------
-- Encounter portraits
--
-- Painted by tools/paint_portraits.py and baked into PORTRAIT_DATA (the
-- part before this one) as 1-bit 32x32 sprite tiles, base64 text. Only the
-- creature on screen is decoded, and only once: PORTRAIT_CACHE holds one
-- subject, so memory stays at a few KB whatever the roster grows to.
--
-- The picture reacts to the fight: far away it is small, near it fills the
-- frame, close up you see its face; wounds show as it gets hurt; dead or
-- fled changes it again.
-- ---------------------------------------------------------------------

local PORTRAIT_SIZE = 96

local B64_VAL = {}   -- base64 digit -> value
do
    local digits = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #digits do B64_VAL[digits:byte(i)] = i - 1 end
end

local function b64_decode(text)
    local out, n = {}, 0
    for i = 1, #text, 4 do
        local a, b = B64_VAL[text:byte(i)], B64_VAL[text:byte(i + 1)]
        local c3, d4 = text:byte(i + 2), text:byte(i + 3)
        local c, d = B64_VAL[c3], B64_VAL[d4]
        local v = (a << 18) | (b << 12) | ((c or 0) << 6) | (d or 0)
        n = n + 1; out[n] = string.char((v >> 16) & 0xff)
        if c then n = n + 1; out[n] = string.char((v >> 8) & 0xff) end
        if d then n = n + 1; out[n] = string.char(v & 0xff) end
    end
    return table.concat(out)
end

local PORTRAIT_CACHE = {who = nil, views = {}, empty = string.rep("\0", 128)}

-- The tiles of one view ({x, y, data} per non-empty 32x32 tile), decoded on
-- first use. Returns nil for a subject with no art.
local function portrait_view(who, view)
    local entry = PORTRAIT_DATA[who]
    if not entry or not entry[view] then return nil end
    if PORTRAIT_CACHE.who ~= who then
        PORTRAIT_CACHE.who, PORTRAIT_CACHE.views = who, {}
    end
    local cached = PORTRAIT_CACHE.views[view]
    if cached then return cached end
    local v = entry[view]
    local bytes = b64_decode(v.data)
    local tiles = {}
    for ty = 0, v.th - 1 do
        for tx = 0, v.tw - 1 do
            local k = (ty * v.tw + tx) * 128
            local tile = bytes:sub(k + 1, k + 128)
            if tile ~= PORTRAIT_CACHE.empty then
                tiles[#tiles + 1] = {x = tx * 32, y = ty * 32, data = tile}
            end
        end
    end
    cached = {w = v.w, h = v.h, th = v.th, tiles = tiles, marks = v.marks}
    PORTRAIT_CACHE.views[view] = cached
    return cached
end

-- How many wound marks to show for a fraction of health left (the same
-- bands as Game:enemy_condition: unhurt > 0.75, hurt > 0.4, else badly).
function Game.wound_count(frac)
    if frac > 0.75 then return 0 elseif frac > 0.4 then return 5 end
    return 11
end

-- Draw the portrait for encounter e in a 96x96 frame at (x, y).
function Game:draw_portrait(e, x, y)
    local size = PORTRAIT_SIZE
    gfx.color(gfx.WHITE)
    gfx.fill_rect(x, y, size, size)
    gfx.color(gfx.BLACK)
    local who = e.def.art
    local fights = e.def.hp ~= nil
    if e.outcome == "fled" then
        gfx.rect(x, y, size, size)
        gfx.font(gfx.FONT_MONO_12)
        gfx.text(x + size // 2 - 14, y + size // 2 + 4, "gone")
        return
    end
    -- far: the small view low in the frame, as if across the field;
    -- close: the face fills it; near (and everything that doesn't fight): all of it
    local view = "near"
    if fights and e.outcome ~= "dead" then
        if e.range == "far" then view = "far" elseif e.range == "close" then view = "close" end
    end
    local v = who and portrait_view(who, view)
    if v then
        -- tiles are 32x32, so a 48 px view is padded to 64: place by the
        -- padded size so no tile hangs outside the frame (far sits low-ish)
        local ox = x + (size - v.w) // 2
        local oy = y + size - v.th * 32
        for _, t in ipairs(v.tiles) do
            draw_sprite(ox + t.x, oy + t.y, 32, 32, t.data)
        end
        -- wounds: small dark blots on the creature, more as it weakens
        local frac = fights and math.max(0, e.hp / e.def.hp) or 1
        local n = e.outcome == "dead" and #v.marks // 2 or Game.wound_count(frac)
        local r = view == "far" and 1 or 2
        for i = 1, math.min(n, #v.marks // 2) do
            local mx, my = v.marks[2 * i - 1], v.marks[2 * i]
            gfx.fill_rect(ox + mx - r, oy + my - r, 2 * r + 1, 2 * r)
            gfx.fill_rect(ox + mx - r + 1, oy + my + r, 2 * r - 1, r + 1)   -- a drip
        end
    end
    if e.outcome == "dead" then
        -- dead: a dark hatch across the picture
        gfx.color(gfx.DARK)
        for k = -size, size, 6 do
            local x0, x1 = math.max(0, k), math.min(size - 1, k + size - 1)
            if x1 > x0 then gfx.line(x + x0, y + x0 - k, x + x1, y + x1 - k) end
        end
        gfx.color(gfx.BLACK)
    end
    gfx.rect(x, y, size, size)
end
