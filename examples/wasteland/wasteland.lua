--[[
Wasteland Survivor - a NEO Scavenger-style hex survival game for SolarOS.

Written for a small monochrome landscape display (400x300, the Waveshare
RLCD's logical size under SolarOS) with no polygon-fill primitive - hex
tiles are drawn as outlines (gfx.line x6) with an optional gfx.fill_rect
bounding-box wash underneath for shading, rather than the isometric 3D
block look used in the desktop/Pi version of this game. That's a
deliberate simplification for this hardware, not a missing feature.

Controls:
  Arrows / WASD   - move on the map screen; on the inventory screen any
                    direction steps the cursor (ground, body top-down, bag)
  Space           - rest (map screen)
  F               - scavenge the tile you're on (1 MP, 1 hour; finds go on
                    the ground here - open the inventory to pick them up)
  Enter / Space   - inventory: pick up the item under the cursor, then press
                    again on a ground cell, bag cell or body slot to move it
  E               - inventory: use the item under the cursor - eat/drink one,
                    wear it, hold it in a free hand, or take it off; on a
                    Cloth Scrap while bleeding: bandage the wound
  I             - toggle inventory screen
  Q / ESC         - quit

A new game opens on the character creator: Up/Down pick a row, Left/Right
change an attribute, Space toggles a trait, Enter starts. You get 5 trait
points; negative traits give more. Health 0 ends the run (death screen,
Enter makes a new survivor).

This is a single self-contained script, matching the SolarOS Playground
convention (see the bundled Snake example) - no extra require()s beyond
the built-in `solaros` module.
]]

local solaros = require("solaros")
local gfx = solaros.gfx
local audio = solaros.audio

-- ---------------------------------------------------------------------
-- Tunables
-- ---------------------------------------------------------------------

local GRID_RADIUS = 4
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

local KEY_SPACE = 32
local KEY_ENTER = 13          -- SolarOS sends Enter as '\n' (KEY_LF); CR kept just in case
local KEY_LF = 10
local KEY_ESC = 27
local KEY_A, KEY_D, KEY_S, KEY_W = 97, 100, 115, 119
local KEY_E, KEY_F, KEY_I, KEY_Q = 101, 102, 105, 113

-- Terrain: id -> {name, cost (MP + hours), passable, shade}
-- shade is one of gfx.WHITE / gfx.LIGHT / gfx.DARK / gfx.BLACK, used as
-- the tile's fill when it's currently visible. ink is the glyph color that
-- contrasts with that fill (white on the dark tiles, black on the light ones).
local TERRAIN = {
    plains = {name = "Plains", cost = 1, passable = true,  shade = "WHITE", ink = "BLACK"},
    forest = {name = "Forest", cost = 2, passable = true,  shade = "LIGHT", ink = "BLACK"},
    hills  = {name = "Hills",  cost = 2, passable = true,  shade = "DARK",  ink = "WHITE"},
    water  = {name = "Water",  cost = 0, passable = false, shade = "BLACK", ink = "WHITE"},
}
local TERRAIN_WEIGHTS = {
    {"plains", 45}, {"forest", 30}, {"hills", 18}, {"water", 7},
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
    tshirt       = {name = "T-Shirt",      slot = "shirt", consumable = nil,
                    wear = {{"torso", 146, 227, "DARK"}, {"arms", 150, 184, "DARK"}}},
    jeans        = {name = "Jeans",        slot = "pants", consumable = nil,
                    wear = {{"torso", 214, 227, "DARK"}, {"legs", 224, 279, "DARK"}}},
    boots        = {name = "Boots",        slot = "feet",  consumable = nil,
                    wear = {{"legs", 272, 290, "BLACK"}}},
    cap          = {name = "Cap",          slot = "head",  consumable = nil,
                    wear = {{"head", 116, 126, "BLACK"}}},
    gloves       = {name = "Gloves",       slot = "hands", consumable = nil,
                    wear = {{"arms", 234, 252, "BLACK"}}},
    -- optional 5th/6th wear fields: only paint where the distance from the
    -- body's center line is between them (authored units), e.g. just the
    -- sides of the head for earmuffs, or an open jacket front
    earmuffs     = {name = "Earmuffs",     slot = "ears",  consumable = nil,
                    wear = {{"head", 118, 122, "BLACK", 0, 12},
                            {"head", 124, 136, "BLACK", 8, 12}}},
    sunglasses   = {name = "Sunglasses",   slot = "eyes",  consumable = nil,
                    wear = {{"head", 127, 131, "BLACK", 1, 9}}},
    scarf        = {name = "Scarf",        slot = "neck",  consumable = nil,
                    wear = {{"torso", 139, 150, "BLACK", 0, 12}}},
    jacket       = {name = "Leather Jacket", slot = "jacket", consumable = nil,
                    wear = {{"torso", 146, 222, "BLACK", 5, 40},
                            {"arms", 150, 232, "BLACK"}}},
    bracers      = {name = "Bracers",      slot = "wrists", consumable = nil,
                    wear = {{"arms", 222, 233, "BLACK"}}},
    -- bags: bag_cells is how many bag cells you get while wearing it
    backpack     = {name = "Backpack",     slot = "back", consumable = nil, bag_cells = 12,
                    wear = {{"torso", 147, 196, "BLACK", 9, 13}}},
    satchel      = {name = "Satchel",      slot = "back", consumable = nil, bag_cells = 8,
                    wear = {{"torso", 147, 210, "BLACK", 12, 15}}},
    canned_beans = {name = "Canned Beans", slot = nil, consumable = {hunger = 40}},
    water_bottle = {name = "Water Bottle", slot = nil, consumable = {thirst = 50}},
    berries      = {name = "Wild Berries", slot = nil, consumable = {hunger = 15, thirst = 5}},
    strange_meat = {name = "Strange Meat", slot = nil, consumable = {hunger = 30, thirst = -5}},
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
}

-- What scavenging can turn up, per terrain: {item, weight}. "nothing" is a
-- dud roll. Plains are old roadside junk, forest is food and cold-weather
-- gear, hills are rock and whatever hikers left behind.
local SCAVENGE_LOOT = {
    plains = {{"nothing", 8}, {"rock", 3}, {"cloth_scrap", 4}, {"canned_beans", 3},
              {"water_bottle", 3}, {"cap", 1}, {"sunglasses", 1}, {"gloves", 1},
              {"satchel", 1}, {"pipe", 1}, {"knife", 1}},
    forest = {{"nothing", 7}, {"berries", 6}, {"cloth_scrap", 2}, {"water_bottle", 2},
              {"scarf", 1}, {"earmuffs", 1}, {"gloves", 1}, {"spear", 1}},
    hills  = {{"nothing", 9}, {"rock", 6}, {"water_bottle", 2}, {"canned_beans", 1},
              {"jacket", 1}, {"bracers", 1}, {"boots", 1}, {"knife", 1}},
}

