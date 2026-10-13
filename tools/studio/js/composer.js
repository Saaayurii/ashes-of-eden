/* Sprite Studio — the room composer, «Конструктор» (tools/rooms/compose.py, docs/ROOM_COMPOSER.md).
 * One painted room is one 1280×720 picture: as big as an image model draws. Here a room becomes a grid
 * of such pictures — two in a row, two by two, an L — and the generator stitches the seams. What the
 * hero walks on is drawn over the grid: a room's own ledges come along with its panel, the tracer
 * (lib.js traceLedges, a port of tools/rooms/trace_panel.py) offers more from the picture, and every
 * rectangle, ramp and thing can be dragged, stretched, added and taken away by hand. The route is
 * checked as it changes (lib.js composeReach = painted_rooms.check_reach). A draft opens in Godot
 * with `room=<name> --composed`; ticked «В игре», it replaces the room. */
'use strict';

const COMP_RECTS = { ground: ['Земля', '#6fae5a'], ledges: ['Уступ', '#e0b54a'], platforms: ['Платформа', '#5fb3d9'], hazards: ['Опасность', '#e0503c'] };
const COMP_THINGS = { spawns: ['Враг', '#ff6b6b'], props: ['Предмет', '#c9a0ff'], npcs: ['Человек', '#7fe0c0'] };
const COMP_THICK = { ground: 120, ledges: 14, platforms: 10, hazards: 40 };
const COMP = { data: null, name: '', entry: null, sel: null, tool: 'select', cell: null, scale: 0.5, ox: 20, oy: 20,
  images: new Map(), uploads: {}, candidates: [], reach: null, undo: [], redo: [], drag: null, dirty: false, raf: 0 };

