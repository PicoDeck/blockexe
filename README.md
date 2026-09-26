# block.exe

A Tetris-style falling-block game for the [ClockworkPi PicoCalc](https://www.clockworkpi.com/),
with neon graphics and a background music track. Written for [PicoDeck](https://github.com/PicoDeck/picodeck).

## Install

block.exe is available on the [PicoDeck App Store](https://store.picodeck.net). Open the
Store app on your PicoCalc and install it from there.

## Build

This is a Lua app — there is nothing to build. Just copy `app.json`, `main.lua`, and
`background01.mp3` to `/apps/blockexe/` on the device's SD card, or install it through
the App Store.

## Release

To cut a new release:

1. Bump `version` in `app.json`.
2. Commit the change.
3. Tag and push: `git tag v<version> && git push --tags`

CI builds the release ZIP and publishes the GitHub Release automatically. The PicoDeck
App Store re-indexes the catalog within 30 minutes of a new release.
