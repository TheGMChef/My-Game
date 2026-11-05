---
name: check
description: "Run Muster's full check: Godot tests, playtest bot and importer tests, with a short pass or fail report. Use after any code change."
argument-hint: "[games]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(bash tools/dev/check.sh*)
model: sonnet
---

# Check

Run `bash tools/dev/check.sh $ARGUMENTS` with a 10-minute timeout. The default is 20 bot games.

Report one line per check, then the result. If something failed:

1. Show the failing test names, or the bot's seed and outcome.
2. Read the log the script named and state the likely cause.
3. For a bot failure, suggest the `playtest-triage` agent with that seed.

Don't fix anything unless asked. Say plainly if a check was skipped.
