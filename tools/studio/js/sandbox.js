/* Sprite Studio — «Песочница»: the real game in a panel beside the frames.
 * The Web build runs in an iframe as studio-live.html (`--studio-live`,
 * scripts/run/studio_live.gd) and stands in the practice yard; every time the
 * frames are rebuilt the studio posts the current strips and the enemy they
 * fight like, and the game swaps the foe in place. No pull request, no export. */
'use strict';

const sandbox = { el: null, frame: null, ready: false, timer: 0, base: localStorage.getItem('ss_live_base') || 'cultist', sent: '', full: true, view: { anim: '', speed: 1, count: 1 } };
try { sandbox.full = localStorage.getItem('ss_live_full') !== '0'; } catch {}

// The game on the same site when it has one (Pages, a local copy of the site),
// otherwise the hosted one (the studio from the working tree): what she draws
// travels in the message, so the main build's engine and data are all the game
// side needs.
async function sandboxUrl() {
  const here = new URL('../studio-live.html', location.href).href;
  try { if ((await fetch(here, { method: 'HEAD', cache: 'no-store' })).ok) return here; } catch {}
  return (META.site || 'https://saaayurii.github.io/ashes-of-eden/') + 'studio-live.html';
}

async function sandboxOpen() {
  // closed: the game was unloaded with the panel (its music must not play on behind the studio)
  if (sandbox.el) { sandbox.el.hidden = false; sandboxAnims(); sandboxState('загружаю игру…'); sandbox.frame.src = await sandboxUrl(); return; }
  try { enemyList ||= await (await fetch('import/enemies.json')).json(); } catch { enemyList = []; }
  const bases = (enemyList || []).filter(e => sandbox.actionMode || (!e.boss && BEHAVIOUR_RU[e.behaviour] && e.bestiary !== false));
  const el = sandbox.el = document.createElement('div');
  el.id = 'sandbox';
  el.innerHTML = `<div class="sb-head"><b>Песочница</b>
      <select id="sbBase" title="Как дерётся">${bases.map(e => `<option value="${e.id}" ${e.id === sandbox.base ? 'selected' : ''}>как ${esc(e.name?.ru || e.id)}</option>`).join('') || '<option value="cultist">как культист</option>'}</select>
      <select id="sbAnim" title="Драться или показать одну анимацию на месте"></select>
      <select id="sbSpeed" title="Замедлить игру, чтобы рассмотреть кадры"><option value="1">100 %</option><option value="0.5">50 %</option><option value="0.25">25 %</option></select>
      <select id="sbCount" title="Сколько их на дворе"><option value="1">×1</option><option value="2">×2</option><option value="3">×3</option></select>
      <button class="sm" data-sb="pause">⏸</button><button class="sm" data-sb="step">Кадр →</button><button class="sm" data-sb="force">⚔ Атака</button><label>Расстояние<input id="sbDistance" type="number" value="50" min="1" max="1200" style="width:65px"></label><label><input type="checkbox" id="sbZones" checked> Зоны</label><span class="grow muted" id="sbState">загружаю игру…</span>
      <button class="sm" data-sb="send" title="Отправить кадры в игру сейчас">⟳</button>
      <button class="sm ghost" data-sb="reload" title="Перезапустить игру">↺</button>
      <button class="sm ghost" data-sb="size" id="sbSize"></button>
      <button class="sm ghost" data-sb="screen" title="Весь экран компьютера (Esc — выйти)">⛶</button>
      <button class="sm ghost" data-sb="close" title="Закрыть игру">✕</button></div>
    <iframe id="sbFrame" src="${esc(await sandboxUrl())}" allow="autoplay; fullscreen; gamepad" title="Игра"></iframe>
    <div class="sb-foot muted">Кликни по игре, чтобы управлять. Кадры обновятся сами через пару секунд после правки.</div>`;
  document.body.appendChild(el);
  sandbox.frame = el.querySelector('iframe');
  sandboxSize();
  for (const id of ['sbAnim', 'sbSpeed', 'sbCount']) el.querySelector('#' + id).addEventListener('change', () => {
    sandbox.view = { anim: $('#sbAnim').value, speed: +$('#sbSpeed').value, count: +$('#sbCount').value }; sandboxView();
  });
  sandboxAnims();
  $('#sbZones').onchange = () => sandboxCommand('debug');
  el.querySelector('#sbBase').addEventListener('change', e => { sandbox.base = e.target.value; try { localStorage.setItem('ss_live_base', sandbox.base); } catch {} sandboxPost(true); });
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-sb]'); if (!b) return;
    if (['pause','step','force'].includes(b.dataset.sb)) { if (b.dataset.sb === 'pause') { sandbox.paused = !sandbox.paused; b.textContent = sandbox.paused ? '▶' : '⏸'; } sandboxCommand(b.dataset.sb); }
    if (b.dataset.sb === 'send') sandboxPost(true);
    if (b.dataset.sb === 'size') { sandbox.full = !sandbox.full; try { localStorage.setItem('ss_live_full', sandbox.full ? '1' : '0'); } catch {} sandboxSize(); }
    if (b.dataset.sb === 'screen') { const f = el.requestFullscreen || el.webkitRequestFullscreen; if (f) Promise.resolve(f.call(el)).catch(() => toast('Браузер не дал открыть на весь экран', 'err')); sandbox.full = true; sandboxSize(); }
    if (b.dataset.sb === 'close') { if (document.fullscreenElement === el) document.exitFullscreen?.().catch(() => {}); el.hidden = true; sandbox.ready = false; sandbox.sent = ''; sandbox.frame.src = 'about:blank'; }
    if (b.dataset.sb === 'reload') { sandbox.ready = false; sandbox.sent = ''; sandboxState('загружаю игру…'); sandboxUrl().then(u => { sandbox.frame.src = u; }); }
  });
}
// What it can show: fight, or stand and play one of its animations.
const SLOT_RU = { idle: 'покой', walk: 'ходьба', attack: 'атака', attack_alt: 'вторая атака', special: 'особое', hurt: 'боль', death: 'смерть' };
function sandboxAnims() {
  const sel = sandbox.el?.querySelector('#sbAnim'); if (!sel || !P) return;
  const have = sandbox.actionMode && ATTACKS.data ? Object.keys(ATTACKS.data.roster.find(r => r.id === sandbox.base)?.body?.anims || {}) : ENEMY_SLOTS.map(([slot]) => slot).filter(slot => enemySlotFor(P.animations, slot));
  if (sandbox.view.anim && !have.includes(sandbox.view.anim)) sandbox.view.anim = '';
  sel.innerHTML = '<option value="">⚔ дерётся</option>' + have.map(slot => `<option value="${slot}" ${slot === sandbox.view.anim ? 'selected' : ''}>▶ ${SLOT_RU[slot] || slot}</option>`).join('');
}
function sandboxView() {
  if (!sandbox.ready || !sandbox.frame) return;
  sandbox.frame.contentWindow.postMessage({ type: 'ashes-live-view', ...sandbox.view }, '*');
}

