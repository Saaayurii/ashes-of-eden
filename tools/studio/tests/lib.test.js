// Tests for the studio's pure half (tools/studio/lib.js).
//   node --test tools/studio/tests/
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

globalThis.ImageData = class ImageData {
  constructor(a, w, h) {
    if (typeof a === 'number') { this.width = a; this.height = w; this.data = new Uint8ClampedArray(a * w * 4); }
    else { this.data = a; this.width = w; this.height = h; }
  }
};
const L = require('../lib.js');
const ROOT = path.resolve(__dirname, '../../..');

// --- helpers: a little "sprite" and the way an image model blows it up ---

function sprite(w, h, seed = 7) {
  const pal = [[43, 58, 34], [79, 107, 46], [110, 74, 42], [217, 179, 140], [26, 20, 16], [143, 209, 79]];
  let s = seed; const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647;
  const d = new Uint8ClampedArray(w * h * 4);
  for (let y = 2; y < h; y++) for (let x = 0; x < w; x++) {
    if (Math.abs(x - w / 2) < w / 6 + (y > h / 3 ? (y - h / 3) / 4 : 1) && rnd() > 0.05) {
      const c = pal[Math.floor(rnd() * pal.length)], i = (y * w + x) * 4;
      d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2]; d[i + 3] = 255;
    }
  }
  return { data: d, w, h };
}
// nearest-neighbour upscale by a fractional step onto a flat background, then a
// soft 5-tap blur and noise, like the edges of a generated picture
function blowUp(sp, step, bg = [255, 0, 255], pad = 60, seed = 3) {
  const W = Math.round(sp.w * step) + pad * 2, H = Math.round(sp.h * step) + pad * 2, d = new Uint8ClampedArray(W * H * 4);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const sx = Math.floor((x - pad) / step), sy = Math.floor((y - pad) / step), o = (y * W + x) * 4;
    let c = bg;
    if (sx >= 0 && sy >= 0 && sx < sp.w && sy < sp.h) { const i = (sy * sp.w + sx) * 4; if (sp.data[i + 3]) c = [sp.data[i], sp.data[i + 1], sp.data[i + 2]]; }
    d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; d[o + 3] = 255;
  }
  let s = seed; const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647;
  const out = new Uint8ClampedArray(d);
  for (let y = 1; y < H - 1; y++) for (let x = 1; x < W - 1; x++) {
    const i = (y * W + x) * 4;
    for (let k = 0; k < 3; k++) out[i + k] = (d[i + k] * 4 + d[i + k - 4] + d[i + k + 4] + d[i + k - W * 4] + d[i + k + W * 4]) / 8 + (rnd() - 0.5) * 8;
  }
  return { data: out, w: W, h: H };
}
function cut(img) {  // maskPixels + cropBox, as the page's maskImage/cropMask do with a canvas
  const d = new Uint8ClampedArray(img.data), m = L.maskPixels(d, img.w, img.h, 48, 'auto'), b = L.cropBox(m, img.w, img.h);
  const w = b.x1 - b.x0 + 1, h = b.y1 - b.y0 + 1, data = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) data.set(d.subarray(((y + b.y0) * img.w + b.x0) * 4, ((y + b.y0) * img.w + b.x1 + 1) * 4), y * w * 4);
  return { data, w, h, ox: b.x0, oy: b.y0, cov: b.cnt / (img.w * img.h) };
}
function trimmed(sp) {
  let x0 = sp.w, y0 = sp.h, x1 = -1, y1 = -1;
  for (let y = 0; y < sp.h; y++) for (let x = 0; x < sp.w; x++) if (sp.data[(y * sp.w + x) * 4 + 3]) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  return { x0, y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}
function sameSprite(orig, got) {
  const t = trimmed(orig);
  if (got.w !== t.w || got.h !== t.h) return 0;
  let same = 0;
  for (let y = 0; y < t.h; y++) for (let x = 0; x < t.w; x++) {
    const a = ((y + t.y0) * orig.w + x + t.x0) * 4, b = (y * got.w + x) * 4, g = got.img.data;
    const ao = orig.data[a + 3] > 0, bo = g[b + 3] > 0;
    if (ao === bo && (!ao || [0, 1, 2].every(k => Math.abs(orig.data[a + k] - g[b + k]) < 18))) same++;
  }
  return same / (t.w * t.h);
}

// --- background removal ---

test('a magenta background goes entirely, with its fringe', () => {
  const img = blowUp(sprite(30, 50), 10), d = new Uint8ClampedArray(img.data);
  L.maskPixels(d, img.w, img.h, 48, 'auto');
  let magenta = 0;
  for (let i = 0; i < d.length; i += 4) if (d[i + 3] && d[i] > 150 && d[i + 2] > 150 && d[i + 1] < 90) magenta++;
  assert.equal(magenta, 0);
});

test('a dark character on a near-black background keeps its dark parts', () => {
  // the archer case: background (24,24,24), cloak (23,33,25), outlined in (10,10,10)
  const w = 200, h = 200, d = new Uint8ClampedArray(w * h * 4);
  for (let i = 0; i < w * h; i++) { d.set([24 + (i % 3), 24, 24 + (i % 2), 255], i * 4); }
  let body = 0;
  for (let y = 40; y < 170; y++) for (let x = 70; x < 130; x++) {
    const edge = y === 40 || y === 169 || x === 70 || x === 129;
    d.set(edge ? [10, 10, 10, 255] : [23, 33, 25, 255], (y * w + x) * 4); body++;
  }
  const m = L.maskPixels(d, w, h, 48, 'auto');
  let kept = 0; for (let y = 40; y < 170; y++) for (let x = 70; x < 130; x++) kept += m[y * w + x];
  assert.ok(kept / body > 0.98, `kept ${kept}/${body}`);
});

// --- the pixel grid of a generated picture ---

for (const step of [6.3, 7.5, 9.2, 11, 13.7, 16, 21.3]) {
  test(`grid ${step} px: the sprite comes back pixel for pixel`, () => {
    const sp = sprite(40, 60), c = cut(blowUp(sp, step));
    const p = L.globalGridP([c]), got = L.nativeSprite(c, p, false);
    assert.equal(sameSprite(sp, got), 1, `step ${step} → ${got.grid.toFixed(2)}, ${got.w}×${got.h}`);
  });
}

test('frames of one animation at different scales each find their own grid', () => {
  const sp = sprite(36, 58, 11), big = cut(blowUp(sp, 10.4)), small = cut(blowUp(sp, 5.2));
  const p = L.globalGridP([big, small]);
  const a = L.nativeSprite(big, p, false), b = L.nativeSprite(small, p, false);
  assert.equal(a.h, trimmed(sp).h);
  assert.equal(b.h, trimmed(sp).h);
});

test('a strip whose bow is detached from the body is still four frames', () => {
  const segs = [[0, 100], [150, 200], [380, 480], [530, 580], [760, 860], [910, 960], [1140, 1240], [1290, 1340]];
  assert.deepEqual(L.mergeInnerGaps(segs), [[0, 200], [380, 580], [760, 960], [1140, 1340]]);
  assert.deepEqual(L.mergeInnerGaps([[0, 10], [40, 50], [80, 90]]), [[0, 10], [40, 50], [80, 90]]);
});

// --- downscale and palette ---

test('dominant-colour downscale of 2×2 blocks is exact', () => {
  const sp = sprite(10, 12), up = { data: new Uint8ClampedArray(20 * 24 * 4), w: 20, h: 24 };
  for (let y = 0; y < 24; y++) for (let x = 0; x < 20; x++) up.data.set(sp.data.subarray(((y >> 1) * 10 + (x >> 1)) * 4, ((y >> 1) * 10 + (x >> 1)) * 4 + 4), (y * 20 + x) * 4);
  const s = L.downscale(up, 0.5, 'dominant');
  assert.equal(s.w, 10); assert.equal(s.h, 12);
  for (let i = 0; i < sp.data.length; i += 4) if (sp.data[i + 3]) assert.deepEqual([...s.img.data.subarray(i, i + 3)], [...sp.data.subarray(i, i + 3)]);
});

test('a palette of k colours maps an image of k colours onto itself', () => {
  const cols = [[200, 30, 30], [20, 160, 40], [30, 40, 200]], img = new ImageData(3, 1);
  cols.forEach((c, i) => img.data.set([...c, 255], i * 4));
  const s = { img, w: 3, h: 1 }, pal = L.buildPalette([s], 3);
  L.applyPalette(s, pal);
  cols.forEach((c, i) => assert.deepEqual([...img.data.subarray(i * 4, i * 4 + 3)], c));
});

// --- the files the studio writes into the game ---

test('SpriteFrames .tres: Godot 4 text, durations and ids as the hero file has them', () => {
  const t = L.spriteFramesTres([{ name: 'idle', fps: 5, loop: true, texPath: 'res://assets/sprites/archer_idle.png', texId: 'tex_archer_idle', ids: ['archer_idle_0', 'archer_idle_1'], durations: [1, 2] }], 128, 64);
  assert.match(t, /^\[gd_resource type="SpriteFrames" load_steps=4 format=3\]/);
  assert.match(t, /region = Rect2\(128, 0, 128, 64\)/);
  assert.match(t, /"duration": 2\.0,\n"texture": SubResource\("archer_idle_1"\)/);
  assert.match(t, /"name": &"idle",\n"speed": 5\.0/);
  const hero = fs.readFileSync(path.join(ROOT, 'assets/sprites/elian_frames.tres'), 'utf8');
  assert.match(hero, /"duration": 1\.0,\n"texture": SubResource\(/);  // same layout as the file the game uses
});

test('strings.csv is written back byte for byte, and merged keys fill every locale', () => {
  const t = fs.readFileSync(path.join(ROOT, 'localization/strings.csv'), 'utf8');
  assert.equal(L.csvStringify(L.csvParse(t)), t);
  const m = L.mergeStrings(t, { DLG_STUDIO_TEST: { ru: 'Привет, мир', en: 'Hello, "world"' } });
  const row = L.csvParse(m).find(r => r[0] === 'DLG_STUDIO_TEST'), head = L.csvParse(m)[0];
  assert.equal(row.length, head.length);
  assert.ok(row.slice(1).every(v => v !== ''));
  assert.equal(m.split('\n').length, t.split('\n').length + 1);
});

test('rewriting an unchanged dialogue leaves its file alone', () => {
  const dir = path.join(ROOT, 'data/dialogues');
  let identical = 0, total = 0;
  for (const f of fs.readdirSync(dir)) {
    const x = fs.readFileSync(path.join(dir, f), 'utf8'), j = JSON.parse(x);
    for (const d of (Array.isArray(j) ? j : [j])) {
      total++;
      const y = L.mergeDialogueFile(x, d);
      assert.deepEqual(JSON.parse(y), j, f);  // never changes what it means
      if (y === x) identical++;
    }
  }
  assert.equal(identical, total, `${identical}/${total} byte-identical`);
});

test('an edited node rewrites only its own lines, in its own layout', () => {
  const f = path.join(ROOT, 'data/dialogues/npc_matthew.json'), x = fs.readFileSync(f, 'utf8'), d = JSON.parse(x);  // one-line and expanded nodes side by side
  const oneLine = Object.keys(d.nodes).find(k => new RegExp(`\n {4}${JSON.stringify(k)}: \\{[^\n]*\\},?\n`).test(x));
  d.nodes[oneLine].speaker = 'SPEAKER_ELIAN';
  const y = L.mergeDialogueFile(x, d), a = x.split('\n'), b = y.split('\n');
  assert.deepEqual(JSON.parse(y), d);
  assert.equal(a.length, b.length);
  assert.equal(a.filter((l, i) => l !== b[i]).length, 1);
  d.nodes.added = { speaker: 'SPEAKER_ELIAN', text: 'K' };
  assert.deepEqual(JSON.parse(L.mergeDialogueFile(x, d)), d);
});

test('an edited dialogue in a multi-dialogue file touches only itself', () => {
  const f = path.join(ROOT, 'data/dialogues/ch1_cutscenes.json'), x = fs.readFileSync(f, 'utf8'), list = JSON.parse(x);
  const d = JSON.parse(JSON.stringify(list[1])); d.nodes[d.start].speaker = 'SPEAKER_ELIAN';
  const y = JSON.parse(L.mergeDialogueFile(x, d));
  assert.equal(y.length, list.length);
  assert.deepEqual(y[0], list[0]);
  assert.equal(y[1].nodes[d.start].speaker, 'SPEAKER_ELIAN');
});

test('an image model\'s drifted edit is put back onto its base by the parts meant to stay', () => {
  const w = 320, h = 200, base = { w, h, data: new Uint8ClampedArray(w * h * 4) }, edit = { w, h, data: new Uint8ClampedArray(w * h * 4) };
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * 4, v = 128 + 60 * Math.sin(x * 0.13) + 50 * Math.cos(y * 0.21 + x * 0.02) + ((x * 7 + y * 13) % 17);
    base.data.set([v, v * 0.8, v * 0.6, 255], i);
  }
  // the edit: 5 px right, 3 px up, 2 % bigger, warmer, and its middle repainted
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const sx = Math.round((x - 5 - w / 2) / 1.02 + w / 2), sy = Math.round((y + 3 - h / 2) / 1.02 + h / 2);
    const j = (Math.min(h - 1, Math.max(0, sy)) * w + Math.min(w - 1, Math.max(0, sx))) * 4, i = (y * w + x) * 4;
    edit.data.set(x > 90 && x < 230 ? [40, 90, 40, 255] : [base.data[j] * 1.1 + 12, base.data[j + 1], base.data[j + 2] * 0.9, 255], i);
  }
  const keep = (x, y) => x < 80 || x >= 240;
  const a = L.alignEdit(base, edit, keep);
  assert.deepEqual([a.sc, a.dx, a.dy], [0.98, -5, 3]);
  const fixed = L.matchColours(base, L.warpEdit(edit, a), keep);
  let e = 0, n = 0;
  for (let y = 10; y < h - 10; y++) for (let x = 10; x < 70; x++) { e += Math.abs(fixed.data[(y * w + x) * 4] - base.data[(y * w + x) * 4]); n++; }
  assert.ok(e / n < 5, `the side should match its base, off by ${(e / n).toFixed(1)}`);
});

