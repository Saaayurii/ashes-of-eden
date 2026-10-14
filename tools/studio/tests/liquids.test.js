// js/liquids.js: data/liquids.json written back as the game keeps it, the spring surface, and the checks on a room's
// "liquids" in tools/rooms/studio_rooms.json.
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const L = require('../js/liquids.js');
const { fmtStudioRooms, mergeStudioRooms } = require('../lib.js');

const ROOT = path.join(__dirname, '..', '..', '..');
const text = fs.readFileSync(path.join(ROOT, 'data/liquids.json'), 'utf8');
const doc = JSON.parse(text);

test('data/liquids.json is written back byte for byte when nothing changed', () => {
  assert.equal(L.liqText(doc), text);
});
test('a changed number changes its line only, and stays a float', () => {
  const v = structuredClone(doc); v.kinds.water.waves.amplitude = 2; v.kinds.lava.damage = 25.5;
  const out = L.liqText(v), a = text.split('\n'), b = out.split('\n');
  assert.equal(a.length, b.length);
  const diff = a.map((l, i) => l === b[i] ? null : i).filter(i => i !== null);
  assert.equal(diff.length, 2);
  assert.match(out, /"amplitude": 2\.0,/);
  assert.match(out, /"damage": 25\.5,/);
  assert.deepEqual(JSON.parse(out), v);
});
test('today\'s kinds pass the studio\'s own checks', () => {
  assert.deepEqual(L.liqKindProblems(doc), []);
  const bad = structuredClone(doc); bad.kinds.water.opacity = 2; bad.kinds.bog.particles.splash = 'confetti'; bad.kinds.blood.colors.foam = 'red';
  const p = L.liqKindProblems(bad);
  assert.equal(p.length, 3);
  assert.ok(p.some(s => s.includes('Непрозрачность') && s.includes('0…1')));
});

test('a resting spring surface stays at rest, a splash spreads and dies away', () => {
  const waves = doc.kinds.water.waves, s = L.liqSim(200);
  assert.equal(s.h.length, 200 / L.LIQ_COL + 1);
  for (let i = 0; i < 60; i++) L.liqSpringStep(s, waves);
  assert.ok(s.h.every(h => h === 0));
  L.liqSplash(s, 100, 8, 500, waves);
  const mid = Math.round(100 / L.LIQ_COL);
  for (let i = 0; i < 10; i++) L.liqSpringStep(s, waves);
  assert.ok(s.h[mid] > 0, 'the surface goes down under the body');
  assert.ok(Math.abs(s.h[mid + 8]) > 1e-4, 'the ripple reaches the neighbours');
  for (let i = 0; i < 1200; i++) L.liqSpringStep(s, waves);
  assert.ok(Math.max(...s.h.map(Math.abs)) < 0.05, 'and dies away');
});
test('the surface between columns is the springs plus the resting wave', () => {
  const s = L.liqSim(40); s.h[1] = 2; s.h[2] = 4;
  const w = { amplitude: 0, length: 50, speed: 1 };
  assert.equal(L.liqSurfaceAt(s, L.LIQ_COL * 1.5, 0, w), 3);
  assert.ok(Math.abs(L.liqSurfaceAt(L.liqSim(40), 12.5, 0, { amplitude: 2, length: 50, speed: 1 }) - 2) < 1e-9);
});
test('the pool is painted: foam on the surface row, the liquid below, nothing above', () => {
  const W = 40, H = 30, img = { width: W, height: H, data: new Uint8ClampedArray(W * H * 4) };
  const spec = { ...doc.kinds.lava, waves: { ...doc.kinds.lava.waves, amplitude: 0 }, shimmer: 0 };
  L.liqPaint(img, spec, L.liqSim(30), { x: 5, y: 10, w: 30, h: 15 }, 0);
  const px = (x, y) => [...img.data.slice((y * W + x) * 4, (y * W + x) * 4 + 3)];
  assert.deepEqual(px(10, 9), [0, 0, 0]);
  const foam = L.liqRgb(spec.colors.foam), got = px(10, 10);
  got.forEach((v, i) => assert.ok(Math.abs(v - foam[i] * 1) < 0.12 * 255 + 40, 'foam'));
  assert.ok(px(10, 20).some(v => v > 0), 'the body');
  assert.deepEqual(px(10, 26), [0, 0, 0]);
  assert.deepEqual(px(2, 15), [0, 0, 0]);
});

