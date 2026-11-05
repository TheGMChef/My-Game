/**
 * Shared data types for the battle simulator.
 *
 * Everything here is plain data (no behaviour) so that unit stats, scenarios and
 * saved games can live in JSON files and be swapped without touching the engine.
 * All distances are in inches.
 */

/** A fixed number (`3`) or a dice expression (`"D6"`, `"2D6"`, `"D3"`, `"D6+2"`). */
export type Quantity = number | string;

/** Player index. Player 0 is the human by default in the UI. */
export type PlayerId = 0 | 1;

/** Turn phases, in order. */
export type Phase = 'move' | 'shoot' | 'fight';

/** One weapon entry on a unit profile. */
export interface WeaponProfile {
  name: string;
  kind: 'ranged' | 'melee';
  /** Maximum range in inches. Ignored for melee weapons. */
  range: number;
  /** Attacks per carrying model. */
  attacks: Quantity;
  /** Roll needed to hit, as the "X+" number (e.g. `3` means 3+). */
  skill: number;
  strength: number;
  /** Armour penetration as a positive number: `1` worsens the target's save by 1. */
  ap: number;
  /** Damage per unsaved wound. */
  damage: Quantity;
  /** How many models carry this weapon: a number, or `"all"` for every model. */
  count: number | 'all';
}

/** Static stat line for a kind of unit. */
export interface UnitProfile {
  id: string;
  name: string;
  /** Two-letter label drawn on the board. */
  short: string;
  /** Models in the unit at full strength. */
  models: number;
  toughness: number;
  /** Armour save as the "X+" number. */
  save: number;
  /** Optional invulnerable save as the "X+" number; ignores AP. */
  invuln?: number;
  /** Wounds per model. */
  wounds: number;
  /** Move distance in inches. */
  move: number;
  points: number;
  /** Radius of one model's base in inches; the unit footprint grows with model count. */
  baseRadius: number;
  weapons: WeaponProfile[];
}

/** Mutable state of one unit on the board. */
export interface UnitState {
  id: string;
  profileId: string;
  owner: PlayerId;
  x: number;
  y: number;
  modelsLeft: number;
  /** Wounds remaining on the model currently taking damage. */
  leadWounds: number;
  hasMoved: boolean;
  hasShot: boolean;
  hasFought: boolean;
}

/** A starting placement in a scenario. */
export interface ScenarioUnit {
  profile: string;
  x: number;
  y: number;
}

/** One side's army and presentation in a scenario. */
export interface ScenarioPlayer {
  name: string;
  /** CSS colour used by the renderer. */
  color: string;
  units: ScenarioUnit[];
}

/** A battlefield, the armies on it and the game length. */
export interface Scenario {
  name: string;
  board: { width: number; height: number };
  /** Number of full rounds (both players' turns) before the game is scored. */
  roundLimit: number;
  players: [ScenarioPlayer, ScenarioPlayer];
}

/** A line in the combat log. */
export interface LogEntry {
  round: number;
  player: PlayerId;
  text: string;
}

/** Game result: a winning player, a draw, or `null` while the game is running. */
export type Winner = PlayerId | 'draw' | null;

/** The whole mutable state of a game. */
export interface GameState {
  round: number;
  activePlayer: PlayerId;
  phase: Phase;
  units: UnitState[];
  log: LogEntry[];
  winner: Winner;
}

/** Outcome of resolving one weapon against a target. */
export interface WeaponResult {
  weapon: string;
  attacks: number;
  hits: number;
  wounds: number;
  failedSaves: number;
  damage: number;
  modelsKilled: number;
}

/** Outcome of one unit attacking another with all eligible weapons. */
export interface AttackReport {
  attackerId: string;
  targetId: string;
  results: WeaponResult[];
  damage: number;
  modelsKilled: number;
}
