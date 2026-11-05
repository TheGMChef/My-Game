import { playAiTurn } from '../ai/simpleAi.ts';
import type { AiDecision } from '../ai/simpleAi.ts';
import { aiConfig, profiles, scenario } from '../data/index.ts';
import { Game } from '../engine/game.ts';
import type { PlayerId, UnitState } from '../engine/types.ts';
import { draw, playerColours } from './render.ts';
import type { View } from './render.ts';
import { t } from './strings.ts';
import type { StringKey } from './strings.ts';

/*
 * Wiring between the page and the engine. This file owns only view state: what is
 * selected, where the pointer is, and the display settings. The game itself is
 * changed only by asking the engine (game.move / shoot / fight / advancePhase),
 * which checks every request, and it is never written to directly.
 */

const HUMAN: PlayerId = 0;
const MARKERS = ['▲', '■'] as const; // same shapes as the board markers

type Mode = 'human' | 'ai';

// ------------------------------------------------------------------ helpers

function el<T extends HTMLElement>(id: string): T {
  const found = document.getElementById(id);
  if (!found) throw new Error(`Missing element #${id}`);
  return found as T;
}

function stored(key: string, fallback: string): string {
  try {
    return localStorage.getItem(`battlesim.${key}`) ?? fallback;
  } catch {
    return fallback;
  }
}

function store(key: string, value: string): void {
  try {
    localStorage.setItem(`battlesim.${key}`, value);
  } catch {
    /* storage can be unavailable (private windows); settings just will not persist */
  }
}

function node<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  text = '',
  className = '',
): HTMLElementTagNameMap[K] {
  const n = document.createElement(tag);
  if (text) n.textContent = text;
  if (className) n.className = className;
  return n;
}

// ------------------------------------------------------------------ state

const params = new URLSearchParams(location.search);
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const canvas = el<HTMLCanvasElement>('board');
const modeSelect = el<HTMLSelectElement>('mode');
const seedInput = el<HTMLInputElement>('seed');
const textSizeSelect = el<HTMLSelectElement>('text-size');
const coloursSelect = el<HTMLSelectElement>('colours');
const endButton = el<HTMLButtonElement>('end-phase');

let mode: Mode = params.get('ai') === 'both' ? 'ai' : (stored('mode', 'human') === 'ai' ? 'ai' : 'human');
let colourMode = params.get('colours') ?? stored('colours', 'default');
let textScale = Number(params.get('scale') ?? stored('textScale', '1')) || 1;
let seedEdited = false;
let seed = 1;
let game: Game;
let selectedId: string | null = null;
let hover: { x: number; y: number } | null = null;
let intents: AiDecision[] = [];
let message = '';
let aiTimer: number | undefined;

// ------------------------------------------------------------------ game flow

function randomSeed(): number {
  return Math.floor(Math.random() * 1_000_000_000);
}

function humanTurn(): boolean {
  return mode === 'human' && game.state.winner === null && game.state.activePlayer === HUMAN;
}

function startGame(newSeed: number): void {
  window.clearTimeout(aiTimer);
  seed = newSeed;
  game = new Game({ profiles, scenario, seed });
  seedInput.value = String(seed);
  seedEdited = false;
  selectedId = null;
  hover = null;
  intents = [];
  message = '';
  render();
  scheduleAi();
}

/** Let the AI take its turn after a short pause (no pause if the user prefers reduced motion). */
function scheduleAi(): void {
  window.clearTimeout(aiTimer);
  if (game.state.winner !== null) return;
  const aiToAct = mode === 'ai' || game.state.activePlayer !== HUMAN;
  if (!aiToAct) return;
  const delay = reduceMotion ? 0 : mode === 'ai' ? 900 : 500;
  aiTimer = window.setTimeout(() => {
    intents = playAiTurn(game, aiConfig);
    selectedId = null;
    render();
    scheduleAi();
  }, delay);
}

/** Skip any pacing: play every remaining AI turn at once. */
function skipToEnd(): void {
  window.clearTimeout(aiTimer);
  for (let guard = 0; game.state.winner === null && guard < 200; guard++) {
    intents = playAiTurn(game, aiConfig);
  }
  selectedId = null;
  render();
}

function onEndPhase(): void {
  if (game.state.winner !== null) return;
  if (mode === 'ai') {
    skipToEnd();
    return;
  }
  if (!humanTurn()) return;
  game.advancePhase();
  selectedId = null;
  message = '';
  render();
  scheduleAi();
}

// ------------------------------------------------------------------ input

function toBoard(ev: PointerEvent): { x: number; y: number } {
  const rect = canvas.getBoundingClientRect();
  const { width, height } = game.scenario.board;
  return {
    x: ((ev.clientX - rect.left) / rect.width) * width,
    y: ((ev.clientY - rect.top) / rect.height) * height,
  };
}

