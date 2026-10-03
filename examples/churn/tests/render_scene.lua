package.path = "./render_stub/?.lua;" .. package.path
local solaros = require("solaros")
local Game = dofile("lib_only.lua")

local function fresh()
    local g = Game.new()
    g.player.q, g.player.r = 0, 0
    return g
end

-- Scene 0: a new game - nothing worn, nothing carried, the pile at your feet
local g = fresh()
g.inv_cursor = 2
g.log = {"You wake with nothing. Not even shoes."}
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_start.txt")

-- Scene 0b: dressed in rags (all crafted), cursor on the rag shirt
g = fresh()
local rags = {head = "rag_hood", ears = "ear_wraps", eyes = "slit_goggles", neck = "rag_scarf",
              jacket = "patch_coat", shirt = "rag_shirt", hands = "hand_wraps", wrists = "scrap_bracers",
              pants = "rag_trousers", feet = "foot_wraps", back = "sack_pack", belt = "rope_belt"}
for slot, item in pairs(rags) do g.player.equipped[slot] = item end
g.inv_cursor = #g:ground_list() + 7
g.log = {"Made Sack Pack.", "Moved Patchwork Coat."}
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_rags.txt")

-- Scene 0c: crafting at the start, cursor on the first makeshift clothes
g = fresh()
g.screen = "craft"
for i, r in ipairs(g:known_recipes()) do if r.id == "rag_shirt" and not g.craft_ui.set then g.craft_ui.cursor, g.craft_ui.set = i, true end end
g:draw_craft(400, 300)
solaros.dump("ops_craft_rags.txt")

-- Scene 0d: worn clothes - a torn rag shirt under the cursor, crafting shows the patch
g = fresh()
g.player.equipped = {shirt = "rag_shirt", pants = "jeans", feet = "foot_wraps", back = "bindle"}
g:wear_out("shirt", 200); g:wear_out("pants", 200); g:wear_out("feet", 35)
g.inv_cursor = 1
g:draw_inventory(400, 300)   -- (lays out the rows)
while not g:cursor_description():find("^Shirt") and g.inv_cursor < 60 do g.inv_cursor = g.inv_cursor + 1 end
g.log = {"Your rag shirt tears. Patch it (C)."}
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_torn.txt")
g.screen = "craft"
for i, r in ipairs(g:known_recipes()) do if r.mend then g.craft_ui.cursor = i end end
g:draw_craft(400, 300)
solaros.dump("ops_craft_patch.txt")

-- Scene 1: inventory, spawn tile with loot, dressed + a full-ish bag, cursor on a ground item
g = dofile("kit.lua")(fresh())   -- the old starting clothes
g.player.equipped.head = "cap"
g.player.equipped.hands = "gloves"
table.insert(g.player.inventory, {item = "rock", qty = 3})
table.insert(g.player.inventory, {item = "cloth_scrap", qty = 12})
g.inv_cursor = 2
g.inv_selected = {"equip", "shirt"}
g.log = {"Moved Canned Beans.", "Consumed Water Bottle."}
g:draw_inventory(400, 300)
solaros.dump("ops_inventory.txt")

-- Scene 2: barefoot + starving, cursor on an empty equip slot
g = fresh()
g.player.equipped.feet = nil
g.player.needs.hunger = 0
g.inv_cursor = 4 + 5
g.log = {"You are starving!", "Moved Rock.", "Consumed Canned Beans."}
g:draw_inventory(400, 300)
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
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_full.txt")

