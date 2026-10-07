/* Sprite Studio — «Песочница»: the real game in a panel beside the frames.
 * The Web build runs in an iframe as studio-live.html (`--studio-live`,
 * scripts/run/studio_live.gd) and stands in the practice yard; every time the
 * frames are rebuilt the studio posts the current strips and the enemy they
 * fight like, and the game swaps the foe in place. No pull request, no export. */
'use strict';

const sandbox = { el: null, frame: null, ready: false, timer: 0, base: localStorage.getItem('ss_live_base') || 'cultist', sent: '' };

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
  if (sandbox.el) { sandbox.el.hidden = false; return sandboxPost(true); }
  try { enemyList ||= await (await fetch('import/enemies.json')).json(); } catch { enemyList = []; }
  const bases = (enemyList || []).filter(e => !e.boss && !e.extends && BEHAVIOUR_RU[e.behaviour] && e.bestiary !== false);
  const el = sandbox.el = document.createElement('div');
  el.id = 'sandbox';
  el.innerHTML = `<div class="sb-head"><b>Песочница</b>
      <select id="sbBase" title="Как дерётся">${bases.map(e => `<option value="${e.id}" ${e.id === sandbox.base ? 'selected' : ''}>как ${esc(e.name?.ru || e.id)}</option>`).join('') || '<option value="cultist">как культист</option>'}</select>
      <span class="grow muted" id="sbState">загружаю игру…</span>
      <button class="sm" data-sb="send" title="Отправить кадры в игру сейчас">⟳</button>
      <button class="sm ghost" data-sb="reload" title="Перезапустить игру">↺</button>
      <button class="sm ghost" data-sb="close" title="Спрятать (игра продолжит ждать)">✕</button></div>
    <iframe id="sbFrame" src="${esc(await sandboxUrl())}" allow="autoplay; fullscreen; gamepad" title="Игра"></iframe>
    <div class="sb-foot muted">Кликни по игре, чтобы управлять. Кадры обновятся сами через пару секунд после правки.</div>`;
  document.body.appendChild(el);
  sandbox.frame = el.querySelector('iframe');
  el.querySelector('#sbBase').addEventListener('change', e => { sandbox.base = e.target.value; try { localStorage.setItem('ss_live_base', sandbox.base); } catch {} sandboxPost(true); });
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-sb]'); if (!b) return;
    if (b.dataset.sb === 'send') sandboxPost(true);
    if (b.dataset.sb === 'close') el.hidden = true;
    if (b.dataset.sb === 'reload') { sandbox.ready = false; sandbox.sent = ''; sandboxState('загружаю игру…'); sandboxUrl().then(u => { sandbox.frame.src = u; }); }
  });
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
function sandboxChanged() { clearTimeout(sandbox.timer); sandbox.timer = setTimeout(() => sandboxPost(false), 600); }

window.addEventListener('message', e => {
  if (!sandbox.frame || e.source !== sandbox.frame.contentWindow || !e.data?.type) return;
  if (e.data.type === 'ashes-live-ready') { sandbox.ready = true; sandbox.sent = ''; sandboxState('игра готова'); sandboxPost(true); }
  if (e.data.type === 'ashes-live-applied') sandboxState(`в игре: ${(e.data.animations || []).join(', ')} · ${new Date().toLocaleTimeString().slice(0, 5)}`);
});
document.addEventListener('click', e => { if (e.target.closest('[data-act="chars-sandbox"]')) sandboxOpen(); });
