-- ---------------------------------------------------------------------
-- The look every screen shares (a few gfx calls each, so cheap on the
-- device): a black title bar with the screen's name and, at its right, a
-- status; a footer of key chips - the key in a black box, then what it
-- does; bars for a value out of a maximum.
-- ---------------------------------------------------------------------

Game.UI = {bar_h = 22, chip_h = 13, gap = 8}

-- The title bar. right (optional): status text at the bar's right end.
-- Leaves the pen black and the font mono 12.
-- bh (optional): a slimmer bar (the bag screen's, 16).
function Game.ui_title(w, title, right, bh)
    bh = bh or Game.UI.bar_h
    gfx.color(gfx.BLACK)
    gfx.fill_rect(0, 0, w, bh)
    gfx.color(gfx.WHITE)
    gfx.font(gfx.FONT_BOLD_14)
    gfx.text(6, bh - 6 + (bh < Game.UI.bar_h and 2 or 0), title)
    gfx.font(gfx.FONT_MONO_12)
    if right then gfx.text(w - 6 - 7 * #right, bh - 7 + (bh < Game.UI.bar_h and 2 or 0), right) end
    gfx.color(gfx.BLACK)
end

-- "Up/Dn pick  Enter make  Q quit", "Arrows Spc:rest F:search", "any key:
-- back": the footer's text as {key, what it does} pairs.
function Game.ui_key_pairs(text)
    local pairs_ = {}
    local function add(group)
        group = group:gsub("^%s+", ""):gsub("%s+$", "")
        if group == "" then return end
        local k, v = group:match("^(.-):%s*(.*)$")
        if k and not k:find(" ") or (k and k:lower() == "any key") then
            pairs_[#pairs_ + 1] = {k, v}
            return
        end
        local first, rest = group:match("^(%S+)%s+(.+)$")
        pairs_[#pairs_ + 1] = first and {first, rest} or {group, ""}
    end
    for group in (text .. "  "):gmatch("(.-)%s%s+") do
        -- one group of single-spaced "K:label" tokens: split them
        if select(2, group:gsub(":", "")) > 1 then
            for tok in group:gmatch("%S+") do add(tok) end
        else
            add(group)
        end
    end
    return pairs_
end

-- The key footer along the bottom. Squeezes the gaps (then drops what
-- won't fit) to stay on the screen.
function Game.ui_keys(w, h, text)
    local U, list = Game.UI, Game.ui_key_pairs(text)
    local total = 0
    for _, kv in ipairs(list) do
        total = total + 7 * #kv[1] + 4 + (kv[2] ~= "" and 7 * #kv[2] + 3 or 0)
    end
    local gap = math.max(2, math.min(U.gap, (w - 8 - total) // math.max(1, #list - 1)))
    local x, y = 4, h - 4 - U.chip_h
    gfx.font(gfx.FONT_MONO_12)
    for _, kv in ipairs(list) do
        local kw, lw = 7 * #kv[1] + 4, kv[2] ~= "" and 7 * #kv[2] + 3 or 0
        if x + kw + lw > w - 2 then break end
        gfx.color(gfx.BLACK)
        gfx.fill_rect(x, y, kw, U.chip_h)
        gfx.color(gfx.WHITE)
        gfx.text(x + 2, y + 10, kv[1])
        gfx.color(gfx.BLACK)
        if lw > 0 then gfx.text(x + kw + 3, y + 10, kv[2]) end
        x = x + kw + lw + gap
    end
end

-- A bar: frame, filled to frac (0..1). dark: fill in dark gray (it dithers).
function Game.ui_bar(x, y, bw, bh, frac, dark)
    gfx.color(gfx.BLACK)
    gfx.rect(x, y, bw, bh)
    local fw = math.floor((bw - 2) * math.max(0, math.min(1, frac)) + 0.5)
    if fw > 0 then
        gfx.color(dark and gfx.DARK or gfx.BLACK)
        gfx.fill_rect(x + 1, y + 1, fw, bh - 2)
    end
    gfx.color(gfx.BLACK)
end

-- Letters work with or without Shift or Caps Lock: A-Z read as a-z (every
-- binding is lowercase; arrows and the rest are 0x80 and up, untouched).
function Game.norm_key(key)
    if key and key >= 65 and key <= 90 then return key + 32 end
    return key
end

-- A small label on a black tag (section headings on busy screens).
function Game.ui_tag(x, y, text)
    gfx.color(gfx.BLACK)
    gfx.fill_rect(x - 2, y - 10, 7 * #text + 4, 13)
    gfx.color(gfx.WHITE)
    gfx.text(x, y, text)
    gfx.color(gfx.BLACK)
end
