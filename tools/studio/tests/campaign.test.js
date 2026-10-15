// js/campaign.js against the real files: weapons, endings and the nights' route are written back in the
// files' own shape, and its checks agree with scripts/tools/validate_data.gd and scripts/run/endings.gd.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const lib = require('../lib.js');
Object.assign(global, lib, { sameDraft: (a, b) => JSON.stringify(a) === JSON.stringify(b) });
const G = require('../js/gamedata.js');
const C = require('../js/campaign.js');

const ROOT = path.join(__dirname, '..', '..', '..');
const read = p => fs.readFileSync(path.join(ROOT, p), 'utf8');
const dir = d => fs.readdirSync(path.join(ROOT, d)).filter(f => f.endsWith('.json')).sort().map(f => `${d}/${f}`);
const FILES = [...dir('data/weapons'), ...dir('data/endings'), 'data/game.json'];
const validator = read('scripts/tools/validate_data.gd');
const gdList = name => [...(validator.match(new RegExp(`const ${name}\\s*:?=\\s*\\[([^\\]]*)\\]`)) || ['', ''])[1].matchAll(/"([^"]+)"/g)].map(x => x[1]);
const gdBounds = name => Object.fromEntries([...validator.match(new RegExp(`const ${name}\\s*:?=\\s*\\{([^}]*)\\}`))[1].matchAll(/"(\w+)": \[(-?[\d.]+), (-?[\d.]+)\]/g)].map(m => [m[1], [+m[2], +m[3]]]));
const strings = new Set(lib.csvParse(read('localization/strings.csv')).map(r => r[0]));
const ids = d => dir(d).map(p => JSON.parse(read(p)).id);

test('an untouched file is written back byte for byte, and its shape is the file\'s own', () => {
  for (const p of FILES) {
    const t = read(p), v = JSON.parse(t);
    assert.strictEqual(C.gdShaped(t, v), t, p);
    assert.strictEqual(C.gdShaped(t, v, { force: true }), t, `${p}: rewritten whole, it keeps its shape`);
  }
});

test('one change changes that part only, in the shape it had', () => {
  const t = read('data/weapons/daggers.json'), w = JSON.parse(t);
  w.chain[1].multiplier = 0.6; w.chain[2].multiplier = 1;   // 0.6 was a float, so 1 stays "1.0"
  const out = C.gdShaped(t, w), lines = out.split('\n'), was = t.split('\n');
  assert.deepStrictEqual(JSON.parse(out), w);
  assert.strictEqual(lines.length, was.length);
  assert.deepStrictEqual(lines.map((l, i) => l === was[i] ? '' : i).filter(Boolean).length, 2, 'two steps, two lines');
  assert.ok(out.includes('{"animation": "thrust", "multiplier": 1.0,'), 'a float keeps its ".0"');
  // a new key goes in last, in the shape of its kind: techniques one move a line
  w.techniques = { lunge: { multiplier: 1.4 } };
  assert.ok(C.gdShaped(t, w).endsWith('",\n  "techniques": {\n    "lunge": {"multiplier": 1.4}\n  }\n}\n'));

  const g = read('data/game.json'), game = JSON.parse(g);
  [game.rooms[1], game.rooms[2]] = [game.rooms[2], game.rooms[1]];
  game.nights.push({ id: 'third', after_dawns: 2, opening: { wake: false }, rooms: [game.rooms.pop()] });
  const gout = C.gdShaped(g, game);
  assert.deepStrictEqual(JSON.parse(gout), game);
  assert.ok(gout.startsWith(g.slice(0, g.indexOf('"rooms"'))), 'what is above stays');
  assert.ok(gout.includes('    {\n      "id": "third",\n      "after_dawns": 2,\n      "opening": {"wake": false},\n      "rooms": [\n        "res://scenes/rooms/hell_gate.tscn"\n      ]\n    }'), 'a new night is shaped like Seir');
  assert.ok(gout.endsWith(g.slice(g.indexOf('  "practice_room"'))), 'what is below stays');
});

