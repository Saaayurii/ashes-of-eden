/* «Боёвка»: how the hero handles — data/hero.json (stats + feel, Player.apply_hero; the moves he has
 * and how enemies keep their distance, "moves" / "enemy_ai", Enemy.apply_ai) and the swings
 * in data/player_actions.json. Her edits are a diff over the game's values, kept in the browser
 * (ss_combat); a send writes only the changed values in place (lib.js heroPatch / actionsPatch),
 * and the sandbox gets the whole hero at once (sandboxDraftData → StudioLive.apply). */
'use strict';
const combatBlank = () => ({ stats: {}, feel: {}, moves: {}, enemy_ai: {}, actions: {} });
const COMBAT = { data: null, work: combatBlank(), open: null };
// [key, label, step, min, max] grouped as she thinks of them; a key missing from the game's file is skipped
const COMBAT_GROUPS = [
  ['Тело и прыжок', [['stats.max_hp', 'Здоровье', 5, 1, 999], ['stats.speed', 'Скорость бега, px/с', 5, 10, 600], ['stats.acceleration', 'Разгон', 50, 100, 8000], ['stats.friction', 'Торможение (отпустил стик)', 50, 0, 8000],
    ['stats.jump_velocity', 'Сила прыжка', 5, 50, 900], ['stats.gravity', 'Гравитация', 25, 100, 4000], ['stats.max_jumps', 'Прыжков в воздухе', 1, 1, 5], ['feel.coyote_time', 'Прыжок после края, с', 0.01, 0, 0.5],
    ['feel.jump_buffer', 'Буфер прыжка, с', 0.01, 0, 0.5], ['feel.jump_cut_velocity', 'Короткий прыжок (отпустил)', 5, -600, 0], ['feel.step_height', 'Ступенька, px', 1, 0, 40], ['feel.mantle_rise', 'Залезание на край, px', 2, 0, 200],
    ['feel.mantle_time', 'Залезание, с', 0.01, 0.05, 1], ['feel.drop_through_time', 'Проход сквозь уступ, с', 0.01, 0.05, 1], ['feel.hard_landing', 'Жёсткое приземление от, px/с', 10, 50, 2000], ['feel.step_distance', 'Шаг (звук), px', 1, 4, 120]]],
  ['Удары', [['stats.attack_damage', 'Урон удара', 1, 1, 200], ['stats.attack_cooldown', 'Перезарядка удара, с', 0.05, 0.05, 5], ['stats.attack_scale', 'Размер зоны удара', 0.05, 0.2, 4],
    ['feel.combo_multipliers', 'Цепочка: множители 1·2·3', 0.05, 0.1, 10], ['feel.combo_recovery', 'Цепочка: перезарядка × базовая', 0.05, 0.05, 3], ['feel.combo_window', 'Окно цепочки, с', 0.05, 0.1, 5],
    ['stats.crit_chance', 'Шанс крита', 0.01, 0, 1], ['stats.crit_multiplier', 'Крит ×', 0.05, 1, 10], ['stats.backstab_multiplier', 'Удар в спину ×', 0.05, 1, 10], ['feel.knockback_fraction', 'Сбивает с ног от доли полоски', 0.01, 0, 1],
    ['feel.swing_time', 'Сколько замах держит тело, с', 0.01, 0.05, 2], ['feel.auto_reach', 'Автоудар: дальность, px', 1, 0, 200], ['feel.auto_height', 'Автоудар: высота, px', 1, 0, 200], ['feel.wave_speed', 'Волна клинка, px/с', 10, 50, 1200]]],
  ['Кувырок', [['stats.dash_speed', 'Скорость, px/с', 10, 50, 1500], ['stats.dash_time', 'Длительность = неуязвимость, с', 0.01, 0.05, 1.5], ['stats.dash_cooldown', 'Перезарядка, с', 0.05, 0, 10],
    ['stats.slide_friction', 'Скольжение после', 50, 0, 8000], ['feel.dash_reach', 'Режущий кувырок: досягаемость, px', 1, 0, 120], ['feel.dodge_counter_time', 'Ответ после уворота: окно, с', 0.05, 0, 10], ['feel.dodge_counter_bonus', 'Ответ после уворота: +урон', 0.01, 0, 1]]],
  ['Блок и парирование', [['feel.parry_window', 'Окно парирования, с', 0.01, 0, 1], ['feel.block_reduction', 'Блок снимает долю урона', 0.01, 0, 1], ['feel.block_speed', 'Скорость в блоке ×', 0.05, 0, 1],
    ['feel.block_recovery', 'Пауза между блоками, с', 0.01, 0, 2], ['feel.parry_push', 'Парирование отталкивает, px', 5, 0, 400], ['feel.block_push', 'Блок отталкивает, px', 5, 0, 400], ['feel.hurt_grace_time', 'Неуязвимость после раны, с', 0.01, 0, 2]]],
  ['Приёмы', [['feel.lunge_window', 'Выпад: окно ввода, с', 0.01, 0.05, 1], ['feel.lunge_speed', 'Выпад: скорость, px/с', 10, 50, 1500], ['feel.lunge_time', 'Выпад: длительность, с', 0.01, 0.05, 1], ['feel.lunge_multiplier', 'Выпад: урон ×', 0.05, 0.1, 10],
    ['feel.charge_after', 'Рассечение: заряд после, с', 0.05, 0, 3], ['feel.charge_full', 'Рассечение: полный заряд, с', 0.05, 0.05, 5], ['feel.charge_speed', 'Рассечение: скорость при заряде ×', 0.05, 0, 1],
    ['feel.cleave_multiplier', 'Рассечение: урон ×', 0.05, 0.1, 10], ['feel.cleave_stagger', 'Рассечение: оглушение, с', 0.05, 0, 5], ['feel.sweep_multiplier', 'Подсечка: урон ×', 0.05, 0.1, 10], ['feel.sweep_stagger', 'Подсечка: оглушение, с', 0.05, 0, 5],
    ['feel.technique_time', 'Сколько приём держит тело, с', 0.01, 0.05, 2]]],
  ['Удар сверху и стена', [['feel.slam_speed', 'Падение удара, px/с', 10, 100, 2000], ['feel.slam_min_height', 'Нужна высота, px', 1, 0, 200], ['feel.slam_radius', 'Радиус удара, px', 1, 4, 200], ['feel.slam_damage_share', 'Урон × удара мечом', 0.05, 0, 1],
    ['feel.slam_recovery', 'Стоит после, с', 0.01, 0, 2], ['feel.wall_slide_speed', 'Скольжение по стене, px/с', 2, 0, 600], ['feel.wall_jump_push', 'Прыжок от стены: вбок', 5, 0, 800], ['feel.wall_jump_rise', 'Прыжок от стены: вверх × прыжка', 0.02, 0, 2], ['feel.wall_jump_turn_lock', 'Прыжок от стены: стик заперт, с', 0.01, 0, 1]]],
  ['Лечение и раны', [['stats.heal_charges', 'Фляг', 1, 0, 10], ['feel.heal_amount', 'Фляга лечит', 1, 0, 500], ['feel.heal_time', 'Пить флягу, с', 0.05, 0.05, 5], ['stats.armor', 'Броня (доля)', 0.01, 0, 0.9], ['stats.extra_lives', 'Запасных жизней', 1, 0, 5],
    ['feel.rally_time', 'Отыграться: окно, с', 0.1, 0, 10], ['feel.rally_damage_share', 'Отыграться: доля раны назад', 0.01, 0, 1], ['feel.rally_hit_share', 'Отыграться: за удар', 0.01, 0, 1], ['feel.rally_max_hp_share', 'Отыграться: не больше доли полоски', 0.01, 0, 1],
    ['feel.curse_damage', 'Проклятие: раны ×', 0.1, 1, 10], ['feel.refuse_heal', 'Отказ от даров лечит долю', 0.01, 0, 1]]],
  ['Враги: дистанция и повадки', [['enemy_ai.attackers_per_side', 'Бьют разом с одной стороны', 1, 1, 6], ['enemy_ai.crowd_step', 'Очередь: каждый следующий дальше, px', 1, 0, 120],
    ['enemy_ai.band_depth', 'Ждёт за досягаемостью, px (от · до)', 1, 0, 200], ['enemy_ai.hit_attack_delay', 'После раны пауза до замаха, с', 0.01, 0, 2], ['enemy_ai.repeat_attack_weight', 'Повтор той же атаки (вес)', 0.01, 0, 1],
    ['enemy_ai.alert_time', '«!» до первого шага, с', 0.05, 0, 3], ['enemy_ai.shout_radius', 'Крик будит спящих в радиусе, px', 5, 0, 600], ['enemy_ai.retarget_interval', 'Пересматривает цель, с', 0.05, 0.05, 5],
    ['enemy_ai.sight_defaults', 'Зрение: дальность · высота · чутьё сзади, px', 5, 0, 1000], ['enemy_ai.patrol_defaults', 'Патруль: радиус · скорость × · паузы, с', 0.05, 0, 1000],
    ['enemy_ai.flyer_min_gap', 'Летун: не ближе, px', 1, 0, 300], ['enemy_ai.personal_space', 'Летун: выталкивается из тела ближе, px', 1, 0, 200], ['enemy_ai.flock_space', 'Летуны друг от друга, px', 1, 0, 200],
    ['enemy_ai.peck_patience', 'Летун бросает заход через, с', 0.05, 0.05, 3], ['enemy_ai.parry_opening', 'Открыт после парирования, с', 0.05, 0, 5], ['enemy_ai.riposte_multiplier', 'Рипост: урон ×', 0.05, 1, 10],
    ['enemy_ai.execute_below', 'Добивание ниже доли здоровья', 0.01, 0, 1]]],
  ['Предметы', [['feel.heal_burst_radius', 'Фляга обжигает в радиусе, px', 2, 0, 400], ['feel.parry_stun_radius', 'Парирование оглушает в радиусе, px', 2, 0, 400], ['feel.wrath_time', 'Гнев после раны, с', 0.1, 0, 10], ['feel.desperate_share', 'Отчаяние ниже доли', 0.01, 0, 1]]],
];
// the special moves a game's hero may have (Player.MOVE_KEYS); off = the button does the plain thing
const COMBAT_MOVES = [['lunge', 'Выпад'], ['cleave', 'Рассечение (заряд)'], ['sweep', 'Подсечка'], ['rising', 'Удар вверх и в прыжке'], ['dash_strike', 'Удар из кувырка'],
  ['slam', 'Удар сверху'], ['wall_jump', 'Стена: скольжение и прыжок'], ['riposte', 'Рипост'], ['backstab', 'Удар в спину']];
