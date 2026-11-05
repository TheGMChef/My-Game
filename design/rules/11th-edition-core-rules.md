# 11th edition core rules: working summary

Written in my own words from the official core rules PDF (Warhammer Community,
1 June 2026) plus the Universal Rules Updates v1.1 (legal from 26 Aug 2026).
Section numbers like (05.03) match the PDF so each item can be checked.
This is a reference for building the sim, not a copy of the rulebook.

Items marked **NOT SOURCEABLE** are not covered by the PDF (the PDF says they
live in the Warhammer 40,000 app). Do not fill them in from memory or from
earlier editions. Items marked **WAHAPEDIA** come from the third-party site's
inline FAQ notes (version 2.7.1, Oct 2026), not from the PDF.

## 1. Basics (01 to 03)

- **Dice:** D6. D3 is a D6 halved, rounded up. A leadership roll is 2D6 and
  succeeds if it equals or beats a Ld of the unit.
- **Distances** are in inches, measurable any time, to the closest part of a base.
  Models without a base (FRAME keyword) are measured from their closest point.
- **Active player:** whoever's turn it is, except a unit's controller is the
  active player while that unit moves, shoots or fights.
- **Battle-shock roll** (01.07): a leadership roll. On a fail the unit is
  battle-shocked: OC becomes '-', it can't be targeted by stratagems, it can't
  start actions and any action it started cannot complete.
- **Profiles** (02): M, T, Sv, optional InSv, W, Ld, OC. Weapons: Range, A, BS or
  WS, S, AP, D. A model reduced to 0 or fewer wounds is destroyed.
- **Moving** (03.01): models move one at a time in straight lines and rotations.
  They can pass through friendly models, not enemy models, and can't cross the
  battlefield edge. Rotation is free. Moving back and forth adds up.
  A move is illegal and is undone if the unit ends out of coherency, a model is
  on or partway through a terrain surface, or an "after moving" condition fails.
- **Coherency** (03.03): each model within 2" horizontally and 5" vertically of at
  least one other model in its unit, and within 9" horizontally and 5" vertically
  of every other model. At the End of Turn step, a unit out of coherency loses
  models one at a time until it is back in (they count as destroyed but trigger
  nothing).
- **Engagement range** (03.04): 2" horizontally and 5" vertically. Opposing
  models in each other's range are engaged. A unit with no engaged models is
  unengaged.
- **Set up** (03.02): units are placed in coherency and unengaged. If a unit can't
  be fully set up it goes back where it came from and has not made that move.

## 2. Making attacks (04 and 05)

1. **Select weapons.** Shooting: any number of ranged weapons per model. Fighting:
   exactly one melee weapon per model.
2. **Select targets.** Shooting: each weapon picks one enemy unit that is visible,
   in range and unengaged (unless a rule says otherwise). Fighting: each target
   must be engaged with the model, and a weapon can't have more targets than its
   A. Melee attacks split between several targets must give at least one to each.
3. **Resolve attacks.** Pick an enemy unit, gather attack dice (A per weapon,
   identical attacks are pooled), run the attack sequence, repeat.
   Identical attacks share BS/WS, S, AP, D and the same applicable abilities.

**Attack sequence** (05), all dice of a step rolled together:

| Step | Result |
|---|---|
| Hit roll | Unmodified 1 fails. Unmodified 6 is a critical hit (still a hit). Otherwise a hit if the roll is at least BS/WS. |
| Wound roll | Unmodified 1 fails. Unmodified 6 is a critical wound (still a wound). Otherwise it needs: S at least twice T: 2+. S greater than T: 3+. S equal to T: 4+. S less than T: 5+. S half T or less: 6+. |
| Save roll | See below. |
| Inflict damage | The model loses D wounds. 0 or fewer destroys it. Excess attacks are lost once the unit is destroyed. |

The wound table was read from the page graphic (dice faces): 2+, 3+, 4+, 5+, 6+.
Check it against your own copy once.

