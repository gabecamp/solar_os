"""
The pygame host (python_version/churn_pygame.py) runs the real game.
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
    import churn_pygame as host_mod
except ImportError as e:
    print("SKIPPED: %s (pip install pygame lupa)" % e)
    sys.exit(0)

GAME = os.path.join(ROOT, "churn.lua")
UP, DOWN, LEFT, RIGHT = 0x80, 0x81, 0x82, 0x83


def run(keys, data, **kw):
    shots = []
    h = host_mod.run(GAME, keys=keys, data_dir=data, mute=True,
                     on_frame=lambda h: shots.append(h.canvas.copy()), **kw)
    assert h.error is None, h.error
    return h, shots


def main():
    tmp = tempfile.mkdtemp(prefix="churn_host_")
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
        assert os.path.isfile(os.path.join(tmp, "churn", "save.lua")), "saved on quit"
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

        print("8. gamepad: buttons, the D-pad and stick (with repeat), Back + Start quits")
        h = host_mod.Host(mute=True, data_dir=os.path.join(tmp, "pad"))
        E = pygame.event.Event
        btn = lambda b, up=False: h.event_key(E(pygame.JOYBUTTONUP if up else pygame.JOYBUTTONDOWN,
                                                 button=b, joy=0, instance_id=0), now=0)
        for b, want in ((0, 10), (1, 0x1B), (2, ord("e")), (3, ord("i")), (4, ord("c")), (5, ord("j"))):
            assert btn(b) == want, (b, btn(b))
            assert btn(b, up=True) is None
        assert btn(6) is None and btn(6, up=True) == ord("h"), "Back acts when let go"
        assert btn(7) is None and btn(7, up=True) == ord(" "), "Start = rest"
        assert btn(6) is None and btn(7) == ord("q"), "Back + Start = Q"
        assert btn(7, up=True) is None and btn(6, up=True) is None, "no H or Space after the chord"
        assert btn(6) is None and btn(6, up=True) == ord("h"), "and the chord is over"
        hat = lambda v, now: h.event_key(E(pygame.JOYHATMOTION, value=v, hat=0, joy=0, instance_id=0), now=now)
        assert hat((0, 1), 0) == UP and hat((1, 0), 0) == RIGHT and hat((0, -1), 0) == DOWN
        assert h._repeat_key(0.1) is None, "no repeat before the delay"
        assert h._repeat_key(host_mod.REPEAT_DELAY + 0.01) == DOWN, "held: it repeats"
        assert hat((0, 0), 1) is None and h._repeat_key(5) is None, "let go: it stops"
        axis = lambda a, v: h.event_key(E(pygame.JOYAXISMOTION, axis=a, value=v, joy=0, instance_id=0), now=0)
        assert axis(0, 0.2) is None, "inside the deadzone"
        assert axis(0, -0.9) == LEFT and axis(0, -0.95) is None, "one press per push"
        assert axis(0, 0.0) is None and axis(1, 0.8) == DOWN and axis(1, -0.8) == UP
        print("   OK")

        print("9. F1 settings: change, saved to settings.json; the game gets no keys meanwhile")
        data = os.path.join(tmp, "settings")
        h = host_mod.Host(mute=False, data_dir=data, look="gray", scale=2)
        key = lambda k, u="": h.event_key(E(pygame.KEYDOWN, key=k, unicode=u, mod=0))
        assert key(pygame.K_i, "i") == ord("i")
        assert key(pygame.K_F1) is None and h.menu == 0
        assert key(pygame.K_i, "i") is None and key(pygame.K_q, "q") is None, "the settings swallow keys"
        key(pygame.K_DOWN); key(pygame.K_DOWN)           # Look
        key(pygame.K_RIGHT)
        assert h.look == "device"
        key(pygame.K_DOWN); key(pygame.K_RETURN)         # Sound off
        assert h.sound is False
        key(pygame.K_UP); key(pygame.K_UP); key(pygame.K_UP); key(pygame.K_LEFT)   # Scale 2 -> 1
        assert h.scale == 1 and h.window.get_size() == (400, 300)
        h.present()                                      # (draws with the overlay up)
        assert key(pygame.K_ESCAPE) is None and h.menu is None
        assert key(pygame.K_i, "i") == ord("i"), "closed: keys reach the game again"
        saved = host_mod.load_settings(data)
        assert saved == {"scale": 1, "fullscreen": False, "look": "device", "sound": False}, saved
        a = type("A", (), {"scale": None, "look": None, "fullscreen": None, "mute": None})()
        o = host_mod.options_from(a, saved)
        assert o == {"scale": 1, "fullscreen": False, "look": "device", "mute": True}, o
        a.scale, a.look = 3, "amber"
        o = host_mod.options_from(a, saved)
        assert o["scale"] == 3 and o["look"] == "amber" and o["mute"], "flags win"
        assert host_mod.options_from(a, {"scale": 99, "look": "pink"})["look"] == "amber"
        assert host_mod.options_from(type(a)(), {"scale": 99, "look": "pink"}) == \
            {"scale": 2, "fullscreen": False, "look": "gray", "mute": False}, "bad values: defaults"
        assert key(pygame.K_F11) is None and h.fullscreen and host_mod.load_settings(data)["fullscreen"]
        key(pygame.K_F11)
        assert not h.fullscreen
        # a pad drives the settings too
        assert key(pygame.K_F1) is None
        assert btn(0) is None and h.scale == 2, "A changes the row (scale 1 -> 2)"
        assert btn(1) is None and h.menu is None, "B closes"
        print("   OK")

        print("10. the window's close button is a key for the game; the third in a row closes")
        h = host_mod.Host(mute=True, data_dir=os.path.join(tmp, "close"))
        quit_ev = lambda: pygame.event.post(pygame.event.Event(pygame.QUIT))
        quit_ev()
        assert h.getch(0) == host_mod.KEY_CLOSE and not h.closed
        quit_ev()
        assert h.getch(0) is None and h.close_tries == 1, "an echo before a redraw is ignored"
        h.close_at = None                  # (as after a redraw and a moment)
        pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=pygame.K_i, unicode="i", mod=0))
        assert h.getch(0) == ord("i") and h.close_tries == 0, "another key: the count starts over"
        for _ in range(host_mod.CLOSE_TRIES - 1):
            quit_ev()
            assert h.getch(0) == host_mod.KEY_CLOSE
            h.close_at = None
        quit_ev()
        assert h.getch(0) is None and h.closed, "a game that ignores it still closes"
        print("   OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\nPYGAME HOST TESTS PASSED")


if __name__ == "__main__":
    main()