function unitAt(x: number, y: number): UnitState | undefined {
  let best: UnitState | undefined;
  let bestGap = Infinity;
  for (const u of game.state.units) {
    if (u.modelsLeft <= 0) continue;
    const gap = Math.hypot(u.x - x, u.y - y) - game.radiusOf(u);
    if (gap <= 0.4 && gap < bestGap) {
      best = u;
      bestGap = gap;
    }
  }
  return best;
}

function handleBoardClick(x: number, y: number): void {
  if (game.state.winner !== null) return;
  if (!humanTurn()) {
    message = t('msgNotYourTurn');
    return;
  }
  const hit = unitAt(x, y);
  if (hit && hit.owner === HUMAN) {
    selectedId = hit.id;
    message = '';
    return;
  }
  if (!selectedId) {
    message = t('msgSelectFirst');
    return;
  }
  const unit = game.getUnit(selectedId);
  if (game.state.phase === 'move') {
    const result = game.move(unit.id, x, y);
    if (result.ok) {
      selectedId = null;
      message = '';
    } else {
      message = result.reason;
    }
    return;
  }
  if (!hit) {
    message = t('msgPickEnemy');
    return;
  }
  const result = game.state.phase === 'shoot' ? game.shoot(unit.id, hit.id) : game.fight(unit.id, hit.id);
  if ('results' in result) {
    selectedId = null;
    message = '';
  } else if (!result.ok) {
    message = result.reason;
  }
}

canvas.addEventListener('pointerdown', (ev) => {
  const p = toBoard(ev);
  hover = p;
  handleBoardClick(p.x, p.y);
  render();
});

canvas.addEventListener('pointermove', (ev) => {
  if (ev.pointerType === 'touch') return;
  hover = toBoard(ev);
  render();
});

canvas.addEventListener('pointerleave', () => {
  hover = null;
  render();
});

document.addEventListener('keydown', (ev) => {
  if (ev.key === 'Escape') {
    selectedId = null;
    message = '';
    render();
    return;
  }
  const target = ev.target as HTMLElement | null;
  if (target && ['INPUT', 'SELECT', 'TEXTAREA', 'BUTTON'].includes(target.tagName)) return;
  if (ev.key === 'Enter') {
    onEndPhase();
  } else if (ev.key.toLowerCase() === 'n' && humanTurn()) {
    // Cycle through your own units from the keyboard.
    const own = game.unitsOf(HUMAN);
    if (own.length === 0) return;
    const index = own.findIndex((u) => u.id === selectedId);
    selectedId = own[(index + 1) % own.length]!.id;
    message = '';
    render();
  }
});

endButton.addEventListener('click', onEndPhase);
el<HTMLButtonElement>('new-game').addEventListener('click', () => {
  const typed = Number(seedInput.value);
  const useTyped = seedEdited && Number.isInteger(typed) && typed >= 0;
  startGame(useTyped ? typed : randomSeed());
});
seedInput.addEventListener('input', () => {
  seedEdited = true;
});
modeSelect.addEventListener('change', () => {
  mode = modeSelect.value === 'ai' ? 'ai' : 'human';
  store('mode', mode);
  startGame(seed); // switching who plays restarts the same battle
});
textSizeSelect.addEventListener('change', () => {
  applyTextScale(Number(textSizeSelect.value) || 1);
  render();
});
coloursSelect.addEventListener('change', () => {
  colourMode = coloursSelect.value === 'safe' ? 'safe' : 'default';
  store('colours', colourMode);
  render();
});

// ------------------------------------------------------------------ display

function applyStrings(): void {
  document.title = t('title');
  for (const n of document.querySelectorAll<HTMLElement>('[data-i18n]')) {
    n.textContent = t(n.dataset.i18n as StringKey);
  }
  for (const n of document.querySelectorAll<HTMLElement>('[data-i18n-aria]')) {
    n.setAttribute('aria-label', t(n.dataset.i18nAria as StringKey));
  }
}

function applyTextScale(scale: number): void {
  textScale = scale;
  document.documentElement.style.setProperty('--text-scale', String(scale));
  store('textScale', String(scale));
}

function fitCanvas(): void {
  const dpr = Math.min(window.devicePixelRatio || 1, 3);
  const { width, height } = game.scenario.board;
  canvas.style.aspectRatio = `${width} / ${height}`;
  const cssWidth = canvas.clientWidth || 600;
  canvas.width = Math.round(cssWidth * dpr);
  canvas.height = Math.round((cssWidth * dpr * height) / width);
}

const phaseLabel = { move: 'phaseMove', shoot: 'phaseShoot', fight: 'phaseFight' } as const;
const endLabel = { move: 'endMove', shoot: 'endShoot', fight: 'endFight' } as const;
const hintFor = { move: 'hintMove', shoot: 'hintShoot', fight: 'hintFight' } as const;

function render(): void {
  const colours = playerColours(game, colourMode === 'safe');
  const view: View = { selectedId, hover, intents, colours, textScale };
  draw(canvas, game, view);
  renderPanel(colours);
}

