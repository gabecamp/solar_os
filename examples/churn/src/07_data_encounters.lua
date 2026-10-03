-- ---------------------------------------------------------------------
-- Encounters: rolled after each move. A fight is a series of choices at a
-- range (far -> near -> close); every choice is a dice roll against an
-- attribute, then the other side acts.
-- ---------------------------------------------------------------------

-- Fight and encounter numbers, as one table (the bundle has a 200-local limit).
local FIGHT = {
    ENCOUNTER_CHANCE = {plains = 10, forest = 15, hills = 12, ruins = 14, ford = 8},   -- % per move onto it
    ENCOUNTER_COOLDOWN = 2,                                 -- moves after an encounter before another can happen
    PLAYER_HIT = 55,                                        -- % to hit, +8 per Speed over 3
    WATCH_AIM = 15,                                         -- extra % on your next hit after a good look
    THROW_HIT = 50,                                         -- % to hit with a throw, +8 per Perception over 3
    WATCH_CHANCE = 60,                                      -- % to read the enemy, +10 per Perception over 3
    HIDE_CHANCE = 35,                                       -- % at Far, +10 per Perception over 3, -10 vs animals
    FLEE_CHANCE = {far = 70, near = 50, close = 30},        -- +10 per Speed over the enemy's
    ADVANCE_CHANCE = 60,                                    -- % an enemy closes in per turn, +10 per speed over yours
    ENEMY_DODGE = 5,                                        -- enemy hit % lost per point of your Speed over 3
    WOUND_DAMAGE = 12,                                      -- one enemy hit this hard leaves a wound
    ENEMY_BLEED_DMG = 3,                                    -- per turn while an enemy bleeds
    ENEMY_FLEE_CHANCE = 30,                                 -- % per turn a beaten enemy (hp <= flees_at) runs
}
local ENCOUNTER_KINDS = {{"animal", 40}, {"mutant", 25}, {"anomaly", 20},
                         {"bandit", 12}, {"helper", 3}}
local RANGE_NAME = {far = "Far", near = "Near", close = "Close"}
local CLOSER = {far = "near", near = "close"}
local FARTHER = {close = "near", near = "far"}
local FISTS = {dmg = 4, reach = "close"}

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
     intro = "A hooded man in a torn raincoat. His mouth is sewn shut corner to "
          .. "corner, the stitches long since healed in, and a second seam runs down "
          .. "his throat. He breathes through it, wet and fast now he has seen you.",
     talk = "He tries to answer. The seam in his throat flutters uselessly.",
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
     intro = "A great bronze bell hangs over a pool that wasn't here yesterday, and "
          .. "nothing holds it up. It tolls with no one to ring it; the water ripples "
          .. "in rings, and something far below answers."},
    {kind = "anomaly", name = "Wrong Stars", art = "stars", who = "wrong stars",
     intro = "At midday a patch of sky above you goes black, in the shape of an eye, "
          .. "and fills with stars no one has named. You have the strong feeling that "
          .. "something up there has noticed you looking."},
    {kind = "anomaly", name = "The Stillness", art = "stillness", who = "stillness",
     intro = "Ahead, birds hang motionless in mid-flight, and in a shaft of light a "
          .. "hand reaches up out of the earth toward them. When you step closer, every "
          .. "sound stops, even your own heartbeat."},
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

