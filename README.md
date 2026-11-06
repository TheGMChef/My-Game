# Muster

Muster is a small tabletop battle simulator with AI opponents. Personal use and testing only; not for release or sharing.

## Overview

A 2D top-down tabletop battle simulator with AI opponents, built in Godot 4.7 with GDScript. Web export comes first, then tablet, then mobile.

## Interface

The look is "cold board, hot actions": blue-black neutrals, one yellow action colour, and sides told apart by shape as well as colour. Colours, type and spacing live in `src/ui/ui_tokens.gd`, and `src/ui/ui_theme_builder.gd` turns them into the Godot theme. Fonts are Chakra Petch, IBM Plex Sans and IBM Plex Mono, under the Open Font License in `assets/fonts/`.

## Status

- **Rules engine started** in `src/engine/` (GDScript), tested with gdUnit4 (280 tests passing headless).
  Built so far: seedable dice, geometry helpers, weapon abilities (anti, blast, cleave, rapid fire, lethal hits,
  sustained hits, devastating wounds, torrent, heavy, lance, melta, ignores cover), turn flow and phases, charges, pile-in, consolidation, fight order, terrain (cover, hidden, obscuring, solid), unit-level shooting and melee, a battle orchestrator with a simple AI, coherency, engagement, battle-shock, movement legality (normal, advance, fall back), the full hit / wound / save /
  damage sequence, mortal wounds, hazard rolls, Feel No Pain, objective control and VP scoring.
- **Not built yet:**
  transports, attached units, reserves (so Rapid Ingress), desperate escape, a smarter AI.
- **Rules source:** official 11th edition PDFs, summarised in own words in `design/rules/`. Gaps that the PDFs do not
  cover (modifier caps, re-rolls, points) are listed there and are not guessed.
- **Scenario:** `assets/data/scenario_clash_of_patrols.json` is a placeholder from the 2023 (10th edition) Combat Patrol
  book. `design/rules/combat-patrol-adaptation.md` lists what to change for 11th edition.
- **An earlier TypeScript prototype** is kept in `prototypes/ts-battle-sim/` for reference.

## Try a sample battle

`godot --headless --path . -s tools/sim_battle.gd -- 1 2 3` plays three AI-versus-AI games on the placeholder
scenario with invented placeholder armies and prints the results.

## Run the tests

Godot 4.7.2 on your PATH, then: `godot --headless --path . --import`, then
`godot --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`

## Next steps

1. Transports and reserves. See `design/rules/engine-coverage.md`.
2. Terrain, cover and visibility in 2D.
3. A first playable board and a simple AI.

Game data stays out of the repo: no Games Workshop rules text or datasheets. Units are loaded from your own JSON files.

## Built with

The `.claude/` folder, `CLAUDE.md` and `studio-tests/` come from [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) by Donchitos, used under the MIT licence (`THIRD-PARTY-LICENSE-Claude-Code-Game-Studios.txt`). `UPGRADING.md` explains how to pull in newer versions of the framework.

## Play it

Run the project in Godot 4.7 (main scene `scenes/main.tscn`): you (blue circles) against the scripted AI (orange hexagons). Place your units in your zone, then drag a unit to move it, tap an enemy to target it, and read the right-hand panel for the rule being applied and exact hit/wound odds before you commit. The main menu has Continue, New battle, Settings and How to play; the game saves at the start of each of your turns to `user://save.json`. In battle, the Menu button (or Esc with nothing selected) opens the pause menu. The Strat tab lists every stratagem, and the game stops to ask when you can answer the AI (`design/rules/stratagems.md`). Settings has Display, Gameplay, Accessibility and Controls tabs. The board toolbar has a Ruler (R key) and zoom. Screenshots of each screen are in `production/qa/evidence/`; `bash tools/dev/shots.sh <folder>` regenerates them.

## Your own armies

The game opens on a roster screen. It lists the invented placeholder armies plus any army JSON you supply:
`res://data/local/army_*.json` (desktop, from the project folder), `user://armies/*.json`, `--armies <file or folder>`,
or the **Load army file** button (works in the browser too; the file is kept in the browser's storage).
Convert your own datasheet PDFs with `tools/datasheets/parse_datasheets.py` then `map_datasheets.py`.
Army data is never committed (`data/local/` is gitignored and excluded from web exports).
