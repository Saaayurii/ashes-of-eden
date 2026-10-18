// The cutscene tab's checks (lib.js cutProblems) against the real game: every scene the
// validator accepts passes here too, and the mistakes she can make are caught before sending.
// Its picture import (lossyImport) is what tools/export/check_lossy.py asks for.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const L = require('../lib.js');
Object.assign(global, L, { sameDraft: (a, b) => JSON.stringify(a) === JSON.stringify(b) });
const G = require('../js/gamedata.js');

const ROOT = path.join(__dirname, '..', '..', '..');
const read = p => fs.readFileSync(path.join(ROOT, p), 'utf8');
function world() {
  const files = {};
  const walk = dir => { for (const f of fs.readdirSync(path.join(ROOT, dir))) { const p = dir + '/' + f;
    if (fs.statSync(path.join(ROOT, p)).isDirectory()) walk(p); else if (f.endsWith('.json')) files[p] = JSON.parse(read(p)); } };
  walk('data');
  return files;
}
const gdConst = name => { const m = read('scripts/tools/validate_data.gd').match(new RegExp(`const ${name}\\s*:?=\\s*\\[([^\\]]*)\\]`)); return [...(m ? m[1] : '').matchAll(/"([^"]+)"/g)].map(x => x[1]); };

function context(files = world()) {
  const all = dir => Object.keys(files).filter(p => p.startsWith(dir)).flatMap(p => [].concat(files[p]));
  const dialogues = Object.fromEntries(all('data/dialogues/').map(d => [d.id, d]));
  const rows = L.csvParse(read('localization/strings.csv')), head = rows[0], ru = head.indexOf('ru'), en = head.indexOf('en');
  const text = new Set(rows.slice(1).filter(r => r[ru] || r[en]).map(r => r[0]));
  const flags = G.gdFlags(files, { read: JSON.parse(read('data/game.json')).flags_read, set: gdConst('FLAGS_SET_IN_CODE'), tests: gdConst('FLAGS_FOR_TESTS'), awaited: gdConst('FLAGS_AWAITED') });
  return { dialogue: id => dialogues[id] || null, key: k => text.has(k), npcs: new Set(all('data/npcs/').map(n => n.id)), flags,
    image: res => fs.existsSync(path.join(ROOT, res.replace('res://', ''))) };
}

test('every cutscene of the game passes the studio\'s checks', () => {
  const ctx = context(), scenes = fs.readdirSync(path.join(ROOT, 'data/cutscenes'));
  assert.ok(scenes.length > 10);
  for (const f of scenes) assert.deepEqual(L.cutProblems(JSON.parse(read('data/cutscenes/' + f)).steps, ctx).err, [], f);
});

test('the step kinds are the validator\'s', () => {
  const src = read('scripts/tools/validate_data.gd'), block = src.slice(src.indexOf('const CUTSCENE_STEPS'), src.indexOf('}', src.indexOf('const CUTSCENE_STEPS')));
  const steps = Object.fromEntries([...block.matchAll(/"(\w+)": \[([^\]]*)\]/g)].map(m => [m[1], [...m[2].matchAll(/"(\w+)"/g)].map(x => x[1])]));
  assert.deepEqual(L.CUTSCENE_NEEDS, steps);
});

test('her mistakes are caught before she sends them', () => {
  const ctx = context(), errs = steps => L.cutProblems(steps, ctx).err;
  assert.deepEqual(errs([{ do: 'hold' }, { do: 'wait', time: 1 }, { do: 'release' }]), []);
  assert.ok(errs([{ do: 'hold' }, { do: 'wait', time: 1 }]).some(m => m.includes('не возвращено')), 'a hold without a release');
  assert.ok(errs([{ do: 'dialogue', id: 'no_such_dialogue' }]).some(m => m.includes('нет диалога')));
  assert.ok(errs([{ do: 'move', who: 'player' }]).some(m => m.includes('куда')));
  assert.ok(errs([{ do: 'walk', who: 'npc:nobody_at_all', by: [10, 0] }]).some(m => m.includes('nobody_at_all')));
  assert.ok(errs([{ do: 'title' }]).length, 'a title with no name');
  assert.ok(errs([{ do: 'panel', image: 'res://assets/cutscenes/nope.png' }]).some(m => m.includes('nope.png')));
  assert.ok(errs([{ do: 'wait', time: 1, if: 'a_flag_nobody_sets' }]).some(m => m.includes('a_flag_nobody_sets')), 'a branch that can never play');

  // a scene's own dialogue: an answer that sets a flag a later step waits for
  const d = { id: 'zz_dlg', start: 'l1', nodes: { l1: { speaker: 'SPEAKER_ELIAN', text: 'DLG_CONTINUE', choices: [
    { id: 'answer1', text: 'DLG_SKIP' }, { id: 'answer2', text: 'DLG_SKIP', next: 'gone', effect: { set_flags: ['zz_chose'] } }] } } };
  const files = world(); files['data/dialogues/~studio.json'] = [d];
  const scene = [{ do: 'dialogue', id: 'zz_dlg', wait: false }, { do: 'wait', time: 1, if: 'zz_chose' }];
  files['data/cutscenes/zz.json'] = { id: 'zz', steps: scene };
  const own = { ...context(files), dialogue: id => id === 'zz_dlg' ? d : ctx.dialogue(id) }, r = L.cutProblems(scene, own);
  assert.ok(r.err.some(m => m.includes('«gone»')), 'an answer that leads nowhere');
  assert.ok(!r.err.some(m => m.includes('zz_chose')), 'the answer sets the flag the step reads');
  assert.ok(r.warn.some(m => m.includes('пропустит')), 'a skip leaves the flag unset');
  assert.ok(r.warn.some(m => m.includes('Ждать конца')), 'a panel dialogue is waited for whatever «wait» says');
  d.blocking = false;
  assert.ok(L.cutProblems(scene, own).err.some(m => m.includes('субтитрах')), 'no answers in captions');
});

