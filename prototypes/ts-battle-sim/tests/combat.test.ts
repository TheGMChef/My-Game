import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  applyDamage,
  chanceAtLeast,
  chanceUnsavedWound,
  expectedDamage,
  resolveWeapon,
  saveNeeded,
  woundThreshold,
} from '../src/engine/combat.ts';
import { averageQuantity, createRng, parseQuantity, rollQuantity } from '../src/engine/dice.ts';
import type { UnitState, WeaponProfile } from '../src/engine/types.ts';
import { testProfile } from './helpers.ts';

const rifle: WeaponProfile = {
  name: 'Rifle', kind: 'ranged', range: 24, attacks: 1, skill: 3, strength: 4, ap: 0, damage: 1, count: 'all',
};

function stateFor(models: number, wounds: number): UnitState {
  return {
    id: 't', profileId: 'troop', owner: 1, x: 0, y: 0,
    modelsLeft: models, leadWounds: wounds, hasMoved: false, hasShot: false, hasFought: false,
  };
}

test('woundThreshold: strength against toughness gives 2+, 3+, 4+, 5+ or 6+', () => {
  // Arrange: toughness 4 across the whole table, plus a very tough target
  const t = 4;
  // Act + Assert
  assert.equal(woundThreshold(8, t), 2, 'double toughness or more');
  assert.equal(woundThreshold(5, t), 3, 'greater than toughness');
  assert.equal(woundThreshold(4, t), 4, 'equal to toughness');
  assert.equal(woundThreshold(3, t), 5, 'less than toughness');
  assert.equal(woundThreshold(2, t), 6, 'half toughness or less');
  assert.equal(woundThreshold(4, 8), 6, 'half toughness exactly');
});

test('saveNeeded: AP worsens armour, a better invulnerable save wins, and 7+ means no save', () => {
  // Arrange
  const armour3 = testProfile({ save: 3 });
  // Act + Assert
  assert.equal(saveNeeded(armour3, 0), 3);
  assert.equal(saveNeeded(armour3, 1), 4);
  assert.equal(saveNeeded(armour3, 3), 6, '3+ with AP 3 is a 6+ save, still possible');
  assert.equal(saveNeeded(armour3, 4), null, '3+ with AP 4 would be 7+, no save');
  assert.equal(saveNeeded(testProfile({ save: 3, invuln: 4 }), 4), 4, 'invulnerable ignores AP');
  assert.equal(saveNeeded(testProfile({ save: 3, invuln: 5 }), 0), 3, 'armour beats a worse invulnerable');
});

test('chanceAtLeast: a natural 1 never succeeds and a natural 6 always does', () => {
  // Act + Assert
  assert.equal(chanceAtLeast(4), 0.5);
  assert.equal(chanceAtLeast(2), 5 / 6);
  assert.equal(chanceAtLeast(1), 5 / 6, 'a target of 1+ still fails on a 1');
  assert.equal(chanceAtLeast(9), 1 / 6, 'a target above 6+ still succeeds on a 6');
});

test('dice quantities: expressions parse, rolls stay in range, averages are exact, bad input throws', () => {
  // Arrange
  const rng = createRng(7);
  // Act + Assert: parsing and averages
  assert.deepEqual(parseQuantity(3), { dice: 0, sides: 0, flat: 3 });
  assert.deepEqual(parseQuantity('2D6+1'), { dice: 2, sides: 6, flat: 1 });
  assert.equal(averageQuantity('D6'), 3.5);
  assert.equal(averageQuantity('D3'), 2);
  assert.equal(averageQuantity('2D6+2'), 9);
  assert.throws(() => parseQuantity('D8'));
  assert.throws(() => parseQuantity('banana'));
  // Act + Assert: rolls
  for (let i = 0; i < 500; i++) {
    const six = rollQuantity('D6+2', rng);
    const three = rollQuantity('D3', rng);
    assert.ok(six >= 3 && six <= 8, `D6+2 gave ${six}`);
    assert.ok(three >= 1 && three <= 3, `D3 gave ${three}`);
  }
});

