# Title screen with top-3 high scores: design

**Date:** 2026-10-01
**Status:** written for review
**Source:** Part A of `docs/handover/2026-09-26-title-screen-and-adaptive-music.md`. The user approved sections A1–A3 there. Every fact below was checked again against the PicoDeck firmware source (`~/Projects/PicoDeck/picodeck`, `develop` at `094a5b9`) on 2026-10-01.

## Goal

block.exe gets a title screen that shows the top three high scores with names. When a game ends with a top-3 score, the player types a name, which is pre-filled with the last name used. The game is currently one `main.lua` that starts playing as soon as it launches.

## Changes from the handover

The handover was written before the rename and before a full check of the firmware. These points differ from it:

| # | Handover said | Spec says | Why |
|---|---|---|---|
| 1 | `min_firmware` stays `0.1.0`, to be checked | `min_firmware: "0.2.0"` | Per-app save files (`/data/<id>/saves/`) and `pc.input.pollEvent` arrived in 0.2.0. On 0.1.0, `pc.game.save` writes to a `/saves/` folder that every app shares. |
| 2 | Read every pending character with `getChar()` each frame | Read characters with `pc.input.pollEvent()` | `getChar()` returns the same character until the next `update()`, so looping over it never ends. `pollEvent()` returns each queued event once, in order. |
| 3 | `"\b"` **or** `BTN_BACKSPACE` deletes | Backspace and Enter come only from character events. Esc comes from `BTN_ESC`. | One key press produces both a character and a button edge, so reading both would delete two characters. |
| 4 | Colour key 0 means "no key" | 0 means "use the global key". The app calls `pc.graphics.setTransparentColor(0)` at startup. | The global key isn't reset between apps. A key left by the previous app could punch holes in the background. |
| 5 | Music "keeps looping, as it does today" | Fix it: `music_player:play(0)` | `play()` with no argument plays once and turns looping off, so the track currently stops after one play. |
| 6 | Trailing spaces trimmed | Leading and trailing spaces trimmed | A leading space would push the name out of line in the score table. |
| 7 | `gameover` → `name_entry` | `playing` goes straight to `gameover` or `name_entry` | The two screens are alternatives, not steps in a sequence. |
| 8 | "Dimmed" board | `pc.display.applyEffect("darken", 96)` over the whole frame, then the panel | This runs in hardware over the whole framebuffer, so it's cheap. |
| 9 | (not covered) | If an image fails to load, the title falls back to the plain background colour and a text logo | A missing asset shouldn't crash the app. |
| 10 | `ENTER save · ESC skip` | `ENTER SAVE   ESC SKIP` | The built-in fonts are ASCII only. |
| 11 | Logo text depends on the final name | `BLOCK.EXE`, confirmed when you review the logo preview | The rename didn't change the app's name. |

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
- **F10 menu** (at most 4 items): *New Game* and *Enable/Disable Music*.
  - Callbacks run at an arbitrary point in the Lua code, so each one only sets a flag: `pending_new_game` or `pending_music_toggle`.
  - The main loop handles both flags at the top of the next frame.
  - *New Game* starts a fresh game from any screen. An unsaved name entry is dropped.
- **Music:** `background01.mp3` loops on every screen (`play(0)`). The title's *MUSIC* item and the F10 item share one `music_enabled` flag through one `set_music(on)` function. That function pauses or resumes the player and rebuilds the F10 menu, so both labels always agree. As today, the setting isn't saved between launches.
- **Every state change** calls `pc.input.clearState()`. This clears button edges, the `pollEvent` queue and the `getChar` backlog, so a key press can't carry over from one screen to the next.

## Files

All Lua modules are loaded with the `require` shim from `picodeck/apps/nonogram/main.lua:20-37`. The shim is a global `require` built on `pc.fs.readFile` and `load`, with paths under `APP_DIR`.
- Firmware 0.5.0+ has a native `require`, but the shim replaces it, so the same loader runs on every firmware from 0.2.0 up.
- Modules don't see `main.lua`'s locals, so each one starts with `local pc = picocalc`.

| File | Responsibility | Depends on |
|---|---|---|
| `main.lua` | The state machine (`title`, `playing`, `gameover`, `name_entry`), the existing game logic, music, the F10 menu, the `require` shim and startup | all modules |
| `theme.lua` | Returns `{ C = colours, TETROMINOES = shapes }`, moved out of `main.lua` without changes, plus the title colours below | `pc.display.rgb` |
| `highscores.lua` | Score-table logic and saving. No drawing and no input. | `picocalc.game.save`, looked up when called so tests can stub it |
| `title.lua` | Title animation, drawing and menu input | `theme`, `highscores` entries passed in |
| `name_entry.lua` | The game-over and name-entry panels: the name buffer, keyboard input, the 400 ms input lock and drawing | `theme`, `highscores` (name rules) |
| `assets/title_bg.png` | 320×320 background, fully opaque | — |
| `assets/logo.png` | Logo of about 240×48 on a pure-green key background `(0,255,0)` = RGB565 `0x07E0`, no alpha channel | — |
| `tests/highscores_test.lua` | Host tests for `highscores.lua` | host `lua` 5.4 |

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

### `title.lua`

