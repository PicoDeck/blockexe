#!/bin/sh
# Syntax-checks every app module, then runs the host tests. Exits non-zero on any failure.
# LUA and LUAC pick the interpreter and compiler (CI uses Debian's lua5.4 and luac5.4).
cd "$(dirname "$0")/.." || exit 1
LUA="${LUA:-lua}"
LUAC="${LUAC:-luac}"
status=0
for f in ./*.lua; do
    "$LUAC" -p "$f" || status=1
done
for t in tests/*_test.lua; do
    echo "== $t"
    "$LUA" "$t" || status=1
done
if ls tests/test_*.py >/dev/null 2>&1; then
    echo "== python"
    python3 -m unittest discover -s tests -p 'test_*.py' || status=1
fi
exit $status
