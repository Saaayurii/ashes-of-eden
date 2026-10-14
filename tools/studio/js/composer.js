/* Sprite Studio — the room composer, «Конструктор» (tools/rooms/compose.py, docs/ROOM_COMPOSER.md).
 * One painted room is one 1280×720 picture: as big as an image model draws. Here a room becomes a grid
 * of such pictures — two in a row, two by two, an L — and the generator stitches the seams. What the
 * hero walks on is drawn over the grid: a room's own ledges come along with its panel, the tracer
 * (lib.js traceLedges, a port of tools/rooms/trace_panel.py) offers more from the picture, and every
 * rectangle, ramp and thing can be dragged, stretched, added and taken away by hand. The route is
 * checked as it changes (lib.js composeReach = painted_rooms.check_reach). A draft opens in Godot
 * with `room=<name> --composed`; ticked «В игре», it replaces the room.
 *
 * Three views. «Клетки»: the pictures side by side, the seam bands marked. «Сшитый»: the picture the
 * generator will paint (lib.js composeTiles, a port of compose.py). «Объём»: the room as the game's
 * camera sees it, the mouse being the camera — the far plates slide in their openings, the pieces in
 * front of the hero (tools/rooms/front.py) run ahead of it — and its layers are edited there: the
 * openings onto the far plate, the front pieces, the candles.
 *
 * A crumbling platform (crumbling_platform.gd) is drawn, moved and stretched like a rectangle but kept
 * as [x, y, w] or [x, y, w, kind]: its height is the plank's own. It is dashed, never on the route. */
'use strict';

const COMP_RECTS = { ground: ['Земля', '#6fae5a'], ledges: ['Уступ', '#e0b54a'], platforms: ['Платформа', '#5fb3d9'],
  crumbling_platforms: ['Осыпь', '#d98a4a'], hazards: ['Опасность', '#e0503c'] };
const COMP_THINGS = { spawns: ['Враг', '#ff6b6b'], props: ['Предмет', '#c9a0ff'], npcs: ['Человек', '#7fe0c0'] };
const COMP_THICK = { ground: 120, ledges: 14, platforms: 10, crumbling_platforms: 8, hazards: 40 };
// A rectangle's [x, y, w, h] as drawn, and back: a crumbling platform keeps no height, only its kind.
const COMP_CRUMBLE = 'crumbling_platforms';
const compRect = (k, r) => k === COMP_CRUMBLE ? [r[0], r[1], r[2], COMP_THICK[k]] : r;
const compUnrect = (k, rect, was = []) => k === COMP_CRUMBLE ? [rect[0], rect[1], rect[2], ...was.slice(3)] : rect;
const COMP_LAYERS = { windows: ['Окно вдаль', '#7fb2ff'], front: ['Передний план', '#4ee0e0'], lights: ['Свеча', '#ffb060'] };
// What the game's camera shows, in room pixels (640×360 at the hero's zoom, player.gd).
const COMP_VIEW = [640 / 1.14, 360 / 1.14];
const COMP = { data: null, name: '', entry: null, sel: null, tool: 'select', cell: null, scale: 0.5, ox: 20, oy: 20,
  images: new Map(), uploads: {}, candidates: [], reach: null, undo: [], redo: [], drag: null, dirty: false, raf: 0,
  view: 'cells', built: new Map(), cam: null, frontCands: [], pieces: new Map() };

const compCell = () => COMP.data.cell;
const compSize = () => composeGrid(COMP.entry, compCell());
function compImage(stem) {
  if (COMP.images.has(stem)) return COMP.images.get(stem);
  const im = new Image(); im.onload = () => compDraw(); im.src = COMP.uploads[stem] ? URL.createObjectURL(COMP.uploads[stem]) : A(`assets/levels/${stem}.png`);
  COMP.images.set(stem, im); return im;
}

const compLoaded = im => im.complete && im.naturalWidth ? Promise.resolve(im)
  : new Promise(r => { im.addEventListener('load', () => r(im), { once: true }); im.addEventListener('error', () => r(im), { once: true }); });
