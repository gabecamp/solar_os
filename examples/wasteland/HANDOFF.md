# Handoff: NEO Scavenger-style survival game (SolarOS Lua app + Python/pygame version)

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
> **Save/load is blocked by the firmware:** Lua has no way to write a file (`solaros.storage` has `read_file` but no write; `io`/`os` aren't loaded, `src/apps/solar_os_lua.c:556-568`). It needs a new `storage.write_file` binding in the fork plus a reflash. The user hasn't decided yet.
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
