import { averageQuantity, rollDie, rollQuantity } from './dice.ts';
import type { Rng } from './dice.ts';
import type { UnitProfile, UnitState, WeaponProfile, WeaponResult } from './types.ts';

const clamp = (n: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, n));

/**
 * Probability of rolling at least `target` on a d6, where a natural 6 always
 * succeeds and a natural 1 always fails (so targets are clamped to 2..6).
 */
export function chanceAtLeast(target: number): number {
  return (7 - clamp(target, 2, 6)) / 6;
}

/**
 * The roll needed to wound, from strength versus toughness:
 * double or more = 2+, greater = 3+, equal = 4+, less = 5+, half or less = 6+.
 */
export function woundThreshold(strength: number, toughness: number): number {
  if (strength >= 2 * toughness) return 2;
  if (strength > toughness) return 3;
  if (strength === toughness) return 4;
  if (2 * strength <= toughness) return 6;
  return 5;
}

/**
 * The roll the target needs to save against a weapon, using the better of the
 * armour save (worsened by AP) and any invulnerable save. Returns `null` when
 * no save is possible.
 */
export function saveNeeded(target: UnitProfile, ap: number): number | null {
  const armour = target.save + ap;
  const best = target.invuln === undefined ? armour : Math.min(armour, target.invuln);
  return best > 6 ? null : Math.max(best, 2);
}

/** Probability that one attack with `weapon` becomes an unsaved wound on `target`. */
export function chanceUnsavedWound(weapon: WeaponProfile, target: UnitProfile): number {
  const pHit = chanceAtLeast(weapon.skill);
  const pWound = chanceAtLeast(woundThreshold(weapon.strength, target.toughness));
  const save = saveNeeded(target, weapon.ap);
  const pFail = save === null ? 1 : 1 - chanceAtLeast(save);
  return pHit * pWound * pFail;
}

/** How many models of a unit carry a weapon right now. */
export function carriers(weapon: WeaponProfile, modelsLeft: number): number {
  return weapon.count === 'all' ? modelsLeft : Math.min(weapon.count, modelsLeft);
}

/**
 * Expected damage from one weapon against a target profile, ignoring spillover
 * (damage above one model's wounds is wasted, so per-wound damage is capped).
 */
export function expectedDamage(weapon: WeaponProfile, carrying: number, target: UnitProfile): number {
  const attacks = carrying * averageQuantity(weapon.attacks);
  const perWound = Math.min(averageQuantity(weapon.damage), target.wounds);
  return attacks * chanceUnsavedWound(weapon, target) * perWound;
}

/**
 * Apply damage to a unit's lead model. Damage beyond what the lead model has left
 * is lost (it never carries over to the next model). Returns wounds actually dealt
 * and whether a model died.
 */
export function applyDamage(
  state: UnitState,
  profile: UnitProfile,
  amount: number,
): { dealt: number; killed: boolean } {
  if (state.modelsLeft <= 0 || amount <= 0) return { dealt: 0, killed: false };
  const dealt = Math.min(amount, state.leadWounds);
  state.leadWounds -= dealt;
  if (state.leadWounds > 0) return { dealt, killed: false };
  state.modelsLeft -= 1;
  state.leadWounds = state.modelsLeft > 0 ? profile.wounds : 0;
  return { dealt, killed: true };
}

/**
 * Resolve one weapon, fired by `carrying` models, against a target and apply the
 * damage to `targetState`. Sequence: hit rolls, wound rolls, save rolls, damage.
 */
export function resolveWeapon(
  weapon: WeaponProfile,
  carrying: number,
  target: UnitProfile,
  targetState: UnitState,
  rng: Rng,
): WeaponResult {
  let attacks = 0;
  for (let i = 0; i < carrying; i++) attacks += rollQuantity(weapon.attacks, rng);

  let hits = 0;
  for (let i = 0; i < attacks; i++) {
    const roll = rollDie(rng);
    if (roll === 6 || (roll !== 1 && roll >= weapon.skill)) hits++;
  }

  const woundNeeded = woundThreshold(weapon.strength, target.toughness);
  let wounds = 0;
  for (let i = 0; i < hits; i++) {
    const roll = rollDie(rng);
    if (roll === 6 || (roll !== 1 && roll >= woundNeeded)) wounds++;
  }

  const save = saveNeeded(target, weapon.ap);
  let failedSaves = 0;
  for (let i = 0; i < wounds; i++) {
    if (save === null) {
      failedSaves++;
      continue;
    }
    const roll = rollDie(rng);
    if (roll === 1 || roll < save) failedSaves++;
  }

  let damage = 0;
  let modelsKilled = 0;
  for (let i = 0; i < failedSaves; i++) {
    if (targetState.modelsLeft <= 0) break;
    const result = applyDamage(targetState, target, rollQuantity(weapon.damage, rng));
    damage += result.dealt;
    if (result.killed) modelsKilled++;
  }

  return { weapon: weapon.name, attacks, hits, wounds, failedSaves, damage, modelsKilled };
}
