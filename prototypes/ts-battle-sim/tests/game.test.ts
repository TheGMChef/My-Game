import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AttackReport, UnitState } from '../src/engine/types.ts';
import { makeDuel, passTurn } from './helpers.ts';

function units(game: ReturnType<typeof makeDuel>): [UnitState, UnitState] {
  return [game.state.units[0]!, game.state.units[1]!];
}

function isReport(r: AttackReport | { ok: boolean }): r is AttackReport {
  return 'results' in r;
}

test('move: a unit can move up to its move distance but not twice in a turn', () => {
  // Arrange
  const game = makeDuel(10);
  const [a] = units(game);
  // Act
  const first = game.move(a.id, a.x + 6, a.y);
  const second = game.move(a.id, a.x + 1, a.y);
  // Assert
  assert.equal(first.ok, true);
  assert.equal(a.x, 16);
  assert.equal(second.ok, false);
  assert.match((second as { reason: string }).reason, /already moved/);
});

test('move: further than the move distance is refused and the unit stays put', () => {
  // Arrange
  const game = makeDuel(10);
  const [a] = units(game);
  // Act
  const result = game.move(a.id, a.x + 6.5, a.y);
  // Assert
  assert.equal(result.ok, false);
  assert.match((result as { reason: string }).reason, /Too far/);
  assert.equal(a.x, 10);
});

test('move: ending on top of another unit is refused', () => {
  // Arrange: centres 4.2 apart, bases are 1.1 radius each
  const game = makeDuel(2);
  const [a] = units(game);
  // Act
  const result = game.move(a.id, a.x + 3, a.y);
  // Assert
  assert.equal(result.ok, false);
  assert.match((result as { reason: string }).reason, /Blocked/);
});

test('move: leaving the board is refused', () => {
  // Arrange
  const game = makeDuel(10);
  const [a] = units(game);
  a.x = 2;
  // Act
  const result = game.move(a.id, -3, a.y);
  // Assert
  assert.equal(result.ok, false);
  assert.match((result as { reason: string }).reason, /off the board/);
});

test('move: the player who is not active cannot move, and nobody can move outside the move phase', () => {
  // Arrange
  const game = makeDuel(10);
  const [a, b] = units(game);
  // Act
  const wrongPlayer = game.move(b.id, b.x - 1, b.y);
  game.advancePhase();
  const wrongPhase = game.move(a.id, a.x + 1, a.y);
  // Assert
  assert.match((wrongPlayer as { reason: string }).reason, /not your unit/);
  assert.match((wrongPhase as { reason: string }).reason, /not the move phase/);
});

test('move: ending within melee range counts as a charge and is logged', () => {
  // Arrange: 5" edge gap, a 4.2" move closes it to 0.8"
  const game = makeDuel(5);
  const [a, b] = units(game);
  // Act
  const result = game.move(a.id, a.x + 4.2, a.y);
  // Assert
  assert.equal(result.ok, true);
  assert.equal(game.isEngaged(a), true);
  assert.equal(game.isEngaged(b), true);
  assert.match(game.state.log.at(-1)!.text, /into melee/);
});

test('shoot: a target beyond weapon range is refused', () => {
  // Arrange: rifle range is 24"
  const game = makeDuel(30);
  const [a, b] = units(game);
  game.advancePhase();
  // Act
  const result = game.shoot(a.id, b.id);
  // Assert
  assert.equal(isReport(result), false);
  assert.match((result as { reason: string }).reason, /out of range/);
});

test('shoot: an in-range target takes a shot with rolls logged, and the shooter cannot shoot twice', () => {
  // Arrange
  const game = makeDuel(10);
  const [a, b] = units(game);
  game.advancePhase();
  // Act
  const first = game.shoot(a.id, b.id);
  const second = game.shoot(a.id, b.id);
  // Assert
  assert.equal(isReport(first), true);
  const report = first as AttackReport;
  assert.equal(report.results.length, 1);
  assert.equal(report.results[0]!.attacks, 5, 'five models, one attack each');
  assert.equal(b.modelsLeft, 5 - report.modelsKilled);
  assert.match(game.state.log.at(-1)!.text, /shoots Troop/);
  assert.match((second as { reason: string }).reason, /already shot/);
});

test('shoot: a unit locked in melee cannot shoot', () => {
  // Arrange: 0.5" edge gap means engaged
  const game = makeDuel(0.5);
  const [a, b] = units(game);
  game.advancePhase();
  // Act
  const result = game.shoot(a.id, b.id);
  // Assert
  assert.match((result as { reason: string }).reason, /melee cannot shoot/);
});

