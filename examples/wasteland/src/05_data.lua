-- ---------------------------------------------------------------------
-- Tunables
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
             S = 115, T = 116, W = 119}

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
    weather = {{"Clear", 40}, {"Overcast", 30}, {"Rain", 20}, {"Cold snap", 10}},
    need = {Clear = 0, Overcast = 1, Rain = 3, ["Cold snap"] = 5},
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
    fields = 7, min_dist = 4, dose = {2, 5, 12}, decay = 0.5, max = 100,
    level_name = {[0] = "clean", "low", "high", "deadly"},
    stages = {{at = 25, name = "Irradiated", hurt = 0, tire = 1},
              {at = 50, name = "Rad sick", hurt = 1, tire = 2},
              {at = 80, name = "Rad poisoned", hurt = 3, tire = 3}},
    artifact_find = 20,   -- % a search on a level 2+ hex also turns up an artifact
    bolts_bonus = 2,      -- extra throws in the bolts puzzle while you carry bolts
    world_items = {"geiger", "gasmask", "antirad", "antirad", "bolts"},   -- dropped once each
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
    thirst_hurt = 2, hunger_hurt = 1,
}

local BACKPACK_CAP = 16      -- most bag cells any build can have (the layout's limit)
local POCKET_CELLS = 4       -- bag cells with nothing worn on your back

-- Also the cursor order on the paperdoll: top of the body to the bottom.
local EQUIP_SLOTS = {
    "head", "ears", "eyes", "neck", "back", "jacket", "shirt",
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
                    rad_armor = 0.5, desc = "Worn: halves radiation",
                    wear = {{"head", 125, 139, "BLACK", 0, 10}}},
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
    antirad      = {name = "Anti-Rad",     slot = nil, consumable = {rads = -50, thirst = -5},
                    desc = "E: -50 rads"},
    vodka        = {name = "Vodka",        slot = nil, consumable = {rads = -20, thirst = -10, rest = -10},
                    desc = "E: -20 rads, dulls you"},
    geiger       = {name = "Geiger Counter", slot = nil, consumable = nil,
                    desc = "Carry it: reads radiation"},
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
    -- crafting materials and crafted goods (see RECIPES)
    stick        = {name = "Stick",        slot = nil, consumable = nil, desc = "For crafting"},
    rope         = {name = "Rope",         slot = nil, consumable = nil, desc = "For crafting"},
    torch        = {name = "Torch",        slot = nil, consumable = nil,
                    desc = "Hold it: light in the dark"},
    bandage      = {name = "Bandage",      slot = nil, consumable = nil,
                    desc = "E: stop bleeding, +15 HP"},
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
    plains = {{"nothing", 8}, {"rock", 3}, {"cloth_scrap", 4}, {"canned_beans", 3},
              {"water_bottle", 3}, {"cap", 1}, {"sunglasses", 1}, {"gloves", 1},
              {"satchel", 1}, {"pipe", 1}, {"knife", 1}, {"stick", 2},
              {"scrawled_notes", 1}, {"bolts", 1}, {"vodka", 1}, {"empty_bottle", 2}},
    forest = {{"nothing", 7}, {"berries", 6}, {"cloth_scrap", 2}, {"water_bottle", 2},
              {"scarf", 1}, {"earmuffs", 1}, {"gloves", 1}, {"spear", 1}, {"stick", 7}},
    -- ruins: what's left in houses and cars
    ruins  = {{"nothing", 8}, {"canned_beans", 4}, {"water_bottle", 3}, {"cloth_scrap", 4},
              {"scrawled_notes", 3}, {"rope", 1}, {"knife", 1}, {"pipe", 1}, {"stick", 1},
              {"jacket", 1}, {"backpack", 1}, {"antirad", 2}, {"vodka", 2}, {"bolts", 2},
              {"geiger", 1}, {"gasmask", 1}, {"empty_bottle", 2}},
    ford   = {{"nothing", 12}, {"rock", 4}, {"stick", 2}, {"water_bottle", 1}},
    hills  = {{"nothing", 9}, {"rock", 6}, {"water_bottle", 2}, {"canned_beans", 1},
              {"jacket", 1}, {"bracers", 1}, {"boots", 1}, {"knife", 1}, {"stick", 1},
              {"scrawled_notes", 1}, {"antirad", 1}},
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
    {id = "rope", name = "Rope", inputs = {cloth_scrap = 3}, hours = 1, out = {"rope", 1}},
    {id = "spear", name = "Spear", inputs = {stick = 1, rope = 1}, tools = {"knife"},
     hours = 2, out = {"spear", 1}},
    {id = "club", name = "Stone Club", inputs = {stick = 1, rock = 1, rope = 1}, hours = 2,
     out = {"stone_club", 1}},
}
RECIPES.campfire_hours = 12   -- a fire burns this long after it's built

