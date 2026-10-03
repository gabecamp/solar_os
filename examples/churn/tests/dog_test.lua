-- The dog companion: meeting and taming, warnings, biting, guarding,
-- eating, leaving, dying, saving.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
fake.gfx.begin()
local Game, H = dofile("lib_hunt.lua")
local KEY = H.KEY

local function parse(k)
    local q, r = k:match("(-?%d+),(-?%d+)")
    return tonumber(q), tonumber(r)
end
local function fresh()
    local g = Game.new()
    g:start_game()
    g.ticked_hour = g.player.hours
    g.karl_next = 1e9
    return g
end
local function on(g, terrain)
    for k, t in pairs(g.tiles) do
        if t == terrain then g.player.q, g.player.r = parse(k); return end
    end
end
local function has_log(g, pat)
    for _, line in ipairs(g.log) do if line:find(pat) then return true end end
    return false
end
local function with_roll(g, always, f)   -- force every roll to pass (or fail)
    local real = g.roll
    g.roll = function() return always end
    f()
    g.roll = real
end
local function tamed()
    local g = fresh()
    g.dog = {hp = 30, fed_hour = g.player.hours, hungry_days = 0}
    return g
end

print("1. strays only on plains/forest, only while you have no dog, ~2% a move")
local g = fresh()
on(g, "hills")
for _ = 1, 400 do assert(not g:maybe_dog()) end
on(g, "plains")
local met = 0
for _ = 1, 5000 do
    if g:maybe_dog() then met = met + 1; g.enc, g.screen = nil, "map" end
end
print(("   met %d strays in 5000 plains moves"):format(met))
assert(met > 50 and met < 160)
g.dog = {hp = 30, fed_hour = 0, hungry_days = 0}
for _ = 1, 400 do assert(not g:maybe_dog(), "a second dog") end

print("2. taming: needs food; it eats it either way")
g = fresh()
on(g, "forest")
g.player.inventory = {}
with_roll(g, true, function() g:maybe_dog() end)
assert(g.screen == "encounter" and g.enc.def.kind == "dog")
local opts = g:encounter_options()
assert(#opts == 1 and opts[1][2] == "leave_quietly", "no food, no offer")
g.player.inventory = {{item = "strange_meat", qty = 1}}
assert(g:encounter_options()[1][2] == "tame")
with_roll(g, true, function() g:encounter_action("tame") end)
assert(g.dog and #g.player.inventory == 0 and g.enc.over)
g = fresh()
g.player.inventory = {{item = "canned_beans", qty = 2}}
with_roll(g, true, function() g:maybe_dog() end)
with_roll(g, false, function() g:encounter_action("tame") end)
assert(not g.dog and g.player.inventory[1].qty == 1, "ran off with it")

print("3. with a dog: better hiding and running")
g = tamed()
assert(g:dog_bonus() == 15)
g.dog = nil
assert(g:dog_bonus() == 0)

print("4. in a fight it bites, and can take a blow (and die of it)")
g = tamed()
g:start_encounter({kind = "animal", name = "Test", who = "test beast", hp = 50, dmg = {10, 10},
                   hit = 100, speed = 3, start = "close", intro = "A test beast."})
local hp = g.enc.hp
with_roll(g, true, function() g:dog_turn() end)
assert(g.enc.hp < hp, "bit it")
g.dog.hp = 5
local php = g.player.health
with_roll(g, true, function() g:enemy_turn() end)
assert(g.dog == nil and g.player.health == php, "the dog took the blow and died")
assert(has_log(g, "died protecting you"))

print("5. it eats once a day, and leaves after 3 hungry days")
g = tamed()
g.player.inventory = {{item = "rotten_meat", qty = 1}, {item = "canned_beans", qty = 1}}
for _ = 1, 25 do   -- the hour that starts 24h after the last meal has to pass
    g.player.needs.thirst, g.player.needs.hunger = 100, 100
    g.player.hours = g.player.hours + 1
    g:tick()
end
assert(#g.player.inventory == 1 and g.player.inventory[1].item == "canned_beans", "ate the rotten meat first")
g.player.inventory = {}
for _ = 1, 24 * 3 do
    g.player.needs.thirst, g.player.needs.hunger, g.player.health = 100, 100, 100
    g.player.hours = g.player.hours + 1
    g:tick()
end
assert(g.dog == nil and has_log(g, "Too long without food"))

print("6. shown on the map; saved")
g = tamed()
SPRITE_CALLS = {}
local rects = 0
local real_fill = fake.gfx.fill_rect
fake.gfx.fill_rect = function(...) rects = rects + 1; return real_fill(...) end
g:draw_map(400, 300)
local with_dog = rects
g.dog, rects = nil, 0
g:draw_map(400, 300)
fake.gfx.fill_rect = real_fill
assert(with_dog > rects, "dog marker drawn")
FAKE_FILES, FAKE_DIRS = {}, {}
g = tamed()
g.dog.hp = 17
g.player.hours = g.player.hours + 1
assert(g:save())
local g2 = Game.new()
g2:load_state(Game.read_save())
assert(g2.dog and g2.dog.hp == 17)

print("DOG TESTS PASSED")
