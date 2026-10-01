-- The game-over panel, with name entry when the score made the top 3.
local pc = picocalc
local theme = require("theme")
local sfx = require("sfx")
local pad = require("pad")
local hs = require("highscores")
local C = theme.C

local M = {}

local LOCK_MS = 400   -- ignore keys this long, so a hard drop's key can't confirm
local BLINK_MS = 500

local score, rank = 0, nil
local name = ""
local opened_at = 0
local locked = false

-- rank is 1-3 for a top-3 score (name entry), nil for a plain game over.
function M.enter(new_score, new_rank, default_name)
    score, rank = new_score, new_rank
    name = rank and hs.clean_name(default_name) or ""
    opened_at = pc.sys.getTimeMs()
    locked = true
    pc.input.clearState()
end

-- Returns "save", name | "skip" | "continue" | nil.
function M.update(now_ms)
    if locked then
        if now_ms - opened_at < LOCK_MS then return nil end
        locked = false
        pc.input.clearState()
        return nil
    end

    if pc.input.getButtonsPressed() & pc.input.BTN_ESC ~= 0 then return "skip" end
    if not rank then
        local _, pressed = pad.read()
        if pad.confirmed(pressed) then return "continue" end
        return nil
    end

    -- Letters come from char events; Enter and Backspace from key-down events.
    local ev = pc.input.pollEvent()
    while ev do
        if ev.type == "char" then
            local c = hs.normalize_char(ev.char)
            if c and #name < hs.MAX_NAME then
                name = name .. c
                sfx.ui("key")
            end
        elseif ev.type == "down" and ev.button == pc.input.BTN_BACKSPACE then
            if #name > 0 then
                name = name:sub(1, -2)
                sfx.ui("delete")
            end
        elseif ev.type == "down" and ev.button == pc.input.BTN_ENTER then
            local clean = hs.clean_name(name)
            if clean ~= "" then return "save", clean end
        end
        ev = pc.input.pollEvent()
    end
    return nil
end

function M.draw()
    local d = pc.display
    local h = rank and 124 or 84
    local y = math.floor((320 - h) / 2)
    d.fillRect(40, y, 240, h, C.PANEL)
    d.drawRect(40, y, 240, h, C.BORDER)
    d.setFont(d.FONT_8X12)
    theme.centre("GAME OVER", y + 12, C.GAMEOVER)
    if rank then
        theme.centre("NEW HIGH SCORE! #" .. rank, y + 32, C.FLASH)
        theme.centre(string.format("%06d", score), y + 50, C.TEXT)
        local field = string.format("NAME: [%-8s]", name)
        local x = math.floor((320 - d.textWidth(field)) / 2)
        d.drawText(x, y + 72, field, C.WHITE, false)
        if #name < hs.MAX_NAME and (pc.sys.getTimeMs() // BLINK_MS) % 2 == 0 then
            local cw = d.getFontWidth()
            d.fillRect(x + (7 + #name) * cw, y + 72, cw, d.getFontHeight(), C.WHITE)
        end
        theme.centre("ENTER SAVE   ESC SKIP", y + 98, C.DIM)
    else
        theme.centre(string.format("%06d", score), y + 34, C.TEXT)
        theme.centre(pad.label(pad.A) .. " CONTINUE", y + 58, C.DIM)
    end
    d.setFont(d.FONT_6X8)
end

return M
