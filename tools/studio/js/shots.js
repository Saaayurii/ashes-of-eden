/* Sprite Studio — ranged attacks: how every bolt looks (data/projectiles.json) and how each
 * attack looses them (the ranged attacks of data/enemies, the bolt gifts of data/abilities).
 * The preview flies them the way scripts/fx/projectile.gd does: the same motions, the same
 * look keys (pulse, breathe, squash, bob, wiggle, spin, echo, burst); a change there is a
 * change here. «→ В игру» writes the style file whole and patches only the attacks she
 * touched (lib.js patchJson), so the rest of each enemy's file stays byte for byte. */
'use strict';

const SHOTS = { data: null, styles: null, user: 0, style: null, edits: new Map(), sheets: new Map(), newSheets: new Map(),
  bolts: [], parts: [], clock: 0, next: 0, raf: 0, last: 0 };
const SHOT_LOOK = { frames: 1, fps: 10, scale: 0.62, light: 20, trail: 8, shader: 0, pulse: 0.07, breathe: [0, 0], squash: [1, 0, 0], bob: [0.7, 20], wiggle: [0, 0], spin: 0 };
const SHOT_ECHO = { offset: 9, sway: [3, 15], scale: 0.45, spin: 0, color: '#ffffff', alpha: -1 };
const SHOT_MOTIONS = { straight: 'Прямо', wave: 'Волной', accelerate: 'Разгоняется', arc: 'Падает дугой', surge: 'Зависает, потом рывок', return: 'Возвращается', home: 'Наводится' };
const SHOT_FX = { sparkle: 'Искры', ash: 'Пепел', debris: 'Осколки', spark: 'Вспышка клинка' };
const SHOT_KEYS = ['projectile_style', 'projectile_speed', 'projectile_motion', 'motion_amount', 'projectiles', 'spread', 'color', 'damage', 'windup', 'cooldown', 'volley', 'volley_gap', 'speed_jitter', 'projectile_scale'];
// a gift's bolt names the same things otherwise (Player._cast_skill)
const GIFT_KEY = { projectile_style: 'style', projectile_speed: 'speed', projectile_motion: 'motion' };

async function shotsLoad() {
  if (SHOTS.data) return;
  SHOTS.data = await (await fetch('import/projectiles.json')).json();
  SHOTS.styles = structuredClone(SHOTS.data.styles);
  try {
    const saved = JSON.parse(localStorage.getItem('ss_shots') || '{}');
    if (saved.styles) SHOTS.styles = saved.styles;
    for (const [k, v] of Object.entries(saved.edits || {})) SHOTS.edits.set(+k, v);
    for (const [k, v] of Object.entries(saved.sheets || {})) SHOTS.newSheets.set(k, v);
  } catch {}
}
function shotsSave() {
  try { localStorage.setItem('ss_shots', JSON.stringify({ styles: SHOTS.styles, edits: Object.fromEntries(SHOTS.edits), sheets: Object.fromEntries(SHOTS.newSheets) })); }
  catch (e) { toast('Не поместилось в память браузера: ' + e.message, 'err'); }
}
const shotUser = () => SHOTS.data.users[SHOTS.user];
// an attack as the game reads it, with her edits on top, in the enemy's own key names
function shotAttack(i = SHOTS.user) {
  const u = SHOTS.data.users[i], raw = { ...u.attack, ...(SHOTS.edits.get(i) || {}) }, a = { ...raw };
  if (u.kind === 'gift') for (const [k, g] of Object.entries(GIFT_KEY)) if (g in raw) a[k] = raw[g];
  return a;
}
function shotLook(key) {
  const look = { ...SHOT_LOOK, ...(SHOTS.styles[key] || SHOTS.styles.sacred) };
  look.echo = { ...SHOT_ECHO, ...(look.echo || {}) };
  return look;
}
function shotSheet(res) {
  if (!res) return null;
  if (!SHOTS.sheets.has(res)) {
    SHOTS.sheets.set(res, null);
    const src = SHOTS.newSheets.get(res) || A(SHOTS.data.sheets[res]?.url || res.replace('res://', ''));
    loadImage(src).then(im => SHOTS.sheets.set(res, im)).catch(() => {});
  }
  return SHOTS.sheets.get(res);
}
const shotsDirty = () => SHOTS.edits.size || SHOTS.newSheets.size || JSON.stringify(SHOTS.styles) !== JSON.stringify(SHOTS.data.styles);

