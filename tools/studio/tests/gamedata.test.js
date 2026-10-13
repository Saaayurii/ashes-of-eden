// js/gamedata.js against the real files: what it writes back is what the game (or its generator) would write,
// and its checks agree with scripts/tools/validate_data.gd on today's data.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const lib = require('../lib.js');
Object.assign(global, lib, { sameDraft: (a, b) => JSON.stringify(a) === JSON.stringify(b) });
const G = require('../js/gamedata.js');

const ROOT = path.join(__dirname, '..', '..', '..');
const read = p => fs.readFileSync(path.join(ROOT, p), 'utf8');
const TABLES = ['data/omens/chapter_1.json', 'data/achievements/chapter_1.json', 'data/items/relics.json', 'data/skins/free.json',
  'data/rest_points/chapter1.json', 'data/ambience.json', 'tools/rooms/studio_rooms.json', 'data/vials/wrath.json',
  'data/affixes/chapter_1.json', 'data/resonances/chapter_1.json', 'data/relics/reliquary.json'];

test('an unchanged table is written back byte for byte', () => {
  for (const p of TABLES) { const t = read(p); assert.strictEqual(G.gdText(t, JSON.parse(t)), t, p); }
});

test('one entry changed changes that entry only, in the file\'s own style', () => {
  for (const p of ['data/omens/chapter_1.json', 'data/items/relics.json']) {
    const t = read(p), v = JSON.parse(t); v[1].id += '_x';
    const out = G.gdText(t, v), was = JSON.parse(t);
    assert.deepStrictEqual(JSON.parse(out), v);
    // every other entry is the very text it was
    for (const e of was.filter((e, i) => i !== 1)) assert.ok(out.includes(JSON.stringify(e.id)), p);
    assert.strictEqual(out.split('\n')[0], '[');
  }
  const t = read('data/ambience.json'), v = JSON.parse(t); v.rules[0].effects = ['clouds'];
  const out = G.gdText(t, v);
  assert.ok(out.startsWith(t.slice(0, t.indexOf('"rules"'))), 'the comment above stays as it was');
  assert.deepStrictEqual(JSON.parse(out), v);
});

test('the music manifest and the playlists come out as fetch_music.py writes them', () => {
  const mt = read('tools/audio/music_manifest.json'), manifest = JSON.parse(mt);
  assert.strictEqual(G.gdPyDump(manifest, 1) + (mt.endsWith('\n') ? '\n' : ''), mt);
  const pt = read('data/music/playlists.json'), src = read('tools/audio/fetch_music.py');
  // EXISTING, the hand-made moods, as build_data.py reads them: a Python literal of lists of strings
  const lit = src.slice(src.indexOf('EXISTING'), src.indexOf('}', src.indexOf('EXISTING')) + 1);
  const existing = JSON.parse(lit.slice(lit.indexOf('{')).replace(/'/g, '"').replace(/,(\s*[}\]])/g, '$1'));
  const out = G.gdPyDump({ _comment: JSON.parse(pt)._comment, playlists: G.gdPlaylists(existing, manifest.tracks) }, 2) + (pt.endsWith('\n') ? '\n' : '');
  assert.strictEqual(out, pt);
});

test('the skin shader: the red cloak takes the new hue, the rest takes the armour tint', () => {
  const skin = { cloak: { hue: 0.62, saturation: 0.6, value: 0.85 }, armor: '#dfe6f2' };
  const [r, g, b] = G.gdSkinPixel([0.6, 0.1, 0.1], skin);
  assert.ok(b > r && b > g, 'a cloak red goes blue');
  const grey = G.gdSkinPixel([0.5, 0.5, 0.5], skin);
  assert.ok(Math.abs(grey[0] - 0.5 * 0xdf / 255) < 1e-6 && Math.abs(grey[2] - 0.5 * 0xf2 / 255) < 1e-6, 'grey is only tinted');
  assert.deepStrictEqual(G.gdSkinPixel([0.6, 0.1, 0.1], {}).map(v => +v.toFixed(6)), [0.6, 0.1, 0.1], 'no skin, no change');
});

function world() {
  const files = {};
  const walk = dir => { for (const f of fs.readdirSync(path.join(ROOT, dir))) { const p = dir + '/' + f;
    if (fs.statSync(path.join(ROOT, p)).isDirectory()) walk(p); else if (f.endsWith('.json')) files[p] = JSON.parse(read(p)); } };
  walk('data');
  return files;
}
const gdConst = name => { const src = read('scripts/tools/validate_data.gd'), m = src.match(new RegExp(`const ${name}\\s*:?=\\s*\\[([^\\]]*)\\]`)); return [...(m ? m[1] : '').matchAll(/"([^"]+)"/g)].map(x => x[1]); };

test('today\'s data passes the browser\'s copy of the validator, and bad entries do not', () => {
  const files = world(), all = dir => Object.keys(files).filter(p => p.startsWith(dir)).flatMap(p => [].concat(files[p]));
  const enemies = Object.fromEntries(all('data/enemies/').map(e => [e.id, !!e.boss]));
  const strings = new Set(lib.csvParse(read('localization/strings.csv')).map(r => r[0]));
  const counters = [...read('scripts/meta/achievements.gd').match(/const COUNTERS\s*:?=\s*\[([^\]]*)\]/)[1].matchAll(/"([^"]+)"/g)].map(x => x[1]);
  const ctx = { stats: gdConst('STATS'), item_stats: gdConst('ITEM_STATS'), techniques: gdConst('TECHNIQUES'), counters, enemies,
    gifts: Object.fromEntries(all('data/abilities/').map(g => [g.id, g.path])), relics: all('data/relics/').map(r => r.id), strings: k => strings.has(k) };
  for (const kind of ['items', 'relics', 'resonances', 'omens', 'vials', 'affixes', 'achievements', 'skins']) {
    const rows = all(`data/${kind}/`);
    assert.ok(rows.length, kind);
    for (const e of rows) assert.deepStrictEqual(G.gdProblems(kind, e, { ...ctx, tiers: rows.filter(x => x !== e).map(x => x.tier) }), [], `${kind}/${e.id}`);
  }
  const omen = all('data/omens/')[0];
  assert.ok(G.gdProblems('omens', { ...omen, rules: { enemy_damage: 1.2 } }, ctx).length, 'an omen that only hurts');
  assert.ok(G.gdProblems('affixes', { id: 'x', name: 'AFFIX_IRONCLAD', color: '#fff', mods: { hp: 3 } }, ctx).length, 'an affix past ×2');
  assert.ok(G.gdProblems('achievements', { id: 'x y', name: 'DEED_FIRST_NIGHT', description: 'DEED_FIRST_NIGHT_DESC', unlock: {} }, ctx).length >= 2, 'a deed with a bad id and no condition');
  assert.ok(G.gdProblems('skins', { id: 'x', name: 'NOPE', description: 'NOPE', unlock: { wins: 1 }, sku: 'itch:1' }, ctx).length >= 3, 'a skin with unknown keys');
});

test('every flag is both set and read, as the validator finds them', () => {
  const src = read('scripts/tools/validate_data.gd');
  const flags = G.gdFlags(world(), { read: gdConst('FLAGS_READ_IN_CODE'), set: gdConst('FLAGS_SET_IN_CODE'), tests: gdConst('FLAGS_FOR_TESTS') });
  assert.ok(Object.keys(flags).length > 10 && src.includes('FLAGS_READ_IN_CODE'));
  assert.deepStrictEqual(Object.entries(flags).filter(([, f]) => !f.set.length).map(([k]) => k), [], 'read but never set');
});
