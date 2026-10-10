/* Every enemy attack, at its actual source (including inherited and archetype lists).
 * hit_frame is zero-based in JSON, one-based in the UI. No timer approximates the hit:
 * Enemy waits for AnimatedSprite2D.frame_changed. Particle rules remain in «Частицы». */
'use strict';
const ATTACK_TYPES = { melee: 'Удар', lunge: 'Рывок', ranged: 'Снаряды', beam: 'Луч', nova: 'По площади', summon: 'Призыв' };
const ATTACKS = { data: null, enemy: 0, index: 0, work: {}, raf: 0, started: 0, playing: false };
function attackDiff(base, changed) {
  return Object.fromEntries([...new Set([...Object.keys(base), ...Object.keys(changed)])]
    .filter(k => JSON.stringify(base[k]) !== JSON.stringify(changed[k])).map(k => [k, changed[k]]));
}
function attackProblems(a, frames) {
  const errors = [];
  if (!a || typeof a !== 'object' || Array.isArray(a)) return ['Нужен объект атаки.'];
  if (!(a.type in ATTACK_TYPES)) errors.push('Неизвестный тип атаки.');
  for (const k of ['range', 'windup', 'damage', 'cooldown']) if (!Number.isFinite(a[k]) || a[k] <= 0) errors.push(`${k}: нужно положительное число.`);
  if (a.animation !== undefined && typeof a.animation !== 'string') errors.push('Анимация: нужно имя.');
  if (a.hit_frame !== undefined && (!Number.isInteger(a.hit_frame) || a.hit_frame < 0 || a.hit_frame >= frames)) errors.push(`Кадр удара: от 1 до ${frames} (в JSON от 0).`);
  if (a.telegraph_fx !== undefined && !['glow', 'none'].includes(a.telegraph_fx)) errors.push('Предупреждение: glow или none.');
  if (a.impact_fx !== undefined && (!['magic', 'dust', 'none'].includes(a.impact_fx) || a.type !== 'nova')) errors.push('Эффект площади: magic, dust или none; только для nova.');
  return errors;
}
const attackRoster = () => ATTACKS.data.roster[ATTACKS.enemy];
const attackKey = () => `${attackRoster().id}:${ATTACKS.index}`;
const attackValue = () => ATTACKS.work[attackKey()] || attackRoster().source.items[ATTACKS.index];
function attackCount(a = attackValue()) {
  const b = attackRoster().body, im = b && shotStrip(b.anims[a.animation || 'attack']);
  return b?.frames?.[a.animation || 'attack'] || (im ? Math.max(1, Math.floor(im.width / b.cell[0])) : 1);
}
function attacksSave() { localStorage.setItem('ss_attacks', JSON.stringify(ATTACKS.work)); }
function attackSet(k, value) {
  const a = structuredClone(attackValue()); a[k] = value;
  if (k === "type" && value !== "nova") delete a.impact_fx;
  if (Object.keys(attackDiff(attackRoster().source.items[ATTACKS.index], a)).length) ATTACKS.work[attackKey()] = a;
  else delete ATTACKS.work[attackKey()];
  attacksSave(); renderAttacks();
}
function renderAttacks() {
  const r = attackRoster(), a = attackValue();
  $('#attackEnemy').innerHTML = ATTACKS.data.roster.map((r, i) => `<option value="${i}">${esc(r.name.ru || r.id)}</option>`).join(''); $('#attackEnemy').value = ATTACKS.enemy;
  $('#attackChoice').innerHTML = r.source.items.map((a, i) => `<option value="${i}">${esc(a.name || `${i + 1}. ${ATTACK_TYPES[a.type]}`)}</option>`).join(''); $('#attackChoice').value = ATTACKS.index;
  const num = (k, title, fallback, min = 0, step = 0.05) => `<label>${title}<input type="number" data-attack="${k}" min="${min}" step="${step}" value="${a[k] ?? fallback}"></label>`;
  const select = (k, title, values, fallback) => `<label>${title}<select data-attack="${k}">${Object.entries(values).map(([v, label]) => `<option value="${esc(v)}"${v === (a[k] ?? fallback) ? ' selected' : ''}>${esc(label)}</option>`).join('')}</select></label>`;
  $('#attackProps').innerHTML = select('type', 'Тип действия', ATTACK_TYPES, 'melee') +
    select('animation', 'Анимация', Object.fromEntries(Object.keys(r.body?.anims || {}).map(x => [x, x])), 'attack') +
    `<label>Кадр удара (с 1)<input type="number" data-attack="hit_frame" min="1" step="1" value="${(a.hit_frame ?? 0) + 1}"></label>` +
    select('telegraph_fx', 'Подсветка перед ударом', { glow: 'Свечение', none: 'Без подсветки' }, 'glow') +
    (a.type === 'nova' ? select('impact_fx', 'Эффект удара', { magic: 'Вспышка и кольцо', dust: 'Пыль по земле', none: 'Без эффекта' }, 'magic') + num('radius', 'Радиус, px', 90, 1, 1) : '') +
    (a.type === 'melee' ? num('reach', 'Размах, px', 38, 1, 1) : '') +
    (a.type === 'lunge' ? num('lunge_speed', 'Скорость рывка, px/с', 400, 1, 10) + num('lunge_time', 'Длительность рывка, с', 0.45, 0.01) : '') +
    (a.type === 'beam' ? num('length', 'Длина луча, px', 420, 1, 1) + num('thickness', 'Толщина луча, px', 26, 1, 1) + num('duration', 'Длительность луча, с', 0.45, 0.01) : '') +
    (a.type === 'summon' ? select('id', 'Кого призвать', Object.fromEntries(ATTACKS.data.roster.map(r => [r.id, r.name.ru || r.id])), 'shade') + num('count', 'Сколько призвать', 1, 1, 1) + num('max_alive', 'Максимум живых', 2, 1, 1) : '') +
    (a.type === 'ranged' ? num('projectile_speed', 'Скорость снаряда, px/с', 170, 1, 5) + num('projectiles', 'Снарядов за раз', 1, 1, 1) + num('spread', 'Разброс, °', 0, 0, 1) + `<label>Стиль снаряда<input data-attack="projectile_style" value="${esc(a.projectile_style || '')}"></label>` : '') +
    `<label>Цвет<input type="color" data-attack="color" value="${esc(a.color || '#b86cff')}"></label>` +
    num('windup', 'Подготовка, с', 0.5, 0.01) + num('damage', 'Урон', 10, 0.01, 1) + num('range', 'Дальность, px', 100, 1, 1) +
    num('cooldown', 'Перезарядка, с', 2, 0.01) + num('recover', 'Восстановление, с', 0.35) + num('weight', 'Частота выбора', 1, 0.01, 1) +
    `<label>Звук удара<input data-attack="sfx" value="${esc(a.sfx || '')}"></label>`;
  $('#attackJson').value = JSON.stringify(a, null, 2);
  $('#attackStatus').textContent = `${r.source.file} • ${Object.keys(ATTACKS.work).length} изменённых атак. Подготовка держит первый кадр; затем анимация запускается и урон срабатывает на выбранном кадре.`;
  ATTACKS.playing = false; $('#attackFrame').value = 1;
}
function attackDraw(now) {
  ATTACKS.raf = requestAnimationFrame(attackDraw);
  if (mode !== 'attacks' || !ATTACKS.data) return;
  const r = attackRoster(), a = attackValue(), fps = r.body?.fps || 6, count = attackCount();
  const hit = a.hit_frame ?? 0, elapsed = (now - ATTACKS.started) / 1000;
  const frame = ATTACKS.playing ? Math.min(count - 1, Math.max(0, Math.floor((elapsed - a.windup) * fps))) : +$('#attackFrame').value - 1;
  if (ATTACKS.playing) $('#attackFrame').value = frame + 1;
  $('#attackFrame').max = count;
  $('#attackTiming').textContent = `Кадр ${frame + 1}/${count} • Урон на кадре ${hit + 1}, через ${(a.windup + hit / fps).toFixed(3)} с от начала подготовки`;
  const c = $('#attackCanvas'), x = c.getContext('2d'), ground = 185;
  x.clearRect(0, 0, c.width, c.height); x.strokeStyle = '#655a4e'; x.beginPath(); x.moveTo(0, ground); x.lineTo(640, ground); x.stroke();
  drawBody(x, r.body, [320, ground - 11], ground, false, a.animation || 'attack', (frame + 0.01) / fps, 0);
  if (ATTACKS.playing && elapsed < a.windup && (a.telegraph_fx || 'glow') === 'glow') {
    x.fillStyle = (a.color || '#b86cff') + '33'; x.beginPath(); x.arc(320, ground - 20, 60, 0, Math.PI * 2); x.fill();
  }
  const since = elapsed - a.windup - hit / fps;
  const show = ATTACKS.playing ? since >= 0 && since < 0.45 : frame === hit;
  if (show && a.type === 'nova' && a.impact_fx !== 'none') {
    const radius = a.radius || 90; x.save(); x.globalAlpha = ATTACKS.playing ? Math.max(0, 1 - since / 0.45) : 0.8;
    x.fillStyle = a.color || '#b86cff'; x.strokeStyle = x.fillStyle;
    if (a.impact_fx === 'dust') {
      for (let i = 0; i < 7; i++) { x.beginPath(); x.ellipse(320 - radius + i * radius / 3, ground - 4, 13, 7, 0, 0, 7); x.fill(); }
    } else { x.beginPath(); x.arc(320, ground - 19, radius, 0, 7); x.stroke(); }
    x.restore();
  }
  if (show) { x.fillStyle = '#f1d9ac'; x.fillText('УДАР / УРОН', 15, 25); }
}
async function attacksFiles() {
  const files = {}, touched = [];
  for (const r of ATTACKS.data.roster) {
    const source = r.source, edits = source.items.map((a, i) => ATTACKS.work[`${r.id}:${i}`]);
    if (!edits.some(Boolean)) continue;
    for (const a of edits.filter(Boolean)) {
      const url = r.body?.anims[a.animation || 'attack'];
      const im = url && await loadImage(A(url));
      const problems = attackProblems(a, im ? Math.floor(im.width / r.body.cell[0]) : 1);
      if (a.animation && !r.body?.anims[a.animation]) problems.push('У персонажа нет этой анимации.');
      if (problems.length) throw new Error(`${r.id}: ${problems.join(' ')}`);
    }
    const original = files[source.file] ?? await repoText(source.file);
    if (source.inherited) files[source.file] = setJsonList(original, source.path, 'attacks', source.items.map((a, i) => edits[i] || a));
    else {
      files[source.file] = original;
      for (const [i, a] of edits.entries()) if (a) files[source.file] = patchJson(files[source.file], source.single ? [...source.path, source.key] : [...source.path, source.key, i], attackDiff(source.items[i], a));
    }
    touched.push(r.name.ru || r.id);
  }
  if (!touched.length) throw new Error('Нет изменений.');
  return { files, title: `Studio: attacks — ${touched.join(', ')}`, body: `Attack parameters, animation hit frames and effects edited in «Атаки»: ${touched.join(', ')}.` };
}
async function attacksEnter() {
  try {
    if (!ATTACKS.data) {
      ATTACKS.data = await (await fetch('import/attacks.json')).json();
      try { ATTACKS.work = JSON.parse(localStorage.getItem('ss_attacks') || '{}'); } catch {}
      const villager = ATTACKS.data.roster.findIndex(r => r.id === 'possessed_villager');
      if (villager >= 0) { ATTACKS.enemy = villager; ATTACKS.index = 2; }
    }
    renderAttacks(); if (!ATTACKS.raf) ATTACKS.raf = requestAnimationFrame(attackDraw);
  } catch (e) { $('#attackStatus').textContent = e.message; }
}
if (typeof document !== 'undefined') {
  $('#attackEnemy').addEventListener('change', e => { ATTACKS.enemy = +e.target.value; ATTACKS.index = 0; renderAttacks(); });
  $('#attackChoice').addEventListener('change', e => { ATTACKS.index = +e.target.value; renderAttacks(); });
  $('#attackProps').addEventListener('change', e => {
    const k = e.target.dataset.attack; if (!k) return;
    let value = e.target.type === 'number' ? +e.target.value : e.target.value;
    if (k === 'hit_frame') value -= 1;
    attackSet(k, value);
  });
  $('#attackFrame').addEventListener('input', () => { ATTACKS.playing = false; });
  $('#attackPlay').addEventListener('click', () => { ATTACKS.started = performance.now(); ATTACKS.playing = true; });
  $('#attackApply').addEventListener('click', () => {
    try { const a = JSON.parse($('#attackJson').value), errors = attackProblems(a, attackCount(a)); if (errors.length) throw new Error(errors.join(' ')); ATTACKS.work[attackKey()] = a; attacksSave(); renderAttacks(); }
    catch (e) { toast(e.message, 'err'); }
  });
  $('#attackReset').addEventListener('click', () => { delete ATTACKS.work[attackKey()]; attacksSave(); renderAttacks(); });
  $('#attackSend').addEventListener('click', async () => {
    await sendToGame(attacksFiles, null);
    if (sendToGame.last?.local) { ATTACKS.data = null; ATTACKS.work = {}; attacksSave(); await attacksEnter(); }
  });
}
if (typeof module !== 'undefined') module.exports = { attackDiff, attackProblems };
