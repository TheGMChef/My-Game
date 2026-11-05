# Keyword conversion: 10th edition datasheets to 11th edition rules

The supplied datasheets are the 2023 10th edition indices. The rules are 11th edition. This is how
`tools/datasheets/map_datasheets.py` and the engine bridge the two. Every unit's own list is in its
conversion report, `data/local/report_<faction>.md`.

**Sources:** `11th-edition-core-rules.md` (from the official core rules PDF) first, then the Wahapedia
11th edition Combat Patrol rules page for FAQ notes, and the official faction packs (Necrons, Tyranids,
Leagues of Votann, Death Guard, T'au Empire) and Space Marines update for army rules and unit changes.

Pack changes to units live in `data/local/corrections/<faction>.json`, applied by
`tools/datasheets/apply_corrections.py` on each rebuild. They stay local, like the army files.

## Weapon abilities

All of these keep their name and apply through the 11th edition rule:

ANTI-X, ASSAULT, BLAST, CLEAVE, DEVASTATING WOUNDS, EXTRA ATTACKS, HAZARDOUS, HEAVY, IGNORES COVER,
INDIRECT FIRE, LANCE, LETHAL HITS, MELTA, ONE SHOT, PRECISION, PSYCHIC, RAPID FIRE, SUSTAINED HITS,
TORRENT, TWIN-LINKED.

| Converted | To | Why |
|---|---|---|
| PISTOL | CLOSE-QUARTERS | The two are identical in 11th edition. Datasheets keep PISTOL, and the engine renames it on load |
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
| Support | Stand-in: fights as its own unit. No definition in the supplied rules |

## Army rules

| Rule | Treatment |
|---|---|
| Reanimation Protocols | Applied at the end of your Command phase, healing D3 wounds |
| Synapse | Applied: TYRANIDS within 6" of a friendly SYNAPSE model test Battle-shock on 3D6 and get +1 Strength in melee |
| Shadow in the Warp | Applied: a once-per-battle button in your Command phase. Enemies near your SYNAPSE units test at -1 |
| For the Greater Good | Applied: a selected unit can mark a visible enemy as Spotted. Other units with the rule get +1 BS against it, and MARKERLIGHT observers also give IGNORES COVER |

**Assumption, unverified:** the supplied rules never define "heal". Wounded models heal first, then
destroyed models return with 1 wound, up to starting strength. Without this, Reanimation would do
nothing for 1-wound models. Change `ArmyRules.reanimate` if the rule turns out to be wounds only.

**Timing change:** you mark Spotted units during your Shooting phase, not all at its start.

**Aircraft whose packs print Move "-"** keep their old Move, because no aircraft rules exist yet.

## Not converted

- **Nurgle's Gift, Oath of Moment and Eye of the Ancestors** have no source for their base rules, so
  they're stored on units but do nothing.
- **Unit-specific and conditional abilities**, such as reworded named abilities, the Canoptek
  Reanimator's extra healing, and -1 to melee hits on the Chronomancer, aren't applied.

- **Unit-specific weapon rules** on fortifications, [DEFENSIVE ARRAY] and [HIVE DEFENCES], aren't core
  abilities. Reports list them as not applied.
- **[CONVERSION]** isn't in the 11th edition core rules, and its current wording wasn't found. It's only
  on two optional Leagues of Votann weapons, so it doesn't affect default loadouts. Reports list it.
- **Faction rules** such as Reanimation Protocols and named unit abilities need the faction packs and
  their own engine work. Reports list them as not applied.
- **Damaged profiles** are read from the sheet but not applied.
- **Datasheet values** are still 10th edition. A stat or weapon that changed for 11th edition is not
  corrected here. That's the job of the `rules-checker` agent.
