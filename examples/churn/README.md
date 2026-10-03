# The Churn (file: churn.lua)

A NEO Scavenger-style survival game for SolarOS, made for the Waveshare
ESP32-S3 RLCD 4.2 (400x300, 1-bit). Make a survivor, cross a fogged hex map
of the Churn, stay fed, warm and out of the radiation, and get out through
the Checkpoint alive.

- **Install:** copy `churn.lua` to the device and run it with the `lua`
  app. Saving (Continue, and the records) needs SolarOS 4.15.17 or newer,
  which added `solaros.storage.write_file`; on older firmware the game runs
  but can't save.
- **Keys:** Left/Right step west/east; Up or Down then Left/Right takes
  a diagonal (Up, Right = up-right; the hexes have six sides); WASD works
  the same. Space rests, F searches, I opens the bag,
  C crafts, E uses, G hunts or fishes, T trades, J opens the journal,
  R calls on the radio, M mutes, Q quits. **H** in game lists every key.
- **You start with nothing:** no clothes, no shoes, no bag, and you know
  almost nothing. Your arms hold two things. The crafting screen (C) knows
  only how to survive the first day: a torch, a fire (the pile you wake next
  to has sticks, a rock and a box of matches), a bandage, foot wraps, a rag
  shirt and trousers, a bindle (5 cells), patching, cooking and boiling.
  Makeshift clothes are as warm as the real thing but hold less: fewer
  pockets, a smaller bag.
- **Everything else is learned** (see *Crafting and research* below): study
  by a fire or at your camp, read books, play the dead's cassettes, or let
  the LoRa radio read a USB drive. The T-shirt, jeans, boots and backpack you used
  to start in are lying somewhere 2 to 6 hexes away. A backpack holds 10,
  a satchel 6, jeans and a jacket 2 pockets each, a belt 1 or 2.
- **Clothes wear out:** a little every day, more under an enemy's blows and
  out in a storm; rags twice as fast. A torn piece (the bag shows "40%" or
  "(torn)" under the cursor) gives no warmth and holds half as much until
  you patch it: **Patch clothes** on the crafting screen, 1 cloth scrap.
- **On a PC or Raspberry Pi:** `python_version/` runs this same game in a
  pygame window. One command installs it: `install.sh` on Linux or a Pi,
  `install.ps1` on Windows (see its README), or by hand `pip install pygame lupa`,
  then `python3 python_version/churn_pygame.py`.
- **More:** `LORE.md` is the world's lore and how everyone and everything
  connects (spoilers from its section 9); `DEVICE_TEST.md` is a 10-minute check on the board;
  `HANDOFF.md` is the developer guide (code map, tests, tools).

---

## Crafting and research

Recipes are grouped into seven topics. Each teaches its recipes in order,
simplest first:

| Topic | Its book | Teaches, for example |
|---|---|---|
| Tailoring | Seamstress's Almanac | string, rope, rag gear, a sack pack, rag shoes, a foil poncho, hide gloves/tunic/pack, a pelt coat |
| Bushcraft | Field Manual | stone knife, glass shiv, spear, snare, fishing rod, bark tea, cured hide, charcoal, smoked meat, a sling, a bow and arrows, a can rattle, a tarp lean-to, a travois |
| Medicine | Surgeon's Notes | filtered water, splints, a suture kit, herb tincture, a medkit |
| Tinkering | Radio Ham Handbook | shiv, machete, rain barrel, lockpicks, cracking a phone, the Choir Cell, a hand cart |
| Chemistry | Institute Lab Book | painkillers, gunpowder, flares, sedatives, gun oil, Rad Purge |
| Gunsmithing | Gunsmith's Ledger | cleaning guns, reloading rounds, assembling the PM, Nagant, Tokarev and Institute Sidearm |
| Warding | The Choir Hymnal | a salt circle, the Elder Sign, a black candle, a glow jar, a choir charm |

