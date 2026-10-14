/* Sprite Studio — what a night is made of beyond its rooms: the weapons (data/weapons, docs/WEAPONS.md,
 * scripts/combat/weapons.gd), the endings (data/endings, scripts/run/endings.gd) and the route of the nights
 * (data/game.json `rooms`, `nights`, `finale`; DataDoc.nights / all_rooms). Three tabs on js/gamedata.js's
 * STUDIO_TABS, drafts in WORLD.work like the rest; a file goes back in its own style (gdShaped), an untouched
 * part byte for byte. Each check mirrors scripts/tools/validate_data.gd (_check_weapon, _check_ending,
 * _check_finale, _check_game, _check_nights, _check_opening): change one, change the other. */
'use strict';

/* ---------- pure helpers (tests/campaign.test.js) ---------- */
const CP_PATHS = ['grace', 'temptation', 'will'];
const cpSame = (a, b) => JSON.stringify(a) === JSON.stringify(b);
// A JSON document written back in the shape it had: an untouched value is the very text it was; a changed one
// takes the old one's shape (one line or one child a line, a float's ".0"), a new one its sibling's (or `like`,
// another file of the same kind, for a file that does not exist yet). `force` rewrites even what did not change —
// the tests use it to prove the shapes are the files' own.
function gdShaped(old, value, opt = {}) {
  const text = old && old.trim() ? old : opt.like || '';
  let root = null; try { root = text.trim() ? jsonSpans(text) : null; } catch { root = null; }
  const nl = !old || old.endsWith('\n') ? '\n' : '';
  return cpShape(text, old && old.trim() ? root : null, old && old.trim() ? null : root, value, 0, !!opt.force, false) + nl;
}
function cpShape(text, node, like, v, level, force, inline) {
  const raw = n => text.slice(n.start, n.end), shape = node || like, pad = n => '  '.repeat(n);
  const container = v && typeof v === 'object';
  if (node && (!force || !container)) { try { if (cpSame(JSON.parse(raw(node)), v)) return raw(node); } catch {} }
  if (!container) {
    if (typeof v === 'number' && Number.isInteger(v) && shape?.type === 'literal' && /[.eE]/.test(shape.raw)) return v.toFixed(1);
    return JSON.stringify(v);
  }
  const isArr = Array.isArray(v), entries = isArr ? v.map((x, i) => [i, x]) : Object.entries(v).filter(([, x]) => x !== undefined);
  if (!entries.length) return isArr ? '[]' : '{}';
  const kind = isArr ? 'array' : 'object', same = shape?.type === kind;
  const kids = same ? (isArr ? shape.items : shape.members.map(m => m.value)) : [];
  // one line, or one child a line: as the shape was, or (no shape) one line unless a child is a container with something in it
  const multi = !inline && (same && kids.length ? raw(shape).includes('\n') : entries.some(([, x]) => x && typeof x === 'object' && Object.keys(x).length));
  const mine = node?.type === kind ? node : null;
  let parsed = null;
  const pick = (k, x) => {
    if (!same) return [null, null];
    if (!isArr) { const m = shape.members.find(m => m.key === k); return mine ? [m?.value || null, null] : [null, m?.value || null]; }
    if (mine && x && typeof x === 'object' && !Array.isArray(x) && x.id !== undefined) {
      parsed ||= mine.items.map(n => { try { return JSON.parse(raw(n)); } catch { return null; } });
      const j = parsed.findIndex(p => p && p.id === x.id);
      return j >= 0 ? [mine.items[j], null] : [null, mine.items[k] || mine.items[0] || null];
    }
    return mine ? [mine.items[k] || null, mine.items[k] ? null : mine.items[0] || null] : [null, shape.items[k] || shape.items[0] || null];
  };
  const out = entries.map(([k, x]) => { const [n, l] = pick(k, x); const s = cpShape(text, n, l, x, level + 1, force, !multi); return isArr ? s : JSON.stringify(k) + ': ' + s; });
  const [a, b] = isArr ? ['[', ']'] : ['{', '}'];
  return multi ? a + '\n' + out.map(s => pad(level + 1) + s).join(',\n') + '\n' + pad(level) + b : a + out.join(', ') + b;
}

const cpNum = v => typeof v === 'number' && isFinite(v);
// ctx: {weapon: {bounds, step_bounds, needs, animations, arcs}, icons: has(res), strings: has(key)}
function cpWeaponProblems(w, ctx) {
  const out = [], err = m => out.push(m), W = ctx.weapon, key = k => { if (!ctx.strings(k)) err(`нет строки ${k} в strings.csv — добавь её ниже`); };
  for (const f of ['id', 'name', 'description', 'icon', 'chain']) if (!(f in w)) err(`нет поля «${f}»`);
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(w.id ?? ''))) err('id: латиница, цифры и _ (не с цифры)');
  key(w.name); key(w.description);
  if (!ctx.icons(String(w.icon || ''))) err(`нет иконки ${w.icon || '—'}`);
  const bounded = (v, [lo, hi], label) => { if (!cpNum(v) || v < lo || v > hi) err(`${label} — число ${lo}…${hi}`); };
  const pair = (p, k, at) => {
    if (!Array.isArray(p) || p.length !== 2 || !p.every(cpNum)) return err(`${at}.${k} — два числа`);
    const [x, y] = p;
    if (k === 'hitbox' && (x < 8 || x > 96 || y < 8 || y > 64)) err(`${at}.hitbox — 8…96 в ширину и 8…64 в высоту`);
    if (k === 'offset' && (x < 0 || x > 60 || Math.abs(y) > 40)) err(`${at}.offset — 0…60 вперёд и не дальше 40 вверх или вниз`);
    if (k === 'slash_scale' && (x < 0.4 || x > 2 || y < 0.4 || y > 2)) err(`${at}.slash_scale — 0.4…2 по каждой оси`);
  };
  for (const [k, b] of Object.entries(W.bounds)) if (k in w) bounded(w[k], b, k);
  for (const k of ['hitbox', 'offset', 'slash_scale']) if (k in w) pair(w[k], k, 'оружие');
  const chain = w.chain;
  if (!Array.isArray(chain) || !chain.length || chain.length > 5) { err('цепь — от 1 до 5 ударов'); return out; }
  const own = w.id === 'sword';
  chain.forEach((s, i) => {
    const at = `удар ${i + 1}`;
    if (!s || typeof s !== 'object' || Array.isArray(s)) return err(`${at} — объект`);
    if (!W.animations.includes(s.animation)) err(`${at}: animation — поза Элиана: ${W.animations.join(', ')}`);
    if (!own) for (const k of W.needs) if (!(k in s)) err(`${at}: нужен «${k}» (своими числами героя падает только меч)`);
    for (const [k, b] of Object.entries(W.step_bounds)) if (k in s) bounded(s[k], b, `${at}.${k}`);
    if ('heavy' in s && typeof s.heavy !== 'boolean') err(`${at}.heavy — да или нет`);
    if ('arc' in s && !W.arcs.includes(s.arc)) err(`${at}.arc — одна из ${W.arcs.join(', ')}`);
    for (const k of ['hitbox', 'offset']) if (k in s) pair(s[k], k, at);
  });
  const moves = w.techniques ?? {};
  if (!moves || typeof moves !== 'object' || Array.isArray(moves)) err('techniques — объект приём → поправки');
  else for (const [m, o] of Object.entries(moves)) {
    if (!['lunge', 'cleave', 'sweep'].includes(m) || !o || typeof o !== 'object' || Array.isArray(o)) { err(`techniques.${m}: только lunge, cleave и sweep, каждый объектом`); continue; }
    for (const [k, v] of Object.entries(o)) {
      if (k === 'hitbox' || k === 'offset') pair(v, k, `techniques.${m}`);
      else if (k === 'multiplier') bounded(v, [0.2, 5], `techniques.${m}.multiplier`);
      else if (k in W.step_bounds) bounded(v, W.step_bounds[k], `techniques.${m}.${k}`);
      else err(`techniques.${m}: неизвестный ключ ${k}`);
    }
  }
  return out;
}
// Seconds a chain takes at attack_cooldown and what it deals (×damage): Weapons.chain_time / chain_damage.
function cpChainNumbers(w, hero) {
  const steps = w.chain?.length ? w.chain : [{ animation: 'attack' }, { animation: 'attack2' }, { animation: 'attack3' }];
  const rec = hero.combo_recovery || [0.45, 0.45, 1], mul = hero.combo_multipliers || [1, 1.1, 1.6], at = (a, i) => a[Math.min(i, a.length - 1)];
  const time = steps.reduce((t, s, i) => t + (hero.attack_cooldown ?? 0.8) * +(s.recovery ?? at(rec, i)), 0);
  const damage = steps.reduce((d, s, i) => d + +(s.multiplier ?? at(mul, i)), 0) * +(w.damage ?? 1);
  return { time, damage, per_second: time > 0 ? damage / time : 0 };
}

