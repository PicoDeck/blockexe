# Handover: title screen + high scores, and adaptive music research

**Date:** 2026-09-26
**Repo state when written:** `main` at `e323a2f` (v1.0.1). The whole game is a 435-line `main.lua`.
**Status:**
- **Part A (title screen + high scores):** design agreed with the user, but implementation is **on hold until the big rename lands**. Nothing has been implemented.
  - **Update 2026-10-01:** the rename has landed and the user approved A3. Part A continues in `docs/superpowers/specs/2026-10-01-title-screen-high-scores-design.md`, which replaces this part of the handover.
- **Part B (adaptive music):** researched only. The design brainstorm hasn't started.

> **The rename comes first.** Every name in this document is a pre-rename name: `block.exe`, `com.picos.blockexe`,
> `/data/com.picos.blockexe/`, `blockexe`, and the file names. Translate them before planning.
> The **logo text** also depends on the final name, so don't draw the logo until the rename is settled.

---

## Part A: Title screen with top-3 high scores

### What the user asked for
A title screen showing the top three high scores with names. Name entry pre-fills the last name used, and keeps it
unless the player changes it.

### Decisions the user made
| Topic | Choice |
|---|---|
| Art style | PixelLab background with animation drawn in code on top (rain and falling tetrominoes). Based on `inspiration.jpg`, which is gitignored, local only, 16:9, and laid out again for the 320×320 screen. |
| Logo | Drawn pixel by pixel in PixelLab's free `pixelart_workbench` (letters guaranteed correct, no generations used), not AI-generated. The user reviews a preview before it's used. |
| Name entry | Custom neon entry on the game-over screen, typed on the keyboard, not the OS `pc.ui.textInput` dialog. |
| Flow | Game over → name entry if the score made the top 3 → back to the title. Esc during a game returns to the title. Only Esc on the title (or QUIT) exits the app. |
| Menu | START / MUSIC: ON-OFF / QUIT. No High Scores item, because the scores are on the title. No Options item, because music is the only setting. |

### A1. Files and high-score data (approved)

**Files**

| File | Contents |
|---|---|
| `main.lua` | The game logic, now inside a state machine: `title` → `playing` → `gameover` → `name_entry` → `title`. Also the music, the F10 menu, and the standard PicOS `require` shim (copy it from `PicOS/apps/nonogram/main.lua:20-36`, because `require`, `dofile` and `package` are blocked). |
| `theme.lua` | Colours (`C`) and `TETROMINOES`, moved out of `main.lua` because the title's falling pieces need them. This is the only restructuring. |
| `highscores.lua` | Pure logic, no drawing: `load()`, `qualifies(score) -> rank or nil`, `insert(name, score) -> rank`, `entries()`, `last_name()`. |
| `title.lua` | Title drawing, animation and menu. `update` returns `"start"`, `"quit"`, `"toggle_music"` or nil. |
| `name_entry.lua` | The game-over and name-entry screen: the name buffer, keyboard handling and drawing. |
| `assets/title_bg.png` | The 320×320 PixelLab background. |
| `assets/logo.png` | The hand-drawn logo on a colour-key background (see A3). |
| `tests/highscores_test.lua` | Tests run with the host's `lua` (`/usr/bin/lua` exists), with `pc.game.save` stubbed. |

**Stored data:** one file, `/data/com.picos.blockexe/saves/highscores.json`, written with `pc.game.save.set("highscores", tbl)`:
```lua
{ version = 1, last_name = "KEITH",
  entries = { {name="KEITH", score=12400}, {name="ALEX", score=8120}, {name="KEITH", score=4560} } } -- max 3, sorted desc
```
- **Why this API:** keeping the name and the scores in one file avoids `pc.config`, which is limited to 4 keys and silently drops a 5th (`PicOS/src/os/appconfig.c:193-196`).
- **`pc.game.save.set` needs a table.** Passing a number raises an error, whatever the docs say.
- **What makes the top 3:** a score above 0 that beats 3rd place, or any score above 0 while fewer than 3 are saved. A new score that ties an existing one is ranked **below** it.
- **Names:** 1–8 characters from `A–Z 0–9 space - .`. Lowercase is converted to uppercase and other characters are ignored. Trailing spaces are trimmed. Enter does nothing while the name is empty.
- **Auto-fill:** every save sets `last_name`, whether the name was edited or not. Esc (skip) saves nothing and leaves `last_name` unchanged. On the first run there's no last name, so the field starts empty.
- **Bad data:** a missing or corrupt file, or any invalid entry, is treated as empty or skipped (`game.save.get` returns nil on corrupt JSON). A broken save never blocks the game. Writes aren't atomic (a plain `fopen("w")`), so the worst case is losing the table. That risk is accepted.

