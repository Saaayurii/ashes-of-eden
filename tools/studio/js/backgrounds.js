/* Sprite Studio — the backgrounds tab: parallax layers, the room library, scene export. Plain scripts share one global scope; index.html loads them in order. */
'use strict';

/* ======================= ЗАДНИКИ ======================= */
const LAYER_PRESETS = {
  sky:   { name: 'Небо', scroll: [0, 0], repeatX: false, cut: false },
  far:   { name: 'Дальний план', scroll: [0.1, 0.1], repeatX: true, cut: true },
  mid:   { name: 'Средний план', scroll: [0.4, 0.5], repeatX: true, cut: true },
  near:  { name: 'Ближний план', scroll: [0.75, 0.85], repeatX: true, cut: true },
  game:  { name: 'Игровой', scroll: [1, 1], repeatX: false, cut: true },
  front: { name: 'Передний план', scroll: [1.2, 1.1], repeatX: true, cut: true },
};
const LAYER_PROMPTS = {
  sky: 'the far sky only: sky gradient, clouds, moon or sun, distant glow. No ground, no buildings, no silhouettes. The whole image is painted, nothing is empty.',
  far: 'far-distance silhouettes on the horizon in the lower half (mountains, a city skyline or ruins), low contrast, hazy and desaturated, blending into the sky color.',
  mid: 'middle-distance scenery standing on the bottom edge of the image (trees, buildings, ruins), medium contrast, slightly hazy.',
  near: 'near scenery right behind the play area (large trees, walls, fences, gravestones) standing on the bottom edge, dark tones, more detail.',
  game: 'the ground strip and large objects at the level where the player walks, standing on the bottom edge.',
  front: 'sparse foreground silhouettes drawn in front of the player: hanging branches or chains at the top edge, tall grass and debris at the bottom edge, almost black. The whole middle of the image stays empty.',
};
const KIND_LABEL = { sky: 'Небо', far: 'Дальний', mid: 'Средний', near: 'Ближний', game: 'Игровой', front: 'Передний' };
const guessKind = sc => { const v = sc?.[0] ?? 1; return v <= 0.02 ? 'sky' : v < 0.25 ? 'far' : v < 0.6 ? 'mid' : v < 0.95 ? 'near' : v <= 1.0 ? 'game' : 'front'; };
function newLayer(kind = 'game') { const p = LAYER_PRESETS[kind] || LAYER_PRESETS.game; return { id: uid(), name: p.name, kind, scroll: [...p.scroll], visible: true, opacity: 1, repeatX: p.repeatX, cut: p.cut, z: 0, items: [] }; }
function newBg(name) {
  return { id: uid(), kind: 'bg', name, description: '', width: 1600, height: 720, viewW: 561, viewH: 316, ambient: null,
    resDir: `res://assets/backgrounds/${name}/`, images: {}, layers: ['sky', 'far', 'mid', 'game', 'front'].map(newLayer), updated: Date.now() };
}
function migrateBg(b) {
  b.images ||= {}; b.layers ||= []; b.viewW ||= 561; b.viewH ||= 316; b.description ??= '';
  b.resDir ||= `res://assets/backgrounds/${slug(b.name)}/`;
  for (const l of b.layers) {
    l.opacity ??= 1; l.visible ??= true; l.kind ||= guessKind(l.scroll); l.items ||= []; l.cut ??= (LAYER_PRESETS[l.kind] || {}).cut ?? true;
    for (const it of l.items) { if (it.kind === 'sprite') { it.modulate ||= [1, 1, 1, 1]; it.sx ??= 1; it.sy ??= 1; } }
  }
  return b;
}

let mode = 'chars', bgs = [], BG = null, bgSel = { layer: null, item: null };
const bgView = { camX: 0, camY: 0, play: false, dir: 1, last: 0, dirty: true };
let bgSaveTimer = null, library = null;
const bgDirty = () => { bgView.dirty = true; };
function saveBg() { if (!BG) return; BG.updated = Date.now(); BG.dirty = true; trackChange('bg'); clearTimeout(bgSaveTimer); bgSaveTimer = setTimeout(persistBg, 400); }
async function persistBg() { if (!dbOk || !BG) return; try { await DB.put(BG, 'backgrounds'); } catch (e) { toast('Не получилось сохранить задник: ' + e.message, 'err'); } }
async function bgUpsert(b) { const i = bgs.findIndex(x => x.id === b.id); if (i >= 0) bgs[i] = b; else bgs.push(b); if (dbOk) try { await DB.put(b, 'backgrounds'); } catch {} }
const curLayer = () => BG?.layers.find(l => l.id === bgSel.layer) || null;
function findBgItem(id) { if (!BG || !id) return null; for (const l of BG.layers) { const i = l.items.findIndex(it => it.id === id); if (i >= 0) return { l, it: l.items[i], i }; } return null; }
const rgba = (c, a = c[3] ?? 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;
const toHex = c => '#' + c.slice(0, 3).map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('');
const fromHex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);

