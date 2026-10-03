#!/usr/bin/env bash
# Wasteland Survivor (pygame version) installer for Linux and Raspberry Pi OS.
#
# Clones the game, checks what it needs, installs anything missing, and makes
# a launcher. Safe to run again: it updates the clone and skips what's done.
#
#   curl -fsSL https://raw.githubusercontent.com/gabecamp/solar_os/main/examples/wasteland/python_version/install.sh | bash
#   bash install.sh [--dir DIR] [--branch NAME] [--repo URL] [--no-system] [--yes]
#
#   --dir DIR      where to put the game (default: ~/wasteland-survivor)
#   --branch NAME  which branch to get (default: main)
#   --repo URL     which repository (default: https://github.com/gabecamp/solar_os.git)
#   --no-system    never install system packages (no sudo); only report them
#   --yes          don't ask before installing system packages
#
# Needs: bash, and internet. Everything else it checks for and installs:
# git, Python 3.8+ with venv and pip, the DejaVu fonts, and (only where pip
# has no ready-made wheel, e.g. 32-bit Raspberry Pi OS) a C compiler and the
# SDL libraries, then pygame and lupa inside a private virtual environment.
set -euo pipefail

REPO_URL="https://github.com/gabecamp/solar_os.git"
BRANCH="main"
DEST="${HOME}/wasteland-survivor"
SYSTEM=1
ASSUME_YES=0
GAME_PATH="examples/wasteland"

while [ $# -gt 0 ]; do
    case "$1" in
        --dir) DEST="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --repo) REPO_URL="$2"; shift 2 ;;
        --no-system) SYSTEM=0; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
done

# -- output helpers -----------------------------------------------------------
if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else B= G= Y= R= N=; fi
step() { echo; echo "${B}== $*${N}"; }
ok()   { echo "  ${G}ok${N}    $*"; }
warn() { echo "  ${Y}warn${N}  $*"; }
die()  { echo "  ${R}error${N} $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# -- system packages ----------------------------------------------------------
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

PM=""
if have apt-get; then PM=apt
elif have dnf; then PM=dnf
elif have pacman; then PM=pacman
elif have zypper; then PM=zypper
fi

# Package names per manager for each thing we may need.
pkgs_for() {
    case "$PM:$1" in
        apt:git) echo git ;;
        apt:python) echo "python3 python3-venv python3-pip" ;;
        apt:fonts) echo fonts-dejavu-core ;;
        apt:build) echo "build-essential python3-dev pkg-config libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev libfreetype6-dev libportmidi-dev libjpeg-dev" ;;
        dnf:git) echo git ;;
        dnf:python) echo "python3 python3-pip" ;;
        dnf:fonts) echo dejavu-sans-mono-fonts ;;
        dnf:build) echo "gcc gcc-c++ make python3-devel pkgconf SDL2-devel SDL2_image-devel SDL2_mixer-devel SDL2_ttf-devel freetype-devel" ;;
        pacman:git) echo git ;;
        pacman:python) echo "python python-pip" ;;
        pacman:fonts) echo ttf-dejavu ;;
        pacman:build) echo "base-devel sdl2 sdl2_image sdl2_mixer sdl2_ttf freetype2" ;;
        zypper:git) echo git ;;
        zypper:python) echo "python3 python3-pip" ;;
        zypper:fonts) echo dejavu-fonts ;;
        zypper:build) echo "gcc gcc-c++ make python3-devel pkg-config libSDL2-devel libSDL2_image-devel libSDL2_mixer-devel libSDL2_ttf-devel freetype2-devel" ;;
    esac
}

