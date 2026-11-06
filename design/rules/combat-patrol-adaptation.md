# Adapting the Combat Patrol placeholder to 11th edition

Status: the Combat Patrol book you supplied is the 2023 (10th edition) version. The
scenario in `assets/data/scenario_clash_of_patrols.json` is a placeholder built from it.
The engine reads every mission value from that file, so adapting means editing data, not code.

## What the engine already takes from 11th edition (sourced)
- Objective control by total OC in range, and "secured" objectives.
- Battle-shock checks in the Command phase, strategic reserves timing (ingress from round 2,
  destroyed if not arrived by the end of round 3).
- All combat resolution (hit, wound, save, damage, mortal wounds, hazard rolls).

## What to check when the 11th edition mission pack arrives
| Item | Placeholder value | What to check |
|---|---|---|
| Battlefield size | 44" x 30" | Combat Patrol size in the new book |
| Battle rounds | 5 | Unchanged? |
| Deployment zones | 12" deep strips | Shape and depth; tactical or fixed |
| Objective positions | 5 markers, approximate | Exact distances from edges and centre |
| Objective range | 3" | Control range for 11th edition markers |
| Scoring | 5 VP each, max 15 per turn, from round 2 | Amounts, caps, when scored |
| Round 5 timing | second player scores at end of turn | Whether this still applies |
| Securing | non-shocked BATTLELINE at end of Command phase | Whether BATTLELINE still secures, and the OC rules |
| Mission rule | Retrieve Intelligence (1 CP per recovery) | Replaced by a new mission rule? |
| First turn | roll-off after deployment, as the 11th edition mission page says | Nothing, unless the book differs |
| Deployment order | Alternating, Defender first, side 1 is always Defender | Add the Attacker and Defender roll-off if it starts to matter |
| Starting CP | 0, unsourced | The value, if the book gives one |
| Banned stratagems | none (`banned_stratagems`) | The mission page bans Crushing Impact, Explosives and Rapid Ingress: list them once the scenario is confirmed |
| Battle size / points | not modelled | Combat Patrol force composition and points in 11th edition |

## How to adapt
1. Copy the placeholder file, rename the `id`, set `status` to `"confirmed"` once checked.
2. Update each field in the table from the new book.
3. If a rule differs in kind (not just a number), add a field to the scoring section and a
   test in `tests/unit/engine/test_missions.gd` first, then change `src/engine/missions.gd`.
4. Keep rules text out of the repo: store numbers and short own-word summaries only.
