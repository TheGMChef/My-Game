#!/usr/bin/env bash
# Sets GODOT to the Godot binary. Sourced by the other tools/dev scripts.
# Order: $GODOT if set, godot on PATH, then the Windows install location.
if [ -z "${GODOT:-}" ]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT=godot
  elif [ -x "${LOCALAPPDATA:-}/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe" ]; then
    GODOT="${LOCALAPPDATA}/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe"
  else
    echo "Godot not found. Set GODOT to the binary's path." >&2
    exit 2
  fi
fi
export GODOT
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 2