test('a new file takes the shape of another of its kind', () => {
  const like = read('data/endings/heaven.json'), e = { id: 'x', name: 'ENDING_X', description: 'ENDING_X_DESC', line: 'ENDING_X_LINE', cutscene: 'ending_heaven', order: 5, when: { balanced: 0, unless: ['a'] } };
  assert.strictEqual(C.gdShaped('', e, { like }), '{\n  "id": "x",\n  "name": "ENDING_X",\n  "description": "ENDING_X_DESC",\n  "line": "ENDING_X_LINE",\n  "cutscene": "ending_heaven",\n  "order": 5,\n  "when": {"balanced": 0, "unless": ["a"]}\n}\n');
  const w = JSON.parse(read('data/weapons/spear.json')); w.id = 'pike';
  const out = C.gdShaped('', w, { like: read('data/weapons/daggers.json') });
  assert.deepStrictEqual(JSON.parse(out), w);
  assert.ok(out.includes('  "chain": [\n    {"animation": "thrust", "multiplier": 1.0, "recovery": 0.6,'));
});

const weaponCtx = { weapon: { bounds: gdBounds('WEAPON_BOUNDS'), step_bounds: gdBounds('WEAPON_STEP_BOUNDS'), needs: gdList('WEAPON_STEP_NEEDS'), animations: gdList('WEAPON_ANIMATIONS'), arcs: gdList('WEAPON_ARCS') },
  icons: r => fs.existsSync(path.join(ROOT, r.replace('res://', ''))), strings: k => strings.has(k) };

test('today\'s weapons pass the browser\'s _check_weapon, and bad ones do not', () => {
  assert.ok(Object.keys(weaponCtx.weapon.step_bounds).length >= 7 && weaponCtx.weapon.animations.includes('thrust'));
  for (const p of dir('data/weapons')) assert.deepStrictEqual(C.cpWeaponProblems(JSON.parse(read(p)), weaponCtx), [], p);
  const spear = JSON.parse(read('data/weapons/spear.json')), bad = s => C.cpWeaponProblems(Object.assign(structuredClone(spear), s), weaponCtx);
  assert.ok(bad({ chain: [] }).length, 'an empty chain');
  assert.ok(bad({ chain: [{ animation: 'attack' }] }).length, 'only the sword falls back on the hero');
  assert.ok(bad({ hitbox: [120, 20] }).length, 'a hitbox past 96');
  assert.ok(bad({ offset: [10, -50] }).length, 'an offset far above him');
  assert.ok(bad({ poise: 0.9 }).length, 'poise past 0.5');
  assert.ok(bad({ techniques: { parry: {} } }).length, 'a technique that is not lunge, cleave or sweep');
  assert.ok(bad({ techniques: { lunge: { colour: 1 } } }).length, 'an unknown key in a technique');
  assert.ok(bad({ chain: [{ ...spear.chain[0], arc: 'blue' }] }).length, 'an arc it has not got');
  assert.ok(bad({ icon: 'res://nope.png' }).length, 'an icon that is not there');
  assert.deepStrictEqual(C.cpWeaponProblems({ ...JSON.parse(read('data/weapons/sword.json')) }, weaponCtx), []);
});

test('the chain\'s numbers are weapon_test\'s', () => {
  const hero = { ...JSON.parse(read('data/hero.json')).feel, attack_cooldown: JSON.parse(read('data/hero.json')).stats.attack_cooldown };
  const sword = C.cpChainNumbers(JSON.parse(read('data/weapons/sword.json')), hero);
  assert.ok(Math.abs(sword.time - hero.attack_cooldown * hero.combo_recovery.reduce((a, b) => a + b)) < 1e-9);
  assert.ok(Math.abs(sword.damage - hero.combo_multipliers.reduce((a, b) => a + b)) < 1e-9);
});

const endingCtx = { cutscenes: ids('data/cutscenes'), strings: k => strings.has(k) };
const endings = dir('data/endings').map(p => JSON.parse(read(p)));

test('today\'s endings pass the browser\'s _check_ending and _check_finale, and bad ones do not', () => {
  for (const e of endings) assert.deepStrictEqual(C.cpEndingProblems(e, endingCtx), [], e.id);
  const game = JSON.parse(read('data/game.json'));
  assert.deepStrictEqual(C.cpEndingsProblems(endings, game, endingCtx), []);
  const heaven = endings.find(e => e.id === 'heaven'), bad = s => C.cpEndingProblems({ ...heaven, ...s }, endingCtx);
  assert.ok(bad({ when: {} }).length, 'an empty when');
  assert.ok(bad({ when: { lead: 2 } }).length, 'a lead with no path');
  assert.ok(bad({ when: { path: 'will', balanced: 1 } }).length, 'balanced and a path');
  assert.ok(bad({ when: { path: 'love' } }).length, 'a fourth path');
  assert.ok(bad({ cutscene: 'nope' }).length, 'a cutscene the game has not got');
  assert.ok(bad({ line: 'NO_SUCH_KEY' }).length, 'a line with no string');
  assert.ok(C.cpEndingsProblems(endings.map(e => ({ ...e, fallback: true })), game, endingCtx).length, 'four fallbacks');
  assert.ok(C.cpEndingsProblems(endings, { ...game, finale: { ...game.finale, room: game.nights[0].rooms[0] } }, endingCtx).length, 'a finale in another night');
});

