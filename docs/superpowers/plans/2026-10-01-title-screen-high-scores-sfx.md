# block.exe title screen, high scores and sound effects: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** block.exe opens on an animated title screen with a top-3 high-score table, takes a name for a top-3 score, plays Comfy Cloud-generated synthwave sound effects, streams its music as QOA, and remembers MUSIC/SFX settings.

**Architecture:**
- `main.lua` keeps the existing game and gains a four-state machine (`title`, `playing`, `gameover`, `name_entry`), plus the music, the settings and the F10 menu.
- New modules, each with one job:
  - `theme.lua`: colours and shapes.
  - `highscores.lua`: the score table.
  - `sfx.lua`: one function per sound event.
  - `title.lua`: the title screen.
  - `name_entry.lua`: the game-over and name-entry panels.
- The modules are pure Lua over the `picocalc` API, and each is tested on the host against a fake `picocalc`.
- Sound effects are generated in Comfy Cloud. A stdlib-only Python tool, `tools/build_sfx.py`, turns the chosen generations into game-ready WAVs.

**Tech stack:**
- Lua 5.4 on PicoDeck firmware 0.5.0+ (32-bit integers, single-precision floats), using the native `require`.
- Host tests: `lua` 5.4 and `luac`.
- Python 3 (standard library only) for the sound tool, tested with `unittest`.
- `ffmpeg` and `qoaconv` for audio conversion.
- MCP servers: Comfy Cloud for sound effects, PixelLab for art, and picodeck for the simulator.

**Spec:** `docs/superpowers/specs/2026-10-01-title-screen-high-scores-design.md`. Read it before starting any task. Where this plan and the spec disagree, the spec wins, and you stop and say so.

## Global constraints

**Firmware, platform and paths:**
- `app.json`: `"min_firmware": "0.5.0"`. The app id is `net.picodeck.blockexe`.
- The screen is 320×320. Built-in fonts are `pc.display.FONT_6X8` and `pc.display.FONT_8X12`, ASCII only. `pc.display.setFont` is global state, so always set it back to `FONT_6X8` before the game draws.
- Text over art is drawn with a literal `false` as the background argument: `pc.display.drawText(x, y, text, fg, false)`.
- Paths are absolute and built from `APP_DIR`. The `io` and `os` libraries don't exist on the device.
- Lua integers are 32-bit on the device. Colours must be integers, from `pc.display.rgb`.

**Saved data:**
- High scores: `pc.game.save.set("highscores", { version = 1, last_name = ..., entries = {...} })`, at most 3 entries.
- Settings: `pc.config` keys `music` and `sfx`, values `"on"` or `"off"`. A missing key, or any value other than `"off"`, means on.

**Input:**
- F10 callbacks only set flags, and there are at most 4 F10 menu items.
- Every state change calls `pc.input.clearState()`.
- Name entry takes letters only from `"char"` events. Enter and Backspace come from `"down"` events with `ev.button`, and Esc from `getButtonsPressed()`.

**Audio:**
- Music: `assets/background01.qoa` through `pc.sound.fileplayer()`, with `play(0)` and volume 60.
- Sound effects: 22.05 kHz 16-bit mono WAV, at most 65536 bytes of PCM each, played at volume 90 through a pool of at most 6 sample players.

**Tooling and conventions:**
- Python tools use only the standard library. `ffmpeg`, `qoaconv` and Pillow are for one-off asset conversion only.
- Host tests run from the repo root with `sh tests/run.sh`.
- Commit messages follow the existing style (`feat:`, `fix:`, `docs:`, `chore:`, `test:`). Match the existing comment style: short `--` comments, only where they help.

## Review focus

These are inputs the spec implies but no task's normal tests would catch. Each is pinned by a test in the task that owns the code.

1. **Keys held or mashed through the game-over transition** (a hard-drop Enter still repeating, a held Esc) must not confirm or skip the name entry. Pinned by Task 4 `held_enter_during_lock_cannot_save` and `lock_ignores_input_for_400ms`.
2. **Keys held during name entry:**
   - letters stop at 8 characters, with no sound past the cap
   - Backspace on an empty name is silent
   - a held Backspace keeps deleting

   Pinned by Task 4 `name_stops_at_8_with_no_extra_sound`, `backspace_on_empty_is_silent` and `held_backspace_repeats`.
3. **A burst of sounds** (fast moves, a rotate, a hard drop, a Tetris and a level-up in one moment) needs more players than the pool has. The newest sound still plays, the earliest-started player is taken over, and nothing errors. Pinned by Task 3 `all_busy_takes_over_earliest`.
4. **Damaged or foreign saved data:** another app's `highscores.json`, a hand-edited file, or a config value other than `"on"`/`"off"` gives defaults, never a crash. Pinned by Task 2 `bad_data_loads_as_empty_or_skips_rows`, and by Task 6 Step 9, a simulator check with a garbage `config.json`.
5. **A missing asset** after an interrupted copy (the background, logo, a sound effect, or the QOA music) leaves the app running with a fallback. Pinned by Task 3 `missing_sound_is_silent`, Task 5 `missing_images_fall_back`, and Task 6 Step 10, a simulator check without the QOA.

---

## Before you start (human steps)

Do these once, in order. Ask the user to approve each item that changes their configuration.

1. **Branch.** The spec and this plan are on `docs/title-screen-music-handover`. Create the feature branch from it:
   ```bash
   cd /home/keith/Projects/PicoDeck/blockexe
   git switch -c feat/title-screen-sfx docs/title-screen-music-handover
   ```
2. **Simulator.** Build it with `make -C /home/keith/Projects/PicoDeck/picodeck simulator`. The binary is `picodeck/build_sim/picodeck_simulator`.
3. **picodeck MCP server for this folder** (user approval needed; this edits `~/.claude.json`):
   ```bash
   claude mcp add --scope local picodeck -- python3 /home/keith/Projects/PicoDeck/picodeck/tools/picodeck_mcp.py
   ```
   Then run `/mcp` (or restart Claude Code), and check that `picodeck` tools such as `start_simulator`, `push_app`, `launch_app`, `keypress` and `screenshot` are listed.
4. **PixelLab MCP server for this folder** (user approval needed; only needed for Task 10). The working entry lives under the old project path in `~/.claude.json`. Copy it without printing the API key:
   ```bash
   python3 - <<'EOF'
   import json, pathlib
   p = pathlib.Path.home() / ".claude.json"
   d = json.loads(p.read_text())
   src = d["projects"]["/home/keith/Projects/picos-blockexe"]["mcpServers"]["pixellab"]
   d["projects"].setdefault("/home/keith/Projects/PicoDeck/blockexe", {}).setdefault("mcpServers", {})["pixellab"] = src
   p.write_text(json.dumps(d, indent=2))
   print("pixellab copied")
   EOF
   ```
   Then run `/mcp` and check that the PixelLab tools appear.
5. **Comfy Cloud** is already connected. If a call asks for sign-in, run `/mcp` (needed for Task 8).

### Simulator routine

Tasks 1, 6, 8, 10 and 11 refer to this routine.

- **Stage the app:** `sh tools/stage.sh`. This copies only the shipped files into `build/stage/`.
- **Start the simulator:** the picodeck MCP `start_simulator()`. It's headless by default, so pass `headless=false` when a person needs to hear audio.
- **Install and launch:**
  - `push_app(local_dir="/home/keith/Projects/PicoDeck/blockexe/build/stage", app_name="blockexe")`. This copies into `picodeck/apps/blockexe/`, which is untracked in the picodeck repo; leave it there.
  - `launch_app(app_name="net.picodeck.blockexe")`.
- **Drive it:** `keypress(key=...)` accepts `up down left right enter esc backspace f10` and single letters. Use `keypress(key="enter", count=5, delay_ms=150)` to repeat.
- **To top out a game,** hard-drop in bursts of `keypress(key="enter", count=5, delay_ms=150)`, taking a screenshot after each burst. Stop as soon as the game-over panel shows: an Enter that arrives after the panel's 400 ms input lock acts on the panel, and saves a pre-filled name or closes a plain game over.
- **Look:** `screenshot(save_path="build/shots/<name>.png")`, then read the PNG. `get_log_buffer()` shows `pc.sys.log` lines, which are prefixed `[APP]`.
- **The app's saved data** is at `/home/keith/Projects/PicoDeck/picodeck/data/net.picodeck.blockexe/` (`saves/highscores.json` and `config.json`).
- **Stop:** `exit_app()` before pushing a new build.

## File map

| File | Status | Responsibility |
|---|---|---|
| `main.lua` | modify | State machine, the existing game (with its sound-effect calls), music, settings, F10 menu, startup |
| `theme.lua` | create | `C` colours, `TETROMINOES`, and `centre(text, y, colour)` |
| `highscores.lua` | create | Top-3 table, name rules, load/save through `pc.game.save` |
| `sfx.lua` | create | Loads 14 WAVs, runs the player pool, one function per event |
| `title.lua` | create | Title animation, drawing and menu input |
| `name_entry.lua` | create | Game-over and name-entry panels: lock, typing, drawing |
| `assets/background01.qoa` | create | Music (from `background01.mp3`) |
| `assets/sfx/*.wav` | create | 14 built sound effects |
| `assets/title_bg.png`, `assets/logo.png` | create | Title art |
| `tools/stage.sh` | create | Copies the shipped files into a folder (simulator and CI) |
| `tools/build_sfx.py` | create | Builds `assets/sfx/` from `tools/sfx_src/` |
| `tools/sfx_src/manifest.json`, `tools/sfx_src/*.wav` | create | Chosen sound sources and where they came from |
| `tests/stub.lua` | create | Fake `picocalc` and a tiny test runner |
| `tests/run.sh` | create | `luac -p` on every module, then every host test |
| `tests/*_test.lua`, `tests/test_build_sfx.py` | create | Host tests |
| `.gitignore` | modify | `build/`, `tools/sfx_src/candidates/` |
| `app.json`, `README.md`, `.github/workflows/build.yml` | modify | Firmware floor, version, docs, packaging |

---

### Task 1: Test harness, staging script and `theme.lua`

**Files:**
- Create: `tests/stub.lua`, `tests/run.sh`, `tests/theme_test.lua`, `theme.lua`, `tools/stage.sh`
- Modify: `main.lua:1-55` (header, colour table and shape table), `app.json` (`min_firmware`), `.gitignore`