/* ---------- flight: scripts/fx/projectile.gd in the browser ---------- */
function shotFire() {
  const a = shotAttack(), W = $('#shotCanvas').width, H = $('#shotCanvas').height;
  const from = [90, H * 0.55], to = [W - 110, H * 0.55 - 6];
  const rounds = Math.max(1, +a.volley || 1), gap = +a.volley_gap || 0.25;
  for (let r = 0; r < rounds; r++) setTimeout(() => {
    if (mode !== 'shots') return;
    const count = Math.max(1, +a.projectiles || 1), spread = (+a.spread || 0) * Math.PI / 180, jitter = +a.speed_jitter || 0;
    const dir = Math.atan2(to[1] - from[1], to[0] - from[0]);
    for (let i = 0; i < count; i++) {
      const off = count === 1 ? 0 : -spread / 2 + spread * i / (count - 1), ang = dir + off;
      SHOTS.bolts.push({ x: from[0], y: from[1], dx: Math.cos(ang), dy: Math.sin(ang), t: 0, life: 4, lateral: 0, turned: false,
        speed: (+a.projectile_speed || 170) * (1 + (Math.random() * 2 - 1) * jitter), motion: a.projectile_motion || 'straight',
        amount: +a.motion_amount || 0, style: a.projectile_style || 'sacred', size: +a.projectile_scale || 1, tint: a.color || '#ffd27a', trail: [] });
    }
    SHOTS.parts.push({ x: from[0] + 12, y: from[1], t: 0, life: 0.18, flash: a.color || '#ffd27a', r: 26 });
  }, r * gap * 1000);
}
function shotStep(b, dt, target) {
  b.t += dt; let travel = b.speed * dt;
  switch (b.motion) {
    case 'accelerate': travel *= 1 + Math.min(b.t, 2) * b.amount; break;
    case 'surge': travel *= 0.2 + 1.5 * Math.min(1, Math.max(0, (b.t - b.amount) / 0.45)); break;
    case 'arc': b.y += b.amount * b.t * dt; break;
    case 'wave': { const lat = Math.sin(b.t * 9) * b.amount; b.x += -b.dy * (lat - b.lateral); b.y += b.dx * (lat - b.lateral); b.lateral = lat; break; }
    case 'home': {
      const want = Math.atan2(target[1] - 12 - b.y, target[0] - b.x), now = Math.atan2(b.dy, b.dx);
      let d = want - now; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI;
      const turn = Math.max(-b.amount * dt, Math.min(b.amount * dt, d)); b.dx = Math.cos(now + turn); b.dy = Math.sin(now + turn); break;
    }
    case 'return': if (!b.turned && b.t >= b.amount) { b.turned = true; b.dx = -b.dx; b.dy = -b.dy; b.speed *= 1.2; travel = b.speed * dt; } break;
  }
  b.x += b.dx * travel; b.y += b.dy * travel; b.life -= dt;
}
function shotBurst(b) {
  const look = shotLook(b.style);
  for (const p of look.burst || [{ fx: 'sparkle', color: '#ffe8a1', count: 11 }]) {
    const n = +p.count || 10, spread = p.fx === 'ash' ? (+p.spread || 37) : p.fx === 'debris' ? 40 : 30;
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, v = (0.3 + Math.random()) * spread;
      SHOTS.parts.push({ x: b.x, y: b.y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - (p.fx === 'ash' ? 12 : 0), t: 0, life: 0.35 + Math.random() * 0.4,
        color: p.color || '#ffe8a1', size: p.fx === 'debris' ? 2 : p.fx === 'spark' ? 1.5 : (+p.size || 5) / 3, grav: p.fx === 'debris' ? 160 : p.fx === 'ash' ? -20 : 0 });
    }
  }
  SHOTS.parts.push({ x: b.x, y: b.y, t: 0, life: 0.22, flash: b.tint, r: 42 * Math.sqrt(b.size) });
}
function drawBolt(x, b) {
  const look = shotLook(b.style), im = shotSheet(look.sheet), t = b.t, frames = Math.max(1, +look.frames || 1);
  const ang = Math.atan2(b.dy, b.dx), pulse = Math.sin(t * 17), base = look.scale * b.size;
  // glow and trail first, as Fx.light / Fx.trail sit under the art
  const glow = x.createRadialGradient(b.x, b.y, 0, b.x, b.y, look.light * Math.sqrt(b.size));
  glow.addColorStop(0, shotRgba(b.tint, 0.32)); glow.addColorStop(1, shotRgba(b.tint, 0));
  x.globalCompositeOperation = 'lighter'; x.fillStyle = glow; x.beginPath(); x.arc(b.x, b.y, look.light * Math.sqrt(b.size), 0, 7); x.fill();
  b.trail.forEach((p, i) => { x.fillStyle = shotRgba(b.tint, 0.35 * (i + 1) / b.trail.length); x.fillRect(p[0] - 1, p[1] - 1, 2, 2); });
  x.globalCompositeOperation = 'source-over';
  if (!im) return;
  const fw = im.width / frames, fh = im.height, frame = frames > 1 ? Math.floor(t * look.fps) % frames : 0;
  const sprite = (fi, px, py, rot, sx, sy, alpha, tint) => {
    x.save(); x.translate(px, py); x.rotate(rot); x.scale(sx, sy); x.globalAlpha = alpha;
    x.drawImage(tint ? shotTinted(im, look.sheet, tint) : im, fi * fw, 0, fw, fh, -fw / 2, -fh / 2, fw, fh);
    x.restore();
  };
  const e = look.echo, rot = (vx, vy) => [vx * Math.cos(ang) - vy * Math.sin(ang), vx * Math.sin(ang) + vy * Math.cos(ang)];
  const [ex, ey] = rot(-e.offset, Math.sin(t * e.sway[1]) * e.sway[0]);
  const ea = e.alpha >= 0 ? e.alpha : 0.2 + 0.12 * (1 + pulse) / 2, es = base * (e.scale + 0.1 * pulse);
  sprite((frame + frames - 1) % frames, b.x + ex, b.y + ey, ang + e.spin * t, es, es, ea, e.color !== '#ffffff' ? e.color : null);
  const s = base * (1 + look.pulse * pulse) * (1 + look.breathe[0] * Math.sin(t * look.breathe[1]));
  const sy = s * (look.squash[0] + look.squash[1] * Math.sin(t * look.squash[2]));
  const [ax, ay] = rot(0, Math.sin(t * look.bob[1]) * look.bob[0]);
  sprite(frame, b.x + ax, b.y + ay, ang + look.wiggle[0] * Math.sin(t * look.wiggle[1]) + look.spin * t, s, sy, 1, null);
}
// the echo's colour laid over the sheet's own pixels only (Echo.modulate in the game)
const shotTints = new Map();
function shotTinted(im, res, color) {
  const key = res + '|' + color;
  if (!shotTints.has(key)) {
    const c = mk(im.width, im.height), x = c.getContext('2d');
    x.drawImage(im, 0, 0); x.globalCompositeOperation = 'multiply'; x.fillStyle = color; x.fillRect(0, 0, c.width, c.height);
    x.globalCompositeOperation = 'destination-in'; x.drawImage(im, 0, 0);
    shotTints.set(key, c);
  }
  return shotTints.get(key);
}
function shotRgba(h, a) { const n = parseInt(String(h).replace('#', '').slice(0, 6), 16); return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${Math.max(0, Math.min(1, a))})`; }
function shotFrame(now) {
  SHOTS.raf = 0; if (mode !== 'shots') return;
  const c = $('#shotCanvas'), x = c.getContext('2d'), dt = Math.min(0.05, (now - (SHOTS.last || now)) / 1000) * (+$('#shotSlow').value || 1); SHOTS.last = now;
  const W = c.width, H = c.height, target = [W - 110, H * 0.55 - 6], a = shotAttack();
  SHOTS.clock += dt;
  if (SHOTS.clock >= SHOTS.next) { shotFire(); SHOTS.next = SHOTS.clock + (+a.windup || 0.8) + (+a.cooldown || 2); }
  x.fillStyle = '#0f0d14'; x.fillRect(0, 0, W, H);
  x.fillStyle = '#1d1a24'; x.fillRect(0, H * 0.55 + 22, W, H);
  // the shooter and the hero, as markers
  const wind = Math.max(0, 1 - (SHOTS.next - SHOTS.clock) / (+a.windup || 0.8));
  x.fillStyle = '#3a3346'; x.fillRect(78, H * 0.55 - 14, 24, 36);
  if (wind > 0 && wind < 1) { x.globalCompositeOperation = 'lighter'; x.fillStyle = shotRgba(a.color || '#ffd27a', 0.5 * wind); x.beginPath(); x.arc(102, H * 0.55, 6 + 10 * wind, 0, 7); x.fill(); x.globalCompositeOperation = 'source-over'; }
  x.fillStyle = '#5b6b7a'; x.fillRect(target[0] - 8, target[1] - 16, 16, 44);
  x.fillStyle = '#cfd8e3'; x.font = '12px system-ui'; x.fillText(shotUser().kind === 'gift' ? 'враг' : 'герой', target[0] - 16, target[1] + 46);
  for (const b of SHOTS.bolts) {
    shotStep(b, dt, target); b.trail.push([b.x, b.y]); if (b.trail.length > (shotLook(b.style).trail || 8)) b.trail.shift();
    if (b.life <= 0 || b.x > W - 20 || b.x < 10 || b.y > H * 0.55 + 22 || b.y < 0 || Math.hypot(b.x - target[0], b.y - target[1]) < 12) { b.dead = true; shotBurst(b); }
    else drawBolt(x, b);
  }
  SHOTS.bolts = SHOTS.bolts.filter(b => !b.dead);
  x.globalCompositeOperation = 'lighter';
  for (const p of SHOTS.parts) {
    p.t += dt; const k = 1 - p.t / p.life;
    if (p.flash) { const g = x.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r); g.addColorStop(0, shotRgba(p.flash, 0.5 * k)); g.addColorStop(1, shotRgba(p.flash, 0)); x.fillStyle = g; x.beginPath(); x.arc(p.x, p.y, p.r, 0, 7); x.fill(); continue; }
    p.vy += (p.grav || 0) * dt; p.x += p.vx * dt; p.y += p.vy * dt;
    x.fillStyle = shotRgba(p.color, k); x.fillRect(p.x, p.y, p.size * 2, p.size * 2);
  }
  x.globalCompositeOperation = 'source-over';
  SHOTS.parts = SHOTS.parts.filter(p => p.t < p.life);
  SHOTS.raf = requestAnimationFrame(shotFrame);
}

/* ---------- panels ---------- */
function renderShots() {
  const users = SHOTS.data.users, list = $('#shotList');
  list.innerHTML = '<div class="muted">Враги</div>' + users.map((u, i) => u.kind === 'enemy' ? shotRow(u, i) : '').join('') +
    '<div class="muted" style="margin-top:6px">Дары героя</div>' + users.map((u, i) => u.kind === 'gift' ? shotRow(u, i) : '').join('') +
    `<div class="muted" style="margin-top:6px">Стили (${Object.keys(SHOTS.styles).length}) — без атаки: «blade» — волна третьего удара героя</div>` +
    Object.keys(SHOTS.styles).map(k => `<div class="irow${SHOTS.style === k ? ' on' : ''}" data-act="shot-style" data-k="${esc(k)}"><span class="grow">${esc(k)}</span><span class="muted">${users.filter((u, i) => shotAttack(i).projectile_style === k).length || ''}</span></div>`).join('');
  const send = $('#shotSend'); send.disabled = !shotsDirty(); send.textContent = shotsDirty() ? `→ В игру (${SHOTS.edits.size + (JSON.stringify(SHOTS.styles) !== JSON.stringify(SHOTS.data.styles) ? 1 : 0)})` : '→ В игру';
  renderShotProps();
}
const shotRow = (u, i) => `<div class="irow${i === SHOTS.user ? ' on' : ''}" data-act="shot-user" data-i="${i}"><span class="grow">${esc(u.name.ru || u.id)}${u.boss ? ' ⚜' : ''}</span>${SHOTS.edits.has(i) ? '<span class="badge">изменено</span>' : ''}<span class="muted">${esc(shotAttack(i).projectile_style || 'sacred')}</span></div>`;
function shotNum(k, v, min, max, step, label, hint = '') {
  return `<label class="lifenum" title="${esc(hint)}">${label} <span class="muted">${(+v).toFixed(step < 1 ? 2 : 0)}</span><input type="range" data-shot="${k}" min="${min}" max="${max}" step="${step}" value="${v}"></label>`;
}
function renderShotProps() {
  const u = shotUser(), a = shotAttack(), box = $('#shotProps'), styleKey = SHOTS.style || a.projectile_style || 'sacred', look = shotLook(styleKey);
  const gift = u.kind === 'gift';
  box.innerHTML = `<div class="card"><div class="row" style="margin:0"><b class="grow">${esc(u.name.ru || u.id)}</b>${SHOTS.edits.has(SHOTS.user) ? '<button class="sm" data-act="shot-revert">↺ Как в игре</button>' : ''}</div>
    <div class="muted">${gift ? 'дар героя · ' : 'атака врага · '}${esc(u.file)}</div>
    <label>Как выглядит<select data-shot="a.projectile_style">${Object.keys(SHOTS.styles).map(k => `<option${k === (a.projectile_style || 'sacred') ? ' selected' : ''}>${esc(k)}</option>`).join('')}</select></label>
    <label>Полёт<select data-shot="a.projectile_motion">${Object.entries(SHOT_MOTIONS).map(([k, v]) => `<option value="${k}"${k === (a.projectile_motion || 'straight') ? ' selected' : ''}>${v}</option>`).join('')}</select></label>
    ${(a.projectile_motion || 'straight') !== 'straight' ? shotNum('a.motion_amount', a.motion_amount ?? 1, 0.05, { wave: 30, arc: 120, return: 3.9, surge: 2, accelerate: 2, home: 4 }[a.projectile_motion] || 4, 0.05, { wave: 'Размах волны, px', arc: 'Сила падения', return: 'Через сколько секунд разворот', surge: 'Сколько висит, с', accelerate: 'Разгон', home: 'Поворот, рад/с' }[a.projectile_motion] || 'Сила') : ''}
    ${shotNum('a.projectile_speed', a.projectile_speed ?? (gift ? 300 : 170), 60, 480, 5, 'Скорость, px/с')}
    ${shotNum('a.projectiles', a.projectiles ?? 1, 1, 9, 1, 'Снарядов за раз')}
    ${(+a.projectiles || 1) > 1 ? shotNum('a.spread', a.spread ?? 0, 0, 90, 1, 'Веер, °') : ''}
    ${gift ? '' : shotNum('a.volley', a.volley ?? 1, 1, 5, 1, 'Залпов подряд', 'тот же залп ещё раз, прицелившись заново')}
    ${!gift && (+a.volley || 1) > 1 ? shotNum('a.volley_gap', a.volley_gap ?? 0.25, 0.08, 1.5, 0.01, 'Пауза между залпами, с') : ''}
    ${gift ? '' : shotNum('a.speed_jitter', a.speed_jitter ?? 0, 0, 0.5, 0.01, 'Разброс скорости', 'каждый снаряд чуть быстрее или медленнее')}
    ${shotNum('a.projectile_scale', a.projectile_scale ?? 1, 0.4, 2.5, 0.05, 'Размер')}
    ${shotNum('a.damage', a.damage ?? 10, 1, 60, 1, 'Урон' + ((+a.projectiles || 1) > 1 && gift ? ' (на все снаряды)' : ' (каждого)'))}
    ${gift ? shotNum('a.cooldown', a.cooldown ?? 6, 1, 20, 0.5, 'Перезарядка, с') : shotNum('a.windup', a.windup ?? 0.8, 0.3, 2, 0.05, 'Замах, с', 'сколько видно, что сейчас выстрелит: не короче 0.3') + shotNum('a.cooldown', a.cooldown ?? 2, 0.5, 8, 0.1, 'Пауза после, с')}
    <label>Цвет света<input type="color" data-shot="a.color" value="${esc(a.color || '#ffd27a')}"></label></div>
    <div class="card" style="margin-top:8px"><div class="row" style="margin:0"><b class="grow">Стиль «${esc(styleKey)}»</b><button class="sm" data-act="shot-clone" title="Новый стиль из этого">⧉ Новый</button></div>
    <div class="muted">Меняется у всех, кто им стреляет: ${esc(SHOTS.data.users.filter((q, i) => shotAttack(i).projectile_style === styleKey).map(q => q.name.ru || q.id).join(', ') || (styleKey === 'blade' ? 'волна героя' : 'пока никто'))}</div>
    <div class="row" style="margin:4px 0;flex-wrap:wrap"><label class="sm btnlike">⬆ Свой спрайт<input type="file" accept="image/png" id="shotFile" hidden></label><span class="muted">лента кадров слева направо, ${look.frames} кадр(а)</span></div>
    ${shotNum('s.frames', look.frames, 1, 8, 1, 'Кадров в ленте')}${look.frames > 1 ? shotNum('s.fps', look.fps, 2, 30, 1, 'Кадров в секунду') : ''}
    ${shotNum('s.scale', look.scale, 0.2, 1.5, 0.01, 'Размер')}${shotNum('s.spin', look.spin, -20, 20, 0.5, 'Вращение, рад/с')}
    ${shotNum('s.pulse', look.pulse, 0, 0.4, 0.01, 'Пульс')}${shotNum('s.bob.0', look.bob[0], 0, 6, 0.1, 'Дрожь вверх-вниз, px')}
    ${shotNum('s.wiggle.0', look.wiggle[0], 0, 0.6, 0.01, 'Виляние, рад')}${shotNum('s.squash.0', look.squash[0], 0.3, 1.5, 0.01, 'Сплющен (высота)')}
    ${shotNum('s.light', look.light, 0, 50, 1, 'Свет вокруг, px')}${shotNum('s.trail', look.trail, 0, 16, 1, 'След, частиц')}
    <div class="muted" style="margin-top:6px">Отражение позади</div>
    ${shotNum('s.echo.offset', look.echo.offset, 0, 30, 1, 'Отстаёт, px')}${shotNum('s.echo.scale', look.echo.scale, 0, 1.5, 0.01, 'Размер')}${shotNum('s.echo.spin', look.echo.spin, -20, 20, 0.5, 'Вращение')}
    ${shotNum('s.echo.alpha', look.echo.alpha < 0 ? 0.26 : look.echo.alpha, 0, 1, 0.01, 'Яркость')}<label>Цвет<input type="color" data-shot="s.echo.color" value="${esc(look.echo.color)}"></label>
    <div class="muted" style="margin-top:6px">Когда разбивается</div>
    ${(look.burst || [{ fx: 'sparkle', color: '#ffe8a1', count: 11 }]).map((p, i) => `<div class="row" style="margin:0;gap:4px"><select data-shot="s.burst.${i}.fx">${Object.entries(SHOT_FX).map(([k, v]) => `<option value="${k}"${k === p.fx ? ' selected' : ''}>${v}</option>`).join('')}</select><input type="color" data-shot="s.burst.${i}.color" value="${esc(p.color || '#ffe8a1')}"><input type="number" min="0" max="40" data-shot="s.burst.${i}.count" value="${+p.count || 10}" style="width:60px"></div>`).join('')}
    </div>`;
  $('#shotFile')?.addEventListener('change', e => { const f = e.target.files[0]; if (f) shotTakeSheet(styleKey, f); });
}
function shotSet(field, v) {
  if (field.startsWith('a.')) {
    const u = shotUser(), k = field.slice(2), key = u.kind === 'gift' ? (GIFT_KEY[k] || k) : k;
    const edit = { ...(SHOTS.edits.get(SHOTS.user) || {}) }; edit[key] = v;
    // a value back at the game's own is no edit
    for (const [ek, ev] of Object.entries(edit)) if (JSON.stringify(u.attack[ek]) === JSON.stringify(ev)) delete edit[ek];
    if (Object.keys(edit).length) SHOTS.edits.set(SHOTS.user, edit); else SHOTS.edits.delete(SHOTS.user);
    if (k === 'projectile_style') SHOTS.style = v;
  } else {
    const key = SHOTS.style || shotAttack().projectile_style || 'sacred', st = SHOTS.styles[key], path = field.slice(2).split('.');
    let o = st;
    for (let i = 0; i < path.length - 1; i++) {
      const p = path[i];
      if (o[p] === undefined) o[p] = p === 'echo' ? {} : p === 'burst' ? structuredClone(shotLook(key).burst || [{ fx: 'sparkle', color: '#ffe8a1', count: 11 }]) : structuredClone((path[0] === 'echo' ? SHOT_ECHO : SHOT_LOOK)[p]);
      o = o[p];
    }
    o[path.at(-1)] = v;
  }
  shotsSave();
}
async function shotTakeSheet(key, file) {
  const url = await blobToDataURL(file), im = await loadImage(url), frames = Math.max(1, Math.round(im.width / im.height)) || 1;
  const res = `res://assets/sprites/projectiles/${slug(key)}_studio.png`;
  SHOTS.newSheets.set(res, url); SHOTS.sheets.delete(res);
  SHOTS.styles[key].sheet = res; SHOTS.styles[key].frames = im.width % frames === 0 ? frames : 1;
  toast(`Спрайт ${im.width}×${im.height}: ${SHOTS.styles[key].frames} кадр(а). Если не так — поправь «Кадров в ленте».`);
  shotsSave(); renderShots();
}
async function shotsFiles() {
  const files = {}, touched = new Set();
  const doc = JSON.parse(await repoText('data/projectiles.json'));
  doc.styles = SHOTS.styles;
  files['data/projectiles.json'] = JSON.stringify(doc, null, 2) + '\n';
  for (const [res, url] of SHOTS.newSheets) if (Object.values(SHOTS.styles).some(s => s.sheet === res)) files[res.replace('res://', '')] = dataURLtoBlob(url);
  const texts = {};
  for (const [i, edit] of SHOTS.edits) {
    const u = SHOTS.data.users[i];
    texts[u.file] = patchJson(texts[u.file] ?? await repoText(u.file), u.path, edit);
    touched.add(u.name.ru || u.id);
  }
  Object.assign(files, texts);
  return { files, title: `Studio: ranged attacks — ${[...touched].join(', ') || 'styles'}`,
    body: `Projectile looks (data/projectiles.json) and ranged attacks edited in the studio's «Снаряды»: ${[...touched].join(', ') || 'styles only'}.`,
    notes: ['Подсказка «как драться» у врага должна остаться правдой: если залп стал другим, напиши об этом владельцу в отправке.'] };
}
async function shotsSend() {
  await sendToGame(shotsFiles, null);
  // written: the local server rebuilt import/, so read the game's own values again
  if (sendToGame.last?.local) { SHOTS.data = null; SHOTS.edits.clear(); SHOTS.newSheets.clear(); SHOTS.sheets.clear(); try { localStorage.removeItem('ss_shots'); } catch {} await shotsEnter(); }
}

