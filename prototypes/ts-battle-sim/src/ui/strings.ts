/**
 * All user-facing text for the interface lives here, keyed by name, so nothing in
 * the UI code or the HTML is hardcoded and a translation is one more table.
 * Placeholders look like `{name}` and are filled by {@link t}.
 */
export const en = {
  title: 'Battle Sim',
  boardLabel: 'Battlefield. Select one of your units, then click the board.',

  phaseMove: 'Move',
  phaseShoot: 'Shoot',
  phaseFight: 'Fight',

  endMove: 'End move phase',
  endShoot: 'End shoot phase',
  endFight: 'End fight phase and turn',
  skipToEnd: 'Skip to the end',
  newGame: 'New game',

  mode: 'Mode',
  modeHuman: 'You vs AI',
  modeAi: 'Watch AI vs AI',
  seed: 'Seed',
  textSize: 'Text size',
  size100: '100%',
  size125: '125%',
  size150: '150%',
  colours: 'Colours',
  coloursDefault: 'Default',
  coloursSafe: 'Colour-blind safe',

  statusLine: 'Round {round} of {limit} · {player} · {phase} phase',
  statusOver: 'Game over',
  hintMove: 'Pick one of your units, then click where it should go. It can move anywhere inside the dashed ring.',
  hintShoot: 'Pick a unit, then click a marked enemy in range. Units locked in melee cannot shoot.',
  hintFight: 'Pick a unit touching an enemy, then click that enemy. Survivors strike back when you end the phase.',
  hintAiTurn: '{player} is taking its turn.',
  hintWatching: 'Watching the AI play both sides.',
  hintOver: 'Start a new game to play again.',
  bannerWin: '{player} wins',
  bannerDraw: 'The game is a draw',

  armyMeta: '{units} units · {points} points',
  selectedNone: 'Select one of your units to see its details.',
  selectedStats: '{models} of {maxModels} models · {wounds} wounds left · move {move}"',
  colWeapon: 'Weapon',
  colRange: 'Range',
  colAttacks: 'A',
  colSkill: 'Hit',
  colStrength: 'S',
  colAp: 'AP',
  colDamage: 'D',
  melee: 'melee',

  msgSelectFirst: 'Select one of your units first.',
  msgPickEnemy: 'Click an enemy unit.',
  msgNotYourTurn: 'It is not your turn.',

  logHeading: 'Combat log',
} as const;

/** Every valid string key. */
export type StringKey = keyof typeof en;

/** Look up a string and fill its `{placeholders}`. Unknown keys return the key itself so gaps are visible. */
export function t(key: StringKey, params: Record<string, string | number> = {}): string {
  const template: string = en[key] ?? key;
  return template.replace(/\{(\w+)\}/g, (match, name: string) =>
    name in params ? String(params[name]) : match,
  );
}