const compPanel = stem => COMP.data.panels.find(p => p.stem === stem) || {};
// What lies behind a cell's openings: its room's inpainted plate, or the painting itself.
const compPlateStem = stem => (compPanel(stem).plate || '').replace(/^assets\/levels\//, '').replace(/\.png$/, '') || stem;

/* ---------- the layers: openings, front pieces, candles — the cells' own until she touches them ---------- */
const compWindows = () => composeWindows(COMP.entry, COMP.data.panels, compCell());
function compAutoLights() {
  const [cw, ch] = compCell();
  return COMP.entry.cells.flatMap(c => (compPanel(c.painting).lights || []).map(([x, y, ...rest]) => [x + c.col * cw, y + c.row * ch, ...rest]));
}
const compLights = () => COMP.entry.lights || compAutoLights();
// compose.depth_parallax: how far the far plate travels per pixel of camera, the cells' rooms' own.
function compStrength() {
  const s = COMP.entry.cells.map(c => compPanel(c.painting).strength).filter(v => v != null);
  return s.length ? s.reduce((a, b) => a + b, 0) / s.length : 0.025;
}
// Before the first edit of a layer the cells' own become hers, written out in the table.
function compOwnLayers(e) {
  e.windows ??= compWindows(); e.lights ??= compAutoLights(); e.front ??= [];
}
const compLayer = k => k === 'windows' ? compWindows() : k === 'lights' ? compLights() : COMP.entry.front || [];
// The seams the generator stitches: a band of SEAM each side of every inner cell edge.
function compSeams() {
  const { cols, rows, width, height } = compSize(), [cw, ch] = compCell(), b = COMP.data.seam;
  return [...Array.from({ length: cols - 1 }, (_, i) => [(i + 1) * cw - b, 0, 2 * b, height]),
          ...Array.from({ length: rows - 1 }, (_, i) => [0, (i + 1) * ch - b, width, 2 * b])];
}
// What stands in a seam: the picture there is made by the stitch, so a ledge may no longer match it.
function compInSeams() {
  const e = COMP.entry, bands = compSeams(), out = [];
  const inBand = (x, y) => bands.some(([bx, by, bw, bh]) => x >= bx && x <= bx + bw && y >= by && y <= by + bh);
  const hits = (x, y, w, h) => bands.some(([bx, by, bw, bh]) => x < bx + bw && bx < x + w && y < by + bh && by < y + h);
  for (const k of ['ground', 'ledges', 'platforms', COMP_CRUMBLE]) e[k].forEach((r, i) => {
    // a floor running on through the seam is expected; an edge of one ending in it is what to look at
    const across = bands.some(([, by, bw, bh]) => bw === compSize().width && r[1] >= by && r[1] <= by + bh);
    const end = across ? r[0] + r[2] / 2 : [r[0], r[0] + r[2]].find(ex => inBand(ex, r[1]));
    if (end !== undefined) out.push({ k, i, text: `${COMP_RECTS[k][0]} ${r[0]},${r[1]}: край в шве`, at: [end, r[1]] });
  });
  for (const k of Object.keys(COMP_THINGS)) e[k].forEach(([id, x, y], i) => { if (hits(x - 1, y - 1, 2, 2)) out.push({ k, i, text: `${id} стоит в шве`, at: [x, y] }); });
  return out;
}

/* ---------- the stitched picture and plate (lib.js composeTiles = compose.py), built once per grid ---------- */
async function compFloats(stem) {
  const [cw, ch] = compCell(), im = await compLoaded(compImage(stem));
  const c = mk(cw, ch), x = c.getContext('2d', { willReadFrequently: true });
  if (im.naturalWidth) x.drawImage(im, 0, 0, cw, ch);
  return composeImage(cw, ch, Float32Array.from(x.getImageData(0, 0, cw, ch).data));
}
function compBuilt(kind) {
  const sig = kind + JSON.stringify(COMP.entry.cells.map(c => [c.painting, c.col, c.row]));
  const got = COMP.built.get(sig);
  if (got) return got.canvas || null;
  const job = { canvas: null };
  COMP.built.set(sig, job);
  $('#compVerdict').textContent = kind === 'plate' ? 'собираю дальний план…' : 'сшиваю картины…';
  (async () => {
    try {
      const tiles = new Map();
      for (const c of COMP.entry.cells) tiles.set(`${c.col},${c.row}`, await compFloats(kind === 'plate' ? compPlateStem(c.painting) : c.painting));
      await new Promise(r => setTimeout(r, 20));
      const { cols, rows } = compSize(), pic = composeTiles(tiles, cols, rows, compCell(), COMP.data.seam);
      const c = mk(pic.w, pic.h), x = c.getContext('2d'), out = x.createImageData(pic.w, pic.h);
      for (let i = 0; i < pic.d.length; i++) out.data[i] = Math.floor(pic.d[i] + 0.5);
      x.putImageData(out, 0, 0); job.canvas = c;
    } catch (err) { toast('Не удалось сшить: ' + err.message, 'err'); }
    $('#compVerdict').textContent = '';
    compDraw();
  })();
  return null;
}

/* ---------- a front piece as the game draws it (front.py bake: keyed, darkened, scaled, softened) ---------- */
function compPiece(piece) {
  const key = JSON.stringify(piece) + (COMP.uploads[piece.from] ? '+' : '');
  if (COMP.pieces.has(key)) return COMP.pieces.get(key);
  const im = compImage(piece.from);
  if (!im.complete || !im.naturalWidth) return null;
  const [x0, y0, w, h] = piece.crop, d = piece.depth ?? 1.35;
  const c = mk(w, h), x = c.getContext('2d', { willReadFrequently: true });
  if (piece.flip) { x.translate(w, 0); x.scale(-1, 1); }
  x.drawImage(im, x0, y0, w, h, 0, 0, w, h);
  const px = x.getImageData(0, 0, w, h), cut = piece.cut ?? 70, keep = 1 - (piece.dark ?? 0.8);
  const fade = frontEdgeFade(w, h, piece.feather ?? (piece.key === 'alpha' ? 0 : 0.18));
  for (let i = 0; i < px.data.length; i += 4) {
    if ((piece.key || 'dark') === 'dark') {
      const lum = (px.data[i] + px.data[i + 1] + px.data[i + 2]) / 3;
      px.data[i + 3] *= Math.min(1, Math.max(0, (cut - lum) / 24 + 0.5));
    }
    px.data[i + 3] *= fade[i >> 2];
    for (let k = 0; k < 3; k++) px.data[i + k] *= keep;
  }
  x.putImageData(px, 0, 0);
  const blur = piece.blur ?? Math.round((d - 1) * 300) / 100, out = mk(Math.round(w * d), Math.round(h * d)), o = out.getContext('2d');
  o.filter = blur > 0 ? `blur(${blur}px)` : 'none'; o.drawImage(c, 0, 0, out.width, out.height);
  COMP.pieces.set(key, out);
  return out;
}

/* ---------- the draft: one per room, kept in this browser until it is sent ---------- */
function compStored() { try { return JSON.parse(localStorage.getItem('ss_composer') || '{}'); } catch { return {}; } }
function compKeep() {
  COMP.dirty = true; trackChange('comp');
  try { localStorage.setItem('ss_composer', JSON.stringify({ ...compStored(), [COMP.name]: COMP.entry })); } catch {}
}
function compFresh(name) {
  const own = COMP.data.rooms[name];
  const { player, door, ...geom } = composeShift(own, 0, 0);
  return { live: false, cells: [{ painting: own.painting, col: 0, row: 0 }], ...geom, player, door };
}
function compOpen(name) {
  COMP.name = name; COMP.sel = null; COMP.cell = { col: 0, row: 0 }; COMP.candidates = []; COMP.undo = []; COMP.redo = [];
  const kept = compStored()[name];
  COMP.entry = structuredClone(kept || COMP.data.composed[name] || compFresh(name));
  COMP.dirty = !!kept;
  for (const k of COMPOSE_LISTS) COMP.entry[k] ??= [];
  compFit(); compChanged(false);
}
// Every change goes through here: a step to undo, the route checked again, the panels redrawn.
function compEdit(fn) {
  COMP.undo.push(JSON.stringify(COMP.entry)); if (COMP.undo.length > 200) COMP.undo.shift(); COMP.redo = [];
  fn(COMP.entry); compChanged(true);
}
function compChanged(keep) {
  COMP.reach = composeReach(COMP.entry, COMP.data.reach);
  if (keep) compKeep();
  renderComposer(); compDraw();
}
const compUndo = redo => redo ? compStep(COMP.redo, COMP.undo) : compStep(COMP.undo, COMP.redo);
function compStep(from, to) {
  if (!from.length) return toast('Нечего ' + (from === COMP.redo ? 'возвращать' : 'отменять'));
  to.push(JSON.stringify(COMP.entry)); COMP.entry = JSON.parse(from.pop()); COMP.sel = null; compChanged(true);
}

/* ---------- the grid of cells ---------- */
function compCellAt(col, row) { return COMP.entry.cells.find(c => c.col === col && c.row === row); }
async function compPickPanel(col, row) {
  const panels = COMP.data.panels;
  let chosen = null;
  const html = `<h3>Картина для клетки ${col + 1}×${row + 1}</h3>
    <p class="muted">Любая 1280×720: задник комнаты из игры или новая. Своя картина подгоняется под 1280×720 (обрезается по центру).</p>
    <label class="sm">Своя картина <input type="file" accept="image/*" id="compUpload"></label>
    <div class="comppanels">${panels.map(p => `<button class="comppanel" data-stem="${esc(p.stem)}" title="${esc(p.stem)}"><img loading="lazy" src="${esc(COMP.uploads[p.stem] ? URL.createObjectURL(COMP.uploads[p.stem]) : A(p.url))}"><span>${esc(p.room || p.stem)}</span></button>`).join('')}</div>`;
  const d = document.getElementById('dlg');
  const picked = new Promise(res => {
    d.addEventListener('click', function on(e) { const b = e.target.closest('.comppanel'); if (b) { chosen = b.dataset.stem; d.removeEventListener('click', on); d.close(); res(); } });
    d.addEventListener('change', async function on(e) {
      if (e.target.id !== 'compUpload' || !e.target.files[0]) return;
      d.removeEventListener('change', on);
      try { chosen = await compUpload(e.target.files[0]); } catch (err) { toast(err.message, 'err'); }
      d.close(); res();
    });
    d.addEventListener('close', () => res(), { once: true });
  });
  dialog(html, [['Отмена']]);
  await picked;
  return chosen;
}
// A picture of her own: fitted to a cell (cover, centred), saved beside the game's as assets/levels/panels/<name>.png.
async function compUpload(file) {
  const im = await loadImage(URL.createObjectURL(file)), [w, h] = compCell();
  const c = mk(w, h), x = c.getContext('2d'), s = Math.max(w / im.naturalWidth, h / im.naturalHeight);
  x.imageSmoothingQuality = 'high';
  x.drawImage(im, (w - im.naturalWidth * s) / 2, (h - im.naturalHeight * s) / 2, im.naturalWidth * s, im.naturalHeight * s);
  let stem = 'panels/' + slug(file.name.replace(/\.[^.]+$/, ''));
  while (COMP.data.panels.some(p => p.stem === stem) && !COMP.uploads[stem]) stem += '_2';
  COMP.uploads[stem] = await canvasBlob(c); COMP.images.delete(stem);
  if (!COMP.data.panels.some(p => p.stem === stem)) COMP.data.panels.push({ stem, url: '', room: '' });
  return stem;
}
async function compSetCell(col, row) {
  const stem = await compPickPanel(col, row); if (!stem) return;
  const owner = COMP.data.panels.find(p => p.stem === stem)?.room;
  const bring = owner && COMP.data.rooms[owner] && confirm(`Это задник комнаты ${owner}. Взять и её уступы, врагов и вещи?\n\n(Вход и дверь не переносятся — они одни на всю комнату.)`);
  const [cw, ch] = compCell();
  compEdit(e => {
    const old = compCellAt(col, row);
    if (old) old.painting = stem; else e.cells.push({ painting: stem, col, row });
    if (bring) {
      const moved = composeShift(COMP.data.rooms[owner], col * cw, row * ch);
      for (const k of COMPOSE_LISTS) e[k] = [...(e[k] || []), ...moved[k]];
    }
  });
  COMP.cell = { col, row };
}
function compRemoveCell(col, row) {
  if (COMP.entry.cells.length < 2) return toast('Одна клетка должна остаться', 'err');
  const [cw, ch] = compCell(), inside = (x, y) => x >= col * cw && x < (col + 1) * cw && y >= row * ch && y < (row + 1) * ch;
  compEdit(e => {
    e.cells = e.cells.filter(c => c.col !== col || c.row !== row);
    // what stood in the cell goes with it; what only crossed it is cut back to the rest of the room
    for (const k of Object.keys(COMP_RECTS)) e[k] = e[k].filter(r => { const [x, y, w, h] = compRect(k, r); return !(inside(x, y) && inside(x + w - 1, y + h - 1)); });
    for (const k of Object.keys(COMP_THINGS)) e[k] = e[k].filter(([, x, y]) => !inside(x, y));
    e.ramps = e.ramps.filter(([x0, y0, x1, y1]) => !inside(x0, y0) && !inside(x1, y1));
    // the grid may have lost a whole column or row on the left or top: the room starts at the first one left
    const dc = Math.min(...e.cells.map(c => c.col)), dr = Math.min(...e.cells.map(c => c.row));
    if (dc || dr) {
      for (const c of e.cells) { c.col -= dc; c.row -= dr; }
      Object.assign(e, composeShift(e, -dc * cw, -dr * ch));
    }
    Object.assign(e, composeClip(e, composeGrid(e, compCell()).width, composeGrid(e, compCell()).height));
  });
  COMP.cell = null;
}
function renderCompGrid() {
  const { cols, rows } = compSize(), [mc, mr] = COMP.data.max;
  const showC = Math.min(mc, cols + 1), showR = Math.min(mr, rows + 1);
  let html = `<div class="compgrid" style="grid-template-columns:repeat(${showC},1fr)">`;
  for (let r = 0; r < showR; r++) for (let c = 0; c < showC; c++) {
    const cell = compCellAt(c, r), on = COMP.cell && COMP.cell.col === c && COMP.cell.row === r;
    html += cell
      ? `<button class="compcell${on ? ' on' : ''}" data-act="comp-cell" data-c="${c}" data-r="${r}" title="${esc(cell.painting)}"><img src="${esc(compImage(cell.painting).src)}"></button>`
      : `<button class="compcell empty" data-act="comp-add" data-c="${c}" data-r="${r}" title="Добавить картину сюда">+</button>`;
  }
  return html + '</div>';
}

/* ---------- the side panel ---------- */
function compSelected() {
  const s = COMP.sel; if (!s) return null;
  if (s.k === 'player' || s.k === 'door') return COMP.entry[s.k];
  if (COMP_LAYERS[s.k]) return compLayer(s.k)[s.i] || null;
  return COMP.entry[s.k]?.[s.i] || null;
}
function renderComposer() {
  if (!COMP.entry) return;
  const e = COMP.entry, { width, height, cols, rows } = compSize(), r = COMP.reach;
  $('#compRooms').value = COMP.name;
  const cell = COMP.cell && compCellAt(COMP.cell.col, COMP.cell.row);
  const s = COMP.sel, v = compSelected();
  let selHtml = '<div class="muted">Ничего не выбрано. Щёлкни по уступу, врагу или предмету на картине.</div>';
  if (s && v) {
    const name = s.k === 'player' ? 'Вход' : s.k === 'door' ? 'Дверь' : (COMP_RECTS[s.k] || COMP_THINGS[s.k] || COMP_LAYERS[s.k] || ['Наклон'])[0];
    const num = (i, label) => `<label>${label}<input type="number" data-compv="${i}" value="${Math.round(v[i])}"></label>`;
    const fields = s.k === 'ramps' ? [num(0, 'x₀'), num(1, 'y₀'), num(2, 'x₁'), num(3, 'y₁')]
      : s.k === COMP_CRUMBLE ? [num(0, 'x'), num(1, 'y'), num(2, 'ширина'),
        `<label title="Как она выглядит в игре (crumbling_platform.gd)">Из<select data-compsurf>${[['stone', 'камня'], ['timber', 'досок']].map(([id, l]) => `<option value="${id}"${(v[3] || 'stone') === id ? ' selected' : ''}>${l}</option>`).join('')}</select></label>`,
        '<div class="muted">Осыпается под героем и вырастает снова; путь на неё не рассчитывает.</div>']
      : COMP_RECTS[s.k] ? [num(0, 'x'), num(1, 'y'), num(2, 'ширина'), num(3, 'высота')]
      : COMP_THINGS[s.k] ? [`<label>Кто<select data-compid>${COMP.data[s.k === 'spawns' ? 'enemies' : s.k].map(id => `<option${id === v[0] ? ' selected' : ''}>${esc(id)}</option>`).join('')}</select></label>`, num(1, 'x'), num(2, 'y')]
      : [num(0, 'x'), num(1, 'y')];
    const kinds = COMP_RECTS[s.k] ? `<label>Это<select data-compkind>${Object.entries(COMP_RECTS).map(([k, [l]]) => `<option value="${k}"${k === s.k ? ' selected' : ''}>${l}</option>`).join('')}</select></label>` : '';
    if (COMP_LAYERS[s.k]) selHtml = compLayerFields(s.k, v);
    else selHtml = `<div class="row"><b>${name}</b><span class="grow"></span>${s.k !== 'player' && s.k !== 'door' ? '<button class="sm danger" data-act="comp-del" title="Убрать (Delete)">✕ Убрать</button>' : ''}</div>
      <div class="compfields">${kinds}${fields.join('')}</div>`;
  }
  const fatal = r.problems.filter(p => p.fatal), soft = r.problems.filter(p => !p.fatal), seams = compInSeams();
  const nW = compWindows().length, nF = (e.front || []).length, nL = compLights().length;
  $('#compSide').querySelector('#compBody').innerHTML = `
    <div class="card"><b>Сетка</b> <span class="muted">${cols}×${rows} — ${width}×${height} px</span>
      ${renderCompGrid()}
      ${cell ? `<div class="row"><span class="muted grow">${esc(cell.painting)}</span><button class="sm" data-act="comp-replace">Заменить</button><button class="sm danger" data-act="comp-remove">Убрать клетку</button></div>` : '<div class="muted">«+» — добавить картину. Швы между картинами генератор сошьёт сам.</div>'}
    </div>
    <div class="card">${selHtml}</div>
    <div class="card"><b>Путь героя</b>
      ${fatal.length ? fatal.map((p, i) => `<div class="warn compprob" data-prob="${i}">✗ ${esc(p.text)}</div>`).join('') : '<div class="ok">✓ От входа до двери, ко всем врагам и вещам можно дойти</div>'}
      ${soft.length ? `<div class="muted">${soft.length} площадк${soft.length === 1 ? 'а' : 'и'} вне пути (подсвечены серым)</div>` : ''}
    </div>
    ${seams.length ? `<div class="card"><b>Швы</b> <span class="muted">картину там рисует сшивка — проверь в виде «Сшитый»</span>
      ${seams.slice(0, 8).map(p => `<div class="muted">≈ ${esc(p.text)}</div>`).join('')}${seams.length > 8 ? `<div class="muted">и ещё ${seams.length - 8}</div>` : ''}</div>` : ''}
    <div class="card"><b>Объём</b> <span class="muted">вид «Объём»: мышь — камера</span>
      <div class="muted">Окон вдаль: ${nW}${e.windows ? '' : ' (из комнат клеток)'} · передний план: ${nF} · свечей: ${nL}${e.lights ? '' : ' (найдены сами)'}</div>
      ${e.windows || e.lights || e.front ? '<button class="sm" data-act="comp-layers-reset" title="Вернуть окна и свечи, какие дают комнаты клеток, и убрать передний план">↺ Слои как у клеток</button>' : ''}
    </div>
    <div class="card"><label title="Пока выключено, это черновик: scenes/rooms/composed/${esc(COMP.name)}.tscn, открывается кнопкой «▶ В Godot». Включено — комната в игре заменяется собранной, и путь героя обязан сходиться."><input type="checkbox" id="compLive"${e.live ? ' checked' : ''}> В игре вместо комнаты ${esc(COMP.name)}</label>
      ${e.live ? '<div class="warn">Собранная комната заменит настоящую. Проверь её в Godot до отправки.</div>' : '<div class="muted">Черновик: игра идёт по старой комнате.</div>'}
    </div>`;
  const send = $('#compSend'); send.textContent = COMP.dirty ? '→ В игру •' : '→ В игру';
  send.disabled = !COMP.dirty;
  $$('[data-comptool]').forEach(b => b.classList.toggle('on', b.dataset.comptool === COMP.tool));
  $$('[data-compview]').forEach(b => b.classList.toggle('on', b.dataset.compview === COMP.view));
  $('#compVerdict').textContent = COMP.candidates.length ? `найдено уступов: ${COMP.candidates.length} — щёлкни жёлтый, чтобы взять`
    : COMP.frontCands.length ? `кандидатов в передний план: ${COMP.frontCands.length} — щёлкни голубую рамку` : '';
}

// An opening, a front piece or a candle: what it is made of, field by field (data-compl, not rounded).
function compLayerFields(k, v) {
  const num = (f, label, step, val, tip = '') => `<label title="${tip}">${label}<input type="number" step="${step}" data-compl="${f}" value="${val}"></label>`;
  let fields;
  if (k === 'windows') fields = [num('depth', 'глубина', 0.02, v.depth ?? 0.84, 'Насколько далеко: чем больше, тем сильнее дальний план отстаёт от камеры (0…1.6)'),
    `<label title="Сквозь это окно видно небо — по нему плывут облака"><input type="checkbox" data-compl="sky"${v.sky ? ' checked' : ''}> небо</label>`,
    `<div class="muted">Точек: ${v.points.length}. Тяни окно целиком или за угол.</div>`];
  else if (k === 'front') fields = [num('depth', 'близость', 0.05, v.depth ?? 1.35, 'Во сколько раз быстрее камеры бежит (1.05…1.8) — и во столько же раз крупнее'),
    num('dark', 'темнота', 0.05, v.dark ?? 0.8, '0 — как на картине, 1 — чёрный силуэт (контражур)'),
    ...((v.key || 'dark') === 'dark' ? [num('cut', 'порог', 5, v.cut ?? 70, 'Что темнее этой яркости (0…255), то и остаётся от вырезки')] : []),
    num('feather', 'края', 0.02, v.feather ?? (v.key === 'alpha' ? 0 : 0.18), 'Как широко гаснут края вырезки (доля короткой стороны, 0…0.5): чтобы не было видно прямоугольника'),
    num('blur', 'размытие', 0.25, v.blur ?? Math.round(((v.depth ?? 1.35) - 1) * 300) / 100, 'Мягкость, px: ближнее не в фокусе'),
    `<label><input type="checkbox" data-compl="flip"${v.flip ? ' checked' : ''}> зеркально</label>`,
    `<label>Вырезать<select data-compl="key"><option value="dark"${(v.key || 'dark') === 'dark' ? ' selected' : ''}>тёмное</option><option value="alpha"${v.key === 'alpha' ? ' selected' : ''}>по прозрачности</option></select></label>`,
    `<div class="muted">Из ${esc(v.from)}, кусок ${v.crop.join('×')}.</div>`];
  else fields = [`<label>Цвет<input type="color" data-compl="2" value="${esc(v[2])}"></label>`,
    num(3, 'радиус', 2, v[3]), num(4, 'сила', 0.05, v[4]), num(5, 'мерцание', 0.05, v[5])];
  return `<div class="row"><b>${COMP_LAYERS[k][0]}</b><span class="grow"></span><button class="sm danger" data-act="comp-del" title="Убрать (Delete)">✕ Убрать</button></div>
    <div class="compfields">${fields.join('')}</div>`;
}

/* ---------- the canvas ---------- */
const compToRoom = (px, py) => [(px - COMP.ox) / COMP.scale, (py - COMP.oy) / COMP.scale];
function compFit() {
  const c = $('#compCanvas'), st = $('#compStage').getBoundingClientRect();
  c.width = Math.max(200, Math.floor(st.width)); c.height = Math.max(200, Math.floor(st.height));
  const { width, height } = compSize();
  COMP.scale = Math.min((c.width - 40) / width, (c.height - 40) / height);
  COMP.ox = (c.width - width * COMP.scale) / 2; COMP.oy = (c.height - height * COMP.scale) / 2;
}
function compDraw() {
  if (COMP.raf || !COMP.entry) return;
  COMP.raf = requestAnimationFrame(() => { COMP.raf = 0; compPaint(); });
}
function compPaint() {
  const c = $('#compCanvas'), x = c.getContext('2d'), e = COMP.entry, [cw, ch] = compCell(), S = COMP.scale;
  const { width, height } = compSize();
  x.setTransform(1, 0, 0, 1, 0, 0); x.fillStyle = '#111'; x.fillRect(0, 0, c.width, c.height);
  x.setTransform(S, 0, 0, S, COMP.ox, COMP.oy);
  x.fillStyle = '#050505'; x.fillRect(0, 0, width, height);
  const stitched = COMP.view !== 'cells' && compBuilt('picture');
  if (stitched) x.drawImage(stitched, 0, 0);
  else for (const cell of e.cells) { const im = compImage(cell.painting); if (im.complete && im.naturalWidth) x.drawImage(im, cell.col * cw, cell.row * ch, cw, ch); }
  if (COMP.view === 'depth') return compPaintDepth(x, S, stitched);
  // the seam bands: there the picture is the stitch's, not either painting's
  x.fillStyle = COMP.view === 'cells' ? '#ff9a3c22' : '#ff9a3c10';
  for (const [bx, by, bw, bh] of compSeams()) x.fillRect(bx, by, bw, bh);
  x.lineWidth = 1 / S;
  x.strokeStyle = '#ffffff40'; x.setLineDash([8 / S, 6 / S]);
  for (let gx = cw; gx < width; gx += cw) { x.beginPath(); x.moveTo(gx, 0); x.lineTo(gx, height); x.stroke(); }
  for (let gy = ch; gy < height; gy += ch) { x.beginPath(); x.moveTo(0, gy); x.lineTo(width, gy); x.stroke(); }
  x.setLineDash([]);
  // what the route reaches: a surface off it is grey
  const surf = COMP.reach.surfaces, idx = new Map(); let n = 0;
  for (const k of ['ground', 'ledges', 'platforms']) e[k].forEach((_, i) => idx.set(k + i, n++));
  for (const [k, [, col]] of Object.entries(COMP_RECTS)) e[k].forEach((raw, i) => {
    const r = compRect(k, raw), on = COMP.sel && COMP.sel.k === k && COMP.sel.i === i, lost = idx.has(k + i) && !COMP.reach.seen.has(idx.get(k + i));
    x.fillStyle = (lost ? '#888888' : col) + (k === 'hazards' ? '44' : '55'); x.fillRect(r[0], r[1], r[2], r[3]);
    // a crumbling platform is dashed: it gives way, the route does not count on it
    if (k === COMP_CRUMBLE) x.setLineDash([5 / S, 3 / S]);
    x.strokeStyle = on ? '#fff' : lost ? '#999' : col; x.lineWidth = (on ? 2.5 : 1.5) / S; x.strokeRect(r[0], r[1], r[2], r[3]);
    x.setLineDash([]);
    if (k !== 'hazards') { x.fillStyle = lost ? '#aaa' : col; x.fillRect(r[0], r[1] - 1 / S, r[2], 3 / S); }
    if (on) for (const [hx, hy] of [[r[0], r[1] + r[3] / 2], [r[0] + r[2], r[1] + r[3] / 2], ...(k === COMP_CRUMBLE ? [] : [[r[0] + r[2], r[1] + r[3]]])]) { x.fillStyle = '#fff'; x.fillRect(hx - 4 / S, hy - 4 / S, 8 / S, 8 / S); }
  });
  e.ramps.forEach((r, i) => {
    const on = COMP.sel && COMP.sel.k === 'ramps' && COMP.sel.i === i;
    x.strokeStyle = on ? '#fff' : '#e0b54a'; x.lineWidth = (on ? 4 : 3) / S; x.beginPath(); x.moveTo(r[0], r[1]); x.lineTo(r[2], r[3]); x.stroke();
    x.fillStyle = '#fff'; for (const [hx, hy] of [[r[0], r[1]], [r[2], r[3]]]) { x.beginPath(); x.arc(hx, hy, 4 / S, 0, 7); x.fill(); }
  });
  x.setLineDash([6 / S, 4 / S]); x.strokeStyle = '#ffe14a'; x.lineWidth = 2 / S;
  for (const [cx, cy, cwid] of COMP.candidates) x.strokeRect(cx, cy, cwid, COMP_THICK.ledges);
  x.setLineDash([]);
  x.font = `${12 / S}px sans-serif`; x.textAlign = 'center';
  const dot = (px, py, col, label, on) => {
    x.fillStyle = col; x.strokeStyle = on ? '#fff' : '#000'; x.lineWidth = (on ? 3 : 1.5) / S;
    x.beginPath(); x.arc(px, py, 7 / S, 0, 7); x.fill(); x.stroke();
    x.fillStyle = '#fff'; x.strokeStyle = '#000'; x.lineWidth = 3 / S; x.strokeText(label, px, py - 11 / S); x.fillText(label, px, py - 11 / S);
  };
  for (const [k, [, col]] of Object.entries(COMP_THINGS)) e[k].forEach(([id, px, py], i) => dot(px, py, col, id, COMP.sel && COMP.sel.k === k && COMP.sel.i === i));
  if (e.player) dot(e.player[0], e.player[1], '#5fd35f', 'вход', COMP.sel?.k === 'player');
  if (e.door) dot(e.door[0], e.door[1], '#ffd75f', 'дверь', COMP.sel?.k === 'door');
  for (const p of COMP.reach.problems) if (p.fatal && p.at) { x.strokeStyle = '#ff3b3b'; x.lineWidth = 3 / S; x.beginPath(); x.arc(p.at[0], p.at[1], 16 / S, 0, 7); x.stroke(); }
  for (const p of compInSeams()) { x.strokeStyle = '#ff9a3c'; x.lineWidth = 2 / S; x.setLineDash([3 / S, 3 / S]); x.beginPath(); x.arc(p.at[0], p.at[1], 12 / S, 0, 7); x.stroke(); x.setLineDash([]); }
  compPaintFrontCands(x, S);
  compPaintBox(x, S);
}
function compPaintBox(x, S) {
  if (COMP.drag?.box) { const b = COMP.drag.box; x.strokeStyle = '#fff'; x.setLineDash([4 / S, 4 / S]); x.lineWidth = 1.5 / S; x.strokeRect(b[0], b[1], b[2], b[3]); x.setLineDash([]); }
}
function compPaintFrontCands(x, S) {
  x.setLineDash([6 / S, 4 / S]); x.strokeStyle = COMP_LAYERS.front[1]; x.lineWidth = 2 / S;
  for (const f of COMP.frontCands) x.strokeRect(...f.box);
  x.setLineDash([]);
}
// Where the camera looks in the «Объём» view: the mouse, kept inside the room as the game's camera is.
function compCam() {
  const { width, height } = compSize(), [vw, vh] = COMP_VIEW, c = COMP.cam || [vw / 2, height - vh / 2];
  return [Math.min(Math.max(c[0], vw / 2), Math.max(vw / 2, width - vw / 2)), Math.min(Math.max(c[1], vh / 2), Math.max(vh / 2, height - vh / 2))];
}
const compPoly = (x, pts) => { x.beginPath(); pts.forEach(([px, py], i) => i ? x.lineTo(px, py) : x.moveTo(px, py)); x.closePath(); };
// The room as the game draws it, three planes: the far plate in its openings sliding a little with the
// camera (room.gd: shift = min(max(0, camera_left) · depth_parallax · depth, 16)), the stitched picture,
// and the front pieces running ahead (FrontLayer.at). Then the layers' outlines, to be picked.
function compPaintDepth(x, S, stitched) {
  const [cx, cy] = compCam(), [vw, vh] = COMP_VIEW, travel = Math.max(0, cx - vw / 2) * compStrength();
  const plate = compBuilt('plate'), wins = compWindows(), sel = COMP.sel;
  if (plate && stitched) wins.forEach(w => {
    const shift = Math.min(travel * (w.depth ?? 0.84), 16);
    x.save(); compPoly(x, w.points); x.clip(); x.drawImage(plate, shift, 0); x.restore();
  });
  for (const piece of COMP.entry.front || []) {
    const baked = compPiece(piece), b = frontBox(piece), [px, py] = frontAt([b.cx, b.cy], [cx, cy], piece.depth ?? 1.35);
    if (baked) x.drawImage(baked, px - baked.width / 2, py - baked.height / 2);
  }
  // outside the camera the room is dimmed, as it would be off the screen
  x.fillStyle = '#000000a0'; x.beginPath(); x.rect(-1e4, -1e4, 3e4, 3e4); x.rect(cx - vw / 2, cy - vh / 2, vw, vh); x.fill('evenodd');
  x.strokeStyle = '#ffffffc0'; x.lineWidth = 1.5 / S; x.strokeRect(cx - vw / 2, cy - vh / 2, vw, vh);
  x.lineWidth = 1.5 / S;
  wins.forEach((w, i) => {
    const on = sel?.k === 'windows' && sel.i === i;
    x.strokeStyle = on ? '#fff' : COMP_LAYERS.windows[1]; x.setLineDash(w.sky ? [] : [5 / S, 4 / S]); compPoly(x, w.points); x.stroke();
    if (on) for (const [hx, hy] of w.points) { x.fillStyle = '#fff'; x.fillRect(hx - 4 / S, hy - 4 / S, 8 / S, 8 / S); }
  });
  x.setLineDash([]);
  (COMP.entry.front || []).forEach((piece, i) => {
    const [px, py, w, h] = compFrontDrawn(piece, [cx, cy]);
    x.strokeStyle = sel?.k === 'front' && sel.i === i ? '#fff' : COMP_LAYERS.front[1] + '90'; x.strokeRect(px, py, w, h);
  });
  compLights().forEach(([lx, ly, tint, radius], i) => {
    const on = sel?.k === 'lights' && sel.i === i;
    const g = x.createRadialGradient(lx, ly, 0, lx, ly, radius); g.addColorStop(0, tint + '80'); g.addColorStop(1, tint + '00');
    x.fillStyle = g; x.fillRect(lx - radius, ly - radius, 2 * radius, 2 * radius);
    x.fillStyle = tint; x.strokeStyle = on ? '#fff' : '#000'; x.lineWidth = (on ? 3 : 1.5) / S; x.beginPath(); x.arc(lx, ly, 5 / S, 0, 7); x.fill(); x.stroke();
  });
  compPaintFrontCands(x, S);
  compPaintBox(x, S);
}
// A front piece's box as it is drawn with the camera at `cam`.
function compFrontDrawn(piece, cam) {
  const b = frontBox(piece), [px, py] = frontAt([b.cx, b.cy], cam, piece.depth ?? 1.35);
  return [px - b.w / 2, py - b.h / 2, b.w, b.h];
}
function compInPoly(pts, px, py) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > py) !== (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
// In «Объём» only the layers are picked: a candle, a front piece where it is drawn, an opening or its corner.
function compHitLayer(rx, ry) {
  const near = 10 / COMP.scale, cam = compCam();
  const lights = compLights();
  for (let i = lights.length - 1; i >= 0; i--) if (Math.hypot(lights[i][0] - rx, lights[i][1] - ry) < near) return { k: 'lights', i, part: 'move' };
  const front = COMP.entry.front || [];
  for (let i = front.length - 1; i >= 0; i--) { const [px, py, w, h] = compFrontDrawn(front[i], cam); if (rx >= px && rx <= px + w && ry >= py && ry <= py + h) return { k: 'front', i, part: 'move' }; }
  const wins = compWindows();
  if (COMP.sel?.k === 'windows' && wins[COMP.sel.i]) {
    const v = wins[COMP.sel.i].points.findIndex(([px, py]) => Math.hypot(px - rx, py - ry) < near);
    if (v >= 0) return { k: 'windows', i: COMP.sel.i, part: 'v' + v };
  }
  for (let i = wins.length - 1; i >= 0; i--) if (compInPoly(wins[i].points, rx, ry)) return { k: 'windows', i, part: 'move' };
  return null;
}
// What is under the pointer, nearest first: a thing, a ramp's end, a rectangle's handle, its body.
function compHit(rx, ry) {
  const e = COMP.entry, near = 10 / COMP.scale;
  for (const k of ['player', 'door']) if (e[k] && Math.hypot(e[k][0] - rx, e[k][1] - ry) < near) return { k, part: 'move' };
  for (const k of Object.keys(COMP_THINGS)) for (let i = e[k].length - 1; i >= 0; i--) if (Math.hypot(e[k][i][1] - rx, e[k][i][2] - ry) < near) return { k, i, part: 'move' };
  for (let i = e.ramps.length - 1; i >= 0; i--) { const r = e.ramps[i];
    if (Math.hypot(r[0] - rx, r[1] - ry) < near) return { k: 'ramps', i, part: 'a' };
    if (Math.hypot(r[2] - rx, r[3] - ry) < near) return { k: 'ramps', i, part: 'b' };
    const t = Math.max(0, Math.min(1, ((rx - r[0]) * (r[2] - r[0]) + (ry - r[1]) * (r[3] - r[1])) / Math.max(1, (r[2] - r[0]) ** 2 + (r[3] - r[1]) ** 2)));
    if (Math.hypot(r[0] + t * (r[2] - r[0]) - rx, r[1] + t * (r[3] - r[1]) - ry) < near / 2) return { k: 'ramps', i, part: 'move' };
  }
  for (const k of ['hazards', COMP_CRUMBLE, 'platforms', 'ledges', 'ground']) for (let i = e[k].length - 1; i >= 0; i--) {
    const [x, y, w, h] = compRect(k, e[k][i]);
    if (COMP.sel?.k === k && COMP.sel.i === i) {
      // the handles never cover more than a quarter of it: the middle always moves it
      const grip = Math.min(near, w / 4), gy = Math.min(near, h / 2);
      if (k !== COMP_CRUMBLE && Math.abs(rx - (x + w)) < grip && Math.abs(ry - (y + h)) < gy) return { k, i, part: 'corner' };
      if (Math.abs(rx - (x + w)) < grip && ry > y - gy && ry < y + h) return { k, i, part: 'right' };
      if (Math.abs(rx - x) < grip && ry > y - gy && ry < y + h) return { k, i, part: 'left' };
    }
    if (rx >= x - near / 2 && rx <= x + w + near / 2 && ry >= y - near / 2 && ry <= y + Math.max(h, near)) return { k, i, part: 'move' };
  }
  return null;
}
function compPointer(e) {
  const r = $('#compCanvas').getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top];
}
function compDown(ev) {
  const [px, py] = compPointer(ev), [rx, ry] = compToRoom(px, py);
  $('#compCanvas').setPointerCapture(ev.pointerId);
  if (ev.button === 1 || ev.button === 2 || COMP.space) { COMP.drag = { pan: true, px, py, ox: COMP.ox, oy: COMP.oy }; return; }
  const tool = COMP.tool;
  if (tool === 'select' && COMP.frontCands.length) {
    const f = COMP.frontCands.findIndex(c => rx >= c.box[0] && rx <= c.box[0] + c.box[2] && ry >= c.box[1] && ry <= c.box[1] + c.box[3]);
    if (f >= 0 && !(COMP.view === 'depth' && compHitLayer(rx, ry))) {
      const cand = COMP.frontCands.splice(f, 1)[0];
      return compAddFront(cand.cell, cand.crop);
    }
  }
  if (tool === 'select' && COMP.view === 'depth') {
    const hit = compHitLayer(rx, ry);
    COMP.sel = hit ? { k: hit.k, i: hit.i } : null; renderComposer(); compDraw();
    if (hit) COMP.drag = { hit, rx, ry, start: JSON.stringify(COMP.entry), was: structuredClone(compSelected()) };
    return;
  }
  if (tool === 'lights') {
    compEdit(e => { compOwnLayers(e); e.lights.push([Math.round(rx), Math.round(ry), '#ffb060', 36, 0.5, 0.3]); });
    COMP.sel = { k: 'lights', i: COMP.entry.lights.length - 1 }; COMP.tool = 'select'; return renderComposer();
  }
  if (tool === 'windows' || tool === 'front') { COMP.drag = { make: tool, rx, ry, box: [rx, ry, 0, 0] }; return; }
  if (tool === 'select') {
    const cand = COMP.candidates.findIndex(([cx, cy, cwid]) => rx >= cx && rx <= cx + cwid && Math.abs(ry - cy) < 10 / COMP.scale);
    const hit = compHit(rx, ry);
    if (!hit && cand >= 0) {
      const [cx, cy, cwid] = COMP.candidates.splice(cand, 1)[0];
      compEdit(e => e.ledges.push([cx, cy, cwid, COMP_THICK.ledges]));
      COMP.sel = { k: 'ledges', i: COMP.entry.ledges.length - 1 }; return renderComposer();
    }
    COMP.sel = hit ? { k: hit.k, i: hit.i } : null; renderComposer(); compDraw();
    if (hit) COMP.drag = { hit, rx, ry, start: JSON.stringify(COMP.entry), was: structuredClone(compSelected()) };
    return;
  }
  if (COMP_RECTS[tool] || tool === 'ramps') { COMP.drag = { make: tool, rx, ry, box: [rx, ry, 0, 0] }; return; }
  if (COMP_THINGS[tool]) {
    const id = tool === 'spawns' ? (COMP.lastId?.spawns || COMP.data.enemies[0]) : tool === 'props' ? (COMP.lastId?.props || 'barrel') : (COMP.lastId?.npcs || COMP.data.npcs[0]);
    compEdit(e => e[tool].push([id, Math.round(rx), Math.round(ry)]));
    COMP.sel = { k: tool, i: COMP.entry[tool].length - 1 }; COMP.tool = 'select'; renderComposer();
  }
}
function compMove(ev) {
  const d = COMP.drag, [px, py] = compPointer(ev);
  if (!d) { if (COMP.view === 'depth') { COMP.cam = compToRoom(px, py); compDraw(); } return; }
  if (d.pan) { COMP.ox = d.ox + px - d.px; COMP.oy = d.oy + py - d.py; return compDraw(); }
  const [rx, ry] = compToRoom(px, py), dx = Math.round(rx - d.rx), dy = Math.round(ry - d.ry);
  if (d.make) { d.ex = rx; d.ey = ry; d.box = [Math.min(d.rx, rx), Math.min(d.ry, ry), Math.abs(rx - d.rx), Math.abs(ry - d.ry)]; return compDraw(); }
  if (!d.hit) return;
  const { k, i, part } = d.hit, w = d.was, e = COMP.entry;
  if (!d.moved && COMP_LAYERS[k]) compOwnLayers(e);
  d.moved = true;
  if (k === 'windows') e.windows[i] = { ...w, points: w.points.map(([x, y], v) => part === 'move' || part === 'v' + v ? [x + dx, y + dy] : [x, y]) };
  else if (k === 'front') e.front[i] = { ...w, at: [w.at[0] + dx, w.at[1] + dy] };
  else if (k === 'lights') e.lights[i] = [w[0] + dx, w[1] + dy, ...w.slice(2)];
  else if (k === 'player' || k === 'door') e[k] = [w[0] + dx, w[1] + dy];
  else if (COMP_THINGS[k]) e[k][i] = [w[0], w[1] + dx, w[2] + dy];
  else if (k === 'ramps') e[k][i] = part === 'a' ? [w[0] + dx, w[1] + dy, w[2], w[3]] : part === 'b' ? [w[0], w[1], w[2] + dx, w[3] + dy] : [w[0] + dx, w[1] + dy, w[2] + dx, w[3] + dy];
  else {
    const r = compRect(k, w);
    e[k][i] = compUnrect(k, part === 'move' ? [r[0] + dx, r[1] + dy, r[2], r[3]] : part === 'right' ? [r[0], r[1], Math.max(4, r[2] + dx), r[3]]
      : part === 'left' ? [Math.min(r[0] + dx, r[0] + r[2] - 4), r[1], Math.max(4, r[2] - dx), r[3]] : [r[0], r[1], Math.max(4, r[2] + dx), Math.max(2, r[3] + dy)], w);
  }
  COMP.reach = composeReach(e, COMP.data.reach); compDraw();
}
function compUp() {
  const d = COMP.drag; COMP.drag = null; if (!d) return;
  if (d.make) {
    const [x, y, w, h] = d.box.map(Math.round), tool = d.make;
    if (w < 6 && h < 6) return compDraw();
    if (tool === 'windows') {
      const ch = compCell()[1];
      compEdit(e => { compOwnLayers(e); e.windows.push({ points: [[x, y], [x + w, y], [x + w, y + h], [x, y + h]], depth: 0.84, sky: y % ch < 16 }); });
      COMP.sel = { k: 'windows', i: COMP.entry.windows.length - 1 }; COMP.tool = 'select'; return renderComposer();
    }
    if (tool === 'front') {
      const [cw, ch] = compCell(), cell = compCellAt(Math.floor((x + w / 2) / cw), Math.floor((y + h / 2) / ch));
      if (!cell) return toast('Передний план вырезается из картины клетки — тяни рамку по картине', 'err');
      return compAddFront(cell, [x - cell.col * cw, y - cell.row * ch, w, h]);
    }
    compEdit(e => {
      if (tool === 'ramps') e.ramps.push([d.rx, d.ry, d.ex, d.ey].map(Math.round));
      else e[tool].push(compUnrect(tool, [x, y, Math.max(4, w), Math.max(2, tool === 'hazards' || h > 6 ? h : COMP_THICK[tool])]));
    });
    COMP.sel = { k: tool, i: COMP.entry[tool].length - 1 }; COMP.tool = 'select'; return renderComposer();
  }
  if (d.moved) {
    // the step to undo is the whole drag, not every pixel of it
    COMP.undo.push(d.start); COMP.redo = []; compClamp(); compChanged(true);
  }
}
function compDelete() {
  const s = COMP.sel; COMP.sel = null;
  compEdit(en => { if (COMP_LAYERS[s.k]) compOwnLayers(en); en[s.k].splice(s.i, 1); });
}
function compClamp() {
  const { width, height } = compSize();
  Object.assign(COMP.entry, composeClip(COMP.entry, width, height));
}
function compWheel(ev) {
  ev.preventDefault();
  const [px, py] = compPointer(ev), [rx, ry] = compToRoom(px, py), f = Math.exp(-ev.deltaY * 0.0015);
  COMP.scale = Math.min(4, Math.max(0.08, COMP.scale * f));
  COMP.ox = px - rx * COMP.scale; COMP.oy = py - ry * COMP.scale; compDraw();
}

