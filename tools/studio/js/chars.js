/* Sprite Studio — the characters tab: processing, export, frames, preview, events. Plain scripts share one global scope; index.html loads them in order. */
'use strict';

/* ---------- image processing ---------- */
function maskImage(img, tol, mode) {
  const w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
  const c = mk(w, h), x = c.getContext('2d', { willReadFrequently: true });
  x.drawImage(img, 0, 0);
  const id = x.getImageData(0, 0, w, h);
  // the background's own colour, when it was a colour and not transparency: the checks look for its fringe
  let tr = 0, sm = 0; for (let p = 0; p < w * h; p += 7) { sm++; if (id.data[p * 4 + 3] < 200) tr++; }
  const key = mode !== 'alpha' && tr / sm <= 0.02 ? cornerColor(id.data, w, h).slice(0, 3) : null;
  const m = maskPixels(id.data, w, h, tol, mode);
  x.putImageData(id, 0, 0);
  return { c, w, h, m, key };
}
function cropMask({ c, w, h, m, key }) {
  const b = cropBox(m, w, h); if (!b) return null;
  const cw = b.x1 - b.x0 + 1, ch = b.y1 - b.y0 + 1, out = mk(cw, ch);
  out.getContext('2d').drawImage(c, b.x0, b.y0, cw, ch, 0, 0, cw, ch);
  return { canvas: out, w: cw, h: ch, ox: b.x0, oy: b.y0, key, cov: b.cnt / (w * h), data: out.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, cw, ch).data };
}
function compose(s, f, S) {
  const W = +S.cellW, H = +S.cellH, c = mk(W, H), t = mk(s.w, s.h);
  t.getContext('2d').putImageData(s.img, 0, 0);
  const keep = S.anchor === 'none' || f.baked;
  const x = (keep ? Math.round(s.ox || 0) : Math.round(W / 2 - anchorX(s, S.anchor))) + (f.dx | 0);
  const y = (keep ? Math.round(s.oy || 0) : H - (+S.bottomPad) - s.h) + (f.dy | 0);
  c.getContext('2d').drawImage(t, x, y);
  c._clip = x < 0 || y < 0 || x + s.w > W || y + s.h > H;
  return c;
}

const cutCache = new Map();
async function getCut(key, src) {
  const S = P.settings, k = key + '|' + fingerprint(src) + '|' + S.tolerance + '|' + S.bgMode;
  if (cutCache.has(k)) return cutCache.get(k);
  if (cutCache.size > 600) cutCache.clear();
  const img = await loadImage(src);
  const cut = cropMask(maskImage(img, +S.tolerance || 48, S.bgMode));
  cutCache.set(k, cut);
  return cut;
}

let processed = new Map(), procRef = null, palette = null, warnings = [], artReport = [];
let building = false, buildAgain = false, buildTimer = null;
function scheduleBuild(ms = 250) { clearTimeout(buildTimer); buildTimer = setTimeout(build, ms); }
async function build() {
  if (building) { buildAgain = true; return; }
  building = true;
  try { do { buildAgain = false; await doBuild(); } while (buildAgain); if (typeof sandboxChanged === 'function') sandboxChanged(); }
  catch (e) { console.error(e); toast('Ошибка обработки: ' + e.message, 'err'); }
  finally { building = false; }
}
async function doBuild() {
  const S = P.settings, CH = Math.max(1, +S.contentH), smalls = [], out = [], warn = [];
  const grid = S.scaleMode === 'grid' || S.scaleMode === 'gridfit';
  let gp = 0;
  if (grid) {
    const cuts = [];
    for (const a of P.animations) for (const f of a.frames) if (f.src && !f.off && !f.baked) { const c = await getCut(f.id, f.src); if (c) cuts.push(c); }
    if (P.reference) { const c = await getCut('ref', P.reference); if (c) cuts.push(c); }
    gp = +S.pixelSize > 0 ? +S.pixelSize : cuts.length ? globalGridP(cuts) : 0;
    if (gp) warn.push(`ℹ Размер «пикселя» в картинках: ${gp.toFixed(1)} px${+S.pixelSize > 0 ? ' (задан вручную)' : ' (найден автоматически)'}`);
  }
  for (const a of P.animations) {
    const items = [];
    for (const [i, f] of a.frames.entries()) {
      if (!f.src) continue;
      const cut = await getCut(f.id, f.src); await tick();
      if (!cut) { warn.push(`${a.name} #${i + 1}: не нашёл персонажа, проверь фон`); continue; }
      if (cut.cov < 0.02 && S.bgMode !== 'alpha') warn.push(`${a.name} #${i + 1}: от персонажа почти ничего не осталось — фон похож на персонажа. Уменьши «Допуск фона» или попроси в ChatGPT пурпурный фон`);
      items.push({ f, cut, i });
    }
    if (!items.length) continue;
    // frames baked from the rig are already pixel art at the game's size, placed in the cell: taken as they are
    for (const it of items.filter(it => it.f.baked)) { const c = copyCut(it.cut); c.ox = it.cut.ox; c.oy = it.cut.oy; smalls.push(c); out.push({ s: c, f: it.f, a, i: it.i }); }
    items.splice(0, items.length, ...items.filter(it => !it.f.baked));
    if (!items.length) continue;
    const maxH = Math.max(...items.map(it => it.cut.h));
    if (grid && gp) {
      const natives = [];
      for (const it of items) { natives.push(nativeSprite(it.cut, gp, +S.pixelSize > 0)); await tick(); }
      const nH = Math.max(...natives.map(n => n.h));
      natives.forEach((n, j) => {
        const it = items[j], k = S.scaleMode === 'gridfit' ? CH / nH * (+a.scale || 1) * (+it.f.sc || 1) : 1;
        // подгоняем уже чистый пиксель-арт; доминантный цвет не смешивает соседние пиксели
        const s = Math.abs(k - 1) < 0.01 ? n : downscale({ data: n.img.data, w: n.w, h: n.h }, k, 'dominant');
        s.ox = s.oy = 0; smalls.push(s); out.push({ s, f: it.f, a, i: it.i });
      });
      if (S.scaleMode === 'grid' && Math.abs(nH - CH) > CH * 0.12)
        warn.push(`FIX${a.name}: ChatGPT нарисовал персонажа ростом ${nH} px, а в игре рост ${CH} px — поэтому он ${nH > CH ? 'крупнее' : 'мельче'} Элиана.`);
      continue;
    }
    for (const it of items) {
      const base = S.scaleMode === 'none' ? 1 : S.scaleMode === 'frame' ? CH / it.cut.h : CH / maxH;
      const k = base * (+a.scale || 1) * (+it.f.sc || 1);
      const s = k === 1 ? copyCut(it.cut) : downscale(it.cut, k, S.downMode);
      s.ox = it.cut.ox * k; s.oy = it.cut.oy * k;
      smalls.push(s); out.push({ s, f: it.f, a, i: it.i });
    }
  }
  let refS = null;
  if (P.reference) {
    const cut = await getCut('ref', P.reference);
    if (cut && grid && gp) {
      refS = nativeSprite(cut, gp, +S.pixelSize > 0);
      if (S.scaleMode === 'gridfit' && Math.abs(refS.h - CH) > 1) refS = downscale({ data: refS.img.data, w: refS.w, h: refS.h }, CH / refS.h, 'dominant');
      smalls.push(refS);
    }
    else if (cut) { const k = S.scaleMode === 'none' ? 1 : CH / cut.h; refS = k === 1 ? copyCut(cut) : downscale(cut, k, S.downMode); refS.ox = cut.ox * k; refS.oy = cut.oy * k; smalls.push(refS); }
  }
  // Палитра персонажа — из референса (это «настоящие» цвета), иначе из всех кадров.
  const palSrc = refS ? [refS] : smalls;
  palette = (+S.palette >= 2 && smalls.length) ? buildPalette(palSrc, +S.palette) : null;
  if (palette) palette.sort((p, q) => (p[0] * 3 + p[1] * 6 + p[2]) - (q[0] * 3 + q[1] * 6 + q[2]));
  if (palette) for (const s of smalls) applyPalette(s, palette);
  const next = new Map();
  for (const o of out) {
    const c = compose(o.s, o.f, S); next.set(o.f.id, c);
    if (o.f.patch) { const x = c.getContext('2d'), id = x.getImageData(0, 0, c.width, c.height); applyPatch(id.data, c.width, c.height, o.f.patch); x.putImageData(id, 0, 0); }
    if (c._clip && !o.f.off) warn.push(`${o.a.name} #${o.i + 1}: персонаж вылезает за кадр`);
  }
  const grew = [...next.keys()].some(k => !processed.has(k));
  processed = next;
  if (grew) renderFrames();
  procRef = refS ? compose(refS, { dx: 0, dy: 0 }, S) : null;
  warnings = warn;
  const keyOf = new Map(); for (const it of out) keyOf.set(it.f.id, cutCache.get(it.f.id + '|' + fingerprint(it.f.src) + '|' + S.tolerance + '|' + S.bgMode)?.key || null);
  artReport = artChecks(P.animations.map(a => ({ name: a.name, loop: a.loop,
    frames: a.frames.filter(f => !f.off && processed.has(f.id)).map(f => { const c = processed.get(f.id); return { data: c.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, c.width, c.height).data, w: c.width, h: c.height, key: keyOf.get(f.id) }; }) })),
  { contentH: S.contentH, palette: S.palette, fit: S.scaleMode !== 'none', flyer: studioFlyer() });
  paintProcessed();
}

