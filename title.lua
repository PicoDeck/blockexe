-- The title screen: background art, rain and falling pieces, the logo, the
-- top-3 table and the START / MUSIC / SFX / QUIT menu.
local pc = picocalc
local theme = require("theme")
local sfx = require("sfx")
local pad = require("pad")
local C, TETROMINOES = theme.C, theme.TETROMINOES

local M = {}

local ITEMS = { "start", "toggle_music", "toggle_sfx", "quit" }
local RAIN_COUNT = 40
local PIECE_COUNT = 5
local BLOCK = 8
local FLASH_MS = 300
local LOGO_KEY = 0x07E0  -- pure green, never used in the logo itself

local bg, logo
local rain, pieces = {}, {}
local selected = 1

-- Table rows and menu labels, rebuilt only when what they show changes
local text = { entries = nil, music = nil, sfx = nil, rows = {}, labels = {} }

local function refresh_text(entries, music_on, sfx_on)
    if entries ~= text.entries then
        text.entries = entries
        for i = 1, 3 do
            local e = entries[i]
            text.rows[i] = string.format("%d. %-8s  %06d", i, e and e.name or "---", e and e.score or 0)
        end
    end
    if music_on ~= text.music or sfx_on ~= text.sfx then
        text.music, text.sfx = music_on, sfx_on
        local names = { "START", "MUSIC: " .. (music_on and "ON" or "OFF"),
                        "SFX: " .. (sfx_on and "ON" or "OFF"), "QUIT" }
        for i, name in ipairs(names) do text.labels[i] = { "  " .. name, "> " .. name } end
    end
end
local flash_rank, flash_start = nil, 0

-- A rain streak; `anywhere` scatters it over the screen instead of above it.
local function new_drop(anywhere)
    return {
        x = math.random(0, 319),
        y = anywhere and math.random(0, 319) or -math.random(12, 60),
        len = math.random(6, 12),
        speed = math.random(250, 400),
    }
end

local function new_piece(anywhere)
    local shape = math.random(1, #TETROMINOES)
    return {
        shape = shape,
        rotation = math.random(1, #TETROMINOES[shape].rotations),
        color = TETROMINOES[math.random(1, #TETROMINOES)].color,
        x = math.random(0, 320 - 4 * BLOCK),
        y = anywhere and math.random(-4 * BLOCK, 319) or -4 * BLOCK - math.random(0, 80),
        speed = math.random(15, 40),
    }
end

local function load_image(file)
    local ok, img = pcall(pc.graphics.image.load, APP_DIR .. "/assets/" .. file)
    if ok then return img end
    pc.sys.log("title: " .. tostring(img))
    return nil
end

function M.load()
    bg = load_image("title_bg.png")
    logo = load_image("logo.png")
    if logo then logo:setTransparentColor(LOGO_KEY) end
    rain, pieces = {}, {}
    for i = 1, RAIN_COUNT do rain[i] = new_drop(true) end
    for i = 1, PIECE_COUNT do pieces[i] = new_piece(true) end
end

-- flash_rank: the row saved in the last game (1-3), or nil.
function M.enter(rank)
    flash_rank = rank
    flash_start = pc.sys.getTimeMs()
    selected = 1
end

function M.flashing() return flash_rank end

function M.update(dt_ms)
    local dt = dt_ms / 1000
    for i, r in ipairs(rain) do
        r.y = r.y + r.speed * dt
        if r.y > 320 then rain[i] = new_drop(false) end
    end
    for i, p in ipairs(pieces) do
        p.y = p.y + p.speed * dt
        if p.y > 320 then pieces[i] = new_piece(false) end
    end

    -- Any key press stops the new row flashing.
    local ev = pc.input.pollEvent()
    while ev do
        if ev.type == "down" then flash_rank = nil end
        ev = pc.input.pollEvent()
    end

    if pc.input.getButtonsPressed() & pc.input.BTN_ESC ~= 0 then return "quit" end
    local _, pressed = pad.read()
    if pressed & pad.UP ~= 0 then
        selected = (selected - 2) % #ITEMS + 1
        sfx.ui("move")
    elseif pressed & pad.DOWN ~= 0 then
        selected = selected % #ITEMS + 1
        sfx.ui("move")
    end
    if pad.confirmed(pressed) then return ITEMS[selected] end
    return nil
end

local function draw_rain()
    for _, r in ipairs(rain) do
        local y0 = math.floor(r.y)
        local y1 = y0 + r.len
        if y1 >= 0 and y0 <= 319 then
            pc.display.fillVLine(r.x, math.max(0, y0), math.min(319, y1), C.RAIN)
        end
    end
end

local function draw_pieces()
    for _, p in ipairs(pieces) do
        local top = math.floor(p.y)
        for _, b in ipairs(TETROMINOES[p.shape].rotations[p.rotation]) do
            local y = top + b[2] * BLOCK
            if y >= 0 and y + BLOCK <= 320 then
                pc.graphics.fillBorderedRect(p.x + b[1] * BLOCK, y, BLOCK, BLOCK, p.color, C.BG)
            end
        end
    end
end

-- entries is compared by identity: pass a new table when the scores change
-- (hs.entries() returns a fresh copy).
function M.draw(entries, music_on, sfx_on)
    local d = pc.display
    if bg then bg:draw(0, 0) else d.clear(C.BG) end
    draw_rain()
    draw_pieces()

    if logo then
        local w = logo:getSize()
        logo:draw(math.floor((320 - w) / 2), 18)
    else
        d.setFont(d.FONT_8X12)
        theme.centre("BLOCK.EXE", 34, C.CYAN)
    end
    d.setFont(d.FONT_6X8)
    theme.centre("A CYBERPUNK TETRIMINO GAME", 72, C.TEXT)

    -- Top-3 table
    d.fillRect(60, 110, 200, 80, C.PANEL)
    d.drawRect(60, 110, 200, 80, C.BORDER)
    d.setFont(d.FONT_8X12)
    theme.centre("HIGH SCORES", 116, C.CYAN)
    refresh_text(entries, music_on, sfx_on)
    local flash_on = ((pc.sys.getTimeMs() - flash_start) // FLASH_MS) % 2 == 0
    for i = 1, 3 do
        theme.centre(text.rows[i], 118 + i * 18, (i == flash_rank and flash_on) and C.FLASH or C.TEXT)
    end

    -- Menu, on its own panel so it reads over the art
    d.fillRect(60, 208, 200, 76, C.PANEL)
    d.drawRect(60, 208, 200, 76, C.BORDER)
    for i, label in ipairs(text.labels) do
        local sel = i == selected
        theme.centre(label[sel and 2 or 1], 216 + (i - 1) * 16, sel and C.WHITE or C.DIM)
    end
    d.setFont(d.FONT_6X8)
end

return M