// The game fills the studio's window (the default), or sits in a corner panel beside the frames.
function sandboxSize() {
  sandbox.el?.classList.toggle('full', sandbox.full);
  const b = sandbox.el?.querySelector('#sbSize'); if (!b) return;
  b.textContent = sandbox.full ? '▣' : '⬚';
  b.title = sandbox.full ? 'Уменьшить: игра в углу, рядом с кадрами' : 'Развернуть на всё окно';
}
const sandboxState = t => { const s = sandbox.el?.querySelector('#sbState'); if (s) s.textContent = t; };

// Strips for every enemy slot that has drawn frames, from the processed frames.
async function sandboxStrips(rebuild) {
  if (rebuild) await build();
  const S = P.settings, W = +S.cellW, H = +S.cellH, strips = {};
  for (const [slot] of ENEMY_SLOTS) {
    const a = enemySlotFor(P.animations, slot); if (!a) continue;
    const frames = a.frames.filter(f => !f.off && processed.has(f.id)); if (!frames.length) continue;
    const sheet = mk(W * frames.length, H), x = sheet.getContext('2d');
    frames.forEach((f, i) => x.drawImage(processed.get(f.id), i * W, 0));
    strips[slot] = sheet.toDataURL('image/png');
  }
  const idle = enemySlotFor(P.animations, 'idle');
  return { strips, cell: [W, H], fps: +idle?.fps || 8 };
}

async function sandboxPost(force) {
  if (!sandbox.ready || sandbox.el?.hidden) return;
  if (sandbox.actionMode) { await sandboxDataPost(); return; }
  if (!P) return;
  const { strips, cell, fps } = await sandboxStrips(force);
  if (!strips.idle) return sandboxState('нужна анимация «idle» с готовыми кадрами');
  const msg = { ...liveMessage({ name: P.name, base: sandbox.base, cell, fps, strips }), ...await sandboxDraftData(sandbox.base) }, key = JSON.stringify(msg);
  if (!force && key === sandbox.sent) return;
  sandbox.sent = key;
  sandbox.frame.contentWindow.postMessage(msg, '*');
  sandboxState('отправляю…');
}
// Called after every rebuild of the frames (chars.js build()), so it never builds itself.
function sandboxChanged() { clearTimeout(sandbox.timer); sandbox.timer = setTimeout(() => { sandboxAnims(); sandboxPost(false); }, 600); }

