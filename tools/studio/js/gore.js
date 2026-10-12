/* Sprite Studio — blood and torn limbs (data/gore.json, scripts/fx/gore.gd).
 * Each material bleeds its own way (flesh, cloth, mail, plate, feather, spirit, gold) and a body
 * may lay its own keys over its material's. The preview is a port of gore.gd: drops fly with
 * gravity and leave marks where they land (a smear on the floor, a streak down the wall), a
 * wound drips, a death throws a gush and grows a pool, and a body that can be torn is cut
 * into pieces of its own drawing that bounce, bleed and lie there. Change one, change the other. */
'use strict';

const GORE_KEYS = {
  blood: ['Цвет крови'],
  drops: ['Капель от удара', 0, 40, 1],
  spray: ['Скорость брызг, px/с', 0, 400, 5],
  stain: ['Размер пятен (0 — без пятен)', 0, 3, 0.05],
  stain_life: ['Пятна держатся, с', 0, 120, 1],
  bleed: ['Рана кровоточит, с', 0, 5, 0.1],
  gush: ['Капель при смерти', 0, 80, 1],
  pool: ['Лужа под телом, px (0 — нет)', 0, 60, 1],
  limbs: ['Кусков при разрыве (0 — не рвётся)', 0, 6, 1],
  chance: ['Шанс разрыва (крит/удар в спину ×2)', 0, 1, 0.05],
  fling: ['Сила разлёта кусков, px/с', 0, 400, 5],
};
const GORE_MATERIAL = { flesh: 'плоть', cloth: 'ткань', mail: 'кольчуга', plate: 'латы', bone: 'кость', feather: 'перья', spirit: 'дух', gold: 'золото' };
const GORE_CUT = { 2: 'верх и низ', 3: 'голова, тело, ноги', 4: 'голова, тело, две ноги', 5: 'голова, тело, руки, ноги', 6: 'голова, тело, руки, две ноги' };
const GORE_G = 560, PIECE_G = 620, BOUNCE = 0.32, LIE = 14, FADE = 1.2;
const GORE = { data: null, work: null, body: 0, scope: 'mat', drops: [], stains: [], pieces: [], wound: 0, drip: 0, clock: 0, last: 0, raf: 0,
  state: 'idle', stateT: 0, hidden: false, auto: 0, step: 0, bounds: new Map() };

