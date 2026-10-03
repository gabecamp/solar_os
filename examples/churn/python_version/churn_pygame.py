#!/usr/bin/env python3
"""
The Churn for a PC or a Raspberry Pi: a pygame window that runs the
real game, ../churn.lua, unchanged.

The game is written for SolarOS, which gives Lua apps a `solaros` module
(screen, keys, storage, sound). This file provides that module from Python:
lupa runs the Lua 5.4 game, and every gfx call draws into a 400x300 canvas
that is shown scaled up in a window. So this plays exactly like the device,
and any change to the Lua game shows up here with no Python work.

    pip install pygame-ce lupa      # (or pygame; pygame-ce has builds for the newest Pythons)
    python3 churn_pygame.py [--scale 2] [--fullscreen] [--look gray]

Looks: gray (four flat grays), device (the reflective LCD's 1-bit dither),
amber and green (terminal tints). Saves and records go to a per-user data
folder (see --data). Close the window or press Q on the map to quit.
"""

import argparse
import array
import math
import os
import sys
import time

os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
import pygame  # noqa: E402

try:
    from lupa import lua54
except ImportError:  # pragma: no cover - explained to the user below
    lua54 = None

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_GAME = os.path.join(HERE, os.pardir, "churn.lua")

W, H = 400, 300
# SolarOS color ids, in the firmware's order (src/services/solar_os_gfx.h)
WHITE, LIGHT, DARK, BLACK = 0, 1, 2, 3
FONT_MONO_12, FONT_BOLD_14 = 0, 1
KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT = 0x1B, 0x80, 0x81, 0x82, 0x83

# The canvas holds these exact grays; each look maps them to what's shown.
GRAY = {WHITE: (255, 255, 255), LIGHT: (190, 190, 190), DARK: (105, 105, 105), BLACK: (0, 0, 0)}
# The firmware's dither: a pixel is white where bayer4 < the color's threshold
# (gfx_dither_threshold / bayer4 in src/services/solar_os_gfx.c).
THRESHOLD = {WHITE: 16, LIGHT: 12, DARK: 5, BLACK: 0}
BAYER4 = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
TINTS = {"amber": ((18, 10, 0), (255, 176, 40)), "green": ((4, 16, 6), (90, 255, 120))}

FONT_FILES = {
    FONT_MONO_12: ("DejaVuSansMono.ttf", 11),
    FONT_BOLD_14: ("DejaVuSansMono-Bold.ttf", 13),
}
FONT_DIRS = (
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/TTF",
    "/usr/share/fonts/dejavu",
    "/Library/Fonts",
    os.path.expanduser("~/Library/Fonts"),
    "C:/Windows/Fonts",
    HERE,
)


def default_data_dir():
    if sys.platform.startswith("win"):
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        return os.path.join(base, "TheChurn")
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "the-churn")


def _text(value):
    """A Lua string (bytes with encoding=None) as Python text."""
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return "" if value is None else str(value)


