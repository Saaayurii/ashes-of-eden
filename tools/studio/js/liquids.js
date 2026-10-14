/* Sprite Studio — water, lava, bog and blood («Жидкости»).
 * Two halves. «В комнате»: pools laid on a room's map — tools/rooms/studio_rooms.json, per room
 * "liquids": [[kind, x, y, w, h, {"painted": true}?]] in finished-room pixels, y the SURFACE and h the
 * depth below it — drawn alive over the room, the lava the painted rooms already carry (scripts/rooms/hazard.gd
 * nodes in the scene) shown read-only beside them. «Виды»: data/liquids.json, every number of every kind, with
 * a pool to throw a body into.
 *
 * The look ports scripts/rooms/hazard.gd: a 1D spring surface (a column every LIQ_COL px; each column
 * v += -spring·h - damping·v, h += v, then a few passes where neighbours pull on each other by spread),
 * a resting wave sin(x/length·2π + t·speed)·amplitude laid on top, the body a vertical gradient
 * surface → body → deep at `opacity` (`painted_opacity` when the painting already shows it), a 1-px line of
 * `foam` on top, `shimmer` glints, the body texture (assets/fx/liquids/body_<kind>.png) drifting by `flow`,
 * and the kind's particles and light. Change one, change the other.
 * Drafts live in WORLD.work like every «Данные» tab (js/gamedata.js); liquids.json is written back in its own
 * layout by liqText (byte for byte when unchanged, tests/liquids.test.js). */
'use strict';

const LIQ_PATH = 'data/liquids.json', LIQ_ROOMS = 'tools/rooms/studio_rooms.json';
const LIQ_COL = 4, LIQ_MIN_W = 16, LIQ_MIN_H = 8, LIQ_SNAP = 6;
const LIQ_BASE_KINDS = ['water', 'lava', 'bog', 'blood'];
const LIQ_KIND_RU = { water: 'Вода', lava: 'Лава', bog: 'Топь', blood: 'Кровь' };
const LIQ_COLORS = { surface: 'Поверхность', body: 'Толща', deep: 'Глубина', foam: 'Кромка, пена', glow: 'Свечение' };
const LIQ_PARTICLES = {
  ambient: { glints: 'блики', embers: 'угли', gas: 'пузыри газа', clots: 'сгустки', none: 'нет' },
  splash: { drops: 'капли', magma: 'магма', mud: 'грязь', blood: 'кровь' },
  trail: { drips: 'капает', smoke: 'дымится', mud: 'грязь', none: 'нет' },
};
const LIQ_HEAL_PATHS = { grace: 'Благодать', temptation: 'Искушение', will: 'Воля' };
const LIQ_MATERIALS = ['flesh', 'cloth', 'mail', 'plate', 'bone', 'feather', 'spirit', 'gold'];
const LIQ_SOUNDS = { enter: 'Вход', big: 'Вход с высоты', exit: 'Выход', wade: 'Бред, гребок', ambient: 'Фон (петля)', bubble: 'Пузырь' };
const LIQ_FLAGS = { burns: 'Жжёт: ожог и назад на последний пол', kills_walkers: 'Пешие враги гибнут в ней', douses: 'Гасит горение' };
// [section, path, label, min, max, step] — the bounds the studio allows (and checks before sending)
const LIQ_FIELDS = [
  ['Вид', 'opacity', 'Непрозрачность', 0, 1, 0.01],
  ['Вид', 'painted_opacity', 'Непрозрачность поверх картины («уже нарисовано»)', 0, 1, 0.01],
  ['Вид', 'flow', 'Течение текстуры (доля ширины в секунду)', -0.5, 0.5, 0.005],
  ['Вид', 'shimmer', 'Блики на поверхности', 0, 1, 0.01],
  ['Волны', 'waves.amplitude', 'Спокойная волна, высота px', 0, 6, 0.1],
  ['Волны', 'waves.speed', 'Спокойная волна, скорость', 0, 4, 0.05],
  ['Волны', 'waves.length', 'Спокойная волна, длина px', 8, 200, 1],
  ['Волны', 'waves.spring', 'Упругость поверхности', 0.001, 0.1, 0.001],
  ['Волны', 'waves.damping', 'Затухание ряби', 0, 0.3, 0.005],
  ['Волны', 'waves.spread', 'Рябь бежит к соседям', 0, 0.5, 0.01],
  ['Волны', 'waves.splash', 'Сила всплеска', 0, 3, 0.05],
  ['Тело', 'body.drag', 'Скорость в ней × (меньше — вязче)', 0, 1, 0.01],
  ['Тело', 'body.buoyancy', 'Тяжесть в ней × (меньше — сильнее держит)', 0, 1, 0.01],
  ['Тело', 'body.sink_speed', 'Тонет не быстрее, px/с', 0, 300, 1],
  ['Тело', 'body.swim', 'Гребок вверх, px/с (0 — не плавается)', 0, 500, 5],
  ['Тело', 'body.swim_cooldown', 'Между гребками, с', 0.05, 2, 0.01],
  ['Тело', 'body.jump', 'Прыжок из неё ×', 0, 1.5, 0.01],
  ['Урон', 'damage', 'Урон герою за касание', 0, 100, 1],
  ['Враги', 'enemy.drag', 'Скорость врагов в ней ×', 0, 1, 0.01],
  ['Враги', 'enemy.heal_per_second', 'Лечит врагов, ед/с', 0, 20, 0.1],
  ['Исцеление', 'heal.per_second', 'Лечит героя, ед/с', 0, 10, 0.1],
  ['Частицы', 'particles.ambient_every', 'Фоновые частицы, каждые с', 0.05, 5, 0.05],
  ['Частицы', 'particles.trail_time', 'След на вышедшем, с', 0, 5, 0.1],
  ['Свет', 'light.radius', 'Радиус, px', 0, 200, 1],
  ['Свет', 'light.energy', 'Яркость', 0, 2, 0.05],
  ['Свет', 'light.every', 'Огонёк каждые, px', 20, 400, 1],
  ['Свет', 'light.flicker', 'Мерцание', 0, 1, 0.01],
];
const LIQ_HARM_MAX = 200;