/* ---------- the front plane: pieces cut from the cells' own paintings ---------- */
// A crop of a cell's painting (cell pixels) becomes a piece standing where the crop was, its foot kept:
// it is drawn `depth` times larger, so it grows up and to both sides from the bottom middle.
function compAddFront(cell, crop) {
  const [cw, ch] = compCell(), d = 1.35;
  let [x, y, w, h] = crop.map(Math.round);
  x = Math.max(0, Math.min(x, cw - 4)); y = Math.max(0, Math.min(y, ch - 4));
  w = Math.max(4, Math.min(w, cw - x)); h = Math.max(4, Math.min(h, ch - y));
  if ((COMP.entry.front || []).length >= COMP.data.front.max) return toast(`Не больше ${COMP.data.front.max} кусков переднего плана в комнате`, 'err');
  // a piece hanging from the top of the picture keeps its top, one standing below keeps its foot
  const hangs = y < 8, foot = [cell.col * cw + x + w / 2, cell.row * ch + (hangs ? y : y + h)];
  const piece = { from: cell.painting, crop: [x, y, w, h], at: [Math.round(foot[0] - w * d / 2), Math.round(hangs ? foot[1] : foot[1] - h * d)], depth: d, dark: 0.8, cut: 70 };
  compEdit(e => { compOwnLayers(e); e.front.push(piece); });
  COMP.sel = { k: 'front', i: COMP.entry.front.length - 1 }; COMP.tool = 'select';
  if (COMP.view !== 'depth') COMP.view = 'depth';
  renderComposer(); compDraw();
}
// Dark masses along the bottom and top of each painting (lib.js frontCandidates), offered as cyan frames.
async function compFindFront() {
  const [cw, ch] = compCell(), out = [];
  $('#compVerdict').textContent = 'ищу передний план…';
  for (const cell of COMP.entry.cells) {
    const im = await compLoaded(compImage(cell.painting));
    const c = mk(cw, ch), x = c.getContext('2d', { willReadFrequently: true }); x.drawImage(im, 0, 0, cw, ch);
    let px; try { px = x.getImageData(0, 0, cw, ch).data; } catch { toast('Картину нельзя прочитать (CORS)', 'err'); continue; }
    const lum = new Float32Array(cw * ch);
    for (let p = 0; p < cw * ch; p++) lum[p] = (px[p * 4] + px[p * 4 + 1] + px[p * 4 + 2]) / 3;
    await new Promise(r => setTimeout(r));
    for (let [x0, y0, w, h] of frontCandidates(lum, cw, ch)) {
      const rx = x0 + cell.col * cw, ry = y0 + cell.row * ch;
      if (y0 > 0) {
        // what is under the floor stands in front of it: the cut starts below the walk, never over it
        const floor = Math.min(...COMP.reach.surfaces.filter(([sx, sy, sw]) => sx < rx + w && rx < sx + sw && sy < ry + h && sy > ry - 60).map(([, sy]) => sy));
        if (Number.isFinite(floor)) { const top = Math.max(ry, floor + 40); h -= top - ry; y0 += top - ry; }
        if (h < 30) continue;
      }
      out.push({ cell, crop: [x0, y0, w, h], box: [rx, y0 + cell.row * ch, w, h] });
    }
  }
  COMP.frontCands = out;
  if (!out.length) toast('Тёмных масс по краям картин не нашлось — протяни рамку инструментом «+ Передний план»');
  renderComposer(); compDraw();
}
// A picture of her own in front (a transparent PNG): kept whole, keyed by its own alpha.
async function compFrontUpload(file) {
  const im = await loadImage(URL.createObjectURL(file));
  let stem = 'pieces/' + slug(file.name.replace(/\.[^.]+$/, ''));
  while (COMP.uploads[stem]) stem += '_2';
  const c = mk(im.naturalWidth, im.naturalHeight); c.getContext('2d').drawImage(im, 0, 0);
  COMP.uploads[stem] = await canvasBlob(c); COMP.images.delete(stem);
  const [cx, cy] = compCam(), [vw, vh] = COMP_VIEW, d = 1.3, w = im.naturalWidth, h = im.naturalHeight;
  const piece = { from: stem, crop: [0, 0, w, h], at: [Math.round(cx - w * d / 2), Math.round(cy + vh / 2 - h * d)], depth: d, dark: 0.3, key: 'alpha' };
  compEdit(e => { compOwnLayers(e); e.front.push(piece); });
  COMP.sel = { k: 'front', i: COMP.entry.front.length - 1 }; COMP.view = 'depth'; renderComposer(); compDraw();
}

