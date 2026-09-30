package.path = "./?.lua;" .. package.path
local solaros = require("solaros")
solaros.gfx.begin()
local src = io.open("lib_only.lua"):read("a")
src = src:gsub("return Game, ITEM_DB, EQUIP_SLOTS, TERRAIN, SPRITES, SPRITE_ART%s*$",
               "return Game, BODY_BLOCKS, BODY_CX, BODY_TOP, BODY_BOTTOM")
local Game, BODY_BLOCKS, CX, TOP, BOTTOM = assert(load(src))()

-- 1. symmetry: every row's spans must mirror about the center line (pixel i <-> 299-i)
local asym = 0
for _, b in ipairs(BODY_BLOCKS) do
    local set = {}
    for _, sp in ipairs(b.spans) do for x = sp[1], sp[2] - 1 do set[x] = true end end
    for x in pairs(set) do
        if not set[2 * CX - 1 - x] then asym = asym + 1; break end
    end
end
print("1. asymmetric blocks:", asym, "of", #BODY_BLOCKS)

-- 2. block count (each is 2 fill_rect calls per span) - keep the per-frame cost visible
local rects = 0
for _, b in ipairs(BODY_BLOCKS) do rects = rects + #b.spans * 2 end
print("2. blocks:", #BODY_BLOCKS, " fill_rect calls per draw:", rects)

-- 3. all blocks integer + inside the body's row range
for _, b in ipairs(BODY_BLOCKS) do
    assert(math.type(b.y) == "integer" and math.type(b.h) == "integer")
    assert(b.y >= TOP and b.y + b.h <= BOTTOM, "block outside body rows")
    for _, sp in ipairs(b.spans) do
        assert(math.type(sp[1]) == "integer" and math.type(sp[2]) == "integer")
        assert(sp[2] > sp[1])
    end
end
print("3. all blocks are integers within rows " .. TOP .. ".." .. (BOTTOM - 1))

-- 4. collision check against everything else on the screen (incl. the 1px outline)
local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
local body_rects = {}
for _, b in ipairs(BODY_BLOCKS) do
    for _, sp in ipairs(b.spans) do
        body_rects[#body_rects + 1] = {sp[1] - 1, b.y - 1, sp[2] + 1, b.y + b.h + 1}
        minx = math.min(minx, sp[1] - 1); maxx = math.max(maxx, sp[2] + 1)
        miny = math.min(miny, b.y - 1);   maxy = math.max(maxy, b.y + b.h + 1)
    end
end
print(("4. figure extents incl. outline: x %d..%d  y %d..%d"):format(minx, maxx, miny, maxy))

-- layout numbers come from the game itself (lib_layout.lua), not copies
local _, L = dofile("lib_layout.lua")
local grid_w = L.GROUND_GRID_COLS * (L.GROUND_CELL + L.GROUND_GAP) - L.GROUND_GAP
local grid_h = L.GROUND_GRID_ROWS * (L.GROUND_CELL + L.GROUND_GAP) - L.GROUND_GAP
-- the figure must stay clear of these (equip slots overlay it on purpose)
local obstacles = {
    {"ground grid + cursor ring", 4, L.GROUND_Y - 2, 8 + grid_w, L.GROUND_Y + grid_h + 2},
    {"conditions text", 4, L.CONDITIONS_Y - 9, 300, L.CONDITIONS_Y + 3},
    {"bag grid + label", 4, L.BACKPACK_Y - 2, 300, L.BACKPACK_Y + 2 * L.BACKPACK_CELL + L.BACKPACK_GAP + 2},
}
local hits = 0
for _, o in ipairs(obstacles) do
    for _, r in ipairs(body_rects) do
        if r[1] < o[4] and r[3] > o[2] and r[2] < o[5] and r[4] > o[3] then
            print("   OVERLAP with " .. o[1]); hits = hits + 1; break
        end
    end
end
print("   overlaps with other UI:", hits)

-- 5. every equip slot but the back sits on the body (covers or touches it), stays
--    clear of the ground row and conditions line, and no two slots (with the
--    2px selection ring) touch
local body_px = {}
for _, b in ipairs(BODY_BLOCKS) do
    for y = b.y, b.y + b.h - 1 do
        for _, sp in ipairs(b.spans) do
            for x = sp[1], sp[2] - 1 do body_px[y * 1000 + x] = true end
        end
    end
end
local slot_problems = 0
for _, slot in ipairs(L.EQUIP_SLOTS) do
    local r = L.EQUIP_RECT[slot]
    local covered = 0
    for y = r[2] - 2, r[2] + r[4] + 1 do        -- touching the body counts (ears)
        for x = r[1] - 2, r[1] + r[3] + 1 do
            if body_px[y * 1000 + x] then covered = covered + 1 end
        end
    end
    -- the back slot is your back: drawn beside the shoulder, not over the front
    if covered == 0 and slot ~= "back" then print("   slot not on the body: " .. slot); slot_problems = slot_problems + 1 end
    if r[1] - 2 < 0 or r[1] + r[3] + 2 > 300 then print("   slot off screen: " .. slot); slot_problems = slot_problems + 1 end
    for _, o in ipairs(obstacles) do
        if r[1] - 2 < o[4] and r[1] + r[3] + 2 > o[2] and r[2] - 2 < o[5] and r[2] + r[4] + 2 > o[3] then
            print("   slot " .. slot .. " hits " .. o[1]); slot_problems = slot_problems + 1
        end
    end
    for _, other in ipairs(L.EQUIP_SLOTS) do
        local o = L.EQUIP_RECT[other]
        if other > slot and r[1] - 2 < o[1] + o[3] and r[1] + r[3] + 2 > o[1]
            and r[2] - 2 < o[2] + o[4] and r[2] + r[4] + 2 > o[2] then
            print("   slots too close: " .. slot .. " / " .. other); slot_problems = slot_problems + 1
        end
    end
end
print("5. equip slots on the body, clear of other UI, none touching:", slot_problems == 0)

assert(asym == 0 and hits == 0 and slot_problems == 0, "body test failed")
print("\nBODY TESTS PASSED")
