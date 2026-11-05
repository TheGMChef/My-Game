# Board View

Status: DRAFT for approval. Decisions from the user: play you-versus-AI, drag models and tap targets,
explain every step, first layout for tablet landscape (desktop browser comes free, phone later).

## 1. Overview
A top-down 2D view of the 44" x 30" board in Godot. You command player 0 against the scripted AI. Each
phase has a banner and a rules panel; every order is checked by the engine in `src/engine/` and refused
with the reason when illegal. The view contains no rules of its own: it asks the engine, draws the answer.

## 2. Player fantasy
Sitting at a tabletop with a patient referee: you move things around freely, and the referee tells you
exactly why a move is not allowed, what your shot is likely to do before you take it, and which rule applies.

## 3. Detailed rules (screen and interaction)
**Layout (tablet landscape, 16:10):** board fills the left ~75%; right panel (25%) holds the rules panel
and battle log; a top bar shows round, phase, active player, CP and VP; a bottom bar holds phase actions.

**Scale:** 1" = 40 px in world space. Camera fits the board; pinch or scroll to zoom, two-finger or middle
mouse drag to pan. Minimum touch target 44 px, so unit handles are larger than the bases at low zoom.

**Selecting:** tap a unit to select it. A selected unit shows its stat card (M, T, Sv, W, Ld, OC, weapons)
in the side panel and coloured status chips (battle-shocked, advanced, charged, engaged).

**Movement phase:** drag the selected unit's handle to move the whole unit rigidly; long-press a model then
drag moves it alone. While dragging: a ring shows the maximum distance, the ghost positions turn green or
red from `UnitRules.check_move`, and the panel shows the reason when red ("must end unengaged", 2" gap).
Buttons: Normal / Advance (rolls the die and shows the extended ring) / Fall Back / Hold. Confirm applies the move.

**Shooting phase:** select a unit, tap an enemy. Panel shows, per weapon, models in range, attacks, hit and
wound targets (e.g. "hit on 4+ because the target has cover"), expected unsaved wounds and expected damage.
Fire rolls the dice with a short animation; the log lists each step with the rule number.

**Charge phase:** tap Declare on an eligible unit (within 12", not engaged, did not advance or fall back).
The 2D6 roll appears; targets in reach highlight; drag to move, same live checks as movement.

**Fight phase:** the sequencer decides who may pick; the panel says "Fights First, you choose" or "opponent
chooses". Pile-in (3") and consolidation (3") use the same drag-and-validate flow, then pick targets and fight.

**AI turns:** the AI's orders animate one unit at a time with a log line each; Skip fast-forwards.

**Overlays (toggle):** engagement ranges (2"), coherency links (2"/9"), objective ranges (3"), line of sight
from the selected model to a tapped target, terrain categories, hidden units' 15" detection range.

**Teaching:** each rejection and each rolled step cites the rule section from `design/rules/` in own words.

## 4. Formulas
Odds shown before shooting use exact probabilities, no simulation: p(hit) from BS or WS with unmodified 1 fail
and 6 critical; p(wound) from the strength/toughness table; p(unsaved) from save, AP and invulnerable save;
expected damage = attacks x p(hit) x p(wound) x p(unsaved) x average damage, with the ability effects (Lethal
Hits, Sustained Hits, Devastating Wounds, Anti, Rapid Fire, Blast, etc.) folded in. Needs a new
`AttackOdds` class in the engine, tested against the dice resolver by Monte Carlo.

## 5. Edge cases
Unit destroyed mid-drag; illegal move leaves the unit where it started; undo before confirm only; touch
and mouse give identical behaviour; resizing the window keeps the board centred; AI never acts during the
human's turn; a game over screen shows VP and a battle summary.

## 6. Dependencies
Engine additions needed first (each test-first): a step-wise `Battle` API (begin turn, run a single phase,
hand control to the player instead of `SimpleAI`), `AttackOdds`, and a log with rule references.
Scenes and scripts go under `src/` (UI) with data from `assets/data/`.

## 7. Tuning knobs
Pixels per inch; animation speed; AI step delay; touch target size; colours for sides, terrain categories,
and status chips; which overlays start on.

## 8. Acceptance criteria
1. Launches in a browser export and in the Godot editor, board fills the window at tablet landscape size.
2. A full 5-round game can be played against the AI with touch or mouse only.
3. Every illegal move shows its reason; every legal move matches `UnitRules`/`ChargeRules`/`MeleeMoves`.
4. Pre-shot odds equal the engine's long-run results within Monte Carlo error (automated test).
5. Retained screenshots in `production/qa/evidence/` for: board at start, movement drag legal and illegal,
   shooting panel with odds, charge, fight, game over.

## Build order
1. Engine: step-wise `Battle`, `AttackOdds` (tests first).
2. Static board: terrain, objectives, units, camera.
3. Selection, stat card, phase banner.
4. Movement with live validation.
5. Shooting with odds panel, then charge, then fight.
6. AI turn playback, game over, overlays.
7. Web export check and screenshots.

## Open questions
- Web export needs a Web export preset and export templates; the sandbox may not have templates, so the browser build may have to be exported on your machine.
- Screenshots need a rendering driver; I will check whether the sandbox can render headlessly before promising retained screenshots.
