-- Sound effects: one function per menu or game event, played through a small
-- pool of sample players. The adaptive music can reroute these events later.
local pc = picocalc

local M = {}

local POOL_SIZE = 6   -- of the firmware's 8 sample players
local VOLUME = 90     -- the music plays at 60
local FILES = { "ui_move", "ui_select", "ui_back", "key", "save", "move", "rotate",
                "hard_drop", "lock", "clear", "tetris", "level_up", "game_over", "high_score" }
local CLEAR_RATES = { 1.0, 1.19, 1.41 }  -- 1-3 lines; a Tetris has its own sound
local UI = {
    move = { "ui_move" }, select = { "ui_select" }, back = { "ui_back" },
    key = { "key" }, delete = { "key", 0.8 }, save = { "save" },
}

local samples = {}
local pool = {}      -- { player, started }
local enabled = true
local plays = 0      -- counts plays, to find the earliest-started player

function M.load()
    samples, pool, plays = {}, {}, 0
    for _, name in ipairs(FILES) do
        local s, err = pc.sound.sample(APP_DIR .. "/assets/sfx/" .. name .. ".wav")
        if s then
            samples[name] = s
        else
            pc.sys.log("sfx: " .. name .. ": " .. tostring(err))
        end
    end
    for _ = 1, POOL_SIZE do
        local p = pc.sound.sampleplayer()
        if not p then break end
        pool[#pool + 1] = { player = p, started = 0 }
    end
end

local function play(name, rate)
    local sample = samples[name]
    if not enabled or not sample or #pool == 0 then return end
    local slot
    for _, s in ipairs(pool) do
        if not s.player:isPlaying() then slot = s; break end
    end
    if not slot then
        slot = pool[1]
        for _, s in ipairs(pool) do
            if s.started < slot.started then slot = s end
        end
    end
    plays = plays + 1
    slot.started = plays
    slot.player:setSample(sample)
    slot.player:setRate(rate or 1.0)
    slot.player:setVolume(VOLUME)
    slot.player:play(1)
end

function M.set_enabled(on)
    enabled = on
    if not on then
        for _, s in ipairs(pool) do s.player:stop() end
    end
end

function M.ui(name)
    local sound = UI[name]
    if sound then play(sound[1], sound[2]) end
end

function M.on_move() play("move") end
function M.on_rotate() play("rotate") end
function M.on_hard_drop() play("hard_drop") end
function M.on_lock() play("lock") end

function M.on_clear(n)
    if n >= 4 then
        play("tetris")
    elseif n >= 1 then
        play("clear", CLEAR_RATES[n])
    end
end

function M.on_level_up(level) play("level_up") end

function M.on_game_over(high_score)
    play(high_score and "high_score" or "game_over")
end

return M
