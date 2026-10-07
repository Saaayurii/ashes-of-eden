/* Sprite Studio — pixel touch-ups and undo / redo, for every tab. Plain scripts share one global scope; index.html loads them in order. */
'use strict';

/* ---------- pixel touch-ups (frame.patch, applied after processing; lib.js applyPatch) ---------- */
const paint = { fid: null, tool: 'pen', color: [0, 0, 0, 255], zoom: 8, down: false };
const toHex8 = c => '#' + c.slice(0, 3).map(v => v.toString(16).padStart(2, '0')).join('');
function openPaint(fid) { paint.fid = fid; $('#paintModal').hidden = false; requestAnimationFrame(() => { drawPaint(); renderPaintPal(); }); }
function closePaint() { $('#paintModal').hidden = true; save(); renderFrames(); }
function drawPaint() {
  const src = processed.get(paint.fid); if (!src || $('#paintModal').hidden) return;
  const W = src.width, H = src.height, st = $('#paintStage'), c = $('#paintCanvas');
  const k = Math.max(2, Math.floor(Math.min((st.clientWidth - 20) / W, (st.clientHeight - 20) / H)));
  paint.zoom = k; c.width = W * k; c.height = H * k;
  const x = c.getContext('2d'); x.imageSmoothingEnabled = false;
  if ($('#paintOnion').checked) {
    const { a, f } = findFrame(paint.fid), i = a.frames.indexOf(f), prev = a.frames.slice(0, i).reverse().find(q => processed.has(q.id));
    if (prev) { x.globalAlpha = 0.25; x.drawImage(processed.get(prev.id), 0, 0, W * k, H * k); x.globalAlpha = 1; }
  }
  x.drawImage(src, 0, 0, W * k, H * k);
  x.fillStyle = 'rgba(255,255,255,.06)';
  for (let i = 1; i < W; i++) x.fillRect(i * k, 0, 1, H * k);
  for (let j = 1; j < H; j++) x.fillRect(0, j * k, W * k, 1);
}
function renderPaintPal() {
  const src = processed.get(paint.fid); if (!src) return;
  const d = src.getContext('2d').getImageData(0, 0, src.width, src.height).data, count = new Map();
  for (let i = 0; i < d.length; i += 4) if (d[i + 3]) { const k = d[i] << 16 | d[i + 1] << 8 | d[i + 2]; count.set(k, (count.get(k) || 0) + 1); }
  const cols = [...(palette || []).map(p => p[0] << 16 | p[1] << 8 | p[2]), ...[...count].sort((a, b) => b[1] - a[1]).map(([k]) => k)];
  const uniq = [...new Set(cols)].slice(0, 48), cur = paint.color[0] << 16 | paint.color[1] << 8 | paint.color[2];
  $('#paintPal').innerHTML = uniq.map(k => `<i data-pc="${k}" class="${k === cur ? 'on' : ''}" style="background:#${k.toString(16).padStart(6, '0')}"></i>`).join('');
}
function setPaintColor(c) { paint.color = [c[0], c[1], c[2], 255]; $('#paintColor').value = toHex8(paint.color); renderPaintPal(); }
function setTool(t) { paint.tool = t; $$('#paintModal [data-pt]').forEach(b => b.classList.toggle('on', b.dataset.pt === t)); }
function paintAt(e) {
  const src = processed.get(paint.fid), { f } = findFrame(paint.fid); if (!src || !f) return;
  const x = Math.floor(e.offsetX / paint.zoom), y = Math.floor(e.offsetY / paint.zoom);
  if (x < 0 || y < 0 || x >= src.width || y >= src.height) return;
  const ctx = src.getContext('2d');
  if (paint.tool === 'picker' || e.altKey) { const p = ctx.getImageData(x, y, 1, 1).data; if (p[3]) setPaintColor(p); setTool('pen'); return; }
  f.patch ||= {};
  if (paint.tool === 'eraser') { f.patch[`${x},${y}`] = [0, 0, 0, 0]; ctx.clearRect(x, y, 1, 1); }
  else { f.patch[`${x},${y}`] = [...paint.color]; ctx.fillStyle = toHex8(paint.color); ctx.fillRect(x, y, 1, 1); }
  drawPaint();
}
$('#paintCanvas').addEventListener('pointerdown', e => { paint.down = true; e.currentTarget.setPointerCapture(e.pointerId); paintAt(e); });
$('#paintCanvas').addEventListener('pointermove', e => { if (paint.down && paint.tool !== 'picker') paintAt(e); });
$('#paintCanvas').addEventListener('pointerup', () => { if (paint.down) { paint.down = false; save(); } });
document.addEventListener('click', e => {
  const t = e.target.closest('[data-pt],[data-pc],[data-act="f-paint"],[data-act="paint-close"],[data-act="paint-clear"]'); if (!t) return;
  if (t.dataset.pt) setTool(t.dataset.pt);
  else if (t.dataset.pc) { const k = +t.dataset.pc; setPaintColor([k >> 16 & 255, k >> 8 & 255, k & 255]); }
  else if (t.dataset.act === 'f-paint') openPaint(t.closest('[data-fid]').dataset.fid);
  else if (t.dataset.act === 'paint-close') closePaint();
  else if (t.dataset.act === 'paint-clear') { const { f } = findFrame(paint.fid); if (f && confirm('Стереть все ручные правки этого кадра?')) { f.patch = {}; save(); build().then(drawPaint); } }
});
document.addEventListener('input', e => { if (e.target.id === 'paintColor') { const h = e.target.value; setPaintColor([1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16))); } if (e.target.id === 'paintOnion') drawPaint(); });
document.addEventListener('keydown', e => {
  if ($('#paintModal').hidden || e.target.closest?.('input,textarea,select')) return;
  const k = e.key.toLowerCase();
  if (k === 'escape') closePaint(); else if (k === 'b') setTool('pen'); else if (k === 'e') setTool('eraser'); else if (k === 'i') setTool('picker');
});
window.addEventListener('resize', drawPaint);