function setMode(m) {
  if (mode === 'cut' && m !== 'cut') cutStop();
  mode = m; document.body.dataset.mode = m; document.body.classList.toggle('mode-bg', m === 'bg');
  if (m === 'snd' || m === 'cut') enterStoryMode(m);
  if (m === 'rig' && typeof renderRig === 'function') renderRig();
  if (m === 'life' && typeof lifeEnter === 'function') lifeEnter();
  if (m === 'shots' && typeof shotsEnter === 'function') shotsEnter();
  if (m === 'pfx' && typeof pfxEnter === 'function') pfxEnter();
  if (m === 'dlg' && typeof dlgEnter === 'function') dlgEnter();
  $$('.modes button').forEach(b => b.classList.toggle('on', b.dataset.m === m));
  try { localStorage.setItem('ss_mode', m); } catch {}
  if (m === 'bg') {
    if (typeof seamsLoad === 'function') seamsLoad().then(() => renderItemPanel()).catch(() => {});
    renderBgAll(); layoutBg();
    // первый вход: если задников нет, сами подтягиваем комнаты из игры (если они доступны)
    if (!bgs.length && !setMode.tried) {
      setMode.tried = true;
      fetch('import/rooms_list.json', { method: 'HEAD' }).then(r => { if (r.ok) importFromUrl('import/rooms_list.json').then(renderBgAll); }).catch(() => {});
    }
  }
}

/* ---- images ---- */
const bgImgs = new Map(), tintCache = new WeakMap();
function bgImage(key) {
  const meta = BG.images[key]; if (!meta) return null;
  const src = meta.src || A(meta.url); let im = bgImgs.get(src);
  if (!im) { im = new Image(); im.crossOrigin = 'anonymous'; im.onload = bgDirty; im.onerror = () => { im._err = true; bgDirty(); }; im.src = src; bgImgs.set(src, im); }
  return im.complete && im.naturalWidth ? im : null;
}
function tinted(im, c) {
  if (c[0] === 1 && c[1] === 1 && c[2] === 1) return im;
  let m = tintCache.get(im); if (!m) tintCache.set(im, m = new Map());
  const k = c.slice(0, 3).join(','); if (m.has(k)) return m.get(k);
  const t = mk(im.naturalWidth, im.naturalHeight), x = t.getContext('2d');
  x.drawImage(im, 0, 0); x.globalCompositeOperation = 'multiply'; x.fillStyle = rgba(c, 1); x.fillRect(0, 0, t.width, t.height);
  x.globalCompositeOperation = 'destination-in'; x.drawImage(im, 0, 0);
  m.set(k, t); return t;
}
function itemSize(it) {
  if (it.kind === 'rect') return [it.w, it.h];
  const meta = BG.images[it.img] || {}; return [(meta.w || 0) * Math.abs(it.sx), (meta.h || 0) * Math.abs(it.sy)];
}
const layerOffset = l => [-bgView.camX * l.scroll[0], -bgView.camY * l.scroll[1]];
function layerPeriod(l) { let r = 0; for (const it of l.items) r = Math.max(r, it.x + itemSize(it)[0]); return Math.max(1, Math.round(r)); }

