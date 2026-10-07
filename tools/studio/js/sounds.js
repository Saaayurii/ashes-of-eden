/* Sprite Studio — the sounds tab and the audio helpers the cutscenes use too. Plain scripts share one global scope; index.html loads them in order. */
'use strict';

/* ======================= ЗВУК: общее ======================= */
let actx = null;
const AC = () => actx || (actx = new (window.AudioContext || window.webkitAudioContext)());
const bufCache = new Map();
async function decodeUrl(url) {
  if (bufCache.has(url)) return bufCache.get(url);
  const p = (async () => {
    const r = await fetch(url); if (!r.ok) throw new Error('файл не найден');
    return await AC().decodeAudioData(await r.arrayBuffer());
  })();
  bufCache.set(url, p);
  try { return await p; } catch (e) { bufCache.delete(url); throw e; }
}
let previewSrc = null;
function stopPreview() { try { previewSrc?.stop(); } catch {} previewSrc = null; }
function playBuf(buf, db = 0, exclusive = true) {
  if (exclusive) stopPreview();
  const s = AC().createBufferSource(), g = AC().createGain();
  s.buffer = buf; g.gain.value = Math.pow(10, db / 20); s.connect(g).connect(AC().destination); s.start();
  if (exclusive) previewSrc = s;
  return s;
}
// Обрезка, громкость, появление/затухание, нормализация — прямо по сэмплам.
function renderEdits(buf, e = {}) {
  const sr = buf.sampleRate, ch = buf.numberOfChannels;
  const s0 = Math.max(0, Math.floor((e.start || 0) * sr)), s1 = Math.min(buf.length, e.end ? Math.floor(e.end * sr) : buf.length);
  const n = Math.max(1, s1 - s0), out = AC().createBuffer(ch, n, sr), g = Math.pow(10, (e.gain || 0) / 20);
  const fi = Math.floor((e.fadeIn || 0) / 1000 * sr), fo = Math.floor((e.fadeOut || 0) / 1000 * sr);
  let peak = 0;
  for (let c = 0; c < ch; c++) {
    const src = buf.getChannelData(c), d = out.getChannelData(c);
    for (let i = 0; i < n; i++) {
      let v = src[s0 + i] * g;
      if (fi && i < fi) v *= i / fi;
      if (fo && i > n - fo) v *= (n - i) / fo;
      d[i] = v; const a = Math.abs(v); if (a > peak) peak = a;
    }
  }
  if (e.normalize && peak > 0) { const k = 0.89 / peak; for (let c = 0; c < ch; c++) { const d = out.getChannelData(c); for (let i = 0; i < n; i++) d[i] *= k; } }
  out._peak = e.normalize ? 0.89 : peak;
  return out;
}
function encodeMp3(buf, kbps = 160) {
  if (typeof lamejs === 'undefined') throw new Error('не загрузилась библиотека MP3 (нужен интернет)');
  const ch = Math.min(2, buf.numberOfChannels), enc = new lamejs.Mp3Encoder(ch, buf.sampleRate, kbps);
  const L = toI16(buf.getChannelData(0)), R = ch > 1 ? toI16(buf.getChannelData(1)) : null, parts = [], B = 1152;
  for (let i = 0; i < L.length; i += B) {
    const m = ch > 1 ? enc.encodeBuffer(L.subarray(i, i + B), R.subarray(i, i + B)) : enc.encodeBuffer(L.subarray(i, i + B));
    if (m.length) parts.push(new Uint8Array(m));
  }
  const e = enc.flush(); if (e.length) parts.push(new Uint8Array(e));
  return new Blob(parts, { type: 'audio/mpeg' });
}