### A2. Screens and input (approved)

**Title screen (320×320), drawn back to front each frame**
1. **Background:** `title_bg.png`.
2. **Rain:** about 40 dim-cyan streaks, 1 px wide and 6–12 px long, falling at 250–400 px/s. Draw them with `pc.display.fillVLine`.
3. **Falling tetrominoes:** about 5 pieces with 8 px blocks, in random shapes, rotations and colours, falling at 15–40 px/s and starting again at the top when they leave the screen. Draw them with `pc.graphics.fillBorderedRect`.
4. **Logo:** `logo.png` near the top (y≈18), with *A CYBERPUNK TETRIS CLONE* underneath in the 6×8 font.
5. **Score panel:** a dark box with a neon border (y≈110–190), containing *HIGH SCORES* and three rows in the 8×12 font, e.g. `1. KEITH    012400`. Empty slots show `---  000000`. A score saved in the last game flashes (a 300 ms toggle) until the next key press.
6. **Menu:** *START / MUSIC: ON / QUIT* (y≈220–280). Up/Down move with wrap-around, the selected item gets a bright `>`, Enter chooses, and Esc quits.

**Speed target:** at least 30 fps on the device, checked with the FPS counter the game already shows (`pc.perf.drawFPS()`). Drawing the full-screen image every frame is the unknown. If it's too slow, reduce the rain and pieces before trying anything cleverer.

**Game over and name entry**
- When the stack tops out, the board stays visible but dimmed, with a panel over it:
  - **Top-3 score:** *GAME OVER*, *NEW HIGH SCORE! #N*, the score, `NAME: [KEITH█]` with a blinking cursor, and *ENTER save · ESC skip*.
  - **Otherwise:** *GAME OVER*, the score, and *ENTER continue*.
- **Typing:** read every pending character from `pc.input.getChar()` each frame.
  - Printable characters are filtered by the name rules above.
  - `"\b"` or `BTN_BACKSPACE` deletes.
  - `"\n"` or `BTN_ENTER` saves, then returns to the title with the new row flashing.
  - `BTN_ESC` skips saving and returns to the title.
  - Holding a key repeats it, because the OS handles repeat.

**Edge cases**
- **A hard drop could confirm the name.** Hard drop uses Enter, and `getChar()` also queues `"\n"` for that same press. When the game-over screen opens, call `pc.input.clearState()` and ignore all input for **400 ms**, which also stops button-mashing from skipping the screen.
- **Esc during a game** returns to the title and discards the game, so no score is recorded. Today's end-of-loop `BTN_ESC → pc.sys.exit()` check (`main.lua:431`) has to become per-state.
- **F10 menu:** callbacks run synchronously at an arbitrary point in the Lua code (`PicOS/src/os/system_menu.c:481-485`), so they should only set flags.
  - *New Game* sets a pending flag that the main loop handles, and starts a fresh game from any screen.
  - The music toggle and the title's *MUSIC* item share one `music_enabled` setting, so their labels always agree.
- **Music:** `background01.mp3` keeps looping across all screens, as it does today.
- **Screen dimming:** the OS dims the title after 60 s idle. The key that wakes it is swallowed, which is harmless on a menu. We deliberately don't call `pc.sys.resetIdleTimer()` on the title, to save battery.

### A3. Art, testing and packaging (written after the user asked for this handover; **the user hasn't reviewed it yet**)