// A flyer has no ground line to hold: the game's enemy of this name, or the one it is set to fight like.
function studioFlyer() {
  if (typeof enemyList === 'undefined') return false;
  if (!enemyList) { if (!studioFlyer.asked) { studioFlyer.asked = true; fetch('import/enemies.json').then(r => r.json()).then(j => { enemyList ||= j; scheduleBuild(0); }).catch(() => {}); } return false; }
  const base = typeof sandbox !== 'undefined' ? sandbox.base : '';
  // the same list the practice yard flies by (scripts/run/practice_drills.gd)
  return ['flyer', 'boss_ophanim'].includes((enemyList.find(e => e.id === P.id) || enemyList.find(e => e.id === base))?.behaviour);
}

/* ---------- strip slicing ---------- */
// Ищет отдельные фигуры в картинке-ленте: возвращает их горизонтальные границы.
async function findSegments(src) {
  const img = await loadImage(src), S = P.settings;
  const { w, h, m } = maskImage(img, +S.tolerance || 48, S.bgMode);
  const col = new Uint8Array(w);
  for (let x = 0; x < w; x++) { let c = 0; for (let y = 0; y < h && c < 2; y++) if (m[y * w + x]) c++; col[x] = c >= 2 ? 1 : 0; }
  let segs = [], s = -1;
  for (let x = 0; x <= w; x++) {
    const on = x < w && col[x];
    if (on && s < 0) s = x;
    if (!on && s >= 0) { if (x - s >= Math.max(3, w * 0.01)) segs.push([s, x - 1]); s = -1; }
  }
  return { img, w, h, segs: mergeInnerGaps(segs) };
}
async function sliceStrip(src, n) {
  let { img, w, h, segs } = await findSegments(src);
  while (segs.length > n) {
    let bi = 0, bg = Infinity;
    for (let i = 0; i < segs.length - 1; i++) { const g = segs[i + 1][0] - segs[i][1]; if (g < bg) { bg = g; bi = i; } }
    segs.splice(bi, 2, [segs[bi][0], segs[bi + 1][1]]);
  }
  let cuts, auto = segs.length === n;
  if (auto) cuts = segs.map((sg, i) => [i === 0 ? 0 : Math.round((segs[i - 1][1] + sg[0]) / 2), i === n - 1 ? w : Math.round((sg[1] + segs[i + 1][0]) / 2)]);
  else cuts = [...Array(n)].map((_, i) => [Math.round(i * w / n), Math.round((i + 1) * w / n)]);
  const res = [];
  for (const [x0, x1] of cuts) { const c = mk(x1 - x0, h); c.getContext('2d').drawImage(img, x0, 0, x1 - x0, h, 0, 0, x1 - x0, h); res.push(await normalizeImage(c.toDataURL('image/png'))); }
  return { slices: res, auto };
}

/* ---------- prompts ---------- */
const bgClause = forApi => (forApi && api.transparent)
  ? 'Transparent background, no floor, no shadow.'
  : 'Background: solid flat pure magenta (#FF00FF), perfectly uniform, no gradient, no floor, no shadow.';
// Размер блока для ChatGPT: персонаж в CH «пикселей» занимает ~70% высоты картинки 1024 px.
const blockPx = () => Math.max(4, Math.round(1024 * 0.7 / Math.max(8, +P.settings.contentH)));
const pixelClause = () => `Pixel scale: true low-resolution pixel art. The character is exactly ${P.settings.contentH} art pixels tall. Every art pixel is a uniform square block of exactly ${blockPx()}×${blockPx()} image pixels, all blocks on ONE fixed grid across the whole image, no half-blocks, no smooth gradients inside blocks.`;
function framePrompt(a, i, forApi) {
  const S = P.settings, f = a.frames[i];
  return [
    'Create ONE frame of a 2D game sprite animation. The attached reference image is the exact character design: keep identical proportions, outfit, colors, hair, weapon and silhouette.',
    `Character: ${P.description || 'the character from the reference image'}.`,
    `Style: ${S.style}.`,
    `View: ${S.view}, full body visible, centered, feet on the same ground line near the bottom.`,
    pixelClause(),
    `Animation "${a.name}"${a.notes ? ` (${a.notes})` : ''}, frame ${i + 1} of ${a.frames.length}: ${f.pose || 'the next pose of the motion'}.`,
    bgClause(forApi),
    'Only one character. No text, no labels, no frame border, no motion blur, no effects.',
  ].join('\n');
}
function stripPrompt(a, forApi) {
  const S = P.settings, n = a.frames.length;
  return [
    `Create a sprite strip: exactly ${n} animation frames of the SAME character in ONE horizontal row, left to right. The attached reference image is the exact character design: keep identical proportions, outfit, colors, hair, weapon and silhouette in every frame.`,
    `Character: ${P.description || 'the character from the reference image'}.`,
    `Style: ${S.style}.`,
    `View: ${S.view}, full body in every frame. All frames have the same scale, the feet stand on the same ground line, frames are evenly spaced with clear empty gaps between them and nothing overlaps.`,
    pixelClause(),
    `Animation "${a.name}"${a.notes ? ` (${a.notes})` : ''}:`,
    ...a.frames.map((f, i) => `${i + 1}. ${f.pose || 'next pose of the motion'}`),
    bgClause(forApi),
    'No text, no numbers, no labels, no grid lines, no frame borders, no motion blur.',
  ].join('\n');
}

