-- Block.exe
-- by PicoDeck

local pc = picocalc -- shorthand for easier access
-- pc.perf.setTargetFPS(40)

local theme = require("theme")
local hs = require("highscores")
local sfx = require("sfx")
local title = require("title")
local name_entry = require("name_entry")

local C = theme.C
local TETROMINOES = theme.TETROMINOES

-- App state: "title", "playing", "gameover" or "name_entry"
local state = "title"
local score = 0
local level = 1
local lines_cleared = 0
local topped_out = false

-- Playfield dimensions
local FIELD_WIDTH = 10
local FIELD_HEIGHT = 20
local BLOCK_SIZE = 14

-- Center the playfield on the 320x320 screen
local PLAYFIELD_X = math.floor((320 - (FIELD_WIDTH * BLOCK_SIZE)) / 2)
local PLAYFIELD_Y = math.floor((320 - (FIELD_HEIGHT * BLOCK_SIZE)) / 2)

-- Game variables
local playfield = {}
local current_piece = {}
local next_piece_idx = 0
local gravity_timer = 0
local gravity_speed = 500 -- ms per step down

-- Particle System
local particles = {}

-- Input handling
local last_input_time = 0
local input_delay = 120 -- ms between moves

-- Initialize a new game
function init_game()
    topped_out = false
    score = 0
    level = 1
    lines_cleared = 0
    gravity_speed = 500
    gravity_timer = 0
    particles = {}

    -- Create empty playfield grid (must initialize rows so playfield[y][x] never hits a nil row)
    playfield = {}
    for y = 1, FIELD_HEIGHT do
        playfield[y] = {}
    end
    next_piece_idx = math.random(1, #TETROMINOES)
    spawn_new_piece()
end

-- Select next piece and spawn it at the top
function spawn_new_piece()
    current_piece = {
        shape_idx = next_piece_idx,
        rotation = 1,
        x = math.floor(FIELD_WIDTH / 2) - 1,
        y = 0
    }
    next_piece_idx = math.random(1, #TETROMINOES)

    -- Game over check
    if not is_valid_position(current_piece) then
        topped_out = true
    end
end

-- Check if a piece is in a valid position (not colliding)
function is_valid_position(piece)
    local shape = TETROMINOES[piece.shape_idx]
    local rotation_data = shape.rotations[piece.rotation]

    for _, block in ipairs(rotation_data) do
        local px = piece.x + block[1]
        local py = piece.y + block[2]

        -- Check boundaries
        if px < 0 or px >= FIELD_WIDTH or py < 0 or py >= FIELD_HEIGHT then
            return false
        end

        -- Check collision with existing blocks on playfield
        if playfield[py + 1] and playfield[py + 1][px + 1] then
            return false
        end
    end
    return true
end

-- Lock the current piece into the playfield
function lock_piece()
    local shape = TETROMINOES[current_piece.shape_idx]
    local rotation_data = shape.rotations[current_piece.rotation]

    for _, block in ipairs(rotation_data) do
        local px = current_piece.x + block[1]
        local py = current_piece.y + block[2]
        if py >= 0 then
            playfield[py + 1][px + 1] = shape.color
        end
    end

    clear_full_lines()
    spawn_new_piece()
end

-- Check for and clear completed lines

-- Particle System Functions
-- particles is a flat array: {x, y, vx, vy, life_ms, color, x, y, ...}
-- 6 values per particle. Managed by pc.graphics.updateDrawParticles() in C.
local function create_line_clear_particles(row_y, num_lines)
    -- Intensity scales with the square of the number of lines for a bigger "punch"
    local num_particles = 20 * num_lines * num_lines
    local center_y_px = PLAYFIELD_Y + (row_y - 1) * BLOCK_SIZE
    local speed = 100 + num_lines * 60
    local colors = {C.PINK, C.CYAN, C.WHITE}
    local base = #particles

    for i = 1, num_particles do
        local b = base + (i - 1) * 6
        particles[b + 1] = PLAYFIELD_X + BLOCK_SIZE / 2 + math.random(0, (FIELD_WIDTH - 1) * BLOCK_SIZE)
        particles[b + 2] = center_y_px + (math.random() - 0.5) * num_lines * BLOCK_SIZE
        particles[b + 3] = (math.random() - 0.5) * speed
        particles[b + 4] = (math.random() - 0.5) * speed
        particles[b + 5] = math.random(500, 1000)
        particles[b + 6] = colors[math.random(1, 3)]
    end
end

function clear_full_lines()
    local cleared_rows = {}
    -- First pass: find all full lines
    for y = 1, FIELD_HEIGHT do
        local is_full = true
        for x = 1, FIELD_WIDTH do
            if not playfield[y][x] then
                is_full = false
                break
            end
        end
        if is_full then
            table.insert(cleared_rows, y)
        end
    end

    local lines_cleared_this_turn = #cleared_rows
    if lines_cleared_this_turn > 0 then
        sfx.on_clear(lines_cleared_this_turn)

        -- Create particle explosion centered on the cleared lines
        local total_y = 0
        for _, y_row in ipairs(cleared_rows) do
            total_y = total_y + y_row
        end
        local avg_y_row = total_y / lines_cleared_this_turn
        create_line_clear_particles(avg_y_row, lines_cleared_this_turn)

        -- Second pass: remove the lines (from bottom to top to preserve indices)
        for i = lines_cleared_this_turn, 1, -1 do
            local y_to_remove = cleared_rows[i]
            table.remove(playfield, y_to_remove)
        end

        -- Add new empty lines at the top
        for i = 1, lines_cleared_this_turn do
            local new_row = {}
            for j = 1, FIELD_WIDTH do new_row[j] = nil end
            table.insert(playfield, 1, new_row)
        end

        -- Update score, level, etc.
        local points = {40, 100, 300, 1200}
        score = score + (points[lines_cleared_this_turn] or 1200) * level
        lines_cleared = lines_cleared + lines_cleared_this_turn
        local old_level = level
        level = math.floor(lines_cleared / 10) + 1
        if level > old_level then sfx.on_level_up(level) end
        gravity_speed = 500 - (level - 1) * 40
        if gravity_speed < 50 then gravity_speed = 50 end
    end
end

-- Handle player input
function handle_input()
    local now = pc.sys.getTimeMs()
    if now - last_input_time < input_delay then return end

    local buttons = pc.input.getButtons()
    local moved = false

    if buttons & pc.input.BTN_LEFT ~= 0 then
        current_piece.x = current_piece.x - 1
        if not is_valid_position(current_piece) then
            current_piece.x = current_piece.x + 1
        else
            sfx.on_move()
        end
        moved = true
    elseif buttons & pc.input.BTN_RIGHT ~= 0 then
        current_piece.x = current_piece.x + 1
        if not is_valid_position(current_piece) then
            current_piece.x = current_piece.x - 1
        else
            sfx.on_move()
        end
        moved = true
    end

    if buttons & pc.input.BTN_DOWN ~= 0 then
        current_piece.y = current_piece.y + 1
        if not is_valid_position(current_piece) then
            current_piece.y = current_piece.y - 1
        else
            score = score + 1 -- Small bonus for soft dropping
        end
        moved = true
    end

    local pressed = pc.input.getButtonsPressed()
    if pressed & pc.input.BTN_UP ~= 0 then -- Rotate
        local old_rotation = current_piece.rotation
        current_piece.rotation = current_piece.rotation + 1
        if current_piece.rotation > #TETROMINOES[current_piece.shape_idx].rotations then
            current_piece.rotation = 1
        end
        if not is_valid_position(current_piece) then -- Basic wall kick
            current_piece.x = current_piece.x - 1
            if not is_valid_position(current_piece) then
                current_piece.x = current_piece.x + 2
                if not is_valid_position(current_piece) then
                    current_piece.x = current_piece.x - 1 -- revert
                    current_piece.rotation = current_piece.rotation - 1
                    if current_piece.rotation < 1 then
                        current_piece.rotation = #TETROMINOES[current_piece.shape_idx].rotations
                    end
                end
            end
        end
        if current_piece.rotation ~= old_rotation then sfx.on_rotate() end
        moved = true
    end

    if pressed & pc.input.BTN_ENTER ~= 0 then -- Hard drop
        while is_valid_position(current_piece) do
            current_piece.y = current_piece.y + 1
            score = score + 2 -- Small bonus for hard dropping
        end
        current_piece.y = current_piece.y - 1
        sfx.on_hard_drop()
        lock_piece()
        moved = true
    end

    if moved then last_input_time = now end
end

-- Update game logic (gravity)
function update_game(delta_ms)
    if topped_out then return end

    gravity_timer = gravity_timer + delta_ms
    if gravity_timer >= gravity_speed then
        gravity_timer = 0
        current_piece.y = current_piece.y + 1
        if not is_valid_position(current_piece) then
            current_piece.y = current_piece.y - 1
            sfx.on_lock()
            lock_piece()
        end
    end
end

-- Drawing functions
function draw_block(grid_x, grid_y, color, offset_x, offset_y)
    local px = (offset_x or PLAYFIELD_X) + (grid_x - 1) * BLOCK_SIZE
    local py = (offset_y or PLAYFIELD_Y) + (grid_y - 1) * BLOCK_SIZE
    pc.graphics.fillBorderedRect(px, py, BLOCK_SIZE, BLOCK_SIZE, color, C.GRID)
end

function draw_playfield()
    -- Single C call: draws grid lines + all locked blocks in one pass.
    -- Replaces drawGrid + up to 200 fillBorderedRect calls per frame.
    pc.graphics.drawPlayfield(playfield, PLAYFIELD_X, PLAYFIELD_Y, BLOCK_SIZE, FIELD_WIDTH, FIELD_HEIGHT, C.GRID)
end

function draw_piece(piece)
    local shape = TETROMINOES[piece.shape_idx]
    local rotation_data = shape.rotations[piece.rotation]
    for _, block in ipairs(rotation_data) do
        draw_block(piece.x + block[1] + 1, piece.y + block[2] + 1, shape.color)
    end
end

function draw_ui()
    local ui_x = PLAYFIELD_X + FIELD_WIDTH * BLOCK_SIZE + 15
    pc.display.drawText(ui_x, PLAYFIELD_Y + 10, "SCORE", C.TEXT, C.BG)
    pc.display.drawText(ui_x, PLAYFIELD_Y + 20, string.format("%06d", score), C.TEXT, C.BG)

    pc.display.drawText(ui_x, PLAYFIELD_Y + 50, "LEVEL", C.TEXT, C.BG)
    pc.display.drawText(ui_x, PLAYFIELD_Y + 60, string.format("%02d", level), C.TEXT, C.BG)

    pc.display.drawText(ui_x, PLAYFIELD_Y + 90, "LINES", C.TEXT, C.BG)
    pc.display.drawText(ui_x, PLAYFIELD_Y + 100, string.format("%03d", lines_cleared), C.TEXT, C.BG)

    pc.display.drawText(ui_x, PLAYFIELD_Y + 130, "NEXT", C.TEXT, C.BG)
    local next_shape = TETROMINOES[next_piece_idx]
    local next_rotation = next_shape.rotations[1]
    for _, block in ipairs(next_rotation) do
        draw_block(block[1], block[2] + 1, next_shape.color, ui_x, PLAYFIELD_Y + 140)
    end
end

-- Settings (pc.config keys "music" and "sfx"; anything but "off" means on)
local music_enabled = true
local sfx_enabled = true

local function load_settings()
    pc.config.load()
    music_enabled = pc.config.get("music") ~= "off"
    sfx_enabled = pc.config.get("sfx") ~= "off"
end

local function save_setting(key, on)
    pc.config.set(key, on and "on" or "off")
    if not pc.config.save() then pc.sys.log("settings: save failed") end
end

-- Music state
local music = pc.sound.fileplayer()
local music_loaded = false
local music_started = false

-- Starts, pauses or resumes the track to match music_enabled
local function apply_music()
    if not music_loaded then return end
    if music_enabled then
        if music_started then
            music:resume()
        else
            music:play(0) -- 0 loops until stopped
            music_started = true
        end
    elseif music_started then
        music:pause()
    end
end

-- Initialize music
local function init_music()
    if not music then
        pc.sys.log("Failed to load music: no file player")
        return
    end
    local success, err = music:load(APP_DIR .. "/assets/background01.qoa")
    if not success then
        pc.sys.log("Failed to load music: " .. tostring(err))
        return
    end
    music:setVolume(60)
    music_loaded = true
    apply_music()
end

-- F10 menu callbacks run mid-frame, so they only set flags
local pending_new_game = false
local pending_music_toggle = false
local pending_sfx_toggle = false

-- Refresh menu items to update labels
local function refresh_menu()
    pc.sys.clearMenuItems()
    pc.sys.addMenuItem("New Game", function() pending_new_game = true end)
    pc.sys.addMenuItem(music_enabled and "Disable Music" or "Enable Music",
        function() pending_music_toggle = true end)
    pc.sys.addMenuItem(sfx_enabled and "Disable Sound Effects" or "Enable Sound Effects",
        function() pending_sfx_toggle = true end)
end

local function set_music(on)
    music_enabled = on
    apply_music()
    save_setting("music", on)
    refresh_menu()
end

local function set_sfx(on)
    sfx_enabled = on
    sfx.set_enabled(on)
    save_setting("sfx", on)
    refresh_menu()
end

-- Screens
local title_entries = {}

local function set_state(new_state)
    state = new_state
    pc.input.clearState()
end

local function start_game()
    init_game()
    set_state("playing")
end

local function go_title(flash_rank)
    title_entries = hs.entries()
    title.enter(flash_rank)
    set_state("title")
end

local function end_game()
    local rank = hs.qualifies(score)
    sfx.on_game_over(rank ~= nil)
    name_entry.enter(score, rank, hs.last_name())
    set_state(rank and "name_entry" or "gameover")
end

-- Startup
pc.graphics.setTransparentColor(0) -- a key left by another app would punch holes in the art
load_settings()
hs.load()
sfx.load()
sfx.set_enabled(sfx_enabled)
title.load()
init_music()
refresh_menu()
go_title(nil)
local last_frame_time = pc.sys.getTimeMs()

-- Main loop
while true do
    pc.perf.beginFrame()
    pc.input.update()

    local now = pc.sys.getTimeMs()
    local delta = now - last_frame_time
    last_frame_time = now

    if pending_music_toggle then
        pending_music_toggle = false
        set_music(not music_enabled)
    end
    if pending_sfx_toggle then
        pending_sfx_toggle = false
        set_sfx(not sfx_enabled)
    end
    if pending_new_game then
        pending_new_game = false
        start_game()
    end

    -- Update logic
    if state == "title" then
        local action = title.update(delta)
        if action == "start" then
            sfx.ui("select")
            start_game()
        elseif action == "toggle_music" then
            set_music(not music_enabled)
            sfx.ui("select")
        elseif action == "toggle_sfx" then
            set_sfx(not sfx_enabled)
            sfx.ui("select") -- silent when SFX was just turned off
        elseif action == "quit" then
            pc.sys.exit()
        end
    elseif state == "playing" then
        if pc.input.getButtonsPressed() & pc.input.BTN_ESC ~= 0 then
            sfx.ui("back")
            go_title(nil) -- the game is discarded
        else
            handle_input()
            update_game(delta)
            if topped_out then end_game() end
        end
    else -- "gameover" or "name_entry"
        local action, name = name_entry.update(now)
        if action == "save" then
            local rank = hs.insert(name, score)
            sfx.ui("save")
            go_title(rank)
        elseif action == "skip" then
            sfx.ui("back")
            go_title(nil)
        elseif action == "continue" then
            sfx.ui("select")
            go_title(nil)
        end
    end

    -- Drawing
    if state == "title" then
        title.draw(title_entries, music_enabled, sfx_enabled)
    else
        pc.display.setFont(pc.display.FONT_6X8)
        pc.display.clear(C.BG)
        draw_playfield()
        if state == "playing" then
            draw_piece(current_piece)
        end
        -- Update positions + draw all particles + compact dead ones — single C call
        pc.graphics.updateDrawParticles(particles, delta / 1000)
        draw_ui()
        if state ~= "playing" then
            pc.display.applyEffect("darken", 96)
            name_entry.draw()
        end
    end

    pc.display.flush()
    pc.perf.endFrame()
end