/* ======================= ВКЛАДКА «ЗВУКИ» ======================= */
let sndLib = null, sndMods = new Map(), sndSel = null, sndTake = null, sndCat = 'sfx', recorder = null;
const CAT_LABEL = { sfx: 'Эффекты', music: 'Музыка', voice: 'Озвучка' };
async function loadSndLib() {
  if (sndLib) return sndLib;
  try { sndLib = await (await fetch('import/audio.json')).json(); } catch { sndLib = []; }
  return sndLib;
}
async function sndInit() {
  try { for (const m of (await DB.all('sounds')) || []) sndMods.set(m.id, m); } catch {}
}
let sndSaveTimer = null;
function saveSnd(m) { m.updated = Date.now(); trackChange('snd'); clearTimeout(sndSaveTimer); sndSaveTimer = setTimeout(() => { if (dbOk) DB.put(m, 'sounds').catch(() => {}); }, 300); }
// Звук = библиотечная запись + наши изменения поверх (замены вариантов, новые варианты).
function sndEntry(key) {
  const lib = sndLib?.find(e => e.key === key), mod = sndMods.get(key);
  if (!lib && !mod) return null;
  const base = lib ? JSON.parse(JSON.stringify(lib)) : { key, cat: mod.cat, name: mod.name, locale: mod.locale, takes: [], isNew: true };
  const takes = base.takes.map(t => ({ ...t, orig: true }));
  for (const [stem, t] of Object.entries(mod?.takes || {})) {
    const ex = takes.find(x => x.stem === stem);
    if (ex) Object.assign(ex, { mod: t }); else takes.push({ stem, ext: targetExt(base.cat), orig: false, mod: t });
  }
  return { ...base, takes, mod };
}
const targetExt = cat => cat === 'sfx' ? 'wav' : 'mp3';
const takeChanged = t => t.mod && (t.mod.src || !isDefaultEdit(t.mod.edits));
function sndMod(entry) {
  let m = sndMods.get(entry.key);
  if (!m) { m = { id: entry.key, cat: entry.cat, name: entry.name, locale: entry.locale, isNew: !!entry.isNew, takes: {} }; sndMods.set(m.id, m); }
  return m;
}
async function takeBuffer(t) {
  if (t.mod?.src) return decodeUrl(t.mod.src);
  if (t.url) return decodeUrl(A(t.url));
  throw new Error('у варианта нет звука — загрузи файл или запиши');
}
function renderSndList() {
  if (!sndLib) return;
  $$('[data-act="snd-cat"]').forEach(b => b.classList.toggle('on', b.dataset.c === sndCat));
  $('#sndLocaleWrap').style.display = sndCat === 'voice' ? '' : 'none';
  const q = $('#sndSearch').value.trim().toLowerCase(), loc = $('#sndLocale').value, only = $('#sndOnlyMod').checked;
  const keys = new Set(sndLib.filter(e => e.cat === sndCat && (sndCat !== 'voice' || e.locale === loc)).map(e => e.key));
  for (const m of sndMods.values()) if (m.cat === sndCat && (sndCat !== 'voice' || m.locale === loc)) keys.add(m.id);
  let list = [...keys].map(sndEntry).filter(Boolean);
  if (q) list = list.filter(e => e.name.toLowerCase().includes(q) || (e.text || '').toLowerCase().includes(q));
  if (only) list = list.filter(e => e.takes.some(takeChanged));
  list.sort((a, b) => a.name.localeCompare(b.name));
  $('#sndCount').textContent = `${list.length}`;
  $('#sndList').innerHTML = list.slice(0, 500).map(e => {
    const ch = e.takes.some(takeChanged);
    return `<div class="irow ${e.key === sndSel ? 'on' : ''}" data-act="snd-sel" data-key="${esc(e.key)}">
      <button class="sm ghost" data-act="snd-quick" title="Прослушать">▶</button>
      <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(e.name)}${e.text ? `<br><span class="muted">${esc(e.text.slice(0, 60))}</span>` : ''}</span>
      ${e.takes.length > 1 ? `<span class="muted">×${e.takes.length}</span>` : ''}${ch ? '<span class="badge">изм.</span>' : ''}${e.isNew ? '<span class="badge new">нов.</span>' : ''}
    </div>`;
  }).join('') || '<div class="muted" style="padding:8px">Ничего не найдено</div>';
}
function usedIn(name) {
  if (!cutData) return [];
  const all = [...(cuts.length ? cuts : cutData.cutscenes)];
  return all.filter(c => c.steps.some(s => (s.do === 'sound' && s.name === name) || (s.do === 'title' && s.sound === name) || (s.do === 'music' && s.name === name))).map(c => c.id);
}
async function renderSndMain() {
  const e = sndSel && sndEntry(sndSel), el = $('#sndMain');
  if (!e) { el.innerHTML = `<div class="bgempty" style="position:static;padding:60px"><div>Выбери звук слева</div><div class="note">Эффекты: имя_1, имя_2 — это варианты одного звука, игра берёт случайный. Голоса врагов: &lt;враг&gt;_alert / _attack / _hurt / _death.</div></div>`; return; }
  if (!sndTake || !e.takes.find(t => t.stem === sndTake)) sndTake = e.takes[0]?.stem || null;
  const dir = e.cat === 'voice' ? `assets/audio/voice/${e.locale}/` : `assets/audio/${e.cat}/`;
  const used = e.cat !== 'voice' ? usedIn(e.name) : [];
  el.innerHTML = `
    <div class="sndhead">
      <h2 style="margin:0">${esc(e.name)}</h2>
      <div class="note">${CAT_LABEL[e.cat]}${e.locale ? ' · ' + e.locale : ''} · ${esc(dir)}${e.moods?.length ? ' · настроения: ' + esc(e.moods.join(', ')) : ''}${used.length ? ' · в катсценах: ' + esc(used.join(', ')) : ''}</div>
      ${e.text ? `<div class="quote">«${esc(e.text)}»</div>` : ''}
    </div>
    <div class="takes">${e.takes.map(t => `
      <div class="take ${t.stem === sndTake ? 'on' : ''}" data-act="snd-take" data-stem="${esc(t.stem)}">
        <b>${esc(t.stem)}</b><span class="muted">.${t.orig && !takeChanged(t) ? t.ext : targetExt(e.cat)}</span>
        ${takeChanged(t) ? '<span class="badge">изменён</span>' : ''}${!t.orig ? '<span class="badge new">новый</span>' : ''}
        <span class="grow"></span>
        ${t.orig ? `<button class="sm" data-act="snd-play-orig" title="Оригинал из игры">▶ оригинал</button>` : ''}
        ${t.mod?.src || (t.orig && t.mod) ? `<button class="sm" data-act="snd-play-cur" title="С изменениями">▶ сейчас</button>` : ''}
        <button class="sm" data-act="snd-up" title="Заменить своим файлом (wav, mp3, ogg)">⬆ Файл</button>
        <button class="sm" data-act="snd-rec">${recorder?.stem === t.stem ? '■ Стоп' : '● Запись'}</button>
        ${takeChanged(t) ? `<button class="sm ghost" data-act="snd-reset" title="Вернуть оригинал">⟲</button>` : ''}
        ${!t.orig ? `<button class="sm ghost danger" data-act="snd-del-take">✕</button>` : ''}
      </div>`).join('')}
    </div>
    <div class="row">${e.cat === 'sfx' ? '<button class="sm" data-act="snd-add-take">+ Вариант</button>' : ''}
      <button class="sm ghost" data-act="snd-stop">■ Тишина</button></div>
    <div id="sndEditor"></div>`;
  renderSndEditor(e);
}
let sndWave = null;  // the clip under the trim handles
// Trim by dragging on the waveform: the nearer handle follows the pointer.
document.addEventListener('pointerdown', e => {
  const c = e.target.closest?.('#wave'); if (!c || !sndWave) return;
  const ent = sndEntry(sndSel), m = sndMod(ent);
  m.takes[sndWave.stem] ||= { src: null, edits: { ...EDIT_DEFAULT } };
  const ed = m.takes[sndWave.stem].edits ||= { ...EDIT_DEFAULT }, dur = sndWave.buf.duration;
  const at = ev => Math.max(0, Math.min(dur, (ev.offsetX / c.clientWidth) * dur));
  const t0 = at(e), end = ed.end || dur, key = Math.abs(t0 - (ed.start || 0)) <= Math.abs(t0 - end) ? 'start' : 'end';
  const move = ev => {
    const t = +at(ev).toFixed(2);
    if (key === 'start') ed.start = Math.min(t, (ed.end || dur) - 0.02); else ed.end = Math.max(t, (ed.start || 0) + 0.02) >= dur - 0.005 ? 0 : Math.max(t, (ed.start || 0) + 0.02);
    const f = document.querySelector(`[data-se="${key}"]`); if (f) f.value = ed[key];
    drawWave(sndWave.buf, ed);
  };
  move(e); c.setPointerCapture(e.pointerId);
  c.onpointermove = move;
  c.onpointerup = () => { c.onpointermove = c.onpointerup = null; saveSnd(m); renderSndList(); };
});
async function renderSndEditor(e) {
  const box = $('#sndEditor'); const t = e.takes.find(x => x.stem === sndTake);
  if (!box || !t) return;
  let buf;
  try { buf = await takeBuffer(t); } catch (err) { box.innerHTML = `<div class="note">${esc(err.message)}</div>`; return; }
  const ed = { ...EDIT_DEFAULT, ...(t.mod?.edits || {}) }, dur = buf.duration;
  box.innerHTML = `
    <h3 style="margin-top:14px">Правка: ${esc(t.stem)} <span class="muted">· ${dur.toFixed(2)} с · ${buf.sampleRate} Гц · ${buf.numberOfChannels === 1 ? 'моно' : 'стерео'}</span></h3>
    <canvas id="wave" class="wave"></canvas>
    <div class="grid4">
      <div><label>Начало, с</label><input type="number" step="0.01" min="0" max="${dur.toFixed(2)}" data-se="start" value="${ed.start}"></div>
      <div><label>Конец, с (0 = до конца)</label><input type="number" step="0.01" min="0" max="${dur.toFixed(2)}" data-se="end" value="${ed.end}"></div>
      <div><label>Громкость, дБ</label><input type="number" step="0.5" min="-40" max="24" data-se="gain" value="${ed.gain}"></div>
      <div><label>Появление, мс</label><input type="number" step="10" min="0" data-se="fadeIn" value="${ed.fadeIn}"></div>
      <div><label>Затухание, мс</label><input type="number" step="10" min="0" data-se="fadeOut" value="${ed.fadeOut}"></div>
      <div><label>&nbsp;</label><label class="inline"><input type="checkbox" data-se="normalize" ${ed.normalize ? 'checked' : ''}> Выровнять громкость</label></div>
    </div>
    <div class="row"><button data-act="snd-play-edit">▶ Прослушать с правками</button><span class="muted" id="sndPeak"></span></div>`;
  sndWave = { buf, stem: t.stem };
  drawWave(buf, ed);
}
function drawWave(buf, ed) {
  const c = $('#wave'); if (!c) return;
  const W = c.clientWidth || 600, H = 110; c.width = W; c.height = H;
  const x = c.getContext('2d'), d = buf.getChannelData(0), step = Math.max(1, Math.floor(d.length / W));
  x.fillStyle = '#101116'; x.fillRect(0, 0, W, H);
  x.fillStyle = '#7cc36b';
  for (let i = 0; i < W; i++) {
    let mn = 1, mx = -1; for (let j = i * step, e = Math.min(d.length, j + step); j < e; j++) { const v = d[j]; if (v < mn) mn = v; if (v > mx) mx = v; }
    x.fillRect(i, (1 - mx) * H / 2, 1, Math.max(1, (mx - mn) * H / 2));
  }
  const dur = buf.duration, a = (ed.start || 0) / dur * W, b = (ed.end ? ed.end / dur : 1) * W;
  x.fillStyle = 'rgba(0,0,0,.6)'; x.fillRect(0, 0, a, H); x.fillRect(b, 0, W - b, H);
  x.fillStyle = '#e0b04a'; x.fillRect(a, 0, 1, H); x.fillRect(b - 1, 0, 1, H);
  const out = renderEdits(buf, ed), pk = $('#sndPeak');
  if (pk) pk.textContent = `пик ${(20 * Math.log10(out._peak || 1e-9)).toFixed(1)} дБ${out._peak > 1 ? ' — будет перегруз, убавь громкость' : ''} · длина ${out.duration.toFixed(2)} с`;
}
async function sndSetSrc(e, stem, blob) {
  const src = await blobToDataURL(blob);
  try { await decodeUrl(src); } catch { return toast('Браузер не смог прочитать этот звук. Нужен wav, mp3 или ogg.', 'err'); }
  const m = sndMod(e); m.takes[stem] = { src, edits: { ...EDIT_DEFAULT } }; saveSnd(m);
  sndTake = stem; renderSndList(); renderSndMain(); toast(`${stem}: заменён`);
}
async function toggleRecord(e, stem) {
  if (recorder) { recorder.rec.stop(); return; }
  let stream;
  try { stream = await navigator.mediaDevices.getUserMedia({ audio: true }); } catch { return toast('Нет доступа к микрофону', 'err'); }
  const rec = new MediaRecorder(stream), chunks = [];
  rec.ondataavailable = ev => chunks.push(ev.data);
  rec.onstop = async () => { stream.getTracks().forEach(t => t.stop()); recorder = null; await sndSetSrc(e, stem, new Blob(chunks, { type: rec.mimeType })); };
  recorder = { rec, stem }; rec.start(); renderSndMain(); toast('Идёт запись… нажми «■ Стоп»');
}
async function exportSounds() {
  if (typeof JSZip === 'undefined') return toast('Нет zip-библиотеки (нужен интернет)', 'err');
  const r = await soundFiles().catch(e => { toast(e.message, 'err'); return null; }); if (!r) return;
  const zip = new JSZip();
  for (const [path, b] of Object.entries(r.files)) zip.file(path, b);
  zip.file('README.md', ['# Звуки для Ashes of Eden', '', 'Файлы разложены по путям игры.', '', ...r.rows.map(x => '- ' + x), '',
    r.del.length ? '## Удалить (со своими .import)\n' + [...new Set(r.del)].map(x => '- ' + x).join('\n') : '', '', ...r.notes].join('\n'));
  download(await zip.generateAsync({ type: 'blob' }), 'sounds_godot.zip');
  toast(`Экспортировано звуков: ${r.rows.length}`);
}