/* ---------- the table: a material's keys, then the body's own ---------- */
function goreSpec(work, defaults, key, material) {
  const own = work.bodies[key] || {}, mat = own.material || material;
  return { ...defaults, ...(work.materials[mat] || work.materials.flesh || {}), ...own };
}
/* data/gore.json as the game keeps it: one line per table, so a send changes only what was touched */
function goreText(comment, work) {
  const line = t => '{' + Object.entries(t).map(([k, v]) => `${JSON.stringify(k)}: ${JSON.stringify(v)}`).join(', ') + '}';
  const section = name => `  ${JSON.stringify(name)}: {\n` + Object.entries(work[name]).map(([k, t]) => `    ${JSON.stringify(k)}: ${line(t)}`).join(',\n') + '\n  }';
  return '{\n' + (comment !== undefined ? `  "_comment": ${JSON.stringify(comment)},\n` : '') + section('materials') + ',\n' + section('bodies') + '\n}\n';
}
/* Gore.cut: where the pieces lie in the drawn part [x, y, w, h] of a frame */
function goreCut(b, limbs) {
  const [x, y] = b, w = Math.max(b[2], 2), h = Math.max(b[3], 3), out = [];
  const row = (a, z) => [y + Math.floor(h * a), y + Math.floor(h * z)];
  const add = (name, x0, x1, band) => out.push({ name, rect: [Math.floor(x0), band[0], Math.max(1, Math.floor(x1) - Math.floor(x0)), Math.max(1, band[1] - band[0])] });
  if (limbs <= 2) { add('upper', x, x + w, row(0, 0.5)); add('lower', x, x + w, row(0.5, 1)); return out; }
  add('head', x + w * 0.2, x + w * 0.8, row(0, 0.3));
  if (limbs >= 5) { add('arm_l', x, x + w * 0.3, row(0.3, 0.64)); add('torso', x + w * 0.3, x + w * 0.7, row(0.3, 0.64)); add('arm_r', x + w * 0.7, x + w, row(0.3, 0.64)); }
  else add('torso', x, x + w, row(0.3, 0.64));
  if (limbs === 3 || limbs === 5) add('legs', x, x + w, row(0.64, 1));
  else { add('leg_l', x, x + w * 0.5, row(0.64, 1)); add('leg_r', x + w * 0.5, x + w, row(0.64, 1)); }
  return out;
}
function goreProblems(work, keys) {
  const out = [];
  for (const [where, tables] of [['materials', work.materials], ['bodies', work.bodies]]) for (const [k, t] of Object.entries(tables)) {
    for (const [f, v] of Object.entries(t)) {
      if (f === 'material' && where === 'bodies') { if (!work.materials[v]) out.push(`${k}: нет таблицы материала ${v}`); continue; }
      if (f === 'blood') { if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(v)) out.push(`${k}: цвет #rrggbb`); continue; }
      const spec = GORE_KEYS[f]; if (!spec || (keys && !keys.includes(f))) { out.push(`${k}: неизвестный ключ ${f}`); continue; }
      if (!(v >= spec[1] && v <= spec[2])) out.push(`${k}: ${f} от ${spec[1]} до ${spec[2]}`);
    }
    if (t.limbs === 1) out.push(`${k}: кусков 0 или 2–6`);
  }
  return out;
}
if (typeof module !== 'undefined') module.exports = { goreSpec, goreText, goreCut, goreProblems };

/* ---------- the studio ---------- */
async function goreLoad() {
  if (GORE.data) return;
  GORE.data = await (await fetch('import/gore.json')).json();
  const base = { materials: GORE.data.materials, bodies: GORE.data.bodies_rules };
  draftBase('gore', base, !!localStorage.getItem('ss_gore'));
  GORE.work = structuredClone(base);
  try { const saved = JSON.parse(localStorage.getItem('ss_gore') || 'null'); if (saved?.materials) GORE.work = saved; } catch {}
}
const goreSave = () => { draftHistory('gore'); try { localStorage.setItem('ss_gore', JSON.stringify(GORE.work)); } catch {} };
const goreBase = () => ({ materials: GORE.data.materials, bodies: GORE.data.bodies_rules });
const goreDirty = () => JSON.stringify(GORE.work) !== JSON.stringify(goreBase());
const goreBody = () => GORE.data.bodies[GORE.body];
const goreMat = () => (GORE.work.bodies[goreBody().key] || {}).material || goreBody().material;
const goreNow = () => goreSpec(GORE.work, GORE.data.defaults, goreBody().key, goreBody().material);
const goreColor = h => { const s = String(h || '#7a0c10').replace('#', ''), n = parseInt(s.slice(0, 6), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255, s.length >= 8 ? parseInt(s.slice(6, 8), 16) / 255 : 1]; };
const goreRgba = (c, a = 1, dark = 0) => `rgba(${Math.round(c[0] * (1 - dark))},${Math.round(c[1] * (1 - dark))},${Math.round(c[2] * (1 - dark))},${c[3] * a})`;
const rnd = (lo, hi) => lo + Math.random() * (hi - lo);

