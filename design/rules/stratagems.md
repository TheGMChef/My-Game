# Stratagems and deployment: what the engine follows

Own-words notes, for building the sim. Section numbers match the 11th edition core rules. Sources:
the official core rules summary in `11th-edition-core-rules.md`, Wahapedia's 11th edition core rules
and Combat Patrol core rules pages (read November 2026), and its Combat Patrol mission page.

Code: `src/engine/stratagems.gd` (data and target tests), `src/engine/battle.gd` (windows, spending).

## General rules (15.01)

- Order of use: pick targets, pay CP, resolve. No CP, no stratagem.
- A player can't use the same stratagem twice in one phase.
- A player can't target one unit with two stratagems in one phase.
- FAQ: you can't target your own battle-shocked unit (01.07).
- FAQ: an optional extra cost is part of the base cost. Heroic Intervention with Into the Fray is 2CP.
- Dice (01.05.02): a die is never re-rolled twice. Re-rolling a roll made of several dice re-rolls
  them all, except where a rule says one die.

## The stratagems

| Stratagem | CP | When | Target | Effect | Limits |
|---|---|---|---|---|---|
| Command Re-roll (15.02) | 1 | Any phase, just after a listed roll | The friendly unit that rolled | Re-roll that roll. With several dice, one die. A charge roll goes in full | Listed rolls: advance, charge, damage, hazard, hit, save, wound, number of attacks |
| Epic Challenge (15.03) | 1 | Fight phase, just after a friendly CHARACTER unit is picked to fight | That unit | One CHARACTER model's melee weapons gain [PRECISION] to the end of the phase | |
| Insane Bravery (15.04) | 1 | Your Command phase, just before a friendly unit's battle-shock roll | That unit | The roll passes automatically | Once per battle |
| Explosives (15.05) | 1 | Your Shooting phase | A friendly unengaged EXPLOSIVES or GRENADES unit that can shoot and did not advance | Pick an unengaged visible enemy unit within 8". Roll six D6: each 4+ is 1 mortal wound | Same as the old Grenades |
| Crushing Impact (15.06) | 1 | Your Charge phase, just after a friendly MONSTER or VEHICLE ends a charge move | That unit | Pick an engaged enemy unit. Roll D6 equal to the model's T. Each 1 is a mortal wound on you, each 5+ on them, at most 6 per unit | Same as the old Tank Shock |
| Rapid Ingress (15.07) | 1 | End of the opponent's Movement phase | A friendly unit in strategic reserves, not AIRCRAFT | It makes an ingress move | Not in round 1 |
| Fire Overwatch (15.08) | 1 | End of the opponent's Movement phase | A friendly unengaged unit, not TITANIC | It shoots with snap shooting | |
| Smokescreen (15.10) | 1 | Start of the opponent's Shooting phase | A friendly SMOKE unit | To the end of the phase, attacks on it, or on units not fully visible because of its models, get cover | |
| Heroic Intervention (15.11) | 1 | End of the opponent's Charge phase | A friendly unengaged unit within 12" of an enemy. A VEHICLE must also be a CHARACTER or WALKER | Resolve a charge. Leap to Defend: only enemies that charged this phase, within the roll | Into the Fray, +1CP: a roll above 6 counts as 6, and any enemy within 6" and within the roll can be picked |
| Counteroffensive (15.12) | 2 | Fight step of the opponent's Fight phase, just after an enemy unit resolves its attacks | A friendly unit eligible to fight | To the end of the phase it has Fights First, and it must be the next unit picked | |

**Snap shooting (15.09):** one visible enemy unit within 24". Each attack hits only on an unmodified
6. No hit re-rolls. The unit can't start an action until the end of the phase.

## Universal Rules Updates v1.1

Encoded in `Stratagems.discounted_cost` and `Stratagems.may_reuse`, tested, and not reached in play
because no rule in the game grants a discount or a reuse yet.
- A rule giving a stratagem for 0CP without naming it takes 1CP off instead.
- Reuse in a phase, or past a use limit, only works if the rule names the stratagem.
- "Within 12"" limits on ranged targeting became 18". No core stratagem has one. Overwatch stays 24".
- Copy-a-destroyed-unit stratagems: none here.

