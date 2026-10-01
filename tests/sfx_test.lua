-- Host tests for sfx.lua. Run from the repo root: lua tests/sfx_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local stub = require("stub")
local eq = stub.eq

local NAMES = { "ui_move", "ui_select", "ui_back", "key", "save", "move", "rotate",
                "hard_drop", "lock", "clear", "tetris", "level_up", "game_over", "high_score" }

-- A loaded sfx module. opts.missing names sounds whose WAV can't load;
-- opts.max_players caps how many sample players the fake hands out.
local function fresh(opts)
    opts = opts or {}
    local fake = stub.new()
    for _, n in ipairs(NAMES) do
        if not (opts.missing and opts.missing[n]) then
            fake.files[APP_DIR .. "/assets/sfx/" .. n .. ".wav"] = true
        end
    end
    fake.max_players = opts.max_players or 8
    local sfx = stub.fresh("sfx")
    sfx.load()
    return sfx, fake
end

-- The sound name and rate of the n-th play (default: the latest).
local function played(fake, n)
    local p = fake.played[n or #fake.played]
    if not p then return nil end
    return p.path:match("([%w_]+)%.wav$"), p.rate
end

local T = {}

function T.creates_a_pool_of_six()
    local _, fake = fresh()
    eq(#fake.players, 6)
end

function T.events_play_their_sounds()
    local sfx, fake = fresh()
    local cases = {
        { function() sfx.ui("move") end, "ui_move", 1.0 },
        { function() sfx.ui("select") end, "ui_select", 1.0 },
        { function() sfx.ui("back") end, "ui_back", 1.0 },
        { function() sfx.ui("key") end, "key", 1.0 },
        { function() sfx.ui("delete") end, "key", 0.8 },
        { function() sfx.ui("save") end, "save", 1.0 },
        { sfx.on_move, "move", 1.0 },
        { sfx.on_rotate, "rotate", 1.0 },
        { sfx.on_hard_drop, "hard_drop", 1.0 },
        { sfx.on_lock, "lock", 1.0 },
        { function() sfx.on_level_up(2) end, "level_up", 1.0 },
        { function() sfx.on_game_over(false) end, "game_over", 1.0 },
        { function() sfx.on_game_over(true) end, "high_score", 1.0 },
    }
    for _, c in ipairs(cases) do
        for _, p in ipairs(fake.players) do p.playing = false end
        c[1]()
        local name, rate = played(fake)
        eq(name, c[2])
        eq(rate, c[3], c[2] .. " rate")
        eq(fake.played[#fake.played].volume, 90, c[2] .. " volume")
    end
end

function T.clears_pitch_up_and_a_tetris_has_its_own_sound()
    local sfx, fake = fresh()
    local want = { { "clear", 1.0 }, { "clear", 1.19 }, { "clear", 1.41 }, { "tetris", 1.0 } }
    for n = 1, 4 do
        for _, p in ipairs(fake.players) do p.playing = false end
        sfx.on_clear(n)
        local name, rate = played(fake)
        eq(name, want[n][1], "lines " .. n)
        eq(rate, want[n][2], "lines " .. n .. " rate")
    end
    local count = #fake.played
    sfx.on_clear(0)
    eq(#fake.played, count, "no lines, no sound")
end

function T.idle_player_is_used_first()
    local sfx, fake = fresh()
    sfx.on_move()
    sfx.on_rotate()
    eq(fake.played[1].player, fake.players[1])
    eq(fake.played[2].player, fake.players[2])  -- player 1 is still playing
    fake.players[1].playing = false
    sfx.on_lock()
    eq(fake.played[3].player, fake.players[1])
end

function T.all_busy_takes_over_earliest()
    local sfx, fake = fresh()
    for _ = 1, 6 do sfx.on_move() end           -- every player now busy
    sfx.on_clear(4)
    eq(fake.played[7].player, fake.players[1])  -- started earliest
    sfx.on_level_up(2)
    eq(fake.played[8].player, fake.players[2])
    eq((played(fake, 8)), "level_up")
end

function T.smaller_pool_still_works()
    local sfx, fake = fresh({ max_players = 2 })
    eq(#fake.players, 2)
    sfx.on_move()
    sfx.on_rotate()
    sfx.on_lock()
    eq(fake.played[3].player, fake.players[1])
end

function T.no_players_plays_nothing()
    local sfx, fake = fresh({ max_players = 0 })
    sfx.on_move()
    eq(#fake.played, 0)
end

function T.disabled_plays_nothing_and_stops_sounds()
    local sfx, fake = fresh()
    sfx.on_clear(4)
    sfx.set_enabled(false)
    eq(fake.players[1].playing, false)
    sfx.on_move()
    eq(#fake.played, 1)
    sfx.set_enabled(true)
    sfx.on_move()
    eq(#fake.played, 2)
end

function T.missing_sound_is_silent()
    local sfx, fake = fresh({ missing = { clear = true } })
    sfx.on_clear(1)
    eq(#fake.played, 0)
    assert(fake.logs[1] and fake.logs[1]:find("clear"), "the missing file should be logged")
    sfx.on_move()
    eq((played(fake)), "move")
end

function T.unknown_ui_name_is_ignored()
    local sfx, fake = fresh()
    sfx.ui("nope")
    eq(#fake.played, 0)
end

stub.run(T)
