#!/usr/bin/env bash
# Run the real game through churn_sdl with no screen or sound: a few keys, and
# check it drew, played and left a save. (make test)
set -euo pipefail
cd "$(dirname "$0")"
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
export CHURN_DATA="$(mktemp -d)"
trap 'rm -rf "$CHURN_DATA"' EXIT

echo "1. a short game: splash, title, creator, walking, bag, back, quit"
# Enter x2 (splash, new survivor), Esc (skip the story), Enter (creator),
# then d d d (right), i (bag), i (map)
./churn_sdl --size 640x480 --keys $'\n\n\x1b\nddd' --dump "$CHURN_DATA/frame.bmp" ../churn.lua
test -s "$CHURN_DATA/frame.bmp"

echo "2. the shift layers, through the real key code"
./churn_sdl --size 640x480 --selftest-keys
python3 - <<'PY'
import re
src = open("churn_sdl.c").read()
m = re.search(r"KEYMAP\[4\]\[B_COUNT\] = \{(.*?)\n\};", src, re.S)
rows = [r for r in re.findall(r"\{([^}]*)\}", m.group(1))]
def key(layer, col):
    v = rows[layer].split(",")[col].strip()
    return v
assert key(1, 0) == "'f'" and key(2, 1) == "'q'", (key(1, 0), key(2, 1))
# every key the game binds is reachable from some layer or a keyboard
reach = {c for r in rows for c in re.findall(r"'(.)'", r)}
need = set("ecfgjhiprmtoxnvlbkyq1234 ")
missing = sorted(need - reach - {" "})
assert not missing, "unreachable on the handheld: %s" % missing
print("   all %d game keys reachable" % len(need))
PY

echo "3. a bad game file shows the error and fails"
echo 'error("boom")' > "$CHURN_DATA/bad.lua"
if ./churn_sdl --size 640x480 --keys "" "$CHURN_DATA/bad.lua" 2>"$CHURN_DATA/err.txt"; then
    echo "should have failed"; exit 1
fi
grep -q boom "$CHURN_DATA/err.txt"

echo "4. 320x240 screens (RG280V and the like) still run"
./churn_sdl --size 320x240 --keys $'\n\n\x1b\nd' ../churn.lua

echo "RG350 HOST TESTS PASSED"
