#!/usr/bin/env bash
# Build churn.opk, the package for OpenDingux (Anbernic RG350 and kin).
#
#   TOOLCHAIN=/opt/gcw0-toolchain ./build_opk.sh     cross-build for the handheld
#   NATIVE=1 ./build_opk.sh                          package a build for THIS computer
#                                                    (to check the packaging; it won't run on a handheld)
#
# TOOLCHAIN is the OpenDingux SDK (the one with bin/mipsel-*-gcc and a sysroot
# that has SDL 1.2): the program has to link against the handheld's own SDL,
# which is why it can't be built anywhere else. Lua 5.4 is downloaded from
# lua.org and built into the program, so nothing else is needed on the device.
# Needs: curl, make, mksquashfs (squashfs-tools), python3 + Pillow only to
# regenerate font_data.h (it is checked in).
set -euo pipefail
cd "$(dirname "$0")"
LUA_VER=5.4.7
OUT=churn.opk
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

command -v mksquashfs >/dev/null || { echo "missing mksquashfs (apt install squashfs-tools)"; exit 1; }

if [ -n "${NATIVE:-}" ]; then
    CC=${CC:-cc}
    SDL_CFLAGS=$(sdl-config --cflags); SDL_LIBS=$(sdl-config --libs)
else
    [ -n "${TOOLCHAIN:-}" ] || { echo "set TOOLCHAIN=/path/to/the/OpenDingux/SDK (or NATIVE=1)"; exit 1; }
    CC=$(ls "$TOOLCHAIN"/bin/*-gcc 2>/dev/null | grep -v -- '-gcc-[0-9]' | head -n1 || true)
    [ -n "$CC" ] || { echo "no *-gcc in $TOOLCHAIN/bin"; exit 1; }
    SDLCONFIG=$(find "$TOOLCHAIN" -name sdl-config -type f 2>/dev/null | head -n1 || true)
    [ -n "$SDLCONFIG" ] || { echo "no sdl-config under $TOOLCHAIN (the SDK needs SDL 1.2)"; exit 1; }
    SYSROOT=$(dirname "$(dirname "$SDLCONFIG")")
    SDL_CFLAGS=$("$SDLCONFIG" --cflags --prefix="$SYSROOT"); SDL_LIBS=$("$SDLCONFIG" --libs --prefix="$SYSROOT")
fi
echo "compiler: $CC"

# Lua, built into the program
if [ ! -d "lua-$LUA_VER" ]; then
    curl -fsSL "https://www.lua.org/ftp/lua-$LUA_VER.tar.gz" | tar xz
fi
LUA_SRC="lua-$LUA_VER/src"
mkdir -p "$STAGE/lua"
for f in "$LUA_SRC"/*.c; do
    case "$f" in */lua.c|*/luac.c) continue ;; esac
    "$CC" -O2 -std=gnu99 -DLUA_USE_POSIX -c "$f" -o "$STAGE/lua/$(basename "${f%.c}").o"
done

"$CC" -O2 -std=gnu99 -Wall $SDL_CFLAGS -I"$LUA_SRC" -o "$STAGE/churn_sdl" churn_sdl.c "$STAGE"/lua/*.o $SDL_LIBS -lm
if [ -z "${NATIVE:-}" ]; then   # (smaller: the handheld doesn't need the symbols)
    STRIP="${CC%-gcc}-strip"
    if [ -x "$STRIP" ]; then "$STRIP" "$STAGE/churn_sdl"; fi
fi
cp ../churn.lua default.gcw0.desktop icon.png "$STAGE/"
[ -f DejaVu-LICENSE.txt ] && cp DejaVu-LICENSE.txt "$STAGE/"
rm -rf "$STAGE/lua"
rm -f "$OUT"
mksquashfs "$STAGE" "$OUT" -all-root -noappend -no-progress >/dev/null
echo "built $OUT ($(du -h "$OUT" | cut -f1))"
