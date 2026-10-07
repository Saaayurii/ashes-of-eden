/* Sprite Studio — the seams of a widened room painting (tools/rooms/generate_rooms.py
 * _expand_panel). Each band the generator inserts is quilted from the painting either side
 * of its cut, so whatever stands near a cut stands there twice. Here she sees the bands,
 * busiest first, takes one out for ChatGPT with the room's floors drawn on it, and pastes
 * the repaint back: only the band changes (feathered into its sides), and it goes into the
 * game as an override of the wide painting (repo.js convertToOverrides). */
'use strict';

const SEAMS = { data: null, res: null, patches: new Map() };   // patches: band x -> canvas of the band, repainted
const SEAM_SIDE = 80, SEAM_FEATHER = 10;

async function seamsLoad() { if (!SEAMS.data) SEAMS.data = await (await fetch('import/seams.json')).json().catch(() => ({})); return SEAMS.data; }
const seamsOf = res => SEAMS.data?.[res] || null;

async function seamsDialog(res) {
  await seamsLoad();
  const s = seamsOf(res); if (!s) return;
  if (SEAMS.res !== res) { SEAMS.res = res; SEAMS.patches.clear(); }
  SEAMS.room = await loadRoom(s.room);
  SEAMS.pic = await loadImage(A(res.replace('res://', '')));
  dialog('<div id="seamsBox"></div>', [['Закрыть']]);
  const d = $('#dlg'); d.classList.add('wide'); d.addEventListener('close', () => d.classList.remove('wide'), { once: true });
  renderSeams();
}
// the band with SEAM_SIDE of painting either side, as the generator left it or with her patch
function seamCrop(b, patched = true) {
  const s = seamsOf(SEAMS.res), x0 = Math.max(0, b.x - SEAM_SIDE), x1 = Math.min(s.w, b.x + b.w + SEAM_SIDE);
  const c = mk(x1 - x0, s.h), x = c.getContext('2d');
  x.drawImage(SEAMS.pic, x0, 0, c.width, s.h, 0, 0, c.width, s.h);
  const p = patched && SEAMS.patches.get(b.x);
  if (p) x.drawImage(p, b.x - x0 - SEAM_FEATHER, 0);
  return { c, x0 };
}
function renderSeams() {
  const box = $('#seamsBox'); if (!box) return;
  const s = seamsOf(SEAMS.res), bands = [...s.bands].sort((a, b) => b.score - a.score);
  box.innerHTML = `<h3>Швы картины · ${esc(s.room)}</h3>
    <p class="muted">Картина комнаты шире нарисованной: генератор вставил полосы по ${bands[0].w} px, сшитые из картины по обе стороны. Всё, что стоит у шва, в полосе повторяется — второе знамя, второе окно. Залатай полосу: скачай кусок, перерисуй середину в ChatGPT, вставь обратно. Меняется только полоса между фиолетовыми рисками; зелёные линии — пол, по которому ходят: он должен остаться на тех же высотах.</p>
    <div class="seamlist">${bands.map(b => `<div class="card seam">
      <div class="row" style="margin:0"><b class="grow">Шов у x ${b.x}</b><span class="muted" title="Сколько мелких деталей в полосе против картины в целом: чем больше, тем заметнее повтор">заметность ${b.score.toFixed(2)}</span></div>
      <canvas data-seam="${b.x}" class="seamcv"></canvas>
      <div class="row" style="margin:0;flex-wrap:wrap">
        <button class="sm" data-act="seam-get" data-x="${b.x}">⬇ Кусок</button><button class="sm" data-act="seam-prompt" data-x="${b.x}">📋 Промпт</button>
        <label class="sm btnlike">⬆ Заплатка<input type="file" accept="image/*" data-seamfile="${b.x}" hidden></label>
        ${SEAMS.patches.has(b.x) ? `<button class="sm" data-act="seam-flip" data-x="${b.x}" title="Нажми и держи — как было">◐ Было</button><button class="sm" data-act="seam-drop" data-x="${b.x}">↺ Убрать</button>` : ''}
      </div></div>`).join('')}</div>
    <div class="row" style="margin-top:8px"><span class="grow muted">${SEAMS.patches.size ? `Заплаток: ${SEAMS.patches.size}. Уйдут правкой поверх картины генератора, робот пересоберёт комнату.` : 'Можно вставить заплатку и через Cmd/Ctrl+V — она ляжет в шов, который заметнее всех без заплатки.'}</span>
      <button class="primary" data-act="seam-send"${SEAMS.patches.size ? '' : ' disabled'}>→ В игру</button></div>`;
  for (const cv of $$('canvas[data-seam]', box)) drawSeam(cv, s.bands.find(b => b.x === +cv.dataset.seam), true);
  for (const inp of $$('input[data-seamfile]', box)) inp.addEventListener('change', e => { const f = e.target.files[0]; if (f) seamTake(+inp.dataset.seamfile, f); });
}
function drawSeam(cv, b, patched) {
  const { c, x0 } = seamCrop(b, patched), k = Math.min(1, 300 / c.height);
  cv.width = Math.round(c.width * k); cv.height = Math.round(c.height * k);
  const x = cv.getContext('2d'); x.imageSmoothingEnabled = k < 1; x.drawImage(c, 0, 0, cv.width, cv.height);
  x.fillStyle = '#e040fb'; for (const at of [b.x, b.x + b.w]) x.fillRect((at - x0) * k - 1, 0, 2, 10 * k + 4);
  x.strokeStyle = 'rgba(74,222,128,.85)'; x.lineWidth = 1;
  for (const [sx, sy, sw] of SEAMS.room?.surfaces || []) {
    const a = Math.max(sx, x0), z = Math.min(sx + sw, x0 + c.width); if (z <= a) continue;
    x.beginPath(); x.moveTo((a - x0) * k, sy * k + .5); x.lineTo((z - x0) * k, sy * k + .5); x.stroke();
  }
}
// her repaint of the crop: scaled back to it if ChatGPT changed the size, the band cut out with a feather of its sides
async function seamTake(bx, file) {
  const s = seamsOf(SEAMS.res), b = s.bands.find(q => q.x === bx); if (!b) return;
  const { c: orig, x0 } = seamCrop(b, false), im = await loadImage(await blobToDataURL(file));
  if (Math.abs(im.width / im.height - orig.width / orig.height) > 0.04) return toast(`Пропорции не те: кусок ${orig.width}×${orig.height}, а картинка ${im.width}×${im.height}. Попроси ChatGPT не обрезать и не менять размер.`, 'err');
  const fit = mk(orig.width, orig.height), fx = fit.getContext('2d'); fx.imageSmoothingQuality = 'high'; fx.drawImage(im, 0, 0, fit.width, fit.height);
  const w = b.w + SEAM_FEATHER * 2, band = mk(w, s.h), bx2 = band.getContext('2d');
  bx2.drawImage(fit, b.x - x0 - SEAM_FEATHER, 0, w, s.h, 0, 0, w, s.h);
  // fade the first and last SEAM_FEATHER columns, so the painting either side keeps its edge
  const d = bx2.getImageData(0, 0, w, s.h);
  for (let x = 0; x < SEAM_FEATHER; x++) { const a = (x + 0.5) / SEAM_FEATHER; for (let y = 0; y < s.h; y++) { d.data[(y * w + x) * 4 + 3] *= a; d.data[(y * w + (w - 1 - x)) * 4 + 3] *= a; } }
  bx2.putImageData(d, 0, 0);
  SEAMS.patches.set(bx, band); renderSeams();
}
async function seamsFiles() {
  const s = seamsOf(SEAMS.res), full = mk(s.w, s.h), x = full.getContext('2d');
  x.drawImage(SEAMS.pic, 0, 0);
  for (const [bx, band] of SEAMS.patches) x.drawImage(band, bx - SEAM_FEATHER, 0);
  const path = SEAMS.res.replace('res://', ''), at = [...SEAMS.patches.keys()].sort((a, b) => a - b);
  return { files: { [path]: await canvasBlob(full) }, title: `Studio: seams of ${s.room} repainted`,
    body: `The inserted bands at x ${at.join(', ')} of \`${path}\` repainted in the studio («🩹 Швы»): only the bands differ, so only they go into the override.`,
    notes: ['Робот студии пересоберёт комнату с заплатками в этой же отправке.'] };
}
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-act^="seam-"]'); if (!b) return;
  const act = b.dataset.act, s = SEAMS.res && seamsOf(SEAMS.res), band = s?.bands.find(q => q.x === +b.dataset.x);
  if (act === 'seam-open') return seamsDialog(b.dataset.res);
  if (act === 'seam-get' && band) return download(await canvasBlob(seamCrop(band, false).c), `${s.room}_seam_${band.x}.png`);
  if (act === 'seam-prompt' && band) {
    const { c } = seamCrop(band, false);
    const text = `This is a ${c.width}x${c.height} strip of a hand-painted pixel-art background from a dark gothic 2D platformer. ` +
      `The middle ${band.w} px (from x=${SEAM_SIDE} to x=${SEAM_SIDE + band.w}) is filler stitched from both sides, so objects repeat. ` +
      `Repaint ONLY that middle part so it continues the left and right parts naturally, with different details: no second copy of any banner, window, statue, cage, tower or gravestone that stands beside it. ` +
      `Keep every floor, ledge and walkway at exactly the same height and running straight through. Keep the left ${SEAM_SIDE} px and the right ${SEAM_SIDE} px exactly as they are. ` +
      `Same pixel scale, palette, lighting and level of detail. Output the whole strip at exactly ${c.width}x${c.height}, no border, no text.`;
    try { await navigator.clipboard.writeText(text); toast('Промпт скопирован. Приложи к нему скачанный кусок.'); } catch { dialog(`<h3>Промпт</h3><pre class="log">${esc(text)}</pre>`); }
    return;
  }
  if (act === 'seam-drop') { SEAMS.patches.delete(+b.dataset.x); return renderSeams(); }
  if (act === 'seam-send') return sendToGame(seamsFiles, 'bg');
});
// hold «◐ Было» to see the band as the generator left it
for (const [ev, patched] of [['pointerdown', false], ['pointerup', true], ['pointerleave', true]])
  document.addEventListener(ev, e => {
    const b = e.target.closest?.('[data-act="seam-flip"]'); if (!b) return;
    const cv = $(`canvas[data-seam="${b.dataset.x}"]`), band = seamsOf(SEAMS.res).bands.find(q => q.x === +b.dataset.x);
    if (cv && band) drawSeam(cv, band, patched);
  }, true);
document.addEventListener('paste', e => {
  if (!$('#seamsBox')) return;
  const f = [...(e.clipboardData?.files || [])].find(f => f.type.startsWith('image/')); if (!f) return;
  const open = [...seamsOf(SEAMS.res).bands].sort((a, b) => b.score - a.score).find(b => !SEAMS.patches.has(b.x));
  if (open) { e.preventDefault(); seamTake(open.x, f); }
});