test('fight: a target outside melee range is refused', () => {
  // Arrange
  const game = makeDuel(5);
  const [a, b] = units(game);
  game.advancePhase();
  game.advancePhase();
  // Act
  const result = game.fight(a.id, b.id);
  // Assert
  assert.match((result as { reason: string }).reason, /not in melee range/);
});

test('fight: the active unit strikes first and the surviving enemy strikes back when the phase ends', () => {
  // Arrange: engaged duel, move to the fight phase
  const game = makeDuel(0.5);
  const [a, b] = units(game);
  game.advancePhase();
  game.advancePhase();
  // Act
  const attack = game.fight(a.id, b.id);
  const beforeReturn = a.modelsLeft;
  game.advancePhase();
  // Assert
  assert.equal(isReport(attack), true);
  assert.ok(b.modelsLeft > 0, 'defender survived the first strike for this seed');
  assert.ok(game.state.log.some((l) => /strikes back at/.test(l.text)));
  assert.ok(a.modelsLeft <= beforeReturn);
  assert.equal(game.state.activePlayer, 1, 'the turn passed to the other player');
  assert.equal(b.hasFought, false, 'flags reset for the next turn');
});

test('turn flow: phases run move, shoot, fight, then play passes; the round advances after both turns', () => {
  // Arrange
  const game = makeDuel(30);
  const seen: string[] = [game.state.phase];
  // Act
  game.advancePhase();
  seen.push(game.state.phase);
  game.advancePhase();
  seen.push(game.state.phase);
  game.advancePhase();
  const afterFirstTurn = { player: game.state.activePlayer, phase: game.state.phase, round: game.state.round };
  passTurn(game);
  // Assert
  assert.deepEqual(seen, ['move', 'shoot', 'fight']);
  assert.deepEqual(afterFirstTurn, { player: 1, phase: 'move', round: 1 });
  assert.equal(game.state.activePlayer, 0);
  assert.equal(game.state.round, 2);
});

test('end of game: wiping out the enemy ends the game at once and blocks further actions', () => {
  // Arrange: one enemy model left and a shooter that cannot miss
  const game = makeDuel(5);
  const [a, b] = units(game);
  b.modelsLeft = 1;
  b.leadWounds = 1;
  const rifle = game.profileOf(a).weapons[0]!;
  rifle.attacks = 60;
  rifle.skill = 2;
  rifle.strength = 10;
  rifle.ap = 6;
  game.advancePhase();
  // Act
  game.shoot(a.id, b.id);
  const blocked = game.move(a.id, a.x, a.y);
  // Assert
  assert.equal(b.modelsLeft, 0);
  assert.equal(game.state.winner, 0);
  assert.match(game.state.log.at(-1)!.text, /Left wins, wiped out the enemy/);
  assert.match((blocked as { reason: string }).reason, /game is over/);
});

test('end of game: after the round limit the side with more surviving points wins', () => {
  // Arrange: one-round game where the right side is already hurt
  const game = makeDuel(30, 1, 1);
  const [, b] = units(game);
  b.modelsLeft = 2;
  // Act
  passTurn(game);
  passTurn(game);
  // Assert
  assert.equal(game.state.winner, 0);
  assert.match(game.state.log.at(-1)!.text, /ahead on points/);
});

test('end of game: equal points at the round limit is a draw', () => {
  // Arrange
  const game = makeDuel(30, 1, 1);
  // Act
  passTurn(game);
  passTurn(game);
  // Assert
  assert.equal(game.state.winner, 'draw');
});

test('unitValue: a partly wounded unit is worth less than a fresh one and a dead unit nothing', () => {
  // Arrange
  const game = makeDuel(30);
  const [a] = units(game);
  const fresh = game.unitValue(a);
  // Act
  a.modelsLeft = 3;
  const hurt = game.unitValue(a);
  a.modelsLeft = 0;
  // Assert
  assert.equal(fresh, 100);
  assert.equal(hurt, 60);
  assert.equal(game.unitValue(a), 0);
});

test('dice: the same seed and actions repeat the same game, and other seeds can differ', () => {
  // Arrange
  const play = (seed: number): string[] => {
    const g = makeDuel(10, seed);
    const [a, b] = units(g);
    g.advancePhase();
    g.shoot(a.id, b.id);
    passTurn(g);
    g.advancePhase();
    g.shoot(b.id, a.id);
    return g.state.log.map((l) => l.text);
  };
  // Act
  const first = play(1);
  const again = play(1);
  const others = [2, 3, 4, 5, 6].map(play);
  // Assert
  assert.deepEqual(first, again);
  assert.ok(others.some((log) => log.join('|') !== first.join('|')), 'at least one other seed differs');
});
