'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { attackDiff, attackProblems } = require('../js/attacks.js');
const { patchJson } = require('../lib.js');
test('attack changes patch only touched fields, including removed fields', () => {
  const base = { type: 'nova', damage: 7, color: '#ff0000', obsolete: true };
  const next = { type: 'nova', damage: 7, color: '#8a7458', hit_frame: 1 };
  const diff = attackDiff(base, next);
  assert.deepEqual(Object.keys(diff).sort(), ['color', 'hit_frame', 'obsolete']);
  const source = '{"keep": 1, "attacks": [' + JSON.stringify(base) + ']}\n';
  const patched = patchJson(source, ['attacks', 0], diff);
  assert.deepEqual(JSON.parse(patched).attacks[0], next);
  assert.ok(patched.startsWith('{"keep": 1, '));
});
test('frame bounds and effect types are validated before sending', () => {
  const a = { type: 'nova', range: 90, windup: .85, damage: 7, cooldown: 4, hit_frame: 1, impact_fx: 'dust', telegraph_fx: 'none' };
  assert.deepEqual(attackProblems(a, 7), []);
  for (const hit_frame of [-1, 7, 1.5]) assert.ok(attackProblems({ ...a, hit_frame }, 7).length);
  assert.ok(attackProblems({ ...a, type: 'melee' }, 7).length);
  assert.ok(attackProblems({ ...a, telegraph_fx: 'red' }, 7).length);
  assert.ok(attackProblems({ ...a, damage: 0 }, 7).length);
});
