-- ---------------------------------------------------------------------
-- Tunables: the map, keys, terrain, time and weather, and the numbers
-- for each system (radiation, survival, trade, Karl, dog, tech, base,
-- quests, night). Items are in 06, encounters in 07.
-- ---------------------------------------------------------------------

local GRID_RADIUS = 12       -- 469 hexes; the map screen follows you
local HEX_SIZE = 16          -- center-to-corner, in pixels
local BASE_MAX_MP = 2
local BASE_SIGHT = 2
local REST_HOURS = 4
local SCAVENGE_HOURS = 1      -- also costs this many MP
local SCAVENGE_TRIES = 3      -- searches per tile before it's picked clean
local SCAVENGE_ROLLS = 2      -- loot-table rolls per search
local MAX_HEALTH = 100
local BLEED_PER_HOUR = 4      -- HP lost per hour while bleeding (awake or resting)
local REST_HEAL_PER_HOUR = 3  -- HP back per hour of rest (not while bleeding), at Endurance 3
local WOUND_REST_HOURS = 24   -- hours of rest before a wound stops costing 1 MP
-- gfx.getch timeout. The screen is only redrawn after a key was handled, so
-- idle wakeups just check should_exit(); this only bounds how quickly a
-- quit request from the OS is noticed.
local POLL_MS = 250

-- Key codes as one table, not a local each: the bundled wasteland.lua is a
-- single Lua chunk and a chunk may have at most 200 local variables.
-- SolarOS sends Enter as '\n' (LF); CR is kept just in case.
local KEY = {SPACE = 32, ENTER = 13, LF = 10, ESC = 27,
             A = 97, C = 99, D = 100, E = 101, F = 102, I = 105, Q = 113,
             S = 115, T = 116, W = 119, H = 104, V = 118, G = 103, M = 109, J = 106, R = 114, O = 111, L = 108}

-- Terrain: id -> {name, cost (MP + hours), passable, shade}
-- shade is one of gfx.WHITE / gfx.LIGHT / gfx.DARK / gfx.BLACK, used as
-- the tile's fill when it's currently visible. ink is the glyph color that
-- contrasts with that fill (white on the dark tiles, black on the light ones).
local TERRAIN = {
    plains = {name = "Plains", cost = 1, passable = true,  shade = "WHITE", ink = "BLACK"},
    forest = {name = "Forest", cost = 2, passable = true,  shade = "LIGHT", ink = "BLACK"},
    hills  = {name = "Hills",  cost = 2, passable = true,  shade = "DARK",  ink = "WHITE"},
    water  = {name = "Water",  cost = 0, passable = false, shade = "BLACK", ink = "WHITE"},
    -- placed by world generation, not rolled: ruins (a town and scattered
    -- wrecks) and fords (where a river can be waded)
    ruins  = {name = "Ruins",  cost = 1, passable = true,  shade = "WHITE", ink = "BLACK"},
    ford   = {name = "Ford",   cost = 2, passable = true,  shade = "LIGHT", ink = "BLACK"},
}
local TERRAIN_WEIGHTS = {
    {"plains", 45}, {"forest", 30}, {"hills", 18}, {"water", 5},
}