APT_UPDATED=0
install_pkgs() {   # install_pkgs <what> : git | python | fonts | build
    local what="$1" list
    list="$(pkgs_for "$what")"
    if [ -z "$PM" ] || [ -z "$list" ]; then
        warn "no known package manager; please install $what yourself"
        return 1
    fi
    if [ "$SYSTEM" -eq 0 ]; then
        warn "skipping system packages (--no-system): $list"
        return 1
    fi
    if [ -n "$SUDO" ] && ! have sudo; then
        warn "need root to install: $list (no sudo found)"
        return 1
    fi
    # Ask on the terminal: under "curl ... | bash" stdin is the script itself.
    if [ "$ASSUME_YES" -eq 0 ] && { : </dev/tty; } 2>/dev/null; then
        read -r -p "  install with $PM: $list ? [Y/n] " answer </dev/tty
        case "$answer" in [nN]*) return 1 ;; esac
    fi
    echo "  installing: $list"
    case "$PM" in
        apt)
            if [ "$APT_UPDATED" -eq 0 ]; then $SUDO apt-get update -qq; APT_UPDATED=1; fi
            # shellcheck disable=SC2086
            $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $list ;;
        dnf)    $SUDO dnf install -y $list ;;
        pacman) $SUDO pacman -S --needed --noconfirm $list ;;
        zypper) $SUDO zypper --non-interactive install $list ;;
    esac
}

# -- 1. git ---------------------------------------------------------------------
step "1/6 git"
if have git; then ok "$(git --version)"
else
    install_pkgs git || die "git is required (https://git-scm.com/download/linux)"
    have git || die "git still not found"
    ok "$(git --version)"
fi

# -- 2. Python 3.8+ with venv and pip ---------------------------------------------
step "2/6 Python 3.8 or newer, with venv"
PY=""
for cand in python3 python; do
    if have "$cand" && "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
        PY="$(command -v "$cand")"; break
    fi
done
venv_ok() { [ -n "$PY" ] && "$PY" -c 'import venv, ensurepip' >/dev/null 2>&1; }
if [ -z "$PY" ] || ! venv_ok; then
    install_pkgs python || true
    for cand in python3 python; do
        if have "$cand" && "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
            PY="$(command -v "$cand")"; break
        fi
    done
fi
[ -n "$PY" ] || die "Python 3.8+ is required (https://www.python.org/downloads/)"
venv_ok || die "Python's venv module is missing (Debian/Ubuntu/Pi: sudo apt install python3-venv)"
ok "$("$PY" --version) at $PY"

# -- 3. get the game ------------------------------------------------------------
step "3/6 the game ($BRANCH) into $DEST"
if [ -d "$DEST/.git" ]; then
    git -C "$DEST" fetch --depth 1 origin "$BRANCH"
    git -C "$DEST" checkout -q -B "$BRANCH" FETCH_HEAD
    ok "updated the existing copy"
else
    [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ] && die "$DEST exists and is not empty (use --dir)"
    # Only the game's folder: the repository also holds a whole firmware.
    if git clone --depth 1 --branch "$BRANCH" --filter=blob:none --sparse "$REPO_URL" "$DEST" 2>/dev/null; then
        git -C "$DEST" sparse-checkout set "$GAME_PATH"
        ok "cloned (game folder only)"
    else
        rm -rf "$DEST"
        git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$DEST"
        ok "cloned"
    fi
fi
GAME="$DEST/$GAME_PATH"
HOST="$GAME/python_version"
[ -f "$HOST/wasteland_pygame.py" ] || die "no python_version/ in branch '$BRANCH' (try --branch)"
[ -f "$GAME/wasteland.lua" ] || die "no wasteland.lua in branch '$BRANCH'"
ok "game files present"

# -- 4. fonts -----------------------------------------------------------------
step "4/6 fonts (DejaVu Sans Mono: the text lines up like on the device)"
font_found() {
    for d in /usr/share/fonts/truetype/dejavu /usr/share/fonts/TTF /usr/share/fonts/dejavu \
             /usr/share/fonts/dejavu-sans-mono-fonts /usr/share/fonts/truetype "$HOST"; do
        [ -f "$d/DejaVuSansMono.ttf" ] && [ -f "$d/DejaVuSansMono-Bold.ttf" ] && return 0
    done
    return 1
}
if font_found; then ok "found"
else
    install_pkgs fonts || true
    if ! font_found; then
        # Last resort: the fonts' own release, next to the game (it looks there too).
        url="https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
        tmp="$(mktemp -d)"
        if curl -fsSL "$url" -o "$tmp/dejavu.zip" 2>/dev/null || wget -q "$url" -O "$tmp/dejavu.zip" 2>/dev/null; then
            "$PY" - "$tmp/dejavu.zip" "$HOST" <<'EOF'