const ACTION_KEYS = [['multiplier', 'Урон ×', 0.05], ['recovery', 'Перезарядка × базовая', 0.05], ['animation_time', 'Длит., с', 0.01], ['knockback', 'Отбрасывание', 0.1], ['hit_frame', 'Кадр удара (с 0)', 1], ['stagger', 'Оглушение, с', 0.05], ['radius', 'Радиус, px', 1]];

async function combatLoad() {
  if (COMBAT.data) return;
  await worldLoad();
  COMBAT.data = { hero: WORLD.data.files['data/hero.json'] || {}, actions: WORLD.data.files['data/player_actions.json']?.actions || {} };
  for (const s of HERO_SECTIONS) COMBAT.data.hero[s] ||= {};
  try { Object.assign(COMBAT.work, JSON.parse(localStorage.getItem('ss_combat') || '{}')); } catch {}
  for (const [k, v] of Object.entries(combatBlank())) COMBAT.work[k] ||= v;
}
const combatGame = key => { const [s, k] = key.split('.'); return COMBAT.data.hero[s]?.[k]; };
const combatMine = key => { const [s, k] = key.split('.'); return k in COMBAT.work[s] ? COMBAT.work[s][k] : combatGame(key); };
function combatSave() { try { localStorage.setItem('ss_combat', JSON.stringify(COMBAT.work)); } catch {} if (typeof workspaceStatus === 'function') workspaceStatus();
  if (typeof sandbox !== 'undefined' && sandbox.ready && sandbox.from === 'combat') sandboxChanged(); }