/* where the body stands and what it draws (shots.js drawBody) */
function goreStage(W, H) { const ground = Math.round(H * 0.72); return { ground, wall: W - 26, origin: [Math.round(W * 0.38), ground - 11] }; }
function goreFrame(b, anim) {
  const name = b.body.anims[anim] ? anim : 'idle', url = b.body.anims[name], im = shotStrip(url); if (!im) return null;
  const [cw, ch] = b.body.cell, frames = Math.max(1, Math.floor(im.width / cw)), fps = b.body.fps_of?.[name] || b.body.fps || 8;
  const loop = ['idle', 'walk', 'special', 'run'].includes(name), t = GORE.clock - GORE.stateT;
  return { name, url, im, cw, ch, fi: loop ? Math.floor(t * fps) % frames : Math.min(frames - 1, Math.floor(t * fps)), fps, frames };
}
/* Gore._opaque: the drawn part of a frame; the middle of the cell when the picture cannot be read */
function goreBounds(f) {
  const k = f.url + ':' + f.fi; if (GORE.bounds.has(k)) return GORE.bounds.get(k);
  let r = [f.cw * 0.25, f.ch * 0.2, f.cw * 0.5, f.ch * 0.75];
  try {
    const c = mk(f.cw, f.ch), x = c.getContext('2d'); x.drawImage(f.im, f.fi * f.cw, 0, f.cw, f.ch, 0, 0, f.cw, f.ch);
    const d = x.getImageData(0, 0, f.cw, f.ch).data; let x0 = f.cw, y0 = f.ch, x1 = -1, y1 = -1;
    for (let y = 0; y < f.ch; y++) for (let i = 0; i < f.cw; i++) if (d[(y * f.cw + i) * 4 + 3] > 0) { x0 = Math.min(x0, i); x1 = Math.max(x1, i); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    if (x1 - x0 >= 2 && y1 - y0 >= 2) r = [x0, y0, x1 - x0 + 1, y1 - y0 + 1];
  } catch {}
  GORE.bounds.set(k, r); return r;
}

/* ---------- gore.gd in the browser ---------- */
function goreDrop(x, y, vx, vy, s) { if (GORE.drops.length > 260) GORE.drops.shift(); GORE.drops.push({ x, y, vx, vy, c: goreColor(s.blood), stain: +s.stain, life: +s.stain_life, age: 0 }); }
function goreSpray(x, y, dir, count, s, spread) {
  const len = Math.hypot(dir[0], dir[1]) || 1, a0 = Math.atan2(dir[1] / len, dir[0] / len);
  for (let i = 0; i < count; i++) { const a = a0 + rnd(-spread, spread) * Math.PI / 180, v = +s.spray * rnd(0.35, 1.15); goreDrop(x + rnd(-3, 3), y + rnd(-3, 3), Math.cos(a) * v, Math.sin(a) * v - rnd(10, 60), s); }
}
function goreMark(x, y, w, wall, c, life, grow = 0.25) { if (w < 0.5 || life <= 0) return; if (GORE.stains.length > 520) GORE.stains.shift(); GORE.stains.push({ x: Math.round(x), y: Math.round(y), w, wall, c, born: GORE.clock, grow, life, seed: Math.random() }); }
function goreHit(crit) {
  const s = goreNow(), st = goreStage(GORE.W, GORE.H), back = $('#goreBack').checked;
  const weight = 1 + (crit ? 0.6 : 0) + (back ? 1 : 0) + 0.3;
  goreSpray(st.origin[0] - 4, st.origin[1] - 10, [1, -0.3], Math.round(+s.drops * Math.min(2.5, Math.max(0.5, weight))), s, 38);
  if (+s.bleed > 0) GORE.wound = Math.max(GORE.wound, +s.bleed * Math.min(2, Math.max(0.6, weight)));
  GORE.state = 'hurt'; GORE.stateT = GORE.clock; GORE.flash = 1;
}
function goreDeath() {
  const s = goreNow(), st = goreStage(GORE.W, GORE.H), b = goreBody(), violent = $('#goreBack').checked;
  goreSpray(st.origin[0], st.origin[1] - 10, [1, -0.8], +s.gush, s, 75);
  if (+s.pool > 0) { const c = goreColor(s.blood).map((v, i) => i < 3 ? v * 0.85 : v); goreMark(st.origin[0], st.ground, +s.pool * rnd(0.85, 1.15), false, c, +s.stain_life * 1.4, 1.6); goreMark(st.origin[0] + rnd(-0.5, 0.5) * +s.pool, st.ground, +s.pool * 0.4, false, c, +s.stain_life, 1.1); }
  const f = goreFrame(b, GORE.state === 'hurt' ? 'hurt' : 'idle');
  const torn = !b.boss && f && +s.limbs >= 2 && ($('#goreAlways').checked || Math.random() < +s.chance * (violent ? 2 : 1));
  GORE.verdict = b.boss ? 'босс не рвётся — он остаётся для последних слов' : +s.limbs < 2 ? 'не рвётся (кусков 0)' : torn ? `разорван на ${s.limbs}: ${GORE_CUT[s.limbs]}` : `цел (шанс ${Math.round(+s.chance * (violent ? 2 : 1) * 100)}%)`;
  if (torn) {
    const sc = +b.body.scale || 1, bounds = goreBounds(f), w = f.cw * sc, h = f.ch * sc;
    const left = b.body.hero ? st.origin[0] - (f.cw - 68) * sc : st.origin[0] - w / 2, top = b.body.hero ? st.ground - 4 - h : st.origin[1] + 12 - h + (+b.body.pad_y || 0) * sc;
    const cx = bounds[0] + bounds[2] / 2, cy = bounds[1] + bounds[3] / 2;
    for (const part of goreCut(bounds, +s.limbs)) {
      const r = part.rect, lx = r[0] + r[2] / 2, ly = r[1] + r[3] / 2;
      const out = [-(lx - cx), ly - cy], ol = Math.hypot(...out) || 1;      // the body faces left: mirrored
      let dx = out[0] / ol * 0.7 + 0.8, dy = out[1] / ol * 0.7 - 1; const dl = Math.hypot(dx, dy); dx /= dl; dy /= dl;
      const v = +s.fling * rnd(0.55, 1.1) * (part.name === 'head' ? 1.2 : 1);
      GORE.pieces.push({ im: b.body.tint ? shotTinted(f.im, f.url, b.body.tint) : f.im, sx: f.fi * f.cw + r[0], sy: r[1], sw: r[2], sh: r[3], sc,
        x: left + (f.cw - lx) * sc, y: top + ly * sc, vx: dx * v, vy: dy * v, rot: 0, spin: rnd(-12, 12) * 2, rad: Math.max(1.5, Math.min(r[2], r[3]) * sc / 2),
        bleed: Math.max(+s.bleed, 0.4) * 1.6, drip: 0, rest: false, lain: 0, air: 0, s });
    }
    goreSpray(st.origin[0], st.origin[1] - 10, [0, -1], Math.floor(+s.gush * 0.5), s, 70);
    GORE.hidden = true;
  } else { GORE.state = 'death'; GORE.stateT = GORE.clock; }
  GORE.dead = GORE.clock; renderGoreVerdict();
}
function goreStep(dt, st) {
  const floorAt = x => x >= st.wall ? -1 : st.ground;
  GORE.drops = GORE.drops.filter(d => {
    d.vy += GORE_G * dt; d.vx *= 1 - 0.6 * dt; d.age += dt;
    const nx = d.x + d.vx * dt, ny = d.y + d.vy * dt;
    if (nx >= st.wall && d.x < st.wall) { goreMark(st.wall, d.y, rnd(2, 5) * d.stain, true, d.c, d.life); return false; }
    if (d.vy > 0 && ny >= st.ground && floorAt(nx) > 0) { goreMark(nx, st.ground, rnd(1, 3.5) * d.stain, false, d.c, d.life); return false; }
    d.x = nx; d.y = ny; return d.age < 4;
  });
  if (GORE.wound > 0) { GORE.wound -= dt; GORE.drip -= dt; if (GORE.drip <= 0 && !GORE.hidden) { GORE.drip = rnd(0.07, 0.16); const s = goreNow(); goreDrop(st.origin[0] - 4 + rnd(-3, 3), st.origin[1] - 10, rnd(-15, 15), rnd(-10, 20), { ...s, stain: +s.stain * 0.7 }); } }
  for (const p of GORE.pieces) {
    if (p.bleed > 0) { p.bleed -= dt; p.drip -= dt; if (p.drip <= 0) { p.drip = p.rest ? 0.22 : 0.05; goreDrop(p.x, p.y, rnd(-20, 20) - p.vx * 0.1, rnd(-30, 10) - p.vy * 0.1, { ...p.s, stain: +p.s.stain * 0.8 }); } }
    if (p.rest) { p.lain += dt; continue; }
    p.air += dt; p.vy += PIECE_G * dt; p.rot += p.spin * dt; p.x += p.vx * dt; p.y += p.vy * dt;
    if (p.x + p.rad >= st.wall) { p.x = st.wall - p.rad; goreMark(st.wall, p.y, rnd(2, 4) * +p.s.stain, true, goreColor(p.s.blood), +p.s.stain_life); p.vx = -p.vx * BOUNCE; p.spin = -p.spin; }
    if (p.y + p.rad >= st.ground && p.vy > 0) {
      p.y = st.ground - p.rad; goreMark(p.x, st.ground, rnd(2, 4) * +p.s.stain, false, goreColor(p.s.blood), +p.s.stain_life);
      p.vx *= 0.55; p.vy = -Math.abs(p.vy) * BOUNCE; p.spin *= 0.5;
      if (Math.abs(p.vy) < 40) { p.vx = p.vy = 0; p.rest = true; p.rot = Math.round(p.rot / (Math.PI / 2)) * Math.PI / 2; }
    }
  }
  GORE.pieces = GORE.pieces.filter(p => p.lain < LIE + FADE && p.air < 5);
  GORE.stains = GORE.stains.filter(s => GORE.clock - s.born < s.life);
}
function goreDraw(x, st) {
  for (const s of GORE.stains) {
    const age = GORE.clock - s.born, g = Math.min(1, age / Math.max(s.grow, 0.01)), grown = 1 - (1 - g) * (1 - g), a = Math.min(1, Math.max(0, (s.life - age) / 3)), w = Math.max(1, Math.round(s.w * grown));
    x.fillStyle = goreRgba(s.c, a);
    if (s.wall) { x.fillRect(s.x - 1, s.y - 1, 1, w); if (w > 3) { x.fillStyle = goreRgba(s.c, a, 0.3); x.fillRect(s.x - 1, s.y + w - 1, 1, 1); } continue; }
    x.fillRect(s.x - Math.floor(w / 2), s.y - 1, w, 1);
    if (w >= 4) { x.fillStyle = goreRgba(s.c, a, 0.2); x.fillRect(s.x - Math.floor(w / 4), s.y - 2, Math.max(1, Math.floor(w / 2)), 1); }
    if (w >= 7) { x.fillStyle = goreRgba(s.c, a); let seed = s.seed * 1e4; const r = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280); for (let k = 0; k < Math.floor(w / 5); k++) x.fillRect(Math.round(s.x + (r() * 1.6 - 0.8) * w), s.y - 1 - Math.round(r()), 1, 1); }
  }
  for (const p of GORE.pieces) {
    x.save(); x.globalAlpha = p.lain > LIE ? Math.max(0, 1 - (p.lain - LIE) / FADE) : 1; x.translate(Math.round(p.x), Math.round(p.y)); x.rotate(p.rot); x.scale(-1, 1);
    x.imageSmoothingEnabled = false; x.drawImage(p.im, p.sx, p.sy, p.sw, p.sh, -p.sw * p.sc / 2, -p.sh * p.sc / 2, p.sw * p.sc, p.sh * p.sc); x.restore();
  }
  for (const d of GORE.drops) { x.fillStyle = goreRgba(d.c); x.fillRect(Math.round(d.x), Math.round(d.y), 1, Math.abs(d.vy) > 120 ? 2 : 1); }
}