-- Time, weather and cold, as one table (the bundle is one Lua chunk with a
-- 200-local limit). The clock starts at start_hour on day 1; night runs
-- from night_from to night_to. Weather is rolled per block of hours from
-- the world seed (so it needs no saved state). Cold: you need at least
-- need[weather] (+ night) warmth from worn clothes, or a fire, or you get
-- cold: rest drains faster and after cold_grace hours you lose health.
local WORLD = {
    start_hour = 8, night_from = 20, night_to = 6, weather_block = 6,
    -- weather is rolled per block from the season's own weights (seasons)
    need = {Clear = 0, Overcast = 1, Rain = 3, ["Cold snap"] = 5, Fog = 1, Storm = 4, Snow = 3},
    -- seasons of season_days each, starting in late Autumn on day 1.
    -- need: extra warmth all season; food: share of food in searches;
    -- thirst: extra thirst drain per awake hour (summer heat)
    season_days = 10,
    seasons = {
        {name = "Autumn", short = "Aut", need = 0, food = 1.25, thirst = 0,
         weather = {{"Clear", 35}, {"Overcast", 30}, {"Rain", 18}, {"Fog", 12}, {"Storm", 5}}},
        {name = "Winter", short = "Win", need = 1, food = 0.9, thirst = 0,
         weather = {{"Clear", 34}, {"Overcast", 24}, {"Snow", 18}, {"Fog", 12}, {"Cold snap", 12}}},
        {name = "Spring", short = "Spr", need = 0, food = 1, thirst = 0,
         weather = {{"Clear", 32}, {"Overcast", 20}, {"Rain", 26}, {"Fog", 17}, {"Storm", 5}}},
        {name = "Summer", short = "Sum", need = -1, food = 1, thirst = 0.4,
         weather = {{"Clear", 52}, {"Overcast", 13}, {"Rain", 10}, {"Fog", 8}, {"Storm", 17}}},
    },
    -- a storm in the open (open terrain, no bedroll camp): rest each hour, and
    -- HP each hour after `grace` hours of it; nothing else moves in it
    storm = {open = {plains = true, ford = true}, rest = 4, grace = 2, hurt = 3, encounters = 0.5},
    calm_start = 12,                   -- no storm or fog in the first hours of a run
    -- clothes wear out (src/37_world_time.lua): condition 100 -> 0 (torn: no
    -- warmth, half the pockets). day: lost per 24 h worn; hit: one piece, per
    -- enemy hit; storm: every piece, per exposed hour; rag: x for makeshift
    -- clothes; mend: what "Patch clothes" (1 cloth) puts back
    wear = {day = 2, hit = 4, storm = 1, rag = 2, mend = 50},
    fog_hide = 15,                     -- % on Hide in fog (encounters start near)
    night_need = 2, cold_rest_drain = 3, cold_grace = 2, cold_hurt = 2,
    night_encounters = 1.5, fire_rest_bonus = 0.5,
    rivers = 2, town_ruins = 9, lone_ruins = 8,
}

-- Radiation, S.T.A.L.K.E.R. style: world generation leaves `fields` hot
-- spots (at least min_dist from the start), level 3 at the center falling
-- off by one per hex out to a radius of 1-2, with an artifact at each
-- center. Every hour on a hot hex adds dose[level] rads (x the worn gear's
-- rad_armor); away from them rads fade by `decay` an hour. Enough rads make
-- you sick (stages: HP and rest lost per hour). A carried Geiger counter
-- shows the level around you and marks hot hexes on the map.
local RAD = {
    fields = 5, min_dist = 4, dose = {1, 4, 10}, decay = 1, max = 100,
    level_name = {[0] = "clean", "low", "high", "deadly"},
    -- name: what a Geiger owner knows it is; feel/onset: all you know without one
    stages = {{at = 30, name = "Irradiated", hurt = 0, tire = 1, feel = "Unwell",
               onset = "You feel weak and washed out, and you don't know why."},
              {at = 60, name = "Rad sick", hurt = 1, tire = 2, feel = "Nauseous",
               onset = "Nausea, and your gums bleed. Something is making you sick."},
              {at = 85, name = "Rad poisoned", hurt = 2, tire = 3, feel = "Wasting",
               onset = "Your hair comes out in clumps. You're getting worse."}},
    -- what a dose feels like, by level, when nothing tells you what it is
    feel = {"You feel a little off here.", "Your skin prickles. A metal taste.",
            "A wave of nausea. Something here is wrong."},
    artifact_find = 20,   -- % a search on a level 2+ hex also turns up an artifact
    bolts_bonus = 2,      -- extra throws in the bolts puzzle while you carry bolts
    world_items = {"geiger", "gasmask", "antirad", "antirad", "bolts"},   -- dropped once each
    -- Emissions (blowouts): the first comes `first` hours in, then every
    -- every[1]-every[2] hours. `warn` hours before, the sky changes; for
    -- `hours` it rages: off `shelter` terrain you lose `hurt` HP and gain
    -- `rads` rads (spread over the hours). After it, every field center
    -- without an artifact grows a new one.
    emission = {first = 50, every = {60, 110}, warn = 10, hours = 2, hurt = 20, rads = 20,
                shelter = {ruins = true, hills = true}},   -- houses, and caves in the hills
    -- Stashes some scrawled notes point to: `items` picks from `loot`.
    stash = {items = 3, near = 4, far = 9,
             loot = {"antirad", "canned_beans", "water_bottle", "bandage", "jerky", "knife",
                     "leather_belt", "scrap_metal", "vodka", "rope", "empty_bottle"}},
}

