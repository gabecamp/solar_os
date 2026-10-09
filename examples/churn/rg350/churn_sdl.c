/*
 * The Churn for handhelds that run OpenDingux (Anbernic RG350 and kin) and
 * anything else with SDL 1.2: it runs the real game, churn.lua, unchanged.
 *
 * The game is written for SolarOS, which gives Lua apps a `solaros` module
 * (screen, keys, storage, sound). This file provides that module from C, like
 * python_version/churn_pygame.py does for a PC: Lua 5.4 runs the game, every
 * drawing call goes to a 400x300 canvas, and the canvas is shown on the
 * screen (centered; the border carries a legend of the buttons).
 *
 *     churn_sdl [options] [churn.lua]
 *       --size WxH     video mode (default: the one the system is in)
 *       --scale N      whole-number scale of the 400x300 canvas (default: the
 *                      biggest that fits; 0 = fill the screen, uneven pixels)
 *       --no-legend    no button legend in the border
 *       --mute         no sound
 *       --pc-keys      Enter, Esc, Space as themselves (a PC keyboard)
 *       --keys TEXT    (tests) send these keys, then quit
 *       --dump FILE    (tests) save the last frame as a BMP at exit
 *       --selftest-keys  (tests) push fake button presses through the key code
 *
 * Buttons: see KEYMAP below. L and R are shift keys: hold one and the face
 * buttons and the D-pad become other keys. A PC keyboard's letters and digits
 * work as themselves.
 */
#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <SDL/SDL.h>
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#include "font_data.h"

#define W 400
#define H 300
enum { WHITE, LIGHT, DARK, BLACK };
#define KEY_ESCAPE 0x1B
#define KEY_UP 0x80
#define KEY_DOWN 0x81
#define KEY_LEFT 0x82
#define KEY_RIGHT 0x83
#define KEY_CLOSE 0xF0

/* ---- the buttons ------------------------------------------------------- */

/* The handheld's buttons as SDL 1.2 sees them on OpenDingux: A = Left Ctrl,
 * B = Left Alt, X = Left Shift, Y = Space, L = Tab, R = Backspace,
 * Start = Return, Select = Escape. */
enum { B_A, B_B, B_X, B_Y, B_START, B_SELECT, B_UP, B_DOWN, B_LEFT, B_RIGHT, B_COUNT };
static const SDLKey BUTTON_KEY[B_COUNT] = {
    SDLK_LCTRL, SDLK_LALT, SDLK_LSHIFT, SDLK_SPACE, SDLK_RETURN, SDLK_ESCAPE,
    SDLK_UP, SDLK_DOWN, SDLK_LEFT, SDLK_RIGHT,
};
#define SHIFT_L_KEY SDLK_TAB
#define SHIFT_R_KEY SDLK_BACKSPACE

/* What each button sends: layer 0 = nothing held, 1 = L, 2 = R, 3 = L and R.
 * 0 = nothing. These are the game's own keys (the Lua checks lower case). */
static const unsigned char KEYMAP[4][B_COUNT] = {
    /*          A     B     X     Y     Start Sel   Up        Down      Left      Right */
    /* none */ {10,   27,  'e',  ' ',  'i',  'h',  KEY_UP,   KEY_DOWN, KEY_LEFT, KEY_RIGHT},
    /* L    */ {'f',  'c', 't',  'g',  'j',  'p',  KEY_UP,   KEY_DOWN, 'r',      'm'},
    /* R    */ {'x',  'q', 'o',  'n',  'v',  'l',  '1',      '3',      '4',      '2'},
    /* L+R  */ {'b',  'k', 'y',  'u',  'r',  0,    KEY_UP,   KEY_DOWN, KEY_LEFT, KEY_RIGHT},
};
/* The legend shown in the border: one line per layer. */
static const char *LEGEND[4] = {
    "A Enter  B Back  X Use  Y Rest  Start Bag  Select Help",
    "L+  A Search  B Craft  X Trade  Y Hunt  St Journal  Sel You  Lt Radio  Rt Mute",
    "R+  A Drop  B Quit  X Work  Y Notes  St Info  Sel Lore  D-pad 1 2 3 4",
    "L+R  A Bestiary  B Skills  X Yes  Y -  Start Records",
};

/* ---- state ------------------------------------------------------------- */

static uint8_t canvas[H][W];            /* 0..3: WHITE, LIGHT, DARK, BLACK */
static const uint8_t GRAY[4] = {255, 190, 105, 0};
static int cur_color = BLACK, cur_font = 0;
static SDL_Surface *screen;
static int scale = -1, show_legend = 1, pc_keys = 0, muted = 0;
static int dest_x, dest_y, dest_w, dest_h;
static int closed = 0, close_tries = 0, frames = 0;
static int layer_l = 0, layer_r = 0;
static const char *script = NULL;       /* --keys */
static const char *dump_file = NULL;
static char data_dir[1024];
static Uint32 close_at = 0;