-- Worn gear that is scattered around the map (the starting clothes aren't).
local WORLD_WEARABLES = {"cap", "gloves", "earmuffs", "sunglasses", "scarf",
                         "jacket", "bracers", "satchel"}

-- ---------------------------------------------------------------------
-- Encounters: rolled after each move. A fight is a series of choices at a
-- range (far -> near -> close); every choice is a dice roll against an
-- attribute, then the other side acts.
-- ---------------------------------------------------------------------

local ENCOUNTER_CHANCE = {plains = 10, forest = 15, hills = 12}   -- % per move onto it
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
local ENCOUNTERS = {
    {kind = "animal", name = "Jawhound", who = "jawhound",
     intro = "A dog stands in the scrub. Its lower jaw has split into three, "
          .. "each ringed with teeth, and all three are working. It hasn't blinked "
          .. "since you saw it.",
     hp = 30, dmg = {6, 12}, hit = 60, speed = 4, bleed = 30, flees_at = 8, start = "far",
     loot = {{"strange_meat", 3}, {"nothing", 1}}, loot_rolls = 1},
    {kind = "animal", name = "Skinless Boar", who = "boar",
     intro = "Something big roots in the dirt, wet and red all over: a boar with "
          .. "no hide, only muscle and gristle shining in the light. It smells you "
          .. "and lifts its head.",
     hp = 45, dmg = {8, 16}, hit = 50, speed = 3, bleed = 10, flees_at = 10, start = "far",
     loot = {{"strange_meat", 1}}, loot_rolls = 2},
    {kind = "animal", name = "Knotted Crows", who = "crow-knot",
     intro = "What you took for a bush is a mass of crows grown together at the "
          .. "wings. One body, dozens of heads, all of them turning toward you at once.",
     hp = 20, dmg = {3, 8}, hit = 70, speed = 5, bleed = 20, flees_at = 5, start = "near",
     loot = {{"strange_meat", 1}, {"nothing", 2}}, loot_rolls = 1},
    {kind = "animal", name = "Crawling Stag", who = "stag",
     intro = "A stag picks its way toward you on seven legs. Its antlers have grown "
          .. "back into its skull, and the eyes beneath them look almost human.",
     hp = 40, dmg = {8, 18}, hit = 45, speed = 3, bleed = 15, flees_at = 10, start = "far",
     loot = {{"strange_meat", 2}, {"nothing", 1}}, loot_rolls = 2},
    {kind = "mutant", name = "The Fused", who = "fused pair",
     intro = "Two people walk as one, joined at the ribs by a bridge of shared skin. "
          .. "They are whispering to each other about you. They agree on something, "
          .. "and turn.",
     talk = "Both mouths answer at once, in words that aren't words.",
     hp = 50, dmg = {8, 14}, hit = 50, speed = 2, bleed = 10, start = "far",
     loot = {{"cloth_scrap", 3}, {"canned_beans", 1}, {"nothing", 2}}, loot_rolls = 2},
    {kind = "mutant", name = "Mouthless Man", who = "mouthless man",
     intro = "A man in a rotted raincoat. Where his mouth should be the skin has "
          .. "healed over smooth. He breathes through wet slits in his neck, faster "
          .. "now that he has seen you.",
     talk = "He tries to answer. The slits in his neck flutter uselessly.",
     hp = 35, dmg = {6, 12}, hit = 60, speed = 4, bleed = 15, start = "far",
     loot = {{"knife", 1}, {"cloth_scrap", 2}, {"nothing", 2}}, loot_rolls = 1},
    {kind = "mutant", name = "The Bloom", who = "bloom",
     intro = "A woman sits in the grass, covered in soft pink growths that swell "
          .. "and shrink as she breathes. She smiles with half a face, then stands "
          .. "up far too quickly.",
     talk = "'Stay,' she says, from somewhere inside the growths. 'Grow with us.'",
     hp = 40, dmg = {5, 10}, hit = 65, speed = 2, bleed = 0, start = "near",
     loot = {{"berries", 2}, {"water_bottle", 1}, {"nothing", 2}}, loot_rolls = 1},
    {kind = "bandit", name = "Road Bandits", who = "bandit",
     intro = "Two figures step out from behind a wrecked car, one holding a knife "
          .. "low. 'Easy,' says the taller one. 'Nobody has to get hurt. That part "
          .. "is up to you.'",
     demand = "'Food. Hand some over and walk away.'",
     hp = 35, dmg = {6, 12}, hit = 55, speed = 3, bleed = 25, flees_at = 8, start = "near",
     loot = {{"knife", 2}, {"canned_beans", 3}, {"water_bottle", 3}, {"jacket", 1},
             {"cloth_scrap", 2}}, loot_rolls = 2},
    {kind = "bandit", name = "Toll Man", who = "toll man",
     intro = "A thin man in a welding mask blocks the path, tapping a lead pipe "
          .. "against his leg. 'Toll road,' he says. 'Pay up or bleed.'",
     demand = "'Something to eat. That's the toll.'",
     hp = 30, dmg = {7, 14}, hit = 55, speed = 3, bleed = 5, flees_at = 6, start = "near",
     loot = {{"pipe", 3}, {"canned_beans", 2}, {"sunglasses", 1}}, loot_rolls = 2},
    {kind = "helper", name = "Old Medic", who = "medic", help = "medic",
     intro = "An old woman with a red cross painted on her pack waves you over. Her "
          .. "eyes are clear and her hands are steady. 'You look like you could use "
          .. "some help.'",
     start = "near"},
    {kind = "helper", name = "Wanderer", who = "wanderer", help = "wanderer",
     intro = "A man with a walking stick sits by a small fire and raises a hand. No "
          .. "weapon in sight. 'Sit a minute. I don't bite. Not like the rest of "
          .. "them out there.'",
     start = "near"},
}
local ENCOUNTERS_BY_KIND = {}
for _, e in ipairs(ENCOUNTERS) do
    ENCOUNTERS_BY_KIND[e.kind] = ENCOUNTERS_BY_KIND[e.kind] or {}
    table.insert(ENCOUNTERS_BY_KIND[e.kind], e)
end

-- ---------------------------------------------------------------------
-- Item sprites (16x16, 1-bit)
--
-- Authored as ASCII art ('#' = drawn pixel, '.' = transparent) and packed
-- once at load into the XBM layout gfx.sprite expects: rows of
-- (w + 7) // 8 bytes, least-significant bit = leftmost pixel. 16x16 is
-- 32 bytes, well under the 128-byte-per-call limit.
-- ---------------------------------------------------------------------

local SPRITE_W, SPRITE_H = 16, 16

local SPRITE_ART = {
    tshirt = {
        "................",
        "..###......###..",
        ".####.####.####.",
        "################",
        "################",
        ".###.######.###.",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "................",
        "................",
    },
    jeans = {
        "................",
        "..############..",
        "..############..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "..#####..#####..",
        "................",
    },
    boots = {
        "................",
        "...#####........",
        "...#####........",
        "...#####........",
        "...#####........",
        "...#####........",
        "...#####........",
        "...######.......",
        "...########.....",
        "...##########...",
        "..############..",
        "..#############.",
        "..#############.",
        "..#############.",
        "................",
        "................",
    },
    cap = {
        "................",
        "................",
        "................",
        "................",
        "....########....",
        "...##########...",
        "..############..",
        "..############..",
        "..############..",
        "..############..",
        "..#############.",
        "..##############",
        "......##########",
        "................",
        "................",
        "................",
    },
    gloves = {
        "................",
        "...##.##.##.##..",
        "...##.##.##.##..",
        "...##.##.##.##..",
        "...############.",
        "...############.",
        "...############.",
        "..#############.",
        ".##############.",
        ".#############..",
        "..############..",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "................",
    },
    earmuffs = {
        "................",
        "....########....",
        "...##......##...",
        "..##........##..",
        "..#..........#..",
        ".##..........##.",
        ".#............#.",
        "###..........###",
        "####........####",
        "####........####",
        "####........####",
        "####........####",
        "###..........###",
        "................",
        "................",
        "................",
    },
    sunglasses = {
        "................",
        "................",
        "................",
        "................",
        "#..............#",
        "##............##",
        ".##############.",
        ".######..######.",
        ".######..######.",
        ".#####....#####.",
        "..####....####..",
        "...##......##...",
        "................",
        "................",
        "................",
        "................",
    },
    scarf = {
        "................",
        "..############..",
        ".##############.",
        ".##############.",
        "..############..",
        "........####....",
        "........####....",
        ".......#####....",
        ".......####.....",
        ".......####.....",
        "......#####.....",
        "......####......",
        "......#.#.#.....",
        "......#.#.#.....",
        "................",
        "................",
    },
    jacket = {
        "................",
        "...####..####...",
        "..#####..#####..",
        ".######..######.",
        "#######..#######",
        "#######..#######",
        "###.###..###.###",
        "###.###..###.###",
        "###.###..###.###",
        "###.###..###.###",
        "###.###..###.###",
        "###.###..###.###",
        "....###..###....",
        "....###..###....",
        "....########....",
        "................",
    },
    bracers = {
        "................",
        "................",
        "................",
        "..############..",
        ".##############.",
        ".#.#.#.#.#.#.#..",
        ".##############.",
        ".##############.",
        ".#.#.#.#.#.#.#..",
        ".##############.",
        "..############..",
        "................",
        "................",
        "................",
        "................",
        "................",
    },
    berries = {
        "................",
        "......#.........",
        ".....#..........",
        "....#.#.........",
        "...#...#........",
        "..###..###......",
        ".#####.#####....",
        ".#####.#####....",
        "..###...###.....",
        ".....###........",
        "....#####.......",
        "....#####.......",
        ".....###........",
        "................",
        "................",
        "................",
    },
    backpack = {
        "................",
        ".....######.....",
        "....#......#....",
        "...##########...",
        "..############..",
        "..##........##..",
        "..##.######.##..",
        "..##.#....#.##..",
        "..##.######.##..",
        "..##........##..",
        "..############..",
        "..############..",
        "..############..",
        "...##########...",
        "................",
        "................",
    },
    satchel = {
        "................",
        "#...............",
        ".#..............",
        "..#.............",
        "...#............",
        "....#...........",
        ".....#..........",
        "..############..",
        "..#..........#..",
        "..############..",
        "..############..",
        "..############..",
        "..############..",
        "..############..",
        "................",
        "................",
    },
    canned_beans = {
        "................",
        "....########....",
        "...##########...",
        "...##########...",
        "...##########...",
        "...#........#...",
        "...#..####..#...",
        "...#.######.#...",
        "...#..####..#...",
        "...#........#...",
        "...##########...",
        "...##########...",
        "...##########...",
        "....########....",
        "................",
        "................",
    },
    water_bottle = {
        "................",
        "......####......",
        "......####......",
        "......####......",
        ".....######.....",
        "....########....",
        "....########....",
        "....#......#....",
        "....#......#....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "....########....",
        "................",
    },
    rock = {
        "................",
        "................",
        "................",
        "................",
        "......####......",
        "....########....",
        "...##########...",
        "..###.########..",
        ".##############.",
        ".##############.",
        "################",
        "################",
        ".##############.",
        "..############..",
        "................",
        "................",
    },
    cloth_scrap = {
        "................",
        "..#######.......",
        ".#########......",
        ".##########.....",
        ".###########....",
        ".############...",
        "..############..",
        "..#####.#######.",
        "..#####.#######.",
        "...####.#######.",
        "...###..#######.",
        "....##..######..",
        ".....#...####...",
        "..........##....",
        "................",
        "................",
    },
    strange_meat = {
        "................",
        "................",
        ".....######.....",
        "...##########...",
        "..####.#######..",
        ".######.#####.#.",
        ".#######.###.##.",
        "################",
        "##.#############",
        "###.######.#####",
        ".####.###.#####.",
        "..############..",
        "...##########...",
        ".....######.....",
        "................",
        "................",
    },
    knife = {
        "................",
        ".............##.",
        "............###.",
        "...........###..",
        "..........###...",
        ".........###....",
        "........###.....",
        ".......###......",
        "......###.......",
        "....#.##........",
        ".....#..........",
        "....#.#.........",
        "...###..........",
        "..###...........",
        ".###............",
        "................",
    },
    pipe = {
        "................",
        "............###.",
        "...........#####",
        "...........#####",
        "..........#####.",
        ".........####...",
        "........####....",
        ".......####.....",
        "......####......",
        ".....####.......",
        "....####........",
        "...####.........",
        "..####..........",
        ".####...........",
        ".###............",
        "................",
    },
    spear = {
        "..............#.",
        ".............###",
        "............####",
        "...........####.",
        "...........##...",
        "..........#.#...",
        ".........#......",
        "........#.......",
        ".......#........",
        "......#.........",
        ".....#..........",
        "....#...........",
        "...#............",
        "..#.............",
        ".#..............",
        "................",
    },
}

-- Pack one ASCII bitmap (w x h) into the binary string gfx.sprite wants.
-- Validates the art so a typo fails loudly at load instead of drawing garbage.
local function pack_bitmap(name, rows, w, h)
    assert(#rows == h, name .. ": bitmap needs " .. h .. " rows, got " .. #rows)
    local bytes_per_row = (w + 7) // 8
    local out = {}
    for y, row in ipairs(rows) do
        assert(#row == w, name .. ": row " .. y .. " is " .. #row .. " chars, need " .. w)
        for b = 0, bytes_per_row - 1 do
            local value = 0
            for bit = 0, 7 do
                local x = b * 8 + bit
                if x < w and row:sub(x + 1, x + 1) == "#" then
                    value = value | (1 << bit)
                end
            end
            out[#out + 1] = string.char(value)
        end
    end
    local packed = table.concat(out)
    assert(#packed == bytes_per_row * h and #packed <= 128, name .. ": bad packed size")
    return packed
end

local SPRITES = {}
for item_id, rows in pairs(SPRITE_ART) do
    SPRITES[item_id] = pack_bitmap(item_id, rows, SPRITE_W, SPRITE_H)
end

-- gfx.sprite is documented as an alias of gfx.bitmap; use whichever exists
-- so an older firmware without the alias still gets icons.
local draw_sprite = gfx.sprite or gfx.bitmap

-- ---------------------------------------------------------------------
-- Terrain glyphs (10x10): drawn in the middle of each map tile and in the
-- legend, so terrain can be told apart by shape and not only by gray level
-- (light vs dark gray dither to similar patterns on a 2-level display).
-- ---------------------------------------------------------------------

local GLYPH_W, GLYPH_H = 10, 10

local GLYPH_ART = {
    plains = {              -- tufts of grass
        "..........",
        "..........",
        "#.#.......",
        ".#....#.#.",
        ".......#..",
        "..........",
        "...#.#....",
        "....#.....",
        "..........",
        "..........",
    },
    forest = {              -- pine tree
        "..........",
        "....##....",
        "...####...",
        "..######..",
        "...####...",
        "..######..",
        ".########.",
        "....##....",
        "....##....",
        "..........",
    },
    hills = {               -- rising ground
        "..........",
        "..........",
        "..........",
        "....##....",
        "...####...",
        "..######..",
        ".########.",
        "##########",
        "..........",
        "..........",
    },
    water = {               -- two rows of waves
        "..........",
        "..........",
        ".##....##.",
        "#..#..#..#",
        "....##....",
        "..........",
        ".##....##.",
        "#..#..#..#",
        "....##....",
        "..........",
    },
}

local GLYPHS = {}
for terrain_id, rows in pairs(GLYPH_ART) do
    GLYPHS[terrain_id] = pack_bitmap("glyph:" .. terrain_id, rows, GLYPH_W, GLYPH_H)
end
for terrain_id in pairs(TERRAIN) do
    assert(GLYPHS[terrain_id], "terrain has no glyph: " .. terrain_id)
end

-- ---------------------------------------------------------------------
-- Small deterministic RNG (avoids depending on math.randomseed behaving
-- a particular way on-device - same approach as the bundled Snake demo)
-- ---------------------------------------------------------------------

local function rand_next(seed)
    return (seed * 109 + 1021) % 32768
end

local function weighted_pick(seed, weights)
    seed = rand_next(seed)
    local total = 0
    for _, w in ipairs(weights) do total = total + w[2] end
    local roll = seed * total // 32768   -- high bits; the LCG's low bits cycle fast
    local acc = 0
    for _, w in ipairs(weights) do
        acc = acc + w[2]
        if roll < acc then return seed, w[1] end
    end
    return seed, weights[#weights][1]
end

-- ---------------------------------------------------------------------
-- Hex math (axial coordinates, pointy-top, flat 2D - no isometric squash)
-- ---------------------------------------------------------------------

local SQRT3 = math.sqrt(3)

local function axial_to_pixel(q, r, size)
    local x = size * (SQRT3 * q + SQRT3 / 2 * r)
    local y = size * (3 / 2 * r)
    return x, y
end

local function axial_round(qf, rf)
    local xf, zf = qf, rf
    local yf = -xf - zf
    local rx, ry, rz = math.floor(xf + 0.5), math.floor(yf + 0.5), math.floor(zf + 0.5)
    local dx, dy, dz = math.abs(rx - xf), math.abs(ry - yf), math.abs(rz - zf)
    if dx > dy and dx > dz then
        rx = -ry - rz
    elseif dy > dz then
        ry = -rx - rz
    else
        rz = -rx - ry
    end
    return rx, rz
end

local function pixel_to_axial(x, y, size)
    local qf = (SQRT3 / 3 * x - 1 / 3 * y) / size
    local rf = (2 / 3 * y) / size
    return axial_round(qf, rf)
end

local function axial_distance(aq, ar, bq, br)
    local ax, az = aq, ar
    local ay = -ax - az
    local bx, bz = bq, br
    local by = -bx - bz
    return math.max(math.abs(ax - bx), math.abs(ay - by), math.abs(az - bz))
end

local AXIAL_DIRS = {{1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1}}

local function hex_key(q, r) return q .. "," .. r end

local function neighbors(tiles, q, r)
    local result = {}
    for _, d in ipairs(AXIAL_DIRS) do
        local nq, nr = q + d[1], r + d[2]
        if tiles[hex_key(nq, nr)] then
            result[#result + 1] = {nq, nr}
        end
    end
    return result
end

-- ---------------------------------------------------------------------
-- World / player state
-- ---------------------------------------------------------------------

local function generate_world(seed)
    local tiles = {}
    for q = -GRID_RADIUS, GRID_RADIUS do
        for r = -GRID_RADIUS, GRID_RADIUS do
            if -GRID_RADIUS <= -q - r and -q - r <= GRID_RADIUS then
                local terrain
                seed, terrain = weighted_pick(seed, TERRAIN_WEIGHTS)
                tiles[hex_key(q, r)] = terrain
            end
        end
    end
    tiles[hex_key(0, 0)] = "plains"

    local ground = {}
    ground[hex_key(0, 0)] = {
        {item = "rock", qty = 1},
        {item = "cloth_scrap", qty = 2},
        {item = "canned_beans", qty = 1},
        {item = "water_bottle", qty = 2},
    }

    -- Scatter loot on other passable tiles: every wearable once, plus a few
    -- food/water caches. Keys are sorted so a seed always gives the same map.
    local spots = {}
    for key, terrain in pairs(tiles) do
        if TERRAIN[terrain].passable and key ~= hex_key(0, 0) then
            spots[#spots + 1] = key
        end
    end
    table.sort(spots)
    local function drop(item, qty)
        seed = rand_next(seed)
        local key = spots[seed % #spots + 1]
        ground[key] = ground[key] or {}
        for _, s in ipairs(ground[key]) do
            if s.item == item then s.qty = s.qty + qty; return end
        end
        table.insert(ground[key], {item = item, qty = qty})
    end
    for _, item in ipairs(WORLD_WEARABLES) do drop(item, 1) end
    for _, item in ipairs({"canned_beans", "canned_beans", "water_bottle",
                           "water_bottle", "water_bottle", "cloth_scrap"}) do
        drop(item, 1)
    end
    return tiles, ground, seed
end

-- ---------------------------------------------------------------------
-- Character: attributes (NEO Scavenger-style point buy) and traits (Project
-- Zomboid-style budget: positive traits cost points, negative ones give them
-- back, and you can only start with the balance at 0 or above). Only traits
-- that actually change something are offered.
-- ---------------------------------------------------------------------

local ATTRIBUTES = {"Strength", "Speed", "Perception", "Endurance"}
local ATTR_MIN, ATTR_MAX, ATTR_DEFAULT, ATTR_POINTS = 1, 6, 3, 12
local ATTR_DESC = {
    Strength   = "Strength: +1 bag cell per point over 3",
    Speed      = "Speed: +1 MP per 2 points over 3",
    Perception = "Perception: sight, finds, fewer duds",
    Endurance  = "Endurance: 10% slower tiring per point",
}

-- cost > 0 spends trait points, cost < 0 gives them. fx keys: mp, sight,
-- scav (finds per search), bag (cells), hunger / rest_gain (multipliers)
local TRAITS = {
    {name = "Quick",        cost = 3,  desc = "+1 movement point",        fx = {mp = 1}},
    {name = "Hawk-Eyed",    cost = 3,  desc = "+1 sight",                 fx = {sight = 1}},
    {name = "Scrounger",    cost = 2,  desc = "+1 find per search",       fx = {scav = 1}},
    {name = "Light Eater",  cost = 2,  desc = "Hunger drains 25% slower", fx = {hunger = 0.75}},
    {name = "Pack Mule",    cost = 2,  desc = "+2 bag cells",             fx = {bag = 2}},
    {name = "Asthmatic",    cost = -3, desc = "-1 movement point",        fx = {mp = -1}},
    {name = "Near-Sighted", cost = -3, desc = "-1 sight",                 fx = {sight = -1}},
    {name = "Careless",     cost = -2, desc = "-1 find per search",       fx = {scav = -1}},
    {name = "Big Eater",    cost = -2, desc = "Hunger drains 25% faster", fx = {hunger = 1.25}},
    {name = "Insomniac",    cost = -2, desc = "Resting restores 25% less", fx = {rest_gain = 0.75}},
}

local function default_attrs()
    local a = {}
    for _, name in ipairs(ATTRIBUTES) do a[name] = ATTR_DEFAULT end
    return a
end

local function attr_points_left(attrs)
    local used = 0
    for _, name in ipairs(ATTRIBUTES) do used = used + attrs[name] end
    return ATTR_POINTS - used
end

-- trait points left: everyone gets TRAIT_START_POINTS, negatives add more,
-- positives spend; must be >= 0 to start
local TRAIT_START_POINTS = 5
local function trait_points_left(traits)
    local left = TRAIT_START_POINTS
    for _, t in ipairs(TRAITS) do
        if traits[t.name] then left = left - t.cost end
    end
    return left
end

-- Derived stats from attributes + traits, stored on the player.
local function recompute_stats(player)
    local a, fx = player.attrs, {mp = 0, sight = 0, scav = 0, bag = 0, hunger = 1, rest_gain = 1}
    for _, t in ipairs(TRAITS) do
        if player.traits[t.name] then
            for k, v in pairs(t.fx) do
                if k == "hunger" or k == "rest_gain" then fx[k] = fx[k] * v else fx[k] = fx[k] + v end
            end
        end
    end
    player.max_mp = math.max(1, BASE_MAX_MP + (a.Speed - 3) // 2 + fx.mp)
    player.sight = math.max(1, BASE_SIGHT + (a.Perception - 3) // 2 + fx.sight)
    player.scav_rolls = math.max(1, SCAVENGE_ROLLS + (a.Perception - 3) // 2 + fx.scav)
    player.bag_bonus = (a.Strength - 3) + fx.bag
    player.hunger_mult = fx.hunger
    player.rest_gain_mult = fx.rest_gain
    player.rest_drain_mult = 1 - 0.1 * (a.Endurance - 3)
end

-- Perception scales how often a search roll comes up empty: 100% at 3,
-- 25% at 6, 150% at 1.
local function dud_percent(perception)
    return 100 * (7 - perception) // 4
end

local function new_player()
    return {
        q = 0, r = 0,
        max_mp = BASE_MAX_MP,
        mp = BASE_MAX_MP,
        sight = BASE_SIGHT,
        hours = 0,
        needs = {hunger = 100, thirst = 100, rest = 100},
        health = MAX_HEALTH,
        injuries = {bleeding = false, wounded_hours = 0},
        equipped = {shirt = "tshirt", pants = "jeans", feet = "boots", back = "backpack"},
        inventory = {
            {item = "water_bottle", qty = 1},
            {item = "canned_beans", qty = 1},
        },
        explored = {},
        visible = {},
        attrs = default_attrs(),
        traits = {},
    }
end

local function update_visibility(player, tiles)
    player.visible = {}
    for key in pairs(tiles) do
        local q, r = key:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        if axial_distance(player.q, player.r, q, r) <= player.sight then
            player.visible[key] = true
            player.explored[key] = true
        end
    end
end

local function clamp(v) return math.max(0, math.min(100, v)) end

-- Split text into lines of at most cols characters, breaking at spaces.
local function wrap(text, cols)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= cols then
            line = line .. " " .. word
        else
            lines[#lines + 1] = line
            line = word
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function apply_awake_hours(player, hours)
    player.needs.hunger = clamp(player.needs.hunger - hours * (100 / 72) * player.hunger_mult)
    player.needs.thirst = clamp(player.needs.thirst - hours * (100 / 48))
    player.needs.rest = clamp(player.needs.rest - hours * (100 / 18) * player.rest_drain_mult)
    if player.injuries.bleeding then
        player.health = clamp(player.health - hours * BLEED_PER_HOUR)
    end
end

local function apply_rest_hours(player, hours)
    player.needs.hunger = clamp(player.needs.hunger - hours * (100 / 72) * 0.5 * player.hunger_mult)
    player.needs.thirst = clamp(player.needs.thirst - hours * (100 / 48) * 0.5)
    player.needs.rest = clamp(player.needs.rest + hours * (100 / 6) * player.rest_gain_mult)
    local inj = player.injuries
    if inj.bleeding then
        player.health = clamp(player.health - hours * BLEED_PER_HOUR)
    else
        local heal = REST_HEAL_PER_HOUR * (1 + 0.1 * (player.attrs.Endurance - 3))
        player.health = clamp(player.health + hours * heal)
        inj.wounded_hours = math.max(0, inj.wounded_hours - hours)
    end
end

local function effective_max_mp(player)
    local penalty = 0
    if player.needs.hunger <= 0 then penalty = penalty + 1 end
    if player.needs.thirst <= 0 then penalty = penalty + 1 end
    if player.needs.rest <= 0 then penalty = penalty + 1 end
    if player.injuries.wounded_hours > 0 then penalty = penalty + 1 end
    return math.max(1, player.max_mp - penalty)
end

-- ---------------------------------------------------------------------
-- Game object (holds everything one screen/session needs)
-- ---------------------------------------------------------------------

local Game = {}
Game.__index = Game

function Game.new()
    local self = setmetatable({}, Game)
    -- The SolarOS Lua runtime does not load the `os` library, so seed from
    -- uptime instead; the constant is only a fallback for other hosts.
    local seed = 12345
    local clock = solaros.time and solaros.time.uptime_ms
    if clock then
        seed = math.floor(clock()) % 32768
    elseif os and os.time then
        seed = os.time() % 32768
    end
    self.tiles, self.ground, seed = generate_world(seed)
    self.seed = seed             -- RNG state for scavenging
    self.scavenged = {}          -- tile key -> searches used
    self.player = new_player()
    recompute_stats(self.player)
    update_visibility(self.player, self.tiles)
    self.screen = "creator"      -- "creator", then "map" or "inventory"
    self.creator_cursor = 1      -- rows: attributes, then traits
    self.creator_msg = nil
    self.log = {"You wake up in the wasteland."}
    self.inv_cursor = 1
    self.inv_selected = nil      -- {"ground"|"inventory"|"equip", key}
    self.quit = false
    return self
end

-- Leave the creator: apply the chosen stats and start on the map.
function Game:start_game()
    if trait_points_left(self.player.traits) < 0 then
        self.creator_msg = "Too many trait points spent."
        return false
    end
    local p = self.player
    recompute_stats(p)
    p.mp = p.max_mp
    p.explored = {}
    update_visibility(p, self.tiles)
    self.screen = "map"
    return true
end

-- Health at 0 ends the run: the death screen, then a new character.
function Game:check_death(cause)
    if self.player.health > 0 then return false end
    self.screen = "dead"
    self.death_cause = cause
    return true
end

function Game:push_log(text)
    table.insert(self.log, text)
    while #self.log > 3 do table.remove(self.log, 1) end
end

-- -- movement / rest --------------------------------------------------

function Game:try_move(q, r)
    local p = self.player
    local key = hex_key(q, r)
    local terrain_id = self.tiles[key]
    if not terrain_id then return end
    local found = false
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        if n[1] == q and n[2] == r then found = true end
    end
    if not found then return end
    local terrain = TERRAIN[terrain_id]
    if not terrain.passable then
        self:push_log("Can't cross " .. terrain.name .. ".")
        return
    end
    if p.mp <= 0 then
        self:push_log("Out of movement. Rest first.")
        return
    end
    p.mp = p.mp - terrain.cost
    p.q, p.r = q, r
    p.hours = p.hours + terrain.cost
    apply_awake_hours(p, terrain.cost)
    update_visibility(p, self.tiles)
    self:push_log("Moved to " .. terrain.name .. " (" .. terrain.cost .. " MP)")
    local pile = self.ground[key]
    if pile and #pile > 0 then self:push_log("Something is here. (I to look)") end
    if p.needs.hunger <= 0 then self:push_log("You are starving!") end
    if p.needs.thirst <= 0 then self:push_log("You are dehydrated!") end
    if not self:check_death("You bled out.") then self:maybe_encounter(terrain_id) end
end

function Game:move_dir(dq, dr)
    local p = self.player
    -- pick the neighbor whose pixel-space direction best matches (dq,dr)
    local px, py = axial_to_pixel(p.q, p.r, HEX_SIZE)
    local best, best_dot = nil, -math.huge
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        local nx, ny = axial_to_pixel(n[1], n[2], HEX_SIZE)
        local vx, vy = nx - px, ny - py
        local len = math.sqrt(vx * vx + vy * vy)
        if len == 0 then len = 1 end
        local dot = (vx / len) * dq + (vy / len) * dr
        if dot > best_dot then best_dot, best = dot, n end
    end
    if best then self:try_move(best[1], best[2]) end
end

function Game:scavenge_left()
    local key = hex_key(self.player.q, self.player.r)
    return SCAVENGE_TRIES - (self.scavenged[key] or 0)
end

-- Search the current tile: costs MP and hours like moving, rolls the
-- terrain's loot table, and drops what turns up on the ground here.
function Game:scavenge()
    local p = self.player
    local key = hex_key(p.q, p.r)
    local loot = SCAVENGE_LOOT[self.tiles[key]]
    if not loot then
        self:push_log("Nothing to search here.")
        return
    end
    if self:scavenge_left() <= 0 then
        self:push_log("This area is picked clean.")
        return
    end
    if p.mp <= 0 then
        self:push_log("Too tired to search. Rest first.")
        return
    end
    p.mp = p.mp - SCAVENGE_HOURS
    p.hours = p.hours + SCAVENGE_HOURS
    apply_awake_hours(p, SCAVENGE_HOURS)
    self.scavenged[key] = (self.scavenged[key] or 0) + 1

    -- Perception: fewer dud rolls (and, via scav_rolls, more of them)
    local table_ = {}
    for i, entry in ipairs(loot) do
        local w = entry[2]
        if entry[1] == "nothing" then w = math.max(1, w * (7 - p.attrs.Perception) // 4) end
        table_[i] = {entry[1], w}
    end
    local found = {}
    for _ = 1, p.scav_rolls do
        local item
        self.seed, item = weighted_pick(self.seed, table_)
        if item ~= "nothing" then
            self:put_stack("ground", nil, {item = item, qty = 1})
            found[#found + 1] = ITEM_DB[item].name
        end
    end
    if #found == 0 then
        self:push_log("Searched " .. SCAVENGE_HOURS .. "h. Found nothing.")
    else
        self:push_log("Found: " .. table.concat(found, ", ") .. ".")
        self:push_log("Press I to pick it up.")
    end
    if p.needs.hunger <= 0 then self:push_log("You are starving!") end
    if p.needs.thirst <= 0 then self:push_log("You are dehydrated!") end
    self:check_death("You bled out.")
end

function Game:rest()
    local p = self.player
    local cap = effective_max_mp(p)
    if p.mp >= cap then
        self:push_log("Already rested.")
        return
    end
    p.hours = p.hours + REST_HOURS
    apply_rest_hours(p, REST_HOURS)
    p.mp = effective_max_mp(p)
    update_visibility(p, self.tiles)
    self:push_log("Rested " .. REST_HOURS .. "h.")
    if p.injuries.bleeding then self:push_log("You're still bleeding. Bandage it (E on cloth).") end
    self:check_death("You bled out in your sleep.")
end

-- -- inventory transfer -------------------------------------------------

function Game:ground_list()
    local key = hex_key(self.player.q, self.player.r)
    self.ground[key] = self.ground[key] or {}
    return self.ground[key]
end

function Game:get_stack(kind, k)
    if kind == "ground" then
        return self:ground_list()[k]
    elseif kind == "inventory" then
        return self.player.inventory[k]
    elseif kind == "equip" then
        local item = self.player.equipped[k]
        return item and {item = item, qty = 1} or nil
    end
end

function Game:remove_stack(kind, k)
    if kind == "ground" then
        return table.remove(self:ground_list(), k)
    elseif kind == "inventory" then
        return table.remove(self.player.inventory, k)
    elseif kind == "equip" then
        local item = self.player.equipped[k]
        self.player.equipped[k] = nil
        return item and {item = item, qty = 1} or nil
    end
end

-- Add stack to list, merging into an existing stack of the same item so the
-- same thing never takes two cells. Returns false (list untouched) when a new
-- stack is needed and the list already holds `cap` stacks.
local function add_to_list(list, stack, cap)
    for _, s in ipairs(list) do
        if s.item == stack.item then
            s.qty = s.qty + stack.qty
            return true
        end
    end
    if cap and #list >= cap then return false end
    table.insert(list, stack)
    return true
end

-- Bag cells available now: the worn bag (or bare pockets) plus Strength and
-- Pack Mule, within what the screen can show.
function Game:bag_capacity()
    local p = self.player
    local bag = p.equipped.back and ITEM_DB[p.equipped.back].bag_cells or POCKET_CELLS
    return math.max(2, math.min(BACKPACK_CAP, bag + (p.bag_bonus or 0)))
end

function Game:put_stack(kind, k, stack)
    if kind == "ground" then
        add_to_list(self:ground_list(), stack)
        return true
    elseif kind == "inventory" then
        if not add_to_list(self.player.inventory, stack, self:bag_capacity()) then
            self:push_log("Bag full.")
            return false
        end
        return true
    elseif kind == "equip" then
        local def = ITEM_DB[stack.item]
        if def.slot ~= k and not HOLD_SLOTS[k] then
            self:push_log(def.name .. " can't go in " .. k .. ".")
            return false
        end
        local current = self.player.equipped[k]
        if current then
            local old = {item = current, qty = 1}
            if not add_to_list(self.player.inventory, old, self:bag_capacity()) then
                add_to_list(self:ground_list(), old)
                self:push_log("Bag full: " .. ITEM_DB[current].name .. " dropped.")
            end
        end
        self.player.equipped[k] = stack.item
        -- equipping takes one; anything else in the stack goes to the bag
        if stack.qty > 1 then
            local rest = {item = stack.item, qty = stack.qty - 1}
            if not add_to_list(self.player.inventory, rest, self:bag_capacity()) then
                add_to_list(self:ground_list(), rest)
            end
        end
        return true
    end
end

-- Undo a remove_stack: put the stack back exactly where it came from.
function Game:restore_stack(kind, k, stack)
    if kind == "ground" then
        table.insert(self:ground_list(), k, stack)
    elseif kind == "inventory" then
        table.insert(self.player.inventory, k, stack)
    elseif kind == "equip" then
        self.player.equipped[k] = stack.item
    end
end

local function copy_stacks(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = {item = s.item, qty = s.qty} end
    return out
end

-- Move a stack. Returns true when it moved. A move that would leave more
-- stacks in the bag than it can hold (e.g. taking off a full backpack) is
-- undone as a whole.
function Game:try_transfer(source, dest)
    local s_kind, s_key = source[1], source[2]
    local d_kind, d_key = dest[1], dest[2]
    if s_kind == d_kind and s_key == d_key then return false end
    local p = self.player
    local saved_inv, saved_ground = copy_stacks(p.inventory), copy_stacks(self:ground_list())
    local saved_eq = {}
    for slot, item in pairs(p.equipped) do saved_eq[slot] = item end

    local stack = self:remove_stack(s_kind, s_key)
    if not stack then return false end
    local ok = self:put_stack(d_kind, d_key, stack)
    if ok and #p.inventory > self:bag_capacity() then
        self:push_log("Bag too small - empty it first.")
        ok = false
    end
    if not ok then
        p.inventory, p.equipped = saved_inv, saved_eq
        self.ground[hex_key(p.q, p.r)] = saved_ground
        return false
    end
    self:push_log("Moved " .. ITEM_DB[stack.item].name .. ".")
    return true
end

function Game:try_consume(kind, k)
    local stack = self:get_stack(kind, k)
    if not stack then return end
    local def = ITEM_DB[stack.item]
    if not def.consumable then
        self:push_log(def.name .. " isn't edible/drinkable.")
        return
    end
    for need, amount in pairs(def.consumable) do
        self.player.needs[need] = clamp(self.player.needs[need] + amount)
    end
    -- one unit per use; the stack only disappears when it runs out
    stack.qty = stack.qty - 1
    if stack.qty <= 0 then
        self:remove_stack(kind, k)
    end
    self:push_log("Consumed " .. def.name .. ".")
end

-- E on the inventory screen: the obvious thing for the item under the cursor.
-- Food/drink is eaten, gear is worn, anything else goes to a free hand; on a
-- body slot it takes the item off (held food is eaten instead).
function Game:use_item(kind, k)
    local stack = self:get_stack(kind, k)
    if not stack then return end
    local def = ITEM_DB[stack.item]
    local p = self.player
    if stack.item == "cloth_scrap" and p.injuries.bleeding then
        p.injuries.bleeding = false
        stack.qty = stack.qty - 1
        if stack.qty <= 0 then self:remove_stack(kind, k) end
        self:push_log("You bind the wound. The bleeding stops.")
        return
    end
    if kind == "equip" then
        if def.consumable and HOLD_SLOTS[k] then
            self:try_consume(kind, k)
        else
            self:try_transfer({kind, k}, {"inventory"})
        end
    elseif def.consumable then
        self:try_consume(kind, k)
    elseif def.slot then
        self:try_transfer({kind, k}, {"equip", def.slot})
    else
        local hand = (not p.equipped.rhand and "rhand") or (not p.equipped.lhand and "lhand") or "rhand"
        self:try_transfer({kind, k}, {"equip", hand})
    end
end

-- -- encounters -----------------------------------------------------------

local ENC_COLS = 55            -- mono 12 is ~7 px/char: 55 chars fit 400 px
local ENC_MSG_LINES = 4

-- 0..n-1 from the LCG's high bits
function Game:rand(n)
    self.seed = rand_next(self.seed)
    return self.seed * n // 32768
end

function Game:roll(pct)
    return self:rand(100) < pct
end

function Game:maybe_encounter(terrain_id)
    if (self.enc_cooldown or 0) > 0 then
        self.enc_cooldown = self.enc_cooldown - 1
        return
    end
    local chance = ENCOUNTER_CHANCE[terrain_id]
    if chance and self:roll(chance) then self:start_encounter(self:pick_encounter()) end
end

-- A kind by ENCOUNTER_KINDS weight (skipping kinds with no entries), then
-- one of its entries at random.
function Game:pick_encounter()
    local kinds = {}
    for _, k in ipairs(ENCOUNTER_KINDS) do
        if ENCOUNTERS_BY_KIND[k[1]] then kinds[#kinds + 1] = k end
    end
    local kind
    self.seed, kind = weighted_pick(self.seed, kinds)
    local list = ENCOUNTERS_BY_KIND[kind]
    return list[self:rand(#list) + 1]
end

function Game:start_encounter(def)
    self.enc = {def = def, hp = def.hp, range = def.start or "far", msg = {},
                intro = wrap(def.intro, ENC_COLS), cursor = 1, aim = 0,
                demanding = def.kind == "bandit"}
    if def.kind == "bandit" then self:enc_say(def.demand) end
    self.screen = "encounter"
end

function Game:enc_say(text)
    for _, line in ipairs(wrap(text, ENC_COLS)) do table.insert(self.enc.msg, line) end
    while #self.enc.msg > ENC_MSG_LINES do table.remove(self.enc.msg, 1) end
end

function Game:end_encounter(summary)
    self.enc.over = true
    self.enc_cooldown = ENCOUNTER_COOLDOWN
    if summary then self:push_log(summary) end
end

-- The weapon in your hands (right first), its name and slot; fists if none.
function Game:weapon()
    for _, slot in ipairs({"rhand", "lhand"}) do
        local item = self.player.equipped[slot]
        if item and ITEM_DB[item].weapon then return ITEM_DB[item].weapon, ITEM_DB[item].name, slot end
    end
    return FISTS, "Fists"
end

function Game:thrown_slot()
    for _, slot in ipairs({"rhand", "lhand"}) do
        local item = self.player.equipped[slot]
        if item and ITEM_DB[item].weapon and ITEM_DB[item].weapon.thrown then return slot end
    end
end

-- First food/drink in the bag, for paying off bandits.
function Game:food_index()
    for i, stack in ipairs(self.player.inventory) do
        if ITEM_DB[stack.item].consumable then return i end
    end
end

function Game:enemy_condition()
    local f = self.enc.hp / self.enc.def.hp
    if f > 0.75 then return "unhurt" elseif f > 0.4 then return "hurt" end
    return "badly hurt"
end

-- What you can do now, as {label, action}.
function Game:encounter_options()
    local e = self.enc
    if e.over then return {{"Continue", "leave"}} end
    local kind = e.def.kind
    if kind == "helper" then return {{"Talk", "talk"}, {"Walk on", "leave_quietly"}} end
    if e.demanding then
        local o = {}
        if self:food_index() then o[#o + 1] = {"Give them some food", "give"} end
        o[#o + 1] = {"Refuse", "refuse"}
        o[#o + 1] = {"Run for it", "flee"}
        return o
    end
    local o = {}
    local w, wname = self:weapon()
    if e.range == "far" then
        o[#o + 1] = {"Approach", "approach"}
    elseif e.range == "near" then
        if w.reach == "near" then o[#o + 1] = {"Attack (" .. wname .. ")", "attack"} end
        o[#o + 1] = {"Close in", "approach"}
    else
        o[#o + 1] = {"Attack (" .. wname .. ")", "attack"}
    end
    local ts = self:thrown_slot()
    if ts and e.range ~= "close" then
        o[#o + 1] = {"Throw the " .. ITEM_DB[self.player.equipped[ts]].name:lower(), "throw"}
    end
    if e.range ~= "far" then o[#o + 1] = {"Back off", "back"} end
    if not e.seen then o[#o + 1] = {"Watch it", "watch"} end
    if e.range == "far" then o[#o + 1] = {"Hide", "hide"} end
    if kind == "mutant" and not e.talked then o[#o + 1] = {"Talk", "talk"} end
    o[#o + 1] = {"Flee", "flee"}
    return o
end

function Game:enemy_dies()
    local e = self.enc
    local found = {}
    for _ = 1, e.def.loot_rolls or 1 do
        local item
        self.seed, item = weighted_pick(self.seed, e.def.loot)
        if item ~= "nothing" then
            self:put_stack("ground", nil, {item = item, qty = 1})
            found[#found + 1] = ITEM_DB[item].name
        end
    end
    self:enc_say("The " .. e.def.who .. " goes still.")
    if #found > 0 then self:enc_say("Left behind: " .. table.concat(found, ", ") .. ".") end
    self:end_encounter("You killed the " .. e.def.who .. ".")
end

-- The other side's turn: bleed, flee when beaten, close in, or strike.
function Game:enemy_turn()
    local e, p, d = self.enc, self.player, self.enc.def
    if e.over or self.screen ~= "encounter" then return end
    if e.bleeding then
        e.hp = e.hp - ENEMY_BLEED_DMG
        if e.hp <= 0 then return self:enemy_dies() end
    end
    if d.flees_at and e.hp <= d.flees_at and self:roll(ENEMY_FLEE_CHANCE) then
        self:enc_say("The " .. d.who .. " breaks away and flees.")
        return self:end_encounter("The " .. d.who .. " fled.")
    end
    if e.range ~= "close" then
        if self:roll(ADVANCE_CHANCE + 10 * (d.speed - p.attrs.Speed)) then
            e.range = CLOSER[e.range]
            self:enc_say("The " .. d.who .. " closes in.")
        else
            self:enc_say("The " .. d.who .. " circles, watching you.")
        end
        return
    end
    if not self:roll(d.hit - ENEMY_DODGE * (p.attrs.Speed - 3)) then
        self:enc_say("The " .. d.who .. " lunges and misses.")
        return
    end
    local dmg = d.dmg[1] + self:rand(d.dmg[2] - d.dmg[1] + 1)
    p.health = clamp(p.health - dmg)
    local text = "The " .. d.who .. " hits you (-" .. dmg .. " HP)."
    if d.bleed and d.bleed > 0 and not p.injuries.bleeding and self:roll(d.bleed) then
        p.injuries.bleeding = true
        text = text .. " You're bleeding."
    end
    if dmg >= WOUND_DAMAGE and p.injuries.wounded_hours == 0 then
        p.injuries.wounded_hours = WOUND_REST_HOURS
        text = text .. " It leaves a deep wound."
    end
    self:enc_say(text)
    self:check_death("Killed by the " .. d.name .. ".")
end

function Game:enc_hit(dmg, bleed, how)
    local e = self.enc
    e.hp = e.hp - dmg
    local text = how .. " (-" .. dmg .. ")."
    if bleed and self:roll(bleed) and not e.bleeding then
        e.bleeding = true
        text = text .. " It's bleeding."
    end
    self:enc_say(text)
    if e.hp <= 0 then self:enemy_dies() end
end

function Game:helper_talk()
    local p, d = self.player, self.enc.def
    if d.help == "medic" then
        p.injuries.bleeding = false
        p.injuries.wounded_hours = p.injuries.wounded_hours // 2
        p.health = clamp(p.health + 25)
        self:put_stack("ground", nil, {item = "cloth_scrap", qty = 2})
        self:enc_say("She cleans and binds your hurts without a word, and leaves you "
            .. "two clean strips of cloth. (+25 HP)")
        self:end_encounter("The medic patched you up.")
    else
        for key in pairs(self.tiles) do
            local q, r = key:match("(-?%d+),(-?%d+)")
            if axial_distance(p.q, p.r, tonumber(q), tonumber(r)) <= 3 then p.explored[key] = true end
        end
        self:put_stack("ground", nil, {item = "water_bottle", qty = 1})
        self:enc_say("He draws the land around you in the dirt and hands you a bottle of "
            .. "clean water. 'Stay off the roads at night.'")
        self:end_encounter("The wanderer shared water and directions.")
    end
end

function Game:encounter_action(action)
    local e, p = self.enc, self.player
    e.msg = {}
    if action == "leave" or action == "leave_quietly" then
        if action == "leave_quietly" then
            self.enc_cooldown = ENCOUNTER_COOLDOWN
            self:push_log("You nod and walk on.")
        end
        self.enc = nil
        self.screen = "map"
        return
    elseif action == "talk" then
        if e.def.kind == "helper" then return self:helper_talk() end
        e.talked = true
        self:enc_say(e.def.talk)
    elseif action == "give" then
        local i = self:food_index()
        local stack = p.inventory[i]
        local name = ITEM_DB[stack.item].name
        stack.qty = stack.qty - 1
        if stack.qty <= 0 then table.remove(p.inventory, i) end
        self:enc_say("They take the " .. name:lower() .. " and back off into the ruins.")
        return self:end_encounter("You paid the " .. e.def.who .. " off.")
    elseif action == "refuse" then
        e.demanding = false
        self:enc_say("'Wrong answer.'")
    elseif action == "approach" then
        e.range = CLOSER[e.range]
        self:enc_say("You move in. Range: " .. RANGE_NAME[e.range] .. ".")
    elseif action == "back" then
        e.range = FARTHER[e.range]
        self:enc_say("You back away. Range: " .. RANGE_NAME[e.range] .. ".")
    elseif action == "attack" then
        local w, wname = self:weapon()
        local hit = PLAYER_HIT + 8 * (p.attrs.Speed - 3) + e.aim
        e.aim = 0
        if self:roll(hit) then
            local dmg = math.max(1, w.dmg - self:rand(w.dmg // 4 + 1) + 2 * (p.attrs.Strength - 3))
            self:enc_hit(dmg, w.bleed, "You hit the " .. e.def.who .. " (" .. wname:lower() .. ")")
        else
            self:enc_say("You swing at the " .. e.def.who .. " and miss.")
        end
    elseif action == "throw" then
        local slot = self:thrown_slot()
        local item = p.equipped[slot]
        local w = ITEM_DB[item].weapon
        p.equipped[slot] = nil
        self:put_stack("ground", nil, {item = item, qty = 1})
        if self:roll(THROW_HIT + 8 * (p.attrs.Perception - 3) + e.aim) then
            self:enc_hit(w.dmg, w.bleed, "Your " .. ITEM_DB[item].name:lower() .. " strikes the " .. e.def.who)
        else
            self:enc_say("Your " .. ITEM_DB[item].name:lower() .. " sails wide.")
        end
        e.aim = 0
    elseif action == "watch" then
        if self:roll(WATCH_CHANCE + 10 * (p.attrs.Perception - 3)) then
            e.seen = true
            e.aim = WATCH_AIM
            self:enc_say("You study how it moves. It looks " .. self:enemy_condition()
                .. ", and you see an opening.")
        else
            self:enc_say("You can't make out much.")
        end
    elseif action == "hide" then
        local chance = HIDE_CHANCE + 10 * (p.attrs.Perception - 3)
        if e.def.kind == "animal" then chance = chance - 10 end
        if self:roll(chance) then
            self:enc_say("You drop into cover and keep very still. It passes you by.")
            return self:end_encounter("You hid from the " .. e.def.who .. ".")
        end
        self:enc_say("It has seen where you went.")
    elseif action == "flee" then
        if self:roll(FLEE_CHANCE[e.range] + 10 * (p.attrs.Speed - e.def.speed)) then
            p.mp = p.mp - 1
            self:enc_say("You run until your lungs burn. It doesn't follow. (-1 MP)")
            return self:end_encounter("You ran from the " .. e.def.who .. ".")
        end
        self:enc_say("You try to run, but it cuts you off.")
    end
    if not e.over then self:enemy_turn() end
end

function Game:encounter_key(key)
    local opts = self:encounter_options()
    local e = self.enc
    local pick
    if key >= 49 and key < 49 + #opts then          -- '1'..
        pick = key - 48
    elseif key == gfx.KEY_UP or key == KEY_W then
        e.cursor = math.max(1, e.cursor - 1)
    elseif key == gfx.KEY_DOWN or key == KEY_S then
        e.cursor = math.min(#opts, e.cursor + 1)
    elseif key == KEY_ENTER or key == KEY_LF or key == KEY_SPACE then
        pick = e.cursor
    end
    if pick and opts[pick] then
        e.cursor = 1
        self:encounter_action(opts[pick][2])
    end
end

-- ---------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------

local function shade_color(name)
    return gfx[name]
end

-- gfx draw calls appear to require integer coordinates (fill_rect at least
-- throws on a float); our hex math is full of sqrt(3)/trig-derived floats,
-- so every computed coordinate gets rounded right before it reaches gfx.*.
local function rnd(v)
    return math.floor(v + 0.5)
end

-- Draw a terrain glyph centered on (cx, cy) in the given color.
local function draw_glyph(terrain_id, cx, cy, color)
    if not draw_sprite then return end
    gfx.color(color)
    draw_sprite(rnd(cx) - GLYPH_W // 2, rnd(cy) - GLYPH_H // 2, GLYPH_W, GLYPH_H, GLYPHS[terrain_id])
end

-- Map screen (400x300 landscape): the hex map in the left MAP_W pixels
-- between MAP_TOP and MAP_BOTTOM; the HUD and the terrain legend in a panel
-- to its right (from PANEL_X); the log and key hints across the bottom.
local MAP_W, MAP_TOP, MAP_BOTTOM = 256, 4, 236
local PANEL_X = 262
local LEGEND_Y = 80
local LEGEND_ORDER = {"plains", "forest", "hills", "water"}

function Game:draw_map(w, h)
    gfx.clear(gfx.WHITE)

    local p = self.player
    local origin_x, origin_y = MAP_W // 2, (MAP_TOP + MAP_BOTTOM) // 2

    -- HUD
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    local scav = SCAVENGE_LOOT[self.tiles[hex_key(p.q, p.r)]]
        and (self:scavenge_left() .. "/" .. SCAVENGE_TRIES) or "-"
    gfx.text(PANEL_X, 14, "MP " .. math.max(p.mp, 0) .. "/" .. p.max_mp .. "  Hrs " .. p.hours)
    gfx.text(PANEL_X, 28, "Sight " .. p.sight .. " Scav " .. scav)
    gfx.text(PANEL_X, 42, "Hun " .. math.floor(p.needs.hunger)
        .. " Thi " .. math.floor(p.needs.thirst))
    gfx.text(PANEL_X, 56, "Rest " .. math.floor(p.needs.rest) .. "  HP " .. math.floor(p.health))
    local inj = {}
    if p.injuries.bleeding then inj[#inj + 1] = "BLEEDING" end
    if p.injuries.wounded_hours > 0 then inj[#inj + 1] = "Wounded" end
    if #inj > 0 then gfx.text(PANEL_X, 70, table.concat(inj, " ")) end

    local reachable = {}
    for _, n in ipairs(neighbors(self.tiles, p.q, p.r)) do
        reachable[hex_key(n[1], n[2])] = true
    end

    for key, terrain_id in pairs(self.tiles) do
        local q, r = key:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        local px, py = axial_to_pixel(q, r, HEX_SIZE)
        px, py = origin_x + px, origin_y + py
        if py > MAP_TOP and py < MAP_BOTTOM then
            local terrain = TERRAIN[terrain_id]
            local is_player = (q == p.q and r == p.r)
            if p.visible[key] then
                self:draw_hex(px, py, shade_color(terrain.shade), gfx.BLACK)
                if reachable[key] and terrain.passable then
                    -- second, inner outline marks tiles you can step onto
                    self:draw_hex(px, py, nil, gfx.BLACK, HEX_SIZE - 3)
                end
                if not is_player then
                    draw_glyph(terrain_id, px, py, shade_color(terrain.ink))
                end
            elseif p.explored[key] then
                -- remembered but out of sight: faded outline and faded glyph,
                -- so you still remember what kind of ground it was
                self:draw_hex(px, py, nil, gfx.LIGHT)
                draw_glyph(terrain_id, px, py, gfx.LIGHT)
            end
            local pile = self.ground[key]
            if pile and #pile > 0 and (p.visible[key] or p.explored[key]) then
                -- something lies here: small boxed dot in the hex's upper right
                local mx, my = rnd(px) + 5, rnd(py) - 11
                gfx.color(gfx.WHITE)
                gfx.fill_rect(mx - 1, my - 1, 7, 7)
                gfx.color(gfx.BLACK)
                gfx.rect(mx - 1, my - 1, 7, 7)
                gfx.fill_rect(mx + 1, my + 1, 3, 3)
            end
            if is_player then
                -- white halo keeps the marker visible on dark/black tiles
                gfx.color(gfx.WHITE)
                gfx.fill_rect(rnd(px) - 5, rnd(py) - 5, 10, 10)
                gfx.color(gfx.BLACK)
                gfx.fill_rect(rnd(px) - 3, rnd(py) - 3, 6, 6)
            end
        end
    end

    self:draw_legend()

    -- log
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    local ly = h - 52
    for _, line in ipairs(self.log) do
        gfx.text(6, ly, line)
        ly = ly + 14
    end
    gfx.text(6, h - 8, "Arrows Spc:rest F:scavenge I:inv Q:quit")

    gfx.refresh()
end

-- Terrain key: swatch (same fill + glyph as on the map), name, and what it
-- costs to cross. The tile you're standing on gets a second box.
function Game:draw_legend()
    local here = self.tiles[hex_key(self.player.q, self.player.r)]
    gfx.font(gfx.FONT_MONO_12)
    for i, terrain_id in ipairs(LEGEND_ORDER) do
        local t = TERRAIN[terrain_id]
        local x, y = PANEL_X + 2, LEGEND_Y + (i - 1) * 18

        local fill = shade_color(t.shade)
        if fill ~= gfx.WHITE then
            gfx.color(fill)
            gfx.fill_rect(x, y, 14, 14)
        end
        gfx.color(gfx.BLACK)
        gfx.rect(x, y, 14, 14)
        draw_glyph(terrain_id, x + 7, y + 7, shade_color(t.ink))

        gfx.color(gfx.BLACK)
        if terrain_id == here then
            gfx.rect(x - 2, y - 2, 18, 18)
        end
        local detail = t.passable and (t.cost .. " MP") or "impassable"
        gfx.text(x + 20, y + 11, t.name .. " " .. detail)
    end
end

-- Fill a pointy-top hexagon with horizontal 2px bands whose width follows the
-- hex outline (gfx has no polygon fill). Inset by 1px so the fill never spills
-- past the outline. Skipped for WHITE since the background is already white.
local function fill_hex(cx, cy, size, color)
    if color == gfx.WHITE then return end
    gfx.color(color)
    local half_w = size * SQRT3 / 2
    local step = 2
    for y0 = -size, size - step, step do
        local a = math.abs(y0 + step / 2)
        local hw
        if a <= size / 2 then
            hw = half_w
        else
            hw = half_w * (size - a) / (size / 2)
        end
        hw = hw - 1
        if hw >= 1 then
            gfx.fill_rect(rnd(cx - hw), rnd(cy + y0), rnd(2 * hw), step)
        end
    end
end

-- fill_color may be nil (outline only). size defaults to HEX_SIZE.
function Game:draw_hex(cx, cy, fill_color, outline_color, size)
    size = size or HEX_SIZE
    if fill_color then
        fill_hex(cx, cy, size, fill_color)
    end
    gfx.color(outline_color)
    local corners = {}
    for i = 0, 5 do
        local angle = math.rad(60 * i - 30)
        corners[i + 1] = {cx + size * math.cos(angle), cy + size * math.sin(angle)}
    end
    for i = 1, 6 do
        local a, b = corners[i], corners[i % 6 + 1]
        gfx.line(rnd(a[1]), rnd(a[2]), rnd(b[1]), rnd(b[2]))
    end
end

local INV_ROWS = {}  -- rebuilt each draw: {kind, key, label} - only selectable item rows
local INV_POS = {}   -- rebuilt each draw: row_index -> {x, y, w, h} - where that row draws

-- Equip slots sit ON the body part they dress, NEO Scavenger style: a box over
-- the head, the face, the torso, the legs, a hand... sized to that part, with
-- the worn item painted onto the body and its icon drawn inside the box.
-- {x, y, w, h} authored against the figure at center x 150 / head top y 72,
-- then shifted with it (BODY_DX/BODY_DY below). Boxes never touch each other.
local EQUIP_RECT = {
    head   = {139,  64, 22, 18},   -- top of the head (a hat sits here)
    ears   = {118,  84, 20, 18},   -- against the side of the head
    eyes   = {140,  84, 20, 18},   -- the face
    neck   = {140, 105, 20, 18},   -- throat / collar
    jacket = {116, 126, 68, 38},   -- chest and shoulders
    shirt  = {124, 167, 52, 36},   -- belly
    hands  = { 73, 212, 22, 22},   -- gloves: the left forearm and hand
    wrists = {205, 212, 22, 22},   -- the right wrist
    lhand  = { 70, 236, 24, 24},   -- held in the left hand (anything)
    rhand  = {206, 236, 24, 24},   -- held in the right hand (anything)
    back   = {230, 118, 40, 40},   -- worn on the back, drawn beside the shoulder
    pants  = {122, 206, 56, 58},   -- hips and legs
    feet   = {120, 267, 60, 20},   -- both feet
}
-- shown inside an empty slot; the long form when it fits the box
local EQUIP_NAME = {head = "Head", ears = "Ears", eyes = "Eyes", neck = "Neck",
                    jacket = "Jacket", shirt = "Shirt", hands = "Gloves",
                    wrists = "Wrists", pants = "Pants", feet = "Feet",
                    lhand = "L Hand", rhand = "R Hand", back = "Back"}
local EQUIP_ABBR = {head = "Hd", ears = "Ea", eyes = "Ey", neck = "Nk", jacket = "Jk",
                    shirt = "Sh", hands = "Gl", wrists = "Wr", pants = "Pt", feet = "Ft",
                    lhand = "LH", rhand = "RH", back = "Bk"}
-- where the doll sits on the 400x300 screen: the left column, head at the top
local BODY_DX, BODY_DY = -66, -46
for _, r in pairs(EQUIP_RECT) do r[1], r[2] = r[1] + BODY_DX, r[2] + BODY_DY end

-- right column (from INV_COL_X): ground grid, bag grid with its name and
-- fill count above it, then what the cursor is on
local INV_COL_X = 212
local GROUND_GRID_COLS = 5
local GROUND_GRID_ROWS = 2   -- visible rows; the grid scrolls to follow the cursor
local GROUND_CELL, GROUND_GAP = 30, 2
local GROUND_Y = 32
-- bag: up to BACKPACK_CAP cells, all visible
local BACKPACK_COLS = 7
local BACKPACK_CELL, BACKPACK_GAP = 24, 2
local BACKPACK_Y = 114
local BAG_LABEL_Y = BACKPACK_Y - 5
local CURSOR_DESC_Y = 210
local CONDITIONS_Y = 264     -- full width, under the doll
-- log lines sit on the last lines of the reported screen height
local INV_LOG_LINES = 2

local function item_abbr(item_id)
    return ITEM_DB[item_id].name:sub(1, 1)
end

function Game:current_conditions()
    -- Only conditions we actually track - nothing fabricated (no injury/
    -- temperature model exists yet, so none are listed here).
    local list = {}
    if self.player.equipped.feet == nil then table.insert(list, "Barefoot") end
    if self.player.needs.hunger <= 0 then table.insert(list, "Starving") end
    if self.player.needs.thirst <= 0 then table.insert(list, "Dehydrated") end
    if self.player.needs.rest <= 0 then table.insert(list, "Exhausted") end
    if self.player.injuries.bleeding then table.insert(list, "Bleeding") end
    if self.player.injuries.wounded_hours > 0 then table.insert(list, "Wounded") end
    if self.player.health < 50 then table.insert(list, "Hurt") end
    if #list == 0 then return "Conditions: none" end
    local text = table.concat(list, ", ")
    -- all four at once don't fit after the prefix (mono 12 is ~7px/char)
    if (12 + #text) * 7 > 392 then return text end
    return "Conditions: " .. text
end

function Game:draw_slot_box(x, y, w, h, stack, is_cursor, is_selected)
    if stack and stack.item then
        gfx.color(gfx.LIGHT)
        gfx.fill_rect(x, y, w, h)
        gfx.color(gfx.BLACK)
        local sprite = SPRITES[stack.item]
        if sprite and draw_sprite then
            -- center the 16x16 icon in the slot (// keeps coordinates integers)
            draw_sprite(x + (w - SPRITE_W) // 2, y + (h - SPRITE_H) // 2,
                        SPRITE_W, SPRITE_H, sprite)
        else
            gfx.font(gfx.FONT_MONO_12)
            gfx.text(x + 3, y + h - 5, item_abbr(stack.item))
        end
        if stack.qty and stack.qty > 1 then
            gfx.font(gfx.FONT_MONO_12)
            -- bottom-right corner, right-aligned (mono 12 is ~7px per char), so
            -- it stays clear of the centered 16x16 icon and inside the box
            local qty_text = tostring(stack.qty)
            gfx.text(x + w - 2 - 7 * #qty_text, y + h - 2, qty_text)
        end
    end
    gfx.color(gfx.BLACK)
    gfx.rect(x, y, w, h)
    if is_selected then
        gfx.rect(x - 2, y - 2, w + 4, h + 4)
    elseif is_cursor then
        gfx.rect(x - 1, y - 1, w + 2, h + 2)
    end
end

-- ---------------------------------------------------------------------
-- Paperdoll silhouette
--
-- gfx has no polygon fill, so the body is described as polygons (points are
-- offsets from the body's center line), rasterized ONCE at load into
-- horizontal blocks (runs of identical rows merged into one tall rect), and
-- drawn with fill_rect. Drawing the union in black expanded by 1px and then in
-- gray at true size gives a clean 1px outline around the whole figure, so
-- overlapping parts (arm meeting torso) don't leave internal seams.
-- ---------------------------------------------------------------------

local BODY_CX = 150 + BODY_DX
-- The figure is authored in the coordinates below (head top at y 117, feet at
-- 289) and scaled by BODY_SCALE about its top, landing at BODY_Y0.
local BODY_SCALE, BODY_SRC_Y0, BODY_Y0 = 1.25, 117, 72 + BODY_DY
local BODY_TOP = BODY_Y0
local BODY_BOTTOM = BODY_Y0 + math.ceil((289 - BODY_SRC_Y0) * BODY_SCALE)   -- exclusive

local function mirror_x(pts)
    local out = {}
    for i = 1, #pts, 2 do
        out[i] = -pts[i]
        out[i + 1] = pts[i + 1]
    end
    return out
end

-- Build a full polygon from its right half (listed top to bottom, starting and
-- ending on the center line) by appending the mirrored points in reverse.
local function symmetric(right)
    local pts = {}
    for i = 1, #right do pts[i] = right[i] end
    for i = #right - 1, 1, -2 do
        pts[#pts + 1] = -right[i]
        pts[#pts + 1] = right[i + 1]
    end
    return pts
end

local function ellipse_points(cy, rx, ry, n)
    local pts = {}
    for i = 0, n - 1 do
        local a = 2 * math.pi * i / n
        pts[#pts + 1] = rx * math.cos(a)
        pts[#pts + 1] = cy + ry * math.sin(a)
    end
    return pts
end

local BODY_POLYGONS = {}
local BODY_PART
local function add_body_polygon(pts)
    local out = {}
    for i = 1, #pts, 2 do
        out[i] = pts[i] * BODY_SCALE
        out[i + 1] = BODY_Y0 + (pts[i + 1] - BODY_SRC_Y0) * BODY_SCALE
    end
    BODY_POLYGONS[#BODY_POLYGONS + 1] = out
end

-- head (which part each polygon is: BODY_PART[i], used to paint worn clothes)
BODY_PART = {}
local function add_part(part, pts)
    add_body_polygon(pts)
    BODY_PART[#BODY_POLYGONS] = part
end
add_part("head", ellipse_points(130, 11, 13, 28))
-- neck, sloped shoulders, tapered torso down to the hips
add_part("torso", symmetric({
    0, 139,  4, 139,  4, 146,  14, 148,  27, 151,  31, 156,  30, 164,
    25, 170,  22, 182,  19, 200,  21, 214,  23, 226,  0, 226,
}))
-- arms hang slightly away from the body and end in hands
local ARM = {
    30, 151,  38, 154,  42, 175,  46, 195,  50, 215,  53, 230,
    56, 238,  56, 246,  52, 250,  48, 246,  47, 238,  47, 230,
    43, 215,  37, 195,  31, 178,  27, 166,  28, 158,
}
add_part("arms", ARM)
add_part("arms", mirror_x(ARM))
-- legs: thigh, knee, calf, ankle, and a foot angled outward
local LEG = {
    1, 224,  23, 224,  22, 240,  20, 254,  18, 266,  15, 278,
    20, 284,  21, 288,  3, 288,  3, 282,  5, 270,  4, 254,  2, 240,
}
add_part("legs", LEG)
add_part("legs", mirror_x(LEG))

-- x-intervals [a, b) covered by one polygon on the pixel row whose center is yc
local function polygon_row_spans(pts, yc)
    local xs = {}
    local n = #pts // 2
    for i = 1, n do
        local j = i % n + 1
        local x1, y1 = pts[2 * i - 1], pts[2 * i]
        local x2, y2 = pts[2 * j - 1], pts[2 * j]
        if y1 ~= y2 and ((y1 <= yc and yc < y2) or (y2 <= yc and yc < y1)) then
            xs[#xs + 1] = x1 + (yc - y1) * (x2 - x1) / (y2 - y1)
        end
    end
    table.sort(xs)
    local spans = {}
    for k = 1, #xs - 1, 2 do
        -- Pixel i is covered when its center (i + 0.5) lies strictly inside the
        -- edges. Strict on BOTH sides so an edge landing exactly on a pixel
        -- center is treated the same left and right - keeps the figure symmetric.
        local a = math.floor(BODY_CX + xs[k] - 0.5) + 1
        local b = math.ceil(BODY_CX + xs[k + 1] - 0.5)
        if b > a then spans[#spans + 1] = {a, b} end
    end
    return spans
end

-- part: only that body part's polygons (nil = the whole figure)
local function build_body_blocks(part)
    local blocks, prev_key = {}, nil
    for y = BODY_TOP, BODY_BOTTOM - 1 do
        local all = {}
        for i, poly in ipairs(BODY_POLYGONS) do
            if part == nil or BODY_PART[i] == part then
                for _, sp in ipairs(polygon_row_spans(poly, y + 0.5)) do
                    all[#all + 1] = sp
                end
            end
        end
        table.sort(all, function(p, q) return p[1] < q[1] end)
        local merged = {}
        for _, sp in ipairs(all) do
            local last = merged[#merged]
            if last and sp[1] <= last[2] then
                if sp[2] > last[2] then last[2] = sp[2] end
            else
                merged[#merged + 1] = {sp[1], sp[2]}
            end
        end
        local parts = {}
        for _, m in ipairs(merged) do parts[#parts + 1] = m[1] .. "," .. m[2] end
        local key = table.concat(parts, ";")
        if key ~= "" and key == prev_key then
            blocks[#blocks].h = blocks[#blocks].h + 1
        elseif key ~= "" then
            blocks[#blocks + 1] = {y = y, h = 1, spans = merged}
        end
        prev_key = key
    end
    return blocks
end

local BODY_BLOCKS = build_body_blocks()
local PART_BLOCKS = {}
for _, part in ipairs({"head", "torso", "arms", "legs"}) do
    PART_BLOCKS[part] = build_body_blocks(part)
end

local function body_row(src_y)
    return BODY_Y0 + math.floor((src_y - BODY_SRC_Y0) * BODY_SCALE + 0.5)
end

-- Paint one body part between two authored rows (clothing on the doll).
-- inner/outer (optional, authored units) keep only the pixels whose distance
-- from the center line is in [inner, outer), on both sides.
local function paint_part(part, src_y0, src_y1, color, inner, outer)
    local y0, y1 = body_row(src_y0), body_row(src_y1)
    local bands
    if outer then
        local i = math.floor(inner * BODY_SCALE + 0.5)
        local o = math.floor(outer * BODY_SCALE + 0.5)
        bands = {{BODY_CX - o, BODY_CX - i}, {BODY_CX + i, BODY_CX + o}}
    end
    gfx.color(color)
    for _, b in ipairs(PART_BLOCKS[part]) do
        local top, bottom = math.max(b.y, y0), math.min(b.y + b.h, y1)
        if bottom > top then
            for _, sp in ipairs(b.spans) do
                if bands then
                    for _, band in ipairs(bands) do
                        local a, z = math.max(sp[1], band[1]), math.min(sp[2], band[2])
                        if z > a then gfx.fill_rect(a, top, z - a, bottom - top) end
                    end
                else
                    gfx.fill_rect(sp[1], top, sp[2] - sp[1], bottom - top)
                end
            end
        end
    end
end

-- Draw order for painting worn items: under-layers before over-layers.
-- Held items (lhand/rhand) are never painted on, only shown in their box.
local WEAR_ORDER = {"shirt", "pants", "jacket", "back", "feet", "hands", "head", "neck",
                    "wrists", "eyes", "ears"}

function Game:draw_silhouette()
    -- pass 1: outline (every block grown by 1px, black)
    gfx.color(gfx.BLACK)
    for _, b in ipairs(BODY_BLOCKS) do
        for _, sp in ipairs(b.spans) do
            gfx.fill_rect(sp[1] - 1, b.y - 1, sp[2] - sp[1] + 2, b.h + 2)
        end
    end
    -- pass 2: body fill at true size
    gfx.color(gfx.LIGHT)
    for _, b in ipairs(BODY_BLOCKS) do
        for _, sp in ipairs(b.spans) do
            gfx.fill_rect(sp[1], b.y, sp[2] - sp[1], b.h)
        end
    end
    -- pass 3: worn clothes painted onto the body, inner layers first
    for _, slot in ipairs(WEAR_ORDER) do
        local item = self.player.equipped[slot]
        local wear = item and ITEM_DB[item].wear
        if wear then
            for _, w in ipairs(wear) do
                paint_part(w[1], w[2], w[3], gfx[w[4]], w[5], w[6])
            end
        end
    end
end

-- Dashed outline: a slot's frame on the doll (the cursor gets a solid one).
local function dashed_rect(x, y, w, h)
    for dx = 0, w - 1, 4 do
        local len = math.min(2, w - dx) - 1
        gfx.line(x + dx, y, x + dx + len, y)
        gfx.line(x + dx, y + h - 1, x + dx + len, y + h - 1)
    end
    for dy = 0, h - 1, 4 do
        local len = math.min(2, h - dy) - 1
        gfx.line(x, y + dy, x, y + dy + len)
        gfx.line(x + w - 1, y + dy, x + w - 1, y + dy + len)
    end
end

local HALO = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}

-- One paperdoll slot, framed by a dashed outline over the body part. Worn:
-- the clothes are already painted on the doll (draw_silhouette); the item's
-- icon sits on top. Empty: the slot's name on a small white tag so it reads
-- on the dithered gray.
function Game:draw_equip_slot(slot, x, y, w, h, is_cursor, is_selected)
    local item = self.player.equipped[slot]
    gfx.font(gfx.FONT_MONO_12)
    if item then
        -- the item sits on the (painted) body: black icon with a 1px white
        -- halo so it reads on any fill, inside the slot's dashed frame
        local sprite = SPRITES[item]
        local sx, sy = x + (w - SPRITE_W) // 2, y + (h - SPRITE_H) // 2
        if sprite and draw_sprite then
            gfx.color(gfx.WHITE)
            for _, d in ipairs(HALO) do
                draw_sprite(sx + d[1], sy + d[2], SPRITE_W, SPRITE_H, sprite)
            end
            gfx.color(gfx.BLACK)
            draw_sprite(sx, sy, SPRITE_W, SPRITE_H, sprite)
        else
            gfx.color(gfx.WHITE)
            gfx.fill_rect(sx + 3, sy + 2, 11, 13)
            gfx.color(gfx.BLACK)
            gfx.text(sx + 5, sy + 12, item_abbr(item))
        end
        gfx.color(gfx.BLACK)
        dashed_rect(x, y, w, h)
    else
        local label = EQUIP_NAME[slot]
        if 7 * #label + 4 > w then label = EQUIP_ABBR[slot] end
        local tw = 7 * #label
        local tx, ty = x + (w - tw) // 2, y + h // 2 + 4
        gfx.color(gfx.WHITE)
        gfx.fill_rect(tx - 1, ty - 9, tw + 2, 11)
        gfx.color(gfx.BLACK)
        gfx.text(tx, ty, label)
        dashed_rect(x, y, w, h)
    end
    if is_selected or is_cursor then
        -- white inner line keeps the cursor visible over black clothes
        gfx.color(gfx.WHITE)
        gfx.rect(x, y, w, h)
    end
    gfx.color(gfx.BLACK)
    if is_selected then
        gfx.rect(x - 2, y - 2, w + 4, h + 4)
        gfx.rect(x - 1, y - 1, w + 2, h + 2)
    elseif is_cursor then
        gfx.rect(x - 1, y - 1, w + 2, h + 2)
    end
end

-- What the cursor is on, e.g. "Head: Cap" or "Bag: Rock x3".
function Game:cursor_description()
    local row = INV_ROWS[self.inv_cursor]
    if not row then return "" end
    local kind, key = row[1], row[2]
    local stack = self:get_stack(kind, key)
    local where = kind == "ground" and "Ground" or kind == "inventory" and "Bag"
        or EQUIP_NAME[key]
    if not stack then return where .. ": empty" end
    local text = where .. ": " .. ITEM_DB[stack.item].name
    if stack.qty > 1 then text = text .. " x" .. stack.qty end
    return text
end

function Game:draw_inventory(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(4, 12, "Up/Dn Enter:move E:use I:map")

    INV_ROWS = {}
    INV_POS = {}

    local function add_row(kind, key, x, y, w2, h2)
        table.insert(INV_ROWS, {kind, key})
        -- no x: selectable but scrolled out of view, so it gets no position
        INV_POS[#INV_ROWS] = x and {x = x, y = y, w = w2, h = h2} or nil
    end

    -- ground items grid. Every ground stack is a cursor row (ground rows come
    -- first, so cursor index == ground index), but only GROUND_GRID_ROWS rows
    -- of cells fit above the paperdoll: scroll the window to keep the cursor
    -- in view and give off-screen stacks no position.
    local ground = self:ground_list()
    -- one extra, empty cell after the last stack: somewhere to drop things
    local n_ground = #ground + 1
    local per_page = GROUND_GRID_COLS * GROUND_GRID_ROWS
    local off = self.ground_off or 0
    if self.inv_cursor <= n_ground then
        local crow = (self.inv_cursor - 1) // GROUND_GRID_COLS
        local first = off // GROUND_GRID_COLS
        if crow < first then
            off = crow * GROUND_GRID_COLS
        elseif crow >= first + GROUND_GRID_ROWS then
            off = (crow - GROUND_GRID_ROWS + 1) * GROUND_GRID_COLS
        end
    end
    local total_rows = (n_ground + GROUND_GRID_COLS - 1) // GROUND_GRID_COLS
    off = math.max(0, math.min(off, (total_rows - GROUND_GRID_ROWS) * GROUND_GRID_COLS))
    self.ground_off = off
    local label = "Ground"
    if #ground > per_page then
        label = label .. " " .. (off + 1) .. "-" .. math.min(#ground, off + per_page)
            .. "/" .. #ground
    end
    gfx.text(INV_COL_X, GROUND_Y - 5, label)
    for i = 1, n_ground do
        if i > off and i <= off + per_page then
            local col = (i - off - 1) % GROUND_GRID_COLS
            local row = (i - off - 1) // GROUND_GRID_COLS
            local x = INV_COL_X + 2 + col * (GROUND_CELL + GROUND_GAP)
            local y = GROUND_Y + row * (GROUND_CELL + GROUND_GAP)
            add_row("ground", i, x, y, GROUND_CELL, GROUND_CELL)
        else
            add_row("ground", i)
        end
    end

    -- equipped slots (positioned near the body, not listed)
    for _, slot in ipairs(EQUIP_SLOTS) do
        local r = EQUIP_RECT[slot]
        add_row("equip", slot, r[1], r[2], r[3], r[4])
    end

    -- bag: one cell per unit of capacity. Every stack is a row, plus the
    -- first empty cell (a drop target); the other empty cells are just drawn.
    local capacity = self:bag_capacity()
    local n_inv = #self.player.inventory
    local function bag_cell(i)
        local col = (i - 1) % BACKPACK_COLS
        local row = (i - 1) // BACKPACK_COLS
        return INV_COL_X + 2 + col * (BACKPACK_CELL + BACKPACK_GAP),
               BACKPACK_Y + row * (BACKPACK_CELL + BACKPACK_GAP)
    end
    for i = 1, math.min(math.max(n_inv, math.min(n_inv + 1, capacity)), BACKPACK_CAP) do
        local x, y = bag_cell(i)
        add_row("inventory", i, x, y, BACKPACK_CELL, BACKPACK_CELL)
    end

    self.inv_cursor = math.max(1, math.min(self.inv_cursor, #INV_ROWS))

    -- draw ground + backpack cells
    for i, row in ipairs(INV_ROWS) do
        if (row[1] == "ground" or row[1] == "inventory") and INV_POS[i] then
            local pos = INV_POS[i]
            local stack = self:get_stack(row[1], row[2])
            self:draw_slot_box(pos.x, pos.y, pos.w, pos.h, stack,
                i == self.inv_cursor,
                self.inv_selected and self.inv_selected[1] == row[1] and self.inv_selected[2] == row[2])
        end
    end

    for i = n_inv + 2, capacity do
        local x, y = bag_cell(i)
        self:draw_slot_box(x, y, BACKPACK_CELL, BACKPACK_CELL, nil, false, false)
    end

    gfx.color(gfx.BLACK)
    gfx.text(4, CONDITIONS_Y, self:current_conditions())

    -- silhouette + equip slots
    self:draw_silhouette()
    for i, row in ipairs(INV_ROWS) do
        if row[1] == "equip" then
            local pos = INV_POS[i]
            self:draw_equip_slot(row[2], pos.x, pos.y, pos.w, pos.h,
                i == self.inv_cursor,
                self.inv_selected and self.inv_selected[1] == row[1] and self.inv_selected[2] == row[2])
        end
    end

    -- what the cursor is on, under the bag
    gfx.color(gfx.BLACK)
    local desc = self:cursor_description()
    local max_chars = (w - INV_COL_X - 2) // 7
    if #desc > max_chars then desc = desc:sub(1, max_chars) end
    gfx.text(INV_COL_X, CURSOR_DESC_Y, desc)

    local back = self.player.equipped.back
    gfx.text(INV_COL_X, BAG_LABEL_Y, (back and ITEM_DB[back].name or "Pockets")
        .. " " .. n_inv .. "/" .. capacity)

    -- log: the newest INV_LOG_LINES lines, the last one at h - 8
    local ly = h - 8 - 12 * (INV_LOG_LINES - 1)
    local start_i = math.max(1, #self.log - INV_LOG_LINES + 1)
    for i = start_i, #self.log do
        gfx.text(4, ly, self.log[i])
        ly = ly + 12
    end

    gfx.refresh()
end

-- ---------------------------------------------------------------------
-- Character creator screen
-- rows 1..#ATTRIBUTES are attributes, the rest are TRAITS in order
-- ---------------------------------------------------------------------

local CREATOR_ROWS = #ATTRIBUTES + #TRAITS
-- attributes in the left column, traits in the right (from CREATOR_TRAIT_X),
-- the highlighted row's description and the resulting build below both
local CREATOR_ATTR_Y, CREATOR_TRAIT_Y, CREATOR_ROW_H = 52, 52, 14
local CREATOR_TRAIT_X = 200

function Game:creator_key(key)
    local p = self.player
    local row = self.creator_cursor
    self.creator_msg = nil
    if key == gfx.KEY_UP or key == KEY_W then
        self.creator_cursor = math.max(1, row - 1)
    elseif key == gfx.KEY_DOWN or key == KEY_S then
        self.creator_cursor = math.min(CREATOR_ROWS, row + 1)
    elseif (key == gfx.KEY_LEFT or key == KEY_A or key == gfx.KEY_RIGHT or key == KEY_D)
        and row <= #ATTRIBUTES then
        local name = ATTRIBUTES[row]
        local up = key == gfx.KEY_RIGHT or key == KEY_D
        if up and p.attrs[name] < ATTR_MAX and attr_points_left(p.attrs) > 0 then
            p.attrs[name] = p.attrs[name] + 1
        elseif up and attr_points_left(p.attrs) <= 0 then
            self.creator_msg = "No points left: lower another first."
        elseif not up and p.attrs[name] > ATTR_MIN then
            p.attrs[name] = p.attrs[name] - 1
        end
        recompute_stats(p)
    elseif key == KEY_SPACE and row > #ATTRIBUTES then
        local t = TRAITS[row - #ATTRIBUTES]
        p.traits[t.name] = not p.traits[t.name] or nil
        recompute_stats(p)
    elseif key == KEY_ENTER or key == KEY_LF then
        self:start_game()
    end
end

function Game:draw_creator(w, h)
    local p = self.player
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, "Create your survivor")
    gfx.font(gfx.FONT_MONO_12)

    gfx.text(6, 36, "Attributes  left " .. attr_points_left(p.attrs))
    for i, name in ipairs(ATTRIBUTES) do
        local y = CREATOR_ATTR_Y + (i - 1) * CREATOR_ROW_H
        local v = p.attrs[name]
        gfx.text(6, y, (self.creator_cursor == i and ">" or " ") .. name)
        for c = 1, ATTR_MAX do
            local cx = 100 + (c - 1) * 12
            if c <= v then gfx.fill_rect(cx, y - 9, 10, 9) else gfx.rect(cx, y - 9, 10, 9) end
        end
        gfx.text(176, y, tostring(v))
    end

    local tleft = trait_points_left(p.traits)
    gfx.text(CREATOR_TRAIT_X, CREATOR_TRAIT_Y - 16, "Traits  left " .. tleft)
    for i, t in ipairs(TRAITS) do
        local row = #ATTRIBUTES + i
        local y = CREATOR_TRAIT_Y + (i - 1) * CREATOR_ROW_H
        local mark = p.traits[t.name] and "[x] " or "[ ] "
        gfx.text(CREATOR_TRAIT_X, y, (self.creator_cursor == row and ">" or " ") .. mark .. t.name)
        -- what it does to the budget: positives spend, negatives give
        local cost = (t.cost > 0 and "-" or "+") .. math.abs(t.cost)
        gfx.text(w - 6 - 7 * #cost, y, cost)
    end

    -- the highlighted row explained, then the build it gives
    local y = CREATOR_TRAIT_Y + #TRAITS * CREATOR_ROW_H + 6
    gfx.line(6, y - 10, w - 6, y - 10)
    local row = self.creator_cursor
    local desc = row <= #ATTRIBUTES and ATTR_DESC[ATTRIBUTES[row]]
        or TRAITS[row - #ATTRIBUTES].desc
    gfx.text(6, y + 4, desc)
    local bag = ITEM_DB.backpack.bag_cells + p.bag_bonus
    gfx.text(6, y + 20, "MP " .. p.max_mp .. " Sight " .. p.sight .. " Finds " .. p.scav_rolls
        .. " Duds " .. dud_percent(p.attrs.Perception) .. "%")
    gfx.text(6, y + 34, "Bag " .. math.max(2, math.min(BACKPACK_CAP, bag)) .. " cells (backpack)")
    if self.creator_msg then
        gfx.text(6, y + 50, self.creator_msg)
    elseif tleft < 0 then
        gfx.text(6, y + 50, "Trait points below 0: can't start.")
    end

    gfx.text(6, h - 20, "Up/Dn row  L/R attribute")
    gfx.text(6, h - 8, "Spc trait  Enter start  Q quit")
    gfx.refresh()
end

-- Encounter screen: name, description, what just happened, status, and the
-- numbered choices (at most 7 rows fit above the bottom edge).
function Game:draw_encounter(w, h)
    local e, p = self.enc, self.player
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 16, e.def.name)
    gfx.font(gfx.FONT_MONO_12)
    for i, line in ipairs(e.intro) do gfx.text(6, 22 + 13 * i, line) end
    gfx.line(6, 114, w - 6, 114)
    for i, line in ipairs(e.msg) do gfx.text(6, 116 + 13 * i, line) end
    local status = "You " .. math.floor(p.health) .. " HP"
    if p.injuries.bleeding then status = status .. " bleeding" end
    if e.def.kind ~= "helper" then
        status = "Range " .. RANGE_NAME[e.range] .. "   " .. status
            .. "   It: " .. (e.seen and self:enemy_condition() or "?")
    end
    gfx.text(6, 186, status)
    gfx.line(6, 192, w - 6, 192)
    for i, o in ipairs(self:encounter_options()) do
        gfx.text(6, 194 + 13 * i, (i == e.cursor and ">" or " ") .. i .. " " .. o[1])
    end
    gfx.refresh()
end

function Game:draw_dead(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 40, "You are dead.")
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(6, 70, self.death_cause or "")
    gfx.text(6, 90, "You lasted " .. self.player.hours .. " hours in the wasteland.")
    gfx.text(6, h - 8, "Enter: new survivor  Q: quit")
    gfx.refresh()
end

-- ---------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------

gfx.begin()

local ok, err = pcall(function()
    local game = Game.new()
    local w, h = gfx.size()

    local function handle_map_key(key)
        if key == gfx.KEY_ESCAPE or key == KEY_Q then
            game.quit = true
        elseif key == gfx.KEY_LEFT or key == KEY_A then
            game:move_dir(-1, 0)
        elseif key == gfx.KEY_RIGHT or key == KEY_D then
            game:move_dir(1, 0)
        elseif key == gfx.KEY_UP or key == KEY_W then
            game:move_dir(0, -1)
        elseif key == gfx.KEY_DOWN or key == KEY_S then
            game:move_dir(0, 1)
        elseif key == KEY_SPACE then
            game:rest()
        elseif key == KEY_F then
            game:scavenge()
        elseif key == KEY_I then
            game.screen = "inventory"
            game.inv_cursor = 1
            game.inv_selected = nil
        end
    end

    local function handle_inventory_key(key)
        if key == gfx.KEY_ESCAPE or key == KEY_Q then
            game.quit = true
        elseif key == KEY_I then
            game.screen = "map"
        elseif key == gfx.KEY_UP or key == KEY_W or key == gfx.KEY_LEFT or key == KEY_A then
            game.inv_cursor = math.max(1, game.inv_cursor - 1)
        elseif key == gfx.KEY_DOWN or key == KEY_S or key == gfx.KEY_RIGHT or key == KEY_D then
            game.inv_cursor = math.min(#INV_ROWS, game.inv_cursor + 1)
        elseif key == KEY_E then
            local row = INV_ROWS[game.inv_cursor]
            if row then
                game:use_item(row[1], row[2])
                -- the stack may be gone or shifted; don't keep a stale pick
                game.inv_selected = nil
            end
        elseif key == KEY_ENTER or key == KEY_LF or key == KEY_SPACE then
            local row = INV_ROWS[game.inv_cursor]
            if row then
                if game.inv_selected == nil then
                    if game:get_stack(row[1], row[2]) ~= nil then
                        game.inv_selected = {row[1], row[2]}
                    end
                else
                    game:try_transfer(game.inv_selected, {row[1], row[2]})
                    game.inv_selected = nil
                end
            end
        end
    end

    -- Redraw only after a key was handled: nothing changes on its own, and a
    -- full frame is hundreds of gfx calls plus a panel refresh.
    local dirty = true
    while not game.quit and not solaros.should_exit() do
        if dirty then
            if game.screen == "creator" then
                game:draw_creator(w, h)
            elseif game.screen == "dead" then
                game:draw_dead(w, h)
            elseif game.screen == "encounter" then
                game:draw_encounter(w, h)
            elseif game.screen == "map" then
                game:draw_map(w, h)
            else
                game:draw_inventory(w, h)
            end
            dirty = false
        end

        local key = gfx.getch(POLL_MS)
        if key ~= nil then
            if game.screen == "creator" then
                if key == gfx.KEY_ESCAPE or key == KEY_Q then
                    game.quit = true
                else
                    game:creator_key(key)
                end
            elseif game.screen == "encounter" then
                game:encounter_key(key)
            elseif game.screen == "dead" then
                if key == gfx.KEY_ESCAPE or key == KEY_Q then
                    game.quit = true
                elseif key == KEY_ENTER or key == KEY_LF then
                    game = Game.new()   -- a fresh world and the creator
                end
            elseif game.screen == "map" then
                handle_map_key(key)
            else
                handle_inventory_key(key)
            end
            dirty = true
        end
    end
end)

-- Per SolarOS convention: cleanup must run even when drawing/logic fails,
-- and the error is re-raised afterward so it still surfaces (with a real
-- traceback) instead of being silently swallowed.
gfx["end"]()
if not ok then
    error(err)
end
