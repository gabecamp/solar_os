-- The intro (src/68_intro.lua): the splash on every launch, the title menu
-- (Continue only with a save), the story crawl, then the creator; Q quits
-- from the splash; the idle eye redraws only itself.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game = dofile("lib_only.lua")
local KEY = {ENTER = 10, ESC = 27, Q = 113, DOWN = 0x81, UP = 0x80, SPACE = 32}

print("1. a new launch: intro, title (New survivor only), crawl pages, creator")
local g = Game.new()
g:begin_intro(nil)
assert(g.screen == "intro")
g:intro_key(KEY.SPACE)
assert(g.screen == "title" and #g:title_rows() == 1 and g:title_rows()[1][2] == "new")
g:title_key(KEY.ENTER)
assert(g.screen == "crawl" and g.crawl_page == 1)
for _ = 1, #Game.INTRO.crawl - 1 do g:crawl_key(KEY.ENTER); assert(g.screen == "crawl") end
g:crawl_key(KEY.ENTER)
assert(g.screen == "creator", "the last page leads to the creator")
g = Game.new(); g:begin_intro(nil); g:intro_key(KEY.ENTER); g:title_key(KEY.ENTER)
g:crawl_key(KEY.ESC)
assert(g.screen == "creator", "Esc skips the story")
print("   OK")

print("2. with a save: Continue first, New survivor below; Q on the splash quits")
local saved = Game.new()
saved:start_game()
g = Game.new()
g:begin_intro({player = {hours = 30, health = 77}})
g:intro_key(KEY.ENTER)
local rows = g:title_rows()
assert(#rows == 2 and rows[1][1]:find("Continue") and rows[1][1]:find("77 HP"))
g:title_key(KEY.DOWN); g:title_key(KEY.DOWN)
assert(g.title_cursor == 2, "the cursor stops at the last row")
g:title_key(KEY.UP)
assert(g.title_cursor == 1)
g = Game.new(); g:begin_intro(nil)
g:intro_key(KEY.Q)
assert(g.quit, "Q quits from the splash")
print("   OK")

print("3. the screens fit; an idle tick redraws only the blinking prompt")
local texts = {}
local real_text = gfx.text
gfx.text = function(x, y, s)
    texts[#texts + 1] = s
    assert(x >= 0 and x + 7 * #s <= 400 and y <= 300, "off screen: " .. s)
end
g = Game.new(); g:begin_intro(nil)
SPRITE_CALLS = {}
g:draw_intro(400, 300)
g.screen = "title"; g:draw_title(400, 300)
for p = 1, #Game.INTRO.crawl do g.crawl_page = p; g:draw_crawl(400, 300) end
gfx.text = real_text
local calls = 0
local count = function() calls = calls + 1 end
local saved_fns = {gfx.line, gfx.fill_rect, gfx.text, gfx.circle, gfx.fill_circle, gfx.pixel, gfx.clear}
gfx.line, gfx.fill_rect, gfx.text, gfx.circle, gfx.fill_circle, gfx.pixel, gfx.clear =
    count, count, count, count, count, count, count
g:intro_tick(400, 300)
local tick_calls = calls
calls = 0
g:draw_intro(400, 300)
gfx.line, gfx.fill_rect, gfx.text, gfx.circle, gfx.fill_circle, gfx.pixel, gfx.clear = table.unpack(saved_fns)
assert(tick_calls < calls and tick_calls < 10, ("tick %d calls, full %d"):format(tick_calls, calls))
print(("   OK (idle tick %d draw calls, full splash %d + the picture)"):format(tick_calls, calls))

print("4. the pictures: whole 32x32 tiles, the splash's on the start screen, the title's on the menu")
local drawn = {}
for _, pair in ipairs({{"draw_intro", "SPLASH_ART"}, {"draw_title", "TITLE_ART"}}) do
    local screen, name = pair[1], pair[2]
    local A = Game[name]
    assert(A and A.w == A.tw * 32 and A.h == A.th * 32, name .. ": whole tiles")
    local tiles = Game.art_tiles(name)
    assert(#tiles > A.tw * A.th // 2, name .. ": most tiles have ink")
    SPRITE_CALLS = {}
    g[screen](g, 400, 300)
    assert(#SPRITE_CALLS == #tiles, screen .. " draws " .. name)
    for i, c in ipairs(SPRITE_CALLS) do
        assert(c.data == tiles[i].data, screen .. ": its own picture")
        assert(c.x >= 0 and c.y >= 0 and c.x + c.w <= Game.INTRO.panel and c.y + c.h <= 300, screen .. ": off its frame")
    end
    drawn[#drawn + 1] = SPRITE_CALLS[1].data
end
assert(Game.SPLASH_ART.data ~= Game.TITLE_ART.data, "two different pictures")
print("   OK")

print("\nINTRO TESTS PASSED")