/* ---------- pure helpers (tests/liquids.test.js) ---------- */
const liqName = k => LIQ_KIND_RU[k] || k;
const liqGet = (o, path) => path.split('.').reduce((a, k) => a == null ? undefined : a[k], o);
function liqSet(o, path, v) { const ks = path.split('.'); let a = o; for (const k of ks.slice(0, -1)) a = a[k] && typeof a[k] === 'object' ? a[k] : (a[k] = {}); a[ks.at(-1)] = v; return o; }
function liqRgb(h, fallback = '#808080') {
  const s = String(h || fallback).replace('#', ''), n = parseInt(s.slice(0, 6), 16);
  return Number.isFinite(n) ? [n >> 16 & 255, n >> 8 & 255, n & 255] : liqRgb(fallback);
}
// data/liquids.json as the game keeps it: a kind a block, each of its keys on one line, every number a float
function liqText(doc) {
  const num = v => Number.isInteger(v) ? v.toFixed(1) : String(v);
  const one = v => typeof v === 'number' ? num(v) : Array.isArray(v) ? '[' + v.map(one).join(', ') + ']'
    : v && typeof v === 'object' ? '{' + Object.entries(v).map(([k, x]) => JSON.stringify(k) + ': ' + one(x)).join(', ') + '}' : JSON.stringify(v);
  const kind = v => '{\n' + Object.entries(v).map(([k, x]) => `      ${JSON.stringify(k)}: ${one(x)}`).join(',\n') + '\n    }';
  const top = Object.entries(doc).map(([k, v]) => k === 'kinds' && v && typeof v === 'object'
    ? `  "kinds": {\n` + Object.entries(v).map(([id, x]) => `    ${JSON.stringify(id)}: ${kind(x)}`).join(',\n') + '\n  }'
    : `  ${JSON.stringify(k)}: ${one(v)}`);
  return '{\n' + top.join(',\n') + '\n}\n';
}
// The spring surface: one step at 60 Hz. h is how far each column stands below its rest (y grows down).
function liqSim(w) { const n = Math.max(2, Math.ceil(w / LIQ_COL) + 1); return { h: new Float32Array(n), v: new Float32Array(n) }; }
function liqSpringStep(s, waves, passes = 4) {
  const k = +waves?.spring || 0, d = +waves?.damping || 0, sp = +waves?.spread || 0, n = s.h.length;
  for (let i = 0; i < n; i++) { s.v[i] += -k * s.h[i] - d * s.v[i]; s.h[i] += s.v[i]; }
  const L = new Float32Array(n), R = new Float32Array(n);
  for (let p = 0; p < passes; p++) {
    for (let i = 0; i < n; i++) {
      L[i] = i > 0 ? sp * (s.h[i] - s.h[i - 1]) : 0; R[i] = i < n - 1 ? sp * (s.h[i] - s.h[i + 1]) : 0;
      if (i > 0) s.v[i - 1] += L[i]; if (i < n - 1) s.v[i + 1] += R[i];
    }
    for (let i = 0; i < n; i++) { if (i > 0) s.h[i - 1] += L[i]; if (i < n - 1) s.h[i + 1] += R[i]; }
  }
  return s;
}
// a body of `width` px hitting the surface at x (pool pixels) at `speed` px/s pushes the columns under it down
function liqSplash(s, x, width, speed, waves) {
  const push = speed * (+waves?.splash || 0) * 0.012, from = Math.floor((x - width / 2) / LIQ_COL), to = Math.ceil((x + width / 2) / LIQ_COL);
  for (let i = Math.max(0, from); i <= Math.min(s.h.length - 1, to); i++) s.v[i] += push;
  return s;
}
const liqWave = (x, t, waves) => Math.sin(x / Math.max(1, +waves?.length || 50) * Math.PI * 2 + t * (+waves?.speed || 0)) * (+waves?.amplitude || 0);
// where the surface stands at x (pool pixels): the springs between their columns, plus the resting wave
function liqSurfaceAt(s, x, t, waves) {
  const f = Math.max(0, Math.min(s.h.length - 1.001, x / LIQ_COL)), i = Math.floor(f), u = f - i;
  return s.h[i] * (1 - u) + s.h[i + 1] * u + liqWave(x, t, waves);
}
// a pool's surface laid on a floor top it nearly touches (surfaces: [x, top, width] from the room's colliders)
function liqSnap(surfaces, x, y, w, tol = LIQ_SNAP) {
  let best = y, gap = tol + 1;
  for (const [sx, sy, sw] of surfaces || []) if (sx < x + w && sx + sw > x && Math.abs(sy - y) < gap) { best = sy; gap = Math.abs(sy - y); }
  return Math.round(best);
}
// a rectangle back into whole pixels inside the room
function liqClamp([x, y, w, h], room) {
  const W = room?.width ?? Infinity, H = room?.height ?? Infinity;
  w = Math.max(1, Math.round(Math.min(w, W))); h = Math.max(1, Math.round(Math.min(h, H)));
  x = Math.round(Math.max(0, Math.min(x, W - w))); y = Math.round(Math.max(0, Math.min(y, H - h)));
  return [x, y, w, h];
}
// what is under the pointer: a handle of the selected pool, or the body of any (the last drawn wins)
function liqHit(list, x, y, tol, sel = -1) {
  const inside = (r, g = 0) => x >= r[1] - g && x <= r[1] + r[3] + g && y >= r[2] - g && y <= r[2] + r[4] + g;
  if (sel >= 0 && list[sel] && inside(list[sel], tol)) {
    const r = list[sel], n = Math.abs(y - r[2]) <= tol, s = Math.abs(y - (r[2] + r[4])) <= tol, w = Math.abs(x - r[1]) <= tol, e = Math.abs(x - (r[1] + r[3])) <= tol;
    const part = (n ? 'n' : s ? 's' : '') + (w ? 'w' : e ? 'e' : '');
    if (part) return { i: sel, part };
  }
  for (let i = list.length - 1; i >= 0; i--) if (Array.isArray(list[i]) && inside(list[i])) return { i, part: 'move' };
  return null;
}
// a pool dragged by one of its parts by (dx, dy): [x, y, w, h]
function liqDrag([x, y, w, h], part, dx, dy) {
  if (part === 'move') return [x + dx, y + dy, w, h];
  if (part.includes('w')) { const nx = Math.min(x + dx, x + w - 1); w += x - nx; x = nx; }
  if (part.includes('e')) w = Math.max(1, w + dx);
  if (part.includes('n')) { const ny = Math.min(y + dy, y + h - 1); h += y - ny; y = ny; }
  if (part.includes('s')) h = Math.max(1, h + dy);
  return [x, y, w, h];
}
// what the generator and the game would refuse in a room's "liquids" (room: {width, height} or null)
function liqPlaceProblems(list, kinds, room) {
  const out = [], ok = [];
  if (list === undefined) return out;
  if (!Array.isArray(list)) return ['«liquids» должен быть списком'];
  list.forEach((p, i) => {
    const n = `Жидкость ${i + 1}`;
    if (!Array.isArray(p) || p.length < 5 || p.length > 6 || typeof p[0] !== 'string' || !p.slice(1, 5).every(Number.isFinite)) { out.push(`${n}: нужно [вид, x, y, ширина, глубина]`); return; }
    const [kind, x, y, w, h, opt] = p;
    if (!(kinds && kind in kinds)) out.push(`${n}: неизвестный вид «${kind}»`);
    if (w < LIQ_MIN_W) out.push(`${n}: ширина ${w} px — нужно не меньше ${LIQ_MIN_W}`);
    if (h < LIQ_MIN_H) out.push(`${n}: глубина ${h} px — нужно не меньше ${LIQ_MIN_H}`);
    if (room && (x < 0 || y < 0 || x + w > room.width || y + h > room.height)) out.push(`${n} выходит за комнату (${room.width}×${room.height})`);
    if (p.length === 6) {
      if (!opt || typeof opt !== 'object' || Array.isArray(opt)) out.push(`${n}: шестое поле — объект настроек`);
      else for (const [k, v] of Object.entries(opt)) if (k !== 'painted') out.push(`${n}: неизвестная настройка «${k}»`); else if (typeof v !== 'boolean') out.push(`${n}: painted — да или нет`);
    }
    ok.push([i, x, y, w, h]);
  });
  for (let a = 0; a < ok.length; a++) for (let b = a + 1; b < ok.length; b++) {
    const [i, ax, ay, aw, ah] = ok[a], [j, bx, by, bw, bh] = ok[b];
    if (ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah) out.push(`Жидкости ${i + 1} и ${j + 1} накладываются`);
  }
  return out;
}
// what is wrong in data/liquids.json, in the studio's bounds
function liqKindProblems(doc) {
  const out = [], kinds = doc?.kinds;
  if (!kinds || typeof kinds !== 'object' || !Object.keys(kinds).length) return ['В data/liquids.json нет ни одного вида'];
  for (const [id, k] of Object.entries(kinds)) {
    const n = `«${liqName(id)}»`;
    if (!/^[a-z_][a-z0-9_]*$/.test(id)) out.push(`${n}: id — латиница, цифры, _`);
    if (!k || typeof k !== 'object') { out.push(`${n}: не объект`); continue; }
    for (const c of Object.keys(LIQ_COLORS)) if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(k.colors?.[c] || '')) out.push(`${n}: цвет «${LIQ_COLORS[c]}» — не цвет`);
    for (const [, path, label, lo, hi] of LIQ_FIELDS) {
      const v = liqGet(k, path);
      if (v === undefined && /^(light|heal)\./.test(path)) continue;
      if (typeof v !== 'number' || !Number.isFinite(v)) out.push(`${n}: ${label} — нет числа`);
      else if (v < lo || v > hi) out.push(`${n}: ${label} — ${v}, а можно ${lo}…${hi}`);
    }
    for (const f of Object.keys(LIQ_FLAGS)) if (typeof k[f] !== 'boolean') out.push(`${n}: «${LIQ_FLAGS[f]}» — да или нет`);
    for (const [slot, names] of Object.entries(LIQ_PARTICLES)) if (!(k.particles?.[slot] in names)) out.push(`${n}: частицы «${slot}» — ${k.particles?.[slot]}? бывают: ${Object.keys(names).join(', ')}`);
    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(k.particles?.tint || '')) out.push(`${n}: цвет частиц — не цвет`);
    if (k.heal && Object.keys(k.heal).length && !(k.heal.path in LIQ_HEAL_PATHS)) out.push(`${n}: лечит на пути «${k.heal.path}» — такого пути нет`);
    if (k.light && Object.keys(k.light).length && !/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(k.light.color || '')) out.push(`${n}: цвет света — не цвет`);
    for (const [m, v] of Object.entries(k.enemy?.harms || {})) if (typeof v !== 'number' || v < 0 || v > LIQ_HARM_MAX) out.push(`${n}: урон «${m}» — ${v}, а можно 0…${LIQ_HARM_MAX}`);
    for (const s of Object.keys(LIQ_SOUNDS)) if (typeof (k.sounds?.[s] ?? '') !== 'string' || !/^[a-z0-9_]*$/.test(k.sounds?.[s] ?? '')) out.push(`${n}: звук «${LIQ_SOUNDS[s]}» — имя из латиницы, цифр и _`);
    if (typeof k.texture !== 'string' || k.texture && !/^res:\/\/.+\.png$/.test(k.texture)) out.push(`${n}: текстура — путь res://….png или пусто`);
  }
  return out;
}
// what the kind does, in words, for the side panel
function liqSummary(k) {
  const b = k.body || {}, e = k.enemy || {}, out = [];
  out.push(+k.damage > 0 ? `Касание ранит героя на ${k.damage}${k.burns ? ' — ожог, и его ставит на последний твёрдый пол' : ''}.` : k.burns ? 'Жжёт: ставит героя на последний твёрдый пол.' : 'Героя не ранит.');
  out.push(+b.swim > 0 ? `Плавается: гребок ${b.swim} px/с раз в ${b.swim_cooldown} с.` : 'Не плавается — только выбраться прыжком.');
  out.push(`Движение в ней ×${b.drag}, тяжесть в ней ${Math.round((+b.buoyancy ?? 1) * 100)} %, тонет не быстрее ${b.sink_speed} px/с, прыжок из неё ×${b.jump}.`);
  if (k.kills_walkers) out.push('Пешие враги в ней гибнут; летуны пролетают над.'); else out.push(`Враги в ней ×${e.drag ?? 1}.`);
  if (+e.heal_per_second > 0) out.push(`Лечит врагов: ${e.heal_per_second} ед/с.`);
  const harms = Object.entries(e.harms || {}).filter(([, v]) => +v > 0);
  if (harms.length) out.push('Ранит врагов: ' + harms.map(([m, v]) => `${m} — ${v} ед/с`).join(', ') + '.');
  if (k.heal && +k.heal.per_second > 0) out.push(`Лечит героя: ${k.heal.per_second} ед/с (путь «${LIQ_HEAL_PATHS[k.heal.path] || k.heal.path}»).`);
  if (k.douses) out.push('Гасит горение.');
  return out;
}
const liqHash = (a, b, c = 0) => { let h = (a * 374761393 + b * 668265263 + c * 2147483647) | 0; h = (h ^ (h >>> 13)) * 1274126177 | 0; return ((h ^ (h >>> 16)) >>> 0) / 4294967296; };
function liqNoise(x, y) {
  const xi = Math.floor(x), yi = Math.floor(y), u = x - xi, v = y - yi, s = q => q * q * (3 - 2 * q);
  const a = liqHash(xi, yi), b = liqHash(xi + 1, yi), c = liqHash(xi, yi + 1), d = liqHash(xi + 1, yi + 1);
  return a + (b - a) * s(u) + (c - a) * s(v) + (a - b - c + d) * s(u) * s(v);
}
// The pool drawn pixel by pixel into an ImageData-like {data, width, height}: r = {x, y, w, h} (y the surface),
// o = {painted, tex: {data, width, height, mean}}. hazard.gd's look, see the top of the file.
function liqPaint(img, spec, sim, r, t, o = {}) {
  const W = img.width, H = img.height, d = img.data, cs = spec.colors || {}, wv = spec.waves || {};
  const sf = liqRgb(cs.surface), bd = liqRgb(cs.body), dp = liqRgb(cs.deep), fm = liqRgb(cs.foam);
  const a = Math.max(0, Math.min(1, +(o.painted ? spec.painted_opacity : spec.opacity) || 0)), foamA = Math.min(1, o.painted ? a * 2.5 + 0.1 : Math.max(a, 0.85));
  const flow = +spec.flow || 0, shim = +spec.shimmer || 0, tex = o.tex, mix = (p, q, u) => [p[0] + (q[0] - p[0]) * u, p[1] + (q[1] - p[1]) * u, p[2] + (q[2] - p[2]) * u];
  const bottom = Math.min(H, Math.round(r.y + r.h));
  for (let px = Math.max(0, Math.floor(r.x)); px < Math.min(W, Math.ceil(r.x + r.w)); px++) {
    const lx = px - r.x, top = r.y + liqSurfaceAt(sim, lx, t, wv), sy = Math.max(0, Math.round(top));
    for (let py = sy; py < bottom; py++) {
      let c, al = a;
      if (py === sy) { c = fm; al = foamA; }
      else {
        const depth = Math.max(0, (py - top) / Math.max(1, r.h));
        c = depth < 0.18 ? mix(sf, bd, depth / 0.18) : mix(bd, dp, Math.min(1, (depth - 0.18) / 0.82));
        let m;
        if (tex) { const u = ((Math.floor(lx + t * flow * tex.width) % tex.width) + tex.width) % tex.width, v = Math.floor(py - r.y) % tex.height, j = (v * tex.width + u) * 4;
          m = (tex.data[j] * 0.3 + tex.data[j + 1] * 0.59 + tex.data[j + 2] * 0.11) / (tex.mean || 128); }
        else m = 0.86 + 0.28 * liqNoise(lx * 0.12 + t * flow * 40, (py - r.y) * 0.3);
        c = [c[0] * m, c[1] * m, c[2] * m];
        if (py - sy <= 3 && shim > 0 && liqHash(px, Math.floor(t * 5 + px * 0.37), py) < shim * 0.06) { c = mix(c, fm, 0.8); al = Math.max(al, foamA * 0.8); }
      }
      const j = (py * W + px) * 4;
      d[j] = d[j] + (Math.min(255, c[0]) - d[j]) * al; d[j + 1] = d[j + 1] + (Math.min(255, c[1]) - d[j + 1]) * al; d[j + 2] = d[j + 2] + (Math.min(255, c[2]) - d[j + 2]) * al; d[j + 3] = 255;
    }
  }
  return img;
}
if (typeof module !== 'undefined') module.exports = { LIQ_COL, LIQ_MIN_W, LIQ_MIN_H, LIQ_FIELDS, LIQ_PARTICLES, liqText, liqSim, liqSpringStep, liqSplash, liqWave, liqSurfaceAt, liqSnap, liqClamp, liqHit, liqDrag, liqPlaceProblems, liqKindProblems, liqSummary, liqPaint, liqRgb, liqGet, liqSet };

