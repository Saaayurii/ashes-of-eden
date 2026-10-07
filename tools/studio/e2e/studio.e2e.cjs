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
      // the next steps want the idle as it was: two clean frames
      await page.evaluate(async () => { const f = P.animations.find(a => a.name === 'idle').frames[2]; f.src = null; save(); await SS.build(); });
    });

    await step('the sandbox posts the strips to the game and hears it took them', async () => {
      // the game's side is studio_live_test.gd; here a stand-in page answers like StudioLive
      await page.route('**/studio-live.html', r => r.fulfill({ contentType: 'text/html', body: `<script>
        addEventListener('message', e => { if (e.source !== parent || e.data.type !== 'ashes-live') return; window.got = e.data;
          parent.postMessage({ type: 'ashes-live-applied', animations: Object.keys(e.data.strips) }, '*'); });
        parent.postMessage({ type: 'ashes-live-ready' }, '*');</script>` }));
      await page.click('[data-act="chars-sandbox"]');
      await page.waitForSelector('#sandbox');
      const full = await page.evaluate(() => { const r = document.querySelector('#sandbox').getBoundingClientRect(); return [r.width, innerWidth, r.height, innerHeight]; });
      assert.ok(full[0] >= full[1] - 1 && full[2] >= full[3] - 1, 'the sandbox opens filling the window: ' + full);
      await page.waitForFunction(() => /в игре: idle/.test(document.querySelector('#sbState')?.textContent || ''), null, { timeout: 15000 });
      const got = await page.frameLocator('#sbFrame').locator('html').evaluate(() => ({ cell: window.got.cell, base: window.got.extends, idle: window.got.strips.idle.slice(0, 22) }));
      assert.deepEqual(got.cell, [48, 56]);
      assert.equal(got.base, 'cultist');
      assert.equal(got.idle, 'data:image/png;base64,');
      await page.click('#sandbox [data-sb="close"]');
      assert.equal(await page.getAttribute('#sbFrame', 'src'), 'about:blank', 'closing the panel unloads the game: no music behind the studio');
    });

    await step('the rig cuts a part sheet, walks it with planted feet and bakes 44 px frames', async () => {
      const r = await page.evaluate(async () => {
        setMode('rig');
        const c = document.createElement('canvas'); c.width = 900; c.height = 600; const x = c.getContext('2d');
        x.fillStyle = '#ff00ff'; x.fillRect(0, 0, 900, 600);
        x.fillStyle = '#2f5a2a'; x.beginPath(); x.ellipse(170, 150, 55, 62, 0, 0, 7); x.fill();
        x.fillStyle = '#3d6b33'; x.fillRect(120, 200, 110, 190);                                   // body
        x.fillStyle = '#4a3a2a'; x.fillRect(420, 120, 46, 250); x.fillStyle = '#2a1e16'; x.fillRect(420, 370, 70, 30);  // leg + boot
        x.fillStyle = '#3d6b33'; x.fillRect(620, 120, 36, 100); x.fillStyle = '#d6b08a'; x.fillRect(624, 220, 28, 100); // arm
        x.strokeStyle = '#7a5230'; x.lineWidth = 10; x.beginPath(); x.arc(700, 300, 200, -0.9, 0.9); x.stroke();           // bow
        await rigLoadSheet(c.toDataURL('image/png'));
        const roles = Object.keys(P.rig.parts).sort();
        const walk = P.animations.find(a => /walk|run/.test(a.name)); P.current = walk.id; renderRig();
        document.querySelector('[data-rig="gen-walk"]').click(); await new Promise(r => setTimeout(r, 200));
        const checks = [...document.querySelectorAll('#rigChecks div')].map(d => d.className);
        rigUI.imgs.clear();  // the parts not loaded yet when «Запечь» is pressed: the bake waits for them
        await rigBake(); await new Promise(r => setTimeout(r, 2500)); await SS.build();
        const hs = walk.frames.map(f => SS.processed().get(f.id)).map(p => { const d = p.getContext('2d').getImageData(0, 0, p.width, p.height).data; let t = 999, b = -1;
          for (let y = 0; y < p.height; y++) for (let xx = 0; xx < p.width; xx++) if (d[(y * p.width + xx) * 4 + 3]) { t = Math.min(t, y); b = Math.max(b, y); } return [b - t + 1, b]; });
        setMode('chars');
        return { roles, checks, baked: walk.frames.filter(f => f.baked).length, n: walk.frames.length, hs };
      });
      assert.deepEqual(r.roles, ['arm', 'body', 'leg', 'weapon']);
      assert.ok(r.checks.length >= 4 && r.checks.every(c => c === 'ok'), JSON.stringify(r.checks));
      assert.equal(r.baked, r.n);
      for (const [h] of r.hs) assert.ok(h >= 42 && h <= 45, `height ${h}`);
      assert.equal(new Set(r.hs.map(([, b]) => b)).size, 1, 'the feet stand on one row in every frame');
    });

    await step('a frame that jumps aside turns the badge on «→ В игру» red', async () => {
      const r = await page.evaluate(async () => {
        setMode('chars'); const a = P.animations.find(a => a.name === 'idle'); P.current = a.id; renderAll();
        await SS.build(); paintProcessed();
        const before = artReport.filter(c => c.bad && c.anim === 'idle').map(c => c.msg);
        const c = document.createElement('canvas'); c.width = c.height = 1024; const x = c.getContext('2d');
        x.fillStyle = '#ff00ff'; x.fillRect(0, 0, 1024, 1024);
        for (let j = 0; j < 55; j++) for (let i = 0; i < 18; i++) if (Math.abs(i - 9) < 6) { x.fillStyle = (i + j) % 3 ? '#3f6b2e' : '#22301a'; x.fillRect(360 + i * 11, 220 + j * 11, 11, 11); }
        const file = new File([await new Promise(r => c.toBlob(r, 'image/png'))], 'f.png', { type: 'image/png' });
        const f = a.frames[2]; await SS.assignFiles([file], { type: 'frame', id: f.id }); f.dx = 14; save();
        await new Promise(r => setTimeout(r, 2500)); await SS.build(); paintProcessed();
        const badge = document.querySelector('[data-act="chars-game"] .badge')?.textContent;
        const msgs = [...document.querySelectorAll('#artChecks .warn')].map(d => d.textContent);
        f.src = null; f.dx = 0; save(); await SS.build(); paintProcessed();
        return { before, badge, msgs };
      });
      assert.deepEqual(r.before, [], 'the clean idle has nothing red: ' + JSON.stringify(r));
      assert.ok(+r.badge >= 1, `badge ${r.badge}`);
      assert.ok(r.msgs.some(m => /idle.*прыгает/.test(m)), r.msgs.join(' | '));
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

    await step('a touch-up of an enemy the bestiary generator draws goes as an override and lands in its strip', async () => {
      const pre = new Set(git('status', '--porcelain', '--', 'assets', 'scenes/rooms', 'data/enemy_archetypes').split('\n').filter(Boolean));
      const res = await page.evaluate(async () => {
        setMode('chars');
        const p = migrate(await (await fetch('import/chars/cultist.sprite.json')).json()); projects.push(p); P = p; renderAll(); await build();
        const a = P.animations.find(a => a.name === 'idle'), f = a.frames[1];
        f.patch = { '12,30': [230, 20, 30, 255], '13,30': [230, 20, 30, 255] }; save(); await build();
        sendToGame(charFiles, 'chars');
        return { cell: [+P.settings.cellW, +P.settings.cellH], file: a.file };
      });
      await page.waitForFunction(() => { const d = document.querySelector('#dlg'); return d?.open && /Записано в игру|Не получилось/i.test(d.innerText); }, null, { timeout: 180000 });
      const text = await page.textContent('#dlg');
      assert.match(text, /tools\/studio\/overrides\/assets\/sprites\/cultist_v2_idle\.png/, text);
      assert.doesNotMatch(text, /Не получилось/, text);
      const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/studio/overrides/overrides.json'), 'utf8'));
      assert.ok(manifest['assets/sprites/cultist_v2_idle.png']?.base, 'the generator recorded the picture she drew on');
      // in the game's strip, frame 2 (x = one cell in), the two red pixels; nothing else in assets moved
      const px = execFileSync('python3', ['-c', `from PIL import Image; im = Image.open('assets/sprites/cultist_v2_idle.png').convert('RGBA'); print(im.getpixel((${res.cell[0]} + 12, 30)), im.getpixel((${res.cell[0]} + 13, 30)))`], { cwd: ROOT, encoding: 'utf8' }).trim();
      assert.equal(px, '(230, 20, 30, 255) (230, 20, 30, 255)');
      const moved = git('status', '--porcelain', '--', 'assets', 'scenes/rooms', 'data/enemy_archetypes').split('\n').filter(l => l && !l.startsWith('??') && !pre.has(l));
      assert.deepEqual(moved.map(l => l.slice(3)), ['assets/sprites/cultist_v2_idle.png'], 'only the edited strip changed');
      await page.evaluate(() => { const d = document.querySelector('#dlg'); d.close(); d.replaceChildren(); });
    });

    await step('a room painting repainted whole goes as an override of what differs', async () => {
      const panel = 'assets/levels/graveyard_cross_wide.png';
      await page.evaluate(async panel => {
        const im = await loadImage(A(panel)), c = mk(im.naturalWidth, im.naturalHeight), x = c.getContext('2d');
        x.drawImage(im, 0, 0); x.fillStyle = 'rgb(20, 200, 40)'; x.fillRect(300, 200, 5, 4);
        sendToGame(async () => ({ files: { [panel]: await canvasBlob(c) }, title: 'e2e repaint', body: '' }));
      }, panel);
      await page.waitForFunction(() => { const d = document.querySelector('#dlg'); return d?.open && /Записано в игру|Не получилось/i.test(d.innerText); }, null, { timeout: 180000 });
      const text = await page.textContent('#dlg');
      assert.doesNotMatch(text, /Не получилось/, text);
      const mask = execFileSync('python3', ['-c', `from PIL import Image; m = Image.open('tools/studio/overrides/assets/levels/graveyard_cross_wide.mask.png').convert('L'); print(m.getbbox())`], { cwd: ROOT, encoding: 'utf8' }).trim();
      assert.equal(mask, '(300, 200, 305, 204)', 'the mask is what she changed, nothing more');
      const px = execFileSync('python3', ['-c', `from PIL import Image; print(Image.open('${panel}').convert('RGB').getpixel((302, 201)))`], { cwd: ROOT, encoding: 'utf8' }).trim();
      assert.equal(px, '(20, 200, 40)', 'the room generator laid it into the painting');
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

    // ---- an iPad with an Apple Pencil: a touch screen, the pencil as a pen pointer (CDP), a palm as a touch ----
    await step('on a tablet the pencil paints, a palm and a finger do not, two fingers zoom, the rig takes the pencil', async () => {
      const ctx = await browser.newContext({ viewport: { width: 820, height: 1180 }, hasTouch: true, deviceScaleFactor: 2 });
      const tab = await ctx.newPage(); tab.on('pageerror', e => errors.push('tablet: ' + e));
      tab.on('dialog', d => d.accept(d.type() === 'prompt' ? 'e2e_tablet' : undefined));
      await tab.goto(URL); await tab.waitForFunction(() => typeof Writer !== 'undefined' && Writer.mode === 'local');
      const cdp = await ctx.newCDPSession(tab);
      const pen = (type, x, y, buttons = 1) => cdp.send('Input.dispatchMouseEvent', { type, x, y, button: type === 'mouseMoved' && !buttons ? 'none' : 'left', buttons, clickCount: 1, pointerType: 'pen' });
      const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map(([x, y], id) => ({ x, y, id })) });
      const fid = await tab.evaluate(async () => {
        document.querySelector('[data-act="proj-new"]').click(); await new Promise(r => setTimeout(r, 300));
        Object.assign(P.settings, { cellW: 48, cellH: 56, bottomPad: 1, contentH: 44, scaleMode: 'gridfit' }); save();
        const c = document.createElement('canvas'); c.width = c.height = 1024; const x = c.getContext('2d');
        x.fillStyle = '#ff00ff'; x.fillRect(0, 0, 1024, 1024);
        for (let j = 0; j < 55; j++) for (let i = 0; i < 18; i++) if (Math.abs(i - 9) < 6) { x.fillStyle = (i + j) % 3 ? '#3f6b2e' : '#22301a'; x.fillRect(360 + i * 11, 220 + j * 11, 11, 11); }
        const a = P.animations.find(a => a.name === 'idle');
        await SS.assignFiles([new File([await new Promise(r => c.toBlob(r, 'image/png'))], 'f.png', { type: 'image/png' })], { type: 'frame', id: a.frames[0].id });
        await new Promise(r => setTimeout(r, 2000)); await SS.build();
        openPaint(a.frames[0].id); await new Promise(r => setTimeout(r, 300));
        return a.frames[0].id;
      });
      assert.ok(await tab.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'no sideways scroll at 820×1180');
      const at = (px, py) => tab.evaluate(([px, py]) => { const c = $('#paintCanvas'), r = c.getBoundingClientRect(), k = paint.zoom * r.width / c.width;
        return [r.left + (px + 0.5) * k, r.top + (py + 0.5) * k]; }, [px, py]);
      const patch = () => tab.evaluate(fid => Object.keys(findFrame(fid).f.patch || {}), fid);
      // the pencil hovers (Pencil Pro), then draws a line
      await pen('mouseMoved', ...await at(5, 5), 0);
      assert.deepEqual(await tab.evaluate(() => paint.hover), [5, 5], 'a hovering pencil shows its pixel');
      await pen('mousePressed', ...await at(5, 5)); await pen('mouseMoved', ...await at(8, 5)); await pen('mouseReleased', ...await at(8, 5), 0);
      assert.ok((await patch()).includes('5,5') && (await patch()).includes('8,5'), 'the pencil paints');
      // a palm lands while the pencil is down
      await pen('mousePressed', ...await at(10, 10));
      await touch('touchStart', [await at(20, 20)]); await touch('touchMove', [await at(22, 20)]); await touch('touchEnd', []);
      await pen('mouseReleased', ...await at(10, 10), 0);
      assert.ok(!(await patch()).includes('20,20') && !(await patch()).includes('22,20'), 'the palm does not paint');
      // a finger alone, once a pencil was seen, does not paint either
      await touch('touchStart', [await at(30, 30)]); await touch('touchEnd', []);
      assert.ok(!(await patch()).includes('30,30'), 'a finger does not paint after the pencil');
      // two fingers spread: the canvas zooms
      const [cx, cy] = await at(24, 28);
      await touch('touchStart', [[cx - 40, cy], [cx + 40, cy]]); await touch('touchMove', [[cx - 120, cy], [cx + 120, cy]]); await touch('touchEnd', []);
      assert.ok(await tab.evaluate(() => paint.view.s) > 2, 'two fingers zoom in');
      assert.ok(await tab.evaluate(() => !!document.querySelector('#paintModal [data-act="undo"]') && !!document.querySelector('#paintModal [data-act="redo"]')), 'undo and redo on screen');
      // the rig: the pencil drags a foot, a palm drags nothing
      await tab.evaluate(async () => {
        closePaint(); setMode('rig');
        const c = document.createElement('canvas'); c.width = 900; c.height = 600; const x = c.getContext('2d');
        x.fillStyle = '#ff00ff'; x.fillRect(0, 0, 900, 600);
        x.fillStyle = '#3d6b33'; x.fillRect(120, 140, 110, 250); x.fillStyle = '#4a3a2a'; x.fillRect(420, 120, 46, 250); x.fillRect(420, 370, 70, 30);
        x.fillStyle = '#d6b08a'; x.fillRect(620, 120, 36, 200);
        await rigLoadSheet(c.toDataURL('image/png')); renderRig(); await new Promise(r => setTimeout(r, 300)); rigDraw();
      });
      await tab.evaluate(() => { $('#rigCanvas').scrollIntoView({ block: 'center' }); rigDraw(); });
      const foot = await tab.evaluate(() => { const h = rigUI.handles.find(h => h.id === 'ankleNear'), v = rigUI.view, c = $('#rigCanvas'), r = c.getBoundingClientRect();
        return [r.left + (v[4] + h.at[0] * v[0]) * r.width / c.width, r.top + (v[5] + h.at[1] * v[3]) * r.height / c.height]; });
      await touch('touchStart', [foot]); await touch('touchMove', [[foot[0] + 30, foot[1] - 20]]); await touch('touchEnd', []);
      assert.ok(foot[1] > 0 && foot[1] < 1180, `the foot is on screen at ${foot}`);
      assert.equal(await tab.evaluate(() => rigAnim().keys.length), 0, 'a palm on the rig moves nothing');
      await pen('mousePressed', ...foot); await pen('mouseMoved', foot[0] + 30, foot[1] - 20); await pen('mouseReleased', foot[0] + 30, foot[1] - 20, 0);
      const why = await tab.evaluate(() => JSON.stringify({ keys: rigAnim().keys.length, canvas: [$('#rigCanvas').width, $('#rigCanvas').height], rect: (r => [r.left, r.top, r.width, r.height].map(Math.round))($('#rigCanvas').getBoundingClientRect()), hdr: $('header.top').offsetHeight, view: innerHeight, pen: Ink.penSeen }));
      assert.equal(await tab.evaluate(() => rigAnim().keys.length), 1, 'the pencil keys a pose ' + why + ' foot ' + foot.map(Math.round));
      await ctx.close();
    });

    assert.deepEqual(errors, [], 'page errors: ' + errors.join('\n'));
    console.log(`studio e2e: ${steps.length} passed`);
  } finally {
    await browser.close();
    server.kill();
    restore();
    // serve.py rebuilt the studio's import/ after the wizard wrote its enemy; build it again from what is
    // committed, or the next run finds e2e_archer already in the game and names its enemy e2e_archer_2
    try { execFileSync('python3', ['tools/studio/build_data.py'], { cwd: ROOT, stdio: 'ignore' }); } catch {}
  }
})().catch(e => { console.error('studio e2e FAILED:', e.message || e); process.exitCode = 1; });