/* ---- render ---- */
function drawBg(c, sel) {
  const VW = +BG.viewW, VH = +BG.viewH;
  if (c.width !== VW || c.height !== VH) { c.width = VW; c.height = VH; }
  const x = c.getContext('2d');
  x.globalCompositeOperation = 'source-over'; x.globalAlpha = 1; x.fillStyle = '#000'; x.fillRect(0, 0, VW, VH);
  for (const l of BG.layers) {
    if (!l.visible) continue;
    const [ox, oy] = layerOffset(l);
    if (l.repeatX) {
      const P = layerPeriod(l), k0 = Math.floor(-ox / P) - 1, k1 = Math.ceil((VW - ox) / P);
      for (let k = k0; k <= k1; k++) for (const it of l.items) drawItem(x, it, l, ox + k * P, oy);
    } else for (const it of l.items) drawItem(x, it, l, ox, oy);
  }
  if ($('#bgAmb').checked && BG.ambient) { x.globalAlpha = 1; x.globalCompositeOperation = 'multiply'; x.fillStyle = rgba(BG.ambient, 1); x.fillRect(0, 0, VW, VH); x.globalCompositeOperation = 'source-over'; }
  const r = sel && findBgItem(bgSel.item);
  if (r && r.l.visible) {
    const [ox, oy] = layerOffset(r.l), [w, h] = itemSize(r.it);
    x.globalAlpha = 1; x.strokeStyle = '#6aa8ff'; x.lineWidth = 1; x.setLineDash([3, 2]);
    x.strokeRect(Math.round(r.it.x + ox) + 0.5, Math.round(r.it.y + oy) + 0.5, Math.max(1, Math.round(w) - 1), Math.max(1, Math.round(h) - 1)); x.setLineDash([]);
  }
}
function drawItem(x, it, l, ox, oy) {
  const a = l.opacity * ((it.kind === 'rect' ? it.color[3] : it.modulate[3]) ?? 1);
  if (a <= 0) return;
  x.globalAlpha = a;
  const X = Math.round(it.x + ox), Y = Math.round(it.y + oy);
  if (it.kind === 'rect') { x.fillStyle = rgba(it.color, 1); x.fillRect(X, Y, it.w, it.h); return; }
  const im = bgImage(it.img); if (!im) return;
  const [w, h] = itemSize(it), src = tinted(im, it.modulate);
  x.imageSmoothingEnabled = it.filter === 2;
  if (it.flipH) { x.save(); x.translate(X + w, Y); x.scale(-1, 1); x.drawImage(src, 0, 0, w, h); x.restore(); }
  else x.drawImage(src, X, Y, w, h);
}
function clampCam() {
  if (!BG) return;
  const mx = Math.max(0, BG.width - BG.viewW), my = Math.max(0, BG.height - BG.viewH);
  bgView.camX = Math.min(Math.max(0, bgView.camX), mx); bgView.camY = Math.min(Math.max(0, bgView.camY), my);
  const sx = $('#bgCamX'), sy = $('#bgCamY'); sx.max = mx; sy.max = my; sx.value = bgView.camX; sy.value = bgView.camY;
  $('#bgInfo').textContent = `камера ${Math.round(bgView.camX)}, ${Math.round(bgView.camY)} · комната ${BG.width}×${BG.height}`;
}
function layoutBg() {
  if (mode !== 'bg' || !BG) return;
  const st = $('#bgStage'), c = $('#bgCanvas'), VW = +BG.viewW, VH = +BG.viewH;
  let k = Math.min((st.clientWidth - 20) / VW, (st.clientHeight - 20) / VH);
  if (k >= 1) k = Math.floor(k);
  c.style.width = Math.round(VW * k) + 'px'; c.style.height = Math.round(VH * k) + 'px';
}
window.addEventListener('resize', layoutBg);
function bgLoop(ts) {
  requestAnimationFrame(bgLoop);
  const dt = Math.min(0.1, (ts - (bgView.last || ts)) / 1000); bgView.last = ts;
  if (mode !== 'bg' || !BG) return;
  if (bgView.play) {
    const mx = Math.max(0, BG.width - BG.viewW);
    bgView.camX += bgView.dir * 90 * dt;
    if (bgView.camX >= mx) { bgView.camX = mx; bgView.dir = -1; } else if (bgView.camX <= 0) { bgView.camX = 0; bgView.dir = 1; }
    clampCam(); bgView.dirty = true;
  }
  if (bgView.dirty) { bgView.dirty = false; drawBg($('#bgCanvas'), true); }
}

