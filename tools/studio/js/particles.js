/* Sprite Studio — particles on any action (data/action_fx.json, scripts/fx/action_fx.gd).
 * Pick a body (Elian or a creature) and a trigger — one of its animations, or an event the
 * game names (step, jump, land, roll, wake) — and dress it with emitters: what flies (dust,
 * puff, sparkle, ash, debris, ring, flash), from where on the body, how many, what colour, and
 * when (the animation's start, some of its frames, or every so often). The preview plays the
 * body's own strip and throws a likeness of what Fx throws in the game. */
'use strict';

const PFX = { data: null, rules: null, body: 0, trigger: null, sel: 0, parts: [], clock: 0, last: 0, raf: 0, lastFrame: -1, every: {}, nextEvent: 0 };
const PFX_KIND = { dust: 'Пыль', puff: 'Облачко', sparkle: 'Искры', ash: 'Пепел, угли', debris: 'Осколки', ring: 'Кольцо', flash: 'Вспышка' };
const PFX_AT = { feet: 'из-под ног', body: 'от тела', head: 'от головы', hand: 'из руки', back: 'за спиной' };
const PFX_WHEN = { start: 'в начале', frames: 'на кадрах', every: 'всё время, каждые …' };
const PFX_EVENT = { step: 'Шаг (каждый шаг при беге)', jump: 'Прыжок', land: 'Приземление', roll: 'Перекат', wake: 'Пробуждение' };
// what the body is doing when the game sends the event, for the preview
const PFX_EVENT_ANIM = { step: 'run', jump: 'jump', land: 'land', roll: 'roll', wake: 'wake' };

async function pfxLoad() {
  if (PFX.data) return;
  PFX.data = await (await fetch('import/action_fx.json')).json();
  PFX.rules = structuredClone(PFX.data.rules);
  try { const saved = JSON.parse(localStorage.getItem('ss_pfx') || 'null'); if (saved) PFX.rules = saved; } catch {}
}
const pfxSave = () => { try { localStorage.setItem('ss_pfx', JSON.stringify(PFX.rules)); } catch {} };
const pfxDirty = () => JSON.stringify(PFX.rules) !== JSON.stringify(PFX.data.rules);
const pfxBody = () => PFX.data.bodies[PFX.body];
const pfxList = () => (PFX.rules[pfxBody().key] || {})[PFX.trigger] || [];
const pfxIsEvent = t => t in PFX_EVENT;

/* ---------- where things leave the body (ActionFx.anchors, as each body sets them) ---------- */
function pfxStage(W, H) {
  const ground = Math.round(H * 0.7), b = pfxBody(), x = Math.round(W * 0.42);
  if (b.hero) return { ground, origin: [x, ground - 14], anchors: { feet: [0, 14], body: [0, -10], head: [0, -24], hand: [12, -12], back: [-6, 6] } };
  const s = +b.body.scale || 1, top = 12 - b.body.cell[1] * s + (+b.body.pad_y || 0) * s;
  return { ground, origin: [x, ground - 11], anchors: { feet: [0, 11], body: [0, (top + 11) / 2], head: [0, top + 6], hand: [12, -14], back: [-6, 4] } };
}

