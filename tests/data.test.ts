import assert from 'node:assert/strict';
import { test } from 'node:test';
import { validateAiConfig, validateProfiles, validateScenario } from '../src/data/validate.ts';
import { Game } from '../src/engine/game.ts';
import type { Scenario } from '../src/engine/types.ts';
import { aiConfig, profiles, scenario } from './data.ts';
import { testProfile } from './helpers.ts';

const goodScenario = (): Scenario => ({
  name: 's',
  board: { width: 20, height: 20 },
  roundLimit: 3,
  players: [
    { name: 'A', color: '#00f', units: [{ profile: 'troop', x: 5, y: 10 }] },
    { name: 'B', color: '#f00', units: [{ profile: 'troop', x: 15, y: 10 }] },
  ],
});

test('shipped data: every unit profile validates and has at least one weapon', () => {
  // Arrange + Act: loading already validated the files
  // Assert
  assert.ok(profiles.length >= 7);
  for (const p of profiles) assert.ok(p.weapons.length > 0, `${p.id} has no weapons`);
});

test('shipped data: the scenario builds a game with both armies and player 0 to move', () => {
  // Arrange + Act
  const game = new Game({ profiles, scenario, seed: 1 });
  // Assert
  assert.equal(game.unitsOf(0).length, 4);
  assert.equal(game.unitsOf(1).length, 5);
  assert.equal(game.state.activePlayer, 0);
  assert.equal(game.state.phase, 'move');
  assert.equal(game.state.round, 1);
});

test('validateProfiles: bad dice expressions, duplicate ids and out-of-range values are rejected with a clear message', () => {
  // Arrange
  const good = JSON.parse(JSON.stringify(testProfile()));
  const withWeapon = (patch: object) => ({ ...good, weapons: [{ ...good.weapons[0], ...patch }] });
  // Act + Assert
  assert.throws(() => validateProfiles({}), /array/);
  assert.throws(() => validateProfiles([withWeapon({ attacks: 'D8' })]), /Invalid quantity/);
  assert.throws(() => validateProfiles([withWeapon({ skill: 7 })]), /skill/);
  assert.throws(() => validateProfiles([withWeapon({ count: 0 })]), /count/);
  assert.throws(() => validateProfiles([good, good]), /duplicate id/);
  assert.throws(() => validateProfiles([{ ...good, models: 0 }]), /models/);
  assert.equal(validateProfiles([good]).length, 1);
});

test('validateScenario: an unknown unit profile or the wrong number of players is rejected', () => {
  // Arrange
  const known = [testProfile()];
  const bad = goodScenario();
  bad.players[0].units[0]!.profile = 'ghost';
  // Act + Assert
  assert.throws(() => validateScenario(bad, known), /unknown profile "ghost"/);
  assert.throws(() => validateScenario({ ...goodScenario(), players: [goodScenario().players[0]] }, known), /exactly two/);
  assert.equal(validateScenario(goodScenario(), known).players.length, 2);
});

test('validateAiConfig: the shipped tuning loads and out-of-range values are rejected', () => {
  // Arrange
  const good = { standoff: 0.8, contactGap: 0.3, distanceWeight: 15 };
  // Act + Assert
  assert.deepEqual(validateAiConfig(good), good);
  assert.deepEqual(aiConfig, good);
  assert.throws(() => validateAiConfig({ ...good, standoff: 2 }), /standoff/);
  assert.throws(() => validateAiConfig({ ...good, contactGap: 5 }), /contactGap/);
  assert.throws(() => validateAiConfig({ standoff: 0.5 }), /contactGap/);
});

test('Game constructor: units that start off the board or overlapping are rejected', () => {
  // Arrange
  const offBoard = goodScenario();
  offBoard.players[0].units[0]!.x = 0.2;
  const overlap = goodScenario();
  overlap.players[1].units[0]!.x = 5.5;
  // Act + Assert
  assert.throws(() => new Game({ profiles: [testProfile()], scenario: offBoard, seed: 1 }), /off the board/);
  assert.throws(() => new Game({ profiles: [testProfile()], scenario: overlap, seed: 1 }), /overlap/);
  assert.doesNotThrow(() => new Game({ profiles: [testProfile()], scenario: goodScenario(), seed: 1 }));
});
