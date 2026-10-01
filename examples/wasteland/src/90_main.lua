-- ---------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------

gfx.begin()

local ok, err = pcall(function()
    local game = Game.new()
    local w, h = gfx.size()
    local saved = Game.read_save()
    if saved then
        game.screen = "title"
        game.title_save = saved
        game.title_cursor = 1
    end

    local function handle_map_key(key)
        if key == gfx.KEY_ESCAPE or key == KEY.Q then
            game.quit = true
        elseif key == gfx.KEY_LEFT or key == KEY.A then
            game:move_dir(-1, 0)
        elseif key == gfx.KEY_RIGHT or key == KEY.D then
            game:move_dir(1, 0)
        elseif key == gfx.KEY_UP or key == KEY.W then
            game:move_dir(0, -1)
        elseif key == gfx.KEY_DOWN or key == KEY.S then
            game:move_dir(0, 1)
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
        elseif key == KEY.C then
            game:open_crafting()
        elseif key == KEY.I then
            game.screen = "inventory"
            game.inv_cursor = 1
            game.inv_selected = nil
        end
    end

    local function handle_inventory_key(key)
        if key == gfx.KEY_ESCAPE or key == KEY.Q then
            game.quit = true
        elseif key == KEY.I then
            game.screen = "map"
        elseif key == KEY.H then
            game:open_help()
        elseif key == KEY.C then
            game.inv_selected = nil
            game:open_crafting()
        elseif key == gfx.KEY_UP or key == KEY.W or key == gfx.KEY_LEFT or key == KEY.A then
            game.inv_cursor = math.max(1, game.inv_cursor - 1)
        elseif key == gfx.KEY_DOWN or key == KEY.S or key == gfx.KEY_RIGHT or key == KEY.D then
            game.inv_cursor = math.min(#INV_ROWS, game.inv_cursor + 1)
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
        if dirty then
            if game.screen == "title" then
                game:draw_title(w, h)
            elseif game.screen == "creator" then
                game:draw_creator(w, h)
            elseif game.screen == "dead" then
                game:draw_dead(w, h)
            elseif game.screen == "ending" then
                game:draw_ending(w, h)
            elseif game.screen == "help" then
                game:draw_help(w, h)
            elseif game.screen == "info" then
                game:draw_info(w, h)
            elseif game.screen == "trade" then
                game:draw_trade(w, h)
            elseif game.screen == "gate" then
                game:draw_gate(w, h)
            elseif game.screen == "encounter" then
                game:draw_encounter(w, h)
            elseif game.screen == "puzzle" then
                game:draw_puzzle(w, h)
            elseif game.screen == "craft" then
                game:draw_craft(w, h)
            elseif game.screen == "map" then
                game:draw_map(w, h)
            else
                game:draw_inventory(w, h)
            end
            dirty = false
        end

        local key = gfx.getch(POLL_MS)
        if key ~= nil then
            if game.screen == "title" then
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
            elseif game.screen == "craft" then
                if key == KEY.Q then game.quit = true else game:craft_key(key) end
            elseif game.screen == "trade" then
                game:trade_key(key)
            elseif game.screen == "help" or game.screen == "info" then
                game:help_key(key)
            elseif game.screen == "gate" then
                game:gate_key(key)
            elseif game.screen == "dead" or game.screen == "ending" then
                if key == gfx.KEY_ESCAPE or key == KEY.Q then
                    game.quit = true
                elseif key == KEY.ENTER or key == KEY.LF then
                    game = Game.new()   -- a fresh world and the creator
                end
            elseif game.screen == "map" then
                handle_map_key(key)
            else
                handle_inventory_key(key)
            end
            -- time may have passed (moving, resting, crafting...): apply cold,
            -- night and light before the next frame
            if game.screen ~= "creator" and game.screen ~= "dead" and game.screen ~= "title"
                and game.screen ~= "ending" then
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
-- traceback) instead of being silently swallowed.
gfx["end"]()
if not ok then
    error(err)
end