**Saves** (05.03 and 05.04):
- Groups: each CHARACTER is its own group. All other models with the same W, Sv
  and InSv form one group.
- Allocation order: a non-CHARACTER group with a wounded model goes first. No
  CHARACTER group can come before a non-CHARACTER group. Wounded CHARACTER groups
  come before unwounded ones. The defender chooses the rest of the order.
- The defender rolls one D6 per wounding attack. Results are resolved lowest to
  highest. For each, pick a model in the current group (a wounded one if possible).
  - Unmodified roll at least the InSv: the attack fails.
  - Otherwise the roll plus AP (AP is negative, so it lowers the roll) must be at
    least Sv, or the attack fails.
  - Anything else inflicts damage.
- When every model in the current group is destroyed, the next group becomes current.

**Mortal wounds** (06.02): taken one at a time by a wounded non-CHARACTER, then
any non-CHARACTER, then a wounded CHARACTER, then any CHARACTER. Each removes
1 wound. Normal damage resolves before mortal wounds.

**Hazard roll** (06.03): D6, fails on 1 to 2, the unit takes 1 mortal wound (3 if
every model is a MONSTER or VEHICLE).

**Visibility** (06.01): a 1 mm line from any part of the observer to any part of
the target, ignoring models in the observer's own unit and the target's unit.
Visible means any part is seen. Fully visible means every part facing the observer
is seen. A unit is visible if any model is, fully visible if all are.

**Starting strength** (appendix): models at the start of battle round 1. At
half-strength or below-half-strength is measured in models for units of 2 or more
and in wounds for a single-model unit. A single model with an odd W can't be
exactly at half.

## 3. The battle round (07 to 12)

A round is: start of round, each player's turn, end of round. The same player goes
first every round (the mission says who). A turn is: start of turn, Command,
Movement, Shooting, Charge, Fight, end of turn. A battle normally lasts five rounds.

**Command phase** (08): both players gain 1 CP. The active player makes a
battle-shock roll for each unit that is battle-shocked or at or below
half-strength. A battle-shocked unit that passes is no longer battle-shocked.

**Movement phase** (09): every unit must be selected once, even to remain
stationary. Move types:
- **Normal:** up to M, unengaged, must end unengaged.
- **Advance:** D6 added to M, unengaged, must end unengaged. The unit can't
  declare a charge or start an action this turn (unless a rule says otherwise).
- **Fall back:** up to M, engaged. Ordered retreat if not battle-shocked,
  otherwise desperate escape (a hazard roll per model, may pass through enemy
  models). Must end unengaged. The unit can't shoot, charge or start actions this
  turn. After a desperate escape a unit that isn't battle-shocked must make a
  battle-shock roll.

**Shooting phase** (10): units shoot one at a time. Shooting types:
- **Normal:** unengaged, did not advance.
- **Assault:** unengaged, advanced, has [ASSAULT] weapons, and may only use those.
- **Close-quarters:** engaged, did not advance, has [CLOSE-QUARTERS] weapons or is
  a MONSTER or VEHICLE. Targets the units it is engaged with. MONSTER and VEHICLE
  attacks take -1 to hit unless they are [CLOSE-QUARTERS] attacks on an engaged
  unit, and can't use [BLAST] against engaged units. Other models may only use
  [CLOSE-QUARTERS] weapons.
- **Indirect:** unengaged, did not advance, has [INDIRECT FIRE] weapons. Can
  target non-visible units, the target gets cover, no hit re-rolls, and a hit
  needs an unmodified 6 (or 4+ if the unit stood still and a friendly unit sees
  the target).
- Engaged MONSTER and VEHICLE units can be shot at by ranged attacks, at -1 to hit
  (no penalty for [CLOSE-QUARTERS] weapons used by a unit engaged with it), and
  not with [BLAST] weapons (17.03).