**Interfaces:**
- Produces:
  - `require("theme")` → `{ C = table<string, integer>, TETROMINOES = { {rotations = {{{x,y}×4}…}, color = integer}×7 }, centre = function(text: string, y: integer, colour: integer) }`
  - `tests/stub.lua`:
    - `stub.new() → fake`, which installs the globals `picocalc` and `APP_DIR = "/apps/blockexe"`
    - `stub.fresh(name, preload?) → module`
    - `stub.eq(actual, expected, msg?)`
    - `stub.run(tests)`
  - `fake` recorder fields: `now, logs, saves, events, pressed, clears, files, images, players, max_players, played, texts, drawn, save_get_error, save_set_error`
  - `sh tools/stage.sh [dir]` stages into `build/stage` by default.

- [ ] **Step 1: Write the test helper `tests/stub.lua`**

```lua
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
```

- [ ] **Step 2: Write `tests/run.sh`**

```sh
#!/bin/sh
# Syntax-checks every app module, then runs the host tests. Exits non-zero on any failure.
cd "$(dirname "$0")/.." || exit 1
status=0
for f in ./*.lua; do
    luac -p "$f" || status=1
done
for t in tests/*_test.lua; do
    echo "== $t"
    lua "$t" || status=1
done
if ls tests/test_*.py >/dev/null 2>&1; then
    echo "== python"
    python3 -m unittest discover -s tests -p 'test_*.py' || status=1
fi
exit $status
```

- [ ] **Step 3: Write the failing test `tests/theme_test.lua`**

```lua
-- Host tests for theme.lua. Run from the repo root: lua tests/theme_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local stub = require("stub")
local eq = stub.eq

local T = {}

function T.colours_and_shapes()
    stub.new()
    local theme = stub.fresh("theme")
    for _, k in ipairs({ "BG", "GRID", "TEXT", "GAMEOVER", "CYAN", "BLUE", "ORANGE", "YELLOW",
                         "GREEN", "PURPLE", "PINK", "WHITE", "RAIN", "PANEL", "BORDER", "DIM", "FLASH" }) do
        assert(math.type(theme.C[k]) == "integer", k .. " should be an integer colour")
    end
    eq(theme.C.BORDER, theme.C.CYAN)
    eq(theme.C.FLASH, theme.C.YELLOW)
    eq(#theme.TETROMINOES, 7)
    for i, t in ipairs(theme.TETROMINOES) do
        assert(#t.rotations >= 1 and t.color, "shape " .. i .. " needs rotations and a colour")
    end
end

function T.centre_draws_transparent_centred_text()
    local fake = stub.new()
    local theme = stub.fresh("theme")
    theme.centre("ABCD", 50, 7)
    local t = fake.texts[1]
    eq(t.x, 144)   -- (320 - 4 * 8) / 2
    eq(t.y, 50)
    eq(t.text, "ABCD")
    eq(t.fg, 7)
    eq(t.bg, false)
end

stub.run(T)
```

- [ ] **Step 4: Run it to see it fail**

Run: `lua tests/theme_test.lua`
Expected: both tests FAIL with `module 'theme' not found`.

- [ ] **Step 5: Create `theme.lua`.** Move the `C` and `TETROMINOES` tables out of `main.lua` unchanged, and add the new colours and `centre`:

```lua
-- Colours, tetromino shapes and a text helper shared by the game and its screens.
local pc = picocalc

-- 80s Neon Colors
local C = {
    BG = pc.display.rgb(10, 0, 20),
    GRID = pc.display.rgb(40, 20, 80),
    TEXT = pc.display.rgb(220, 220, 255),
    GAMEOVER = pc.display.rgb(255, 50, 50),
    -- Piece colors
    CYAN = pc.display.rgb(0, 255, 255),
    BLUE = pc.display.rgb(0, 100, 255),
    ORANGE = pc.display.rgb(255, 150, 0),
    YELLOW = pc.display.rgb(255, 255, 0),
    GREEN = pc.display.rgb(50, 255, 50),
    PURPLE = pc.display.rgb(150, 50, 255),
    PINK = pc.display.rgb(255, 50, 150),
    WHITE = pc.display.rgb(255, 255, 255),
    -- Title screen and panels
    RAIN = pc.display.rgb(0, 110, 130),
    PANEL = pc.display.rgb(8, 0, 18),
    DIM = pc.display.rgb(110, 110, 150),
}
C.BORDER = C.CYAN
C.FLASH = C.YELLOW

-- Tetromino shapes and colors
-- Coordinates are relative to top-left of a 4x4 grid
local TETROMINOES = {
    -- I
    { rotations = { {{0,1},{1,1},{2,1},{3,1}}, {{1,0},{1,1},{1,2},{1,3}} }, color = C.CYAN },
    -- J
    { rotations = { {{0,0},{0,1},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{1,2}}, {{0,1},{1,1},{2,1},{2,2}}, {{1,0},{1,1},{0,2},{1,2}} }, color = C.BLUE },
    -- L
    { rotations = { {{2,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{1,2},{2,2}}, {{0,1},{1,1},{2,1},{0,2}}, {{0,0},{1,0},{1,1},{1,2}} }, color = C.ORANGE },
    -- O
    { rotations = { {{1,1},{2,1},{1,2},{2,2}} }, color = C.YELLOW },
    -- S
    { rotations = { {{1,0},{2,0},{0,1},{1,1}}, {{1,0},{1,1},{2,1},{2,2}} }, color = C.GREEN },
    -- T
    { rotations = { {{1,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{2,1},{1,2}}, {{0,1},{1,1},{2,1},{1,2}}, {{1,0},{0,1},{1,1},{1,2}} }, color = C.PURPLE },
    -- Z
    { rotations = { {{0,0},{1,0},{1,1},{2,1}}, {{2,0},{1,1},{2,1},{1,2}} }, color = C.PINK }
}

-- Draws text centred across the screen in the current font, with no background.
local function centre(text, y, colour)
    local w = pc.display.textWidth(text)
    pc.display.drawText(math.floor((320 - w) / 2), y, text, colour, false)
end

return { C = C, TETROMINOES = TETROMINOES, centre = centre }
```

- [ ] **Step 6: Point `main.lua` at it.**
  - Delete lines 21–55 of `main.lua`: the `-- 80s Neon Colors` table and the `-- Tetromino shapes and colors` table.
  - Directly after `local pc = picocalc -- shorthand for easier access` (line 9), add:

```lua
local theme = require("theme")
local C = theme.C
local TETROMINOES = theme.TETROMINOES
```

- [ ] **Step 7: Raise the firmware floor.** In `app.json`, change `"min_firmware": "0.1.0"` to `"min_firmware": "0.5.0"`, because native `require` needs 0.5.0.

- [ ] **Step 8: Write `tools/stage.sh`**

```sh
#!/bin/sh
# Copies only the files the app ships into a folder (default build/stage), for
# the simulator's push_app and for the release zip.
set -e
cd "$(dirname "$0")/.."
out="${1:-build/stage}"
rm -rf "$out"
mkdir -p "$out"
cp app.json icon.png ./*.lua "$out"/
# The MP3 ships only while main.lua still plays it.
if grep -q 'background01.mp3' main.lua; then cp background01.mp3 "$out"/; fi
if [ -d assets ]; then cp -r assets "$out"/; fi
echo "staged into $out:"
(cd "$out" && find . -type f | sort)
```

- [ ] **Step 9: Ignore build output.** Append to `.gitignore`:

```
build/
tools/sfx_src/candidates/
```

- [ ] **Step 10: Run the host checks**

Run: `sh tests/run.sh`
Expected: `luac -p` prints nothing, `== tests/theme_test.lua` shows `2 passed, 0 failed`, and the exit code is 0.

- [ ] **Step 11: Check the game still plays, using the simulator routine**
  1. `sh tools/stage.sh` lists `./app.json ./background01.mp3 ./icon.png ./main.lua ./theme.lua`.
  2. Start the simulator, push the stage, then launch.
  3. Take a screenshot. The board and the score panel must look as they did before (neon colours, grid).
  4. Run `keypress(key="left")` and `keypress(key="up")`, then take another screenshot. The piece has moved and rotated.
  5. `get_log_buffer()` has no Lua errors.
  6. `exit_app()`.

- [ ] **Step 12: Commit**

```bash
git add theme.lua main.lua app.json tests/stub.lua tests/run.sh tests/theme_test.lua tools/stage.sh .gitignore
git commit -m "refactor: move colours and shapes into theme.lua; add host test harness and staging script"
```

---

### Task 2: `highscores.lua`

**Files:**
- Create: `highscores.lua`
- Test: `tests/highscores_test.lua`

**Interfaces:**
- Consumes: `picocalc.game.save.get/set` and `picocalc.sys.log`.
- Produces:
  - `hs.MAX_NAME` (8)
  - `hs.load()`
  - `hs.entries() → { {name: string, score: integer} … }`, at most 3, highest score first, as a copy
  - `hs.last_name() → string`
  - `hs.qualifies(score) → integer 1..3 | nil`
  - `hs.insert(name, score) → integer rank | nil`. It returns nil if the score doesn't qualify or the name cleans to "".
  - `hs.clean_name(s) → string`
  - `hs.normalize_char(ch) → string | nil`

- [ ] **Step 1: Write the failing tests `tests/highscores_test.lua`**