/* ---------- OpenAI ---------- */
// Who can generate: a key in this browser, the local server's key, or — signed
// in through GitHub — the repository's secret, through the studio-images robot.
const canGenerate = () => !!api.key || Writer.mode === 'local' || Writer.mode === 'github';
async function apiImage(prompt, refs, size) {
  if (!api.key) {
    const req = { prompt, size, quality: api.quality, model: api.model, transparent: api.transparent, fidelity: api.fidelity };
    if (Writer.mode === 'local') return localImage(req, refs);
    if (Writer.mode === 'github') return robotImage(req, refs);
    $('#apiBox').open = true; throw new Error('Войди через GitHub (кнопка справа вверху) или укажи свой ключ OpenAI слева, в блоке «OpenAI API»');
  }
  const send = async withFid => {
    let r;
    if (refs.length) {
      const fd = new FormData();
      fd.append('model', api.model); fd.append('prompt', prompt); fd.append('size', size); fd.append('quality', api.quality); fd.append('n', '1');
      refs.forEach((d, i) => { const b = dataURLtoBlob(d); fd.append('image[]', b, `ref${i}.${(b.type.split('/')[1] || 'png')}`); });
      if (api.transparent) fd.append('background', 'transparent');
      if (withFid) fd.append('input_fidelity', 'high');
      r = await fetch('https://api.openai.com/v1/images/edits', { method: 'POST', headers: { Authorization: 'Bearer ' + api.key }, body: fd });
    } else {
      const body = { model: api.model, prompt, size, quality: api.quality, n: 1 };
      if (api.transparent) body.background = 'transparent';
      r = await fetch('https://api.openai.com/v1/images/generations', { method: 'POST', headers: { Authorization: 'Bearer ' + api.key, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    }
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error?.message || ('HTTP ' + r.status));
    const b64 = j.data?.[0]?.b64_json;
    if (!b64) throw new Error('API не вернул изображение');
    return 'data:image/png;base64,' + b64;
  };
  try { return await send(api.fidelity); }
  catch (e) { if (api.fidelity && /input_fidelity/i.test(e.message)) return await send(false); throw e; }
}
async function genFrame(a, f) {
  if (busy.has(f.id)) return;
  const i = a.frames.indexOf(f), refs = [];
  if (P.reference) refs.push(P.reference);
  if (api.chain) { const prev = a.frames.slice(0, i).reverse().find(x => x.src && !x.off); if (prev) refs.push(prev.src); }
  busy.add(f.id); renderFrames();
  try {
    const src = await apiImage(framePrompt(a, i, true), refs, '1024x1024');
    f.src = await normalizeImage(src); f.baked = false; save(); scheduleBuild(50);
    toast(`${a.name}: кадр ${i + 1} готов`);
  } catch (e) { toast('Ошибка генерации: ' + e.message, 'err'); throw e; }
  finally { busy.delete(f.id); renderFrames(); }
}
const needRef = () => P.reference || confirm('Нет референса: персонаж будет каждый раз выходить другим. Всё равно продолжить?');
async function genAll(a) {
  if (genRunning) { genStop = true; return; }
  if (!canGenerate()) { $('#apiBox').open = true; return toast('Войди через GitHub или укажи ключ OpenAI', 'err'); }
  let targets = a.frames.filter(f => !f.src && !f.off);
  if (!targets.length) { if (!confirm('Все кадры уже заполнены. Перегенерировать все?')) return; targets = a.frames.filter(f => !f.off); }
  if (!needRef() || !confirm(`Будет ${targets.length} платных запросов к API. Продолжить?`)) return;
  genRunning = true; genStop = false; renderAnimBar();
  try { for (const f of targets) { if (genStop) break; try { await genFrame(a, f); } catch { break; } } }
  finally { genRunning = false; renderAnimBar(); }
}
async function genStrip(a) {
  if (!canGenerate()) { $('#apiBox').open = true; return toast('Войди через GitHub или укажи ключ OpenAI', 'err'); }
  if (!needRef()) return;
  const key = 'anim:' + a.id; if (busy.has(key)) return;
  busy.add(key); a.frames.forEach(f => busy.add(f.id)); renderAll();
  try {
    const refs = P.reference ? [P.reference] : [];
    const src = await apiImage(stripPrompt(a, true), refs, '1536x1024');
    await applyStrip(a, src);
  } catch (e) { toast('Ошибка генерации: ' + e.message, 'err'); }
  finally { busy.delete(key); a.frames.forEach(f => busy.delete(f.id)); renderAll(); }
}
async function applyStrip(a, src, n = a.frames.length) {
  while (a.frames.length < n) a.frames.push(newFrame());
  if (a.frames.length > n) a.frames = a.frames.slice(0, n);
  const { slices, auto } = await sliceStrip(src, n);
  slices.forEach((s, i) => { a.frames[i].src = s; a.frames[i].baked = false; a.frames[i].dx = a.frames[i].dy = 0; a.frames[i].sc = 1; });
  save(); renderFrames(); scheduleBuild(50);
  toast(auto ? `Лента разрезана на ${n} кадров по промежуткам` : `Не нашёл ${n} отдельных фигур, разрезал ленту на равные части. Проверь кадры.`, auto ? '' : 'err');
}

/* ---------- export ---------- */
async function exportGodot() {
  const r = await charFiles().catch(e => { toast(e.message, 'err'); return null; }); if (!r) return;
  const zip = new JSZip(), dir = zip.folder(r.name);
  for (const [path, b] of Object.entries(r.files)) dir.file(path.split('/').pop(), b);
  for (const [an, sh] of Object.entries(r.sheets)) for (const [i, f] of sh.frames.entries()) dir.file(`frames/${an}/${an}_${String(i).padStart(2, '0')}.png`, await canvasBlob(processed.get(f.id)));
  dir.file(`${r.name}.json`, JSON.stringify({ name: r.name, cell: { w: r.W, h: r.H }, groundY: r.groundY, tres: r.tres, palette, animations: r.manifest }, null, 2));
  dir.file('README.md', [`# ${r.name}: спрайты для Godot 4`, '',
    `Кадр ${r.W}×${r.H} px, ноги на y = ${r.groundY}. Одна PNG-лента на анимацию, все они в \`${r.tres.split('/').pop()}\` (SpriteFrames).`, '',
    `Файлы кладутся в \`${r.base}\`. AnimatedSprite2D → Sprite Frames → \`${r.tres}\`; origin у ног: centered = true, offset = Vector2(0, ${-(r.H / 2 - (r.H - r.groundY))}). Влево: flip_h = true.`, '',
    ...r.notes, '', '| анимация | кадров | fps | loop |', '|---|---|---|---|', ...r.manifest.map(m => `| ${m.name} | ${m.frames} | ${m.fps} | ${m.loop ? 'да' : 'нет'} |`), ''].join('\n'));
  download(await zip.generateAsync({ type: 'blob' }), `${r.name}_godot.zip`);
  toast(`Экспортировано анимаций: ${r.manifest.length}`);
}

/* ---------- render ---------- */
function renderProjSel() {
  $('#projSel').innerHTML = projects.slice().sort((a, b) => (a.name || '').localeCompare(b.name || ''))
    .map(p => `<option value="${p.id}" ${p.id === P.id ? 'selected' : ''}>${esc(p.name || 'без имени')}</option>`).join('');
}
function renderSide() {
  $('#pName').value = P.name || '';
  $('#pDesc').value = P.description || '';
  $$('[data-s]').forEach(el => { el.value = P.settings[el.dataset.s]; });
  $$('[data-api]').forEach(el => { if (el.type === 'checkbox') el.checked = !!api[el.dataset.api]; else el.value = api[el.dataset.api] ?? ''; });
  renderRef();
}
function renderRef() {
  $('#refImgs').innerHTML = P.reference
    ? `<img class="checker" src="${P.reference}" alt="референс"><canvas id="refProc" class="pixel checker" title="Как референс выглядит после обработки"></canvas>`
    : `<div class="ph">Референс персонажа<br>кликни и нажми Ctrl+V<br>или перетащи файл</div>`;
  $('#refZone').classList.toggle('sel', selected?.type === 'ref');
  paintRef();
}
function renderTabs() {
  $('#tabs').innerHTML = P.animations.map(a => {
    const done = a.frames.filter(f => f.src).length;
    return `<button class="tab ${a.id === P.current ? 'on' : ''}" data-act="tab" data-aid="${a.id}">${esc(a.name)}<span class="cnt">${done}/${a.frames.length}</span></button>`;
  }).join('') +
    `<span style="width:10px"></span><select id="addPreset">${Object.keys(PRESETS).map(k => `<option value="${k}">${PRESET_LABELS[k]}</option>`).join('')}</select><button class="sm" data-act="add-anim">+ Анимация</button>`;
}
function renderAnimBar() {
  const a = curAnim();
  if (!a) { $('#animBar').innerHTML = '<span class="muted">Добавь анимацию</span>'; return; }
  const sb = busy.has('anim:' + a.id);
  $('#animBar').innerHTML = `
    <div class="f"><label>Название</label><input class="name" data-a="name" value="${esc(a.name)}"></div>
    <div class="f"><label>FPS</label><input type="number" min="1" max="60" data-a="fps" value="${a.fps}"></div>
    <div class="f"><label>Масштаб</label><input type="number" step="0.05" min="0.2" max="3" data-a="scale" value="${a.scale}"></div>
    <div class="f"><label>Кадров</label><div class="row" style="margin:0"><button class="sm" data-act="frames-remove">−</button><b>${a.frames.length}</b><button class="sm" data-act="frames-add">+</button></div></div>
    <label class="inline" style="margin-bottom:6px"><input type="checkbox" data-a="loop" ${a.loop ? 'checked' : ''}> Цикл</label>
    <div class="f"><label>Пояснение к движению (в промпт)</label><input class="notes" data-a="notes" value="${esc(a.notes)}"></div>
    <span class="grow"></span>
    <div class="row" style="margin:0">
      <button data-act="anim-dl" title="Скачать все готовые кадры анимации и ленту одним zip">⬇ Кадры (.zip)</button>
      <button data-act="copy-strip" title="Промпт на все кадры одной картинкой, для ChatGPT">📋 Промпт ленты</button>
      <button data-act="import-strip" title="Вставить картинку-ленту из буфера или файла и разрезать на кадры">Импорт ленты</button>
      <button data-act="gen-strip" ${sb || genRunning ? 'disabled' : ''}>${sb ? '…генерирую' : '⚡ Лентой'}</button>
      <button data-act="gen-all" ${sb ? 'disabled' : ''}>${genRunning ? '■ Остановить' : '⚡ Все кадры'}</button>
      <button class="ghost danger" data-act="anim-del" title="Удалить анимацию">🗑</button>
    </div>`;
}
function renderFrames() {
  const a = curAnim();
  if (!a) { $('#frames').innerHTML = ''; return; }
  const S = P.settings;
  $('#frames').innerHTML = a.frames.map((f, i) => `
    <div class="card ${selected?.id === f.id ? 'sel' : ''} ${f.off ? 'off' : ''}" data-fid="${f.id}">
      <div class="ch"><b>#${i + 1}</b><span class="grow"></span>
        <button class="sm ghost" data-act="f-insert" title="Вставить пустой кадр после этого">＋</button>
        ${f.src ? `<button class="sm ghost" data-act="f-dup" title="Дублировать кадр">⧉</button><button class="sm ghost" data-act="f-mirror" title="Отразить по горизонтали">⇋</button><button class="sm ghost" data-act="f-copyto" title="Скопировать кадр в другую анимацию">→</button>` : ''}
        <button class="sm ghost" data-act="f-left" title="Сдвинуть раньше">◀</button>
        <button class="sm ghost" data-act="f-right" title="Сдвинуть позже">▶</button>
        <button class="sm ghost" data-act="f-off" title="${f.off ? 'Включить кадр' : 'Не использовать кадр'}">${f.off ? '◌' : '👁'}</button>
        <button class="sm ghost danger" data-act="f-del" title="Удалить кадр">✕</button>
      </div>
      <div class="imgs">
        <div class="src checker">${f.src ? `<img src="${f.src}" alt="">` : 'кликни и Ctrl+V<br>или перетащи'}</div>
        <canvas class="proc pixel checker" data-pid="${f.id}" width="${S.cellW}" height="${S.cellH}"></canvas>
      </div>
      <textarea data-f="pose" rows="2" placeholder="поза в этом кадре">${esc(f.pose)}</textarea>
      <div class="row" style="margin:4px 0 0"><label class="inline" style="margin:0" title="Сколько держится кадр: 1 — обычно, 2 — вдвое дольше (удар, замах)">Длит. ×<input type="number" data-f="dur" step="0.25" min="0.25" max="8" value="${f.dur ?? 1}" style="width:64px"></label>
        ${processed.has(f.id) ? `<button class="sm" data-act="f-paint" title="Доработать пиксели карандашом">✎${f.patch && Object.keys(f.patch).length ? ' ' + Object.keys(f.patch).length : ''}</button>` : ''}</div>
      <div class="row">
        <button class="sm" data-act="f-gen">⚡ API</button>
        <button class="sm" data-act="f-copy">📋 Промпт</button>
        <button class="sm" data-act="f-paste" title="Вставить картинку из буфера (на iPad — вместо Cmd+V)">📋 Вставить</button>
        <button class="sm" data-act="f-up" title="Файл или фото (на iPad — «Фото» или «Файлы»)">⬆ Файл</button>
        ${processed.has(f.id) ? '<button class="sm" data-act="f-dl" title="Скачать готовый кадр PNG (Shift — исходную картинку)">⬇</button>' : ''}
        ${f.src ? '<button class="sm ghost danger" data-act="f-clear" title="Убрать картинку">⌫</button>' : ''}
      </div>
      ${f.src ? `<div class="row nudge">
        <button data-act="f-nudge" data-d="-1,0,0">←</button><button data-act="f-nudge" data-d="1,0,0">→</button>
        <button data-act="f-nudge" data-d="0,-1,0">↑</button><button data-act="f-nudge" data-d="0,1,0">↓</button>
        <button data-act="f-nudge" data-d="0,0,-1">−</button><button data-act="f-nudge" data-d="0,0,1">+</button>
        <button data-act="f-reset" title="Сбросить сдвиг">⟲</button>
        <span class="v">${f.dx},${f.dy} ×${(+f.sc).toFixed(2)}</span></div>` : ''}
      ${busy.has(f.id) ? '<div class="busy">Генерирую…</div>' : ''}
    </div>`).join('');
  paintProcessed();
}
function paintRef() {
  const c = $('#refProc'); if (!c) return;
  const S = P.settings; c.width = S.cellW; c.height = S.cellH;
  const x = c.getContext('2d'); x.clearRect(0, 0, c.width, c.height);
  if (procRef) x.drawImage(procRef, 0, 0);
}
function paintProcessed() {
  const S = P.settings;
  $$('canvas.proc').forEach(c => {
    if (c.width !== +S.cellW || c.height !== +S.cellH) { c.width = S.cellW; c.height = S.cellH; }
    const x = c.getContext('2d'); x.clearRect(0, 0, c.width, c.height);
    const p = processed.get(c.dataset.pid); if (p) x.drawImage(p, 0, 0);
  });
  paintRef();
  $('#pal').innerHTML = palette ? palette.map(p => `<i style="background:rgb(${p})" title="rgb(${p})"></i>`).join('') : '<span class="muted" style="font-size:12px">выключена</span>';
  // the checks before sending: what is wrong in red, on top; the badge on «→ В игру» counts it
  const bad = artReport.filter(c => c.bad);
  $('#artChecks').innerHTML = artReport.map(c => `<div class="${c.bad ? 'warn' : 'note'}">${c.bad ? '✗' : '✓'} ${esc(c.msg)}</div>`).join('');
  $$('[data-act="chars-game"]').forEach(b => { b.querySelector('.badge')?.remove(); if (bad.length) b.insertAdjacentHTML('beforeend', `<span class="badge" title="${esc(bad.map(c => c.msg).join('\n'))}">${bad.length}</span>`); });
  $('#warns').innerHTML = warnings.slice(0, 6).map(w => w.startsWith('ℹ') ? `<div class="note">${esc(w)}</div>`
    : w.startsWith('FIX') ? `<div class="warn">⚠ ${esc(w.slice(3))}<br><button class="sm primary" data-act="fix-gridfit" style="margin-top:4px">Подогнать под рост ${esc(P.settings.contentH)} px</button></div>`
    : `<div class="warn">⚠ ${esc(w)}</div>`).join('');
  renderFs();
  $$('.tab .cnt').forEach((el, i) => { const a = P.animations[i]; if (a) el.textContent = `${a.frames.filter(f => f.src).length}/${a.frames.length}`; });
}
function renderAll() { trackChange('chars'); renderProjSel(); renderSide(); renderTabs(); renderAnimBar(); renderFrames(); }
function select(sel) {
  selected = sel;
  $$('.card').forEach(c => c.classList.toggle('sel', sel?.type === 'frame' && c.dataset.fid === sel.id));
  $('#refZone').classList.toggle('sel', sel?.type === 'ref');
}

/* ---------- preview ---------- */
const pv = { i: 0, t: 0, play: true, bg: 0, flip: false, onion: false, grid: false };
const PV_BG = ['checker', '#1a1c22', '#6b8fb5', '#e8e8e8'];
const fsOpen = () => !$('#fs').hidden;
const pvAnim = () => pv.chain ? P.animations.find(a => a.id === pv.chain[pv.ci]) || curAnim() : curAnim();
const pvFrames = () => { const a = pvAnim(); return a ? a.frames.filter(f => !f.off && processed.has(f.id)) : []; };
function drawPreview(c, fr, gridScale) {
  const S = P.settings, W = +S.cellW, H = +S.cellH;
  if (c.width !== W || c.height !== H) { c.width = W; c.height = H; }
  const x = c.getContext('2d'); x.clearRect(0, 0, W, H);
  if (!fr.length) return;
  x.save();
  if (pv.flip) { x.translate(W, 0); x.scale(-1, 1); }
  if (pv.onion && fr.length > 1) { x.globalAlpha = 0.3; x.drawImage(processed.get(fr[(pv.i - 1 + fr.length) % fr.length].id), 0, 0); x.globalAlpha = 1; }
  x.drawImage(processed.get(fr[pv.i].id), 0, 0);
  x.restore();
  x.fillStyle = 'rgba(124,195,107,.4)'; x.fillRect(0, H - (+S.bottomPad), W, 1);
}
function loop(ts) {
  requestAnimationFrame(loop);
  if (!P) return;
  const a = pvAnim(), fr = pvFrames();
  $('#prevTitle').textContent = a ? `Превью: ${pv.chain ? pv.chain.map(id => P.animations.find(x => x.id === id)?.name).join(' → ') : a.name}` : 'Превью';
  if (fr.length && pv.play && ts - pv.t >= 1000 / (+a.fps || 8) * (+fr[Math.min(pv.i, fr.length - 1)]?.dur || 1)) {
    pv.t = ts; pv.i++;
    if (pv.i >= fr.length) {
      pv.i = 0;
      // a chain plays each animation once (a loop twice) and moves on
      if (pv.chain && (!a.loop || ++pv.plays >= 2)) { pv.plays = 0; pv.ci = (pv.ci + 1) % pv.chain.length; }
    }
  }
  if (pv.i >= fr.length) pv.i = 0;
  const info = fr.length ? `кадр ${pv.i + 1}/${fr.length} · ${a.fps} fps` : 'нет кадров';
  $('#prevInfo').textContent = info;
  drawPreview($('#prev'), fr);
  if (fsOpen()) {
    drawPreview($('#fsCanvas'), fr);
    $('#fsInfo').textContent = info;
    $$('#fsStrip canvas').forEach(c => c.classList.toggle('on', fr[pv.i]?.id === c.dataset.pid));
  }
}
function applyPvBg() {
  const b = PV_BG[pv.bg];
  for (const c of [$('#prev'), $('#fsCanvas')]) { c.classList.toggle('checker', b === 'checker'); c.style.background = b === 'checker' ? '' : b; }
}
function layoutFs() {
  if (!fsOpen()) return;
  const S = P.settings, W = +S.cellW, H = +S.cellH, st = $('#fsStage'), c = $('#fsCanvas');
  const k = Math.max(1, Math.floor(Math.min((st.clientWidth - 24) / W, (st.clientHeight - 24) / H)));
  c.style.width = W * k + 'px'; c.style.height = H * k + 'px';
  // сетка пикселей поверх (через фон-градиент на размер одного пикселя)
  c.style.backgroundImage = pv.grid ? `linear-gradient(to right, #ffffff14 1px, transparent 1px), linear-gradient(to bottom, #ffffff14 1px, transparent 1px)` : '';
  c.style.backgroundSize = pv.grid ? `${k}px ${k}px` : '';
  if (!pv.grid) applyPvBg();
}
function renderFs() {
  if (!fsOpen()) return;
  const a = curAnim();
  $('#fsAnim').innerHTML = P.animations.map(x => `<option value="${x.id}" ${x.id === P.current ? 'selected' : ''}>${esc(x.name)}</option>`).join('');
  $('#fsFps').value = a?.fps ?? '';
  const S = P.settings;
  $('#fsStrip').innerHTML = pvFrames().map((f, i) => `<canvas class="pixel checker" data-pid="${f.id}" data-i="${i}" width="${S.cellW}" height="${S.cellH}" title="кадр ${i + 1}"></canvas>`).join('');
  $$('#fsStrip canvas').forEach(c => c.getContext('2d').drawImage(processed.get(c.dataset.pid), 0, 0));
  layoutFs();
}
function openFs() { $('#fs').hidden = false; renderFs(); }
function closeFs() { $('#fs').hidden = true; }
function syncPvControls() {
  $$('[data-pv]').forEach(el => { el.checked = !!pv[el.dataset.pv]; });
  for (const id of ['#playBtn', '#fsPlay']) $(id).textContent = pv.play ? '⏸' : '▶';
}
window.addEventListener('resize', layoutFs);

/* ---------- image input ---------- */
async function assignFiles(files, target) {
  files = files.filter(f => f.type.startsWith('image/'));
  if (!files.length) return;
  if (!target) return toast('Сначала кликни по кадру или по референсу', 'err');
  if (target.type === 'ref') {
    P.reference = await normalizeImage(await blobToDataURL(files[0])); save(); renderRef(); scheduleBuild(50); toast('Референс обновлён'); return;
  }
  const { a, f } = findFrame(target.id); if (!a) return;
  if (files.length === 1) {
    const src = await blobToDataURL(files[0]);
    const { w, h, segs } = await findSegments(src);
    if (segs.length >= 2 && w > h * 1.2 && confirm(`Похоже, это лента из ${segs.length} кадров. Разрезать её на кадры анимации «${a.name}»?\n(Отмена — положить картинку целиком в этот кадр)`)) {
      await applyStrip(a, src, segs.length); renderTabs(); renderAnimBar(); return;
    }
  }
  let i = a.frames.indexOf(f);
  for (const file of files) {
    if (i >= a.frames.length) a.frames.push(newFrame());
    const fr = a.frames[i++];
    fr.src = await normalizeImage(await blobToDataURL(file)); fr.baked = false; fr.dx = fr.dy = 0; fr.sc = 1;
  }
  const nextEmpty = a.frames.slice(i - 1).find(x => !x.src) || a.frames[Math.min(i, a.frames.length - 1)];
  save(); renderTabs(); renderFrames(); scheduleBuild(50);
  if (nextEmpty) select({ type: 'frame', id: nextEmpty.id });
}
async function clipboardImage() {
  try {
    for (const item of await navigator.clipboard.read()) {
      const t = item.types.find(t => t.startsWith('image/'));
      if (t) return blobToDataURL(await item.getType(t));
    }
  } catch {}
  return null;
}

/* ---------- events ---------- */
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-act]');
  const card = e.target.closest('.card');
  const strip = e.target.closest('#fsStrip canvas');
  if (strip) { pv.play = false; pv.i = +strip.dataset.i; syncPvControls(); return; }
  if (!b) {
    if (card && !e.target.closest('textarea,input')) select({ type: 'frame', id: card.dataset.fid });
    else if (e.target.closest('#refZone')) select({ type: 'ref' });
    return;
  }
  const act = b.dataset.act, a = curAnim();
  const fid = card?.dataset.fid, F = fid ? findFrame(fid).f : null;
  if (card) select({ type: 'frame', id: fid });
  switch (act) {
    case 'proj-new': {
      const name = prompt('Имя персонажа латиницей (так будут называться файлы):', 'enemy'); if (!name) return;
      P = newProject(slug(name)); projects.push(P); await persist(); selected = null;
      try { localStorage.setItem('ss_last', P.id); } catch {}
      renderAll(); scheduleBuild(0); break;
    }
    case 'proj-del': {
      if (!confirm(`Удалить персонажа «${P.name}» со всеми кадрами из этого браузера? Сначала можно сохранить его в .json.`)) return;
      try { await DB.del(P.id); } catch {}
      projects = projects.filter(p => p.id !== P.id);
      if (!projects.length) { projects.push(newProject('archer')); }
      P = migrate(projects[0]); await persist(); renderAll(); scheduleBuild(0); break;
    }
    case 'proj-export':
      download(new Blob([JSON.stringify(P)], { type: 'application/json' }), `${slug(P.name)}.sprite.json`); break;
    case 'proj-import': {
      const [file] = await pickFiles('.json,application/json', false); if (!file) return;
      let p; try { p = migrate(JSON.parse(await file.text())); } catch (err) { return toast('Не получилось прочитать файл: ' + err.message, 'err'); }
      if (!p.id || !Array.isArray(p.animations)) return toast('Это не файл проекта Sprite Studio', 'err');
      const ex = projects.findIndex(x => x.id === p.id);
      if (ex >= 0) { if (!confirm(`Персонаж «${projects[ex].name}» уже есть. Заменить его версией из файла?`)) { p.id = uid(); projects.push(p); } else projects[ex] = p; }
      else projects.push(p);
      P = p; await persist(); try { localStorage.setItem('ss_last', P.id); } catch {}
      renderAll(); scheduleBuild(0); toast('Проект открыт'); break;
    }
    case 'export-godot': exportGodot().catch(err => toast('Ошибка экспорта: ' + err.message, 'err')); break;
    case 'ref-upload': { const fs = await pickFiles('image/*', false); await assignFiles(fs, { type: 'ref' }); break; }
    case 'ref-paste': { const src = await clipboardImage(); if (!src) { toast('В буфере нет картинки', 'err'); break; } P.reference = await normalizeImage(src); save(); renderRef(); scheduleBuild(50); toast('Референс обновлён'); break; }
    case 'ref-clear': if (P.reference && confirm('Убрать референс?')) { P.reference = null; save(); renderRef(); scheduleBuild(0); } break;
    case 'ref-copy': {
      if (!P.reference) return toast('Референса нет', 'err');
      try { await navigator.clipboard.write([new ClipboardItem({ 'image/png': dataURLtoBlob(await normalizeImage(P.reference)) })]); toast('Референс скопирован, вставь его в ChatGPT'); }
      catch { toast('Браузер не дал скопировать картинку. Перетащи её в ChatGPT мышкой.', 'err'); }
      break;
    }
    case 'tab': P.current = b.dataset.aid; pv.i = 0; save(); selected = null; renderTabs(); renderAnimBar(); renderFrames(); break;
    case 'add-anim': {
      const key = $('#addPreset').value; let name = key === 'custom' ? (prompt('Название анимации (латиницей):', 'special') || '') : key;
      if (!name) return; name = slug(name);
      let n = name, k = 2; while (P.animations.some(x => x.name === n)) n = `${name}${k++}`;
      const an = newAnim(n, key); P.animations.push(an); P.current = an.id; save(); renderTabs(); renderAnimBar(); renderFrames(); break;
    }
    case 'anim-del':
      if (a && confirm(`Удалить анимацию «${a.name}» со всеми кадрами?`)) { P.animations = P.animations.filter(x => x !== a); P.current = P.animations[0]?.id || null; save(); renderAll(); scheduleBuild(0); }
      break;
    case 'frames-add': a.frames.push(newFrame()); save(); renderTabs(); renderAnimBar(); renderFrames(); break;
    case 'frames-remove': {
      if (a.frames.length <= 1) return;
      const last = a.frames[a.frames.length - 1];
      if (last.src && !confirm('У последнего кадра есть картинка. Удалить?')) return;
      a.frames.pop(); save(); renderTabs(); renderAnimBar(); renderFrames(); scheduleBuild(); break;
    }
    case 'copy-strip': copyText(stripPrompt(a, false)); break;
    case 'import-strip': {
      let src = await clipboardImage();
      if (!src) { const [file] = await pickFiles('image/*', false); if (!file) return; src = await blobToDataURL(file); }
      else if (!confirm('В буфере есть картинка. Разрезать её на кадры этой анимации? (Отмена: выбрать файл)')) { const [file] = await pickFiles('image/*', false); if (!file) return; src = await blobToDataURL(file); }
      if (a.frames.some(f => f.src) && !confirm(`Заменить кадры анимации «${a.name}» кадрами из ленты?`)) return;
      let n = a.frames.length;
      const found = (await findSegments(src)).segs.length;
      if (found >= 2 && found !== n && confirm(`Нашёл ${found} фигур, а кадров в анимации ${n}. OK — разрезать на ${found} кадров, Отмена — на ${n}.`)) n = found;
      try { await applyStrip(a, src, n); renderTabs(); renderAnimBar(); } catch (err) { toast('Не получилось разрезать: ' + err.message, 'err'); }
      break;
    }
    case 'gen-strip': genStrip(a); break;
    case 'gen-all': genAll(a); break;
    case 'f-gen': if (needRef()) genFrame(a, F).catch(() => {}); break;
    case 'f-copy': copyText(framePrompt(a, a.frames.indexOf(F), false)); break;
    case 'fix-gridfit': P.settings.scaleMode = 'gridfit'; save(); renderSide(); scheduleBuild(0); toast('Масштаб: «Сетка пикселей + подогнать рост»'); break;
    case 'f-dl': {
      const i = a.frames.indexOf(F) + 1, base = `${slug(P.name)}_${slug(a.name)}_${String(i).padStart(2, '0')}`;
      if (e.shiftKey && F.src) { download(dataURLtoBlob(F.src), `${base}_source.png`); break; }
      const c = processed.get(F.id); if (!c) return toast('Кадр ещё не обработан', 'err');
      download(await canvasBlob(c), `${base}.png`); break;
    }
    case 'anim-dl': {
      const fr = a.frames.filter(f => !f.off && processed.has(f.id)); if (!fr.length) return toast('Нет готовых кадров', 'err');
      const zip = new JSZip(), name = `${slug(P.name)}_${slug(a.name)}`, S = P.settings;
      const strip = mk(S.cellW * fr.length, S.cellH), sx = strip.getContext('2d');
      for (const [k, f] of fr.entries()) { const c = processed.get(f.id); sx.drawImage(c, k * S.cellW, 0); zip.file(`${name}_${String(k + 1).padStart(2, '0')}.png`, await canvasBlob(c)); if (f.src) zip.file(`source/${name}_${String(k + 1).padStart(2, '0')}.png`, dataURLtoBlob(f.src)); }
      zip.file(`${name}_strip.png`, await canvasBlob(strip));
      download(await zip.generateAsync({ type: 'blob' }), `${name}_frames.zip`); toast(`Скачано кадров: ${fr.length}`); break;
    }
    case 'f-up': { const fs = await pickFiles('image/*', true); await assignFiles(fs, { type: 'frame', id: fid }); break; }
    // a tablet has no Cmd+V for a picture: the clipboard read behind a button (Safari asks once with its «Вставить» bubble)
    case 'f-paste': { const src = await clipboardImage(); if (!src) { toast('В буфере нет картинки: в ChatGPT нажми на картинку → «Скопировать», или «⬆ Файл» → Фото', 'err'); break; }
      await assignFiles([new File([dataURLtoBlob(src)], 'clipboard.png', { type: 'image/png' })], { type: 'frame', id: fid }); break; }
    case 'f-clear': F.src = null; F.baked = false; F.dx = F.dy = 0; F.sc = 1; save(); renderTabs(); renderFrames(); scheduleBuild(0); break;
    case 'f-off': F.off = !F.off; save(); renderFrames(); break;
    case 'f-del':
      if (a.frames.length <= 1) return;
      if (F.src && !confirm('Удалить кадр с картинкой?')) return;
      a.frames = a.frames.filter(x => x !== F); save(); renderTabs(); renderAnimBar(); renderFrames(); scheduleBuild(); break;
    case 'f-insert': { const i = a.frames.indexOf(F); a.frames.splice(i + 1, 0, newFrame()); save(); renderTabs(); renderAnimBar(); renderFrames(); break; }
    case 'f-dup': {
      const i = a.frames.indexOf(F), c = { ...JSON.parse(JSON.stringify(F)), id: uid() };
      a.frames.splice(i + 1, 0, c); save(); renderTabs(); renderAnimBar(); renderFrames(); scheduleBuild(0); break;
    }
    case 'f-mirror': {
      const img = await loadImage(F.src), c = mk(img.width, img.height), x = c.getContext('2d');
      x.translate(img.width, 0); x.scale(-1, 1); x.drawImage(img, 0, 0);
      F.src = c.toDataURL('image/png'); F.patch = {}; F.dx = -F.dx;  // touch-ups were for the other side
      save(); renderFrames(); scheduleBuild(0); toast('Кадр отражён'); break;
    }
    case 'f-copyto': {
      const others = P.animations.filter(x => x !== a);
      if (!others.length) return toast('Других анимаций нет — добавь через «+ Анимация»', 'err');
      const name = prompt(`В какую анимацию скопировать кадр? (${others.map(x => x.name).join(', ')})`, others[0].name);
      const to = others.find(x => x.name === name?.trim()); if (!to) return;
      const c = { ...JSON.parse(JSON.stringify(F)), id: uid() }, empty = to.frames.find(x => !x.src);
      if (empty) Object.assign(empty, { ...c, id: empty.id, pose: empty.pose || c.pose }); else to.frames.push(c);
      save(); renderTabs(); scheduleBuild(0); toast(`Скопировано в «${to.name}»`); break;
    }
    case 'f-left': case 'f-right': {
      const i = a.frames.indexOf(F), j = i + (act === 'f-left' ? -1 : 1);
      if (j < 0 || j >= a.frames.length) return;
      [a.frames[i], a.frames[j]] = [a.frames[j], a.frames[i]]; save(); renderFrames(); break;
    }
    case 'f-nudge': { const [dx, dy, ds] = b.dataset.d.split(',').map(Number); nudge(F, dx, dy, ds); break; }
    case 'f-reset': F.dx = F.dy = 0; F.sc = 1; save(); renderFrames(); scheduleBuild(0); break;
    case 'prev-play': pv.play = !pv.play; syncPvControls(); break;
    case 'prev-bg': pv.bg = (pv.bg + 1) % PV_BG.length; pv.grid = false; syncPvControls(); applyPvBg(); layoutFs(); break;
    case 'fs-open': openFs(); break;
    case 'fs-close': closeFs(); break;
    case 'fs-step': { const n = pvFrames().length; if (!n) return; pv.play = false; pv.i = (pv.i + +b.dataset.d + n) % n; syncPvControls(); break; }
    case 'side-toggle': {
      const off = $('.layout').classList.toggle('noside');
      $('#bgLayout').classList.toggle('noside', off);
      try { localStorage.setItem('ss_noside', off ? '1' : ''); } catch {}
      break;
    }
  }
});
function nudge(F, dx, dy, ds) {
  F.dx += dx; F.dy += dy; F.sc = Math.max(0.3, Math.min(3, +(F.sc + ds * 0.03).toFixed(2)));
  save();
  const v = $(`.card[data-fid="${F.id}"] .v`); if (v) v.textContent = `${F.dx},${F.dy} ×${F.sc.toFixed(2)}`;
  scheduleBuild(ds ? 120 : 30);
}
document.addEventListener('keydown', e => {
  if (e.target.closest?.('input,textarea,select')) return;
  if (mode !== 'chars') return;
  if (fsOpen()) {
    const n = pvFrames().length;
    if (e.key === 'Escape' || e.key === 'f' || e.key === 'а') closeFs();
    else if (e.key === ' ') { pv.play = !pv.play; syncPvControls(); }
    else if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight') && n) { pv.play = false; pv.i = (pv.i + (e.key === 'ArrowLeft' ? -1 : 1) + n) % n; syncPvControls(); }
    else return;
    e.preventDefault(); return;
  }
  if (e.key === 'f' || e.key === 'а') { e.preventDefault(); openFs(); return; }
  if (selected?.type !== 'frame') return;
  const { f } = findFrame(selected.id); if (!f?.src) return;
  const map = { ArrowLeft: [-1, 0, 0], ArrowRight: [1, 0, 0], ArrowUp: [0, -1, 0], ArrowDown: [0, 1, 0], '+': [0, 0, 1], '=': [0, 0, 1], '-': [0, 0, -1] };
  const d = map[e.key]; if (!d) return;
  e.preventDefault(); nudge(f, ...d);
});
const PROC_KEYS = new Set(['cellW', 'cellH', 'contentH', 'bottomPad', 'palette', 'tolerance', 'pixelSize', 'bgMode', 'scaleMode', 'anchor', 'downMode']);
document.addEventListener('input', e => {
  const t = e.target;
  if (t.dataset.pv) { pv[t.dataset.pv] = t.checked; syncPvControls(); if (t.dataset.pv === 'grid') layoutFs(); return; }
  if (t.id === 'fsChain') {
    const ids = t.value.split(/[,\s→>]+/).map(n => P.animations.find(a => a.name === n.trim())?.id).filter(Boolean);
    Object.assign(pv, { chain: ids.length > 1 ? ids : null, ci: 0, plays: 0, i: 0 }); return;
  }
  if (t.id === 'fsFps') { const a = curAnim(); if (a) { a.fps = +t.value || 1; save(); renderAnimBar(); } return; }
  if (t.id === 'fsAnim') { P.current = t.value; pv.i = 0; save(); selected = null; renderTabs(); renderAnimBar(); renderFrames(); renderFs(); return; }
  if (t.dataset.s) { P.settings[t.dataset.s] = t.type === 'number' ? (t.value === '' ? 0 : +t.value) : t.value; save(); if (PROC_KEYS.has(t.dataset.s)) scheduleBuild(); }
  else if (t.dataset.api) { api[t.dataset.api] = t.type === 'checkbox' ? t.checked : t.value.trim(); saveApi(); }
  else if (t.id === 'pName') { P.name = t.value; save(); renderProjSel(); }
  else if (t.id === 'pDesc') { P.description = t.value; save(); }
  else if (t.dataset.a) {
    const a = curAnim(), k = t.dataset.a;
    a[k] = t.type === 'checkbox' ? t.checked : t.type === 'number' ? +t.value : t.value; save();
    if (k === 'scale') scheduleBuild();
    if (k === 'name') renderTabs();
  }
  else if (t.dataset.f) { const { f } = findFrame(t.closest('[data-fid]').dataset.fid); if (f) { f[t.dataset.f] = t.type === 'number' ? Math.max(0.25, +t.value || 1) : t.value; save(); } }
});
$('#projSel').addEventListener('change', e => {
  const p = projects.find(x => x.id === e.target.value); if (!p) return;
  P = migrate(p); selected = null; pv.i = 0; processed = new Map(); procRef = null;
  try { localStorage.setItem('ss_last', P.id); } catch {}
  renderAll(); scheduleBuild(0);
});
document.addEventListener('paste', e => {
  const files = [...(e.clipboardData?.items || [])].filter(i => i.type.startsWith('image/')).map(i => i.getAsFile()).filter(Boolean);
  if (!files.length) return;
  e.preventDefault();
  if (mode === 'bg') { bgAddFiles(files).catch(err => toast(err.message, 'err')); return; }
  if (mode === 'rig') { blobToDataURL(files[0]).then(rigLoadSheet).catch(err => toast(err.message, 'err')); return; }
  if (mode !== 'chars') return;
  assignFiles(files, selected).catch(err => toast(err.message, 'err'));
});
document.addEventListener('dragover', e => { if (e.dataTransfer?.types?.includes('Files')) e.preventDefault(); });
document.addEventListener('drop', e => {
  if (!e.dataTransfer?.files?.length) return;
  e.preventDefault();
  if (mode === 'bg') { bgAddFiles([...e.dataTransfer.files]).catch(err => toast(err.message, 'err')); return; }
  if (mode === 'snd') {
    const f = [...e.dataTransfer.files].find(x => /^audio\/|\.(wav|mp3|ogg)$/i.test(x.type + ' ' + x.name)), ent = sndSel && sndEntry(sndSel);
    if (f && ent && sndTake) sndSetSrc(ent, sndTake, f); else toast('Выбери звук и вариант, потом перетащи файл', 'err');
    return;
  }
  if (mode !== 'chars') return;
  const card = e.target.closest('.card');
  const target = card ? { type: 'frame', id: card.dataset.fid } : e.target.closest('#refZone') ? { type: 'ref' } : null;
  if (target) select(target);
  assignFiles([...e.dataTransfer.files], target).catch(err => toast(err.message, 'err'));
});
window.addEventListener('beforeunload', () => { if (saveTimer) persist(); });

