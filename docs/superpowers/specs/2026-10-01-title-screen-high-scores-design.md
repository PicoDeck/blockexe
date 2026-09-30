# Title screen, top-3 high scores and sound effects: design

**Date:** 2026-10-01
**Status:** written for review
**Source:** Part A of `docs/handover/2026-09-26-title-screen-and-adaptive-music.md`, where the user approved sections A1–A3. Sound effects and saved settings were added on 2026-10-01, and the user approved that design in chat. Every fact below was checked again against the PicoDeck firmware source (`~/Projects/PicoDeck/picodeck`, `develop` at `094a5b9`) on 2026-10-01.

## Goal

block.exe gets:
- a title screen that shows the top three high scores with names
- name entry when a game ends with a top-3 score, pre-filled with the last name used
- synthwave sound effects for the menus and the game
- MUSIC and SFX settings that are remembered between launches

The game is currently one `main.lua` with no sound effects, and it starts playing as soon as it launches.

## Changes from the handover

The handover was written before the rename and before a full check of the firmware. These points differ from it:

| # | Handover said | Spec says | Why |
|---|---|---|---|
| 1 | `min_firmware` stays `0.1.0`, to be checked | `min_firmware: "0.5.0"` | QOA playback in the FilePlayer (row 5), native `require`, and MP3/sample mixing on hardware all arrived in 0.5.0. Per-app save files and `pc.input.pollEvent` arrived in 0.2.0; on 0.1.0, `pc.game.save` writes to a `/saves/` folder that every app shares. |
| 2 | Read every pending character with `getChar()` each frame | Read characters with `pc.input.pollEvent()` | `getChar()` returns the same character until the next `update()`, so looping over it never ends. `pollEvent()` returns each queued event once, in order. |
| 3 | `"\b"` **or** `BTN_BACKSPACE` deletes | Backspace and Enter come only from character events. Esc comes from `BTN_ESC`. | One key press produces both a character and a button edge, so reading both would delete two characters. |
| 4 | Colour key 0 means "no key" | 0 means "use the global key". The app calls `pc.graphics.setTransparentColor(0)` at startup. | The global key isn't reset between apps. A key left by the previous app could punch holes in the background. |
| 5 | `background01.mp3` "keeps looping, as it does today" through the MP3 player | The same track converted to QOA (`assets/background01.qoa`) and played through `pc.sound.fileplayer()` with `play(0)` | The PicoDeck docs measured 22.05 kHz MP3 making every frame 1.24× (mono) to 2.1× (44.1 kHz stereo) slower. QOA costs 2.4–5.3%. The QOA file is only 11% bigger (2.39 MB against 2.15 MB). This also fixes a bug: `play()` with no argument plays the MP3 once, so the music currently stops after one play. |
| 5a | The `require` shim from nonogram | The firmware's native `require` | Built in since 0.5.0, which is now the minimum. The shim would be dead code. |
| 6 | Trailing spaces trimmed | Leading and trailing spaces trimmed | A leading space would push the name out of line in the score table. |
| 7 | `gameover` → `name_entry` | `playing` goes straight to `gameover` or `name_entry` | The two screens are alternatives, not steps in a sequence. |
| 8 | "Dimmed" board | `pc.display.applyEffect("darken", 96)` over the whole frame, then the panel | This runs in hardware over the whole framebuffer, so it's cheap. |
| 9 | (not covered) | If an image fails to load, the title falls back to the plain background colour and a text logo | A missing asset shouldn't crash the app. |
| 10 | `ENTER save · ESC skip` | `ENTER SAVE   ESC SKIP` | The built-in fonts are ASCII only. |
| 11 | Logo text depends on the final name | `BLOCK.EXE`, confirmed when you review the logo preview | The rename didn't change the app's name. |
| 12 | Tagline *A CYBERPUNK TETRIS CLONE* | *A CYBERPUNK TETRIMINO GAME* | It matches the description changed in `cf09379`, which dropped "Tetris". |
| 13 | Check fps with the game's own `pc.perf.drawFPS()` | Check fps with the OS's *Settings → Show FPS* | v1.0.5 removed the in-game counter. PicoDeck 0.5.0 shows one for every app, counting `pc.perf.endFrame()` ticks. |
| 14 | No sound effects: MP3 and samples conflict on hardware | Synthwave sound effects for menus and gameplay, through an `sfx` module | Since 0.5.0, samples and music play through one mixer. The user asked for effects on 2026-10-01. |
| 15 | Menu START / MUSIC / QUIT; nothing saved; no Options item | Menu START / MUSIC / SFX / QUIT; both settings saved with `pc.config` | A second audio setting was added. `pc.config` has room for four keys and saves atomically, and only two are used. The high scores stay in `pc.game.save`. |