```lua
-- Host tests for highscores.lua. Run from the repo root: lua tests/highscores_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local stub = require("stub")
local eq = stub.eq

-- A freshly loaded module over a fake whose save holds `saved`.
local function fresh(saved)
    local fake = stub.new()
    fake.saves.highscores = saved
    local hs = stub.fresh("highscores")
    hs.load()
    return hs, fake
end

local function scores(hs)
    local out = {}
    for i, e in ipairs(hs.entries()) do out[i] = e.name .. "=" .. e.score end
    return table.concat(out, ",")
end

local T = {}

function T.empty_table_qualifies_any_positive_score()
    local hs = fresh(nil)
    eq(hs.qualifies(1), 1)
    eq(hs.qualifies(0), nil)
    eq(hs.qualifies(-5), nil)
end

function T.qualifies_while_fewer_than_three()
    local hs = fresh({ entries = { { name = "A", score = 500 }, { name = "B", score = 300 } } })
    eq(hs.qualifies(10), 3)
    eq(hs.qualifies(400), 2)
    eq(hs.qualifies(900), 1)
end

function T.full_table_needs_to_beat_third()
    local hs = fresh({ entries = { { name = "A", score = 500 }, { name = "B", score = 300 },
                                   { name = "C", score = 100 } } })
    eq(hs.qualifies(100), nil)   -- a tie with 3rd doesn't beat it
    eq(hs.qualifies(101), 3)
    eq(hs.qualifies(300), 3)     -- a tie ranks below the existing score
    eq(hs.qualifies(301), 2)
end

function T.insert_keeps_order_and_drops_fourth()
    local hs = fresh(nil)
    eq(hs.insert("ann", 300), 1)
    eq(hs.insert("bob", 500), 1)
    eq(hs.insert("cat", 100), 3)
    eq(scores(hs), "BOB=500,ANN=300,CAT=100")
    eq(hs.insert("dan", 300), 3)  -- ties ANN, so goes below her; CAT drops out
    eq(scores(hs), "BOB=500,ANN=300,DAN=300")
end

function T.insert_refuses_non_qualifying_and_blank_names()
    local hs = fresh({ entries = { { name = "A", score = 500 }, { name = "B", score = 300 },
                                   { name = "C", score = 100 } } })
    eq(hs.insert("zed", 50), nil)
    eq(hs.insert("!!!", 900), nil)
    eq(scores(hs), "A=500,B=300,C=100")
end

function T.insert_saves_table_and_last_name()
    local hs, fake = fresh(nil)
    hs.insert("keith", 12400)
    local saved = fake.saves.highscores
    eq(saved.version, 1)
    eq(saved.last_name, "KEITH")
    eq(#saved.entries, 1)
    eq(saved.entries[1].name, "KEITH")
    eq(saved.entries[1].score, 12400)
    eq(hs.last_name(), "KEITH")
end

function T.saved_data_round_trips()
    local hs = fresh(nil)
    hs.insert("ann", 300)
    hs.insert("bob", 500)
    hs.load()
    eq(scores(hs), "BOB=500,ANN=300")
    eq(hs.last_name(), "BOB")
end

function T.last_name_empty_on_first_run_and_unchanged_without_insert()
    eq(fresh(nil).last_name(), "")
    local hs = fresh({ last_name = "alex", entries = {} })
    eq(hs.last_name(), "ALEX")
    hs.qualifies(999)
    eq(hs.last_name(), "ALEX")
end

function T.bad_data_loads_as_empty_or_skips_rows()
    eq(scores(fresh("nonsense")), "")
    eq(scores(fresh({ entries = "nope" })), "")
    eq(fresh({ last_name = 42 }).last_name(), "")
    local hs = fresh({ entries = {
        { name = "GOOD", score = 50 },
        { name = 7, score = 60 },          -- name not a string
        { name = "!!!", score = 70 },      -- cleans to nothing
        { name = "ZERO", score = 0 },
        { name = "NEG", score = -10 },
        { name = "FRAC", score = 12.5 },
        { name = "STR", score = "900" },
        "not a table",
        { name = "whole", score = 80.0 },  -- a whole float is fine
    } })
    eq(scores(hs), "WHOLE=80,GOOD=50")
end

function T.loading_more_than_three_keeps_the_top_three()
    local hs = fresh({ entries = { { name = "D", score = 10 }, { name = "A", score = 40 },
                                   { name = "C", score = 20 }, { name = "B", score = 30 } } })
    eq(scores(hs), "A=40,B=30,C=20")
end

function T.loaded_ties_keep_their_saved_order()
    local hs = fresh({ entries = { { name = "FIRST", score = 100 }, { name = "SECOND", score = 100 } } })
    eq(scores(hs), "FIRST=100,SECOND=100")
end

function T.clean_name_rules()
    local hs = fresh(nil)
    eq(hs.clean_name("keith"), "KEITH")
    eq(hs.clean_name("a_b!c"), "ABC")
    eq(hs.clean_name("  mr. x-1  "), "MR. X-1")
    eq(hs.clean_name("abcdefghijk"), "ABCDEFGH")
    eq(hs.clean_name("abcdefg hij"), "ABCDEFG")  -- the cap leaves a trailing space, which is trimmed
    eq(hs.clean_name(nil), "")
end

function T.normalize_char_rules()
    local hs = fresh(nil)
    eq(hs.normalize_char("a"), "A")
    eq(hs.normalize_char("Z"), "Z")
    eq(hs.normalize_char("7"), "7")
    eq(hs.normalize_char(" "), " ")
    eq(hs.normalize_char("-"), "-")
    eq(hs.normalize_char("."), ".")
    eq(hs.normalize_char("_"), nil)
    eq(hs.normalize_char("\n"), nil)
    eq(hs.normalize_char("\b"), nil)
    eq(hs.normalize_char("ab"), nil)
end

function T.insert_survives_a_failing_save()
    local hs, fake = fresh(nil)
    fake.save_set_error = "disk full"
    eq(hs.insert("ann", 100), 1)
    eq(scores(hs), "ANN=100")
    assert(fake.logs[1] and fake.logs[1]:find("disk full"), "the failure should be logged")
end

function T.load_survives_a_raising_get()
    local fake = stub.new()
    fake.save_get_error = "boom"
    local hs = stub.fresh("highscores")
    hs.load()
    eq(scores(hs), "")
end

stub.run(T)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/highscores_test.lua`
Expected: every test FAILs with `module 'highscores' not found`.

- [ ] **Step 3: Write `highscores.lua`**

```lua
-- The top-3 high-score table with names, saved with pc.game.save.
local pc = picocalc

local M = {}

M.MAX_NAME = 8
local MAX_ENTRIES = 3
local SAVE_NAME = "highscores"

local entries = {}  -- { name, score }, highest first
local last = ""

-- The uppercase form of an allowed name character (A-Z 0-9 space - .), or nil.
function M.normalize_char(ch)
    if type(ch) ~= "string" or #ch ~= 1 then return nil end
    local up = ch:upper()
    if up:match("^[A-Z0-9 %-%.]$") then return up end
    return nil
end

-- Uppercases, drops disallowed characters, trims both ends and caps at 8.
function M.clean_name(s)
    if type(s) ~= "string" then return "" end
    local out = {}
    for i = 1, #s do
        out[#out + 1] = M.normalize_char(s:sub(i, i))
    end
    local name = table.concat(out):match("^%s*(.-)%s*$")
    return (name:sub(1, M.MAX_NAME):match("^(.-)%s*$"))
end

-- A whole number above 0 as an integer, or nil.
local function whole_positive(v)
    if type(v) ~= "number" then return nil end
    local i = math.tointeger(v)
    if i and i > 0 then return i end
    return nil
end

local function save()
    local list = {}
    for i, e in ipairs(entries) do list[i] = { name = e.name, score = e.score } end
    local ok, res, err = pcall(pc.game.save.set, SAVE_NAME,
        { version = 1, last_name = last, entries = list })
    if not ok then
        pc.sys.log("highscores: save failed: " .. tostring(res))
    elseif res == false then
        pc.sys.log("highscores: save failed: " .. tostring(err))
    end
end

function M.load()
    entries, last = {}, ""
    local ok, data = pcall(pc.game.save.get, SAVE_NAME)
    if not ok or type(data) ~= "table" then return end
    last = M.clean_name(data.last_name)
    if type(data.entries) ~= "table" then return end
    local list = {}
    for i, e in ipairs(data.entries) do
        if type(e) == "table" then
            local name, score = M.clean_name(e.name), whole_positive(e.score)
            if name ~= "" and score then
                list[#list + 1] = { name = name, score = score, order = i }
            end
        end
    end
    -- Highest first; equal scores keep their saved order.
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    for i = 1, math.min(#list, MAX_ENTRIES) do
        entries[i] = { name = list[i].name, score = list[i].score }
    end
end

function M.entries()
    local out = {}
    for i, e in ipairs(entries) do out[i] = { name = e.name, score = e.score } end
    return out
end

function M.last_name() return last end

-- The rank (1-3) a score would take, or nil. A tie ranks below the saved score.
function M.qualifies(score)
    score = whole_positive(score)
    if not score then return nil end
    local rank = 1
    for _, e in ipairs(entries) do
        if e.score >= score then rank = rank + 1 end
    end
    if rank <= MAX_ENTRIES then return rank end
    return nil
end

function M.insert(name, score)
    local rank = M.qualifies(score)
    name = M.clean_name(name)
    if not rank or name == "" then return nil end
    table.insert(entries, rank, { name = name, score = whole_positive(score) })
    while #entries > MAX_ENTRIES do table.remove(entries) end
    last = name
    save()
    return rank
end

return M
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua tests/highscores_test.lua`
Expected: `15 passed, 0 failed`.

- [ ] **Step 5: Run everything**

Run: `sh tests/run.sh`
Expected: exit code 0.

- [ ] **Step 6: Commit**

```bash
git add highscores.lua tests/highscores_test.lua
git commit -m "feat: highscores module for the top-3 table with names"
```

---

### Task 3: `sfx.lua`

**Files:**
- Create: `sfx.lua`
- Test: `tests/sfx_test.lua`

**Interfaces:**
- Consumes:
  - `picocalc.sound.sample(path) → sample | nil, err`
  - `picocalc.sound.sampleplayer() → player | nil, err`, with `player:setSample/setRate/setVolume/play/stop/isPlaying`
  - `picocalc.sys.log`
  - the global `APP_DIR`
- Produces:
  - `sfx.load()`
  - `sfx.set_enabled(on: boolean)`
  - `sfx.ui(name)`, where name is one of `"move" | "select" | "back" | "key" | "delete" | "save"`
  - `sfx.on_move()`, `sfx.on_rotate()`, `sfx.on_hard_drop()` and `sfx.on_lock()`
  - `sfx.on_clear(n: integer)`, `sfx.on_level_up(level: integer)` and `sfx.on_game_over(high_score: boolean)`
  - The sound files are `APP_DIR .. "/assets/sfx/<name>.wav"` for each name in: `ui_move ui_select ui_back key save move rotate hard_drop lock clear tetris level_up game_over high_score`.

- [ ] **Step 1: Write the failing tests `tests/sfx_test.lua`**

```lua
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
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/sfx_test.lua`
Expected: every test FAILs with `module 'sfx' not found`.

- [ ] **Step 3: Write `sfx.lua`**

```lua
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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua tests/sfx_test.lua`
Expected: `10 passed, 0 failed`.

- [ ] **Step 5: Run everything, then commit**

Run: `sh tests/run.sh` (expected exit code 0), then:

```bash
git add sfx.lua tests/sfx_test.lua
git commit -m "feat: sfx module with one function per sound event and a player pool"
```

---

### Task 4: `name_entry.lua`

**Files:**
- Create: `name_entry.lua`
- Test: `tests/name_entry_test.lua`

**Interfaces:**
- Consumes:
  - `theme.C` and `theme.centre` (Task 1)
  - `hs.clean_name`, `hs.normalize_char` and `hs.MAX_NAME` (Task 2)
  - `sfx.ui` (Task 3)
  - from `picocalc`: `pc.input.pollEvent`, `getButtonsPressed`, `clearState`, `BTN_ENTER`, `BTN_ESC` and `BTN_BACKSPACE`, plus `pc.sys.getTimeMs`
- Produces:
  - `name_entry.enter(score: integer, rank: integer|nil, default_name: string)`
  - `name_entry.update(now_ms) → "save", name | "skip" | "continue" | nil`
  - `name_entry.draw()`

- [ ] **Step 1: Write the failing tests `tests/name_entry_test.lua`**

```lua
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
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/name_entry_test.lua`
Expected: every test FAILs with `module 'name_entry' not found`.

- [ ] **Step 3: Write `name_entry.lua`**

```lua
-- The game-over panel, with name entry when the score made the top 3.
local pc = picocalc
local theme = require("theme")
local sfx = require("sfx")
local hs = require("highscores")
local C = theme.C

local M = {}

local LOCK_MS = 400   -- ignore keys this long, so a hard drop's Enter can't confirm
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

    local pressed = pc.input.getButtonsPressed()
    if pressed & pc.input.BTN_ESC ~= 0 then return "skip" end
    if not rank then
        if pressed & pc.input.BTN_ENTER ~= 0 then return "continue" end
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
        theme.centre("ENTER CONTINUE", y + 58, C.DIM)
    end
    d.setFont(d.FONT_6X8)
end

return M
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua tests/name_entry_test.lua`
Expected: `14 passed, 0 failed`.

- [ ] **Step 5: Run everything, then commit**

Run: `sh tests/run.sh` (expected exit code 0), then:

```bash
git add name_entry.lua tests/name_entry_test.lua
git commit -m "feat: game-over panel with locked, keyboard-typed name entry"
```

---

### Task 5: `title.lua`

**Files:**
- Create: `title.lua`
- Test: `tests/title_test.lua`

**Interfaces:**
- Consumes:
  - `theme` (Task 1) and `sfx.ui` (Task 3)
  - from `picocalc`: `pc.graphics.image.load`, `img:getSize/setTransparentColor/draw`, `pc.display.fillVLine/fillRect/drawRect/clear/setFont`, `pc.graphics.fillBorderedRect`, `pc.input.pollEvent/getButtonsPressed` and `pc.sys.getTimeMs/log`
- Produces:
  - `title.load()`
  - `title.enter(flash_rank: integer|nil)`
  - `title.update(dt_ms) → "start" | "toggle_music" | "toggle_sfx" | "quit" | nil`
  - `title.draw(entries, music_on: boolean, sfx_on: boolean)`, where `entries` is `hs.entries()`
  - `title.flashing() → integer|nil`

- [ ] **Step 1: Write the failing tests `tests/title_test.lua`**

```lua
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

function T.animation_runs_for_a_minute()
    local title = fresh()
    for _ = 1, 3600 do title.update(16) end
    title.draw({}, true, true)
end

stub.run(T)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/title_test.lua`
Expected: every test FAILs with `module 'title' not found`.

- [ ] **Step 3: Write `title.lua`**

```lua
-- The title screen: background art, rain and falling pieces, the logo, the
-- top-3 table and the START / MUSIC / SFX / QUIT menu.
local pc = picocalc
local theme = require("theme")
local sfx = require("sfx")
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

    local pressed = pc.input.getButtonsPressed()
    if pressed & pc.input.BTN_ESC ~= 0 then return "quit" end
    if pressed & pc.input.BTN_UP ~= 0 then
        selected = (selected - 2) % #ITEMS + 1
        sfx.ui("move")
    elseif pressed & pc.input.BTN_DOWN ~= 0 then
        selected = selected % #ITEMS + 1
        sfx.ui("move")
    end
    if pressed & pc.input.BTN_ENTER ~= 0 then return ITEMS[selected] end
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
    local flash_on = ((pc.sys.getTimeMs() - flash_start) // FLASH_MS) % 2 == 0
    for i = 1, 3 do
        local e = entries[i]
        local row = string.format("%d. %-8s  %06d", i, e and e.name or "---", e and e.score or 0)
        theme.centre(row, 118 + i * 18, (i == flash_rank and flash_on) and C.FLASH or C.TEXT)
    end

    -- Menu
    local labels = { "START", "MUSIC: " .. (music_on and "ON" or "OFF"),
                     "SFX: " .. (sfx_on and "ON" or "OFF"), "QUIT" }
    for i, label in ipairs(labels) do
        local sel = i == selected
        theme.centre((sel and "> " or "  ") .. label, 216 + (i - 1) * 16, sel and C.WHITE or C.DIM)
    end
    d.setFont(d.FONT_6X8)
end

return M
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua tests/title_test.lua`
Expected: `11 passed, 0 failed`.

- [ ] **Step 5: Run everything, then commit**

Run: `sh tests/run.sh` (expected exit code 0), then:

```bash
git add title.lua tests/title_test.lua
git commit -m "feat: animated title screen with top-3 table and START/MUSIC/SFX/QUIT menu"
```

---

### Task 6: Wire `main.lua`: state machine, settings, QOA music and sound calls

**Files:**
- Modify: `main.lua` (replace the whole file with the version below)
- Create: `assets/background01.qoa`

**Interfaces:**
- Consumes: everything from Tasks 1–5, plus:
  - `pc.sound.fileplayer()` with `:load/:play/:pause/:resume/:setVolume`
  - `pc.config.load/get/set/save`
  - `pc.sys.addMenuItem/clearMenuItems/exit`
  - `pc.display.applyEffect`
  - `pc.graphics.setTransparentColor`
- Produces: the finished app flow. Later tasks only add assets.

- [ ] **Step 1: Convert the music**

```bash
mkdir -p assets
qoaconv background01.mp3 assets/background01.qoa
ls -l assets/background01.qoa
```
Expected: `qoaconv` reports 22050 Hz, 2 channels and about 134 s, and the file is about 2.39 MB.

- [ ] **Step 2: Replace `main.lua` with this file.** The game logic is the existing code with these changes:
  - `game_state` becomes `topped_out`.
  - `particles` and `gravity_timer` are reset in `init_game`.
  - Sound calls are added for moves, rotations, the hard drop, the gravity lock, clears and level-ups.
  - `draw_gameover` is gone.
  - The main loop becomes the state machine.

```lua
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
```

- [ ] **Step 3: Run the host checks**

Run: `sh tests/run.sh`
Expected: exit code 0. In particular, `luac -p ./main.lua` passes.

- [ ] **Step 4: Stage it and check what's included**

Run: `sh tools/stage.sh`
Expected list: `./app.json ./assets/background01.qoa ./highscores.lua ./icon.png ./main.lua ./name_entry.lua ./sfx.lua ./theme.lua ./title.lua`. There's no `background01.mp3`, because `main.lua` no longer mentions it.

