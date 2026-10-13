/* Sprite Studio — blood and torn limbs (data/gore.json, scripts/fx/gore.gd).
 * Each material bleeds its own way (flesh, cloth, mail, plate, feather, spirit, gold) and a body
 * may lay its own keys over its material's. The preview is a port of gore.gd: drops fly with
 * gravity and leave marks where they land (a smear on the floor, a streak down the wall), a
 * wound drips, a death throws a gush and grows a pool, and a body that can be torn is cut
 * into pieces of its own drawing — to pieces, the head off, in half or an arm off, the line ragged, what is
 * left standing a beat before it topples, a stump jetting in pulses. Drops and marks each take their own
 * shade; marks are smears, splats or broken trails. Blood keeps to what it lands on: a mark stops at its
 * ledge's edge and what hangs over drips off, a streak runs down a wall no further than the wall goes, a
 * ledge's underside drips, a heavy drop splashes, some drops fly into the depth and stick to the painted wall
 * behind (never in the sky's opening), a mist hangs a moment, and the marks soak into the picture under them
 * (a multiply pass, as the Soak node does). The stage has all of it: a brick wall with an opening, a ledge,
 * a wall that ends in the air. Change one, change the other. */
'use strict';

const GORE_KEYS = {
  blood: ['Цвет крови'],
  shade: ['Разброс оттенка капель и пятен', 0, 0.5, 0.01],
  drops: ['Капель от удара', 0, 40, 1],
  spray: ['Скорость брызг, px/с', 0, 400, 5],
  stain: ['Размер пятен (0 — без пятен)', 0, 3, 0.05],
  stain_life: ['Пятна держатся, с', 0, 120, 1],
  mist: ['Морось от удара (без пятен)', 0, 20, 1],
  soak: ['Впитывается в текстуру (0 — лежит сверху)', 0, 1, 0.05],
  splash: ['Брызги от упавшей капли', 0, 6, 1],
  run: ['Потёки по стене, px', 0, 40, 1],
  drip: ['Стекает с края, капает с потолка', 0, 1, 0.05],
  back: ['Доля капель на фон (не в небо и проёмы)', 0, 0.6, 0.01],
  bleed: ['Рана кровоточит, с', 0, 5, 0.1],
  gush: ['Капель при смерти', 0, 80, 1],
  pool: ['Лужа под телом, px (0 — нет)', 0, 60, 1],
  spurt: ['Обрубок бьёт струёй, с (0 — только капает)', 0, 4, 0.1],
  limbs: ['Кусков при разрыве (0 — не рвётся)', 0, 6, 1],
  chance: ['Шанс разрыва (крит/удар в спину ×2)', 0, 1, 0.05],
  fling: ['Сила разлёта кусков, px/с', 0, 400, 5],
};
/* Gore.CUTS: the ways a body tears, weighed by `cuts` */
const GORE_WAYS = { all: 'на куски', head: 'голова прочь', half: 'пополам', limb: 'рука прочь' };
const GORE_RAGGED = 0.07;
const GORE_MATERIAL = { flesh: 'плоть', cloth: 'ткань', mail: 'кольчуга', plate: 'латы', bone: 'кость', feather: 'перья', spirit: 'дух', gold: 'золото' };
const GORE_CUT = { 2: 'верх и низ', 3: 'голова, тело, ноги', 4: 'голова, тело, две ноги', 5: 'голова, тело, руки, ноги', 6: 'голова, тело, руки, две ноги' };
const GORE_G = 560, PIECE_G = 620, BOUNCE = 0.32, LIE = 14, FADE = 1.2, TOPPLE = 22;
/* Gore's drop flags: thrown off another (no splash again), a speck of mist (no mark), bound for the wall behind */
const SPLASHED = 1, MISTY = 2, BACK = 4, SPLASH_SPEED = 120;
const GORE = { data: null, work: null, body: 0, scope: 'mat', drops: [], stains: [], drips: [], pieces: [], wound: 0, drip: 0, clock: 0, last: 0, raf: 0,
  state: 'idle', stateT: 0, way: 'any', hidden: false, auto: 0, step: 0, bounds: new Map() };

/* ---------- the table: a material's keys, then the body's own ---------- */
function goreSpec(work, defaults, key, material) {
  const own = work.bodies[key] || {}, mat = own.material || material;
  return { ...defaults, ...(work.materials[mat] || work.materials.flesh || {}), ...own };
}
/* data/gore.json as the game keeps it: one line per table, so a send changes only what was touched */
function goreText(comment, work) {
  const val = v => v && typeof v === 'object' ? line(v) : JSON.stringify(v);
  const line = t => '{' + Object.entries(t).map(([k, v]) => `${JSON.stringify(k)}: ${val(v)}`).join(', ') + '}';
  const section = name => `  ${JSON.stringify(name)}: {\n` + Object.entries(work[name]).map(([k, t]) => `    ${JSON.stringify(k)}: ${line(t)}`).join(',\n') + '\n  }';
  return '{\n' + (comment !== undefined ? `  "_comment": ${JSON.stringify(comment)},\n` : '') + section('materials') + ',\n' + section('bodies') + '\n}\n';
}
/* Gore.pick_cut: one of the ways by its weight (none at all: to pieces); no arms (4 pieces or fewer): the head */
function gorePickCut(weights, limbs, rand = Math.random) {
  const ways = Object.keys(GORE_WAYS), w = k => Math.max(+(weights || {})[k] || 0, 0), total = ways.reduce((a, k) => a + w(k), 0);
  let way = 'all';
  if (total > 0) { let roll = rand() * total; for (const k of ways) { roll -= w(k); if (roll < 0) { way = k; break; } } }
  return way === 'limb' && limbs < 5 ? 'head' : way;
}
/* Gore.cut: where the pieces lie in the drawn part [x, y, w, h] of a frame, torn `way`, each line wandering by
 * up to `ragged` of the body. A part: {name, rect, stands (left standing), stump ([x, y] its wound faces, or null)} */
