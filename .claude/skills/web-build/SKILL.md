---
name: web-build
description: "Export Muster's web build and test it in the browser pane: title, roster and first battle phase."
user-invocable: true
allowed-tools: Read, Bash(bash tools/dev/web.sh*), Bash(python -m http.server*), mcp__Claude_Browser__preview_start, mcp__Claude_Browser__computer, mcp__Claude_Browser__browser_batch, mcp__Claude_Browser__read_console_messages, mcp__Claude_Browser__resize_window
model: sonnet
---

# Web build

1. Run `bash tools/dev/web.sh` with a 5-minute timeout. If templates are missing, say so and stop: they're a 1.2 GB download that needs the user's OK.
2. Start `python -I -m http.server 8766 --bind 127.0.0.1 --directory build/web` in the background.
3. Open `http://127.0.0.1:8766/index.html` in the browser pane at 1280x800. Wait about 8 seconds, then read the console.
4. Press Start, Quick fill and Start battle, take a screenshot of each step, and check the console for errors.
5. Stop the server and reset the viewport.

Release web builds hide script errors. If the page misbehaves with a clean console, reproduce it on desktop.

Report what was reached and any console errors. Say plainly that touch input isn't covered by this test.
