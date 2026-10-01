# block.exe

A Tetrimino game for the [ClockworkPi PicoCalc](https://www.clockworkpi.com/),
with neon graphics and a background music track. Written for [PicoDeck](https://github.com/PicoDeck/picodeck).

It has a title screen with a top-3 high-score table and synthwave sound effects.

## Install

block.exe is available on the [PicoDeck App Store](https://store.picodeck.net). Open the
Store app on your PicoCalc and install it from there.

## Controls

| Action | Button | Default key |
|--------|--------|-------------|
| Move left / right, soft drop | D-pad | arrow keys |
| Rotate | D-pad up | Up |
| Hard drop | A | F4 |
| Menus: move, confirm | D-pad, A | arrows, F4 or Enter |
| Back to the title, quit | | Esc |

The game reads the gamepad, so Settings > Controls in the system menu rebinds the buttons.
Enter still confirms the title menu and the game-over screen, and typing a high-score name stays
on the keyboard. On firmware without the gamepad API it reads the plain keys it always did, with Enter
as the hard drop.

## Build

This is a Lua app; there's nothing to compile. `sh tools/stage.sh` copies the files that ship
into `build/stage/`:

- `app.json` and `icon.png`
- `main.lua`, `theme.lua`, `highscores.lua`, `sfx.lua`, `title.lua`, `name_entry.lua` and `pad.lua`
- `assets/`: the title art, the QOA music and `assets/sfx/`

Copy that folder to `/apps/blockexe/` on the SD card, or install through the App Store.

It needs PicoDeck 0.5.0 or later.

To regenerate assets:

- Music: `qoaconv background01.mp3 assets/background01.qoa`
- Sound effects: `python3 tools/build_sfx.py` rebuilds `assets/sfx/` from the chosen
  sources in `tools/sfx_src/` (see `manifest.json` there for where each one came from).
  `--preview out.wav` writes them all into one file to listen to.

Tests: `sh tests/run.sh` (needs `lua` 5.4 and Python 3).

## Release

To cut a new release:

1. Bump `version` in `app.json`.
2. Commit the change.
3. Tag and push: `git tag v<version> && git push --tags`

CI builds the release ZIP and publishes the GitHub Release automatically. The PicoDeck
App Store re-indexes the catalog within 30 minutes of a new release.

## Credits

- Sound effects were generated on [Comfy Cloud](https://comfy.org/cloud) with two models;
  `tools/sfx_src/manifest.json` records which one made each sound, with its prompt.
  - [Stable Audio 3 small SFX](https://huggingface.co/stabilityai/stable-audio-3-small-sfx)
    (Stability AI Community License: you own the outputs, and commercial use is allowed for
    organisations under $1M annual revenue).
  - [ElevenLabs sound effects](https://elevenlabs.io/sound-effects) through Comfy's partner
    nodes (Comfy lists ElevenLabs as cleared for commercial use on Comfy Cloud, and paid
    ElevenLabs sound effects are royalty-free).
- The title background was generated with [PixelLab](https://www.pixellab.ai/). The logo
  was drawn pixel by pixel in PixelLab's workbench.