function combatSet(key, v) {
  const [s, k] = key.split('.');
  if (sameDraft(v, combatGame(key))) delete COMBAT.work[s][k]; else COMBAT.work[s][k] = v;
  combatSave();
}
// the whole hero as the game would load it after a send (for the sandbox)
const combatHero = () => Object.fromEntries(HERO_SECTIONS.map(s => [s, { ...COMBAT.data.hero[s], ...COMBAT.work[s] }]));
const combatActions = () => Object.fromEntries(Object.entries(COMBAT.data.actions).map(([id, a]) => [id, { ...a, ...(COMBAT.work.actions[id] || {}) }]));
const combatHeroCount = () => HERO_SECTIONS.reduce((n, s) => n + Object.keys(COMBAT.work[s]).length, 0);
const combatCount = () => combatHeroCount() + Object.values(COMBAT.work.actions).reduce((n, a) => n + Object.keys(a).length, 0);

function combatField(key, label, step, min, max) {
  const game = combatGame(key); if (game === undefined) return '';
  const mine = combatMine(key), changed = !sameDraft(mine, game);
  const num = (v, sub) => `<input type="number" step="${step}" min="${min}" max="${max}" value="${v}" data-cb="${key}"${sub !== undefined ? ` data-cb-sub="${sub}"` : ''} style="width:${sub !== undefined ? 62 : 84}px">`;
  // a list, a table, a table of lists (sight_defaults): one box per number, its path in data-cb-sub
  const boxes = (g, m, path) => Array.isArray(g) ? g.map((_, i) => num(m?.[i] ?? g[i], [...path, i].join('.'))).join('')
    : g && typeof g === 'object' ? Object.keys(g).map(k => `<span class="muted" style="font-size:11px">${esc(k)}</span>${boxes(g[k], m?.[k], [...path, k])}`).join('')
    : num(m ?? g, path.length ? path.join('.') : undefined);
  const inputs = boxes(game, mine, []);
  return `<div class="cbrow${changed ? ' cbchanged' : ''}"><label title="${esc(key)}">${esc(label)}</label><span class="cbin">${inputs}</span>
    <span class="muted cbgame" title="как в игре">${changed ? 'было ' + esc(fmtJson(game)) : ''}</span>${changed ? `<button class="sm ghost" data-cb-reset="${key}" title="Как в игре">⟲</button>` : ''}</div>`;
}
function renderCombat() {
  if (!COMBAT.data) return;
  const groups = COMBAT_GROUPS.map(([title, rows]) => `<details class="card" ${COMBAT.open === title || (!COMBAT.open && title === COMBAT_GROUPS[0][0]) ? 'open' : ''} data-cb-group="${esc(title)}"><summary><b>${esc(title)}</b>
      <span class="muted">${rows.filter(([k]) => !sameDraft(combatMine(k), combatGame(k))).length || ''}</span></summary>${rows.map(r => combatField(...r)).join('')}</details>`).join('');
  const acts = combatActions();
  const table = `<details class="card"><summary><b>Удары и приёмы героя</b> <span class="muted">data/player_actions.json</span></summary><div style="overflow:auto"><table class="cbtable"><tr><th></th>${ACTION_KEYS.map(([, l]) => `<th>${esc(l)}</th>`).join('')}</tr>
    ${Object.entries(acts).map(([id, a]) => `<tr><td><b>${esc(id)}</b></td>${ACTION_KEYS.map(([k, , step]) => k in COMBAT.data.actions[id]
      ? `<td><input type="number" step="${step}" min="0" value="${a[k]}" data-cb-act="${esc(id)}" data-cb-key="${k}" style="width:70px${sameDraft(a[k], COMBAT.data.actions[id][k]) ? '' : ';outline:1px solid #e0b050'}"></td>` : '<td></td>').join('')}</tr>`).join('')}</table></div>
    <div class="note">Хитбокс, смещение и звук — во вкладке «Поведение» (player_actions.json).</div></details>`;
  const extra = Object.keys(COMBAT.data.hero.stats).filter(k => !COMBAT_GROUPS.some(([, rows]) => rows.some(([key]) => key === 'stats.' + k)));
  const mech = `<details class="card"><summary><b>Механики даров и предметов</b> <span class="muted">у героя без даров — 0</span></summary>${extra.map(k => combatField('stats.' + k, k, 0.05, 0, 100)).join('')}</details>`;
  const has = COMBAT_MOVES.filter(([id]) => id in COMBAT.data.hero.moves);
  const moves = has.length ? `<details class="card" open><summary><b>Приёмы героя</b> <span class="muted">выключенный — кнопка делает простое: удар, падение, скольжение</span></summary>
    <div style="display:flex;flex-wrap:wrap;gap:4px 14px;padding:4px 0">${has.map(([id, label]) => { const on = combatMine('moves.' + id) !== false, changed = !sameDraft(on, combatGame('moves.' + id));
      return `<label style="${changed ? 'outline:1px solid #e0b050;' : ''}padding:1px 4px"><input type="checkbox" data-cb-move="${id}" ${on ? 'checked' : ''}> ${esc(label)}</label>`; }).join('')}</div></details>` : '';
  $('#combatBody').innerHTML = moves + groups + table + mech;
  const n = combatCount();
  $('#combatStatus').textContent = n ? `Изменено значений: ${n}. Сохранено в браузере; «→ В игру» запишет только их.` : 'Всё как в игре.';
  $('#combatSend').disabled = !n;
}
async function combatEnter() { try { await combatLoad(); renderCombat(); } catch (e) { toast(e.message, 'err'); } }