/* ---- drawing ----------------------------------------------------------- */

static void put(int x, int y)
{
    if (x >= 0 && x < W && y >= 0 && y < H) canvas[y][x] = (uint8_t)cur_color;
}

static void hline(int x0, int x1, int y)
{
    if (y < 0 || y >= H) return;
    if (x0 > x1) { int t = x0; x0 = x1; x1 = t; }
    if (x0 < 0) x0 = 0;
    if (x1 >= W) x1 = W - 1;
    if (x0 <= x1) memset(&canvas[y][x0], cur_color, (size_t)(x1 - x0 + 1));
}

static void g_line(int x0, int y0, int x1, int y1)
{
    int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    for (;;) {
        put(x0, y0);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}

static void g_fill_rect(int x, int y, int w, int h)
{
    for (int j = 0; j < h; j++) hline(x, x + w - 1, y + j);
}

static void g_rect(int x, int y, int w, int h)
{
    if (w <= 0 || h <= 0) return;
    hline(x, x + w - 1, y);
    hline(x, x + w - 1, y + h - 1);
    for (int j = 1; j < h - 1; j++) { put(x, y + j); put(x + w - 1, y + j); }
}

static void g_circle(int cx, int cy, int r, int fill)
{
    int x = r, y = 0, err = 1 - r;
    while (x >= y) {
        if (fill) {
            hline(cx - x, cx + x, cy + y); hline(cx - x, cx + x, cy - y);
            hline(cx - y, cx + y, cy + x); hline(cx - y, cx + y, cy - x);
        } else {
            put(cx + x, cy + y); put(cx - x, cy + y); put(cx + x, cy - y); put(cx - x, cy - y);
            put(cx + y, cy + x); put(cx - y, cy + x); put(cx + y, cy - x); put(cx - y, cy - x);
        }
        y++;
        if (err < 0) err += 2 * y + 1;
        else { x--; err += 2 * (y - x) + 1; }
    }
}

static void font_metrics(int id, int *w, int *h, int *ascent)
{
    if (id == 1) { *w = FONT_bold14_W; *h = FONT_bold14_H; *ascent = FONT_bold14_ASCENT; }
    else { *w = FONT_mono12_W; *h = FONT_mono12_H; *ascent = FONT_mono12_ASCENT; }
}

static const unsigned short *glyph(int id, unsigned char c)
{
    if (c < 32 || c > 126) c = '?';
    return id == 1 ? FONT_bold14[c - 32] : FONT_mono12[c - 32];
}

/* y is the baseline, as in the SolarOS gfx.text */
static void g_text(int x, int y, const char *s, size_t len)
{
    int fw, fh, asc;
    font_metrics(cur_font, &fw, &fh, &asc);
    for (size_t i = 0; i < len; i++, x += fw) {
        const unsigned short *g = glyph(cur_font, (unsigned char)s[i]);
        for (int row = 0; row < fh; row++) {
            unsigned bits = g[row];
            for (int col = 0; bits; col++, bits >>= 1)
                if (bits & 1) put(x + col, y - asc + row);
        }
    }
}

/* 1-bit rows, (w+7)/8 bytes each, least significant bit first; set bits are
 * drawn in the current color, clear bits leave the canvas alone. */
static void g_sprite(int x, int y, int w, int h, const unsigned char *data, size_t len)
{
    int bpr = (w + 7) / 8;
    for (int row = 0; row < h; row++)
        for (int col = 0; col < w; col++) {
            size_t i = (size_t)row * bpr + col / 8;
            if (i < len && ((data[i] >> (col % 8)) & 1)) put(x + col, y + row);
        }
}

/* ---- the screen -------------------------------------------------------- */

static Uint32 pal[4];
static Uint32 px_white, px_black, px_dim, px_border;

static void px_set(int x, int y, Uint32 v)
{
    if (x < 0 || y < 0 || x >= screen->w || y >= screen->h) return;
    Uint8 *p = (Uint8 *)screen->pixels + y * screen->pitch + x * screen->format->BytesPerPixel;
    if (screen->format->BytesPerPixel == 2) *(Uint16 *)p = (Uint16)v;
    else *(Uint32 *)p = v;
}

static void screen_text(int x, int y, const char *s, int font, Uint32 v)
{
    int fw, fh, asc;
    font_metrics(font, &fw, &fh, &asc);
    for (; *s; s++, x += fw) {
        const unsigned short *g = glyph(font, (unsigned char)*s);
        for (int row = 0; row < fh; row++) {
            unsigned bits = g[row];
            for (int col = 0; bits; col++, bits >>= 1)
                if (bits & 1) px_set(x + col, y - asc + row, v);
        }
    }
}

static void layout(void)
{
    int sw = screen->w, sh = screen->h, k = scale;
    if (k < 0) {   /* the biggest whole scale that fits (or a fit, when smaller than the canvas) */
        k = sw / W < sh / H ? sw / W : sh / H;
        if (k < 1) k = 0;
    }
    if (k == 0) {   /* fill, keeping the shape */
        if (sw * H <= sh * W) { dest_w = sw; dest_h = sw * H / W; }
        else { dest_h = sh; dest_w = sh * W / H; }
    } else {
        dest_w = W * k;
        dest_h = H * k;
    }
    dest_x = (sw - dest_w) / 2;
    dest_y = (sh - dest_h) / 2;
}

static void present(void)
{
    int bpp = screen->format->BytesPerPixel;
    if (SDL_MUSTLOCK(screen)) SDL_LockSurface(screen);
    SDL_FillRect(screen, NULL, px_border);
    /* the canvas, nearest-neighbour into dest */
    static int *xmap = NULL;
    static int xmap_n = 0;
    if (xmap_n != dest_w) {
        free(xmap);
        xmap = (int *)malloc(sizeof(int) * (size_t)dest_w);
        for (int i = 0; i < dest_w; i++) xmap[i] = i * W / dest_w;
        xmap_n = dest_w;
    }
    for (int dy = 0; dy < dest_h; dy++) {
        const uint8_t *src = canvas[dy * H / dest_h];
        Uint8 *row = (Uint8 *)screen->pixels + (dest_y + dy) * screen->pitch + dest_x * bpp;
        if (bpp == 2) {
            Uint16 *d = (Uint16 *)row;
            for (int dx = 0; dx < dest_w; dx++) d[dx] = (Uint16)pal[src[xmap[dx]]];
        } else {
            Uint32 *d = (Uint32 *)row;
            for (int dx = 0; dx < dest_w; dx++) d[dx] = pal[src[xmap[dx]]];
        }
    }
    /* a thin frame, so the picture's black title bars don't melt into the border */
    for (int i = -1; i <= dest_w; i++) { px_set(dest_x + i, dest_y - 1, px_dim); px_set(dest_x + i, dest_y + dest_h, px_dim); }
    for (int j = -1; j <= dest_h; j++) { px_set(dest_x - 1, dest_y + j, px_dim); px_set(dest_x + dest_w, dest_y + j, px_dim); }
    /* the legend, in whatever border is left under the picture */
    int fw, fh, asc;
    font_metrics(0, &fw, &fh, &asc);
    int ly = dest_y + dest_h + 6 + asc;
    int cols = screen->w / fw;
    if (show_legend && ly + 3 * (fh + 1) + fh < screen->h) {
        int active = (layer_l ? 1 : 0) | (layer_r ? 2 : 0);
        for (int i = 0; i < 4; i++) {
            char line[200];
            snprintf(line, sizeof line, "%.*s", cols < 199 ? cols : 199, LEGEND[i]);
            screen_text(2, ly + i * (fh + 1), line, 0, i == active ? px_white : px_dim);
        }
    }
    if (SDL_MUSTLOCK(screen)) SDL_UnlockSurface(screen);
    (void)bpp;
    SDL_Flip(screen);
}

static int open_screen(int want_w, int want_h)
{
    int bits = 16;
    screen = SDL_SetVideoMode(want_w, want_h, bits, SDL_SWSURFACE);
    if (!screen) screen = SDL_SetVideoMode(640, 480, bits, SDL_SWSURFACE);
    if (!screen) return 0;
    for (int i = 0; i < 4; i++) pal[i] = SDL_MapRGB(screen->format, GRAY[i], GRAY[i], GRAY[i]);
    px_white = SDL_MapRGB(screen->format, 235, 235, 235);
    px_black = SDL_MapRGB(screen->format, 0, 0, 0);
    px_dim = SDL_MapRGB(screen->format, 110, 110, 110);
    px_border = SDL_MapRGB(screen->format, 24, 24, 24);
    layout();
    return 1;
}

/* ---- sound ------------------------------------------------------------- */

#define RATE 22050
typedef struct { int freq, ms, vol; } Note;
static Note notes[64];
static int note_head = 0, note_n = 0, audio_ok = 0;
static int cur_left = 0, cur_half = 1, cur_amp = 0, cur_phase = 0, cur_sign = 1;

static void audio_cb(void *ud, Uint8 *stream, int len)
{
    Sint16 *out = (Sint16 *)stream;
    (void)ud;
    for (int i = 0; i < len / 2; i++) {
        if (cur_left <= 0 && note_n > 0) {
            Note n = notes[note_head];
            note_head = (note_head + 1) % 64;
            note_n--;
            cur_left = RATE * n.ms / 1000;
            if (cur_left < 1) cur_left = 1;
            cur_amp = n.freq <= 0 ? 0 : 9000 * (n.vol < 0 ? 0 : n.vol > 100 ? 100 : n.vol) / 100;
            cur_half = n.freq <= 0 ? 1 : RATE / n.freq / 2;
            if (cur_half < 1) cur_half = 1;
            cur_phase = 0;
            cur_sign = 1;
        }
        if (cur_left > 0) {
            out[i] = (Sint16)(cur_sign * cur_amp);
            if (++cur_phase >= cur_half) { cur_phase = 0; cur_sign = -cur_sign; }
            cur_left--;
        } else {
            out[i] = 0;
        }
    }
}

static void audio_open(void)
{
    SDL_AudioSpec want;
    memset(&want, 0, sizeof want);
    want.freq = RATE; want.format = AUDIO_S16SYS; want.channels = 1; want.samples = 1024;
    want.callback = audio_cb;
    if (SDL_OpenAudio(&want, NULL) == 0) { audio_ok = 1; SDL_PauseAudio(0); }
}

static void note_add(int freq, int ms, int vol)
{
    if (!audio_ok || muted) return;
    SDL_LockAudio();
    if (note_n < 64) { notes[(note_head + note_n) % 64] = (Note){freq, ms, vol}; note_n++; }
    SDL_UnlockAudio();
}

/* ---- keys -------------------------------------------------------------- */

static int held_key = 0;          /* a held D-pad direction (for repeat) */
static SDLKey held_sdl = SDLK_UNKNOWN;
static Uint32 held_next = 0;
#define REPEAT_DELAY 300
#define REPEAT_EVERY 150

static int button_of(SDLKey k)
{
    for (int b = 0; b < B_COUNT; b++) if (BUTTON_KEY[b] == k) return b;
    return -1;
}

/* One SDL key press as the game's key (0 = none, or a shift key). */
static int game_key(SDLKey sym, int *is_dir)
{
    *is_dir = 0;
    if (pc_keys) {
        if (sym == SDLK_RETURN || sym == SDLK_KP_ENTER) return 10;
        if (sym == SDLK_ESCAPE) return KEY_ESCAPE;
        if (sym == SDLK_SPACE) return ' ';
    }
    int b = button_of(sym);
    if (b >= 0) {
        int layer = (layer_l ? 1 : 0) | (layer_r ? 2 : 0);
        int k = KEYMAP[layer][b];
        *is_dir = b >= B_UP && k >= KEY_UP && k <= KEY_RIGHT;
        return k;
    }
    if (sym >= 'a' && sym <= 'z') return sym;       /* a keyboard */
    if (sym >= '0' && sym <= '9') return sym;
    if (sym == SDLK_BACKSPACE) return 8;
    if (sym == SDLK_TAB) return 9;
    return 0;
}

static Uint32 now_ms(void) { return SDL_GetTicks(); }

static int poll_key(void)
{
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
        if (ev.type == SDL_QUIT) {
            Uint32 t = now_ms();
            if (close_at && t - close_at < 250) continue;   /* an echo */
            close_at = t;
            if (++close_tries >= 3) { closed = 1; return -1; }
            return KEY_CLOSE;
        }
        if (ev.type == SDL_KEYDOWN) {
            SDLKey s = ev.key.keysym.sym;
            if (s == SHIFT_L_KEY) { layer_l = 1; held_key = 0; continue; }
            if (s == SHIFT_R_KEY) { layer_r = 1; held_key = 0; continue; }
            int dir, k = game_key(s, &dir);
            if (k) {
                close_tries = 0;
                if (dir) { held_key = k; held_sdl = s; held_next = now_ms() + REPEAT_DELAY; }
                return k;
            }
        } else if (ev.type == SDL_KEYUP) {
            SDLKey s = ev.key.keysym.sym;
            if (s == SHIFT_L_KEY) { layer_l = 0; held_key = 0; }
            else if (s == SHIFT_R_KEY) { layer_r = 0; held_key = 0; }
            else if (s == held_sdl) held_key = 0;
        }
    }
    if (held_key && now_ms() >= held_next) {
        held_next = now_ms() + REPEAT_EVERY;
        return held_key;
    }
    return 0;
}

