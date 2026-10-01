package.path = "./?.lua;" .. package.path
local solaros = require("solaros")
solaros.gfx.begin()
local Game, ITEM_DB, EQUIP_SLOTS, TERRAIN, SPRITES, SPRITE_ART = dofile("lib_only.lua")

-- 1. every item has art, and no art is orphaned
for id in pairs(ITEM_DB) do assert(SPRITES[id], "item has no sprite: " .. id) end
for id in pairs(SPRITE_ART) do assert(ITEM_DB[id], "sprite for unknown item: " .. id) end
print("1. every ITEM_DB entry has a sprite, none orphaned")

-- 2. round trip: unpack the packed bytes back to ASCII, must equal the art
local function unpack_rows(data)
    local rows = {}
    for y = 0, 15 do
        local line = {}
        for x = 0, 15 do
            local byte = data:byte(y * 2 + (x // 8) + 1)
            line[#line + 1] = ((byte >> (x % 8)) & 1) == 1 and "#" or "."
        end
        rows[#rows + 1] = table.concat(line)
    end
    return rows
end
for id, art in pairs(SPRITE_ART) do
    local back = unpack_rows(SPRITES[id])
    for y = 1, 16 do
        assert(back[y] == art[y], ("%s row %d mismatch: %s vs %s"):format(id, y, back[y], art[y]))
    end
    assert(#SPRITES[id] == 32)
end
print("2. all 9 sprites pack to 32 bytes and round-trip exactly (LSB = leftmost pixel)")

-- 3. bit order sanity on a hand-checkable case: leftmost pixel -> bit 0 of byte 0
local probe = {}
for y = 1, 16 do probe[y] = string.rep(".", 16) end
probe[1] = "#..............#"
-- expect byte0 = 0b00000001 = 1, byte1 = 0b10000000 = 128
local function pack_like_game(rows)
    local out = {}
    for _, row in ipairs(rows) do
        for b = 0, 1 do
            local v = 0
            for bit = 0, 7 do
                if row:sub(b * 8 + bit + 1, b * 8 + bit + 1) == "#" then v = v | (1 << bit) end
            end
            out[#out + 1] = string.char(v)
        end
    end
    return table.concat(out)
end
local p = pack_like_game(probe)
assert(p:byte(1) == 1 and p:byte(2) == 128, "bit order wrong")
print("3. bit order confirmed: pixel 0 -> 0x01, pixel 15 -> 0x80 (matches XBM LSB-first)")

-- 4. drawing: sprites land inside their slot boxes with valid args
local game = Game.new()
game.player.q, game.player.r = 0, 0
game.player.equipped.head = "cap"
game.player.equipped.hands = "gloves"
SPRITE_CALLS = {}
game:draw_inventory(400, 300)
print("4. draw_inventory issued " .. #SPRITE_CALLS .. " sprite calls (args validated by stub)")
assert(#SPRITE_CALLS > 0)
for _, c in ipairs(SPRITE_CALLS) do
    assert(c.x >= 0 and c.y >= 0 and c.x + c.w <= 400 and c.y + c.h <= 300,
        ("sprite off screen at %d,%d"):format(c.x, c.y))
end
-- expected: ground 4 + bag 2 + equipped (tshirt,jeans,boots,backpack,cap,gloves)
-- 6 x 5 (each worn icon is drawn 4x in white as a halo, then once in black)
-- (the doll itself is drawn as bitmap tiles: count the 16x16 icons apart)
local icons = 0
for _, c in ipairs(SPRITE_CALLS) do if c.w == 16 and c.h == 16 then icons = icons + 1 end end
assert(icons == 36, "expected 36 icon sprites, got " .. icons)
assert(#SPRITE_CALLS == 36 + #game:doll_tiles(), "the rest are the doll's tiles")
print("   count matches: 4 ground + 2 bag + 6 worn x 5 (halo) = 36 icons, + " .. #game:doll_tiles()
    .. " doll tiles, all on screen")

-- 5. an item with no art must fall back to a letter, not crash
ITEM_DB.mystery = {name = "Mystery", slot = nil, consumable = nil}
table.insert(game.player.inventory, {item = "mystery", qty = 1})
SPRITE_CALLS = {}
game:draw_inventory(400, 300)
print("5. unknown item drew without error (letter fallback), sprites this frame: " .. #SPRITE_CALLS)

-- 6. eyeball the art
print("\n--- sprite previews ---")
local order = {"tshirt","jeans","boots","cap","gloves","canned_beans","water_bottle","rock","cloth_scrap"}
for _, id in ipairs(order) do
    print(id)
    for _, row in ipairs(SPRITE_ART[id]) do print("  " .. row:gsub("#", "█"):gsub("%.", "·")) end
end
print("\nALL SPRITE TESTS PASSED")
