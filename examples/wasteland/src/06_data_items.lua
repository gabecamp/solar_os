-- ---------------------------------------------------------------------
-- Items: the bag and body slots, ITEM_DB, artifacts, scavenging loot
-- tables and crafting recipes
-- ---------------------------------------------------------------------

local BACKPACK_CAP = 16      -- most bag cells any build can have (the layout's limit)
local POCKET_CELLS = 4       -- bag cells with nothing worn on your back

-- Also the cursor order on the paperdoll: top of the body to the bottom.
local EQUIP_SLOTS = {
    "head", "ears", "eyes", "neck", "back", "jacket", "shirt", "belt",
    "hands", "wrists", "pants", "lhand", "rhand", "feet",
}
-- Hand slots hold any item (a rock, a bottle, a spare jacket); every other
-- slot only takes items whose ITEM_DB slot matches.
local HOLD_SLOTS = {lhand = true, rhand = true}

local ITEM_DB = {
    -- wear: what the item paints on the paperdoll when worn - {body part,
    -- first row, last row (exclusive), color}, rows in the figure's authored
    -- coordinates (see BODY_POLYGONS). Drawn in order, later entries on top.
    tshirt       = {name = "T-Shirt",      slot = "shirt", consumable = nil, warmth = 1,
                    wear = {{"torso", 146, 227, "DARK"}, {"arms", 150, 184, "DARK"}}},
    jeans        = {name = "Jeans",        slot = "pants", consumable = nil, warmth = 1,
                    wear = {{"torso", 214, 227, "DARK"}, {"legs", 224, 279, "DARK"}}},
    boots        = {name = "Boots",        slot = "feet",  consumable = nil, warmth = 1,
                    wear = {{"legs", 272, 290, "BLACK"}}},
    cap          = {name = "Cap",          slot = "head",  consumable = nil, warmth = 1,
                    wear = {{"head", 116, 126, "BLACK"}}},
    gloves       = {name = "Gloves",       slot = "hands", consumable = nil, warmth = 1,
                    wear = {{"arms", 234, 252, "BLACK"}}},
    -- optional 5th/6th wear fields: only paint where the distance from the
    -- body's center line is between them (authored units), e.g. just the
    -- sides of the head for earmuffs, or an open jacket front
    earmuffs     = {name = "Earmuffs",     slot = "ears",  consumable = nil, warmth = 1,
                    wear = {{"head", 118, 122, "BLACK", 0, 12},
                            {"head", 124, 136, "BLACK", 8, 12}}},
    sunglasses   = {name = "Sunglasses",   slot = "eyes",  consumable = nil,
                    wear = {{"head", 127, 131, "BLACK", 1, 9}}},
    scarf        = {name = "Scarf",        slot = "neck",  consumable = nil, warmth = 1,
                    wear = {{"torso", 139, 150, "BLACK", 0, 12}}},
    jacket       = {name = "Leather Jacket", slot = "jacket", consumable = nil, warmth = 3,
                    wear = {{"torso", 146, 222, "BLACK", 5, 40},
                            {"arms", 150, 232, "BLACK"}}},
    bracers      = {name = "Bracers",      slot = "wrists", consumable = nil,
                    wear = {{"arms", 222, 233, "BLACK"}}},
    -- bags: bag_cells is how many bag cells you get while wearing it
    backpack     = {name = "Backpack",     slot = "back", consumable = nil, bag_cells = 12,
                    wear = {{"torso", 147, 196, "BLACK", 9, 13}}},
    -- rad_armor multiplies the radiation you take while it's worn
    gasmask      = {name = "Gas Mask",     slot = "eyes",  consumable = nil, warmth = 1,
                    rad_armor = 0.5, desc = "Worn: halves radiation", vague_desc = "Worn: filters bad air",
                    wear = {{"head", 125, 139, "BLACK", 0, 10}}},
    -- belts: belt_cells more bag cells (pouches), on top of the bag
    leather_belt = {name = "Leather Belt", slot = "belt", consumable = nil, belt_cells = 2,
                    desc = "Worn: +2 bag cells", wear = {{"torso", 209, 214, "BLACK"}}},
    rope_belt    = {name = "Rope Belt",    slot = "belt", consumable = nil, belt_cells = 1,
                    desc = "Worn: +1 bag cell", wear = {{"torso", 210, 213, "BLACK"}}},
    satchel      = {name = "Satchel",      slot = "back", consumable = nil, bag_cells = 8,
                    wear = {{"torso", 147, 210, "BLACK", 12, 15}}},
    canned_beans = {name = "Canned Beans", slot = nil, consumable = {hunger = 40}},
    -- empty: what is left in your hands after drinking (see SURVIVE)
    water_bottle = {name = "Water Bottle", slot = nil, consumable = {thirst = 50},
                    empty = "empty_bottle"},
    dirty_water  = {name = "Dirty Water",  slot = nil, consumable = {thirst = 50},
                    empty = "empty_bottle", sick = 40, desc = "Boil it at a fire (C)"},
    empty_bottle = {name = "Empty Bottle", slot = nil, consumable = nil,
                    desc = "E on the map by water: fill"},
    rotten_meat  = {name = "Rotten Meat",  slot = nil, consumable = {hunger = 20},
                    sick = 70, desc = "Gone bad. Risky"},
    berries      = {name = "Wild Berries", slot = nil, consumable = {hunger = 15, thirst = 5}},
    strange_meat = {name = "Strange Meat", slot = nil, consumable = {hunger = 30, thirst = -5},
                    sick = 25, perish = {hours = 36, into = "rotten_meat"}, desc = "Cook it (C at a fire)"},
    -- rads: taken off your radiation (see RAD)
    -- vague_name/vague_desc: what you see without a Geiger counter (nothing
    -- may say "radiation" until you can measure it; see apply_item_names)
    antirad      = {name = "Anti-Rad",     slot = nil, consumable = {rads = -50, thirst = -5},
                    desc = "E: -50 rads", vague_name = "Iodine Pills", vague_desc = "E: for sickness"},
    vodka        = {name = "Vodka",        slot = nil, consumable = {rads = -20, thirst = -10, rest = -10},
                    desc = "E: -20 rads, dulls you", vague_desc = "E: settles the stomach"},
    geiger       = {name = "Geiger Counter", slot = nil, consumable = nil,
                    desc = "Carry it: reads radiation"},
    permit       = {name = "Zone Permit",  slot = nil, consumable = nil,
                    desc = "Gets you past the Checkpoint"},
    bolts        = {name = "Bolts",        slot = nil, consumable = nil,
                    desc = "Anomalies: +2 bolt throws"},
    -- weapon: used from a hand slot. dmg per hit; reach "close" (arm's
    -- length) or "near" (a spear's length); thrown ones are hurled from
    -- range and land on the ground; bleed: % chance a hit opens a wound
    rock         = {name = "Rock",         slot = nil, consumable = nil,
                    weapon = {dmg = 6, reach = "close", thrown = true}},
    cloth_scrap  = {name = "Cloth Scrap",  slot = nil, consumable = nil},   -- E: bandage
    knife        = {name = "Knife",        slot = nil, consumable = nil,
                    weapon = {dmg = 12, reach = "close", bleed = 30}},
    pipe         = {name = "Lead Pipe",    slot = nil, consumable = nil,
                    weapon = {dmg = 15, reach = "close"}},
    spear        = {name = "Spear",        slot = nil, consumable = nil,
                    weapon = {dmg = 10, reach = "near", bleed = 15}},
    stone_club   = {name = "Stone Club",   slot = nil, consumable = nil,
                    weapon = {dmg = 13, reach = "close"}, desc = "Weapon: 13 dmg"},
    shiv         = {name = "Shiv",         slot = nil, consumable = nil,
                    weapon = {dmg = 9, reach = "close", bleed = 25}, desc = "Weapon: 9 dmg, bleeds"},
    machete      = {name = "Machete",      slot = nil, consumable = nil,
                    weapon = {dmg = 17, reach = "close", bleed = 25}, desc = "Weapon: 17 dmg, bleeds"},
    spiked_club  = {name = "Spiked Club",  slot = nil, consumable = nil,
                    weapon = {dmg = 16, reach = "close", bleed = 10}, desc = "Weapon: 16 dmg"},
    pipe_spear   = {name = "Pipe Spear",   slot = nil, consumable = nil,
                    weapon = {dmg = 14, reach = "near", bleed = 20}, desc = "Weapon: 14 dmg, reach"},
    -- Karl's gifts. fish_bonus: % added to fishing while worn (or carried, for the lure)
    pilk         = {name = "Pilk",         slot = nil, consumable = {thirst = 40, hunger = 10, rest = 15},
                    desc = "Pepsi and milk. Karl swears by it"},
    lucky_lure   = {name = "Lucky Lure",   slot = nil, consumable = nil, fish_bonus = 15,
                    desc = "Carried: +15% fishing"},
    karls_waders = {name = "Karl's Waders", slot = "feet", consumable = nil, warmth = 2,
                    fish_bonus = 10, desc = "Worn: +10% fishing",
                    wear = {{"legs", 236, 290, "DARK"}}},
    karls_hat    = {name = "Karl's Hat",   slot = "head", consumable = nil, warmth = 1,
                    fish_bonus = 10, desc = "Worn: +10% fishing",
                    wear = {{"head", 112, 125, "BLACK"}}},
    fishing_rod  = {name = "Fishing Rod",  slot = nil, consumable = nil,
                    desc = "G by water: fish"},
    snare        = {name = "Snare",        slot = nil, consumable = nil,
                    desc = "E: set it here, check later"},
    raw_fish     = {name = "Pale Fish",    slot = nil, consumable = {hunger = 20, thirst = 5},
                    sick = 15, perish = {hours = 24, into = "rotten_meat"}, desc = "Too many eyes. Cook it"},
    cooked_fish  = {name = "Cooked Fish",  slot = nil, consumable = {hunger = 35},
                    perish = {hours = 48, into = "rotten_meat"}},
    -- broken tech and its parts (TECH)
    broken_radio     = {name = "Broken Radio", slot = nil, consumable = nil, desc = "Repair: C, with parts"},
    lora_radio       = {name = "LoRa Radio",   slot = nil, consumable = nil, desc = "R: call for help"},
    broken_detector  = {name = "Dead Detector", slot = nil, consumable = nil, desc = "Repair: C, with parts"},
    anomaly_detector = {name = "Anomaly Detector", slot = nil, consumable = nil,
                        desc = "Carried: reads rads 3 hexes out"},
    broken_headlamp  = {name = "Broken Headlamp", slot = nil, consumable = nil, desc = "Repair: C, with parts"},
    headlamp     = {name = "Headlamp",     slot = "head", consumable = nil, light = true,
                    desc = "Worn: light at night", wear = {{"head", 118, 122, "BLACK"}}},
    circuit_board = {name = "Circuit Board", slot = nil, consumable = nil, desc = "A repair part"},
    copper_wire  = {name = "Copper Wire",  slot = nil, consumable = nil, desc = "A repair part"},
    battery_cell = {name = "Battery Cell", slot = nil, consumable = nil, desc = "Part; E: charge radio"},
    antenna      = {name = "Antenna",      slot = nil, consumable = nil, desc = "A repair part"},
    multitool    = {name = "Multitool",    slot = nil, consumable = nil, desc = "Tool for repairs"},
    lore_page    = {name = "Torn Page",    slot = nil, consumable = nil, desc = "E: read it"},
    scrap_metal  = {name = "Scrap Metal",  slot = nil, consumable = nil, desc = "For crafting"},
    jerky        = {name = "Jerky",        slot = nil, consumable = {hunger = 25, thirst = -5}},
    -- crafting materials and crafted goods (see RECIPES)
    stick        = {name = "Stick",        slot = nil, consumable = nil, desc = "For crafting"},
    rope         = {name = "Rope",         slot = nil, consumable = nil, desc = "For crafting"},
    torch        = {name = "Torch",        slot = nil, consumable = nil,
                    desc = "Hold it: light in the dark"},
    medkit       = {name = "Medkit",       slot = nil, consumable = nil,
                    desc = "E: +40 HP, stops bleeding"},
    bandage      = {name = "Bandage",      slot = nil, consumable = nil,
                    desc = "E: stop bleeding, +15 HP"},
    splint       = {name = "Splint",       slot = nil, consumable = nil,
                    desc = "E: a wound heals 12h sooner"},
    cooked_meat  = {name = "Cooked Meat",  slot = nil, consumable = {hunger = 45},
                    perish = {hours = 72, into = "rotten_meat"}},
    scrawled_notes = {name = "Scrawled Notes", slot = nil, consumable = nil,
                    desc = "E: read, learn a recipe"},
    -- artifacts: left by anomalies; artifact = effects while held in a hand
    -- (see recompute_stats), desc = what the inventory shows under the cursor
    weeping_stone = {name = "Weeping Stone", slot = nil, consumable = nil,
                     artifact = {mp = 1, thirst = 1.5}, desc = "+1 MP, thirst x1.5"},
    drowned_eye   = {name = "Drowned Eye",   slot = nil, consumable = nil,
                     artifact = {sight = 1, rest_drain = 1.3}, desc = "+1 sight, tire x1.3"},
    flesh_knot    = {name = "Flesh Knot",    slot = nil, consumable = nil,
                     artifact = {heal = 2, hunger = 1.5}, desc = "+2 HP/h, hunger x1.5"},
    hollow_star   = {name = "Hollow Star",   slot = nil, consumable = nil,
                     artifact = {scav = 1, scav_hurt = 3}, desc = "+1 find, -3 HP/search"},
    quiet_shell   = {name = "Quiet Shell",   slot = nil, consumable = nil,
                     artifact = {encounter = 0.5, sight = -1}, desc = "half encounters, -1 sight"},
}
local ARTIFACTS = {"weeping_stone", "drowned_eye", "flesh_knot", "hollow_star", "quiet_shell"}

-- What scavenging can turn up, per terrain: {item, weight}. "nothing" is a
-- dud roll. Plains are old roadside junk, forest is food and cold-weather
-- gear, hills are rock and whatever hikers left behind.
local SCAVENGE_LOOT = {
    plains = {{"nothing", 22}, {"rock", 3}, {"cloth_scrap", 3}, {"canned_beans", 3},
              {"water_bottle", 2}, {"cap", 1}, {"sunglasses", 1}, {"gloves", 1},
              {"satchel", 1}, {"pipe", 1}, {"knife", 1}, {"stick", 2},
              {"scrawled_notes", 1}, {"bolts", 1}, {"vodka", 1}, {"empty_bottle", 2},
              {"scrap_metal", 2}, {"jerky", 2}, {"copper_wire", 1}, {"battery_cell", 1}},
    forest = {{"nothing", 16}, {"berries", 9}, {"cloth_scrap", 1}, {"water_bottle", 1},
              {"scarf", 1}, {"earmuffs", 1}, {"gloves", 1}, {"spear", 1}, {"stick", 6}},
    -- ruins: what's left in houses and cars
    ruins  = {{"nothing", 34}, {"canned_beans", 7}, {"water_bottle", 3}, {"cloth_scrap", 3},
              {"scrawled_notes", 2}, {"rope", 1}, {"knife", 1}, {"pipe", 1}, {"stick", 1},
              {"jacket", 1}, {"backpack", 1}, {"antirad", 1}, {"vodka", 1}, {"bolts", 2},
              {"geiger", 1}, {"gasmask", 1}, {"empty_bottle", 2}, {"scrap_metal", 3},
              {"leather_belt", 1}, {"jerky", 5}, {"broken_radio", 1}, {"broken_detector", 1},
              {"broken_headlamp", 1}, {"circuit_board", 1}, {"copper_wire", 2}, {"battery_cell", 1},
              {"antenna", 1}, {"multitool", 1}, {"lore_page", 2}},
    ford   = {{"nothing", 18}, {"rock", 4}, {"stick", 2}, {"water_bottle", 1}, {"scrap_metal", 1}},
    hills  = {{"nothing", 20}, {"rock", 5}, {"water_bottle", 1}, {"canned_beans", 2},
              {"jacket", 1}, {"bracers", 1}, {"boots", 1}, {"knife", 1}, {"stick", 1},
              {"scrawled_notes", 1}, {"antirad", 1}, {"scrap_metal", 1}, {"antenna", 1}},
}

-- Crafting, NEO Scavenger style: inputs come from your bag, your hands and
-- the ground where you stand. inputs are used up, tools only have to be
-- there, fire = needs a lit campfire on this tile. out = what you get (to the
-- bag, or the ground if it's full); place = something built on the tile.
-- known = you start knowing it; the rest are learned from Scrawled Notes.
local RECIPES = {
    {id = "torch", name = "Torch", inputs = {stick = 1, cloth_scrap = 1}, hours = 1,
     out = {"torch", 1}, known = true},
    {id = "bandage", name = "Bandage", inputs = {cloth_scrap = 2}, hours = 1,
     out = {"bandage", 1}, known = true},
    {id = "campfire", name = "Campfire", inputs = {stick = 3, rock = 1}, hours = 1,
     place = "campfire", known = true},
    {id = "cook", name = "Cooked Meat", inputs = {strange_meat = 1}, fire = true, hours = 1,
     out = {"cooked_meat", 1}, known = true},
    {id = "boil", name = "Boil Water", inputs = {dirty_water = 1}, fire = true, hours = 1,
     out = {"water_bottle", 1}, known = true},
    {id = "rope_belt", name = "Rope Belt", inputs = {rope = 1, cloth_scrap = 1}, hours = 1,
     out = {"rope_belt", 1}, known = true},
    {id = "shiv", name = "Shiv", inputs = {scrap_metal = 1, cloth_scrap = 1}, hours = 1,
     out = {"shiv", 1}, known = true},
    {id = "fishing_rod", name = "Fishing Rod", inputs = {stick = 1, rope = 1, scrap_metal = 1},
     hours = 1, out = {"fishing_rod", 1}, known = true},
    {id = "snare", name = "Snare", inputs = {rope = 1, stick = 2}, hours = 1,
     out = {"snare", 1}, known = true},
    {id = "cook_fish", name = "Cooked Fish", inputs = {raw_fish = 1}, fire = true, hours = 1,
     out = {"cooked_fish", 1}, known = true},
    -- base building (base = what it builds; see BASE and src/51_base.lua)
    {id = "claim", name = "Claim this ruin", inputs = {rope = 2, scrap_metal = 3}, hours = 4,
     base = "claim", known = true},
    {id = "box", name = "Stash box", inputs = {scrap_metal = 2, rope = 1}, hours = 2,
     base = "box", known = true},
    {id = "bedroll", name = "Bedroll", inputs = {cloth_scrap = 3, stick = 2}, hours = 2,
     base = "bedroll", known = true},
    {id = "barrel", name = "Rain barrel", inputs = {scrap_metal = 2, empty_bottle = 1}, hours = 2,
     base = "barrel", needs = "box", known = true},
    {id = "barricade", name = "Barricade", inputs = {stick = 4, scrap_metal = 2}, hours = 3,
     base = "barricade", known = true},
    {id = "filter", name = "Filter Water", inputs = {dirty_water = 1, cloth_scrap = 1}, hours = 1,
     out = {"water_bottle", 1}, known = true},
    {id = "splint", name = "Splint", inputs = {stick = 2, cloth_scrap = 1}, hours = 1,
     out = {"splint", 1}, known = true},
    {id = "rope", name = "Rope", inputs = {cloth_scrap = 3}, hours = 1, out = {"rope", 1}},
    {id = "spear", name = "Spear", inputs = {stick = 1, rope = 1}, tools = {"knife"},
     hours = 2, out = {"spear", 1}},
    {id = "club", name = "Stone Club", inputs = {stick = 1, rock = 1, rope = 1}, hours = 2,
     out = {"stone_club", 1}},
    {id = "machete", name = "Machete", inputs = {scrap_metal = 2, stick = 1, rope = 1},
     tools = {"rock"}, hours = 3, out = {"machete", 1}},
    {id = "spiked_club", name = "Spiked Club", inputs = {stone_club = 1, scrap_metal = 1},
     hours = 1, out = {"spiked_club", 1}},
    {id = "pipe_spear", name = "Pipe Spear", inputs = {pipe = 1, knife = 1, rope = 1},
     hours = 2, out = {"pipe_spear", 1}},
}
RECIPES.campfire_hours = 12   -- a fire burns this long after it's built

-- Worn gear that is scattered around the map (the starting clothes aren't).
local WORLD_WEARABLES = {"cap", "gloves", "earmuffs", "sunglasses", "scarf",
                         "jacket", "bracers", "satchel", "leather_belt"}