test('an enemy or a gift is edited in place, written the way Python writes the rest', () => {
  const files = [...fs.readdirSync(path.join(ROOT, 'data/enemies')).map(f => 'data/enemies/' + f), ...fs.readdirSync(path.join(ROOT, 'data/abilities')).map(f => 'data/abilities/' + f)].filter(f => f.endsWith('.json'));
  for (const f of files) {
    const t = fs.readFileSync(path.join(ROOT, f), 'utf8'), d = JSON.parse(t);
    const places = Array.isArray(d) ? [] : [...(d.attacks || []).map((a, i) => [['attacks', i], a]), ...(d.attack ? [[['attack'], d.attack]] : [])];
    for (const [where, a] of places) {
      assert.equal(L.patchJson(t, where, { ...a }), t, f + ': nothing changed, nothing written');
      const u = L.patchJson(t, where, { damage: 33, volley: 2, volley_gap: 0.3, windup: undefined });
      const want = structuredClone(d), at = where.reduce((o, k) => o[k], want);
      Object.assign(at, { damage: 33, volley: 2, volley_gap: 0.3 }); delete at.windup;
      assert.deepEqual(JSON.parse(u), want, f);
      assert.equal(L.patchJson(u, where, { damage: a.damage, volley: undefined, volley_gap: undefined, windup: a.windup }).length > 0, true);
    }
  }
  // a float stays a float, the last two keys can go together, an integer float keeps its ".0"
  const t = '{\n  "a": {\n    "x": 6.0,\n    "y": 1,\n    "z": 2\n  }\n}\n';
  assert.equal(L.patchJson(t, ['a'], { x: 7 }), t.replace('6.0', '7.0'));
  assert.equal(L.patchJson(t, ['a'], { y: undefined, z: undefined }), '{\n  "a": {\n    "x": 6.0\n  }\n}\n');
  assert.equal(L.patchJson(t, ['a'], { w: [1, 2] }), t.replace('"z": 2\n', '"z": 2,\n    "w": [\n      1,\n      2\n    ]\n'));
});