// ctx: {cutscenes: [ids], strings: has(key)}
function cpEndingProblems(e, ctx) {
  const out = [], err = m => out.push(m), key = k => { if (!ctx.strings(String(k ?? ''))) err(`нет строки ${k ?? '—'} в strings.csv — добавь её ниже`); };
  for (const f of ['id', 'name', 'description', 'line', 'cutscene', 'order', 'when']) if (!(f in e)) err(`нет поля «${f}»`);
  for (const f of ['name', 'description', 'line']) key(e[f]);
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(e.id ?? ''))) err('id называет подвиг и запись: латиница, цифры и _');
  if (!ctx.cutscenes.includes(e.cutscene)) err(`нет катсцены ${e.cutscene ?? '—'}`);
  if (!cpNum(e.order)) err('order — число (меньше — проверяется раньше)');
  const w = e.when;
  if (!w || typeof w !== 'object' || Array.isArray(w) || !Object.keys(w).length) { err('when — {path, lead, balanced, flags, unless}, не пустое'); return out; }
  for (const [k, v] of Object.entries(w)) {
    if (k === 'path') { if (!CP_PATHS.includes(v)) err(`when.path — один из ${CP_PATHS.join(', ')}`); }
    else if (k === 'lead' || k === 'balanced') { if (!cpNum(v) || Math.trunc(v) < 0 || Math.trunc(v) > 20) err(`when.${k} — целое число скрытых счётчиков, 0…20`); }
    else if (k === 'flags' || k === 'unless') { if (!Array.isArray(v)) err(`when.${k} — список флагов`); }
    else err(`when.${k} — не path, lead, balanced, flags или unless`);
  }
  if ('lead' in w && !('path' in w)) err('when.lead — отрыв чего? нужен path');
  if ('balanced' in w && 'path' in w) err('ровная ночь никуда не клонится: when.path и when.balanced не встречаются');
  return out;
}
// The whole set and the finale (_check_finale): one fallback, a finale room among the first night's rooms.
function cpEndingsProblems(list, game, ctx) {
  const out = [], falls = list.filter(e => e.fallback).map(e => e.id);
  if (list.length && falls.length !== 1) out.push(`запасной концовкой («fallback») должна быть ровно одна (сейчас: ${falls.join(', ') || 'ни одной'})`);
  if (!('finale' in game)) { if (list.length) out.push('концовки есть, а финала (game.json "finale") нет — негде кончаться кампании'); return out; }
  const f = game.finale;
  if (!f || typeof f !== 'object' || Array.isArray(f)) return [...out, 'finale — {room, cutscene, ends_campaign}'];
  if (!(game.rooms || []).includes(f.room)) out.push(`комната финала должна быть из первой ночи: ${f.room ?? '—'}`);
  if ('cutscene' in f && !ctx.cutscenes.includes(f.cutscene)) out.push(`нет катсцены финала ${f.cutscene}`);
  if ('ends_campaign' in f && typeof f.ends_campaign !== 'boolean') out.push('ends_campaign — да или нет');
  return out;
}
// Endings.choose: the first in order whose `when` holds, else the fallback. alignment {grace, temptation, will}, flags: Set
function cpDominant(a) { let best = 'will'; for (const p of ['grace', 'temptation']) if ((a[p] || 0) > (a[best] || 0)) best = p; return best; }
function cpLead(a) { const p = cpDominant(a); return Math.min(...CP_PATHS.filter(o => o !== p).map(o => (a[p] || 0) - (a[o] || 0))); }
function cpHolds(e, a, flags) {
  const w = e.when || {};
  if (!Object.keys(w).length) return false;
  if ('path' in w && cpDominant(a) !== String(w.path)) return false;
  if ('lead' in w && cpLead(a) < Math.trunc(w.lead)) return false;
  if ('balanced' in w && cpLead(a) > Math.trunc(w.balanced)) return false;
  if ((w.flags || []).some(f => !flags.has(String(f)))) return false;
  if ((w.unless || []).some(f => flags.has(String(f)))) return false;
  return true;
}
const cpEndingOrder = list => [...list].sort((a, b) => { const oa = Math.trunc(a.order ?? 99), ob = Math.trunc(b.order ?? 99); return oa !== ob ? oa - ob : String(a.id) < String(b.id) ? -1 : 1; });
function cpChoose(list, a, flags) {
  let fallback = '';
  for (const e of cpEndingOrder(list)) { if (cpHolds(e, a, flags)) return e.id; if (e.fallback && !fallback) fallback = e.id; }
  return fallback;
}

