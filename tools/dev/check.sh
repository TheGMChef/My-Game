#!/usr/bin/env bash
# The full local check: Godot tests, playtest bot, importer tests.
# Usage: bash tools/dev/check.sh [games]
# Prints one line per check. Exits 0 only if every check that ran passed. When the tree is
# clean it records HEAD in last-check, which .claude/hooks/require-check.sh reads before a push.
source "$(dirname "${BASH_SOURCE[0]}")/godot.sh"
games="${1:-20}"
logs="$(mktemp -d)"
failed=0

report() { printf '%-16s %s\n' "$1" "$2"; }

"$GODOT" --headless --path . --import >"$logs/import.log" 2>&1
if grep -q 'Parse Error' "$logs/import.log"; then
  report "Import" "FAILED: parse errors, see $logs/import.log"
  failed=1
else
  report "Import" "passed"
fi

"$GODOT" --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests --ignoreHeadlessMode >"$logs/tests.log" 2>&1
code=$?
summary="$(sed 's/\x1b\[[0-9;]*m//g' "$logs/tests.log" | grep 'Overall Summary' | sed 's/Overall Summary: //; s/ |$//')"
if [ "$code" -eq 0 ]; then
  report "Godot tests" "passed: $summary"
else
  report "Godot tests" "FAILED: $summary (log: $logs/tests.log)"
  sed 's/\x1b\[[0-9;]*m//g' "$logs/tests.log" | grep -E ' FAILED [0-9]' | head -10
  failed=1
fi

"$GODOT" --headless --path . -s tools/playtest.gd -- "$games" 1 >"$logs/play.log" 2>&1
code=$?
if [ "$code" -eq 0 ]; then
  report "Playtest bot" "passed: $(grep '^played' "$logs/play.log")"
else
  report "Playtest bot" "FAILED (log: $logs/play.log)"
  grep -E '^FAIL' "$logs/play.log" | head -10
  failed=1
fi

if python -m pytest --version >/dev/null 2>&1; then
  if python -m pytest -q tests/tools >"$logs/pytest.log" 2>&1; then
    report "Importer tests" "passed: $(tail -1 "$logs/pytest.log")"
  else
    report "Importer tests" "FAILED (log: $logs/pytest.log)"
    failed=1
  fi
else
  report "Importer tests" "NOT RUN: pytest is not installed here (CI still runs them)"
  not_run="importer tests"
fi

stamp="production/session-state/last-check"
if [ "$failed" -ne 0 ]; then
  rm -f "$stamp"
  echo "RESULT: FAILED"
  exit 1
fi
mkdir -p production/session-state
if [ -z "$(git status --porcelain | grep -v '\.png\.import$')" ]; then
  git rev-parse HEAD >"$stamp"
  verdict="PASSED"
  [ -n "${not_run:-}" ] && verdict="NOT FULLY ASSESSED ($not_run not run)"
  echo "RESULT: $verdict, recorded for $(git rev-parse --short HEAD)"
else
  rm -f "$stamp"
  echo "RESULT: uncommitted changes, nothing recorded for push"
fi