/* (test) button presses as SDL sends them, and what the game should see */
static void press(SDLKey k, int down)
{
    SDL_Event ev;
    memset(&ev, 0, sizeof ev);
    ev.type = down ? SDL_KEYDOWN : SDL_KEYUP;
    ev.key.keysym.sym = k;
    SDL_PushEvent(&ev);
}

static int selftest_keys(void)
{
    struct { SDLKey shift, shift2, button; int want; } cases[] = {
        {0, 0, SDLK_LCTRL, 10},                        /* A: Enter */
        {0, 0, SDLK_LALT, 27},                         /* B: Esc */
        {0, 0, SDLK_LSHIFT, 'e'},                      /* X: use */
        {0, 0, SDLK_RETURN, 'i'},                      /* Start: bag */
        {0, 0, SDLK_UP, KEY_UP},
        {SHIFT_L_KEY, 0, SDLK_LCTRL, 'f'},             /* L + A: search */
        {SHIFT_L_KEY, 0, SDLK_LALT, 'c'},              /* L + B: craft */
        {SHIFT_L_KEY, 0, SDLK_LEFT, 'r'},              /* L + left: radio */
        {SHIFT_R_KEY, 0, SDLK_LALT, 'q'},              /* R + B: quit */
        {SHIFT_R_KEY, 0, SDLK_UP, '1'},                /* R + up: sigil 1 */
        {SHIFT_R_KEY, 0, SDLK_LEFT, '4'},
        {SHIFT_L_KEY, SHIFT_R_KEY, SDLK_LCTRL, 'b'},   /* L + R + A: bestiary */
        {0, 0, SDLK_g, 'g'},                           /* a keyboard's letters */
    };
    int bad = 0;
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        layer_l = layer_r = held_key = 0;
        if (cases[i].shift) press(cases[i].shift, 1);
        if (cases[i].shift2) press(cases[i].shift2, 1);
        press(cases[i].button, 1);
        int got = 0, tries = 0;
        while (!(got = poll_key()) && tries++ < 5) SDL_Delay(1);
        if (got != cases[i].want) { printf("case %u: wanted %d, got %d\n", i, cases[i].want, got); bad++; }
        press(cases[i].button, 0);
        if (cases[i].shift) press(cases[i].shift, 0);
        if (cases[i].shift2) press(cases[i].shift2, 0);
        poll_key();
        if (layer_l || layer_r) { printf("case %u: a shift key stuck\n", i); bad++; }
    }
    /* a held direction repeats; letting go stops it */
    layer_l = layer_r = 0;
    press(SDLK_RIGHT, 1);
    int first = poll_key();
    SDL_Delay(REPEAT_DELAY + 20);
    int again = poll_key();
    press(SDLK_RIGHT, 0);
    poll_key();
    SDL_Delay(REPEAT_EVERY + 20);
    int after = poll_key();
    if (first != KEY_RIGHT || again != KEY_RIGHT || after != 0) { printf("repeat: %d %d %d\n", first, again, after); bad++; }
    printf(bad ? "KEY TEST FAILED\n" : "key layers ok\n");
    return bad ? 1 : 0;
}