- **Study** (crafting screen, *Study: topic*, by a fire or at your camp):
  3 hours for research points, more with a high Perception and with the
  topic's book in reach (x2). Enough points teach the next recipe.
  Chemistry needs chemicals to work with, Gunsmithing a gun or a gun part,
  and Warding something of *theirs* (black ichor, a pale eye). Warding takes
  something out of you each time.
- **Books** (E): the first read teaches the next recipe in the topic; a
  reread only helps.
- **Cassettes** (E): a Cassette Player with charge (a Battery Cell, E) plays
  the logs of dead stalkers. Each tape teaches once, and some mention a stash.
- **USB drives** (E): with a LoRa Radio, a charge reads a drive: one or two
  recipes, sometimes a map to the Checkpoint or a stash. Corrupt drives fail
  and can be tried again. Locked phones crack open (Tinkering) into a drive.
- **Scrawled Notes** still teach a random recipe.

**Properties:** many recipes ask for a kind of thing instead of one item,
as NEO Scavenger does: any *sharp edge* (glass shard, stone knife, scalpel,
screwdriver, crowbar, shiv, kitchen knife, hacksaw, multitool, knife,
hunting knife, machete, broad spear), any *thread* (string, sinew, choir
wire, copper wire, rope), any *fireproof pot* (tin can, metal pot; a plastic
bottle melts), any *heat source* (fire drill, matches, lighter, torch), any
*fuel*, *shaft* or *hide*. A craft uses the cheapest thing that fits, so the
glass goes before your knife. A fire needs a heat source, and boiling or
cooking needs a pot (the empty tin from the beans is your first).

**Placed things:** E sets a Can Rattle (something coming at you is heard
first), pitches a Tarp Lean-to (cover from storms and emissions anywhere) or
pours a Salt Circle (night horrors keep away from the hex).

**Lockpicks** open the locked crates hidden in some ruins (search with F).
They hold the rare things: lab books, ledgers, gunsmith kits, frames, rounds
and the odd whole gun.

## Handguns

Guns are rare and loud. Hold one with its rounds in reach, and a fight
offers **Shoot** at any range. Each shot uses a round, wears the gun a
little (a worn gun jams more; *Clean Guns* with gun oil and a rag fixes
that) and is heard for hours, so more things come looking. Animals may
bolt at the noise.

| Gun | Rounds | Notes |
|---|---|---|
| PM Pistol | 9x18 | the commonest; bandits carry them |
| Nagant Revolver | 7.62N | never jams, a little less accurate |
| Tokarev TT | 7.62x25 | hits hardest of the pistols |
| Institute Sidearm | 9x18 | precise, rarely jams; its frame has no maker's mark |
| The Marsh Revolver | .38 | one per world, never made. Hits like nothing else, and every shot costs you rest. Something counts them. |

Most guns are **assembled** (Gunsmithing): a frame (it decides the gun) plus
a slide, barrel, recoil spring, firing pin and magazine (a cylinder for the
Nagant), with a Gunsmith Kit or a Multitool. It can fail, and then a part
breaks. Rounds **reload** from brass casings, gunpowder and lead (.38s want
black ichor too). The **bow** (arrows) and **sling** (rocks) shoot quietly.

---

## The Churn

Years ago there was an Institute out by the old quarry. The town around it
was told the hum from the quarry was a transformer fault, and not to talk
about the birds. Lorries came and went at night with crates that were warm
to the touch, and one of them, a driver swore, was singing.

Then one night the sky over the quarry turned purple, and it **breathed**.
Nobody who was outside lived. The people in the cellars came up two days
later into fields that had changed: grass growing in spirals, dogs that
came back wrong. That was the **first emission**. The town was evacuated:
assemble at the school, bring nothing, no pets, *nothing that is warm to
the touch*.

What was left became **the Churn**, fenced off behind a military
**Checkpoint** that lets no one out without paper.

What the Churn is like now:

- **Emissions.** The sky still breaks open every few days (the first about
  two days in, then every 60-110 hours). You get about ten hours' warning;
  get under cover in **ruins** or **hills** or take the damage and the rads.