test('a picture she uploads comes with the import check_lossy wants', () => {
  const t = L.lossyImport('res://assets/cutscenes/zz_1.png'), lines = t.split('\n');
  assert.ok(lines.includes('compress/mode=1'));
  assert.ok(lines.includes('source_file="res://assets/cutscenes/zz_1.png"'));
  assert.ok(read('.gitignore').split('\n').includes('!assets/cutscenes/*.png.import'), 'the cutscene pictures are under a lossy glob');
  // every param the game's own imports carry, so Godot's first import changes nothing but the uid and path
  const theirs = read('assets/cutscenes/' + fs.readdirSync(path.join(ROOT, 'assets/cutscenes')).find(f => f.endsWith('.png.import')));
  const params = s => s.slice(s.indexOf('[params]')).trim();
  assert.equal(params(t), params(theirs));
});

test('a camera on two people and a camera on whoever speaks are checked like the game checks them', () => {
  const ctx = context(), errs = steps => L.cutProblems(steps, ctx).err;
  assert.deepEqual(errs([{ do: 'camera', between: ['player', 'npc:stranger'], time: 1 }]), []);
  assert.ok(errs([{ do: 'camera', between: ['player', ''] }]).some(m => m.includes('два')), 'the picker half filled');
  assert.ok(errs([{ do: 'camera', between: ['player', 'npc:nobody_at_all'] }]).some(m => m.includes('nobody_at_all')));
  const dlg = 'ch1_stranger';
  assert.deepEqual(errs([{ do: 'dialogue', id: dlg, cast: { SPEAKER_ELIAN: 'player', SPEAKER_STRANGER: 'npc:stranger' } }]), []);
  assert.ok(errs([{ do: 'dialogue', id: dlg, cast: { SPEAKER_ELIAN: '' } }]).some(m => m.includes('не выбран')), 'a speaker with no one to look at');
  assert.ok(errs([{ do: 'dialogue', id: dlg, cast: { SPEAKER_NOBODY_ZZ: 'player' } }]).some(m => m.includes('SPEAKER_NOBODY_ZZ')));
  assert.ok(errs([{ do: 'dialogue', id: dlg, cast: { SPEAKER_ELIAN: 'npc:nobody_at_all' } }]).some(m => m.includes('nobody_at_all')));
  assert.ok(errs([{ do: 'dialogue', id: dlg, cast: ['player'] }]).length, 'cast is a map, not a list');
});