test('a living-backdrop rule rewrites only itself, in the file\'s own style', () => {
  const t = fs.readFileSync(path.join(ROOT, 'data/backdrops.json'), 'utf8');
  const rooms = JSON.parse(t).rooms;
  for (const [key, rule] of Object.entries(rooms)) assert.equal(L.setBackdropRule(t, key, rule), t, key);
  const zones = [{ kind: 'sway', rect: [10, 20, 30, 40], strength: 2, anchor: 'stands' }];
  const u = L.setBackdropRule(t, 'church', { family: 'church', zones });   // "church" is a family too
  assert.deepEqual(JSON.parse(u).rooms.church.zones, zones);
  assert.deepEqual(JSON.parse(u).families, JSON.parse(t).families);
  assert.match(u, /"strength": 2\.0, "anchor": "stands"\}/);
  const at = t.indexOf('\n    "church": {', t.indexOf('"rooms"')), after = t.indexOf('\n    "ashes_threshold": {');
  assert.ok(u.startsWith(t.slice(0, at)) && u.endsWith(t.slice(after)));
  const last = Object.keys(rooms).at(-1), v = L.setBackdropRule(t, last, { family: 'hell', zones: [] });
  assert.deepEqual(JSON.parse(v).rooms[last], { family: 'hell', zones: [] });
  const w = L.setBackdropRule(t, 'studio_new', { family: 'dusk', flame: 0.4, zones });
  assert.deepEqual(JSON.parse(w).rooms.studio_new, { family: 'dusk', flame: 0.4, zones });
});

