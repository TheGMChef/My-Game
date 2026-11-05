---
name: shots
description: "Capture every Muster screen at all sizes, plus large-text colour-blind shots, as QA evidence. Use after any UI change."
argument-hint: "[folder name]"
user-invocable: true
allowed-tools: Read, Glob, Bash(bash tools/dev/shots.sh*)
model: sonnet
---

# Shots

Run `bash tools/dev/shots.sh $ARGUMENTS` with a 10-minute timeout. It opens game windows while it runs.

Screenshots go to `production/qa/evidence/<folder>`, using today's date if no name is given.

Report the error count per size and where the shots went, then open `d-shoot-odds` at 1280x800 and 812x375 and say whether they look right. Note that portrait height is capped by the monitor, so 820x1180 may come out shorter.

For a full review against the design rules, suggest the `ui-reviewer` agent.