- **Radiation.** Some ground is hot. Without a **Geiger counter** you
  can't measure it: you only feel unwell, and some things in your bag go
  by vaguer names. With one, it clicks and marks the hot hexes.
- **Artifacts.** Hot ground and anomalies leave strange objects behind: the
  Weeping Stone, the Drowned Eye, the Flesh Knot, the Hollow Star, the
  Quiet Shell. They're worth a lot, some change you while you hold them,
  and three of them will buy your way out.
- **Night.** From 20:00 to 06:00 your sight shrinks unless you carry a
  light, and other things come out.
- **Seasons and weather.** A run starts in late Autumn; each season lasts
  10 days (Autumn, Winter, Spring, Summer, round again). Winter is colder,
  with snow and less food; Summer is hot and thirsty, with storms; Autumn
  has the most to forage. **Fog** shortens your sight, and things are on
  you before you see them (but it's easier to hide). A **storm** out on
  open plains or a ford wears you down hour by hour: get into ruins, hills
  or trees and wait it out.
- **The way out.** Find the **Trader** in the ruined town; he'll tell you
  where the **Checkpoint** is. Bring a **Churn Permit**, or 3 artifacts.

---

## People of the Churn

### The Trader
- **Role:** keeps a stall behind a barricade at the center of the ruined
  town (always a ruins hex). **T** on his hex opens barter. He asks 1.5x
  what your goods are worth and restocks every 48 hours. He sells
  Anti-Rad, food and water, a Geiger counter, a gas mask, a Multitool and
  the one **Churn Permit** in the Churn (it's expensive). The first time you
  reach him he tells you where the Checkpoint is.
  - **Work (O on the trade screen):** *"Bring me an artifact"* (paid in
    Anti-Rad, food and a Battery Cell), or *"Something's denned up out
    there, killing my runners. Clear it."* (a beast with half again its
    usual health, 5-9 hexes out; paid with a Multitool, gas mask or
    machete).
  - **On the radio ("Trader's net"):** points you at the way out and
    leaves supply parcels. Once every 3 days.
- **Lore:** he calls everyone "friend", keeps the only Churn Permit for
  sale behind his counter, and has runners out in the Churn, some of whom
  don't come back (that's the den job).

### Mother Okun, at the Ferry Post
- **Role:** a second place to trade, a few ruined huts and a jetty on a
  river far from the town. Her prices are kinder (1.3x value) and she
  stocks what the town trader doesn't: a fishing rod, snares, rope,
  fish, copper wire, a battery cell. She knows the way out too.
  - **Work (O on her screen):** *"Bring me three fish."* Paid with two
    snares and a Lucky Lure.
- **Lore:** she ran the ferry before the evacuation and never left. The
  boat hasn't crossed in years, but she still feeds the men who sleep on
  it, and she trades so they can eat. *"Ferry's not running. Trading is."*

### The Peddler
- **Role:** a man pushing a rattling handcart on a round of seven stops
  around the Churn, half a day at each. When you see him he goes in your
  journal (where and when). **T** on his hex to trade: odd things the
  Churn gives up, batteries, wire, the occasional torn page or broken
  device. He doesn't take work.
- **Lore:** nobody has seen where he sleeps. The cart never seems to get
  emptier or fuller, and he always knows which way the next storm is
  coming from. *"Everything rattles. Everything's for sale."*

### The sergeant at the Checkpoint
- **Role:** the end of the game. The Checkpoint is a guard tower on the
  edge of the map, as far from the town as it gets. **T** there: show a
  Churn Permit, or hand over 3 artifacts, and you're out. With neither you
  can only walk away.
- **Lore:** concrete blocks, razor wire, a searchlight that never goes
  off, and a sergeant in a gas mask. The standing orders say no one leaves
  without paper, all objects are confiscated, nobody holds an object
  longer than necessary, and *if an object speaks, report to the
  sergeant*. Take the bribe route and one of the guards starts to cry
  without knowing why.