window.addEventListener('message', e => {
  if (!sandbox.frame || e.source !== sandbox.frame.contentWindow || !e.data?.type) return;
  if (e.data.type === 'ashes-live-ready') { sandbox.ready = true; sandbox.sent = ''; sandboxState('игра готова'); sandboxPost(true).then(sandboxView); }
  if (e.data.type === 'ashes-live-event') sandboxState(`${e.data.event} · кадр ${e.data.frame + 1} · урон ${e.data.damage}`);
  if (e.data.type === 'ashes-live-applied') { sandboxCommand('debug'); sandboxState(`в игре: ${(e.data.animations || []).join(', ')} · ${new Date().toLocaleTimeString().slice(0, 5)}`); }
});
document.addEventListener('click', e => { if (e.target.closest('[data-act="chars-sandbox"]')) sandboxOpen(); });

async function sandboxDraftData(id) {
  await worldLoad(); await attacksEnterData(); await shotsLoad(); await pfxLoad(); await loadSndLib();
  const docs = { ...WORLD.data.files, ...WORLD.work }, raw = docs[`data/enemies/${id}.json`];
  const spec = { ...(raw?.extends ? docs[`data/enemies/${raw.extends}.json`] : {}), ...raw };
  const over = docs['data/enemy_archetypes/tree.json']?.find(x => x.id === id);
  if (over) Object.assign(spec, over);
  const r = ATTACKS.data.roster.find(r => r.id === id);
  if (r) { spec.attacks = r.source.items.map((a, i) => sharedAttack(id, i, a)).filter((a, i) => !SHOTS.removed.has(`enemy:${id}:${i}`)); spec.attacks.push(...SHOTS.adds.filter(a => a.id === id).map(a => a.attack)); delete spec.attack; }
  const bodies = structuredClone(PFX.rules); bodies.studio_live = structuredClone(bodies[id] || {});
  const sounds = {};
  if (sndLib) for (const m of sndMods.values()) for (const t of sndEntry(m.id)?.takes || []) if (takeChanged(t) && !t.deleted) {
    const buf = await renderEdits(await takeBuffer(t), t.mod?.edits || EDIT_DEFAULT); sounds[t.stem] = await blobToDataURL(encodeWav(buf));
  }
  return { spec, bodies, styles: SHOTS.styles, sheets: Object.fromEntries(SHOTS.newSheets), sounds,
    player_actions: docs['data/player_actions.json']?.actions || {},
    abilities: Object.fromEntries(Object.entries(docs).filter(([p]) => p.startsWith('data/abilities/')).flatMap(([, a]) => a.map(v => [v.id, v]))) };
}
async function attacksEnterData() {
  if (!ATTACKS.data) {
    ATTACKS.data = await (await fetch('import/attacks.json')).json();
    ATTACKS.work = JSON.parse(localStorage.getItem('ss_attacks') || '{}');
    draftBase('attacks', ATTACKS.data, Object.keys(ATTACKS.work).length > 0);
    if (Object.keys(ATTACKS.work).length && !BASES.attacks.uncertain) ATTACKS.data = draftClone(BASES.attacks.value);
    const i = ATTACKS.data.roster.findIndex(r => r.id === 'possessed_villager'); ATTACKS.enemy = Math.max(0, i); ATTACKS.index = i >= 0 ? 2 : 0;
  }
}
async function sandboxActionOpen() {
  await attacksEnterData(); sandbox.actionMode = true; sandbox.base = attackRoster().id; sandbox.view.anim = '';
  await sandboxOpen(); $('#sbBase').value = sandbox.base;
  if (sandbox.ready) await sandboxDataPost();
}
async function sandboxDataPost() {
  const data = await sandboxDraftData(sandbox.base);
  sandbox.frame.contentWindow.postMessage({ type: 'ashes-live', mode: 'data', extends: sandbox.base, ...data }, '*');
  sandboxState('применяю действия и эффекты…');
}
function sandboxCommand(command) {
  if (!sandbox.ready) return toast('Сначала нажми Play в игре и дождись загрузки');
  sandbox.frame.contentWindow.postMessage({ type: 'ashes-live-control', command, paused: !!sandbox.paused, attack: ATTACKS.index, debug: $('#sbZones')?.checked !== false, distance: +$('#sbDistance')?.value || 50 }, '*');
}
document.addEventListener('click', e => { if (e.target.closest('[data-act="chars-sandbox"]')) sandbox.actionMode = false; });
