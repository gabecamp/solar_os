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

-- (old_dir: where saves lived before the game became The Churn; still read)
local SAVE = {version = 1, dir = "churn", old_dir = "wasteland", file = "save.lua",
              fields = {"world_seed", "seed", "weather_seed", "scavenged", "camps",
                        "known", "ground", "log", "enc_cooldown", "ticked_hour", "rad_known",
                        "trader", "sites_known", "stashes", "next_emission", "snares",
                        "karl_asked", "karl_next", "karl_gave", "muted",
                        "difficulty", "dog", "radio", "karl_hint",
                        "base", "quest", "quests_done",
                        "lore_read", "signal_page", "skills", "stats",
                        "ferry_trader", "peddler", "little", "story", "run_id", "scenes_seen",
                        "research", "books_read", "tapedeck", "gun_wear", "noise_until",
                        "placed", "crates"}}

-- Where the save lives: <preferred storage>/churn/save.lua (dir: another folder)
function SAVE.path(dir)
    local storage = solaros.storage
    if not storage then return nil end
    local ok, root = pcall(function() return storage.mount_point and storage.mount_point() end)
    if not ok or type(root) ~= "string" or root == "" then root = "/flash" end
    dir = dir or SAVE.dir
    return root .. "/" .. dir, root .. "/" .. dir .. "/" .. SAVE.file
end

-- Read a file from the game's folder, or (a save or records from before the
-- rename) from the old one. nil if neither has it.
function SAVE.read(file, max)
    local storage = solaros.storage
    if not (storage and storage.read_file) then return nil end
    for _, dir in ipairs({SAVE.dir, SAVE.old_dir}) do
        local folder = SAVE.path(dir)
        local ok, text = pcall(storage.read_file, folder .. "/" .. file, max)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return nil
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
    local text = SAVE.read(SAVE.file, 65536)
    if not text then return nil end
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
    self.extras = Game.place_extras(tiles, sites, rad, data.world_seed)
    for _, f in ipairs(SAVE.fields) do
        if data[f] ~= nil then self[f] = data[f] end
    end
    if data.scenes_seen == nil then self.scenes_seen = Game.all_scenes_seen() end   -- (older saves)
    -- saves from before emissions existed (or one left far behind) would
    -- otherwise never see another: schedule the next from now
    local E = RAD.emission
    if (self.next_emission or 0) + E.hours <= data.player.hours then
        self.next_emission = data.player.hours + E.every[1]
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
    for _, dir in ipairs({SAVE.dir, SAVE.old_dir}) do   -- (an old save too: one life)
        local _, path = SAVE.path(dir)
        pcall(function() if storage.exists(path) then storage.remove(path) end end)
    end
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
