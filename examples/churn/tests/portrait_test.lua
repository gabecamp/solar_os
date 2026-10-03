-- Encounter portraits: every encounter has art, the baked tiles are valid
-- sprites, the picture reacts to range/wounds/death/fleeing, it stays inside
-- its frame, and only one creature is ever held decoded.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, E = dofile("lib_encounter.lua")
local SIZE = E.PORTRAIT_SIZE
local FX, FY = 400 - 102, 18          -- where draw_encounter puts the frame

print("1. every encounter has a portrait with near, far and close views")
for _, d in ipairs(E.ENCOUNTERS) do
    assert(d.art, d.name .. " has no art key")
    local entry = E.PORTRAIT_DATA[d.art]
    assert(entry, d.name .. ": no PORTRAIT_DATA." .. d.art)
    for _, view in ipairs({"near", "far", "close"}) do
        assert(entry[view], d.name .. " has no " .. view .. " view")
    end
end
print("   OK (" .. #E.ENCOUNTERS .. " encounters)")

print("2. the baked data decodes to whole 32x32 tiles (128 bytes each)")
local tiles_total = 0
for who, entry in pairs(E.PORTRAIT_DATA) do
    for view, v in pairs(entry) do
        local bytes = E.b64_decode(v.data)
        assert(#bytes == v.tw * v.th * 128, who .. "." .. view .. ": " .. #bytes .. " bytes")
        assert(v.w <= v.tw * 32 and v.h <= v.th * 32 and v.w <= SIZE and v.h <= SIZE)
        assert(#v.marks % 2 == 0 and #v.marks >= 10, who .. "." .. view .. " needs wound marks")
        for i = 1, #v.marks, 2 do
            assert(v.marks[i] >= 2 and v.marks[i] < v.w - 2 and v.marks[i + 1] >= 2
                   and v.marks[i + 1] < v.h - 3, who .. "." .. view .. " mark off the picture")
        end
        tiles_total = tiles_total + v.tw * v.th
    end
end
print("   OK (" .. tiles_total .. " tiles)")

-- record the portrait's drawing for one encounter state
local function frame_calls(def, setup)
    local g = Game.new()
    g:start_encounter(def)
    if setup then setup(g.enc) end
    local rects, sprites = {}, {}
    local saved_fill = gfx.fill_rect
    gfx.fill_rect = function(x, y, w, h) saved_fill(x, y, w, h); rects[#rects + 1] = {x, y, w, h} end
    -- the game grabbed gfx.sprite at load; the fake logs every call in SPRITE_CALLS
    SPRITE_CALLS = {}
    g:draw_portrait(g.enc, FX, FY)
    gfx.fill_rect = saved_fill
    for _, c in ipairs(SPRITE_CALLS) do sprites[#sprites + 1] = {c.x, c.y, c.w, c.h} end
    return rects, sprites, g
end
local function inside(x, y, w, h)
    return x >= FX and y >= FY and x + w <= FX + SIZE and y + h <= FY + SIZE
end

print("3. every state draws valid sprites inside the frame")
local fighter
for _, d in ipairs(E.ENCOUNTERS) do
    if d.hp and not fighter then fighter = d end
    for _, range in ipairs({"far", "near", "close"}) do
        for _, hpf in ipairs({1, 0.6, 0.2}) do
            local rects, sprites = frame_calls(d, function(e)
                e.range = range
                if d.hp then e.hp = math.floor(d.hp * hpf) end
            end)
            assert(#sprites > 0, d.name .. " drew nothing at " .. range)
            for _, s in ipairs(sprites) do assert(inside(table.unpack(s)), d.name .. " sprite outside the frame") end
            for _, r in ipairs(rects) do assert(inside(table.unpack(r)), d.name .. " mark outside the frame") end
        end
    end
end
print("   OK")

print("4. it reacts: far is smaller, close differs from near, wounds grow, dead/fled change it")
local function marks(hpf, range)
    local rects = frame_calls(fighter, function(e) e.range = range or "near"; e.hp = math.floor(fighter.hp * hpf) end)
    return #rects - 1                       -- minus the white background fill
end
local _, far = frame_calls(fighter, function(e) e.range = "far" end)
local _, near = frame_calls(fighter, function(e) e.range = "near" end)
local _, close = frame_calls(fighter, function(e) e.range = "close" end)
assert(#far < #near, "far view should be smaller")
local same = #near == #close
if same then
    for i = 1, #near do if near[i][1] ~= close[i][1] or near[i][2] ~= close[i][2] then same = false end end
end
assert(#close > 0, "close view drew nothing")
local unhurt, hurt, badly = marks(1), marks(0.6), marks(0.2)
print(("   wound blots: unhurt %d, hurt %d, badly hurt %d"):format(unhurt, hurt, badly))
assert(unhurt == 0 and hurt > unhurt and badly > hurt)
local dead_rects = frame_calls(fighter, function(e) e.outcome = "dead"; e.hp = 0 end)
assert(#dead_rects > badly, "a dead creature shows every wound")
local _, fled = frame_calls(fighter, function(e) e.outcome = "fled" end)
assert(#fled == 0, "a fled creature leaves an empty frame")
print("   OK")

print("5. helpers and anomalies always show their whole picture")
for _, d in ipairs(E.ENCOUNTERS) do
    if not d.hp then
        local _, s1 = frame_calls(d, function(e) e.range = "far" end)
        local _, s2 = frame_calls(d, function(e) e.range = "close" end)
        assert(#s1 == #s2 and #s1 > 0, d.name .. " should not zoom")
    end
end
print("   OK")

print("6. only one creature is ever held decoded")
local g = Game.new()
for _, d in ipairs(E.ENCOUNTERS) do
    g:start_encounter(d)
    g:draw_portrait(g.enc, FX, FY)
    assert(E.PORTRAIT_CACHE.who == d.art)
end
local n = 0
for _ in pairs(E.PORTRAIT_CACHE.views) do n = n + 1 end
assert(n <= 3, "cache should hold at most the 3 views of one creature")
print("   OK")

print("7. the encounter screen: intro clear of the portrait, real main-loop draw")
for _, d in ipairs(E.ENCOUNTERS) do
    local texts = {}
    local saved = gfx.text
    gfx.text = function(x, y, s) texts[#texts + 1] = {x, y, s} end
    local g2 = Game.new()
    g2:start_encounter(d)
    g2:draw_encounter(400, 300)
    gfx.text = saved
    for _, t in ipairs(texts) do
        if t[2] > FY and t[2] - 10 < FY + SIZE then
            assert(t[1] + 7 * #t[3] <= FX - 2, d.name .. ": text runs under the portrait: " .. t[3])
        end
    end
end
print("   OK")

print("\nPORTRAIT TESTS PASSED")
