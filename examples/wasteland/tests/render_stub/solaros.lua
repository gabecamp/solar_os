-- Recording stub: logs every gfx call to ops.txt so a Python script can replay
-- them into a real image. Used only for eyeballing layout, not shipped.
local M = {gfx = {}, audio = {}}
local gfx = M.gfx
local ops = {}
local cur_color, cur_font = "BLACK", "MONO12"

gfx.WHITE, gfx.LIGHT, gfx.DARK, gfx.BLACK = "WHITE", "LIGHT", "DARK", "BLACK"
gfx.FONT_BOLD_14, gfx.FONT_MONO_12 = "BOLD14", "MONO12"
gfx.KEY_ESCAPE, gfx.KEY_UP, gfx.KEY_DOWN, gfx.KEY_LEFT, gfx.KEY_RIGHT = 0x1b, 0x80, 0x81, 0x82, 0x83

local function log(...) ops[#ops + 1] = table.concat({...}, "\t") end
local function ints(...)
    for _, v in ipairs({...}) do assert(math.type(v) == "integer", "non-integer arg: " .. tostring(v)) end
end

function gfx.begin() end
gfx["end"] = function() end
function gfx.clear(c) log("clear", c or "WHITE") end
function gfx.color(c) cur_color = c end
function gfx.font(f) cur_font = f end
function gfx.text(x, y, s) ints(x, y); log("text", x, y, cur_color, cur_font, s) end
function gfx.line(a, b, c, d) ints(a, b, c, d); log("line", a, b, c, d, cur_color) end
function gfx.rect(x, y, w, h) ints(x, y, w, h); log("rect", x, y, w, h, cur_color) end
function gfx.fill_rect(x, y, w, h) ints(x, y, w, h); log("fillrect", x, y, w, h, cur_color) end
function gfx.circle(x, y, r) ints(x, y, r); log("circle", x, y, r, cur_color) end
function gfx.fill_circle(x, y, r) ints(x, y, r); log("fillcircle", x, y, r, cur_color) end
function gfx.pixel(x, y) ints(x, y); log("pixel", x, y, cur_color) end
function gfx.sprite(x, y, w, h, data)
    ints(x, y, w, h)
    local hex = {}
    for i = 1, #data do hex[#hex + 1] = ("%02x"):format(data:byte(i)) end
    log("sprite", x, y, w, h, cur_color, table.concat(hex))
end
gfx.bitmap = gfx.sprite
function gfx.refresh() end
function gfx.size() return 300, 400 end
function gfx.getch() return nil end
function M.should_exit() return true end
function M.audio.tone() end

function M.dump(path)
    local f = assert(io.open(path, "w"))
    f:write(table.concat(ops, "\n"), "\n")
    f:close()
    ops = {}
end
return M