### Karl (K-A-R-L)
- **Role:** a rare fisherman who only turns up by rivers: a 3% chance per
  move onto a ford or next to water, 10% after you fish, and then not for
  another 4 days. He asks a **riddle** (six of them, never repeated until
  you've heard them all) with three answers to pick from.
  - **Right:** he gives you something. It might be **Pilk** (Pepsi and
    milk: a big drink that also feeds and rests you; *"Karl swears by
    it"*), a **Fishing Rod**, a **Lucky Lure** (+15% to fish, just
    carried), **Karl's Waders** (+10% fishing, warm feet) or **Karl's
    Bucket Hat** (+10% fishing). He never gives the same gear twice.
  - **Wrong:** *"Wrong. The river keeps its secrets."* He wades off
    laughing. No harm done.
  - After a right answer he may ask you to find his **old dog**, lost
    somewhere along the river 4-8 hexes away. She pays you back with
    whichever of his waders or hat you don't have, or two Pilks.
  - **On the radio ("Karl, 433 MHz"):** fishing tips, when the next
    emission is due, and a hint for his next riddle. Every 2 days.
- **Lore:** he has fished this river for forty years. The fish came back
  with too many eyes and still bite at dusk. Written on his tackle box
  lid: *"A river doesn't care what happened. That's the comfort of it."*
  (His portrait is a placeholder until his own photo is added.)

### Anna, the old medic
- **Role:** a voice on the **LoRa radio** ("Anna, old medic"). Call her
  when you're hurt and she talks you through first aid: +20 HP and the
  bleeding stops. Once every 3 days.
  - **Her request:** *"We're out of bandages. Call me when you've two to
    spare."* Call with 2 bandages on you and a runner brings a Medkit and
    two bottles of water. After that her line stays open.
- **Lore:** when the doctors were ordered out, she stayed. *"Somebody has
  to sew up the fools who come back for the money."* She keeps a candle in
  the window, and nobody asks why. Somewhere near her there are children
  who sleep better for your bandages.

### The Old Medic and the Wanderer
Two rare kind faces on the road (encounters, not radio voices).
- **The Old Medic:** an old woman with a red cross painted on her pack.
  She cleans and binds your wounds without a word (+25 HP, stops the
  bleeding, eases wounds) and leaves you two strips of clean cloth.
- **The Wanderer:** a man with a walking stick by a small fire, no weapon
  in sight: *"Sit a minute. I don't bite. Not like the rest of them out
  there."* He draws the land around you in the dirt (the map within 3
  hexes is revealed), gives you a bottle of clean water, and tells you
  about the Checkpoint or the trader's town. *"Stay off the roads at
  night."*

### Road Bandits and the Toll Man
- **Role:** people who want what you carry, met on the road. **Road Bandits** step out from
  behind a wrecked car: *"Nobody has to get hurt. That part is up to
  you."* The **Toll Man**, in a welding mask, taps a lead pipe against his
  leg: *"Toll road. Pay up or bleed."* Give them some food, fight, or
  run.
- **Lore:** the Churn's own economy. Everyone out here came for the
  artifacts, and some found it easier to take them from the ones who
  survived the finding.

### The Stray Dog
- **Role:** a thin mongrel that sometimes watches you from the grass on
  plains and in forests (2% per move while you have no dog). Offer it
  food (60%, more for meat) and it follows you. It growls before trouble
  (Hide and Flee go better), bites what you fight, and sometimes takes a
  blow meant for you. It eats once a day from your bag and leaves after
  three hungry days. It has 30 HP and can die.
- **Lore:** most dogs here *came back wrong*. This one didn't, or not yet.

