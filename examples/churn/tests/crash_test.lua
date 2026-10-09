-- A crash mid-game leaves churn/crash.txt (the error and a traceback) and a
-- screen that says what happened, waits for a key, then still turns the
-- fast event pump off and calls gfx.end before re-raising the error.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
fake.storage.makedirs("/sd/churn")

local text, said = gfx.text, {}
gfx.text = function(x, y, s)
    said[#said + 1] = s
    return text(x, y, s)
end
local ok, err = pcall(function()
    local chunk = assert(loadfile("../churn.lua"))
    -- the sixth frame blows up (a run is under way by then)
    local real_refresh = gfx.refresh
    local frames = 0
    gfx.refresh = function()
        frames = frames + 1
        if frames == 6 then error("test crash at frame 6") end
        return real_refresh()
    end
    chunk()
end)

print("1. the error still surfaces")
assert(not ok and tostring(err):find("test crash at frame 6", 1, true), tostring(err))
print("2. crash.txt keeps the error and a traceback")
local log = FAKE_FILES["/sd/churn/crash.txt"]
assert(log and log:find("test crash at frame 6", 1, true) and log:find("traceback", 1, true), tostring(log))
print("3. the screen says so")
local all = table.concat(said, "|")
assert(all:find("The Churn crashed", 1, true), "the crash screen's title")
assert(all:find("churn/crash.txt", 1, true), "the crash screen")
print("CRASH TESTS PASSED")