-- Worn gear that is scattered around the map (the starting clothes aren't).
local WORLD_WEARABLES = {"cap", "gloves", "earmuffs", "sunglasses", "scarf",
                         "jacket", "bracers", "satchel"}

-- ---------------------------------------------------------------------
-- Encounters: rolled after each move. A fight is a series of choices at a
-- range (far -> near -> close); every choice is a dice roll against an
-- attribute, then the other side acts.
-- ---------------------------------------------------------------------

local ENCOUNTER_CHANCE = {plains = 10, forest = 15, hills = 12, ruins = 14, ford = 8}   -- % per move onto it
local ENCOUNTER_COOLDOWN = 2   -- moves after an encounter before another can happen
local ENCOUNTER_KINDS = {{"animal", 40}, {"mutant", 25}, {"anomaly", 20},
                         {"bandit", 12}, {"helper", 3}}
local RANGE_NAME = {far = "Far", near = "Near", close = "Close"}
local CLOSER = {far = "near", near = "close"}
local FARTHER = {close = "near", near = "far"}
local FISTS = {dmg = 4, reach = "close"}
local PLAYER_HIT = 55          -- % to hit, +8 per Speed over 3
local WATCH_AIM = 15           -- extra % on your next hit after a good look
local THROW_HIT = 50           -- % to hit with a throw, +8 per Perception over 3
local WATCH_CHANCE = 60        -- % to read the enemy, +10 per Perception over 3
local HIDE_CHANCE = 35         -- % at Far, +10 per Perception over 3, -10 vs animals
local FLEE_CHANCE = {far = 70, near = 50, close = 30}   -- +10 per Speed over the enemy's
local ADVANCE_CHANCE = 60      -- % an enemy closes in per turn, +10 per speed over yours
local ENEMY_DODGE = 5          -- enemy hit % lost per point of your Speed over 3
local WOUND_DAMAGE = 12        -- one enemy hit this hard leaves a wound
local ENEMY_BLEED_DMG = 3      -- per turn while an enemy bleeds
local ENEMY_FLEE_CHANCE = 30   -- % per turn a beaten enemy (hp <= flees_at) runs

-- kind: animal / mutant (hostile, can't be reasoned with), bandit (demands
-- food first), helper (never fights), anomaly (step 3). hp, dmg {lo, hi},
-- hit %, speed (1-6 like your Speed), bleed % per hit, flees_at (hp), start
-- range, loot {item, weight} rolled loot_rolls times, who = how the log and
-- the fight text name it.
-- art = its portrait in PORTRAIT_DATA (tools/paint_portraits.py paints them).
local ENCOUNTERS = {
    {kind = "animal", name = "Jawhound", art = "jawhound", who = "jawhound",
     intro = "A dog stands in the scrub, but wrong: eyes crowd its flanks and "
          .. "back, all of them open, and wet tendrils lift and sway above it. "
          .. "Its mouth splits back past the ears. Every eye is on you.",
     hp = 30, dmg = {6, 12}, hit = 60, speed = 4, bleed = 30, flees_at = 8, start = "far",
     loot = {{"strange_meat", 3}, {"nothing", 1}}, loot_rolls = 1},
    {kind = "animal", name = "Skinless Boar", art = "boar", who = "boar",
     intro = "Something big roots in the dirt, wet and red all over: a boar with "
          .. "no hide, only muscle and gristle shining in the light. It smells you "
          .. "and lifts its head.",
     hp = 45, dmg = {8, 16}, hit = 50, speed = 3, bleed = 10, flees_at = 10, start = "far",
     loot = {{"strange_meat", 1}}, loot_rolls = 2},
    {kind = "animal", name = "Knotted Crows", art = "crows", who = "crow-knot",
     intro = "What you took for a bush is a mass of crows grown together at the "
          .. "wings. One body, dozens of heads, all of them turning toward you at once.",
     hp = 20, dmg = {3, 8}, hit = 70, speed = 5, bleed = 20, flees_at = 5, start = "near",
     loot = {{"strange_meat", 1}, {"nothing", 2}}, loot_rolls = 1},
    {kind = "animal", name = "Crawling Stag", art = "stag", who = "stag",
     intro = "A stag picks its way toward you, flayed to the ribs and dripping. "
          .. "Eyes crowd its neck, all watching. Its antlers end in hands that open "
          .. "and close, and its mouth is full of teeth.",
     hp = 40, dmg = {8, 18}, hit = 45, speed = 3, bleed = 15, flees_at = 10, start = "far",
     loot = {{"strange_meat", 2}, {"nothing", 1}}, loot_rolls = 2},
    {kind = "mutant", name = "The Fused", art = "fused", who = "fused pair",
     intro = "Two people walk as one, joined at the ribs by a bridge of bare bone "
          .. "that creaks when they breathe. They are whispering to each other "
          .. "about you. They agree on something, and turn.",
     talk = "Both mouths answer at once, in words that aren't words.",
     hp = 50, dmg = {8, 14}, hit = 50, speed = 2, bleed = 10, start = "far",
     loot = {{"cloth_scrap", 3}, {"canned_beans", 1}, {"nothing", 2}}, loot_rolls = 2},
    {kind = "mutant", name = "Mouthless Man", art = "mouthless", who = "mouthless man",
     intro = "A man in a rotted raincoat. Where his mouth should be the skin has "
          .. "healed over smooth. He breathes through wet slits in his neck, faster "
          .. "now that he has seen you.",
     talk = "He tries to answer. The slits in his neck flutter uselessly.",
     hp = 35, dmg = {6, 12}, hit = 60, speed = 4, bleed = 15, start = "far",
     loot = {{"knife", 1}, {"cloth_scrap", 2}, {"nothing", 2}}, loot_rolls = 1},
    {kind = "mutant", name = "The Bloom", art = "bloom", who = "bloom",
     intro = "A woman stands in the grass, covered head to chest in soft pink "
          .. "growths that swell and shrink as she breathes. She smiles at you "
          .. "through them, then steps closer far too quickly.",
     talk = "'Stay,' she says, from somewhere inside the growths. 'Grow with us.'",
     hp = 40, dmg = {5, 10}, hit = 65, speed = 2, bleed = 0, start = "near",
     loot = {{"berries", 2}, {"water_bottle", 1}, {"nothing", 2}}, loot_rolls = 1},
    {kind = "bandit", name = "Road Bandits", art = "bandits", who = "bandit",
     intro = "Two figures step out from behind a wrecked car, one holding a knife "
          .. "low. 'Easy,' says the taller one. 'Nobody has to get hurt. That part "
          .. "is up to you.'",
     demand = "'Food. Hand some over and walk away.'",
     hp = 35, dmg = {6, 12}, hit = 55, speed = 3, bleed = 25, flees_at = 8, start = "near",
     loot = {{"knife", 2}, {"canned_beans", 3}, {"water_bottle", 3}, {"jacket", 1},
             {"cloth_scrap", 2}}, loot_rolls = 2},
    {kind = "bandit", name = "Toll Man", art = "tollman", who = "toll man",
     intro = "A thin man in a welding mask blocks the path, tapping a lead pipe "
          .. "against his leg. 'Toll road,' he says. 'Pay up or bleed.'",
     demand = "'Something to eat. That's the toll.'",
     hp = 30, dmg = {7, 14}, hit = 55, speed = 3, bleed = 5, flees_at = 6, start = "near",
     loot = {{"pipe", 3}, {"canned_beans", 2}, {"sunglasses", 1}}, loot_rolls = 2},
    {kind = "helper", name = "Old Medic", art = "medic", who = "medic", help = "medic",
     intro = "An old woman with a red cross painted on her pack waves you over. Her "
          .. "eyes are clear and her hands are steady. 'You look like you could use "
          .. "some help.'",
     start = "near"},
    {kind = "helper", name = "Wanderer", art = "wanderer", who = "wanderer", help = "wanderer",
     intro = "A man with a walking stick sits by a small fire and raises a hand. No "
          .. "weapon in sight. 'Sit a minute. I don't bite. Not like the rest of "
          .. "them out there.'",
     start = "near"},
}
-- anomalies: no fight. Investigate opens a random puzzle; finishing it has
-- ARTIFACT_CHANCE of leaving an artifact, failing it hurts in odd ways.
local ANOMALIES = {
    {kind = "anomaly", name = "The Humming Hollow", art = "hollow", who = "humming hollow",
     intro = "The grass in this dip lies flat in a perfect spiral, and the air above "
          .. "it hums at a pitch you feel in your teeth. A crow lands at the edge and "
          .. "is folded into nothing without a sound."},
    {kind = "anomaly", name = "The Drowned Bell", art = "bell", who = "drowned bell",
     intro = "A bell tolls somewhere beneath your feet, though there is no church for "
          .. "miles. With every stroke the ground ripples like water, and something "
          .. "far below answers it."},
    {kind = "anomaly", name = "Wrong Stars", art = "stars", who = "wrong stars",
     intro = "At midday a patch of sky above you goes black and fills with stars in "
          .. "shapes no one has named. You have the strong feeling that something up "
          .. "there has noticed you looking."},
    {kind = "anomaly", name = "The Stillness", art = "stillness", who = "stillness",
     intro = "Ahead, birds hang motionless in mid-flight and dust floats unmoving in "
          .. "the light. When you reach toward it, every sound stops, even your own "
          .. "heartbeat."},
    {kind = "anomaly", name = "The Door in the Field", art = "door", who = "door",
     intro = "A door frame stands alone in the field, no walls around it. Through it "
          .. "you see this same field, but at night, and someone standing in it, "
          .. "waiting for you."},
}
for _, a in ipairs(ANOMALIES) do ENCOUNTERS[#ENCOUNTERS + 1] = a end
local ARTIFACT_CHANCE = 25     -- % after a finished puzzle, +5 per Perception over 3
local BOLT_N, BOLT_HAZARDS = 5, 6               -- grid side, deadly cells
local BOLT_START, BOLT_GOAL = BOLT_N * (BOLT_N - 1) + 3, 3   -- bottom and top middle
local BOLTS = 3                -- bolts to throw, +1 per Perception over 3 (min 1)
local SEQ_LENGTHS = {3, 4, 5}  -- sequence puzzle rounds
local RUNE_N, RUNE_SCRAMBLE = 5, 3
local RUNE_MOVES = 6           -- presses allowed, +1 per Perception over 3 (min RUNE_SCRAMBLE)

local ENCOUNTERS_BY_KIND = {}
for _, e in ipairs(ENCOUNTERS) do
    ENCOUNTERS_BY_KIND[e.kind] = ENCOUNTERS_BY_KIND[e.kind] or {}
    table.insert(ENCOUNTERS_BY_KIND[e.kind], e)
end

