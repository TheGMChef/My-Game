import assert from 'node:assert/strict';
import { test } from 'node:test';
import { playAiTurn } from '../src/ai/simpleAi.ts';
import { Game } from '../src/engine/game.ts';
import type { PlayerId } from '../src/engine/types.ts';
import { aiConfig, profiles, scenario } from './data.ts';
import { makeDuel } from './helpers.ts';

/** Play a full game where each listed player is run by the AI; other players pass every turn. */
function playGame(seed: number, aiPlayers: PlayerId[]): Game {
  const game = new Game({ profiles, scenario, seed });
  for (let turn = 0; turn < 40 && game.state.winner === null; turn++) {
    if (aiPlayers.includes(game.state.activePlayer)) playAiTurn(game, aiConfig);
    else for (let i = 0; i < 3; i++) game.advancePhase();
  }
  return game;
}

test('AI turn: plays through move, shoot and fight and hands play to the opponent', () => {
  // Arrange
  const game = new Game({ profiles, scenario, seed: 1 });
  // Act
  playAiTurn(game, aiConfig);
  // Assert
  assert.equal(game.state.activePlayer, 1);
  assert.equal(game.state.phase, 'move');
  assert.ok(game.state.log.some((l) => l.player === 0 && /moves/.test(l.text)), 'the AI moved something');
});

test('AI turn: refuses to start outside the move phase', () => {
  // Arrange
  const game = new Game({ profiles, scenario, seed: 1 });
  game.advancePhase();
  // Act + Assert
  assert.throws(() => playAiTurn(game, aiConfig), /move phase/);
});

test('AI decisions: every unit gets a move decision that names a living enemy, a reason and a score', () => {
  // Arrange
  const game = new Game({ profiles, scenario, seed: 1 });
  const enemyIds = new Set(game.unitsOf(1).map((u) => u.id));
  const ownCount = game.unitsOf(0).length;
  // Act
  const decisions = playAiTurn(game, aiConfig);
  // Assert
  const moves = decisions.filter((d) => d.kind === 'move');
  assert.equal(moves.length, ownCount);
  for (const d of decisions) {
    assert.equal(d.player, 0);
    assert.ok(enemyIds.has(d.targetId), `${d.unitId} targets unknown unit ${d.targetId}`);
    assert.ok(d.note.length > 0);
    assert.ok(Number.isFinite(d.score));
  }
});

test('AI tuning: a smaller standoff fraction makes ranged units close in further', () => {
  // Arrange: rifle range 24", edge gap 22"; standoff 0.9 wants 21.6", standoff 0.3 wants 7.2"
  const cautious = makeDuel(22);
  const bold = makeDuel(22);
  // Act
  playAiTurn(cautious, { ...aiConfig, standoff: 0.9 });
  playAiTurn(bold, { ...aiConfig, standoff: 0.3 });
  // Assert
  const cautiousMoved = cautious.state.units[0]!.x - 10;
  const boldMoved = bold.state.units[0]!.x - 10;
  assert.ok(cautiousMoved < 1, `cautious unit moved ${cautiousMoved}`);
  assert.ok(boldMoved > 5, `bold unit moved ${boldMoved}`);
});

test('AI vs AI: 40 seeded games on the shipped scenario all finish with a result inside the round limit', () => {
  for (let seed = 1; seed <= 40; seed++) {
    // Arrange + Act
    const game = playGame(seed, [0, 1]);
    // Assert
    assert.notEqual(game.state.winner, null, `seed ${seed} did not finish`);
    assert.ok(game.state.round <= scenario.roundLimit + 1, `seed ${seed} ran too long`);
  }
});

test('AI vs a side that never acts: the AI wins nearly every game from either side of the board', () => {
  // Arrange
  const games = 30;
  const wins: Record<number, number> = { 0: 0, 1: 0 };
  // Act
  for (let seed = 1; seed <= games; seed++) {
    for (const side of [0, 1] as const) {
      if (playGame(seed, [side]).state.winner === side) wins[side]!++;
    }
  }
  // Assert
  assert.ok(wins[0]! >= games * 0.9, `AI as player 0 won only ${wins[0]} of ${games}`);
  assert.ok(wins[1]! >= games * 0.9, `AI as player 1 won only ${wins[1]} of ${games}`);
});

test('AI vs AI: the same seed plays out identically', () => {
  // Arrange + Act
  const a = playGame(7, [0, 1]).state.log.map((l) => l.text);
  const b = playGame(7, [0, 1]).state.log.map((l) => l.text);
  // Assert
  assert.deepEqual(a, b);
});

test('AI performance: the 95th percentile of a full AI turn stays under the 2ms budget', () => {
  // Arrange: warm up the JIT, then time many turns
  for (let seed = 1; seed <= 20; seed++) playGame(seed, [0, 1]);
  const times: number[] = [];
  // Act
  for (let seed = 100; seed < 160; seed++) {
    const game = new Game({ profiles, scenario, seed });
    while (game.state.winner === null) {
      const t0 = performance.now();
      playAiTurn(game, aiConfig);
      times.push(performance.now() - t0);
    }
  }
  // Assert
  times.sort((a, b) => a - b);
  const p95 = times[Math.floor(times.length * 0.95)]!;
  assert.ok(p95 < 2, `95th percentile AI turn took ${p95.toFixed(3)}ms`);
});