test('a new cutscene picture gets a still rule; existing rules keep their layout', () => {
  const t = fs.readFileSync(path.join(ROOT, 'data/backdrops.json'), 'utf8');
  const u = L.insertBackdropRules(t, { studio_panel_1: 'dusk', elian_gallows_drop: 'dusk' });
  assert.equal(u.split('\n').length, t.split('\n').length + 1);
  assert.deepEqual(JSON.parse(u).rooms.studio_panel_1, { family: 'dusk', zones: [] });
  assert.equal(L.insertBackdropRules(t, { elian_gallows_drop: 'x' }), t);
});

test('cutscene JSON keeps the one-step-per-line layout of data/cutscenes', () => {
  for (const f of fs.readdirSync(path.join(ROOT, 'data/cutscenes'))) {
    const x = fs.readFileSync(path.join(ROOT, 'data/cutscenes', f), 'utf8'), c = JSON.parse(x);
    assert.equal(L.cutsceneJson(c.id, c.steps), x, f);
  }
});

test('a changed generated sound is written beside it, never over it', () => {
  const gen = new Set(['assets/audio/sfx/bell.wav', 'assets/audio/sfx/knight_hurt_1.wav', 'assets/audio/sfx/knight_hurt_2.wav']);
  const isGen = p => gen.has(p);
  const bell = { cat: 'sfx', name: 'bell', takes: [{ stem: 'bell', ext: 'wav' }] };
  assert.deepEqual(L.planSoundWrite(bell, { stem: 'bell', orig: true }, isGen), { write: 'assets/audio/sfx/bell_1.wav', delete: [], renamed: 'bell_1' });
  const hurt = { cat: 'sfx', name: 'knight_hurt', takes: [{ stem: 'knight_hurt_1', ext: 'wav' }, { stem: 'knight_hurt_2', ext: 'wav' }] };
  assert.deepEqual(L.planSoundWrite(hurt, { stem: 'knight_hurt_2', orig: true }, isGen),
    { write: 'assets/audio/sfx/knight_hurt_3.wav', delete: ['assets/audio/sfx/knight_hurt_2.wav'], renamed: 'knight_hurt_3' });
  const real = { cat: 'sfx', name: 'beam', takes: [{ stem: 'beam', ext: 'ogg' }] };
  assert.deepEqual(L.planSoundWrite(real, { stem: 'beam', orig: true }, isGen), { write: 'assets/audio/sfx/beam.wav', delete: ['assets/audio/sfx/beam.ogg'] });
  const line = { cat: 'voice', locale: 'ru', name: 'DLG_X', takes: [{ stem: 'DLG_X', ext: 'mp3' }] };
  assert.deepEqual(L.planSoundWrite(line, { stem: 'DLG_X', orig: true }, isGen), { write: 'assets/audio/voice/ru/DLG_X.mp3', delete: [] });
});

