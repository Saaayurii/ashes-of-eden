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
