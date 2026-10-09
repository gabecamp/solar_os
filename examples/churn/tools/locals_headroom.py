"""How many more top-level locals churn.lua can take before Lua's
200-locals-per-chunk limit (the bundle is one chunk). Run by
tests/run_tests.sh, which fails below MIN_HEADROOM.

    python3 tools/locals_headroom.py [--min N]
"""
import pathlib
import subprocess
import sys
import tempfile

here = pathlib.Path(__file__).resolve().parent.parent
src = (here / "churn.lua").read_text()
cut = src.index("-- Main loop")
need = int(sys.argv[sys.argv.index("--min") + 1]) if "--min" in sys.argv else 0


def compiles(pad):
    text = src[:cut] + "".join(f"local _pad{i} = 1\n" for i in range(pad)) + src[cut:]
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write(text)
    ok = subprocess.run(["luac5.4", "-p", f.name], capture_output=True).returncode == 0
    pathlib.Path(f.name).unlink()
    return ok


lo, hi = 0, 200   # binary search for the largest pad that still compiles
while lo < hi:
    mid = (lo + hi + 1) // 2
    if compiles(mid):
        lo = mid
    else:
        hi = mid - 1
print(f"top-level locals headroom: {lo}")
if lo < need:
    print(f"FAIL: below {need}; group new constants into tables (see HANDOFF)")
    sys.exit(1)
