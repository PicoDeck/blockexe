-- Host tests for pad.lua. Run from the repo root: lua tests/pad_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local stub = require("stub")
local eq = stub.eq

-- A fake gamepad with its own button bits and key labels; nil labels mean unbound.
local function with_gamepad(fake, labels)
    local gp = { PAD_UP = 1, PAD_DOWN = 2, PAD_LEFT = 4, PAD_RIGHT = 8, PAD_A = 16,
                 held = 0, pressed = 0 }
    function gp.getButtons() return gp.held end
    function gp.getButtonsPressed() return gp.pressed end
    function gp.getLabel(btn) return labels[btn] end
    picocalc.gamepad = gp
    return gp
end

local T = {}

function T.without_a_gamepad_it_reads_the_keys()
    local fake = stub.new()
    local pad = stub.fresh("pad")
    eq(pad.A, picocalc.input.BTN_ENTER)
    fake.held, fake.pressed = picocalc.input.BTN_LEFT, picocalc.input.BTN_ENTER
    local held, pressed = pad.read()
    eq(held, picocalc.input.BTN_LEFT)
    eq(pressed, picocalc.input.BTN_ENTER)
    eq(pad.label(pad.A), "ENTER")
    eq(pad.confirmed(pressed), true)
end

function T.with_a_gamepad_it_reads_the_pad_and_follows_labels()
    local fake = stub.new()
    local gp = with_gamepad(fake, { [16] = "z" })
    local pad = stub.fresh("pad")
    eq(pad.A, 16)
    gp.held, gp.pressed = 4, 16
    local held, pressed = pad.read()
    eq(held, 4)
    eq(pressed, 16)
    eq(pad.label(pad.A), "Z", "label follows the binding")
    gp.getLabel = function() return nil end
    eq(pad.label(pad.A), "?", "unbound")
end

function T.enter_confirms_only_when_it_pressed_no_pad_button()
    local fake = stub.new()
    with_gamepad(fake, {})
    local pad = stub.fresh("pad")
    fake.pressed = picocalc.input.BTN_ENTER
    eq(pad.confirmed(0), true, "Enter on a menu")
    eq(pad.confirmed(2), false, "Enter bound to another button is that button alone")
    eq(pad.confirmed(16), true, "A")
    fake.pressed = 0
    eq(pad.confirmed(0), false)
end

stub.run(T)
