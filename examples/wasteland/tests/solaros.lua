-- Fake `solaros` module for local logic testing (NOT the real on-device API,
-- just enough surface area to drive wasteland.lua through a scripted key
-- sequence and print out resulting state so we can sanity-check it).

local M = {}
M.gfx = {}
M.audio = {}

local gfx = M.gfx

gfx.WHITE, gfx.LIGHT, gfx.DARK, gfx.BLACK = "WHITE", "LIGHT", "DARK", "BLACK"
gfx.FONT_BOLD_14, gfx.FONT_MONO_12 = "BOLD14", "MONO12"
-- real values from src/services/solar_os_keys.h (exported as gfx.KEY_*)
gfx.KEY_ESCAPE, gfx.KEY_UP, gfx.KEY_DOWN, gfx.KEY_LEFT, gfx.KEY_RIGHT = 0x1b, 0x80, 0x81, 0x82, 0x83

function gfx.begin() end
gfx["end"] = function() print("[gfx.end called]") end
function gfx.clear(c) end
function gfx.color(c) end
function gfx.font(f) end
function gfx.text(x, y, s) end
function gfx.line(x1, y1, x2, y2)
    for _, v in ipairs({x1, y1, x2, y2}) do
        assert(v == math.floor(v), 'line got a non-integer: ' .. tostring(v))
    end
end
function gfx.rect(x, y, w, h) end
function gfx.fill_rect(x, y, w, h)
    for _, v in ipairs({x, y, w, h}) do
        assert(v == math.floor(v), 'fill_rect got a non-integer: ' .. tostring(v))
    end
end
SPRITE_CALLS = {}
function gfx.sprite(x, y, w, h, data)
    for _, v in ipairs({x, y, w, h}) do
        assert(math.type(v) == 'integer', 'sprite got a non-integer arg: ' .. tostring(v))
    end
    assert(type(data) == 'string', 'sprite data must be a string')
    local need = ((w + 7) // 8) * h
    assert(#data == need, ('sprite data is %d bytes, need %d'):format(#data, need))
    assert(#data <= 128, 'sprite over 128 bytes')
    SPRITE_CALLS[#SPRITE_CALLS + 1] = {x = x, y = y, w = w, h = h, data = data}
end
gfx.bitmap = gfx.sprite
function gfx.circle(x, y, r) end
function gfx.fill_circle(x, y, r) end
function gfx.pixel(x, y) end
REFRESH_COUNT = 0
function gfx.refresh() REFRESH_COUNT = REFRESH_COUNT + 1 end
function gfx.size() return 400, 300 end

-- D=100 right, A=97 left, W=119 up, S=115 down, Space=32 rest,
-- I=105 inventory toggle, Enter=10 confirm (SolarOS sends '\n'), E=101 eat/drink,
-- Q=113 quit. nil entries are idle getch timeouts (must not trigger redraws).
local KEY_QUEUE = {
    10,                  -- start with the default build (character creator)
    100, nil, nil,       -- move right (D)
    119, nil, nil,       -- move up (W)
    32,                  -- rest (in case out of MP)
    105,                 -- open inventory
    115, 115,            -- cursor down twice (into ground items, past header logic handled by game)
    10,                  -- select a ground item stack
    115, 115, 115, 115,  -- move cursor down toward backpack section
    10,                  -- confirm transfer into backpack
    119, 119, 119, 119, 119, 119,  -- back up to the ground grid
    101,                 -- eat/drink whatever is under the cursor
    105,                 -- back to map
    113,                 -- quit
}
local idx = 0
KEYS_HANDLED = 0

function gfx.getch(timeout_ms)
    idx = idx + 1
    if KEY_QUEUE[idx] ~= nil then KEYS_HANDLED = KEYS_HANDLED + 1 end
    return KEY_QUEUE[idx]
end

local exhausted_calls = 0
function M.should_exit()
    if idx >= #KEY_QUEUE then
        exhausted_calls = exhausted_calls + 1
        return exhausted_calls > 2  -- give the quit keypress a chance to land first
    end
    return false
end

function M.audio.tone(freq, ms, vol) end

-- Game.new seeds its world from uptime. run_tests.sh sets WASTELAND_SEED (and
-- prints it) so a failure can be replayed: WASTELAND_SEED=1234 bash tests/run_tests.sh
local SEED = tonumber(os.getenv("WASTELAND_SEED") or "") or os.time()
M.time = {uptime_ms = function() return SEED end}

-- In-memory storage with the real API's shape (read_file raises on a missing
-- file, like the device). write_file is the new call from firmware/; tests set
-- M.storage.write_file = nil to play an older SolarOS that can't save.
FAKE_FILES, FAKE_DIRS = {}, {}
M.storage = {}
function M.storage.mount_point() return "/sd" end
function M.storage.exists(path) return FAKE_FILES[path] ~= nil or FAKE_DIRS[path] ~= nil end
function M.storage.makedirs(path) FAKE_DIRS[path] = true end
function M.storage.remove(path)
    if FAKE_FILES[path] == nil then error("no such file: " .. path) end
    FAKE_FILES[path] = nil
end
function M.storage.read_file(path, max)
    local data = FAKE_FILES[path]
    if data == nil then error("no such file: " .. path) end
    return data:sub(1, max or 4096)
end
function M.storage.write_file(path, data, append)
    assert(type(data) == "string", "write_file data must be a string")
    assert(#data <= 65536, "write_file over 64 KiB")
    local dir = path:match("^(.*)/[^/]+$")
    if not FAKE_DIRS[dir] then error("no such directory: " .. dir) end
    FAKE_FILES[path] = (append and FAKE_FILES[path] or "") .. data
end

return M