## Screens and flow

```
launch ─► title ─START─► playing ─top out, top 3─► name_entry ─ENTER─► title (new row flashes)
                            │                          └─ESC────────► title (nothing saved)
                            ├─top out, not top 3─► gameover ─ENTER/ESC─► title
                            └─ESC─► title (game discarded)
          title ─ESC or QUIT─► exit
```

- The app opens on the title screen, not in a game.
- **Esc exits the app only from the title screen.** Anywhere else it goes back to the title.
  - During a game, the game is discarded and no score is recorded.
  - On the name-entry screen, Esc skips saving.
- **F10 menu:** *New Game*, *Enable/Disable Music* and *Enable/Disable Sound Effects*, using 3 of the 4 slots.
  - Callbacks run at an arbitrary point in the Lua code, so each one only sets a flag: `pending_new_game`, `pending_music_toggle` or `pending_sfx_toggle`.
  - The main loop handles these flags at the top of the next frame.
  - *New Game* starts a fresh game from any screen. An unsaved name entry is dropped.
- **Every state change** calls `pc.input.clearState()`. This clears button edges, the `pollEvent` queue and the `getChar` backlog, so a key press can't carry over from one screen to the next.

## Music and settings

- **Music:**
  - `music = pc.sound.fileplayer()`, `music:load(APP_DIR .. "/assets/background01.qoa")`, `music:setVolume(60)`. It loops on every screen with `play(0)`.
  - The player is kept in a variable for the whole run, because a collected player stops.
  - A failed `load` returns `nil, err`. It's logged, and the game runs without music.
- **Settings:** `pc.config` keys `music` and `sfx`, each `"on"` or `"off"`. A missing key means on.
  - **Startup:** `pc.config.load()`, which returns `false` on first run and that's fine. Then `music_enabled = pc.config.get("music") ~= "off"`, and the same for `sfx`.
  - **`set_music(on)`** starts the track with `play(0)` the first time and uses `resume()` after that. Turning music off calls `pause()`.
  - **`set_sfx(on)`** calls `sfx.set_enabled(on)`.
  - **After either change:** the function writes the key, calls `pc.config.save()` (atomic; a `false` result is logged), and rebuilds the F10 menu. The title and F10 labels always agree, because both read the same two flags.

## Files

Modules are loaded with the firmware's native `require` (0.5.0+). It looks up `require("title")` as `<APP_DIR>/title.lua`, and caches each module per app. Modules don't see `main.lua`'s locals, so each one starts with `local pc = picocalc`.

