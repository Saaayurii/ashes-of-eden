// The art studio's GitHub side in a real browser: the page as Pages serves it
// (?hosted), signed in as "tester", with api.github.com answered by a fake
// repository held in memory — nothing reaches GitHub. It walks the loop she
// lives in: send → a pull request on studio/tester-…, the owner's review under
// «Мои отправки», her answer, and a fix that lands in the same pull request.
//
//   cd tools/studio/e2e && npm install --no-save --no-package-lock playwright@1.49.1
//   npx playwright install chromium && node studio.github.e2e.cjs
'use strict';
const { chromium } = require('playwright');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../../..');
const PORT = 8798;
const URL = `http://127.0.0.1:${PORT}/tools/studio/?hosted`;
const REPO = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/studio/import/meta.json'), 'utf8')).repo;

// ---- a repository in memory: main is the checkout, everything else is blobs on top ----
function fakeGitHub() {
  const gh = { n: 0, blobs: {}, trees: { t0: { files: {} } }, commits: { c0: { tree: 't0', parents: [], message: 'main' } },
    refs: { main: 'c0' }, pulls: [], reviews: {}, lineNotes: {}, talk: {}, unhandled: [] };
  const id = p => p + (++gh.n);
  const commitOf = ref => gh.commits[ref] ? ref : gh.refs[ref];
  gh.fileAt = (ref, file) => {
    const files = gh.trees[gh.commits[commitOf(ref)].tree].files;
    if (file in files) return files[file];
    const p = path.join(ROOT, file);
    return fs.existsSync(p) ? fs.readFileSync(p) : null;
  };
  const pull = pr => ({ ...pr, head: { ref: pr.branch, sha: gh.refs[pr.branch], repo: { full_name: REPO } } });
  const user = login => ({ login });
  gh.handle = (method, url, body) => {
    const u = new globalThis.URL(url), p = u.pathname.replace(`/repos/${REPO}`, ''), J = body ? JSON.parse(body) : null;
    let m;
    if (method === 'GET' && (m = p.match(/^\/git\/ref\/heads\/(.+)$/))) return gh.refs[m[1]] ? { object: { sha: gh.refs[m[1]] } } : 404;
    if (method === 'GET' && (m = p.match(/^\/git\/commits\/(\w+)$/))) return { sha: m[1], tree: { sha: gh.commits[m[1]].tree } };
    if (method === 'POST' && p === '/git/blobs') { const s = id('b'); gh.blobs[s] = Buffer.from(J.content, 'base64'); return { sha: s }; }
    if (method === 'POST' && p === '/git/trees') {
      const files = { ...gh.trees[J.base_tree].files };
      for (const e of J.tree) { if (e.sha === null) delete files[e.path]; else files[e.path] = gh.blobs[e.sha]; }
      const s = id('t'); gh.trees[s] = { files }; return { sha: s };
    }
    if (method === 'POST' && p === '/git/commits') { const s = id('c'); gh.commits[s] = { tree: J.tree, parents: J.parents, message: J.message }; return { sha: s }; }
    if (method === 'POST' && p === '/git/refs') { gh.refs[J.ref.replace('refs/heads/', '')] = J.sha; return { ref: J.ref }; }
    if (method === 'PATCH' && (m = p.match(/^\/git\/refs\/heads\/(.+)$/))) { gh.refs[m[1]] = J.sha; return { ref: m[1] }; }
    if (method === 'GET' && (m = p.match(/^\/contents\/(.+)$/))) {
      const f = gh.fileAt(u.searchParams.get('ref') || 'main', decodeURIComponent(m[1]));
      return f === null ? 404 : { raw: f };
    }
    if (method === 'POST' && p === '/pulls') {
      const number = gh.pulls.length + 1;
      gh.pulls.push({ number, title: J.title, body: J.body, branch: J.head, state: 'open', merged_at: null,
        created_at: new Date().toISOString(), html_url: `https://github.com/${REPO}/pull/${number}`, user: user('tester') });
      gh.reviews[number] = []; gh.lineNotes[number] = []; gh.talk[number] = [];
      return pull(gh.pulls[number - 1]);
    }
    if (method === 'GET' && p === '/pulls') return gh.pulls.slice().reverse().map(pull);
    if (method === 'GET' && (m = p.match(/^\/pulls\/(\d+)$/))) return pull(gh.pulls[m[1] - 1]);
    if (method === 'GET' && (m = p.match(/^\/pulls\/(\d+)\/reviews$/))) return gh.reviews[m[1]] || 404;
    if (method === 'GET' && (m = p.match(/^\/pulls\/(\d+)\/comments$/))) return gh.lineNotes[m[1]] || 404;
    if (method === 'GET' && (m = p.match(/^\/pulls\/(\d+)\/files$/))) return Object.keys(gh.trees[gh.commits[gh.refs[gh.pulls[m[1] - 1].branch]].tree].files).map(filename => ({ filename }));
    if (method === 'GET' && (m = p.match(/^\/issues\/(\d+)\/comments$/))) return gh.talk[m[1]] || 404;
    if (method === 'POST' && (m = p.match(/^\/issues\/(\d+)\/comments$/))) { if (!gh.talk[m[1]]) return 404; gh.talk[m[1]].push({ user: user('tester'), body: J.body, created_at: new Date().toISOString() }); return {}; }
    if (method === 'GET' && /^\/commits\/\w+\/check-runs$/.test(p)) return { check_runs: [{ status: 'completed', conclusion: 'success' }] };
    gh.unhandled.push(`${method} ${p}`);
    return 404;
  };
  return gh;
}