### The Little Ones
- **Role:** small, pale, huge-eyed children, blotched by the Churn and dressed
  in rags, who live in burrows (warrens) in the woods and hills. They wear
  strings of buttons and bottle caps. They're never hostile, only mischievous.
  - **Befriending them:** you'll find little **cairns** of stones near
    their warrens. Leave a **trinket** there (**E** on it, or **T** on the
    cairn). Trinkets are toys and junk a toddler would play with: a plastic
    earring, a toy car, crayons, a rubber duck, a doll's head, a marble, a
    toy dinosaur, a hair clip, a button, a bottle cap, a tin whistle, a
    jingle bell. They turn up in searches and the Peddler sells them, and
    they're worth nothing to anyone else.
  - **After three gifts**, visit a warren and a troupe follows you (one
    more for every three further gifts, up to three). Walk up to a warren
    as a stranger and they come out to look: watch them, offer a trinket
    (worth two gifts), or shoo them away (they take something as they go).
  - **Following you:** every few hours one of them brings you something it
    found (sometimes a toy), or hides one of your odds and ends (often it
    turns up again later; never food, water, medicine, tools or your way
    out). In a fight they pelt the enemy with stones and help you run (more
    so from the night horrors); at night they sometimes giggle half the
    night away, and they go silent when something is out there.
  - **Keep them happy:** without gifts they get bored (a little every two
    days) and eventually wander home; one trinket wins them back.
- **Lore:** when the town was evacuated, not every child made it to the
  school. The ones who stayed in the cellars were small when the first
  emission came, and they stayed small. They don't talk, or don't want
  to. They remember toys, and wear the ones they're given.

### The Signal
- **Role:** the fourth channel on the radio. The first call gives you a
  torn page. Every call marks where the nearest artifact lies, and every
  call costs you 10 rads. Once a day.
- **Lore:** a numbers station on the old military band. It isn't the
  Institute's. It started the night of the first emission, and it reads
  numbers. Lately it reads names. (What it is counting is in the spoiler
  section below.)

### What the Churn made of people
- **The Fused:** two people walking as one, joined at the ribs by a bridge
  of bare bone that creaks when they breathe. They whisper to each other
  about you, agree on something, and turn.
- **The Mouthless Man:** a hooded man in a torn raincoat whose mouth is sewn
  shut, the stitches long healed in, with a second seam down his throat. He
  breathes through it, faster once he has seen you.
- **The Bloom:** a woman covered head to chest in soft pink growths that
  swell and shrink as she breathes. She smiles through them, then comes
  closer far too quickly.

### What the Churn made of animals
- **The Jawhound:** a dog with eyes crowding its flanks and wet tendrils
  above it, its mouth split back past the ears.
- **The Skinless Boar:** a boar with no hide at all, only shining muscle
  and gristle.
- **The Knotted Crows:** dozens of crows grown together at the wings into
  one body, every head turning toward you at once.
- **The Crawling Stag:** a flayed stag with eyes along its neck and
  antlers that end in hands.

You can hunt the animals as well as meet them: **G** on plains, in a
forest or in the hills (by water with a Fishing Rod, G fishes instead). The
Trader's den job sends you after one of them.

### Night horrors (20:00 to 06:00)
They only come after dark (4% per move), half as often if you carry a
light or stand by a fire, and never at a camp with a bedroll.
- **The Long Man:** someone at the edge of your light, too tall, arms
  hanging past his knees. *Look away* and he's gone (and you sleep badly).
  Run, or **speak to it**: half the time it bends down and leaves you an
  artifact, half the time you lose 15 HP to something you can't explain.
- **The Crawler:** something low and wide in the grass, too many legs,
  too many eyes catching your light. It clicks. It's coming. Without light
  your blows only half land; hold a torch close and it may flee.
- **The Whisperers:** pale faces under the black water saying your name,
  then your mother's. *Cover your ears* (and lose sleep), or follow the
  voice: you may find a stash, or wade in and lose 20 HP.

### Anomalies
Places where the rules stopped working. Each one is a short puzzle (throw
bolts through a field, repeat a sequence, turn runes to match a carving);
solve it and it may leave an artifact, fail it and it hurts in odd ways.
- **The Humming Hollow:** a dip where the grass lies in a perfect spiral
  and the air hums in your teeth. A crow lands at the edge and is folded
  into nothing.