**Charge phase** (11): to declare, a unit must be on the battlefield, within 12"
of an enemy, unengaged, and not have advanced or fallen back. Roll 2D6 for the
maximum distance. Choose enemy units within 12" and within that distance as charge
targets. Each model must end closer to a charge target, within 1" of one if it can,
and engaged with one if it can. The unit must end engaged with all charge targets
and no other enemy units. A roll of 2 can never succeed, because the unit can't
start within 2". Chargers have Fights First until end of turn.

**Fight phase** (12), in order:
1. **Pile in** (up to 3"): both players, active player first, units that are
   engaged, charged this turn, or are making an overrun fight. Models in base
   contact don't move. Each moved model ends closer to the closest target and
   engaged if possible. The unit must end engaged, and models that started engaged
   must stay engaged with that unit.
2. **Fight:** a unit is eligible if it hasn't fought and is engaged (or was at the
   start of this step) or charged. Fights First units go first, players alternating
   starting with the active player. Then the remaining units, alternating. After
   each remaining fight, go back to Fights First if any unit became eligible.
   Types: normal fight (engaged) or overrun fight (unengaged, or was unengaged at
   the start but became engaged; makes one extra pile-in first). A player with no
   eligible unit within 5" of an enemy can pass.
3. **Consolidate** (up to 3"): units that were eligible to fight. Modes in order:
   ongoing (if engaged, mandatory), engaging (if an enemy is within 3", must end
   engaged and any not-yet-fought enemy units it ends engaged with get to fight),
   objective (if an objective is within 3", must end within range of it).

## 4. Terrain and objectives (13 and 14)

- **Categories:** exposed (craters, razorwire), light (barricades, low walls),
  dense (buildings, ruins, containers, woods).
- **Movement:** exposed and light can be crossed by anything. Dense: INFANTRY,
  BEASTS, SWARM and MOBILE models can move through horizontally, and the first
  three can also move vertically. Other models can only cross sections 2" tall
  or less, otherwise they climb vertically and can't end on a non-ground surface.
  Moving vertically means staying within 1/2" of the feature and the distance
  counts. Models may end on upper surfaces only if INFANTRY, BEASTS, SWARM, FLY or
  MONSTER, stable, and not overhanging the edge.
- **Benefit of cover:** if every model in the target is either INFANTRY, BEASTS or
  SWARM within a terrain area, or not fully visible because of terrain, each
  ranged attack against it has BS worsened by 1.
- **Hidden:** INFANTRY, BEASTS or SWARM within a terrain area containing dense
  terrain, whose unit made no ranged attacks this turn or last turn. A hidden model
  is only visible to enemies within its detection range, 15" unless stated.
- **Obscuring:** a terrain area with light or dense terrain. If every line of sight
  between two models crosses one (not counting areas either model is inside), they
  can't see each other.
- **Solid:** dense terrain. Line of sight can't cross an enclosed gap 3" or less
  above the ground.
- **Plunging fire** (22.05): +1 BS against a visible unit with ground-level models
  if the attacker is on a section 3" or taller, or has TOWERING and the target is
  within 12". No effect for AIRCRAFT.
- **Objectives:** a terrain area is the objective. A model is within range while
  inside that area. At the end of each phase and turn, add up the OC of each
  player's models in range. The higher total controls it, a tie means nobody does
  (unless it is secured). A secured objective stays yours until your opponent has
  a higher total at the end of a phase. Objective markers (40 mm) are used when no
  terrain area is present: range is 3" horizontally and 5" vertically.

## 5. Stratagems and actions (15 and 16)

- Each player gains 1 CP per turn (08.02). A player can't use the same stratagem
  twice in a phase, and can't target one unit with two stratagems in a phase
  unless stated.
- **Core stratagems:** Command Re-roll 1CP (re-roll one die, or a charge roll in
  full), Epic Challenge 1CP (a CHARACTER's melee gains [PRECISION]), Insane Bravery
  1CP (auto-pass a battle-shock roll, once per battle), Explosives 1CP (six D6,
  each 4+ is a mortal wound, within 8"), Crushing Impact 1CP (roll T dice, 1s hurt
  you, 5+ hurt them, max 6), Rapid Ingress 1CP, Fire Overwatch 1CP (snap shooting:
  one visible enemy within 24", hits only on unmodified 6, no re-rolls, not
  TITANIC), Smokescreen 1CP, Heroic Intervention 1CP (a charge in the opponent's
  Charge phase, +1CP for the "Into the Fray" mode), Counteroffensive 2CP (Fights
  First, and it fights next).
- **Actions:** a unit can't start one if battle-shocked, OC is 0 or '-', engaged
  (TITANIC excepted), advanced or fell back, or already started another. Starting
  one stops shooting (TITANIC excepted) and declaring charges. Moving or leaving the
  battlefield stops it completing.

## 6. Advanced rules (17 to 23)

- **MONSTER and VEHICLE:** can move through friendly and enemy models (not other
  MONSTER or VEHICLE) on normal and advance moves.
- **Transports** (18): units embark if every model is within 3" after a normal,
  advance or fall-back move and they weren't set up this turn. Disembark in the
  Movement phase: rapid (3", transport made a normal or ingress move, no charge),
  tactical (3", transport stood still or hasn't moved yet, the unit then moves),
  combat (6", hazard roll per model, then battle-shocked and no charge). A destroyed
  transport lets its passengers make an emergency disembark (6", a hazard roll per
  model, models that don't fit are destroyed, then battle-shocked). Updated by the
  Universal Rules Updates below.
- **Attached units** (19): a leader or support unit leads a bodyguard unit and the
  two become one unit. Attacks use the highest T of the bodyguard models if any
  remain. Destroyed-unit rules trigger only when the last original model is gone.
- **Strategic reserves** (20): up to 50% of the points limit. They arrive by ingress
  move from round 2, wholly within 6" of a battlefield edge and more than 8" from
  enemies (and not in the opponent's deployment zone before round 3). Units still
  in reserve at the end of round 3 are destroyed.
- **Flying** (21): a FLY unit can take to the skies (minus 2" distance) to ignore
  vertical distance and pass through everything. Surge moves go toward the closest
  enemy, must end engaged if possible, and the unit can't then move again.
- **Aircraft** (23): start in reserve, only make ingress moves, go back to reserve
  at the end of the opponent's turn, can only be charged and fought by FLY units.

## 7. Core and weapon abilities (24)

| Ability | Effect |
|---|---|
| [ANTI-X Y+] | Unmodified wound roll of Y+ against keyword X is a critical wound |
| [ASSAULT] | Allows assault shooting |
| [BLAST X] | Add X (1 if unnumbered) attack dice per 5 models in the target, rounded down. Can't target engaged units |
| [CLEAVE X] | Add X dice per 5 models in the target, if all attacks go to one target |
| [CLOSE-QUARTERS] / [PISTOL] | Allows close-quarters shooting (the two are identical) |
| Deadly Demise X | When destroyed, D6: on a 6 each unit within 6" takes X mortal wounds |
| Deep Strike | Ingress anywhere more than 8" from enemies |
| [DEVASTATING WOUNDS] | A critical wound ends the sequence and inflicts mortal wounds equal to D (one model max) |
| [EXTRA ATTACKS] | Used in addition to another melee weapon |
| Feel No Pain X+ | Each time a wound would be lost, roll a D6: X+ ignores it |
| Fights First | While all models have it, the unit is a Fights First unit |
| Firing Deck X | Embarked models' weapons can be used by the transport |
| [HAZARDOUS] | After the attacks, one hazard roll per such weapon used |
| [HEAVY] | +1 to hit in your Shooting phase if unengaged, not set up this turn, and no model moved more than 3" |
| Hover | Taking to the skies doesn't cost 2" |
| [IGNORES COVER] | Target gets no benefit of cover |
| [INDIRECT FIRE] | Allows indirect shooting |
| Infiltrators | Set up anywhere more than 8" from the enemy deployment zone and enemy units |
| [LANCE] | +1 to wound if the unit charged this turn |
| [LETHAL HITS] | A critical hit may automatically wound (no wound roll, so it can't be a critical wound) |
| Lone Operative (X") | Not visible beyond 12" (or X") unless part of an attached unit |
| [MELTA X] | +X damage if the target was within half range |
| [ONE SHOT] | Once per battle |
| [PRECISION] | A visible CHARACTER group can be made the current allocation group |
| [PSYCHIC] | Ignore modifiers to BS/WS and to the hit roll |
| [RAPID FIRE X] | +X dice within half range |
| Scouts X" | Pre-battle move |
| Stealth | Ranged attacks against the unit get cover |
| [SUSTAINED HITS X] | A critical hit scores X extra hits |
| Super-heavy walker | Moves through models and terrain up to 4" tall, can gain MOBILE (1 on a D6 battle-shocks it) |
| [TORRENT] | Automatically hits |
| [TWIN-LINKED] | May re-roll the wound roll |

Duplicate instances of the same ability don't stack: pick one each time attacks are
made (24.02). An ability followed by keywords only applies against units with them.

## 8. Updates after the core rules

**Universal Rules Updates v1.1** (legal from 26 Aug 2026):
- A rule giving a stratagem for 0CP without naming it reduces that stratagem's cost by 1CP.
- Parts of rules that let you reuse a stratagem in the same phase, or beyond its use limit,
  only work if the rule names the stratagem.
- Stratagem effects limiting ranged targeting to "within 12"" now say 18".
- Stratagems that add a copy of a destroyed unit are limited to once per battle.
- A unit disembarking from a transport that made a normal move, and allowed to charge,
  makes an assault disembark move (18.06). A unit disembarking from a transport that
  advanced makes a shock disembark move (18.07). (Those two move types are not in the
  launch PDF: NOT SOURCEABLE until the app text is available.)

**Faction packs** (Necrons v1.3, 30 Sep 2026; Tyranids and Leagues of Votann 14 Oct 2026;
T'au Empire, undated) hold detachments, datasheets and per-faction updates. The Space
Marines printed-product update (v1.1, 14 Oct 2026) changes individual datasheets. These
are unit data, so they go in your own JSON, not in this document.

**WAHAPEDIA FAQ notes (not in the PDF, version 2.7.1):**
- "+1 A" raises each weapon's A, it does not add a die per attack.
- Snap shooting only hits on an unmodified 6.
- A save modified above 6 is still rolled, and models with better saves can absorb those results.
- HAZARDOUS failures wound the unit, not the carrier. A rule requiring a hazard roll for a
  unit gives one roll per unit.
- Models removed for coherency still count for objectives.
- Moving through an enemy's engagement range doesn't make a unit engaged.
- Overrun fight needs the unit to be eligible to fight as well.
- Errata to 12.08: wording for engaging consolidation and enemy units not yet selected to fight.

## 9. NOT SOURCEABLE from the documents I have

These are in the Warhammer 40,000 app or the mission pack, not in the PDFs. The sim
must not guess them.

- Modifying dice rolls: limits on how much hit, wound and save rolls can be modified,
  and the order modifiers apply. Re-roll rules (how many times a die can be re-rolled).
- Characteristic modifiers (stacking), random characteristics, "rules sequencing"
  when two rules trigger together.
- The rules for the Declare Battle Formations, Resolve Pre-battle Abilities and
  Begin the Battle steps, and the Muster Armies rules.
- **Combat Patrol:** battle size (points), battlefield size, deployment maps, mission
  rules and scoring, who goes first. These come from the mission deck, which I don't
  have. The faction packs you sent don't include them either.
- Points values (online Munitorum Field Manual).
- The two disembark move types added by the Universal Rules Updates.
- Terrain footprints: the footprint PDFs you sent are printed-outline graphics, so
  they hold layouts, not rules text.
