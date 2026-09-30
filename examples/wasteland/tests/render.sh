#!/usr/bin/env bash
# Render what the screens WOULD look like into ../previews/*.png (needs Pillow:
# pip install pillow). This replays the game's gfx calls into a 300x400 image;
# it does NOT reproduce the real RLCD's dithering, fonts, or refresh behaviour.
set -euo pipefail
cd "$(dirname "$0")"
python3 make_lib.py
LUA_PATH=";;" lua5.4 render_scene.lua      # writes ops_*.txt via render_stub/solaros.lua
python3 replay.py                          # ops_*.txt -> preview_*.png
mkdir -p ../previews && mv preview_*.png ../previews/ && rm -f ops_*.txt
ls ../previews
