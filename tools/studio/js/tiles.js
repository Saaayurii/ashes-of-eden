/* Sprite Studio — platform pieces (assets/decor/platforms): the blocks the room generator
 * (tools/rooms/generate_rooms.py terrain_nodes) lays over floors, ledges and room edges.
 * A piece redrawn at the same size goes straight into the game: the scenes name the file,
 * the manifest keeps its size and the row its walkable top starts on. */
'use strict';

const TILES = { data: null, fam: 'ground', sel: null, mine: new Map() };   // mine: name -> dataURL of her piece
const TILE_FAMILY = {
  ground: ['Земля', 'широкие блоки земли с травой — пол, кладутся вплотную'],
  cap: ['Обрыв', 'обломанный край земли у ямы (для левого края зеркалится)'],
  earth: ['Глыба', 'квадратные блоки земли с травой — толстые уступы'],
  ledge: ['Полка', 'каменные полки со свисающим мхом — тонкие платформы'],
  float: ['Островок', 'маленькие мшистые куски с корнями — крошечные платформы'],
  wall: ['Стена', 'мшистые сегменты стены — края комнаты'],
  pillar: ['Колонна', 'колонны и постаменты — декор'],
  rock: ['Камни', 'низкие ступени и щебень — декор'],
};
const TILE_PROMPT = {
  ground: 'a wide block of dark earth with a ruined stone course and a strip of short dark-green grass on top',
  cap: 'the broken-off right end of a grassy earth block, a jagged crumbling edge falling into a pit',
  earth: 'a squarish block of dark earth and stone with short grass on top',
  ledge: 'a thin carved stone shelf with an arched underside and moss hanging below it',
  float: 'a small chunk of mossy stone with a ball of roots hanging under it',
  wall: 'a tall segment of mossy ruined stone wall, bricks about 10 px high',
  pillar: 'a free-standing ruined stone column on a small base',
  rock: 'a low pile of broken stone steps and rubble',
};

async function tilesLoad() {
  if (TILES.data) return;
  TILES.data = await (await fetch('import/tiles.json')).json();
  try { for (const [k, v] of Object.entries(JSON.parse(localStorage.getItem('ss_tiles') || '{}'))) TILES.mine.set(k, v); } catch {}
}
const tilePiece = name => TILES.data.pieces.find(p => p.name === name);
const tileSrc = p => TILES.mine.get(p.name) || A(p.url);
function tilesSave() { try { localStorage.setItem('ss_tiles', JSON.stringify(Object.fromEntries(TILES.mine))); } catch (e) { toast('Не поместилось в память браузера: ' + e.message, 'err'); } }

