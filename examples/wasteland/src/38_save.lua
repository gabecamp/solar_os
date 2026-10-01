-- ---------------------------------------------------------------------
-- Saving and continuing
--
-- Needs solaros.storage.write_file, which SolarOS gains with the patch in
-- firmware/ (upstream request pending). Without it the game runs exactly as
-- before and simply can't save.
--
-- The save is a Lua table literal (read back with load() in an empty
-- environment, so it can't run code). The world itself is not stored: it is
-- regenerated from world_seed, and only what changes is saved - the player,
-- ground items, fires, searched tiles, known recipes, the clock and the log.
-- Autosave runs whenever time passes on the map/inventory/crafting screens
-- and on quit; death deletes the save (one life, like NEO Scavenger).
-- ---------------------------------------------------------------------

local SAVE = {version = 1, dir = "wasteland", file = "save.lua",
              fields = {"world_seed", "seed", "weather_seed", "scavenged", "camps",
                        "known", "ground", "log", "enc_cooldown", "ticked_hour", "rad_known",
                        "trader", "sites_known", "stashes", "next_emission", "snares",
                        "karl_asked", "karl_next", "karl_gave", "muted"}}

-- Where the save lives: <preferred storage>/wasteland/save.lua
function SAVE.path()
    local storage = solaros.storage
    if not storage then return nil end
    local ok, root = pcall(function() return storage.mount_point and storage.mount_point() end)
    if not ok or type(root) ~= "string" or root == "" then root = "/flash" end
    return root .. "/" .. SAVE.dir, root .. "/" .. SAVE.dir .. "/" .. SAVE.file
end

function SAVE.can_write()
    return solaros.storage ~= nil and solaros.storage.write_file ~= nil
end

-- Plain values and nested tables of them, keys sorted so saves are stable.
function SAVE.serialize(v, out)
    local t = type(v)
    if t == "number" then
        out[#out + 1] = math.type(v) == "integer" and tostring(v) or string.format("%.17g", v)
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                out[#out + 1] = k .. "="
            else
                out[#out + 1] = "["
                SAVE.serialize(k, out)
                out[#out + 1] = "]="
            end
            SAVE.serialize(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "nil"
    end
    return out
end

function Game:save_state()
    local data = {version = SAVE.version, player = {}}
    for _, f in ipairs(SAVE.fields) do data[f] = self[f] end
    for k, v in pairs(self.player) do
        if k ~= "visible" then data.player[k] = v end   -- visible is recomputed
    end
    return table.concat(SAVE.serialize(data, {}))
end

-- Write the save. Returns true, or false and why (never raises).
function Game:save()
    if not SAVE.can_write() then return false, "this SolarOS can't write files" end
    local dir, path = SAVE.path()
    local ok, err = pcall(function()
        if solaros.storage.makedirs then solaros.storage.makedirs(dir) end
        solaros.storage.write_file(path, self:save_state())
    end)
    if not ok then return false, (tostring(err):gsub("^.-:%d+: ", "")) end
    self.saved_hour = self.player.hours
    return true
end

-- The saved table, or nil (no save, unreadable, or from another version).
function Game.read_save()
    local storage = solaros.storage
    if not (storage and storage.read_file) then return nil end
    local _, path = SAVE.path()
    local ok, text = pcall(storage.read_file, path, 65536)
    if not ok or type(text) ~= "string" or text == "" then return nil end
    local chunk = load("return " .. text, "=save", "t", {})
    if not chunk then return nil end
    local good, data = pcall(chunk)
    if not good or type(data) ~= "table" or data.version ~= SAVE.version
        or type(data.player) ~= "table" or not data.world_seed then
        return nil
    end
    return data
end

function Game:load_state(data)
    local tiles, _, _, rad, sites = generate_world(data.world_seed)
    self.tiles, self.rad, self.sites = tiles, rad, sites
    for _, f in ipairs(SAVE.fields) do
        if data[f] ~= nil then self[f] = data[f] end
    end
    self.player = data.player
    self.player.visible = {}
    self.player.explored = self.player.explored or {}
    recompute_stats(self.player)
    self.saved_hour = self.player.hours
    self:refresh_view()
    self.screen = "map"
    local day, hour = self:clock()
    self:push_log(("Welcome back. Day %d, %02d:00."):format(day, hour))
end

function Game.delete_save()
    local storage = solaros.storage
    if not (storage and storage.remove and storage.exists) then return end
    local _, path = SAVE.path()
    pcall(function() if storage.exists(path) then storage.remove(path) end end)
end

-- Save after anything that took time, on the screens where a run is at rest.
function Game:autosave()
    if not SAVE.can_write() then return end
    local s = self.screen
    if s ~= "map" and s ~= "inventory" and s ~= "craft" then return end
    if self.saved_hour == self.player.hours and not self.force_save then return end
    self.force_save = nil
    local ok, why = self:save()
    if not ok and not self.save_warned then
        self.save_warned = true
        self:push_log("Couldn't save: " .. why)
    end
end

-- Title screen, shown at start-up when there is a save to continue.
function Game:draw_title(w, h)
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(w // 2 - 70, 60, "Wasteland Survivor")
    gfx.font(gfx.FONT_MONO_12)
    local d = self.title_save
    local rows = {("Continue  (day %d, %d HP)"):format(
                      (WORLD.start_hour + d.player.hours) // 24 + 1, math.floor(d.player.health or 0)),
                  "New survivor"}
    for i, text in ipairs(rows) do
        local y = 120 + (i - 1) * 24
        if i == self.title_cursor then
            gfx.fill_rect(w // 2 - 110, y - 13, 220, 18)
            gfx.color(gfx.WHITE)
        end
        gfx.text(w // 2 - 100, y, text)
        gfx.color(gfx.BLACK)
    end
    gfx.text(6, h - 8, "Up/Dn pick  Enter choose  Q quit")
    gfx.refresh()
end

function Game:title_key(key)
    if key == gfx.KEY_UP or key == KEY.W or key == gfx.KEY_DOWN or key == KEY.S then
        self.title_cursor = 3 - self.title_cursor
    elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
        if self.title_cursor == 1 then
            self:load_state(self.title_save)
        else
            self.screen = "creator"
        end
        self.title_save = nil
    end
end
