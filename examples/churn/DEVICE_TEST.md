# Device test checklist

About 10 minutes on the board. Copy `churn.lua` over the way you did
before and start it. For anything that goes wrong, a photo of the screen
(or the error text) is the most useful thing to send back.

## 1. First look (1 min)
1. The character creator appears. Up/Down move the cursor, Left/Right change
   an attribute, Space toggles a trait. **Expect:** nothing cut off at the
   bottom; the stats line updates.
2. Press Enter. **Expect:** the hex map on the left, the panel on the right
   (day/time, weather, MP, needs, HP), three log lines and a key line at the
   bottom.
3. Press **H**, then **V**. **Expect:** the device info page. **Take a photo
   of it**: it shows the game version, memory use, the storage path and
   whether saving works.

## 2. Moving and the clock (2 min)
4. Move a few hexes: Left/Right step sideways; Up then Left (or Right) steps
   up-left (up-right), Down then Left/Right down-left/right (WASD too).
   **Expect:** after Up the bottom line says "Up: now Left or Right picks the
   side"; the map scrolls to keep you centered; MP drops; the hour goes up.
5. Space to rest. **Expect:** +4 hours, MP back.
6. F to search. **Expect:** "Found: ..." or "Found nothing", and the
   "Scav n/3" count drops.

## 3. Inventory and crafting (2 min)
7. I opens the bag. Arrows move the cursor over the ground, the body slots
   and the bag. Enter picks something up, Enter again drops it somewhere.
   **Expect:** you start with nothing: a bare doll and 2 bag cells (your
   arms). The ground holds a rock, 4 sticks, 6 cloth scraps, beans and 2 waters, with
   icons drawn (not blank boxes).
8. Pick up a water bottle and press E on it. **Expect:** thirst goes up and
   an Empty Bottle appears.
9. C opens crafting. **Expect:** a list of recipes with what each needs.
   Make **Foot Wraps** from the scraps on the ground, then E on them in the bag:
   **Expect:** holed boot icon on the doll's feet.

## 4. Things that make sound or use storage (2 min)
10. If you find a Geiger Counter, step onto a hot hex. **Expect:** a click
    and a "Geiger crackles" line.
11. Quit with Q and start again. **Expect:** with the `write_file` firmware
    patch, a title screen with **Continue**; without it, straight to the
    creator (that's correct, not a bug).
12. On the title (or the creator) press **R**. **Expect:** the records page
    with the achievement list; any key goes back. After a death it should
    show one more run.

## 5. An encounter (2 min)
13. Walk until something happens (forest is busiest), or press **G** in a
    forest to hunt. **Expect:** a 96x96 picture top right, the story text,
    and a list of choices.

## 6. New things to try (2026-10-02)
- **Story moments:** a new game opens on a short "The Churn" page (any key
  goes on); the first night, the first emission warning, the first burrow
  of the Little Ones and the quarry gate each get one too, once a run.
- **Weather on the map:** rain and storms draw streaks over the map, snow
  white flakes, fog a dotted veil; the panel reads like "Winter Snow".
- **Clothes wear out:** wear something a few days, or fight in it, then put
  the bag cursor on it: "Shirt: Rag Shirt 80%". C, **Patch clothes** mends
  the most worn piece for 1 cloth.
- **Starting with nothing:** walk 2 to 6 hexes out and search the piles:
  your old T-shirt, jeans, boots and backpack are out there. The rags you
  craft show as holed versions of the real icons.
- **Seasons and weather:** the panel's second line reads like "Aut Overcast"
  (season, weather). Wait or walk a few days: fog (sight 1), storms (find
  ruins, hills or trees), snow in winter (from day 11).
- **Mother Okun:** the journal and the map show the Ferry Post once you've
  seen it; **T** there trades (her prices are lower), **O** asks for work.
- **The Peddler:** a cart glyph that moves every 12 hours; **T** on his hex.
- **The Little Ones:** toys (crayons, a toy car...) turn up in searches.
  Leave three at the little stone cairns near a burrow (**E** on the toy or
  **T** on the cairn), then visit the burrow: small heads follow your
  figure on the map.
- **The quarry:** after reading six torn pages, the journal points to it.

## Expected numbers (measured on a PC with the test fake)
- Lua memory: about **845 KB** once loaded, **~1 MB** at most while
  playing. The device info page (H, then V) shows the real figure. On the
  SolarTerm board Lua lives in the 8 MB PSRAM, so this should be fine;
  much higher than ~1.3 MB on the device would be worth reporting.
- The script is ~460 KB; SolarOS streams it from storage, so size is not
  a limit.
- Redraws: the map is ~200-500 draw calls, the bag ~280 for a full redraw
  and ~100 when only the cursor moves. The device info page (H, V) says
  "Fast drawing: yes" when the firmware has `solaros.tick_interval`; then
  moving the bag cursor should feel instant and other screens should appear
  in well under half a second. If not, say which screen is slow.

## What to send back
- The photo of the device info page (H then V).
- Any error text, or a photo of anything that looks wrong.
- Whether the arrow keys work, or only WASD.
- Whether the screen feels slow to redraw after a key press.
