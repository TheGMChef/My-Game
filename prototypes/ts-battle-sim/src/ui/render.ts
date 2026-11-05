import type { AiDecision } from '../ai/simpleAi.ts';
import type { Game } from '../engine/game.ts';
import type { PlayerId, UnitState } from '../engine/types.ts';

/*
 * Display only: this file reads the game to draw it and never changes it.
 * Information is never carried by colour alone: sides also differ by marker shape
 * (triangle / square), health is an arc length, target highlights have tick marks,
 * and the "can I move here?" preview uses a solid or crossed-out outline.
 */

/** What the renderer needs besides the game itself. */
export interface View {
  selectedId: string | null;
  hover: { x: number; y: number } | null;
  /** The AI's most recent decisions, drawn as intent lines. */
  intents: AiDecision[];
  /** Colours for player 0 and player 1. */
  colours: [string, string];
  /** Multiplier for text drawn on the board. */
  textScale: number;
}

/** An Okabe-Ito pair that stays distinguishable for the common kinds of colour blindness. */
export const SAFE_COLOURS: [string, string] = ['#56b4e9', '#e69f00'];

/** The colours to use for each player, either the scenario's own or the colour-blind-safe pair. */
export function playerColours(game: Game, safe: boolean): [string, string] {
  if (safe) return SAFE_COLOURS;
  return [game.scenario.players[0].color, game.scenario.players[1].color];
}

const BG = '#141a21';
const GRID = '#1f2832';
const FRAME = '#2b3541';
const TARGET = '#ffd166';
const INK = '#ffffff';
const OUTLINE = '#0b0f14';