/* ---- panels ---- */
function renderBgSel() {
  $('#bgSel').innerHTML = bgs.slice().sort((a, b) => (a.name || '').localeCompare(b.name || ''))
    .map(b => `<option value="${b.id}" ${b.id === BG?.id ? 'selected' : ''}>${esc(b.name)}</option>`).join('') || '<option>—</option>';
}
function renderBgAll() {
  trackChange('bg');
  renderBgSel();
  $('#bgEmpty').style.display = BG ? 'none' : '';
  if (!BG) { $('#layerList').innerHTML = ''; $('#layerProps').innerHTML = ''; $('#itemPanel').innerHTML = ''; return; }
  $$('[data-bg]').forEach(el => { el.value = BG[el.dataset.bg] ?? ''; });
  if (!curLayer()) bgSel.layer = BG.layers[BG.layers.length - 1]?.id || null;
  clampCam(); renderLayerList(); renderLayerProps(); renderItemPanel(); layoutBg(); bgDirty();
}
function renderLayerList() {
  $('#layerList').innerHTML = BG.layers.map((l, i) => `
    <div class="lrow ${l.id === bgSel.layer ? 'on' : ''} ${l.visible ? '' : 'hid'}" data-act="bg-lsel" data-lid="${l.id}">
      <button data-act="bg-lvis" title="Показать / скрыть">${l.visible ? '👁' : '◌'}</button>
      <span class="ln">${esc(l.name)}</span>
      <span class="sc">×${+l.scroll[0].toFixed(2)}${l.repeatX ? ' ⟳' : ''} · ${l.items.length}</span>
      <button data-act="bg-lup" title="Ближе к игроку">▲</button><button data-act="bg-ldown" title="Дальше">▼</button>
    </div>`).reverse().join('') || '<div class="muted">Слоёв нет</div>';
}
function renderLayerProps() {
  const l = curLayer();
  if (!l) { $('#layerProps').innerHTML = ''; return; }
  $('#layerProps').innerHTML = `
    <h3>Слой</h3>
    <label>Название</label><input data-ly="name" value="${esc(l.name)}">
    <label>Тип (для промпта)</label>
    <select data-ly="kind">${Object.keys(LAYER_PRESETS).map(k => `<option value="${k}" ${k === l.kind ? 'selected' : ''}>${KIND_LABEL[k]}</option>`).join('')}</select>
    <div class="grid2">
      <div><label>Параллакс X</label><input type="number" step="0.05" data-ly="sx" value="${l.scroll[0]}"></div>
      <div><label>Параллакс Y</label><input type="number" step="0.05" data-ly="sy" value="${l.scroll[1]}"></div>
    </div>
    <div class="note">0 — стоит на месте (небо), 1 — движется вместе с миром, больше 1 — передний план.</div>
    <label>Прозрачность слоя</label><input type="range" min="0" max="1" step="0.05" data-ly="opacity" value="${l.opacity}">
    <label class="inline"><input type="checkbox" data-ly="repeatX" ${l.repeatX ? 'checked' : ''}> Повторять по горизонтали</label>
    <label class="inline"><input type="checkbox" data-ly="cut" ${l.cut ? 'checked' : ''}> Убирать фон у новых картинок</label>
    <div class="row">
      <button class="sm" data-act="bg-lprompt" title="Промпт для ChatGPT под этот слой">📋 Промпт слоя</button>
      <button class="sm" data-act="bg-lfile">⬆ Картинка</button>
      <button class="sm" data-act="bg-lib">Из игры…</button>
    </div>
    <div class="row"><button class="sm" data-act="bg-ldup">Копия слоя</button><button class="sm ghost danger" data-act="bg-ldel">🗑 Удалить слой</button></div>`;
}
// A picture a generator draws that she may repaint as an override: its path, or null.
const repaintable = meta => { const p = String(meta?.res || '').replace('res://', ''); return p && overridableSet().has(p) ? p : null; };
function renderItemPanel() {
  const l = curLayer(), r = findBgItem(bgSel.item);
  let h = '';
  if (r) {
    const it = r.it, meta = it.kind === 'sprite' ? BG.images[it.img] || {} : null;
    const col = it.kind === 'rect' ? it.color : it.modulate;
    h += `<section><h3>Картинка</h3>
      ${meta ? `<img class="ithumb checker" src="${meta.src || A(meta.url)}" alt="">
      <div class="note">${esc(meta.res || 'своя картинка')} · ${meta.w}×${meta.h}</div>
      ${repaintable(meta) ? `<button class="sm" data-act="bg-repaint" title="Картинка того же размера (например, исправленная в ChatGPT или Procreate) ляжет правкой поверх генератора — тем, чем отличается">🖌 Перерисовать картину</button>
        ${typeof SEAMS !== 'undefined' && SEAMS.data?.[meta.res] ? `<button class="sm" data-act="seam-open" data-res="${esc(meta.res)}" title="Полосы, которые генератор вставил, чтобы расширить картину: в них повторяется то, что стоит рядом">🩹 Швы (${SEAMS.data[meta.res].bands.length})</button>` : ''}
        ${META.overrides?.[repaintable(meta)]?.stale ? '<div class="warn">⚠ База изменилась — проверь: генератор перерисовал картину под твоей правкой.</div>' : META.overrides?.[repaintable(meta)] ? '<div class="note">Есть твоя правка этой картины.</div>' : ''}` : ''}` : `<div class="note">Прямоугольник цвета</div>`}
      <div class="grid2">
        <div><label>X</label><input type="number" data-it="x" value="${+it.x.toFixed(1)}"></div>
        <div><label>Y</label><input type="number" data-it="y" value="${+it.y.toFixed(1)}"></div>
        ${it.kind === 'rect'
          ? `<div><label>Ширина</label><input type="number" data-it="w" value="${it.w}"></div><div><label>Высота</label><input type="number" data-it="h" value="${it.h}"></div>`
          : `<div><label>Масштаб</label><input type="number" step="0.05" min="0.05" data-it="scale" value="${+Math.abs(it.sx).toFixed(3)}"></div>
             <div><label>&nbsp;</label><label class="inline"><input type="checkbox" data-it="flipH" ${it.flipH ? 'checked' : ''}> Отразить</label></div>`}
      </div>
      <div class="grid2">
        <div><label>Оттенок</label><input type="color" data-it="tint" value="${toHex(col)}" style="height:30px;padding:2px"></div>
        <div><label>Прозрачность</label><input type="range" min="0" max="1" step="0.05" data-it="opacity" value="${col[3] ?? 1}"></div>
      </div>
      ${it.kind === 'sprite' ? `<label class="inline"><input type="checkbox" data-it="smooth" ${it.filter === 2 ? 'checked' : ''}> Сглаживание (для рисованных картин)</label>` : ''}
      <label>Слой</label><select data-it="layer">${BG.layers.map(x => `<option value="${x.id}" ${x === r.l ? 'selected' : ''}>${esc(x.name)}</option>`).join('')}</select>
      <div class="row">
        <button class="sm" data-act="bg-iup" title="Выше внутри слоя">▲</button><button class="sm" data-act="bg-idown" title="Ниже внутри слоя">▼</button>
        <button class="sm" data-act="bg-idup">Копия</button><button class="sm ghost danger" data-act="bg-idel">Удалить</button>
      </div></section>`;
  }
  if (l) {
    h += `<section><h3>В слое «${esc(l.name)}»: ${l.items.length}</h3><div class="ilist">${l.items.map((it, i) => {
      const meta = it.kind === 'sprite' ? BG.images[it.img] : null;
      return `<div class="irow ${it.id === bgSel.item ? 'on' : ''}" data-act="bg-isel" data-iid="${it.id}">${meta ? `<img class="checker" src="${meta.src || A(meta.url)}" alt="">` : `<i style="background:${rgba(it.color, 1)}"></i>`}<span>${esc(it.name || (meta?.res || 'картинка').split('/').pop())}</span></div>`;
    }).reverse().join('') || '<div class="muted">Пусто. Ctrl+V, «⬆ Картинка» или «Из игры…»</div>'}</div></section>`;
  }
  $('#itemPanel').innerHTML = h;
}
function bgSelectItem(id) {
  const r = findBgItem(id); bgSel.item = r ? id : null;
  if (r && r.l.id !== bgSel.layer) { bgSel.layer = r.l.id; renderLayerList(); renderLayerProps(); }
  renderItemPanel(); bgDirty();
}

