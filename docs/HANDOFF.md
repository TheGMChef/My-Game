# Project handoff (for Claude Code)

Personal-use 40k battle simulator. Repo: TheGMChef/My-Game, branch `main`. Not for release or sharing.
The owner has supplied official datasheets and rules PDFs and approved using them for development: converting them, running and testing the game with them, and reading them for rules work.
They stay out of git (`data/local/`, gitignored) because the GitHub repo is public. If the owner wants them committed, make the repo private first, then ask for explicit confirmation.

## What it is
- 2D top-down, you vs a scripted AI. Godot 4.7.2, GDScript, Compatibility renderer.
- Targets: web first, then tablet (landscape and portrait, native multi-touch with pinch and pan), then mobile.
- Rules goal: true 11th edition from the official free PDFs. No LLM needed for now.
- Standing owner rules (see CLAUDE.md): ask before writing files in collaboration flows, no commits without instruction, verify UI with retained screenshots in `production/qa/evidence/`.

## State at handoff
- 210 gdUnit4 tests pass headless, plus 5 pytest tests for the importer (`tests/tools`).
- Playable: roster screen, then the board (HUD, odds panel, AI turn playback, game over), desktop and tablet.
- Web export works (`build/web`, gitignored). Roster file upload works in Chromium.
- Last commits: roster screen, importer tooling, tablet layout, web export preset.

## Architecture
- `src/engine/`: rules and state, no UI. `battle.gd` (Battle.cmd_* commands, plain-data events), `unit_state.gd`, `weapon.gd`, `weapon_ability.gd`, `attack_resolver.gd`, `simple_ai.gd` (AI uses the same command API), `army_loader.gd` (finds and prepares army JSON).
- `src/ui/`: `game_root.gd` (HUD and phase handlers), `board_view.gd` (camera, drawing, touch), `roster_screen.gd` (army and unit picker), `ui_text.gd` plus `assets/data/strings_en.json` (all user text; a test scans for missing keys), `ui_tokens.gd`, `ui_theme_builder.gd`.
- UI never owns game state. It calls `Battle.cmd_*` and reads events.
- Data: `assets/data/` holds scenario and invented placeholder armies. Army files: `res://data/local/army_*.json` (gitignored, excluded from export), `user://armies/*.json`, `--armies <path>`, or the Load button.
- Tools: `tools/datasheets/parse_datasheets.py` (PDF to raw JSON via `pdftotext -layout`), `map_datasheets.py` (raw to engine format plus a report of every judgement call), `ui_tour.gd` (screenshot tour, sets `skip_roster`), `roster_flow.gd`, `roster_shot.gd`, `sim_battle.gd` (AI vs AI).
- Scale: sizing by CSS points (`win.size / screen_scale`), base = clamp(min(w/1280, h/800), 1, 2). Touch events with `DEVICE_ID_EMULATION` are ignored in `BoardView`.

## Running
- Godot is not on PATH in some environments. Binary used so far: `Godot_v4.7.2-stable_linux.x86_64`. Run `godot --headless --path . --import` after adding any `class_name` script, or parse errors appear.
- Tests: `godot --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode` and `python3 -m pytest -q tests/tools`.
- Screenshots: `xvfb-run -a godot --path . --resolution 1280x800 --rendering-driver opengl3 -s tools/ui_tour.gd -- <out_dir> <tag>`.
- Web: `godot --headless --path . --export-release Web build/web/index.html` (do not pipe into `head`: it kills the export). Serve over HTTP; nothreads template.
- Release web builds hide script errors. Reproduce on desktop with `data/local` moved aside to test the placeholders-only path.
- Playwright note: a zero-length click does not open the browser file picker. Use down, wait 150 ms, up.

## Datasheet pipeline
- Source: user's Drive folders of per-unit PDFs (T'au, Necrons, Tyranids, Death Guard, Space Marines), downloaded as zips. These are the 2023 10th edition indices, not 11th.
- Stage 1 parses 402 sheets, 396 clean. Six flagged (second ability block on Primarch-style sheets).
- Stage 2 picks the default loadout from "equipped with", keeps weapon counts, fixes source typos (ANTI-VECHILE, DEVESTATING, TWIN -LINKED), and logs issues.
- 11th edition faction packs (T'au, Necrons, Tyranids, Leagues of Votann) and the core rules text were extracted earlier into a scratchpad `rules/` folder. They were not committed.

## Open items, in suggested order
1. Add weapon keywords the engine cannot apply yet. Counts across all armies: TWIN-LINKED 212, ASSAULT 49, PSYCHIC 43, PRECISION 38, ONE SHOT 29, INDIRECT FIRE 26.
2. Decide TWIN-LINKED for 11th: the core rules text has no definition, the T'au pack still prints it. Default if undecided: re-roll wound rolls, marked unverified.
3. Per-weapon counts (for example two carbines on one model), profile choice (standard vs overcharge), mixed-model units (engine uses the first stat line).
4. Leaders and attached units, transports, wargear options, reserves and Deep Strike, Infiltrators, Scouts, aircraft, Deadly Demise, stratagems, desperate escape, overrun fights.
5. Verify datasheet values against the 11th edition packs, unit by unit. Base sizes are estimated (`ArmyLoader.guess_base_mm`).
6. AI-vs-AI soak games with converted armies to find odd units.
7. Housekeeping: `project.yaml` commands use bare `godot`. Real-tablet testing is unverified. Consider hosting the web build.
8. History note: an early commit includes roster screenshots showing real unit names. Replaced in the next commit, still in git history. Scrub only if the owner asks.

## Owner preferences observed
- Wants results, not narration. Mouse and trackpad are not touch: tablet needs its own touch path (pinch zoom, pan).
- Tests use invented fixtures only. Keep conversion decisions logged, and surface what the engine cannot apply.