test('WAV: a 16-bit PCM RIFF header with the right sizes', async () => {
  const n = 441, ch = new Float32Array(n).map((_, i) => Math.sin(i / 7));
  const blob = L.encodeWav({ numberOfChannels: 1, sampleRate: 44100, length: n, getChannelData: () => ch });
  const v = new DataView(await blob.arrayBuffer());
  assert.equal(String.fromCharCode(v.getUint8(0), v.getUint8(1), v.getUint8(2), v.getUint8(3)), 'RIFF');
  assert.equal(v.getUint32(24, true), 44100);
  assert.equal(v.getUint16(34, true), 16);
  assert.equal(v.getUint32(40, true), n * 2);
});

// --- undo and touch-ups ---

test('undo snapshots share big pictures instead of copying them', () => {
  const pic = 'data:image/png;base64,' + 'A'.repeat(100000), table = { ids: new Map(), list: [] };
  const a = L.snapshot({ frames: [{ src: pic }, { src: pic }], name: 'archer' }, table);
  assert.ok(a.length < 200);
  assert.equal(table.list.length, 1);
  assert.deepEqual(L.unsnapshot(a, table), { frames: [{ src: pic }, { src: pic }], name: 'archer' });
});

test('a touch-up patch paints exactly its pixels', () => {
  const d = new Uint8ClampedArray(4 * 4 * 4);
  L.applyPatch(d, 4, 4, { '1,2': [10, 20, 30, 255], '9,9': [1, 1, 1, 255], '0,0': [0, 0, 0, 0] });
  assert.deepEqual([...d.subarray((2 * 4 + 1) * 4, (2 * 4 + 1) * 4 + 4)], [10, 20, 30, 255]);
  assert.equal(d.reduce((a, b) => a + b, 0), 10 + 20 + 30 + 255);
});

// --- her work against the game's copy ---

test('the game copy replaces only what she has not changed', () => {
  const game = { id: 'knight_arrival', kind: 'cutscene', steps: [{ do: 'hold' }], rev: 'a1', updated: 0 };
  assert.equal(L.mergeDecision(null, game), 'take');
  assert.equal(L.mergeDecision({ ...game, dirty: false, base: 'a1' }, { ...game, rev: 'b2' }), 'take');
  const mine = { ...game, steps: [{ do: 'hold' }, { do: 'wait', time: 1 }], dirty: true, base: 'a1' };
  assert.equal(L.mergeDecision(mine, game), 'keep');
  assert.equal(L.mergeDecision(mine, { ...game, rev: 'b2' }), 'conflict');  // someone else changed it meanwhile
  assert.equal(L.mergeDecision({ ...game, dirty: true, base: 'a1', current: 'x' }, { ...game, rev: 'b2' }), 'take');  // only browsed
  assert.equal(L.mergeDecision({ ...mine, pendingPr: 12 }, { ...game, rev: 'b2' }), 'keep');  // sent, not in main yet
});

test('a pull request reads as one plain status', () => {
  assert.equal(L.prStatus({ state: 'open', checks: { total: 2, pending: 1, failed: 0 } }).key, 'checking');
  assert.equal(L.prStatus({ state: 'open', checks: { total: 2, pending: 0, failed: 1 } }).key, 'failed');
  assert.equal(L.prStatus({ state: 'open', checks: { total: 2, pending: 0, failed: 0 } }).key, 'ready');
  assert.equal(L.prStatus({ state: 'closed', merged: true, deployed: false }).key, 'merged');
  assert.equal(L.prStatus({ state: 'closed', merged: true, deployed: true }).key, 'live');
  assert.equal(L.prStatus({ state: 'closed', merged: false }).key, 'closed');
  assert.equal(L.prStatus({ state: 'open', review: 'CHANGES_REQUESTED', checks: { total: 1, pending: 0, failed: 0 } }).key, 'changes');
});

// --- placing an enemy in a room ---