// DataDoc.nights: the first night is the game's own "rooms" and "opening", the rest "nights"
function cpNights(game) {
  return [{ id: '', rooms: game.rooms || [], opening: game.opening || {}, after_dawns: 0 }, ...(game.nights || []).filter(n => n && typeof n === 'object' && String(n.id ?? '') !== '')];
}
const cpOwner = game => { const out = {}; for (const n of cpNights(game)) for (const r of n.rooms || []) out[String(r)] ??= String(n.id); return out; };
// ctx: {scenes: has(res), forks: [{id, after, then, options}], cutscenes: [ids], dialogues: [ids]}
function cpRouteProblems(game, ctx) {
  const out = [], err = m => out.push(m), night = id => id ? `ночь «${id}»` : 'первая ночь';
  if (!(game.rooms || []).length) err('у первой ночи нет комнат');
  const seen = new Set();
  for (const r of [...cpNights(game).flatMap(n => n.rooms || []), game.practice_room || '']) {
    if (seen.has(r)) err(`${r} стоит дважды (комната — только в одной ночи и не во дворе)`);
    seen.add(r);
    if (!ctx.scenes(String(r))) err(`нет сцены ${r}`);
  }
  const ids = new Set(['']);
  cpNights(game).forEach((n, i) => {
    if (i > 0) {
      if (ids.has(String(n.id))) err(`ночь «${n.id}» дважды`);
      ids.add(String(n.id));
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(n.id))) err(`id ночи «${n.id}»: латиница, цифры и _ (сохранения и профиль хранят его)`);
      if (!Array.isArray(n.rooms) || !n.rooms.length) err(`${night(n.id)} без комнат`);
      if (!cpNum(n.after_dawns) || Math.trunc(n.after_dawns) < 1) err(`${night(n.id)}: after_dawns — 1 и больше (всегда открыта только первая ночь)`);
    }
    for (const [k, v] of Object.entries(n.opening || {})) {
      if (k === 'wake') { if (typeof v !== 'boolean') err(`${night(n.id)}: opening.wake — да или нет`); continue; }
      const dlg = k === 'intro' || k === 'last_fall';
      if (!(dlg ? ctx.dialogues : ctx.cutscenes).includes(String(v))) err(`${night(n.id)}: opening.${k} — нет ${dlg ? 'диалога' : 'катсцены'} «${v}»`);
    }
  });
  const owner = cpOwner(game);
  for (const f of ctx.forks || []) {
    const where = new Set([f.after, f.then, ...Object.values(f.options || {})].map(r => owner[String(r)] ?? '?'));
    if (where.size !== 1 || where.has('?')) err(`развилка ${f.id}: все её комнаты — в одной ночи`);
  }
  return out;
}
// Not the validator's, only sense: a fork's door must come before the ways it opens and where they join.
function cpRouteWarnings(game, forks) {
  const out = [];
  for (const n of cpNights(game)) {
    const at = r => (n.rooms || []).indexOf(r);
    for (const f of forks || []) {
      if (at(f.after) < 0) continue;
      const ways = Object.values(f.options || {});
      if (ways.some(r => at(r) >= 0 && at(r) < at(f.after)) || at(f.then) >= 0 && at(f.then) < at(f.after)) out.push(`развилка ${f.id}: пути и встреча стоят раньше её двери (${f.after.replace(/.*\//, '')})`);
      if (ways.some(r => at(r) > at(f.then))) out.push(`развилка ${f.id}: путь стоит после комнаты, где пути сходятся`);
    }
  }
  return out;
}
if (typeof module !== 'undefined') module.exports = { gdShaped, cpWeaponProblems, cpChainNumbers, cpEndingProblems, cpEndingsProblems, cpChoose, cpHolds, cpLead, cpDominant, cpNights, cpOwner, cpRouteProblems, cpRouteWarnings };