/* ---------- the stage ---------- */
function goreFrameLoop(now) {
  GORE.raf = 0; if (mode !== 'gore' || !GORE.data) return;
  const c = $('#goreCanvas'), x = c.getContext('2d'), dt = Math.min(0.05, (now - (GORE.last || now)) / 1000) * (+$('#goreSlow').value || 1); GORE.last = now;
  const W = GORE.W = c.width, H = GORE.H = c.height, st = goreStage(W, H), b = goreBody();
  GORE.clock += dt;
  // by itself: two blows, a crit, the death, a pause, up again
  if ($('#goreAuto').checked) { GORE.auto -= dt; if (GORE.auto <= 0) { const beat = GORE.step++ % 6; if (beat < 2) goreHit(false); else if (beat === 2) goreHit(true); else if (beat === 3) goreDeath(); else if (beat === 5) goreRise(); GORE.auto = beat === 3 ? 2.6 : beat === 4 ? 0.6 : 0.7; } }
  if (GORE.state === 'hurt' && GORE.clock - GORE.stateT > 0.3) { GORE.state = 'idle'; GORE.stateT = GORE.clock; }
  goreStep(dt, st);
  x.fillStyle = '#0f0d14'; x.fillRect(0, 0, W, H); x.fillStyle = '#1d1a24'; x.fillRect(0, st.ground, W, H); x.fillRect(st.wall, 0, W, st.ground);
  x.fillStyle = '#2a2633'; x.fillRect(0, st.ground, st.wall, 1); x.fillRect(st.wall, 0, 1, st.ground);
  if (!GORE.hidden) {
    const anim = GORE.state === 'death' ? (b.body.anims.death ? 'death' : 'hurt') : GORE.state === 'hurt' && b.body.anims.hurt ? 'hurt' : 'idle';
    const f = goreFrame(b, anim);
    if (!(GORE.state === 'death' && f && f.name === 'death' && f.fi >= f.frames - 1 && GORE.clock - GORE.stateT > f.frames / f.fps + 0.35)) {
      drawBody(x, { ...b.body, fps: f?.fps || b.body.fps }, st.origin, st.ground, true, f?.name || 'idle', GORE.clock - GORE.stateT, GORE.flash || 0);
    }
    GORE.flash = Math.max(0, (GORE.flash || 0) - dt * 8);
  }
  goreDraw(x, st);
  x.fillStyle = '#cfd8e3'; x.font = '8px system-ui';
  x.fillText(`${b.name.ru || b.key} · ${GORE_MATERIAL[goreMat()] || goreMat()} · капель в воздухе ${GORE.drops.length}, пятен ${GORE.stains.length}, кусков ${GORE.pieces.length}`, 8, 14);
  GORE.raf = requestAnimationFrame(goreFrameLoop);
}
function goreRise() { GORE.hidden = false; GORE.state = 'idle'; GORE.stateT = GORE.clock; GORE.wound = 0; GORE.verdict = ''; renderGoreVerdict(); }

