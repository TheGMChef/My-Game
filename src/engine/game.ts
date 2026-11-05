import { carriers, expectedDamage, resolveWeapon } from './combat.ts';
import { createRng } from './dice.ts';
import type { Rng } from './dice.ts';
import type {
  AttackReport,
  GameState,
  PlayerId,
  Scenario,
  UnitProfile,
  UnitState,
  WeaponProfile,
  WeaponResult,
} from './types.ts';

/** Units whose bases are within this many inches (edge to edge) are in melee. */
export const ENGAGEMENT_RANGE = 1;

/** Everything needed to start a game. Profiles and scenario normally come from JSON. */
export interface GameConfig {
  profiles: UnitProfile[];
  scenario: Scenario;
  /** Seed for the dice. The same seed and the same actions give the same game. */
  seed: number;
}

/** Result of asking whether an action is legal. */
export type Check = { ok: true } | { ok: false; reason: string };

const OK: Check = { ok: true };
const no = (reason: string): Check => ({ ok: false, reason });
const other = (p: PlayerId): PlayerId => (p === 0 ? 1 : 0);

/**
 * A battle between two players on a flat board.
 *
 * Turn order: each player takes a turn of Move, Shoot, Fight; after both have
 * played, the round counter goes up. The game ends when one side is wiped out or
 * after the scenario's round limit (then the side with more surviving points wins).
 *
 * Deliberate simplifications for this first version: units are single circles (no
 * individual models), there is no terrain or line of sight, a move is a straight
 * line checked only at its end point, and moving into contact counts as a charge.
 */
export class Game {
  readonly scenario: Scenario;
  readonly state: GameState;
  private readonly profiles: Map<string, UnitProfile>;
  private readonly rng: Rng;

  /**
   * Create a game. Throws if the scenario references unknown profiles or places
   * units off the board or on top of each other.
   * @param rng optional dice source, mainly for tests; defaults to a seeded generator
   */
  constructor(config: GameConfig, rng?: Rng) {
    this.scenario = config.scenario;
    this.rng = rng ?? createRng(config.seed);
    this.profiles = new Map(config.profiles.map((p) => [p.id, p]));

    const units: UnitState[] = [];
    config.scenario.players.forEach((player, owner) => {
      player.units.forEach((su, index) => {
        const profile = this.profiles.get(su.profile);
        if (!profile) throw new Error(`Scenario uses unknown unit profile "${su.profile}"`);
        units.push({
          id: `p${owner}-u${index}`,
          profileId: profile.id,
          owner: owner as PlayerId,
          x: su.x,
          y: su.y,
          modelsLeft: profile.models,
          leadWounds: profile.wounds,
          hasMoved: false,
          hasShot: false,
          hasFought: false,
        });
      });
    });

    this.state = { round: 1, activePlayer: 0, phase: 'move', units, log: [], winner: null };

    for (const u of units) {
      const r = this.radiusOf(u);
      const { width, height } = this.scenario.board;
      if (u.x - r < 0 || u.x + r > width || u.y - r < 0 || u.y + r > height) {
        throw new Error(`Unit ${u.id} starts off the board`);
      }
      for (const v of units) {
        if (v.id < u.id && this.distance(u, v) < r + this.radiusOf(v)) {
          throw new Error(`Units ${u.id} and ${v.id} overlap at the start`);
        }
      }
    }
    this.log(0, `Round 1 — ${this.playerName(0)} to move.`);
  }

  // ---------------------------------------------------------------- lookups

  /** Look up a unit by id. Throws if it does not exist. */
  getUnit(id: string): UnitState {
    const u = this.state.units.find((x) => x.id === id);
    if (!u) throw new Error(`Unknown unit "${id}"`);
    return u;
  }

  /** The stat line of a unit. */
  profileOf(unit: UnitState): UnitProfile {
    return this.profiles.get(unit.profileId)!;
  }

  /** A player's display name. */
  playerName(player: PlayerId): string {
    return this.scenario.players[player].name;
  }

  /** Units of a player that still have models on the table. */
  unitsOf(player: PlayerId): UnitState[] {
    return this.state.units.filter((u) => u.owner === player && u.modelsLeft > 0);
  }

  /** Footprint radius of a unit in inches; shrinks as models are lost. */
  radiusOf(unit: UnitState): number {
    const p = this.profileOf(unit);
    return p.baseRadius * Math.sqrt(Math.max(unit.modelsLeft, 1));
  }

  /** Centre-to-centre distance in inches. */
  distance(a: UnitState, b: UnitState): number {
    return Math.hypot(a.x - b.x, a.y - b.y);
  }

  /** Edge-to-edge distance in inches (never negative). */
  edgeDistance(a: UnitState, b: UnitState): number {
    return Math.max(0, this.distance(a, b) - this.radiusOf(a) - this.radiusOf(b));
  }

  /** True if the unit is in melee range of any living enemy. */
  isEngaged(unit: UnitState): boolean {
    return this.unitsOf(other(unit.owner)).some((e) => this.edgeDistance(unit, e) <= ENGAGEMENT_RANGE);
  }