-- Water and the survival loop. Bottles are containers: drinking leaves an
-- Empty Bottle, E on the map by a river (or on a ford) fills them with Dirty
-- Water (or, with none, you drink straight from it), resting in the rain
-- fills them clean, and boiling at a fire (a recipe) cleans dirty water.
-- Items with `sick` can make you ill (that % chance): while sick you lose
-- `sick` per hour. `perish` items go bad: each carried unit has a
-- 1-in-hours chance per hour of turning into `into`. At 0 thirst or
-- hunger you lose HP every hour.
local SURVIVE = {
    sick_hours = {12, 24},
    sick = {thirst = 3, hunger = 2, hurt = 1, rest = 1},
    drink_here = 30, drink_hours = 1,
    clot_hours = 8,   -- bleeding stops on its own after this many hours
    thirst_hurt = 2, hunger_hurt = 1,
}

-- Traders and the way out. A trader keeps a stall on the town's center hex
-- (sites.trader); the Checkpoint (sites.checkpoint) sits on the far edge of
-- the map, the only way out of the Zone. Barter: every item is worth
-- value[item] (default 1); the trader gives full value for what you bring
-- and asks markup x the value of what you take. Stock restocks every
-- restock_hours with a couple of `restock` items.
local TRADE = {
    markup = 1.5, restock_hours = 48, restock_n = 2,
    value = {
        canned_beans = 6, water_bottle = 5, dirty_water = 2, empty_bottle = 2, berries = 2,
        strange_meat = 3, cooked_meat = 7, rotten_meat = 0, bandage = 6, cloth_scrap = 1,
        rope = 4, torch = 3, stick = 0, rock = 0, scrawled_notes = 5,
        knife = 12, pipe = 10, spear = 8, stone_club = 8,
        antirad = 15, vodka = 8, geiger = 30, gasmask = 25, bolts = 1,
        jacket = 20, backpack = 25, satchel = 12, boots = 8, gloves = 5, cap = 3,
        earmuffs = 4, sunglasses = 4, scarf = 4, bracers = 5, tshirt = 2, jeans = 3,
        rag_shirt = 1, rag_trousers = 1, foot_wraps = 1, rag_hood = 1, hand_wraps = 1, ear_wraps = 1,
        slit_goggles = 1, rag_scarf = 1, patch_coat = 4, scrap_bracers = 2, bindle = 3, sack_pack = 5, rag_mask = 2,
        weeping_stone = 35, drowned_eye = 35, flesh_knot = 35, hollow_star = 35,
        quiet_shell = 35, permit = 80,
        leather_belt = 10, rope_belt = 4, scrap_metal = 3, jerky = 6,
        shiv = 6, machete = 18, spiked_club = 12, pipe_spear = 15, splint = 5,
        fishing_rod = 8, snare = 4, raw_fish = 3, cooked_fish = 6,
        pilk = 7, lucky_lure = 12, karls_waders = 14, karls_hat = 10,
        broken_radio = 15, lora_radio = 60, broken_detector = 12, anomaly_detector = 45,
        broken_headlamp = 6, headlamp = 25, circuit_board = 10, copper_wire = 5,
        battery_cell = 8, antenna = 6, multitool = 20, medkit = 15, lore_page = 2,
    },
    stock = {{"antirad", 3}, {"water_bottle", 4}, {"canned_beans", 4}, {"bandage", 2},
             {"multitool", 1}, {"battery_cell", 1},
             {"vodka", 2}, {"empty_bottle", 3}, {"geiger", 1}, {"gasmask", 1},
             {"knife", 1}, {"permit", 1}},
    restock = {"canned_beans", "water_bottle", "antirad", "bandage", "vodka", "empty_bottle"},
    -- everyone you can trade with: the town's trader (self.trader, the
    -- numbers above), Mother Okun at the Ferry Post (self.ferry_trader) and
    -- the Peddler on his round (self.peddler); src/46_peddler.lua
    people = {
        town = {name = "Trader", markup = 1.5},
        ferry = {name = "Mother Okun", markup = 1.3, restock_hours = 48, restock_n = 2,
                 hello = "'Ferry's not running. Trading is.'",
                 stock = {{"fishing_rod", 1}, {"snare", 2}, {"rope", 3}, {"antirad", 2}, {"raw_fish", 2},
                          {"copper_wire", 1}, {"battery_cell", 1}, {"empty_bottle", 2}},
                 restock = {"snare", "rope", "raw_fish", "antirad", "copper_wire", "empty_bottle"}},
        peddler = {name = "The Peddler", markup = 1.4, restock_hours = 36, restock_n = 2,
                   hello = "'Everything rattles. Everything's for sale.'",
                   stock = {{"battery_cell", 1}, {"jerky", 2}, {"antenna", 1}, {"lore_page", 1},
                            {"broken_headlamp", 1}, {"rope", 1}, {"crayons", 1}, {"rubber_duck", 1}},
                   restock = {"jerky", "battery_cell", "copper_wire", "circuit_board", "lore_page",
                              "bandage", "antenna", "toy_car", "marble", "jingle_bell"}},
    },
    -- the Ferry Post: a little cluster of ruins by the water, far from the town
    ferry = {ruins = 4, min_from_town = 9, min_from_start = 4},
    -- the Peddler's round: route_n stops around the map, stay hours at each
    route_n = 7, stay = 12,
}
-- The guards let you through with a Zone Permit, or for `bribe` artifacts.
local GOAL = {bribe = 3}