/* ---------- the tracer: ledges offered from the pictures, picked by hand ---------- */
async function compTrace() {
  const [cw, ch] = compCell(), out = [];
  $('#compVerdict').textContent = 'ищу уступы…';
  for (const cell of COMP.entry.cells) {
    const im = compImage(cell.painting);
    if (!im.complete) await new Promise(r => { im.addEventListener('load', r, { once: true }); im.addEventListener('error', r, { once: true }); });
    const c = mk(cw, ch), x = c.getContext('2d', { willReadFrequently: true }); x.drawImage(im, 0, 0, cw, ch);
    let px; try { px = x.getImageData(0, 0, cw, ch).data; } catch { toast('Картину нельзя прочитать (CORS)', 'err'); continue; }
    const lum = new Uint8Array(cw * ch);
    for (let p = 0; p < cw * ch; p++) lum[p] = Math.floor((px[p * 4] * 299 + px[p * 4 + 1] * 587 + px[p * 4 + 2] * 114) / 1000);
    await new Promise(r => setTimeout(r));
    for (const [lx, ly, lw] of traceLedges(lum, cw, ch)) out.push([lx + cell.col * cw, ly + cell.row * ch, lw]);
  }
  // what is already a surface is not offered again
  const have = COMP.reach.surfaces;
  COMP.candidates = out.filter(([x, y, w]) => !have.some(([sx, sy, sw]) => Math.abs(sy - y) <= 6 && x < sx + sw && sx < x + w));
  renderComposer(); compDraw();
}