/* ---------- shared ---------- */
const CP_GAME = 'data/game.json';
const cp = { images: new Map(), ready: {} };
// every path of a folder: the game's, and a new one only a draft has
const cpFiles = dir => [...new Set([...Object.keys(WORLD.data.files), ...Object.keys(WORLD.work)])].filter(p => p.startsWith(dir) && gdDoc(p) !== undefined).sort();
const cpIds = dir => cpFiles(dir).flatMap(p => [].concat(gdDoc(p))).map(e => e && e.id).filter(Boolean);
const cpScene = r => String(r).replace(/^res:\/\/(content\/)?scenes\/rooms\//, '').replace(/\.tscn$/, '');
const cpOpt = (list, cur, none) => (none !== undefined ? `<option value=""${cur ? '' : ' selected'}>${esc(none)}</option>` : '') + [...new Set([...list, ...(cur ? [cur] : [])])].map(v => `<option value="${esc(v)}"${v === cur ? ' selected' : ''}>${esc(v)}</option>`).join('');
const cpWarn = list => list.map(p => `<div class="warn">${esc(p)}</div>`).join('');
// a file this studio would write next to the others of its folder: shaped like the first of them
async function cpText(p, merged, text, dir) {
  if (text && text.trim()) return gdShaped(text, merged);
  const sibling = cpFiles(dir).find(x => x !== p && WORLD.data.files[x]);
  return gdShaped('', merged, { like: sibling ? await repoText(sibling) : '' });
}
function cpImage(res) {
  let im = cp.images.get(res);
  if (!im) { im = new Image(); im.crossOrigin = 'anonymous'; im.onload = () => STUDIO_TABS[GD.tab]?.draw?.(); im.src = A(res); cp.images.set(res, im); }
  return im;
}
// the tab's own listeners, ahead of gamedata.js's (which still takes the strings, «→ В игру» and «↺ Как в игре»)
function cpListen(m, input, click) {
  if (cp.ready[m]) return; cp.ready[m] = true;
  const box = $('#gdLayout_' + m);
  const take = e => { if (e.target.closest('[data-cp]') && !e.target.dataset.gdStr) { e.stopImmediatePropagation(); input(e.target, e); } };
  box.addEventListener('input', take, true); box.addEventListener('change', take, true);
  box.addEventListener('click', e => { const b = e.target.closest('[data-cp-act]'); if (b) { e.stopImmediatePropagation(); e.preventDefault(); click(b.dataset.cpAct, b); } }, true);
}
function cpEdit(p, fn) { const doc = structuredClone(gdDoc(p)); fn(doc); gdPut(p, doc); }

/* ---------- «Оружие»: data/weapons ---------- */
const CP_WEAPONS = 'data/weapons/';
const CP_STEP_NUMS = ['multiplier', 'recovery', 'wind', 'knockback', 'stagger', 'animation_time', 'speed'];
const CP_STEP_LABEL = { multiplier: 'урон ×', recovery: 'отдых', wind: 'замах, с', knockback: 'отброс', stagger: 'оглушение, с', animation_time: 'длина позы, с', speed: 'скорость позы' };
const CP_WEAPON_LABEL = { damage: 'урон × (на всё)', backstab: 'удар в спину + (к ×2.5 героя)', poise: 'стойкость (доля раны, не взятая в замахе)', combo_window: 'окно цепи, с', pitch: 'высота звука', auto_reach: 'автоудар: досягаемость' };
function cpWeaponCtx() { return { weapon: GD.data.weapon, icons: r => GD.data.icons.includes(r), strings: gdHas }; }
function cpWeaponPath() { const files = cpFiles(CP_WEAPONS); return files.includes(GD.sel.weapon) ? GD.sel.weapon : files.find(p => p.endsWith('/sword.json')) || files[0]; }
// what a sword step left out: the hero's own (hero.json combo_*, player_actions.json attack…)
function cpHeroStep(i, anim) {
  const feel = gdDoc('data/hero.json')?.feel || {}, act = gdDoc('data/player_actions.json')?.actions?.[anim] || {}, at = (a, d) => (a || d)[Math.min(i, (a || d).length - 1)];
  return { multiplier: at(feel.combo_multipliers, [1, 1.1, 1.6]), recovery: at(feel.combo_recovery, [0.45, 0.45, 1]), knockback: act.knockback ?? 1, heavy: act.heavy ?? i === 2, animation_time: act.animation_time, stagger: act.stagger, hitbox: act.hitbox, offset: act.offset };
}
function renderWeapons() {
  const p = cpWeaponPath(); GD.sel.weapon = p;
  const w = gdDoc(p), ctx = cpWeaponCtx(), W = GD.data.weapon, inGame = !!WORLD.data.files[p], sword = w.id === 'sword';
  const hero = { ...(gdDoc('data/hero.json')?.feel || {}), attack_cooldown: gdDoc('data/hero.json')?.stats?.attack_cooldown ?? 0.8 };
  const sel = Math.min(GD.sel.wstep || 0, (w.chain || []).length - 1), n = cpChainNumbers(w, hero);
  $('#gdSide_weapons').innerHTML = `<div class="gdlist">${cpFiles(CP_WEAPONS).map(x => { const o = gdDoc(x); return `<button class="sm ${x === p ? 'on' : ''}" data-cp-act="pick" data-p="${esc(x)}">${cpWeaponProblems(o, ctx).length ? '⚠ ' : ''}${esc(gdStr(o.name) || o.id)}${WORLD.work[x] ? ' •' : ''}</button>`; }).join('')}</div>
    <div class="row" style="margin:0;gap:6px"><input id="cpNewWeapon" data-cp="new" placeholder="id нового оружия" class="grow"><button class="sm" data-cp-act="add" title="Копия выбранного под новым id">+ Копией</button>${inGame ? '' : '<button class="sm" data-cp-act="del">✕ Убрать новое</button>'}</div>
    <div class="muted">id <b>${esc(w.id)}</b> — имя файла, сохранений и подобранного; новое оружие получает его при создании</div>
    <label>Иконка<select data-cp="icon">${cpOpt(GD.data.icons, w.icon)}</select></label>
    <div class="card"><b>На каждый удар</b> <span class="muted">пусто — как у героя</span><div class="gdfields">
      ${Object.entries(W.bounds).map(([k, [lo, hi]]) => `<label title="${lo}…${hi}">${esc(CP_WEAPON_LABEL[k] || k)}<input type="number" step="any" min="${lo}" max="${hi}" data-cp="w.${k}" value="${w[k] ?? ''}" placeholder="—"></label>`).join('')}</div></div>
    <div class="card"><b>Досягаемость</b> <span class="muted">x, y; пусто — как у героя (удар 30×30 в 24, −4)</span><div class="gdfields">
      ${[['hitbox', 'зона удара (ш × в)'], ['offset', 'центр зоны (вперёд, вверх−)'], ['slash_scale', 'дуга удара ×']].map(([k, l]) => `<label>${l}<span class="row" style="margin:0;gap:4px">${[0, 1].map(j => `<input type="number" step="any" data-cp="pair.${k}" data-j="${j}" value="${w[k]?.[j] ?? ''}" placeholder="—">`).join('')}</span></label>`).join('')}</div></div>
    <label>Заметка (notes)<textarea data-cp="notes" rows="3">${esc(w.notes || '')}</textarea></label>
    ${gdStrFields(w.name, 'Название')}${gdStrFields(w.description, 'Описание')}`;
  const own = i => sword ? cpHeroStep(i, w.chain[i]?.animation) : {};
  $('#gdMain_weapons').innerHTML = `<canvas id="cpWeaponCanvas" class="gdstage" style="height:260px;flex:none"></canvas>
    <div class="muted">Цепь: ${(w.chain || []).length} ${sword ? '(меч — пустые числа берутся у героя: «Боёвка»)' : ''} · время цепи ${n.time.toFixed(2)} с · урон за цепь ×${n.damage.toFixed(2)} · ×${n.per_second.toFixed(2)} в секунду — как считает weapon_test.gd</div>
    <table class="gdtable"><tr><th></th><th>поза</th>${CP_STEP_NUMS.map(k => `<th title="${k}${W.step_bounds[k] ? ': ' + W.step_bounds[k].join('…') : ''}">${CP_STEP_LABEL[k]}</th>`).join('')}<th>тяжёлый</th><th>дуга</th><th></th></tr>
    ${(w.chain || []).map((s, i) => `<tr class="${i === sel ? 'on' : ''}"><td><button class="sm${i === sel ? ' on' : ''}" data-cp-act="step" data-i="${i}" title="Показать зону этого удара">${i + 1}</button></td>
      <td><select data-cp="s.animation" data-i="${i}">${cpOpt(W.animations, s.animation)}</select></td>
      ${CP_STEP_NUMS.map(k => `<td><input type="number" step="any" style="width:62px" data-cp="s.${k}" data-i="${i}" value="${s[k] ?? ''}" placeholder="${own(i)[k] ?? '—'}"></td>`).join('')}
      <td><select data-cp="s.heavy" data-i="${i}">${[['', sword ? `— (${own(i).heavy ? 'да' : 'нет'})` : '—'], ['true', 'да'], ['false', 'нет']].map(([v, l]) => `<option value="${v}"${String(s.heavy ?? '') === v ? ' selected' : ''}>${l}</option>`).join('')}</select></td>
      <td><select data-cp="s.arc" data-i="${i}">${cpOpt(W.arcs, s.arc, '—')}</select></td>
      <td><button class="sm" data-cp-act="step-up" data-i="${i}" title="Раньше в цепи">↑</button><button class="sm" data-cp-act="step-del" data-i="${i}">✕</button></td></tr>`).join('')}</table>
    <div class="row" style="gap:6px">${(w.chain || []).length < 5 ? '<button class="sm" data-cp-act="step-add">+ Удар в цепь</button>' : '<span class="muted">в цепи не больше пяти ударов</span>'}</div>
    <div class="card"><b>Приёмы</b> <span class="muted">поправки к выпаду (lunge), рассечению (cleave) и подсечке (sweep): multiplier 0.2…5, hitbox, offset и числа удара</span>
      ${['lunge', 'cleave', 'sweep'].map(m => `<label>${m}<textarea class="gdjson" rows="1" data-cp="tech" data-m="${m}" placeholder="{} — как у героя">${esc(w.techniques?.[m] ? JSON.stringify(w.techniques[m]) : '')}</textarea></label>`).join('')}</div>
    ${cpWarn(cpWeaponProblems(w, ctx))}
    <div class="note">Поза удара — кадры, которые у Элиана уже есть; новое оружие — это числа, не новый рисунок. Каждый удар идёт через Player._land_hits, так что дары, предметы и созвучия действуют на любое оружие. Найти его можно в золотом сундуке ("weapon": true), опробовать — на стойке тренировочного двора.</div>`;
  $('#gdBar_weapons').innerHTML = `<span class="muted grow">${esc(p)}</span>` + gdBar('weapons');
  drawWeapon();
}
function drawWeapon() {
  const c = $('#cpWeaponCanvas'); if (!c || GD.tab !== 'weapons') return;
  const w = gdDoc(cpWeaponPath()), i = Math.min(GD.sel.wstep || 0, (w.chain || []).length - 1), s = w.chain?.[i] || {};
  const hero = w.id === 'sword' ? cpHeroStep(i, s.animation) : {};
  const size = s.hitbox || w.hitbox || hero.hitbox || [30, 30], at = s.offset || w.offset || hero.offset || [24, -4], arc = w.slash_scale || [1, 1];
  const W = c.clientWidth || 640, H = 260; if (c.width !== W || c.height !== H) { c.width = W; c.height = H; }
  const x = c.getContext('2d'), k = Math.max(1, Math.floor(Math.min(W / 200, H / 90))), ox = W / 2 - 20 * k, oy = H * 0.72;
  x.imageSmoothingEnabled = false; x.fillStyle = '#16131c'; x.fillRect(0, 0, W, H); x.fillStyle = '#2a2433'; x.fillRect(0, oy + 15 * k, W, H);
  const im = cpImage(`res://assets/sprites/elian_${s.animation || 'idle'}.png`);
  if (im.complete && im.naturalWidth) { const n = Math.max(1, Math.floor(im.naturalWidth / 128)), f = Math.min(n - 1, Math.floor(n / 2)); x.drawImage(im, f * 128, 0, 128, 64, ox - 64 * k, oy + (-15 - 32) * k, 128 * k, 64 * k); }
  x.strokeStyle = 'rgba(120,200,255,.6)'; x.strokeRect(ox - 7 * k, oy - 15 * k, 14 * k, 30 * k);
  x.fillStyle = 'rgba(255,90,90,.25)'; x.strokeStyle = '#ff6a6a'; x.lineWidth = 2;
  x.fillRect(ox + (at[0] - size[0] / 2) * k, oy + (at[1] - size[1] / 2) * k, size[0] * k, size[1] * k); x.strokeRect(ox + (at[0] - size[0] / 2) * k, oy + (at[1] - size[1] / 2) * k, size[0] * k, size[1] * k);
  x.strokeStyle = s.arc === 'red' ? '#ff5050' : s.arc === 'gold' || s.arc === 'path' ? '#ffd75f' : '#f0f0ff'; x.lineWidth = (s.heavy ?? hero.heavy) ? 4 : 2;
  x.beginPath(); x.ellipse(ox + 22 * k, oy - 10 * k, 24 * arc[0] * k, 20 * arc[1] * k, 0, -Math.PI * 0.45, Math.PI * 0.45); x.stroke();
  x.fillStyle = '#cfd8e3'; x.font = '12px system-ui'; x.lineWidth = 1;
  x.fillText(`удар ${i + 1}: ${s.animation || '—'} · зона ${size.join('×')} в ${at.join(', ')} · дуга ×${arc.join('/')} (примерно)`, 8, 16);
  x.fillText('голубое — тело героя, красное — куда бьёт', 8, H - 8);
}
function cpWeaponInput(el, e) {
  const p = cpWeaponPath(), k = el.dataset.cp, i = +el.dataset.i, v = el.value;
  if (k === 'new' || e.type !== 'change') return;
  cpEdit(p, w => {
    if (k === 'icon') w.icon = v;
    else if (k === 'notes') { if (v.trim()) w.notes = v; else delete w.notes; }
    else if (k.startsWith('w.')) { const f = k.slice(2); if (v === '') delete w[f]; else w[f] = +v; }
    else if (k.startsWith('pair.')) { const f = k.slice(5), j = +el.dataset.j, other = el.parentElement.querySelectorAll('input')[1 - j].value;
      if (v === '' && other === '') delete w[f]; else { const pr = [...(w[f] || [0, 0])]; pr[j] = v === '' ? 0 : +v; w[f] = pr; } }
    else if (k === 'tech') { const m = el.dataset.m; let o;
      try { o = v.trim() ? JSON.parse(v) : null; } catch (err) { return toast('Не JSON: ' + err.message, 'err'); }
      const t = { ...(w.techniques || {}) }; if (o && Object.keys(o).length) t[m] = o; else delete t[m];
      if (Object.keys(t).length) w.techniques = t; else delete w.techniques; }
    else if (k.startsWith('s.')) { const f = k.slice(2), s = w.chain[i];
      if (f === 'animation') s.animation = v;
      else if (f === 'heavy') { if (v === '') delete s.heavy; else s.heavy = v === 'true'; }
      else if (f === 'arc') { if (v) s.arc = v; else delete s.arc; }
      else if (v === '') delete s[f]; else s[f] = +v; }
  });
  renderWeapons();
}
function cpWeaponClick(act, b) {
  const p = cpWeaponPath();
  if (act === 'pick') { GD.sel.weapon = b.dataset.p; GD.sel.wstep = 0; return renderWeapons(); }
  if (act === 'step') { GD.sel.wstep = +b.dataset.i; return renderWeapons(); }
  if (act === 'add') {
    const id = $('#cpNewWeapon').value.trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(id) || cpIds(CP_WEAPONS).includes(id)) return toast('Нужен новый id: латиница, цифры, _', 'err');
    const w = structuredClone(gdDoc(p)), up = id.toUpperCase(), np = `${CP_WEAPONS}${id}.json`;
    Object.assign(w, { id, name: `WEAPON_${up}`, description: `WEAPON_${up}_DESC` }); delete w.notes;
    // a copy of the sword gives every step its numbers: only the sword falls back on the hero's own
    if (gdDoc(p).id === 'sword') w.chain = w.chain.map((s, i) => { const h = cpHeroStep(i, s.animation); return { animation: s.animation, multiplier: h.multiplier, recovery: h.recovery, knockback: h.knockback, heavy: !!h.heavy }; });
    gdPut(np, w); for (const key of [w.name, w.description]) if (!gdHas(key)) gdSetStr(key, 'en', '');
    GD.sel.weapon = np; GD.sel.wstep = 0; return renderWeapons();
  }
  if (act === 'del') { if (WORLD.data.files[p]) return; delete WORLD.work[p]; gdPut(p, undefined); delete WORLD.work[p]; GD.sel.weapon = ''; return renderWeapons(); }
  if (act === 'step-add') { cpEdit(p, w => { const last = w.chain.at(-1) || { animation: 'attack' }; w.chain.push(structuredClone(last)); }); GD.sel.wstep = gdDoc(p).chain.length - 1; return renderWeapons(); }
  if (act === 'step-del') { if (gdDoc(p).chain.length <= 1) return toast('В цепи хотя бы один удар', 'err'); cpEdit(p, w => w.chain.splice(+b.dataset.i, 1)); GD.sel.wstep = 0; return renderWeapons(); }
  if (act === 'step-up') { const i = +b.dataset.i; if (i > 0) cpEdit(p, w => { [w.chain[i - 1], w.chain[i]] = [w.chain[i], w.chain[i - 1]]; }); GD.sel.wstep = Math.max(0, i - 1); return renderWeapons(); }
}
if (typeof STUDIO_TABS !== 'undefined') STUDIO_TABS.weapons = {
  label: 'Оружие', title: 'weapons', tip: 'Оружие героя: цепь ударов, досягаемость, урон, удар в спину, стойкость, приёмы (data/weapons)',
  paths: p => p.startsWith(CP_WEAPONS), strings: true,
  html: `<aside class="side lifeside" id="gdSide_weapons"></aside><main class="lifemain"><div class="lifebar" id="gdBar_weapons"></div><div id="gdMain_weapons" class="gdscroll"></div></main>`,
  text: (p, merged, text) => cpText(p, merged, text, CP_WEAPONS),
  problems() {
    const ctx = cpWeaponCtx(), ids = cpIds(CP_WEAPONS);
    return [...cpFiles(CP_WEAPONS).flatMap(p => cpWeaponProblems(gdDoc(p), ctx).map(x => `${gdDoc(p).id}: ${x}`)), ...(ids.includes('sword') ? [] : ['меч (sword) — первое оружие каждой ночи, без него нельзя'])];
  },
  render: renderWeapons, draw: drawWeapon,
  enter() { cpListen('weapons', cpWeaponInput, cpWeaponClick); renderWeapons(); },
};

