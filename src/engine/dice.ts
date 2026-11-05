import type { Quantity } from './types.ts';

/** A source of random numbers in `[0, 1)`. Injected so games are reproducible. */
export interface Rng {
  next(): number;
}

/**
 * Create a seeded pseudo-random number generator (mulberry32).
 * The same seed always produces the same sequence.
 */
export function createRng(seed: number): Rng {
  let a = seed >>> 0;
  return {
    next(): number {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    },
  };
}

/** Roll one die with the given number of sides (default 6). */
export function rollDie(rng: Rng, sides = 6): number {
  return 1 + Math.floor(rng.next() * sides);
}

interface ParsedQuantity {
  dice: number;
  sides: number;
  flat: number;
}

/**
 * Parse a {@link Quantity}. Accepts numbers and expressions like `D6`, `2D6`,
 * `D3`, `D6+2`. Throws on anything else so bad data fails loudly at load time.
 */
export function parseQuantity(q: Quantity): ParsedQuantity {
  if (typeof q === 'number') {
    if (!Number.isFinite(q) || q < 0) throw new Error(`Invalid quantity: ${q}`);
    return { dice: 0, sides: 0, flat: q };
  }
  const m = /^\s*(\d*)\s*D(3|6)\s*(?:\+\s*(\d+))?\s*$/i.exec(q);
  if (!m) throw new Error(`Invalid quantity: "${q}"`);
  return {
    dice: m[1] ? parseInt(m[1], 10) : 1,
    sides: parseInt(m[2]!, 10),
    flat: m[3] ? parseInt(m[3], 10) : 0,
  };
}

/** Roll a {@link Quantity} and return the total. */
export function rollQuantity(q: Quantity, rng: Rng): number {
  const p = parseQuantity(q);
  let total = p.flat;
  for (let i = 0; i < p.dice; i++) total += rollDie(rng, p.sides);
  return total;
}

/** Average result of a {@link Quantity}; used by the AI and odds calculations. */
export function averageQuantity(q: Quantity): number {
  const p = parseQuantity(q);
  return p.dice * ((p.sides + 1) / 2) + p.flat;
}