/* ---------- sending ---------- */
async function composerFiles() {
  const fatal = COMP.reach.problems.filter(p => p.fatal);
  if (COMP.entry.live && fatal.length) throw new Error('Комната в игре должна быть проходимой:\n' + fatal.map(p => p.text).join('\n'));
  const doc = JSON.parse((await repoText('tools/rooms/composed_rooms.json')) || '{}');
  const entry = structuredClone(COMP.entry);
  for (const k of COMPOSE_LISTS) if (!entry[k].length && k !== 'ground' && k !== 'ledges') delete entry[k];
  // the layers are written only once she made them hers; an empty front says nothing
  for (const k of Object.keys(COMP_LAYERS)) if (entry[k] == null || (k === 'front' && !entry[k].length)) delete entry[k];
  doc[COMP.name] = entry;
  const files = { 'tools/rooms/composed_rooms.json': fmtComposed(doc) };
  for (const cell of entry.cells) if (COMP.uploads[cell.painting]) files[`assets/levels/${cell.painting}.png`] = COMP.uploads[cell.painting];
  for (const piece of entry.front || []) if (COMP.uploads[piece.from]) files[`assets/levels/${piece.from}.png`] = COMP.uploads[piece.from];
  const { cols, rows } = composeGrid(entry, compCell());
  return { files, title: `Studio: composed room — ${COMP.name} (${cols}×${rows})`,
    body: `The room composer («Конструктор»): ${COMP.name} from ${entry.cells.length} paintings, ${cols}×${rows} cells. ${entry.live ? 'Live: it replaces the room.' : 'A draft: `room=' + COMP.name + ' --composed`.'}`,
    notes: fatal.length ? ['Путь героя пока не сходится: ' + fatal.map(p => p.text).join('; ')] : [] };
}