## Deployment and first turn

From the Combat Patrol mission page. The rule for each is short, and the placeholder scenario keeps its
own map data.

- Roll off, the winner picks Attacker or Defender.
- Players take turns setting up one unit, wholly inside their zone, starting with the Defender. Once a
  player has finished, the other sets up the rest.
- A unit is set up in coherency and unengaged (03.02).
- A roll-off then decides the first turn, and the winner takes it. A roll-off is one D6 each, highest
  wins, and a tie rolls again (01.05.05).
- **Starting CP is still not sourced.** The core rules, the Combat Patrol core rules and the mission
  page all stay silent, so it stays 0, and both players gain 1 CP each Command phase (08.02).

## Assumptions

Each is the simplest reading of a gap or a conflict. Check these against your own copy.

1. **Combat Patrol bans three stratagems.** The Combat Patrol mission page says Crushing Impact,
   Explosives and Rapid Ingress can't be used. The placeholder scenario is a 10th edition stand-in, so
   the brief's list applies and `banned_stratagems` in the scenario file is empty. Set it to
   `["crushing_impact", "explosives", "rapid_ingress"]` to play to that rule: they then show greyed
   with the reason.
2. **Command Re-roll on battle-shock rolls.** The brief asks for it, but battle-shock isn't on the
   source's list of rolls. It's built, as one entry in `Stratagems.REROLL_KINDS`. Take it out to follow
   the list exactly.
3. **Rolls with no re-roll.** Hit, wound, save, damage, hazard and attack-count dice are resolved in one
   go by the attack code, so the game doesn't expose them. Advance, charge and battle-shock rolls can
   be re-rolled.
4. **A battle-shock re-roll is one die**, the lowest, because several dice were rolled together.
5. **Insane Bravery only works on a unit that isn't already shocked.** The FAQ bars targeting a
   battle-shocked unit, so the rule protects a unit testing because it's at half strength. A shocked
   unit recovering gets no stratagem, and neither does a recovery re-roll. The brief's "when shocked on
   an objective" became "about to test, on an objective".
6. **Attacker and Defender are fixed**: side 1 is the Defender and deploys first, because zones, unit
   ids and the board all follow the side. The Defender roll-off isn't modelled. The first-turn roll-off
   is.
7. **Heroic Intervention counts as a charge.** The unit gains Fights First until the end of the turn,
   since 11.04 gives that to any unit that charges and the stratagem doesn't say otherwise.
8. **Heroic Intervention moves automatically**, for human and AI: straight towards the nearest legal
   target, or it fails. There's no dragging during the opponent's turn. Into the Fray is offered as a
   second choice in the prompt.
9. **Explosives doesn't use up the unit's shooting.** It only needs a unit that could shoot. It still
   counts as the one stratagem on that unit in that phase.
10. **A unit under Smokescreen gets cover itself.** The extra part, units hidden behind its models,
    isn't modelled because the sim has no model-blocked sight lines.
11. **[TORRENT] under snap shooting** rolls and needs a 6, like any other weapon, because the rule says
    every attack only hits on a 6.
12. **Snap shooting** can't use [INDIRECT FIRE] against an unseen unit, because the target must be
    visible. [HEAVY] gives no bonus, because that bonus is for your own Shooting phase.
13. **Crushing Impact** rolls for one model, using the unit's T, since all models share a profile.
14. **"Just after" windows on your own turn stay open** until you do something else with that unit,
    because a person needs a moment to decide. The one-per-phase limit still applies.
15. **A charge roll with no reachable target** can still be re-rolled.
16. **Stand-in abilities.** Scouts, Infiltrators and Deep Strike deploy normally, as in
    `keyword-conversion.md`.
17. **A zone with no room** for a unit, which needs an oversized army, places the unit in its zone
    anyway and logs it, so a game can never stall at deployment.

## Into the Fray

Built. It's a second option on Heroic Intervention.