/* ---------- undo / redo (per tab; pictures are shared between snapshots, see lib.js) ---------- */
const undoTable = { ids: new Map(), list: [] };
const history = { chars: { u: [], r: [] }, bg: { u: [], r: [] }, cut: { u: [], r: [] }, snd: { u: [], r: [] } };
const undoTarget = m => m === 'chars' ? P : m === 'bg' ? BG : m === 'cut' ? CUT
  : m === 'snd' ? { id: 'snd', mods: [...sndMods.values()].sort((a, b) => a.id.localeCompare(b.id)) } : null;
function trackChange(m) {
  const h = history[m], o = undoTarget(m); if (!h || !o) return;
  const snap = snapshot(o, undoTable);
  if (h.id !== o.id) { Object.assign(h, { id: o.id, u: [], r: [], last: snap, t: 0 }); return; }
  if (snap === h.last) return;
  const now = Date.now();
  if (now - h.t > 700) { h.u.push(h.last); if (h.u.length > 80) h.u.shift(); }  // a burst of typing is one step
  h.r = []; h.last = snap; h.t = now;
}
function undoRedo(redo) {
  const h = history[mode];
  if (!h) return toast('Здесь отмена не работает', 'err');
  const from = redo ? h.r : h.u; if (!from.length) return toast(redo ? 'Нечего возвращать' : 'Нечего отменять');
  (redo ? h.u : h.r).push(h.last); h.last = from.pop(); h.t = 0;
  const obj = unsnapshot(h.last, undoTable);
  // what is restored is the new baseline, so re-rendering does not count as a change
  const settle = o => { h.last = snapshot(o, undoTable); return o; };
  if (mode === 'chars') { const i = projects.indexOf(P); P = settle(migrate(obj)); if (i >= 0) projects[i] = P; persist(); renderAll(); scheduleBuild(0); }
  else if (mode === 'bg') { const i = bgs.indexOf(BG); BG = settle(migrateBg(obj)); if (i >= 0) bgs[i] = BG; persistBg(); renderBgAll(); }
  else if (mode === 'snd') {
    settle(obj);
    const keep = new Set(obj.mods.map(m => m.id));
    for (const id of sndMods.keys()) if (!keep.has(id)) { sndMods.delete(id); if (dbOk) DB.del(id, 'sounds').catch(() => {}); }
    for (const m of obj.mods) { sndMods.set(m.id, m); if (dbOk) DB.put(m, 'sounds').catch(() => {}); }
    renderSndList(); renderSndMain();
  }
  else { const i = cuts.indexOf(CUT); CUT = settle(migrateCut(obj)); if (i >= 0) cuts[i] = CUT; if (dbOk) DB.put(CUT, 'cutscenes').catch(() => {}); renderCutAll(); }
  toast(redo ? 'Возвращено' : 'Отменено');
}
document.addEventListener('keydown', e => {
  if (!(e.metaKey || e.ctrlKey) || e.key.toLowerCase() !== 'z' && e.key.toLowerCase() !== 'я') return;
  if (e.target.closest?.('input,textarea,select')) return;  // text fields keep their own undo
  e.preventDefault(); undoRedo(e.shiftKey);
});
document.addEventListener('click', e => { const b = e.target.closest('[data-act="undo"],[data-act="redo"]'); if (b) undoRedo(b.dataset.act === 'redo'); });
