#!/usr/bin/env bash
# Captures every screen at each size, plus large-text colour-blind shots.
# Usage: bash tools/dev/shots.sh [folder name under production/qa/evidence]
# Opens game windows, so it needs a display. Portrait height is capped by the monitor.
source "$(dirname "${BASH_SOURCE[0]}")/godot.sh"
out="production/qa/evidence/${1:-shots-$(date +%Y-%m-%d)}"
mkdir -p "$out"
abs="$(cd "$out" && pwd)"
logs="$(mktemp -d)"
errors=0

for size in 1280x800 1920x1080 820x1180 812x375 390x844; do
  "$GODOT" --path . --resolution "$size" --rendering-driver opengl3 -s tools/ui_shots.gd -- "$abs" "$size" >"$logs/shots-$size.log" 2>&1
  "$GODOT" --path . --resolution "$size" --rendering-driver opengl3 -s tools/ui_tour.gd -- "$abs" "$size" >"$logs/tour-$size.log" 2>&1
  bad=$(cat "$logs/shots-$size.log" "$logs/tour-$size.log" | grep -c 'SCRIPT ERROR\|ERROR:')
  errors=$((errors + bad))
  printf '%-10s %s, %d errors\n' "$size" "$(grep '^over:' "$logs/tour-$size.log")" "$bad"
done
"$GODOT" --path . --resolution 1280x800 --rendering-driver opengl3 -s tools/ui_shots.gd -- "$abs" a11y a11y >"$logs/shots-a11y.log" 2>&1
printf '%-10s %d errors\n' "a11y" "$(grep -c 'SCRIPT ERROR\|ERROR:' "$logs/shots-a11y.log")"
echo "Saved $(ls "$abs" | wc -l) screenshots to $out"
[ "$errors" -eq 0 ]