/* ---------- the studio ---------- */
const LIQ = { view: 'room', kind: 'water', room: '', rooms: {}, sel: -1, drag: null, snap: true, raf: 0, last: 0, t: 0, acc: 0, sims: new Map(), base: null, tex: new Map(), sfx: null,
  pv: { sim: null, parts: [], bodies: [], texts: [], heard: [], ambient: 0, auto: 0 } };
const liqDoc = () => gdDoc(LIQ_PATH) || { kinds: {} };
const liqKinds = () => liqDoc().kinds || {};
const liqSpec = k => liqKinds()[k] || null;
const liqRoomsDoc = () => gdDoc(LIQ_ROOMS) || {};
const liqList = (name = LIQ.room) => liqRoomsDoc()[name]?.liquids || [];
function liqSetList(list, name = LIQ.room) {
  const doc = structuredClone(liqRoomsDoc()), r = doc[name] ||= {};
  if (list.length) r.liquids = list; else delete r.liquids;
  if (!Object.keys(r).length) delete doc[name];
  gdPut(LIQ_ROOMS, doc);
}
function liqKindEdit(fn) { const doc = structuredClone(liqDoc()); fn(doc.kinds[LIQ.kind], doc); gdPut(LIQ_PATH, doc); }
// the scene's own pools (hazard.gd nodes), less the ones the scene got from studio_rooms.json as it is on disk
function liqBuiltIn(room) {
  const mine = (WORLD.data.files[LIQ_ROOMS]?.[room.name]?.liquids || []).map(p => p.slice(0, 5).join());
  return (room.hazards || []).filter(h => !mine.includes(h.slice(0, 5).join()));
}
function liqAllProblems() {
  const out = liqKindProblems(liqDoc()).slice();
  for (const [name, r] of Object.entries(liqRoomsDoc())) if (r.liquids) out.push(...liqPlaceProblems(r.liquids, liqKinds(), LIQ.rooms[name] || null).map(p => `${name}: ${p}`));
  return out;
}
function liqTex(kind) {
  const spec = liqSpec(kind), src = spec?.texture ? A(spec.texture) : '';
  let t = LIQ.tex.get(kind);
  if (t && t.src === src) return t.ok ? t : null;
  t = { src, ok: false }; LIQ.tex.set(kind, t);
  if (src) loadImage(src).then(im => {
    const c = document.createElement('canvas'); c.width = im.width; c.height = im.height; const x = c.getContext('2d'); x.drawImage(im, 0, 0);
    const d = x.getImageData(0, 0, c.width, c.height); let sum = 0, n = 0;
    for (let j = 0; j < d.data.length; j += 4) if (d.data[j + 3]) { sum += d.data[j] * 0.3 + d.data[j + 1] * 0.59 + d.data[j + 2] * 0.11; n++; }
    Object.assign(t, { ok: true, data: d.data, width: c.width, height: c.height, mean: n ? sum / n : 128, img: im });
  }).catch(() => {});
  return null;
}
async function liqSfxLoad() {
  if (LIQ.sfx) return;
  LIQ.sfx = new Map();
  try { for (const s of await (await fetch('import/audio.json')).json()) if (s.cat === 'sfx') LIQ.sfx.set(s.name, (s.takes || []).map(t => t.url)); } catch {}
  if ($('#liqSfxList')) $('#liqSfxList').innerHTML = [...LIQ.sfx.keys()].sort().map(n => `<option value="${esc(n)}">`).join('');
}
function liqHear(name, force = false) {
  if (!name) return;
  LIQ.pv.heard.push({ name, t: 0 }); if (LIQ.pv.heard.length > 4) LIQ.pv.heard.shift();
  const takes = LIQ.sfx?.get(name);
  if ((force || LIQ.pv.sound) && takes?.length) { const a = new Audio(A(takes[Math.floor(Math.random() * takes.length)])); a.volume = 0.5; a.play().catch(() => {}); }
}