/* ---- the data folder --------------------------------------------------- */

static int safe_path(const char *p, char *out, size_t n)
{
    while (*p == '/') p++;
    if (strstr(p, "..")) return 0;
    snprintf(out, n, "%s/%s", data_dir, p);
    return 1;
}

static void mkdirs(char *path)
{
    for (char *c = path + 1; *c; c++)
        if (*c == '/') { *c = 0; mkdir(path, 0777); *c = '/'; }
    mkdir(path, 0777);
}

/* ---- Lua bindings ------------------------------------------------------ */

static int L_clear(lua_State *L)
{
    int c = (int)luaL_optinteger(L, 1, WHITE);
    memset(canvas, c >= 0 && c <= 3 ? c : WHITE, sizeof canvas);
    return 0;
}
static int L_color(lua_State *L) { int c = (int)luaL_checkinteger(L, 1); cur_color = c >= 0 && c <= 3 ? c : BLACK; return 0; }
static int L_font(lua_State *L) { int f = (int)luaL_checkinteger(L, 1); cur_font = f == 1 ? 1 : 0; return 0; }
static int L_text(lua_State *L)
{
    size_t n;
    int x = (int)luaL_checknumber(L, 1), y = (int)luaL_checknumber(L, 2);
    const char *s = luaL_tolstring(L, 3, &n);
    g_text(x, y, s, n);
    return 0;
}
static int L_line(lua_State *L)
{
    g_line((int)luaL_checknumber(L, 1), (int)luaL_checknumber(L, 2), (int)luaL_checknumber(L, 3), (int)luaL_checknumber(L, 4));
    return 0;
}
static int L_rect(lua_State *L)
{
    g_rect((int)luaL_checknumber(L, 1), (int)luaL_checknumber(L, 2), (int)luaL_checknumber(L, 3), (int)luaL_checknumber(L, 4));
    return 0;
}
static int L_fill_rect(lua_State *L)
{
    g_fill_rect((int)luaL_checknumber(L, 1), (int)luaL_checknumber(L, 2), (int)luaL_checknumber(L, 3), (int)luaL_checknumber(L, 4));
    return 0;
}
static int L_circle(lua_State *L)
{
    g_circle((int)luaL_checknumber(L, 1), (int)luaL_checknumber(L, 2), (int)luaL_checknumber(L, 3), 0);
    return 0;
}
static int L_fill_circle(lua_State *L)
{
    g_circle((int)luaL_checknumber(L, 1), (int)luaL_checknumber(L, 2), (int)luaL_checknumber(L, 3), 1);
    return 0;
}
static int L_pixel(lua_State *L) { put((int)luaL_checknumber(L, 1), (int)luaL_checknumber(L, 2)); return 0; }
static int L_sprite(lua_State *L)
{
    size_t len;
    int x = (int)luaL_checknumber(L, 1), y = (int)luaL_checknumber(L, 2);
    int w = (int)luaL_checkinteger(L, 3), h = (int)luaL_checkinteger(L, 4);
    const char *d = luaL_checklstring(L, 5, &len);
    g_sprite(x, y, w, h, (const unsigned char *)d, len);
    return 0;
}
static int L_refresh(lua_State *L) { (void)L; frames++; present(); return 0; }
static int L_size(lua_State *L) { lua_pushinteger(L, W); lua_pushinteger(L, H); return 2; }
static int L_nop(lua_State *L) { (void)L; return 0; }

