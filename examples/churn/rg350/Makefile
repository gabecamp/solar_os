# The Churn for OpenDingux handhelds (RG350 and kin) and any SDL 1.2 system.
#
#   make                 build churn_sdl for this computer (needs libsdl1.2-dev, liblua5.4-dev)
#   make test            run the game headless for a few keys, check it drew
#   ./build_opk.sh       cross-build churn.opk for the handheld (see README.md)
#
# CC, SDL_CFLAGS, SDL_LIBS, LUA_CFLAGS and LUA_LIBS can be overridden (the
# cross build does).
CC ?= cc
SDL_CFLAGS ?= $(shell sdl-config --cflags 2>/dev/null || pkg-config --cflags sdl)
SDL_LIBS ?= $(shell sdl-config --libs 2>/dev/null || pkg-config --libs sdl)
LUA_CFLAGS ?= $(shell pkg-config --cflags lua5.4)
LUA_LIBS ?= $(shell pkg-config --libs lua5.4)
CFLAGS ?= -O2 -Wall -Wextra

churn_sdl: churn_sdl.c font_data.h
	$(CC) $(CFLAGS) $(SDL_CFLAGS) $(LUA_CFLAGS) -o $@ churn_sdl.c $(SDL_LIBS) $(LUA_LIBS) -lm

font_data.h: make_font.py
	python3 make_font.py

test: churn_sdl
	./test.sh

clean:
	rm -f churn_sdl churn.opk