/* ---- adding images ---- */
async function bgAddFiles(files) {
  files = files.filter(f => f.type.startsWith('image/'));
  if (!files.length || !BG) return;
  const l = curLayer(); if (!l) return toast('Сначала выбери слой', 'err');
  for (const f of files) await bgAddCustom(l, await blobToDataURL(f));
}
// Картинка из ChatGPT = один «экран». Масштабируем её под экран игры, по желанию
// убираем фон и ставим туда, где она была на экране при текущей камере.
async function bgAddCustom(l, src) {
  const img = await loadImage(src), W0 = img.naturalWidth, H0 = img.naturalHeight, VW = +BG.viewW, VH = +BG.viewH;
  let c = mk(W0, H0), offX = 0, offY = 0;
  c.getContext('2d').drawImage(img, 0, 0);
  if (l.cut) {
    const cut = cropMask(maskImage(img, 48, 'auto'));
    if (!cut) return toast('После удаления фона ничего не осталось. Сними галочку «Убирать фон».', 'err');
    c = cut.canvas; offX = cut.ox; offY = cut.oy;
  }
  const s = l.kind === 'sky' ? Math.max(VW / W0, VH / H0) : VH / H0;
  const out = mk(Math.max(1, Math.round(c.width * s)), Math.max(1, Math.round(c.height * s))), ox = out.getContext('2d');
  ox.imageSmoothingQuality = 'high'; ox.drawImage(c, 0, 0, out.width, out.height);
  const key = 'c_' + uid();
  BG.images[key] = { src: out.toDataURL('image/png'), w: out.width, h: out.height };
  const it = { id: uid(), kind: 'sprite', name: `${slug(l.name)}_${l.items.length + 1}`, img: key,
    x: Math.round(bgView.camX * l.scroll[0] + offX * s), y: Math.round(bgView.camY * l.scroll[1] + offY * s), sx: 1, sy: 1, flipH: false, modulate: [1, 1, 1, 1], filter: 0 };
  l.items.push(it); bgSel.item = it.id; saveBg(); renderLayerList(); renderItemPanel(); bgDirty();
  toast(`Добавлено в «${l.name}»`);
}
function bgAddGame(entry) {
  const l = curLayer(); if (!l) return toast('Сначала выбери слой', 'err');
  BG.images[entry.res] ||= { url: entry.url, res: entry.res, w: entry.w, h: entry.h };
  const VW = +BG.viewW, VH = +BG.viewH, big = entry.w >= VW * 0.9;
  const it = { id: uid(), kind: 'sprite', name: entry.res.split('/').pop().replace(/\.png$/, ''), img: entry.res,
    x: Math.round(bgView.camX * l.scroll[0] + (big ? 0 : (VW - entry.w) / 2)), y: Math.round(bgView.camY * l.scroll[1] + (big ? 0 : VH - entry.h)),
    sx: 1, sy: 1, flipH: false, modulate: [1, 1, 1, 1], filter: big ? 2 : 0 };
  l.items.push(it); bgSel.item = it.id; saveBg(); renderLayerList(); renderItemPanel(); bgDirty();
}
async function openLibrary() {
  if (!library) {
    try { library = await (await fetch('import/library.json')).json(); }
    catch { return toast('Библиотека игры недоступна: запусти студию из её папки и выполни конвертер с --rooms', 'err'); }
  }
  $('#libModal').hidden = false; renderLibrary();
}
function renderLibrary() {
  const cat = $('#libCat').value, q = $('#libSearch').value.trim().toLowerCase();
  const list = library.filter(e => (!cat || e.cat === cat) && (!q || e.res.toLowerCase().includes(q)));
  $('#libInfo').textContent = `${list.length} картинок · добавятся в слой «${curLayer()?.name || '—'}»`;
  $('#libGrid').innerHTML = list.slice(0, 400).map((e, i) => `<button data-act="lib-pick" data-res="${esc(e.res)}" class="checker"><img loading="lazy" src="${esc(A(e.url))}" alt=""><span>${esc(e.res.replace('res://assets/', ''))} · ${e.w}×${e.h}</span></button>`).join('');
}