/* ---------- a likeness of Fx ---------- */
function pfxColor(c, fallback) {
  const h = String(c || fallback).replace('#', ''), n = parseInt(h.slice(0, 6), 16), a = h.length >= 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1;
  return [n >> 16 & 255, n >> 8 & 255, n & 255, a];
}
function pfxEmit(spec, st) {
  if (Math.random() > (spec.chance ?? 1)) return;
  const a = st.anchors[spec.at || 'feet'] || st.anchors.feet, off = spec.offset || [0, 0];
  const x = st.origin[0] + a[0] + off[0], y = st.origin[1] + a[1] + off[1], n = Math.max(1, +spec.count || 6), size = +spec.size || 0;
  const add = p => PFX.parts.push({ t: 0, ...p });
  const r = (lo, hi) => lo + Math.random() * (hi - lo);
  switch (spec.fx || 'dust') {
    case 'dust': { const d = spec.dir || [0, -1], c = pfxColor(spec.color, '#9e8f80bf');
      for (let i = 0; i < n; i++) add({ x: x + r(-4, 4), y, vx: d[0] * r(20, 55) + r(-12, 12), vy: d[1] * r(20, 55) + r(-8, 4), g: 40, life: r(0.3, 0.45), c, s: r(1, 2.5), drag: 2 }); break; }
    case 'puff': { const k = size || 0.7; add({ x, y, puff: 14 * k, life: 0.35, c: pfxColor(spec.color, '#ffffff') }); break; }
    case 'sparkle': { const w = size || 12, c = pfxColor(spec.color, '#ffe699');
      for (let i = 0; i < n; i++) add({ x: x + r(-w / 2, w / 2), y: y + r(-w / 3, w / 3), vx: r(-10, 10), vy: r(-30, -8), g: 0, life: r(0.35, 0.6), c, s: 1.5, glow: true }); break; }
    case 'ash': { const w = size || 10, rise = +spec.rise || 40, c = pfxColor(spec.color, '#ccbfb3');
      for (let i = 0; i < n; i++) add({ x: x + r(-w, w), y: y + r(-3, 3), vx: r(-8, 8), vy: -rise * r(0.5, 1.1), g: 0, life: r(0.7, 1.1), c, s: r(1, 2) }); break; }
    case 'debris': { const c = pfxColor(spec.color, '#99734d');
      for (let i = 0; i < n; i++) add({ x, y, vx: r(-60, 60), vy: r(-110, -40), g: 320, life: r(0.5, 0.8), c, s: r(1.5, 3) }); break; }
    case 'ring': add({ x, y, ring: size || 24, life: 0.35, c: pfxColor(spec.color, '#ffe6b3') }); break;
    case 'flash': add({ x, y, flash: size || 40, life: 0.2, c: pfxColor(spec.color, '#ffe6b3') }); break;
  }
}
function pfxDrawParts(x, dt) {
  for (const p of PFX.parts) {
    p.t += dt; const k = Math.max(0, 1 - p.t / p.life), [R, G, B, A] = p.c;
    if (p.puff) { const rad = p.puff * (0.5 + p.t / p.life); const g = x.createRadialGradient(p.x, p.y, 0, p.x, p.y, rad); g.addColorStop(0, `rgba(${R},${G},${B},${A * 0.55 * k})`); g.addColorStop(1, `rgba(${R},${G},${B},0)`); x.fillStyle = g; x.beginPath(); x.arc(p.x, p.y, rad, 0, 7); x.fill(); continue; }
    if (p.ring) { x.strokeStyle = `rgba(${R},${G},${B},${A * k})`; x.lineWidth = 1.5; x.beginPath(); x.arc(p.x, p.y, p.ring * (1 - k * 0.8), 0, 7); x.stroke(); continue; }
    if (p.flash) { x.globalCompositeOperation = 'lighter'; const g = x.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.flash); g.addColorStop(0, `rgba(${R},${G},${B},${0.6 * k})`); g.addColorStop(1, `rgba(${R},${G},${B},0)`); x.fillStyle = g; x.beginPath(); x.arc(p.x, p.y, p.flash, 0, 7); x.fill(); x.globalCompositeOperation = 'source-over'; continue; }
    p.vx *= 1 - (p.drag || 0) * dt; p.vy += (p.g || 0) * dt; p.x += p.vx * dt; p.y += p.vy * dt;
    if (p.glow) x.globalCompositeOperation = 'lighter';
    x.fillStyle = `rgba(${R},${G},${B},${A * k})`; x.fillRect(Math.round(p.x), Math.round(p.y), p.s, p.s);
    x.globalCompositeOperation = 'source-over';
  }
  PFX.parts = PFX.parts.filter(p => p.t < p.life);
}

