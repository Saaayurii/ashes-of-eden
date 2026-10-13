'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { goreSpec, goreText, goreCut, gorePickCut, goreProblems } = require('../js/gore.js');

const FILE = path.join(__dirname, '../../../data/gore.json');
const text = fs.readFileSync(FILE, 'utf8');
const doc = JSON.parse(text);

test('the studio writes data/gore.json byte for byte when nothing changed', () => {
  assert.equal(goreText(doc._comment, { materials: doc.materials, bodies: doc.bodies }), text);
});
test('a body lays its own keys over its material (Gore.spec)', () => {
  const work = { materials: { flesh: { drops: 9, limbs: 5 }, spirit: { drops: 5, limbs: 0 } }, bodies: { elian: { limbs: 0 }, odd: { material: 'spirit' } } };
  const d = { drops: 6, limbs: 0, blood: '#7a0c10' };
  assert.deepEqual(goreSpec(work, d, 'elian', 'flesh'), { drops: 9, limbs: 0, blood: '#7a0c10' });
  assert.equal(goreSpec(work, d, 'villager', 'flesh').limbs, 5);
  assert.equal(goreSpec(work, d, 'odd', 'flesh').drops, 5);
  assert.equal(goreSpec(work, d, 'x', 'no_such').drops, 9);   // an unknown material bleeds like flesh
});
test('the cuts match Gore.cut: as many pieces as asked, inside the drawing', () => {
  const b = [10, 4, 20, 40];
  for (const n of [2, 3, 4, 5, 6]) {
    const parts = goreCut(b, n);
    assert.equal(parts.length, n);
    for (const { rect: [x, y, w, h] } of parts) assert.ok(x >= 10 && y >= 4 && x + w <= 30.5 && y + h <= 44.5, `${n}: ${[x, y, w, h]}`);
  }
  assert.deepEqual(goreCut(b, 4).map(p => p.name), ['head', 'torso', 'leg_l', 'leg_r']);
});
test('every way to tear, ragged, as Gore.cut: the right pieces, inside the drawing, what is left stands', () => {
  const b = [10, 4, 20, 40], ways = { head: ['head', 'body'], half: ['upper', 'lower'], limb: ['arm', 'body', 'legs'], all: ['head', 'arm_l', 'torso', 'arm_r', 'leg_l', 'leg_r'] };
  for (const [way, names] of Object.entries(ways)) for (let n = 0; n < 20; n++) {
    const parts = goreCut(b, 6, way, 0.07);
    assert.deepEqual(parts.map(p => way === 'limb' && p.name.startsWith('arm') ? 'arm' : p.name), names);
    for (const { name, rect: [x, y, w, h], stands } of parts) {
      assert.ok(x >= 10 && y >= 4 && x + w <= 30.5 && y + h <= 44.5 && w >= 1 && h >= 1, `${way} ${name}: ${[x, y, w, h]}`);
      assert.equal(stands, way !== 'all' && ['body', 'lower', 'legs'].includes(name), `${way} ${name}`);
    }
  }
  assert.deepEqual(goreCut(b, 4, 'limb').map(p => p.name), ['head', 'body']);   // no arms: the head
  assert.ok(new Set(Array.from({ length: 12 }, () => JSON.stringify(goreCut(b, 6, 'all', 0.07).map(p => p.rect)))).size > 6);
});
test('the ways are picked by their weights (Gore.pick_cut)', () => {
  const seen = {};
  for (let i = 0; i < 400; i++) { const w = gorePickCut({ all: 1, head: 1, half: 0 }, 6); seen[w] = (seen[w] || 0) + 1; }
  assert.deepEqual(Object.keys(seen).sort(), ['all', 'head']);
  assert.ok(seen.all > 120 && seen.head > 120);
  assert.equal(gorePickCut({ limb: 1 }, 4), 'head');
  assert.equal(gorePickCut({}, 6), 'all');
});
test('the game\'s table is valid, and bad values are caught before a send', () => {
  assert.deepEqual(goreProblems({ materials: doc.materials, bodies: doc.bodies }), []);
  assert.ok(goreProblems({ materials: { flesh: { limbs: 1 } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: { drops: 99 } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: { blood: 'red' } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: {} }, bodies: { x: { material: 'ice' } } }).length);
  assert.ok(goreProblems({ materials: { flesh: { cuts: { all: 0 } } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: { cuts: { sideways: 1 } } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: { cuts: { head: 11 } } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: { shade: 0.9 } }, bodies: {} }).length);
});