static int L_getch(lua_State *L)
{
    if (script) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) if (ev.type == SDL_QUIT) closed = 1;
        if (*script) { lua_pushinteger(L, (unsigned char)*script++); return 1; }
        if (dump_file && !closed) { SDL_SaveBMP(screen, dump_file); dump_file = NULL; }   /* (the frame before the quit) */
        closed = 1;
        lua_pushinteger(L, 'q');
        return 1;
    }
    Uint32 deadline = lua_isnoneornil(L, 1) ? 0 : now_ms() + (Uint32)luaL_checkinteger(L, 1);
    int forever = lua_isnoneornil(L, 1);
    for (;;) {
        int k = poll_key();
        if (k > 0) { lua_pushinteger(L, k); return 1; }
        if (closed || (!forever && now_ms() >= deadline)) { lua_pushnil(L); return 1; }
        SDL_Delay(5);
    }
}
static int L_should_exit(lua_State *L) { lua_pushboolean(L, closed); return 1; }

static int L_tone(lua_State *L)
{
    int ms = (int)luaL_checkinteger(L, 2);
    note_add((int)luaL_checkinteger(L, 1), ms, (int)luaL_optinteger(L, 3, 60));
    if (audio_ok && !muted) SDL_Delay((Uint32)ms);
    lua_pushboolean(L, 1);
    return 1;
}
static int L_tone_async(lua_State *L)
{
    note_add((int)luaL_checkinteger(L, 1), (int)luaL_checkinteger(L, 2), (int)luaL_optinteger(L, 3, 60));
    lua_pushboolean(L, 1);
    return 1;
}