-- Scene 2b2/2b3: the Churn's items with their own icons (tools/paint_icons.py),
-- 31 a screen: the bag and the ground
for n, ids2 in ipairs({
    {"book_tailor", "book_surgeon", "book_radio", "book_lab", "book_gunsmith", "book_hymnal",
     "tape_medic", "tape_gun", "tape_choir", "tape_lab", "tape_tinker", "blank_tape",
     "r762n", "r762t", "r38", "brass", "frame_pm", "frame_tt", "frame_inst", "frame_nagant",
     "gun_slide", "gun_spring", "firing_pin", "magazine", "cylinder", "tokarev", "inst_sidearm",
     "marsh_revolver", "gunsmith_kit", "gun_oil", "lockpicks"},
    {"sinew", "choir_wire", "metal_pot", "lighter", "raw_hide", "jawhound_pelt", "newspaper",
     "duct_tape", "pale_eye", "charcoal", "lead_scrap", "screws", "mech_parts", "foil",
     "laptop_battery", "locked_phone", "pliers", "screwdriver", "hacksaw", "scalpel",
     "kitchen_knife", "hunting_knife", "stone_knife", "glass_shiv", "broad_spear", "bone_needle",
     "smoked_meat", "tincture", "painkillers", "sedative", "rad_purge"},
    {"choir_cell", "glow_jar", "salt_circle", "bark_tea", "stitches", "hide_gloves", "hide_tunic",
     "hide_pack", "pelt_coat", "travois", "hand_cart"},
}) do
    g = fresh()
    g.player.inventory = {}
    local ground = g:ground_list()
    for k = #ground, 1, -1 do ground[k] = nil end
    for k, id in ipairs(ids2) do
        if k <= 16 then g.player.inventory[k] = {item = id, qty = 1}
        else ground[k - 16] = {item = id, qty = 1} end
    end
    g.inv_cursor = 1
    g.log = {"(icons " .. n .. "/3)"}
    g:draw_inventory(400, 300)
    solaros.dump("ops_inventory_icons" .. n .. ".txt")
end

-- Scene: Q on the map asks before quitting
g = fresh()
g.screen = "map"
g:draw_map(400, 300)
g:ask_quit()
g:draw_quit_confirm(400, 300)
solaros.dump("ops_quit_confirm.txt")

-- Scene: finds on the map (a dead churner, a crate) and the Finds page
g = fresh()
g.screen = "map"
g.player.q, g.player.r = 0, 0
g.finds = {["1,0"] = {kind = "corpse", label = "Vesna, from the tape", day = 3,
                      what = "Lockpicks, USB Drive, Radio Ham Handbook"},
           ["-1,1"] = {kind = "crate", label = "An Institute crate", day = 5,
                       what = "Institute Lab Book, 7.62x25 Rounds, Gunsmith Kit"},
           ["0,-1"] = {kind = "corpse", label = "A dead churner", day = 6, what = "Tape: Count Rounds"}}
for k in pairs(g.finds) do g.player.explored[k] = true end
g.tiles["-1,1"] = "water"   -- (the crate mark on the darkest hex)
g:refresh_view()
g:draw_map(400, 300)
solaros.dump("ops_map_finds.txt")
g:open_finds()
g:draw_skills(400, 300)
solaros.dump("ops_finds.txt")

-- Scene 2c: every slot worn, cursor on the jacket
g = fresh()
local worn = {head = "cap", ears = "earmuffs", eyes = "sunglasses", neck = "scarf",
              jacket = "jacket", shirt = "tshirt", hands = "gloves", wrists = "bracers",
              pants = "jeans", feet = "boots"}
for slot, item in pairs(worn) do g.player.equipped[slot] = item end
g.inv_cursor = #g:ground_list() + 5
g.log = {"Moved Leather Jacket.", "Moved Scarf."}
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_dressed.txt")

-- Scene 2d: holding a rock and a bottle, satchel on the back, 392px panel
g = fresh()
g.player.equipped.back = "satchel"
g.player.equipped.rhand = "rock"
g.player.equipped.lhand = "water_bottle"
g.inv_cursor = #g:ground_list() + 1 + 11      -- L Hand
g.log = {"Moved Satchel.", "Moved Rock."}
g:draw_inventory(400, 292)
solaros.dump("ops_inventory_hands.txt")