/* ---------- «Концовки»: data/endings ---------- */
const CP_ENDINGS = 'data/endings/';
const CP_PATH_NAME = { grace: 'благодать', temptation: 'искушение', will: 'воля' };
function cpEndingCtx() { return { cutscenes: cpIds('data/cutscenes/'), strings: gdHas }; }
const cpEndingList = () => cpFiles(CP_ENDINGS).map(p => ({ p, e: gdDoc(p) }));
function renderEndings() {
  const list = cpEndingList(), ordered = cpEndingOrder(list.map(x => x.e)), ctx = cpEndingCtx(), game = gdDoc(CP_GAME) || {};
  const cur = list.find(x => x.p === GD.sel.ending) || list.find(x => x.e.id === ordered[0]?.id) || list[0];
  if (!cur) { $('#gdMain_endings').innerHTML = '<div class="muted">У игры нет концовок.</div>'; $('#gdBar_endings').innerHTML = gdBar('endings'); return; }
  GD.sel.ending = cur.p;
  const e = cur.e, w = e.when || {}, inGame = !!WORLD.data.files[cur.p];
  const files = Object.fromEntries([...new Set([...Object.keys(WORLD.data.files), ...Object.keys(WORLD.work)])].map(p => [p, gdDoc(p)]).filter(([, v]) => v !== undefined));
  const flags = gdFlags(files, { read: GD.data.flags_read_in_code, set: GD.data.flags_set_in_code, tests: GD.data.flags_for_tests });
  const known = Object.keys(flags).sort(), sim = GD.sel.esim ||= { grace: 0, temptation: 0, will: 0, flags: [] };
  const simFlags = [...new Set(list.flatMap(x => [...(x.e.when?.flags || []), ...(x.e.when?.unless || [])]))].sort();
  const chosen = cpChoose(list.map(x => x.e), sim, new Set(sim.flags));
  $('#gdSide_endings').innerHTML = `<div class="muted">Пробуются по порядку (order), первая, чьё «когда» выполнено, — та самая; если ни одна — запасная.</div>
    <div class="gdlist" style="flex-direction:column;flex-wrap:nowrap">${ordered.map(o => { const x = list.find(y => y.e === o); return `<button class="sm ${x.p === cur.p ? 'on' : ''}" data-cp-act="pick" data-p="${esc(x.p)}">${cpEndingProblems(o, ctx).length ? '⚠ ' : ''}${o.order ?? '?'}. ${esc(gdStr(o.name) || o.id)}${o.fallback ? ' ⚑' : ''}${WORLD.work[x.p] ? ' •' : ''}</button>`; }).join('')}</div>
    <div class="row" style="margin:0;gap:6px"><input id="cpNewEnding" data-cp="new" placeholder="id новой концовки" class="grow"><button class="sm" data-cp-act="add">+ Концовка</button></div>
    <div class="card"><b>Проверить ночь</b> <span class="muted">скрытые счётчики и флаги — какая концовка выпадет</span>
      <div class="gdfields">${CP_PATHS.map(pa => `<label>${CP_PATH_NAME[pa]}<input type="number" min="0" data-cp="sim" data-k="${pa}" value="${sim[pa]}"></label>`).join('')}</div>
      <div class="gdchips">${simFlags.map(f => `<label><input type="checkbox" data-cp="simflag" data-f="${esc(f)}"${sim.flags.includes(f) ? ' checked' : ''}>${esc(f)}</label>`).join('')}</div>
      <div>Ведёт ${esc(CP_PATH_NAME[cpDominant(sim)])}, отрыв ${cpLead(sim)} → <b>${esc(gdStr(list.find(x => x.e.id === chosen)?.e.name) || chosen || 'нет концовки')}</b></div></div>
    <div class="card"><b>Финал</b> <span class="muted">${esc(cpScene(game.finale?.room || '—'))} · ${esc(game.finale?.cutscene || '—')} · ${game.finale?.ends_campaign ? 'кампания кончается' : 'пока «продолжение следует»'}</span><div class="muted">Правится во вкладке «Ночи».</div></div>`;
  const flagRow = (k, label) => `<div><b>${label}</b> ${(w[k] || []).map(f => `<span class="badge">${esc(f)}${flags[f] && !flags[f].set.length ? ' ⛔' : ''} <a href="#" data-cp-act="flag-del" data-k="${k}" data-f="${esc(f)}">✕</a></span>`).join(' ') || '<span class="muted">—</span>'}
      <input list="cpFlags" data-cp="flag-add" data-k="${k}" placeholder="+ флаг" style="width:180px"></div>`;
  $('#gdMain_endings').innerHTML = `<datalist id="cpFlags">${known.map(f => `<option value="${esc(f)}">`).join('')}</datalist>
    <div class="row" style="gap:6px"><b class="grow">${esc(gdStr(e.name) || e.id)}</b><span class="muted">${esc(cur.p)}</span>${inGame ? '<span class="muted" title="id концовки — подвиг ending_<id> и запись в хронике">id навсегда</span>' : '<button class="sm" data-cp-act="del">✕ Убрать новую</button>'}</div>
    <div class="gdfields"><label>порядок (order)<input type="number" data-cp="order" value="${e.order ?? ''}"></label>
      <label>катсцена<select data-cp="cutscene">${cpOpt(ctx.cutscenes, e.cutscene)}</select></label>
      <label><span><input type="checkbox" data-cp="fallback"${e.fallback ? ' checked' : ''}> запасная (ни одна не подошла)</span></label></div>
    <div class="card"><b>Когда</b>
      <div class="gdfields"><label>ведущий путь<select data-cp="when.path">${[['', '— любой'], ...CP_PATHS.map(pa => [pa, CP_PATH_NAME[pa]])].map(([v, l]) => `<option value="${v}"${(w.path || '') === v ? ' selected' : ''}>${l}</option>`).join('')}</select></label>
        <label>отрыв не меньше (lead)<input type="number" min="0" max="20" data-cp="when.lead" value="${w.lead ?? ''}" placeholder="—"></label>
        <label>ровная ночь: отрыв не больше (balanced)<input type="number" min="0" max="20" data-cp="when.balanced" value="${w.balanced ?? ''}" placeholder="—"></label></div>
      ${flagRow('flags', 'нужны флаги')}${flagRow('unless', 'только без флагов')}
      <div class="muted">Флаги концовки — в карте сюжета («Сюжет»): ⛔ — флаг, который нигде не ставится, ветку не открыть.</div>
      <table class="gdtable"><tr><th>Флаг</th><th>Ставят</th></tr>${[...(w.flags || []), ...(w.unless || [])].map(f => `<tr><td>${esc(f)}</td><td class="muted">${esc(flags[f]?.set.join(', ') || '—')}</td></tr>`).join('')}</table></div>
    ${cpWarn([...cpEndingProblems(e, ctx), ...cpEndingsProblems(list.map(x => x.e), game, ctx)])}
    ${gdStrFields(e.name, 'Название')}${gdStrFields(e.description, 'Описание')}${gdStrFields(e.line, 'Строка на экране конца ночи')}
    <div class="note">Ни одна концовка не истинная; Бог не появляется на экране. Четвёртая хочет ровную ночь и все три версии казни Элиана — ни одну не подтверждать. Катсцены концовок берут только картины, у которых уже есть правило оживления.</div>`;
  $('#gdBar_endings').innerHTML = gdBar('endings');
  gdAutosize($('#gdMain_endings'));
}
function cpEndingInput(el, e) {
  const k = el.dataset.cp, v = el.value, p = GD.sel.ending;
  if (k === 'new') return;
  if (k === 'sim') { if (e.type === 'change') { GD.sel.esim[el.dataset.k] = Math.max(0, Math.trunc(+v || 0)); renderEndings(); } return; }
  if (k === 'simflag') { const s = new Set(GD.sel.esim.flags); if (el.checked) s.add(el.dataset.f); else s.delete(el.dataset.f); GD.sel.esim.flags = [...s]; return renderEndings(); }
  if (e.type !== 'change') return;
  if (k === 'fallback') {
    // exactly one fallback: taking it here lets go of it everywhere else
    if (el.checked) for (const x of cpEndingList()) if (x.p !== p && x.e.fallback) cpEdit(x.p, o => { delete o.fallback; });
    cpEdit(p, o => { if (el.checked) o.fallback = true; else delete o.fallback; }); return renderEndings();
  }
  cpEdit(p, o => {
    if (k === 'order') o.order = +v;
    else if (k === 'cutscene') o.cutscene = v;
    else if (k.startsWith('when.')) { const f = k.slice(5), w = o.when ||= {}; if (v === '') delete w[f]; else w[f] = f === 'path' ? v : Math.trunc(+v); }
    else if (k === 'flag-add') { const f = v.trim(); if (!f) return; const w = o.when ||= {}, l = w[el.dataset.k] ||= []; if (!l.includes(f)) l.push(f); }
  });
  renderEndings();
}
function cpEndingClick(act, b) {
  const p = GD.sel.ending;
  if (act === 'pick') { GD.sel.ending = b.dataset.p; return renderEndings(); }
  if (act === 'flag-del') { cpEdit(p, o => { const l = o.when[b.dataset.k].filter(f => f !== b.dataset.f); if (l.length) o.when[b.dataset.k] = l; else delete o.when[b.dataset.k]; }); return renderEndings(); }
  if (act === 'add') {
    const id = $('#cpNewEnding').value.trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(id) || cpIds(CP_ENDINGS).includes(id)) return toast('Нужен новый id: латиница, цифры, _', 'err');
    const up = id.toUpperCase(), np = `${CP_ENDINGS}${id}.json`, last = Math.max(0, ...cpEndingList().map(x => +x.e.order || 0));
    const e = { id, name: `ENDING_${up}`, description: `ENDING_${up}_DESC`, line: `ENDING_${up}_LINE`, cutscene: cpEndingList()[0]?.e.cutscene || '', order: last + 1, when: { path: 'grace', lead: 2 } };
    gdPut(np, e); for (const key of [e.name, e.description, e.line]) if (!gdHas(key)) gdSetStr(key, 'en', '');
    GD.sel.ending = np; return renderEndings();
  }
  if (act === 'del') { if (WORLD.data.files[p]) return; gdPut(p, undefined); delete WORLD.work[p]; GD.sel.ending = ''; return renderEndings(); }
}
if (typeof STUDIO_TABS !== 'undefined') STUDIO_TABS.endings = {
  label: 'Концовки', title: 'endings', tip: 'Концовки: порядок, когда какая выпадает (путь и отрыв, ровная ночь, флаги), запасная, катсцена, слова (data/endings)',
  paths: p => p.startsWith(CP_ENDINGS), strings: true,
  html: `<aside class="side lifeside" id="gdSide_endings"></aside><main class="lifemain"><div class="lifebar" id="gdBar_endings"></div><div id="gdMain_endings" class="gdscroll"></div></main>`,
  text: (p, merged, text) => cpText(p, merged, text, CP_ENDINGS),
  problems() { const ctx = cpEndingCtx(), list = cpEndingList().map(x => x.e); return [...list.flatMap(e => cpEndingProblems(e, ctx).map(x => `${e.id}: ${x}`)), ...cpEndingsProblems(list, gdDoc(CP_GAME) || {}, ctx)]; },
  render: renderEndings,
  enter() { cpListen('endings', cpEndingInput, cpEndingClick); renderEndings(); },
};