static int L_mount_point(lua_State *L) { mkdirs(data_dir); lua_pushstring(L, "/"); return 1; }
static int L_exists(lua_State *L)
{
    char p[1400];
    struct stat st;
    lua_pushboolean(L, safe_path(luaL_checkstring(L, 1), p, sizeof p) && stat(p, &st) == 0);
    return 1;
}
static int L_makedirs(lua_State *L)
{
    char p[1400];
    if (!safe_path(luaL_checkstring(L, 1), p, sizeof p)) return luaL_error(L, "path outside the data folder");
    mkdirs(p);
    lua_pushboolean(L, 1);
    return 1;
}
static int L_read_file(lua_State *L)
{
    char p[1400];
    if (!safe_path(luaL_checkstring(L, 1), p, sizeof p)) return luaL_error(L, "path outside the data folder");
    long max = (long)luaL_optinteger(L, 2, 0);
    FILE *f = fopen(p, "rb");
    if (!f) { lua_pushnil(L); lua_pushstring(L, "not found"); return 2; }
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    char chunk[4096];
    long got = 0;
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) {
        if (max > 0 && got + (long)n > max) n = (size_t)(max - got);
        luaL_addlstring(&b, chunk, n);
        got += (long)n;
        if (max > 0 && got >= max) break;
    }
    fclose(f);
    luaL_pushresult(&b);
    return 1;
}
static int L_write_file(lua_State *L)
{
    char p[1400];
    size_t len;
    if (!safe_path(luaL_checkstring(L, 1), p, sizeof p)) return luaL_error(L, "path outside the data folder");
    const char *d = luaL_checklstring(L, 2, &len);
    int append = lua_toboolean(L, 3);
    char dir[1400];
    snprintf(dir, sizeof dir, "%s", p);
    char *slash = strrchr(dir, '/');
    if (slash) { *slash = 0; mkdirs(dir); }
    FILE *f = fopen(p, append ? "ab" : "wb");
    if (!f) return luaL_error(L, "can't write %s: %s", p, strerror(errno));
    if (fwrite(d, 1, len, f) != len) { fclose(f); return luaL_error(L, "write failed: %s", strerror(errno)); }
    if (fclose(f) != 0) return luaL_error(L, "write failed: %s", strerror(errno));
    lua_pushboolean(L, 1);
    return 1;
}
static int L_remove(lua_State *L)
{
    char p[1400];
    if (safe_path(luaL_checkstring(L, 1), p, sizeof p)) remove(p);
    lua_pushboolean(L, 1);
    return 1;
}
static int L_rename(lua_State *L)
{
    char a[1400], b[1400];
    if (!safe_path(luaL_checkstring(L, 1), a, sizeof a) || !safe_path(luaL_checkstring(L, 2), b, sizeof b))
        return luaL_error(L, "path outside the data folder");
    if (rename(a, b) != 0) return luaL_error(L, "can't rename: %s", strerror(errno));
    lua_pushboolean(L, 1);
    return 1;
}
static int L_stat(lua_State *L)
{
    char p[1400];
    struct stat st;
    if (!safe_path(luaL_checkstring(L, 1), p, sizeof p) || stat(p, &st) != 0) { lua_pushnil(L); return 1; }
    lua_newtable(L);
    lua_pushinteger(L, (lua_Integer)st.st_size);
    lua_setfield(L, -2, "size");
    return 1;
}
static int L_uptime_ms(lua_State *L) { lua_pushinteger(L, (lua_Integer)(now_ms() & 0x7fffffff)); return 1; }
static int L_tick_interval(lua_State *L) { (void)L; lua_pushinteger(L, 25); return 1; }