/* ---------- panels ---------- */
function renderGoreVerdict() { const el = $('#goreVerdict'); if (el) el.textContent = GORE.verdict || ''; }
function renderGore() {
  if (!GORE.data) return;
  const b = goreBody(), mat = goreMat(), own = GORE.work.bodies[b.key] || {}, matT = GORE.work.materials[mat] || {}, s = goreNow(), scope = GORE.scope;
  $('#goreBodies').innerHTML = GORE.data.bodies.map((q, i) => `<option value="${i}"${i === GORE.body ? ' selected' : ''}>${esc(q.name.ru || q.key)}${q.boss ? ' ⚜' : ''} — ${GORE_MATERIAL[(GORE.work.bodies[q.key] || {}).material || q.material] || q.material}${GORE.work.bodies[q.key] ? ' •' : ''}</option>`).join('');
  const field = (k, v, mine) => {
    const [label, min, max, step] = GORE_KEYS[k], reset = scope === 'body' && mine ? `<button class="sm" data-act="gore-unset" data-k="${k}" title="Убрать своё значение — брать из материала">↺</button>` : '';
    const tag = scope === 'body' ? (mine ? '<span class="badge new">своё</span>' : '<span class="muted">от материала</span>') : '';
    if (k === 'blood') { const c = goreColor(v), hex = '#' + c.slice(0, 3).map(n => n.toString(16).padStart(2, '0')).join('');
      return `<div class="row" style="margin:0;gap:6px"><label>${label} <input type="color" data-gorecolor value="${hex}"></label><label class="lifenum">Непрозрачность <span class="muted">${c[3].toFixed(2)}</span><input type="range" data-gore="alpha" min="0.1" max="1" step="0.05" value="${c[3]}"></label>${tag}${reset}</div>`; }
    return `<div class="row" style="margin:0;gap:6px"><label class="lifenum grow">${label} <span class="muted">${(+v).toFixed(step < 1 ? 2 : 0)}</span><input type="range" data-gore="${k}" min="${min}" max="${max}" step="${step}" value="${v}"></label>${tag}${reset}</div>`;
  };
  const shown = scope === 'mat' ? { ...GORE.data.defaults, ...matT } : s;
  $('#goreProps').innerHTML = `
    <div style="margin:6px 0;display:grid;gap:4px"><label style="display:flex;gap:6px;align-items:center"><input type="radio" style="width:auto;flex:none;margin:0" name="goreScope" value="mat"${scope === 'mat' ? ' checked' : ''}> Править материал «${esc(GORE_MATERIAL[mat] || mat)}» — для всех из него</label>
    <label style="display:flex;gap:6px;align-items:center"><input type="radio" style="width:auto;flex:none;margin:0" name="goreScope" value="body"${scope === 'body' ? ' checked' : ''}> Только «${esc(b.name.ru || b.key)}»</label></div>
    ${scope === 'body' ? `<label>Материал крови<select data-gore="material">${Object.keys(GORE.work.materials).map(m => `<option value="${m}"${m === mat ? ' selected' : ''}>${esc(GORE_MATERIAL[m] || m)}${m === b.material ? ' (как в бестиарии)' : ''}</option>`).join('')}</select></label>` : ''}
    <div class="card"><b>Удар</b>${['blood', 'drops', 'spray', 'stain', 'stain_life', 'bleed'].map(k => field(k, shown[k], k in own)).join('')}</div>
    <div class="card"><b>Смерть</b>${['gush', 'pool', 'limbs', 'chance', 'fling'].map(k => field(k, shown[k], k in own)).join('')}
      <div class="muted">${+shown.limbs >= 2 ? 'Режется сам рисунок — кадр, в котором умер: ' + GORE_CUT[Math.min(6, +shown.limbs)] + '.' : 'Тело не рвётся — играет своя анимация смерти.'}${b.boss ? ' Боссы не рвутся никогда.' : ''}</div></div>
    ${goreProblems(GORE.work, GORE.data.keys).map(p => `<div class="warn">${esc(p)}</div>`).join('')}`;
  const send = $('#goreSend'); send.disabled = !goreDirty(); send.textContent = goreDirty() ? '→ В игру •' : '→ В игру';
  renderGoreVerdict();
}
function goreEdit(fn) {
  const key = goreBody().key;
  if (GORE.scope === 'body') { const t = GORE.work.bodies[key] ??= {}; fn(t); if (!Object.keys(t).length) delete GORE.work.bodies[key]; }
  else fn(GORE.work.materials[goreMat()] ??= {});
  goreSave();
}
function goreInput(e) {
  const el = e.target;
  if (el.name === 'goreScope') { GORE.scope = el.value; return renderGore(); }
  if (el.dataset.gorecolor !== undefined) { goreEdit(t => { const a = goreColor(t.blood || goreNow().blood)[3]; t.blood = el.value + (a < 1 ? Math.round(a * 255).toString(16).padStart(2, '0') : ''); }); return; }
  const k = el.dataset.gore; if (!k) return;
  const v = el.type === 'range' ? +el.value : el.value;
  if (el.type === 'range' && el.previousElementSibling) el.previousElementSibling.textContent = (+v).toFixed(+el.step < 1 ? 2 : 0);
  goreEdit(t => {
    if (k === 'alpha') { const c = goreColor(t.blood || goreNow().blood); t.blood = '#' + c.slice(0, 3).map(n => n.toString(16).padStart(2, '0')).join('') + (v < 1 ? Math.round(v * 255).toString(16).padStart(2, '0') : ''); }
    else if (k === 'material') { if (v === goreBody().material) delete t.material; else t.material = v; }
    else t[k] = k === 'limbs' && v === 1 ? 2 : v;
  });
  if (e.type === 'change' || el.tagName === 'SELECT') renderGore();
}
async function goreFiles() {
  const problems = goreProblems(GORE.work, GORE.data.keys); if (problems.length) throw new Error(problems.join('; '));
  const doc = JSON.parse(await repoText('data/gore.json'));
  const merged = await resolveDraft(draftBase('gore', goreBase()), GORE.work, { materials: doc.materials, bodies: doc.bodies }, 'Кровь', BASES.gore.uncertain);
  const changed = [...new Set([...Object.keys(merged.materials), ...Object.keys(doc.materials)].filter(k => JSON.stringify(merged.materials[k]) !== JSON.stringify(doc.materials[k]))
    .concat([...Object.keys(merged.bodies), ...Object.keys(doc.bodies)].filter(k => JSON.stringify(merged.bodies[k]) !== JSON.stringify(doc.bodies[k]))))];
  return { files: { 'data/gore.json': goreText(doc._comment, merged) }, title: `Studio: blood — ${changed.join(', ') || 'gore'}`,
    body: `Blood and torn limbs (data/gore.json) from the studio's «Кровь»: ${changed.join(', ')}.` };
}
async function goreEnter() {
  try { await goreLoad(); } catch (e) { $('#goreProps').innerHTML = `<div class="warn">Нет данных (import/gore.json): ${esc(e.message)}</div>`; return; }
  const c = $('#goreCanvas'), r = $('#goreStage').getBoundingClientRect(); c.width = 360; c.height = Math.round(360 * Math.max(0.4, Math.min(0.75, r.height / Math.max(1, r.width))));
  trackChange('gore'); renderGore(); if (!GORE.raf) GORE.raf = requestAnimationFrame(goreFrameLoop);
}
function goreInit() {
  if (!$('#goreLayout')) return;
  $('#goreSide').addEventListener('input', goreInput); $('#goreSide').addEventListener('change', goreInput);
  $('#goreBodies').addEventListener('change', e => { GORE.body = +e.target.value; GORE.pieces = []; goreRise(); renderGore(); });
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act^="gore-"]'); if (!b) return;
    const act = b.dataset.act;
    if (act === 'gore-hit') { if (GORE.hidden || GORE.state === 'death') goreRise(); return goreHit(false); }
    if (act === 'gore-crit') { if (GORE.hidden || GORE.state === 'death') goreRise(); return goreHit(true); }
    if (act === 'gore-death') { if (GORE.hidden || GORE.state === 'death') goreRise(); return goreDeath(); }
    if (act === 'gore-clear') { GORE.stains = []; GORE.pieces = []; GORE.drops = []; return goreRise(); }
    if (act === 'gore-unset') { goreEdit(t => { delete t[b.dataset.k]; }); return renderGore(); }
    if (act === 'gore-revert') { GORE.work = structuredClone(goreBase()); goreSave(); return renderGore(); }
    if (act === 'gore-send') {
      await sendToGame(goreFiles, null);
      if (sendToGame.last?.local) { GORE.data.materials = structuredClone(GORE.work.materials); GORE.data.bodies_rules = structuredClone(GORE.work.bodies); delete BASES.gore; draftBasesSave(); try { localStorage.removeItem('ss_gore'); } catch {} renderGore(); }
    }
  });
}
if (typeof document !== 'undefined') goreInit();