test('a click snaps to the floor below it, as check_reach would find it', () => {
  const surfaces = [[0, 520, 400], [500, 300, 100], [500, 560, 300]];
  assert.deepEqual(L.snapToSurface(surfaces, 100, 400), { x: 100, y: 508 });
  assert.deepEqual(L.snapToSurface(surfaces, 550, 200), { x: 550, y: 288 });  // the ledge, not the ground under it
  assert.deepEqual(L.snapToSurface(surfaces, 550, 400), { x: 550, y: 548 });
  assert.equal(L.snapToSurface(surfaces, 450, 400), null);  // a pit
});

test('studio_rooms.json: one spot per enemy per room, cutscenes per room, stable layout', () => {
  let t = L.mergeStudioRooms('', { room: 'graveyard_cross', spawn: ['archer', 700, 508] });
  t = L.mergeStudioRooms(t, { room: 'church', intro_cutscene: 'my_scene' });
  t = L.mergeStudioRooms(t, { room: 'graveyard_cross', spawn: ['archer', 720, 508] });
  const j = JSON.parse(t);
  assert.deepEqual(j.graveyard_cross.spawns, [['archer', 720, 508]]);
  assert.equal(j.church.intro_cutscene, 'my_scene');
  assert.deepEqual(Object.keys(j), ['church', 'graveyard_cross']);
  assert.match(t, /\["archer", 720, 508\]/);
});

// --- prompts: no exact size, every image named by its role, later frames are edits ---

test('sprite prompts name each attached image by role and never ask for a pixel count', () => {
  const anim = { name: 'walk', notes: '', poses: ['contact', 'passing', '', 'down'] };
  const base = { description: 'a hooded archer', style: 'pixel art', view: 'side view, facing right', anim };
  const first = L.spritePrompt({ ...base, kind: 'frame', index: 0, refs: ['design', 'style'] });
  assert.match(first, /Image 1: the CHARACTER DESIGN/);
  assert.match(first, /Image 2: STYLE AND SCALE ONLY/);
  assert.match(first, /Do NOT draw this knight/);
  assert.match(first, /frame 1 of 4: contact/);
  assert.match(first, /magenta/);
  for (const t of [first, L.spritePrompt({ ...base, kind: 'strip', refs: ['style'] })]) {
    assert.doesNotMatch(t, /exactly \d+ (art )?pixels|\d+×\d+ image pixels|block of exactly/);
    assert.match(t, /Do not aim for any exact pixel count/);
  }
  const edit = L.spritePrompt({ ...base, kind: 'frame', index: 2, refs: ['approved'] });
  assert.match(edit, /^Attached images, in order:\nImage 1: the APPROVED FRAME/);
  assert.match(edit, /Edit Image 1: change ONLY the pose, to frame 3 of 4/);
  assert.match(edit, /next pose of the motion/);
  assert.doesNotMatch(edit, /Create ONE frame/);
  const strip = L.spritePrompt({ ...base, kind: 'strip', refs: ['design', 'style'], transparent: true });
  assert.match(strip, /exactly 4 animation frames/);
  assert.match(strip, /\n3\. next pose of the motion\n/);
  assert.match(strip, /Transparent background/);
  assert.match(L.spritePrompt({ ...base, description: '', kind: 'frame', index: 0, refs: ['design'] }), /Character: the character in Image 1\./);
});

// --- the sandbox: which animation plays a slot, and the post the game reads ---

test('sandbox posts pick an animation per enemy slot and carry the base', () => {
  const anims = [{ id: 'a', name: 'idle' }, { id: 'b', name: 'shoot_bow' }, { id: 'c', name: 'walk' }];
  assert.equal(L.enemySlotFor(anims, 'idle').id, 'a');
  assert.equal(L.enemySlotFor(anims, 'attack').id, 'b');
  assert.equal(L.enemySlotFor(anims, 'death'), null);
  const m = L.liveMessage({ name: 'Лучница', base: '', cell: ['48', 56], fps: '', strips: { idle: 'data:' } });
  assert.deepEqual(m, { type: 'ashes-live', name: 'Лучница', extends: 'cultist', cell: [48, 56], fps: 8, strips: { idle: 'data:' } });
});

// --- checks before sending: size, feet, jumps, palette, key-colour halos ---

function cellFrame(w, h, draw) {
  const d = new Uint8ClampedArray(w * h * 4);
  const put = (x, y, c) => { const i = (y * w + x) * 4; d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2]; d[i + 3] = c[3] ?? 255; };
  draw(put); return { data: d, w, h };
}
// a 44 px figure, its feet on row `foot`, shifted by dx
const figure = (foot = 55, dx = 0, h = 44, extra) => cellFrame(48, 56, put => {
  for (let y = foot - h + 1; y <= foot; y++) for (let x = 20 + dx; x < 28 + dx; x++) put(x, y, (x + y) % 2 ? [60, 80, 50] : [30, 40, 30]);
  if (extra) extra(put);
});