static void reg(lua_State *L, const char *name, lua_CFunction f)
{
    lua_pushcfunction(L, f);
    lua_setfield(L, -2, name);
}
static void set_int(lua_State *L, const char *name, lua_Integer v)
{
    lua_pushinteger(L, v);
    lua_setfield(L, -2, name);
}

/* the `solaros` module, left on the stack */
static int open_solaros(lua_State *L)
{
    lua_newtable(L);                         /* M */
    lua_newtable(L);                         /* gfx */
    set_int(L, "WHITE", WHITE); set_int(L, "LIGHT", LIGHT); set_int(L, "DARK", DARK); set_int(L, "BLACK", BLACK);
    set_int(L, "FONT_MONO_12", 0); set_int(L, "FONT_BOLD_14", 1);
    set_int(L, "KEY_ESCAPE", KEY_ESCAPE); set_int(L, "KEY_UP", KEY_UP); set_int(L, "KEY_DOWN", KEY_DOWN);
    set_int(L, "KEY_LEFT", KEY_LEFT); set_int(L, "KEY_RIGHT", KEY_RIGHT);
    reg(L, "clear", L_clear); reg(L, "color", L_color); reg(L, "font", L_font); reg(L, "text", L_text);
    reg(L, "line", L_line); reg(L, "rect", L_rect); reg(L, "fill_rect", L_fill_rect);
    reg(L, "circle", L_circle); reg(L, "fill_circle", L_fill_circle); reg(L, "pixel", L_pixel);
    reg(L, "sprite", L_sprite); reg(L, "bitmap", L_sprite); reg(L, "refresh", L_refresh);
    reg(L, "size", L_size); reg(L, "getch", L_getch);
    reg(L, "begin", L_nop); reg(L, "end", L_refresh);
    lua_setfield(L, -2, "gfx");
    lua_newtable(L);
    reg(L, "tone", L_tone); reg(L, "tone_async", L_tone_async);
    lua_setfield(L, -2, "audio");
    lua_newtable(L);
    reg(L, "mount_point", L_mount_point); reg(L, "exists", L_exists); reg(L, "makedirs", L_makedirs);
    reg(L, "read_file", L_read_file); reg(L, "write_file", L_write_file); reg(L, "remove", L_remove);
    reg(L, "rename", L_rename); reg(L, "stat", L_stat);
    lua_setfield(L, -2, "storage");
    lua_newtable(L);
    reg(L, "uptime_ms", L_uptime_ms);
    lua_setfield(L, -2, "time");
    reg(L, "tick_interval", L_tick_interval);
    reg(L, "should_exit", L_should_exit);
    return 1;
}

