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
