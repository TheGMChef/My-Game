import type { AiConfig } from '../data/validate.ts';
import type { Game } from '../engine/game.ts';
import type { PlayerId, UnitState } from '../engine/types.ts';

/*
 * A deliberately simple, utility-scored opponent. For every unit it:
 *   1. scores each enemy by the points of damage it could do (expected damage, capped
 *      at what the target has left), discounted by distance,
 *   2. closes to a comfortable firing distance, or into melee for fighting units,
 *   3. shoots or fights the best target available.
 * It never looks ahead, uses cover or protects itself, so it is beatable. It only uses
 * the public Game API, so it cannot make an illegal move. All tuning comes from
 * `AiConfig` (loaded from `ai.json`), and every choice is returned as an `AiDecision`
 * so the UI and tests can see what it intended and why.
 */

/** One thing the AI decided to do, with the reasoning behind it. */
export interface AiDecision {
  player: PlayerId;
  unitId: string;
  kind: 'move' | 'shoot' | 'fight';
  /** The enemy unit it is aiming at. */
  targetId: string;
  mode: 'ranged' | 'melee';
  /** Utility score of the chosen target (points of expected damage, distance-weighted). */
  score: number;
  /** Human-readable summary, e.g. "advances 5.2\" toward Horde Troops". */
  note: string;
}

const otherPlayer = (p: PlayerId): PlayerId => (p === 0 ? 1 : 0);

/** Points value of one wound on a unit; used to weigh targets. */
function valuePerWound(game: Game, unit: UnitState): number {
  const p = game.profileOf(unit);
  return p.points / (p.models * p.wounds);
}

/** Wounds the unit has left in total. */
function woundsLeft(game: Game, unit: UnitState): number {
  const p = game.profileOf(unit);
  return (unit.modelsLeft - 1) * p.wounds + unit.leadWounds;
}

/** Points of damage the attacker is expected to do to the target with one kind of weapon. */
function threat(game: Game, attacker: UnitState, target: UnitState, kind: 'ranged' | 'melee'): number {
  const damage = Math.min(game.expectedDamageVs(attacker, target, kind), woundsLeft(game, target));
  return damage * valuePerWound(game, target);
}

/** Longest range among a unit's ranged weapons (0 if it has none). */
function longestRange(game: Game, unit: UnitState): number {
  return game.weaponsOf(unit, 'ranged').reduce((max, w) => Math.max(max, w.range), 0);
}

/**
 * Play the whole of the active player's turn (move, shoot, fight) and pass play
 * to the opponent. Must be called at the start of a move phase; does nothing if
 * the game is over.
 * @returns every decision made, in order, for display and debugging
 */
export function playAiTurn(game: Game, config: AiConfig): AiDecision[] {
  if (game.state.winner !== null) return [];
  if (game.state.phase !== 'move') throw new Error('The AI must start its turn in the move phase');
  const player = game.state.activePlayer;
  const decisions: AiDecision[] = [];

  for (const unit of game.unitsOf(player)) moveUnit(game, config, unit, decisions);
  game.advancePhase();
  for (const unit of game.unitsOf(player)) shootWith(game, unit, decisions);
  game.advancePhase();
  for (const unit of game.unitsOf(player)) fightWith(game, unit, decisions);
  game.advancePhase();
  return decisions;
}

function moveUnit(game: Game, config: AiConfig, unit: UnitState, decisions: AiDecision[]): void {
  const enemies = game.unitsOf(otherPlayer(unit.owner));
  if (enemies.length === 0 || game.isEngaged(unit)) return; // already fighting: stay and fight

  const hasRanged = longestRange(game, unit) > 0;
  let target = enemies[0]!;
  let bestScore = -Infinity;
  let melee = !hasRanged;
  for (const e of enemies) {
    const ranged = threat(game, unit, e, 'ranged');
    const close = threat(game, unit, e, 'melee');
    const score = Math.max(ranged, close) / (1 + game.edgeDistance(unit, e) / config.distanceWeight);
    if (score > bestScore) {
      bestScore = score;
      target = e;
      melee = !hasRanged || close > ranged;
    }
  }

  const name = game.profileOf(target).name;
  const wanted = melee ? config.contactGap : longestRange(game, unit) * config.standoff;
  const edge = game.edgeDistance(unit, target);
  const record = (note: string): void => {
    decisions.push({
      player: unit.owner, unitId: unit.id, kind: 'move', targetId: target.id,
      mode: melee ? 'melee' : 'ranged', score: bestScore, note,
    });
  };

  if (edge <= wanted) {
    record(`holds position, ${name} is already where it wants it`);
    return;
  }
  const moved = stepToward(game, unit, target, Math.min(game.profileOf(unit).move, edge - wanted));
  record(moved > 0 ? `${melee ? 'charges' : 'advances'} ${moved.toFixed(1)}" toward ${name}` : `is blocked advancing on ${name}`);
}

/** Move up to `distance` toward the target, backing off in half-inch steps if blocked. Returns inches moved. */
function stepToward(game: Game, unit: UnitState, target: UnitState, distance: number): number {
  const dx = target.x - unit.x;
  const dy = target.y - unit.y;
  const len = Math.hypot(dx, dy);
  if (len === 0) return 0;
  for (let d = distance; d > 0.2; d -= 0.5) {
    const x = unit.x + (dx / len) * d;
    const y = unit.y + (dy / len) * d;
    if (game.checkMove(unit, x, y).ok) {
      game.move(unit.id, x, y);
      return d;
    }
  }
  return 0;
}

function shootWith(game: Game, unit: UnitState, decisions: AiDecision[]): void {
  if (game.state.winner !== null) return;
  let best: UnitState | null = null;
  let bestScore = 0;
  for (const e of game.unitsOf(otherPlayer(unit.owner))) {
    if (!game.checkShoot(unit, e).ok) continue;
    const score = threat(game, unit, e, 'ranged');
    if (best === null || score > bestScore) {
      best = e;
      bestScore = score;
    }
  }
  if (!best) return;
  decisions.push({
    player: unit.owner, unitId: unit.id, kind: 'shoot', targetId: best.id, mode: 'ranged', score: bestScore,
    note: `shoots ${game.profileOf(best).name}`,
  });
  game.shoot(unit.id, best.id);
}

function fightWith(game: Game, unit: UnitState, decisions: AiDecision[]): void {
  if (game.state.winner !== null) return;
  let best: UnitState | null = null;
  let bestScore = 0;
  for (const e of game.engagedWith(unit)) {
    if (!game.checkFight(unit, e).ok) continue;
    const score = threat(game, unit, e, 'melee');
    if (best === null || score > bestScore) {
      best = e;
      bestScore = score;
    }
  }
  if (!best) return;
  decisions.push({
    player: unit.owner, unitId: unit.id, kind: 'fight', targetId: best.id, mode: 'melee', score: bestScore,
    note: `fights ${game.profileOf(best).name}`,
  });
  game.fight(unit.id, best.id);
}