async function shotsEnter() {
  try { await shotsLoad(); } catch (e) { $('#shotProps').innerHTML = `<div class="warn">Нет данных о снарядах (import/projectiles.json): ${esc(e.message)}</div>`; return; }
  // world pixels, as the game's 640 px wide view sees them, stretched to the stage
  const c = $('#shotCanvas'), r = $('#shotStage').getBoundingClientRect(); c.width = 640; c.height = Math.round(640 * Math.max(0.35, Math.min(0.75, r.height / Math.max(1, r.width))));
  renderShots(); SHOTS.next = 0;
  if (!SHOTS.raf) SHOTS.raf = requestAnimationFrame(shotFrame);
}
function shotsInit() {
  if (!$('#shotLayout')) return;
  const onInput = e => {
    const el = e.target.closest('[data-shot]'); if (!el) return;
    const f = el.dataset.shot, v = el.type === 'range' || el.type === 'number' ? +el.value : el.value;
    if (el.type === 'range' && el.previousElementSibling) el.previousElementSibling.textContent = (+v).toFixed(+el.step < 1 ? 2 : 0);
    shotSet(f, v);
    if (e.type === 'change') renderShots();
  };
  $('#shotSide').addEventListener('input', onInput); $('#shotSide').addEventListener('change', onInput);
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act^="shot-"]'); if (!b) return;
    const act = b.dataset.act;
    if (act === 'shot-user') { SHOTS.user = +b.dataset.i; SHOTS.style = null; SHOTS.bolts = []; SHOTS.next = 0; return renderShots(); }
    if (act === 'shot-style') { SHOTS.style = b.dataset.k; return renderShots(); }
    if (act === 'shot-revert') { SHOTS.edits.delete(SHOTS.user); shotsSave(); return renderShots(); }
    if (act === 'shot-fire') { SHOTS.next = SHOTS.clock; return; }
    if (act === 'shot-clone') {
      const from = SHOTS.style || shotAttack().projectile_style || 'sacred', name = slug(prompt('Имя нового стиля (латиницей):', from + '_2') || '');
      if (!name || name === 'sprite') return;
      if (SHOTS.styles[name]) return toast('Такой стиль уже есть.', 'err');
      SHOTS.styles[name] = structuredClone(SHOTS.styles[from]); SHOTS.style = name; shotSet('a.projectile_style', name); return renderShots();
    }
    if (act === 'shot-send') return shotsSend();
  });
}
shotsInit();
