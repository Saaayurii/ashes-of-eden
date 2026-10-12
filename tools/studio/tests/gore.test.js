'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { goreSpec, goreText, goreCut, goreProblems } = require('../js/gore.js');

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
test('the game\'s table is valid, and bad values are caught before a send', () => {
  assert.deepEqual(goreProblems({ materials: doc.materials, bodies: doc.bodies }), []);
  assert.ok(goreProblems({ materials: { flesh: { limbs: 1 } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: { drops: 99 } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: { blood: 'red' } }, bodies: {} }).length);
  assert.ok(goreProblems({ materials: { flesh: {} }, bodies: { x: { material: 'ice' } } }).length);
});
