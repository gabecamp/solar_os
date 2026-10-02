-- The kit you used to start in (tshirt, jeans, boots, backpack, a water and
-- a can), for tests written back then. A new game starts with nothing now.
return function(game)
    local p = game.player
    p.equipped = {shirt = "tshirt", pants = "jeans", feet = "boots", back = "backpack"}
    p.inventory = {{item = "water_bottle", qty = 1}, {item = "canned_beans", qty = 1}}
    game:set_difficulty(game.difficulty or "normal")   -- recomputes stats
    return game
end