/* the preview's physics, as gore.gd's: blood keeps to what it lands on */
const G = require('../js/gore.js');
const ink = { stain: 1, life: 30, soak: 0.6, splash: 6, run: 30, drip: 1, back: 0 };
const run = (st, seconds) => { for (let t = 0; t < seconds; t += 1 / 60) { G.GORE.clock += 1 / 60; G.goreStep(1 / 60, st); } };
const fresh = () => { G.GORE.drops = []; G.GORE.stains = []; G.GORE.drips = []; G.GORE.pieces = []; G.GORE.wound = 0; };
test('a mark on the ledge stops at its edges, and what hangs over drips to the floor', () => {
  const st = G.goreStage(480, 270), L = st.ledge; fresh();
  for (let i = 0; i < 12; i++) G.goreDrop(L.x1 - 4 + Math.random() * 3.5, L.top - 16, 0, 40, [200, 0, 0, 1], ink, G.SPLASHED);
  run(st, 0.3);
  const on = G.GORE.stains.filter(s => s.face === 0 && s.y === L.top);
  assert.ok(on.length && on.every(s => s.lo === L.x0 && s.hi === L.x1));
  assert.ok(G.GORE.drips.length, 'gathering to drip off the edge');
  run(st, 4);
  assert.ok(G.GORE.stains.some(s => s.face === 0 && s.y === st.ground && s.x >= L.x1 - 1), 'dripped onto the floor below');
});
test('a streak runs down the wall no further than its foot; the underside drips', () => {
  const st = G.goreStage(480, 270); fresh();
  for (let i = 0; i < 8; i++) G.goreDrop(st.wall - 20, st.foot - 20 + Math.random() * 18, 400, 0, [200, 0, 0, 1], ink, G.SPLASHED);
  run(st, 0.2);
  const streaks = G.GORE.stains.filter(s => s.face === 1);
  assert.ok(streaks.length >= 6 && streaks.every(s => s.y + s.w <= st.foot + 0.5));
  fresh(); G.goreDrop(st.ledge.x0 + 10, st.ledge.bottom + 20, 0, -400, [200, 0, 0, 1], ink, G.SPLASHED);
  run(st, 0.15);
  assert.ok(G.GORE.stains.some(s => s.face === 2 && s.y === st.ledge.bottom) && G.GORE.drips.length);
});
test('a heavy drop splashes; drops into the depth stick to the wall behind, never in the sky', () => {
  const st = G.goreStage(480, 270); fresh();
  G.goreDrop(40, st.ground - 60, 0, 300, [200, 0, 0, 1], ink);
  G.GORE.drops[0].flags = 0;
  run(st, 0.25);
  assert.ok(G.GORE.drops.length + G.GORE.stains.length >= 3, 'droplets thrown back up');
  fresh();
  const [ox, oy, ow, oh] = st.opening;
  for (let i = 0; i < 10; i++) { G.goreDrop(ox + ow / 2, oy + oh / 2, 0, 0, [200, 0, 0, 1], ink, G.BACK); G.goreDrop(300, 60, 0, 0, [200, 0, 0, 1], ink, G.BACK); }
  run(st, 0.4);
  const behind = G.GORE.stains.filter(s => s.face === 3);
  assert.ok(behind.length >= 8 && behind.every(s => s.x > ox + ow) && behind.every(s => s.soak === 0.6));
});
test('mist leaves no mark', () => {
  const st = G.goreStage(480, 270); fresh();
  for (let i = 0; i < 20; i++) G.goreDrop(100, st.ground - 4, 0, 50, [200, 0, 0, 0.4], ink, G.MISTY);
  run(st, 1);
  assert.equal(G.GORE.stains.length, 0);
});
