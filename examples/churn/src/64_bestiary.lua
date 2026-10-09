-- ---------------------------------------------------------------------
-- The bestiary (numbers in CHURN.bestiary): a page for every creature you
-- meet, kept by who it is (def.who). self.bestiary[who] = {name, seen,
-- watched, killed, sold} (saved). Watching one (Watch it, in a fight) finds
-- its weak spot for good: + bonus % to hit that kind ever after. A full
-- page - seen, watched and killed - sells to the Trader (N on his screen).
-- B in the journal shows the pages.
-- ---------------------------------------------------------------------

function Game:beast_page(def, make)
    if not def or CHURN.bestiary.skip[def.kind] or def.phantom or def.legacy then return nil end
    self.bestiary = self.bestiary or {}
    local page = self.bestiary[def.who]
    if not page and make then
        page = {name = def.name, seen = 0, killed = 0}
        self.bestiary[def.who] = page
    end
    return page
end

function Game:beast_seen(def)
    local page = self:beast_page(def, true)
    if page then page.seen = page.seen + 1 end
end

function Game:beast_watched(def)
    local page = self:beast_page(def, true)
    if page and not page.watched then
        page.watched = true
        self:enc_say("You note how it moves, where it's soft. (Bestiary: weak spot)")
    end
end

function Game:beast_killed(def)
    local page = self:beast_page(def, true)
    if page then page.killed = page.killed + 1 end
end

-- +% to hit what you're fighting, if you know its weak spot.
function Game:beast_bonus()
    local page = self.enc and self:beast_page(self.enc.def)
    return page and page.watched and CHURN.bestiary.bonus or 0
end

function Game.beast_full(page)
    return page.seen > 0 and page.watched and page.killed > 0
end

-- The journal page (B).
function Game:bestiary_lines()
    local names = {}
    for who, page in pairs(self.bestiary or {}) do names[#names + 1] = who end
    table.sort(names, function(a, b) return self.bestiary[a].name < self.bestiary[b].name end)
    if #names == 0 then return wrap("Nothing yet. Every creature you meet gets a page.", 55) end
    local lines, full = {}, 0
    for _, who in ipairs(names) do
        local pg = self.bestiary[who]
        if Game.beast_full(pg) then full = full + 1 end
        lines[#lines + 1] = ("%s%s"):format(pg.name, Game.beast_full(pg) and (pg.sold and "  (sold)" or "  (full page)") or "")
        lines[#lines + 1] = ("   seen %d, killed %d, weak spot: %s"):format(pg.seen, pg.killed,
            pg.watched and ("+" .. CHURN.bestiary.bonus .. "% to hit") or "watch it")
    end
    table.insert(lines, 1, ("%d pages, %d full. The Trader buys full ones (N)."):format(#names, full))
    table.insert(lines, 2, "")
    return lines
end

function Game:open_bestiary()
    self.skills_off, self.page = 0, "bestiary"
    self.screen = "skills"
end

-- N on the Trader's screen: full pages for rubles.
function Game:sell_bestiary()
    local n = 0
    for _, pg in pairs(self.bestiary or {}) do
        if Game.beast_full(pg) and not pg.sold then
            pg.sold, n = true, n + 1
        end
    end
    if n == 0 then return "'Bring me a full page. Seen it, studied it, killed it.'" end
    local pay = n * CHURN.bestiary.price
    if not self:put_stack("inventory", nil, {item = "rubles", qty = pay}) then
        self:put_stack("ground", nil, {item = "rubles", qty = pay})
    end
    return ("'Good notes.' He pays %d rubles for %d page%s."):format(pay, n, n > 1 and "s" or "")
end
