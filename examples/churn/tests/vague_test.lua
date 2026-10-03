-- Without a Geiger counter, no item gives radiation away: names and
-- descriptions are vague on every screen and in the log.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local ITEM_DB = H.ITEM_DB

local function leaks(text)
    local t = text:lower()
    return t:find("%f[%a]rads?%f[%A]") or t:find("radiation") or t:find("anti%-rad")
end
local texts = {}
gfx.text = function(_, _, s) texts[#texts + 1] = s end
local function screen_text(g, draw)
    texts = {}
    g[draw](g, 400, 300)
    return table.concat(texts, "\n")
end

local g = Game.new()
g:start_game()
g.player.inventory = {{item = "antirad", qty = 1}, {item = "vodka", qty = 1}, {item = "gasmask", qty = 1}}
g:refresh_view()

print("1. without a counter: vague names and descriptions everywhere")
assert(ITEM_DB.antirad.name == "Iodine Pills" and ITEM_DB.antirad.desc == "E: for sickness")
assert(not leaks(ITEM_DB.vodka.desc) and not leaks(ITEM_DB.gasmask.desc))
for i = 1, 3 do
    g.inv_cursor = 0
    local s = screen_text(g, "draw_inventory")
    for row = 1, 40 do
        g.inv_cursor = row
        s = s .. screen_text(g, "draw_inventory")
    end
    assert(not leaks(s), "inventory gives it away")
end
g.trader.stock[#g.trader.stock + 1] = {item = "antirad", qty = 2}
local tq, tr = g.sites.trader:match("(-?%d+),(-?%d+)")
g.player.q, g.player.r = tonumber(tq), tonumber(tr)
g:open_trade()
assert(not leaks(screen_text(g, "draw_trade")), "trade screen gives it away")
g.screen = "map"
g:use_item("inventory", 1)
for _, line in ipairs(g.log) do assert(not leaks(line), "log: " .. line) end

print("2. with a Geiger counter: the real names come back")
g.player.inventory[#g.player.inventory + 1] = {item = "geiger", qty = 1}
g:refresh_view()
assert(ITEM_DB.antirad.name == "Anti-Rad" and ITEM_DB.gasmask.desc:find("radiation", 1, true))
g.player.inventory[#g.player.inventory] = nil
g:refresh_view()
assert(ITEM_DB.antirad.name == "Iodine Pills", "and go vague again if you drop it")

print("VAGUE TESTS PASSED")