**Background**
- Use `create_image_pixflux`, which costs 1 generation per call and supports canvases up to 400×400, so it can produce 320×320 directly.
- Prompt direction: a rainy night cyberpunk city, neon signs **without readable text**, and darker, quieter areas where the logo (top) and score panel (middle) go.
- You can crop and resize `inspiration.jpg` to 320×320 and use it as `init_image` with a low `init_image_strength` (about 50, which keeps only the composition). Any fake text it brings along ends up under the logo or panel.
- Budget: 10 generations or fewer. The account had 1,604 subscription generations left on 2026-09-25, resetting on 2026-10-24.
- Avoid `create_image_pro` here: it costs 20–40 generations per call and returns only one candidate above 170 px.

**Logo**
- Draw it with `pixelart_workbench`, about 240×48 px, as a cyan→pink chrome gradient with a dark outline and a few hand-placed glow pixels.
- **Save it on an opaque colour-key background, not as PNG alpha.**
  - The PicOS PNG decoder composites alpha onto black (`PicOS/src/os/image_decoders.cpp:205-210`).
  - Colour key 0 (black) means "no key".
  - So use a key colour the logo never uses, such as pure green (0,255,0 = RGB565 `0x07E0`), and call `img:setTransparentColor(0x07E0)`.
- Show the user a preview before using it.

**Tests: `lua tests/highscores_test.lua` on the host**
- A score qualifies when fewer than 3 are saved.
- Qualifying and insert order when the table is full.
- A tie goes below the existing score.
- A 4th insert drops the lowest.
- The list stays sorted.
- Zero scores never qualify.
- Corrupt or partial data (a non-table, a missing `entries`, bad entries) loads as empty or skips the bad rows.
- Name cleanup: uppercase conversion, disallowed characters dropped, 8-character cap, trailing spaces trimmed.
- `last_name` is updated on save and left unchanged on skip.