async function combatFiles() {
  await combatLoad();
  const files = {}, notes = [];
  if (combatHeroCount()) {
    // a game pack's hero.json holds only what it changes (deep-merged over the engine's), so
    // its own file, or a fresh one, is patched, never a copy of the engine's whole handling
    const text = META.pack ? (await repoText('content/data/hero.json')) || '{\n}\n' : await repoText('data/hero.json');
    const out = heroPatch(text, COMBAT.work);
    if (out !== text) files['data/hero.json'] = out;
  }
  const acts = Object.fromEntries(Object.entries(COMBAT.work.actions).filter(([, a]) => Object.keys(a).length));
  if (Object.keys(acts).length) {
    const text = await repoText('data/player_actions.json'), out = actionsPatch(text, acts);
    if (out !== text) files['data/player_actions.json'] = out;
  }
  if (!Object.keys(files).length) throw new Error('В «Боёвке» нет изменений.');
  const list = [...HERO_SECTIONS.flatMap(s => Object.entries(COMBAT.work[s]).map(([k, v]) => `${s === 'stats' || s === 'feel' ? '' : s + '.'}${k} → ${fmtJson(v)}`)),
    ...Object.entries(acts).flatMap(([id, a]) => Object.entries(a).map(([k, v]) => `${id}.${k} → ${fmtJson(v)}`))];
  notes.push('Проверь в песочнице и парирование/приёмы в игре: тесты parry_test, techniques_test, traversal_moves_test, enemy_spacing_test прогонит CI.');
  return { files, notes, title: `Studio: hero handling (${list.length})`, body: 'Боёвка героя:\n' + list.map(l => '- `' + l + '`').join('\n') };
}

