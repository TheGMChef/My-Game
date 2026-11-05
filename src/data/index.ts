import aiJson from './ai.json';
import scenarioJson from './scenario.json';
import unitsJson from './units.json';
import { validateAiConfig, validateProfiles, validateScenario } from './validate.ts';

/**
 * Built-in data for the browser build. Edit `units.json`, `scenario.json` and
 * `ai.json` to change the armies and the AI's tuning; they are validated here
 * when the page loads.
 *
 * (Node scripts and tests read the same JSON files with `fs` instead, so the
 * engine itself never depends on how the data is loaded.)
 */
export const profiles = validateProfiles(unitsJson);
export const scenario = validateScenario(scenarioJson, profiles);
export const aiConfig = validateAiConfig(aiJson);
