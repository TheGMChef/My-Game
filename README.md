# My-Game

A small tabletop battle simulator with AI opponents. Personal use and testing only; not for release or sharing.

## Overview

A 2D top-down tabletop battle simulator with AI opponents, built in Godot 4.7 with GDScript. Web export comes first, then tablet, then mobile.

## Status

- **Engine set up, no game code yet.** `project.godot` exists (Compatibility renderer, so the web export works) and the project config lives in `project.yaml`.
- **An earlier TypeScript prototype** is kept in `prototypes/ts-battle-sim/` as a reference for the rules and AI. It uses invented placeholder units. See its README to run it.
- **Not yet verified:** Godot isn't installed in the build sandbox, so `project.godot` has not been opened by the engine. Open the folder in Godot 4.7.2 and check it loads.

## Next steps

1. Install Godot 4.7.2 and open this folder as a project.
2. Add a Web export preset (the `build` command in `project.yaml` expects one named `Web`).
3. Design the battle sim (`/brainstorm` or `/quick-design`), then build it with `/dev-story`.

Game data stays out of the repo: no Games Workshop rules text or datasheets. Units are loaded from your own JSON files.

## Built with

The `.claude/` folder, `CLAUDE.md` and `studio-tests/` come from [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) by Donchitos, used under the MIT licence (`THIRD-PARTY-LICENSE-Claude-Code-Game-Studios.txt`). `UPGRADING.md` explains how to pull in newer versions of the framework.
