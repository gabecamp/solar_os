-- Worst-case inventory layout: full bag, more ground stacks than fit, every
-- slot filled. Checks every cell is on screen and that the cell/text regions
-- never overlap each other. Positions are read back from the INV_POS table
-- the game itself fills while drawing, and constants from lib_layout.lua.
-- Runs at the device size, 400x300.
package.path = "./?.lua;" .. package.path
local solaros = require("solaros")
local gfx = solaros.gfx
gfx.begin()

local Game, L, rows_pos = dofile("lib_layout.lua")

local W, H = 400, 300
local game = Game.new()
game.player.q, game.player.r = 0, 0
game.player.bag_bonus = 16   -- widest possible bag: every one of BACKPACK_CAP cells

-- full bag (distinct fake items so nothing merges), 15 ground stacks
game.player.inventory = {}
for i = 1, L.BACKPACK_CAP do game.player.inventory[i] = {item = "rock", qty = i} end
local ground = game:ground_list()
while #ground < 15 do ground[#ground + 1] = {item = "cloth_scrap", qty = #ground} end
for _, slot in ipairs(L.EQUIP_SLOTS) do game.player.equipped[slot] = "cap" end

local problems = 0
local function fail(msg) print("  " .. msg); problems = problems + 1 end

local function check_frame(label)
    label = label .. " @" .. H .. "px"
    game:draw_inventory(W, H)
    local INV_ROWS, INV_POS = rows_pos()
    local rects = {}
    local shown = {ground = 0, inventory = 0, equip = 0}
    for i, row in ipairs(INV_ROWS) do
        local p = INV_POS[i]
        if p and p.x then
            shown[row[1]] = shown[row[1]] + 1
            if p.x - 2 < 0 or p.y - 2 < 0 or p.x + p.w + 2 > W or p.y + p.h + 2 > H then
                fail(("%s: %s %s out of bounds"):format(label, row[1], tostring(row[2])))
            end
            -- exact cell; the 2px selection ring only matters against text
            rects[#rects + 1] = {row[1] .. ":" .. tostring(row[2]), p.x, p.y, p.x + p.w, p.y + p.h, cell = true}
        elseif row[1] ~= "ground" then
            fail(label .. ": " .. row[1] .. " row has no position (not drawn)")
        end
        if i == game.inv_cursor and not (p and p.x) then
            fail(label .. ": cursor row " .. i .. " is off screen")
        end
    end
    -- text lines (approximate glyph box: baseline-9 .. baseline+3)
    rects[#rects + 1] = {"conditions", 0, L.CONDITIONS_Y - 9, W, L.CONDITIONS_Y + 3}
    rects[#rects + 1] = {"bag label", L.INV_COL_X, L.BAG_LABEL_Y - 9, W, L.BAG_LABEL_Y + 3}
    rects[#rects + 1] = {"ground label", L.INV_COL_X, L.GROUND_Y - 14, W, L.GROUND_Y - 2}
    rects[#rects + 1] = {"cursor line", L.INV_COL_X, L.CURSOR_DESC_Y - 9, W, L.CURSOR_DESC_Y + 3}
    rects[#rects + 1] = {"key hint", 0, 0, W, 15}
    for k = 0, L.INV_LOG_LINES - 1 do
        local y = H - 8 - 12 * (L.INV_LOG_LINES - 1 - k)
        if y + 3 > H then fail(label .. ": log line " .. (k + 1) .. " below the screen") end
        rects[#rects + 1] = {"log" .. (k + 1), 0, y - 9, W, y + 3}
    end
    for a = 1, #rects do
        for b = a + 1, #rects do
            local r, s = rects[a], rects[b]
            local m = (r.cell ~= s.cell) and 2 or 0   -- ring vs text
            if r[2] - m < s[4] and r[4] + m > s[2] and r[3] - m < s[5] and r[5] + m > s[3] then
                fail(("%s: %s overlaps %s"):format(label, r[1], s[1]))
            end
        end
    end
    return shown
end

for _, height in ipairs({300}) do
    H = height
    game.inv_cursor = 1
    local shown = check_frame("cursor on first ground stack")
    print("bag cells drawn:", shown.inventory, "of", #game.player.inventory)
    assert(shown.inventory == L.BACKPACK_CAP, "every bag stack must be drawn")
    print("ground cells drawn:", shown.ground, "of", #ground + 1)
    assert(shown.ground == L.GROUND_GRID_COLS * L.GROUND_GRID_ROWS)

    game.inv_cursor = #ground + 1   -- the empty drop cell after the last stack
    check_frame("cursor on the ground drop cell")
    print("ground window after scrolling to the end starts at", game.ground_off + 1)

    game.inv_cursor = 1             -- and back
    check_frame("cursor back on first ground stack")
    assert(game.ground_off == 0, "grid should scroll back to the top")
end

print("\nproblems found:", problems)
assert(problems == 0, "inventory layout problems")
