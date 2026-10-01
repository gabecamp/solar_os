--[[
Wasteland Survivor - a NEO Scavenger-style hex survival game for SolarOS.

Written for the Waveshare RLCD 4.2 (400x300 landscape, 1-bit) on an
ESP32-S3. SolarOS has no polygon fill, so hexes are filled with
horizontal fill_rect bands and outlined with gfx.line.

Make a survivor, cross the Zone, stay fed, warm and unirradiated, and get
out through the Checkpoint with a Zone Permit or a bribe of artifacts.
Every key is listed in game: press H on the map or in the bag (V there
shows device info). In short: arrows/WASD move, Space rests, F searches,
I bag, C craft, E use, G hunt or fish, T trade, J journal, R radio,
M mute, Q quit.

This file is GENERATED from src/*.lua by tools/build.py; it is still a
single self-contained script, as SolarOS Playground apps are - no
require()s beyond the built-in `solaros` module.
]]

local solaros = require("solaros")
local gfx = solaros.gfx
local audio = solaros.audio

