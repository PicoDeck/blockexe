-- A fake `picocalc` for the host tests, plus a tiny test runner.
-- stub.new() installs a fresh fake as the global `picocalc` (and sets APP_DIR)
-- and returns its recorder table; stub.fresh(name) re-requires an app module.
local stub = {}

local function noop() return 0 end

-- Unknown display and graphics calls do nothing and return 0.
local function permissive(t)
    return setmetatable(t, { __index = function() return noop end })
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

function stub.new()
    local fake = {
        now = 0,          -- what pc.sys.getTimeMs() returns
        logs = {},        -- pc.sys.log messages
        saves = {},       -- pc.game.save store, by name
        events = {},      -- queue that pc.input.pollEvent pops
        pressed = 0,      -- what pc.input.getButtonsPressed() returns
        clears = 0,       -- pc.input.clearState() calls
        files = {},       -- WAV paths pc.sound.sample can load
        images = {},      -- image paths pc.graphics.image.load can load
        players = {},     -- sample players created
        max_players = 8,
        played = {},      -- { path, rate, volume, player } per play()
        texts = {},       -- { x, y, text, fg, bg } per drawText
        rects = {},       -- { kind = "fill"|"draw", x, y, w, h, colour } per fillRect/drawRect
        drawn = {},       -- { path, x, y, key } per image draw
    }

    local pc = {}
    pc.sys = {
        log = function(msg) fake.logs[#fake.logs + 1] = msg end,
        getTimeMs = function() return fake.now end,
    }
    pc.input = {
        BTN_UP = 1, BTN_DOWN = 2, BTN_LEFT = 4, BTN_RIGHT = 8,
        BTN_ENTER = 16, BTN_ESC = 32, BTN_BACKSPACE = 64,
        getButtonsPressed = function() return fake.pressed end,
        pollEvent = function() return table.remove(fake.events, 1) end,
        clearState = function()
            fake.clears = fake.clears + 1
            fake.events = {}
            fake.pressed = 0
        end,
    }
    pc.game = { save = {
        get = function(name)
            if fake.save_get_error then error(fake.save_get_error) end
            return copy(fake.saves[name])
        end,
        set = function(name, tbl)
            if fake.save_set_error then error(fake.save_set_error) end
            assert(type(tbl) == "table", "game.save.set needs a table")
            fake.saves[name] = copy(tbl)
            return true
        end,
    } }
    pc.sound = {
        sample = function(path)
            if fake.files[path] then return { path = path } end
            return nil, "failed to load sample"
        end,
        sampleplayer = function()
            if #fake.players >= fake.max_players then
                return nil, "at most 8 sampleplayers can exist at once"
            end
            local p = { playing = false }
            function p:setSample(s) self.sample = s; return true end
            function p:setRate(r) self.rate = r end
            function p:setVolume(v) self.volume = v end
            function p:play()
                self.playing = true
                fake.played[#fake.played + 1] =
                    { path = self.sample.path, rate = self.rate, volume = self.volume, player = self }
                return true
            end
            function p:stop() self.playing = false end
            function p:isPlaying() return self.playing end
            fake.players[#fake.players + 1] = p
            return p
        end,
    }
    pc.display = permissive({
        FONT_6X8 = 0, FONT_8X12 = 1,
        rgb = function(r, g, b) return r * 65536 + g * 256 + b end,
        textWidth = function(s) return #s * 8 end,
        getFontWidth = function() return 8 end,
        getFontHeight = function() return 12 end,
        fillRect = function(x, y, w, h, colour)
            fake.rects[#fake.rects + 1] = { kind = "fill", x = x, y = y, w = w, h = h, colour = colour }
        end,
        drawRect = function(x, y, w, h, colour)
            fake.rects[#fake.rects + 1] = { kind = "draw", x = x, y = y, w = w, h = h, colour = colour }
        end,
        drawText = function(x, y, text, fg, bg)
            fake.texts[#fake.texts + 1] = { x = x, y = y, text = text, fg = fg, bg = bg }
            return #text * 8
        end,
    })
    pc.graphics = permissive({ image = { load = function(path)
        if not fake.images[path] then error("failed to load image: " .. path) end
        local img = { path = path }
        function img:getSize() return 240, 48 end
        function img:setTransparentColor(c) self.key = c end
        function img:draw(x, y)
            fake.drawn[#fake.drawn + 1] = { path = self.path, x = x, y = y, key = self.key }
        end
        return img
    end } })

    picocalc = pc
    APP_DIR = "/apps/blockexe"
    return fake
end

local APP_MODULES = { "theme", "highscores", "sfx", "title", "name_entry" }

-- Re-requires an app module (and the app modules it requires) against the
-- current fake. `preload` maps module names to stand-ins, e.g. a fake sfx.
function stub.fresh(name, preload)
    for _, m in ipairs(APP_MODULES) do package.loaded[m] = nil end
    for m, mod in pairs(preload or {}) do package.loaded[m] = mod end
    return require(name)
end

function stub.eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "",
            tostring(expected), tostring(actual)), 2)
    end
end

-- Runs every function in `tests` (sorted by name) and exits non-zero on failure.
function stub.run(tests)
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    local failed = 0
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if ok then
            print("PASS " .. name)
        else
            failed = failed + 1
            print("FAIL " .. name .. ": " .. tostring(err))
        end
    end
    print(string.format("%d passed, %d failed", #names - failed, failed))
    os.exit(failed == 0 and 0 or 1)
end

return stub