function renderPanel(colours: [string, string]): void {
  const s = game.state;

  // Status, hint and the main button.
  el('status').textContent =
    s.winner !== null
      ? t('statusOver')
      : t('statusLine', {
          round: Math.min(s.round, scenario.roundLimit),
          limit: scenario.roundLimit,
          player: game.playerName(s.activePlayer),
          phase: t(phaseLabel[s.phase]),
        });

  let base: string;
  if (s.winner !== null) base = t('hintOver');
  else if (mode === 'ai') base = t('hintWatching');
  else if (s.activePlayer !== HUMAN) base = t('hintAiTurn', { player: game.playerName(s.activePlayer) });
  else base = t(hintFor[s.phase]);
  const hint = el('hint');
  hint.textContent = base;
  if (message) hint.append(' ', node('span', message, 'warn'));

  if (s.winner !== null) endButton.textContent = t('statusOver');
  else endButton.textContent = mode === 'ai' ? t('skipToEnd') : t(endLabel[s.phase]);
  endButton.disabled = mode === 'ai' ? s.winner !== null : !humanTurn();

  // Banner.
  const banner = el('banner');
  banner.hidden = s.winner === null;
  if (s.winner !== null) {
    banner.textContent =
      s.winner === 'draw' ? t('bannerDraw') : t('bannerWin', { player: game.playerName(s.winner) });
  }

  // Armies.
  const armies = el('armies');
  armies.replaceChildren(
    ...([0, 1] as const).map((p) => {
      const row = node('div', '', 'army');
      row.style.borderLeftColor = colours[p];
      const marker = node('span', MARKERS[p]);
      marker.setAttribute('aria-hidden', 'true');
      marker.style.color = colours[p];
      row.append(
        marker,
        node('span', game.playerName(p), 'name'),
        node('span', t('armyMeta', { units: game.unitsOf(p).length, points: Math.round(game.score(p)) }), 'meta'),
      );
      return row;
    }),
  );

  // Selected unit.
  const panel = el('selected');
  const sel = selectedId ? game.state.units.find((u) => u.id === selectedId && u.modelsLeft > 0) : undefined;
  if (!sel) {
    panel.replaceChildren(document.createTextNode(t('selectedNone')));
  } else {
    const p = game.profileOf(sel);
    const wounds = (sel.modelsLeft - 1) * p.wounds + sel.leadWounds;
    const table = node('table');
    const head = node('tr');
    for (const k of ['colWeapon', 'colRange', 'colAttacks', 'colSkill', 'colStrength', 'colAp', 'colDamage'] as const) {
      head.append(node('th', t(k)));
    }
    table.append(head);
    for (const w of p.weapons) {
      const row = node('tr');
      const cells = [
        w.name,
        w.kind === 'melee' ? t('melee') : `${w.range}"`,
        String(w.attacks),
        `${w.skill}+`,
        String(w.strength),
        w.ap === 0 ? '0' : `-${w.ap}`,
        String(w.damage),
      ];
      for (const c of cells) row.append(node('td', c));
      table.append(row);
    }
    panel.replaceChildren(
      node('strong', p.name),
      node(
        'div',
        t('selectedStats', { models: sel.modelsLeft, maxModels: p.models, wounds, move: p.move }),
      ),
      table,
    );
  }

  // Log (newest at the bottom).
  const log = el('log');
  log.replaceChildren(
    ...s.log.slice(-80).map((entry) => {
      const li = node('li');
      const marker = node('span', `${MARKERS[entry.player]} `);
      marker.setAttribute('aria-hidden', 'true');
      marker.style.color = colours[entry.player];
      li.append(marker, document.createTextNode(entry.text));
      return li;
    }),
  );
  log.scrollTop = log.scrollHeight;
}

// ------------------------------------------------------------------ start

applyStrings();
textSizeSelect.value = String(textScale);
if (![...textSizeSelect.options].some((o) => o.value === textSizeSelect.value)) textSizeSelect.value = '1';
applyTextScale(Number(textSizeSelect.value));
coloursSelect.value = colourMode === 'safe' ? 'safe' : 'default';
modeSelect.value = mode;

const firstSeed = Number(params.get('seed'));
seed = Number.isInteger(firstSeed) && params.has('seed') && firstSeed >= 0 ? firstSeed : randomSeed();
game = new Game({ profiles, scenario, seed });
fitCanvas();

const stopAfter = Number(params.get('stop') ?? 0);
if (mode === 'ai' && stopAfter > 0) {
  // Jump straight to a mid-game position (used for reproducible screenshots).
  while (game.state.winner === null && game.state.round <= stopAfter) intents = playAiTurn(game, aiConfig);
  seedInput.value = String(seed);
  render();
} else {
  startGame(seed);
}

new ResizeObserver(() => {
  fitCanvas();
  render();
}).observe(canvas);