-- Scene 2e: character creator, Perception raised, a trait picked
g = fresh()
local gfx = solaros.gfx
g.creator_cursor = 1; g:creator_key(gfx.KEY_LEFT)    -- Strength 3 -> 2
g.creator_cursor = 3; g:creator_key(gfx.KEY_RIGHT)   -- Perception 3 -> 4
g.creator_cursor = 7; g:creator_key(32)              -- Scrounger
g.creator_cursor = 13; g:creator_key(32)             -- Big Eater
g.creator_cursor = 3
g:draw_creator(400, 300)
solaros.dump("ops_creator.txt")

-- Scene 3: the map screen
g = fresh()
g:draw_map(400, 300)
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
g:draw_map(400, 300)
solaros.dump("ops_map_explored.txt")

-- Scene 4b: just scavenged a forest tile
g = fresh()
g.tiles["0,0"] = "forest"
g.ground["0,0"] = {}
g:scavenge()
g:draw_map(400, 300)
solaros.dump("ops_map_scavenge.txt")

-- Scene 5: whole map revealed, player standing on hills (worst case for the marker)
g = fresh()
g.tiles["0,0"] = "hills"
g.tiles["1,0"] = "forest"
g.tiles["0,1"] = "water"
g.tiles["-1,1"] = "plains"
for key in pairs(g.tiles) do g.player.visible[key] = true; g.player.explored[key] = true end
g.log = {"Moved to Hills (2 MP)", "Rested 4h."}
g.player.injuries.bleeding = true
g.player.injuries.wounded_hours = 10
g.player.health = 41
g:draw_map(400, 300)
solaros.dump("ops_map_full.txt")

-- Scene 6: death screen
g = fresh()
g.player.hours = 57
g.stats = {kills = 3, searches = 14, artifacts = 1, fish = 2}
g.player.health = 0
g:check_death("You bled out.")
g:draw_dead(400, 300)
solaros.dump("ops_dead.txt")

-- Encounters: roll until the named one comes up (the table is local to the game)
local function start_named(g2, name)
    local i = 0
    repeat
        i = i + 1
        local d = g2:pick_encounter()
        if d.name == name then g2:start_encounter(d); return end
    until i > 5000
    error("never rolled " .. name)
end

-- Scene 7: bandits demanding food
g = fresh(); g:start_game()
start_named(g, "Road Bandits")
g:draw_encounter(400, 300)
solaros.dump("ops_encounter_bandit.txt")

