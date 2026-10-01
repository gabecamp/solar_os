-- Difficulty: picked with 1/2/3 on the creator; scales food, encounters,
-- radiation, emissions and hunger/thirst drain; saved.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local D = H.DIFFICULTY

print("1. 1/2/3 on the creator pick the level; Normal is the default and all 1.0")
local g = Game.new()
assert(g:diff("food") == 1 and g:diff("encounter") == 1)
for k, v in pairs(D.normal) do if k ~= "name" and k ~= "short" then assert(v == 1, k) end end
g:creator_key(49)
assert(g.difficulty == "easy")
g:creator_key(51)
assert(g.difficulty == "hard" and g:diff("rad") == D.hard.rad)
g:creator_key(50)
assert(g.difficulty == "normal")

print("2. drain: hunger and thirst fall faster on hard")
local easy, hard = Game.new(), Game.new()
easy:set_difficulty("easy"); hard:set_difficulty("hard")
assert(easy.player.hunger_mult < 1 and hard.player.hunger_mult > 1)
assert(math.abs(hard.player.thirst_mult - D.hard.drain) < 1e-9)
hard.player.traits["Light Eater"] = true
hard:set_difficulty("hard")
assert(math.abs(hard.player.hunger_mult - 0.75 * D.hard.drain) < 1e-9, "stacks with traits")

print("3. radiation dose and emission harm scale")
local function dose(level)
    local gg = Game.new()
    gg:set_difficulty(level)
    gg:start_game()
    for k, l in pairs(gg.rad) do
        if l == 3 then gg.player.q, gg.player.r = k:match("(-?%d+),(-?%d+)"); break end
    end
    gg.player.q, gg.player.r = tonumber(gg.player.q), tonumber(gg.player.r)
    return gg:rad_hour()
end
assert(dose("easy") < dose("normal") and dose("normal") < dose("hard"))

print("4. encounters: rarer on easy, commoner on hard (measured)")
local function rate(level)
    local gg = Game.new()
    gg:set_difficulty(level)
    gg:start_game()
    gg.karl_next = 1e9
    local n = 0
    for _ = 1, 3000 do
        gg.enc_cooldown, gg.enc, gg.screen = 0, nil, "map"
        gg:maybe_encounter("forest")
        if gg.screen == "encounter" then n = n + 1 end
    end
    return n
end
local e, nm, hd = rate("easy"), rate("normal"), rate("hard")
print(("   forest encounters per 3000 moves: easy %d, normal %d, hard %d"):format(e, nm, hd))
assert(e < nm and nm < hd)

print("5. food: more of it in search tables on easy")
local function food_share(level)
    local gg = Game.new()
    gg:set_difficulty(level)
    gg:start_game()
    local n, food = 4000, 0
    for k in pairs(gg.ground) do gg.ground[k] = {} end
    for _ = 1, n do
        gg.player.mp, gg.scavenged = 5, {}
        local key = gg.player.q .. "," .. gg.player.r
        gg.ground[key] = {}
        gg:scavenge()
        for _, s in ipairs(gg.ground[key]) do
            local c = H.ITEM_DB[s.item].consumable
            if c and c.hunger and c.hunger > 0 then food = food + s.qty end
        end
    end
    return food
end
assert(food_share("easy") > food_share("hard"))

print("6. saved, and shown on the creator")
FAKE_FILES, FAKE_DIRS = {}, {}
g = Game.new()
g:set_difficulty("hard")
g:start_game()
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.difficulty == "hard" and g2:diff("drain") == D.hard.drain)
assert(math.abs(g2.player.hunger_mult - D.hard.drain) < 1e-9, "drain survives the reload")
local texts = {}
fake.gfx.text = function(_, _, s) texts[#texts + 1] = s end
g = Game.new()
g:draw_creator(400, 300)
assert(table.concat(texts, "\n"):find("Difficulty 1-3: Normal", 1, true))

print("DIFFICULTY TESTS PASSED")
