#!/usr/bin/env bash
# Exports the release web build to build/web. Needs Godot's export templates installed.
# Usage: bash tools/dev/web.sh
source "$(dirname "${BASH_SOURCE[0]}")/godot.sh"
mkdir -p build/web
log="$(mktemp)"
"$GODOT" --headless --path . --export-release Web build/web/index.html >"$log" 2>&1
code=$?
if [ "$code" -ne 0 ] || [ ! -f build/web/index.wasm ]; then
  echo "Web export FAILED (log: $log)"
  grep -E 'ERROR|No export template' "$log" | head -10
  exit 1
fi
echo "Web build ready in build/web ($(du -sh build/web | cut -f1)). Serve it over HTTP to play it:"
echo "python -m http.server 8766 --bind 127.0.0.1 --directory build/web"
