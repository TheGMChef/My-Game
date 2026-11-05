# My-Game

A small tabletop battle simulator with AI opponents. Personal use and testing only; not for release or sharing.

## Overview

A 2D top-down tabletop battle simulator with AI opponents, built in Godot 4.7 with GDScript. Web export comes first, then tablet, then mobile.

## Status

- **Rules engine started** in `src/engine/` (GDScript), tested with gdUnit4 (95 tests passing headless).
  Built so far: seedable dice, geometry helpers, weapon abilities (anti, blast, cleave, rapid fire, lethal hits,
  sustained hits, devastating wounds, torrent, heavy, lance, melta, ignores cover), turn flow and phases, coherency, engagement, battle-shock, movement legality (normal, advance, fall back), the full hit / wound / save /
  damage sequence, mortal wounds, hazard rolls, Feel No Pain, objective control and VP scoring.
- **Not built yet:** charges, fights, terrain and line of sight,
  stratagems, transports, attached units, reserves, desperate escape, UI, AI.
- **Rules source:** official 11th edition PDFs, summarised in own words in `design/rules/`. Gaps that the PDFs do not
  cover (modifier caps, re-rolls, points) are listed there and are not guessed.
- **Scenario:** `assets/data/scenario_clash_of_patrols.json` is a placeholder from the 2023 (10th edition) Combat Patrol
  book. `design/rules/combat-patrol-adaptation.md` lists what to change for 11th edition.
- **An earlier TypeScript prototype** is kept in `prototypes/ts-battle-sim/` for reference.

## Run the tests

Godot 4.7.2 on your PATH, then: `godot --headless --path . --import`, then
`godot --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`

## Next steps

1. Charges, pile-in, fights and consolidation.
2. Terrain, cover and visibility in 2D.
3. A first playable board and a simple AI.

Game data stays out of the repo: no Games Workshop rules text or datasheets. Units are loaded from your own JSON files.

## Built with

The `.claude/` folder, `CLAUDE.md` and `studio-tests/` come from [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) by Donchitos, used under the MIT licence (`THIRD-PARTY-LICENSE-Claude-Code-Game-Studios.txt`). `UPGRADING.md` explains how to pull in newer versions of the framework.
