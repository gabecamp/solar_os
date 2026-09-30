-- Traders and the way out: where the sites are, finding them, barter,
-- restocking, the Checkpoint (permit or bribe), the ending, and saving.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()

local Game, T = dofile("lib_trade.lua")
local KEY = T.KEY

local function key(q, r) return q .. "," .. r end
local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function dist(q, r) return (math.abs(q) + math.abs(r) + math.abs(q + r)) // 2 end
local function reachable(tiles)
    local seen, queue, i = {["0,0"] = true}, {{0, 0}}, 1
    while queue[i] do
        local c = queue[i]; i = i + 1
        for _, d in ipairs(T.AXIAL_DIRS) do
            local k = key(c[1] + d[1], c[2] + d[2])
            if tiles[k] and not seen[k] and T.TERRAIN[tiles[k]].passable then
                seen[k] = true; queue[#queue + 1] = {c[1] + d[1], c[2] + d[2]}
            end
        end
    end
    return seen
end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end
local function count(g, item)
    local n = 0
    for _, s in ipairs(g.player.inventory) do if s.item == item then n = n + s.qty end end
    return n
end
local function fresh()
    local g = Game.new()
    g:start_game()
    g.ticked_hour = g.player.hours
    return g
end
local function stand_on(g, site)
    g.player.q, g.player.r = parse(g.sites[site])
end

print("1. 40 worlds: trader in the town's ruins, Checkpoint on the edge, both reachable and clean")
for seed = 1, 40 do
    local s = seed * 613 % 32768
    local tiles, _, _, rad, sites = T.generate_world(s)
    assert(tiles[sites.trader] == "ruins", "trader on " .. tostring(tiles[sites.trader]))
    local cq, cr = parse(sites.checkpoint)
    assert(dist(cq, cr) == T.GRID_RADIUS, "checkpoint not on the edge")
    assert(T.TERRAIN[tiles[sites.checkpoint]].passable)
    local seen = reachable(tiles)
    assert(seen[sites.trader] and seen[sites.checkpoint], "seed " .. s .. ": a site is cut off")
    for name, k in pairs(sites) do
        local q, r = parse(k)
        for hk in pairs(rad) do
            local hq, hr = parse(hk)
            assert(dist(hq - q, hr - r) >= 2, "seed " .. s .. ": " .. name .. " is next to a field")
        end
    end
end

print("2. compass bearings")
local g = fresh()
g.player.q, g.player.r = 0, 0
for _, c in ipairs({{"0,0", "here"}, {"5,0", "E 5"}, {"-5,0", "W 5"}, {"0,4", "SE 4"},
                    {"0,-4", "NW 4"}, {"4,-8", "N 8"}, {"-4,8", "S 8"}}) do
    g.sites.checkpoint = c[1]
    assert(g:site_bearing("checkpoint") == c[2], c[1] .. " -> " .. g:site_bearing("checkpoint"))
end

print("3. walking onto the trader: safe, announced, and you hear of the Checkpoint")
g = fresh()
local tq, tr = parse(g.sites.trader)
local from
for _, d in ipairs(T.AXIAL_DIRS) do
    local k = key(tq + d[1], tr + d[2])
    if g.tiles[k] and T.TERRAIN[g.tiles[k]].passable then from = {tq + d[1], tr + d[2]} break end
end
for i = 1, 30 do   -- encounters never start on a site
    g.player.q, g.player.r = from[1], from[2]
    g.player.mp, g.enc_cooldown = 5, 0
    g:try_move(tq, tr)
    assert(g.screen == "map", "encounter on the trader's hex")
    if i == 1 then
        assert(g.sites_known.trader and g.sites_known.checkpoint)
        assert(has_log(g, "T to trade") and has_log(g, "checkpoint out of the Zone"))
    end
end
assert(g:goal_text():match("^Exit %u+ %d+$"), g:goal_text())

print("4. barter: must take something, must offer enough, then goods change hands")
g = fresh()
stand_on(g, "trader")
g.player.inventory = {{item = "weeping_stone", qty = 1}, {item = "rock", qty = 1}}
g:site_action()
assert(g.screen == "trade")
g:trade_key(KEY.T)
assert(g.trade_ui.msg:find("Pick something"))
g:trade_key(gfx.KEY_RIGHT)                        -- trader's first row: Anti-Rad
assert(g.trader.stock[1].item == "antirad")
g:trade_key(KEY.ENTER); g:trade_key(KEY.ENTER); g:trade_key(KEY.ENTER)   -- take 3
g:trade_key(KEY.E); g:trade_key(KEY.E)            -- no, just 1
local _, ask = g:trade_totals()
assert(ask == math.ceil(T.TRADE.value.antirad * T.TRADE.markup), "ask " .. ask)
g:trade_key(gfx.KEY_LEFT)
g:trade_key(gfx.KEY_DOWN)                         -- the rock: worth nothing much
g:trade_key(KEY.ENTER)
g:trade_key(KEY.T)
assert(g.trade_ui.msg:find("Not enough"), g.trade_ui.msg)
g:trade_key(KEY.E)                                -- keep the rock
g:trade_key(gfx.KEY_UP)
g:trade_key(KEY.ENTER)                            -- the stone instead
g:trade_key(KEY.ENTER)                            -- only one to give
assert(g.trade_ui.give.weeping_stone == 1)
g:trade_key(KEY.T)
assert(g.trade_ui.msg == "Deal.", g.trade_ui.msg)
assert(count(g, "antirad") == 1 and count(g, "weeping_stone") == 0 and count(g, "rock") == 1)
assert(g.trader.stock[1].qty == 2)
local has_stone = false
for _, s in ipairs(g.trader.stock) do has_stone = has_stone or s.item == "weeping_stone" end
assert(has_stone, "the trader keeps what you sold")
g:trade_key(KEY.Q)
assert(g.screen == "map")

print("5. a full bag: bought goods land on the ground")
g = fresh()
stand_on(g, "trader")
-- every bag cell holds something; paying with part of a stack frees none
local ids = {"weeping_stone", "stick", "rope", "torch", "knife", "pipe", "spear", "cap", "gloves",
             "scarf", "bracers", "earmuffs", "sunglasses", "rock", "flesh_knot", "quiet_shell"}
g.player.inventory = {}
for i = 1, g:bag_capacity() do g.player.inventory[i] = {item = ids[i], qty = 1} end
g.player.inventory[1].qty = 3
g:open_trade()
g.trade_ui.get = {geiger = 1}
g.trade_ui.give = {weeping_stone = 2}
assert(g:make_deal(), g.trade_ui.msg)
local on_ground = false
for _, s in ipairs(g:ground_list()) do on_ground = on_ground or s.item == "geiger" end
assert(on_ground and count(g, "geiger") == 0 and g.trade_ui.msg:find("ground"))

print("6. the trader restocks every " .. T.TRADE.restock_hours .. "h")
g = fresh()
stand_on(g, "trader")
local function units(stock) local n = 0; for _, s in ipairs(stock) do n = n + s.qty end; return n end
local before = units(g.trader.stock)
g.player.hours = T.TRADE.restock_hours * 2 + 5
g:open_trade()
assert(units(g.trader.stock) == before + 2 * T.TRADE.restock_n)
g:open_trade()
assert(units(g.trader.stock) == before + 2 * T.TRADE.restock_n, "not twice")

print("7. the Checkpoint: turned back empty-handed")
g = fresh()
stand_on(g, "checkpoint")
g:site_action()
assert(g.screen == "gate" and #g.gate_ui.opts == 1)
g:draw_gate(400, 300)
g:gate_key(KEY.ENTER)
assert(g.screen == "map" and has_log(g, "step back"))

print("8. ...through with a permit: the ending, and the save is gone")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
assert(g:save())
stand_on(g, "checkpoint")
g.player.inventory = {{item = "permit", qty = 1}}
g:open_gate()
assert(g.gate_ui.opts[1][2] == "permit")
g:gate_key(KEY.ENTER)
assert(g.screen == "ending" and g.ending.how == "permit")
assert(next(FAKE_FILES) == nil, "save deleted")
g:draw_ending(400, 300)

print("9. ...or for " .. T.GOAL.bribe .. " artifacts (from the bag and hands)")
g = fresh()
stand_on(g, "checkpoint")
g.player.inventory = {{item = "weeping_stone", qty = 2}, {item = "water_bottle", qty = 1}}
g.player.equipped.rhand = "quiet_shell"
g:open_gate()
assert(g.gate_ui.opts[1][2] == "bribe")
g:gate_key(KEY.ENTER)
assert(g.screen == "ending" and g.ending.how == "bribe" and g:artifact_count() == 0)
assert(count(g, "water_bottle") == 1 and g.player.equipped.rhand == nil)

print("10. notes and the wanderer point the way")
g = fresh()
for _, r in ipairs({"rope", "spear", "club"}) do g.known[r] = true end
g.player.inventory = {{item = "scrawled_notes", qty = 1}}
g:use_item("inventory", 1)
assert(g.sites_known.checkpoint and count(g, "scrawled_notes") == 0)
g = fresh()
g.enc = {def = {help = "wanderer"}, msg = {}}
g:helper_talk()
assert(g.sites_known.checkpoint)
g.enc = {def = {help = "wanderer"}, msg = {}}
g:helper_talk()
assert(g.sites_known.trader and has_log(g, "trader in the town"))

print("11. the map shows known sites; the trade screen draws")
g = fresh()
g:learn_site("trader")
stand_on(g, "trader")
local tq2, tr2 = g.player.q, g.player.r
g.player.q, g.player.r = tq2 + 1, tr2   -- look at it from next door
g:refresh_view()
SPRITE_CALLS = {}
g:draw_map(400, 300)
assert(#SPRITE_CALLS > 0)
g.player.q, g.player.r = tq2, tr2
g:open_trade()
g:draw_trade(400, 300)
assert(T.SPRITES.permit)

print("12. saved: the trader's stock and what you know; sites come back from the seed")
FAKE_FILES, FAKE_DIRS = {}, {}
g = fresh()
g:learn_site("trader")
g.trader.stock[1].qty = 0
table.remove(g.trader.stock, 1)
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.sites.trader == g.sites.trader and g2.sites.checkpoint == g.sites.checkpoint)
assert(g2.sites_known.trader and #g2.trader.stock == #g.trader.stock)

print("13. T is on the map")
local src = io.open("wasteland_run.lua"):read("a")
assert(src:find("game:site_action()", 1, true))
g = fresh()
g.player.q, g.player.r = 0, 0
g:site_action()
assert(has_log(g, "Nobody here"))

print("TRADE TESTS PASSED")