/* ---- prompt ---- */
function layerPrompt(l) {
  const sky = l.kind === 'sky';
  return [
    'Create ONE parallax background layer for a 2D side-scrolling dark-fantasy pixel-art game (like the attached screenshot, if any).',
    `Location: ${BG.description || 'the location from the attached reference'}.`,
    `This layer is: ${LAYER_PROMPTS[l.kind] || LAYER_PROMPTS.game}`,
    'Style: painted pixel art with a muted, dark, desaturated palette, soft atmospheric depth, no characters, no creatures, no UI, no text.',
    'Format: wide landscape 3:2 image, side view, the horizon and ground line are perfectly horizontal.',
    l.repeatX ? 'The left and right edges must match so the image can repeat seamlessly side by side.' : '',
    sky ? 'Fill the entire image.' : 'Everything that is NOT part of this layer must be solid flat pure magenta (#FF00FF), perfectly uniform, so it can be cut out. No magenta inside the scenery.',
  ].filter(Boolean).join('\n');
}

/* ---- export ---- */
async function exportBg() {
  if (!BG) return;
  const r = await bgFiles().catch(e => { toast(e.message, 'err'); return null; }); if (!r) return;
  const zip = new JSZip();
  for (const [path, b] of Object.entries(r.files)) zip.file(path, b);
  zip.file(`${r.dir}README.md`, [`# ${r.name}: задник для Godot 4`, '', `Сцена \`${r.scene}\` (слои Parallax2D, сверху вниз — от дальнего к ближнему). Файлы разложены по путям игры.`,
    'Картинки из игры не копируются: сцена ссылается на них по их путям.', '', ...r.notes, '',
    '| слой | узел | параллакс | повтор | картинок |', '|---|---|---|---|---|', ...r.table, ''].join('\n'));
  download(await zip.generateAsync({ type: 'blob' }), `${r.name}_background.zip`);
  toast('Задник экспортирован');
}

