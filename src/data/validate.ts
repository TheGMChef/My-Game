import { parseQuantity } from '../engine/dice.ts';
import type { Scenario, UnitProfile, WeaponProfile } from '../engine/types.ts';

type Obj = Record<string, unknown>;

function obj(v: unknown, where: string): Obj {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) throw new Error(`${where}: expected an object`);
  return v as Obj;
}

function str(o: Obj, key: string, where: string): string {
  const v = o[key];
  if (typeof v !== 'string' || v === '') throw new Error(`${where}: "${key}" must be a non-empty string`);
  return v;
}

function num(o: Obj, key: string, where: string, min: number, max = Infinity): number {
  const v = o[key];
  if (typeof v !== 'number' || !Number.isFinite(v) || v < min || v > max) {
    throw new Error(`${where}: "${key}" must be a number from ${min}${max === Infinity ? ' up' : ` to ${max}`}`);
  }
  return v;
}

function weapon(raw: unknown, where: string): WeaponProfile {
  const o = obj(raw, where);
  const kind = o.kind;
  if (kind !== 'ranged' && kind !== 'melee') throw new Error(`${where}: "kind" must be "ranged" or "melee"`);
  const attacks = o.attacks;
  const damage = o.damage;
  if (typeof attacks !== 'number' && typeof attacks !== 'string') throw new Error(`${where}: bad "attacks"`);
  if (typeof damage !== 'number' && typeof damage !== 'string') throw new Error(`${where}: bad "damage"`);
  parseQuantity(attacks);
  parseQuantity(damage);
  const count = o.count;
  if (count !== 'all' && !(typeof count === 'number' && Number.isInteger(count) && count >= 1)) {
    throw new Error(`${where}: "count" must be "all" or a whole number of at least 1`);
  }
  return {
    name: str(o, 'name', where),
    kind,
    range: kind === 'ranged' ? num(o, 'range', where, 1) : 0,
    attacks,
    skill: num(o, 'skill', where, 2, 6),
    strength: num(o, 'strength', where, 1),
    ap: num(o, 'ap', where, 0),
    damage,
    count,
  };
}

/** Validate and normalise a list of unit profiles loaded from JSON. Throws a readable error. */
export function validateProfiles(raw: unknown): UnitProfile[] {
  if (!Array.isArray(raw)) throw new Error('Unit data must be an array of profiles');
  const seen = new Set<string>();
  return raw.map((entry, i) => {
    const o = obj(entry, `unit #${i + 1}`);
    const id = str(o, 'id', `unit #${i + 1}`);
    const where = `unit "${id}"`;
    if (seen.has(id)) throw new Error(`${where}: duplicate id`);
    seen.add(id);
    if (!Array.isArray(o.weapons)) throw new Error(`${where}: "weapons" must be an array`);
    const profile: UnitProfile = {
      id,
      name: str(o, 'name', where),
      short: str(o, 'short', where),
      models: num(o, 'models', where, 1),
      toughness: num(o, 'toughness', where, 1),
      save: num(o, 'save', where, 2, 7),
      wounds: num(o, 'wounds', where, 1),
      move: num(o, 'move', where, 0),
      points: num(o, 'points', where, 0),
      baseRadius: num(o, 'baseRadius', where, 0.1),
      weapons: o.weapons.map((w, j) => weapon(w, `${where} weapon #${j + 1}`)),
    };
    if (o.invuln !== undefined) profile.invuln = num(o, 'invuln', where, 2, 6);
    return profile;
  });
}

/** Tuning values for the AI opponent, loaded from `ai.json`. */
export interface AiConfig {
  /** Ranged units try to sit at this fraction of their longest weapon range (0.1 to 1). */
  standoff: number;
  /** Melee units stop this many inches (edge to edge) from their target; must be inside melee range. */
  contactGap: number;
  /** Larger values make the AI care less about distance when choosing a target. */
  distanceWeight: number;
}

/** Validate AI tuning values. Throws a readable error. */
export function validateAiConfig(raw: unknown): AiConfig {
  const o = obj(raw, 'AI config');
  return {
    standoff: num(o, 'standoff', 'AI config', 0.1, 1),
    contactGap: num(o, 'contactGap', 'AI config', 0, 1),
    distanceWeight: num(o, 'distanceWeight', 'AI config', 1),
  };
}

/** Validate a scenario against the known profiles. Throws a readable error. */
export function validateScenario(raw: unknown, profiles: UnitProfile[]): Scenario {
  const o = obj(raw, 'scenario');
  const board = obj(o.board, 'scenario board');
  if (!Array.isArray(o.players) || o.players.length !== 2) throw new Error('scenario: "players" must list exactly two players');
  const known = new Set(profiles.map((p) => p.id));
  const players = o.players.map((p, i) => {
    const po = obj(p, `player #${i + 1}`);
    if (!Array.isArray(po.units) || po.units.length === 0) throw new Error(`player #${i + 1}: needs at least one unit`);
    return {
      name: str(po, 'name', `player #${i + 1}`),
      color: str(po, 'color', `player #${i + 1}`),
      units: po.units.map((u, j) => {
        const uo = obj(u, `player #${i + 1} unit #${j + 1}`);
        const profile = str(uo, 'profile', `player #${i + 1} unit #${j + 1}`);
        if (!known.has(profile)) throw new Error(`player #${i + 1} unit #${j + 1}: unknown profile "${profile}"`);
        return { profile, x: num(uo, 'x', `unit #${j + 1}`, 0), y: num(uo, 'y', `unit #${j + 1}`, 0) };
      }),
    };
  });
  return {
    name: str(o, 'name', 'scenario'),
    board: { width: num(board, 'width', 'scenario board', 1), height: num(board, 'height', 'scenario board', 1) },
    roundLimit: num(o, 'roundLimit', 'scenario', 1),
    players: [players[0]!, players[1]!],
  };
}