| File | Responsibility | Depends on |
|---|---|---|
| `main.lua` | The state machine (`title`, `playing`, `gameover`, `name_entry`), the existing game logic with its sound-effect calls, music, settings, the F10 menu and startup | all modules |
| `theme.lua` | Returns `{ C = colours, TETROMINOES = shapes }`, moved out of `main.lua` without changes, plus the title colours below | `pc.display.rgb` |
| `highscores.lua` | Score-table logic and saving. No drawing and no input. | `picocalc.game.save`, looked up when called so tests can stub it |
| `sfx.lua` | Loads the sound effects, runs the player pool, and exposes one function per menu or game event | `picocalc.sound`, looked up when called |
| `title.lua` | Title animation, drawing and menu input | `theme`, `sfx`, `highscores` entries passed in |
| `name_entry.lua` | The game-over and name-entry panels: the name buffer, keyboard input, the 400 ms input lock and drawing | `theme`, `sfx`, `highscores` (name rules) |
| `assets/title_bg.png` | 320×320 background, fully opaque | — |
| `assets/logo.png` | Logo of about 240×48 on a pure-green key background `(0,255,0)` = RGB565 `0x07E0`, no alpha channel | — |
| `assets/background01.qoa` | The music: `qoaconv background01.mp3 assets/background01.qoa` (22.05 kHz stereo, same as the MP3) | — |
| `assets/sfx/*.wav` | 14 sound effects made by `tools/gen_sfx.py`, committed | — |
| `background01.mp3` | Stays in the repo as the source for the QOA file, but is no longer packaged | — |
| `tools/gen_sfx.py` | Generates the sound effects, repeatably | host Python 3, standard library only |
| `tests/highscores_test.lua`, `tests/sfx_test.lua` | Host tests | host `lua` 5.4 |

New colours in `theme.C`:
- `RAIN = rgb(0,110,130)`
- `PANEL = rgb(8,0,18)`
- `BORDER = CYAN`
- `DIM = rgb(110,110,150)`
- `FLASH = YELLOW`

## Module interfaces

### `highscores.lua`

```lua
local hs = require("highscores")
hs.MAX_NAME            -- 8
hs.load()              -- read the save into module state; never raises
hs.entries()           -- copy of up to 3 {name=, score=}, sorted by score, highest first
hs.last_name()         -- string, "" on first run
hs.qualifies(score)    -- the rank (1-3) this score would take, or nil
hs.insert(name, score) -- clean the name, insert, cap at 3, set last_name, save; returns rank
hs.clean_name(s)       -- uppercase, drop disallowed characters, cap at 8, trim both ends
hs.normalize_char(ch)  -- the uppercase allowed character, or nil
```

- **Allowed characters:** `A–Z 0–9 space - .`
- **Ranking:**
  - A score qualifies when it's above 0 and either fewer than 3 are saved or it beats 3rd place.
  - A tie ranks **below** the existing score: rank = 1 + the number of saved scores ≥ the new score.
- **Saving:**
  - One call, `pc.game.save.set("highscores", { version = 1, last_name = ..., entries = {...} })`, writes `/data/net.picodeck.blockexe/saves/highscores.json`.
  - It's wrapped in `pcall`. A failure is logged with `pc.sys.log` and otherwise ignored.
- **Loading:**
  - `pc.game.save.get` returns nil for a missing or corrupt file, and that loads as an empty table.
  - An entry is kept only when its `name` is a string that cleans to something non-empty and its `score` is a whole number above 0.
  - Kept entries are sorted, capped at 3 and stored as integers (`math.tointeger`).
  - `last_name` that isn't a string loads as `""`.
  - `version` is written but not checked.
  - The same rules cover a legacy `/saves/highscores.json` from another app, which the firmware copies in on the first read.
- **Skip and last name:** skipping (Esc) calls nothing, so `last_name` stays unchanged.

### `sfx.lua`

```lua
local sfx = require("sfx")
sfx.load()                   -- load every WAV and create the player pool; never raises
sfx.set_enabled(on)          -- off also stops any sound that's playing
sfx.ui(name)                 -- "move" | "select" | "back" | "key" | "delete" | "save"
sfx.on_move()                -- piece moved left or right
sfx.on_rotate()              -- rotation succeeded
sfx.on_hard_drop()
sfx.on_lock()                -- gravity lock only; a hard drop plays on_hard_drop instead
sfx.on_clear(n)              -- n = 1..4 lines
sfx.on_level_up(level)
sfx.on_game_over(high_score) -- high_score true plays "high_score" instead of "game_over"
```

- **Seam for adaptive music:** the game and screens call only these functions, never a sample directly. Part B can later reroute an event, for example to snap it to the beat, without changing the game code.
- **Loading:**
  - Each sound is `pc.sound.sample(APP_DIR .. "/assets/sfx/<file>.wav")`.
  - A sound that fails to load is logged and left silent. Every function is a no-op for a missing sound, and when effects are disabled.