function goreCut(b, limbs, way = 'all', ragged = 0, rand = Math.random) {
  const out = []; if (limbs < 2) return out;
  const [x, y] = b, w = Math.max(b[2], 2), h = Math.max(b[3], 3), cl = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const j = v => v + (rand() * 2 - 1) * ragged;
  const neck = cl(j(0.3), 0.15, 0.45), waist = cl(j(0.64), neck + 0.15, 0.85), middle = cl(j(0.5), 0.3, 0.7), arm = cl(j(0.3), 0.18, 0.4), legs = cl(j(0.5), 0.35, 0.65);
  const U = [0, -1], D = [0, 1], L = [-1, 0], R = [1, 0];
  const add = (name, x0, x1, a, z, stands, stump) => { const top = y + Math.floor(h * a);
    out.push({ name, rect: [Math.floor(x0), top, Math.max(1, Math.floor(x1) - Math.floor(x0)), Math.max(1, y + Math.floor(h * z) - top)], stands, stump }); };
  if (way === 'limb' && limbs < 5) way = 'head';
  if (way === 'head') { add('head', x + w * 0.2, x + w * 0.8, 0, neck, false, D); add('body', x, x + w, neck, 1, true, U); }
  else if (way === 'half') { add('upper', x, x + w, 0, middle, false, D); add('lower', x, x + w, middle, 1, true, U); }
  else if (way === 'limb') {
    if (rand() < 0.5) { add('arm_l', x, x + w * arm, neck, waist, false, R); add('body', x + w * arm, x + w, 0, waist, true, L); }
    else { add('arm_r', x + w * (1 - arm), x + w, neck, waist, false, L); add('body', x, x + w * (1 - arm), 0, waist, true, R); }
    add('legs', x, x + w, waist, 1, true, null);
  } else {
    if (limbs === 2) { add('upper', x, x + w, 0, middle, false, D); add('lower', x, x + w, middle, 1, false, U); return out; }
    add('head', x + w * 0.2, x + w * 0.8, 0, neck, false, D);
    if (limbs >= 5) { add('arm_l', x, x + w * arm, neck, waist, false, null); add('torso', x + w * arm, x + w * (1 - arm), neck, waist, false, U); add('arm_r', x + w * (1 - arm), x + w, neck, waist, false, null); }
    else add('torso', x, x + w, neck, waist, false, U);
    if (limbs === 3 || limbs === 5) add('legs', x, x + w, waist, 1, false, null);
    else { add('leg_l', x, x + w * legs, waist, 1, false, null); add('leg_r', x + w * legs, x + w, waist, 1, false, null); }
  }
  return out;
}
function goreProblems(work, keys) {
  const out = [];
  for (const [where, tables] of [['materials', work.materials], ['bodies', work.bodies]]) for (const [k, t] of Object.entries(tables)) {
    for (const [f, v] of Object.entries(t)) {
      if (f === 'material' && where === 'bodies') { if (!work.materials[v]) out.push(`${k}: нет таблицы материала ${v}`); continue; }
      if (f === 'blood') { if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(v)) out.push(`${k}: цвет #rrggbb`); continue; }
      if (f === 'cuts' && (!keys || keys.includes(f))) {
        if (!v || typeof v !== 'object' || Array.isArray(v) || !Object.keys(v).length) { out.push(`${k}: cuts — веса способов`); continue; }
        for (const [way, n] of Object.entries(v)) { if (!GORE_WAYS[way]) out.push(`${k}: неизвестный разрыв ${way}`); else if (!(n >= 0 && n <= 10)) out.push(`${k}: вес «${GORE_WAYS[way]}» от 0 до 10`); }
        if (!(Object.values(v).reduce((a, n) => a + (+n || 0), 0) > 0)) out.push(`${k}: хоть один разрыв должен весить больше 0`);
        continue;
      }
      const spec = GORE_KEYS[f]; if (!spec || (keys && !keys.includes(f))) { out.push(`${k}: неизвестный ключ ${f}`); continue; }
      if (!(v >= spec[1] && v <= spec[2])) out.push(`${k}: ${f} от ${spec[1]} до ${spec[2]}`);
    }
    if (t.limbs === 1) out.push(`${k}: кусков 0 или 2–6`);
  }
  return out;
}
if (typeof module !== 'undefined') module.exports = { goreSpec, goreText, goreCut, gorePickCut, goreProblems, goreStage, goreInk, goreDrop, goreMark, goreStep, GORE, SPLASHED, MISTY, BACK };

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
/* the floor; a ledge floating over it (top and underside, x from–to); a wall on the right whose foot ends in
 * the air; the sky's opening in the painted wall behind, where nothing sticks */