/* ---------- the stage ---------- */
function pfxFrame(now) {
  PFX.raf = 0; if (mode !== 'pfx' || !PFX.data) return;
  const c = $('#pfxCanvas'), x = c.getContext('2d'), dt = Math.min(0.05, (now - (PFX.last || now)) / 1000) * (+$('#pfxSlow').value || 1); PFX.last = now;
  const W = c.width, H = c.height, st = pfxStage(W, H), b = pfxBody(), list = pfxList(), event = pfxIsEvent(PFX.trigger);
  PFX.clock += dt;
  const anim = event ? (b.body.anims[PFX_EVENT_ANIM[PFX.trigger]] ? PFX_EVENT_ANIM[PFX.trigger] : 'idle') : PFX.trigger;
  const fps = b.body.fps_of?.[anim] || b.body.fps || 8, im = shotStrip(b.body.anims[anim] || b.body.anims.idle);
  const frames = im ? Math.max(1, Math.floor(im.width / b.body.cell[0])) : 1, frame = Math.floor(PFX.clock * fps) % frames;
  // the triggers, as ActionFx fires them
  if (event) { if (PFX.clock >= PFX.nextEvent) { list.forEach(s => pfxEmit(s, st)); PFX.nextEvent = PFX.clock + (PFX.trigger === 'step' ? 0.28 : 1.2); } }
  else {
    if (frame !== PFX.lastFrame) {
      if (frame === 0 && PFX.lastFrame !== -1 && $('#pfxLoop').checked) list.filter(s => (s.when || 'start') === 'start').forEach(s => pfxEmit(s, st));
      if (PFX.lastFrame === -1) list.filter(s => (s.when || 'start') === 'start').forEach(s => pfxEmit(s, st));
      list.filter(s => s.when === 'frames' && (s.frames || []).some(f => +f === frame)).forEach(s => pfxEmit(s, st));
      PFX.lastFrame = frame;
    }
    list.forEach((s, i) => { if (s.when !== 'every') return; PFX.every[i] = (PFX.every[i] ?? 0) - dt; if (PFX.every[i] <= 0) { pfxEmit(s, st); PFX.every[i] = Math.max(0.05, +s.every || 0.3); } });
  }
  x.fillStyle = '#0f0d14'; x.fillRect(0, 0, W, H); x.fillStyle = '#1d1a24'; x.fillRect(0, st.ground, W, H);
  drawBody(x, { ...b.body, fps }, st.origin, st.ground, false, anim, PFX.clock, 0);
  pfxDrawParts(x, dt);
  if ($('#pfxAnchors').checked) for (const [k, a] of Object.entries(st.anchors)) { x.fillStyle = '#4ade80'; x.fillRect(st.origin[0] + a[0] - 1, st.origin[1] + a[1] - 1, 3, 3); x.font = '6px system-ui'; x.fillText(PFX_AT[k], st.origin[0] + a[0] + 4, st.origin[1] + a[1] + 3); }
  x.fillStyle = '#cfd8e3'; x.font = '8px system-ui'; x.fillText(`${event ? PFX_EVENT[PFX.trigger] : PFX.trigger} · кадр ${frame + 1}/${frames}`, 8, 14);
  if (im && PFX.frames !== frames) { PFX.frames = frames; renderPfx(); }   // the frame boxes match the strip
  PFX.raf = requestAnimationFrame(pfxFrame);
}