```lua
title.load()                        -- load images once (in pcall), set up the rain and falling pieces
title.enter(flash_rank)             -- flash_rank is 1-3 or nil; the menu goes back to START
title.update(dt_ms)                 -- returns "start" | "toggle_music" | "quit" | nil
title.draw(entries, music_enabled)
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
   - Underneath: *A CYBERPUNK TETRIS CLONE* in `FONT_6X8`.
   - If the logo failed to load, draw `BLOCK.EXE` in `FONT_8X12` instead.
5. **Score panel:**
   - Covers y=110–190: `C.PANEL` fill with a `C.BORDER` border.
   - *HIGH SCORES* and three rows in `FONT_8X12`, each `string.format("%d. %-8s  %06d", rank, name, score)`.
   - An empty slot shows `---` and `000000`.
   - The row saved in the last game switches between `C.FLASH` and `C.TEXT` every 300 ms until the next key press. `title.update` reads `pollEvent()` until it returns nil each frame, and any `"down"` event counts.
6. **Menu:**
   - Covers y=220–280 in `FONT_8X12`, centred: *START*, *MUSIC: ON* or *MUSIC: OFF*, *QUIT*.
   - Up and Down move the selection and wrap around. The selected item has a `>` in front and is drawn in `C.WHITE`; the others use `C.DIM`.
   - Enter chooses the selected item. Esc returns `"quit"`.
7. **FPS counter and fonts:** `pc.perf.drawFPS()`, as on every screen. The font is set explicitly with `pc.display.setFont` before each block of text, because the font setting is global. It's set back to `FONT_6X8` before the game draws.

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
  - An allowed character goes through `hs.normalize_char` and is appended if the name has fewer than 8 characters.
  - `"\b"` deletes the last character.
  - `"\n"` returns `"save", name` if `hs.clean_name(name)` isn't empty; otherwise nothing happens.
  - Everything else is ignored. The OS provides key repeat.
- **Esc:** `BTN_ESC` from `getButtonsPressed()` returns `"skip"` on the name-entry screen and `"continue"` on the plain game-over screen.
- **Plain game-over screen:** `BTN_ENTER` from `getButtonsPressed()` also returns `"continue"`. This screen reads no characters.
- **Saving:** `main.lua` calls `hs.insert(name, score)`, then `title.enter(rank)`.

## Performance and memory

- **Speed target:** the title runs at 30 fps or more on the device, measured with `pc.perf.drawFPS()`. If it's too slow, cut the rain and falling pieces first.
- **Memory:** the background takes 200 KB of PSRAM and the logo about 23 KB. Both are loaded once and kept, because re-decoding a PNG on every title visit would be slower than keeping 200 KB.
- **Music cost:** MP3 decoding runs on Core 1 but slows Core 0 frames too. It's already running today, so the fps target is measured with music on.

## Testing

**Host: `lua tests/highscores_test.lua` from the repo root.** It exits non-zero on failure.
- Stubs a global `picocalc` with an in-memory `game.save` and a no-op `sys.log`.
- Loads the module with `dofile("highscores.lua")`.

Cases:
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

**Simulator:** `make simulator` in `picodeck/`, then stage the app with the picodeck MCP `push_app` tool. Walk through:
- Title → START → top out with a hard drop. Check the Enter doesn't confirm the name.
- Type a name → Enter → the title shows the new row flashing.
- Get another top-3 score. Check the name is pre-filled, then edit it and check the new name becomes the default.
- A game that doesn't reach the top 3 shows *ENTER CONTINUE*.
- Esc during a game returns to the title with no score saved.
- Esc on the title exits.
- F10 *New Game* works from the title and from name entry.
- F10 music toggle and the title's *MUSIC* item stay in sync.
- The music loops past the end of the track.
- Take a screenshot of each screen for visual review.

**Device:**
- The title runs at 30 fps or more.
- The colours match the simulator.
- Scores and the last name survive a reboot.

## Art

**Background:** PixelLab `create_image_pixflux` at 320×320, 10 generations or fewer.
- **Prompt:** a rainy cyberpunk city at night, neon signs with **no readable text**, and darker, quieter areas at the top (logo) and middle (score panel).
- **Starting image:** optionally, a 320×320 crop of `inspiration.jpg` as `init_image` with `init_image_strength` of about 50.
- **Don't** use `create_image_pro`.

**Logo:**
- Drawn by hand in `pixelart_workbench`, about 240×48: `BLOCK.EXE` in a cyan→pink chrome gradient with a dark outline and a few glow pixels.
- Opaque pixels only, on the `(0,255,0)` key colour.
- The user approves a preview before it's used.

**Before the art work:** the PixelLab MCP server is configured only for the old `~/Projects/picos-blockexe` path and must be added for this folder. The simulator work also needs the picodeck MCP server (`python3 tools/picodeck_mcp.py`, from `picodeck/.mcp.json`) to be reachable from this folder.

## Packaging and release

- **CI:** `.github/workflows/build.yml` packages `app.json main.lua theme.lua highscores.lua title.lua name_entry.lua background01.mp3 icon.png` plus `assets/` (recursively), and leaves out `tests/` and `docs/`.
- **README:** the install file list names every packaged file and folder.
- **`app.json`:** `version` becomes `1.1.0` and `min_firmware` becomes `0.2.0` when releasing.

## Out of scope

- Adaptive music: Part B of the handover, which needs its own brainstorm.
- Sound effects: the MP3 player and the sample mixer conflict on hardware.
- Saving the music setting between launches.
- **PicoDeck firmware issues found (not fixed here):**
  - `develop` builds report `0.1.0-N` because release tags aren't ancestors of `develop`, so the Store refuses `min_firmware ≥ 0.2.0` on those builds. Install with `push_app` instead.
  - The global colour key isn't reset between apps.