function goreStage(W, H) {
  const ground = Math.round(H * 0.72), wall = W - 26;
  return { ground, wall, foot: ground - 22, origin: [Math.round(W * 0.38), ground - 11],
    ledge: { x0: Math.round(W * 0.56), x1: Math.round(W * 0.72), top: ground - 36, bottom: ground - 30 },
    opening: [Math.round(W * 0.05), Math.round(H * 0.08), Math.round(W * 0.24), Math.round(H * 0.3)] };
}
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
/* Gore.shaded: a shade darker or lighter, by up to `amount` — no two drops the same red */
function goreShaded(c, amount) {
  if (!(amount > 0)) return c;
  const k = rnd(-amount, amount);
  return k < 0 ? [c[0] * (1 + k), c[1] * (1 + k), c[2] * (1 + k), c[3]] : [c[0] + (255 - c[0]) * k * 0.6, c[1] + (255 - c[1]) * k * 0.6, c[2] + (255 - c[2]) * k * 0.6, c[3]];
}
/* Gore.ink: what a drop carries of its body's table */
function goreInk(s, size = 1) {
  return { stain: (+s.stain || 0) * size, life: +s.stain_life || 0, soak: +s.soak || 0, splash: +s.splash || 0, run: +s.run || 0, drip: +s.drip || 0, back: +s.back || 0 };
}
function goreDrop(x, y, vx, vy, c, ink, flags = 0) {
  if (GORE.drops.length > 260) GORE.drops.shift();
  if (!flags && Math.random() < ink.back) flags = BACK;
  GORE.drops.push({ x, y, vx, vy, c, ink, age: 0, px: !(flags & (SPLASHED | MISTY)) && Math.random() < 0.18 ? 2 : 1, flags, lands: rnd(0.06, 0.32), fade: rnd(0.25, 0.7) });
}
/* every blow its own tilt; now and then the spray breaks into a jet; a fine mist hangs round it */
function goreSpray(x, y, dir, count, s, spread) {
  const len = Math.hypot(dir[0], dir[1]) || 1, a0 = Math.atan2(dir[1] / len, dir[0] / len) + rnd(-0.22, 0.22), speed = +s.spray * rnd(0.85, 1.15), jet = Math.random() < 0.35, c = goreColor(s.blood), ink = goreInk(s);
  for (let i = 0; i < count; i++) {
    const inJet = jet && i < count / 3, fan = spread * (inJet ? 0.25 : 1), a = a0 + rnd(-fan, fan) * Math.PI / 180, v = speed * (inJet ? rnd(0.9, 1.35) : rnd(0.3, 1.1));
    goreDrop(x + rnd(-3, 3), y + rnd(-3, 3), Math.cos(a) * v, Math.sin(a) * v - rnd(10, 60), goreShaded(c, +s.shade || 0), ink);
  }
  const faint = [c[0], c[1], c[2], c[3] * 0.45];
  for (let i = 0, n = Math.round((+s.mist || 0) * Math.min(2, Math.max(0.5, count / Math.max(+s.drops, 1)))); i < n; i++) {
    const a = a0 + rnd(-spread, spread) * 1.4 * Math.PI / 180, v = speed * rnd(0.1, 0.45);
    goreDrop(x + rnd(-4, 4), y + rnd(-4, 4), Math.cos(a) * v, Math.sin(a) * v, goreShaded(faint, +s.shade || 0), ink, MISTY);
  }
}
/* Gore.mark. face: 0 a floor, 1 a wall (runs down by the ink's `run`, never past the wall's foot), 2 under a
 * ledge (drips), 3 the painted wall behind. kind: 0 a smear, 1 a splat, 2 a broken trail (-1 picks).
 * span: the surface it lies on — not drawn past it; what a floor mark reaches over the edge with drips off */
