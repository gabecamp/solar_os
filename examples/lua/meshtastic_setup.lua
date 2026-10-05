-- Meshtastic setup for SolarTerm with an RFM95W on the runtime-safe pins.
--
-- Wiring: SCK=GPIO1, MOSI=GPIO2, MISO=GPIO3, CS=GPIO17; RESET and DIO0 are
-- not connected. Creates the SPI bus, attaches the radio, and starts the
-- meshtastic job. Running it again skips steps that are already done.
-- Edit the settings below, then run: lua /path/to/meshtastic_setup.lua

local solaros = require("solaros")

local BUS = "spi1"
local RADIO = "radio0"
local PINS = {sclk = 1, mosi = 2, miso = 3, cs = 17}

local REGION = "US"          -- US, EU_868, EU_433, ANZ, or a frequency in Hz
local PRESET = "LongFast"
local CHANNEL = nil          -- nil uses the preset name, like a stock node
local KEY = "default"        -- default, none, index:N, or 32/64 hex digits
local LONG_NAME = nil        -- e.g. "Gabe's SolarTerm"; nil uses SolarTerm XXXX
local SHORT_NAME = nil       -- up to 4 bytes; nil uses the node ID digits

local function exists(lookup, name)
    return (pcall(lookup, name))
end

local function has_device(name)
    for _, device in ipairs(solaros.expansion.devices()) do
        if device.name == name then
            return true
        end
    end
    return false
end

if exists(solaros.buses.get, BUS) then
    print("bus " .. BUS .. ": already present")
else
    solaros.buses.create_spi(BUS, {
        host = solaros.buses.SPI3_HOST,
        sclk = PINS.sclk,
        mosi = PINS.mosi,
        miso = PINS.miso,
        cs = {PINS.cs},
    })
    print("bus " .. BUS .. ": created")
end

if has_device(RADIO) then
    print("radio " .. RADIO .. ": already attached")
else
    solaros.expansion.attach("rfm95", RADIO, {spi = BUS, cs = PINS.cs})
    print("radio " .. RADIO .. ": attached")
end

local status = solaros.jobs.status("meshtastic")
if status.state == "running" then
    print("meshtastic: already running")
else
    -- Optional positional arguments must be filled in order.
    local args = {RADIO, REGION, PRESET, CHANNEL or PRESET, KEY}
    if LONG_NAME then
        args[#args + 1] = "name=" .. LONG_NAME
    end
    if SHORT_NAME then
        args[#args + 1] = "short=" .. SHORT_NAME
    end
    solaros.jobs.start("meshtastic", args)
    print("meshtastic: started on " .. RADIO .. " (" .. REGION .. ", " .. PRESET .. ")")
end

print("Run 'meshtastic status' for counters, or 'chat meshtastic' to message.")