- [ ] **Step 5: Simulator walkthrough, part 1: the title screen and settings.** Run the simulator routine with `start_simulator()` (headless), push and launch.
  1. Delete `picodeck/data/net.picodeck.blockexe/saves/highscores.json` and `config.json` first if they exist, so the run starts clean.
  2. Take a screenshot. Expect a plain background with rain and falling pieces, `BLOCK.EXE` as the text logo, the tagline, `HIGH SCORES` with rows `1. ---       000000` to `3.`, and the menu `> START`, `MUSIC: ON`, `SFX: ON`, `QUIT`.
  3. `get_log_buffer()` shows only the expected lines: two `title: failed to load image` lines and 14 `sfx:` lines (the art and sound effects don't exist yet). It has no Lua errors.
  4. Run `keypress("down")` then `keypress("enter")`, and take a screenshot. It shows `MUSIC: OFF`, and `config.json` contains `"music":"off"`.
  5. Run `keypress("enter")` again. It shows `MUSIC: ON`.

- [ ] **Step 6: Simulator walkthrough, part 2: a game and the name entry**
  1. Run `keypress("up")`, `keypress("up")` and `keypress("enter")` to start a game, and take a screenshot.
  2. Top out the game in bursts (see "To top out a game" in the simulator routine).
  3. Take a screenshot. It shows the dimmed board and the `NEW HIGH SCORE! #1` panel with `NAME: [        ]`. The Enters that topped out the stack must **not** have saved anything: `saves/highscores.json` doesn't exist yet.
  4. Now check the lock directly: start another game and top it out, but end with one burst that carries on for at least 300 ms past the top-out. The name-entry panel must still be showing, and the file must be unchanged. (On this first run the name is empty, so a late Enter can't save anything either way.)
  5. Esc back to the title.
  6. Start a game again and top it out in bursts, stopping at the panel.
  7. Run `keypress("k")`, `keypress("e")`, `keypress("i")`, `keypress("t")` and `keypress("h")`, then take a screenshot. It shows `NAME: [KEITH   ]`.
  8. Run `keypress("enter")` and take a screenshot. The title is back, with row 1 `KEITH` in yellow or flashing.
  9. Check that `saves/highscores.json` holds `"last_name":"KEITH"` and one entry with KEITH's score.

- [ ] **Step 7: Simulator walkthrough, part 3: the pre-filled name, editing it, and Esc**
  1. Start a second game and top out in bursts, stopping at the panel. The name field shows `KEITH`.
  2. Run `keypress(key="backspace", count=5)`, then type `alex` and press `enter`. The table shows ALEX at the right rank.
  3. Start a third game. The name field is pre-filled with `ALEX`.
  4. Press `keypress("esc")`. You're back on the title, and the file is unchanged.
  5. Start a game and press `esc` at once. You're back on the title with no new score.

- [ ] **Step 8: Simulator walkthrough, part 4: plain game over, F10, and quitting**
  1. `exit_app()`. Overwrite `saves/highscores.json` with:
     ```json
     {"version":1,"last_name":"KEITH","entries":[{"name":"AAA","score":900000},{"name":"BBB","score":800000},{"name":"CCC","score":700000}]}
     ```
  2. Launch, start a game and top out in bursts, stopping at the panel. The panel shows `GAME OVER`, the score and `ENTER CONTINUE`, with no name field. Press `enter`: you're on the title, which shows AAA/BBB/CCC.
  3. Run `keypress("f10")` and take a screenshot. The OS menu lists *New Game*, *Disable Music* and *Disable Sound Effects*. Choose *New Game* with arrows and `enter`; the game starts.
  4. Top out with a qualifying score: delete `highscores.json` first and relaunch. On the name-entry screen, press `f10` and choose *New Game*. A fresh game starts, and nothing is saved.
  5. Press `f10` and choose *Disable Music*. Esc back to the title; it shows `MUSIC: OFF`.
  6. On the title, press `esc`. The app exits back to the launcher.

- [ ] **Step 9: Simulator walkthrough, part 5: damaged settings (Review focus 4)**
  1. `exit_app()`. Write `config.json` as `{"music":"maybe","sfx":"OFF"}`.
  2. Launch. The title shows `MUSIC: ON` and `SFX: ON`, because only the exact value `"off"` turns a setting off. There are no errors in the log.

- [ ] **Step 10: Simulator walkthrough, part 6: missing music (Review focus 5)**
  1. `exit_app()`. Run `rm build/stage/assets/background01.qoa`, then `push_app` and launch.
  2. The app runs normally, and the log shows `Failed to load music:`.
  3. Run `sh tools/stage.sh` to restore the stage, then push again.

- [ ] **Step 11: Commit**

```bash
git add main.lua assets/background01.qoa
git commit -m "feat: title, game-over and name-entry flow; QOA music; saved MUSIC/SFX settings; sound-effect hooks"
```

---

### Task 7: The sound-effect build tool, `tools/build_sfx.py`

**Files:**
- Create: `tools/build_sfx.py`
- Test: `tests/test_build_sfx.py`

**Interfaces:**
- Produces:
  - `tools/sfx_src/manifest.json`, shaped like `{"sounds": {"<name>": {"source": "<file>.wav", "start_ms": int, "length_ms": int, "fade_ms": int, "gain_db": number, …provenance fields}}}`
  - The provenance fields are `generator`, `model`, `prompt`, `negative_prompt`, `seed`, `generated_seconds`, `date` and `candidate`. They're recorded but not read by the tool.
  - CLI: `python3 tools/build_sfx.py [--preview WAV] [--suggest-start]`
  - Python API, used by the tests and Task 9:
    - `build(src_dir, out_dir) → {name: pcm_bytes}`
    - `write_preview(path, built)`
    - `onset_ms(samples) → int`
    - `edit(samples, entry) → list[float]`
    - `read_source(path) → list[float]`
    - `BuildError`
    - `RATE` (22050), `MAX_BYTES` (65536) and `NAMES`

- [ ] **Step 1: Write the failing tests `tests/test_build_sfx.py`**

```python
"""Host tests for tools/build_sfx.py. Run from the repo root:
python3 -m unittest discover -s tests -p 'test_*.py'"""
import importlib.util
import json
import math
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("build_sfx", ROOT / "tools" / "build_sfx.py")
build_sfx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_sfx)
RATE = build_sfx.RATE


def make_wav(path, seconds, freq=440.0, amp=0.5, rate=RATE, channels=1, lead_silence_ms=0):
    frames = int(seconds * rate)
    lead = int(lead_silence_ms * rate / 1000)
    data = bytearray()
    for i in range(frames):
        v = 0 if i < lead else int(amp * 32767 * math.sin(2 * math.pi * freq * i / rate))
        data += v.to_bytes(2, "little", signed=True) * channels
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(data))


def read_pcm(path):
    with wave.open(str(path), "rb") as w:
        raw = w.readframes(w.getnframes())
    return [int.from_bytes(raw[i:i + 2], "little", signed=True) for i in range(0, len(raw), 2)]


class BuildSfxTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.src = Path(self.tmp.name) / "src"
        self.out = Path(self.tmp.name) / "out"
        self.src.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def manifest(self, sounds):
        (self.src / "manifest.json").write_text(json.dumps({"sounds": sounds}))

    def entry(self, **over):
        e = {"source": "a.wav", "start_ms": 0, "length_ms": 100, "fade_ms": 20, "gain_db": 0}
        e.update(over)
        return e

    def test_cuts_to_length(self):
        make_wav(self.src / "a.wav", 1.0)
        self.manifest({"move": self.entry(length_ms=100)})
        built = build_sfx.build(self.src, self.out)
        self.assertEqual(len(built["move"]), 2 * round(100 * RATE / 1000))
        self.assertTrue((self.out / "move.wav").is_file())

    def test_fade_out_ends_at_zero(self):
        make_wav(self.src / "a.wav", 1.0, freq=100)
        self.manifest({"move": self.entry(fade_ms=30)})
        build_sfx.build(self.src, self.out)
        self.assertEqual(read_pcm(self.out / "move.wav")[-1], 0)

    def test_peak_is_minus_1_dbfs_plus_gain(self):
        make_wav(self.src / "a.wav", 1.0, amp=0.2)
        self.manifest({"move": self.entry(fade_ms=0), "lock": self.entry(fade_ms=0, gain_db=-6)})
        build_sfx.build(self.src, self.out)
        loud = max(abs(s) for s in read_pcm(self.out / "move.wav"))
        quiet = max(abs(s) for s in read_pcm(self.out / "lock.wav"))
        self.assertAlmostEqual(loud, 0.891 * 32767, delta=40)
        self.assertAlmostEqual(quiet / loud, 10 ** (-6 / 20), delta=0.01)

    def test_output_is_22050_mono_16_bit(self):
        make_wav(self.src / "a.wav", 0.5)
        self.manifest({"move": self.entry()})
        build_sfx.build(self.src, self.out)
        with wave.open(str(self.out / "move.wav"), "rb") as w:
            self.assertEqual((w.getframerate(), w.getnchannels(), w.getsampwidth()), (RATE, 1, 2))

    def test_onset_finds_the_sound_after_silence(self):
        make_wav(self.src / "a.wav", 1.0, lead_silence_ms=200)
        samples = build_sfx.read_source(self.src / "a.wav")
        self.assertAlmostEqual(build_sfx.onset_ms(samples), 200, delta=2)

    def test_rejects_wrong_format(self):
        make_wav(self.src / "a.wav", 0.5, rate=44100)
        self.manifest({"move": self.entry()})
        with self.assertRaisesRegex(build_sfx.BuildError, "22050 Hz"):
            build_sfx.build(self.src, self.out)

    def test_rejects_stereo(self):
        make_wav(self.src / "a.wav", 0.5, channels=2)
        self.manifest({"move": self.entry()})
        with self.assertRaisesRegex(build_sfx.BuildError, "mono"):
            build_sfx.build(self.src, self.out)

    def test_rejects_missing_field(self):
        make_wav(self.src / "a.wav", 0.5)
        e = self.entry()
        del e["fade_ms"]
        self.manifest({"move": e})
        with self.assertRaisesRegex(build_sfx.BuildError, "lacks fade_ms"):
            build_sfx.build(self.src, self.out)

    def test_rejects_missing_source(self):
        self.manifest({"move": self.entry(source="nope.wav")})
        with self.assertRaisesRegex(build_sfx.BuildError, "missing source"):
            build_sfx.build(self.src, self.out)

    def test_rejects_unknown_sound(self):
        make_wav(self.src / "a.wav", 0.5)
        self.manifest({"boing": self.entry()})
        with self.assertRaisesRegex(build_sfx.BuildError, "not a sound"):
            build_sfx.build(self.src, self.out)

    def test_rejects_over_64_kb(self):
        make_wav(self.src / "a.wav", 2.0)
        self.manifest({"tetris": self.entry(length_ms=1600)})
        with self.assertRaisesRegex(build_sfx.BuildError, "65536"):
            build_sfx.build(self.src, self.out)

    def test_rejects_a_silent_cut(self):
        make_wav(self.src / "a.wav", 1.0, lead_silence_ms=900)
        self.manifest({"move": self.entry(length_ms=100)})
        with self.assertRaisesRegex(build_sfx.BuildError, "silent"):
            build_sfx.build(self.src, self.out)

    def test_nothing_written_when_any_sound_fails(self):
        make_wav(self.src / "a.wav", 0.5)
        self.manifest({"move": self.entry(), "lock": self.entry(source="nope.wav")})
        with self.assertRaises(build_sfx.BuildError):
            build_sfx.build(self.src, self.out)
        self.assertFalse(self.out.exists() and any(self.out.iterdir()))

    def test_same_inputs_same_bytes(self):
        make_wav(self.src / "a.wav", 1.0)
        self.manifest({"move": self.entry(start_ms=37, gain_db=-3.5)})
        build_sfx.build(self.src, self.out)
        first = (self.out / "move.wav").read_bytes()
        build_sfx.build(self.src, self.out)
        self.assertEqual((self.out / "move.wav").read_bytes(), first)

    def test_preview_joins_sounds_with_gaps(self):
        make_wav(self.src / "a.wav", 1.0)
        self.manifest({"move": self.entry(length_ms=100), "lock": self.entry(length_ms=200)})
        built = build_sfx.build(self.src, self.out)
        preview = Path(self.tmp.name) / "preview.wav"
        build_sfx.write_preview(preview, built, gap_ms=400)
        with wave.open(str(preview), "rb") as w:
            frames = w.getnframes()
        expected = round(100 * RATE / 1000) + round(200 * RATE / 1000) + 2 * round(400 * RATE / 1000)
        self.assertEqual(frames, expected)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

Run: `python3 -m unittest discover -s tests -p 'test_*.py'`
Expected: an error that `tools/build_sfx.py` can't be found.

- [ ] **Step 3: Write `tools/build_sfx.py`**

```python
#!/usr/bin/env python3
"""Build block.exe's sound effects from tools/sfx_src/.

Reads tools/sfx_src/manifest.json, cuts each chosen source WAV to length with a
fade-out, normalises it to -1 dBFS, applies its gain and writes
assets/sfx/<name>.wav as 22.05 kHz 16-bit mono. The firmware keeps only the
first 64 KB of a sample, so a longer result is an error. Standard library only;
the same inputs always give the same bytes.

    python3 tools/build_sfx.py                     build assets/sfx/
    python3 tools/build_sfx.py --preview out.wav   also write every sound into one file
    python3 tools/build_sfx.py --suggest-start     print where each source's sound begins
"""
import argparse
import array
import json
import sys
import wave
from pathlib import Path

RATE = 22050
MAX_BYTES = 65536
PEAK = 10 ** (-1 / 20)   # -1 dBFS
FADE_IN_MS = 2           # only when the cut starts mid-sound
ONSET_DB = -40
EDIT_FIELDS = ("start_ms", "length_ms", "fade_ms", "gain_db")
NAMES = ("ui_move", "ui_select", "ui_back", "key", "save", "move", "rotate",
         "hard_drop", "lock", "clear", "tetris", "level_up", "game_over", "high_score")

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "tools" / "sfx_src"
OUT_DIR = ROOT / "assets" / "sfx"


class BuildError(Exception):
    pass


def read_source(path):
    """A source WAV's samples as floats in -1..1. It must be 22.05 kHz 16-bit mono."""
    path = Path(path)
    if not path.is_file():
        raise BuildError(f"{path.name}: missing source file")
    with wave.open(str(path), "rb") as w:
        fmt = (w.getframerate(), w.getsampwidth(), w.getnchannels())
        if fmt != (RATE, 2, 1):
            raise BuildError(f"{path.name}: must be {RATE} Hz 16-bit mono, "
                             f"not {fmt[0]} Hz {8 * fmt[1]}-bit {fmt[2]}-channel")
        data = array.array("h")
        data.frombytes(w.readframes(w.getnframes()))
    if sys.byteorder == "big":
        data.byteswap()
    return [s / 32768 for s in data]


def edit(samples, entry):
    """Cut, fade and level one sound as its manifest entry says."""
    start = round(entry["start_ms"] * RATE / 1000)
    length = round(entry["length_ms"] * RATE / 1000)
    out = samples[start:start + length]
    if not out:
        raise BuildError("nothing left after the cut")
    fade_in = min(round(FADE_IN_MS * RATE / 1000), len(out)) if start > 0 else 0
    for i in range(fade_in):
        out[i] *= i / fade_in
    fade = min(round(entry["fade_ms"] * RATE / 1000), len(out))
    for i in range(fade):
        out[len(out) - 1 - i] *= i / fade
    peak = max(abs(s) for s in out)
    if peak == 0:
        raise BuildError("the cut is silent")
    scale = PEAK / peak * 10 ** (entry["gain_db"] / 20)
    return [s * scale for s in out]


def onset_ms(samples, threshold_db=ONSET_DB):
    """Where a sound first rises above the threshold, in ms (0 if it never does)."""
    level = 10 ** (threshold_db / 20)
    for i, s in enumerate(samples):
        if abs(s) >= level:
            return round(i * 1000 / RATE)
    return 0


def to_pcm(samples):
    data = array.array("h", (max(-32768, min(32767, round(s * 32767))) for s in samples))
    if sys.byteorder == "big":
        data.byteswap()
    return data.tobytes()


def write_wav(path, pcm):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)


def load_manifest(src_dir):
    path = Path(src_dir) / "manifest.json"
    if not path.is_file():
        raise BuildError(f"{path}: missing manifest")
    sounds = json.loads(path.read_text())["sounds"]
    for name, entry in sounds.items():
        if name not in NAMES:
            raise BuildError(f"{name}: not a sound block.exe plays")
        missing = [k for k in EDIT_FIELDS if k not in entry]
        if missing:
            raise BuildError(f"{name}: manifest entry lacks {', '.join(missing)}")
        if "source" not in entry and "synth" not in entry:
            raise BuildError(f"{name}: manifest entry needs a source or a synth table")
    return sounds


def render(name, entry, src_dir):
    try:
        if "synth" in entry:
            raise BuildError("synth entries need the fallback synthesiser (plan Task 9)")
        return edit(read_source(Path(src_dir) / entry["source"]), entry)
    except BuildError as e:
        raise BuildError(f"{name}: {e}") from None


def build(src_dir=SRC_DIR, out_dir=OUT_DIR):
    """Build every sound in the manifest; nothing is written unless all succeed."""
    built = {}
    for name, entry in sorted(load_manifest(src_dir).items()):
        pcm = to_pcm(render(name, entry, src_dir))
        if len(pcm) > MAX_BYTES:
            raise BuildError(f"{name}: {len(pcm)} bytes of PCM, over the {MAX_BYTES}-byte sample limit")
        built[name] = pcm
    for name, pcm in built.items():
        write_wav(Path(out_dir) / f"{name}.wav", pcm)
    return built


def write_preview(path, built, gap_ms=400):
    """Every built sound in play order, with a gap after each, in one WAV."""
    gap = bytes(2 * round(gap_ms * RATE / 1000))
    write_wav(path, b"".join(built[n] + gap for n in NAMES if n in built))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build block.exe's sound effects from tools/sfx_src/.")
    parser.add_argument("--preview", metavar="WAV", help="also write every sound, one after another, to WAV")
    parser.add_argument("--suggest-start", action="store_true",
                        help="print where each source's sound begins, then stop")
    args = parser.parse_args(argv)
    try:
        if args.suggest_start:
            for name, entry in sorted(load_manifest(SRC_DIR).items()):
                if "source" in entry:
                    print(f"{name}: start_ms {onset_ms(read_source(SRC_DIR / entry['source']))}")
            return 0
        built = build()
        print(f"built {len(built)} sounds into {OUT_DIR.relative_to(ROOT)}")
        missing = [n for n in NAMES if n not in built]
        if missing:
            print("not in the manifest yet: " + ", ".join(missing))
        if args.preview:
            write_preview(args.preview, built)
            print(f"preview: {args.preview}")
        return 0
    except BuildError as e:
        print(f"build_sfx: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `python3 -m unittest discover -s tests -p 'test_*.py' -v`
Expected: `Ran 15 tests … OK`.

- [ ] **Step 5: Run everything, then commit**

Run: `sh tests/run.sh` (expected exit code 0), then:

```bash
chmod +x tools/build_sfx.py
git add tools/build_sfx.py tests/test_build_sfx.py
git commit -m "feat: build_sfx.py turns chosen sound sources into game-ready WAVs"
```

---

### Task 8: Generate and choose the sound effects in Comfy Cloud

This task is interactive. The user picks every sound by ear. Don't choose for them.

**Files:**
- Create: `tools/sfx_src/manifest.json`, `tools/sfx_src/<name>.wav` (14 files), `assets/sfx/<name>.wav` (14 files)
- Scratch (gitignored): `tools/sfx_src/candidates/<name>/`

**Interfaces:**
- Consumes: `tools/build_sfx.py` (Task 7) and the sound names from Task 3.
- Produces: the 14 `assets/sfx/*.wav` files that `sfx.lua` loads.

**The sounds.** "Gen s" is the length to generate: ElevenLabs needs at least 0.5 s, and Stable Audio at least 1 s. The last three columns are the starting edit values for the manifest.

| name | prompt (append the style suffix) | EL gen s | SA gen s | length_ms | fade_ms | gain_db |
|---|---|---|---|---|---|---|
| ui_move | tiny soft synth UI tick, clean, retro-futuristic interface | 0.5 | 1 | 40 | 10 | -10 |
| ui_select | short bright synth confirm blip, two rising notes, 80s synthwave UI | 0.5 | 1 | 150 | 40 | -6 |
| ui_back | short synth cancel blip, two falling notes | 0.5 | 1 | 150 | 40 | -6 |
| key | very short soft digital keyboard click | 0.5 | 1 | 30 | 8 | -12 |
| save | bright sparkling rising synth arpeggio, success jingle, synthwave | 1.0 | 1 | 600 | 150 | -3 |
| move | tiny quiet digital tick | 0.5 | 1 | 25 | 8 | -14 |
| rotate | short snappy futuristic synth blip | 0.5 | 1 | 60 | 15 | -8 |
| hard_drop | heavy punchy digital impact, sub-bass hit, cyberpunk | 0.5 | 1 | 250 | 80 | -2 |
| lock | soft muted digital thud, block snapping into place | 0.5 | 1 | 100 | 30 | -6 |
| clear | neon laser sweep upward with shimmer and echo, synthwave | 1.0 | 1 | 600 | 200 | -3 |
| tetris | huge synthwave chord stab with electric impact and rising sweep, echo | 1.5 | 2 | 1300 | 300 | 0 |
| level_up | rising synth arpeggio power-up, retro-futuristic | 1.0 | 1 | 600 | 150 | -3 |
| game_over | cyberpunk power-down, descending glitchy synth sweep, system shutdown | 1.5 | 2 | 1200 | 300 | -2 |
| high_score | triumphant synthwave fanfare, bright rising chords | 1.5 | 2 | 1200 | 300 | -1 |

- **Style suffix**, added to every prompt: `, synthwave, cyberpunk, single sound effect, clean, no music bed, no voice`.
- **Negative prompt** (Stable Audio only): `music loop, melody, vocals, speech, hiss, low quality, distorted, reverb wash`.

- [ ] **Step 1: Check the Stable Audio workflow on one sound (a spike).** Load the Comfy Cloud `submit_workflow` tool.
  1. Validate the graph below with `dry_run: true`. Substitute `ui_select`'s prompt, seconds = 1 and seed = 1.
  2. Fix anything it reports. If `stable_audio_3_small_sfx.safetensors` or `t5_base.safetensors` is rejected, try `t5gemma_b_b_ul2.safetensors` as the CLIP.
  3. Then submit it for real. Cost isn't a concern for this user, but the tool's spend gate still needs one explicit yes from the user.
  4. If the run fails or the output is silent or garbage, change `ckpt_name` to `stable-audio-open-1.0.safetensors` (this graph is the known-good Stable Audio Open recipe) and run it again.
  5. Write down which model worked; it goes into the manifest's `model` field. If neither works, use ElevenLabs for all 10 candidates and tell the user.

```json
{
  "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": "stable_audio_3_small_sfx.safetensors"}},
  "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "t5_base.safetensors", "type": "stable_audio"}},
  "3": {"class_type": "CLIPTextEncode", "inputs": {"text": "<prompt + style suffix>", "clip": ["2", 0]}},
  "4": {"class_type": "CLIPTextEncode", "inputs": {"text": "<negative prompt>", "clip": ["2", 0]}},
  "5": {"class_type": "ConditioningStableAudio", "inputs": {"positive": ["3", 0], "negative": ["4", 0], "seconds_start": 0, "seconds_total": 1}},
  "6": {"class_type": "EmptyLatentAudio", "inputs": {"seconds": 1, "batch_size": 1}},
  "7": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "seed": 1, "steps": 50, "cfg": 6, "sampler_name": "dpmpp_3m_sde", "scheduler": "exponential", "positive": ["5", 0], "negative": ["5", 1], "latent_image": ["6", 0], "denoise": 1}},
  "8": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["7", 0], "vae": ["1", 2]}},
  "9": {"class_type": "SaveAudioAdvanced", "inputs": {"audio": ["8", 0], "filename_prefix": "blockexe_sfx/ui_select_sa1", "format": "flac"}}
}
```

- [ ] **Step 2: Generate 10 candidates per sound.** Use `submit_batch` (at most 50 items per call), so 14 sounds × 10 = 140 items in 3 batches: sounds 1–5, 6–10 and 11–14. For each sound, add:
  - **5 ElevenLabs items** `el1` to `el5`:
    ```json
    {"tool": "partner_generate", "type": "audio", "model": "elevenlabs/sound-generation",
     "prompt": "<prompt + style suffix>", "params": {"duration": <EL gen s>, "prompt_influence": <0.3, 0.5, 0.5, 0.7, 0.7>},
     "description": "<name>-el<N>"}
    ```
  - **5 Stable Audio items** `sa1` to `sa5`: `{"tool": "submit_workflow", "workflow": <the Step 1 graph with this sound's prompt, SA gen s and seed N>, "description": "<name>-sa<N>"}`.

  Pass `client_os: "linux"`. The first call returns a spend prompt; relay it to the user once, and re-call with `confirm: true` after their explicit yes. Poll `get_batch_status` until each batch is done. Items in `failed[]` are regenerated once; if they fail again, the sound has fewer candidates.

- [ ] **Step 3: Download and convert.** Load the Comfy Cloud `get_batch_output` tool, and run each batch's download command into `tools/sfx_src/candidates/raw/`. Then convert every file to the format the tool needs:

```bash
cd /home/keith/Projects/PicoDeck/blockexe/tools/sfx_src/candidates
for f in raw/*; do
  base=$(basename "${f%.*}")          # e.g. clear-el3
  name=${base%-*}; tag=${base##*-}    # clear, el3
  mkdir -p "$name"
  ffmpeg -loglevel error -y -i "$f" -ac 1 -ar 22050 -c:a pcm_s16le "$name/$tag.wav"
done
ls */ | head -50
```
Expected: one folder per sound, each with up to 10 files named `el1.wav … sa5.wav`. If the downloaded file names differ from `<name>-<tag>.<ext>`, rename them first to match the batch `description`s.

- [ ] **Step 4: The user picks.** For each sound, give the user this command to play its candidates. They can run it themselves with the `!` prefix.

```bash
! for f in tools/sfx_src/candidates/clear/*.wav; do echo "$f"; pw-play "$f"; sleep 0.4; done
```

  - Ask them to reply in this form: `clear=sa3, tetris=el2, …`.
  - They may hear a sound against the music with `pw-play background01.mp3 &` (stop it with `kill %1`).
  - If no candidate is good enough for a sound, generate up to 10 new ones with an adjusted prompt agreed with the user.
  - If that also fails, mark the sound for the synthesiser fallback (Task 9).

- [ ] **Step 5: Save the chosen sources and the manifest**
  1. Copy each pick: `cp tools/sfx_src/candidates/<name>/<tag>.wav tools/sfx_src/<name>.wav`.
  2. Write `tools/sfx_src/manifest.json` with one entry per sound. Edit values come from the table above; provenance comes from the batch item. Example entry:

```json
{
  "sounds": {
    "clear": {
      "source": "clear.wav",
      "start_ms": 0,
      "length_ms": 600,
      "fade_ms": 200,
      "gain_db": -3,
      "candidate": "sa3",
      "generator": "stable-audio",
      "model": "stable_audio_3_small_sfx.safetensors",
      "prompt": "neon laser sweep upward with shimmer and echo, synthwave, synthwave, cyberpunk, single sound effect, clean, no music bed, no voice",
      "negative_prompt": "music loop, melody, vocals, speech, hiss, low quality, distorted, reverb wash",
      "seed": 3,
      "generated_seconds": 1,
      "date": "2026-10-02"
    }
  }
}
```
  For ElevenLabs picks, use `"generator": "elevenlabs"`, `"model": "elevenlabs/sound-generation"`, `"negative_prompt": null` and `"seed": null`, and add `"prompt_influence"`.

- [ ] **Step 6: Set the start points and build**

```bash
python3 tools/build_sfx.py --suggest-start
```
Copy each printed `start_ms` into its manifest entry, but leave 0 where the onset is under 5 ms. Then:

```bash
python3 tools/build_sfx.py --preview build/sfx_preview.wav
```
Expected: `built 14 sounds into assets/sfx`, with no "not in the manifest yet" line.

- [ ] **Step 7: The user approves the set.** Ask them to listen with `! pw-play build/sfx_preview.wav`, which plays the sounds in play order. Adjust `length_ms`, `fade_ms` and `gain_db` as they ask, then rebuild, until they approve.

- [ ] **Step 8: Hear them in the game.** Stage, push and launch with `start_simulator(headless=false)` so the user can hear. Ask the user to play a short game and check:
  - every sound listed in the spec's "Where the sounds are triggered" plays over the music
  - a Tetris with a level-up doesn't audibly clip
  - turning SFX off on the title silences them all

  Tune `gain_db` (and, if the user asks, the volumes in `sfx.lua`/`main.lua`) until they're happy.

- [ ] **Step 9: Check that builds are repeatable, then commit**

```bash
python3 tools/build_sfx.py && sha256sum assets/sfx/*.wav > /tmp/sfx1 && python3 tools/build_sfx.py && sha256sum assets/sfx/*.wav | diff - /tmp/sfx1 && echo same
sh tests/run.sh
git add tools/sfx_src/manifest.json tools/sfx_src/*.wav assets/sfx/*.wav
git commit -m "feat: 14 synthwave sound effects generated in Comfy Cloud and picked by ear"
```
Expected: `same`, and the tests pass.

---

### Task 9 (only if Task 8 marked a sound for the fallback): Synthesiser fallback in `build_sfx.py`

Skip this task entirely if every sound got a usable generated candidate.

**Files:**
- Modify: `tools/build_sfx.py` (add `synth()`, and change `render()`)
- Test: `tests/test_build_sfx.py` (add `SynthTest`)

**Interfaces:**
- Consumes: Task 7's `edit`, `RATE` and `BuildError`.
- Produces: manifest entries may hold `"synth": {"wave": "saw"|"pulse"|"noise", "notes_hz": [float…], "note_ms": int, "detune_cents"?, "decay_ms"?, "cutoff_start_hz"?, "cutoff_end_hz"?, "echo_ms"?, "echo_feedback"?, "seed"?}` in place of `"source"`.

- [ ] **Step 1: Add the failing tests** to `tests/test_build_sfx.py`, before the `if __name__` line:

```python
class SynthTest(unittest.TestCase):
    PARAMS = {"wave": "saw", "notes_hz": [440, 660], "note_ms": 100, "echo_ms": 50}

    def test_length_covers_notes_and_echo_tail(self):
        out = build_sfx.synth(self.PARAMS)
        self.assertEqual(len(out), 2 * round(100 * RATE / 1000) + 4 * round(50 * RATE / 1000))

    def test_same_params_same_samples(self):
        self.assertEqual(build_sfx.synth(self.PARAMS), build_sfx.synth(self.PARAMS))
        noise = {"wave": "noise", "notes_hz": [1], "note_ms": 50, "seed": 7}
        self.assertEqual(build_sfx.synth(noise), build_sfx.synth(noise))

    def test_not_silent(self):
        for wave_kind in ("saw", "pulse", "noise"):
            out = build_sfx.synth(dict(self.PARAMS, wave=wave_kind))
            self.assertGreater(max(abs(s) for s in out), 0.01, wave_kind)

    def test_synth_entry_builds(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            src.mkdir()
            (src / "manifest.json").write_text(json.dumps({"sounds": {"rotate": {
                "synth": self.PARAMS, "start_ms": 0, "length_ms": 150, "fade_ms": 30, "gain_db": -8}}}))
            built = build_sfx.build(src, Path(tmp) / "out")
            self.assertEqual(len(built["rotate"]), 2 * round(150 * RATE / 1000))
```

- [ ] **Step 2: Run them to see them fail**

Run: `python3 -m unittest discover -s tests -p 'test_*.py'`
Expected: `SynthTest` fails with `AttributeError: … has no attribute 'synth'`, and `test_synth_entry_builds` fails with `synth entries need the fallback synthesiser`.

- [ ] **Step 3: Add `synth()` to `tools/build_sfx.py`.** Put `import math` and `import random` with the other imports, and put this function above `render()`:

```python
def synth(params):
    """A fallback sound: detuned saw/pulse (or noise) notes, each with a decaying
    envelope, through a swept one-pole low-pass, plus an echo."""
    rng = random.Random(params.get("seed", 42))
    kind = params["wave"]
    notes = params["notes_hz"]
    note_len = round(params["note_ms"] * RATE / 1000)
    detune = 2 ** (params.get("detune_cents", 7) / 1200)
    decay = params.get("decay_ms", params["note_ms"]) * RATE / 1000
    c0 = params.get("cutoff_start_hz", 8000)
    c1 = params.get("cutoff_end_hz", c0)
    echo = round(params.get("echo_ms", 0) * RATE / 1000)
    feedback = params.get("echo_feedback", 0.35)
    total = note_len * len(notes) + 4 * echo
    out = [0.0] * total
    for n, f in enumerate(notes):
        for i in range(note_len):
            t = i / RATE
            if kind == "noise":
                v = rng.uniform(-1, 1)
            else:
                v = 0.0
                for ff in (f / detune, f * detune):
                    ph = (ff * t) % 1.0
                    v += 2 * ph - 1 if kind == "saw" else (1.0 if ph < 0.5 else -1.0)
                v /= 2
            out[n * note_len + i] += v * math.exp(-i / decay)
    y = 0.0
    for i in range(total):
        fc = c0 + (c1 - c0) * i / max(1, total - 1)
        y += (1 - math.exp(-2 * math.pi * fc / RATE)) * (out[i] - y)
        out[i] = y
    for i in range(echo, total):
        out[i] += out[i - echo] * feedback
    return out
```

Then replace the body of `render()` with:

```python
def render(name, entry, src_dir):
    try:
        if "synth" in entry:
            return edit(synth(entry["synth"]), entry)
        return edit(read_source(Path(src_dir) / entry["source"]), entry)
    except BuildError as e:
        raise BuildError(f"{name}: {e}") from None
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `python3 -m unittest discover -s tests -p 'test_*.py'`
Expected: `Ran 19 tests … OK`.

- [ ] **Step 5: Fill in the fallback sounds.** For each sound marked in Task 8:
  1. Write a `synth` entry, with no `source` and with `"generator": "synth"`, starting from the spec's description of that sound. For example, `ui_select` could be `{"wave": "saw", "notes_hz": [880, 1320], "note_ms": 70, "cutoff_start_hz": 6000, "cutoff_end_hz": 2500, "echo_ms": 60}`.
  2. Build with `--preview`, and have the user approve it by ear, exactly as in Task 8 Steps 6–8.

- [ ] **Step 6: Commit**

```bash
sh tests/run.sh
git add tools/build_sfx.py tests/test_build_sfx.py tools/sfx_src/manifest.json assets/sfx/*.wav
git commit -m "feat: synthesiser fallback for sounds with no usable generation"
```

---

### Task 10: Title art (PixelLab)

This task is interactive. The user approves the background pick and the logo preview.

**Files:**
- Create: `assets/title_bg.png` (320×320, opaque RGB) and `assets/logo.png` (about 240×48, opaque RGB on the key colour `(0,255,0)`)

**Interfaces:**
- Consumes: `title.lua` loads `APP_DIR .. "/assets/title_bg.png"`, and `logo.png` with colour key `0x07E0`.
- Produces: the two images.

- [ ] **Step 1: Check the tools.** Load the PixelLab MCP tools. If `create_image_pixflux` or `pixelart_workbench` is missing, stop and ask the user; the "Before you start" step 4 may not have taken effect yet. Read each tool's parameter schema, and map the values below onto its real parameter names.

- [ ] **Step 2: Prepare the composition hint**

```bash
mkdir -p build/art
ffmpeg -loglevel error -y -i inspiration.jpg -vf "crop=ih:ih,scale=320:320" build/art/inspiration_320.png
```

- [ ] **Step 3: Generate background candidates.** Use `create_image_pixflux` at 320×320, with no more than 10 generations in total. **Don't** use `create_image_pro`.
  - **Description:** `pixel art rainy cyberpunk city at night, neon signs with no readable text, wet streets reflecting neon, dark quiet sky in the top third, darker calm area in the middle, purple and cyan palette`
  - **Init image:** `build/art/inspiration_320.png`, with init image strength about 50 for some candidates and none for others.

  Save the candidates to `build/art/bg_<n>.png`, show them to the user (read each PNG), and let them pick. Generate more, within the budget of 10, if they ask.

- [ ] **Step 4: Save the background**

```bash
python3 - <<'EOF'
from PIL import Image
im = Image.open("build/art/bg_<n>.png").convert("RGB")
if im.size != (320, 320):
    im = im.resize((320, 320), Image.NEAREST)
im.save("assets/title_bg.png")
print(im.size, im.mode)
EOF
```
Expected: `(320, 320) RGB`.

- [ ] **Step 5: Draw the logo.** Draw it by hand in `pixelart_workbench`. This uses no generations, and the letters are placed by hand so they're guaranteed correct.
  - **Canvas:** 240×48, filled with the key colour `(0,255,0)`.
  - **Text:** `BLOCK.EXE` in block capitals, about 30–36 px tall and centred.
  - **Colour:** a vertical chrome gradient from cyan `(0,255,255)` at the top to pink `(255,50,150)` at the bottom.
  - **Outline:** 1 px of `(20,0,40)` around every letter.
  - **Glow:** a few single glow pixels of `(180,255,255)`.
  - **No** anti-aliasing or semi-transparent pixels. **No** pixel of the art may be exactly `(0,255,0)`.

  Save it to `build/art/logo.png`.

- [ ] **Step 6: Flatten and check the logo**

```bash
python3 - <<'EOF'
from PIL import Image
KEY = (0, 255, 0)
im = Image.open("build/art/logo.png").convert("RGBA")
out = Image.new("RGB", im.size, KEY)
for x in range(im.width):
    for y in range(im.height):
        r, g, b, a = im.getpixel((x, y))
        out.putpixel((x, y), (r, g, b) if a >= 128 else KEY)
keyed = sum(1 for p in out.getdata() if p == KEY)
assert out.width <= 320 and out.height <= 80, out.size
assert 0 < keyed < out.width * out.height, "logo must have both art and key pixels"
out.save("assets/logo.png")
print(out.size, "key pixels:", keyed)
EOF
```

- [ ] **Step 7: The user approves the logo.** Show them `assets/logo.png` and a simulator screenshot of the title (stage, push, launch, screenshot):
  - The logo is centred at y=18, with no green fringe or holes.
  - The background is behind the rain, falling pieces, table and menu, and everything stays readable.
  - The log has no `title:` lines.

  Redo Steps 3–6 as the user asks.

- [ ] **Step 8: Commit**

```bash
git add assets/title_bg.png assets/logo.png
git commit -m "feat: PixelLab title background and hand-drawn BLOCK.EXE logo"
```

---

### Task 11: Packaging, docs, release prep and the final walkthrough

**Files:**
- Modify: `.github/workflows/build.yml`, `README.md`, `app.json`, `docs/handover/2026-09-26-title-screen-and-adaptive-music.md`

**Interfaces:**
- Consumes: `tools/stage.sh` (Task 1) and every asset.
- Produces: a release-ready branch. Tagging and pushing are left to the user.

- [ ] **Step 1: Package with the staging script.** In `.github/workflows/build.yml`, replace the `Package` step's `run:` block with:

```yaml
        run: |
          rm -f picodeck-blockexe-*.zip
          sh tools/stage.sh build/pkg
          (cd build/pkg && zip -9r "$GITHUB_WORKSPACE/picodeck-blockexe-${GITHUB_REF_NAME//\//-}.zip" .)
```

- [ ] **Step 2: Check the zip locally**

```bash
sh tools/stage.sh build/pkg >/dev/null && (cd build/pkg && rm -f ../test.zip && zip -9rq ../test.zip .) && unzip -l build/test.zip
```
Expected entries: `app.json`, `icon.png`, `main.lua`, `theme.lua`, `highscores.lua`, `sfx.lua`, `title.lua`, `name_entry.lua`, `assets/background01.qoa`, `assets/title_bg.png`, `assets/logo.png` and `assets/sfx/` (14 WAVs). There's no `background01.mp3`, `tools/`, `tests/` or `docs/`, and the total is under 3 MB.

- [ ] **Step 3: Update `README.md`**
  - **Build section:** replace it with:

```markdown
## Build

This is a Lua app; there's nothing to compile. `sh tools/stage.sh` copies the files that ship
(`app.json`, `icon.png`, the `.lua` modules and `assets/`) into `build/stage/`; copy that
folder to `/apps/blockexe/` on the SD card, or install through the App Store.

It needs PicoDeck 0.5.0 or later.

To regenerate assets:

- Music: `qoaconv background01.mp3 assets/background01.qoa`
- Sound effects: `python3 tools/build_sfx.py` rebuilds `assets/sfx/` from the chosen
  sources in `tools/sfx_src/` (see `manifest.json` there for where each one came from).
  `--preview out.wav` writes them all into one file to listen to.

Tests: `sh tests/run.sh` (needs `lua` 5.4 and Python 3).
```

  - **Description:** add one line after the opening paragraph: `It has a title screen with a top-3 high-score table and synthwave sound effects.`

- [ ] **Step 4: Check the licences of the generated sounds.** For each generator used in `tools/sfx_src/manifest.json`, find its output terms:
  - **Stable Audio 3:** the licence on the model card. Stable Audio Open 1.0 uses the Stability AI Community License.
  - **ElevenLabs:** the terms for sound-generation output made through Comfy Cloud.

  Use WebSearch or WebFetch for both. Add a `## Credits` section to `README.md` naming each generator and the licence or terms that cover its output. If any terms don't clearly allow a free public app, stop and ask the user before release (spec, "Packaging and release").

- [ ] **Step 5: Bump the version.** In `app.json`, set `"version": "1.1.0"`. `"min_firmware"` is already `"0.5.0"` from Task 1.

- [ ] **Step 6: Mark the handover done.** In `docs/handover/2026-09-26-title-screen-and-adaptive-music.md`, under the Part A update line, add:
  `  - **Implemented 2026-10 on feat/title-screen-sfx** (version 1.1.0).`

- [ ] **Step 7: Final simulator walkthrough with sound.** The user listens.
  1. Stage, then run `start_simulator(headless=false)`, push and launch.
  2. With the user, check:
     - the title screen with the real art, rain, pieces and logo
     - the menu sounds
     - a full game with every in-game sound
     - a top-3 name entry with key and delete sounds, the save, and the flashing row
     - a plain game over
     - the F10 menu
     - the MUSIC and SFX toggles, and that they're remembered after a relaunch
  3. **Music:** it keeps playing across every screen change. Leave the title open for at least 2.5 minutes and confirm the track loops past its 134 s end.
  4. Take a screenshot of each screen and keep them in `build/shots/` for the user.

- [ ] **Step 8: Device checklist.** Hand this to the user; it needs the real PicoCalc.
  1. Install `build/test.zip`'s contents to `/apps/blockexe/`. The Store won't install it on a `develop` build that reports `0.1.0-N`.
  2. With *Settings → Show FPS* on, the title runs at 30 fps or more with the music playing. If it doesn't, lower `RAIN_COUNT`, then `PIECE_COUNT`, in `title.lua` and recheck.
  3. The colours match the simulator.
  4. The effects are clearly audible over the music, and a Tetris with a level-up doesn't audibly clip.
  5. Scores, the last name and both settings survive a reboot.

- [ ] **Step 9: Run everything and commit**

```bash
sh tests/run.sh
git add .github/workflows/build.yml README.md app.json docs/handover/2026-09-26-title-screen-and-adaptive-music.md
git commit -m "chore: package with stage.sh, document assets and tests, version 1.1.0"
```

  Don't tag or push. Releasing (`git tag v1.1.0 && git push --tags`) is the user's call after the device checklist passes.
