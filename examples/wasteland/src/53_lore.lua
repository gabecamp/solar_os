-- ---------------------------------------------------------------------
-- Lore: torn pages that tell what happened here (LORE.pages, in order)
--
-- E on a Torn Page reads the next unread page (self.lore_read, saved);
-- the Signal on the radio gives one the first time. J then L opens the
-- reader. How much you've read changes the ending (lore_ending_line).
-- ---------------------------------------------------------------------

LORE = {
    pages = {
        {title = "Institute memo, day 0",
         text = "Instrument readings over the old quarry are 'within tolerance'. Staff are "
             .. "reminded that the hum is a transformer fault. Do not discuss the birds."},
        {title = "A driver's notebook",
         text = "Third run out to the Institute this week. They load crates at night now. "
             .. "One was warm. One was singing, I swear on my mother."},
        {title = "Radio log, 03:12",
         text = "- Say again, the sky over the quarry is what?\n- Purple. It's purple and "
             .. "it's breathing.\n- Breathing.\n- Get everyone inside. Everyone. Now."},
        {title = "The first emission",
         text = "Nobody outside lived. The ones in the cellars came up two days later and "
             .. "the fields had changed. The grass grew in spirals. The dogs came back wrong."},
        {title = "Evacuation order 14",
         text = "All residents will assemble at the school. Bring nothing. Do not bring pets. "
             .. "Do not bring anything that is warm to the touch."},
        {title = "Anna's diary",
         text = "They told the doctors to go. I stayed. Somebody has to sew up the fools who "
             .. "come back for the money. I keep a candle in the window. Nobody asks why."},
        {title = "Karl, written on a tackle box lid",
         text = "Fished this river forty years. Fish came back with too many eyes. Still bite "
             .. "at dusk. A river doesn't care what happened. That's the comfort of it."},
        {title = "The Checkpoint's standing orders",
         text = "No one leaves without paper. Confiscate all objects. Do not hold any object "
             .. "longer than necessary. If an object speaks, report to the sergeant."},
        {title = "A stalker's last note",
         text = "Third artifact today. They're easy if you don't mind the dreams. I dream "
             .. "of a door in a field. Every night it's open a little wider."},
        {title = "Institute memo, day 400",
         text = "The broadcast on the old military band is not ours. It began the night of "
             .. "the first emission. It reads numbers. Lately it reads names."},
        {title = "The numbers",
         text = "We decoded it. They aren't coordinates. They're a count. It counts us, the "
             .. "ones still here, and every time it reads the list, it is shorter."},
        {title = "Unsigned, in the Checkpoint's tower",
         text = "The Churn isn't a wound. It's an eye opening. Everything we take out of it "
             .. "is something it lets us carry, so it can see where we go."},
    },
    -- the ending's last line, by pages read (first match from the top)
    ending = {
        {at = 9, text = "You know what the Signal counts now. As the barrier drops you "
            .. "hear it begin again, one name shorter. It doesn't say yours. Not yet."},
        {at = 4, text = "You've read enough to wonder what you're carrying out, and who "
            .. "is looking through it."},
    },
}

function Game:lore_count()
    return #(self.lore_read or {})
end

-- Read the next page. Returns false if there are none left.
function Game:read_lore(how)
    self.lore_read = self.lore_read or {}
    local n = #self.lore_read + 1
    local page = LORE.pages[n]
    if not page then
        self:push_log("Nothing new on it. You've read them all.")
        return false
    end
    self.lore_read[n] = true
    self:sfx("chime")
    self:push_log(("%s: '%s' (%d/%d, J then L)"):format(how or "A torn page", page.title, n, #LORE.pages))
    return true
end

function Game:lore_ending_line()
    local n = self:lore_count()
    for _, e in ipairs(LORE.ending) do
        if n >= e.at then return e.text end
    end
end

function Game:open_lore()
    if self:lore_count() == 0 then return end
    self.lore_page = math.min(self.lore_page or 1, self:lore_count())
    self.screen = "lore"
end

function Game:lore_key(key)
    local n = self:lore_count()
    if key == gfx.KEY_UP or key == KEY.W or key == gfx.KEY_LEFT or key == KEY.A then
        self.lore_page = math.max(1, self.lore_page - 1)
    elseif key == gfx.KEY_DOWN or key == KEY.S or key == gfx.KEY_RIGHT or key == KEY.D then
        self.lore_page = math.min(n, self.lore_page + 1)
    else
        self.screen = "journal"
    end
end

function Game:draw_lore(w, h)
    local page = LORE.pages[self.lore_page]
    gfx.clear(gfx.WHITE)
    gfx.color(gfx.BLACK)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, 18, page.title)
    gfx.font(gfx.FONT_MONO_12)
    gfx.text(w - 60, 18, self.lore_page .. "/" .. self:lore_count())
    gfx.line(6, 26, w - 6, 26)
    local y = 48
    for para in (page.text .. "\n"):gmatch("(.-)\n") do   -- "\n" starts a new line
        for _, line in ipairs(wrap(para, 54)) do
            gfx.text(6, y, line)
            y = y + 16
        end
    end
    gfx.text(6, h - 8, "Up/Dn page  any other key: back")
    gfx.refresh()
end
