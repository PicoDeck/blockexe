-- Host tests for name_entry.lua. Run from the repo root: lua tests/name_entry_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local stub = require("stub")
local eq = stub.eq

-- A fresh module with a fake sfx that records which UI sounds played.
local function fresh()
    local fake = stub.new()
    local ui = {}
    local ne = stub.fresh("name_entry", { sfx = { ui = function(name) ui[#ui + 1] = name end } })
    return ne, fake, ui
end

-- Opens the screen at t=0 and steps past the 400 ms input lock.
local function open(ne, fake, score, rank, default)
    fake.now = 0
    ne.enter(score, rank, default)
    fake.now = 400
    eq(ne.update(fake.now), nil)   -- the frame the lock ends
    fake.now = 416
end

local function char(fake, c) fake.events[#fake.events + 1] = { type = "char", char = c } end
local function down(fake, button, rep)
    fake.events[#fake.events + 1] = { type = "down", button = button, ["repeat"] = rep }
end
local function type_text(fake, s) for i = 1, #s do char(fake, s:sub(i, i)) end end
local function enter_key(fake) down(fake, picocalc.input.BTN_ENTER) end
local function backspace(fake, rep) down(fake, picocalc.input.BTN_BACKSPACE, rep) end

local T = {}

function T.lock_ignores_input_for_400ms()
    local ne, fake = fresh()
    fake.now = 0
    ne.enter(500, 1, "KEITH")
    eq(fake.clears, 1, "enter clears input")
    fake.now = 100
    enter_key(fake)
    fake.pressed = picocalc.input.BTN_ESC
    eq(ne.update(fake.now), nil)
    fake.now = 399
    eq(ne.update(fake.now), nil)
    fake.now = 400
    eq(ne.update(fake.now), nil)
    eq(fake.clears, 2, "the end of the lock clears input again")
    eq(#fake.events, 0)
    fake.now = 416
    eq(ne.update(fake.now), nil, "nothing typed after the lock")
end

function T.held_enter_during_lock_cannot_save()
    local ne, fake = fresh()
    fake.now = 0
    ne.enter(500, 1, "KEITH")
    for t = 50, 350, 50 do
        fake.now = t
        down(fake, picocalc.input.BTN_ENTER, true)
        eq(ne.update(fake.now), nil)
    end
    fake.now = 400
    eq(ne.update(fake.now), nil)
    fake.now = 416
    eq(ne.update(fake.now), nil, "repeats from before the lock ended are gone")
    enter_key(fake)
    local action, name = ne.update(fake.now)
    eq(action, "save")
    eq(name, "KEITH")
end

function T.typing_appends_uppercase_with_a_key_sound()
    local ne, fake, ui = fresh()
    open(ne, fake, 500, 1, "")
    type_text(fake, "ab1")
    enter_key(fake)
    local action, name = ne.update(fake.now)
    eq(action, "save")
    eq(name, "AB1")
    eq(table.concat(ui, ","), "key,key,key")
end

function T.disallowed_characters_are_ignored_silently()
    local ne, fake, ui = fresh()
    open(ne, fake, 500, 1, "")
    type_text(fake, "a_!")
    enter_key(fake)
    local _, name = ne.update(fake.now)
    eq(name, "A")
    eq(#ui, 1)
end

function T.name_stops_at_8_with_no_extra_sound()
    local ne, fake, ui = fresh()
    open(ne, fake, 500, 1, "")
    type_text(fake, "abcdefghij")
    enter_key(fake)
    local _, name = ne.update(fake.now)
    eq(name, "ABCDEFGH")
    eq(#ui, 8)
end

function T.backspace_deletes_with_a_sound()
    local ne, fake, ui = fresh()
    open(ne, fake, 500, 1, "KEITH")
    backspace(fake)
    backspace(fake)
    enter_key(fake)
    local _, name = ne.update(fake.now)
    eq(name, "KEI")
    eq(table.concat(ui, ","), "delete,delete")
end

function T.backspace_on_empty_is_silent()
    local ne, fake, ui = fresh()
    open(ne, fake, 500, 1, "")
    backspace(fake)
    eq(ne.update(fake.now), nil)
    eq(#ui, 0)
end

function T.held_backspace_repeats()
    local ne, fake = fresh()
    open(ne, fake, 500, 1, "KEITH")
    backspace(fake)
    backspace(fake, true)
    backspace(fake, true)
    enter_key(fake)
    local _, name = ne.update(fake.now)
    eq(name, "KE")
end

function T.newline_and_backspace_characters_are_ignored()
    local ne, fake, ui = fresh()
    open(ne, fake, 500, 1, "KEITH")
    char(fake, "\b")
    char(fake, "\n")
    eq(ne.update(fake.now), nil, "a newline character doesn't save")
    enter_key(fake)
    local _, name = ne.update(fake.now)
    eq(name, "KEITH", "a backspace character doesn't delete")
    eq(#ui, 0)
end

function T.enter_with_a_blank_name_does_nothing()
    local ne, fake = fresh()
    open(ne, fake, 500, 1, "")
    type_text(fake, "   ")
    enter_key(fake)
    eq(ne.update(fake.now), nil)
    type_text(fake, "x")
    enter_key(fake)
    local action, name = ne.update(fake.now)
    eq(action, "save")
    eq(name, "X")
end

function T.prefill_is_the_last_name()
    local ne, fake = fresh()
    open(ne, fake, 500, 2, "keith")
    enter_key(fake)
    local _, name = ne.update(fake.now)
    eq(name, "KEITH")
end

function T.esc_skips_name_entry()
    local ne, fake = fresh()
    open(ne, fake, 500, 1, "KEITH")
    fake.pressed = picocalc.input.BTN_ESC
    eq(ne.update(fake.now), "skip")
end

function T.plain_game_over_continues_or_skips()
    local ne, fake = fresh()
    open(ne, fake, 5, nil, "KEITH")
    type_text(fake, "abc")
    enter_key(fake)
    eq(ne.update(fake.now), nil, "no typing on the plain screen")
    fake.pressed = picocalc.input.BTN_ENTER
    eq(ne.update(fake.now), "continue")
    fake.pressed = picocalc.input.BTN_ESC
    eq(ne.update(fake.now), "skip")
end

function T.draw_runs_in_both_modes()
    local ne, fake = fresh()
    open(ne, fake, 12400, 1, "KEITH")
    ne.draw()
    local found = false
    for _, t in ipairs(fake.texts) do
        if t.text == "NAME: [KEITH   ]" then found = true end
    end
    assert(found, "the name field should be drawn padded to 8")
    open(ne, fake, 5, nil, "")
    ne.draw()
end

stub.run(T)
