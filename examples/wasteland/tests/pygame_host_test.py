"""
The pygame host (python_version/wasteland_pygame.py) runs the real game.
Headless: SDL's dummy video and audio. Skipped (not failed) when pygame or
lupa isn't installed, so the Lua suite still runs anywhere.

    python3 tests/pygame_host_test.py
"""
import os
import re
import shutil
import sys
import tempfile

os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["SDL_AUDIODRIVER"] = "dummy"
os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "1"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "python_version"))

try:
    import pygame
    import lupa  # noqa: F401
    import wasteland_pygame as host_mod
except ImportError as e:
    print("SKIPPED: %s (pip install pygame lupa)" % e)
    sys.exit(0)

GAME = os.path.join(ROOT, "wasteland.lua")
UP, DOWN, LEFT, RIGHT = 0x80, 0x81, 0x82, 0x83


def run(keys, data, **kw):
    shots = []
    h = host_mod.run(GAME, keys=keys, data_dir=data, mute=True,
                     on_frame=lambda h: shots.append(h.canvas.copy()), **kw)
    assert h.error is None, h.error
    return h, shots


def main():
    tmp = tempfile.mkdtemp(prefix="wasteland_host_")
    try:
        print("1. every solaros call the game makes is provided by the host")
        src = open(GAME).read()
        lua = host_mod.build_runtime.__code__.co_consts
        provided = " ".join(c for c in lua if isinstance(c, str))
        for kind, names in (("gfx", re.findall(r"\bgfx\.([a-z_]+)\(", src)),
                            ("storage", re.findall(r"storage\.([a-z_]+)", src)),
                            ("audio", re.findall(r"audio\.([a-z_]+)", src))):
            for n in set(names):
                assert re.search(r'\b%s\b' % n, provided), "%s.%s missing" % (kind, n)
        print("   OK")

        print("2. bitmaps: LSB-first rows, set bits in the current color")
        h = host_mod.Host(look="gray", mute=True, data_dir=tmp)
        h.clear(host_mod.WHITE)
        h.set_color(host_mod.BLACK)
        h.sprite(10, 20, 10, 2, bytes([0b00000101, 0b10, 0xFF, 0b11]))
        black, white = host_mod.GRAY[host_mod.BLACK], host_mod.GRAY[host_mod.WHITE]
        px = lambda x, y: tuple(h.canvas.get_at((x, y)))[:3]
        assert px(10, 20) == black and px(11, 20) == white and px(12, 20) == black
        assert px(19, 20) == black and px(18, 20) == white       # bit 1 of byte 2 = x 9
        assert all(px(10 + i, 21) == black for i in range(10))
        print("   OK")

        print("3. text: the mono font advances 7 px a character (the layout assumes it)")
        adv = h.fonts[host_mod.FONT_MONO_12].size("M" * 10)[0]
        assert 65 <= adv <= 75, adv
        print("   OK")

        print("4. the device look dithers LIGHT and DARK like the firmware")
        hd = host_mod.Host(look="device", mute=True, data_dir=tmp)
        for c in (host_mod.LIGHT, host_mod.DARK):
            hd.set_color(c)
            hd.fill_rect(0, 0, 8, 8)
            out = hd._shown()
            for y in range(4):
                for x in range(4):
                    want = host_mod.BAYER4[y][x] < host_mod.THRESHOLD[c]
                    got = tuple(out.get_at((x, y)))[:3] == (255, 255, 255)
                    assert want == got, (c, x, y)
        print("   OK")

        print("5. a scripted game: creator, wake scene, a diagonal, the bag, crafting")
        h, shots = run([10, 10, 27, 10, 32, UP, RIGHT, ord("i"), ord("i"), ord("c"), ord("c")], tmp)
        assert h.frames >= 6 and len(shots) == h.frames
        assert os.path.isfile(os.path.join(tmp, "wasteland", "save.lua")), "saved on quit"
        print("   OK (%d frames)" % h.frames)

        print("6. a second start finds the save: the title offers Continue")
        h2, shots2 = run([10, 10], tmp)   # past the intro; Enter on the title = Continue
        text = []
        old = host_mod.Host.text
        host_mod.Host.text = lambda self, x, y, s: (text.append(host_mod._text(s)), old(self, x, y, s))
        try:
            run([10], tmp)   # (any key past the intro)
        finally:
            host_mod.Host.text = old
        assert any("Continue" in t for t in text), "the title screen"
        print("   OK")

        print("7. screenshots for the README")
        prev = os.path.join(ROOT, "previews")
        h, shots = run([10, 10, 27, 10, 32], os.path.join(tmp, "fresh"))
        pygame.image.save(pygame.transform.scale(shots[-1], (800, 600)),
                          os.path.join(prev, "pygame_map.png"))
        h, shots = run([10, 10, 27, 10, 32], os.path.join(tmp, "fresh2"), look="device")
        hd = host_mod.Host(look="device", mute=True, data_dir=tmp)
        hd.canvas = shots[-1]
        pygame.image.save(pygame.transform.scale(hd._shown(), (800, 600)),
                          os.path.join(prev, "pygame_map_device.png"))
        h, shots = run([10, 10, 27, 10, 32, ord("i")], os.path.join(tmp, "fresh3"), look="amber")
        ha = host_mod.Host(look="amber", mute=True, data_dir=tmp)
        ha.canvas = shots[-1]
        pygame.image.save(pygame.transform.scale(ha._shown(), (800, 600)),
                          os.path.join(prev, "pygame_bag_amber.png"))
        print("   OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\nPYGAME HOST TESTS PASSED")


if __name__ == "__main__":
    main()
