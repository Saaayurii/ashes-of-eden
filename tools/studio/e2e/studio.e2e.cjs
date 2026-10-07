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

function restore() {
  // put back what the studio wrote: tracked files to HEAD, new files removed
  for (const line of git('status', '--porcelain', '--untracked-files=all').split('\n').filter(Boolean)) {
    if (before.has(line)) continue;
    const file = line.slice(3);
    if (line.startsWith('??')) fs.rmSync(path.join(ROOT, file), { force: true });
    else git('checkout', '--', file);
  }
}

const steps = [];
async function step(name, fn) {
  process.stdout.write(`  … ${name}\n`);
  await fn();
  steps.push(name);
  process.stdout.write(`  ok ${name}\n`);
}

(async () => {
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

    await step('every tab loads the game', async () => {
      for (const m of ['bg', 'cut', 'snd', 'chars']) { await page.evaluate(m => setMode(m), m); await page.waitForTimeout(1500); }
      const n = await page.evaluate(() => ({ rooms: bgs.length, cuts: cuts.length, snd: document.querySelectorAll('#sndList .irow').length }));
      assert.ok(n.rooms > 10 && n.cuts > 5 && n.snd > 50, JSON.stringify(n));
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

    await step('«📂 Файлы» fills frames, and the prompts name their images by role', async () => {
      const png = await page.evaluate(() => {
        const a = P.animations.find(a => a.name === 'idle'); P.current = a.id; renderAll();
        select({ type: 'frame', id: a.frames[2].id });
        const c = document.createElement('canvas'); c.width = c.height = 256; const x = c.getContext('2d');
        x.fillStyle = '#ff00ff'; x.fillRect(0, 0, 256, 256); x.fillStyle = '#3f6b2e'; x.fillRect(100, 40, 56, 180);
        return c.toDataURL('image/png').split(',')[1];
      });
      await page.setInputFiles('#frameFiles', { name: 'chatgpt.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
      await page.waitForFunction(() => !!P.animations.find(a => a.name === 'idle').frames[2].src);
      const t = await page.evaluate(() => {
        const a = P.animations.find(a => a.name === 'idle');
        return { edit: framePrompt(a, 3, false), strip: stripPrompt(a, false) };
      });
      assert.match(t.edit, /^Attached images, in order:\nImage 1: the APPROVED FRAME/);
      assert.match(t.edit, /Edit Image 1: change ONLY the pose/);
      assert.match(t.strip, /STYLE AND SCALE ONLY/);
      for (const v of Object.values(t)) assert.doesNotMatch(v, /exactly 44|image pixels/);
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
