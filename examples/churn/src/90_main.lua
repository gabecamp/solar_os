-- ---------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------

-- Everything built at load is in place: clear out the garbage the build left
-- (the collector setting is at the top of the file, 00_header).
collectgarbage("collect")

gfx.begin()

local ok, err = pcall(function()
    local game = Game.new()
    local w, h = gfx.size()
    game:begin_intro(Game.read_save())   -- the splash, then the title menu

    local function handle_map_key(key)
        if game:map_dir_key(key) then
            return   -- (a step, or Up/Down leaning for the next one)
        elseif key == gfx.KEY_ESCAPE or key == KEY.Q then
            game:ask_quit()   -- (asks first: a run is under way)
        elseif key == KEY.SPACE then
            game:rest()
        elseif key == KEY.F then
            game:scavenge()
        elseif key == KEY.E then
            game:water_action()
        elseif key == KEY.T then
            game:site_action()
        elseif key == KEY.H then
            game:open_help()
        elseif key == KEY.G then
            game:gather()
        elseif key == KEY.M then
            game:toggle_mute()
        elseif key == KEY.R then
            game:open_radio()
        elseif key == KEY.J then
            game:open_journal()
        elseif key == KEY.C then
            game:open_crafting()
        elseif key == KEY.I then
            game.screen = "inventory"
            game.camp_view = nil
            game.inv_cursor = 1
            game.inv_selected = nil
        end
    end

    local function handle_inventory_key(key)
        if key == gfx.KEY_ESCAPE or key == KEY.Q then
            game:ask_quit()
        elseif key == KEY.I then
            game.screen = "map"
            game.camp_view = nil
        elseif key == KEY.T and game:at_base() then   -- the bag <-> the camp
            game.camp_view = not game.camp_view or nil
            game.inv_cursor, game.inv_selected = 1, nil
        elseif key == KEY.H then
            game:open_help()
        elseif key == KEY.J then
            game:open_journal()
        elseif key == KEY.C then
            game.inv_selected = nil
            game:open_crafting()
        elseif key == gfx.KEY_UP or key == KEY.W then
            game:inv_move(0, -1)
        elseif key == gfx.KEY_DOWN or key == KEY.S then
            game:inv_move(0, 1)
        elseif key == gfx.KEY_LEFT or key == KEY.A then
            game:inv_move(-1, 0)
        elseif key == gfx.KEY_RIGHT or key == KEY.D then
            game:inv_move(1, 0)
        elseif key == KEY.X or key == KEY.BACKSPACE then
            game:inv_drop()
        elseif key == KEY.E then
            local row = INV_ROWS[game.inv_cursor]
            if row then
                game:use_item(row[1], row[2])
                -- the stack may be gone or shifted; don't keep a stale pick
                game.inv_selected = nil
            end
        elseif key == KEY.ENTER or key == KEY.LF or key == KEY.SPACE then
            local row = INV_ROWS[game.inv_cursor]
            if row then
                if game.inv_selected == nil then
                    if game:get_stack(row[1], row[2]) ~= nil then
                        game.inv_selected = {row[1], row[2]}
                    end
                else
                    game:try_transfer(game.inv_selected, {row[1], row[2]})
                    game.inv_selected = nil
                end
            end
        end
    end

    -- Redraw only after a key was handled: nothing changes on its own, and a
    -- full frame is hundreds of gfx calls plus a panel refresh.
    local dirty = true
    while not game.quit and not solaros.should_exit() do
        if game:show_queued_scene() then dirty = true end   -- (a story moment)
        if dirty then
            -- the bag screen patches itself when only its cursor moved; any
            -- other screen in between means it has to be drawn whole again
            if game.screen ~= "inventory" then game.inv_drawn = nil end
            if game.screen ~= "map" then game.move_lean = nil end   -- (no stale Up/Down)
            Game.draw_pump(true)
            if game.screen == "intro" then
                game:draw_intro(w, h)
            elseif game.screen == "title" then
                game:draw_title(w, h)
            elseif game.screen == "crawl" then
                game:draw_crawl(w, h)
            elseif game.screen == "creator" then
                game:draw_creator(w, h)
            elseif game.screen == "dead" then
                game:draw_dead(w, h)
            elseif game.screen == "ending" then
                game:draw_ending(w, h)
            elseif game.screen == "help" then
                game:draw_help(w, h)
            elseif game.screen == "radio" then
                game:draw_radio(w, h)
            elseif game.screen == "journal" then
                game:draw_journal(w, h)
            elseif game.screen == "lore" then
                game:draw_lore(w, h)
            elseif game.screen == "skills" then
                game:draw_skills(w, h)
            elseif game.screen == "info" then
                game:draw_info(w, h)
            elseif game.screen == "records" then
                game:draw_records(w, h)
            elseif game.screen == "trade" then
                game:draw_trade(w, h)
            elseif game.screen == "gate" then
                game:draw_gate(w, h)
            elseif game.screen == "encounter" then
                game:draw_encounter(w, h)
            elseif game.screen == "puzzle" then
                game:draw_puzzle(w, h)
            elseif game.screen == "fishing" then
                game:draw_fishing(w, h)
            elseif game.screen == "craft" then
                game:draw_craft(w, h)
            elseif game.screen == "scene" then
                game:draw_scene(w, h)
            elseif game.screen == "map" then
                game:draw_map(w, h)
            else
                game:draw_inventory(w, h)
            end
            if game.confirm_quit then game:draw_quit_confirm(w, h) end
            Game.draw_pump(false)
            dirty = false
        end

        local key = gfx.getch(POLL_MS)
        if key == nil and game.screen == "intro" then game:intro_tick(w, h) end   -- (the eye turns)
        if key == KEY.CLOSE then
            game:close_requested()
            dirty = true
        elseif key ~= nil and game.confirm_quit then
            game:quit_confirm_key(key)   -- (no time passes while it asks)
            dirty = true
        elseif key ~= nil then
            if game.screen == "records" then
                game:records_key(key)
            elseif key == KEY.R and (game.screen == "title" or game.screen == "creator"
                                     or game.screen == "dead" or game.screen == "ending") then
                game:open_records()
            elseif game.screen == "intro" then
                game:intro_key(key)
            elseif game.screen == "crawl" then
                game:crawl_key(key)
            elseif game.screen == "title" then
                if key == gfx.KEY_ESCAPE or key == KEY.Q then
                    game.quit = true
                else
                    game:title_key(key)
                end
            elseif game.screen == "creator" then
                if key == gfx.KEY_ESCAPE or key == KEY.Q then
                    game.quit = true
                else
                    game:creator_key(key)
                end
            elseif game.screen == "encounter" then
                game:encounter_key(key)
            elseif game.screen == "puzzle" then
                game:puzzle_key(key)
            elseif game.screen == "fishing" then
                game:fishing_key(key)
            elseif game.screen == "craft" then
                if key == KEY.Q then game:ask_quit() else game:craft_key(key) end
            elseif game.screen == "trade" then
                game:trade_key(key)
            elseif game.screen == "help" or game.screen == "info" or game.screen == "journal" then
                game:help_key(key)
            elseif game.screen == "radio" then
                game:radio_key(key)
            elseif game.screen == "lore" then
                game:lore_key(key)
            elseif game.screen == "skills" then
                game:skills_key(key, h)
            elseif game.screen == "gate" then
                game:gate_key(key)
            elseif game.screen == "dead" or game.screen == "ending" then
                if key == gfx.KEY_ESCAPE or key == KEY.Q then
                    game.quit = true
                elseif key == KEY.ENTER or key == KEY.LF then
                    game = Game.new()   -- a fresh world and the creator
                end
            elseif game.screen == "scene" then
                game:scene_key(key)
            elseif game.screen == "map" then
                handle_map_key(key)
            else
                handle_inventory_key(key)
            end
            -- time may have passed (moving, resting, crafting...): apply cold,
            -- night and light before the next frame
            if game.screen ~= "creator" and game.screen ~= "dead" and game.screen ~= "title"
                and game.screen ~= "intro" and game.screen ~= "crawl"
                and game.screen ~= "ending" and game.screen ~= "records" then
                game:tick()
            end
            game:autosave()
            dirty = true
        end
    end
    -- quitting mid-run keeps it (a run on the title or creator isn't started yet)
    game.force_save = true
    game:autosave()
end)

-- Per SolarOS convention: cleanup must run even when drawing/logic fails,
-- and the error is re-raised afterward so it still surfaces (with a real
-- traceback) instead of being silently swallowed. (A draw that failed
-- mid-frame left the fast event pump on: turn it off first.)
Game.draw_pump(false)
gfx["end"]()
if not ok then
    error(err)
end
