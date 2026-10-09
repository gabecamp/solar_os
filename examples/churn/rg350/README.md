# The Churn on an Anbernic RG350 (OpenDingux) and other SDL 1.2 handhelds

`churn_sdl.c` is a small C program that runs the real game, `../churn.lua`,
unchanged. It gives the game the `solaros` module it expects (screen, keys,
storage, sound), the same way `../python_version/churn_pygame.py` does on a PC.
Lua 5.4 is built into it; the only thing it needs from the handheld is SDL 1.2,
which every OpenDingux device has. The 400x300 picture is centered, with the
button legend in the border:

![On a 640x480 screen](../previews/rg350_map.png)

**Status: the program is built and tested on a PC (headless SDL, the real game,
every button path). It has not been run on a handheld, and the MIPS cross-build
has not been done; that needs the OpenDingux SDK, below.**

## Buttons

L and R are shift keys: hold one and the face buttons and the D-pad become
other keys. The legend in the border lights up the layer you're holding.

| | none | hold **L** | hold **R** | **L + R** |
|---|---|---|---|---|
| **A** | Enter | F search | X drop | B bestiary |
| **B** | Esc / back | C craft | Q quit (asks) | K skills |
| **X** | E use | T trade / camp | O work | Y yes |
| **Y** | Space (rest) | G hunt / fish | N notes | |
| **Start** | I bag / map | J journal | V device info | R records |
| **Select** | H help | P you (stats) | L lore | |
| **D-pad** | arrows | arrows, Left R radio, Right M sound | Up 1, Right 2, Down 3, Left 4 | arrows |

Every key the game uses can be reached. R + B is quit; Q then asks first
during a run, and your run is saved either way. A keyboard (an emulator on a
PC, say) works too: letters and digits are themselves. `--pc-keys` makes
Return, Esc and Space themselves as well.

## Screens

The program uses the video mode the handheld is in, and the biggest whole
scale of the 400x300 picture that fits: 1x on the RG350's 640x480. On a
320x240 screen (RG280V and the like) the picture is shrunk to fit, which
works but gives uneven pixels. Options: `--size WxH`, `--scale N` (0 = fill
the screen), `--no-legend`, `--mute`.

## Where things go

Saves and records are in `~/.the-churn` (or `$CHURN_DATA`), so the game file
can be replaced without touching them. There is no Wi-Fi code, so the game's
"update on open" prompt doesn't appear here: replace `churn.lua` instead
(download it from GitHub, or rebuild the OPK).

## Building

On a PC (to try it, or to work on it): `sudo apt install libsdl1.2-dev
liblua5.4-dev python3-pil fonts-dejavu-core`, then `make` and `make test`.
`make test` runs the real game headless through a few keys, pushes fake
button presses through the key code, and checks a broken game file is
reported.

For the handheld you need the OpenDingux SDK (a cross compiler for the
MIPS chip plus the handheld's SDL libraries). I couldn't fetch one from the
environment I wrote this in, so `build_opk.sh` takes it as a setting:

```sh
TOOLCHAIN=/opt/opendingux-toolchain ./build_opk.sh
```

It looks for `bin/*-gcc` and an `sdl-config` under that folder, downloads
and builds Lua 5.4, links it all into one program, and packs `churn.opk`
(a squashfs with the program, `churn.lua`, the icon and the launcher entry).
Copy the `.opk` to the SD card's `apps` folder, or install it from the
handheld's file manager. `NATIVE=1 ./build_opk.sh` builds the package for
your own computer, which only checks the packaging.

Fonts: `make_font.py` bakes DejaVu Sans Mono (the PC port's fonts) into
`font_data.h`, so neither SDL_ttf nor FreeType is needed on the device. The
fonts' licence is in `DejaVu-LICENSE.txt`.
