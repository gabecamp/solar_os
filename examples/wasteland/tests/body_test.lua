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
local obstacles = {
    {"ground grid, worst case (all visible rows full)", 6, L.GROUND_Y, 6 + grid_w, L.GROUND_Y + grid_h},
    {"conditions text", 4, L.CONDITIONS_Y - 9, 300, L.CONDITIONS_Y + 3},
    {"bag label", 6, L.BACKPACK_Y - 14, 80, L.BACKPACK_Y - 2},
}
for _, slot in ipairs(L.EQUIP_SLOTS) do
    local cx, ry, box = L.EQUIP_COL_X[slot], L.EQUIP_ROW_Y[slot], L.EQUIP_BOX
    table.insert(obstacles, {"equip box " .. slot, cx - 2, ry - 2, cx + box + 2, ry + box + 2})
    if cx < 150 then
        table.insert(obstacles, {"equip label " .. slot, cx + box + 4, ry + 5, cx + box + 22, ry + 19})
    else
        table.insert(obstacles, {"equip label " .. slot, cx - 20, ry + 5, cx - 2, ry + 19})
    end
end
local hits = 0
for _, o in ipairs(obstacles) do
    for _, r in ipairs(body_rects) do
        if r[1] < o[4] and r[3] > o[2] and r[2] < o[5] and r[4] > o[3] then
            print("   OVERLAP with " .. o[1]); hits = hits + 1; break
        end
    end
end
print("   overlaps with other UI:", hits)
assert(asym == 0 and hits == 0, "body test failed")
print("\nBODY TESTS PASSED")
