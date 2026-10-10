// Exercises the actual controls and local write path; restores exact input bytes.
'use strict';
const { chromium } = require('playwright');
const { spawn, execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), tree = path.join(root, 'data/enemy_archetypes/tree.json');
const original = fs.readFileSync(tree), port = 8797;
const rebuild = () => execFileSync('python3', ['tools/studio/build_data.py'], { cwd: root, stdio: 'ignore' });
(async () => {
  rebuild();
  const server = spawn('python3', ['tools/studio/serve.py'], { cwd: root, env: { ...process.env, STUDIO_PORT: String(port) }, stdio: 'ignore' });
  let browser;
  try {
    for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://127.0.0.1:${port}/api/ping`)).ok) break; } catch {} await new Promise(r => setTimeout(r, 200)); }
    browser = await chromium.launch();
    const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } }), errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    await page.goto(`http://127.0.0.1:${port}/tools/studio/`);
    await page.waitForFunction(() => typeof Writer !== 'undefined' && Writer.mode === 'local');
    await page.locator('[data-m="attacks"]').click();
    await page.waitForFunction(() => ATTACKS.data && document.querySelector('[data-attack="hit_frame"]'));
    assert.equal(await page.locator('[data-attack="hit_frame"]').inputValue(), '2');
    assert.equal(await page.locator('[data-attack="impact_fx"]').inputValue(), 'dust');
    assert.equal(await page.locator('[data-attack="telegraph_fx"]').inputValue(), 'none');
    const types = await page.evaluate(() => [...new Set(ATTACKS.data.roster.flatMap(r => r.source.items.map(a => a.type)))].sort());
    assert.deepEqual(types, ['beam', 'lunge', 'melee', 'nova', 'ranged', 'summon']);
    await page.locator('[data-attack="hit_frame"]').fill('3');
    await page.locator('[data-attack="hit_frame"]').dispatchEvent('change');
    const output = await page.evaluate(async () => (await attacksFiles()).files);
    const changed = JSON.parse(output['data/enemy_archetypes/tree.json']);
    assert.equal(changed[0].attacks[2].hit_frame, 2);
    assert.deepEqual(changed.slice(1), JSON.parse(original.toString()).slice(1));
    // Reloading keeps the change, without sending yet.
    await page.reload();
    await page.locator('[data-m="attacks"]').click();
    await page.waitForFunction(() => ATTACKS.data && document.querySelector('[data-attack="hit_frame"]')?.value === '3');
    await page.locator('#attackPlay').click();
    await page.waitForFunction(() => document.querySelector('#attackFrame').value === '3');
    await page.screenshot({ path: '/tmp/ashes-studio-attacks.png' });
    await page.locator('#attackSend').click();
    await page.waitForFunction(() => document.querySelector('#dlg h3')?.textContent === 'Записано в игру', null, { timeout: 30000 });
    assert.equal(JSON.parse(fs.readFileSync(tree)).find(r => r.id === 'possessed_villager').attacks[2].hit_frame, 2);
    assert.deepEqual(errors, []);
    console.log('ATTACKS_E2E PASSED: all attack types, frame controls, persistence, byte-preserving patch and local write');
  } finally {
    await browser?.close(); server.kill(); fs.writeFileSync(tree, original); rebuild();
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
