// The art studio in a real browser, against tools/studio/serve.py (local mode,
// so it writes into this checkout — everything it writes is put back at the end).
//
//   cd tools/studio/e2e && npm install --no-save --no-package-lock playwright@1.49.1
//   npx playwright install chromium && node studio.e2e.cjs
'use strict';
const { chromium } = require('playwright');
const { spawn, execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../../..');
const PORT = 8799;
const URL = `http://127.0.0.1:${PORT}/tools/studio/`;
const git = (...a) => execFileSync('git', a, { cwd: ROOT, encoding: 'utf8' });
const before = new Set(git('status', '--porcelain', '--untracked-files=all').split('\n').filter(Boolean));

// The studio's view of the game (tools/studio/import, not tracked). serve.py
// rebuilds it after each write, so a run leaves it listing the enemy it made;
// a second run then saw e2e_archer as taken and wrote e2e_archer_2.
const rebuildStudioData = () => execFileSync('python3', ['tools/studio/build_data.py'], { cwd: ROOT, stdio: 'ignore' });

function restore() {
  // put back what the studio wrote: tracked files to HEAD, new files removed
  for (const line of git('status', '--porcelain', '--untracked-files=all').split('\n').filter(Boolean)) {
    if (before.has(line)) continue;
    const file = line.slice(3);
    if (line.startsWith('??')) fs.rmSync(path.join(ROOT, file), { force: true });
    else git('checkout', '--', file);
  }
  rebuildStudioData();
}

const steps = [];
async function step(name, fn) {
  process.stdout.write(`  … ${name}\n`);
  await fn();
  steps.push(name);
  process.stdout.write(`  ok ${name}\n`);
}

(async () => {
  rebuildStudioData();
  const server = spawn('python3', ['tools/studio/serve.py'], { cwd: ROOT, env: { ...process.env, STUDIO_PORT: String(PORT) }, stdio: 'inherit' });
  const browser = await chromium.launch();
  const errors = [];
  try {
    for (let i = 0; i < 60; i++) { try { if ((await fetch(URL + 'import/meta.json')).ok) break; } catch {} await new Promise(r => setTimeout(r, 500)); }
    const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
    page.on('pageerror', e => errors.push(String(e)));
    page.on('dialog', d => d.accept(d.type() === 'prompt' ? 'e2e_archer' : undefined));
    await page.goto(URL);
    await page.waitForFunction(() => typeof Writer !== 'undefined' && Writer.mode === 'local');

    // Before any other tab has loaded: the wizard is reached from the
    // characters tab straight away, and its room list used to come up empty.
    await step('the enemy wizard lists the rooms on a fresh page', async () => {
      await page.waitForFunction(() => P);  // the wizard does nothing until the current character is loaded
      assert.equal(await page.evaluate(() => roomNames().length), 0, 'no tab has loaded the rooms yet');
      await page.evaluate(() => { enemyWizard(); });
      await page.waitForFunction(() => document.querySelectorAll('#dlg[open] .rp-room option').length > 10, null, { timeout: 15000 });
      const rooms = await page.$$eval('#dlg .rp-room option', o => o.map(x => x.value));
      assert.ok(rooms.includes('graveyard_cross'), rooms.join(' '));
      await page.evaluate(() => { const d = document.querySelector('#dlg'); d.close(); d.replaceChildren(); });
    });

    await step('every tab loads the game', async () => {
      for (const m of ['bg', 'cut', 'snd', 'chars']) { await page.evaluate(m => setMode(m), m); await page.waitForTimeout(1500); }
      // the rooms arrive in the background (25 files and their pictures): wait for them, not for a clock
      const count = () => page.evaluate(() => ({ rooms: bgs.length, cuts: cuts.length, snd: document.querySelectorAll('#sndList .irow').length }));
      await page.waitForFunction(() => bgs.length > 10 && cuts.length > 5 && document.querySelectorAll('#sndList .irow').length > 50, null, { timeout: 30000 })
        .catch(async () => assert.fail(JSON.stringify(await count())));
    });

    await step('a generated-style frame becomes a clean 44 px sprite', async () => {
      const h = await page.evaluate(async () => {
        document.querySelector('[data-act="proj-new"]').click();
        await new Promise(r => setTimeout(r, 300));
        Object.assign(P.settings, { cellW: 48, cellH: 56, bottomPad: 1, contentH: 44, scaleMode: 'gridfit' }); save();
        const c = document.createElement('canvas'); c.width = c.height = 1024; const x = c.getContext('2d');
        x.fillStyle = '#ff00ff'; x.fillRect(0, 0, 1024, 1024);
        for (let j = 0; j < 55; j++) for (let i = 0; i < 18; i++) if (Math.abs(i - 9) < 6) { x.fillStyle = (i + j) % 3 ? '#3f6b2e' : '#22301a'; x.fillRect(360 + i * 11, 220 + j * 11, 11, 11); }
        const file = new File([await new Promise(r => c.toBlob(r, 'image/png'))], 'f.png', { type: 'image/png' });
        const a = P.animations.find(a => a.name === 'idle');
        for (let i = 0; i < 2; i++) await SS.assignFiles([file], { type: 'frame', id: a.frames[i].id });
        await new Promise(r => setTimeout(r, 2500)); await SS.build();
        const p = SS.processed().get(a.frames[0].id), d = p.getContext('2d').getImageData(0, 0, p.width, p.height).data;
        let t = 99, b = -1; for (let y = 0; y < p.height; y++) for (let x = 0; x < p.width; x++) if (d[(y * p.width + x) * 4 + 3]) { t = Math.min(t, y); b = Math.max(b, y); }
        return b - t + 1;
      });
      assert.ok(Math.abs(h - 44) <= 1, `height ${h}`);
    });

    await step('the sandbox posts the strips to the game and hears it took them', async () => {
      // the game's side is studio_live_test.gd; here a stand-in page answers like StudioLive
      await page.route('**/studio-live.html', r => r.fulfill({ contentType: 'text/html', body: `<script>
        addEventListener('message', e => { if (e.source !== parent || e.data.type !== 'ashes-live') return; window.got = e.data;
          parent.postMessage({ type: 'ashes-live-applied', animations: Object.keys(e.data.strips) }, '*'); });
        parent.postMessage({ type: 'ashes-live-ready' }, '*');</script>` }));
      await page.click('[data-act="chars-sandbox"]');
      await page.waitForFunction(() => /в игре: idle/.test(document.querySelector('#sbState')?.textContent || ''), null, { timeout: 15000 });
      const got = await page.frameLocator('#sbFrame').locator('html').evaluate(() => ({ cell: window.got.cell, base: window.got.extends, idle: window.got.strips.idle.slice(0, 22) }));
      assert.deepEqual(got.cell, [48, 56]);
      assert.equal(got.base, 'cultist');
      assert.equal(got.idle, 'data:image/png;base64,');
      await page.click('#sandbox [data-sb="close"]');
      assert.equal(await page.getAttribute('#sbFrame', 'src'), 'about:blank', 'closing the panel unloads the game: no music behind the studio');
    });

    await step('undo and redo', async () => {
      const seq = await page.evaluate(() => {
        const f = () => P.animations.find(a => a.name === 'idle').frames[1];
        const set = v => { f().dur = v; history.chars.t = 0; save(); };
        set(2); set(3); const out = [f().dur]; undoRedo(false); out.push(f().dur); undoRedo(true); out.push(f().dur); return out;
      });
      assert.deepEqual(seq, [3, 2, 3]);
    });

    await step('the enemy wizard writes an enemy, places it and the room is regenerated', async () => {
      await page.evaluate(() => { enemyWizard(); });
      await page.waitForSelector('#dlg[open] #ewNameRu');
      await page.fill('#ewNameRu', 'Лучница e2e'); await page.fill('#ewTipRu', 'Проверка.');
      await page.selectOption('#ewBase', 'cultist');
      await page.selectOption('.rp-room', 'graveyard_cross');
      await page.waitForTimeout(1500);
      const placed = await page.evaluate(() => { const map = document.querySelector('.rp-map'); map.onclick({ offsetX: 420 * map.clientWidth / 1440, offsetY: 430 * map.clientWidth / 1440 }); return document.querySelector('.rp-info').textContent; });
      assert.match(placed, /graveyard_cross: 420, 506/);
      await page.click('#dlg [data-dlg="0"]');
      await page.waitForFunction(() => { const d = document.querySelector('#dlg'); return d?.open && /Записано в игру|Не получилось/i.test(d.innerText); }, null, { timeout: 120000 });
      const text = await page.textContent('#dlg');
      assert.match(text, /data\/enemies\/e2e_archer\.json/, text);
      // only the Russian name and tip were given: she is told English shows Russian
      assert.match(text, /без английского/, text);
      const scene = fs.readFileSync(path.join(ROOT, 'scenes/rooms/graveyard_cross.tscn'), 'utf8');
      assert.match(scene, /enemy_id = "e2e_archer"/);
      const entry = JSON.parse(fs.readFileSync(path.join(ROOT, 'data/enemies/e2e_archer.json'), 'utf8'));
      assert.equal(entry.extends, 'cultist'); assert.equal(entry.voice, 'cultist');
      // a closed dialog keeps its text: empty it, or the next step's wait passes at once
      await page.evaluate(() => { const d = document.querySelector('#dlg'); d.close(); d.replaceChildren(); });
    });

    await step('a dialogue line edited in a cutscene changes one line of strings.csv', async () => {
      git('checkout', '--', 'localization/strings.csv');
      await page.evaluate(async () => {
        setMode('cut'); await new Promise(r => setTimeout(r, 1500));
        CUT = cuts.find(c => c.id === 'knight_arrival');
        const s = CUT.steps.find(s => s.do === 'dialogue'), d = getDialogue(s.id), key = d.nodes[d.start].text;
        CUT.strings[key] = { ru: 'e2e строка', en: cutData.strings[key].en }; saveCut();
        sendToGame(cutFiles, 'cut');
      });
      await page.waitForFunction(() => { const d = document.querySelector('#dlg'); return d?.open && /Записано в игру|Не получилось/i.test(d.innerText); }, null, { timeout: 60000 });
      const diff = git('diff', '--numstat', '--', 'localization/strings.csv', 'data/cutscenes', 'data/dialogues').trim().split('\n');
      assert.deepEqual(diff, ['1\t1\tlocalization/strings.csv'], diff.join(' | '));
    });

    assert.deepEqual(errors, [], 'page errors: ' + errors.join('\n'));
    console.log(`studio e2e: ${steps.length} passed`);
  } finally {
    await browser.close();
    server.kill();
    restore();
  }
})().catch(e => { console.error('studio e2e FAILED:', e.message || e); process.exitCode = 1; });