/* ---------- panels ---------- */
function renderLiq() {
  if (!$('#gdSide_liq')) return;
  const room = LIQ.view === 'room';
  $('#liqMapBox').hidden = !room; $('#liqPreview').hidden = room;
  const tabs = `<div class="row" style="margin:0 0 6px;gap:4px"><button class="sm ${room ? 'on' : ''}" data-liq-act="view" data-v="room">В комнате</button><button class="sm ${room ? '' : 'on'}" data-liq-act="view" data-v="kind">Виды жидкостей</button></div>`;
  if (room) renderLiqRoom(tabs); else renderLiqKind(tabs);
}
const liqSwatch = k => { const c = liqSpec(k)?.colors || {}; return `<span class="liqsw" style="background:linear-gradient(${esc(c.surface || '#888')},${esc(c.body || '#444')},${esc(c.deep || '#111')})"></span>`; };
function renderLiqRoom(tabs) {
  const names = roomNames(); if (!LIQ.room || !names.includes(LIQ.room)) LIQ.room = names[0] || '';
  const list = liqList(), kinds = Object.keys(liqKinds()), room = LIQ.rooms[LIQ.room];
  if (!kinds.includes(LIQ.kind)) LIQ.kind = kinds[0];
  if (LIQ.sel >= list.length) LIQ.sel = list.length - 1;
  const kindOpts = cur => [...new Set([...kinds, cur])].map(k => `<option value="${esc(k)}"${k === cur ? ' selected' : ''}>${esc(liqName(k))}${kinds.includes(k) ? '' : ' (нет такого)'}</option>`).join('');
  const builtIn = room ? liqBuiltIn(room) : [];
  const problems = liqPlaceProblems(list, liqKinds(), room || null);
  const onLava = room ? list.map((p, i) => builtIn.some(h => p[1] < h[1] + h[3] && h[1] < p[1] + p[3] && p[2] < h[2] + h[4] && h[2] < p[2] + p[4]) ? `Жидкость ${i + 1} лежит на жидкости сцены — так задумано?` : '').filter(Boolean) : [];
  $('#gdSide_liq').innerHTML = tabs + `<label>Комната<select id="liqRoom">${names.map(n => `<option${n === LIQ.room ? ' selected' : ''}>${esc(n)}${liqList(n).length ? ' •' : ''}</option>`).join('')}</select></label>
    <div class="card"><b>Кисть</b><div class="row" style="margin:4px 0;gap:4px;flex-wrap:wrap">${kinds.map(k => `<button class="sm ${k === LIQ.kind ? 'on' : ''}" data-liq-act="brush" data-k="${esc(k)}">${liqSwatch(k)}${esc(liqName(k))}</button>`).join('')}</div>
      <label><input type="checkbox" id="liqSnap"${LIQ.snap ? ' checked' : ''}> прилипать поверхностью к полу (±${LIQ_SNAP} px)</label>
      <div class="muted">Тяни по карте — новая жидкость; клик по пустому — 96×32; тяни жидкость — двигать, за край или угол — размер; Delete — убрать, стрелки — сдвиг (Shift — по 8 px); двойной клик — всплеск. Верх рамки — поверхность, высота — глубина вниз.</div></div>
    <div class="card"><b>Жидкости студии</b>${list.length ? list.map((p, i) => { const [k, x, y, w, h, o] = Array.isArray(p) ? p : []; return `<div class="liqrow${i === LIQ.sel ? ' on' : ''}" data-liq-act="pick" data-i="${i}">
        <select data-liq-pool="${i}" data-f="0">${kindOpts(k)}</select>
        ${[['x', 1, x], ['y', 2, y], ['ш', 3, w], ['г', 4, h]].map(([l, f, v]) => `<label title="${{ x: 'левый край', y: 'поверхность', ш: 'ширина', г: 'глубина' }[l]}">${l}<input type="number" data-liq-pool="${i}" data-f="${f}" value="${v ?? ''}"></label>`).join('')}
        <label title="уже нарисовано на картинке: игра рисует её бледно, только живую поверхность"><input type="checkbox" data-liq-pool="${i}" data-f="painted"${o?.painted ? ' checked' : ''}> нарисована</label>
        <button class="sm" data-liq-act="dup" data-i="${i}" title="Копия рядом">⧉</button><button class="sm danger" data-liq-act="del" data-i="${i}" title="Убрать">✕</button></div>`; }).join('')
      : '<div class="muted">Пока нет — потяни по карте.</div>'}
      <div class="muted">«нарисована» — жидкость уже есть на картине: игра кладёт её бледно (painted_opacity), живут только поверхность, частицы и свет.</div></div>
    <div class="card"><b>Уже в сцене</b> <span class="muted">(только чтение)</span>${builtIn.length ? builtIn.map(h => `<div class="muted">${esc(liqName(h[0]))} ${h[1]}, ${h[2]} · ${h[3]}×${h[4]}${h[5]?.painted ? ' · на картине' : ''}</div>`).join('') : '<div class="muted">ничего</div>'}
      <div class="muted">Лава расписанных комнат живёт в таблицах (tools/rooms/painted_rooms.py, «hazards»); здесь её не поменять.</div></div>
    ${problems.map(p => `<div class="warn">${esc(p)}</div>`).join('')}${onLava.map(p => `<div class="note">${esc(p)}</div>`).join('')}`;
  $('#gdBar_liq').innerHTML = `<span class="muted grow">${room ? `${esc(LIQ.room)}: ${room.width}×${room.height}. Зелёное — пол, красное — враги, штрих — жидкость сцены.` : 'Загружаю комнату…'}</span>` + gdBar('liq');
  if (!room && LIQ.room) loadRoom(LIQ.room).then(r => { if (r) { LIQ.rooms[r.name] = r; LIQ.base = null; renderLiq(); } });
}
function renderLiqKind(tabs) {
  const kinds = liqKinds(); if (!(LIQ.kind in kinds)) LIQ.kind = Object.keys(kinds)[0];
  const k = kinds[LIQ.kind], was = WORLD.data.files[LIQ_PATH]?.kinds?.[LIQ.kind];
  if (!k) { $('#gdSide_liq').innerHTML = tabs + '<div class="warn">В data/liquids.json нет видов.</div>'; return; }
  const field = (path, label, lo, hi, step) => { const v = liqGet(k, path) ?? lo, changed = was && !sameDraft(liqGet(was, path), liqGet(k, path));
    return `<div class="liqfield${changed ? ' changed' : ''}"><span>${esc(label)}</span><input type="range" data-liq="${path}" min="${lo}" max="${hi}" step="${step}" value="${v}"><input type="number" data-liq="${path}" min="${lo}" max="${hi}" step="${step}" value="${v}"></div>`; };
  const section = name => LIQ_FIELDS.filter(f => f[0] === name).map(f => field(f[1], f[2], f[3], f[4], f[5])).join('');
  const color = (path, label) => `<label class="liqcolor"><input type="color" data-liq="${path}" value="${esc(String(liqGet(k, path) || '#808080').slice(0, 7))}"> ${esc(label)}</label>`;
  const sel = (path, opts, label) => `<label>${esc(label)}<select data-liq="${path}">${Object.entries(opts).map(([v, l]) => `<option value="${esc(v)}"${v === (liqGet(k, path) ?? '') ? ' selected' : ''}>${esc(l)}</option>`).join('')}</select></label>`;
  const harms = Object.entries(k.enemy?.harms || {});
  $('#gdSide_liq').innerHTML = tabs + `<div class="row" style="margin:0;gap:4px;flex-wrap:wrap">${Object.keys(kinds).map(id => `<button class="sm ${id === LIQ.kind ? 'on' : ''}" data-liq-act="kind" data-k="${esc(id)}">${liqSwatch(id)}${esc(liqName(id))}${sameDraft(kinds[id], WORLD.data.files[LIQ_PATH]?.kinds?.[id]) ? '' : ' •'}</button>`).join('')}
      <button class="sm" data-liq-act="kind-add" title="Новый вид — копия этого">＋</button>${LIQ_BASE_KINDS.includes(LIQ.kind) ? '' : '<button class="sm danger" data-liq-act="kind-del" title="Убрать этот вид">✕</button>'}</div>
    <div class="card liqsum">${liqSummary(k).map(s => `<div>${esc(s)}</div>`).join('')}</div>
    <div class="card"><b>Цвета</b><div class="liqcolors">${Object.entries(LIQ_COLORS).map(([c, l]) => color('colors.' + c, l)).join('')}</div></div>
    <div class="card"><b>Вид</b>${section('Вид')}<label>Текстура толщи<input data-liq="texture" value="${esc(k.texture || '')}" placeholder="res://assets/fx/liquids/body_${esc(LIQ.kind)}.png"></label>
      <div class="muted">${k.texture ? (LIQ.tex.get(LIQ.kind)?.ok ? 'Текстура видна в превью.' : 'Картинки пока нет — превью рисует свой узор.') : 'Без текстуры — ровный градиент.'}</div></div>
    <div class="card"><b>Волны</b>${section('Волны')}<div class="muted">Поверхность — пружинки каждые ${LIQ_COL} px: упругость тянет их назад, затухание гасит, рябь передаётся соседям. Кликни по превью — всплеск.</div></div>
    <div class="card"><b>Тело в ней</b>${section('Тело')}</div>
    <div class="card"><b>Урон и свойства</b>${section('Урон')}${Object.entries(LIQ_FLAGS).map(([f, l]) => `<label><input type="checkbox" data-liq="${f}"${k[f] ? ' checked' : ''}> ${esc(l)}</label>`).join('')}</div>
    <div class="card"><b>Враги</b>${section('Враги')}
      ${harms.map(([m, v]) => `<div class="liqfield"><span>Ранит «${esc(m)}», ед/с</span><input type="range" data-liq-harm="${esc(m)}" min="0" max="${LIQ_HARM_MAX}" step="0.5" value="${v}"><input type="number" data-liq-harm="${esc(m)}" min="0" max="${LIQ_HARM_MAX}" step="0.5" value="${v}"><button class="sm" data-liq-act="harm-del" data-m="${esc(m)}">✕</button></div>`).join('')}
      <label>+ ранит материал<select data-liq-act-change="harm-add"><option value="">—</option>${LIQ_MATERIALS.filter(m => !(m in (k.enemy?.harms || {}))).map(m => `<option>${m}</option>`).join('')}</select></label></div>
    <div class="card"><b>Исцеление героя</b>${sel('heal.path', { '': 'не лечит', ...LIQ_HEAL_PATHS }, 'Путь')}${k.heal?.path ? section('Исцеление') : ''}</div>
    <div class="card"><b>Частицы</b>${sel('particles.ambient', LIQ_PARTICLES.ambient, 'Над поверхностью')}${sel('particles.splash', LIQ_PARTICLES.splash, 'Всплеск')}${sel('particles.trail', LIQ_PARTICLES.trail, 'След на вышедшем')}
      ${section('Частицы')}${color('particles.tint', 'Цвет частиц')}</div>
    <div class="card"><b>Свет</b> <label style="display:inline"><input type="checkbox" data-liq-act-change="light"${k.light && Object.keys(k.light).length ? ' checked' : ''}> светится</label>
      ${k.light && Object.keys(k.light).length ? color('light.color', 'Цвет света') + section('Свет') : ''}</div>
    <div class="card"><b>Звуки</b>${Object.entries(LIQ_SOUNDS).map(([s, l]) => `<div class="row" style="margin:0;gap:4px"><label class="grow">${esc(l)}<input list="liqSfxList" data-liq="sounds.${s}" value="${esc(k.sounds?.[s] || '')}" placeholder="—"></label><button class="sm" data-liq-act="hear" data-s="${esc(k.sounds?.[s] || '')}" title="Послушать">▶</button></div>`).join('')}
      <datalist id="liqSfxList">${LIQ.sfx ? [...LIQ.sfx.keys()].sort().map(n => `<option value="${esc(n)}">`).join('') : ''}</datalist>
      <div class="muted">Имя звука, не файл (Audio.play): дубли «_1, _2…» играются вперемешку. Нет такого звука — игра промолчит.</div></div>
    ${liqKindProblems({ kinds: { [LIQ.kind]: k } }).map(p => `<div class="warn">${esc(p)}</div>`).join('')}`;
  $('#gdBar_liq').innerHTML = `<label>Кто падает <select id="liqWho"><option value="hero"${LIQ.pv.who !== 'walker' ? ' selected' : ''}>герой</option><option value="walker"${LIQ.pv.who === 'walker' ? ' selected' : ''}>пеший враг</option></select></label>
    <label title="как будет в комнате, где эта жидкость уже нарисована"><input type="checkbox" id="liqPainted"${LIQ.pv.painted ? ' checked' : ''}> уже нарисована</label>
    <label><input type="checkbox" id="liqAuto"${LIQ.pv.autoOn !== false ? ' checked' : ''}> по кругу</label>
    <label><input type="checkbox" id="liqSound"${LIQ.pv.sound ? ' checked' : ''}> звук</label>
    <button class="sm" data-liq-act="drop" title="Бросить тело сверху">▼ Бросить</button>` + gdBar('liq');
}
function liqInput(e) {
  const el = e.target;
  if (el.id === 'liqRoom') { LIQ.room = el.value; LIQ.sel = -1; LIQ.base = null; return renderLiq(); }
  if (el.id === 'liqSnap') { LIQ.snap = el.checked; return; }
  if (el.id === 'liqWho') { LIQ.pv.who = el.value; return; }
  if (el.id === 'liqPainted') { LIQ.pv.painted = el.checked; return; }
  if (el.id === 'liqAuto') { LIQ.pv.autoOn = el.checked; return; }
  if (el.id === 'liqSound') { LIQ.pv.sound = el.checked; return; }
  if (el.dataset.liqPool !== undefined) {
    if (e.type !== 'change') return;
    const i = +el.dataset.liqPool, f = el.dataset.f, list = structuredClone(liqList()), p = list[i]; if (!p) return;
    if (f === 'painted') { if (el.checked) p[5] = { ...(p[5] || {}), painted: true }; else if (p[5]) { delete p[5].painted; if (!Object.keys(p[5]).length) p.length = 5; } }
    else if (f === '0') p[0] = el.value;
    else p[+f] = Math.round(+el.value || 0);
    LIQ.sel = i; liqSetList(list); return renderLiq();
  }
  if (el.dataset.liqActChange === 'harm-add' && el.value) { const m = el.value; liqKindEdit(k => { (k.enemy ||= {}).harms = { ...(k.enemy.harms || {}), [m]: 5.0 }; }); return renderLiq(); }
  if (el.dataset.liqActChange === 'light') {
    liqKindEdit(k => { k.light = el.checked ? { color: (k.colors?.glow || '#ff7a2a').slice(0, 7), radius: 60.0, energy: 0.5, every: 120.0, flicker: 0.15 } : {}; }); return renderLiq();
  }
  const harm = el.dataset.liqHarm, path = el.dataset.liq; if (!harm && !path) return;
  let v = el.type === 'checkbox' ? el.checked : el.type === 'range' || el.type === 'number' ? +el.value : el.value;
  if (typeof v === 'number') { if (!Number.isFinite(v)) return; const step = +el.step || 0.01; v = +(Math.round(v / step) * step).toFixed(6); }
  const twin = el.parentElement?.querySelector(`input[data-liq${harm ? '-harm' : ''}="${CSS.escape(harm || path)}"]:not([type="${el.type}"])`); if (twin) twin.value = v;
  if (harm) liqKindEdit(k => { k.enemy.harms[harm] = v; });
  else liqKindEdit(k => {
    if (path === 'heal.path') { k.heal = v ? { path: v, per_second: +(k.heal?.per_second ?? 1.0) || 1.0 } : {}; return; }
    if (path === 'texture') { k.texture = String(v).trim(); return; }
    if (path.startsWith('sounds.')) { liqSet(k, path, String(v).trim()); return; }
    liqSet(k, path, v);
  });
  if (e.type === 'change') renderLiq();
}
async function liqClick(e) {
  const b = e.target.closest('[data-liq-act],[data-gd]'); if (!b) return;
  if (b.dataset.gd === 'revert') {
    if (!confirm('Отменить несохранённые правки жидкостей (виды и все комнаты)?')) return;
    delete WORLD.work[LIQ_PATH];
    const base = WORLD.data.files[LIQ_ROOMS] || {}, doc = structuredClone(liqRoomsDoc());
    for (const n of new Set([...Object.keys(doc), ...Object.keys(base)])) { const r = doc[n] ||= {}; if (base[n]?.liquids) r.liquids = structuredClone(base[n].liquids); else delete r.liquids; if (!Object.keys(r).length) delete doc[n]; }
    gdPut(LIQ_ROOMS, doc); LIQ.sel = -1; return renderLiq();
  }
  if (b.dataset.gd) return gdClick(e);
  const act = b.dataset.liqAct;
  if (act === 'view') { LIQ.view = b.dataset.v; try { localStorage.setItem('ss_liq_view', LIQ.view); } catch {} return renderLiq(); }
  if (act === 'brush' || act === 'kind') { LIQ.kind = b.dataset.k; return renderLiq(); }
  if (act === 'pick') { if (e.target.closest('input,select,button')) return; LIQ.sel = +b.dataset.i; return renderLiq(); }
  if (act === 'del') { const list = structuredClone(liqList()); list.splice(+b.dataset.i, 1); LIQ.sel = -1; liqSetList(list); return renderLiq(); }
  if (act === 'dup') { const list = structuredClone(liqList()), p = structuredClone(list[+b.dataset.i]), room = LIQ.rooms[LIQ.room];
    const r = liqClamp([p[1] + p[3] + 8, p[2], p[3], p[4]], room); p.splice(1, 4, ...r); list.push(p); LIQ.sel = list.length - 1; liqSetList(list); return renderLiq(); }
  if (act === 'kind-add') {
    const id = (prompt('id нового вида (латиница, цифры, _), например acid:', '') || '').trim();
    if (!id) return; if (!/^[a-z_][a-z0-9_]*$/.test(id) || id in liqKinds()) return toast('Нужен новый id: латиница в нижнем регистре, цифры, _', 'err');
    const doc = structuredClone(liqDoc()); doc.kinds[id] = structuredClone(doc.kinds[LIQ.kind]); doc.kinds[id].texture = `res://assets/fx/liquids/body_${id}.png`;
    gdPut(LIQ_PATH, doc); LIQ.kind = id; toast('Новый вид — копия. Игре нужен и код, если он должен вести себя по-новому; цвета и числа она возьмёт сама.'); return renderLiq();
  }
  if (act === 'kind-del') {
    const used = Object.entries(liqRoomsDoc()).filter(([, r]) => (r.liquids || []).some(p => p[0] === LIQ.kind)).map(([n]) => n);
    if (used.length) return toast('Этот вид лежит в комнатах: ' + used.join(', '), 'err');
    if (!confirm(`Убрать вид «${LIQ.kind}»?`)) return;
    const doc = structuredClone(liqDoc()); delete doc.kinds[LIQ.kind]; gdPut(LIQ_PATH, doc); LIQ.kind = Object.keys(doc.kinds)[0]; return renderLiq();
  }
  if (act === 'harm-del') { liqKindEdit(k => { delete k.enemy.harms[b.dataset.m]; }); return renderLiq(); }
  if (act === 'hear') { if (!b.dataset.s) return; if (!LIQ.sfx?.get(b.dataset.s)?.length) return toast(`Звука «${b.dataset.s}» в игре пока нет`, 'err'); return liqHear(b.dataset.s, true); }
  if (act === 'drop') return liqDropBody(LIQ_PV.x0 + Math.random() * (LIQ_PV.x1 - LIQ_PV.x0), 10);
}