/* ---- events ---- */
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-act]'); if (!b) return;
  const act = b.dataset.act;
  if (act === 'mode') return setMode(b.dataset.m);
  if (!act.startsWith('bg-') && !act.startsWith('lib-')) return;
  const row = e.target.closest('[data-lid]'), l = row ? BG.layers.find(x => x.id === row.dataset.lid) : curLayer();
  switch (act) {
    case 'bg-new': {
      const name = prompt('Имя задника латиницей:', 'new_room'); if (!name) return;
      BG = newBg(slug(name)); bgSel = { layer: null, item: null }; await bgUpsert(BG); saveLastBg(); renderBgAll(); break;
    }
    case 'bg-del':
      if (!BG || !confirm(`Удалить задник «${BG.name}» из этого браузера?`)) return;
      try { await DB.del(BG.id, 'backgrounds'); } catch {}
      bgs = bgs.filter(x => x !== BG); BG = bgs[0] || null; bgSel = { layer: null, item: null }; renderBgAll(); break;
    case 'bg-rooms': await importFromUrl('import/rooms_list.json'); renderBgAll(); break;
    case 'bg-save': if (BG) download(new Blob([JSON.stringify(BG)], { type: 'application/json' }), `${slug(BG.name)}.bg.json`); break;
    case 'bg-import': {
      const [file] = await pickFiles('.json,application/json', false); if (!file) return;
      let b; try { b = JSON.parse(await file.text()); } catch (err) { return toast('Не получилось прочитать файл: ' + err.message, 'err'); }
      if (b.kind !== 'bg') return toast('Это не файл задника', 'err');
      BG = migrateBg(b); await bgUpsert(BG); saveLastBg(); renderBgAll(); toast('Задник открыт'); break;
    }
    case 'bg-export': exportBg().catch(err => toast('Ошибка экспорта: ' + err.message, 'err')); break;
    case 'bg-lsel': bgSel.layer = l.id; if (findBgItem(bgSel.item)?.l !== l) bgSel.item = null; renderLayerList(); renderLayerProps(); renderItemPanel(); bgDirty(); break;
    case 'bg-lvis': l.visible = !l.visible; saveBg(); renderLayerList(); bgDirty(); break;
    case 'bg-lup': case 'bg-ldown': {
      const i = BG.layers.indexOf(l), j = i + (act === 'bg-lup' ? 1 : -1);
      if (j < 0 || j >= BG.layers.length) return;
      [BG.layers[i], BG.layers[j]] = [BG.layers[j], BG.layers[i]]; saveBg(); renderLayerList(); bgDirty(); break;
    }
    case 'bg-ladd': {
      const nl = newLayer($('#layerPreset').value), cur = curLayer();
      const idx = cur ? BG.layers.indexOf(cur) + 1 : BG.layers.length;
      BG.layers.splice(idx, 0, nl); bgSel = { layer: nl.id, item: null }; saveBg(); renderLayerList(); renderLayerProps(); renderItemPanel(); break;
    }
    case 'bg-ldup': {
      const copy = JSON.parse(JSON.stringify(l)); copy.id = uid(); copy.name += ' копия'; copy.items.forEach(it => it.id = uid());
      BG.layers.splice(BG.layers.indexOf(l) + 1, 0, copy); bgSel = { layer: copy.id, item: null }; saveBg(); renderLayerList(); renderLayerProps(); renderItemPanel(); bgDirty(); break;
    }
    case 'bg-ldel':
      if (!confirm(`Удалить слой «${l.name}»${l.items.length ? ` и ${l.items.length} картинок в нём` : ''}?`)) return;
      BG.layers = BG.layers.filter(x => x !== l); bgSel = { layer: null, item: null }; saveBg(); renderBgAll(); break;
    case 'bg-lprompt': copyText(layerPrompt(l)); break;
    case 'bg-lfile': await bgAddFiles(await pickFiles('image/*', true)); break;
    case 'bg-lib': openLibrary(); break;
    case 'lib-close': $('#libModal').hidden = true; break;
    case 'lib-pick': { const en = library.find(x => x.res === b.dataset.res); if (en) { bgAddGame(en); toast(`Добавлено: ${en.res.split('/').pop()}`); } break; }
    case 'bg-isel': bgSelectItem(b.dataset.iid); break;
    case 'bg-repaint': {
      // a room's painting is the room generator's: her repaint goes as an override (repo.js convertToOverrides)
      const r = findBgItem(bgSel.item), meta = r && BG.images[r.it.img], path = meta && repaintable(meta); if (!path) return;
      const [file] = await pickFiles('image/*', false); if (!file) return;
      const im = await loadImage(await blobToDataURL(file));
      if (im.naturalWidth !== meta.w || im.naturalHeight !== meta.h) return toast(`Картина ${meta.w}×${meta.h}, а эта ${im.naturalWidth}×${im.naturalHeight}. Нужен тот же размер — правка ложится поверх картины игры.`, 'err');
      sendToGame(async () => ({ files: { [path]: file }, title: `Studio: перерисована картина ${path.split('/').pop()}`,
        body: `Правка картины \`${path}\` из студии: что отличается от игры, ляжет поверх генератора комнат.`,
        notes: ['Робот студии пересоберёт комнату с твоей правкой в этой же отправке.'] }), 'bg');
      return;
    }
    case 'bg-idel': case 'bg-idup': case 'bg-iup': case 'bg-idown': {
      const r = findBgItem(bgSel.item); if (!r) return;
      if (act === 'bg-idel') { r.l.items.splice(r.i, 1); bgSel.item = null; }
      else if (act === 'bg-idup') { const c = JSON.parse(JSON.stringify(r.it)); c.id = uid(); c.x += 10; c.y += 10; r.l.items.splice(r.i + 1, 0, c); bgSel.item = c.id; }
      else { const j = r.i + (act === 'bg-iup' ? 1 : -1); if (j < 0 || j >= r.l.items.length) return; [r.l.items[r.i], r.l.items[j]] = [r.l.items[j], r.l.items[r.i]]; }
      saveBg(); renderLayerList(); renderItemPanel(); bgDirty(); break;
    }
    case 'bg-play': bgView.play = !bgView.play; b.textContent = bgView.play ? '⏸ Прокрутка' : '▶ Прокрутка'; break;
    case 'bg-full': $('#bgMain').classList.toggle('full'); requestAnimationFrame(layoutBg); break;
  }
});
document.addEventListener('input', e => {
  const t = e.target;
  if (t.id === 'libCat' || t.id === 'libSearch') return renderLibrary();
  if (!BG) return;
  if (t.id === 'bgCamX' || t.id === 'bgCamY') { bgView[t.id === 'bgCamX' ? 'camX' : 'camY'] = +t.value; clampCam(); bgDirty(); return; }
  if (t.id === 'bgAmb') return bgDirty();
  if (t.dataset.bg) {
    const k = t.dataset.bg; BG[k] = t.type === 'number' ? Math.max(1, +t.value || 1) : t.value;
    if (k === 'name') renderBgSel();
    if (k.startsWith('view')) layoutBg();
    clampCam(); saveBg(); bgDirty(); return;
  }
  if (t.dataset.ly) {
    const l = curLayer(); if (!l) return; const k = t.dataset.ly;
    if (k === 'sx') l.scroll[0] = +t.value; else if (k === 'sy') l.scroll[1] = +t.value;
    else if (k === 'opacity') l.opacity = +t.value;
    else if (k === 'repeatX' || k === 'cut') l[k] = t.checked;
    else l[k] = t.value;
    saveBg(); bgDirty();
    if (k !== 'opacity' && k !== 'cut') renderLayerList();
    return;
  }
  if (t.dataset.it) {
    const r = findBgItem(bgSel.item); if (!r) return; const it = r.it, k = t.dataset.it;
    const col = it.kind === 'rect' ? it.color : it.modulate;
    if (k === 'scale') { const v = Math.max(0.01, +t.value || 1); it.sx = v; it.sy = v; }
    else if (k === 'flipH') it.flipH = t.checked;
    else if (k === 'smooth') it.filter = t.checked ? 2 : 0;
    else if (k === 'opacity') col[3] = +t.value;
    else if (k === 'tint') col.splice(0, 3, ...fromHex(t.value));
    else if (k === 'layer') { const to = BG.layers.find(x => x.id === t.value); if (to && to !== r.l) { r.l.items.splice(r.i, 1); to.items.push(it); bgSel.layer = to.id; renderLayerList(); renderLayerProps(); renderItemPanel(); } }
    else it[k] = +t.value;
    saveBg(); bgDirty(); return;
  }
});
$('#bgSel').addEventListener('change', e => { const b = bgs.find(x => x.id === e.target.value); if (!b) return; BG = migrateBg(b); bgSel = { layer: null, item: null }; saveLastBg(); renderBgAll(); });
function saveLastBg() { try { localStorage.setItem('ss_lastbg', BG?.id || ''); } catch {} }

