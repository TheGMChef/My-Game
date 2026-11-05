# 11th edition rules: research notes (in my own words)

Personal-use reference for building the sim. Not a copy of the rulebook. Check
every item against the official core rules before relying on it.

## Sources and status

| Source | What it is | Date / version |
|---|---|---|
| [Warhammer Community: core rules announcement](https://www.warhammer-community.com/en-gb/articles/nhqt9wx3/new40k-rules-download-the-free-core-rules-now/) | Official. Says the free 11th edition core rules are out. Links only to the downloads page, no PDF URL | 1 Jun 2026 |
| [Warhammer Community: downloads page](https://www.warhammer-community.com/en-gb/downloads/warhammer-40000/) | Official. Currently lists only the online Munitorum Field Manual (points) | MFM updated 14 Oct 2026 |
| [Warhammer Community: "Updates Update"](https://www.warhammer-community.com/en-gb/articles/cumo9vbg/the-warhammer-40000-updates-update/) | Official. Rules updates at most monthly, balance updates quarterly (next: week of 7 Dec 2026). A dated Rules Update Log is promised with the next app version | 29 Oct 2026 |
| [Wahapedia 11th edition Combat Patrol core rules](https://wahapedia.ru/wh40k11ed_cp/the-rules/core-rules/) | Third-party site that tracks the official text and shows FAQ and errata notes inline. Shows core rules "Edition 11, version 2.7.1", last update Oct 2026 | Oct 2026 |

**Not found:** an official 11th edition core rules PDF, an official Combat Patrol
PDF, or a separate errata document. The PDF links I found on warhammer40000.com
and warhammer-community.com are 2023 files (10th edition). Do not use them.

**Read so far:** sections 01, 03, 04, 05, 06 and 12 of the Wahapedia page.
**Not read yet:** 02 datasheets, 07 to 11 (battle round, command, movement,
shooting, charge), most of 13 terrain, 14 objectives, 15 stratagems, 16 actions,
17 to 25. The page text is about 408,000 characters and the tool I used reads it
in lossy chunks.

**Known gaps in what I read:** the hit and wound tables came through with blank
numbers, so the strength-versus-toughness thresholds are not confirmed. Benefit
of cover, Heavy, Torrent, Devastating Wounds, Feel No Pain values and re-roll
limits are in sections 13 and 24, not read yet.

## Confirmed so far

- **Distances** are measured to the closest part of a base. A model without a base
  (usually a MONSTER or VEHICLE) has the FRAME keyword and is measured from its
  closest point.
- **Engagement range** is 2" horizontally and 5" vertically.
- **Coherency:** each model within 2" horizontally and 5" vertically of another
  model in its unit, and within 9" horizontally and 5" vertically of every other
  model. A unit that ends a turn out of coherency loses models one at a time
  until it is back in coherency; they count as destroyed but trigger nothing.
- **Move types:** normal (up to M, unengaged), advance (D6 added to M, unengaged,
  then no charging or starting actions), fall back (up to M, engaged; needs an
  "ordered retreat" unless battle-shocked, otherwise a desperate escape with a
  hazard roll per model).
- **Models can't pass through enemy models**; they can pass through friendly ones.
- **Attack sequence:** hit roll, wound roll, save roll, inflict damage. An
  unmodified 1 always fails. Critical hits and wounds still hit and wound, and can
  trigger other rules.
- **Saves:** invulnerable save ignores AP; armour save is worsened by AP.
  Save-roll dice are grouped by identical wounds, save and invulnerable save, and
  each CHARACTER is its own group. Wounded non-CHARACTER models are allocated
  first, and a CHARACTER cannot take wounds ahead of non-CHARACTER models.
- **Damage:** a model that reaches 0 wounds is destroyed. Excess attacks are lost
  when the unit is gone. There is no spill-over to the next model.
- **Mortal wounds** are taken by a wounded non-CHARACTER, then any non-CHARACTER,
  then wounded CHARACTER, then any CHARACTER. Normal damage resolves before mortal
  wounds.
- **Hazard roll:** D6, fails on 1 or 2, the unit takes 1 mortal wound (3 if every
  model is a MONSTER or VEHICLE).
- **Battle-shocked units** treat OC as '-', can't be targeted by stratagems, and
  can't start actions. Leadership is a 2D6 roll that must equal or beat Ld.
- **Fight phase order:** pile in (up to 3", both players, active player first),
  fight (Fights First units, then the rest, alternating), consolidate (up to 3",
  three kinds: ongoing, engaging, objective). Overrun fights exist for units that
  are unengaged.

## Differences that matter for the TypeScript prototype

| Prototype | 11th edition |
|---|---|
| Engagement range 1" | 2" horizontal and 5" vertical |
| Unit is one circle | Individual models, coherency, per-model removal |
| Damage capped to the lead model | Same idea, but allocation groups and CHARACTER ordering |
| Moving into contact is a free charge | Separate charge phase with a charge roll (rules not read yet) |
| No terrain, no line of sight | Terrain areas, visibility, cover (13, not read yet) |

## Errata and FAQ items seen inline (so far)

- A "+1 A" effect raises the weapon's A characteristic; it does not add a die to
  each attack.
- Snap shooting only hits on an unmodified 6.
- A save modified above 6 is still rolled, and other models with better saves can
  take those wounds.
- Failed hazard rolls from HAZARDOUS weapons wound the unit, not the carrier, and
  a rule requiring a hazard roll gives one roll per unit.
- Fight phase 12.08 (ongoing consolidation) has an errata replacing its After
  Moving text about enemy units not yet selected to fight.
