// js/textures.js («Текстуры»): its check agrees with tools/rooms/studio_textures.py, a handle dragged keeps the opposite
// one where it was, and an edit of a generated picture keeps only what differs from the scene.
const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const { execFileSync } = require('child_process');
const T = require('../js/textures.js');

const ROOT = path.join(__dirname, '..', '..', '..');
const TOMB = 'decor/tombstone_3.png';
const near = (a, b, eps = 1e-6) => a.every((v, i) => Math.abs(v - b[i]) < eps);

test('the studio refuses what the generator refuses, and nothing else', () => {
  const entries = [
    { textures: [{ tex: TOMB, at: [10, 20], scale: [1.5, 0.5], rot: -12, flip_h: true, layer: 'top', z: 2, tint: '#c8b8ff', alpha: 0.5, blend: 'add', region: [0, 0, 300, 40], repeat: 'tile', filter: 'pixel', name: 'a' }],
      retouch: { 'DecorMid/tomb_1': { was: TOMB, at: [1, 2], hidden: true } } },
    { textures: [{ at: [0, 0] }] },
    { textures: [{ tex: TOMB }] },
    { textures: [{ tex: '../x.png', at: [0, 0] }] },
    { textures: [{ tex: TOMB, at: [0, 0], scale: [0, 1] }] },
    { textures: [{ tex: TOMB, at: [0, 0], rot: 400 }] },
    { textures: [{ tex: TOMB, at: [0, 0], layer: 'sky' }] },
    { textures: [{ tex: TOMB, at: [0, 0], tint: 'red' }] },
    { textures: [{ tex: TOMB, at: [0, 0], z: 1.5 }] },
    { textures: [{ tex: TOMB, at: [0, 0], region: [0, 0, 0, 4] }] },
    { textures: [{ tex: TOMB, at: [0, 0], wobble: 1 }] },
    { retouch: { 'DecorMid/x': { layer: 'top' } } },
    { retouch: { '../x': {} } },
  ];
  const py = `import json, sys
sys.path.insert(0, "tools/rooms")
import studio_textures as st
out = []
for e in json.loads(sys.stdin.read()):
    try:
        st.validate("room", e); out.append(0)
    except SystemExit as err:
        out.append(len(str(err).splitlines()))
print(json.dumps(out))`;
  const counts = JSON.parse(execFileSync('python3', ['-c', py], { cwd: ROOT, input: JSON.stringify(entries) }).toString());
  entries.forEach((e, i) => assert.strictEqual(T.txProblems('room', e, () => true).length, counts[i], JSON.stringify(e)));
});

test('a corner dragged stretches the picture and the opposite corner stays', () => {
  for (const o of [{ at: [100, 50], scale: [1, 1], rot: 0 }, { at: [100, 50], scale: [2, 0.5], rot: 30, flip_h: true }, { at: [7, 9], scale: [1.5, 1], rot: -75, flip_v: true, centered: false }]) {
    const box = T.txBox(o, 40, 20), fixed = T.txApply(T.txMatrix(o), box[0], box[1]);  // the nw corner, opposite se
    const r = T.txResize(o, box, 'se', [300, 260]);
    const n = { ...o, ...r };
    assert.ok(near(T.txApply(T.txMatrix(n), box[0], box[1]), fixed), JSON.stringify(o));
    assert.ok(near(T.txApply(T.txMatrix(n), box[0] + box[2], box[1] + box[3]), [300, 260], 1e-6) || r.scale.some(s => s === 0.02 || s === 40), JSON.stringify(o));
  }
});

test('an edge stretches one way only, Shift keeps the proportions', () => {
  const o = { at: [0, 0], scale: [1, 1], rot: 0 }, box = T.txBox(o, 40, 20);
  assert.deepStrictEqual(T.txResize(o, box, 'e', [60, 999]).scale, [2, 1]);
  const u = T.txResize(o, box, 'se', [40, 20], 'scale', true).scale;
  assert.ok(Math.abs(u[0] - u[1]) < 1e-9);
});

test('in region mode a handle grows the crop, not the picture', () => {
  const o = { at: [0, 0], scale: [2, 2], rot: 0, region: [0, 0, 16, 16], repeat: 'tile' }, box = T.txBox(o, 16, 16);
  const r = T.txResize(o, box, 'e', [16 + 64, 0], 'region', false, 16, 16);  // the right edge from x=16 to 80: 32 px of picture more
  assert.deepStrictEqual(r.region, [0, 0, 48, 16]);
  const n = { ...o, ...r }, nb = T.txBox(n, 16, 16);
  assert.ok(near(T.txApply(T.txMatrix(n), nb[0], nb[1]), [-16, -16]));     // the left edge stayed
});

test('a retouch keeps only what differs, tint with alpha, and what the game already has', () => {
  const base = { tex: TOMB, at: [10, 20], scale: [1, 1], rot: 0, flip_h: false, flip_v: false, z: 0, blend: 'mix', region: null, repeat: '', filter: '', hidden: false, tint: '#ffffff', alpha: 1 };
  assert.strictEqual(T.txRetouch(base, { ...base }, null), null);
  assert.deepStrictEqual(T.txRetouch(base, { ...base, at: [11, 20] }, null), { was: TOMB, at: [11, 20] });
  assert.deepStrictEqual(T.txRetouch(base, { ...base, alpha: 0.5 }, null), { was: TOMB, tint: '#ffffff', alpha: 0.5 });
  // the scene already shows the committed move: putting it where it is keeps it, rather than dropping it
  assert.deepStrictEqual(T.txRetouch(base, { ...base }, { was: 'decor/other.png', at: [10, 20] }), { was: 'decor/other.png', at: [10, 20] });
});

test('her texture is written without its defaults', () => {
  assert.deepStrictEqual(T.txTexture({ tex: TOMB, at: [1.234, 2], scale: [1, 1], rot: 0, layer: 'mid', z: 0, tint: '#FFFFFF', alpha: 1, blend: 'mix', region: null, repeat: '', filter: '' }),
    { tex: TOMB, at: [1.23, 2] });
  assert.deepStrictEqual(T.txTexture({ tex: TOMB, at: [0, 0], scale: [2, 1], rot: 15, flip_v: true, layer: 'top', z: -1, tint: '#C8B8FF', alpha: 0.5, blend: 'add', region: [0, 0, 64.4, 8], repeat: 'tile', filter: 'smooth' }),
    { tex: TOMB, at: [0, 0], scale: [2, 1], rot: 15, flip_v: true, layer: 'top', z: -1, tint: '#c8b8ff', alpha: 0.5, blend: 'add', region: [0, 0, 64, 8], repeat: 'tile', filter: 'smooth' });
});