/* ---- running the game -------------------------------------------------- */

static int traceback(lua_State *L)
{
    luaL_traceback(L, L, lua_tostring(L, 1), 1);
    return 1;
}

static void show_error(const char *msg)
{
    fprintf(stderr, "%s\n", msg);
    memset(canvas, WHITE, sizeof canvas);
    cur_color = BLACK; cur_font = 0;
    g_text(6, 16, "The game stopped with an error:", 31);
    int y = 32;
    const char *p = msg;
    while (*p && y < H - 24) {
        const char *nl = strchr(p, '\n');
        size_t n = nl ? (size_t)(nl - p) : strlen(p);
        while (n > 0 && y < H - 24) {
            size_t k = n > 55 ? 55 : n;
            g_text(6, y, p, k);
            p += k; n -= k; y += 14;
        }
        if (nl) p = nl + 1; else break;
    }
    g_text(6, H - 8, "Any key closes the game.", 24);
    present();
    if (!script) for (;;) { if (poll_key() > 0 || closed) break; SDL_Delay(20); }
}

int main(int argc, char **argv)
{
    int want_w = 0, want_h = 0;
    const char *game = NULL;
    int selftest = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--size") && i + 1 < argc) sscanf(argv[++i], "%dx%d", &want_w, &want_h);
        else if (!strcmp(argv[i], "--scale") && i + 1 < argc) scale = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--no-legend")) show_legend = 0;
        else if (!strcmp(argv[i], "--mute")) muted = 1;
        else if (!strcmp(argv[i], "--pc-keys")) pc_keys = 1;
        else if (!strcmp(argv[i], "--keys") && i + 1 < argc) script = argv[++i];
        else if (!strcmp(argv[i], "--dump") && i + 1 < argc) dump_file = argv[++i];
        else if (!strcmp(argv[i], "--selftest-keys")) selftest = 1;
        else if (argv[i][0] != '-') game = argv[i];
        else { fprintf(stderr, "unknown option %s (see the top of churn_sdl.c)\n", argv[i]); return 2; }
    }
    /* where things live: the game next to the program, saves in the home folder */
    char dir[1024] = ".";
    if (argc > 0 && strchr(argv[0], '/')) {
        snprintf(dir, sizeof dir, "%s", argv[0]);
        *strrchr(dir, '/') = 0;
    }
    char game_path[1100];
    if (game) snprintf(game_path, sizeof game_path, "%s", game);
    else if (access("churn.lua", R_OK) == 0) snprintf(game_path, sizeof game_path, "churn.lua");
    else snprintf(game_path, sizeof game_path, "%s/churn.lua", dir);
    const char *env = getenv("CHURN_DATA"), *home = getenv("HOME");
    if (env && *env) snprintf(data_dir, sizeof data_dir, "%s", env);
    else if (home && *home) snprintf(data_dir, sizeof data_dir, "%s/.the-churn", home);
    else snprintf(data_dir, sizeof data_dir, "%s/churn_data", dir);

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER) < 0 &&
        SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) < 0) {
        fprintf(stderr, "SDL: %s\n", SDL_GetError());
        return 1;
    }
    SDL_ShowCursor(SDL_DISABLE);
    if (!open_screen(want_w, want_h)) { fprintf(stderr, "no screen: %s\n", SDL_GetError()); return 1; }
    SDL_WM_SetCaption("The Churn", "The Churn");
    audio_open();
    memset(canvas, WHITE, sizeof canvas);
    if (selftest) { int r = selftest_keys(); SDL_Quit(); return r; }

    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    luaL_requiref(L, "solaros", open_solaros, 0);
    lua_pop(L, 1);
    int ok = 0;
    lua_pushcfunction(L, traceback);
    if (luaL_loadfile(L, game_path) != LUA_OK) {
        show_error(lua_tostring(L, -1));
    } else if (lua_pcall(L, 0, 0, -2) != LUA_OK) {
        show_error(lua_tostring(L, -1));
    } else {
        ok = 1;
    }
    if (dump_file) SDL_SaveBMP(screen, dump_file);
    lua_close(L);
    SDL_CloseAudio();
    SDL_Quit();
    return ok ? 0 : 1;
}
