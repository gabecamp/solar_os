-- ---------------------------------------------------------------------
-- Story moments (texts in QUESTS.scenes): a short full-screen scene, once a
-- run, at a few turning points. Game:queue_scene(id) from the moment's own
-- code; the main loop shows queued scenes only from the map screen (so the
-- tests and the balance sim, which call methods directly, never see one).
-- self.scenes_seen = {id = true} (saved; an old save counts all as seen).
-- ---------------------------------------------------------------------

function Game:queue_scene(id)
    self.scenes_seen = self.scenes_seen or {}
    if self.scenes_seen[id] or not QUESTS.scenes[id] then return false end
    self.scenes_seen[id] = true
    self.scene_queue = self.scene_queue or {}
    table.insert(self.scene_queue, id)
    return true
end

-- From the main loop: true if a scene is now on screen.
function Game:show_queued_scene()
    local q = self.scene_queue
    if self.screen ~= "map" or not q or #q == 0 then return false end
    self.scene = table.remove(q, 1)
    self.screen = "scene"
    return true
end

function Game:scene_key()
    self.scene = nil
    self.screen = "map"
end

-- Every scene counted as seen (old saves: nothing replays).
function Game.all_scenes_seen()
    local seen = {}
    for _, id in ipairs(QUESTS.scenes.order) do seen[id] = true end
    return seen
end

function Game:draw_scene(w, h)
    local sc = QUESTS.scenes[self.scene] or QUESTS.scenes.wake
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(10, 24, sc.title)
    gfx.font(gfx.FONT_MONO_12)
    local cols = 54
    if sc.art and draw_sprite then
        self:draw_portrait({def = {art = sc.art}}, w - PORTRAIT_SIZE - 10, 34)
        gfx.color(gfx.BLACK)
        gfx.rect(w - PORTRAIT_SIZE - 11, 33, PORTRAIT_SIZE + 2, PORTRAIT_SIZE + 2)
        cols = (w - PORTRAIT_SIZE - 30) // 7
    end
    local y = 50
    for _, line in ipairs(wrap(sc.text, cols)) do
        gfx.text(10, y, line)
        y = y + 16
    end
    gfx.text(10, h - 8, "Any key to go on")
end
