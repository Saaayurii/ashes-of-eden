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
  if (!P) return;
  // closed: the game was unloaded with the panel (its music must not play on behind the studio)
  if (sandbox.el) { sandbox.el.hidden = false; sandboxAnims(); sandboxState('загружаю игру…'); sandbox.frame.src = await sandboxUrl(); return; }
  try { enemyList ||= await (await fetch('import/enemies.json')).json(); } catch { enemyList = []; }
  const bases = (enemyList || []).filter(e => !e.boss && !e.extends && BEHAVIOUR_RU[e.behaviour] && e.bestiary !== false);
  const el = sandbox.el = document.createElement('div');
  el.id = 'sandbox';
  el.innerHTML = `<div class="sb-head"><b>Песочница</b>
      <select id="sbBase" title="Как дерётся">${bases.map(e => `<option value="${e.id}" ${e.id === sandbox.base ? 'selected' : ''}>как ${esc(e.name?.ru || e.id)}</option>`).join('') || '<option value="cultist">как культист</option>'}</select>
      <select id="sbAnim" title="Драться или показать одну анимацию на месте"></select>
      <select id="sbSpeed" title="Замедлить игру, чтобы рассмотреть кадры"><option value="1">100 %</option><option value="0.5">50 %</option><option value="0.25">25 %</option></select>
      <select id="sbCount" title="Сколько их на дворе"><option value="1">×1</option><option value="2">×2</option><option value="3">×3</option></select>
      <span class="grow muted" id="sbState">загружаю игру…</span>
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
  el.querySelector('#sbBase').addEventListener('change', e => { sandbox.base = e.target.value; try { localStorage.setItem('ss_live_base', sandbox.base); } catch {} sandboxPost(true); });
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-sb]'); if (!b) return;
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
  const have = ENEMY_SLOTS.map(([slot]) => slot).filter(slot => enemySlotFor(P.animations, slot));
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
  if (!sandbox.ready || sandbox.el?.hidden || !P) return;
  const { strips, cell, fps } = await sandboxStrips(force);
  if (!strips.idle) return sandboxState('нужна анимация «idle» с готовыми кадрами');
  const msg = liveMessage({ name: P.name, base: sandbox.base, cell, fps, strips }), key = JSON.stringify(msg);
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
  if (e.data.type === 'ashes-live-applied') sandboxState(`в игре: ${(e.data.animations || []).join(', ')} · ${new Date().toLocaleTimeString().slice(0, 5)}`);
});
document.addEventListener('click', e => { if (e.target.closest('[data-act="chars-sandbox"]')) sandboxOpen(); });