-- Hunting and fishing (G on the map). Fishing: by open water or on a ford
-- with a Fishing Rod, fish_hours for a fish_chance % (+5 per Perception over
-- 3) catch. Hunting: elsewhere, hunt_hours of tracking, hunt_chance % (+10
-- per Perception over 3) to find an animal, which you meet already studied
-- (aim bonus). Snares: E sets one on the hex; each hour it has snare_chance
-- [terrain] % to catch, collected when you step back onto it.
local HUNT = {
    fish_hours = 2, fish_chance = 40, hunt_hours = 2, hunt_chance = 45,
    snare_chance = {forest = 5, plains = 3, hills = 3},
    snare_catch = {"strange_meat", 2},
}

-- Karl (K-A-R-L), the riddling fisherman. Only by water (a ford, or next to
-- the river): `chance` % per move onto such a hex, `fish_chance` % per
-- fishing session, never again within `cooldown` hours. Answer his riddle
-- right and he gives you one of `rewards` (worn gear only once).
local KARL = {
    chance = 3, fish_chance = 10, cooldown = 96,
    intro = "A man in rubber waders stands knee-deep in the river, rod bent. "
         .. "Stencilled on his tackle box: KARL. 'Name's Karl. With a K. "
         .. "Answer me a riddle, friend.'",
    riddles = {
        {q = "What has a mouth but never eats, and a bed but never sleeps?",
         a = {"A river", "A fish", "A grave"}},
        {q = "The more you take, the more you leave behind. What am I?",
         a = {"Footsteps", "Fish", "Bolts"}},
        {q = "I have scales but weigh nothing. What am I?",
         a = {"A map", "A fish", "A snake"}},
        {q = "What gets wetter the more it dries?",
         a = {"A towel", "Rain", "A sponge"}},
        {q = "Forward I'm heavy, backward I'm not. What am I?",
         a = {"A ton", "A rock", "A boat"}},
        {q = "I have hooks but catch nothing. What am I?",
         a = {"A coat rack", "A fisherman", "A bandit"}},
    },   -- the first answer is the right one; they're shuffled when asked
    rewards = {"pilk", "pilk", "fishing_rod", "lucky_lure", "karls_waders", "karls_hat"},
}

-- Difficulty, picked on the creator with 1/2/3 (self.difficulty, saved).
-- Multipliers: food = weight of food in search tables, encounter = encounter
-- chance, rad = radiation dose, emission = emission harm, drain = how fast
-- hunger and thirst fall.
local DIFFICULTY = {
    order = {"easy", "normal", "hard"},
    easy   = {name = "Easy", short = "Easy",          food = 2.0, encounter = 0.5, rad = 0.5, emission = 0.5, drain = 0.65},
    normal = {name = "Normal", short = "Normal",        food = 1.4, encounter = 0.85, rad = 1, emission = 1, drain = 0.85},
    hard   = {name = "Zone-Hardened", short = "Hard", food = 1.0, encounter = 1.2, rad = 1.25, emission = 1.25, drain = 1.05},
}