class Host:
    """The `solaros` module for the game, drawn with pygame."""

    def __init__(self, scale=2, fullscreen=False, look="gray", mute=False, data_dir=None,
                 keys=None, on_frame=None, caption="The Churn"):
        self.scale, self.fullscreen, self.look = scale, fullscreen, look
        self.data_dir = os.path.abspath(data_dir or default_data_dir())
        self.script = list(keys) if keys is not None else None   # tests: keys to send, then quit
        self.on_frame = on_frame                                    # tests: called after each refresh
        self.closed = False
        self.color, self.font_id = BLACK, FONT_MONO_12
        self.frames = 0
        self.notes = []          # tone_async queue: (freq, ms, vol)
        self.sprite_cache = {}

        pygame.init()
        pygame.display.set_caption(caption)
        pygame.key.set_repeat(300, 60)
        flags = pygame.FULLSCREEN if fullscreen else 0
        size = (0, 0) if fullscreen else (W * scale, H * scale)
        self.window = pygame.display.set_mode(size, flags)
        self.canvas = pygame.Surface((W, H))
        self.canvas.fill(GRAY[WHITE])
        self.fonts = {fid: self._load_font(fid) for fid in FONT_FILES}
        self.patterns = self._dither_patterns() if look == "device" else None
        self.audio_ok = False
        if not mute:
            try:
                pygame.mixer.init(frequency=22050, size=-16, channels=1)
                self.channel = pygame.mixer.Channel(0)
                self.audio_ok = True
            except pygame.error:
                pass
        self.tones = {}

    # -- fonts and looks ---------------------------------------------------

    def _load_font(self, fid):
        name, size = FONT_FILES[fid]
        for d in FONT_DIRS:
            path = os.path.join(d, name)
            if os.path.exists(path):
                return pygame.font.Font(path, size)
        print("warning: %s not found; text will not line up (install fonts-dejavu)" % name,
              file=sys.stderr)
        return pygame.font.Font(None, size + 4)

    def _dither_patterns(self):
        """White/black pattern surfaces for LIGHT and DARK, the size of the screen."""
        out = {}
        for c in (LIGHT, DARK):
            s = pygame.Surface((W, H))
            s.fill((0, 0, 0))
            for y in range(H):
                row = BAYER4[y & 3]
                for x in range(W):
                    if row[x & 3] < THRESHOLD[c]:
                        s.set_at((x, y), (255, 255, 255))
            out[c] = s
        return out

    def _shown(self):
        """The canvas as it should look: grays, dithered, or tinted."""
        if self.look == "device":
            out = self.canvas.copy()
            for c in (LIGHT, DARK):
                mask = pygame.mask.from_threshold(self.canvas, GRAY[c], (1, 1, 1, 255))
                if mask.count():
                    mask.to_surface(out, setsurface=self.patterns[c], unsetsurface=None,
                                    setcolor=None, unsetcolor=None)
            return out
        if self.look in TINTS:
            dark, bright = TINTS[self.look]
            out = self.canvas.copy()
            for c in (WHITE, LIGHT, DARK, BLACK):
                k = GRAY[c][0] / 255.0
                col = tuple(int(dark[i] + (bright[i] - dark[i]) * k) for i in range(3))
                pygame.PixelArray(out).replace(GRAY[c], col)
            return out
        return self.canvas

    # -- gfx ------------------------------------------------------------------

    def gfx_begin(self, *_):
        return None

    def gfx_end(self, *_):
        self.refresh()

    def clear(self, c=None):
        self.canvas.fill(GRAY[c if c is not None else WHITE])

    def set_color(self, c):
        self.color = c if c in GRAY else BLACK

    def set_font(self, f):
        self.font_id = f if f in self.fonts else FONT_MONO_12

    def text(self, x, y, s):
        font = self.fonts[self.font_id]
        img = font.render(_text(s), False, GRAY[self.color])
        self.canvas.blit(img, (int(x), int(y) - font.get_ascent()))   # y is the baseline

    def line(self, x0, y0, x1, y1):
        pygame.draw.line(self.canvas, GRAY[self.color], (int(x0), int(y0)), (int(x1), int(y1)))

    def rect(self, x, y, w, h):
        if w > 0 and h > 0:
            pygame.draw.rect(self.canvas, GRAY[self.color], (int(x), int(y), int(w), int(h)), 1)

    def fill_rect(self, x, y, w, h):
        if w > 0 and h > 0:
            self.canvas.fill(GRAY[self.color], (int(x), int(y), int(w), int(h)))

    def circle(self, x, y, r):
        pygame.draw.circle(self.canvas, GRAY[self.color], (int(x), int(y)), int(r), 1)

    def fill_circle(self, x, y, r):
        pygame.draw.circle(self.canvas, GRAY[self.color], (int(x), int(y)), int(r))

    def pixel(self, x, y):
        if 0 <= x < W and 0 <= y < H:
            self.canvas.set_at((int(x), int(y)), GRAY[self.color])

    def sprite(self, x, y, w, h, data):
        """1-bit rows, (w+7)//8 bytes each, least significant bit first; set
        bits are drawn in the current color, clear bits leave the canvas."""
        w, h = int(w), int(h)
        key = (w, h, bytes(data), self.color)
        img = self.sprite_cache.get(key)
        if img is None:
            if len(self.sprite_cache) > 4000:
                self.sprite_cache.clear()
            img = pygame.Surface((w, h))
            hole = (1, 2, 3) if self.color != WHITE else (3, 2, 1)
            img.fill(hole)
            img.set_colorkey(hole)
            ink, bpr = GRAY[self.color], (w + 7) // 8
            for row in range(h):
                for col in range(w):
                    i = row * bpr + col // 8
                    if i < len(data) and (data[i] >> (col % 8)) & 1:
                        img.set_at((col, row), ink)
            self.sprite_cache[key] = img
        self.canvas.blit(img, (int(x), int(y)))

    def refresh(self, *_):
        self.frames += 1
        shown = self._shown()
        ww, wh = self.window.get_size()
        k = max(1, min(ww // W, wh // H)) if self.fullscreen else self.scale
        scaled = pygame.transform.scale(shown, (W * k, H * k))
        self.window.fill((0, 0, 0))
        self.window.blit(scaled, ((ww - W * k) // 2, (wh - H * k) // 2))
        pygame.display.flip()
        if self.on_frame:
            self.on_frame(self)

    def size(self):
        return W, H

    def _key_code(self, ev):
        special = {
            pygame.K_UP: KEY_UP, pygame.K_DOWN: KEY_DOWN, pygame.K_LEFT: KEY_LEFT,
            pygame.K_RIGHT: KEY_RIGHT, pygame.K_ESCAPE: KEY_ESCAPE, pygame.K_RETURN: 10,
            pygame.K_KP_ENTER: 10, pygame.K_BACKSPACE: 8, pygame.K_TAB: 9,
        }
        if ev.key in special:
            return special[ev.key]
        if ev.unicode and len(ev.unicode) == 1 and 32 <= ord(ev.unicode) < 127:
            return ord(ev.unicode.lower()) if ev.unicode.isalpha() else ord(ev.unicode)
        return None

    def getch(self, timeout_ms=None):
        """The next key, waiting up to timeout_ms (nil: forever)."""
        if self.script is not None:   # tests: scripted keys, then Q
            self._pump_audio()
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    self.closed = True
            if self.script:
                return self.script.pop(0)
            self.closed = True
            return ord("q")
        deadline = None if timeout_ms is None else time.monotonic() + int(timeout_ms) / 1000.0
        while True:
            self._pump_audio()
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    self.closed = True
                    return None
                if ev.type == pygame.KEYDOWN:
                    code = self._key_code(ev)
                    if code is not None:
                        return code
                if ev.type in (pygame.VIDEOEXPOSE, pygame.WINDOWEXPOSED):
                    self.refresh()
            if self.closed or (deadline is not None and time.monotonic() >= deadline):
                return None
            pygame.time.wait(5)

    def should_exit(self):
        return self.closed

    # -- sound ----------------------------------------------------------------

    def _sound(self, freq, ms, vol):
        key = (int(freq), int(ms), int(vol or 60))
        snd = self.tones.get(key)
        if snd is None:
            rate = 22050
            n = max(1, rate * key[1] // 1000)
            amp = int(9000 * min(100, max(0, key[2])) / 100)
            if key[0] <= 0:
                samples = array.array("h", [0] * n)
            else:
                half = max(1, int(rate / key[0] / 2))
                samples = array.array("h", (amp if (i // half) % 2 == 0 else -amp for i in range(n)))
            snd = pygame.mixer.Sound(buffer=samples.tobytes())
            self.tones[key] = snd
        return snd

    def _pump_audio(self):
        if self.audio_ok and self.notes and not self.channel.get_busy():
            self.channel.play(self._sound(*self.notes.pop(0)))

    def tone(self, freq, ms, vol=None):
        if self.audio_ok:
            self.channel.play(self._sound(freq, ms, vol))
            pygame.time.wait(int(ms))
        return True

    def tone_async(self, freq, ms, vol=None):
        if self.audio_ok:
            self.notes.append((freq, ms, vol))
            self._pump_audio()
        return True

    # -- storage (under the data folder) --------------------------------------

    def _path(self, p):
        """A game path to a real one, kept inside the data folder."""
        p = _text(p)
        full = os.path.abspath(os.path.join(self.data_dir, p.lstrip("/")))
        if os.path.commonpath([full, self.data_dir]) != self.data_dir:
            raise ValueError("path outside the data folder: " + p)
        return full

    def mount_point(self):
        os.makedirs(self.data_dir, exist_ok=True)
        return b"/"

    def exists(self, p):
        return os.path.exists(self._path(p))

    def makedirs(self, p):
        os.makedirs(self._path(p), exist_ok=True)
        return True

    def read_file(self, p, max_bytes=None):
        path = self._path(p)
        if not os.path.isfile(path):
            return None, b"not found"
        with open(path, "rb") as f:
            return f.read(int(max_bytes) if max_bytes else -1)

    def write_file(self, p, data):
        path = self._path(p)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data if isinstance(data, bytes) else _text(data).encode())
        os.replace(tmp, path)
        return True

    def rename(self, old, new):
        src, dst = self._path(old), self._path(new)
        if not os.path.isfile(src):
            raise FileNotFoundError(_text(old))
        os.replace(src, dst)
        return True

    def remove(self, p):
        path = self._path(p)
        if os.path.isfile(path):
            os.remove(path)
        return True

    # -- time -----------------------------------------------------------------

    def uptime_ms(self):
        return int(time.time() * 1000) % (2 ** 31)

    def tick_interval(self, ms=None):
        return 25


def build_runtime(host):
    """A Lua 5.4 runtime whose require("solaros") is the host."""
    lua = lua54.LuaRuntime(encoding=None, unpack_returned_tuples=True)
    make = lua.eval("""
        function(h)
            local gfx = {
                WHITE = 0, LIGHT = 1, DARK = 2, BLACK = 3,
                FONT_MONO_12 = 0, FONT_BOLD_14 = 1,
                KEY_ESCAPE = 0x1b, KEY_UP = 0x80, KEY_DOWN = 0x81, KEY_LEFT = 0x82, KEY_RIGHT = 0x83,
            }
            local function wrap(name) return function(...) return h[name](...) end end
            for _, n in ipairs({"clear", "text", "line", "rect", "fill_rect", "circle",
                                "fill_circle", "pixel", "sprite", "refresh", "size", "getch"}) do
                gfx[n] = wrap(n)
            end
            gfx.begin, gfx["end"] = wrap("gfx_begin"), wrap("gfx_end")
            gfx.color, gfx.font = wrap("set_color"), wrap("set_font")
            gfx.bitmap = gfx.sprite
            local M = {
                gfx = gfx,
                audio = {tone = wrap("tone"), tone_async = wrap("tone_async")},
                storage = {mount_point = wrap("mount_point"), exists = wrap("exists"),
                           makedirs = wrap("makedirs"), read_file = wrap("read_file"),
                           write_file = wrap("write_file"), remove = wrap("remove"),
                           rename = wrap("rename")},
                time = {uptime_ms = wrap("uptime_ms")},
                tick_interval = wrap("tick_interval"),
                should_exit = wrap("should_exit"),
            }
            package.preload.solaros = function() return M end
            package.loaded.solaros = nil
            return M
        end
    """)
    calls = {name: getattr(host, name) for name in (
        "clear", "text", "line", "rect", "fill_rect", "circle", "fill_circle", "pixel",
        "sprite", "refresh", "size", "getch", "gfx_begin", "gfx_end", "set_color", "set_font",
        "tone", "tone_async", "mount_point", "exists", "makedirs", "read_file", "write_file",
        "remove", "rename", "uptime_ms", "tick_interval", "should_exit")}
    make(lua.table_from({k.encode(): v for k, v in calls.items()}))
    return lua


def show_error(host, message):
    """A Lua error, on screen, until a key or the window is closed."""
    print(message, file=sys.stderr)
    host.canvas.fill(GRAY[WHITE])
    font = host.fonts[FONT_MONO_12]
    lines = ["The game stopped with an error:", ""]
    for raw in message.splitlines():
        while raw:
            lines.append(raw[:55])
            raw = raw[55:]
    y = 16
    for line in lines[:19]:
        host.canvas.blit(font.render(line, False, GRAY[BLACK]), (6, y - font.get_ascent()))
        y += 14
    host.canvas.blit(font.render("Any key closes the window.", False, GRAY[BLACK]),
                     (6, H - 8 - font.get_ascent()))
    host.refresh()
    if host.script is None:
        while not host.closed and host.getch(None) is None:
            pass


def run(game_path=DEFAULT_GAME, **options):
    """Run the game; returns the host (tests look at it afterwards)."""
    if lua54 is None:
        sys.exit("lupa is missing: pip install lupa")
    host = Host(**options)
    with open(game_path, "rb") as f:
        source = f.read()
    lua = build_runtime(host)
    try:
        lua.execute(source)
    except Exception as err:  # a lupa.LuaError, with the Lua traceback in it
        host.error = str(err)
        show_error(host, host.error)
    else:
        host.error = None
    return host


def main(argv=None):
    ap = argparse.ArgumentParser(description="The Churn on a PC or Raspberry Pi.")
    ap.add_argument("--scale", type=int, default=2, help="window size: 400x300 times this (default 2)")
    ap.add_argument("--fullscreen", action="store_true", help="fill the screen (largest whole scale)")
    ap.add_argument("--look", choices=("gray", "device", "amber", "green"), default="gray",
                    help="gray (default), device (1-bit dither like the LCD), amber, green")
    ap.add_argument("--mute", action="store_true", help="no sound")
    ap.add_argument("--data", help="where saves and records go (default: %s)" % default_data_dir())
    ap.add_argument("--game", default=DEFAULT_GAME, help="the game file (default: ../churn.lua)")
    a = ap.parse_args(argv)
    host = run(a.game, scale=max(1, a.scale), fullscreen=a.fullscreen, look=a.look,
               mute=a.mute, data_dir=a.data)
    pygame.quit()
    return 1 if host.error else 0


if __name__ == "__main__":
    sys.exit(main())
