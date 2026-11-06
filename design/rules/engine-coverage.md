# Engine coverage against the 11th edition core rules

Section numbers refer to the official core rules PDF (1 Jun 2026) as summarised in
`11th-edition-core-rules.md`. Code lives in `src/engine/`.

## Implemented and tested
| Rule | Where | Notes |
|---|---|---|
| Leadership and battle-shock rolls (01.06, 01.07) | `unit_rules.gd` | Shock zeroes OC for objectives |
| Coherency, engagement (03.03, 03.04) | `unit_rules.gd` | Flat 2D, vertical limits ignored |
| Attack sequence (05) | `attack_resolver.gd` | Save groups simplified, see below |
| Mortal wounds, hazard rolls (06.02, 06.03) | `attack_resolver.gd` | |
| Deployment, first-turn roll-off | `battle.gd`, `unit_rules.gd` | Alternating set-up, Defender first. Attacker and Defender are fixed by side. See `stratagems.md` |
| Command phase: CP, battle-shock (08) | `turn_flow.gd`, `battle.gd` | Starting CP not sourced, so 0. Tests run one unit at a time so stratagems can step in |
| Normal, advance, fall-back moves (09) | `unit_rules.gd` | Ordered retreat only |
| Charge (11) | `charge_rules.gd` | Per-model "must end within 1"" clauses not enforced |
| Pile-in, fight order, consolidation (12) | `melee_moves.gd`, `fight_sequencer.gd` | Overrun fights not wired |
| Stratagems (15) | `stratagems.gd`, `battle.gd`, `simple_ai.gd` | All core stratagems except Rapid Ingress, which needs reserves and shows greyed. Snap shooting included. See `stratagems.md` |
| Terrain: categories, cover, hidden, obscuring, solid (13) | `terrain_area.gd`, `visibility.gd` | 2D approximation, sample-point lines |
| Objectives and VP (mission data) | `missions.gd` | Placeholder scenario |
| Weapon abilities (24) | `attack_resolver.gd`, `combat.gd` | Anti, Blast, Cleave, Close-quarters flag, Devastating Wounds, Extra Attacks, Hazardous, Heavy, Ignores Cover, Lance, Lethal Hits, Melta, Rapid Fire, Sustained Hits, Torrent |
| Feel No Pain, Fights First (24.12, 24.13) | `attack_resolver.gd`, `unit_state.gd` | |
| Stealth, Lone Operative, Deadly Demise (24) | `combat.gd`, `battle.gd` | Deadly Demise rolls once per unit |
| Faction army rules | `army_rules.gd`, `battle.gd` | See `keyword-conversion.md` |

## Simplifications that matter
- **Save groups:** every model in a unit shares one profile. CHARACTER models are only ordered last.
- **Visibility:** lines are drawn between 5 sample points per base. Cover uses the nearest attacking model.
- **Dense terrain height:** only used for movement (2" rule). Climbing and plunging fire are not modelled.
- **Shooting:** all models with the target visible and in range fire. No per-model weapon choice, Assault (advanced units), indirect fire and One Shot are enforced; close-quarters shooting is not. Weapon keywords done: Twin-linked (re-roll wounds, 10th rule, unverified for 11th), Assault, Indirect Fire, One Shot, Precision, Psychic.

## Not implemented yet
Transports and embarking, attached units and leaders, strategic reserves and ingress (so Rapid Ingress),
aircraft, flying and Super-heavy Walker, desperate escape, overrun fights, Scouts and Infiltrators, actions,
secured objectives, a smarter AI, and Command Re-roll on hit, wound, save, damage, hazard and attack-count dice.

## Not sourceable from the supplied PDFs (left out on purpose)
Modifier caps and ordering, re-rolls, characteristic modifier stacking, random characteristics,
rules sequencing, army muster and points values, and the 11th edition mission deck. Starting CP is not
in any source checked so far. Who goes first is now sourced: a roll-off after deployment.
