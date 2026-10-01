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