/* ---------- panels ---------- */
function renderPfx() {
  if (!PFX.data) return;
  const b = pfxBody(), rules = PFX.rules[b.key] || {};
  const triggers = [...b.events, ...Object.keys(b.body.anims)];
  if (!PFX.trigger || !triggers.includes(PFX.trigger)) PFX.trigger = b.hero ? 'run' : 'walk' in b.body.anims ? 'walk' : 'idle';
  $('#pfxBodies').innerHTML = PFX.data.bodies.map((q, i) => `<option value="${i}"${i === PFX.body ? ' selected' : ''}>${esc(q.name.ru || q.key)}${q.boss ? ' ⚜' : ''}${Object.keys(PFX.rules[q.key] || {}).length ? ' •' : ''}</option>`).join('');
  const row = t => { const n = (rules[t] || []).length; return `<div class="irow${t === PFX.trigger ? ' on' : ''}" data-act="pfx-trigger" data-t="${esc(t)}"><span class="grow">${esc(pfxIsEvent(t) ? PFX_EVENT[t] : t)}</span>${n ? `<span class="badge new">${n}</span>` : ''}</div>`; };
  $('#pfxTriggers').innerHTML = (b.events.length ? '<div class="muted">События</div>' + b.events.map(row).join('') + '<div class="muted" style="margin-top:6px">Анимации</div>' : '') + Object.keys(b.body.anims).map(row).join('');
  const list = pfxList(), event = pfxIsEvent(PFX.trigger);
  const num = (i, k, v, min, max, step, label) => `<label class="lifenum">${label} <span class="muted">${(+v).toFixed(step < 1 ? 2 : 0)}</span><input type="range" data-pfx="${i}.${k}" min="${min}" max="${max}" step="${step}" value="${v}"></label>`;
  $('#pfxProps').innerHTML = `<div class="row" style="margin:0"><b class="grow">${esc(event ? PFX_EVENT[PFX.trigger] : 'Анимация «' + PFX.trigger + '»')}</b><button class="sm" data-act="pfx-add">＋ Частицы</button></div>
    ${list.length ? '' : '<div class="muted">Пока ничего — нажми «＋ Частицы».</div>'}
    ${list.map((s, i) => { const color = pfxColor(s.color, s.fx === 'dust' ? '#9e8f80bf' : '#ffffff'), hex = '#' + color.slice(0, 3).map(v => v.toString(16).padStart(2, '0')).join('');
      return `<div class="card" style="margin-top:8px"><div class="row" style="margin:0"><select data-pfx="${i}.fx">${Object.entries(PFX_KIND).map(([k, v]) => `<option value="${k}"${k === (s.fx || 'dust') ? ' selected' : ''}>${v}</option>`).join('')}</select><span class="grow"></span><button class="sm" data-act="pfx-dup" data-i="${i}">⧉</button><button class="sm danger" data-act="pfx-del" data-i="${i}">✕</button></div>
      <label>Откуда<select data-pfx="${i}.at">${Object.entries(PFX_AT).map(([k, v]) => `<option value="${k}"${k === (s.at || 'feet') ? ' selected' : ''}>${v}</option>`).join('')}</select></label>
      ${event ? '' : `<label>Когда<select data-pfx="${i}.when">${Object.entries(PFX_WHEN).map(([k, v]) => `<option value="${k}"${k === (s.when || 'start') ? ' selected' : ''}>${v}</option>`).join('')}</select></label>
      ${s.when === 'frames' ? `<div class="row" style="margin:0;flex-wrap:wrap;gap:4px">${Array.from({ length: PFX.frames || 8 }, (_, f) => `<label class="sm btnlike"><input type="checkbox" data-pfxframe="${i}" value="${f}"${(s.frames || []).some(x => +x === f) ? ' checked' : ''}> ${f + 1}</label>`).join('')}</div>` : ''}
      ${s.when === 'every' ? num(i, 'every', s.every ?? 0.3, 0.05, 2, 0.05, 'Каждые, с') : ''}`}
      ${['dust', 'sparkle', 'ash', 'debris'].includes(s.fx || 'dust') ? num(i, 'count', s.count ?? 6, 1, 60, 1, 'Сколько') : ''}
      ${(s.fx || 'dust') !== 'dust' && (s.fx || 'dust') !== 'debris' ? num(i, 'size', s.size ?? { puff: 0.7, sparkle: 12, ash: 10, ring: 24, flash: 40 }[s.fx], s.fx === 'puff' ? 0.2 : 2, s.fx === 'puff' ? 3 : 80, s.fx === 'puff' ? 0.05 : 1, { puff: 'Размер', sparkle: 'Ширина', ash: 'Разлёт', ring: 'Радиус', flash: 'Радиус' }[s.fx]) : ''}
      ${s.fx === 'ash' ? num(i, 'rise', s.rise ?? 40, 0, 120, 1, 'Подъём') : ''}
      ${(s.fx || 'dust') === 'dust' ? num(i, 'dir.0', (s.dir || [0, -1])[0], -1, 1, 0.05, 'Куда: назад ← → вперёд') + num(i, 'dir.1', (s.dir || [0, -1])[1], -1, 1, 0.05, 'Куда: вверх ↑ ↓ вниз') : ''}
      ${num(i, 'offset.0', (s.offset || [0, 0])[0], -40, 40, 1, 'Сдвиг вперёд, px')}${num(i, 'offset.1', (s.offset || [0, 0])[1], -60, 30, 1, 'Сдвиг вниз, px')}
      <div class="row" style="margin:0"><label>Цвет <input type="color" data-pfxcolor="${i}" value="${hex}"></label>${num(i, 'alpha', Math.round(color[3] * 100) / 100, 0.05, 1, 0.05, 'Непрозрачность')}</div>
      ${num(i, 'chance', s.chance ?? 1, 0.05, 1, 0.05, 'Вероятность')}</div>`; }).join('')}`;
  const send = $('#pfxSend'); send.disabled = !pfxDirty(); send.textContent = pfxDirty() ? '→ В игру •' : '→ В игру';
}
function pfxEdit(fn) {
  const b = pfxBody(), rules = PFX.rules[b.key] ??= {}, list = rules[PFX.trigger] ??= [];
  fn(list);
  if (!list.length) delete rules[PFX.trigger];
  if (!Object.keys(rules).length) delete PFX.rules[b.key];
  pfxSave();
}
function pfxInput(e) {
  const el = e.target;
  if (el.dataset.pfxframe !== undefined) {
    const i = +el.dataset.pfxframe;
    pfxEdit(list => { const set = new Set((list[i].frames || []).map(Number)); el.checked ? set.add(+el.value) : set.delete(+el.value); list[i].frames = [...set].sort((a, b) => a - b); });
    return;
  }
  if (el.dataset.pfxcolor !== undefined) {
    const i = +el.dataset.pfxcolor;
    pfxEdit(list => { const a = pfxColor(list[i].color, '#ffffff')[3]; list[i].color = el.value + (a < 1 ? Math.round(a * 255).toString(16).padStart(2, '0') : ''); });
    return;
  }
  const f = el.dataset.pfx; if (!f) return;
  const [i, k, sub] = f.split('.'), v = el.type === 'range' ? +el.value : el.value;
  if (el.type === 'range' && el.previousElementSibling) el.previousElementSibling.textContent = (+v).toFixed(+el.step < 1 ? 2 : 0);
  pfxEdit(list => {
    const s = list[+i];
    if (k === 'alpha') { const c = pfxColor(s.color, '#ffffff'); s.color = '#' + c.slice(0, 3).map(x => x.toString(16).padStart(2, '0')).join('') + (v < 1 ? Math.round(v * 255).toString(16).padStart(2, '0') : ''); }
    else if (sub !== undefined) { s[k] = [...(s[k] || (k === 'dir' ? [0, -1] : [0, 0]))]; s[k][+sub] = v; }
    else s[k] = v;
    if (k === 'when' && v === 'frames' && !s.frames) s.frames = [0];
    if (k === 'when' && v === 'every' && !s.every) s.every = 0.3;
  });
  if (e.type === 'change' || el.tagName === 'SELECT') renderPfx();
}
async function pfxFiles() {
  const doc = JSON.parse(await repoText('data/action_fx.json'));
  doc.bodies = PFX.rules;
  const names = Object.keys(PFX.rules).filter(k => JSON.stringify(PFX.rules[k]) !== JSON.stringify(PFX.data.rules[k]))
    .concat(Object.keys(PFX.data.rules).filter(k => !(k in PFX.rules)));
  return { files: { 'data/action_fx.json': JSON.stringify(doc, null, 2) + '\n' }, title: `Studio: particles — ${names.join(', ') || 'actions'}`,
    body: `Particles on actions (data/action_fx.json) from the studio's «Частицы»: ${names.join(', ')}.` };
}
async function pfxEnter() {
  try { await pfxLoad(); } catch (e) { $('#pfxProps').innerHTML = `<div class="warn">Нет данных (import/action_fx.json): ${esc(e.message)}</div>`; return; }
  const c = $('#pfxCanvas'), r = $('#pfxStage').getBoundingClientRect(); c.width = 360; c.height = Math.round(360 * Math.max(0.4, Math.min(0.75, r.height / Math.max(1, r.width))));
  renderPfx(); if (!PFX.raf) PFX.raf = requestAnimationFrame(pfxFrame);
}
function pfxInit() {
  if (!$('#pfxLayout')) return;
  $('#pfxSide').addEventListener('input', pfxInput); $('#pfxSide').addEventListener('change', pfxInput);
  $('#pfxBodies').addEventListener('change', e => { PFX.body = +e.target.value; PFX.trigger = null; PFX.lastFrame = -1; PFX.parts = []; renderPfx(); });
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act^="pfx-"]'); if (!b) return;
    const act = b.dataset.act;
    if (act === 'pfx-trigger') { PFX.trigger = b.dataset.t; PFX.lastFrame = -1; PFX.every = {}; PFX.clock = 0; PFX.nextEvent = 0; return renderPfx(); }
    if (act === 'pfx-add') { pfxEdit(list => list.push(pfxIsEvent(PFX.trigger) ? { fx: 'dust', at: 'feet', count: 6 } : { fx: 'dust', at: 'feet', when: 'start', count: 6 })); return renderPfx(); }
    if (act === 'pfx-dup') { pfxEdit(list => list.splice(+b.dataset.i + 1, 0, structuredClone(list[+b.dataset.i]))); return renderPfx(); }
    if (act === 'pfx-del') { pfxEdit(list => list.splice(+b.dataset.i, 1)); return renderPfx(); }
    if (act === 'pfx-revert') { PFX.rules = structuredClone(PFX.data.rules); pfxSave(); return renderPfx(); }
    if (act === 'pfx-send') {
      await sendToGame(pfxFiles, null);
      if (sendToGame.last?.local) { PFX.data.rules = structuredClone(PFX.rules); try { localStorage.removeItem('ss_pfx'); } catch {} renderPfx(); }
    }
  });
}
pfxInit();
