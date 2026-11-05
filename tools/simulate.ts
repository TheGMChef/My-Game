/**
 * Run many AI-vs-AI games on the shipped scenario and print summary statistics.
 * Handy for checking army balance and AI tuning after editing the JSON in src/data.
 *
 *   npm run sim            # 500 games
 *   npm run sim -- 2000    # 2000 games
 */
import { readFileSync } from 'node:fs';
import { playAiTurn } from '../src/ai/simpleAi.ts';
import { validateAiConfig, validateProfiles, validateScenario } from '../src/data/validate.ts';
import { Game } from '../src/engine/game.ts';

const read = (file: string): unknown =>
  JSON.parse(readFileSync(new URL(`../src/data/${file}`, import.meta.url), 'utf8'));

const profiles = validateProfiles(read('units.json'));
const scenario = validateScenario(read('scenario.json'), profiles);
const aiConfig = validateAiConfig(read('ai.json'));

const games = Math.max(1, Number(process.argv[2]) || 500);
const wins = [0, 0];
let draws = 0;
let wipeouts = 0;
let rounds = 0;
const left = [0, 0];

for (let seed = 1; seed <= games; seed++) {
  const game = new Game({ profiles, scenario, seed });
  while (game.state.winner === null) playAiTurn(game, aiConfig);
  const w = game.state.winner;
  if (w === 'draw') draws++;
  else wins[w]!++;
  if (game.state.log.at(-1)!.text.includes('wiped out')) wipeouts++;
  rounds += Math.min(game.state.round, scenario.roundLimit);
  left[0]! += game.score(0);
  left[1]! += game.score(1);
}

const pct = (n: number): string => `${((100 * n) / games).toFixed(1)}%`;
const start = (p: 0 | 1): number => scenario.players[p].units.reduce(
  (sum, u) => sum + profiles.find((x) => x.id === u.profile)!.points, 0);

console.log(`${games} AI-vs-AI games on "${scenario.name}"`);
for (const p of [0, 1] as const) {
  console.log(
    `  ${scenario.players[p].name.padEnd(12)} wins ${pct(wins[p]!).padStart(6)}   ` +
      `army ${start(p)} pts, average ${(left[p]! / games).toFixed(0)} pts left at the end`,
  );
}
console.log(`  draws ${pct(draws)}   ended by wipe-out ${pct(wipeouts)}   average rounds played ${(rounds / games).toFixed(2)}`);
