-- Host tests for theme.lua. Run from the repo root: lua tests/theme_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local stub = require("stub")
local eq = stub.eq

local T = {}

function T.colours_and_shapes()
    stub.new()
    local theme = stub.fresh("theme")
    for _, k in ipairs({ "BG", "GRID", "TEXT", "GAMEOVER", "CYAN", "BLUE", "ORANGE", "YELLOW",
                         "GREEN", "PURPLE", "PINK", "WHITE", "RAIN", "PANEL", "BORDER", "DIM", "FLASH" }) do
        assert(math.type(theme.C[k]) == "integer", k .. " should be an integer colour")
    end
    eq(theme.C.BORDER, theme.C.CYAN)
    eq(theme.C.FLASH, theme.C.YELLOW)
    eq(#theme.TETROMINOES, 7)
    for i, t in ipairs(theme.TETROMINOES) do
        assert(#t.rotations >= 1 and t.color, "shape " .. i .. " needs rotations and a colour")
    end
end

function T.centre_draws_transparent_centred_text()
    local fake = stub.new()
    local theme = stub.fresh("theme")
    theme.centre("ABCD", 50, 7)
    local t = fake.texts[1]
    eq(t.x, 144)   -- (320 - 4 * 8) / 2
    eq(t.y, 50)
    eq(t.text, "ABCD")
    eq(t.fg, 7)
    eq(t.bg, false)
end

stub.run(T)