-- A dog companion (src/48_dog.lua). chance: % per move on `terrain` while
-- you have none. tame: % that food wins it over (+meat_bonus for meat).
-- warn_bonus: + % to hide and flee. bite: dmg range, bite_chance % per
-- enemy turn at close range. guard: % it takes a blow meant for you. It
-- eats one item from `eats` every meal_hours; leave_after hungry meals and
-- it goes.
local DOG = {
    chance = 2, terrain = {plains = true, forest = true},
    tame = 60, meat_bonus = 25, hp = 30,
    warn_bonus = 15, bite_chance = 50, bite = {3, 6}, guard = 20,
    meal_hours = 24, leave_after = 3,
    eats = {"rotten_meat", "strange_meat", "raw_fish", "cooked_meat", "cooked_fish", "jerky",
            "canned_beans"},
    intro = "A thin mongrel watches you from the grass, ribs showing, one ear up. "
         .. "It doesn't run. It doesn't come closer either.",
}

-- Broken tech (src/49_tech.lua): very rare devices that scavenged parts and
-- a Multitool can bring back. A repair takes repair_hours and succeeds with
-- base % (+per_point per Perception over 3); a failure burns one part.
-- The LoRa Radio (R on the map) calls helpful voices for a charge each.
local TECH = {
    repairs = {
        {broken = "broken_radio", out = "lora_radio", base = 35,
         parts = {circuit_board = 1, copper_wire = 1, battery_cell = 1, antenna = 1}},
        {broken = "broken_detector", out = "anomaly_detector", base = 45,
         parts = {circuit_board = 1, copper_wire = 1, battery_cell = 1}},
        {broken = "broken_headlamp", out = "headlamp", base = 60,
         parts = {copper_wire = 1, battery_cell = 1}},
    },
    repair_hours = 3, per_point = 8, tool = "multitool",
    world_items = {"broken_radio", "multitool", "lore_page", "lore_page"},   -- dropped once each
    radio_max = 5, radio_start = 3, detector_range = 3, signal_rads = 10,
    channels = {
        {id = "trader", name = "Trader's net", cooldown = 72},
        {id = "anna",   name = "Anna, old medic", cooldown = 72},
        {id = "karl",   name = "Karl, 433 MHz", cooldown = 48},
        {id = "signal", name = "The Signal", cooldown = 24},
    },
}

-- A base (src/51_base.lua): claim a ruin, then build on it. The barrel
-- fills a bottle every barrel_hours (2 in rain) into the stash box.
local BASE = {
    order = {"box", "bedroll", "barrel", "barricade"},
    names = {box = "Stash box", bedroll = "Bedroll", barrel = "Rain barrel", barricade = "Barricade"},
    barrel_hours = 12, barrel_max = 6, bed_rest_bonus = 0.5,
}

-- Quests (src/52_quests.lua): offer = what they say, journal = the reminder.
local QUESTS = {
    fetch = {offer = "'Bring me an artifact. Any kind. I'll make it worth your while.'",
             journal = "bring the trader an artifact.",
             reward = {{"antirad", 2}, {"canned_beans", 3}, {"battery_cell", 1}}},
    den = {offer = "'Something's denned up out there, killing my runners. Clear it.'",
           journal = "clear the den", near = 5, far = 9, hp_mult = 1.5,
           reward = {{"multitool", 1}, {"gasmask", 1}, {"machete", 1}}},
    supply = {offer = "Anna: 'We're out of bandages. Call me when you've two to spare.'",
              journal = "find 2 bandages, then call her.", need = {"bandage", 2},
              reward = {{"medkit", 1}, {"water_bottle", 2}}},
    -- the storyline (src/58_story.lua): what the Signal counts
    story = {pages = 6, signal_calls = 2, min_from_towns = 8,
             shut_base = 45, shut_per_point = 8, fail_rads = 20, retry_hours = 12,
             journal = {quarry = "The pages point to the old quarry, %s. The Institute.",
                        gate = "The Institute's gate at the quarry needs a pass. Karl? Anna?",
                        source = "You have a pass. The Institute gate, %s."},
             intro = "The gate grinds open on a stair going down. At the bottom, a doorway "
                  .. "full of a slow violet light, and a hum you feel in your fillings. The "
                  .. "Signal is not on the radio here. It is in the walls."},
    fish = {offer = "Mother Okun: 'Bring me three fish. The ferry men row badly hungry.'",
            journal = "bring 3 fish to the Ferry Post.", need = 3,
            reward = {{"snare", 2}, {"lucky_lure", 1}}},
    dog = {offer = "Karl: 'Before you go - my old dog ran off. Find her by the water?'",
           journal = "find his dog by the river", near = 4, far = 8},
}

