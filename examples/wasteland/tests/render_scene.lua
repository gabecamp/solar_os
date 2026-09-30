package.path = "./render_stub/?.lua;" .. package.path
local solaros = require("solaros")
local Game = dofile("lib_only.lua")

local function fresh()
    local g = Game.new()
    g.player.q, g.player.r = 0, 0
    return g
end

-- Scene 1: inventory, spawn tile with loot, dressed + a full-ish bag, cursor on a ground item
local g = fresh()
g.player.equipped.head = "cap"
g.player.equipped.hands = "gloves"
table.insert(g.player.inventory, {item = "rock", qty = 3})
table.insert(g.player.inventory, {item = "cloth_scrap", qty = 12})
g.inv_cursor = 2
g.inv_selected = {"equip", "shirt"}
g.log = {"Moved Canned Beans.", "Consumed Water Bottle."}
g:draw_inventory(300, 400)
solaros.dump("ops_inventory.txt")

-- Scene 2: barefoot + starving, cursor on an empty equip slot
g = fresh()
g.player.equipped.feet = nil
g.player.needs.hunger = 0
g.inv_cursor = 4 + 5
g.log = {"You are starving!", "Moved Rock.", "Consumed Canned Beans."}
g:draw_inventory(300, 400)
solaros.dump("ops_inventory_barefoot.txt")

-- Scene 2b: worst case - full bag, more ground stacks than fit (grid scrolled
-- to the cursor), a bag cell selected, all four conditions
g = fresh()
g.player.inventory = {}
local ids = {"rock", "cloth_scrap", "canned_beans", "water_bottle", "tshirt", "jeans", "boots", "cap", "gloves"}
for k = 1, 16 do g.player.inventory[k] = {item = ids[(k - 1) % #ids + 1], qty = k} end
local ground = g:ground_list()
for k = #ground + 1, 15 do ground[k] = {item = ids[(k - 1) % #ids + 1], qty = 1} end
g.player.equipped.feet = nil
g.player.needs.hunger, g.player.needs.thirst, g.player.needs.rest = 0, 0, 0
g.inv_cursor = 14
g.inv_selected = {"inventory", 9}
g.log = {"Consumed Water Bottle.", "Backpack full.", "Moved Rock."}
g:draw_inventory(300, 400)
solaros.dump("ops_inventory_full.txt")

-- Scene 2c: every slot worn, cursor on the jacket
g = fresh()
local worn = {head = "cap", ears = "earmuffs", eyes = "sunglasses", neck = "scarf",
              jacket = "jacket", shirt = "tshirt", hands = "gloves", wrists = "bracers",
              pants = "jeans", feet = "boots"}
for slot, item in pairs(worn) do g.player.equipped[slot] = item end
g.inv_cursor = #g:ground_list() + 5
g.log = {"Moved Leather Jacket.", "Moved Scarf."}
g:draw_inventory(300, 400)
solaros.dump("ops_inventory_dressed.txt")

-- Scene 2d: holding a rock and a bottle, satchel on the back, 392px panel
g = fresh()
g.player.equipped.back = "satchel"
g.player.equipped.rhand = "rock"
g.player.equipped.lhand = "water_bottle"
g.inv_cursor = #g:ground_list() + 1 + 11      -- L Hand
g.log = {"Moved Satchel.", "Moved Rock."}
g:draw_inventory(300, 392)
solaros.dump("ops_inventory_hands.txt")

-- Scene 2e: character creator, Perception raised, a trait picked
g = fresh()
local gfx = solaros.gfx
g.creator_cursor = 1; g:creator_key(gfx.KEY_LEFT)    -- Strength 3 -> 2
g.creator_cursor = 3; g:creator_key(gfx.KEY_RIGHT)   -- Perception 3 -> 4
g.creator_cursor = 7; g:creator_key(32)              -- Scrounger
g.creator_cursor = 13; g:creator_key(32)             -- Big Eater
g.creator_cursor = 3
g:draw_creator(300, 400)
solaros.dump("ops_creator.txt")

-- Scene 3: the map screen
g = fresh()
g:draw_map(300, 400)
solaros.dump("ops_map.txt")

-- Scene 4: map after walking a few tiles (remembered tiles + reachable highlight)
g = fresh()
local steps = 0
local dirs = {{1,0},{0,-1},{1,-1},{1,0},{0,1}}
for _, d in ipairs(dirs) do
    if g.player.mp <= 0 then g:rest() end
    g:move_dir(d[1], d[2])
    steps = steps + 1
end
g:draw_map(300, 400)
solaros.dump("ops_map_explored.txt")

-- Scene 4b: just scavenged a forest tile
g = fresh()
g.tiles["0,0"] = "forest"
g.ground["0,0"] = {}
g:scavenge()
g:draw_map(300, 400)
solaros.dump("ops_map_scavenge.txt")

-- Scene 5: whole map revealed, player standing on hills (worst case for the marker)
g = fresh()
g.tiles["0,0"] = "hills"
g.tiles["1,0"] = "forest"
g.tiles["0,1"] = "water"
g.tiles["-1,1"] = "plains"
for key in pairs(g.tiles) do g.player.visible[key] = true; g.player.explored[key] = true end
g.log = {"Moved to Hills (2 MP)", "Rested 4h."}
g:draw_map(300, 400)
solaros.dump("ops_map_full.txt")
print("scenes recorded, player at", g.player.q, g.player.r)
