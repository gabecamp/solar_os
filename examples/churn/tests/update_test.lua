-- Updates on open (src/38_update.lua), against a fake GitHub: the check
-- only runs online with somewhere to write; a newer build adds a title
-- row; the download is checked before it replaces churn.lua; a bad one
-- changes nothing.
package.path = "./?.lua;" .. package.path
local fake = require("solaros")
local gfx = fake.gfx
gfx.begin()
local Game = dofile("lib_layout.lua")
local U = Game.UPDATE
local here = Game.VERSION:match("^%S+")
local series, build = here:match("^(.*)%.(%d+)$")

-- the fake server: url -> {status, body, length (nil: #body)}
local SERVER, opened = {}, 0
fake.http = {}
function fake.http.stream_open(method, url, body, headers, timeout, follow)
    opened = opened + 1
    local r = SERVER[url] or {status = 404, body = ""}
    local evs = {{type = "response", status_code = r.status, content_length = r.length or #r.body}}
    for i = 1, #r.body, 10000 do evs[#evs + 1] = {type = "data", data = r.body:sub(i, i + 9999)} end
    evs[#evs + 1] = r.cut and {type = "error", error_name = "ESP_ERR_HTTP_EAGAIN"} or {type = "complete"}
    return {evs = evs, i = 0}
end
function fake.http.stream_read(h) h.i = h.i + 1; return h.evs[h.i] end
function fake.http.stream_close(h) end
local online = true
fake.wifi = {status = function() return {has_ip = online} end}
fake.storage.makedirs("/sd")
local OLD = "-- The Churn version " .. here .. "\nold game"
FAKE_FILES["/sd/churn.lua"] = OLD
local function version_json(b)
    return ('{\n  "series": "%s",\n  "build": %d,\n  "date": "2026-10-07"\n}\n'):format(series, b)
end
local GAME_BODY = "-- The Churn version new\n" .. string.rep("-- code\n", 30000)
local function serve(b, body, extra)
    SERVER[U.base .. U.version_file] = {status = 200, body = version_json(b)}
    local r = {status = 200, body = body or GAME_BODY}
    for k, v in pairs(extra or {}) do r[k] = v end
    SERVER[U.base .. U.file] = r
end
local function fresh()
    local g = Game.new()
    g:begin_intro(nil)
    return g
end
local function shown(g)
    local said, text = {}, gfx.text
    gfx.text = function(x, y, s) said[#said + 1] = s end
    g:draw_title(400, 300)
    gfx.text = text
    return table.concat(said, "|")
end

print("1. versions compare number by number")
assert(Game.version_newer("0.13.10", "0.13.9") and not Game.version_newer("0.13.9", "0.13.10"))
assert(Game.version_newer("0.14.1", "0.13.40") and not Game.version_newer("0.13.9", "0.13.9"))

print("2. a newer build: leaving the splash checks, and the title offers it")
serve(build + 1)
local g = fresh()
g:intro_key(10)
assert(g.screen == "title" and g.update_avail == series .. "." .. (build + 1), tostring(g.update_avail))
local rows = g:title_rows()
assert(rows[#rows][2] == "update" and rows[#rows][1]:find("Update to", 1, true))
assert(shown(g):find("A new version is out", 1, true))

print("3. the same build, offline, no HTTP, or no churn.lua: nothing offered")
serve(build)
g = fresh(); g:intro_key(10)
assert(g.update_avail == nil and g:title_rows()[#g:title_rows()][2] ~= "update")
serve(build + 1)
online = false
local before = opened
g = fresh(); g:intro_key(10)
assert(g.update_avail == nil and opened == before, "offline: never asks")
online = true
local http = fake.http
fake.http = nil
g = fresh(); g:intro_key(10)
assert(g.update_avail == nil, "no HTTP")
fake.http = http
FAKE_FILES["/sd/churn.lua"] = nil
g = fresh(); g:intro_key(10)
assert(g.update_avail == nil, "nowhere to put it")
FAKE_FILES["/sd/churn.lua"] = OLD

print("4. the check happens once")
g = fresh(); g:intro_key(10)
before = opened
g.screen = "intro"; g:intro_key(10)
assert(opened == before)

print("5. picking it downloads, checks and swaps in the new file; the old one is kept")
serve(build + 1)
g = fresh(); g:intro_key(10)
g.title_cursor = #g:title_rows()
g:title_key(10)
assert(FAKE_FILES["/sd/churn.lua"] == GAME_BODY, "the new game in place")
assert(FAKE_FILES["/sd/churn.lua.bak"] == OLD and not FAKE_FILES["/sd/churn.lua.new"])
assert(g.update_msg:find("Updated", 1, true) and g.update_avail == nil and g.screen == "title")
assert(shown(g):find("Updated to", 1, true), "the title says so")

print("6. a broken download changes nothing")
for _, case in ipairs({
    {"cut short", {cut = true}},
    {"shorter than promised", {length = #GAME_BODY + 5000}},
    {"not the game", {body = string.rep("<html>", 30000)}},
    {"a 404", {status = 404}},
}) do
    FAKE_FILES["/sd/churn.lua"], FAKE_FILES["/sd/churn.lua.bak"] = OLD, nil
    serve(build + 1, nil, case[2])
    g = fresh(); g:intro_key(10)
    g.title_cursor = #g:title_rows()
    g:title_key(10)
    assert(FAKE_FILES["/sd/churn.lua"] == OLD, case[1] .. ": the old game stays")
    assert(not FAKE_FILES["/sd/churn.lua.new"] and not FAKE_FILES["/sd/churn.lua.bak"], case[1])
    assert(g.update_msg:find("Update failed", 1, true), case[1] .. ": " .. tostring(g.update_msg))
end

print("UPDATE TESTS PASSED")