- **Player pool:**
  - Up to 6 `pc.sound.sampleplayer()`s are created at load. The firmware allows 8, and a creation that returns `nil, err` just makes the pool smaller.
  - Each play uses the first idle player. If none is idle, it takes over the one that started earliest.
  - Each play calls `setSample`, `setRate`, `setVolume(90)` and `play(1)`.
- **Event → sound:**

  | Call | File | Rate |
  |---|---|---|
  | `ui("move")` | `ui_move` | 1.0 |
  | `ui("select")` | `ui_select` | 1.0 |
  | `ui("back")` | `ui_back` | 1.0 |
  | `ui("key")` | `key` | 1.0 |
  | `ui("delete")` | `key` | 0.8 |
  | `ui("save")` | `save` | 1.0 |
  | `on_move()` | `move` | 1.0 |
  | `on_rotate()` | `rotate` | 1.0 |
  | `on_hard_drop()` | `hard_drop` | 1.0 |
  | `on_lock()` | `lock` | 1.0 |
  | `on_clear(1)`, `(2)`, `(3)` | `clear` | 1.0, 1.19, 1.41 |
  | `on_clear(4)` | `tetris` | 1.0 |
  | `on_level_up(level)` | `level_up` | 1.0 |
  | `on_game_over(false)` | `game_over` | 1.0 |
  | `on_game_over(true)` | `high_score` | 1.0 |

### `title.lua`

```lua
title.load()                                     -- load images once (in pcall), set up the rain and falling pieces
title.enter(flash_rank)                          -- flash_rank is 1-3 or nil; the menu goes back to START
title.update(dt_ms)                              -- returns "start" | "toggle_music" | "toggle_sfx" | "quit" | nil
title.draw(entries, music_enabled, sfx_enabled)
```

### `name_entry.lua`

```lua
name_entry.enter(score, rank, default_name) -- rank nil = plain game over; calls clearState, starts the 400 ms lock
name_entry.update(now_ms)                   -- returns "save", name | "skip" | "continue" | nil
name_entry.draw()                           -- the panel only; main.lua draws the dimmed board first
```

## Title screen (320×320)

Drawn back to front every frame:

1. **Background:** `title_bg.png` at (0,0). If it failed to load, fill with `C.BG`.
2. **Rain:**
   - 40 streaks, each 1 px wide and 6–12 px long, falling at 250–400 px/s, drawn in `C.RAIN` with `pc.display.fillVLine(x, y0, y1, color)`.
   - A streak that leaves the bottom starts again above the top at a random x.
3. **Falling pieces:**
   - 5 pieces made of 8 px blocks, each with a random shape, rotation and colour from `TETROMINOES`, falling at 15–40 px/s.
   - Drawn with `pc.graphics.fillBorderedRect(x, y, 8, 8, color, C.BG)`.
   - A piece that leaves the bottom starts again above the top at a random x.
4. **Logo:**
   - `logo.png`, centred at y=18, drawn with `logo:setTransparentColor(0x07E0)`.
   - Underneath: *A CYBERPUNK TETRIMINO GAME* in `FONT_6X8`.
   - If the logo failed to load, draw `BLOCK.EXE` in `FONT_8X12` instead.
5. **Score panel:**
   - Covers y=110–190: `C.PANEL` fill with a `C.BORDER` border.
   - *HIGH SCORES* and three rows in `FONT_8X12`, each `string.format("%d. %-8s  %06d", rank, name, score)`.
   - An empty slot shows `---` and `000000`.
   - The row saved in the last game switches between `C.FLASH` and `C.TEXT` every 300 ms until the next key press. `title.update` reads `pollEvent()` until it returns nil each frame, and any `"down"` event counts.
6. **Menu:**
   - Covers y=216–280 in `FONT_8X12`, 16 px per row, centred: *START*, *MUSIC: ON|OFF*, *SFX: ON|OFF*, *QUIT*.
   - Up and Down move the selection, wrap around, and play `sfx.ui("move")`. The selected item has a `>` in front and is drawn in `C.WHITE`; the others use `C.DIM`.
   - Enter chooses the selected item. Esc returns `"quit"`.
