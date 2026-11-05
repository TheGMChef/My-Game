# My-Game

A small tabletop battle simulator with AI opponents. Personal use and testing only; not for release or sharing.

## Overview

Two armies fight on a 44" x 30" board over five rounds. Each turn has three phases: **move**, **shoot**, **fight**. Combat follows the usual tabletop dice sequence: hit roll, wound roll (strength against toughness), save (worsened by armour penetration), then damage. You play Blue against an AI-controlled Red, or watch the AI play both sides.

The units in `src/data/units.json` are invented placeholders with generic stats. The engine reads units, the scenario and the AI tuning from JSON, so you can load your own armies without touching any code.

## Status

- Web first (works now), then tablet, then mobile. The layout already adapts down to phone width, with 44px touch targets and pointer events instead of mouse-only events.
- First playable slice: rules engine, simple AI opponent, canvas board, combat log.
- Planned order after this: richer rules (terrain, charge rolls, special abilities), then a tablet-friendly layout pass, then mobile.

## Run it

Requires Node 22.18 or newer.

```bash
npm install        # once: installs Vite and TypeScript
npm run dev        # start the game in the browser
npm run build      # type-check and make a static build in dist/
npm test           # 41 tests, no extra packages needed
npm run sim        # play 500 AI-vs-AI games and print win rates (npm run sim -- 2000 for more)
```

How to play: select one of your units (click it, or press `N` to cycle), then click where it should go. In the shoot and fight phases, click a marked enemy. `Enter` ends the phase, `Esc` deselects. URL options: `?seed=42` for a repeatable game, `?ai=both` to watch the AI, `?scale=1.5` for bigger text, `?colours=safe` for the colour-blind palette.

## Where things are

| Path | What it is |
|---|---|
| `src/engine/` | Rules: dice, combat maths, the `Game` class (turns, phases, legality, scoring). No browser code. |
| `src/ai/simpleAi.ts` | The AI opponent. Returns a record of every decision it makes. |
| `src/data/` | `units.json`, `scenario.json`, `ai.json`, and the loaders that validate them. |
| `src/ui/` | Canvas renderer, page wiring, and all on-screen text (`strings.ts`). |
| `tests/` | Unit and integration tests (Node's built-in test runner). |
| `tools/simulate.ts` | Batch AI-vs-AI simulation for balance checks. |
| `production/qa/evidence/` | Screenshots of the UI at phone, tablet, desktop and large sizes. |

## Simplifications in this version

Units are single circles (no individual models), there is no terrain or line of sight, a move is a straight line checked only at its end point, and moving into contact counts as a charge with no roll. Damage never spills over to the next model. These are deliberate to keep the first slice small.

## Known gaps

- Written and tested without being able to run `npm install` (the build sandbox blocked the npm registry), so the Vite build itself has not been run. The code was type-checked with `tsc`, tested with Node's runner, and exercised in headless Chrome through a throwaway build.
- The engine's combat-log lines and "why that move is illegal" messages are English text inside the engine, not routed through `src/ui/strings.ts` yet.
- No gamepad support. Keyboard covers selecting units and ending phases, but not choosing a destination or target.
- `CLAUDE.md` still has the engine marked `[CHOOSE: ...]` and imports the Godot reference. The framework's `/setup-engine` covers Godot, Unity and Unreal, not a TypeScript web app.

## Built with

The `.claude/` folder, `CLAUDE.md` and `studio-tests/` come from [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) by Donchitos, used under the MIT licence (`THIRD-PARTY-LICENSE-Claude-Code-Game-Studios.txt`). `UPGRADING.md` explains how to pull in newer versions of the framework.