function goreMark(x, y, w, face, c, ink, grow = 0.25, kind = -1, span = [-Infinity, Infinity]) {
  const life = ink.life; if (w < 0.5 || life <= 0) return; if (GORE.stains.length > 520) GORE.stains.shift();
  if (kind < 0) kind = [0, 0, 1, 2][Math.floor(Math.random() * 4)];
  x = Math.round(x); y = Math.round(y);
  let length = w;
  if (face === 1 || face === 3) {
    length = w * rnd(0.7, 1.4) + ink.run * rnd(0.2, 1.2) * (face === 3 ? 0.4 : 1);
    if (face === 1) length = Math.min(length, span[1] - y);
    grow = Math.max(grow, length / rnd(6, 16));
  } else if (face === 0 && isFinite(span[0])) {
    for (const edge of span) if (Math.abs(x - edge) < Math.max(w * 0.6, 2) && Math.random() < 0.35 + ink.drip) goreDripFrom(edge + (edge === span[0] ? -0.5 : 0.5), y, c, ink, 1 + Math.floor(Math.random() * 3));
  } else if (face === 2 && Math.random() < ink.drip * 2) goreDripFrom(x, y + 1, c, ink, 1 + Math.floor(Math.random() * 4));
  GORE.stains.push({ x, y, w: length, spot: w, face, c, born: GORE.clock, grow, life: life * rnd(0.8, 1.2), seed: Math.random(), kind, soak: ink.soak, lo: span[0], hi: span[1] });
}
function goreDripFrom(x, y, c, ink, left) { if (GORE.drips.length >= 40) GORE.drips.shift(); GORE.drips.push({ x, y, c, ink, left, tick: rnd(0.2, 0.9) }); }
function gorePool(x, y, s, st) {
  const c = goreColor(s.blood).map((v, i) => i < 3 ? v * 0.85 : v), shade = (+s.shade || 0) * 0.5, w = +s.pool, span = [-Infinity, Infinity], ink = goreInk(s);
  goreMark(x, y, w * rnd(0.8, 1.2), 0, goreShaded(c, shade), { ...ink, life: +s.stain_life * 1.4 }, rnd(1.2, 2.2), 0, span);
  for (let i = 0, n = 1 + Math.floor(Math.random() * 3); i < n; i++) goreMark(x + rnd(-w, w) * 0.6, y, w * rnd(0.25, 0.5), 0, goreShaded(c, shade), ink, rnd(0.8, 2.6), 0, span);
}
/* where a drop going from (x, y) to (nx, ny) meets the stage: [x, y, face (0 floor / 1 wall / 2 underside), span] */
function goreHitStage(x, y, nx, ny, st) {
  const L = st.ledge;
  if (nx >= st.wall && x < st.wall) { const at = y + (ny - y) * (st.wall - x) / ((nx - x) || 1); if (at < st.foot) return [st.wall, at, 1, [0, st.foot]]; }
  if (ny < y && y >= st.foot && ny < st.foot && nx >= st.wall) return [nx, st.foot, 2, [st.wall, Infinity]];
  if (ny > y && y <= L.top && ny >= L.top && nx >= L.x0 && nx <= L.x1) return [nx, L.top, 0, [L.x0, L.x1]];
  if (ny < y && y >= L.bottom && ny <= L.bottom && nx >= L.x0 && nx <= L.x1) return [nx, L.bottom, 2, [L.x0, L.x1]];
  if (ny > y && ny >= st.ground) return [nx, st.ground, 0, [-Infinity, Infinity]];
  return null;
}
const goreInOpening = (x, y, st) => x >= st.opening[0] && x <= st.opening[0] + st.opening[2] && y >= st.opening[1] && y <= st.opening[1] + st.opening[3];
function goreHit(crit) {
  const s = goreNow(), st = goreStage(GORE.W, GORE.H), back = $('#goreBack').checked;
  const weight = 1 + (crit ? 0.6 : 0) + (back ? 1 : 0) + 0.3;
  goreSpray(st.origin[0] - 4, st.origin[1] - 10, [1, -0.3], Math.round(+s.drops * Math.min(2.5, Math.max(0.5, weight)) * rnd(0.75, 1.25)), s, 38);
  if (+s.bleed > 0) GORE.wound = Math.max(GORE.wound, +s.bleed * Math.min(2, Math.max(0.6, weight)));
  GORE.state = 'hurt'; GORE.stateT = GORE.clock; GORE.flash = 1;
}
function goreDeath() {
  const s = goreNow(), st = goreStage(GORE.W, GORE.H), b = goreBody(), violent = $('#goreBack').checked, away = [1, -0.2];
  goreSpray(st.origin[0], st.origin[1] - 10, [away[0], away[1] + rnd(-0.9, -0.3)], Math.round(+s.gush * rnd(0.75, 1.25)), s, rnd(55, 90));
  if (+s.pool > 0) gorePool(st.origin[0], st.ground, s, st);
  const f = goreFrame(b, GORE.state === 'hurt' ? 'hurt' : 'idle'), limbs = +s.limbs;
  const torn = !b.boss && f && limbs >= 2 && ($('#goreAlways').checked || Math.random() < +s.chance * (violent ? 2 : 1));
  const way = torn ? (GORE.way && GORE.way !== 'any' ? (GORE.way === 'limb' && limbs < 5 ? 'head' : GORE.way) : gorePickCut(s.cuts, limbs)) : '';
  GORE.verdict = b.boss ? 'босс не рвётся — он остаётся для последних слов' : limbs < 2 ? 'не рвётся (кусков 0)'
    : torn ? (way === 'all' ? `разорван на ${limbs}: ${GORE_CUT[limbs]}` : way === 'head' ? 'голова прочь — тело стоит миг и валится' : way === 'half' ? 'разрублен пополам — ноги стоят миг и валятся' : 'отрублена рука — тело стоит миг и валится')
    : `цел (шанс ${Math.round(+s.chance * (violent ? 2 : 1) * 100)}%)`;
  if (torn) {
    const sc = +b.body.scale || 1, bounds = goreBounds(f), w = f.cw * sc, h = f.ch * sc;
    const left = b.body.hero ? st.origin[0] - (f.cw - 68) * sc : st.origin[0] - w / 2, top = b.body.hero ? st.ground - 4 - h : st.origin[1] + 12 - h + (+b.body.pad_y || 0) * sc;
    const cx = bounds[0] + bounds[2] / 2, cy = bounds[1] + bounds[3] / 2, al = Math.hypot(...away), ax = away[0] / al, ay = away[1] / al, side = Math.sign(ax) || 1, hold = rnd(0.12, 0.45);
    const im = b.body.tint ? shotTinted(f.im, f.url, b.body.tint) : f.im;
    for (const part of goreCut(bounds, limbs, way, GORE_RAGGED)) {
      const r = part.rect, lx = r[0] + r[2] / 2, ly = r[1] + r[3] / 2;
      const out = [-(lx - cx), ly - cy], ol = Math.hypot(...out) || 1;      // the body faces left: mirrored, as flip_h
      const p = { im, sx: f.fi * f.cw + r[0], sy: r[1], sw: r[2], sh: r[3], sc, hx: Math.max(1, r[2] * sc / 2), hy: Math.max(1, r[3] * sc / 2),
        x: left + (f.cw - lx) * sc, y: top + ly * sc, rot: 0, spin: 0, hold: 0, target: null, tv: 0, rest: false, floor: 0, lain: 0, air: 0,
        bleed: Math.max(+s.bleed, 0.4) * rnd(1.1, 2), drip: 0, stump: null, spurt: 0, spurtFull: 0, pulse: 0, s, c: goreColor(s.blood) };
      if (part.stands) { p.vx = side * rnd(5, 25); p.vy = 0; p.hold = hold + rnd(0, 0.08); p.target = side * Math.PI / 2 * rnd(0.85, 1); }
      else {
        let dx = out[0] / ol * rnd(0.5, 0.9) + ax * rnd(0.6, 1) + rnd(-0.2, 0.2), dy = out[1] / ol * rnd(0.5, 0.9) + ay * rnd(0.6, 1) - 1; const dl = Math.hypot(dx, dy) || 1;
        const v = +s.fling * rnd(0.55, 1.15) * (part.name === 'head' ? rnd(1.1, 1.35) : 1);
        p.vx = dx / dl * v; p.vy = dy / dl * v; p.spin = rnd(-14, 14) * (1 + Math.hypot(ax, ay));
      }
      if (part.stump && +s.spurt > 0) {
        const d = [-part.stump[0], part.stump[1]];
        p.stump = { at: [d[0] * r[2] * 0.5, d[1] * r[3] * 0.5], dir: d }; p.spurt = p.spurtFull = +s.spurt * rnd(0.6, 1.3) * (part.stands ? 1.4 : 1);
      }
      GORE.pieces.push(p);
    }
    goreSpray(st.origin[0], st.origin[1] - 10, [side * 0.3, -1], Math.floor(+s.gush * rnd(0.3, 0.6)), s, 70);
    GORE.hidden = true;
  } else { GORE.state = 'death'; GORE.stateT = GORE.clock; }
  GORE.dead = GORE.clock; renderGoreVerdict();
}
/* GorePiece: how far the turned piece reaches from its centre, sideways and down */
const goreReach = p => { const c = Math.abs(Math.cos(p.rot)), s = Math.abs(Math.sin(p.rot)); return [p.hx * c + p.hy * s, p.hy * c + p.hx * s]; };
const goreTurn = (p, v) => [(v[0] * Math.cos(p.rot) - v[1] * Math.sin(p.rot)), (v[0] * Math.sin(p.rot) + v[1] * Math.cos(p.rot))];
function gorePieceBleed(p, dt) {
  const s = p.s, shade = +s.shade || 0, root = p.stump ? goreTurn(p, [p.stump.at[0] * p.sc, p.stump.at[1] * p.sc]).map((v, i) => v + (i ? p.y : p.x)) : [p.x, p.y];
  if (p.bleed > 0) { p.bleed -= dt; p.drip -= dt; if (p.drip <= 0) { p.drip = (p.rest ? 0.22 : 0.05) * rnd(0.6, 1.5); goreDrop(root[0], root[1], rnd(-20, 20) - p.vx * 0.1, rnd(-30, 10) - p.vy * 0.1, goreShaded(p.c, shade), goreInk(s, 0.8)); } }
  if (p.spurt <= 0) return;
  p.spurt -= dt; p.pulse -= dt; if (p.pulse > 0) return;
  // a heartbeat that weakens: each pulse a jet of a few drops out of the stump
  const strength = Math.min(1, Math.max(0.2, p.spurt / Math.max(p.spurtFull, 0.01))), dir = goreTurn(p, p.stump.dir);
  p.pulse = rnd(0.14, 0.26) / (0.6 + strength * 0.4);
  for (let i = 0, n = 2 + Math.floor(Math.random() * 3); i < n; i++) {
    const a = rnd(-0.25, 0.25), v = rnd(80, 170) * strength;
    goreDrop(root[0], root[1], (dir[0] * Math.cos(a) - dir[1] * Math.sin(a)) * v + p.vx * 0.5, (dir[0] * Math.sin(a) + dir[1] * Math.cos(a)) * v + p.vy * 0.5, goreShaded(p.c, shade), goreInk(s, 0.9));
  }
}
function gorePieceStep(p, dt, st) {
  gorePieceBleed(p, dt);
  if (p.hold > 0) { p.hold -= dt; return; }
  if (p.target !== null && (p.rest || p.spin === 0)) { p.tv += TOPPLE * dt; const d = p.target - p.rot, m = p.tv * dt; p.rot = Math.abs(d) <= m ? p.target : p.rot + Math.sign(d) * m; }
  if (p.rest) { p.y = p.floor - goreReach(p)[1]; p.lain += dt; return; }
  p.air += dt; p.vy += PIECE_G * dt;
  if (p.target === null || p.spin !== 0) p.rot += p.spin * dt;
  p.x += p.vx * dt; p.y += p.vy * dt;
  const [rx, ry] = goreReach(p), shade = +p.s.shade || 0;
  if (p.x + rx >= st.wall && p.vx > 0) { p.x = st.wall - rx; goreMark(st.wall, p.y, rnd(2, 4.5) * +p.s.stain, p.y < st.foot ? 1 : 3, goreShaded(p.c, shade), goreInk(p.s), 0.25, -1, [0, st.foot]); p.vx = -p.vx * BOUNCE; p.spin = -p.spin; }
  if (p.y + ry >= st.ground && p.vy > 0) {
    p.y = st.ground - ry; goreMark(p.x, st.ground, rnd(2, 4.5) * +p.s.stain, 0, goreShaded(p.c, shade), goreInk(p.s));
    p.vx *= rnd(0.4, 0.65); p.vy = -Math.abs(p.vy) * BOUNCE * rnd(0.7, 1.2); p.spin *= rnd(0.3, 0.6);
    if (Math.abs(p.vy) < 40) { p.vx = p.vy = 0; p.rest = true; p.floor = st.ground; if (p.target === null) p.target = Math.round(p.rot / (Math.PI / 2)) * Math.PI / 2; p.spin = 0; }
  }
}
function goreStep(dt, st) {
  for (const dr of GORE.drips) { dr.tick -= dt; if (dr.tick <= 0) { goreDrop(dr.x, dr.y, rnd(-3, 3), rnd(0, 20), dr.c, dr.ink, SPLASHED); dr.left--; dr.tick = rnd(0.35, 1.4); } }
  GORE.drips = GORE.drips.filter(dr => dr.left > 0);
  const born = [];
  GORE.drops = GORE.drops.filter(d => {
    const misty = d.flags & MISTY;
    d.vy += GORE_G * dt * (misty ? 0.35 : 1); d.vx *= 1 - (misty ? 3 : 0.6) * dt; d.age += dt;
    const nx = d.x + d.vx * dt, ny = d.y + d.vy * dt;
    if (misty) { d.x = nx; d.y = ny; return d.age < d.fade; }
    if (d.flags & BACK && d.age >= d.lands) {   // flew into the depth and met the painted wall behind
      if (!goreInOpening(d.x, d.y, st)) goreMark(d.x, d.y, rnd(1, 2.5) * d.ink.stain * d.px, 3, d.c, d.ink, 0.25, [1, 1, 0][Math.floor(Math.random() * 3)]);
      return false;
    }
    const hit = d.flags & BACK ? null : goreHitStage(d.x, d.y, nx, ny, st);
    if (hit) {
      const [hx, hy, face, span] = hit, size = d.ink.stain * d.px * (d.flags & SPLASHED ? 0.5 : 1);
      goreMark(hx, hy, (face === 1 ? rnd(1, 2.5) : face === 2 ? rnd(1, 2) : rnd(1, 3.5)) * size, face, d.c, d.ink, 0.25, face === 2 ? 0 : -1, span);
      const speed = Math.hypot(d.vx, d.vy);
      if (face === 0 && !(d.flags & SPLASHED) && speed > SPLASH_SPEED) {   // a heavy drop splashes back up
        const force = Math.min(1, Math.max(0.3, speed / 320));
        for (let i = 0, n = Math.round(d.ink.splash * rnd(0.3, 1.3) * force); i < n; i++) born.push([hx, hy - 1, rnd(-55, 55) + d.vx * 0.2, -rnd(35, 95) * force, d.c, d.ink]);
      }
      return false;
    }
    d.x = nx; d.y = ny; return d.age < 4;
  });
  for (const b of born) goreDrop(b[0], b[1], b[2], b[3], b[4], b[5], SPLASHED);
  if (GORE.wound > 0) { GORE.wound -= dt; GORE.drip -= dt; if (GORE.drip <= 0 && !GORE.hidden) { GORE.drip = rnd(0.07, 0.16); const s = goreNow(); goreDrop(st.origin[0] - 4 + rnd(-3, 3), st.origin[1] - 10, rnd(-15, 15), rnd(-10, 20), goreShaded(goreColor(s.blood), +s.shade || 0), goreInk(s, 0.7)); } }
  for (const p of GORE.pieces) gorePieceStep(p, dt, st);
  GORE.pieces = GORE.pieces.filter(p => p.lain < LIE + FADE && p.air < 5);
  GORE.stains = GORE.stains.filter(s => GORE.clock - s.born < s.life);
}
/* Gore._paint: every mark as it lies (less what soaked in), or soaked — the share that sank in, multiplied
 * into the picture under it (white changes nothing) */