**Simulator**
- Build it with `make simulator` in `PicOS/`, which produces `build_sim/picos_simulator`.
- Stage the app with the `push_app` MCP tool (`PicOS/tools/picos_mcp.py`).
- Play the whole flow: title → game → top out with a hard drop (check the Enter doesn't confirm the name) → name entry → title with the new row flashing. Then check that the pre-filled name is used on the next high score, and that editing it changes the default.
- Take screenshots of each screen for visual review.

**Device**
- The title reaches at least 30 fps.
- Colours look right (the simulator's display code is separate from the firmware's).
- Scores and the last name survive a reboot.

**Packaging**
- Add the new `.lua` files and `assets/` to the `zip` line in `.github/workflows/build.yml`. Use `zip -r` for `assets/`, and leave out `tests/`.
- Update the README's install file list.
- Bump the version in `app.json` (1.1.0 suggested) when releasing.
- **Check** that `min_firmware: "0.1.0"` is still honest for `pc.game.save`, `pc.fs.readFile` (used by the `require` shim), `pc.input.getChar`, `pc.input.clearState` and `pc.graphics.image.load`.

### Next step for Part A
After the rename:
1. Show the user A3 for review.
2. Write the design up as a spec.
3. Use `superpowers:writing-plans` to turn it into an implementation plan.

---

## Part B: Adaptive music like Tetris Effect (research only, not designed)

### What the user asked for
Explore an algorithm for music that flows and reacts to gameplay, as in Tetris Effect. CPU is limited, but a core
should be mostly free for this.

### Key constraint: Lua cannot run code on Core 1
- **Hardware:** an RP2350 at 200 MHz by default. An app can ask for up to 300 MHz with `"system_clock_khz"` in `app.json`, which disconnects WiFi unless the app declares `"http"`.
- **Core 0** runs the Lua VM, the display, the keyboard and the SD card.
- **Core 1** ticks every 1 ms (`PicOS/src/main.c:1614-1775`). Each tick it does the WiFi and HTTP work, the audio stream poll, MP3 decoding, the fileplayer, MOD rendering, the native audio callback and image preloading, then it sleeps. It's mostly idle.
- **None of Core 1's idle time is available to Lua.**
  - There's no Lua binding for running code on Core 1.
  - Lua apps can't load native modules. An app is either `main.lua` or `main.elf`, and `main.elf` wins if both exist (`PicOS/src/os/launcher.c:72-82`).
  - Only native apps can register a Core 1 callback, with `api->sys->setAudioCallback`. It runs every 1 ms, although `sdk/native/os.h:213-216` says 5 ms.

### Audio facts that shape any design

> **Update 2026-10-01: PicoDeck 0.5.0 (released 2026-09-29) changed the audio stack.** Several facts below are now wrong. Check `picodeck/docs/API-Audio-and-Sound.md` before the music brainstorm.
> - **One mixer** sums tones, up to 8 SamplePlayers, the MP3 player and one PCM stream (FilePlayer, MOD or `pushSamples`, one at a time). **MP3 and sound effects now play together on hardware**, and the simulator runs the same mixer.
> - **Samples:** the 8-sample limit is gone (8 *players* remain). WAV samples still keep only the first 64 KB.
> - **QOA ("Quite OK Audio")** streams through the FilePlayer and is the cheapest music format: 2.4–5.3% of frame time, against 1.24×–2.1× slower frames for MP3.
> - **MP3 `play(0)` loops.** `play()` with no argument plays once.
> - The block.exe spec switches its music to QOA (`docs/superpowers/specs/2026-10-01-title-screen-high-scores-design.md`).
- **Output:** PWM on GP26/27 at a fixed 44.1 kHz. DMA uses two 128-frame buffers of about 2.9 ms each, and the mixer runs in DMA_IRQ_0 on Core 1 (`PicOS/src/drivers/audio.c:152-216`).
- **What the mixer adds up:** up to 8 sample players, the square-wave tone from `pc.audio.playTone`, and **one** stream-ring producer. The producer is either Lua `pc.audio.pushSamples`, the fileplayer, or MOD. The ring stores **8 bits per channel** and holds 4096 frames.
- **Samples:** at most 8 samples alive at once, each with at most 64 KB of PCM.
  - That's only about 0.74 s at 44.1 kHz 16-bit mono, or about 3 s at 22.05 kHz 8-bit.
  - Pitch is changed with `player:setRate(r)`, which resamples by nearest-neighbour.
  - There are no envelopes and no pan.
  - Lua can't write PCM into a sample directly. The workaround is to write a WAV file with `string.pack` and `pc.fs`, then load it.
  - Keep a reference to every player: a player that gets garbage-collected stops.
- **Timing from Lua:** notes land to within one Lua frame, so roughly 20–30 ms of jitter at the game's frame rate. You can hear that in a rhythm. Sample trigger latency itself is about 3–6 ms.
- **MP3 is not mixed with anything on hardware.** `mp3player` sets up its own DMA on the same PWM slice (`PicOS/src/drivers/mp3_player.c:799-801`). Starting a sample or tone during MP3 playback restarts the mixer's DMA on that slice as well, so the two fight. The simulator *does* mix them, which hides the problem. block.exe plays its music through `mp3player`, so **adding any sound effects or music layers breaks on hardware** unless the MP3 is dropped or PicOS is fixed.
- **MP3 cost on Core 1:** decode bursts of about 10–90 ms, according to the code comments. Replacing the MP3 with a synth frees that time.
- **`pc.modplayer`:** ProTracker MOD only, rendered on Core 1 at 22.05 kHz, with no tempo, pattern or channel control, so it's only good for swapping whole tracks.

### Possible approaches
1. **Lua sequencer using the sample mixer.**
   - Works on today's firmware.
   - Lua schedules notes, quantised to the beat and kept in key, when game events happen, and Core 1 mixes up to 8 short instrument samples in 16-bit.
   - Limits: frame-rate timing jitter, 8 voices and 8 samples, no envelopes.
   - Good for a quick prototype.
2. **New synth/sequencer in the PicOS firmware** *(leaning this way)*.
   - A native synth on Core 1 with a Lua API. Lua sends game events and settings such as `onRotate`, `onLineClear(n)`, `setIntensity(x)` and `setTempo(bpm)`, and the synth quantises them with sample-accurate timing.
   - It's the real "free core" answer, and other apps could use it too.
   - It needs a firmware release and a higher `min_firmware` for the game.
   - The closest existing pattern is PicOS-Rally's native synth: a shared `volatile` input struct plus a single-producer/single-consumer event queue (`PicOS-Rally/core/audio_synth.{c,h}`, `PicOS-Rally/app/main.c:311-358`).
   - The user maintains PicOS, so this is realistic.
3. **Rewrite the game as a native C app,** as Rally did. Overkill.

### Open questions for the music brainstorm
1. Is the user willing to add a synth/sequencer to the PicOS firmware (approach 2)?
2. Which gameplay signals should drive the music? Candidates:
   - moves and rotations → short notes, quantised to the beat and kept in key
   - hard drop and locking a piece → percussion
   - line clears (1–4) → chords or fills, with a big hit for a Tetris
   - level → tempo, key or added layers
   - stack height or danger → tension
3. What happens to `background01.mp3`? Replace it with the adaptive music, turn it into a WAV for the fileplayer (which does mix, but at 8-bit), or fix the MP3/mixer conflict in PicOS?
4. Should the instruments be synthesised voices (oscillators and envelopes) or short samples?
5. Is 44.1 kHz needed, or would a lower internal rate do to save Core 1 time?

---

## PicOS API facts for this work (from source; the docs are out of date in places)
All paths are under `/home/keith/Projects/PicOS/`.
- **Storage:**
  - `pc.game.save.set/get/exists/delete/list` stores files at `/data/<id>/saves/<name>.json` (`src/os/lua_bridge_game_save.c`).
  - `pc.json.encode/decode`.
  - `pc.fs.*`: apps can only write under `/data/<id>/`, and relative paths and `..` are rejected.
  - The `io` and `os` libraries aren't available.
- **Text input:**
  - `pc.input.getChar()` returns printable ASCII with Shift already applied, `"\b"` for Backspace and `"\n"` for Enter.
  - `BTN_BACKSPACE`, `BTN_ENTER` and `BTN_ESC` all exist, and `pc.input.clearState()` clears pending input.
  - `pc.ui.textInput(prompt, default)` exists but wasn't chosen.
- **Images:**
  - `pc.graphics.image.load(path)` handles PNG, BMP, JPEG and the first frame of a GIF, stored as RGB565 in PSRAM (a full screen is 200 KB). It raises an error on failure.
  - `img:draw(x, y)` and `img:setTransparentColor(rgb565)`. Only one colour key is supported, and 0 means none.
- **Fonts:**
  - Built-in fonts are `FONT_6X8` (default), `FONT_8X12`, `FONT_SCIENTIFICA` and `FONT_SCIENTIFICA_BOLD`.
  - There's no scale parameter. For bigger text, build a `.pfn` font with `tools/mkfont.py`, or use `pc.graphics.imageWithText` followed by `drawScaledNN`.
- **Text drawing:** `pc.display.drawText(x, y, text, fg[, bg])`. Pass `bg=false` for a transparent background.
- **Memory:**
  - The Lua heap is about 6 MB of PSRAM, shared with images and samples, and `pc.sys.getMemInfo()` reports it.
  - `lua_Integer` is 32-bit and `lua_Number` is single-precision float.
- **System menu:** at most 4 items, and a 5th raises an error. It opens on F10, which apps never receive.
- **Reference docs:** `PicOS/docs/API-*.md` and the Lua stub `PicOS/sdk/lua/picocalc.lua`.

### PicOS issues found along the way (worth fixing separately)
- The MP3 player and the sample mixer both drive the same PWM output with no coordination (described above). It only shows up on hardware.
- `pc.config` silently drops a 5th key. This is already tracked in `tests/e2e/test_config_store.py:18-23`.
- **Stale docs:**
  - Volumes: the docs say 0–255; the code uses 0–100.
  - `sound.getCurrentTime`: the docs say milliseconds; it returns seconds.
  - Sample-player callbacks: the docs say at most 4; the code allows 8.
  - `coroutine` and `utf8` are listed as missing, but both are available.
  - `game.save.set`: the docs' example saves a number, but a table is required.
  - Modplayer: the docs claim XM and S3M, but only MOD is supported.
  - `ui.textInput`: the docs say 128 characters maximum; the limit is 127.
  - `setAudioCallback`: documented as every 5 ms; it runs every 1 ms.
  - `pollEvent` and `isKeyDown` are missing from `API-Input.md`.