/* ---------- the room map ---------- */
function liqMapPoint(c, e, room) { const r = c.getBoundingClientRect(); return { x: (e.clientX - r.left) / r.width * room.width, y: (e.clientY - r.top) / r.height * room.height, k: r.width / room.width }; }
function liqMapDown(e) {
  const room = LIQ.rooms[LIQ.room], c = $('#liqMap'); if (!room || e.button !== 0) return;
  const p = liqMapPoint(c, e, room), list = liqList(), hit = liqHit(list, p.x, p.y, 6 / p.k, LIQ.sel);
  if (hit) { LIQ.sel = hit.i; LIQ.drag = { part: hit.part, from: p, rect: list[hit.i].slice(1, 5), i: hit.i, moved: false }; }
  else LIQ.drag = { part: 'new', from: p, rect: [p.x, p.y, 0, 0], moved: false };
  c.setPointerCapture?.(e.pointerId); e.preventDefault();
  renderLiq();
}
function liqDragRect(p, d = LIQ.drag) {
  const room = LIQ.rooms[LIQ.room];
  if (d.part === 'new') { const x0 = Math.min(d.from.x, p.x), y0 = Math.min(d.from.y, p.y); return [x0, y0, Math.abs(p.x - d.from.x), Math.abs(p.y - d.from.y)]; }
  let r = liqDrag(d.rect, d.part, p.x - d.from.x, p.y - d.from.y);
  if (LIQ.snap && (d.part === 'move' || d.part.includes('n'))) { const y = liqSnap(room.surfaces, r[0], r[1], r[2]); if (d.part === 'move') r[1] = y; else { r[3] += r[1] - y; r[1] = y; } }
  return r;
}
function liqMapMove(e) {
  const room = LIQ.rooms[LIQ.room], c = $('#liqMap'); if (!room) return;
  const p = liqMapPoint(c, e, room);
  if (!LIQ.drag) { const h = liqHit(liqList(), p.x, p.y, 6 / p.k, LIQ.sel); c.style.cursor = !h ? 'crosshair' : h.part === 'move' ? 'move' : { n: 'ns-resize', s: 'ns-resize', e: 'ew-resize', w: 'ew-resize', ne: 'nesw-resize', sw: 'nesw-resize', nw: 'nwse-resize', se: 'nwse-resize' }[h.part]; return; }
  LIQ.drag.now = p; LIQ.drag.moved ||= Math.hypot(p.x - LIQ.drag.from.x, p.y - LIQ.drag.from.y) * p.k > 3;
}
function liqMapUp(e) {
  const d = LIQ.drag, room = LIQ.rooms[LIQ.room]; LIQ.drag = null; if (!d || !room) return;
  const p = liqMapPoint($('#liqMap'), e, room), list = structuredClone(liqList());
  if (d.part === 'new') {
    let r = d.moved ? liqDragRect(p, d) : [p.x - 48, p.y, 96, 32];
    r = [r[0], r[1], Math.max(LIQ_MIN_W, r[2]), Math.max(LIQ_MIN_H, r[3])];
    if (LIQ.snap) r[1] = liqSnap(room.surfaces, r[0], r[1], r[2]);
    list.push([LIQ.kind, ...liqClamp(r, room)]); LIQ.sel = list.length - 1;
  } else if (d.moved) { list[d.i].splice(1, 4, ...liqClamp(liqDragRect(p, d), room)); }
  else return renderLiq();
  liqSetList(list); renderLiq();
}
function liqMapDbl(e) {
  const room = LIQ.rooms[LIQ.room]; if (!room) return;
  const p = liqMapPoint($('#liqMap'), e, room), h = liqHit(liqList(), p.x, p.y, 0); if (!h) return;
  const pool = liqList()[h.i], sim = LIQ.sims.get(`${LIQ.room}:${h.i}:${pool[3]}`); if (sim) liqSplash(sim, p.x - pool[1], 12, 500, liqSpec(pool[0])?.waves);
}
function liqKey(e) {
  if (mode !== 'liq' || LIQ.view !== 'room' || LIQ.sel < 0 || e.target.closest?.('input,textarea,select')) return;
  const list = structuredClone(liqList()), p = list[LIQ.sel]; if (!p) return;
  if (e.key === 'Delete' || e.key === 'Backspace') { list.splice(LIQ.sel, 1); LIQ.sel = -1; }
  else { const s = e.shiftKey ? 8 : 1, d = { ArrowLeft: [-s, 0], ArrowRight: [s, 0], ArrowUp: [0, -s], ArrowDown: [0, s] }[e.key]; if (!d) return;
    p.splice(1, 4, ...liqClamp([p[1] + d[0], p[2] + d[1], p[3], p[4]], LIQ.rooms[LIQ.room])); }
  e.preventDefault(); liqSetList(list); renderLiq();
}
// a pool on a 2D context in map pixels (k: map px per room px)
function liqDrawPool(x, k, spec, sim, r, t, painted) {
  const cs = spec?.colors || {}, wv = spec?.waves || {}, a = spec ? Math.max(0.12, +(painted ? spec.painted_opacity : spec.opacity) || 0) : 0.5;
  const step = Math.max(1, LIQ_COL / 2), pts = [];
  for (let lx = 0; lx <= r[2]; lx += step) pts.push([(r[0] + lx) * k, (r[1] + (sim ? liqSurfaceAt(sim, lx, t, wv) : 0)) * k]);
  pts.push([(r[0] + r[2]) * k, (r[1] + (sim ? liqSurfaceAt(sim, r[2], t, wv) : 0)) * k]);
  const g = x.createLinearGradient(0, r[1] * k, 0, (r[1] + r[3]) * k);
  g.addColorStop(0, cs.surface || '#888'); g.addColorStop(0.18, cs.body || '#555'); g.addColorStop(1, cs.deep || '#222');
  x.save(); x.globalAlpha = a; x.fillStyle = g; x.beginPath(); x.moveTo(...pts[0]); for (const q of pts) x.lineTo(...q);
  x.lineTo((r[0] + r[2]) * k, (r[1] + r[3]) * k); x.lineTo(r[0] * k, (r[1] + r[3]) * k); x.closePath(); x.fill();
  x.globalAlpha = Math.min(1, a * 1.6 + 0.2); x.strokeStyle = cs.foam || '#fff'; x.lineWidth = 1; x.beginPath(); x.moveTo(...pts[0]); for (const q of pts) x.lineTo(...q); x.stroke();
  const L = spec?.light;
  if (L && Object.keys(L).length && +L.every > 0) { x.globalCompositeOperation = 'lighter'; const n = Math.max(1, Math.round(r[2] / +L.every));
    for (let i = 0; i < n; i++) { const cx = (r[0] + r[2] * (i + 0.5) / n) * k, cy = r[1] * k, rad = Math.max(2, +L.radius * k), [R, G, B] = liqRgb(L.color), f = 1 - (+L.flicker || 0) * liqNoise(t * 4 + i * 7.3, i);
      const gr = x.createRadialGradient(cx, cy, 0, cx, cy, rad); gr.addColorStop(0, `rgba(${R},${G},${B},${0.35 * (+L.energy || 0) * f})`); gr.addColorStop(1, `rgba(${R},${G},${B},0)`); x.globalAlpha = 1; x.fillStyle = gr; x.fillRect(cx - rad, cy - rad, rad * 2, rad * 2); } }
  x.restore();
}
function liqMapFrame(t, dt) {
  const room = LIQ.rooms[LIQ.room], c = $('#liqMap'); if (!room || !c) return;
  const W = Math.max(200, c.clientWidth || 640), k = W / room.width, H = Math.round(room.height * k);
  if (c.width !== W || c.height !== H) { c.width = W; c.height = H; LIQ.base = null; }
  if (!LIQ.base || LIQ.base.room !== room || LIQ.base.w !== W || t - LIQ.base.t > 1) {
    const off = LIQ.base?.room === room && LIQ.base.w === W ? LIQ.base.c : document.createElement('canvas');
    Object.defineProperty(off, 'clientWidth', { value: W, configurable: true });
    drawRoomOverview(off, room, null, ''); LIQ.base = { room, w: W, c: off, t };
  }
  const x = c.getContext('2d'); x.drawImage(LIQ.base.c, 0, 0);
  for (const h of liqBuiltIn(room)) {
    const spec = liqSpec(h[0]), key = `${room.name}:built:${h[5]?.name || h.join()}`; let sim = LIQ.sims.get(key); if (!sim) LIQ.sims.set(key, sim = liqSim(h[3])); sim.kind = h[0];
    liqDrawPool(x, k, spec, sim, h.slice(1, 5), t, h[5]?.painted);
    x.save(); x.setLineDash([3, 3]); x.strokeStyle = 'rgba(255,170,90,.9)'; x.strokeRect(h[1] * k, h[2] * k, h[3] * k, h[4] * k);
    x.fillStyle = 'rgba(255,190,120,.95)'; x.font = '10px system-ui'; x.fillText(`сцена: ${liqName(h[0])}`, h[1] * k + 2, h[2] * k - 3); x.restore();
  }
  const list = liqList(), problems = new Set();
  list.forEach((p, i) => { if (!Array.isArray(p)) return; const one = liqPlaceProblems([p], liqKinds(), room); if (one.length) problems.add(i); });
  for (const m of liqPlaceProblems(list, liqKinds(), room).map(s => s.match(/^Жидкости (\d+) и (\d+)/)).filter(Boolean)) { problems.add(+m[1] - 1); problems.add(+m[2] - 1); }
  list.forEach((p, i) => {
    if (!Array.isArray(p)) return;
    const d = LIQ.drag, live = d && d.i === i && d.moved && d.now ? liqClamp(liqDragRect(d.now), room) : p.slice(1, 5);
    const key = `${room.name}:${i}:${live[2]}`; let sim = LIQ.sims.get(key); if (!sim) LIQ.sims.set(key, sim = liqSim(live[2])); sim.kind = p[0];
    liqDrawPool(x, k, liqSpec(p[0]), sim, live, t, p[5]?.painted);
    x.save(); x.strokeStyle = problems.has(i) ? '#ff5a5a' : i === LIQ.sel ? '#ffd75f' : 'rgba(255,255,255,.55)'; x.lineWidth = i === LIQ.sel ? 2 : 1;
    if (p[5]?.painted) x.setLineDash([4, 2]); x.strokeRect(live[0] * k + 0.5, live[1] * k + 0.5, live[2] * k, live[3] * k);
    x.fillStyle = x.strokeStyle; x.font = '11px system-ui'; x.fillText(`${i + 1} ${liqName(p[0])}`, live[0] * k + 3, live[1] * k + 12);
    if (i === LIQ.sel) { x.setLineDash([]); x.fillStyle = '#ffd75f'; for (const [hx, hy] of [[0, 0], [1, 0], [0, 1], [1, 1], [0.5, 0], [0.5, 1], [0, 0.5], [1, 0.5]]) x.fillRect((live[0] + live[2] * hx) * k - 3, (live[1] + live[3] * hy) * k - 3, 6, 6); }
    x.restore();
  });
  if (LIQ.drag?.part === 'new' && LIQ.drag.moved && LIQ.drag.now) { const r = liqDragRect(LIQ.drag.now); x.save(); x.strokeStyle = '#6aa8ff'; x.setLineDash([4, 3]); x.strokeRect(r[0] * k, r[1] * k, r[2] * k, r[3] * k);
    x.fillStyle = '#6aa8ff'; x.font = '11px system-ui'; x.fillText(`${Math.round(r[2])}×${Math.round(r[3])}`, (r[0] + r[2]) * k + 4, (r[1] + r[3]) * k); x.restore(); }
}