-- Night horrors (src/54_night.lua): chance % per move after dark, halved
-- by light and again by a fire; never at a camp with a bedroll.
local NIGHT = {
    chance = 4, dread_rest = 10, madness_hurt = 15, whisper_rest = 15, follow_hurt = 20,
    light_drives_off = 35,
    horrors = {
        {kind = "horror", horror = "long_man", name = "The Long Man", art = "long_man",
         who = "long man", start = "far",
         intro = "Someone stands at the edge of your light. Too tall. Its arms hang past its "
              .. "knees. It doesn't move, and you can't tell which way it's facing.", speed = 3},
        {kind = "beast", name = "The Crawler", art = "crawler", who = "crawler", dark = true,
         intro = "Something low and wide moves in the grass, too many legs, too many eyes "
              .. "catching your light. It clicks. It's coming.",
         hp = 40, dmg = {6, 12}, hit = 55, speed = 4, bleed = 25, start = "near",
         loot = {{"strange_meat", 2}, {"nothing", 1}}, loot_rolls = 1},
        {kind = "horror", horror = "whisper", name = "The Whisperers", art = "whisper",
         who = "whisperers", start = "far",
         intro = "From the black water, voices. They say your name, then your mother's. "
              .. "Pale faces turn just under the surface.", speed = 3},
    },
}

-- The Little Ones (src/57_little.lua): the Zone's children, grown small,
-- grey and grinning. Never hostile. Trinkets left at their cairns befriend
-- them: at join_at gifts a troupe follows you from a warren (1 more per
-- per_extra gifts, up to max). Their mood falls 1 per decay_hours without
-- a gift; at 0 they go home. Every act_every hours one of them does
-- something: find (% a found item), mischief (% hides one of your things,
-- back_chance % it turns up again later), keep_awake (% at night). In
-- fights they pelt (pebble %, 1-3 dmg each) and help you run.
local LITTLE = {
    trinkets = {"earring", "toy_car", "crayons", "rubber_duck", "doll_head", "marble", "toy_dino",
                "hair_clip", "button", "bottle_cap", "tin_whistle", "jingle_bell"},
    warrens = 3, cairns = 7, cairn_near = 2, cairn_far = 5, min_from_start = 4,
    join_at = 3, per_extra = 3, max = 3, mood_start = 6, mood_max = 10, mood_per_gift = 2,
    decay_hours = 48, act_every = 6,
    find = 40, find_trinket = 25, mischief = 20, keep_awake = 15, awake_rest = 8,
    back_chance = 60, back_hours = {6, 18},
    keep = {permit = true, lora_radio = true, medkit = true, bandage = true, splint = true,   -- (never taken)
            multitool = true, geiger = true, anomaly_detector = true, fishing_rod = true, snare = true},
    pebble = 40, pebble_dmg = {1, 3}, flee_bonus = 10, horror_run = 15,
    intro = "Small grey faces in the grass, too many teeth in their grins. Children, once. "
         .. "They giggle and edge closer, eyes on your bag.",
}

-- Skills that grow with use (src/55_skills.lua). levels = XP needed for
-- levels 1-5; xp = what each action earns (catches and found trails, not
-- empty casts or tracks); bonus = per level: % fewer duds
-- (scav), % catch and find (fish), % to hit (fight), % repair (tinker).
-- Tinker at fast_craft or more takes an hour off crafting (min 1).
local SKILLS = {
    order = {"scav", "fish", "fight", "tinker"},
    name = {scav = "Scav", fish = "Fish", fight = "Fight", tinker = "Tinker"},
    long = {scav = "Scavenging", fish = "Fishing and hunting", fight = "Fighting",
            tinker = "Tinkering"},
    levels = {10, 25, 50, 90, 150},
    xp = {search = 1, find = 1, catch = 3, hunt = 2, hit = 1, kill = 3,
          craft = 1, repair = 2, repaired = 3},
    bonus = {scav = 5, fish = 4, fight = 3, tinker = 5},
    fast_craft = 3,
}