test('a person made for one scene is written as the validator wants an NPC, and stands in one room', () => {
  const ctx = context(), npcs = fs.readdirSync(path.join(ROOT, 'data/npcs')).map(f => JSON.parse(read('data/npcs/' + f)));
  const gdNeeds = read('scripts/tools/validate_data.gd').match(/"npcs": \[([^\]]*)\]/)[1].match(/"(\w+)"/g).map(x => x.slice(1, -1));
  const stranger = npcs.find(n => n.id === 'stranger'), idle = stranger.sprite.animations.idle;
  const person = { name: 'SPEAKER_STRANGER', dialogue: 'ch1_stranger', face: 'right', avatar: 'res://assets/portraits/elders.png',
    sprite: { idle, cell: stranger.sprite.cell, fps: 4, size: [stranger.sprite.cell[0] * 4, stranger.sprite.cell[1]] }, at: { room: 'graveyard_cross', x: 300, y: 254 } };
  const doc = JSON.parse(L.npcJson('zz_shepherd', person, 'zz_scene'));
  for (const k of gdNeeds) assert.ok(k in doc, k);
  assert.equal(doc.scripted, true); assert.equal(doc.menu, false); assert.equal(doc._studio, 'zz_scene');
  assert.deepEqual(doc.sprite, { animations: { idle }, cell: stranger.sprite.cell, fps: 4 }, 'the studio\'s own bookkeeping (size) stays out');
  assert.equal(doc.avatar, person.avatar);

  // checked before sending
  const own = extra => ({ ...ctx, own: { zz_shepherd: { ...person, ...extra } }, scene: 'zz_scene', rooms: ['graveyard_cross'],
    gameNpcs: new Map(npcs.map(n => [n.id, n._studio || ''])), scripted: new Set(npcs.filter(n => n.scripted).map(n => n.id)), missing: () => [] });
  const scene = [{ do: 'hold' }, { do: 'appear', who: 'npc:zz_shepherd', time: 0.6 }, { do: 'camera', between: ['player', 'npc:zz_shepherd'] }, { do: 'face', who: 'npc:zz_shepherd', dir: -1 }, { do: 'release' }];
  assert.deepEqual(L.cutProblems(scene, own({})).err, [], 'her own person is an actor of the scene');
  assert.deepEqual(L.cutProblems(scene, own({})).warn, []);
  const problems = (extra, id) => { const c = own(extra); if (id) c.own = { [id]: c.own.zz_shepherd }; return L.cutProblems(scene, c); };
  assert.ok(problems({}, 'Bad-Id').err.some(m => m.includes('латиница')));
  assert.ok(problems({}, 'stranger').err.some(m => m.includes('уже есть')), 'the game\'s own person is not overwritten');
  assert.ok(problems({ at: null }).err.some(m => m.includes('ни в одной комнате')));
  assert.ok(problems({ at: { room: 'swamp_moon', x: 1, y: 1 } }).warn.some(m => m.includes('swamp_moon')), 'standing where the scene does not play');
  assert.ok(problems({ dialogue: '' }).err.some(m => m.includes('диалог')));
  assert.ok(problems({ sprite: { ...person.sprite, cell: [50, stranger.sprite.cell[1]] } }).err.some(m => m.includes('не делится')));
  assert.ok(problems({ sprite: { ...person.sprite, idle: 'res://assets/sprites/zz_nope.png' } }).err.some(m => m.includes('zz_nope')));
  assert.ok(problems({ name: 'SPEAKER_ZZ_NO_TEXT' }).err.some(m => m.includes('нет имени')));
  const c = own({}); c.missing = () => ['uk', 'zh_CN'];
  assert.ok(L.cutProblems(scene, c).warn.some(m => m.includes('uk, zh_CN')));
  assert.ok(L.cutProblems(scene.filter(s => s.do !== 'appear'), own({})).warn.some(m => m.includes('zz_shepherd')), 'unseen until it appears');
  // the game's own scenes aim a camera or a burst at the spot before a person comes, and vanish them branch by branch: no warning there
  for (const f of fs.readdirSync(path.join(ROOT, 'data/cutscenes')))
    assert.ok(!L.cutProblems(JSON.parse(read('data/cutscenes/' + f)).steps, own({})).warn.some(m => m.includes('Не видно')), f);

  // the room table: placed once, placing again moves them, the rest of the table untouched
  const before = read('tools/rooms/studio_rooms.json');
  const once = L.mergeStudioRooms(before, { room: 'graveyard_cross', npc: ['zz_shepherd', 300, 254] });
  assert.deepEqual(JSON.parse(once).graveyard_cross.npcs, [['zz_shepherd', 300, 254]]);
  const moved = JSON.parse(L.mergeStudioRooms(once, { room: 'swamp_moon', npc: ['zz_shepherd', 10, 20] }));
  assert.equal(moved.graveyard_cross.npcs, undefined);
  assert.deepEqual(moved.swamp_moon.npcs, [['zz_shepherd', 10, 20]]);
  assert.equal(L.mergeStudioRooms(L.mergeStudioRooms(once, { room: 'graveyard_cross', npc: ['zz_shepherd', 1, 1] }), { room: 'graveyard_cross', npc: ['zz_shepherd', 300, 254] }), once);
  assert.ok(once.includes('["zz_shepherd", 300, 254]'), 'one row a line, like every other row');
});

test('a person stands on the floor, an enemy over it', () => {
  const floor = [[100, 300, 200]];
  assert.deepEqual(L.snapToSurface(floor, 150, 250), { x: 150, y: 288 });
  assert.deepEqual(L.snapToSurface(floor, 150, 250, L.NPC_LIFT), { x: 150, y: 300 - L.NPC_LIFT });
});