function gorePaint(x, soaked) {
  if (soaked) x.globalCompositeOperation = 'multiply';
  for (const s of GORE.stains) {
    const age = GORE.clock - s.born, g = Math.min(1, age / Math.max(s.grow, 0.01)), grown = 1 - (1 - g) * (1 - g), fade = Math.min(1, Math.max(0, (s.life - age) / 3)), w = Math.max(1, Math.round(s.w * grown));
    if (soaked && !(s.soak > 0)) continue;
    const k = soaked ? s.soak * s.c[3] * fade : 0, a = soaked ? 1 : fade * (1 - s.soak * 0.85);
    if (!soaked && a <= 0.01) continue;
    const col = soaked ? [255 + (s.c[0] - 255) * k, 255 + (s.c[1] - 255) * k, 255 + (s.c[2] - 255) * k, 1] : s.c;
    let seed = Math.floor(s.seed * 1e4); const r = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);
    const dot = (px, py, pw, ph, dark = 0) => { x.fillStyle = goreRgba(col, a, dark); x.fillRect(px, py, pw, ph); };
    const span = (px, py, pw, ph, dark = 0) => { const l = Math.max(px, s.lo), rr = Math.min(px + pw, s.hi); if (rr > l) dot(l, py, rr - l, ph, dark); };
    if (s.face === 1) {   // a streak running down, a drop gathering at its end; some fork
      dot(s.x - 1, s.y - 1, 1, w); if (w > 3) dot(s.x - 1, s.y + w - 1, 1, 1, 0.3);
      if (s.kind === 1 && w > 4) dot(s.x - 1 + (s.seed < 0.5 ? 1 : -1), s.y + Math.floor(w / 3), 1, Math.floor(w / 2), 0.1);
    } else if (s.face === 2) {   // under a ledge: a blot clinging on, a bead hanging off it
      const rr = Math.max(1, Math.round(s.spot * grown)); span(s.x - Math.floor(rr / 2), s.y, rr, 1); if (rr >= 2) dot(s.x - Math.round(r()), s.y + 1, 1, 1, 0.25);
    } else if (s.face === 3) {   // on the painted wall behind: a splat, its spatter, what runs down from it
      const rr = Math.max(1, Math.floor(s.spot * 0.6)); dot(s.x - Math.floor(rr / 2), s.y - Math.floor(rr / 2), rr, rr);
      for (let q = 0, n = 1 + Math.floor(r() * 3); q < n; q++) dot(s.x + Math.round(r() * 6 - 3), s.y + Math.round(r() * 5 - 3), 1, 1);
      if (w > rr) { dot(s.x - Math.round(r() * Math.floor(rr / 2)), s.y, 1, w, 0.1); dot(s.x, s.y + w, 1, 1, 0.3); }
    } else if (s.kind === 1) {   // a splat: a blot two rows deep and spatter round it
      const rr = Math.max(1, Math.floor(w / 3)); span(s.x - rr, s.y - 1, rr * 2, 1); span(s.x - Math.floor(rr / 2), s.y - 2, Math.max(1, rr), 1, 0.15);
      for (let q = 0; q < Math.max(2, Math.floor(w / 2)); q++) span(Math.round(s.x + (r() * 2 - 1) * w), s.y - 1 - Math.round(r()), 1, 1);
    } else if (s.kind === 2) {   // a broken trail: dashes along the lip
      for (let at = s.x - Math.floor(w / 2); at < s.x + w / 2;) { const dash = 1 + Math.floor(r() * 3); span(at, s.y - 1, dash, 1); at += dash + 1 + Math.floor(r() * 2); }
    } else {   // a smear, thicker in the middle, a few spatters beside
      span(s.x - Math.floor(w / 2), s.y - 1, w, 1);
      if (w >= 4) span(s.x - Math.floor(w / 4), s.y - 2, Math.max(1, Math.floor(w / 2)), 1, 0.2);
      if (w >= 7) for (let q = 0; q < Math.floor(w / 5); q++) span(Math.round(s.x + (r() * 1.6 - 0.8) * w), s.y - 1 - Math.round(r()), 1, 1);
    }
  }
  x.globalCompositeOperation = 'source-over';
}
function goreDraw(x, st) {
  gorePaint(x, true); gorePaint(x, false);
  for (const p of GORE.pieces) {
    x.save(); x.globalAlpha = p.lain > LIE ? Math.max(0, 1 - (p.lain - LIE) / FADE) : 1; x.translate(Math.round(p.x), Math.round(p.y)); x.rotate(p.rot); x.scale(-1, 1);
    x.imageSmoothingEnabled = false; x.drawImage(p.im, p.sx, p.sy, p.sw, p.sh, -p.sw * p.sc / 2, -p.sh * p.sc / 2, p.sw * p.sc, p.sh * p.sc); x.restore();
  }
  for (const d of GORE.drops) { x.fillStyle = goreRgba(d.c, d.flags & BACK ? 1 - 0.5 * Math.min(1, d.age / d.lands) : 1); x.fillRect(Math.round(d.x), Math.round(d.y), d.px, (Math.abs(d.vy) > 120 ? 2 : 1) + d.px - 1); }
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
  goreBackdrop(x, W, H, st);
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
/* the painted wall behind (bricks, so a soaked mark shows the texture through it), the sky's opening, the
 * ledge, the wall on the right ending in the air above the floor */
function goreBackdrop(x, W, H, st) {
  if (!GORE.wallArt || GORE.wallArt.width !== W || GORE.wallArt.height !== H) {
    const c = GORE.wallArt = mk(W, H), b = c.getContext('2d'); let seed = 7; const r = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);
    b.fillStyle = '#4a4250'; b.fillRect(0, 0, W, H);
    for (let row = 0, y = 0; y < st.ground; row++, y += 7) for (let xx = row % 2 ? -8 : 0; xx < W; xx += 16) {
      const v = 70 + Math.floor(r() * 26); b.fillStyle = `rgb(${v},${v - 8},${v + 4})`; b.fillRect(xx + 1, y + 1, 15, 6);
      if (r() < 0.25) { b.fillStyle = `rgb(${v - 18},${v - 24},${v - 14})`; b.fillRect(xx + 2 + Math.floor(r() * 12), y + 2 + Math.floor(r() * 3), 2, 1); }
    }
    const [ox, oy, ow, oh] = st.opening, sky = b.createLinearGradient(0, oy, 0, oy + oh); sky.addColorStop(0, '#1b2440'); sky.addColorStop(1, '#4a3f5e');
    b.fillStyle = sky; b.fillRect(ox, oy, ow, oh); b.fillStyle = '#e8e2c8'; b.fillRect(ox + ow - 14, oy + 6, 3, 3);
    b.fillStyle = '#2d2733'; b.fillRect(ox - 2, oy + oh, ow + 4, 2);
  }
  x.drawImage(GORE.wallArt, 0, 0);
  x.fillStyle = '#26212c'; x.fillRect(0, st.ground, W, H - st.ground); x.fillRect(st.wall, 0, W - st.wall, st.foot);
  x.fillRect(st.ledge.x0, st.ledge.top, st.ledge.x1 - st.ledge.x0, st.ledge.bottom - st.ledge.top);
  x.fillStyle = '#5a5163'; x.fillRect(0, st.ground, W, 1); x.fillRect(st.wall, 0, 1, st.foot); x.fillRect(st.ledge.x0, st.ledge.top, st.ledge.x1 - st.ledge.x0, 1);
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
    <div class="card"><b>Удар</b>${['blood', 'shade', 'drops', 'spray', 'mist', 'stain', 'stain_life', 'bleed'].map(k => field(k, shown[k], k in own)).join('')}</div>
    <div class="card"><b>Где ложится</b>${['soak', 'splash', 'run', 'drip', 'back'].map(k => field(k, shown[k], k in own)).join('')}
      <div class="muted">Пятно не заходит за край того, на чём лежит: что свисает с уступа — капает вниз, потёк по стене кончается там, где кончается стена, с нижней стороны уступа капает. Капли «на фон» липнут к нарисованной стене позади, но не к небу и не к дальним проёмам. «Впитывается» — пятно умножается на картинку под ним, и сквозь кровь видна кладка.</div></div>
    <div class="card"><b>Смерть</b>${['gush', 'pool', 'limbs', 'chance', 'fling', 'spurt'].map(k => field(k, shown[k], k in own)).join('')}
      <div class="muted">${+shown.limbs >= 2 ? 'Режется сам рисунок — кадр, в котором умер; линии разреза рваные, каждый раз другие.' : 'Тело не рвётся — играет своя анимация смерти.'}${b.boss ? ' Боссы не рвутся никогда.' : ''}</div></div>
    ${+shown.limbs >= 2 ? `<div class="card"><b>Как рвётся</b> ${scope === 'body' ? ('cuts' in own ? '<span class="badge new">своё</span> <button class="sm" data-act="gore-unset" data-k="cuts" title="Убрать своё — брать из материала">↺</button>' : '<span class="muted">от материала</span>') : ''}
      ${Object.entries(GORE_WAYS).map(([w, label]) => { const v = +((shown.cuts || {})[w] || 0), off = w === 'limb' && +shown.limbs < 5;
        return `<div class="row" style="margin:0;gap:6px"><label class="lifenum grow">${label}${w === 'all' ? ' (' + GORE_CUT[Math.min(6, +shown.limbs)] + ')' : ''}${off ? ' <span class="muted">— без рук: голова</span>' : ''} <span class="muted">${v}</span><input type="range" data-gorecut="${w}" min="0" max="10" step="1" value="${v}"></label></div>`; }).join('')}
      <div class="muted">Вес способа: чем больше, тем чаще. Что осталось стоять — стоит миг, бьёт струёй из обрубка и валится туда, куда пришёлся удар.</div>
      <label>В превью <select id="goreWay">${[['any', 'по весам'], ...Object.entries(GORE_WAYS)].map(([w, l]) => `<option value="${w}"${GORE.way === w ? ' selected' : ''}>${l}</option>`).join('')}</select></label></div>` : ''}
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
  if (el.id === 'goreWay') { GORE.way = el.value; return; }
  if (el.dataset.gorecut) {
    const w = el.dataset.gorecut, v = +el.value; if (el.previousElementSibling) el.previousElementSibling.textContent = v;
    goreEdit(t => { t.cuts = { ...(t.cuts || goreNow().cuts || {}), [w]: v }; });
    if (e.type === 'change') renderGore(); return;
  }
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