/** Draw the whole battlefield onto the canvas. The canvas size sets the resolution. */
export function draw(canvas: HTMLCanvasElement, game: Game, view: View): void {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const { width, height } = game.scenario.board;
  const s = canvas.width / width; // device pixels per inch
  const dpr = canvas.clientWidth > 0 ? canvas.width / canvas.clientWidth : 1;
  const lw = (cssPixels: number): number => (cssPixels * dpr) / s;

  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.setTransform(s, 0, 0, s, 0, 0);
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';

  // Ground and a 4" grid so distances can be judged by eye.
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, width, height);
  ctx.strokeStyle = GRID;
  ctx.lineWidth = lw(1);
  ctx.beginPath();
  for (let x = 4; x < width; x += 4) { ctx.moveTo(x, 0); ctx.lineTo(x, height); }
  for (let y = 4; y < height; y += 4) { ctx.moveTo(0, y); ctx.lineTo(width, y); }
  ctx.stroke();
  ctx.strokeStyle = FRAME;
  ctx.lineWidth = lw(2);
  ctx.strokeRect(0, 0, width, height);

  const { phase, activePlayer, winner } = game.state;
  const selected = view.selectedId
    ? game.state.units.find((u) => u.id === view.selectedId && u.modelsLeft > 0)
    : undefined;
  const live = winner === null && selected !== undefined && selected.owner === activePlayer;

  // Reach of the selected unit: move ring in the move phase, longest gun in the shoot phase.
  if (live && selected) {
    let reach = 0;
    if (phase === 'move' && !selected.hasMoved) reach = game.profileOf(selected).move;
    if (phase === 'shoot' && !selected.hasShot) {
      const longest = game.weaponsOf(selected, 'ranged').reduce((m, w) => Math.max(m, w.range), 0);
      if (longest > 0) reach = longest + game.radiusOf(selected);
    }
    if (reach > 0) {
      ctx.beginPath();
      ctx.arc(selected.x, selected.y, reach, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255,255,255,0.05)';
      ctx.fill();
      ctx.setLineDash([lw(8), lw(6)]);
      ctx.strokeStyle = 'rgba(255,255,255,0.4)';
      ctx.lineWidth = lw(1.5);
      ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  // What the AI intended on its last turn.
  for (const d of view.intents) {
    const from = game.state.units.find((u) => u.id === d.unitId);
    const to = game.state.units.find((u) => u.id === d.targetId);
    if (!from || !to || from.modelsLeft <= 0 || to.modelsLeft <= 0) continue;
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    if (d.kind === 'move') {
      ctx.setLineDash([lw(3), lw(6)]);
      ctx.strokeStyle = 'rgba(255,255,255,0.35)';
      ctx.lineWidth = lw(1.5);
    } else if (d.kind === 'shoot') {
      ctx.setLineDash([]);
      ctx.strokeStyle = TARGET;
      ctx.lineWidth = lw(2);
    } else {
      ctx.setLineDash([]);
      ctx.strokeStyle = INK;
      ctx.lineWidth = lw(4);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // Units.
  for (const u of game.state.units) {
    if (u.modelsLeft > 0) drawUnit(ctx, game, u, view, lw);
  }

  // Selection and valid targets.
  if (selected) {
    ctx.beginPath();
    ctx.arc(selected.x, selected.y, game.radiusOf(selected) + 0.45, 0, Math.PI * 2);
    ctx.strokeStyle = INK;
    ctx.lineWidth = lw(3);
    ctx.stroke();
  }
  if (live && selected && (phase === 'shoot' || phase === 'fight')) {
    for (const e of game.unitsOf(activePlayer === 0 ? 1 : 0)) {
      const ok = phase === 'shoot' ? game.checkShoot(selected, e).ok : game.checkFight(selected, e).ok;
      if (ok) drawTargetMark(ctx, e.x, e.y, game.radiusOf(e) + 0.9, lw);
    }
  }

  // Ghost of where the selected unit would end up.
  if (live && selected && phase === 'move' && !selected.hasMoved && view.hover) {
    const { x, y } = view.hover;
    const r = game.radiusOf(selected);
    const ok = game.checkMove(selected, x, y).ok;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.lineWidth = lw(2);
    if (ok) {
      ctx.fillStyle = 'rgba(255,255,255,0.16)';
      ctx.fill();
      ctx.strokeStyle = INK;
      ctx.stroke();
    } else {
      ctx.setLineDash([lw(5), lw(4)]);
      ctx.strokeStyle = 'rgba(255,255,255,0.7)';
      ctx.stroke();
      ctx.setLineDash([]);
      const k = r * 0.5;
      ctx.beginPath();
      ctx.moveTo(x - k, y - k); ctx.lineTo(x + k, y + k);
      ctx.moveTo(x + k, y - k); ctx.lineTo(x - k, y + k);
      ctx.stroke();
    }
  }
}

function drawUnit(
  ctx: CanvasRenderingContext2D,
  game: Game,
  u: UnitState,
  view: View,
  lw: (n: number) => number,
): void {
  const p = game.profileOf(u);
  const r = game.radiusOf(u);
  const colour = view.colours[u.owner];

  ctx.beginPath();
  ctx.arc(u.x, u.y, r, 0, Math.PI * 2);
  ctx.globalAlpha = 0.3;
  ctx.fillStyle = colour;
  ctx.fill();
  ctx.globalAlpha = 1;
  ctx.strokeStyle = colour;
  ctx.lineWidth = lw(2.5);
  ctx.stroke();

  // Health as arc length around the unit (not as a colour).
  const total = p.models * p.wounds;
  const left = (u.modelsLeft - 1) * p.wounds + u.leadWounds;
  ctx.beginPath();
  ctx.arc(u.x, u.y, r + 0.22, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (left / total));
  ctx.strokeStyle = INK;
  ctx.lineWidth = lw(3);
  ctx.stroke();

  drawSideMarker(ctx, u.owner, u.x - r * 0.72, u.y - r * 0.72, 0.5, colour, lw);

  // Text is sized to the unit but never smaller than 11 CSS pixels, so it stays readable on a phone.
  const size = Math.max(Math.min(1.6, Math.max(0.75, r * 0.7)) * view.textScale, lw(11));
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  // The model count only fits when the unit is big enough on screen (otherwise the side panel has it).
  const roomForCount = r > lw(15);
  label(ctx, p.short, u.x, u.y - (roomForCount ? size * 0.1 : 0), size, true, lw);
  if (roomForCount) label(ctx, `×${u.modelsLeft}`, u.x, u.y + size * 0.85, Math.max(size * 0.72, lw(9)), false, lw);
}

/** Triangle for player 0, square for player 1: tells the sides apart without colour. */
function drawSideMarker(
  ctx: CanvasRenderingContext2D,
  owner: PlayerId,
  x: number,
  y: number,
  size: number,
  colour: string,
  lw: (n: number) => number,
): void {
  ctx.beginPath();
  if (owner === 0) {
    ctx.moveTo(x, y - size);
    ctx.lineTo(x + size, y + size * 0.8);
    ctx.lineTo(x - size, y + size * 0.8);
    ctx.closePath();
  } else {
    ctx.rect(x - size * 0.85, y - size * 0.85, size * 1.7, size * 1.7);
  }
  ctx.fillStyle = colour;
  ctx.fill();
  ctx.strokeStyle = OUTLINE;
  ctx.lineWidth = lw(1.5);
  ctx.stroke();
}

/** A ring with four tick marks, so a valid target is recognisable without colour. */
function drawTargetMark(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  r: number,
  lw: (n: number) => number,
): void {
  ctx.strokeStyle = TARGET;
  ctx.lineWidth = lw(3);
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  const t = 0.7;
  ctx.moveTo(x - r - t, y); ctx.lineTo(x - r + t, y);
  ctx.moveTo(x + r - t, y); ctx.lineTo(x + r + t, y);
  ctx.moveTo(x, y - r - t); ctx.lineTo(x, y - r + t);
  ctx.moveTo(x, y + r - t); ctx.lineTo(x, y + r + t);
  ctx.stroke();
}

function label(
  ctx: CanvasRenderingContext2D,
  text: string,
  x: number,
  y: number,
  size: number,
  bold: boolean,
  lw: (n: number) => number,
): void {
  ctx.font = `${bold ? '700 ' : '600 '}${size}px system-ui, -apple-system, 'Segoe UI', sans-serif`;
  ctx.lineWidth = lw(3.5);
  ctx.strokeStyle = OUTLINE;
  ctx.strokeText(text, x, y);
  ctx.fillStyle = INK;
  ctx.fillText(text, x, y);
}
