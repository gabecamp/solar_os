-- The Ferry Post (Mother Okun) and the Peddler's round.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local TRADE, QUESTS, KEY = H.TRADE, H.QUESTS, H.KEY

local function fresh()
    local g = Game.new()
    g:start_game()
    return g
end
local function dist(a, b)
    local aq, ar = a:match("(-?%d+),(-?%d+)")
    local bq, br = b:match("(-?%d+),(-?%d+)")
    aq, ar, bq, br = tonumber(aq), tonumber(ar), tonumber(bq), tonumber(br)
    return math.max(math.abs(aq - bq), math.abs(ar - br), math.abs(aq + ar - bq - br))
end

print("1. old worlds keep every tile and site; the extras only add a few ruins")
local placed = 0
for i = 1, 40 do
    local seed = i * 811 % 32768
    local tiles, _, _, rad, sites = H.generate_world(seed)
    local before, sites_before = {}, {}
    for k, v in pairs(tiles) do before[k] = v end
    for k, v in pairs(sites) do sites_before[k] = v end
    local extras = Game.place_extras(tiles, sites, rad, seed)
    for name, key in pairs(sites_before) do assert(sites[name] == key, "site moved: " .. name) end
    local changed = 0
    for k, v in pairs(tiles) do
        if v ~= before[k] then
            changed = changed + 1
            assert(v == "ruins" and before[k] ~= "water", "only dry land becomes ruins")
        end
    end
    assert(changed <= TRADE.ferry.ruins + 1, changed .. " tiles changed")
    if sites.ferry then
        placed = placed + 1
        assert(dist(sites.ferry, sites.trader) >= TRADE.ferry.min_from_town - 3, "ferry too close to town")
        assert(tiles[sites.ferry] == "ruins")
    end
    assert(#extras.route >= TRADE.route_n - 2, "a round of stops")
    for _, k in ipairs(extras.route) do assert(tiles[k] ~= "water") end
end
assert(placed >= 36, "a ferry post in most worlds: " .. placed)

print("2. the same seed always gives the same extras (old saves load the same)")
local t1, _, _, r1, s1 = H.generate_world(4242)
local e1 = Game.place_extras(t1, s1, r1, 4242)
local t2, _, _, r2, s2 = H.generate_world(4242)
local e2 = Game.place_extras(t2, s2, r2, 4242)
assert(s1.ferry == s2.ferry and table.concat(e1.route, ";") == table.concat(e2.route, ";"))

print("3. the Peddler stays 12 hours at each stop, then moves on, round and round")
local g = fresh()
local route = g.extras.route
g.player.hours = 0
assert(g:peddler_key() == route[1])
assert(g:peddler_key(TRADE.stay - 1) == route[1] and g:peddler_key(TRADE.stay) == route[2])
assert(g:peddler_key(TRADE.stay * #route) == route[1], "a loop")

print("4. Mother Okun and the Peddler keep their own stock and prices")
g = fresh()
local ferry_key = g.sites.ferry
assert(ferry_key, "this world has a ferry post")
local q, r = ferry_key:match("(-?%d+),(-?%d+)")
g.player.q, g.player.r = tonumber(q), tonumber(r)
g:site_action()
assert(g.screen == "trade" and g.trade_ui.who == "ferry")
local rows = g:trade_rows("theirs")
assert(rows == g.ferry_trader.stock and rows ~= g.trader.stock)
local _, cfg = g:trade_partner()
assert(cfg.markup == TRADE.people.ferry.markup and cfg.markup < TRADE.people.town.markup)
g.player.inventory = {{item = "antirad", qty = 3}}
g.trade_ui.get = {rope = 1}
g.trade_ui.give = {antirad = 1}
assert(g:make_deal())
assert(g:count_item("rope") == 1)
local town_has_rope = false
for _, s in ipairs(g.trader.stock) do if s.item == "antirad" and s.qty > 3 then town_has_rope = true end end
assert(not town_has_rope, "the town's stock didn't change")

print("5. her fish job: O asks, three fish hand it in")
g:trade_key(KEY.O)
assert(g.quest and g.quest.kind == "fish")
g.player.inventory = {{item = "raw_fish", qty = 2}, {item = "cooked_fish", qty = 2}}
g:trade_key(KEY.O)
assert(g.quest == nil and g:count_item("lucky_lure") == 1)
assert(g:count_item("raw_fish") + g:count_item("cooked_fish") == 1, "three fish taken")

print("6. T where the Peddler stands trades with him; he shows on the map and in the journal")
g = fresh()
g.player.hours = 0
local pk = g:peddler_key()
q, r = pk:match("(-?%d+),(-?%d+)")
g.player.q, g.player.r = tonumber(q), tonumber(r)
g:refresh_view()
g:spot_sites()
assert(g.peddler.seen_key == pk)
g:site_action()
assert(g.screen == "trade" and g.trade_ui.who == "peddler")
local found = false
for _, l in ipairs(g:journal_lines()) do if l:find("^Peddler: last seen") then found = true end end
assert(found)
g.screen = "map"
g.player.q, g.player.r = 0, 0
g.player.visible[pk] = true
SPRITE_CALLS = {}
g:draw_map(400, 300)

print("7. a save from before the ferry loads with Mother Okun's stock")
g = fresh()
assert(g:save())
local data = Game.read_save()
data.ferry_trader, data.peddler = nil, nil
local g2 = Game.new()
g2:load_state(data)
assert(g2.ferry_trader and #g2.ferry_trader.stock > 0 and g2.peddler and g2.extras.route)
assert(g2.sites.ferry == g.sites.ferry)

print("TOWNS TESTS PASSED")