  /** Living enemies currently in melee range of the unit. */
  engagedWith(unit: UnitState): UnitState[] {
    return this.unitsOf(other(unit.owner)).filter((e) => this.edgeDistance(unit, e) <= ENGAGEMENT_RANGE);
  }

  /** Points value of what is left of a unit (counts partly wounded models). */
  unitValue(unit: UnitState): number {
    if (unit.modelsLeft <= 0) return 0;
    const p = this.profileOf(unit);
    const wounds = (unit.modelsLeft - 1) * p.wounds + unit.leadWounds;
    return (p.points * wounds) / (p.models * p.wounds);
  }

  /** Total points value of a player's surviving units. */
  score(player: PlayerId): number {
    return this.unitsOf(player).reduce((sum, u) => sum + this.unitValue(u), 0);
  }

  /** Expected damage of all of the attacker's weapons of one kind against a target (ignores range). */
  expectedDamageVs(attacker: UnitState, target: UnitState, kind: 'ranged' | 'melee'): number {
    const tp = this.profileOf(target);
    return this.weaponsOf(attacker, kind).reduce(
      (sum, w) => sum + expectedDamage(w, carriers(w, attacker.modelsLeft), tp),
      0,
    );
  }

  /** The attacker's weapons of one kind. */
  weaponsOf(unit: UnitState, kind: 'ranged' | 'melee'): WeaponProfile[] {
    return this.profileOf(unit).weapons.filter((w) => w.kind === kind);
  }

  // ---------------------------------------------------------------- actions

  /** Whether `unit` may move its centre to (x, y) right now. */
  checkMove(unit: UnitState, x: number, y: number): Check {
    const s = this.state;
    if (s.winner !== null) return no('The game is over.');
    if (s.phase !== 'move') return no('It is not the move phase.');
    if (unit.owner !== s.activePlayer) return no('That is not your unit.');
    if (unit.modelsLeft <= 0) return no('That unit is destroyed.');
    if (unit.hasMoved) return no('That unit has already moved.');
    const profile = this.profileOf(unit);
    const dist = Math.hypot(x - unit.x, y - unit.y);
    if (dist > profile.move + 1e-9) return no(`Too far: this unit moves ${profile.move}".`);
    const r = this.radiusOf(unit);
    const { width, height } = this.scenario.board;
    if (x - r < 0 || x + r > width || y - r < 0 || y + r > height) return no('That is off the board.');
    for (const v of s.units) {
      if (v === unit || v.modelsLeft <= 0) continue;
      if (Math.hypot(x - v.x, y - v.y) < r + this.radiusOf(v) - 1e-9) {
        return no(`Blocked by ${this.profileOf(v).name}.`);
      }
    }
    return OK;
  }

  /** Move a unit. Returns the check result; the unit only moves when it is `ok`. */
  move(unitId: string, x: number, y: number): Check {
    const unit = this.getUnit(unitId);
    const check = this.checkMove(unit, x, y);
    if (!check.ok) return check;
    const dist = Math.hypot(x - unit.x, y - unit.y);
    unit.x = x;
    unit.y = y;
    unit.hasMoved = true;
    const engaged = this.isEngaged(unit);
    this.log(unit.owner, `${this.profileOf(unit).name} moves ${dist.toFixed(1)}"${engaged ? ' into melee' : ''}.`);
    return OK;
  }

  /** Whether `attacker` may shoot `target` right now. */
  checkShoot(attacker: UnitState, target: UnitState): Check {
    const s = this.state;
    if (s.winner !== null) return no('The game is over.');
    if (s.phase !== 'shoot') return no('It is not the shooting phase.');
    if (attacker.owner !== s.activePlayer) return no('That is not your unit.');
    if (attacker.modelsLeft <= 0) return no('That unit is destroyed.');
    if (attacker.hasShot) return no('That unit has already shot.');
    if (target.owner === attacker.owner) return no('You cannot shoot your own units.');
    if (target.modelsLeft <= 0) return no('That target is already destroyed.');
    if (this.isEngaged(attacker)) return no('A unit in melee cannot shoot.');
    const edge = this.edgeDistance(attacker, target);
    const inRange = this.weaponsOf(attacker, 'ranged').some((w) => edge <= w.range);
    if (!inRange) return no('Target is out of range.');
    return OK;
  }

  /** Shoot with every ranged weapon in range. Returns the report, or the reason it was illegal. */
  shoot(attackerId: string, targetId: string): AttackReport | Check {
    const attacker = this.getUnit(attackerId);
    const target = this.getUnit(targetId);
    const check = this.checkShoot(attacker, target);
    if (!check.ok) return check;
    const edge = this.edgeDistance(attacker, target);
    const weapons = this.weaponsOf(attacker, 'ranged').filter((w) => edge <= w.range);
    const report = this.attack(attacker, target, weapons, 'shoots');
    attacker.hasShot = true;
    return report;
  }