-- Scenes 7b/7c: the user's own pictures - the Fused at Near, the stray dog
g = fresh(); g:start_game()
start_named(g, "The Fused")
g.enc.range = "near"
g:draw_encounter(400, 300)
solaros.dump("ops_encounter_fused.txt")
g = fresh(); g:start_game()
g.tiles[g.player.q .. "," .. g.player.r] = "plains"
for _ = 1, 5000 do if g:maybe_dog() then break end end   -- (the game's own dog encounter)
g:draw_encounter(400, 300)
solaros.dump("ops_encounter_dog.txt")

-- Scene 7d: inside the Institute, the archive, the count read (Vesna found)
g = fresh(); g:start_game()
g.player.inventory = {{item = "institute_pass", qty = 1}}
g:open_institute()
g:encounter_action("deeper_institute"); g:encounter_action("deeper_institute")
g.vesna = "found"
g:encounter_action("read_institute")
g:draw_encounter(400, 300)
solaros.dump("ops_institute_archive.txt")

-- Scene 8: mid-fight at Near with a spear and a rock: the most options at once
g = fresh(); g:start_game()
g.player.equipped.rhand, g.player.equipped.lhand = "spear", "rock"
g.player.health = 58; g.player.injuries.bleeding = true
start_named(g, "Mouthless Man")
g.enc.range = "near"
g:enc_say("You hit the mouthless man (spear) (-9). It's bleeding.")
g:enc_say("The mouthless man hits you (-11 HP). You're bleeding.")
g.enc.cursor = 2
g:draw_encounter(400, 300)
solaros.dump("ops_encounter_fight.txt")

-- Scenes 8b-8e: the portrait reacting - far, close, badly hurt, dead
for _, st in ipairs({{"far", 1, nil}, {"close", 1, nil}, {"near", 0.2, nil}, {"near", 0, "dead"}}) do
    g = fresh(); g:start_game()
    start_named(g, "Jawhound")
    g.enc.range, g.enc.hp, g.enc.outcome = st[1], math.floor(g.enc.def.hp * st[2]), st[3]
    g.enc.seen = true
    g:draw_encounter(400, 300)
    solaros.dump("ops_portrait_" .. (st[3] or (st[2] < 1 and "hurt" or st[1])) .. ".txt")
end

-- Scene 8f: crafting - some materials, one recipe learned, a fire burning
g = fresh(); g:start_game()
g.player.inventory = {{item = "stick", qty = 4}, {item = "cloth_scrap", qty = 1},
                      {item = "rock", qty = 1}, {item = "strange_meat", qty = 1}}
g.known.spear = true
g.camps[g.player.q .. "," .. g.player.r] = {until_hour = g.player.hours + 9}
g.log = {"You build a campfire. It will burn 12h.", "Made Torch."}
g:open_crafting()
g.craft_ui.cursor = 5
g:draw_craft(400, 300)
solaros.dump("ops_craft.txt")

-- Scenes 8g/8h: the big map around the town, by day and at night, with a
-- campfire; a fixed seed so the preview is stable
for _, st in ipairs({{"day", 2}, {"night", 13}}) do
    os.time = function() return 4242 end
    g = fresh(); g:start_game()
    -- stand next to the town's first ruin and reveal a wide area
    local best
    for key, t in pairs(g.tiles) do
        if t == "ruins" then
            local q, r = key:match("(-?%d+),(-?%d+)")
            q, r = tonumber(q), tonumber(r)
            if not best or math.abs(q) + math.abs(r) < math.abs(best[1]) + math.abs(best[2]) then best = {q, r} end
        end
    end
    g.player.q, g.player.r = best[1], best[2]
    g.player.hours = st[2]
    for key in pairs(g.tiles) do
        local q, r = key:match("(-?%d+),(-?%d+)")
        if math.abs(tonumber(q) - best[1]) + math.abs(tonumber(r) - best[2]) <= 9 then g.player.explored[key] = true end
    end
    g.camps[best[1] .. "," .. best[2]] = {until_hour = st[2] + 6}
    g:refresh_view()
    g.log = {"Moved to Ruins (1 MP)", "You build a campfire. It will burn 12h."}
    g:draw_map(400, 300)
    solaros.dump("ops_map_world_" .. st[1] .. ".txt")
end

-- Scenes 8i-8k: the stag (the user's picture) at each range
for _, range in ipairs({"far", "near", "close"}) do
    g = fresh(); g:start_game()
    start_named(g, "Crawling Stag")
    g.enc.range = range
    g:draw_encounter(400, 300)
    solaros.dump("ops_stag_" .. range .. ".txt")
end

-- Scene 9: a helper
g = fresh(); g:start_game()
start_named(g, "Old Medic")
g:draw_encounter(400, 300)
solaros.dump("ops_encounter_helper.txt")

-- Scenes 10-13: an anomaly and each of its puzzle types, part-way through
g = fresh(); g:start_game()
start_named(g, "The Door in the Field")
g:draw_encounter(400, 300)
solaros.dump("ops_anomaly.txt")
local function puzzle_of(kind)
    for s = 1, 500 do
        local g2 = fresh(); g2:start_game(); g2.seed = s
        start_named(g2, "The Stillness")
        g2:encounter_action("investigate")
        if g2.puz.kind == kind then return g2 end
    end
end
g = puzzle_of("bolts")
g:puzzle_key(116); g:puzzle_key(solaros.gfx.KEY_UP)   -- throw a bolt ahead
for _, k in ipairs({solaros.gfx.KEY_LEFT, solaros.gfx.KEY_RIGHT}) do
    local c = g.puz.pos + (k == solaros.gfx.KEY_LEFT and -1 or 1)
    if not g.puz.haz[c] then g:puzzle_key(k); break end
end
g:draw_puzzle(400, 300)
solaros.dump("ops_puzzle_bolts.txt")
g = puzzle_of("sequence")
g:draw_puzzle(400, 300)
solaros.dump("ops_puzzle_sequence.txt")
g:puzzle_key(32); g:puzzle_key(48 + g.puz.seq[1])
g:draw_puzzle(400, 300)
solaros.dump("ops_puzzle_sequence_input.txt")
g = puzzle_of("runes")
g:draw_puzzle(400, 300)
solaros.dump("ops_puzzle_runes.txt")

-- Scene 14: inventory with an artifact under the cursor (its effect shows)
g = fresh(); g:start_game()
g.player.equipped.rhand = "drowned_eye"
g:put_stack("ground", nil, {item = "weeping_stone", qty = 1})
g.inv_cursor = #g:ground_list()   -- ground rows come first: this is the stone
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_artifact.txt")
print("scenes recorded, player at", g.player.q, g.player.r)

-- Scene: standing at the edge of an anomaly field with a Geiger counter
g = fresh()
g:start_game()
for k, l in pairs(g.rad) do
    if l == 2 and g.tiles[k] ~= "water" then
        local q, r = k:match("(-?%d+),(-?%d+)")
        g.player.q, g.player.r = tonumber(q), tonumber(r)
        break
    end
end
g.player.inventory[#g.player.inventory + 1] = {item = "geiger", qty = 1}
g.ticked_hour = g.player.hours
g.player.rads = 48
g.player.hours = g.player.hours + 1
g:tick()
g:draw_map(400, 300)
solaros.dump("ops_map_radiation.txt")
g.player.equipped.eyes = "gasmask"
g.player.inventory[#g.player.inventory + 1] = {item = "antirad", qty = 2}
g.player.inventory[#g.player.inventory + 1] = {item = "vodka", qty = 1}
g.player.inventory[#g.player.inventory + 1] = {item = "bolts", qty = 5}
g.inv_cursor = 1
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_radiation.txt")

-- Scenes: the trader (map next to the stall, barter), the Checkpoint, the ending
g = fresh()
g:start_game()
local tq, tr = g.sites.trader:match("(-?%d+),(-?%d+)")
g.player.q, g.player.r = tonumber(tq) + 1, tonumber(tr)
g:learn_site("trader")
g:learn_site("checkpoint")
g:refresh_view()
g.log = {"Moved to Ruins (1 MP)", "Trader: a checkpoint out of the Churn, NE 17."}
g:draw_map(400, 300)
solaros.dump("ops_map_trader.txt")
g.player.q, g.player.r = tonumber(tq), tonumber(tr)
g.player.inventory = {{item = "weeping_stone", qty = 2}, {item = "canned_beans", qty = 3},
                      {item = "dirty_water", qty = 2}, {item = "knife", qty = 1}}
g:open_trade()
g.trade_ui.give = {weeping_stone = 1}
g.trade_ui.get = {antirad = 1}
g.trade_ui.col = "theirs"
g.trade_ui.cursor.theirs = 1
g:draw_trade(400, 300)
solaros.dump("ops_trade.txt")
g.player.inventory = {{item = "permit", qty = 1}, {item = "weeping_stone", qty = 3}}
g:open_gate()
g:draw_gate(400, 300)
solaros.dump("ops_gate.txt")
g.stats = {kills = 7, searches = 40, artifacts = 4, fish = 3}
g.player.hours = 190
g:finish_run("permit")
g:draw_ending(400, 300)
solaros.dump("ops_ending.txt")

-- Scene: a leather belt worn, new weapons in the bag
g = fresh()
g.player.equipped.belt = "leather_belt"
g.player.equipped.rhand = "machete"
g.player.inventory = {{item = "shiv", qty = 1}, {item = "spiked_club", qty = 1},
                      {item = "pipe_spear", qty = 1}, {item = "scrap_metal", qty = 3},
                      {item = "jerky", qty = 2}, {item = "rope_belt", qty = 1}}
g.inv_cursor = 1
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_belt.txt")

-- Scenes: help (H) and device info (V)
g = fresh()
g:open_help()
g:draw_help(400, 300)
solaros.dump("ops_help.txt")
g:help_key(118)
g:draw_info(400, 300)
solaros.dump("ops_info.txt")

-- Scene: Karl asks a riddle
g = fresh()
g:start_game()
g:start_karl()
g:draw_encounter(400, 300)
solaros.dump("ops_karl.txt")

-- Scene: a stray dog
g = fresh()
g:start_game()
g.player.inventory = {{item = "strange_meat", qty = 1}}
g:start_encounter({kind = "dog", name = "Stray Dog", art = "stray", who = "dog", intro = "A thin mongrel watches you from the grass, ribs showing, one ear up. It doesn't run. It doesn't come closer either.", start = "near"})
g:draw_encounter(400, 300)
solaros.dump("ops_dog.txt")

-- Scenes: crafting with a repair on offer, and the LoRa radio
g = fresh()
g:start_game()
for k in pairs(g.ground) do g.ground[k] = {} end
g.player.inventory = {{item = "broken_radio", qty = 1}, {item = "multitool", qty = 1},
                      {item = "circuit_board", qty = 1}, {item = "copper_wire", qty = 1},
                      {item = "battery_cell", qty = 1}}
g:open_crafting()
g.craft_ui.cursor = #g:known_recipes()
g:draw_craft(400, 300)
solaros.dump("ops_craft_repair.txt")
g.player.inventory = {{item = "lora_radio", qty = 1}}
g.radio = {charge = 3, next = {anna = g.player.hours + 20}}
g:open_radio()
g:radio_call(1)
g:draw_radio(400, 300)
solaros.dump("ops_radio.txt")

-- Scene: the journal mid-run
g = fresh()
g:start_game()
g:learn_site("trader"); g:learn_site("checkpoint")
g:mark_stash()
g.rad_known["2,0"] = 2
g.player.rads = 31
g.dog = {hp = 24, fed_hour = 0, hungry_days = 0}
g.player.inventory = {{item = "lora_radio", qty = 1}, {item = "weeping_stone", qty = 1}}
g.radio = {charge = 3, next = {}}
g.player.hours = 61
g.skills = {scav = 30, fish = 12, fight = 55, tinker = 4}
g:open_journal()
g:draw_journal(400, 300)
solaros.dump("ops_journal.txt")

-- Scene: the skills page (K in the journal)
g:open_skills()
g:draw_skills(400, 300)
solaros.dump("ops_skills.txt")

-- Scenes: your camp (map from next door, and the stash box in the bag)
g = fresh()
g:start_game()
local ck
for k, t in pairs(g.tiles) do if t == "ruins" and k ~= g.sites.trader then ck = k; break end end
local cq, cr = ck:match("(-?%d+),(-?%d+)")
g.base = {key = ck, built = {box = true, bedroll = true, barrel = true}, barrel_hour = 0}
g.ground[ck] = {{item = "water_bottle", qty = 3}, {item = "canned_beans", qty = 2}, {item = "rope", qty = 1}}
g.player.q, g.player.r = tonumber(cq) + 1, tonumber(cr)
g:refresh_view()
g:draw_map(400, 300)
solaros.dump("ops_map_camp.txt")
g.player.q, g.player.r = tonumber(cq), tonumber(cr)
g:refresh_view()
g.inv_cursor = 1
g:draw_inventory(400, 300)
solaros.dump("ops_inventory_camp.txt")

-- Scene: the lore reader
g = fresh()
g:start_game()
for _ = 1, 4 do g:read_lore() end
g.lore_page = 3
g.screen = "lore"
g:draw_lore(400, 300)
solaros.dump("ops_lore.txt")

-- Scene: a night horror (the Long Man)
g = fresh()
g:start_game()
g.player.hours = 14
g:start_encounter({kind = "horror", horror = "long_man", name = "The Long Man", art = "long_man",
    who = "long man", start = "far", speed = 3,
    intro = "Someone stands at the edge of your light. Too tall. Its arms hang past its knees. It doesn't move, and you can't tell which way it's facing."})
g:draw_encounter(400, 300)
solaros.dump("ops_horror.txt")

-- Scene: the records screen (title, R)
g = Game.new()
g.screen = "title"
local rec = Game.records()
rec.achieved.night_owl, rec.achieved.karl = true, true
g:open_records()
g:draw_records(400, 300)
solaros.dump("ops_records.txt")

-- Scene: a foggy winter day (shorter sight, the season on the panel)
g = Game.new()
g:start_game()
g.player.hours = 13 * 24 + 2
g.weather = function() return "Fog" end
g:refresh_view()
g:draw_map(400, 300)
solaros.dump("ops_map_fog_winter.txt")

-- Scenes: the map in rain, a storm and snow (the weather drawn over it)
for _, kind in ipairs({"Rain", "Storm", "Snow"}) do
    g = Game.new()
    g:start_game()
    g.player.hours = (kind == "Snow" and 13 or 2) * 24 + 10
    g.weather = function() return kind end
    g:refresh_view()
    g:draw_map(400, 300)
    solaros.dump("ops_map_" .. kind:lower() .. ".txt")
end

-- Scenes: the Ferry Post on the map (with the Peddler passing), Mother Okun's stall
g = Game.new()
g:start_game()
if g.sites.ferry then
    local q, r = g.sites.ferry:match("(-?%d+),(-?%d+)")
    g.player.q, g.player.r = tonumber(q) + 1, tonumber(r)
    if not g.tiles[g.player.q .. "," .. g.player.r] then g.player.q = tonumber(q) end
    g:refresh_view()
    g:spot_sites()
    g.extras.route[1] = g.player.q .. "," .. (g.player.r + 1)   -- (he's passing by)
    g.player.hours = 0
    g:draw_map(400, 300)
    solaros.dump("ops_map_ferry.txt")
    g:open_trade("ferry")
    g.trade_ui.col = "theirs"
    g:draw_trade(400, 300)
    solaros.dump("ops_trade_ferry.txt")
end

-- Scenes: the Little Ones (a warren and a cairn on the map, a troupe of 3 following; meeting them)
g = Game.new()
g:start_game()
local w = g.extras.warrens[1]
local q, r = w:match("(-?%d+),(-?%d+)")
g.player.q, g.player.r = tonumber(q), tonumber(r) + 1
if not g.tiles[g.player.q .. "," .. g.player.r] then g.player.r = tonumber(r) end
g:refresh_view()
g.little.seen[w] = true
for _, c in ipairs(g.extras.cairns) do g.little.seen[c] = true end
g.little.n, g.little.friend, g.little.mood = 3, 9, 8
g:draw_map(400, 300)
solaros.dump("ops_map_little.txt")
g.little = Game.new_little()
g.player.inventory = {{item = "crayons", qty = 1}}
g.player.q, g.player.r = tonumber(q), tonumber(r)
g:little_arrive()   -- strangers at their warren: they come out to look
g:draw_encounter(400, 300)
solaros.dump("ops_little.txt")

-- Scenes: the storyline (the quarry gate, the Institute, the Quiet ending)
g = Game.new()
g:start_game()
if g.sites.quarry then
    local q, r = g.sites.quarry:match("(-?%d+),(-?%d+)")
    g.player.q, g.player.r = tonumber(q) - 1, tonumber(r) + 1
    if not g.tiles[g.player.q .. "," .. g.player.r] then g.player.q, g.player.r = tonumber(q), tonumber(r) end
    g.lore_read = {true, true, true, true, true, true}
    g:story_check()
    g:refresh_view()
    g:spot_sites()
    g:draw_map(400, 300)
    solaros.dump("ops_map_quarry.txt")
    g.player.q, g.player.r = tonumber(q), tonumber(r)
    g.story.step, g.story.pass = "source", true
    g.player.inventory = {{item = "institute_pass", qty = 1}, {item = "multitool", qty = 1}}
    g:open_institute()
    g:draw_encounter(400, 300)
    solaros.dump("ops_institute.txt")
    g.enc = nil
    g:finish_run("quiet")
    g:draw_ending(400, 300)
    solaros.dump("ops_ending_quiet.txt")
end

-- Story moments: waking up, and the quarry gate (with the Institute's portrait)
for _, id in ipairs({"wake", "the_gate", "little_ones"}) do
    g = Game.new()
    g.scene, g.screen = id, "scene"
    g:draw_scene(400, 300)
    solaros.dump("ops_scene_" .. id .. ".txt")
end

-- Scene: the intro splash, the title menu, the first page of the story
g = Game.new()
g:begin_intro(nil)
g.intro_phase = 2
g:draw_intro(400, 300)
solaros.dump("ops_intro.txt")
g.screen = "title"
g:draw_title(400, 300)
solaros.dump("ops_title.txt")
g.crawl_page = 3
g:draw_crawl(400, 300)
solaros.dump("ops_crawl.txt")

-- Scene: crafting by a fire - a Study entry under the cursor, research under way
g = Game.new()
g:start_game()
g.camps[g.player.q .. "," .. g.player.r] = {until_hour = g.player.hours + 9}
g.research = {bushcraft = 5}
table.insert(g.player.inventory, {item = "book_field", qty = 1})
g.screen = "craft"
for i, r in ipairs(g:known_recipes()) do if r.study == "bushcraft" then g.craft_ui.cursor = i end end
g.log = {"You study bushcraft for 3h. (5/6)"}
g:draw_craft(400, 300)
solaros.dump("ops_craft_study.txt")

-- Scene: assembling a pistol (a learned recipe with a chance)
g.known.assemble_pm = true
for _, id in ipairs({"frame_pm", "gun_slide", "gun_barrel", "gun_spring", "firing_pin", "magazine"}) do
    table.insert(g:ground_list(), {item = id, qty = 1})
end
table.insert(g:ground_list(), {item = "multitool", qty = 1})
for i, r in ipairs(g:known_recipes()) do if r.id == "assemble_pm" then g.craft_ui.cursor = i end end
g.log = {"From the tape: Assemble PM."}
g:draw_craft(400, 300)
solaros.dump("ops_craft_gun.txt")

-- Scene: a gunfight - the PM in hand, rounds in the bag
g = Game.new()
g:start_game()
g.player.equipped.rhand = "pm_pistol"
table.insert(g.player.inventory, {item = "r9x18", qty = 7})
g:start_encounter({kind = "animal", name = "Jawhound", art = "jawhound", who = "jawhound",
    intro = "A dog stands in the scrub, but wrong: eyes crowd its flanks and back, all of them open.",
    hp = 30, dmg = {6, 12}, hit = 60, speed = 4, bleed = 30, flees_at = 8, start = "far",
    loot = {{"nothing", 1}}})
g:enc_say("The PM Pistol cracks. You hit the jawhound (-19). It's bleeding.")
g:draw_encounter(400, 300)
solaros.dump("ops_encounter_gun.txt")
