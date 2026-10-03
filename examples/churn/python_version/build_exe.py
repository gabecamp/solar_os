#!/usr/bin/env python3
"""
Build a one-file, no-install version of the PC game with PyInstaller:
dist/TheChurn.exe on Windows (TheChurn on Linux or macOS). It carries the
Lua game (../churn.lua) and the DejaVu Sans Mono fonts, so the player needs
nothing else. A churn.lua put next to the .exe is used instead of the one
inside, so the game can be updated without a new build.

    pip install pygame-ce lupa pyinstaller
    python build_exe.py [--fonts DIR]

--fonts: a folder holding DejaVuSansMono.ttf and DejaVuSansMono-Bold.ttf
(default: look in the usual places, else download the DejaVu release).
The GitHub workflow .github/workflows/churn-windows.yml runs this on Windows.
"""
import argparse
import io
import os
import pathlib
import shutil
import sys
import urllib.request
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
GAME = HERE.parent / "churn.lua"
FONTS = ("DejaVuSansMono.ttf", "DejaVuSansMono-Bold.ttf")
FONT_ZIP = ("https://github.com/dejavu-fonts/dejavu-fonts/releases/download/"
            "version_2_37/dejavu-fonts-ttf-2.37.zip")
SEARCH = ("/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/TTF", "/usr/share/fonts/dejavu",
          "/Library/Fonts", os.path.expanduser("~/Library/Fonts"), "C:/Windows/Fonts", str(HERE))


def find_fonts(build, given):
    """The two font files, copied into the build folder."""
    out = build / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    for d in ([given] if given else []) + list(SEARCH):
        if all((pathlib.Path(d) / f).is_file() for f in FONTS):
            for f in FONTS:
                shutil.copy(pathlib.Path(d) / f, out / f)
            return out
    print("fonts: downloading the DejaVu release")
    data = urllib.request.urlopen(FONT_ZIP, timeout=120).read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            if os.path.basename(name) in FONTS:
                (out / os.path.basename(name)).write_bytes(z.read(name))
    missing = [f for f in FONTS if not (out / f).is_file()]
    if missing:
        sys.exit("fonts: missing %s" % ", ".join(missing))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--fonts", help="a folder with the two DejaVu Sans Mono files")
    a = ap.parse_args(argv)
    if not GAME.is_file():
        sys.exit("no %s: build it first (python3 ../tools/build.py)" % GAME)
    import PyInstaller.__main__
    build = HERE / "build"
    fonts = find_fonts(build, a.fonts)
    sep = os.pathsep   # (PyInstaller's SOURCE<sep>DEST)
    args = [
        str(HERE / "churn_pygame.py"),
        "--name", "TheChurn",
        "--onefile",
        "--windowed",                      # (no console window behind the game)
        "--noconfirm",
        "--clean",
        "--distpath", str(HERE / "dist"),
        "--workpath", str(build / "work"),
        "--specpath", str(build),
        "--collect-all", "lupa",           # (its Lua runtimes are compiled modules)
        "--add-data", "%s%s." % (GAME, sep),
    ]
    for f in FONTS:
        args += ["--add-data", "%s%s." % (fonts / f, sep)]
    PyInstaller.__main__.run(args)
    exe = HERE / "dist" / ("TheChurn.exe" if sys.platform.startswith("win") else "TheChurn")
    if not exe.is_file():
        sys.exit("no %s after the build" % exe)
    print("built %s (%.1f MB)" % (exe, exe.stat().st_size / 1e6))


if __name__ == "__main__":
    main()
