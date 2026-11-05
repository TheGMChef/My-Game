#!/bin/bash
# Claude Code PreToolUse hook: blocks a push of main until tools/dev/check.sh has passed on HEAD.
# Exit 0 = allow, Exit 2 = block. Input: { "tool_input": { "command": "git push origin main" } }

INPUT=$(cat)
case "$INPUT" in
  *'"tool_input"'*push*) ;;
  *) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
COMMAND=$(printf '%s' "$INPUT" | python -I -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
printf '%s' "$COMMAND" | grep -Eq '(^|[;&| ])git( -[cC] [^ ]+)* push( |$)' || exit 0

STAMP="$ROOT/production/session-state/last-check"
HEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$HEAD" ]; then
  exit 0
fi
echo "Push blocked: the full check has not passed on this commit. Run: bash tools/dev/check.sh" >&2
exit 2
