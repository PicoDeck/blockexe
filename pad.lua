-- pad.lua: the one place that reads the controls.
--
-- Uses the logical gamepad (picocalc.gamepad, rebindable in Settings >
-- Controls) when the firmware has it. Older firmware has no gamepad: there it
-- reads the keys this game used before the gamepad. Esc and the name entry's
-- typing stay on picocalc.input.
--
--   pad.read()            -> held, pressed   masks of pad.* buttons
--   pad.poll(now_ms)      -> this frame's game moves, see below
--   pad.confirmed(pressed) -> A pressed, or Enter (menus), see below
--   pad.label(btn)        -> the name of the key bound to btn, for hints

local input = picocalc.input
local gp = picocalc.gamepad

local M = {}

if gp then
    M.UP, M.DOWN, M.LEFT, M.RIGHT = gp.PAD_UP, gp.PAD_DOWN, gp.PAD_LEFT, gp.PAD_RIGHT
    M.A = gp.PAD_A

    function M.read() return gp.getButtons(), gp.getButtonsPressed() end
    function M.label(btn) return (gp.getLabel(btn) or "?"):upper() end
else
    M.UP, M.DOWN, M.LEFT, M.RIGHT = input.BTN_UP, input.BTN_DOWN, input.BTN_LEFT, input.BTN_RIGHT
    M.A = input.BTN_ENTER

    local names = {
        [M.UP] = "UP", [M.DOWN] = "DOWN", [M.LEFT] = "LEFT", [M.RIGHT] = "RIGHT",
        [M.A] = "ENTER",
    }
    function M.read() return input.getButtons(), input.getButtonsPressed() end
    function M.label(btn) return names[btn] or "?" end
end

-- The game's moves for this frame. Left, right and the soft drop repeat while
-- held, at most once per MOVE_DELAY_MS; rotate (Up) and the hard drop (A) are
-- presses, so the gate must never swallow them.
--   pad.poll(now_ms) -> { left, right, down, rotate, drop } booleans
local MOVE_DELAY_MS = 120
local last_move_ms = 0

function M.poll(now)
    local held, pressed = M.read()
    local act = { rotate = pressed & M.UP ~= 0, drop = pressed & M.A ~= 0,
                  left = false, right = false, down = false }
    if now - last_move_ms >= MOVE_DELAY_MS then
        act.left = held & M.LEFT ~= 0
        act.right = not act.left and held & M.RIGHT ~= 0
        act.down = held & M.DOWN ~= 0
        if act.left or act.right or act.down then last_move_ms = now end
    end
    return act
end

-- Menus take A, or Enter as before the gamepad. Enter counts only when it
-- pressed no gamepad button: a player who bound it to one gets that button's
-- meaning alone. `pressed` is this frame's pad.read() press mask.
function M.confirmed(pressed)
    if pressed & M.A ~= 0 then return true end
    return gp ~= nil and pressed == 0
        and input.getButtonsPressed() & input.BTN_ENTER ~= 0
end

return M