test('a clean character passes, said to be the hero\'s height', () => {
  const r = L.artChecks([{ name: 'idle', loop: true, frames: [figure(), figure(55, 1)] }], { contentH: 44 });
  assert.deepEqual(r.filter(c => c.bad), []);
  assert.match(r.find(c => c.id === 'hero').msg, /как у героя/);
});

test('the checks catch hopping feet, a jump, a wrong height, a big palette and a magenta fringe', () => {
  const feet = L.artChecks([{ name: 'idle', frames: [figure(), figure()] }, { name: 'walk', loop: true, frames: [figure(55), figure(52)] }], { contentH: 44 });
  assert.ok(feet.find(c => c.id === 'feet' && c.bad));
  assert.equal(L.artChecks([{ name: 'idle', frames: [figure(), figure()] }, { name: 'attack', frames: [figure(55), figure(40, 14)] }], { contentH: 44 }).filter(c => c.bad).length, 0, 'an attack may leave the ground and lunge');
  assert.equal(L.artChecks([{ name: 'idle', loop: true, frames: [figure(50), figure(46)] }, { name: 'walk', frames: [figure(50), figure(44)] }], { contentH: 44 }).find(c => c.id === 'feet'), undefined, 'a flyer hovers: no line to hold');
  const jump = L.artChecks([{ name: 'idle', loop: true, frames: [figure(55, 0), figure(55, 14)] }], { contentH: 44 });
  assert.match(jump.find(c => c.id === 'jump').msg, /кадрами 1 и 2/);
  assert.ok(L.artChecks([{ name: 'idle', frames: [figure(55, 0, 30)] }], { contentH: 44 }).find(c => c.id === 'height' && c.bad));
  const many = put => { for (let k = 0; k < 60; k++) put(30 + (k % 10), 20 + (k / 10 | 0), [k * 4, 100, 200 - k]); };
  assert.ok(L.artChecks([{ name: 'idle', frames: [figure(55, 0, 44, many)] }], { contentH: 44, palette: 16 }).find(c => c.id === 'palette' && c.bad), 'more colours than the palette she set');
  assert.equal(L.artChecks([{ name: 'idle', frames: [figure(55, 0, 44, many)] }], { contentH: 44, palette: 0 }).find(c => c.id === 'palette').bad, false, 'no palette set: said, not red');
  const fringe = figure(55, 0, 44, put => put(28, 30, [250, 10, 240])); fringe.key = [255, 0, 255];
  const halo = L.artChecks([{ name: 'idle', frames: [fringe] }], { contentH: 44 });
  assert.ok(halo.find(c => c.id === 'halo' && c.bad));
  const soft = L.artChecks([{ name: 'idle', frames: [figure(55, 0, 44, put => put(28, 31, [60, 80, 50, 120]))] }], { contentH: 44 });
  assert.ok(soft.find(c => c.id === 'soft' && c.bad));
  const boss = L.artChecks([{ name: 'idle', frames: [figure(55, 0, 52)] }, { name: 'attack', frames: [figure(55, 0, 54)] }], { contentH: 52 });
  assert.deepEqual(boss.filter(c => c.bad), [], 'the height is the idle\'s: a raised blade in an attack is not the body');
  assert.deepEqual(L.artChecks([{ name: 'idle', frames: [figure(55, 0, 30)] }], { contentH: 44, fit: false }).filter(c => c.bad), [], 'a game sprite taken as it is: its height is the game\'s');
  assert.equal(L.artChecks([{ name: 'idle', frames: [figure(), figure()] }, { name: 'walk', frames: [figure(55), figure(49)] }], { contentH: 44, flyer: true }).find(c => c.id === 'feet'), undefined, 'a flyer');
  const brute = L.artChecks([{ name: 'idle', frames: [figure(55, 0, 52)] }], { contentH: 52 });
  assert.deepEqual(brute.filter(c => c.bad), [], 'bigger than the hero on purpose is information, not an error');
  assert.match(brute.find(c => c.id === 'hero').msg, /выше героя/);
});

test('the fringe is the source\'s own background colour: a purple ghost on a transparent source is not one', () => {
  const ghost = figure(55, 0, 44, put => { for (let y = 20; y < 50; y++) put(28, y, [200, 40, 220]); });
  assert.equal(L.artChecks([{ name: 'idle', frames: [ghost] }], { contentH: 44 }).find(x => x.id === 'halo'), undefined, 'no key: nothing to look for');
  const cloak = figure(55, 0, 44, put => { for (let y = 20; y < 50; y++) put(28, y, [63, 107, 46]); }); cloak.key = [255, 0, 255];
  assert.equal(L.artChecks([{ name: 'idle', frames: [cloak] }], { contentH: 44 }).find(x => x.id === 'halo'), undefined, 'a green cloak on magenta');
  const screen = figure(55, 0, 44, put => put(28, 30, [40, 200, 60])); screen.key = [0, 255, 0];
  assert.ok(L.artChecks([{ name: 'idle', frames: [screen] }], { contentH: 44 }).find(x => x.id === 'halo'), 'green-screen fringe on a green key');
  const tint = figure(55, 0, 44, put => put(28, 30, [120, 20, 110])); tint.key = [255, 0, 255];
  assert.ok(L.artChecks([{ name: 'idle', frames: [tint] }], { contentH: 44 }).find(x => x.id === 'halo'), 'the key blended into a dark outline');
});