/* ---------- the preview: a pit in stone, a body to throw in ---------- */
const LIQ_PV = { W: 320, H: 180, floor: 108, x0: 60, x1: 260, top: 114, bottom: 166, G: 900, JUMP: 330 };
function liqPvSpec() { return liqSpec(LIQ.kind); }
function liqPvBackground(x) {
  const P = LIQ_PV, g = x.createLinearGradient(0, 0, 0, P.H); g.addColorStop(0, '#15121c'); g.addColorStop(1, '#0b0a10'); x.fillStyle = g; x.fillRect(0, 0, P.W, P.H);
  // a wall of dressed stone behind, and the pit
  for (let y = 0; y < P.H; y += 10) for (let i = 0; i < P.W / 20 + 1; i++) { const bx = i * 20 - (y / 10 % 2) * 10; x.fillStyle = `rgba(60,52,70,${0.25 + 0.15 * liqHash(i, y)})`; x.fillRect(bx + 1, y + 1, 18, 8); }
  x.fillStyle = '#2b2530'; x.fillRect(0, P.floor, P.x0, P.H - P.floor); x.fillRect(P.x1, P.floor, P.W - P.x1, P.H - P.floor); x.fillRect(P.x0 - 4, P.bottom, P.x1 - P.x0 + 8, P.H - P.bottom);
  x.fillStyle = '#45394a'; x.fillRect(0, P.floor, P.x0, 2); x.fillRect(P.x1, P.floor, P.W - P.x1, 2);
  x.fillStyle = '#1c1820'; x.fillRect(P.x0 - 4, P.floor, 4, P.bottom - P.floor); x.fillRect(P.x1, P.floor, 4, P.bottom - P.floor);
  if (LIQ.pv.painted) { const s = liqPvSpec(), c = s?.colors || {}; const gg = x.createLinearGradient(0, P.top, 0, P.bottom); gg.addColorStop(0, c.body || '#444'); gg.addColorStop(1, c.deep || '#111'); x.fillStyle = gg; x.fillRect(P.x0, P.top + 1, P.x1 - P.x0, P.bottom - P.top - 1); }
}
const liqPvSurf = (x, t) => LIQ_PV.top + (LIQ.pv.sim ? liqSurfaceAt(LIQ.pv.sim, x - LIQ_PV.x0, t, liqPvSpec()?.waves) : 0);
const liqInPool = x => x > LIQ_PV.x0 && x < LIQ_PV.x1;
function liqPart(p) { LIQ.pv.parts.push({ t: 0, g: 0, s: 1, ...p }); if (LIQ.pv.parts.length > 600) LIQ.pv.parts.shift(); }
function liqSplashParts(px, speed, big) {
  const s = liqPvSpec(); if (!s) return;
  const kind = s.particles?.splash || 'drops', tint = liqRgb(s.particles?.tint), foam = liqRgb(s.colors?.foam), sp = +s.waves?.splash || 0;
  const n = Math.min(48, Math.round((4 + speed / 45) * Math.max(0.2, sp) * (big ? 1 : 0.5))), r = (a, b) => a + Math.random() * (b - a), y = liqPvSurf(px, LIQ.t) - 1;
  for (let i = 0; i < n; i++) {
    if (kind === 'magma') liqPart({ x: px + r(-5, 5), y, vx: r(-50, 50), vy: -r(60, 170) * Math.max(0.4, sp), g: 520, life: r(0.6, 1.1), c: tint, s: r() < 0.3 ? 2 : 1, glow: true, sink: true });
    else if (kind === 'mud') liqPart({ x: px + r(-5, 5), y, vx: r(-40, 40), vy: -r(40, 120) * Math.max(0.4, sp), g: 620, life: r(0.5, 0.9), c: tint, s: 2, sink: true });
    else if (kind === 'blood') liqPart({ x: px + r(-5, 5), y, vx: r(-60, 60), vy: -r(70, 190) * Math.max(0.4, sp), g: 460, life: r(0.6, 1.0), c: tint, s: r() < 0.2 ? 2 : 1, sink: true });
    else liqPart({ x: px + r(-5, 5), y, vx: r(-65, 65), vy: -r(80, 220) * Math.max(0.4, sp), g: 420, life: r(0.5, 0.9), c: r() < 0.5 ? foam : tint, s: 1, sink: true });
  }
}
function liqAmbient(dt) {
  const s = liqPvSpec(); if (!s) return;
  const kind = s.particles?.ambient || 'none', every = Math.max(0.05, +s.particles?.ambient_every || 1), P = LIQ_PV;
  if (kind === 'none') return;
  LIQ.pv.ambient -= dt; if (LIQ.pv.ambient > 0) return; LIQ.pv.ambient = every;
  const tint = liqRgb(s.particles?.tint), foam = liqRgb(s.colors?.foam), r = (a, b) => a + Math.random() * (b - a), n = Math.max(1, Math.round((P.x1 - P.x0) / 64));
  for (let i = 0; i < n; i++) {
    const x = r(P.x0 + 2, P.x1 - 2), y = liqPvSurf(x, LIQ.t);
    if (kind === 'glints') liqPart({ x, y: y + r(0, 2), vx: 0, vy: 0, life: r(0.25, 0.5), c: foam, glow: true, twinkle: true });
    else if (kind === 'embers') liqPart({ x, y: y - 1, vx: r(-8, 8), vy: -r(15, 45), g: -20, life: r(1.0, 1.6), c: tint, glow: true });
    else if (kind === 'gas') liqPart({ x, y: r(y + 6, P.bottom - 3), vx: 0, vy: -r(8, 16), life: 6, c: tint, bubble: true, s: 2 });
    else if (kind === 'clots') liqPart({ x, y, vx: r(-5, 5), vy: 0, life: r(2, 3.5), c: tint.map(v => v * 0.55), s: 2, float: true });
  }
}
function liqDropBody(x, y) {
  const who = LIQ.pv.who === 'walker' ? 'walker' : 'hero';
  LIQ.pv.bodies.push({ x, y, vx: 0, vy: 0, w: who === 'hero' ? 6 : 9, h: who === 'hero' ? 14 : 11, who, state: 'fall', tIn: 0, stroke: 0, tries: 0, trail: 0, drip: 0, heal: 0, alpha: 1, life: 0 });
  if (LIQ.pv.bodies.length > 6) LIQ.pv.bodies.shift();
}
function liqFloat(s, x, y, c) { LIQ.pv.texts.push({ s, x, y, t: 0, c }); }
function liqBodyStep(b, dt) {
  const s = liqPvSpec(), P = LIQ_PV; if (!s) return;
  const body = b.who === 'hero' ? s.body || {} : { ...s.body, drag: s.enemy?.drag ?? s.body?.drag }, surf = liqPvSurf(b.x, LIQ.t), feet = b.y + b.h / 2;
  b.life += dt;
  if (b.state === 'fall' || b.state === 'out') {
    b.vy += P.G * dt; b.x += b.vx * dt; b.y += b.vy * dt;
    const f = b.y + b.h / 2;
    if (liqInPool(b.x) && f >= liqPvSurf(b.x, LIQ.t) && b.vy > 0) {
      const speed = b.vy; liqSplash(LIQ.pv.sim, b.x - P.x0, b.w + 4, speed, s.waves); liqSplashParts(b.x, speed, true);
      liqHear(speed > 420 ? s.sounds?.big : s.sounds?.enter);
      if (b.who === 'hero' && (+s.damage > 0 || s.burns)) { if (+s.damage > 0) liqFloat('−' + s.damage, b.x, b.y - 10, '#ff7060'); if (s.burns) { b.state = 'burn'; b.tIn = 0; return; } }
      if (b.who === 'walker' && s.kills_walkers) { b.state = 'die'; b.tIn = 0; liqFloat('гибнет', b.x, b.y - 10, '#ffb070'); return; }
      b.state = 'in'; b.tIn = 0; b.vx *= +body.drag || 0; b.vy *= +body.drag || 0; b.trail = 0;
    } else if (!liqInPool(b.x) && f >= P.floor && b.vy > 0) { b.y = P.floor - b.h / 2; b.vy = 0; b.vx = 0; b.state = 'stand'; b.tIn = 0; }
    if (b.state === 'out' && b.x > P.x0 - 6 && b.x < P.x1 + 6 && b.y > P.bottom) b.state = 'gone';
    return;
  }
  if (b.state === 'stand') { b.tIn += dt; if (b.tIn > 1.2) b.alpha -= dt * 2; if (b.alpha <= 0) b.state = 'gone'; return; }
  if (b.state === 'burn') { b.tIn += dt; if (Math.random() < 0.5) liqPart({ x: b.x + (Math.random() - 0.5) * 6, y: b.y - 4, vx: 0, vy: -30, g: -10, life: 0.6, c: [90, 80, 80], s: 2, smoke: true });
    if (b.tIn > 0.35) { b.x = 24; b.y = P.floor - b.h / 2; b.vx = 0; b.vy = 0; b.state = 'stand'; b.tIn = 0; liqFloat('назад на пол', 24, P.floor - 24, '#ffd0a0'); liqPart({ x: 24, y: P.floor - 6, ring: 10, life: 0.3, c: [255, 220, 180] }); }
    return; }
  if (b.state === 'die') { b.tIn += dt; b.y += 12 * dt; b.alpha = Math.max(0, 1 - b.tIn / 1.2); if (Math.random() < 0.4) liqPart({ x: b.x, y: surf - 2, vx: (Math.random() - 0.5) * 10, vy: -25, g: -10, life: 0.8, c: [80, 70, 70], s: 2, smoke: true }); if (b.tIn > 1.2) b.state = 'gone'; return; }
  // in the liquid
  b.tIn += dt;
  b.vy += P.G * (body.buoyancy ?? 1) * dt; /* player.gd: gravity × buoyancy */ b.vy = Math.min(b.vy, +body.sink_speed || 0); b.vx *= Math.pow(0.2, dt);
  if (b.who === 'hero' && +body.swim > 0 && b.tIn > 0.45) { b.stroke -= dt; if (b.stroke <= 0 && b.y - b.h / 2 > surf - 2) { b.vy = -(+body.swim); /* player.gd _swim_stroke */ b.stroke = Math.max(0.05, +body.swim_cooldown || 0.3); liqHear(s.sounds?.wade); liqSplash(LIQ.pv.sim, b.x - P.x0, 4, 80, s.waves); } }
  b.x += b.vx * dt; b.y += b.vy * dt;
  if (b.y + b.h / 2 > P.bottom) { b.y = P.bottom - b.h / 2; b.vy = 0; }
  if (b.who === 'hero' && s.heal?.path && +s.heal.per_second > 0) { b.heal -= dt; if (b.heal <= 0) { b.heal = 0.6; liqFloat('+' + s.heal.per_second, b.x, b.y - 10, '#9fe0a0'); } }
  if (b.who === 'walker' && +s.enemy?.heal_per_second > 0) { b.heal -= dt; if (b.heal <= 0) { b.heal = 0.6; liqFloat('+' + s.enemy.heal_per_second, b.x, b.y - 10, '#e0a0a0'); } }
  // out with a jump: the hero after a while (on the surface if he can swim), a walker that lives through it too
  const ready = +body.swim > 0 ? b.tIn > 1.6 && b.y - b.h / 2 <= surf + 2 : b.tIn > 1.4;
  if (ready) {
    b.tries++; b.tIn = 0;
    if (b.tries > 3) { b.state = 'die'; liqFloat('не выбрался', b.x, b.y - 12, '#c0c0c0'); return; }
    const bank = b.x - P.x0 < P.x1 - b.x ? P.x0 - 14 : P.x1 + 14;
    b.vy = -P.JUMP * (+body.jump || 0); b.vx = (bank - b.x) * 1.4; b.state = 'out'; b.trail = +s.particles?.trail_time || 0;
    liqSplash(LIQ.pv.sim, b.x - P.x0, b.w, 160, s.waves); liqSplashParts(b.x, 160, false); liqHear(s.sounds?.exit);
  }
}
function liqTrail(b, dt) {
  const s = liqPvSpec(); if (!s || b.trail <= 0 || b.state === 'in') return;
  b.trail -= dt; b.drip -= dt; if (b.drip > 0) return;
  const kind = s.particles?.trail || 'none', tint = liqRgb(s.particles?.tint);
  if (kind === 'drips') { b.drip = 0.09; liqPart({ x: b.x + (Math.random() - 0.5) * b.w, y: b.y + b.h / 2 - 2, vx: 0, vy: 10, g: 500, life: 0.8, c: tint, sink: true }); }
  else if (kind === 'mud') { b.drip = 0.14; liqPart({ x: b.x + (Math.random() - 0.5) * b.w, y: b.y + b.h / 2 - 2, vx: 0, vy: 5, g: 600, life: 0.8, c: tint.map(v => v * 0.8), s: 2, sink: true }); }
  else if (kind === 'smoke') { b.drip = 0.1; liqPart({ x: b.x + (Math.random() - 0.5) * b.w, y: b.y - b.h / 2, vx: (Math.random() - 0.5) * 8, vy: -22, g: -8, life: 0.9, c: [96, 88, 92], s: 2, smoke: true }); }
}
function liqPvFrame(t, dt) {
  const c = $('#liqPreview'); if (!c) return;
  const P = LIQ_PV, s = liqPvSpec(); if (!s) return;
  if (c.width !== P.W) { c.width = P.W; c.height = P.H; }
  const x = c.getContext('2d'); x.imageSmoothingEnabled = false;
  if (!LIQ.pv.sim || LIQ.pv.kind !== LIQ.kind) { LIQ.pv.sim = liqSim(P.x1 - P.x0); LIQ.pv.kind = LIQ.kind; LIQ.pv.parts = []; }
  if (LIQ.pv.autoOn !== false) { LIQ.pv.auto -= dt; if (LIQ.pv.auto <= 0) { LIQ.pv.auto = 3.6; liqDropBody(P.x0 + 30 + Math.random() * (P.x1 - P.x0 - 60), 8); } }
  liqAmbient(dt);
  for (const b of LIQ.pv.bodies) { liqBodyStep(b, dt); liqTrail(b, dt); }
  LIQ.pv.bodies = LIQ.pv.bodies.filter(b => b.state !== 'gone');
  liqPvBackground(x);
  const img = x.getImageData(0, 0, P.W, P.H);
  // bodies under the surface are drawn into the picture first, so the liquid lies over them
  const drawBody = (d, b, under) => {
    const col = b.who === 'hero' ? [[150, 160, 180], [220, 200, 170]] : [[140, 70, 60], [180, 110, 90]];
    for (let yy = Math.round(b.y - b.h / 2); yy < Math.round(b.y + b.h / 2); yy++) for (let xx = Math.round(b.x - b.w / 2); xx < Math.round(b.x + b.w / 2); xx++) {
      if (xx < 0 || yy < 0 || xx >= P.W || yy >= P.H) continue;
      const head = yy < b.y - b.h / 2 + (b.who === 'hero' ? 4 : 3), cc = head ? col[1] : col[0], j = (yy * P.W + xx) * 4, a = b.alpha * (under ? 1 : 1);
      d[j] += (cc[0] - d[j]) * a; d[j + 1] += (cc[1] - d[j + 1]) * a; d[j + 2] += (cc[2] - d[j + 2]) * a;
    }
  };
  for (const b of LIQ.pv.bodies) drawBody(img.data, b, true);
  liqPaint(img, s, LIQ.pv.sim, { x: P.x0, y: P.top, w: P.x1 - P.x0, h: P.bottom - P.top }, t, { painted: LIQ.pv.painted, tex: liqTex(LIQ.kind) });
  // what stands above the surface is drawn again over the liquid
  for (const b of LIQ.pv.bodies) if (b.state !== 'in' && b.state !== 'die' || b.y - b.h / 2 < liqPvSurf(b.x, t)) {
    const surf = liqInPool(b.x) ? liqPvSurf(b.x, t) : P.H, keep = { ...b, h: Math.max(0, Math.min(b.h, surf - (b.y - b.h / 2))) }; keep.y = b.y - b.h / 2 + keep.h / 2; if (keep.h > 0) drawBody(img.data, keep, false);
  }
  x.putImageData(img, 0, 0);
  // light along the surface
  const L = s.light;
  if (L && Object.keys(L).length && +L.every > 0) { x.save(); x.globalCompositeOperation = 'lighter'; const n = Math.max(1, Math.round((P.x1 - P.x0) / +L.every)), [R, G, B] = liqRgb(L.color);
    for (let i = 0; i < n; i++) { const cx = P.x0 + (P.x1 - P.x0) * (i + 0.5) / n, cy = P.top + 4, rad = Math.max(2, +L.radius), f = 1 - (+L.flicker || 0) * liqNoise(t * 4 + i * 7.3, i);
      const g = x.createRadialGradient(cx, cy, 0, cx, cy, rad); g.addColorStop(0, `rgba(${R},${G},${B},${0.45 * (+L.energy || 0) * f})`); g.addColorStop(1, `rgba(${R},${G},${B},0)`); x.fillStyle = g; x.fillRect(cx - rad, cy - rad, rad * 2, rad * 2); }
    x.restore(); }
  // particles
  for (const p of LIQ.pv.parts) {
    p.t += dt; const k = Math.max(0, 1 - p.t / p.life), [R, G, B] = p.c;
    if (p.ring) { x.strokeStyle = `rgba(${R},${G},${B},${k})`; x.lineWidth = 1; x.beginPath(); x.arc(p.x, p.y, p.ring * (1.2 - k), 0, 7); x.stroke(); continue; }
    if (p.float) { p.x += p.vx * dt; p.y = liqPvSurf(p.x, t); if (!liqInPool(p.x)) p.t = p.life; }
    else { p.vy += (p.g || 0) * dt; p.x += p.vx * dt; p.y += p.vy * dt; }
    if (p.bubble && liqInPool(p.x) && p.y <= liqPvSurf(p.x, t)) { p.t = p.life; liqPart({ x: p.x, y: p.y - 1, ring: 3, life: 0.25, c: p.c }); liqSplash(LIQ.pv.sim, p.x - P.x0, 2, 40, s.waves); if (Math.random() < 0.35) liqHear(s.sounds?.bubble); continue; }
    if (p.sink && p.vy > 0 && liqInPool(p.x) && p.y >= liqPvSurf(p.x, t)) { p.t = p.life; liqSplash(LIQ.pv.sim, p.x - P.x0, 1, 30, s.waves); continue; }
    if (p.sink && p.vy > 0 && !liqInPool(p.x) && p.y >= P.floor) { p.y = P.floor - 1; p.vy = 0; p.vx = 0; p.g = 0; }
    const a = p.twinkle ? Math.sin(k * Math.PI) : p.smoke ? 0.5 * k : k;
    x.globalCompositeOperation = p.glow ? 'lighter' : 'source-over';
    x.fillStyle = `rgba(${R | 0},${G | 0},${B | 0},${a})`; x.fillRect(Math.round(p.x), Math.round(p.y), p.s, p.s);
  }
  x.globalCompositeOperation = 'source-over';
  LIQ.pv.parts = LIQ.pv.parts.filter(p => p.t < p.life);
  x.font = '7px system-ui'; x.textAlign = 'center';
  for (const q of LIQ.pv.texts) { q.t += dt; x.fillStyle = q.c; x.globalAlpha = Math.max(0, 1 - q.t / 1.1); x.fillText(q.s, q.x, q.y - q.t * 14); }
  x.globalAlpha = 1; x.textAlign = 'left'; LIQ.pv.texts = LIQ.pv.texts.filter(q => q.t < 1.1);
  x.fillStyle = '#cfd8e3'; x.fillText(`${liqName(LIQ.kind)}${LIQ.pv.painted ? ' · поверх картины' : ''}${s.sounds?.ambient ? ' · фон ♪ ' + s.sounds.ambient : ''}`, 6, 10);
  LIQ.pv.heard.forEach((h, i) => { h.t += dt; x.fillStyle = `rgba(255,215,95,${Math.max(0, 1 - h.t / 1.6)})`; x.fillText('♪ ' + h.name, 6, 20 + i * 8); });
  LIQ.pv.heard = LIQ.pv.heard.filter(h => h.t < 1.6);
}
function liqPvClick(e) {
  const c = $('#liqPreview'), r = c.getBoundingClientRect(), P = LIQ_PV, s = Math.min(r.width / P.W, r.height / P.H);
  const x = (e.clientX - r.left - (r.width - P.W * s) / 2) / s, y = (e.clientY - r.top - (r.height - P.H * s) / 2) / s;
  if (x < 0 || x > P.W || y < 0 || y > P.H) return;
  if (liqInPool(x) && y >= liqPvSurf(x, LIQ.t) - 2) { liqSplash(LIQ.pv.sim, x - P.x0, 10, 420, liqPvSpec()?.waves); liqSplashParts(x, 420, true); liqHear(liqPvSpec()?.sounds?.enter); }
  else liqDropBody(x, y);
}
function liqLoop(now) {
  LIQ.raf = 0; if (mode !== 'liq') return;
  const dt = Math.min(0.05, (now - (LIQ.last || now)) / 1000); LIQ.last = now; LIQ.t += dt;
  // the springs step at 60 Hz, as in the game's physics frame
  LIQ.acc += dt;
  while (LIQ.acc >= 1 / 60) {
    LIQ.acc -= 1 / 60;
    if (LIQ.view === 'kind' && LIQ.pv.sim) liqSpringStep(LIQ.pv.sim, liqPvSpec()?.waves);
    if (LIQ.view === 'room') for (const [key, sim] of LIQ.sims) if (key.startsWith(LIQ.room + ':')) liqSpringStep(sim, liqSpec(sim.kind)?.waves);
  }
  if (LIQ.sims.size > 200) LIQ.sims.clear();
  try { if (LIQ.view === 'room') liqMapFrame(LIQ.t, dt); else liqPvFrame(LIQ.t, dt); } catch (err) { console.error(err); }
  LIQ.raf = requestAnimationFrame(liqLoop);
}
async function liqEnter() {
  try { LIQ.view = localStorage.getItem('ss_liq_view') || LIQ.view; } catch {}
  await loadCutData();
  if (!WORLD.data.files[LIQ_PATH]) { $('#gdSide_liq').innerHTML = '<div class="warn">Нет data/liquids.json в import/world.json — перезапусти tools/studio/build_data.py.</div>'; return; }
  liqSfxLoad().then(() => { if (LIQ.view === 'kind') renderLiq(); });
  renderLiq();
  if (!LIQ.raf) LIQ.raf = requestAnimationFrame(liqLoop);
}
// js/gamedata.js mounted its tabs as it loaded; this one comes after it and mounts itself the same way
function liqMount() {
  const modes = $('.modes'); if (!modes || $('#gdLayout_liq')) return;
  const t = STUDIO_TABS.liq, style = document.createElement('style');
  style.textContent = `body:not([data-mode=liq]) #gdLayout_liq{display:none!important}
    body[data-mode=liq] :is(.layout,.bglayout,.cutlayout,.sndlayout,.riglayout,.lifelayout,.attacklayout,.shotlayout,.pfxlayout,.gorelayout,.dlglayout,.complayout){display:none!important}
    #gdLayout_liq .side{overflow:auto}.liqsw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px;border:1px solid #0006}
    .liqrow{display:flex;flex-wrap:wrap;gap:3px 6px;align-items:center;padding:4px;border-radius:5px;margin:3px 0;border:1px solid var(--line)}.liqrow.on{outline:2px solid #ffd75f}
    .liqrow label{display:flex;align-items:center;gap:2px;font-size:11px;margin:0}.liqrow input[type=number]{width:54px}.liqrow select{width:auto}
    .liqfield{display:grid;grid-template-columns:1fr 90px 58px auto;gap:4px;align-items:center;font-size:12px;margin:2px 0}.liqfield.changed span{color:#ffd75f}.liqfield input[type=number]{width:58px}
    .liqcolors{display:grid;grid-template-columns:1fr 1fr;gap:2px 8px}.liqcolor{display:flex;align-items:center;gap:6px;font-size:12px}.liqcolor input{width:34px;height:22px;padding:0;flex:none}
    .liqsum{font-size:12px;line-height:1.45}#liqMapBox{flex:1;min-height:0;overflow:auto}#liqMap{width:100%;display:block;border-radius:6px;cursor:crosshair;touch-action:none}
    #liqPreview{flex:1;min-height:0;width:100%;object-fit:contain;image-rendering:pixelated;background:#0f0d14;border-radius:6px;cursor:pointer}`;
  document.head.append(style);
  const b = document.createElement('button'); Object.assign(b.dataset, { act: 'mode', m: 'liq' }); b.textContent = t.label; b.title = t.tip;
  const after = [...modes.querySelectorAll('button')].find(x => x.dataset.m === 'gore'); if (after) after.after(b); else modes.append(b);
  const box = document.createElement('div'); box.id = 'gdLayout_liq'; box.className = 'gdlayout'; box.innerHTML = t.html;
  ($('#gdLayout_places') || $('#goreLayout')).after(box);
  box.addEventListener('input', liqInput); box.addEventListener('change', liqInput); box.addEventListener('click', liqClick);
  const map = $('#liqMap');
  map.addEventListener('pointerdown', liqMapDown); map.addEventListener('pointermove', liqMapMove); map.addEventListener('pointerup', liqMapUp); map.addEventListener('dblclick', liqMapDbl);
  $('#liqPreview').addEventListener('click', liqPvClick);
  document.addEventListener('keydown', liqKey);
}
if (typeof document !== 'undefined' && typeof STUDIO_TABS !== 'undefined') {
  STUDIO_TABS.liq = {
    label: 'Жидкости', title: 'liquids', tip: 'Вода, лава, топь и кровь: где лежат в комнатах (tools/rooms/studio_rooms.json) и какие они (data/liquids.json)',
    paths: p => p === LIQ_PATH || p === LIQ_ROOMS, strings: false,
    html: `<aside class="side lifeside" id="gdSide_liq"></aside><main class="lifemain"><div class="lifebar" id="gdBar_liq"></div><div id="liqMapBox"><canvas id="liqMap"></canvas></div><canvas id="liqPreview" hidden></canvas></main>`,
    render: renderLiq, enter: liqEnter, problems: liqAllProblems,
    text: (p, value) => p === LIQ_PATH ? liqText(value) : undefined,
  };
  liqMount();
}