async function tilesDialog() {
  try { await tilesLoad(); } catch (e) { return dialog(`<h3>Плитки</h3><p>Нет данных о плитках (import/tiles.json): ${esc(e.message)}</p>`); }
  dialog('<div id="tilesBox" class="tilesbox"></div>', [['Закрыть']]);
  const d = $('#dlg'); d.classList.add('wide'); d.addEventListener('close', () => d.classList.remove('wide'), { once: true });
  renderTiles();
}
function renderTiles() {
  const box = $('#tilesBox'); if (!box) return;
  const played = new Set(TILES.data.played), fams = Object.keys(TILE_FAMILY).filter(f => TILES.data.pieces.some(p => p.family === f));
  const list = TILES.data.pieces.filter(p => p.family === TILES.fam);
  const where = p => { const r = Object.entries(p.uses), live = r.filter(([room]) => played.has(room));
    return live.length ? live.map(([room, n]) => `${room} ×${n}`).join(', ') : r.length ? 'только в старых комнатах' : 'пока нигде'; };
  const p = TILES.sel && tilePiece(TILES.sel);
  box.innerHTML = `<h3>Плитки комнат</h3>
    <p class="muted">Из этих кусков генератор комнат складывает пол, полки и края там, где их не нарисовала картина: тренировочный двор, пол церкви и нефа, ступени. Перерисуй кусок того же размера — он сразу встанет во все комнаты.</p>
    <div class="modes" style="margin:6px 0">${fams.map(f => `<button data-act="tiles-fam" data-f="${f}" class="${f === TILES.fam ? 'on' : ''}">${TILE_FAMILY[f][0]}</button>`).join('')}</div>
    <div class="muted">${esc(TILE_FAMILY[TILES.fam][1])}</div>
    <div class="tilegrid">${list.map(q => `<button data-act="tiles-pick" data-n="${q.name}" class="checker${q.name === TILES.sel ? ' on' : ''}" title="${esc(where(q))}">
      <img src="${esc(tileSrc(q))}" style="width:${q.w * 2}px;height:${q.h * 2}px" alt=""><span>${q.name}${TILES.mine.has(q.name) ? ' <b class="badge">твоя</b>' : ''}</span></button>`).join('')}</div>
    <div class="muted" style="margin-top:6px">Так генератор кладёт этот ряд (куски внахлёст по ${TILES.data.overlap} px, каждый чуть в своём свете):</div>
    <canvas id="tilesRow" class="checker" style="width:100%;image-rendering:pixelated"></canvas>
    ${p ? `<div class="card" style="margin-top:8px"><div class="row" style="margin:0"><b class="grow">${p.name} · ${p.w}×${p.h}</b>
      <button class="sm" data-act="tiles-get">⬇ Скачать</button><button class="sm" data-act="tiles-prompt">📋 Промпт</button>
      <label class="sm btnlike">⬆ Своя картинка<input type="file" accept="image/*" id="tilesFile" hidden></label>
      ${TILES.mine.has(p.name) ? '<button class="sm" data-act="tiles-revert">↺ Как в игре</button>' : ''}</div>
      <div class="muted">Где: ${esc(where(p))}. Зелёная линия — верх, по которому ходят (${p.top} px от края): трава может торчать выше неё.</div>
      <canvas id="tilesBig" class="checker" style="image-rendering:pixelated;margin-top:6px"></canvas></div>` : '<div class="muted" style="margin-top:6px">Выбери кусок.</div>'}
    <div class="row" style="margin-top:8px"><span class="grow muted">${TILES.mine.size ? `Твоих кусков: ${TILES.mine.size}` : ''}</span><button class="primary" data-act="tiles-send"${TILES.mine.size ? '' : ' disabled'}>→ В игру${TILES.mine.size ? ` (${TILES.mine.size})` : ''}</button></div>`;
  drawTileRow(); drawTileBig();
  $('#tilesFile')?.addEventListener('change', e => { const f = e.target.files[0]; if (f) tilesTake(f); });
}
// lay() from generate_rooms.py, in the browser: no twins, overlapping by OVERLAP, a shade each
async function drawTileRow() {
  const c = $('#tilesRow'); if (!c) return;
  const pieces = TILES.data.pieces.filter(p => p.family === TILES.fam), H = Math.max(...pieces.map(p => p.h)) + 8, W = 420;
  c.width = W; c.height = H; c.style.height = H * (c.clientWidth / W) + 'px';
  const x = c.getContext('2d'), ims = await Promise.all(pieces.map(p => loadImage(tileSrc(p)).catch(() => null)));
  let at = 0, prev = -1, seed = 7;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) >>> 0) / 2 ** 32);
  while (at < W) {
    let i = Math.floor(rnd() * pieces.length); if (i === prev && pieces.length > 1) i = (i + 1) % pieces.length; prev = i;
    const p = pieces[i], im = ims[i]; if (!im) break;
    const top = H - 4 - (p.h - p.top) - p.top;   // every walkable top on one line
    x.save(); x.filter = `brightness(${0.9 + 0.1 * rnd()})`;
    if (rnd() < 0.5) { x.translate(at + p.w, 0); x.scale(-1, 1); x.drawImage(im, 0, top); } else x.drawImage(im, at, top);
    x.restore();
    at += p.w - TILES.data.overlap;
  }
}
async function drawTileBig() {
  const c = $('#tilesBig'), p = TILES.sel && tilePiece(TILES.sel); if (!c || !p) return;
  const k = 4; c.width = p.w * k; c.height = p.h * k;
  const x = c.getContext('2d'); x.imageSmoothingEnabled = false;
  const im = await loadImage(tileSrc(p)).catch(() => null); if (im) x.drawImage(im, 0, 0, p.w * k, p.h * k);
  x.fillStyle = '#4ade80'; x.fillRect(0, p.top * k, p.w * k, 1);
}
// her picture, made a piece: trimmed to what it draws, fitted to the piece's size, alpha hardened
async function tilesTake(file) {
  const p = tilePiece(TILES.sel); if (!p) return;
  const im = await loadImage(await blobToDataURL(file));
  const src = mk(im.width, im.height), sx = src.getContext('2d'); sx.drawImage(im, 0, 0);
  const d = sx.getImageData(0, 0, im.width, im.height).data;
  let x0 = im.width, y0 = im.height, x1 = -1, y1 = -1;
  for (let y = 0; y < im.height; y++) for (let x = 0; x < im.width; x++) if (d[(y * im.width + x) * 4 + 3] > 24) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  if (x1 < 0) return toast('В картинке нет ничего непрозрачного — нужен кусок на прозрачном фоне.', 'err');
  const out = mk(p.w, p.h), ox = out.getContext('2d'); ox.imageSmoothingEnabled = (x1 - x0 + 1) > p.w * 2; ox.imageSmoothingQuality = 'high';
  ox.drawImage(src, x0, y0, x1 - x0 + 1, y1 - y0 + 1, 0, 0, p.w, p.h);
  const o = ox.getImageData(0, 0, p.w, p.h);
  for (let i = 3; i < o.data.length; i += 4) o.data[i] = o.data[i] < 128 ? 0 : 255;   // slice_batch9 hardens it the same way
  ox.putImageData(o, 0, 0);
  if (x1 - x0 + 1 !== p.w || y1 - y0 + 1 !== p.h) toast(`Подогнано к ${p.w}×${p.h}: таков размер куска в игре.`);
  TILES.mine.set(p.name, out.toDataURL('image/png')); tilesSave(); renderTiles();
}
async function tilesFiles() {
  const files = {};
  for (const [name, url] of TILES.mine) files[`assets/decor/platforms/${name}.png`] = dataURLtoBlob(url);
  const names = [...TILES.mine.keys()];
  return { files, title: `Studio: platform pieces — ${names.join(', ')}`,
    body: `Redrawn at the same size in the studio («🧱 Плитки»): ${names.map(n => '`' + n + '`').join(', ')}. The rooms that lay them (tools/rooms/generate_rooms.py terrain_nodes) name the files, so no scene changes.` };
}
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-act^="tiles-"]'); if (!b) return;
  const act = b.dataset.act, p = TILES.sel && tilePiece(TILES.sel);
  if (act === 'tiles-open') return tilesDialog();
  if (act === 'tiles-fam') { TILES.fam = b.dataset.f; TILES.sel = null; return renderTiles(); }
  if (act === 'tiles-pick') { TILES.sel = b.dataset.n; return renderTiles(); }
  if (act === 'tiles-revert') { TILES.mine.delete(TILES.sel); tilesSave(); return renderTiles(); }
  if (act === 'tiles-get' && p) { const r = await fetch(tileSrc(p)); return download(await r.blob(), p.name + '.png'); }
  if (act === 'tiles-prompt' && p) {
    const text = `Pixel art game tile for a dark gothic 2D platformer, matching the attached piece exactly in style, palette and pixel scale: ${TILE_PROMPT[p.family]}. ` +
      `Exactly ${p.w}x${p.h} pixels of art (draw it at ${p.w * 8}x${p.h * 8} on a ${p.w * 8 * 1.5 | 0}px canvas if needed, I will scale it down), ` +
      `crisp hard pixel edges, no anti-aliasing, on a fully transparent background, lit from the upper left, the walkable top flat and ${p.top}px below the top edge. No text, no frame, no shadow on the background.`;
    try { await navigator.clipboard.writeText(text); toast('Промпт скопирован. Приложи к нему скачанный кусок как образец.'); } catch { dialog(`<h3>Промпт</h3><pre class="log">${esc(text)}</pre>`); }
    return;
  }
  if (act === 'tiles-send') {
    await sendToGame(tilesFiles, null);
    if (sendToGame.last?.local) { TILES.mine.clear(); tilesSave(); }
    return renderTiles();
  }
});
document.addEventListener('paste', e => {
  if (!$('#tilesBox') || !TILES.sel) return;
  const f = [...(e.clipboardData?.files || [])].find(f => f.type.startsWith('image/')); if (f) { e.preventDefault(); tilesTake(f); }
});
