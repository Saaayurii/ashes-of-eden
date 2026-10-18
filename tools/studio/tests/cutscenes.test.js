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