async function composerEnter() {
  if (!COMP.data) {
    try { COMP.data = await (await fetch('import/composer.json', { cache: 'no-store' })).json(); }
    catch (e) { $('#compBody').innerHTML = `<div class="warn">Нет данных (import/composer.json): ${esc(e.message)}</div>`; return; }
    $('#compRooms').innerHTML = Object.keys(COMP.data.rooms).map(n => `<option value="${esc(n)}">${esc(n)}${COMP.data.composed[n] ? ' ●' : ''}</option>`).join('');
    let last = ''; try { last = localStorage.getItem('ss_composer_room') || ''; } catch {}
    compOpen(COMP.data.rooms[last] ? last : Object.keys(COMP.data.composed)[0] || Object.keys(COMP.data.rooms)[0]);
  } else { compFit(); renderComposer(); compDraw(); }
}
function composerInit() {
  if (!$('#compLayout')) return;
  const c = $('#compCanvas');
  c.addEventListener('pointerdown', compDown); c.addEventListener('pointermove', compMove);
  c.addEventListener('pointerup', compUp); c.addEventListener('pointercancel', compUp);
  c.addEventListener('wheel', compWheel, { passive: false }); c.addEventListener('contextmenu', e => e.preventDefault());
  addEventListener('resize', () => { if (mode === 'comp' && COMP.entry) { compFit(); compDraw(); } });
  $('#compRooms').addEventListener('change', e => { try { localStorage.setItem('ss_composer_room', e.target.value); } catch {} compOpen(e.target.value); });
  $('#compSide').addEventListener('change', e => {
    const el = e.target, s = COMP.sel;
    if (el.id === 'compLive') return compEdit(en => { en.live = el.checked; });
    if (!s) return;
    if (el.dataset.compl !== undefined) return compEdit(en => {
      compOwnLayers(en);
      const f = el.dataset.compl, v = en[s.k][s.i];
      const val = el.type === 'checkbox' ? el.checked : el.type === 'number' ? +el.value : el.value;
      if (s.k === 'lights') v[+f] = val;
      else if (val === false && f !== 'sky') delete v[f];
      else v[f] = val;
      if (s.k === 'front' && f === 'depth') v.depth = Math.min(COMP.data.front.depth[1], Math.max(COMP.data.front.depth[0], val));
      if (s.k === 'windows' && f === 'depth') v.depth = Math.min(COMP.data.window_depth[1], Math.max(COMP.data.window_depth[0], val));
      if (s.k === 'front' && f === 'key' && val === 'alpha') delete v.cut;
    });
    if (el.dataset.compv !== undefined) return compEdit(en => { const v = s.k === 'player' || s.k === 'door' ? en[s.k] : en[s.k][s.i]; v[+el.dataset.compv] = Math.round(+el.value); });
    if (el.dataset.compid !== undefined) { (COMP.lastId ??= {})[s.k] = el.value; return compEdit(en => { en[s.k][s.i][0] = el.value; }); }
    if (el.dataset.compsurf !== undefined) return compEdit(en => { const v = en[s.k][s.i]; v.length = 3; if (el.value !== 'stone') v.push(el.value); });
    if (el.dataset.compkind !== undefined) return compEdit(en => {
      const [r] = en[s.k].splice(s.i, 1), rect = compRect(s.k, r);
      en[el.value].push(compUnrect(el.value, s.k === COMP_CRUMBLE ? [rect[0], rect[1], rect[2], COMP_THICK[el.value]] : rect));
      COMP.sel = { k: el.value, i: en[el.value].length - 1 };
    });
  });
  document.addEventListener('keydown', e => {
    if (mode !== 'comp' || /INPUT|SELECT|TEXTAREA/.test(document.activeElement?.tagName || '') || document.getElementById('dlg')?.open) return;
    if (e.code === 'Space') { COMP.space = true; e.preventDefault(); }
    if ((e.key === 'Delete' || e.key === 'Backspace') && COMP.sel && COMP.sel.k !== 'player' && COMP.sel.k !== 'door') { e.preventDefault(); compDelete(); }
    if (e.key === 'Escape') { COMP.tool = 'select'; COMP.sel = null; COMP.frontCands = []; renderComposer(); compDraw(); }
  });
  document.addEventListener('keyup', e => { if (e.code === 'Space') COMP.space = false; });
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act^="comp-"], [data-comptool], [data-compview]'); if (!b || !COMP.entry) return;
    if (b.dataset.compview) { COMP.view = b.dataset.compview; COMP.sel = null; renderComposer(); return compDraw(); }
    if (b.dataset.comptool) {
      COMP.tool = b.dataset.comptool;
      // the layers live in the volume view, the walk in the flat ones
      if (COMP_LAYERS[COMP.tool]) COMP.view = 'depth'; else if (COMP.tool !== 'select' && COMP.view === 'depth') COMP.view = 'stitched';
      renderComposer(); return compDraw();
    }
    const act = b.dataset.act, c0 = +b.dataset.c, r0 = +b.dataset.r;
    if (act === 'comp-add') return compSetCell(c0, r0);
    if (act === 'comp-cell') { COMP.cell = { col: c0, row: r0 }; return renderComposer(); }
    if (act === 'comp-replace' && COMP.cell) return compSetCell(COMP.cell.col, COMP.cell.row);
    if (act === 'comp-remove' && COMP.cell) return compRemoveCell(COMP.cell.col, COMP.cell.row);
    if (act === 'comp-del' && COMP.sel) return compDelete();
    if (act === 'comp-findfront') return compFindFront();
    if (act === 'comp-frontfile') {
      const inp = document.createElement('input'); inp.type = 'file'; inp.accept = 'image/png';
      inp.onchange = () => inp.files[0] && compFrontUpload(inp.files[0]).catch(err => toast(err.message, 'err'));
      return inp.click();
    }
    if (act === 'comp-layers-reset') {
      if (!confirm('Вернуть окна и свечи, какие дают комнаты клеток, и убрать весь передний план?')) return;
      COMP.sel = null; return compEdit(en => { delete en.windows; delete en.lights; delete en.front; });
    }
    if (act === 'comp-check') return checkInGodot(COMP.name);
    if (act === 'comp-trace') return compTrace();
    if (act === 'comp-untrace') { COMP.candidates = []; renderComposer(); return compDraw(); }
    if (act === 'comp-fit') { compFit(); return compDraw(); }
    if (act === 'comp-revert') {
      if (!confirm('Выбросить правки этой комнаты и вернуть то, что в игре?')) return;
      const kept = compStored(); delete kept[COMP.name]; try { localStorage.setItem('ss_composer', JSON.stringify(kept)); } catch {}
      return compOpen(COMP.name);
    }
    if (act === 'comp-run') {
      if (Writer.mode !== 'local') return dialog(`<h3>Сыграть собранную комнату</h3><p>Отправь её кнопкой «→ В игру»: робот соберёт сцену в pull request, и в «Мои отправки» появится ссылка «▶ Играть с моими правками» — браузерная сборка откроет именно этот черновик (<code>room=${esc(COMP.name)} --composed</code>).</p><p class="muted">Из папки игры (<code>python3 tools/studio/serve.py</code>) эта кнопка открывает Godot сразу.</p>`);
      return runInGodot(COMP.name, !COMP.entry.live);
    }
    if (act === 'comp-send') {
      await sendToGame(composerFiles, null);
      if (sendToGame.last?.local || sendToGame.last?.url) {
        COMP.dirty = false; COMP.data.composed[COMP.name] = structuredClone(COMP.entry);
        const kept = compStored(); delete kept[COMP.name]; try { localStorage.setItem('ss_composer', JSON.stringify(kept)); } catch {}
        renderComposer();
      }
    }
  });
}
if (typeof document !== 'undefined') composerInit();