/* ---------- «Ночи»: data/game.json rooms, nights, finale ---------- */
function cpRouteCtx() {
  return { scenes: r => GD.data.scenes.includes(r), forks: cpFiles('data/forks/').flatMap(p => [].concat(gdDoc(p))), cutscenes: cpIds('data/cutscenes/'), dialogues: cpIds('data/dialogues/') };
}
// the night's rooms live in two places: "rooms" for the first, nights[i].rooms for the rest
function cpNightRooms(game, id) { return id ? (game.nights.find(n => n.id === id)?.rooms || []) : game.rooms; }
function cpEditGame(fn) { cpEdit(CP_GAME, fn); renderRoute(); }
function renderRoute() {
  const game = gdDoc(CP_GAME) || {}, nights = cpNights(game), ctx = cpRouteCtx();
  const cur = nights.find(n => n.id === GD.sel.night) || nights[0]; GD.sel.night = cur.id;
  const owner = cpOwner(game), forks = ctx.forks, rests = new Set(cpFiles('data/rest_points/').flatMap(p => [].concat(gdDoc(p))).map(r => r.id));
  const place = Object.fromEntries(cpFiles('data/chapters/').flatMap(p => [].concat(gdDoc(p))).flatMap(c => (c.rooms || []).map(r => [cpScene(r), gdStr(c.title) || c.id])));
  const name = n => n.id ? `«${n.id}»` : 'Первая ночь', label = id => id === '' ? 'первая' : id ?? '—';
  const loose = GD.data.scenes.filter(r => !(r in owner) && r !== game.practice_room);
  $('#gdSide_route').innerHTML = `<div class="gdlist" style="flex-direction:column;flex-wrap:nowrap">${nights.map(n => `<button class="sm ${n.id === cur.id ? 'on' : ''}" data-cp-act="pick" data-id="${esc(n.id)}">${esc(name(n))} <span class="muted">${(n.rooms || []).length} комнат${n.id ? ` · после ${n.after_dawns} рассветов` : ' · открыта всегда'}</span></button>`).join('')}</div>
    <div class="row" style="margin:0;gap:6px"><input id="cpNewNight" data-cp="new" placeholder="id новой ночи" class="grow"><button class="sm" data-cp-act="add">+ Ночь</button></div>
    <div class="card"><b>${esc(name(cur))}</b>
      ${cur.id ? `<label>после скольких рассветов открывается (after_dawns)<input type="number" min="1" data-cp="dawns" value="${cur.after_dawns ?? ''}"></label>` : '<div class="muted">Первая ночь — rooms и opening самой игры, она открыта всегда.</div>'}
      <label><span><input type="checkbox" data-cp="wake"${cur.opening?.wake === false ? '' : ' checked'}> встаёт из могилы (иначе входит на ногах)</span></label>
      ${[['prologue', 'пролог', 'c'], ['prologue_short', 'короткий пролог', 'c'], ['intro', 'вступление', 'd'], ['last_fall', 'там, где пал прошлой ночью', 'd']].map(([k, l, t]) => `<label>${l} <span class="muted">${k}</span><select data-cp="open" data-k="${k}">${cpOpt(t === 'c' ? ctx.cutscenes : ctx.dialogues, cur.opening?.[k] || '', '—')}</select></label>`).join('')}
      ${cur.id && !(cur.rooms || []).length ? '<button class="sm" data-cp-act="night-del">✕ Убрать пустую ночь</button>' : ''}</div>
    <div class="card"><b>Финал</b> <span class="muted">комната первой ночи, после которой кончается кампания</span>
      <label>комната<select data-cp="finale.room">${cpOpt(game.rooms.map(String), game.finale?.room || '', '— нет финала')}</select></label>
      <label>катсцена перед концовкой<select data-cp="finale.cutscene">${cpOpt(ctx.cutscenes, game.finale?.cutscene || '', '—')}</select></label>
      <label><span><input type="checkbox" data-cp="finale.ends"${game.finale?.ends_campaign ? ' checked' : ''}> кампания здесь кончается (иначе рассвет и «продолжение следует»)</span></label></div>`;
  const rooms = cur.rooms || [];
  $('#gdMain_route').innerHTML = `<div class="muted" style="margin:4px 0">${esc(name(cur))}: комнаты в порядке игры. Номер — Route.step; развилка ведёт в один из путей, оба сходятся в одной комнате.</div>
    <table class="gdtable"><tr><th>#</th><th>Комната</th><th>Место</th><th></th><th></th></tr>
    ${rooms.map((r, i) => { const f = forks.find(x => x.after === r), way = forks.find(x => Object.values(x.options || {}).includes(r));
      return `<tr><td>${i + 1}</td><td><b>${esc(cpScene(r))}</b>${rests.has(cpScene(r)) ? ' <span title="привал">✚</span>' : ''}${game.finale?.room === r ? ' <span title="финал">🏁</span>' : ''}
        ${f ? `<div class="gdfork">⑂ ${esc(f.id)}: ${Object.keys(f.options || {}).map(esc).join(' / ')} → ${esc(cpScene(f.then))}</div>` : ''}${way ? `<div class="muted">путь развилки ${esc(way.id)}</div>` : ''}</td>
        <td class="muted">${esc(place[cpScene(r)] || '—')}</td>
        <td><button class="sm" data-cp-act="up" data-i="${i}" title="Раньше">↑</button><button class="sm" data-cp-act="down" data-i="${i}" title="Позже">↓</button><button class="sm" data-cp-act="out" data-i="${i}" title="Убрать из ночи (сцена остаётся)">✕</button></td>
        <td><select data-cp="move" data-i="${i}"><option value="">в другую ночь…</option>${nights.filter(n => n.id !== cur.id).map(n => `<option value="${esc(n.id || '@first')}">${esc(name(n))}</option>`).join('')}</select></td></tr>`; }).join('')}</table>
    <label>+ комната в эту ночь<select data-cp="add-room"><option value="">—</option>${loose.map(r => `<option value="${esc(r)}">${esc(cpScene(r))}</option>`).join('')}</select></label>
    ${loose.length ? `<div class="muted">Сцены вне всех ночей: ${esc(loose.map(cpScene).join(', '))}</div>` : ''}
    ${cpWarn(cpRouteProblems(game, ctx))}${cpRouteWarnings(game, forks).map(w => `<div class="muted">⚠ ${esc(w)}</div>`).join('')}
    <div class="card"><b>Какой ночи комната</b><table class="gdtable"><tr><th>Комната</th><th>Ночь</th><th>Место</th></tr>
      ${GD.data.scenes.map(r => `<tr><td>${esc(cpScene(r))}</td><td class="muted">${r === game.practice_room ? 'тренировочный двор' : esc(label(owner[r]))}</td><td class="muted">${esc(place[cpScene(r)] || '')}</td></tr>`).join('')}</table></div>
    <div class="note">Новая комната в ночи требует правила оживления (data/backdrops.json) и места в data/chapters — валидатор это проверит. Развилка не может переходить из ночи в ночь. Карта главы (Пауза → Карта) и номер комнаты на экране идут за этим порядком.</div>`;
  $('#gdBar_route').innerHTML = `<span class="muted grow">${esc(CP_GAME)}: rooms · nights · finale</span>` + gdBar('route');
}
function cpRouteInput(el, e) {
  if (e.type !== 'change') return;
  const k = el.dataset.cp, v = el.value, id = GD.sel.night, i = +el.dataset.i;
  const night = g => id ? g.nights.find(n => n.id === id) : null;
  if (k === 'new') return;
  if (k === 'dawns') return cpEditGame(g => { night(g).after_dawns = Math.max(1, Math.trunc(+v || 1)); });
  if (k === 'wake' || k === 'open') return cpEditGame(g => {
    const n = night(g), o = { ...((n ? n.opening : g.opening) || {}) };
    if (k === 'wake') { if (el.checked) delete o.wake; else o.wake = false; } else if (v) o[el.dataset.k] = v; else delete o[el.dataset.k];
    if (n) { if (Object.keys(o).length) n.opening = o; else delete n.opening; } else g.opening = o;
  });
  if (k === 'finale.room') return cpEditGame(g => { if (!v) delete g.finale; else g.finale = g.finale ? { ...g.finale, room: v } : { room: v, ends_campaign: false }; });
  if (k === 'finale.cutscene') return cpEditGame(g => { if (!g.finale) return toast('Сначала комната финала', 'err'); if (v) g.finale.cutscene = v; else delete g.finale.cutscene; });
  if (k === 'finale.ends') return cpEditGame(g => { if (!g.finale) return toast('Сначала комната финала', 'err'); g.finale.ends_campaign = el.checked; });
  if (k === 'add-room' && v) return cpEditGame(g => { cpNightRooms(g, id).push(v); });
  if (k === 'move' && v) {
    const to = v === '@first' ? '' : v;
    return cpEditGame(g => { const from = cpNightRooms(g, id), [r] = from.splice(i, 1); cpNightRooms(g, to).push(r); });
  }
}
function cpRouteClick(act, b) {
  const id = GD.sel.night, i = +b.dataset.i;
  if (act === 'pick') { GD.sel.night = b.dataset.id; return renderRoute(); }
  if (act === 'up' || act === 'down') return cpEditGame(g => { const l = cpNightRooms(g, id), j = act === 'up' ? i - 1 : i + 1; if (j >= 0 && j < l.length) [l[i], l[j]] = [l[j], l[i]]; });
  if (act === 'out') {
    const g = gdDoc(CP_GAME), r = cpNightRooms(g, id)[i];
    if (g.finale?.room === r) return toast('Это комната финала: сначала перенеси финал', 'err');
    return cpEditGame(x => { cpNightRooms(x, id).splice(i, 1); });
  }
  if (act === 'add') {
    const nid = $('#cpNewNight').value.trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(nid) || cpNights(gdDoc(CP_GAME)).some(n => n.id === nid)) return toast('Нужен новый id ночи: латиница, цифры, _', 'err');
    GD.sel.night = nid;
    return cpEditGame(g => { const last = (g.nights || []).reduce((m, n) => Math.max(m, +n.after_dawns || 0), 0); (g.nights ||= []).push({ id: nid, after_dawns: last + 1, opening: { wake: false }, rooms: [] }); });
  }
  if (act === 'night-del') { GD.sel.night = ''; return cpEditGame(g => { g.nights = g.nights.filter(n => n.id !== id); if (!g.nights.length) delete g.nights; }); }
}
if (typeof STUDIO_TABS !== 'undefined') STUDIO_TABS.route = {
  label: 'Ночи', title: 'nights and route', tip: 'Ночи игры: какие комнаты и в каком порядке, какой ночи комната, как ночь открывается, финал (data/game.json)',
  paths: p => p === CP_GAME, strings: false,
  html: `<aside class="side lifeside" id="gdSide_route"></aside><main class="lifemain"><div class="lifebar" id="gdBar_route"></div><div id="gdMain_route" class="gdscroll"></div></main>`,
  text: (p, merged, text) => gdShaped(text, merged),
  problems() { const game = gdDoc(CP_GAME) || {}, ctx = cpRouteCtx(); return [...cpRouteProblems(game, ctx), ...cpEndingsProblems(cpEndingList().map(x => x.e), game, cpEndingCtx())]; },
  render: renderRoute,
  enter() { cpListen('route', cpRouteInput, cpRouteClick); renderRoute(); },
};
if (typeof document !== 'undefined' && typeof gdInit === 'function') gdInit();
