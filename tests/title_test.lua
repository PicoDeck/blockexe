-- Host tests for title.lua. Run from the repo root: lua tests/title_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local stub = require("stub")
local eq = stub.eq

-- A loaded and entered title with a fake sfx. opts.images makes both images loadable.
local function fresh(opts)
    opts = opts or {}
    local fake = stub.new()
    if opts.images then
        fake.images[APP_DIR .. "/assets/title_bg.png"] = true
        fake.images[APP_DIR .. "/assets/logo.png"] = true
    end
    local ui = {}
    local title = stub.fresh("title", { sfx = { ui = function(n) ui[#ui + 1] = n end } })
    title.load()
    title.enter(opts.flash)
    return title, fake, ui
end

local function press(title, fake, button)
    fake.pressed = button
    local action = title.update(16)
    fake.pressed = 0
    return action
end

local T = {}

function T.enter_starts_from_start()
    local title, fake = fresh()
    eq(press(title, fake, picocalc.input.BTN_ENTER), "start")
end

function T.menu_order_and_wrap()
    local title, fake = fresh()
    local I = picocalc.input
    press(title, fake, I.BTN_DOWN)
    eq(press(title, fake, I.BTN_ENTER), "toggle_music")
    press(title, fake, I.BTN_DOWN)
    eq(press(title, fake, I.BTN_ENTER), "toggle_sfx")
    press(title, fake, I.BTN_DOWN)
    eq(press(title, fake, I.BTN_ENTER), "quit")
    press(title, fake, I.BTN_DOWN)
    eq(press(title, fake, I.BTN_ENTER), "start", "down from QUIT wraps to START")
end

function T.up_from_start_wraps_to_quit()
    local title, fake = fresh()
    press(title, fake, picocalc.input.BTN_UP)
    eq(press(title, fake, picocalc.input.BTN_ENTER), "quit")
end

function T.arrows_play_the_move_sound_and_enter_plays_none()
    local title, fake, ui = fresh()
    press(title, fake, picocalc.input.BTN_DOWN)
    press(title, fake, picocalc.input.BTN_UP)
    press(title, fake, picocalc.input.BTN_ENTER)
    eq(table.concat(ui, ","), "move,move")
end

function T.esc_quits()
    local title, fake = fresh()
    eq(press(title, fake, picocalc.input.BTN_ESC), "quit")
end

function T.entering_again_resets_the_selection()
    local title, fake = fresh()
    press(title, fake, picocalc.input.BTN_DOWN)
    title.enter(nil)
    eq(press(title, fake, picocalc.input.BTN_ENTER), "start")
end

function T.flash_clears_on_a_key_down_only()
    local title, fake = fresh({ flash = 2 })
    eq(title.flashing(), 2)
    fake.events = { { type = "up" }, { type = "char", char = "a" } }
    title.update(16)
    eq(title.flashing(), 2)
    fake.events = { { type = "down", key = 65 } }
    title.update(16)
    eq(title.flashing(), nil)
end

function T.missing_images_fall_back()
    local title, fake = fresh()
    eq(#fake.logs, 2, "both missing images are logged")
    title.draw({}, true, true)
    local found = false
    for _, t in ipairs(fake.texts) do
        if t.text == "BLOCK.EXE" then found = true end
    end
    assert(found, "a text logo replaces the missing image")
end

function T.images_draw_with_the_logo_keyed_and_centred()
    local title, fake = fresh({ images = true })
    title.draw({}, true, true)
    eq(fake.drawn[1].path, APP_DIR .. "/assets/title_bg.png")
    eq(fake.drawn[1].x, 0)
    eq(fake.drawn[2].path, APP_DIR .. "/assets/logo.png")
    eq(fake.drawn[2].x, 40)   -- (320 - 240) / 2
    eq(fake.drawn[2].y, 18)
    eq(fake.drawn[2].key, 0x07E0)
end

function T.score_rows_and_menu_labels()
    local title, fake = fresh()
    title.draw({ { name = "KEITH", score = 12400 }, { name = "ALEXANDR", score = 1234567 } }, false, true)
    local texts = {}
    for _, t in ipairs(fake.texts) do texts[t.text] = true end
    assert(texts["1. KEITH     012400"], "row 1")
    assert(texts["2. ALEXANDR  1234567"], "a 7-digit score just widens the row")
    assert(texts["3. ---       000000"], "an empty slot")
    assert(texts["> START"], "START is selected")
    assert(texts["  MUSIC: OFF"], "music label")
    assert(texts["  SFX: ON"], "sfx label")
end

function T.menu_sits_on_a_panel()
    local title, fake = fresh()
    local C = require("theme").C
    title.draw({}, true, true)
    local fill, border
    for _, r in ipairs(fake.rects) do
        if r.x == 60 and r.y == 208 and r.w == 200 and r.h == 76 then
            if r.kind == "fill" then fill = r.colour else border = r.colour end
        end
    end
    eq(fill, C.PANEL, "panel fill behind the menu")
    eq(border, C.BORDER, "panel border around the menu")
end

function T.repeat_draws_do_not_rebuild_text()
    local title = fresh()
    local entries = { { name = "KEITH", score = 12400 } }
    title.draw(entries, true, true)
    local real_format, calls = string.format, 0
    string.format = function(...) calls = calls + 1; return real_format(...) end
    for _ = 1, 10 do title.draw(entries, true, true) end
    string.format = real_format
    eq(calls, 0, "string.format calls over 10 unchanged frames")
end

function T.text_follows_new_entries_settings_and_selection()
    local title, fake = fresh()
    title.draw({ { name = "KEITH", score = 12400 } }, true, true)
    fake.texts = {}
    title.draw({ { name = "ALEX", score = 500 } }, false, true)
    press(title, fake, picocalc.input.BTN_DOWN)
    title.draw({ { name = "ALEX", score = 500 } }, false, true)
    local texts = {}
    for _, t in ipairs(fake.texts) do texts[t.text] = true end
    assert(texts["1. ALEX      000500"], "new entries are drawn")
    assert(texts["  MUSIC: OFF"], "a changed setting is drawn")
    assert(texts["> MUSIC: OFF"], "the selection marker moves")
    assert(texts["  START"], "START loses the marker")
end

function T.animation_runs_for_a_minute()
    local title = fresh()
    for _ = 1, 3600 do title.update(16) end
    title.draw({}, true, true)
end

stub.run(T)
