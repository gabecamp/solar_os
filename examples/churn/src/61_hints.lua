-- ---------------------------------------------------------------------
-- First-day hints: the first time a situation comes up in a run, one
-- "Tip:" line in the log (at most one a tick, from tick). self.hints =
-- {id -> true} (saved), so each shows once a run. Every line fits the
-- map's log (57 characters).
-- ---------------------------------------------------------------------

Game.HINTS = {
    {"bleeding", "Tip: bleeding. E on a bandage or a rag stops it.",
     function(g, p) return p.injuries.bleeding end},
    {"cold", "Tip: cold hurts. Wear more, or C: a fire (matches).",
     function(g, p) return (p.cold_hours or 0) > 0 end},
    {"thirsty", "Tip: thirsty. E drinks; boil dirty water by a fire (C).",
     function(g, p) return p.needs.thirst < 45 end},
    {"hungry", "Tip: hungry. E eats; F searches; G hunts or fishes.",
     function(g, p) return p.needs.hunger < 45 end},
    {"tired", "Tip: tired. Space rests; it's safer by a fire.",
     function(g, p) return p.needs.rest < 35 end},
    {"night", "Tip: nights are cold and worse. Rest by a fire.",
     function(g, p) return g:is_night() end},
    {"fire", "Tip: by a fire, C has Study: work out a recipe.",
     function(g, p) return g:fire_here() end},
    {"book", "Tip: E on a book: its first read teaches a recipe.",
     function(g, p)
         for _, s in ipairs(p.inventory) do
             if ITEM_DB[s.item].book and not (g.books_read or {})[s.item] then return true end
         end
     end},
    {"radio", "Tip: R calls on the radio. Anna heals; Karl tells.",
     function(g, p) return g:carrying("lora_radio") end},
}

function Game:hint_tick()
    if self.no_hints then return end
    self.hints = self.hints or {}
    local p = self.player
    for _, h in ipairs(Game.HINTS) do
        if not self.hints[h[1]] and h[3](self, p) then
            self.hints[h[1]] = true
            self:push_log(h[2])
            return
        end
    end
end
