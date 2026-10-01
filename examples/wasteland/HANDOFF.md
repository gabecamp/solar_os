# Handoff: NEO Scavenger-style survival game (SolarOS Lua app + Python/pygame version)

> **Read first:** more than one Claude session works on this branch, and the GitHub branch is the source of truth. Before editing, compare commit hashes and only fetch when they differ (`ls-remote` asks GitHub for one line, not the repo):
> ```sh
> remote=$(git ls-remote origin refs/heads/claude/new-session-ws67f3 | cut -f1)
> [ "$remote" = "$(git rev-parse HEAD)" ] || { git fetch origin claude/new-session-ws67f3 && git merge --ff-only FETCH_HEAD; }
> ```
> If the fast-forward fails (both sides have new commits), merge as a continuation of GitHub's version; never force-push.
>
> **The code lives in `src/` now (split 2026-09-30).** `wasteland.lua` is GENERATED: edit the parts in `src/` (`00_header`, `05_data`, `10_sprites`, `20_world`, `30_game`, `35_crafting`, `36_survival`, `37_world_time`, `38_save`, `39_radiation`, `40_encounters`, `45_trade`, `50_draw_map`, `60_draw_inventory`, `65_portrait_data` (generated), `66_portraits`, `70_draw_screens`, `72_draw_craft`, `76_draw_trade`, `90_main`), then run `python3 tools/build.py` (the test runner does this first). The parts are concatenated in name order and share one scope - chapters, not modules - so a local defined in an earlier part is visible in later ones and order matters. Still ship/copy only `wasteland.lua`; `python3 tools/build.py --check` says whether it is current.
>
> **The 200-local limit (hit 2026-09-30):** the bundle is ONE Lua chunk, and Lua allows at most 200 local variables in a chunk's main function. The parts had used ~197. Key codes are now one table (`KEY.A`, `KEY.ENTER`, ... instead of `KEY_A`...), freeing 13. **Rules for new code:** group new constants in a table (`CRAFT_UI = {...}`, `RECIPES.campfire_hours`), make helpers `Game.name` fields or locals inside functions/`do ... end`, not new top-level `local`s. Check headroom by compiling (`luac5.4 -p wasteland.lua`, which fails with "too many local variables").
>
> **Crafting (2026-09-30):** `C` on the map or inventory opens the crafting screen (`src/35_crafting.lua` logic, `src/72_draw_craft.lua` screen). `RECIPES` in `src/05_data.lua`: inputs (used up) come from bag + hands + the ground here (ground first, hands last), tools just have to be present, `fire` needs a lit campfire on the tile (`self.camps[key].until_hour`, 12 h). Known at start: Torch, Bandage, Campfire, Cooked Meat; Rope, Spear and Stone Club come from Scrawled Notes (E reads them). New items: stick, rope, torch (light comes in the world phase), bandage (E: stops bleeding, +15 HP), cooked meat, scrawled notes, stone club. Screen state is `self.craft_ui` (a field named `craft` would shadow `Game:craft`). Tests: `tests/crafting_test.lua`.
>
> **Bigger world, day/night, weather, cold (2026-09-30):** `GRID_RADIUS` 12 (469 hexes). `generate_world` adds `WORLD.rivers` random-walk rivers with two fords each, a town (`WORLD.town_ruins` ruins 5-9 hexes out) and `WORLD.lone_ruins` wrecks, then converts water to fords along a line wherever land would be cut off, so every walkable hex is reachable from the start. New terrains `ruins` (cost 1, its own loot incl. notes/backpack) and `ford` (cost 2). The map screen has a **camera centered on the player** and draws only whole hexes inside the map area (`draw_map` walks an axial box around you). `update_visibility` visits only hexes within sight. `src/37_world_time.lua`: clock (day 1 starts 08:00), night 20-06 (sight -1 unless holding a torch; encounters x1.5), weather rolled per 6 h block from `self.weather_seed` (Clear/Overcast/Rain/Cold snap), cold = worn `warmth` below the weather+night need and no fire; `Game:tick()` runs after every key and applies the hours that passed (cold drains rest; past `cold_grace` hours it costs health). Resting by a campfire restores 50% more. All numbers live in the `WORLD` table in `05_data.lua`. Tests: `tests/world_test.lua` (40 seeds of generation, camera, clock, torch, weather, cold, fire).
>
> **Dog companion (2026-10-01):** `src/48_dog.lua`, numbers in `DOG`. A "Stray Dog" (kind `"dog"`, painted portrait `stray()` in tools/portraits.py) turns up 2% per move on plains/forest while you have no dog (`maybe_dog`, after `maybe_karl` in `maybe_encounter`). "Offer it food" (first match from `DOG.eats`, rotten meat first): 60% (+25 for meat/fish/jerky) it joins (`self.dog = {hp, fed_hour, hungry_days}`, saved), else it runs off with the food. With a dog: +15% hide/flee (`dog_bonus`), it bites 3-6 half the time at close range (`dog_turn` at the start of `enemy_turn`), 20% it takes a blow meant for you (`dog_guard`; at 0 HP it dies). Once a day (`dog_hour` from `tick`) it eats from your bag; 3 hungry days and it leaves; +1 HP per 6 h. A small block beside your marker on the map. Test: `dog_test.lua`; the bot tames when it can.
>
> **Difficulty (2026-10-01):** keys **1/2/3** on the creator pick Easy / Normal / Zone-Hardened (`self.difficulty`, saved; shown top right of the creator and on the info page). `DIFFICULTY` multipliers via `Game:diff(key)`: food (weight of hunger-food entries in search tables), encounter (chance), rad (dose), emission (HP and rads), drain (`player.diff_drain` folded into hunger/thirst mults by `recompute_stats`). Balance sim (`lua5.4 ../tools/balance_sim.lua 300 1 easy|normal|hard`): deaths within 30 days ~4% / ~20% / ~41%. (The creator shows the `short` label: Easy / Normal / Hard.) Test: `difficulty_test.lua`.
>
> **Sound (2026-10-01):** `src/47_sound.lua`: `Game:sfx(name)` plays `SFX[name]` ({Hz, ms} notes, 0 Hz = rest) through `solaros.audio.tone_async` (non-blocking queue; falls back to blocking `tone`; pcall'd). Hooks: hit/miss/hurt/kill in fights, geiger, emission siren (warning) and roar (caught), chime (craft, stash, fish, snare), gift (Karl), death, escape; bark/whine are for the dog. **M** on the map toggles `self.muted` (saved). Test: `sound_test.lua`.
>
> **Karl (2026-10-01):** the user asked for **Karl (spelled K-A-R-L)**, a rare fisherman found only by rivers who asks a riddle and gives an item for a right answer. `src/44_karl.lua`, data in `KARL` (05_data). `maybe_karl` runs from `maybe_encounter` (3% per move onto a ford or next to water) and after G fishing (10%); then a 96 h cooldown (`karl_next`). Encounter kind `"riddle"` (never picked by `pick_encounter`): intro shows "KARL" on his tackle box; 6 riddles, asked without repeats until all are used (`karl_asked`), 3 shuffled answers (`answer_N` actions) + Walk away. Right: a gift from `KARL.rewards` (Pilk = Pepsi and milk: thirst +40, hunger +10, rest +15; Fishing Rod; Lucky Lure +15% fishing carried; Karl's Waders feet +10% / warmth 2; Karl's Hat head +10% / warmth 1), gear only once (`karl_gave`). Wrong: "The river keeps its secrets." `fish_bonus` field + `Game:fish_bonus()` feed `Game:fish`. **Portrait: a placeholder smiley** (`karl()` in tools/portraits.py); the user will supply `art/karl.jpg` (a real person): do not generate him. Tests: `karl_test.lua`; the bot guesses riddles (~1 Karl per 30-day run).
>
> **Help, device info, hunting, headroom (2026-10-01):** **H** (map/bag) opens a key list (`src/78_draw_help.lua`); **V** there shows device info (`Game.VERSION`, Lua version, memory, screen, uptime, storage path, whether `write_file` exists, save found, world seed, audio) for testing on a board; `DEVICE_TEST.md` is a 10-minute checklist for the user. The map hint is now "Arrows Spc:rest F:search E:water I:bag H:help". **G** (`src/43_hunting.lua`, numbers in `HUNT`): by water with a Fishing Rod you fish (2 h, 40% +5/Per, Pale Fish: perishes, 15% sick raw, cook it); elsewhere you track game (2 h, 45% +10/Per) and an animal encounter starts with you already having studied it (`enc.seen`, `aim`). Snare: E sets it on a forest/plains/hills hex (`self.snares`, saved, a loop on the map); stepping back on rolls `1-(1-p)^hours` for 2 Strange Meat. New known recipes: Fishing Rod (stick + rope + scrap), Snare (rope + 2 sticks), Cooked Fish. **Headroom 8 -> 29**: the paperdoll polygon builders run inside a `do` block (only `BODY_BLOCKS`/`PART_BLOCKS` escape) and the fight numbers are one `FIGHT` table (`FIGHT.PLAYER_HIT`...). `tools/locals_headroom.py` prints the headroom and run_tests.sh fails below 10. Tests: `hunting_test.lua`, `help_test.lua`.
>
> **Balance pass (2026-10-01):** `tools/balance_sim.lua` plays whole runs with the real game code (`cd tests && lua5.4 ../tools/balance_sim.lua 300 1`; ~10 s for 300 runs) and prints how runs end, days survived, encounters, artifacts, peak rads and how often the trader is found. The bot is careful (eats/drinks/bandages/anti-rads, wears and wields the best it has, fights only when armed, pays bandits, shelters from emissions, drops junk, hunts known artifacts once it knows the exit, skips anomaly puzzles). Most early "deaths" were bot bugs (it stopped searching with a full bag, looped between junk piles, couldn't wait when rest was refused); fixed in the bot, not the game. Game changes from it: radiation was the top killer (37%) -> `RAD.fields` 7->5, doses {2,5,12}->{1,4,10}, decay 0.5->1/h, stages 30/60/85 with 0/1/2 HP/h; emission 25 HP/25 rads -> 20/20, warning 6->10 h, **hills are cover too**; bleeding now **clots after 8 h** (`SURVIVE.clot_hours`; it never stopped before, so no cloth = death); **no rest healing at 0 hunger or thirst** (a starving survivor used to sit at full HP forever); you **learn a site as soon as you can see it** (`spot_sites`, from `tick`; before, only by stepping on it, though its glyph was already drawn); the permit is worth 80 (ask 120) so buying out competes with the 3-artifact bribe; loot duds ~43% (the first cut to ~50% starved everyone); "Killed by the The Fused" -> "Killed by the fused pair". Result over 300 runs: ~18% die within 30 days (bleeding, starving, radiation, emissions, then fights), ~24% escape, ~58% still alive at day 30 (mostly short of artifacts), the trader is found in ~71%. Local headroom: 8.
>
> **Emissions, stashes, splint, filter (2026-10-01):** `src/42_events.lua`, numbers in `RAD.emission` / `RAD.stash`. Emissions: first at hour 50, then every 60-110 h (`self.next_emission`, saved); `Game:tick` calls `emission_hour(hour)` per hour: a log warning 6 h ahead ("EMIT 5h" replaces the weather on the panel, "EMISSION!" while it rages), 2 h of it: off ruins you take 30 HP and 40 rads (x rad armor) spread over the hours; afterwards every field center without an artifact grows one. Death by it: "The emission took you." Stashes: scrawled notes have a 1-in-4 chance (always, once every recipe is known) to mark a stash 4-9 hexes away (`mark_stash`: 3 items from `RAD.stash.loot` on the ground, `self.stashes`, saved, drawn as an X on the map until you step there, `find_stash` from `try_move`). New known recipes: Filter Water (dirty water + cloth, no fire) and Splint (2 sticks + cloth; E: a wound heals 12 h sooner). `Game:bearing_to(key)` is the general compass helper. Tests: `tests/events_test.lua`.
>
> **Gear pass (2026-10-01):** new `belt` slot at the waist (`EQUIP_SLOTS`, `EQUIP_RECT`; the shirt box shrank and pants moved down 6 px): Leather Belt (loot + one world drop, +2 bag cells) and Rope Belt (known recipe: rope + cloth, +1) via `ITEM_DB[..].belt_cells` in `bag_capacity`. New material Scrap Metal, food Jerky, weapons Shiv (known: scrap + cloth), Machete (scrap x2 + stick + rope, rock as tool), Spiked Club (stone club + scrap), Pipe Spear (pipe + knife + rope, reach) - the last three from notes. Loot is scarcer: "nothing" is now ~45-55% of every terrain table (was ~20-30%) and the world has 2 food/water caches instead of 3. Shift+Enter can't be told apart from Enter (the firmware sends `\n` either way and Lua sees no modifiers), so quick-equip stays on **E** (`use_item`: wearables go to their slot, anything else to a free hand). Tests now take their world seed from `WASTELAND_SEED` (run_tests.sh prints it; replay with `WASTELAND_SEED=n bash tests/run_tests.sh`). Tests: `tests/gear_test.lua`.
>
> **Traders and a goal (2026-09-30):** `generate_world` returns a 5th value, `sites` (rebuilt from the seed): `trader` = the town's center hex (always ruins), `checkpoint` = the edge hex farthest from the trader (never water; the reachability pass connects it). Anomaly fields keep `RAD.min_dist` away from both. `src/45_trade.lua`: stepping onto a site announces it and never starts an encounter (`arrive_site`, from `try_move`); **T on the map** (`site_action`) opens barter at the trader or the gate at the Checkpoint. Barter (`"trade"` screen, `src/76_draw_trade.lua`): your bag left, the trader's stock right, Enter +1 / E -1 unit, T deals if what you give (full `TRADE.value`, default 1) covers `TRADE.markup` (1.5) x what you take; sold items join the stock; +`restock_n` items every `restock_hours`. Stock is `self.trader` (saved). Where the sites are: `sites_known` (saved), learned by walking there, from the trader (tells you the Checkpoint), the wanderer (Checkpoint, then the trader), or scrawled notes (1 in 3, always once every recipe is known). The panel shows "Exit NE 12" (or "Trader ..") at y 112; `LEGEND_Y` is now 130; known sites get their 10x10 glyph (`GLYPH_ART.trader/checkpoint`) on the map. The gate (`"gate"` screen): Zone Permit (trader sells one, value 120 -> 180) or `GOAL.bribe` (3) artifacts -> `finish_run` -> `"ending"` screen (Enter = new survivor); the save is deleted. Tests: `tests/trade_test.lua`. Local headroom: 8.
>
> **Water and the survival loop (2026-09-30):** `src/36_survival.lua`, numbers in `SURVIVE` (05_data). Bottles are containers (`ITEM_DB[..].empty`): drinking leaves an Empty Bottle in the bag or the same hand (`Game:after_consume`, called from `try_consume`). **E on the map** (`Game:water_action`) by open water or on a ford fills every carried empty with Dirty Water; with none you drink straight from the river (1 h, +30 thirst, dirty-water risk). Resting in Rain fills empties with clean water (`rain_fill`). Recipe **Boil Water** (known, needs a fire). `ITEM_DB[..].sick` = % chance to get sick (dirty water 40, raw Strange Meat 25, Rotten Meat 70): `p.sick_hours` 12-24, costs thirst/hunger/rest and 1 HP per hour ("SICK" on the panel, "Sick" condition). `perish = {hours, into}` on Strange/Cooked Meat: each carried unit has a 1-in-hours chance per hour to turn into Rotten Meat. At 0 thirst (-2 HP/h) or 0 hunger (-1 HP/h) you now lose health. `Game:tick` calls `survive_hour` per hour and `death_reason()` names the cause. Map hint now reads "F:search E:water". Tests: `tests/survival_test.lua`. Local headroom: 12.
>
> **Radiation and anomaly fields (2026-09-30):** `generate_world` now returns a 4th value, `rad` (tile key -> level 1-3; kept on `self.rad`, rebuilt from the seed, not saved): `RAD.fields` hot spots at least `RAD.min_dist` from the start, level 3 at the center falling off by one per hex (radius 1-2), an artifact on the ground at each center. `src/39_radiation.lua`: `Game:tick` calls `rad_hour()` for every hour that passed (dose `RAD.dose[level]` x worn `rad_armor`; away from fields rads fade by `RAD.decay`/h; `RAD.stages` Irradiated 25 / Rad sick 50 / Rad poisoned 80 cost rest and HP per hour; radiation can kill). New items: Geiger Counter (carried: reads your hex and neighbours into `self.rad_known` (saved), trefoil marks on the map (inverted = deadly), "Geiger high Rad 53" panel line at y 98 (legend moved to `LEGEND_Y` 116), a click via `solaros.audio.tone`), Gas Mask (eyes slot, `rad_armor` 0.5), Anti-Rad (-50), Vodka (-20; `consumable.rads`), Bolts (+2 throws in the bolts puzzle). They're in ruins/plains/hills loot and dropped once each (`RAD.world_items`). Searching a level 2+ hex has a `RAD.artifact_find` % chance of an extra artifact. Tests: `tests/radiation_test.lua`. Local headroom: 13.
>
> **Portrait pass 2 (2026-09-30):** subject functions may return a third value, a `near` crop box: the people (fused, mouthless, bloom, bandits, tollman, medic, wanderer) use a head-and-shoulders crop so faces get about twice the pixels; `human_body` now has sloping trapezius + rounded deltoids and the necks are shorter. New 10x10 glyphs: ruins, ford, campfire; new 16x16 icons for the crafting items.
>
> **Encounter portraits (2026-09-30):** every encounter has `art = "<subject>"` and a 96x96 picture in the top-right of the encounter screen (`Game:draw_portrait`, `src/66_portraits.lua`). The art is painted in code by `tools/paint_portraits.py` (engine `tools/paint_lib.py`, one function per subject in `tools/portraits.py`): shaded grayscale at 192x192, then contrast-stretched and **ordered-dithered** (Bayer 4x4; Floyd-Steinberg turned faces into noise at this size) to 1-bit, and baked into the GENERATED part `src/65_portrait_data.lua` as base64 32x32 sprite tiles (~69 KB). Views: `near` (whole), `far` (48x48, small in the frame), `close` (the subject's face zoomed); plus wound-mark points. It reacts: range picks the view, blots appear at hurt/badly hurt (same bands as `enemy_condition`), dead = hatched, fled = empty "gone" frame; helpers/anomalies don't change. Only one creature is decoded at a time. **To use your own picture** for a subject, drop `art/<subject>.png` or `.jpg` (any size; a white background works best) and rerun `python3 tools/paint_portraits.py` then `tools/build.py`. Supplied pictures go through `photo_views`: median smoothing, levels + gamma (lifts dark mid-tones), dark edges, Floyd-Steinberg; per-subject crop boxes (far = whole body, near = head/front, close = face) and gamma/edge live in `PHOTO` in `tools/paint_portraits.py`, otherwise they are guessed from the subject's bounding box. `art/jawhound.jpg` and `art/stag.jpg` are the user's own pictures (both intros rewritten to match; the stag is pale, so it uses gamma 1.0 / edge 0.8 instead of the Jawhound's mid-tone lift). **`art/PROMPTS.md`** has image-generator prompts for every subject. The session has a **Hugging Face connector** whose Z-Image Turbo tool (`mcp__huggingface__gr1_z_image_turbo_generate`) generated boar, crows, fused, bloom and bandits; the free ZeroGPU quota ran out after 7 images. Generated images have light-gray backgrounds: use `"bg": 0.78` in `PHOTO`. The Fused and Bloom intros were rewritten to match their pictures. Previews: `previews/portraits/` (+ `contact_sheet.png`). Tests: `tests/portrait_test.lua`. Needs Pillow + numpy on the PC. The display is **400x300 landscape** (see the note below), not the 300x400 the older sections describe.

*Written 2026-09-30 at the end of a long chat session. The active work is `wasteland.lua`, a single-file Lua app for a handheld running SolarOS. A parked Python/pygame version lives in `python_version/`. Read "Where We Are" bullets 17–20 before touching anything: an audit done while writing this found four real bugs, one of which makes the Lua game unplayable.*

> **Update 2026-09-30 (second session, now in `gabecamp/solar_os` at `examples/wasteland/`):**
> bugs 17–20 are fixed and covered by `tests/regression_test.lua` (the old `repro_known_bugs.sh` is gone).
> - **17/18:** `E` on the inventory screen eats/drinks ONE unit of the item under the cursor; the stack is removed only at 0 (Lua only; `python_version/` still has bug 18).
> - **19:** the loop redraws only after a handled key (200 idle polls: 200 → 5 refreshes).
> - **20:** the bag shows all 16 stacks (2×8 cells of 26px; log on this screen is now 2 lines); the ground grid shows 2 rows and scrolls to follow the cursor.
> - Also: identical items merge into one stack; failed moves restore the item in place; equipping over a slot with a full bag drops the old item on the ground; the conditions line fits with all four conditions.
> - **Checked against firmware source:** `gfx.KEY_UP/DOWN/LEFT/RIGHT/ESCAPE` exist (0x80–0x83, 0x1b); Enter arrives as `\n`; the Lua runtime does **not** load `os`, so the seed now comes from `solaros.time.uptime_ms()`; `require` is a shim for `solaros` only, so the app stays one file.
> - Layout tests (`bounds_test`, `body_test`) now read the game's constants through the generated `lib_layout.lua` (gap 25 fixed).
> - Still unverified on the device: everything since "it works!".
>
> **Paperdoll rework (same day, user asked for "slots overlay the body part, like NEO Scavenger"):** the two slot columns are gone. Each slot is a dashed frame *on* its body part (`EQUIP_RECT`); worn clothes are painted onto the figure via `ITEM_DB[...].wear` (part, row range, color) using per-part body blocks (`PART_BLOCKS`), and the item icon sits on top with a white halo. Empty slots show their name on a white tag. The figure is 1.25× bigger (`BODY_SCALE`) with a larger head; to make room the ground grid is one scrolling row of 9 × 30px cells. The cursor's item is named on the "Ground" line. Left/right also step the cursor on this screen. `body_test` now checks every slot is on the body and no two slots touch. All 10 slots now have an item (earmuffs, sunglasses, scarf, leather jacket, bracers added; wear entries can clip to a distance band from the center line). Every wearable not worn at start (incl. cap/gloves) spawns once on a random passable tile, plus a few food/water caches; tiles with items get a small boxed-dot marker on the map and a log line when you step on them. Items placed at world generation are simply lying on the ground.
>
> **Scavenging:** `F` on the map searches the current tile: 1 MP + 1 h of needs drain (`SCAVENGE_HOURS`), `SCAVENGE_ROLLS` = 2 rolls on `SCAVENGE_LOOT[terrain]` (weighted, with "nothing" entries), finds dropped on the tile's ground. `SCAVENGE_TRIES` = 3 searches per tile, tracked in `Game.scavenged`, then "picked clean". HUD shows `Scav n/3`. New consumable `berries` (forest). RNG state lives in `Game.seed`. Covered by `tests/scavenge_test.lua` (tables valid, costs, dry tiles, every entry reachable, F wired); measured drop rates match the weights within ~1%.
>
> **Character creator, hands, bags (2026-09-30, continued on the user's Windows PC):** a new game opens on a `"creator"` screen (`Game:draw_creator` / `Game:creator_key`): 4 attributes (1-6, 12-point pool, all start at 3) and 10 traits with a Project Zomboid budget (only traits with a real effect). `recompute_stats` derives `max_mp`, `sight`, `scav_rolls`, `bag_bonus`, hunger/rest multipliers. **Perception** drives scavenging: `scav_rolls = 2 + (Per-3)//2` (+/- Scrounger/Careless) and the loot table's "nothing" weight is scaled by `(7-Per)/4` (measured on hills: Per 1 = 0.47 items/search, Per 3 = 1.11, Per 6 = 2.54). New slots `lhand`/`rhand` hold any item (`HOLD_SLOTS`), `back` holds a bag: `backpack` (12 cells, worn at start) or `satchel` (8, found on plains); no bag = 4 pockets; Strength adds cells. `try_transfer` snapshots state and undoes any move that leaves more stacks than the bag holds. `E` is now context "use" (`Game:use_item`): eat, wear, hold in a free hand, or take off. The ground and bag always offer one empty drop cell (before, an empty bag could not receive anything). The inventory log is anchored to `h - 8` like the map hint (fix for the device cutting it off), bag cells are 24px with the bag's name/count to the right. Tests: new `creator_test.lua`, extended `scavenge_test`/`regression_test`, `bounds_test` runs at 400 and 392 px.
>
> **The screen is 400x300 landscape, not 300x400 (fixed 2026-09-30).** First device photo of this build: creator text garbled at the bottom, map key missing. Cause: `boards.md` gives the RLCD's logical size after rotation as `SOLAR_OS_BOARD_DISPLAY_WIDTH 400 / HEIGHT 300`; every screen had been laid out for 300x400, so everything below y 300 was drawn off screen or on top of the key hints. New layouts: **map** = hexes in the left 256 px (`MAP_W`), HUD + vertical legend in a right panel (`PANEL_X` 262), log + hints across the bottom (the "Wasteland Survivor" title is gone); **inventory** = doll in the left column (`BODY_DX/BODY_DY` shift the figure and `EQUIP_RECT`), ground 5x2 + bag 7 cols + cursor line in the right column (`INV_COL_X` 212), conditions + log across the bottom; **creator** = attributes left, traits right (`CREATOR_TRAIT_X` 200), description/stats below. Fakes, `replay.py` and every test now use 400x300. The 392 px bounds case was dropped: it was a guess at the "log cut off" symptom, which was really this.
>
> **Save/continue (2026-09-30):** the firmware half is commit "storage: add write_file for Lua and Python scripts" on this branch (also `firmware/0001-...patch`; `firmware/UPSTREAM_REQUEST.md` says what it changes, for asking the SolarOS author). Host test passes; **not yet built with ESP-IDF or run on the device**. The game half is `src/38_save.lua`: the save is `<storage.mount_point()>/wasteland/save.lua`, a Lua table literal read back with `load(..., "t", {})` (no code runs). The map isn't stored; it is rebuilt from `self.world_seed` (`generate_world` is deterministic). Stored: `SAVE.fields` + the player minus `visible` (~2-6 KB). Autosave (`Game:autosave`, called after every key in `90_main`) writes only on map/inventory/craft when `player.hours` changed, and on quit; death deletes the save (`check_death`). Start-up shows a `"title"` screen (Continue / New survivor) only if a valid save exists. Everything is gated on `solaros.storage.write_file` existing, so on stock SolarOS the game runs as before. The test fake has in-memory storage (`FAKE_FILES`); `tests/save_test.lua` covers round trip, bad files, no write_file, failed writes, death, and the title through the real main loop. Bump `SAVE.version` when the save shape changes incompatibly. Local headroom after this part: 14.
>
> **Encounters plan, step 1 of 3 done (trait points, health, weapons).** The plan is in `C:\Users\Gabe\.claude\plans\for-the-next-part-snuggly-popcorn.md`. Steps 2 (encounter engine and combat: mutant animals and humans, bandits, rare helpers) and 3 (anomalies with random puzzles, artifacts) come next. Step 1: `TRAIT_START_POINTS = 5`; `player.health` (100) and `player.injuries` (`bleeding`: −4 HP/h awake or resting; `wounded_hours`: −1 MP until 24 h of rest); rest heals +3 HP/h (Endurance scales it) unless bleeding; E on a Cloth Scrap while bleeding bandages; HP 0 → `"dead"` screen → Enter → `Game.new()`. Map panel shows HP plus an injury line (legend moved to y 80). Weapons: `ITEM_DB[..].weapon = {dmg, reach, thrown, bleed}` on rock, knife, pipe, spear (sprites and loot entries added); nothing uses them until step 2. New `tests/encounter_test.lua`; `replay.py` now renders every recorded `ops_*.txt`.
>
> **Encounters step 2 done (engine, combat, mutants, bandits, helpers).** `Game:try_move` → `maybe_encounter` (`ENCOUNTER_CHANCE` per terrain, 2-move cooldown) → `pick_encounter` (`ENCOUNTER_KINDS` weights, skipping kinds without entries, so anomalies turn on as soon as step 3 adds them) → `"encounter"` screen (`draw_encounter`, `encounter_key`, `encounter_action`, `encounter_options`). `ENCOUNTERS` holds 4 animals, 3 mutants, 2 bandits, 2 helpers. Ranges Far → Near → Close; every choice is a `Game:roll(pct)` against an attribute, then `enemy_turn` (closes in, strikes, may cause bleeding or a wound, beaten enemies have a 30% chance per turn to run). Bandits demand food first; the medic heals, the wanderer maps the area. Kills drop loot on the ground (new consumable Strange Meat). `weighted_pick` now takes the LCG's high bits (its low bits cycle quickly). Measured over 300 seeds each: with fists you usually lose to mutants (hide or run instead); with a pipe you almost always win but lose about 25–35 HP. Tune the constants after playing.
>
> **Encounters step 3 done (anomalies, puzzles, artifacts). The encounters plan is complete.** 5 `ANOMALIES` are appended to `ENCOUNTERS` (weight 20). Investigate → `start_puzzle` picks one of: **bolts** (5x5, 6 hidden hazards, re-rolled until a BFS path exists; the cells you've stood on show how many hazards border them; T+arrow throws a bolt to reveal a cell; bolts = 3 + (Per−3)), **sequence** (4 sigils `SIGIL_ART` on keys 1–4, shown until any key, 3 rounds of length 3/4/5), **runes** (5 needles; a press turns that rune and its neighbours; scrambled by 3 backward presses, 6 + (Per−3) presses allowed). `finish_puzzle`: solved → `ARTIFACT_CHANCE` 25% + 5%×(Per−3) (measured 25.8%) of one of 5 artifacts on the ground; failed → damage, bleeding, or 4–8 lost hours; Esc/Q = back away, no harm. Artifacts (`ITEM_DB[..].artifact`, `desc` shown under the inventory cursor line) work while held in a hand: `recompute_stats` folds them in and runs after every `try_transfer` and throw. New fx: `thirst`, `rest_drain`, `heal`, `encounter`, `scav_hurt`. Still untested on the device.
>
> **Running the tests on Windows:** Lua 5.4 (`winget install DEVCOM.Lua`) and Python 3.12 are installed; the suite runs under Git Bash with small wrapper scripts named `lua5.4`, `luac5.4`, `python3` on `PATH` (they live in `%TEMP%\claude\wbin`, outside the repo). Previews there use a proportional PC font, so text widths look different from the device's mono font.

---

## 1. The Goal

**What:** a clone/homage of *NEO Scavenger* (the Flash survival RPG: hex overworld, fog of war, hunger/thirst/rest, a paper-doll inventory with body slots, scavenging, turn-based combat, crafting). The user wanted it **not in Flash**.

**Two targets, in the order they appeared:**
1. **Raspberry Pi 3B+** in Python/pygame. Built, then parked (see `python_version/`).
2. **An ESP32-S3 handheld running SolarOS**, as a Lua app. This is now the active target. The user tests on the real device and reports back.

**Why it matters to the user:** personal hobby project: a playable NEO Scavenger-like game on their own pocket hardware. Success looks like: launch the app on the device, explore a fogged hex map, watch needs drain, manage gear on a paper-doll inventory screen; later scavenging, encounters, combat, crafting.

**Hardware / platform (details in Evidence):**
- Board: Waveshare **ESP32-S3-RLCD-4.2**, 300×400 portrait reflective LCD, 16 MB flash / 8 MB PSRAM. It's a handheld with a physical QWERTY keyboard (visible in the user's photo).
- OS: **SolarOS** (`nilseuropa/solar_os`). The user's fork is **`gabecamp/solar_os`**. Apps are Lua/Python scripts using `solaros.gfx` etc. Embedded Lua is 5.4.8.
- The user chose "Lua/Python script on SolarOS" over "bare-metal Arduino/ESP-IDF firmware" (which would overwrite SolarOS).

**Hard constraints on the Lua app:** single file (SolarOS Playground convention); all `gfx` coordinates must be **integers**; colors only `gfx.WHITE/LIGHT/DARK/BLACK`; no polygon fill (only `line/rect/fill_rect/circle/fill_circle/pixel/text/sprite`); `gfx.sprite` ≤ 128 bytes per call; the panel is 1-bit so LIGHT/DARK are dithered; input via `gfx.getch`.

---

## 2. Where We Are

**Codebases**
1. **Lua app (active):** `wasteland.lua`, 1,235 lines / 41,745 bytes, one file. Byte-identical to the copy the user has.
2. **Python/pygame (parked):** `python_version/`, 15 files / 1,610 lines. Main menu (Continue if `savegame.json` exists) → character creator (12 attribute points over Str/Spd/Per/End, range 1–6; Project-Zomboid-style trait budget with 6 positive + 6 negative traits) → isometric hex overworld ⇄ inventory. JSON save/load. Entry point `main.py`.
3. `hex_map.py` in the user's downloads is the obsolete first single-file prototype. Ignore it.

**What has and hasn't been verified**
4. **Explicitly confirmed on the device by the user: only "it works!"**, said after the float→integer fix + `pcall` wrapper. The inventory was still a text list then.
5. **Inferred working** (the user kept requesting refinements to things they must have seen, but never said so): graphical inventory, item sprites, hex-shaped tile fills.
6. **Never seen on hardware / no feedback yet:** the current build's terrain glyphs + legend (i.e. `gfx.sprite` on the *map* screen) and the polygon silhouette. `gfx.circle`/`fill_circle` are no longer used anywhere (only the old stick figure used them). The app now calls just: `begin end size clear color font text line rect fill_rect sprite refresh getch`.
7. Everything else rests on a **fake `solaros` module I wrote** from the docs and the Snake sample (`tests/solaros.lua`). It checks argument types (integers, sprite byte counts) but not real rendering, dithering, fonts, or timing.

**What the Lua app does today**
8. **Map:** 61 tiles (hex radius 4), pointy-top axial coordinates, flat top-down, `HEX_SIZE 16`. Four terrains. Fog of war (sight 2): *visible* (filled + glyph), *remembered* (faded outline + faded glyph), *unseen* (blank).
9. **Movement:** arrows/WASD → the neighbor best matching the direction. Cost = terrain cost in both MP and hours. 2 MP max, overdraft allowed while MP > 0. Space rests 4 h (only if MP is below cap).
10. **Needs:** hunger/thirst/rest drain per awake hour and rest restores; each need at 0 reduces the MP you get back from resting by 1 (min 1); warnings go to the log. Three needs only (the Python UI shows seven bars, four of them static).
11. **Map screen:** HUD, centered hex map, 2×2 terrain legend (swatch + name + cost, extra box on the terrain you stand on), 10×10 glyph per tile, player marker with white halo, 3-line log, key hints.
12. **Inventory (`I`):** ground icon grid (6 cols), 10 equip slots (head, ears, eyes, neck, shirt, jacket, hands, wrists, pants, feet) in two columns flanking a polygon body silhouette, bag strip, conditions line (only real ones: Barefoot / Starving / Dehydrated / Exhausted). Cursor order: ground → equip → bag. Enter/Space selects, then moves; wrong-slot equips are rejected and reverted; equipping over an occupied slot bumps the old item to the bag.
13. **Render pipeline:** ASCII art → `pack_bitmap` → `gfx.sprite` (9 item sprites 16×16, 4 terrain glyphs 10×10); silhouette polygons rasterized once at load into 81 blocks; hex fill via 2-px scanline bands; every computed coordinate goes through `rnd()`.
14. **Structure:** one `Game` class; main loop wrapped in `pcall`, then `gfx["end"]()` always runs and the error is re-raised (the SolarOS documented convention).

**Tooling**
15. **Test suite** (`tests/run_tests.sh`, ~1 s): syntax, 6 unit tests, sprite round-trip, slot bounds, silhouette symmetry/collision, glyph+legend, a scripted main-loop run, a 400-random-key soak. All pass on the delivered file, verified from a clean copy.
16. **Preview renderer** (`tests/render.sh`) replays the game's gfx calls into PNGs. It found six layout bugs the numeric tests missed (Evidence has the list). Previews are in `previews/`.

**Known bugs and gaps (highest impact first)**
17. **BUG, game-breaking:** the Lua UI cannot consume anything. `Game:try_consume` is never called from a key handler (`grep -c try_consume wasteland.lua` → 1, the definition). Needs drain and nothing restores them. The header comment falsely says Enter consumes, and my earlier tests passed only because they called the function directly.
18. **BUG (both versions):** `try_consume` removes the *whole stack*. Eating one of "Water Bottle ×2" gives +50 thirst and deletes both.
19. **BUG / waste:** the main loop calls `draw_*` + `gfx.refresh()` every `POLL_MS` (250 ms) even with no input: ~4 full redraws/s while idle, up to 1,041 gfx calls per frame on a fully revealed map. The `-- power-friendly` comment is wrong, and so was my earlier claim that it redraws only on input.
20. **BUG:** bag capacity is 16 (`put_stack`) but only the first 9 are drawn/selectable, so stacks 10–16 are invisible. The ground grid has no row cap: more than 12 ground items would overlap the paper-doll.
21. **GAP:** loot exists only on the spawn tile (`generate_world`). Only 5 of the 10 slots have any wearable defined (head, hands, shirt, pants, feet); `cap` and `gloves` exist in `ITEM_DB` but never spawn, and ears/eyes/neck/jacket/wrists can never be filled.
22. **GAP:** the Lua app has no save/load, no main menu, no character creator/attributes/traits (sight 2 and MP 2 are constants); a new world every launch. The seed uses `os.time()` behind an `os and os.time and …` guard. Whether SolarOS's Lua includes `os` is unknown (if not, the seed is always 12345).
23. **GAP (both):** no combat, encounters, crafting, or Run/Hide/Spy/Scavenge actions (Python has placeholder buttons; Lua has nothing). "Known recipes" is a placeholder.
24. **Unverified assumptions:** mono-12 ≈ 7 px/char (taken from the Snake sample's `#msg * 7`); `gfx.KEY_LEFT/RIGHT/UP/DOWN` exist (used by the Snake sample, not listed in `lua.gfx.md`); Enter arrives as 13 or 10 (both handled); whether the physical keyboard has arrow keys is unknown (WASD works regardless).
25. **Test weakness:** `bounds_test.lua` and `body_test.lua` duplicate layout constants instead of importing them, so changing a layout constant in the game leaves those tests checking stale numbers.

---

## 3. What We Tried (chronological)

**Phase 1: Python/pygame for the Pi 3B+**
1. **Single-file pygame prototype:** flat hex grid (axial coordinates), click/arrow movement, terrain cost as hours. Worked.
2. **Isometric look:** vertical squash (`ISO_Y_SCALE 0.58`), darker extruded side faces, painter's-order drawing. Worked; later abandoned for the ESP target.
3. **Movement points:** first a flat 1 MP per step, then per-terrain cost. Swamp cost 3 exceeded the 2-MP cap and would have been unreachable, so I switched to *overdraft* (a move is allowed while MP > 0 and may go negative).
4. **Fog of war** (sight 2; explored tiles dimmed and flattened). *Bug:* rewriting the file silently dropped `axial_distance`, so the user hit `NameError` when running it. Fixed. The user then asked for 1024×600 and tile size 25.
5. **NEO Scavenger-style UI chrome** from a screenshot (left needs bars, right action buttons, bottom log). Mostly placeholders; bars were static.
6. **Refactor into modules + state machine** with `main.py` as the only entry point; main menu, character creator, `Player` model, JSON save. Tested only with a hand-written fake pygame (real pygame could not be installed in the sandbox).
7. **Needs system + inventory** (10 slots, ground loot, two-click transfer, CONSUME mode). One test failure was the *test's* fault (it walked onto water). In this version TAKE/DROP ≡ MOVE and WHOLE STACK is decorative.

**Phase 2: ESP32-S3 / SolarOS**
8. User asked if it'd run on an ESP32-S3. I explained pygame can't, and asked about display and language. Answers: "something else / not sure" and "C++/Arduino". The user then revealed the board and that it runs SolarOS.
9. Web search identified the Waveshare board and nilseuropa's SolarOS. I realized an Arduino sketch would *overwrite* SolarOS and asked; the user chose a Lua/Python script.
10. Searching for the Lua API returned **unrelated Lua APIs** (TI-Nspire, lsnes, lua9). Dead end. I asked the user, who pasted the SolarOS README and the **Snake** sample, which is what defined the API shape.
11. **`wasteland.lua` v1:** flat hexes drawn as 6 lines with a `fill_rect` bounding-box "wash", text-list inventory. Tested under Lua 5.4 with a fake `solaros`. Test-stub bug: `function gfx["end"]()` is invalid Lua syntax (use assignment).
12. User: "getting errors". I fetched their fork's `doc/manual/lua.gfx.md` and `lua.input.md`. Found: missing the documented `pcall`/cleanup convention; and that `circle`/`fill_circle` *do* exist (I had wrongly assumed no fill primitives). Wrapped everything in `pcall`. Errors persisted.
13. User photographed the on-device **`agent` app** diagnosing the crash: a float passed to `gfx.fill_rect` (it pointed at "line 480", which was the hex-fill `fill_rect`). Fix: `rnd()` at every `fill_rect`/`line` call; I hardened the fake to assert integers. User: **"it works!"**
14. **Inventory redesign** to match a NEO Scavenger screenshot (ground grid, paper-doll, slots around it, bag strip, conditions). The new *render-to-PNG* tool showed two bugs invisible to numeric checks: slot labels drawn under the boxes collided with the next slot (30 px pitch < 22 box + 12 text), and the bag row overlapped the log. Fixed: labels moved beside boxes, bag/log moved up.
15. The same tool exposed **map bugs**: fill rects poked out of the hexes (squares); the "reachable" highlight was invisible (black outline redrawn over black); remembered tiles looked identical to visible ones; the map sat off-center. Fixed with scanline hex fill, an inner outline, a LIGHT outline for remembered tiles, and centering.
16. **Item sprites:** 16×16 ASCII art packed to XBM at load; letter fallback for unknown items.
17. **Stick figure → polygon silhouette.** First version was asymmetric on 26 of 92 blocks: when an edge lands exactly on a pixel center, my rule included the pixel on the left and excluded it on the right. Fixed by making both sides strict → 0 of 81 lopsided.
18. **Terrain glyphs + legend + faded glyphs for remembered tiles + player halo.** I caught a Lua scoping bug *before running*: `draw_glyph` called `rnd`, which was defined ~350 lines below it (a `local` isn't visible above its definition).
19. **This handoff's audit** found bugs 17–20 above by *reading what's actually wired up* instead of trusting earlier test output.

**Dead ends / rejected micro-approaches:** bounding-box hex fills; labels under slots; a bold font to highlight the current legend entry (unknown glyph width could overflow 300 px); a single-row legend (needs exactly 288 of 300 px); duplicate `gfx.begin()` (was briefly present after a refactor).

---

## 4. Key Decisions

| Decision | Chosen | Rejected | Why |
|---|---|---|---|
| ESP target | Lua app on SolarOS | Bare-metal Arduino/ESP-IDF firmware | Would erase SolarOS; user picked scripting |
| Language on SolarOS | Lua | MicroPython | Only a Lua reference (Snake) was available; Python is equally supported (`python.gfx.md`) |
| ESP map look | Flat top-down hexes | Isometric blocks | No polygon fill, 1-bit dithered panel, 300 px width |
| App layout | One file | Multi-file like the Python version | Playground convention. Untested whether SolarOS `require` can load sibling files, which would be worth checking now that it's 1,235 lines |
| Art pipeline | ASCII → packed at load, validated | Hand-typed hex bytes | Readable, editable, typo fails loudly at startup |
| Body figure | Polygons rasterized once at load (81 blocks) | Per-frame polygon fill; tiling a big bitmap through the 128-byte sprite limit | Cheapest per frame; keeps art editable as point lists |
| Figure outline | Draw union in black grown 1 px, then gray at true size | Outline each part | Parts overlap; per-part outlines leave seams |
| Coordinates | `rnd()` at each gfx call site | Making all math integer | Hex math is inherently fractional |
| RNG | Own LCG (from Snake sample) | `math.random` | Sample's convention; avoids seeding surprises |
| Movement | Terrain cost = MP *and* hours; overdraft while MP > 0 | Hard block when MP < cost | Cost-3 tiles would be unreachable at a 2-MP cap (Lua's max cost is 2, but the rule was kept) |
| Conditions text | Only things the game tracks | Copy screenshot's "In pain / Camp benefits" | No injury/camp system exists; don't print labels with nothing behind them |
| Equip slots | Two columns flanking the figure | Anatomically placed on the body | 30 px pitch, 300 px width. **Open question for the user** |
| Legend | 2×2, mono font, box marks current terrain | 1×4 row; bold highlight | Width risk (see dead ends) |
| Glyphs | 10×10 (20 bytes) | 8×8 | Readability inside a 27 px hex |
| Data model | Plain tables `{item="id", qty=n}` | Objects | Trivially serializable when save/load is built |
| Testing | Fake `solaros` + recording renderer | Device-only testing | Fast loop. Cost: fakes encode *my beliefs* about the API |
| Redraw model | *Intended* redraw-on-input, *implemented* as a 250 ms poll loop | | Mismatch is bug 19 |

---

## 5. Evidence & Data

**Hardware (source: web search of Waveshare pages, not verified on the unit except resolution, which the user stated):** ESP32-S3-WROOM-1-N16R8 (16 MB flash, 8 MB PSRAM, 512 KB SRAM); 4.2" RLCD 300×400, ST7305 controller, 1-bit (no backlight). SolarOS (per `lua.gfx.md`): "One-bit displays keep the existing luminance and dither path", so LIGHT/DARK are ordered-dither patterns. The user's photo shows a status bar (battery, keyboard, Bluetooth, signal, speaker) and a shell prompt `gabe>`.

**SolarOS Lua API facts** (from the user's fork, `doc/manual/`):
- `gfx`: `begin([target])`, `end()`, `width/height/size`, `clear`, `color`, `font`, `pixel`, `line`, `rect`, `fill_rect`, `circle`, `fill_circle`, `icon`, `bitmap`/`sprite(x,y,w,h,data)`, `text(x, baseline_y, s)`, `refresh`/`present`, `getch([timeout_ms])`.
- Sprites: packed XBM, rows of `(w+7)//8` bytes, **LSB = leftmost pixel**, set bits draw in the current color, clear bits are transparent, ≤ 128 bytes per call.
- Fonts: `FONT_MONO_12…20`, `FONT_BOLD_12…20`. Colors: `WHITE/LIGHT/DARK/BLACK`, `gray(level)`, `rgb()`.
- `gfx["end"]()` because `end` is a Lua keyword. `solaros.should_exit()` for the loop.
- Keyboard navigation keys are documented under `solaros.tui.getch()` (`lua.input.md`), not `gfx`; the Snake sample nonetheless uses `gfx.KEY_*` with `gfx.getch`.

**The device error (from the user's photo of the on-device agent):** advice was to wrap the argument in `math.floor()` because `gfx.fill_rect` received a float; it referenced "line 480", which grep confirmed was `gfx.fill_rect(cx - HEX_SIZE * 0.75, …)` in `draw_hex` (other unrounded sites: line 452 player marker, line 485 `gfx.line`). **The literal runtime error string was never captured**; this diagnosis came via the agent's paraphrase.

**Test results on the delivered file** (from a clean copy of this bundle; tests ran under Lua 5.4.6, the device embeds 5.4.8): syntax OK; 6/6 unit tests; sprites: 9 items × 32 bytes round-trip exactly, LSB-first confirmed (pixel 0 → 0x01, pixel 15 → 0x80); 11 sprite calls in the default inventory frame (4 ground + 5 equipped + 2 bag); silhouette: 81 blocks, **394 `fill_rect` calls per frame**, extents x 93..207 / y 116..289 including outline, **0 asymmetric blocks (was 26 of 92)**, 0 overlaps with slots/labels/ground grid/conditions; glyph test: 64 glyph sprites on a fully revealed map (61 tiles − 1 player tile + 4 legend), legend text ends at x = 288 of 300; soak: 401 polls, no error.

**Per-frame gfx call counts** (recorded from the game; ×4/s while idle, per bug 19):

| Scene | Total | Breakdown |
|---|---|---|
| Map, start (fog radius 2) | 346 | 159 fill_rect, 150 line, 22 sprite |
| Map after walking | 397 | 117 fill_rect, 228 line, 35 sprite |
| Map, fully revealed | **1,041** | 565 fill_rect, 396 line, 64 sprite |
| Inventory, default | 462 | 407 fill_rect (394 silhouette), 20 rect, 20 text, 13 sprite |

No on-device timing has ever been measured.

**Bug repros** (`bash tests/repro_known_bugs.sh`):
```
[17] references to try_consume in wasteland.lua: 1   <- the definition only; never called
[18] stack of 2 bottles: thirst 10 -> 60 (one bottle gives +50); bottles left: 0 (expected 1)
[19] prints the loop source: draw_* then gfx.getch(POLL_MS), every iteration
[20] bag holds 16 stacks (cap 16) but the screen drew 9 bag icons
```

**Gameplay constants (Lua):** `GRID_RADIUS 4`, `HEX_SIZE 16`, `BASE_MAX_MP 2`, `BASE_SIGHT 2`, `REST_HOURS 4`, `POLL_MS 250`. Terrain (cost MP = hours): plains 1, forest 2, hills 2, water impassable. World weights: plains 45, forest 30, hills 18, water 7. Needs per awake hour: hunger −100/72, thirst −100/48, rest −100/18; resting: hunger/thirst ×0.5, rest +100/6 per hour (a 4 h rest ≈ +66.7). Each need at 0 → −1 MP on the next rest refill and on the "already rested" cap check (`effective_max_mp`, min 1); `max_mp` itself never changes.
Python additionally has swamp (cost 3) and ruins (cost 2), sight = 2 + (Perception−3)//2 + trait deltas, max MP = 2 + (Speed−3)//2 + trait deltas (both min 1), backpack cap 24.

**Layout numbers (300×400).** *Inventory:* ground grid origin (6,32), cell 40, gap 3, 6 cols; equip boxes 22 px, left column x=14, right column x=264, rows y=120/150/180/210/240, labels beside boxes (left: x+26, right: x−18); silhouette center x=150, rows 117..288; conditions baseline y=300; bag label y=318; bag cells y=322, 30 px, gap 2; log baselines 370/382/394. *Map:* HUD baselines 16/34/50; hex origin (150, 180), full map spans y=68..292; legend rows y=306 and 322 (14 px swatches, columns x=6 and x=156, text at +20); log baselines 348/362/376; hint baseline 392.

**Layout bugs the PNG renderer caught (numeric tests had passed):** equip labels clipped by next slot; bag overlapping log; square hex fills; invisible reachable highlight; remembered = visible look; off-center map.

---

## 6. User Feedback

**Style:** short, lowercase, direct requests ("ok now make it where…", "lets impliment gfx.sprite"). Chats from the **mobile app**, so keep answers brief and lead with the result. Reports device problems by **photographing the screen**, and once by pasting docs when asked. Wants the thing to *run on the device* and says so plainly ("it works!"). Never asked for explanations of the code.

**Explicit specs the user set:**
- Python, not Flash; Raspberry Pi 3B+; Python defaults **1024×600, tile size 25**; player starts with **2 MP**; **default sight 2**.
- Terrain movement cost should consume MP (they said yes when offered it); fog of war radius = sight stat.
- Body slots **exactly**: head, ears, eyes, neck, shirt, jacket, hands, wrists, pants, feet (single slots, no L/R).
- Separate files with **one file to run**; initial screen: load a save if present, else new character; character creator as a **cross of NEO Scavenger and Project Zomboid traits**.
- ESP: **keep SolarOS**, write a Lua/Python script for it.
- Visual targets are always **their NEO Scavenger screenshots** ("make the ui look like this", "change the inventory to look like this"). They want the *layout/feel* matched.
- Inventory: "make the stick figure … look like a person"; map: "show what tiles reflect what terrain".

**Corrections received:**
- `NameError: axial_distance` after I rewrote a file and dropped a function. Lesson: after any rewrite, check every name still exists.
- "im getting errors": my Lua script crashed on floats; I hadn't known the API required integers.

**What has worked in the working relationship:** flag placeholders honestly (the user has never objected to stubs, only to breakage); verify with fakes *and* look at rendered output before shipping; when stuck, ask the user for a device photo or the fork's docs rather than guess. The user had no objection to being asked one focused question.

**Not yet asked / unknown:** whether they want the Python version kept alive; how they deploy files to the board; whether the physical keyboard has arrow keys; whether they like the current silhouette and glyph art.

---

## 7. Where We're Going

**0. Ask the user (blocking unknowns; one message):** does the current `wasteland.lua` run without error (photo or pasted output)? How do you copy scripts onto the board, and what command launches one? Do arrow keys work or only WASD? Are the 10×10 terrain glyphs readable on the real panel? Should equip slots move next to their body parts? Keep the Python version alive?

**1. Fix consumption (bugs 17, 18), first, since the game is unplayable without it.** Bind a key in the inventory screen (`e`: free, since `a/d/s/w/i/q`, space and Enter are taken) to eat/drink the item under the cursor. Consume **one unit**: decrement `qty`, remove the stack only at 0. Fix the same stack bug in `python_version/state_inventory.py`. Update the header comment and the on-screen hint (`"Up/Dn select  Enter act  I map"`). Turn the two repros into real tests.

**2. Redraw only when something changed (bug 19).** Add a `dirty` flag set after any handled key, draw only when set, keep `gfx.getch` as the wait. Check `getch`'s blocking limits in `lua.input.md`/`lua.gfx.md`. Expected: idle redraws 4/s → 0. Fix the misleading `POLL_MS` comment.

**3. Bag/ground display limits (bug 20).** Either show 16 bag cells (needs a second row and layout re-check) or cap the bag at 9. Cap or scroll the ground grid. Extend `bounds_test.lua` to cover the worst case.

**4. Loot and scavenging (gap 21).** Per-terrain loot tables, a Scavenge action (costs MP/hours; pick an unused key, e.g. `f`), spawn `cap`/`gloves`, add items for ears/eyes/neck/jacket/wrists with sprites, merge identical stacks in `put_stack`.

**5. Persistence (gap 22).** Read `doc/manual/lua.storage.md` first. Save on quit; add a start-up "Continue". Persist player (pos, mp, hours, needs, equipped, inventory), tiles, ground items, explored set, seed. Data is already plain tables. Settle the `os.time` question at the same time.

**6. Main menu + character creator port (gap 22).** Port `traits.py`/`player.py` (attributes, trait budget, derived sight/MP formulas above) to a keyboard-driven 300×400 UI.

**7. Equip-slot layout + empty-slot ghost icons**, per the user's answer in step 0.

**8. Real gameplay systems (gap 23):** Run/Hide/Spy, encounters, combat with body-part injuries (→ real "conditions"), crafting + recipes screen, weight ("Unburdened"), temperature.

**9. Python version:** decide keep/archive. If kept, test with real pygame headless (`SDL_VIDEODRIVER=dummy`, *untested by me*) instead of a hand-written fake.

**10. Housekeeping:** `git init`; run `tests/run_tests.sh` in CI; make tests import layout constants from the game (gap 25); consider splitting `wasteland.lua` if SolarOS `require` can load sibling files.

---

## 8. Quick Start

```bash
cd solaros_wasteland_handoff

# deps (Debian/Ubuntu). Pillow is only needed for previews.
sudo apt-get install -y lua5.4 python3 && pip install pillow

bash tests/run_tests.sh           # whole suite, ~1 s, non-zero exit on failure
bash tests/repro_known_bugs.sh    # confirm bugs 17-20 reproduce BEFORE fixing
bash tests/render.sh              # writes previews/*.png; open them and LOOK

# Python version (parked); needs a display
cd python_version && pip install pygame && python3 main.py
```

**Layout of this bundle**
```
wasteland.lua            the app (edit this; nothing else is shipped)
HANDOFF.md               this file
previews/*.png           renders of the current screens (approximate; see caveat below)
tests/run_tests.sh       full suite            tests/render.sh        PNG previews
tests/make_lib.py        cuts wasteland.lua at the "-- Main loop" marker to make test-only copies
tests/solaros.lua        FAKE on-device module (has the scripted key queue). NEVER ship it
tests/render_stub/       FAKE that records gfx calls for the renderer. NEVER ship it
tests/*_test.lua, soak.lua, repro_known_bugs.sh, render_scene.lua, replay.py
python_version/          the pygame game (15 files)
```

**Deploying to the device:** unknown. The manual says the `lua` app can "execute .lua scripts from storage" (`man lua`, `help` on the device). I never learned how the user copies files or which path they use. Ask.

**Docs, in the user's fork** (`https://github.com/gabecamp/solar_os`, under `doc/manual/`): `lua.md`, `lua.gfx.md`, `lua.input.md`, `lua.tui.md`, `lua.storage.md`, `script.conventions.md`, `playground.md`. Read `lua.storage.md` before step 5 and `lua.tui.md` for the documented key handling.

**Debug loop that has worked:** change → `run_tests.sh` → `render.sh` → *view the PNGs* → give the user the updated `wasteland.lua` → they run it on the device and send a photo or pasted output. The board's built-in `agent` app can also explain runtime errors, and the user has used it.

**Gotchas (each cost real time):**
- Lua 5.4 `/` always returns a float; use `//` for integers. `math.floor/ceil` return integers. Every `gfx` coordinate must be an integer: wrap at the call site with `rnd()`.
- A `local function` is invisible to code *above* it in the file (`draw_glyph` was defined above `rnd` once, which would have crashed at the first map draw).
- Never write `function gfx["end"]() … end` (invalid syntax); call `gfx["end"]()`. Keep the `pcall` + always-`end` + re-raise pattern; don't call `gfx.begin()` twice.
- Sprite data must be exactly `((w+7)//8)*h` bytes, ≤ 128.
- Colors are the `gfx.*` constants only, never strings or ints.
- `tests/lib_only.lua`, `lib_map.lua`, `wasteland_run.lua` are **generated**. Edit only `wasteland.lua`, and keep the `-- Main loop` marker (make_lib.py cuts there).
- **Previews are approximations:** they replay the draw calls with a PC font and plain grays, and do not reproduce the RLCD's dithering, real font metrics, or refresh behavior. Trust the device over the PNGs.