7. **Fonts:** the font is set explicitly with `pc.display.setFont` before each block of text, because the font setting is global. It's set back to `FONT_6X8` before the game draws.

- **Frame timing:** every screen runs inside the existing `pc.perf.beginFrame()` / `pc.perf.endFrame()` loop, which the OS's Show FPS counter relies on. The app doesn't draw its own counter.
- **Text:** always drawn with `bg=false` so it's transparent over the art.
- **Idle dimming:** the OS dims the screen after 60 s idle and swallows the key that wakes it. That's acceptable on a menu, and the app doesn't call `resetIdleTimer`.

## Game over and name entry

- **Drawing:** the board, particles and side panel are drawn as usual, without the falling piece. Then `pc.display.applyEffect("darken", 96)`, then the centred panel (`C.PANEL` fill, `C.BORDER` border).
- **Top-3 score:** *GAME OVER*, then *NEW HIGH SCORE! #N*, then the score, then `NAME: [KEITH_]`, then *ENTER SAVE   ESC SKIP*.
  - The name field is 8 characters wide, with a block cursor that blinks every 500 ms and is hidden when the name is full.
  - The field starts with `hs.last_name()`, which is empty on the first run.
- **Other scores:** *GAME OVER*, then the score, then *ENTER CONTINUE*.
- **Input lock:**
  - `enter` calls `clearState()` and ignores all input for 400 ms. When the lock ends, it calls `clearState()` again.
  - This stops the hard drop's Enter, and any key-mashing, from confirming or skipping the screen.
- **Typing** (name entry only): each frame, read `pollEvent()` until it returns nil, and act on `"char"` events.
  - An allowed character goes through `hs.normalize_char`. It's appended, with `sfx.ui("key")`, if the name has fewer than 8 characters.
  - `"\b"` deletes the last character with `sfx.ui("delete")`. Nothing happens if the name is empty.
  - `"\n"` returns `"save", name` if `hs.clean_name(name)` isn't empty; otherwise nothing happens.
  - Everything else is ignored. The OS provides key repeat.
- **Esc:** `BTN_ESC` from `getButtonsPressed()` returns `"skip"` on the name-entry screen and `"continue"` on the plain game-over screen.
- **Plain game-over screen:** `BTN_ENTER` from `getButtonsPressed()` also returns `"continue"`. This screen reads no characters.
- **Saving:** `main.lua` calls `hs.insert(name, score)`, then `sfx.ui("save")`, then `title.enter(rank)`.

## Where the sounds are triggered

Sounds for input a screen handles itself are played by that screen (`title.lua`, `name_entry.lua`). Everything else is played by `main.lua`:

- **Title actions:**
  - `"start"` → `sfx.ui("select")`, then a new game.
  - `"toggle_music"` or `"toggle_sfx"` → apply the change, then `sfx.ui("select")`, so turning SFX off is silent.
  - `"quit"` → exit, with no sound, because exiting would cut it off.
- **F10 changes** make no sound.
- **Going back:**
  - Esc during a game, or a skip on name entry → `sfx.ui("back")`.
  - A plain game over closed with Esc → `sfx.ui("back")`; closed with Enter → `sfx.ui("select")`.
- **Game events, in the existing game code:**
  - `on_move()` when a left or right move changes `x`.
  - `on_rotate()` when the rotation (after wall kicks) differs from before.
  - `on_hard_drop()` on the hard drop.
  - `on_lock()` when gravity locks the piece.
  - `on_clear(n)` when `n > 0` lines clear.
  - `on_level_up(level)` when the level rises, on top of the clear sound.
  - Soft-drop steps make no sound.
- **Top out:** `on_game_over(rank ~= nil)` when the game enters `gameover` or `name_entry`.

## Sound design

- **Format:**
  - 22.05 kHz, 16-bit, mono WAV, written by `tools/gen_sfx.py` into `assets/sfx/`.
  - Each file's PCM data is at most 64 KB (about 1.45 s), because the firmware keeps only the first 64 KB of a sample. The script fails if any file is bigger.
