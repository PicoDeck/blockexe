#!/bin/sh
# Copies only the files the app ships into a folder (default build/stage), for
# the simulator's push_app and for the release zip.
set -e
cd "$(dirname "$0")/.."
out="${1:-build/stage}"
# Add a new module here as well as in main.lua's requires.
files="app.json icon.png main.lua theme.lua highscores.lua sfx.lua title.lua name_entry.lua pad.lua"
for f in $files; do
    if [ ! -f "$f" ]; then
        echo "stage.sh: missing $f" >&2
        exit 1
    fi
done
rm -rf "$out"
mkdir -p "$out"
cp $files "$out"/
if [ -d assets ]; then cp -r assets "$out"/; fi
echo "staged into $out:"
(cd "$out" && find . -type f | sort)