// ?import=путь — файл проекта или список файлов (JSON-массив путей).
// Lay copies from the game (or shared projects) over what this browser has,
// without losing her work: lib.js mergeDecision says take, keep or ask.
async function mergeIncoming(list, have, put, fix) {
  let kept = 0; const conflicts = [];
  for (const raw of list) {
    const local = have.find(x => x.id === raw.id), d = mergeDecision(local, raw);
    if (d === 'take') await put(fix({ ...raw, base: raw.rev, dirty: false }));
    else if (d === 'keep') kept++;
    else conflicts.push(raw);
  }
  if (conflicts.length) {
    const names = conflicts.map(c => c.name || c.id).join(', ');
    if (confirm(`В игре изменились: ${names}.\nУ тебя в них свои правки.\n\nOK — взять версию из игры (твои правки пропадут)\nОтмена — оставить свои`))
      for (const raw of conflicts) await put(fix({ ...raw, base: raw.rev, dirty: false }));
    else kept += conflicts.length;
  }
  return kept;
}
async function importFromUrl(url) {
  try {
    const data = await (await fetch(url)).json();
    const files = Array.isArray(data) ? data.map(f => new URL(f, new URL(url, location.href)).href) : null;
    const list = files ? await Promise.all(files.map(async f => (await fetch(f)).json())) : [data];
    const chars = list.filter(r => r.kind !== 'bg'), rooms = list.filter(r => r.kind === 'bg');
    const kept = await mergeIncoming(chars, projects, async p => { const ex = projects.findIndex(x => x.id === p.id); if (ex >= 0) projects[ex] = p; else projects.push(p); P = p; await persist(); }, migrate);
    if (chars.length) P = projects.find(p => p.id === chars[0].id) || P;
    const keptBg = await mergeIncoming(rooms, bgs, b => bgUpsert(b), migrateBg);
    if (rooms.length) { const first = rooms.find(r => r.name === 'graveyard') || rooms[0]; BG = bgs.find(b => b.id === first.id); setMode('bg'); }
    toast((chars.length ? `Персонажей из игры: ${chars.length}` : `Задников из игры: ${rooms.length}`) + (kept + keptBg ? ` · твои правки сохранены: ${kept + keptBg}` : ''));
  } catch (e) { toast('Не получилось импортировать: ' + e.message, 'err'); }
}
