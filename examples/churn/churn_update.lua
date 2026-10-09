-- churn_update.lua: download the latest The Churn (churn.lua) from GitHub
-- onto this SolarTerm. Run it with the lua app: lua churn_update.lua
--
-- It finds your churn.lua (or puts a new one at the top of storage),
-- downloads the newest version over Wi-Fi to churn.lua.new, checks it, and
-- only then swaps it in. The old one is kept as churn.lua.bak. Your save
-- (churn/save.lua) is not touched.
--
-- Needs Wi-Fi (a saved network is used) and firmware with solaros.http.

local URL = "https://raw.githubusercontent.com/gabecamp/solar_os/main/examples/churn/churn.lua"
local TARGET = nil   -- set a path here (e.g. "/sdcard/churn.lua") to skip the search

local storage, http, wifi, time = solaros.storage, solaros.http, solaros.wifi, solaros.time
local CHUNK = 32768   -- bytes per write (write_file takes at most 65536)

local function fail(msg)
    print("Update failed: " .. msg)
    print("Your old churn.lua is unchanged.")
    error(msg, 0)
end

if not (storage and storage.write_file) then fail("this SolarOS can't write files") end
if not (http and http.stream_open) then fail("this SolarOS has no HTTP streaming") end

-- where the game lives
local function mount()
    local ok, root = pcall(storage.mount_point)
    if ok and type(root) == "string" and root ~= "" then return root end
    return "/flash"
end
local function exists(path)
    local ok, yes = pcall(storage.exists, path)
    return ok and yes
end
if not TARGET then
    local root = mount()
    for _, p in ipairs({root .. "/churn.lua", "/sdcard/churn.lua", "/flash/churn.lua",
                        root .. "/lua/churn.lua", root .. "/apps/churn.lua", root .. "/games/churn.lua"}) do
        if exists(p) then TARGET = p break end
    end
    TARGET = TARGET or (root .. "/churn.lua")
end
local NEW, BAK = TARGET .. ".new", TARGET .. ".bak"
print("The Churn updater")
print("Target: " .. TARGET .. (exists(TARGET) and "" or " (new)"))

-- Wi-Fi: use the saved network if not online yet
if wifi and wifi.status then
    local s = wifi.status()
    if not s.has_ip then
        print("Connecting to Wi-Fi" .. (s.saved_ssid ~= "" and (" (" .. s.saved_ssid .. ")") or "") .. "...")
        pcall(wifi.start)
        pcall(wifi.connect_saved)
        local t0 = time.uptime_ms()
        repeat
            time.sleep_ms(500)
            s = wifi.status()
        until s.has_ip or time.uptime_ms() - t0 > 20000
        if not s.has_ip then fail("no Wi-Fi. Connect first (wifi in the shell)") end
    end
    print("Online: " .. (s.ip or "?"))
end

-- download to churn.lua.new, a chunk at a time
pcall(storage.remove, NEW)
storage.write_file(NEW, "")
print("Downloading...")
local h = http.stream_open("GET", URL, nil, nil, 20000, true)
local status, length, got, buf, n, buffered = 0, -1, 0, {}, 0, 0
local version, tail = nil, ""
local last_shown = 0
local function flush()
    if n == 0 then return end
    storage.write_file(NEW, table.concat(buf, "", 1, n), true)
    buf, n, buffered = {}, 0, 0
end
local ok, err = pcall(function()
    while true do
        local ev = http.stream_read(h, 30000)
        if ev == nil then error("the server stopped answering") end
        if ev.type == "response" then
            status, length = ev.status_code or 0, ev.content_length or -1
            if status ~= 200 then error("server said " .. status) end
        elseif ev.type == "data" then
            local d = ev.data
            got, buffered = got + #d, buffered + #d
            n = n + 1
            buf[n] = d
            if not version then   -- (the version line, as it streams past)
                local s = tail .. d
                version = s:match('Game%.VERSION = "([^"]+)"')
                tail = s:sub(-64)
            end
            if got >= last_shown + 100000 then
                last_shown = got
                print(("  %d KB%s"):format(got // 1024, length > 0 and (" of " .. length // 1024) or ""))
            end
            if buffered >= CHUNK then flush() end
        elseif ev.type == "complete" then
            flush()
            return
        elseif ev.type == "error" then
            error("download error " .. tostring(ev.error_name or ev.error))
        end
    end
end)
pcall(http.stream_close, h)
if not ok then
    pcall(storage.remove, NEW)
    fail(tostring(err))
end

-- check it before swapping it in
local st = storage.stat(NEW)
local head = storage.read_file(NEW, 256) or ""
if length > 0 and st.size ~= length then
    pcall(storage.remove, NEW)
    fail(("incomplete: %d of %d bytes"):format(st.size, length))
end
if st.size < 100000 or not head:find("The Churn", 1, true) then
    pcall(storage.remove, NEW)
    fail("that doesn't look like churn.lua (" .. st.size .. " bytes)")
end

-- swap: churn.lua -> churn.lua.bak, churn.lua.new -> churn.lua
if exists(TARGET) then
    pcall(storage.remove, BAK)
    storage.rename(TARGET, BAK)
end
local swapped, why = pcall(storage.rename, NEW, TARGET)
if not swapped then
    if exists(BAK) then pcall(storage.rename, BAK, TARGET) end
    fail("couldn't put the new file in place: " .. tostring(why))
end

print(("Done: %d KB, version %s."):format(st.size // 1024, version or "?"))
print("Saved to " .. TARGET .. (exists(BAK) and (" (old one: " .. BAK .. ")") or ""))
print("Run it: lua " .. TARGET)
