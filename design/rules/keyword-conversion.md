# Keyword conversion: 10th edition datasheets to 11th edition rules

The supplied datasheets are the 2023 10th edition indices. The rules are 11th edition. This is how
`tools/datasheets/map_datasheets.py` and the engine bridge the two. Every unit's own list is in its
conversion report, `data/local/report_<faction>.md`.

**Sources:** `11th-edition-core-rules.md` (from the official core rules PDF) first, then the Wahapedia
11th edition Combat Patrol rules page for FAQ notes. Faction packs were not available for this pass.

## Weapon abilities

All of these keep their name and apply through the 11th edition rule:

ANTI-X, ASSAULT, BLAST, CLEAVE, DEVASTATING WOUNDS, EXTRA ATTACKS, HAZARDOUS, HEAVY, IGNORES COVER,
INDIRECT FIRE, LANCE, LETHAL HITS, MELTA, ONE SHOT, PRECISION, PSYCHIC, RAPID FIRE, SUSTAINED HITS,
TORRENT, TWIN-LINKED.

| Converted | To | Why |
|---|---|---|
| PISTOL | CLOSE-QUARTERS | The two are identical in 11th edition |
| Squashed text such as SUSTAINEDHITS1 or ANTI-VEHICLE4+ | SUSTAINED HITS 1, ANTI-VEHICLE 4+ | The PDF text can lose spaces |
| Dice values: SUSTAINED HITS D3, RAPID FIRE D6 | SUSTAINED HITS 2, RAPID FIRE 4 | The engine has no dice values for abilities, so these use the average, rounded up |
| Source typos: ANTI-VECHILE, DEVESTATING WOUNDS, TWIN -LINKED | The correct spelling | Logged as a warning on the unit |

HEAVY uses the 11th edition test (no model moved more than 3"), and TWIN-LINKED is a re-roll of the
wound roll. Any other tag is reported as "not applied".

## Core unit abilities

| Ability | Treatment |
|---|---|
| Feel No Pain X+ | Applied |
| Fights First | Applied |
| Stealth | Applied: ranged attacks against the unit count as having cover |
| Lone Operative | Applied: can't be shot from beyond 12". The X" form and attached units aren't handled |
| Deadly Demise X | Applied: rolled once per unit on destruction, measured from the last model to fall |
| Deep Strike, Infiltrators | Stand-in: deploys normally |
| Scouts | Stand-in: no pre-battle move, deploys normally |
| Leader | Stand-in: fights as its own unit |
| Firing Deck, Hover | Unused: no transport or aircraft rules yet |
| Super-heavy walker | Stand-in: moves as a normal unit |

## Not converted

- **Unit-specific weapon rules** on fortifications, [DEFENSIVE ARRAY] and [HIVE DEFENCES], aren't core
  abilities. Reports list them as not applied.
- **[CONVERSION]** isn't in the 11th edition core rules, and its current wording wasn't found. It's only
  on two optional Leagues of Votann weapons, so it doesn't affect default loadouts. Reports list it.
- **Faction rules** such as Reanimation Protocols and named unit abilities need the faction packs and
  their own engine work. Reports list them as not applied.
- **Damaged profiles** are read from the sheet but not applied.
- **Datasheet values** are still 10th edition. A stat or weapon that changed for 11th edition is not
  corrected here. That's the job of the `rules-checker` agent.