test('createRng: the same seed repeats the same sequence and different seeds differ', () => {
  // Arrange
  const a = createRng(123);
  const b = createRng(123);
  // Act + Assert
  for (let i = 0; i < 50; i++) assert.equal(a.next(), b.next());
  assert.notEqual(createRng(1).next(), createRng(2).next());
});

test('applyDamage: damage lands on the lead model, excess is wasted, the next model starts fresh', () => {
  // Arrange: three models with 2 wounds each
  const profile = testProfile({ wounds: 2 });
  const s = stateFor(3, 2);
  // Act + Assert
  assert.deepEqual(applyDamage(s, profile, 1), { dealt: 1, killed: false });
  assert.equal(s.leadWounds, 1);
  assert.deepEqual(applyDamage(s, profile, 5), { dealt: 1, killed: true }, 'only 1 wound was left to take');
  assert.equal(s.modelsLeft, 2);
  assert.equal(s.leadWounds, 2);
  applyDamage(s, profile, 2);
  applyDamage(s, profile, 2);
  assert.equal(s.modelsLeft, 0);
  assert.deepEqual(applyDamage(s, profile, 2), { dealt: 0, killed: false }, 'nothing left to damage');
});

test('resolveWeapon: over many rolls the unsaved-wound rate matches the calculated odds', () => {
  // Arrange: 3+ to hit (2/3), S4 vs T3 wounds on 3+ (2/3), a 4+ save fails half the time
  const target = testProfile({ toughness: 3, save: 4, wounds: 1 });
  const expected = chanceUnsavedWound(rifle, target);
  const rng = createRng(2024);
  const state = stateFor(1_000_000, 1);
  let attacks = 0;
  let unsaved = 0;
  // Act
  for (let i = 0; i < 4000; i++) {
    const r = resolveWeapon(rifle, 10, target, state, rng);
    attacks += r.attacks;
    unsaved += r.failedSaves;
  }
  // Assert
  assert.ok(Math.abs(expected - (2 / 3) * (2 / 3) * 0.5) < 1e-12);
  assert.equal(attacks, 40000);
  assert.ok(Math.abs(unsaved / attacks - expected) < 0.01, `observed ${unsaved / attacks}, expected ${expected}`);
});

test('resolveWeapon: when no save is possible every wound goes through', () => {
  // Arrange: AP 4 against a 3+ save leaves no save
  const heavy: WeaponProfile = { ...rifle, ap: 4, skill: 2, strength: 10 };
  const target = testProfile({ save: 3 });
  const rng = createRng(5);
  // Act
  const r = resolveWeapon(heavy, 50, target, stateFor(1000, 1), rng);
  // Assert
  assert.ok(r.wounds > 0);
  assert.equal(r.failedSaves, r.wounds);
});

test('expectedDamage: damage per wound is capped at the target model wounds', () => {
  // Arrange: a damage-6 weapon with no save possible, against 2-wound and 12-wound models
  const bigGun: WeaponProfile = { ...rifle, damage: 6, strength: 10, ap: 5, skill: 2 };
  const small = testProfile({ wounds: 2, save: 3 });
  const big = testProfile({ wounds: 12, save: 3 });
  // Act
  const vsSmall = expectedDamage(bigGun, 1, small);
  const vsBig = expectedDamage(bigGun, 1, big);
  // Assert: 6 damage vs 2 wounds wastes 4, so the big target takes exactly 3x as much
  assert.ok(Math.abs(vsBig / vsSmall - 3) < 1e-9);
});

test('resolveWeapon: killing every model leaves zero models and counts each kill', () => {
  // Arrange: three 1-wound models, no armour, a flood of hits
  const target = testProfile({ save: 7 });
  const s = stateFor(3, 1);
  const rng = createRng(9);
  // Act
  const r = resolveWeapon({ ...rifle, skill: 2, strength: 10, attacks: 30 }, 1, target, s, rng);
  // Assert
  assert.equal(s.modelsLeft, 0);
  assert.equal(r.modelsKilled, 3);
  assert.equal(r.damage, 3);
});