- **Synthesis:**
  - Python standard library only (`wave`, `math`, `random` with seed 42), following `picodeck/apps/guinea_pig/tools/gen_sfx.py`. Running it twice gives identical files.
  - Saw and pulse oscillators with ±7-cent detune, attack/decay envelopes, a one-pole low-pass whose cutoff sweeps over time, a feedback echo (about 90 ms at 0.35 feedback), and noise for the thumps.
  - Each sound is normalised to a peak of −1 dBFS, then scaled by its own gain, so the move tick sits well below a Tetris.
- **The sounds:**

  | File | Sound |
  |---|---|
  | `ui_move` | Short pulse tick, ~40 ms |
  | `ui_select` | Rising two-note saw blip, ~120 ms |
  | `ui_back` | Falling two-note saw blip, ~120 ms |
  | `key` | Soft tick, ~30 ms |
  | `save` | Bright rising arpeggio, ~0.6 s |
  | `move` | Very short quiet tick, ~25 ms |
  | `rotate` | Pulse blip, ~50 ms |
  | `hard_drop` | Noise-and-low-sweep thump, ~150 ms |
  | `lock` | Soft thud, ~80 ms |
  | `clear` | Filtered upward sweep with echo, ~0.5 s |
  | `tetris` | Big detuned chord stab, sweep and echo, ~1.2 s |
  | `level_up` | Rising arpeggio, ~0.5 s |
  | `game_over` | Descending detuned saw sweep, ~0.9 s |
  | `high_score` | Rising fanfare, ~1 s |

- **Preview:** `python3 tools/gen_sfx.py --preview <file.wav>` also writes every sound one after another, with a short gap between them, to one file for listening on the host.
- **Approval:** the user approves the sounds before they're used.
- **Mix:** music at volume 60 and effects at 90. The mixer adds sources together, and a loud mix clips. The final levels are tuned by ear on the device.

## Performance and memory

- **Speed target:** the title runs at 30 fps or more on the device, measured with *Settings → Show FPS* (PicoDeck 0.5.0 or later). If it's too slow, cut the rain and falling pieces first.
- **Images:** the background takes 200 KB of PSRAM and the logo about 23 KB. Both are loaded once and kept, because re-decoding a PNG on every title visit would be slower than keeping 200 KB.
- **Sound effects:** about 300 KB of PSRAM for the 14 samples, with a hard ceiling of 14 × 64 KB. They're mixed on Core 1.
- **Music cost:** QOA decodes on Core 1 a chunk at a time, and the PicoDeck docs measured it at 2.4–5.3% of frame time. The MP3 it replaces made frames 1.24×–2.1× slower. The fps target is measured with the music on.

## Testing

**Host tests,** run from the repo root. Each exits non-zero on failure and loads its module with `dofile`.

`lua tests/highscores_test.lua` stubs a global `picocalc` with an in-memory `game.save` and a no-op `sys.log`. Cases:
- A score qualifies while fewer than 3 are saved.
- When all 3 slots are full, the rank and insert order are correct.
- A tie ranks below the existing score.
- A 4th insert drops the lowest.
- The list stays sorted.
- A score of 0 never qualifies.
- Bad data loads as empty or skips the bad rows: a non-table save, a missing `entries`, a non-string name, a name that cleans to nothing, a zero, negative, fractional or string score.
- `clean_name`: converts to uppercase, drops disallowed characters, caps at 8 characters and trims both ends.
- `normalize_char` handles allowed characters, lowercase letters, and disallowed characters.
- `last_name` is set by `insert` and unchanged when nothing is inserted. It's `""` on first run.
- A save that raises doesn't raise from `insert`.

`lua tests/sfx_test.lua` stubs `picocalc.sound.sample` / `sampleplayer` (which record calls), `APP_DIR` and a no-op `sys.log`. Cases:
- An idle player is used before a busy one. With all players busy, the earliest-started one is taken over.
- A pool smaller than 6, because `sampleplayer()` returned nil, still works.
- When disabled, nothing plays, and disabling stops anything playing.
- A sound that failed to load plays nothing and doesn't raise.
- `on_clear(1..3)` uses `clear` at rates 1.0, 1.19, 1.41, and `on_clear(4)` uses `tetris`.
- `on_game_over(true)` plays `high_score`, and `on_game_over(false)` plays `game_over`.
- `ui("delete")` plays `key` at rate 0.8.