const compCell = () => COMP.data.cell;
const compSize = () => composeGrid(COMP.entry, compCell());
function compImage(stem) {
  if (COMP.images.has(stem)) return COMP.images.get(stem);
  const im = new Image(); im.onload = () => compDraw(); im.src = COMP.uploads[stem] ? URL.createObjectURL(COMP.uploads[stem]) : A(`assets/levels/${stem}.png`);
  COMP.images.set(stem, im); return im;
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
    for (const k of Object.keys(COMP_RECTS)) e[k] = e[k].filter(([x, y, w, h]) => !(inside(x, y) && inside(x + w - 1, y + h - 1)));
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
    const name = s.k === 'player' ? 'Вход' : s.k === 'door' ? 'Дверь' : (COMP_RECTS[s.k] || COMP_THINGS[s.k] || ['Наклон'])[0];
    const num = (i, label) => `<label>${label}<input type="number" data-compv="${i}" value="${Math.round(v[i])}"></label>`;
    const fields = s.k === 'ramps' ? [num(0, 'x₀'), num(1, 'y₀'), num(2, 'x₁'), num(3, 'y₁')]
      : COMP_RECTS[s.k] ? [num(0, 'x'), num(1, 'y'), num(2, 'ширина'), num(3, 'высота')]
      : COMP_THINGS[s.k] ? [`<label>Кто<select data-compid>${COMP.data[s.k === 'spawns' ? 'enemies' : s.k].map(id => `<option${id === v[0] ? ' selected' : ''}>${esc(id)}</option>`).join('')}</select></label>`, num(1, 'x'), num(2, 'y')]
      : [num(0, 'x'), num(1, 'y')];
    const kinds = COMP_RECTS[s.k] ? `<label>Это<select data-compkind>${Object.entries(COMP_RECTS).map(([k, [l]]) => `<option value="${k}"${k === s.k ? ' selected' : ''}>${l}</option>`).join('')}</select></label>` : '';
    selHtml = `<div class="row"><b>${name}</b><span class="grow"></span>${s.k !== 'player' && s.k !== 'door' ? '<button class="sm danger" data-act="comp-del" title="Убрать (Delete)">✕ Убрать</button>' : ''}</div>
      <div class="compfields">${kinds}${fields.join('')}</div>`;
  }
  const fatal = r.problems.filter(p => p.fatal), soft = r.problems.filter(p => !p.fatal);
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
    <div class="card"><label title="Пока выключено, это черновик: scenes/rooms/composed/${esc(COMP.name)}.tscn, открывается кнопкой «▶ В Godot». Включено — комната в игре заменяется собранной, и путь героя обязан сходиться."><input type="checkbox" id="compLive"${e.live ? ' checked' : ''}> В игре вместо комнаты ${esc(COMP.name)}</label>
      ${e.live ? '<div class="warn">Собранная комната заменит настоящую. Проверь её в Godot до отправки.</div>' : '<div class="muted">Черновик: игра идёт по старой комнате.</div>'}
    </div>`;
  const send = $('#compSend'); send.textContent = COMP.dirty ? '→ В игру •' : '→ В игру';
  send.disabled = !COMP.dirty;
  $$('[data-comptool]').forEach(b => b.classList.toggle('on', b.dataset.comptool === COMP.tool));
  $('#compVerdict').textContent = COMP.candidates.length ? `найдено уступов: ${COMP.candidates.length} — щёлкни жёлтый, чтобы взять` : '';
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
  for (const cell of e.cells) { const im = compImage(cell.painting); if (im.complete && im.naturalWidth) x.drawImage(im, cell.col * cw, cell.row * ch, cw, ch); }
  x.lineWidth = 1 / S;
  x.strokeStyle = '#ffffff40'; x.setLineDash([8 / S, 6 / S]);
  for (let gx = cw; gx < width; gx += cw) { x.beginPath(); x.moveTo(gx, 0); x.lineTo(gx, height); x.stroke(); }
  for (let gy = ch; gy < height; gy += ch) { x.beginPath(); x.moveTo(0, gy); x.lineTo(width, gy); x.stroke(); }
  x.setLineDash([]);
  // what the route reaches: a surface off it is grey
  const surf = COMP.reach.surfaces, idx = new Map(); let n = 0;
  for (const k of ['ground', 'ledges', 'platforms']) e[k].forEach((_, i) => idx.set(k + i, n++));
  for (const [k, [, col]] of Object.entries(COMP_RECTS)) e[k].forEach((r, i) => {
    const on = COMP.sel && COMP.sel.k === k && COMP.sel.i === i, lost = idx.has(k + i) && !COMP.reach.seen.has(idx.get(k + i));
    x.fillStyle = (lost ? '#888888' : col) + (k === 'hazards' ? '44' : '55'); x.fillRect(r[0], r[1], r[2], r[3]);
    x.strokeStyle = on ? '#fff' : lost ? '#999' : col; x.lineWidth = (on ? 2.5 : 1.5) / S; x.strokeRect(r[0], r[1], r[2], r[3]);
    if (k !== 'hazards') { x.fillStyle = lost ? '#aaa' : col; x.fillRect(r[0], r[1] - 1 / S, r[2], 3 / S); }
    if (on) for (const [hx, hy] of [[r[0], r[1] + r[3] / 2], [r[0] + r[2], r[1] + r[3] / 2], [r[0] + r[2], r[1] + r[3]]]) { x.fillStyle = '#fff'; x.fillRect(hx - 4 / S, hy - 4 / S, 8 / S, 8 / S); }
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
  if (COMP.drag?.box) { const b = COMP.drag.box; x.strokeStyle = '#fff'; x.setLineDash([4 / S, 4 / S]); x.lineWidth = 1.5 / S; x.strokeRect(b[0], b[1], b[2], b[3]); x.setLineDash([]); }
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
  for (const k of ['hazards', 'platforms', 'ledges', 'ground']) for (let i = e[k].length - 1; i >= 0; i--) {
    const [x, y, w, h] = e[k][i];
    if (COMP.sel?.k === k && COMP.sel.i === i) {
      // the handles never cover more than a quarter of it: the middle always moves it
      const grip = Math.min(near, w / 4), gy = Math.min(near, h / 2);
      if (Math.abs(rx - (x + w)) < grip && Math.abs(ry - (y + h)) < gy) return { k, i, part: 'corner' };
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
  const d = COMP.drag; if (!d) return;
  const [px, py] = compPointer(ev);
  if (d.pan) { COMP.ox = d.ox + px - d.px; COMP.oy = d.oy + py - d.py; return compDraw(); }
  const [rx, ry] = compToRoom(px, py), dx = Math.round(rx - d.rx), dy = Math.round(ry - d.ry);
  if (d.make) { d.ex = rx; d.ey = ry; d.box = [Math.min(d.rx, rx), Math.min(d.ry, ry), Math.abs(rx - d.rx), Math.abs(ry - d.ry)]; return compDraw(); }
  if (!d.hit) return;
  const { k, i, part } = d.hit, w = d.was, e = COMP.entry;
  d.moved = true;
  if (k === 'player' || k === 'door') e[k] = [w[0] + dx, w[1] + dy];
  else if (COMP_THINGS[k]) e[k][i] = [w[0], w[1] + dx, w[2] + dy];
  else if (k === 'ramps') e[k][i] = part === 'a' ? [w[0] + dx, w[1] + dy, w[2], w[3]] : part === 'b' ? [w[0], w[1], w[2] + dx, w[3] + dy] : [w[0] + dx, w[1] + dy, w[2] + dx, w[3] + dy];
  else e[k][i] = part === 'move' ? [w[0] + dx, w[1] + dy, w[2], w[3]] : part === 'right' ? [w[0], w[1], Math.max(4, w[2] + dx), w[3]]
    : part === 'left' ? [Math.min(w[0] + dx, w[0] + w[2] - 4), w[1], Math.max(4, w[2] - dx), w[3]] : [w[0], w[1], Math.max(4, w[2] + dx), Math.max(2, w[3] + dy)];
  COMP.reach = composeReach(e, COMP.data.reach); compDraw();
}
function compUp() {
  const d = COMP.drag; COMP.drag = null; if (!d) return;
  if (d.make) {
    const [x, y, w, h] = d.box.map(Math.round), tool = d.make;
    if (w < 6 && h < 6) return compDraw();
    compEdit(e => {
      if (tool === 'ramps') e.ramps.push([d.rx, d.ry, d.ex, d.ey].map(Math.round));
      else e[tool].push([x, y, Math.max(4, w), Math.max(2, tool === 'hazards' || h > 6 ? h : COMP_THICK[tool])]);
    });
    COMP.sel = { k: tool, i: COMP.entry[tool].length - 1 }; COMP.tool = 'select'; return renderComposer();
  }
  if (d.moved) {
    // the step to undo is the whole drag, not every pixel of it
    COMP.undo.push(d.start); COMP.redo = []; compClamp(); compChanged(true);
  }
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
  doc[COMP.name] = entry;
  const files = { 'tools/rooms/composed_rooms.json': fmtComposed(doc) };
  for (const cell of entry.cells) if (COMP.uploads[cell.painting]) files[`assets/levels/${cell.painting}.png`] = COMP.uploads[cell.painting];
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
    if (el.dataset.compv !== undefined) return compEdit(en => { const v = s.k === 'player' || s.k === 'door' ? en[s.k] : en[s.k][s.i]; v[+el.dataset.compv] = Math.round(+el.value); });
    if (el.dataset.compid !== undefined) { (COMP.lastId ??= {})[s.k] = el.value; return compEdit(en => { en[s.k][s.i][0] = el.value; }); }
    if (el.dataset.compkind !== undefined) return compEdit(en => { const [r] = en[s.k].splice(s.i, 1); en[el.value].push(r); COMP.sel = { k: el.value, i: en[el.value].length - 1 }; });
  });
  document.addEventListener('keydown', e => {
    if (mode !== 'comp' || /INPUT|SELECT|TEXTAREA/.test(document.activeElement?.tagName || '') || document.getElementById('dlg')?.open) return;
    if (e.code === 'Space') { COMP.space = true; e.preventDefault(); }
    if ((e.key === 'Delete' || e.key === 'Backspace') && COMP.sel && COMP.sel.k !== 'player' && COMP.sel.k !== 'door') { e.preventDefault(); const s = COMP.sel; COMP.sel = null; compEdit(en => en[s.k].splice(s.i, 1)); }
    if (e.key === 'Escape') { COMP.tool = 'select'; COMP.sel = null; renderComposer(); compDraw(); }
  });
  document.addEventListener('keyup', e => { if (e.code === 'Space') COMP.space = false; });
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act^="comp-"], [data-comptool]'); if (!b || !COMP.entry) return;
    if (b.dataset.comptool) { COMP.tool = b.dataset.comptool; return renderComposer(); }
    const act = b.dataset.act, c0 = +b.dataset.c, r0 = +b.dataset.r;
    if (act === 'comp-add') return compSetCell(c0, r0);
    if (act === 'comp-cell') { COMP.cell = { col: c0, row: r0 }; return renderComposer(); }
    if (act === 'comp-replace' && COMP.cell) return compSetCell(COMP.cell.col, COMP.cell.row);
    if (act === 'comp-remove' && COMP.cell) return compRemoveCell(COMP.cell.col, COMP.cell.row);
    if (act === 'comp-del' && COMP.sel) { const s = COMP.sel; COMP.sel = null; return compEdit(en => en[s.k].splice(s.i, 1)); }
    if (act === 'comp-trace') return compTrace();
    if (act === 'comp-untrace') { COMP.candidates = []; renderComposer(); return compDraw(); }
    if (act === 'comp-fit') { compFit(); return compDraw(); }
    if (act === 'comp-revert') {
      if (!confirm('Выбросить правки этой комнаты и вернуть то, что в игре?')) return;
      const kept = compStored(); delete kept[COMP.name]; try { localStorage.setItem('ss_composer', JSON.stringify(kept)); } catch {}
      return compOpen(COMP.name);
    }
    if (act === 'comp-run') return runInGodot(COMP.name, !COMP.entry.live);
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
