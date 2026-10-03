-- ---------------------------------------------------------------------
-- The Churn's bigger crafting: item properties, research topics, the media
-- that teach recipes (books, cassettes, USB drives), the new materials and
-- recipes (many adapted from NEO Scavenger's), wards against the things in
-- the dark, and the rare handguns with their parts and rounds.
--
-- Everything is one table, CHURN (one local: see the 200-local note in
-- 35_crafting); the items, recipes and loot are added to ITEM_DB, RECIPES,
-- SCAVENGE_LOOT, TRADE and the encounters' loot below.
-- ---------------------------------------------------------------------

local CHURN = {
    -- Properties, NEO Scavenger style: a recipe can ask for "@sharp" (any
    -- sharp edge) instead of one item. items = what counts, cheapest first:
    -- a craft uses up (or works with) the first one you have.
    props = {
        sharp = {name = "sharp edge", items = {"glass_shard", "stone_knife", "scalpel", "screwdriver",
                 "crowbar", "glass_shiv", "shiv", "kitchen_knife", "hacksaw", "multitool", "knife",
                 "hunting_knife", "machete", "broad_spear"}},
        thread_s = {name = "thread", items = {"string", "sinew", "choir_wire", "copper_wire", "rope"}},
        thread_m = {name = "cord", items = {"rope", "duct_tape"}},
        shaft = {name = "shaft", items = {"stick", "large_branch", "pipe"}},
        shaft_l = {name = "long shaft", items = {"large_branch", "pipe"}},
        fuel = {name = "fuel", items = {"newspaper", "stick", "charcoal", "large_branch"}},
        heat = {name = "heat source", items = {"fire_drill", "matches", "lighter", "torch"}},
        fire_container = {name = "fireproof pot", items = {"tin_can", "metal_pot"}},
        rigid = {name = "small metal", items = {"screws", "scrap_metal"}},
        fletching = {name = "fletching", items = {"feathers", "newspaper"}},
        hide = {name = "hide", items = {"hide", "jawhound_pelt"}},
        gun_tool = {name = "gun tools", items = {"gunsmith_kit", "multitool"}},
    },

    -- Research (src/59_research.lua). A topic's recipes are learned in
    -- RECIPES order. Study at a fire or your camp: hours, then points
    -- (base, +per_point per Perception over 3, + tinker skill / 5; x2 with
    -- the topic's book in reach); need (+ need_step per recipe already
    -- known in the topic) points learns the next one. needs: one of these
    -- in reach to study the topic at all. cost: extra rest it takes.
    topics = {
        {id = "rags", name = "Tailoring", book = "book_tailor"},
        {id = "bushcraft", name = "Bushcraft", book = "book_field"},
        {id = "medicine", name = "Medicine", book = "book_surgeon"},
        {id = "tinkering", name = "Tinkering", book = "book_radio"},
        {id = "chemistry", name = "Chemistry", book = "book_lab",
         needs = {"chemicals", "book_lab", "gunpowder"}},
        {id = "gunsmithing", name = "Gunsmithing", book = "book_gunsmith",
         needs = {"book_gunsmith", "pm_pistol", "nagant", "tokarev", "inst_sidearm", "marsh_revolver",
                  "frame_pm", "frame_nagant", "frame_tt", "frame_inst", "gun_barrel", "firing_pin"}},
        {id = "warding", name = "Warding", book = "book_hymnal", cost = 15,
         needs = {"ichor", "pale_eye", "book_hymnal", "elder_sign"}},
    },
    study = {hours = 3, base = 4, per_point = 1, book_mult = 2, need = 8, need_step = 2,
             read_hours = 2, tape_hours = 1, tape_max = 4, usb_hours = 1, usb_fail = 25},

    -- Cassettes: the logs of the dead. Each teaches from its topic once.
    tapes = {
        tape_cook = {topic = "bushcraft", voice = "A tired man: 'Day forty. Bark tea for the gut, "
            .. "smoke the meat or lose it. The ground moved again last night. Our hut is "
            .. "a field further east than it was.'"},
        tape_medic = {topic = "medicine", voice = "A woman, calm: 'Boil the thread. Stitch toward "
            .. "you. If the wound sings, don't close it. Walk away and don't look back.'"},
        tape_gun = {topic = "gunsmithing", voice = "Someone chewing: 'The Makarov's a brick, it "
            .. "forgives you. Brass, powder, lead. Count your rounds. Out here the dark counts them too.'"},
        tape_choir = {topic = "warding", voice = "Static, then singing - many voices, one breath. "
            .. "Under it a man whispers: 'Salt the ground. Wax and black water. Draw the sign. "
            .. "They can't cross what they can't read.'"},
        tape_lab = {topic = "chemistry", voice = "A clipped voice: 'Institute log 7. Sample "
            .. "reacts to charcoal and nitrate. The quarry samples react to us. Recommend "
            .. "we stop listening to them.'"},
        tape_tinker = {topic = "tinkering", voice = "A teenager: 'If you're hearing this, the "
            .. "Choir Cell works. Phone memory, screwdriver, patience. Mum, if you find "
            .. "this - I went north.'"},
    },
    usb_topics = {"gunsmithing", "chemistry", "tinkering", "warding"},

    -- Ranged weapons (src/50s: Game:shoot): shoot = {dmg, ammo, jam %, hit
    -- bonus, quiet (no noise), curse (rest lost per shot)}. Guns wear a
    -- little each shot (self.gun_wear), and a worn gun jams more.
    guns = {wear_per_shot = 3, jam_per_wear = 5, noise_hours = 6, noise_mult = 1.5,
            shoot_hit = 55, far_penalty = 10, animal_flee = 25, bleed = 30},
}

-- -- the new items -------------------------------------------------------
-- look = whose sprite it borrows (10_sprites copies it) where it has none of its own.
for id, def in pairs({
    -- materials and simple tools
    glass_shard  = {name = "Glass Shard",  desc = "A sharp edge. Fragile"},
    string       = {name = "String",       desc = "Thread, for crafting"},
    sinew        = {name = "Sinew",        desc = "Thread, from an animal"},
    choir_wire   = {name = "Choir Wire",   desc = "Hums when you hold it. Thread"},
    large_branch = {name = "Large Branch", desc = "A long shaft; fuel"},
    newspaper    = {name = "Old Newspaper", desc = "Fuel. The headlines are wrong"},
    tin_can      = {name = "Tin Can",      desc = "Fireproof: boil and cook in it"},
    metal_pot    = {name = "Metal Pot",    desc = "Fireproof: boil and cook in it"},
    matches      = {name = "Matches",      desc = "Heat: light fires (C)"},
    lighter      = {name = "Lighter",      desc = "Heat: light fires (C)"},
    fire_drill   = {name = "Fire Drill",   desc = "Heat: slow, but it works"},
    bark         = {name = "Tree Bark",    desc = "Tannin: for tea and hides"},
    raw_hide     = {name = "Raw Hide",     desc = "Cure it with bark tea"},
    hide         = {name = "Cured Hide",   desc = "For crafting"},
    jawhound_pelt = {name = "Jawhound Pelt", desc = "Still has eyes in it. Hide"},
    bone         = {name = "Bone",         desc = "For crafting"},
    feathers     = {name = "Crow Feathers", desc = "Fletching, for arrows"},
    tarp         = {name = "Tarp",         desc = "For a shelter or a travois"},
    foil         = {name = "Foil Scrap",   desc = "For crafting"},
    screws       = {name = "Screws",       desc = "Small metal, for crafting"},
    mech_parts   = {name = "Mech. Parts",  desc = "Gears and springs"},
    duct_tape    = {name = "Duct Tape",    desc = "Cord, for crafting"},
    salt         = {name = "Salt",         desc = "For wards and curing"},
    pale_wax     = {name = "Pale Wax",     desc = "From the Institute's candles"},
    ichor        = {name = "Black Ichor",  desc = "It bled. It shouldn't have"},
    pale_eye     = {name = "Pale Eye",     desc = "It still follows you"},
    chemicals    = {name = "Chemicals",    desc = "Lab stock. Don't drink it"},
    charcoal     = {name = "Charcoal",     desc = "Fuel; for gunpowder"},
    gunpowder    = {name = "Gunpowder",    desc = "For rounds"},
    brass        = {name = "Brass Casings", desc = "Spent. Reload them"},
    lead_scrap   = {name = "Lead Scrap",   desc = "For bullets"},
    gun_oil      = {name = "Gun Oil",      desc = "For cleaning a gun"},
    laptop_battery = {name = "Laptop Battery", desc = "For a Choir Cell"},
    locked_phone = {name = "Locked Phone", desc = "Crack it open (C)"},
    pliers       = {name = "Pliers",       desc = "A tool"},
    screwdriver  = {name = "Screwdriver",  desc = "A tool; a crude edge",
                    weapon = {dmg = 7, reach = "close", bleed = 15}},
    crowbar      = {name = "Crowbar",      desc = "Weapon: 14 dmg; a tool",
                    weapon = {dmg = 14, reach = "close"}},
    hacksaw      = {name = "Hacksaw",      desc = "A tool; an edge"},
    scalpel      = {name = "Scalpel",      desc = "A sharp edge",
                    weapon = {dmg = 6, reach = "close", bleed = 40}},
    kitchen_knife = {name = "Kitchen Knife", desc = "Weapon: 10 dmg, bleeds",
                     weapon = {dmg = 10, reach = "close", bleed = 25}},
    hunting_knife = {name = "Hunting Knife", desc = "Weapon: 15 dmg, bleeds",
                     weapon = {dmg = 15, reach = "close", bleed = 35}},
    gunsmith_kit = {name = "Gunsmith Kit", desc = "Tools for guns"},
    -- crafted gear
    stone_knife  = {name = "Stone Knife",  desc = "Weapon: 7 dmg; an edge",
                    weapon = {dmg = 7, reach = "close", bleed = 15}},
    glass_shiv   = {name = "Glass Shiv",   desc = "Weapon: 9 dmg, bleeds",
                    weapon = {dmg = 9, reach = "close", bleed = 35}},
    broad_spear  = {name = "Broad Spear",  desc = "Weapon: 14 dmg, reach",
                    weapon = {dmg = 14, reach = "near", bleed = 25}},
    bone_needle  = {name = "Bone Needle",  desc = "A tool for stitching"},
    rag_shoes    = {name = "Rag Shoes",    slot = "feet", warmth = 1, ragged_of = "boots",
                    desc = "Warmer than wraps", wear = {{"legs", 274, 290, "DARK"}}},
    foil_poncho  = {name = "Foil Poncho",  slot = "jacket", warmth = 1, rad_armor = 0.85,
                    desc = "Worn: some radiation", vague_desc = "Worn: crackles faintly",
                    wear = {{"torso", 146, 215, "LIGHT", 5, 40}, {"arms", 150, 200, "LIGHT"}}},
    hide_tunic   = {name = "Hide Tunic",   slot = "shirt", warmth = 2, desc = "Worn: warmth 2",
                    wear = {{"torso", 146, 227, "DARK"}, {"arms", 150, 180, "DARK"}}},
    hide_gloves  = {name = "Hide Gloves",  slot = "hands", warmth = 1,
                    wear = {{"arms", 234, 252, "DARK"}}},
    hide_pack    = {name = "Hide Pack",    slot = "back", bag_cells = 12, desc = "Worn: 12 bag cells",
                    wear = {{"torso", 147, 200, "BLACK", 9, 13}}},
    pelt_coat    = {name = "Pelt Coat",    slot = "jacket", warmth = 4, pocket_cells = 2,
                    desc = "Warmth 4, +2 cells. It watches", wear = {{"torso", 146, 226, "BLACK", 5, 40},
                    {"arms", 150, 234, "BLACK"}}},
    travois      = {name = "Travois",      slot = "back", bag_cells = 14, fx = {mp = -1},
                    desc = "Dragged: 14 cells, -1 MP", wear = {{"torso", 147, 196, "DARK", 9, 13}}},
    hand_cart    = {name = "Hand Cart",    slot = "back", bag_cells = 16, fx = {mp = -1},
                    desc = "Pushed: 16 cells, -1 MP", wear = {{"torso", 147, 196, "BLACK", 9, 13}}},
    lockpicks    = {name = "Lockpicks",    desc = "Opens locked crates (F)"},
    can_rattle   = {name = "Can Rattle",   desc = "E: hang it here; warns you"},
    tarp_shelter = {name = "Tarp Lean-to", desc = "E: pitch it; cover from storms"},
    bark_tea     = {name = "Bark Tea",     consumable = {thirst = 30}, cures = true,
                    desc = "E: drink; settles sickness"},
    smoked_meat  = {name = "Smoked Meat",  consumable = {hunger = 40}, desc = "Keeps a long time"},
    stitches     = {name = "Suture Kit",   desc = "E: stops bleeding, heals a wound"},
    tincture     = {name = "Herb Tincture", consumable = {rads = -25, thirst = -5},
                    desc = "E: -25 rads", vague_desc = "E: bitter, settling"},
    painkillers  = {name = "Painkillers",  desc = "E: +12 HP"},
    sedative     = {name = "Sedative",     consumable = {rest = 35}, desc = "E: sleep comes"},
    rad_purge    = {name = "Rad Purge",    consumable = {rads = -100, thirst = -15, hunger = -10},
                    desc = "E: -100 rads. Rough", vague_name = "Grey Syrup", vague_desc = "E: purges you"},
    flare        = {name = "Flare",        desc = "Throw it: burns, scares",
                    weapon = {dmg = 8, reach = "close", thrown = true}},
    choir_cell   = {name = "Choir Cell",   desc = "E: fully charges your devices"},
    -- wards against what walks in the dark
    salt_circle  = {name = "Salt Circle",  desc = "E: pour it; wards this hex"},
    black_candle = {name = "Black Candle", light = true, ward = true,
                    desc = "Hold it: light; horrors hang back"},
    glow_jar     = {name = "Glow Jar",     light = true, desc = "Hold it: a cold light"},
    choir_charm  = {name = "Choir Charm",  slot = "neck", fx = {encounter = 0.8, thirst = 1.1},
                    desc = "Worn: fewer meetings, thirst", wear = {{"torso", 140, 146, "BLACK", 0, 4}}},
    elder_sign   = {name = "Elder Sign",   desc = "Raise it at a horror: it goes"},
    -- media that teach (src/59_research.lua)
    book_tailor  = {name = "Seamstress's Almanac", book = "rags", desc = "E: read (Tailoring)"},
    book_field   = {name = "Field Manual", book = "bushcraft", desc = "E: read (Bushcraft)"},
    book_surgeon = {name = "Surgeon's Notes", book = "medicine", desc = "E: read (Medicine)"},
    book_radio   = {name = "Radio Ham Handbook", book = "tinkering", desc = "E: read (Tinkering)"},
    book_lab     = {name = "Institute Lab Book", book = "chemistry", desc = "E: read (Chemistry)"},
    book_gunsmith = {name = "Gunsmith's Ledger", book = "gunsmithing", desc = "E: read (Gunsmithing)"},
    book_hymnal  = {name = "The Choir Hymnal", book = "warding", desc = "E: read (Warding). Costs you"},
    cassette_player = {name = "Cassette Player", desc = "Plays tapes; Battery Cell: E"},
    tape_cook    = {name = "Tape: Day Forty", desc = "E: play it"},
    tape_medic   = {name = "Tape: The Medic", desc = "E: play it"},
    tape_gun     = {name = "Tape: Count Rounds", desc = "E: play it"},
    tape_choir   = {name = "Tape: The Choir", desc = "E: play it"},
    tape_lab     = {name = "Tape: Institute 7", desc = "E: play it"},
    tape_tinker  = {name = "Tape: I Went North", desc = "E: play it"},
    blank_tape   = {name = "Blank Tape",   desc = "Played out"},
    usb_drive    = {name = "USB Drive",    desc = "E: pair it with the LoRa Radio"},
    -- handguns: weapon = pistol-whip at arm's length; shoot = the shot (CHURN.guns)
    pm_pistol    = {name = "PM Pistol",    weapon = {dmg = 5, reach = "close"},
                    shoot = {dmg = 22, ammo = "r9x18", jam = 6, hit = 0}, desc = "Shoots 9x18"},
    nagant       = {name = "Nagant Revolver", weapon = {dmg = 5, reach = "close"},
                    shoot = {dmg = 24, ammo = "r762n", jam = 0, hit = -5}, desc = "Shoots 7.62N; never jams"},
    tokarev      = {name = "Tokarev TT",   weapon = {dmg = 6, reach = "close"},
                    shoot = {dmg = 30, ammo = "r762t", jam = 8, hit = 0}, desc = "Shoots 7.62x25; hits hard"},
    inst_sidearm = {name = "Institute Sidearm", weapon = {dmg = 5, reach = "close"},
                    shoot = {dmg = 26, ammo = "r9x18", jam = 2, hit = 15}, desc = "Shoots 9x18; precise"},
    marsh_revolver = {name = "Marsh Revolver", weapon = {dmg = 6, reach = "close"},
                      shoot = {dmg = 40, ammo = "r38", jam = 0, hit = 5, curse = 8},
                      desc = "Shoots .38. Each shot costs you"},
    bow          = {name = "Greenwood Bow", weapon = {dmg = 3, reach = "close"},
                    shoot = {dmg = 12, ammo = "arrow", jam = 0, hit = -5, quiet = true}, desc = "Shoots arrows; quiet"},
    sling        = {name = "Sling",        shoot = {dmg = 7, ammo = "rock", jam = 0, hit = -10, quiet = true},
                    desc = "Hurls rocks; quiet"},
    arrow        = {name = "Arrows",       desc = "Ammo: the bow"},
    r9x18        = {name = "9x18 Rounds",  desc = "Ammo: PM, Institute"},
    r762n        = {name = "7.62N Rounds", desc = "Ammo: Nagant"},
    r762t        = {name = "7.62x25 Rounds", desc = "Ammo: Tokarev"},
    r38          = {name = ".38 Rounds",   desc = "Ammo: Marsh Revolver"},
    -- gun parts: a frame decides the gun; the rest are shared
    frame_pm     = {name = "PM Frame",     desc = "Gun part: PM Pistol"},
    frame_nagant = {name = "Nagant Frame", desc = "Gun part: Nagant"},
    frame_tt     = {name = "TT Frame",     desc = "Gun part: Tokarev"},
    frame_inst   = {name = "Odd Frame",    desc = "Gun part: no maker's mark"},
    gun_slide    = {name = "Slide",        desc = "Gun part"},
    gun_barrel   = {name = "Gun Barrel",   desc = "Gun part"},
    gun_spring   = {name = "Recoil Spring", desc = "Gun part"},
    firing_pin   = {name = "Firing Pin",   desc = "Gun part"},
    magazine     = {name = "Magazine",     desc = "Gun part: pistols"},
    cylinder     = {name = "Cylinder",     desc = "Gun part: revolvers"},
}) do ITEM_DB[id] = def end
-- sprites borrowed from a look-alike (the rest have art in CHURN.art below)
for id, look in pairs({
    sinew = "string", choir_wire = "string", metal_pot = "tin_can", lighter = "matches",
    raw_hide = "hide", jawhound_pelt = "hide", newspaper = "lore_page", duct_tape = "rope",
    pale_eye = "ichor", charcoal = "rock", lead_scrap = "scrap_metal", screws = "bolts",
    mech_parts = "scrap_metal", foil = "cloth_scrap", gun_oil = "water_bottle",
    laptop_battery = "battery_cell", locked_phone = "usb_drive", pliers = "multitool",
    screwdriver = "shiv", hacksaw = "machete", scalpel = "shiv", kitchen_knife = "knife",
    hunting_knife = "knife", gunsmith_kit = "multitool", stone_knife = "shiv",
    glass_shiv = "shiv", broad_spear = "spear", bone_needle = "bone", hide_gloves = "gloves",
    hide_tunic = "tshirt", hide_pack = "backpack", pelt_coat = "jacket", travois = "sack_pack",
    hand_cart = "backpack", lockpicks = "bolts", smoked_meat = "jerky", tincture = "antirad",
    painkillers = "antirad", sedative = "antirad", rad_purge = "antirad", choir_cell = "battery_cell",
    glow_jar = "water_bottle", salt_circle = "salt", bark_tea = "water_bottle", stitches = "bandage",
    book_tailor = "book_field", book_surgeon = "book_field", book_radio = "book_field",
    book_lab = "book_field", book_gunsmith = "book_field", book_hymnal = "book_field",
    tape_medic = "tape_cook", tape_gun = "tape_cook", tape_choir = "tape_cook",
    tape_lab = "tape_cook", tape_tinker = "tape_cook", blank_tape = "tape_cook",
    marsh_revolver = "nagant", tokarev = "pm_pistol", inst_sidearm = "pm_pistol",
    r762n = "r9x18", r762t = "r9x18", r38 = "r9x18", brass = "r9x18",
    frame_pm = "pm_pistol", frame_nagant = "nagant", frame_tt = "pm_pistol", frame_inst = "pm_pistol",
    gun_slide = "gun_barrel", gun_spring = "mech_parts", firing_pin = "gun_barrel",
    magazine = "r9x18", cylinder = "mech_parts",
}) do ITEM_DB[id].look = look end
ITEM_DB.canned_beans.empty = "tin_can"   -- the can is your first pot

-- -- recipes ------------------------------------------------------------
-- Existing recipes: which topic teaches them (everything not listed and
-- not marked known below has to be learned).
for id, topic in pairs({
    rope = "rags", rag_hood = "rags", hand_wraps = "rags", ear_wraps = "rags", slit_goggles = "rags",
    rag_scarf = "rags", patch_coat = "rags", scrap_bracers = "rags", sack_pack = "rags",
    rag_mask = "rags", rope_belt = "rags",
    snare = "bushcraft", fishing_rod = "bushcraft", spear = "bushcraft", club = "bushcraft",
    bedroll = "bushcraft", barricade = "bushcraft",
    filter = "medicine", splint = "medicine",
    shiv = "tinkering", machete = "tinkering", spiked_club = "tinkering", pipe_spear = "tinkering",
    barrel = "tinkering",
}) do
    for _, r in ipairs(RECIPES) do
        if r.id == id then r.topic, r.known = topic, nil end
    end
end
for _, r in ipairs({
    -- known from the start: you wake with nothing, and need these to live
    {id = "fire_drill", name = "Fire Drill", inputs = {stick = 2, cloth_scrap = 1}, hours = 1,
     out = {"fire_drill", 1}, known = true},
    {id = "small_fire", name = "Small Fire", inputs = {["@fuel"] = 1}, tools = {"@heat"}, hours = 1,
     place = "campfire", burn = 4, known = true},
    -- Tailoring
    {id = "string", name = "String", inputs = {cloth_scrap = 1}, hours = 1, out = {"string", 2}, topic = "rags"},
    {id = "bone_needle", name = "Bone Needle", inputs = {bone = 1}, tools = {"@sharp"}, hours = 1,
     out = {"bone_needle", 1}, topic = "rags"},
    {id = "rag_shoes", name = "Rag Shoes", inputs = {cloth_scrap = 2, ["@thread_s"] = 2}, hours = 1,
     out = {"rag_shoes", 1}, topic = "rags"},
    {id = "foil_poncho", name = "Foil Poncho", inputs = {foil = 4, ["@thread_s"] = 2}, hours = 2,
     out = {"foil_poncho", 1}, topic = "rags"},
    {id = "hide_gloves", name = "Hide Gloves", inputs = {["@hide"] = 1, ["@thread_s"] = 1},
     tools = {"@sharp"}, hours = 1, out = {"hide_gloves", 1}, topic = "rags"},
    {id = "hide_tunic", name = "Hide Tunic", inputs = {["@hide"] = 3, ["@thread_s"] = 3},
     tools = {"@sharp", "bone_needle"}, hours = 3, out = {"hide_tunic", 1}, topic = "rags"},
    {id = "hide_pack", name = "Hide Pack", inputs = {["@hide"] = 3, ["@thread_m"] = 1},
     tools = {"@sharp", "bone_needle"}, hours = 3, out = {"hide_pack", 1}, topic = "rags"},
    {id = "pelt_coat", name = "Pelt Coat", inputs = {jawhound_pelt = 1, ["@thread_m"] = 1},
     tools = {"@sharp", "bone_needle"}, hours = 4, out = {"pelt_coat", 1}, topic = "rags"},
    -- Bushcraft
    {id = "stone_knife", name = "Stone Knife", inputs = {rock = 2}, hours = 1, out = {"stone_knife", 1},
     topic = "bushcraft"},
    {id = "glass_shiv", name = "Glass Shiv", inputs = {glass_shard = 1, ["@thread_s"] = 1, cloth_scrap = 1},
     hours = 1, out = {"glass_shiv", 1}, topic = "bushcraft"},
    {id = "bark_tea", name = "Bark Tea", inputs = {water_bottle = 1, bark = 2}, tools = {"@fire_container"},
     fire = true, hours = 1, out = {"bark_tea", 1}, topic = "bushcraft"},
    {id = "cure_hide", name = "Cure Hide", inputs = {raw_hide = 1, bark_tea = 1}, hours = 4,
     out = {"hide", 1}, topic = "bushcraft"},
    {id = "charcoal", name = "Charcoal", inputs = {stick = 2}, fire = true, hours = 2,
     out = {"charcoal", 2}, topic = "bushcraft"},
    {id = "smoked_meat", name = "Smoked Meat", inputs = {cooked_meat = 1, ["@fuel"] = 1}, fire = true,
     hours = 3, out = {"smoked_meat", 1}, topic = "bushcraft"},
    {id = "sling", name = "Sling", inputs = {cloth_scrap = 1, ["@thread_s"] = 2}, hours = 1,
     out = {"sling", 1}, topic = "bushcraft"},
    {id = "broad_spear", name = "Broad Spear", inputs = {spear = 1, glass_shard = 1, ["@thread_s"] = 1},
     hours = 1, out = {"broad_spear", 1}, topic = "bushcraft"},
    {id = "can_rattle", name = "Can Rattle", inputs = {tin_can = 2, ["@rigid"] = 1, ["@thread_s"] = 1},
     hours = 1, out = {"can_rattle", 1}, topic = "bushcraft"},
    {id = "tarp_shelter", name = "Tarp Lean-to", inputs = {tarp = 1, ["@shaft"] = 2, ["@thread_m"] = 1},
     hours = 2, out = {"tarp_shelter", 1}, topic = "bushcraft"},
    {id = "bow", name = "Greenwood Bow", inputs = {large_branch = 1, ["@thread_m"] = 1}, tools = {"@sharp"},
     hours = 3, out = {"bow", 1}, topic = "bushcraft"},
    {id = "arrows", name = "Arrows", inputs = {stick = 1, bone = 1, ["@thread_s"] = 1, ["@fletching"] = 1},
     tools = {"@sharp"}, hours = 2, out = {"arrow", 3}, topic = "bushcraft"},
    {id = "travois", name = "Travois", inputs = {large_branch = 2, ["@thread_m"] = 1, tarp = 1}, hours = 3,
     out = {"travois", 1}, topic = "bushcraft"},
    -- Medicine
    {id = "stitches", name = "Suture Kit", inputs = {["@thread_s"] = 1, vodka = 1}, tools = {"bone_needle"},
     hours = 1, out = {"stitches", 1}, topic = "medicine"},
    {id = "tincture", name = "Herb Tincture", inputs = {bark = 1, berries = 2, vodka = 1}, hours = 2,
     out = {"tincture", 1}, topic = "medicine"},
    {id = "medkit", name = "Medkit", inputs = {bandage = 2, stitches = 1, painkillers = 1}, hours = 1,
     out = {"medkit", 1}, topic = "medicine"},
    -- Tinkering
    {id = "lockpicks", name = "Lockpicks", inputs = {["@rigid"] = 1}, tools = {"pliers"}, hours = 2,
     out = {"lockpicks", 1}, topic = "tinkering"},
    {id = "crack_phone", name = "Crack Phone", inputs = {locked_phone = 1}, tools = {"screwdriver"}, hours = 2,
     out = {"usb_drive", 1}, topic = "tinkering"},
    {id = "choir_cell", name = "Choir Cell", inputs = {laptop_battery = 1, mech_parts = 1, choir_wire = 1},
     tools = {"pliers", "screwdriver"}, hours = 3, out = {"choir_cell", 1}, topic = "tinkering"},
    {id = "hand_cart", name = "Hand Cart", inputs = {mech_parts = 2, scrap_metal = 4, ["@rigid"] = 2},
     tools = {"pliers"}, hours = 4, out = {"hand_cart", 1}, topic = "tinkering"},
    -- Chemistry
    {id = "painkillers", name = "Painkillers", inputs = {chemicals = 1, bark = 1}, hours = 1,
     out = {"painkillers", 2}, topic = "chemistry"},
    {id = "gunpowder", name = "Gunpowder", inputs = {chemicals = 1, charcoal = 1, salt = 1}, hours = 2,
     out = {"gunpowder", 2}, topic = "chemistry"},
    {id = "flare", name = "Flare", inputs = {chemicals = 1, tin_can = 1}, hours = 1, out = {"flare", 2},
     topic = "chemistry"},
    {id = "sedative", name = "Sedative", inputs = {chemicals = 1, berries = 2}, hours = 1,
     out = {"sedative", 1}, topic = "chemistry"},
    {id = "gun_oil", name = "Gun Oil", inputs = {chemicals = 1, pale_wax = 1}, hours = 1,
     out = {"gun_oil", 2}, topic = "chemistry"},
    {id = "rad_purge", name = "Rad Purge", inputs = {antirad = 1, chemicals = 2}, fire = true, hours = 2,
     out = {"rad_purge", 1}, topic = "chemistry"},
    -- Gunsmithing: chance = assembly can fail and break a part (Perception, tinker)
    {id = "clean_gun", name = "Clean Guns", inputs = {gun_oil = 1, cloth_scrap = 1}, hours = 1,
     clean = true, topic = "gunsmithing"},
    {id = "reload_9x18", name = "Reload 9x18", inputs = {brass = 3, gunpowder = 1, lead_scrap = 1},
     tools = {"@gun_tool"}, hours = 2, out = {"r9x18", 3}, topic = "gunsmithing"},
    {id = "assemble_pm", name = "Assemble PM", chance = 55, tools = {"@gun_tool"}, hours = 4,
     inputs = {frame_pm = 1, gun_slide = 1, gun_barrel = 1, gun_spring = 1, firing_pin = 1, magazine = 1},
     out = {"pm_pistol", 1}, topic = "gunsmithing"},
    {id = "reload_762n", name = "Reload 7.62N", inputs = {brass = 3, gunpowder = 1, lead_scrap = 1},
     tools = {"@gun_tool"}, hours = 2, out = {"r762n", 3}, topic = "gunsmithing"},
    {id = "assemble_nagant", name = "Assemble Nagant", chance = 50, tools = {"@gun_tool"}, hours = 4,
     inputs = {frame_nagant = 1, gun_barrel = 1, cylinder = 1, gun_spring = 1, firing_pin = 1},
     out = {"nagant", 1}, topic = "gunsmithing"},
    {id = "reload_762t", name = "Reload 7.62x25", inputs = {brass = 3, gunpowder = 1, lead_scrap = 1},
     tools = {"@gun_tool"}, hours = 2, out = {"r762t", 3}, topic = "gunsmithing"},
    {id = "assemble_tt", name = "Assemble Tokarev", chance = 45, tools = {"@gun_tool"}, hours = 4,
     inputs = {frame_tt = 1, gun_slide = 1, gun_barrel = 1, gun_spring = 1, firing_pin = 1, magazine = 1},
     out = {"tokarev", 1}, topic = "gunsmithing"},
    {id = "assemble_inst", name = "Assemble Sidearm", chance = 35, tools = {"gunsmith_kit"}, hours = 6,
     inputs = {frame_inst = 1, gun_slide = 1, gun_barrel = 1, gun_spring = 1, firing_pin = 1, magazine = 1},
     out = {"inst_sidearm", 1}, topic = "gunsmithing"},
    {id = "reload_38", name = "Reload .38", inputs = {brass = 3, gunpowder = 1, lead_scrap = 1, ichor = 1},
     tools = {"@gun_tool"}, hours = 3, out = {"r38", 3}, topic = "gunsmithing"},
    -- Warding
    {id = "salt_circle", name = "Salt Circle", inputs = {salt = 2}, hours = 1, out = {"salt_circle", 1},
     topic = "warding"},
    {id = "elder_sign", name = "Elder Sign", inputs = {bone = 1, ichor = 1}, tools = {"@sharp"}, hours = 2,
     out = {"elder_sign", 1}, topic = "warding"},
    {id = "black_candle", name = "Black Candle", inputs = {pale_wax = 1, ichor = 1, ["@thread_s"] = 1},
     hours = 2, out = {"black_candle", 1}, topic = "warding"},
    {id = "glow_jar", name = "Glow Jar", inputs = {empty_bottle = 1, ichor = 1, salt = 1}, hours = 1,
     out = {"glow_jar", 1}, topic = "warding"},
    {id = "choir_charm", name = "Choir Charm", inputs = {choir_wire = 2, bone = 1, pale_eye = 1}, hours = 3,
     out = {"choir_charm", 1}, topic = "warding"},
}) do RECIPES[#RECIPES + 1] = r end

-- -- where it all turns up ---------------------------------------------
-- {item, weight} added to each terrain's scavenge table; "nothing" grows
-- with them, so a search comes up empty as often as before (the Churn is
-- stingy) but what it does turn up is more varied.
for terrain, adds in pairs({
    plains = {{"glass_shard", 2}, {"string", 2}, {"newspaper", 2}, {"tin_can", 2}, {"matches", 1},
              {"foil", 1}, {"screws", 1}, {"tarp", 1}, {"brass", 1}, {"usb_drive", 1}, {"book_field", 1}},
    forest = {{"large_branch", 4}, {"bark", 4}, {"feathers", 2}, {"bone", 2}, {"string", 1},
              {"tape_cook", 1}},
    ruins  = {{"glass_shard", 3}, {"string", 2}, {"tin_can", 3}, {"metal_pot", 1}, {"matches", 2},
              {"lighter", 1}, {"newspaper", 2}, {"foil", 2}, {"screws", 2}, {"mech_parts", 1},
              {"duct_tape", 1}, {"salt", 2}, {"chemicals", 1}, {"pliers", 1}, {"screwdriver", 1},
              {"kitchen_knife", 1}, {"crowbar", 1}, {"laptop_battery", 1}, {"locked_phone", 1},
              {"usb_drive", 1}, {"cassette_player", 1}, {"tape_medic", 1}, {"tape_tinker", 1},
              {"tape_gun", 1}, {"book_tailor", 1}, {"book_surgeon", 1}, {"book_radio", 1},
              {"brass", 2}, {"lead_scrap", 1}, {"r9x18", 1}, {"r762t", 1}, {"gun_spring", 1},
              {"magazine", 1}, {"frame_pm", 1}, {"gun_barrel", 1}, {"firing_pin", 1}, {"gun_slide", 1}},
    hills  = {{"bone", 3}, {"large_branch", 2}, {"salt", 1}, {"hunting_knife", 1}, {"r762n", 1},
              {"frame_nagant", 1}, {"cylinder", 1}, {"tape_choir", 1}, {"book_hymnal", 1}, {"pale_wax", 1}},
    ford   = {{"glass_shard", 2}, {"bone", 1}, {"tin_can", 1}, {"choir_wire", 1}},
}) do
    -- (duds = nothing and trinkets; loot[1] is {"nothing", n})
    local loot, rest, trink, added = SCAVENGE_LOOT[terrain], 0, 0, 0
    for i = 2, #loot do
        rest = rest + loot[i][2]
        if ITEM_DB[loot[i][1]].trinket then trink = trink + loot[i][2] end
    end
    local share = (loot[1][2] + trink) / (loot[1][2] + rest)
    for _, a in ipairs(adds) do loot[#loot + 1] = a; added = added + a[2] end
    loot[1][2] = math.ceil((share * (rest + added) - trink) / (1 - share))
end

-- Locked crates (F with Lockpicks in ruins, once per hex): the rare stuff.
CHURN.crate_loot = {{"book_lab", 2}, {"book_gunsmith", 2}, {"tape_lab", 2}, {"gunsmith_kit", 2},
                    {"frame_tt", 2}, {"frame_inst", 1}, {"chemicals", 4}, {"gunpowder", 3},
                    {"r9x18", 4}, {"r762t", 2}, {"pm_pistol", 1}, {"tokarev", 1}, {"nagant", 1},
                    {"inst_sidearm", 1}, {"usb_drive", 3}, {"medkit", 2}, {"antirad", 3}}
CHURN.crate_chance = 35   -- % a ruin hex has a locked crate to pick

-- Enemies leave more: hides, sinew and bone from beasts, guns from people.
for _, e in ipairs(ENCOUNTERS) do
    local extra = ({
        jawhound = {{"jawhound_pelt", 2}, {"sinew", 1}, {"bone", 1}},
        boar = {{"raw_hide", 2}, {"sinew", 1}, {"bone", 2}},
        ["crow-knot"] = {{"feathers", 3}, {"bone", 1}},
        stag = {{"raw_hide", 2}, {"sinew", 2}, {"bone", 2}},
        ["fused pair"] = {{"ichor", 2}, {"bone", 1}},
        ["mouthless man"] = {{"ichor", 1}, {"locked_phone", 1}},
        bloom = {{"ichor", 1}, {"pale_eye", 1}},
        bandit = {{"brass", 2}, {"r9x18", 1}, {"pm_pistol", 1}, {"gun_spring", 1}, {"lighter", 1}},
        ["toll man"] = {{"brass", 1}, {"r762n", 1}, {"frame_pm", 1}, {"matches", 1}},
    })[e.who]
    if extra and e.loot then
        for _, x in ipairs(extra) do e.loot[#e.loot + 1] = x end
        e.loot_rolls = (e.loot_rolls or 1) + 1
    end
end

-- Barter values for the new things (TRADE.value; default 1).
for id, v in pairs({
    glass_shard = 1, string = 1, sinew = 2, choir_wire = 6, large_branch = 0, newspaper = 0,
    tin_can = 1, metal_pot = 5, matches = 4, lighter = 8, fire_drill = 1, bark = 0, raw_hide = 3,
    hide = 6, jawhound_pelt = 14, bone = 1, feathers = 1, tarp = 6, foil = 1, screws = 2, mech_parts = 5,
    duct_tape = 4, salt = 3, pale_wax = 5, ichor = 10, pale_eye = 15, chemicals = 8, charcoal = 1,
    gunpowder = 8, brass = 2, lead_scrap = 2, gun_oil = 5, laptop_battery = 8, locked_phone = 8,
    pliers = 6, screwdriver = 5, crowbar = 12, hacksaw = 6, scalpel = 6, kitchen_knife = 8,
    hunting_knife = 18, gunsmith_kit = 30, stone_knife = 2, glass_shiv = 3, broad_spear = 12,
    bone_needle = 3, rag_shoes = 2, foil_poncho = 10, hide_tunic = 12, hide_gloves = 6, hide_pack = 20,
    pelt_coat = 35, travois = 10, hand_cart = 25, lockpicks = 10, can_rattle = 3, tarp_shelter = 10,
    bark_tea = 4, smoked_meat = 9, stitches = 10, tincture = 10, painkillers = 8, sedative = 8,
    rad_purge = 30, flare = 6, choir_cell = 40, salt_circle = 8, black_candle = 20, glow_jar = 15,
    choir_charm = 30, elder_sign = 25,
    book_tailor = 10, book_field = 10, book_surgeon = 14, book_radio = 14, book_lab = 20,
    book_gunsmith = 25, book_hymnal = 30, cassette_player = 15, blank_tape = 1, usb_drive = 15,
    tape_cook = 6, tape_medic = 6, tape_gun = 6, tape_choir = 6, tape_lab = 6, tape_tinker = 6,
    pm_pistol = 60, nagant = 65, tokarev = 75, inst_sidearm = 100, marsh_revolver = 120,
    bow = 15, sling = 3, arrow = 2, r9x18 = 4, r762n = 4, r762t = 5, r38 = 8,
    frame_pm = 15, frame_nagant = 15, frame_tt = 18, frame_inst = 30, gun_slide = 8, gun_barrel = 10,
    gun_spring = 5, firing_pin = 6, magazine = 6, cylinder = 10,
}) do TRADE.value[id] = v end
for _, st in ipairs({{"matches", 2}, {"string", 3}, {"r9x18", 4}, {"book_surgeon", 1}}) do
    TRADE.stock[#TRADE.stock + 1] = st
end
for _, id in ipairs({"matches", "r9x18", "brass"}) do TRADE.restock[#TRADE.restock + 1] = id end
do
local ped = TRADE.people.peddler
for _, st in ipairs({{"cassette_player", 1}, {"tape_lab", 1}, {"usb_drive", 1}, {"gun_barrel", 1},
                     {"r762n", 3}}) do ped.stock[#ped.stock + 1] = st end
for _, id in ipairs({"brass", "screws", "chemicals", "firing_pin", "tape_cook"}) do
    ped.restock[#ped.restock + 1] = id
end
local ferry = TRADE.people.ferry
for _, st in ipairs({{"bark", 3}, {"metal_pot", 1}, {"salt", 2}, {"book_field", 1}}) do
    ferry.stock[#ferry.stock + 1] = st
end
end
-- one Marsh Revolver lies somewhere in each world (a relic: never made)
TECH.world_items[#TECH.world_items + 1] = "marsh_revolver"
