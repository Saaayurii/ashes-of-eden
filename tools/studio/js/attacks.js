/* Every enemy attack, at its actual source (including inherited and archetype lists).
 * hit_frame is zero-based in JSON, one-based in the UI. No timer approximates the hit:
 * Enemy waits for AnimatedSprite2D.frame_changed. Particle rules remain in «Частицы». */
'use strict';
const ATTACK_TYPES = { melee: 'Удар', lunge: 'Рывок', ranged: 'Снаряды', beam: 'Луч', nova: 'По площади', summon: 'Призыв', hail: 'Град' };
const ATTACKS = { data: null, enemy: 0, index: 0, work: {}, position: 0, raf: 0, started: 0, playing: false };
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
  if (a.type === 'hail') {   // validate_data.gd: the stones fall where he can stand between them, after a wind-up he can read
    if (!Number.isInteger(a.count) || a.count < 1 || a.count > 8) errors.push('Град: камней от 1 до 8.');
    if (!(a.spacing >= 70)) errors.push('Град: между камнями не меньше 70 px — он должен уместиться.');
    if (!(a.windup >= 1) || !(a.fall_time > 0)) errors.push('Град: подготовка не меньше 1 с и время падения.');
  }
  return errors;
}
const attackRoster = () => ATTACKS.data.roster[ATTACKS.enemy];
const attackKey = () => `${attackRoster().id}:${ATTACKS.index}`;
const attackValue = () => sharedAttack(attackRoster().id, ATTACKS.index, attackRoster().source.items[ATTACKS.index]);
function attackCount(a = attackValue()) {
  const b = attackRoster().body, im = b && shotStrip(b.anims[a.animation || 'attack']);
  return b?.frames?.[a.animation || 'attack'] || (im ? Math.max(1, Math.floor(im.width / b.cell[0])) : 1);
}
function attacksSave() { localStorage.setItem('ss_attacks', JSON.stringify(ATTACKS.work)); draftHistory('attacks'); }
function attackSet(k, value) {
  const a = structuredClone(attackValue()); a[k] = value;
  if (SHOTS.data) { const u = SHOTS.data.users.find(u => u.kind === 'enemy' && u.id === attackRoster().id && u.index === ATTACKS.index && !u.added); if (u) { const e = SHOTS.edits.get(shotKey(u)); if (e) { delete e[k]; if (!Object.keys(e).length) SHOTS.edits.delete(shotKey(u)); shotsSave(); } } }
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
  $('#attackProps').innerHTML = `<label>Название действия<input data-attack="name" value="${esc(a.name || '')}"></label>` + select('type', 'Тип действия', ATTACK_TYPES, 'melee') +
    select('animation', 'Анимация', Object.fromEntries(Object.keys(r.body?.anims || {}).map(x => [x, x])), 'attack') +
    `<label>Кадр удара (с 1)<input type="number" data-attack="hit_frame" min="1" step="1" value="${(a.hit_frame ?? 0) + 1}"></label>` +
    select('telegraph_fx', 'Подсветка перед ударом', { glow: 'Свечение', none: 'Без подсветки' }, 'glow') +
    (a.type === 'nova' ? select('impact_fx', 'Эффект удара', { magic: 'Вспышка и кольцо', dust: 'Пыль по земле', none: 'Без эффекта' }, 'magic') + num('radius', 'Радиус, px', 90, 1, 1) : '') +
    (a.type === 'melee' ? num('reach', 'Размах, px', 38, 1, 1) : '') +
    (a.type === 'lunge' ? num('lunge_speed', 'Скорость рывка, px/с', 400, 1, 10) + num('lunge_time', 'Длительность рывка, с', 0.45, 0.01) : '') +
    (a.type === 'hail' ? num('count', 'Камней', 5, 1, 1) + num('spacing', 'Между камнями, px', 90, 1, 5) + num('fall_time', 'Время падения, с', 0.5, 0.01) : '') +
    (a.type === 'beam' ? num('length', 'Длина луча, px', 420, 1, 1) + num('thickness', 'Толщина луча, px', 26, 1, 1) + num('duration', 'Длительность луча, с', 0.45, 0.01) : '') +
    (a.type === 'summon' ? select('id', 'Кого призвать', Object.fromEntries(ATTACKS.data.roster.map(r => [r.id, r.name.ru || r.id])), 'shade') + num('count', 'Сколько призвать', 1, 1, 1) + num('max_alive', 'Максимум живых', 2, 1, 1) : '') +
    (a.type === 'ranged' ? num('projectile_speed', 'Скорость снаряда, px/с', 170, 1, 5) + num('projectiles', 'Снарядов за раз', 1, 1, 1) + num('spread', 'Разброс, °', 0, 0, 1) + `<label>Стиль снаряда<input data-attack="projectile_style" value="${esc(a.projectile_style || '')}"></label>` : '') +
    `<label>Цвет<input type="color" data-attack="color" value="${esc(a.color || '#b86cff')}"></label>` +
    num('windup', 'Подготовка, с', 0.5, 0.01) + num('damage', 'Урон', 10, 0.01, 1) + num('range', 'Дальность, px', 100, 1, 1) +
    num('from_hp', 'Использовать ниже доли здоровья (1 = всегда)', 1, 0.01) + (a.type === 'nova' ? num('trigger_range', 'Начинать при расстоянии, px', a.range, 1, 1) : '') +
    num('cooldown', 'Перезарядка, с', 2, 0.01) + num('recover', 'Восстановление, с', 0.35) + num('weight', 'Частота выбора', 1, 0.01, 1) +
    `<label>Звук удара<input data-attack="sfx" value="${esc(a.sfx || '')}"></label>`;
  $('#attackJson').value = JSON.stringify(a, null, 2);
  $('#attackStatus').textContent = `${r.source.file} • ${Object.keys(ATTACKS.work).length} изменённых атак. Подготовка держит первый кадр; затем анимация запускается и урон срабатывает на выбранном кадре.`;
  ATTACKS.playing = false; ATTACKS.position = 0; $('#attackFrame').value = 1; renderActionTimeline();
}
function attackDraw(now) {
  ATTACKS.raf = requestAnimationFrame(attackDraw);
  if (mode !== 'attacks' || !ATTACKS.data) return;
  const r = attackRoster(), a = attackValue(), fps = r.body?.fps || 6, count = attackCount();
  const hit = a.hit_frame ?? 0, elapsed = ATTACKS.playing ? (now - ATTACKS.started) / 1000 : ATTACKS.position;
  if (ATTACKS.playing) { ATTACKS.position = elapsed; $('#attackSeek').value = elapsed; if (elapsed >= +$('#attackSeek').max) ATTACKS.playing = false; }
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
  const baseline = draftBase('attacks', ATTACKS.data);
  for (const r of baseline.roster) {
    const source = r.source, edits = source.items.map((a, i) => sharedAttack(r.id, i, a));
    if (!edits.some((a, i) => !sameDraft(a, source.items[i]))) continue;
    const original = files[source.file] ?? await repoText(source.file);
    const doc = JSON.parse(original);
    let path = source.path;
    if (path.length && Array.isArray(doc)) { const i = doc.findIndex(x => x.id === r.id); if (i < 0) throw new Error(`Нет ${r.id} в актуальном файле`); path = [i]; }
    const node = path.reduce((o, k) => o[k], doc);
    let current = source.single ? [source.over ? { ...JSON.parse(await repoText(source.over)).attack, ...node[source.key] } : node[source.key]] : node[source.key];
    if (!current && source.inherited) {
      const inherited = JSON.parse(await repoText(source.from)); current = source.from_key === 'attack' ? [inherited.attack] : inherited.attacks;
    }
    if (!Array.isArray(current)) throw new Error(`Источник действий ${r.id} изменился.`);
    const plan = structuredClone(current);
    for (const [i, a] of edits.entries()) {
      if (sameDraft(a, source.items[i])) continue;
      const at = locateAction(current, source.items[i], i, source.items);
      plan[at] = await resolveDraft(source.items[i], a, current[at], `${r.id}: ${a.name || i + 1}`, BASES.attacks.uncertain);
      const url = r.body?.anims[plan[at].animation || 'attack'], im = url && await loadImage(A(url));
      const problems = attackProblems(plan[at], im ? Math.floor(im.width / r.body.cell[0]) : 1);
      if (plan[at].animation && !r.body?.anims[plan[at].animation]) problems.push('У персонажа нет этой анимации.');
      if (problems.length) throw new Error(`${r.id}: ${problems.join(' ')}`);
    }
    if (source.single) files[source.file] = patchJson(original, [...path, source.key], attackDiff(current[0], plan[0]));
    else if (source.inherited) files[source.file] = setJsonList(original, path, 'attacks', plan);
    else {
      files[source.file] = original;
      for (const [i, a] of plan.entries()) if (!sameDraft(current[i], a)) files[source.file] = patchJson(files[source.file], [...path, source.key, i], attackDiff(current[i], a));
    }
    touched.push(r.name.ru || r.id);
  }
  if (!touched.length) throw new Error('Нет изменений.');
  return { files, title: `Studio: actions — ${touched.join(', ')}`, body: `Action parameters, animation hit frames and effects: ${touched.join(', ')}.` };
}
// One action across the attack and projectile editors. Projectile-only edits overlay
// the shared attack; edits made here retire that field in the projectile overlay.
function sharedAttack(id, index, fallback) {
  const a = { ...(ATTACKS.work[`${id}:${index}`] || fallback) };
  if (SHOTS.data) { const u = SHOTS.data.users.find(u => u.kind === 'enemy' && !u.added && u.id === id && u.index === index); if (u) Object.assign(a, SHOTS.edits.get(shotKey(u)) || {}); }
  return a;
}
async function attacksEnter() {
  try {
    if (!ATTACKS.data) {
      ATTACKS.data = await (await fetch('import/attacks.json')).json();
      try { ATTACKS.work = JSON.parse(localStorage.getItem('ss_attacks') || '{}'); } catch {}
      draftBase('attacks', ATTACKS.data, Object.keys(ATTACKS.work).length > 0);
      if (Object.keys(ATTACKS.work).length && !BASES.attacks.uncertain) ATTACKS.data = draftClone(BASES.attacks.value);
      const villager = ATTACKS.data.roster.findIndex(r => r.id === 'possessed_villager');
      if (villager >= 0) { ATTACKS.enemy = villager; ATTACKS.index = 2; }
    }
    await pfxLoad(); trackChange('attacks'); renderAttacks(); if (!ATTACKS.raf) ATTACKS.raf = requestAnimationFrame(attackDraw);
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
  $('#attackFrame').addEventListener('input', () => { ATTACKS.playing = false; ATTACKS.position = attackValue().windup + (+$('#attackFrame').value - 1) / (attackRoster().body?.fps || 6); $('#attackSeek').value = ATTACKS.position; });
  $('#attackPlay').addEventListener('click', () => { ATTACKS.position = 0; ATTACKS.started = performance.now(); ATTACKS.playing = true; });
  $('#attackPause').onclick = () => { ATTACKS.playing = !ATTACKS.playing; ATTACKS.started = performance.now() - ATTACKS.position * 1000; };
  $('#attackStep').onclick = () => { ATTACKS.playing = false; $('#attackFrame').value = Math.min(attackCount(), +$('#attackFrame').value + 1); $('#attackFrame').dispatchEvent(new Event('input')); };
  $('#attackSeek').oninput = e => { ATTACKS.playing = false; ATTACKS.position = +e.target.value; $('#attackFrame').value = Math.min(attackCount(), Math.max(1, Math.floor((ATTACKS.position - attackValue().windup) * (attackRoster().body?.fps || 6)) + 1)); };
  $('#attackLive').onclick = sandboxActionOpen;
  $('#attackApply').addEventListener('click', () => {
    try { const a = JSON.parse($('#attackJson').value), errors = attackProblems(a, attackCount(a)); if (errors.length) throw new Error(errors.join(' ')); const u = SHOTS.data?.users.find(u => u.kind === 'enemy' && u.id === attackRoster().id && u.index === ATTACKS.index && !u.added); if (u) { SHOTS.edits.delete(shotKey(u)); shotsSave(); } ATTACKS.work[attackKey()] = a; attacksSave(); renderAttacks(); }
    catch (e) { toast(e.message, 'err'); }
  });
  $('#attackReset').addEventListener('click', () => { delete ATTACKS.work[attackKey()]; const u = SHOTS.data?.users.find(u => u.id === attackRoster().id && u.index === ATTACKS.index && !u.added); if (u) { SHOTS.edits.delete(shotKey(u)); shotsSave(); } attacksSave(); renderAttacks(); });
  $('#attackSend').addEventListener('click', async () => {
    await sendToGame(attacksFiles, null);
    if (sendToGame.last?.local) { delete BASES.attacks; draftBasesSave(); ATTACKS.data = null; ATTACKS.work = {}; attacksSave(); await attacksEnter(); }
  });
}
if (typeof module !== 'undefined') module.exports = { attackDiff, attackProblems };

function renderActionTimeline() {
  const a = attackValue(), r = attackRoster(), fps = r.body?.fps || 6;
  const animEnd = a.windup + attackCount() / fps, hit = a.windup + (a.hit_frame || 0) / fps;
  const end = Math.max(animEnd, hit + (a.recover ?? .35));
  $('#attackSeek').max = end; $('#attackSeek').step = 1 / fps;
  const marks = [{ t: 0, text: 'Подготовка' }, { t: a.windup, text: `Анимация ${a.animation || 'attack'}` }, { t: hit, text: `Удар: ${a.damage}` }, { t: end, text: 'Восстановление завершено' }];
  if (a.sfx) marks.push({ t: hit, text: `Звук: ${a.sfx}` });
  for (const fx of PFX.rules?.[r.id]?.[a.animation || 'attack'] || []) {
    if (fx.when === 'every') marks.push({ t: a.windup, text: `${fx.fx} каждые ${fx.every || .3} с` });
    else for (const frame of fx.when === 'frames' ? fx.frames || [] : [0]) marks.push({ t: a.windup + frame / fps, text: `${fx.fx} · кадр ${frame + 1}` });
  }
  $('#attackTimeline').innerHTML = marks.sort((a, b) => a.t - b.t).map(m => `<button class="sm" data-timeline="${m.t}">${m.t.toFixed(2)} с · ${esc(m.text)}</button>`).join('');
  $('#attackLinks').innerHTML = '<button class="sm" data-action-link="chars">Рисунок</button><button class="sm" data-action-link="pfx">Частицы этого действия</button>' + (a.type === 'ranged' ? '<button class="sm" data-action-link="shots">Снаряд</button>' : '') + (a.sfx ? '<button class="sm" data-action-link="snd">Звук удара</button>' : '');
}
if (typeof document !== 'undefined') document.addEventListener('click', async e => {
  const mark = e.target.closest('[data-timeline]'); if (mark) { $('#attackSeek').value = mark.dataset.timeline; $('#attackSeek').dispatchEvent(new Event('input')); }
  const b = e.target.closest('[data-action-link]'); if (!b) return;
  const r = attackRoster(), a = attackValue(), to = b.dataset.actionLink;
  if (to === 'pfx') { await pfxLoad(); PFX.body = Math.max(0, PFX.data.bodies.findIndex(b => b.key === r.id)); PFX.trigger = a.animation || 'attack'; }
  if (to === 'shots') { await shotsLoad(); SHOTS.user = Math.max(0, SHOTS.data.users.findIndex(u => u.id === r.id && u.index === ATTACKS.index)); SHOTS.style = null; }
  if (to === 'snd') { await loadSndLib(); sndSel = `sfx/${a.sfx}`; sndCat = 'sfx'; }
  if (to === 'chars') { const list = await (await fetch('import/list.json')).json(); const file = list.find(p => p.endsWith(`/${r.id}.sprite.json`)); if (file) await importFromUrl(file.startsWith('import/') ? file : 'import/' + file); }
  setMode(to);
});
