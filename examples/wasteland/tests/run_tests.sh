#!/usr/bin/env bash
# Whole suite, headless, ~1 second. Exits non-zero on the first failure.
#   bash tests/run_tests.sh
# Needs: lua5.4 + luac5.4 (apt-get install lua5.4), python3.
set -euo pipefail
cd "$(dirname "$0")"

command -v lua5.4  >/dev/null || { echo "missing lua5.4  (sudo apt-get install lua5.4)"; exit 1; }
command -v luac5.4 >/dev/null || { echo "missing luac5.4 (sudo apt-get install lua5.4)"; exit 1; }

# the game is edited in ../src/ and bundled into ../wasteland.lua: test what src/ says
python3 ../tools/build.py
python3 make_lib.py
# tests/solaros.lua is a FAKE of the on-device module; this makes require("solaros") find it.
export LUA_PATH="./?.lua;;"
export WASTELAND_SEED="${WASTELAND_SEED:-$(( $(date +%s) % 32768 ))}"
echo "world seed: $WASTELAND_SEED  (replay: WASTELAND_SEED=$WASTELAND_SEED bash tests/run_tests.sh)"

echo "== syntax ==";           luac5.4 -p ../wasteland.lua && echo OK
echo "== locals ==";           python3 ../tools/locals_headroom.py --min 10
for t in unit_test sprite_test bounds_test body_test glyph_test regression_test scavenge_test creator_test encounter_test portrait_test crafting_test world_test save_test radiation_test survival_test trade_test gear_test events_test hunting_test help_test karl_test sound_test difficulty_test dog_test tech_test journal_test vague_test base_test; do
  echo "== $t ==";             lua5.4 "$t.lua" | tail -n 2
done
echo "== main loop (scripted keys) =="; lua5.4 wasteland_run.lua
echo "== soak (400 random keys) ==";    lua5.4 soak.lua | tail -n 1
echo; echo "ALL PASSED"