`python3 tools/gen_sfx.py` asserts the size limit and writes the same bytes on every run. Check by running it twice and comparing hashes.

**Simulator:** `make simulator` in `picodeck/`, then stage the app with the picodeck MCP `push_app` tool. Walk through:
- Title → START → top out with a hard drop. Check the Enter doesn't confirm the name.
- Type a name → Enter → the title shows the new row flashing.
- Get another top-3 score. Check the name is pre-filled, then edit it and check the new name becomes the default.
- A game that doesn't reach the top 3 shows *ENTER CONTINUE*.
- Esc during a game returns to the title with no score saved.
- Esc on the title exits.
- F10 *New Game* works from the title and from name entry.
- The F10 toggles and the title's *MUSIC* / *SFX* items stay in sync, and both settings survive a relaunch.
- The music loops past the end of the track (134 s), and keeps playing across every screen change.
- Each event in "Where the sounds are triggered" plays its sound over the music. Turning SFX off silences them all.
- Take a screenshot of each screen for visual review.

**Device:**
- The title runs at 30 fps or more, with Show FPS turned on.
- The colours match the simulator.
- Scores, the last name and both settings survive a reboot.
- Effects are clearly audible over the music, and the loudest moment doesn't audibly clip: a Tetris with a level-up during the music.

## Art and sound production

**Background:** PixelLab `create_image_pixflux` at 320×320, 10 generations or fewer.
- **Prompt:** a rainy cyberpunk city at night, neon signs with **no readable text**, and darker, quieter areas at the top (logo) and middle (score panel).
- **Starting image:** optionally, a 320×320 crop of `inspiration.jpg` as `init_image` with `init_image_strength` of about 50.
- **Don't** use `create_image_pro`.

**Logo:**
- Drawn by hand in `pixelart_workbench`, about 240×48: `BLOCK.EXE` in a cyan→pink chrome gradient with a dark outline and a few glow pixels.
- Opaque pixels only, on the `(0,255,0)` key colour.
- The user approves a preview before it's used.

**Sound effects:** `tools/gen_sfx.py`, as described in "Sound design". The user approves the preview before the effects are used.

**Tool setup needed:**
- The PixelLab MCP server is configured only for the old `~/Projects/picos-blockexe` path, and must be added for this folder before the art work.
- The simulator work needs the picodeck MCP server (`python3 tools/picodeck_mcp.py`, from `picodeck/.mcp.json`) to be reachable from this folder.

## Packaging and release

- **CI:** `.github/workflows/build.yml` packages `app.json main.lua theme.lua highscores.lua sfx.lua title.lua name_entry.lua icon.png` plus `assets/` (recursively, so it includes `assets/sfx/`). It leaves out `background01.mp3`, `tools/`, `tests/` and `docs/`.
- **README Build section:** records the `qoaconv` command that regenerates the music and the `python3 tools/gen_sfx.py` command that regenerates the effects.
- **README:** the install file list names every packaged file and folder.
- **`app.json`:** `version` becomes `1.1.0` and `min_firmware` becomes `0.5.0` when releasing.

## Out of scope

- **Adaptive music:** Part B of the handover, which needs its own brainstorm. Its hook points are the `sfx.on_*` events. The effects here play the moment the event happens, not on the beat.
- **PicoDeck firmware issues found (not fixed here):**
  - `develop` builds report `0.1.0-N` because release tags aren't ancestors of `develop`, so the Store refuses any `min_firmware` above 0.1.0 on those builds, including this app's 0.5.0. Install with `push_app` instead.
  - The global colour key isn't reset between apps.
  - `pc.game.save.set` writes with a plain `fopen("w")`, not atomically, so a power loss mid-write can wipe the high scores. `pc.config` already uses `sd_atomic`.