$('#combatBody').addEventListener('change', e => {
  const t = e.target;
  if (t.dataset.cb) {
    const key = t.dataset.cb, sub = t.dataset.cbSub, game = combatGame(key);
    let v = +t.value; if (!Number.isFinite(v)) return;
    if (sub !== undefined) {
      const cur = structuredClone(combatMine(key)), path = sub.split('.');
      let at = cur; for (const p of path.slice(0, -1)) at = at[p];
      at[path.at(-1)] = v; v = cur;
    }
    else if (Number.isInteger(game) && !String(game).includes('.')) v = Math.round(v);
    combatSet(key, v); renderCombat();
  } else if (t.dataset.cbMove) {
    combatSet('moves.' + t.dataset.cbMove, t.checked); renderCombat();
  } else if (t.dataset.cbAct) {
    const id = t.dataset.cbAct, k = t.dataset.cbKey, v = k === 'hit_frame' ? Math.max(0, Math.round(+t.value)) : +t.value;
    if (!Number.isFinite(v)) return;
    const a = COMBAT.work.actions[id] ||= {};
    if (sameDraft(v, COMBAT.data.actions[id][k])) delete a[k]; else a[k] = v;
    if (!Object.keys(a).length) delete COMBAT.work.actions[id];
    combatSave(); renderCombat();
  }
});
$('#combatBody').addEventListener('click', e => { const b = e.target.closest('[data-cb-reset]'); if (b) { combatSet(b.dataset.cbReset, combatGame(b.dataset.cbReset)); renderCombat(); } });
$('#combatBody').addEventListener('toggle', e => { if (e.target.open && e.target.dataset.cbGroup) COMBAT.open = e.target.dataset.cbGroup; }, true);
$('#combatReset').onclick = () => { if (!combatCount() || confirm('Вернуть всю боёвку как в игре?')) { COMBAT.work = combatBlank(); combatSave(); renderCombat(); } };
$('#combatSend').onclick = async () => {
  await sendToGame(combatFiles, 'workspace');
  if (sendToGame.last?.local) { COMBAT.data = null; WORLD.data = null; COMBAT.work = combatBlank(); combatSave(); await combatEnter(); }
};
// the hero as she set him, against a foe of her choice (data mode, like «Атаки»)
$('#combatSandbox').onclick = async () => {
  await attacksEnterData(); sandbox.actionMode = true; sandbox.from = 'combat'; sandbox.view.anim = '';
  sandbox.base = localStorage.getItem('ss_live_base') || 'possessed_villager';
  await sandboxOpen(); sandboxBaseSelect();
};