import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if os.path.basename(n) in ("DejaVuSansMono.ttf", "DejaVuSansMono-Bold.ttf"):
        open(os.path.join(sys.argv[2], os.path.basename(n)), "wb").write(z.read(n))
EOF
        fi
        rm -rf "$tmp"
    fi
    if font_found; then ok "installed"; else warn "not found: the game runs, but its text won't line up"; fi
fi

# -- 5. pygame and lupa in a virtual environment ----------------------------------
step "5/6 pygame and lupa (in $HOST/.venv)"
VENV="$HOST/.venv"
make_venv() {   # make_venv [--system-site-packages]
    rm -rf "$VENV"
    "$PY" -m venv "$@" "$VENV"
    "$VENV/bin/python" -m pip install --quiet --upgrade pip
}
pip_install() { "$VENV/bin/python" -m pip install --quiet --prefer-binary -r "$HOST/requirements.txt"; }
deps_ok() { "$VENV/bin/python" -c 'import pygame; from lupa import lua54' >/dev/null 2>&1; }

if [ -x "$VENV/bin/python" ] && deps_ok; then
    ok "already installed"
else
    make_venv
    if ! pip_install; then
        # No ready-made wheel for this machine (32-bit Pi OS, an unusual
        # distribution or a very new Python): build from source.
        warn "no ready-made packages for $(uname -m); building from source (several minutes on a Pi)"
        install_pkgs build || true
        if ! pip_install; then
            # pygame from the system, lupa from source.
            if [ "$PM" = apt ]; then
                warn "trying the system's pygame (python3-pygame)"
                if [ "$SYSTEM" -eq 1 ]; then
                    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-pygame || true
                fi
                make_venv --system-site-packages
                pip_install || "$VENV/bin/python" -m pip install --quiet lupa || true
            fi
        fi
    fi
    deps_ok || die "pygame or lupa could not be installed; see the messages above"
    ok "$("$VENV/bin/python" -c 'import pygame, lupa; print("pygame", pygame.version.ver, "- lupa", lupa.__version__)' 2>/dev/null | tail -1)"
fi

# -- 6. check it runs, and make launchers --------------------------------------------
step "6/6 a quick test game (no window), and launchers"
check="$(cd "$HOST" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy PYGAME_HIDE_SUPPORT_PROMPT=1 \
    "$VENV/bin/python" - <<'EOF' 2>&1 | tail -1
import tempfile
import wasteland_pygame as w
tmp = tempfile.mkdtemp()
h = w.run(keys=[10, 32], mute=True, data_dir=tmp)
print("ERROR " + h.error if h.error else "OK %d frames" % h.frames)
EOF
)"
case "$check" in
    OK*) ok "the game started and drew ${check#OK }" ;;
    *) die "the test game failed: $check" ;;
esac

cat > "$DEST/play.sh" <<EOF
#!/usr/bin/env bash
# Start Wasteland Survivor. Options: --fullscreen --scale N --look gray|device|amber|green --mute
cd "$HOST" && exec "$VENV/bin/python" wasteland_pygame.py "\$@"
EOF
chmod +x "$DEST/play.sh"
ok "launcher: $DEST/play.sh"

# A menu entry on desktops that use .desktop files (not on a headless box).
if [ -d "$HOME/.local/share" ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/wasteland-survivor.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Wasteland Survivor
Comment=Survive the Zone
Exec=$DEST/play.sh
Terminal=false
Categories=Game;
EOF
    ok "menu entry: Games > Wasteland Survivor"
fi

echo
echo "${B}Ready.${N} Play with:"
echo "  $DEST/play.sh                 (a window, 800x600)"
echo "  $DEST/play.sh --fullscreen    (good on a Raspberry Pi screen or TV)"
echo "Run this installer again any time to update the game."