const steps = [];
async function step(name, fn) {
  process.stdout.write(`  … ${name}\n`);
  await fn();
  steps.push(name);
  process.stdout.write(`  ok ${name}\n`);
}
const textOf = buf => Buffer.from(buf).toString('utf8');

(async () => {
  const server = spawn('python3', ['tools/studio/serve.py'], { cwd: ROOT, env: { ...process.env, STUDIO_PORT: String(PORT) }, stdio: 'inherit' });
  const browser = await chromium.launch();
  const gh = fakeGitHub();
  const errors = [];
  try {
    for (let i = 0; i < 60; i++) { try { if ((await fetch(URL.replace('?hosted', '') + 'import/meta.json')).ok) break; } catch {} await new Promise(r => setTimeout(r, 500)); }
    const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
    await context.addInitScript(() => localStorage.setItem('ss_github', JSON.stringify({ token: 'e2e-fake-token', login: 'tester' })));
    await context.route('https://api.github.com/**', async route => {
      const r = route.request();
      let out;
      // a request the fake cannot place must still get an answer, or the page waits forever
      try { out = gh.handle(r.method(), r.url(), r.postData()); }
      catch (e) { gh.unhandled.push(`${r.method()} ${r.url()}: ${e.message}`); return route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"fake GitHub"}' }); }
      if (out === 404) return route.fulfill({ status: 404, contentType: 'application/json', body: '{"message":"Not Found"}' });
      if (out.raw) return route.fulfill({ status: 200, contentType: 'application/octet-stream', body: out.raw });
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(out) });
    });
    // the site's preview pages are not built here
    await context.route(/github\.io\//, route => route.fulfill({ status: 404, body: '' }));
    const page = await context.newPage();
    page.on('pageerror', e => errors.push(String(e)));
    page.on('dialog', d => d.accept());   // «добавить в ту же отправку?» — yes
    await page.goto(URL);
    await page.waitForFunction(() => typeof Writer !== 'undefined' && Writer.mode === 'github');

    const editLine = text => page.evaluate(async text => {
      setMode('cut'); await new Promise(r => setTimeout(r, 1500));
      CUT = cuts.find(c => c.id === 'knight_arrival') || CUT;
      if (CUT?.id !== 'knight_arrival') { await importGameCutscenes(); CUT = cuts.find(c => c.id === 'knight_arrival'); }
      const s = CUT.steps.find(s => s.do === 'dialogue'), d = getDialogue(s.id), key = d.nodes[d.start].text;
      CUT.strings[key] = { ru: text, en: cutData.strings[key].en }; saveCut();
      sendToGame(cutFiles, 'cut');
    }, text);
    const result = re => page.waitForFunction(re => { const d = document.querySelector('#dlg'); return d?.open && new RegExp(re, 'i').test(d.innerText); }, re.source, { timeout: 60000 })
      .then(() => page.textContent('#dlg'));
    const closeDialog = () => page.evaluate(() => { const d = document.querySelector('#dlg'); d.close(); d.replaceChildren(); });

    let branch, first;
    await step('a send opens a pull request on her studio branch', async () => {
      await editLine('e2e строка');
      const text = await result(/Отправлено|Не получилось/);
      assert.match(text, /Отправлено/, text);
      assert.equal(gh.pulls.length, 1);
      const pr = gh.pulls[0];
      branch = pr.branch; first = gh.refs[branch];
      assert.match(branch, /^studio\/tester-\d{12}$/);
      assert.equal(pr.title, 'Studio: cutscene knight_arrival');
      assert.match(pr.body, /отправлено из Sprite Studio/);
      assert.match(textOf(gh.fileAt(branch, 'localization/strings.csv')), /e2e строка/);
      assert.ok(gh.fileAt(branch, 'tools/studio/projects/cuts/knight_arrival.json'), 'the project travels with the send');
      assert.deepEqual(gh.commits[first].parents, ['c0']);
      await closeDialog();
    });

    await step('the owner\'s review shows under «Мои отправки»', async () => {
      const at = new Date().toISOString();
      gh.reviews[1].push({ user: { login: 'owner' }, state: 'CHANGES_REQUESTED', body: 'Реплика длинновата, сократи.', submitted_at: at });
      gh.lineNotes[1].push({ user: { login: 'owner' }, body: 'Здесь запятая лишняя.', path: 'localization/strings.csv', created_at: at });
      gh.talk[1].push({ user: { login: 'owner' }, body: 'В остальном отлично.', created_at: at });
      await page.evaluate(() => { sentDialog(); });
      await page.waitForSelector('#dlg[open] .sentrow');
      const text = await page.textContent('#dlg');
      for (const want of ['просят исправить', 'Реплика длинновата', 'Здесь запятая лишняя', 'strings.csv', 'В остальном отлично', 'owner'])
        assert.ok(text.includes(want), `«${want}» not in: ${text}`);
    });

    await step('her answer goes into the conversation', async () => {
      await page.fill('#dlg [data-reply="1"]', 'Сократила, смотри.');
      await page.click('#dlg [data-send-reply="1"]');
      await page.waitForFunction(() => /Сократила, смотри\./.test(document.querySelector('#dlg')?.innerText || ''), null, { timeout: 15000 });
      assert.deepEqual(gh.talk[1].filter(c => c.user.login === 'tester').map(c => c.body), ['Сократила, смотри.']);
      await closeDialog();
    });

    await step('a fix lands in the same pull request', async () => {
      await editLine('e2e строка, короче');
      const text = await result(/Исправления добавлены|Отправлено|Не получилось/);
      assert.match(text, /Исправления добавлены/, text);
      assert.equal(gh.pulls.length, 1, 'no second pull request');
      const head = gh.refs[branch];
      assert.notEqual(head, first);
      assert.deepEqual(gh.commits[head].parents, [first], 'on top of her first commit');
      assert.equal(gh.commits[head].message, 'Studio: cutscene knight_arrival (исправления)');
      assert.match(textOf(gh.fileAt(branch, 'localization/strings.csv')), /e2e строка, короче/);
      assert.equal(gh.refs.main, 'c0', 'main untouched');
    });

    assert.deepEqual(errors, [], 'page errors: ' + errors.join('\n'));
    console.log(`studio github e2e: ${steps.length} passed`);
  } finally {
    if (gh.unhandled.length) console.log('fake GitHub had no answer for:', [...new Set(gh.unhandled)].join(', '));
    await browser.close();
    server.kill();
  }
})().catch(e => { console.error('studio github e2e FAILED:', e.message || e); process.exitCode = 1; });