- **The Drowned Bell:** a great bronze bell hanging over a new pool with
  nothing holding it up, miles from any church. It tolls by itself, the water
  ripples in rings, and something below answers.
- **Wrong Stars:** at midday a patch of sky goes black in the shape of an
  eye and fills with stars no one has named. Something up there notices you looking.
- **The Stillness:** birds hang motionless mid-flight, and a hand reaches up
  out of the earth toward them. Step closer and every sound stops, even your
  own heartbeat.
- **The Door in the Field:** a door frame standing alone. Through it, this
  same field at night, and someone standing in it, waiting for you.

---

## The full story (spoilers)

<details>
<summary>Open only if you don't mind knowing what the torn pages say.</summary>

Twelve **Torn Pages** tell what happened, always read in this order. You
find them in ruins (search with F), two lie somewhere in the world, and the
Signal reads you one the first time you call it. **E** on a page reads it;
**J** then **L** rereads the ones you have.

1. **Institute memo, day 0:** the readings over the quarry are "within
   tolerance"; the hum is a transformer fault; *do not discuss the birds*.
2. **A driver's notebook:** night runs to the Institute; one crate was
   warm, one was singing.
3. **Radio log, 03:12:** *"The sky over the quarry is what?" "Purple. It's
   purple and it's breathing."*
4. **The first emission:** nobody outside lived; the grass grew in
   spirals; the dogs came back wrong.
5. **Evacuation order 14:** bring nothing, no pets, nothing warm to the
   touch.
6. **Anna's diary:** she stayed when the doctors left.
7. **Karl, on a tackle box lid:** forty years on the river; the river
   doesn't care what happened.
8. **The Checkpoint's standing orders:** confiscate all objects; *if an
   object speaks, report to the sergeant*.
9. **A stalker's last note:** artifacts are easy if you don't mind the
   dreams. *"I dream of a door in a field. Every night it's open a little
   wider."*
10. **Institute memo, day 400:** the broadcast on the military band isn't
    theirs. It reads numbers. Lately it reads names.
11. **The numbers:** they decoded it. It isn't coordinates, it's a
    **count**. It counts the people still in the Churn, and every time it
    reads the list, the list is shorter.
12. **Unsigned, in the Checkpoint's tower:** *"The Churn isn't a wound.
    It's an eye opening. Everything we take out of it is something it lets
    us carry, so it can see where we go."*

**How it fits together.** Whatever the Institute was doing at the quarry,
it opened something. The emissions are that something breathing. The
anomalies are where it touches the world (the Door in the Field is the
door the stalker dreamed about), and the artifacts aren't treasure: they
are how it sees. The Signal has been counting the living since the first
night, and the guards who confiscate every object are, without quite
knowing it, trying not to be looked through.

**The Institute (the storyline).** Read six torn pages, or call the Signal
twice, and everything points to the **old quarry** in the hills: a sealed
gate stencilled INSTITUTE. It needs a pass. **Karl** gives you his son's
for a right answer (*"He worked there. Didn't come back. You might."*),
or **Anna** sends her brother's by runner if you did her bandage job. Down
the stair is a doorway of violet light and the hum: the Signal isn't on
the radio here, it's in the walls. With a Multitool you can try to **shut
it down** (a Tinkering and Perception roll; a failure throws you out with
a dose of rads). Succeed and you walk out into **the Quiet**: the Churn
falls silent, the Checkpoint stands empty, and that's a fourth way out
(and its own achievement). Or **listen to it**: you understand all of it
at once, and then you hear your own name.

**The ending changes with what you've read:**
- **0-3 pages:** you simply leave.
- **4-8 pages:** you've read enough to wonder what you're carrying out,
  and who is looking through it.
- **9 or more:** you know what the Signal counts. As the barrier drops you
  hear it begin again, one name shorter. It doesn't say yours. Not yet.

</details>