test('the chooser picks as Endings.choose does', () => {
  const pick = (a, f = []) => C.cpChoose(endings, { grace: 0, temptation: 0, will: 0, ...a }, new Set(f));
  assert.strictEqual(pick({ grace: 4 }), 'heaven');
  assert.strictEqual(pick({ temptation: 3, grace: 1 }), 'abyss');
  assert.strictEqual(pick({ grace: 2, temptation: 1 }), 'man', 'a lead of 1 earns none: the fallback');
  assert.strictEqual(pick({ grace: 1, will: 1 }, ['version_heaven', 'version_abyss', 'version_man', 'book_read']), 'fourth');
  assert.strictEqual(pick({ grace: 1, will: 1 }, ['version_heaven', 'version_abyss', 'version_man']), 'man', 'the book not read');
  assert.strictEqual(C.cpLead({ grace: 3, temptation: 1, will: 2 }), 1);
  assert.strictEqual(C.cpDominant({ grace: 1, temptation: 1, will: 1 }), 'will', 'a tie goes to will');
});

test('the ending flags are on the story map both ways', () => {
  const files = {};
  const walk = d => { for (const f of fs.readdirSync(path.join(ROOT, d))) { const p = d + '/' + f;
    if (fs.statSync(path.join(ROOT, p)).isDirectory()) walk(p); else if (f.endsWith('.json')) files[p] = JSON.parse(read(p)); } };
  walk('data');
  const flags = G.gdFlags(files, { read: files['data/game.json'].flags_read, set: gdList('FLAGS_SET_IN_CODE'), tests: gdList('FLAGS_FOR_TESTS') });
  for (const f of ['version_heaven', 'version_abyss', 'version_man', 'book_read']) {
    assert.ok(flags[f].read.some(w => w.startsWith('endings/fourth')), `${f} is read by the fourth ending`);
    assert.ok(flags[f].set.length, `${f} is set somewhere`);
  }
});

const routeCtx = () => ({ scenes: r => fs.existsSync(path.join(ROOT, r.replace('res://', ''))), forks: dir('data/forks').flatMap(p => [].concat(JSON.parse(read(p)))),
  cutscenes: ids('data/cutscenes'), dialogues: dir('data/dialogues').flatMap(p => [].concat(JSON.parse(read(p)))).map(d => d.id) });

test('today\'s route passes the browser\'s _check_game and _check_nights, and a bad one does not', () => {
  const game = JSON.parse(read('data/game.json')), ctx = routeCtx();
  assert.deepStrictEqual(C.cpRouteProblems(game, ctx), []);
  assert.deepStrictEqual(C.cpRouteWarnings(game, ctx.forks), []);
  const owner = C.cpOwner(game);
  assert.strictEqual(owner['res://scenes/rooms/village_night.tscn'], '');
  assert.strictEqual(owner['res://scenes/rooms/seir_quay.tscn'], 'seir');
  assert.strictEqual(C.cpNights(game).length, 1 + game.nights.length);
  const bad = fn => { const g = structuredClone(game); fn(g); return C.cpRouteProblems(g, ctx); };
  assert.ok(bad(g => g.nights[0].rooms.push(g.rooms[0])).length, 'a room in two nights');
  assert.ok(bad(g => { g.nights[0].after_dawns = 0; }).length, 'a later night open from the start');
  assert.ok(bad(g => g.nights.push({ id: 'seir', after_dawns: 2, rooms: ['res://scenes/rooms/practice_yard.tscn'] })).length, 'a night twice, and the yard in a night');
  assert.ok(bad(g => { g.nights[0].opening.intro = 'nope'; }).length, 'an opening that names nothing');
  // a fork's way moved to Seir: the fork leaves its night
  const fork = ctx.forks[0], way = Object.values(fork.options)[0];
  assert.ok(bad(g => { g.rooms = g.rooms.filter(r => r !== way); g.nights[0].rooms.push(way); }).some(p => p.includes(fork.id)));
  const g = structuredClone(game), at = g.rooms.indexOf(fork.after); g.rooms.splice(at, 1); g.rooms.push(fork.after);
  assert.ok(C.cpRouteWarnings(g, ctx.forks).length, 'a fork whose door comes after its ways');
});
