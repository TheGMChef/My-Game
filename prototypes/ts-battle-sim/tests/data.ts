import { readFileSync } from 'node:fs';
import { validateAiConfig, validateProfiles, validateScenario } from '../src/data/validate.ts';
import type { AiConfig } from '../src/data/validate.ts';
import type { Scenario, UnitProfile } from '../src/engine/types.ts';

/**
 * Loads the shipped JSON data from disk. Only data and integration tests import
 * this file; pure unit tests use the in-memory fixtures in `helpers.ts`.
 */
function readJson(file: string): unknown {
  return JSON.parse(readFileSync(new URL(`../src/data/${file}`, import.meta.url), 'utf8'));
}

/** The shipped unit profiles, validated. */
export const profiles: UnitProfile[] = validateProfiles(readJson('units.json'));

/** The shipped scenario, validated. */
export const scenario: Scenario = validateScenario(readJson('scenario.json'), profiles);

/** The shipped AI tuning, validated. */
export const aiConfig: AiConfig = validateAiConfig(readJson('ai.json'));