// --- editing what a generator draws: only what she changed, written beside it ---

test('frameEdits keeps untouched frames out and finds a replaced frame and a touch-up', () => {
  const orig = [{ id: 'cultist_idle', frames: [0, 1, 2].map(i => ({ id: `cultist_idle_${i}`, src: `s${i}`, dx: 0, dy: 0, sc: 1 })),
    regions: [0, 1, 2].map(i => ['res://assets/sprites/cultist_v2_idle.png', i * 32, 0, 32, 40]) }];
  const mine = [{ id: 'cultist_idle', name: 'idle', frames: [
    { id: 'cultist_idle_0', src: 's0', dx: 0, dy: 0, sc: 1 },
    { id: 'cultist_idle_1', src: 's1', dx: 0, dy: 0, sc: 1, patch: { '3,4': [1, 2, 3, 255], '40,4': [0, 0, 0, 0] } },
    { id: 'cultist_idle_2', src: 'new', dx: 0, dy: 0, sc: 1 }] }];
  const e = L.frameEdits(mine, orig);
  assert.equal(e.length, 2, 'the untouched frame is not an edit');
  assert.deepEqual(e[0], { res: 'res://assets/sprites/cultist_v2_idle.png', x: 32, y: 0, w: 32, h: 40, frame: 'cultist_idle_1', whole: false, pixels: [[3, 4]] }, 'a touch-up is its pixels, inside the cell');
  assert.equal(e[1].whole, true); assert.equal(e[1].x, 64);
  mine[0].frames.push({ id: 'x', src: 'y' });
  assert.throws(() => L.frameEdits(mine, orig), /не удлинять/);
  assert.throws(() => L.frameEdits([{ id: 'cultist_fly', name: 'fly', frames: [] }], orig), /новым персонажем/);
});

test('an override is her picture, its mask and a manifest line the Python side reads', () => {
  assert.deepEqual(L.overrideFiles('assets/levels/graveyard_cross_wide.png'),
    { edit: 'tools/studio/overrides/assets/levels/graveyard_cross_wide.png', mask: 'tools/studio/overrides/assets/levels/graveyard_cross_wide.mask.png' });
  const a = new Uint8ClampedArray([0, 0, 0, 255, 10, 10, 10, 255, 5, 5, 5, 0]), b = new Uint8ClampedArray([0, 0, 0, 255, 30, 10, 10, 255, 9, 5, 5, 0]);
  assert.deepEqual([...L.diffMask(a, b, 3, 1)], [0, 1, 0]);
  const was = '{\n  "assets/props/altar_book.png": {\n    "size": [\n      128,\n      32\n    ],\n    "base": "abc",\n    "stale": true,\n    "by": "x",\n    "at": "2026-10-01"\n  }\n}\n';
  const out = JSON.parse(L.mergeOverrides(was, { 'assets/props/altar_book.png': { size: [128, 32], by: 'her', at: '2026-10-07' }, 'assets/levels/a.png': { size: [1, 1], by: 'her', at: '2026-10-07' } }));
  assert.deepEqual(Object.keys(out), ['assets/levels/a.png', 'assets/props/altar_book.png']);
  assert.equal(out['assets/props/altar_book.png'].stale, undefined, 'drawn again: no longer stale');
  assert.equal(out['assets/props/altar_book.png'].base, null, 'and the generator records the picture she drew on now');
  const kept = JSON.parse(L.mergeOverrides(was.replace('"stale": true,\n    ', ''), { 'assets/props/altar_book.png': { size: [128, 32], by: 'her', at: '2026-10-08' } }));
  assert.equal(kept['assets/props/altar_book.png'].base, 'abc', 'not stale: the base she first drew on is kept');
  assert.equal(out['assets/levels/a.png'].base, null, 'the generator records a new one');
});

// --- one send, one pull request ---

test('the same files sent twice have the same fingerprint, whatever the project file says', async () => {
  const e = s => new TextEncoder().encode(s);
  const a = await L.filesFingerprint([['assets/sprites/x.png', e('pixels')], ['tools/studio/projects/chars/x.json', e('{"updated":1}')]]);
  const b = await L.filesFingerprint([['tools/studio/projects/chars/x.json', e('{"updated":2}')], ['assets/sprites/x.png', e('pixels')]]);
  const c = await L.filesFingerprint([['assets/sprites/x.png', e('other pixels')]]);
  assert.equal(a, b, 'order and the project file do not matter');
  assert.notEqual(a, c, 'different pixels are a different send');
  assert.match(L.fingerprintMark(a), /^<!-- studio-files:[0-9a-f]{24} -->$/);
});