// мышь на холсте: тащим картинку или камеру
const drag = { on: false };
function canvasPoint(e) { const c = $('#bgCanvas'), k = c.clientWidth / c.width; return [e.offsetX / k, e.offsetY / k, k]; }
function hitTest(px, py) {
  for (let li = BG.layers.length - 1; li >= 0; li--) {
    const l = BG.layers[li]; if (!l.visible) continue;
    const [ox, oy] = layerOffset(l);
    for (let i = l.items.length - 1; i >= 0; i--) {
      const it = l.items[i], [w, h] = itemSize(it), x = it.x + ox, y = it.y + oy;
      if (px >= x && px < x + w && py >= y && py < y + h) return it;
    }
  }
  return null;
}
palmGuard($('#bgCanvas'), { fingers: 'use' });   // a finger pans the scene; a palm under the pencil does nothing
$('#bgCanvas').addEventListener('pointerdown', e => {
  if (!BG) return;
  const [px, py] = canvasPoint(e), it = e.altKey ? null : hitTest(px, py);
  drag.on = true; drag.px = px; drag.py = py; drag.moved = false;
  if (it) { bgSelectItem(it.id); drag.item = it; drag.sx = it.x; drag.sy = it.y; }
  else { drag.item = null; drag.cx = bgView.camX; drag.cy = bgView.camY; }
  e.currentTarget.setPointerCapture(e.pointerId); e.currentTarget.style.cursor = 'grabbing';
});
$('#bgCanvas').addEventListener('pointermove', e => {
  if (!drag.on) return;
  const [px, py] = canvasPoint(e), dx = px - drag.px, dy = py - drag.py;
  if (Math.abs(dx) + Math.abs(dy) > 0.5) drag.moved = true;
  if (drag.item) { drag.item.x = Math.round(drag.sx + dx); drag.item.y = Math.round(drag.sy + dy); const fx = $('[data-it="x"]'), fy = $('[data-it="y"]'); if (fx) fx.value = drag.item.x; if (fy) fy.value = drag.item.y; }
  else { bgView.camX = drag.cx - dx; bgView.camY = drag.cy - dy; clampCam(); }
  bgDirty();
});
$('#bgCanvas').addEventListener('pointerup', e => {
  if (!drag.on) return; drag.on = false; e.currentTarget.style.cursor = '';
  if (drag.item && drag.moved) saveBg();
  if (!drag.item && !drag.moved && bgSel.item) { bgSel.item = null; renderItemPanel(); bgDirty(); }
});
$('#bgCanvas').addEventListener('wheel', e => { if (!BG) return; e.preventDefault(); bgView.camX += (e.deltaX || e.deltaY); clampCam(); bgDirty(); }, { passive: false });
document.addEventListener('keydown', e => {
  if (mode !== 'bg' || e.target.closest?.('input,textarea,select')) return;
  if (e.key === 'Escape') { $('#bgMain').classList.remove('full'); $('#libModal').hidden = true; requestAnimationFrame(layoutBg); return; }
  if (e.key === ' ') { e.preventDefault(); $('#bgPlay').click(); return; }
  if (e.key === 'f' || e.key === 'а') { e.preventDefault(); $('#bgMain').classList.toggle('full'); requestAnimationFrame(layoutBg); return; }
  const r = findBgItem(bgSel.item); if (!r) return;
  const st = e.shiftKey ? 10 : 1, mv = { ArrowLeft: [-st, 0], ArrowRight: [st, 0], ArrowUp: [0, -st], ArrowDown: [0, st] }[e.key];
  if (mv) { e.preventDefault(); r.it.x += mv[0]; r.it.y += mv[1]; saveBg(); renderItemPanel(); bgDirty(); return; }
  if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); r.l.items.splice(r.i, 1); bgSel.item = null; saveBg(); renderLayerList(); renderItemPanel(); bgDirty(); }
});

async function bgInit() {
  try { bgs = ((await DB.all('backgrounds')) || []).map(migrateBg); } catch { bgs = []; }
  let last = null; try { last = localStorage.getItem('ss_lastbg'); } catch {}
  if (!BG) BG = bgs.find(b => b.id === last) || bgs[0] || null;
  let m = 'chars'; try { m = localStorage.getItem('ss_mode') || 'chars'; } catch {}
  await sndInit(); await cutInit(); requestAnimationFrame(cutLoop);
  setMode(mode === 'bg' ? 'bg' : m);
  requestAnimationFrame(bgLoop);
}
