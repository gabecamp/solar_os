-- Lore: torn pages read in order, the reader, the Signal's page, the ending.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KEY = H.KEY

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end
local texts = {}
gfx.text = function(_, y, s) assert(y <= 300, "off screen: " .. s); texts[#texts + 1] = s end

print("1. twelve pages, each fits the reader")
assert(#LORE.pages == 12)
local g = fresh()
g.lore_read = {}
for i = 1, 12 do g.lore_read[i] = true end
for i = 1, 12 do
    g.lore_page = i
    g.screen = "lore"
    g:draw_lore(400, 300)
end

print("2. E on a Torn Page reads the next one and uses it up")
g = fresh()
g.player.inventory = {{item = "lore_page", qty = 2}}
g:use_item("inventory", 1)
assert(g:lore_count() == 1 and g.player.inventory[1].qty == 1)
assert(g.log[#g.log]:find(LORE.pages[1].title, 1, true))
g:use_item("inventory", 1)
assert(g:lore_count() == 2 and #g.player.inventory == 0)

print("3. the journal counts them; L opens the reader; arrows page; any key back")
texts = {}
g:open_journal()
g:draw_journal(400, 300)
assert(table.concat(texts, "\n"):find("Pages read: 2/12", 1, true))
g:help_key(KEY.L)
assert(g.screen == "lore" and g.lore_page == 1)
g:lore_key(gfx.KEY_DOWN)
assert(g.lore_page == 2)
g:lore_key(gfx.KEY_DOWN)
assert(g.lore_page == 2, "stops at the last page read")
g:lore_key(KEY.Q)
assert(g.screen == "journal")

print("4. the Signal reads you a page the first time only")
g = fresh()
g.player.inventory = {{item = "lora_radio", qty = 1}}
g:open_radio()
g:radio_call(4)
assert(g:lore_count() == 1)
g.radio.next.signal, g.radio.charge = nil, 5
g:radio_call(4)
assert(g:lore_count() == 1)

print("5. all read: no more; the ending changes with what you know")
g = fresh()
for _ = 1, 12 do g:read_lore() end
assert(not g:read_lore())
g.player.inventory = {{item = "permit", qty = 1}}
g:finish_run("permit")
assert(g.ending.lore == LORE.ending[1].text)
g = fresh()
for _ = 1, 5 do g:read_lore() end
assert(g:lore_ending_line() == LORE.ending[2].text)
g = fresh()
assert(g:lore_ending_line() == nil)

print("6. saved")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
g:read_lore(); g:read_lore(); g:read_lore()
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2:lore_count() == 3)

print("LORE TESTS PASSED")