test('a pool\'s surface lies on a floor it nearly touches', () => {
  const surfaces = [[0, 500, 300], [400, 600, 200]];
  assert.equal(L.liqSnap(surfaces, 100, 503, 50), 500);
  assert.equal(L.liqSnap(surfaces, 100, 520, 50), 520);
  assert.equal(L.liqSnap(surfaces, 350, 598, 100), 600);
});
test('handles, moving and resizing', () => {
  const list = [['water', 100, 100, 80, 30], ['lava', 300, 200, 50, 20]];
  assert.deepEqual(L.liqHit(list, 120, 110, 4, -1), { i: 0, part: 'move' });
  assert.deepEqual(L.liqHit(list, 100, 100, 4, 0), { i: 0, part: 'nw' });
  assert.deepEqual(L.liqHit(list, 140, 131, 4, 0), { i: 0, part: 's' });
  assert.equal(L.liqHit(list, 10, 10, 4, 0), null);
  assert.deepEqual(L.liqDrag([100, 100, 80, 30], 'move', 5, -3), [105, 97, 80, 30]);
  assert.deepEqual(L.liqDrag([100, 100, 80, 30], 'nw', 10, 10), [110, 110, 70, 20]);
  assert.deepEqual(L.liqDrag([100, 100, 80, 30], 'se', 10, 5), [100, 100, 90, 35]);
  assert.deepEqual(L.liqClamp([-10.4, 700, 50.6, 40], { width: 1280, height: 720 }), [0, 680, 51, 40]);
});
test('what a room\'s liquids may not be, in Russian', () => {
  const kinds = doc.kinds, room = { width: 1280, height: 720 };
  assert.deepEqual(L.liqPlaceProblems([['water', 10, 500, 100, 40], ['lava', 200, 600, 80, 30, { painted: true }]], kinds, room), []);
  const p = L.liqPlaceProblems([['acid', 10, 10, 100, 40], ['water', 0, 0, 10, 4], ['bog', 1250, 700, 60, 40], ['blood', 50, 20, 30, 30], ['water', 1, 2, 3]], kinds, room);
  assert.ok(p.includes('Жидкость 1: неизвестный вид «acid»'));
  assert.ok(p.includes('Жидкость 2: ширина 10 px — нужно не меньше 16'));
  assert.ok(p.includes('Жидкость 2: глубина 4 px — нужно не меньше 8'));
  assert.ok(p.includes('Жидкость 3 выходит за комнату (1280×720)'));
  assert.ok(p.includes('Жидкости 1 и 4 накладываются'));
  assert.ok(p.includes('Жидкость 5: нужно [вид, x, y, ширина, глубина]'));
  assert.ok(L.liqPlaceProblems([['water', 0, 0, 20, 10, { glow: 1 }]], kinds, room)[0].includes('неизвестная настройка'));
});
test('studio_rooms.json keeps each liquid on one line, as it keeps spawns', () => {
  const t = fs.readFileSync(path.join(ROOT, 'tools/rooms/studio_rooms.json'), 'utf8');
  assert.equal(fmtStudioRooms(JSON.parse(t)), t);
  const v = JSON.parse(t); (v.crypt_lava ||= {}).liquids = [['water', 100, 600, 200, 40], ['lava', 400, 650, 80, 30, { painted: true }]];
  const out = fmtStudioRooms(v);
  assert.match(out, /\n      \["water", 100, 600, 200, 40\],\n      \["lava", 400, 650, 80, 30, \{"painted": true\}\]\n/);
  assert.deepEqual(JSON.parse(out), v);
  assert.deepEqual(Object.keys(JSON.parse(out)), Object.keys(v).sort());
  // the old writer and the new one agree
  assert.equal(mergeStudioRooms(out, { room: 'church', intro_cutscene: 'x' }), fmtStudioRooms({ ...v, church: { ...(v.church || {}), intro_cutscene: 'x' } }));
});
