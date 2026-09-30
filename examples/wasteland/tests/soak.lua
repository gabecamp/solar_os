package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local keys = {100, 97, 119, 115, 32, 105, 13, 10, 101, 0x80, 0x81, 0x82, 0x83}
local n, seed = 0, 12345
local orig_getch = fake.gfx.getch
fake.gfx.getch = function()
    n = n + 1
    if n > 400 then return 113 end                  -- Q
    seed = (seed * 109 + 1021) % 32768
    return keys[seed % #keys + 1]
end
fake.should_exit = function() return n > 410 end
dofile("wasteland_run.lua")
print("soak finished after " .. n .. " polls without error")
