import { Game } from '../src/engine/game.ts';
import type { Scenario, UnitProfile } from '../src/engine/types.ts';

/** A simple five-model profile with a rifle and a blade, easy to reason about in tests. */
export function testProfile(over: Partial<UnitProfile> = {}): UnitProfile {
  return {
    id: 'troop',
    name: 'Troop',
    short: 'TR',
    models: 5,
    toughness: 3,
    save: 4,
    wounds: 1,
    move: 6,
    points: 100,
    baseRadius: 0.5,
    weapons: [
      { name: 'Rifle', kind: 'ranged', range: 24, attacks: 1, skill: 3, strength: 4, ap: 0, damage: 1, count: 'all' },
      { name: 'Blade', kind: 'melee', range: 0, attacks: 1, skill: 3, strength: 4, ap: 0, damage: 1, count: 'all' },
    ],
    ...over,
  };
}

/**
 * A two-unit game: one `troop` per side on a 60x30 board, with the given
 * edge-to-edge gap between them. Player 0 is on the left.
 */
export function makeDuel(edgeGap: number, seed = 1, roundLimit = 5): Game {
  const profile = testProfile();
  const radius = profile.baseRadius * Math.sqrt(profile.models);
  const x0 = 10;
  const x1 = x0 + 2 * radius + edgeGap;
  const sc: Scenario = {
    name: 'duel',
    board: { width: 60, height: 30 },
    roundLimit,
    players: [
      { name: 'Left', color: '#00f', units: [{ profile: 'troop', x: x0, y: 15 }] },
      { name: 'Right', color: '#f00', units: [{ profile: 'troop', x: x1, y: 15 }] },
    ],
  };
  return new Game({ profiles: [profile], scenario: sc, seed });
}

/** Advance phases until the other player's move phase begins (or the game ends). */
export function passTurn(game: Game): void {
  const player = game.state.activePlayer;
  const round = game.state.round;
  for (let i = 0; i < 3 && game.state.winner === null; i++) game.advancePhase();
  if (game.state.winner === null && game.state.activePlayer === player && game.state.round === round) {
    throw new Error('turn did not pass');
  }
}