  /** Whether `attacker` may fight `target` in melee right now. */
  checkFight(attacker: UnitState, target: UnitState): Check {
    const s = this.state;
    if (s.winner !== null) return no('The game is over.');
    if (s.phase !== 'fight') return no('It is not the fight phase.');
    if (attacker.owner !== s.activePlayer) return no('That is not your unit.');
    if (attacker.modelsLeft <= 0) return no('That unit is destroyed.');
    if (attacker.hasFought) return no('That unit has already fought.');
    if (target.owner === attacker.owner) return no('You cannot attack your own units.');
    if (target.modelsLeft <= 0) return no('That target is already destroyed.');
    if (this.edgeDistance(attacker, target) > ENGAGEMENT_RANGE) return no('Target is not in melee range.');
    if (this.weaponsOf(attacker, 'melee').length === 0) return no('That unit has no melee weapons.');
    return OK;
  }

  /** Fight a target in melee with every melee weapon. */
  fight(attackerId: string, targetId: string): AttackReport | Check {
    const attacker = this.getUnit(attackerId);
    const target = this.getUnit(targetId);
    const check = this.checkFight(attacker, target);
    if (!check.ok) return check;
    const report = this.attack(attacker, target, this.weaponsOf(attacker, 'melee'), 'fights');
    attacker.hasFought = true;
    return report;
  }

  /**
   * Move to the next phase. Leaving the fight phase makes surviving enemy units
   * that are still in melee strike back, then ends the turn and passes play on.
   */
  advancePhase(): void {
    const s = this.state;
    if (s.winner !== null) return;
    if (s.phase === 'move') {
      s.phase = 'shoot';
    } else if (s.phase === 'shoot') {
      s.phase = 'fight';
    } else {
      this.retaliate();
      this.endTurn();
    }
  }

  // ---------------------------------------------------------------- internals

  private attack(
    attacker: UnitState,
    target: UnitState,
    weapons: WeaponProfile[],
    verb: string,
  ): AttackReport {
    const tp = this.profileOf(target);
    const results: WeaponResult[] = weapons.map((w) =>
      resolveWeapon(w, carriers(w, attacker.modelsLeft), tp, target, this.rng),
    );
    const damage = results.reduce((n, r) => n + r.damage, 0);
    const modelsKilled = results.reduce((n, r) => n + r.modelsKilled, 0);
    const detail = results
      .map((r) => `${r.weapon}: ${r.attacks} attacks, ${r.hits} hit, ${r.wounds} wound, ${r.failedSaves} unsaved`)
      .join('; ');
    const outcome = target.modelsLeft <= 0
      ? `${tp.name} destroyed`
      : `${modelsKilled} killed, ${target.modelsLeft} left`;
    this.log(attacker.owner, `${this.profileOf(attacker).name} ${verb} ${tp.name} (${detail}) — ${outcome}.`);
    this.checkAnnihilation();
    return { attackerId: attacker.id, targetId: target.id, results, damage, modelsKilled };
  }

  private retaliate(): void {
    const defender = other(this.state.activePlayer);
    for (const u of this.unitsOf(defender)) {
      if (u.hasFought || this.state.winner !== null) continue;
      const foes = this.engagedWith(u).filter((e) => this.weaponsOf(u, 'melee').length > 0 && e.modelsLeft > 0);
      if (foes.length === 0) continue;
      const foe = foes.reduce((best, e) =>
        this.expectedDamageVs(u, e, 'melee') > this.expectedDamageVs(u, best, 'melee') ? e : best,
      );
      this.attack(u, foe, this.weaponsOf(u, 'melee'), 'strikes back at');
      u.hasFought = true;
    }
  }

  private endTurn(): void {
    const s = this.state;
    for (const u of s.units) {
      u.hasMoved = false;
      u.hasShot = false;
      u.hasFought = false;
    }
    if (this.checkAnnihilation()) return;
    if (s.activePlayer === 1) {
      s.round += 1;
      if (s.round > this.scenario.roundLimit) {
        this.finishOnPoints();
        return;
      }
    }
    s.activePlayer = other(s.activePlayer);
    s.phase = 'move';
    this.log(s.activePlayer, `Round ${s.round} — ${this.playerName(s.activePlayer)} to move.`);
  }

  private checkAnnihilation(): boolean {
    const s = this.state;
    const alive0 = this.unitsOf(0).length > 0;
    const alive1 = this.unitsOf(1).length > 0;
    if (alive0 && alive1) return false;
    s.winner = !alive0 && !alive1 ? 'draw' : alive0 ? 0 : 1;
    this.announceWinner('wiped out the enemy');
    return true;
  }

  private finishOnPoints(): void {
    const a = this.score(0);
    const b = this.score(1);
    this.state.winner = Math.abs(a - b) < 0.5 ? 'draw' : a > b ? 0 : 1;
    this.announceWinner(`ahead on points (${a.toFixed(0)} to ${b.toFixed(0)})`);
  }

  private announceWinner(how: string): void {
    const w = this.state.winner;
    this.log(
      w === 1 ? 1 : 0,
      w === 'draw' ? `The game is a draw (${how}).` : `${this.playerName(w as PlayerId)} wins, ${how}.`,
    );
  }

  private log(player: PlayerId, text: string): void {
    this.state.log.push({ round: this.state.round, player, text });
  }
}

/** Create a game from a config. */
export function createGame(config: GameConfig): Game {
  return new Game(config);
}
