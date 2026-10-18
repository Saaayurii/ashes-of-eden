/* Sprite Studio — the game's own tables that had no tab: the hero's cloaks (data/skins), every string in four
 * languages (localization/strings.csv), music and ambience (tools/audio/music_manifest.json → data/music/playlists.json,
 * data/ambience.json, a room's `music` in tools/rooms/studio_rooms.json), the run's balance and the deeds
 * (data/items, relics, resonances, omens, vials, affixes, achievements), the chapter's story map (chapters, forks,
 * notes, every flag both ways) and the rest points and chests on the room map.
 * The data files are drafts in WORLD.work (js/world.js), so «Поведение» and the workspace see the same edits;
 * strings and the music manifest are drafts of their own. Each check here mirrors scripts/tools/validate_data.gd:
 * change one, change the other. import/gamedata.json comes from build_data.py. */
'use strict';

const GD_LOCALES = ['en', 'ru', 'uk', 'zh_CN'];
const GD = { data: null, strings: {}, music: {}, zh: null, tab: '', sel: {}, pic: null, raf: 0, audio: null };
/* A tab: {label, title, enter, render, paths(p) → bool, strings?, music?, problems?, revert?, extraFiles?}; setMode, undo and
 * the workspace ask here. `revert` undoes only the tab's own part of a file it shares (studio_rooms.json is three tabs');
 * `extraFiles` adds what is not a data file (an uploaded picture) to a send. */
const STUDIO_TABS = {};

/* ---------- pure helpers (tests/gamedata.test.js) ---------- */
// A data file as the game keeps it: a list keeps every untouched entry as the very text it was, and writes a new
// or changed one on one line (the run tables are one line an entry); an object is patched key by key.
function gdText(old, value) {
  try { return gdTextKept(old, value); } catch { return JSON.stringify(value, null, 2) + (old.endsWith('\n') ? '\n' : ''); }
}
function gdTextKept(old, value) {
  const was = JSON.parse(old), nl = old.endsWith('\n') ? '\n' : '';
  if (Array.isArray(value) && Array.isArray(was)) {
    const raws = jsonItems(old, []), at = new Map(was.map((x, i) => [x && x.id !== undefined ? 'id:' + x.id : 'i:' + i, i]));
    // a file written by json.dump(indent=2) stays so; one written an entry a line stays one line an entry
    const pretty = raws.length > 0 && /^[[{]\n/.test(raws[0].raw), fresh = x => pretty ? pyJson(x, 1) : fmtJson(x);
    const lines = value.map((x, i) => { const j = at.get(x && x.id !== undefined ? 'id:' + x.id : 'i:' + i); return j !== undefined && sameDraft(was[j], x) ? raws[j].raw : fresh(x); });
    return lines.length ? '[\n' + lines.map(l => '  ' + l).join(',\n') + '\n]' + nl : '[]' + nl;
  }
  if (value && typeof value === 'object' && !Array.isArray(value) && was && typeof was === 'object' && !Array.isArray(was)) {
    const changes = {};
    for (const k of new Set([...Object.keys(was), ...Object.keys(value)])) if (!sameDraft(was[k], value[k])) changes[k] = value[k];
    return Object.keys(changes).length ? patchJson(old, [], changes) : old;
  }
  return JSON.stringify(value, null, 2) + nl;
}
// Python's json.dump(indent=n): ASCII only, the same spacing JSON.stringify gives
const gdPyDump = (v, indent) => JSON.stringify(v, null, indent).replace(/[\u007f-￿]/g, c => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
// tools/audio/fetch_music.py: the hand-made moods (EXISTING) first, then each manifest track in the moods it names
function gdPlaylists(existing, tracks) {
  const out = Object.fromEntries(Object.entries(existing).map(([k, v]) => [k, [...v]]));
  for (const t of tracks) for (const name of t.playlists || []) (out[name] ||= []).push(t.slug);
  return out;
}
/* data/skins → the shader's skin() (assets/shaders/alignment_marks.gdshader), one pixel at a time */
function gdRgb2hsv(r, g, b) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn; let h = 0;
  if (d > 1e-10) { h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h /= 6; if (h < 0) h += 1; }
  return [h, mx > 1e-10 ? d / mx : 0, mx];
}
function gdHsv2rgb(h, s, v) {
  const f = n => { const k = (n + h * 6) % 6; return v - v * s * Math.max(0, Math.min(k, 4 - k, 1)); };
  return [f(5), f(3), f(1)];
}
const gdSmooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
function gdSkinPixel(rgb, skin) {
  const cloakSpec = skin.cloak || {}, tint = gdHex(skin.armor || '#ffffff');
  const [h, s, v] = gdRgb2hsv(...rgb), red = Math.max(gdSmooth(0.07, 0.03, h), gdSmooth(0.90, 0.95, h)), cloak = red * gdSmooth(0.28, 0.45, s);
  const dyed = gdHsv2rgb(+(cloakSpec.hue ?? 0), Math.min(1, Math.max(0, s * +(cloakSpec.saturation ?? 1))), Math.min(1, Math.max(0, v * +(cloakSpec.value ?? 1))));
  return rgb.map((c, i) => c * tint[i] * (1 - cloak) + dyed[i] * cloak);
}
const gdHex = h => { const m = /^#?([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(String(h)); return m ? [0, 2, 4].map(i => parseInt(m[1].slice(i, i + 2), 16) / 255) : [1, 1, 1]; };
/* every flag both ways, as _check_story_flags collects them: {flag: {set: [where], read: [where]}} */
function gdFlags(files, code = {}) {
  const out = {}, put = (flag, how, where) => { const f = out[String(flag)] ||= { set: [], read: [] }; if (!f[how].includes(where)) f[how].push(where); };
  const entries = (path, doc) => Array.isArray(doc) ? doc : doc && typeof doc === 'object' && doc.id ? [doc] : [];
  for (const [path, doc] of Object.entries(files)) {
    for (const e of entries(path, doc)) {
      const where = path.replace(/^data\//, '').replace(/\.json$/, '') + '/' + (e.id ?? '?');
      if (path.startsWith('data/dialogues/')) for (const [nid, node] of Object.entries(e.nodes || {})) {
        for (const b of node.branches || []) if (b.flag !== undefined) put(b.flag, 'read', `${where}#${nid}`);
        for (const c of node.choices || []) for (const f of c.effect?.set_flags || []) put(f, 'set', `${where}#${nid}`);
      }
      if (path.startsWith('data/cutscenes/')) for (const step of e.steps || []) for (const k of ['if', 'unless']) if (step[k] !== undefined) for (const f of [].concat(step[k])) put(f, 'read', where);
      if (path.startsWith('data/props/')) { if (e.requires_flag !== undefined) put(e.requires_flag, 'read', where); for (const f of e.effect?.set_flags || []) put(f, 'set', where); }
      if (path.startsWith('data/abilities/')) for (const f of e.alignment?.set_flags || []) put(f, 'set', where);
      if (path.startsWith('data/endings/')) for (const k of ['flags', 'unless']) for (const f of [].concat(e.when?.[k] || [])) put(f, 'read', where);
    }
  }
  for (const f of code.read || []) put(f, 'read', 'scripts/');
  for (const f of code.set || []) put(f, 'set', 'scripts/');
  for (const f of code.tests || []) { put(f, 'set', 'a test'); put(f, 'read', 'a test'); }
  // FLAGS_AWAITED: the campaign's end reads them, a chapter still to come will write them
  for (const f of code.awaited || []) if (!out[f]?.set.length) put(f, 'set', 'a chapter still to come');
  return out;
}
/* validate_data.gd, entry by entry: what the validator would refuse ({error}) or only say ({warn}) */
const GD_RULES = {
  achievements: ['nights', 'wins', 'total_kills', 'kills', 'known', 'notes', 'items', 'affixes', 'moves', 'deeds', 'fast', 'endings'],
  vials: ['flasks', 'enemy_damage', 'enemy_hp', 'promote_chance', 'rest_heal', 'promote'],
  omens: ['essence', 'ash', 'flasks', 'enemy_damage', 'enemy_hp', 'skill_cooldown', 'enemy_sight', 'promote_chance', 'rest_heal', 'promote', 'dark', 'lamp_price'],
  affixes: ['hp', 'damage', 'speed', 'cooldown', 'armor'],
  skins: ['nights', 'total_kills', 'kills'],
};
const GD_REQUIRED = {
  items: ['id', 'name', 'description', 'rarity', 'icon', 'effects'], skins: ['id', 'name', 'description', 'unlock'],
  achievements: ['id', 'name', 'description', 'unlock'], resonances: ['id', 'name', 'description', 'needs', 'effects'],
  vials: ['id', 'tier', 'name', 'description', 'rules'], relics: ['id', 'name', 'description', 'cost', 'effects'],
  omens: ['id', 'name', 'description', 'rules'], affixes: ['id', 'name', 'color', 'mods'], rest_points: ['id', 'at'],
};
// ctx: {stats, item_stats, techniques, counters, enemies (id → boss?), gifts (id → path), relics: [ids], strings: has(key), tiers: [tier of the others]}
function gdProblems(kind, e, ctx) {
  const out = [], err = m => out.push(m), num = v => typeof v === 'number' && isFinite(v), key = k => { if (k !== undefined && !ctx.strings(k)) err(`нет строки ${k} в strings.csv — добавь её во вкладке «Тексты»`); };
  for (const f of GD_REQUIRED[kind] || []) if (!(f in e)) err(`нет поля «${f}»`);
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(e.id ?? ''))) err('id: латиница, цифры и _ (не с цифры)');
  if (kind !== 'rest_points' && kind !== 'affixes') { key(e.name); key(e.description); }
  if (kind === 'affixes') key(e.name);
  const stats = (effects, allowed, label) => { for (const f of effects || []) if (f.type !== 'stat' || !allowed.includes(f.stat)) err(`${label}: ${f.stat || f.type}`); else if (!['add', 'mul'].includes(f.op || 'add')) err('op — add или mul'); };
  if (kind === 'items') {
    if (!['common', 'rare'].includes(e.rarity)) err('rarity — common или rare');
    stats(e.effects, ctx.item_stats, 'предмет меняет только механику из ITEM_STATS');
  } else if (kind === 'relics') {
    if (!(+e.cost > 0)) err('реликвия стоит пепла (cost > 0)');
    if (String(e.id).startsWith('early_')) err('early_-реликвии делаются из поздних даров в коде');
    for (const f of e.effects || []) if (f.type === 'stat' ? !ctx.stats.includes(f.stat) : f.type !== 'reroll') err(`эффект реликвии — stat из BASE_STATS или reroll: ${f.stat || f.type}`);
    if (e.needs !== undefined && !ctx.relics.includes(e.needs)) err(`needs не называет реликвию: ${e.needs}`);
  } else if (kind === 'resonances') {
    const n = e.needs || {};
    if ('path' in n) { const offered = Object.values(ctx.gifts).filter(p => p === n.path).length;
      if (!['grace', 'temptation', 'will'].includes(n.path)) err('needs.path — grace, temptation или will');
      else if (!(+n.count >= 2 && +n.count <= offered)) err(`needs.count — 2…${offered} (столько даров у ${n.path})`); }
    else if ('gifts' in n) { const paths = new Set(); for (const g of n.gifts || []) { if (!(g in ctx.gifts)) err(`needs.gifts: нет дара ${g}`); else paths.add(ctx.gifts[g]); }
      if ((n.gifts || []).length < 2 || paths.size < 2) err('пара даров должна пересекать пути (внутри пути — счёт)'); }
    else err('needs — {path, count} или {gifts}');
    stats(e.effects, ctx.stats, 'эффект созвучия — stat из BASE_STATS');
    if (!(e.effects || []).length) err('созвучие, которое ничего не делает');
  } else if (kind === 'vials') {
    if (!(e.tier >= 1 && e.tier <= 5) || (ctx.tiers || []).includes(e.tier)) err('tier — 1…5, каждый по разу');
    if (+(e.ash ?? 1) < 1) err('чаша не платит меньше простой ночи (ash ≥ 1)');
    const r = e.rules || {};
    for (const k of Object.keys(r)) if (!GD_RULES.vials.includes(k)) err(`rules.${k} — не правило чаш`);
    for (const [from, to] of Object.entries(r.promote || {})) if (!(from in ctx.enemies) || !(to in ctx.enemies)) err(`promote ${from} → ${to}: нет такого врага`);
    if (+(r.promote_chance ?? 0) > 1 || +(r.rest_heal ?? 1) <= 0) err('promote_chance — 0…1, rest_heal больше 0');
  } else if (kind === 'omens') {
    const r = e.rules || {}; let helps = false, hurts = false;
    for (const [k, v] of Object.entries(r)) {
      if (k === 'essence' || k === 'ash') { helps ||= v > 1; hurts ||= v < 1; }
      else if (k === 'flasks') { helps ||= v > 0; hurts ||= v < 0; }
      else if (['enemy_damage', 'enemy_hp', 'skill_cooldown', 'enemy_sight'].includes(k)) { hurts ||= v > 1; helps ||= v < 1; }
      else if (k === 'promote_chance') { hurts ||= v > 0; if (v > 1) err('promote_chance — 0…1'); }
      else if (k === 'rest_heal') { hurts ||= v < 1; if (v <= 0) err('rest_heal больше 0'); }
      // chapter V (docs/CHAPTER5.md §7): the sting, the cloud, the fruit — as validate_data.gd's _check_omen
      else if (k === 'torment') { hurts ||= v > 1; helps ||= v < 1; if (!(v > 0 && v <= 3)) err('torment — множитель длины мучения, 0…3'); }
      else if (k === 'swarm') { hurts ||= v > 0; helps ||= v < 0; if (Math.abs(v) > 6) err('swarm — −6…6 саранчи на рой'); }
      else if (k === 'fruit_heal') { helps ||= v > 1; hurts ||= v < 1; if (!(v > 0 && v <= 3)) err('fruit_heal — множитель лечения плода, 0…3'); }
      else if (k === 'surfeit_per_fruit') { hurts ||= v > 1; if (!(v >= 1 && v <= 3)) err('surfeit_per_fruit — 1…3'); }
      else if (k === 'tether_length') { hurts ||= v > 1; helps ||= v < 1; if (v < 1 || v > 2) err('tether_length — 1…2'); }  // глава VI: цепь длиннее
      else if (k === 'dark' || k === 'lamp_price') { hurts ||= v > 1; helps ||= v < 1; if (v <= 0 || v > 2) err(`rules.${k} — 0…2`); }  // глава IV: темнее, лампы дороже
      else if (k === 'promote') { for (const [from, to] of Object.entries(v || {})) if (!(from in ctx.enemies) || !(to in ctx.enemies)) err(`promote ${from} → ${to}: нет такого врага`); }
      else err(`rules.${k} — не правило знамения`);
    }
    if (!(helps && hurts)) err('знамение — сделка: что-то помогает и что-то вредит');
    if (('promote_chance' in r) !== ('promote' in r)) err('promote_chance и promote — только вместе');
  } else if (kind === 'affixes') {
    for (const [k, v] of Object.entries(e.mods || {})) {
      if (['hp', 'damage', 'speed', 'cooldown'].includes(k)) { if (!(v >= 0.5 && v <= 2)) err(`mods.${k} — множитель 0.5…2`); }
      else if (k === 'armor') { if (!(v >= 0 && v <= 0.3)) err('mods.armor — 0…0.3 (элитный остаётся смертным)'); }
      else err(`mods.${k} — только hp, damage, speed, cooldown, armor`);
    }
    if (e.mods && 'windup' in e.mods) err('аффикс не трогает замах');
  } else if (kind === 'achievements') {
    const u = e.unlock || {};
    if (!Object.keys(u).length) err('подвиг без условия не будет выполнен никогда');
    if (!(+(e.ash ?? 0) >= 0 && +(e.ash ?? 0) <= 50)) err('ash — 0…50');
    for (const k of Object.keys(u)) if (!GD_RULES.achievements.includes(k)) err(`unlock.${k} — не условие подвигов`);
    for (const k of ['nights', 'wins', 'total_kills']) if (k in u && !(+u[k] >= 1)) err(`unlock.${k} — не меньше 1`);
    for (const k of ['known', 'notes', 'items', 'affixes']) if (k in u && u[k] !== 'all' && !(+u[k] >= 1)) err(`unlock.${k} — число или "all"`);
    for (const id of Object.keys(u.kills || {})) if (!(id in ctx.enemies)) err(`unlock.kills: нет врага ${id}`);
    if (u.moves !== undefined && u.moves !== 'all') for (const m of u.moves) if (!ctx.techniques.includes(m)) err(`unlock.moves: нет приёма ${m}`);
    for (const [boss, t] of Object.entries(u.fast || {})) if (!ctx.enemies[boss]) err(`unlock.fast: ${boss} — не босс`); else if (!(+t > 0)) err(`unlock.fast.${boss} — время в секундах`);
    for (const c of Object.keys(u.deeds || {})) if (!ctx.counters.includes(c)) err(`unlock.deeds.${c} не считается (Achievements.COUNTERS: ${ctx.counters.join(', ')})`);
  } else if (kind === 'skins') {
    for (const k of Object.keys(e.unlock || {})) if (!GD_RULES.skins.includes(k)) err(`unlock.${k} — только nights, total_kills или kills`);
    for (const id of Object.keys(e.unlock?.kills || {})) if (!(id in ctx.enemies)) err(`unlock.kills: нет врага ${id}`);
    if (e.sku && !/^steam:\d+$/.test(e.sku)) err('sku — "steam:<id DLC>"');
    const h = +(e.cloak?.hue ?? 0); if (!(h >= 0 && h <= 1)) err('cloak.hue — 0…1');
    if ('armor' in e && !/^#?[0-9a-f]{6}([0-9a-f]{2})?$/i.test(e.armor)) err('armor — #rrggbb');
  }
  return out;
}
if (typeof module !== 'undefined') module.exports = { gdText, gdTextKept, gdPyDump, gdPlaylists, gdSkinPixel, gdRgb2hsv, gdHsv2rgb, gdFlags, gdProblems };

/* ---------- drafts ---------- */
const gdDoc = p => WORLD.work[p] ?? WORLD.data.files[p];
function gdPut(p, v) {
  if (sameDraft(v, WORLD.data.files[p])) delete WORLD.work[p]; else WORLD.work[p] = v;
  try { localStorage.setItem('ss_world', JSON.stringify(WORLD.work)); } catch {}
  draftHistory(GD.tab);
}
function gdSaveStrings() { try { localStorage.setItem('ss_gd_strings', JSON.stringify(GD.strings)); localStorage.setItem('ss_gd_music', JSON.stringify(GD.music)); } catch {} draftHistory(GD.tab); }
const gdStr = (k, loc = 'ru') => GD.strings[k]?.[loc] ?? GD.data.strings[k]?.[loc] ?? '';
const gdHas = k => !!(GD.strings[k] || GD.data.strings[k]);
function gdSetStr(k, loc, v) {
  const row = { ...(GD.data.strings[k] || {}), ...(GD.strings[k] || {}), [loc]: v };
  if (GD.data.strings[k] && GD_LOCALES.every(l => (row[l] ?? '') === (GD.data.strings[k][l] ?? ''))) delete GD.strings[k]; else GD.strings[k] = row;
  gdSaveStrings();
}
// what the Chinese subset carries: every character strings.csv already uses (tools/art/make_cjk_font.py)
const gdZhMissing = text => [...new Set([...(text || '')].filter(ch => ch.charCodeAt(0) > 0x2e7f && !GD.zh.has(ch)))];
function gdStrFields(k, label) {
  if (!k) return '';
  const zh = gdZhMissing(gdStr(k, 'zh_CN'));
  return `<div class="card gdstr"><b>${esc(label || k)}</b>${label ? ` <span class="muted">${esc(k)}</span>` : ''}${gdHas(k) ? (GD.strings[k] ? ' <span class="badge new">правка</span>' : '') : ' <span class="badge new">новая строка</span>'}
    ${GD_LOCALES.map(l => `<label class="gdloc"><span>${l}</span><textarea rows="1" data-gd-str="${esc(k)}" data-loc="${l}">${esc(gdStr(k, l))}</textarea></label>`).join('')}
    ${zh.length ? `<div class="warn">Этих иероглифов нет в шрифте сборки (${esc(zh.join(''))}): после отправки перезапусти tools/art/make_cjk_font.py, иначе валидатор упадёт.</div>` : ''}</div>`;
}
async function gdLoad() {
  if (GD.data) return;
  GD.data = await (await fetch('import/gamedata.json')).json();
  await worldLoad();
  try { GD.strings = JSON.parse(localStorage.getItem('ss_gd_strings') || '{}'); GD.music = JSON.parse(localStorage.getItem('ss_gd_music') || '{}'); } catch {}
  GD.zh = new Set(Object.values(GD.data.strings).flatMap(v => [...(v.zh_CN || '')]));
}
function gdCtx() {
  const files = Object.keys(WORLD.data.files), all = dir => files.filter(p => p.startsWith(dir)).flatMap(p => [].concat(gdDoc(p) || []));
  const enemies = Object.fromEntries(files.filter(p => p.startsWith('data/enemies/')).map(p => [gdDoc(p).id, !!gdDoc(p).boss || (gdDoc(p).tags || []).includes('boss')]));
  return { stats: GD.data.stats, item_stats: GD.data.item_stats, techniques: GD.data.techniques, counters: GD.data.counters, enemies,
    gifts: Object.fromEntries(all('data/abilities/').map(g => [g.id, g.path])), relics: all('data/relics/').map(r => r.id), strings: gdHas };
}

/* ---------- sending ---------- */
const GD_MANIFEST = 'tools/audio/music_manifest.json', GD_PLAYLISTS = 'data/music/playlists.json';
// strings or music waiting in this browser, whether or not a tab of ours was opened since the page loaded
const gdPending = () => ['ss_gd_strings', 'ss_gd_music'].some(k => { try { return Object.keys(JSON.parse(localStorage.getItem(k) || '{}')).length > 0; } catch { return false; } });
async function gdExtraFiles(withStrings, withMusic) {
  const files = {}, what = [];
  if (withStrings && Object.keys(GD.strings).length) {
    files['localization/strings.csv'] = mergeStrings(await repoText('localization/strings.csv'), GD.strings); what.push(`strings: ${Object.keys(GD.strings).join(', ')}`);
  }
  if (withMusic && Object.keys(GD.music).length) {
    const text = await repoText(GD_MANIFEST), doc = JSON.parse(text);
    for (const t of doc.tracks) if (GD.music[t.slug]) t.playlists = [...GD.music[t.slug]];
    files[GD_MANIFEST] = gdPyDump(doc, 1) + (text.endsWith('\n') ? '\n' : '');
    const old = await repoText(GD_PLAYLISTS);
    files[GD_PLAYLISTS] = gdPyDump({ _comment: JSON.parse(old)._comment, playlists: gdPlaylists(GD.data.music.existing, doc.tracks) }, 2) + (old.endsWith('\n') ? '\n' : '');
    what.push(`music: ${Object.keys(GD.music).join(', ')}`);
  }
  return { files, what };
}
async function gdFiles(tab) {
  const problems = tab.problems ? tab.problems() : [];
  if (problems.length) throw new Error('Валидатор игры это не пропустит: ' + problems.slice(0, 5).join('; '));
  const files = {}, what = [];
  for (const [p, mine] of Object.entries(WORLD.work)) {
    if (!tab.paths(p)) continue;
    // a file the studio makes (a new weapon, a new ending) is not in the game yet: nothing to merge with
    const text = await repoText(p), latest = text.trim() ? JSON.parse(text) : undefined;
    const merged = await resolveDraft(draftBase('world', WORLD.data.files)[p], mine, latest, p, BASES.world?.uncertain);
    if (!sameDraft(merged, latest)) { files[p] = (await tab.text?.(p, merged, text)) ?? (p === GD_ROOMS ? fmtStudioRooms(merged) : gdText(text, merged)); what.push(p); }
  }
  const extra = await gdExtraFiles(tab.strings, tab.music), own = tab.extraFiles ? await tab.extraFiles() : { files: {}, what: [] };
  Object.assign(files, extra.files, own.files); what.push(...extra.what, ...own.what);
  if (!Object.keys(files).length) throw new Error('Нет изменений');
  const notes = tab.music && extra.files[GD_PLAYLISTS] ? ['После слияния: python3 tools/export/music_filters.py — лёгкие сборки (Android, Web) берут свои треки из плейлистов.'] : [];
  return { files, notes, title: `Studio: ${tab.title} — ${what.join('; ').slice(0, 120)}`, body: `${tab.title} from the studio's «${tab.label}»:\n\n${what.map(w => '- ' + w).join('\n')}${notes.length ? '\n\n' + notes.join('\n') : ''}` };
}
async function gdSend(m) {
  const tab = STUDIO_TABS[m];
  await sendToGame(() => gdFiles(tab), null);
  if (!sendToGame.last?.local) return;
  // written into the working tree: what was sent is the game now
  for (const p of Object.keys(WORLD.work)) if (tab.paths(p)) { WORLD.data.files[p] = WORLD.work[p]; if (BASES.world) BASES.world.value[p] = structuredClone(WORLD.work[p]); delete WORLD.work[p]; }
  if (tab.strings) { for (const [k, v] of Object.entries(GD.strings)) GD.data.strings[k] = v; GD.strings = {}; GD.zh = new Set(Object.values(GD.data.strings).flatMap(v => [...(v.zh_CN || '')])); }
  if (tab.music) { for (const t of GD.data.music.tracks) if (GD.music[t.slug]) t.playlists = GD.music[t.slug]; GD.music = {}; }
  if (tab.sent) tab.sent();
  draftBasesSave(); try { localStorage.setItem('ss_world', JSON.stringify(WORLD.work)); } catch {} gdSaveStrings(); tab.render();
}
const gdDirty = tab => Object.keys(WORLD.work).some(p => tab.paths(p)) || tab.strings && Object.keys(GD.strings).length > 0 || tab.music && Object.keys(GD.music).length > 0;
function gdBar(m) {
  const tab = STUDIO_TABS[m], dirty = gdDirty(tab);
  return `<span class="grow"></span><button class="sm" data-gd="revert" title="Отменить несохранённые правки этой вкладки">↺ Как в игре</button><button class="primary" data-gd="send"${dirty ? '' : ' disabled'}>→ В игру${dirty ? ' •' : ''}</button>`;
}
function gdRevert(m) {
  const tab = STUDIO_TABS[m];
  if (tab.revert) tab.revert(); else for (const p of Object.keys(WORLD.work)) if (tab.paths(p)) delete WORLD.work[p];
  if (tab.strings && m === 'txt') GD.strings = {};
  if (tab.music) GD.music = {};
  try { localStorage.setItem('ss_world', JSON.stringify(WORLD.work)); } catch {} gdSaveStrings(); tab.render();
}
/* undo / redo (js/edit.js asks undoTarget / restore) */
function gdSnap(m) {
  const tab = STUDIO_TABS[m];
  return { id: m, work: Object.fromEntries(Object.entries(WORLD.work).filter(([p]) => tab.paths(p))), strings: tab.strings ? GD.strings : null, music: tab.music ? GD.music : null };
}
function gdRestore(m, o) {
  const tab = STUDIO_TABS[m];
  for (const p of Object.keys(WORLD.work)) if (tab.paths(p)) delete WORLD.work[p];
  Object.assign(WORLD.work, o.work || {});
  if (o.strings) GD.strings = o.strings; if (o.music) GD.music = o.music;
  try { localStorage.setItem('ss_world', JSON.stringify(WORLD.work)); } catch {} gdSaveStrings(); tab.render();
}

/* ---------- «Облик»: the hero's cloaks ---------- */
const GD_SKINS = 'data/skins/free.json';
function gdSkin() { const list = gdDoc(GD_SKINS); return list[Math.min(GD.sel.skin || 0, list.length - 1)]; }
function gdSkinEdit(fn) { const list = structuredClone(gdDoc(GD_SKINS)), i = Math.min(GD.sel.skin || 0, list.length - 1); fn(list[i], list); gdPut(GD_SKINS, list); }
function renderSkins() {
  const list = gdDoc(GD_SKINS), s = gdSkin(), was = WORLD.data.files[GD_SKINS].find(x => x.id === s.id), ctx = gdCtx(), u = s.unlock || {};
  const enemies = Object.keys(ctx.enemies).sort();
  $('#gdSide_skins').innerHTML = `<div class="gdlist">${list.map((x, i) => `<button class="sm ${i === (GD.sel.skin || 0) ? 'on' : ''}" data-gd-pick="skin" data-i="${i}">${esc(gdStr(x.name) || x.id)}${x.sku ? ' 💰' : ''}</button>`).join('')}</div>
    <div class="row" style="margin:0;gap:6px"><button class="sm" data-gd="skin-add">+ Новый облик</button>${was ? '' : '<button class="sm" data-gd="skin-del">✕ Убрать новый</button>'}</div>
    <label>id ${was ? '<span class="muted">(хранится в настройках игрока — не меняется)</span>' : ''}<input data-gd-skin="id" value="${esc(s.id)}"${was ? ' disabled' : ''}></label>
    <div class="card"><label><input type="checkbox" data-gd-skin="has_cloak"${s.cloak ? ' checked' : ''}> Перекрасить плащ</label>
      ${s.cloak ? ['hue', 'saturation', 'value'].map(k => { const [lo, hi, label] = { hue: [0, 1, 'Оттенок'], saturation: [0, 2, 'Насыщенность ×'], value: [0, 2, 'Яркость ×'] }[k], v = +(s.cloak[k] ?? (k === 'hue' ? 0 : 1));
        return `<label class="lifenum">${label} <span class="muted">${v.toFixed(2)}</span><input type="range" min="${lo}" max="${hi}" step="0.01" data-gd-skin="cloak.${k}" value="${v}"></label>`; }).join('') : '<div class="muted">Плащ остаётся красным.</div>'}</div>
    <div class="card"><label><input type="checkbox" data-gd-skin="has_armor"${s.armor ? ' checked' : ''}> Тонировать доспех и всё остальное</label>
      ${s.armor ? `<label>Тон <input type="color" data-gd-skin="armor" value="${esc(s.armor.slice(0, 7))}"></label>` : ''}</div>
    <div class="card"><b>Открывается</b>
      <label class="lifenum">после ночей <input type="number" min="0" data-gd-skin="unlock.nights" value="${u.nights ?? ''}" placeholder="—"></label>
      <label class="lifenum">всего убито <input type="number" min="0" data-gd-skin="unlock.total_kills" value="${u.total_kills ?? ''}" placeholder="—"></label>
      ${Object.entries(u.kills || {}).map(([id, n]) => `<div class="row" style="margin:0;gap:6px"><span class="grow">убить ${esc(id)}</span><input type="number" min="1" style="width:64px" data-gd-skin="kills" data-enemy="${esc(id)}" value="${n}"><button class="sm" data-gd="skin-kill-del" data-enemy="${esc(id)}">✕</button></div>`).join('')}
      <label>+ убить врага<select data-gd-skin="kills-add"><option value="">—</option>${enemies.filter(id => !(id in (u.kills || {}))).map(id => `<option>${esc(id)}</option>`).join('')}</select></label>
      <label>Магазин (sku) <input data-gd-skin="sku" value="${esc(s.sku || '')}" placeholder="steam:<id DLC> — пусто: бесплатный"></label>
      <div class="muted">${!Object.keys(u).length && !s.sku ? 'Открыт с самого начала.' : s.sku ? 'Открывается только покупкой (StoreBridge.owns).' : ''}</div></div>
    ${gdStrFields(s.name, 'Название')}${gdStrFields(s.description, 'Описание')}
    ${gdProblems('skins', s, ctx).map(p => `<div class="warn">${esc(p)}</div>`).join('')}`;
  $('#gdBar_skins').innerHTML = `<label>Анимация <select id="gdSkinAnim">${['idle', 'attack', 'roll', 'run', 'jump', 'guard', 'hurt'].map(a => `<option${a === (GD.sel.anim || 'idle') ? ' selected' : ''}>${a}</option>`).join('')}</select></label><label><input type="checkbox" id="gdSkinCompare"${GD.sel.compare ? ' checked' : ''}> рядом — как было</label>` + gdBar('skins');
  gdSkinSheet();
}
function gdSkinSheet() {
  const anim = GD.sel.anim || 'idle', src = A(`res://assets/sprites/elian_${anim}.png`);
  if (GD.pic?.src === src) return;
  const im = new Image(); im.crossOrigin = 'anonymous'; GD.pic = { src, im, frames: [], dyed: new Map() };
  im.onload = () => { const n = Math.max(1, Math.floor(im.naturalWidth / 128)); GD.pic.frames = [...Array(n).keys()]; };
  im.onerror = () => { if (anim !== 'idle') { GD.sel.anim = 'idle'; gdSkinSheet(); } };
  im.src = src;
}
function gdSkinFrame(i, skin) {
  const key = i + JSON.stringify([skin.cloak, skin.armor]); let c = GD.pic.dyed.get(key);
  if (c) return c;
  if (GD.pic.dyed.size > 64) GD.pic.dyed.clear();
  c = mk(128, 64); const x = c.getContext('2d'); x.drawImage(GD.pic.im, i * 128, 0, 128, 64, 0, 0, 128, 64);
  if (skin.cloak || skin.armor) {
    const d = x.getImageData(0, 0, 128, 64), p = d.data;
    for (let j = 0; j < p.length; j += 4) if (p[j + 3]) { const o = gdSkinPixel([p[j] / 255, p[j + 1] / 255, p[j + 2] / 255], skin); p[j] = o[0] * 255; p[j + 1] = o[1] * 255; p[j + 2] = o[2] * 255; }
    x.putImageData(d, 0, 0);
  }
  GD.pic.dyed.set(key, c); return c;
}
function gdSkinLoop(t) {
  GD.raf = 0;
  if (GD.tab !== 'skins') return;
  const c = $('#gdCanvas_skins'), x = c.getContext('2d'), s = gdSkin(), was = WORLD.data.files[GD_SKINS].find(o => o.id === s.id);
  const W = c.clientWidth || 640, H = c.clientHeight || 360; if (c.width !== W || c.height !== H) { c.width = W; c.height = H; }
  x.imageSmoothingEnabled = false; x.fillStyle = '#16131c'; x.fillRect(0, 0, W, H);
  x.fillStyle = '#2a2433'; x.fillRect(0, H * 0.72, W, H * 0.28);
  if (GD.pic?.frames.length) {
    const i = Math.floor(t / 1000 * 8) % GD.pic.frames.length, k = Math.max(1, Math.floor(Math.min(W / (GD.sel.compare ? 260 : 140), H / 70)));
    const draw = (skin, cx, label) => { x.drawImage(gdSkinFrame(i, skin), Math.round(cx - 68 * k), Math.round(H * 0.72 - 64 * k), 128 * k, 64 * k); x.fillStyle = '#cfd8e3'; x.font = '12px system-ui'; x.textAlign = 'center'; x.fillText(label, cx, H * 0.72 + 18); };
    if (GD.sel.compare) { draw(was || {}, W * 0.3, was ? 'в игре' : 'без облика'); draw(s, W * 0.7, 'черновик'); } else draw(s, W / 2, gdStr(s.name) || s.id);
    x.textAlign = 'left';
  }
  GD.raf = requestAnimationFrame(gdSkinLoop);
}
function gdSkinInput(el) {
  const k = el.dataset.gdSkin, v = el.type === 'checkbox' ? el.checked : el.value;
  gdSkinEdit((s, list) => {
    if (k === 'id') { const id = v.trim(); if (!id || list.some(o => o !== s && o.id === id)) return; const up = id.toUpperCase();
      if (s.name === `SKIN_${s.id.toUpperCase()}_NAME`) s.name = `SKIN_${up}_NAME`; if (s.description === `SKIN_${s.id.toUpperCase()}_DESC`) s.description = `SKIN_${up}_DESC`; s.id = id; }
    else if (k === 'has_cloak') { if (v) s.cloak = { hue: 0.6, saturation: 0.6, value: 0.85 }; else delete s.cloak; }
    else if (k === 'has_armor') { if (v) s.armor = '#dfe6f2'; else delete s.armor; }
    else if (k.startsWith('cloak.')) s.cloak[k.slice(6)] = Math.round(+v * 100) / 100;
    else if (k === 'armor') s.armor = v;
    else if (k.startsWith('unlock.')) { const u = s.unlock ||= {}, f = k.slice(7); if (v === '' || +v <= 0) delete u[f]; else u[f] = Math.round(+v); }
    else if (k === 'kills') { s.unlock.kills[el.dataset.enemy] = Math.max(1, Math.round(+v)); }
    else if (k === 'kills-add' && v) { const u = s.unlock ||= {}; (u.kills ||= {})[v] = 1; }
    else if (k === 'sku') { if (v.trim()) s.sku = v.trim(); else delete s.sku; }
  });
  if (el.type === 'range') { el.previousElementSibling.textContent = (+v).toFixed(2); return; }
  renderSkins();
}
STUDIO_TABS.skins = {
  label: 'Облик', title: 'skins', tip: 'Облики героя: цвет плаща, тон доспеха, условия открытия (data/skins)',
  paths: p => p === GD_SKINS, strings: true,
  html: `<aside class="side lifeside" id="gdSide_skins"></aside><main class="lifemain"><div class="lifebar" id="gdBar_skins"></div><canvas id="gdCanvas_skins" class="gdstage"></canvas>
    <div class="note">Тот же расчёт, что у шейдера alignment_marks.gdshader: плащ — единственный насыщенно-красный на листе героя, поэтому окно по оттенку находит его в каждом кадре без маски; всё остальное умножается на тон доспеха. Облик с sku открывается только покупкой.</div></main>`,
  render: renderSkins,
  problems() { const ctx = gdCtx(); return gdDoc(GD_SKINS).flatMap(s => gdProblems('skins', s, ctx).map(p => `${s.id}: ${p}`)); },
  enter() { renderSkins(); if (!GD.raf) GD.raf = requestAnimationFrame(gdSkinLoop); },
};

/* ---------- «Тексты»: every string in four languages ---------- */
function gdTxtRows() {
  const q = (GD.sel.q || '').toLowerCase(), group = GD.sel.group || '', only = GD.sel.only || '';
  const keys = [...new Set([...Object.keys(GD.data.strings), ...Object.keys(GD.strings)])];
  return keys.filter(k => {
    if (group && !k.startsWith(group)) return false;
    const row = { ...(GD.data.strings[k] || {}), ...(GD.strings[k] || {}) };
    if (only === 'edited' && !GD.strings[k]) return false;
    if (only === 'missing' && GD_LOCALES.every(l => (row[l] || '').trim())) return false;
    if (only === 'same' && !GD_LOCALES.some(l => l !== 'en' && row[l] && row[l] === row.en && /[a-z]{3}/i.test(row.en))) return false;
    if (only === 'zh' && !gdZhMissing(row.zh_CN).length) return false;
    return !q || k.toLowerCase().includes(q) || GD_LOCALES.some(l => (row[l] || '').toLowerCase().includes(q));
  });
}
function renderTxt() {
  const groups = Object.entries([...Object.keys(GD.data.strings)].reduce((a, k) => { const g = k.split('_')[0] + '_'; a[g] = (a[g] || 0) + 1; return a; }, {})).sort((a, b) => b[1] - a[1]);
  $('#gdSide_txt').innerHTML = `<label>Поиск<input id="gdTxtQ" value="${esc(GD.sel.q || '')}" placeholder="ключ или слово на любом языке"></label>
    <label>Группа<select id="gdTxtGroup"><option value="">все (${Object.keys(GD.data.strings).length})</option>${groups.map(([g, n]) => `<option value="${esc(g)}"${g === GD.sel.group ? ' selected' : ''}>${esc(g)}… (${n})</option>`).join('')}</select></label>
    <label>Показать<select id="gdTxtOnly">${[['', 'все'], ['missing', 'где не хватает перевода'], ['same', 'где перевод совпадает с английским'], ['zh', 'иероглифы вне шрифта'], ['edited', 'мои правки']].map(([v, l]) => `<option value="${v}"${v === (GD.sel.only || '') ? ' selected' : ''}>${l}</option>`).join('')}</select></label>
    <div class="card"><b>Новая строка</b><div class="row" style="margin:0;gap:6px"><input id="gdTxtNew" placeholder="KEY_NAME" class="grow"><button class="sm" data-gd="txt-add">+</button></div>
      <div class="muted">Ключ — заглавные латинские буквы, цифры и _. Новой строке нужны все четыре языка (валидатор), пустой язык при отправке возьмёт английский.</div></div>
    <div class="muted">Правок: ${Object.keys(GD.strings).length}. Подсказки врагов — TIP_, имена — ENEMY_, дары — ABILITY_, предметы — ITEM_, подвиги — DEED_.</div>`;
  const rows = gdTxtRows(), shown = rows.slice(0, 120);
  $('#gdMain_txt').innerHTML = `<div class="muted" style="margin:4px 0">${rows.length} строк${rows.length > shown.length ? `, показаны первые ${shown.length} — сузь поиск` : ''}</div>` + shown.map(k => gdStrFields(k)).join('');
  $('#gdBar_txt').innerHTML = gdBar('txt');
  gdAutosize($('#gdMain_txt'));
}
const gdAutosize = root => root && root.querySelectorAll('textarea[data-gd-str]').forEach(t => { t.style.height = 'auto'; t.style.height = Math.min(160, t.scrollHeight + 2) + 'px'; });
STUDIO_TABS.txt = {
  label: 'Тексты', title: 'strings', tip: 'Все строки игры на четырёх языках (localization/strings.csv): имена, подсказки, дары, предметы',
  paths: () => false, strings: true,
  html: `<aside class="side lifeside" id="gdSide_txt"></aside><main class="lifemain"><div class="lifebar" id="gdBar_txt"></div><div id="gdMain_txt" class="gdscroll"></div></main>`,
  render: renderTxt, enter: renderTxt,
};

/* ---------- «Музыка»: moods, tracks, ambience and the room's mood ---------- */
const GD_AMBIENCE = 'data/ambience.json', GD_ROOMS = 'tools/rooms/studio_rooms.json';
const GD_EFFECTS = { clouds: 'облака', ravens: 'вороны', bats: 'летучие мыши', leaves: 'листья', petals: 'лепестки', wisps: 'огоньки', motes: 'пылинки', embers: 'угли', low_fog: 'низкий туман', lightning: 'молнии' };
const gdTracks = () => GD.data.music.tracks.map(t => ({ ...t, playlists: GD.music[t.slug] || t.playlists }));
const gdMoods = () => Object.keys(gdPlaylists(GD.data.music.existing, gdTracks()));
const gdRoomMusic = room => gdDoc(GD_ROOMS)?.[room]?.music ?? GD.data.rooms[room]?.music ?? '';
function gdAmbienceFor(room) { const rules = gdDoc(GD_AMBIENCE).rules || []; const i = rules.findIndex(r => room.includes(r.match || '')); return i; }
function renderMusic() {
  const moods = gdMoods(), mood = GD.sel.mood && moods.includes(GD.sel.mood) ? GD.sel.mood : moods[0], lists = gdPlaylists(GD.data.music.existing, gdTracks());
  GD.sel.mood = mood;
  const rooms = Object.keys(GD.data.rooms).sort(), track = slug => GD.data.music.tracks.find(t => t.slug === slug), file = slug => GD.data.music.files[slug];
  const amb = gdDoc(GD_AMBIENCE).rules || [];
  $('#gdSide_music').innerHTML = `<div class="card"><b>Музыка комнаты</b><div class="muted">Настроение, из которого комната берёт треки (никогда один и тот же дважды подряд).</div>
      ${rooms.map(r => `<label class="gdroom"><span>${esc(r)}</span><select data-gd-roommusic="${esc(r)}"><option value=""${gdRoomMusic(r) ? '' : ' selected'}>— своя по умолчанию</option>${[...new Set([...moods, gdRoomMusic(r)])].filter(Boolean).map(m => `<option${m === gdRoomMusic(r) ? ' selected' : ''}>${esc(m)}</option>`).join('')}</select>${gdDoc(GD_ROOMS)?.[r]?.music !== undefined ? ' •' : ''}</label>`).join('')}</div>
    <div class="card"><b>Живые детали</b> <span class="muted">data/ambience.json — первое совпадение по имени комнаты</span>
      ${amb.map((rule, i) => `<div class="gdamb"><div class="row" style="margin:0;gap:4px"><input data-gd-amb="match" data-i="${i}" value="${esc(rule.match || '')}" class="grow"><button class="sm" data-gd="amb-up" data-i="${i}" title="Выше: проверяется раньше">↑</button><button class="sm" data-gd="amb-del" data-i="${i}">✕</button></div>
        <div class="gdchips">${Object.entries(GD_EFFECTS).map(([e, l]) => `<label><input type="checkbox" data-gd-amb="effect" data-i="${i}" data-e="${e}"${(rule.effects || []).includes(e) ? ' checked' : ''}>${l}</label>`).join('')}</div>
        <div class="muted">${rooms.filter(r => gdAmbienceFor(r) === i).join(', ') || 'ни одной комнаты — её забирают правила выше'}</div></div>`).join('')}
      <button class="sm" data-gd="amb-add">+ Правило</button>
      ${rooms.filter(r => gdAmbienceFor(r) < 0).length ? `<div class="muted">Без деталей: ${esc(rooms.filter(r => gdAmbienceFor(r) < 0).join(', '))}</div>` : ''}</div>`;
  const inMood = lists[mood] || [], hand = GD.data.music.existing[mood] || [];
  $('#gdMain_music').innerHTML = `<div class="row" style="gap:6px"><label>Настроение <select id="gdMood">${moods.map(m => `<option${m === mood ? ' selected' : ''}>${esc(m)} (${(lists[m] || []).length})</option>`).join('')}</select></label>
      <span class="muted">комнаты: ${esc(rooms.filter(r => gdRoomMusic(r) === mood).join(', ') || '—')}</span></div>
    <table class="gdtable"><tr><th></th><th>Трек</th><th>Автор · лицензия</th><th>Ещё в настроениях</th><th></th></tr>
    ${inMood.map(slug => { const t = track(slug), own = hand.includes(slug) && !t;
      return `<tr><td><button class="sm" data-gd="play" data-slug="${esc(slug)}"${file(slug) ? '' : ' disabled title="Файла нет в assets/audio/music"'}>${GD.sel.playing === slug ? '■' : '▶'}</button></td><td>${esc(t?.title || slug)}</td><td class="muted">${esc(t ? `${t.author} · ${t.license}` : 'свой трек игры')}</td>
        <td class="muted">${esc(t ? (GD.music[slug] || t.playlists).filter(p => p !== mood).join(', ') : '')}</td><td>${own ? '<span class="muted">задан в fetch_music.py</span>' : `<button class="sm" data-gd="track-out" data-slug="${esc(slug)}" title="Убрать из этого настроения">✕</button>`}</td></tr>`; }).join('')}</table>
    <label>Добавить трек из библиотеки <select id="gdTrackAdd"><option value="">—</option>${GD.data.music.tracks.filter(t => !inMood.includes(t.slug)).map(t => `<option value="${esc(t.slug)}">${esc(t.title)} — ${esc(t.author)}</option>`).join('')}</select></label>
    <div class="note">Новый трек в библиотеку — строкой в tools/audio/music_manifest.json и python3 tools/audio/fetch_music.py (скачает, обрежет до 150 с, выровняет громкость, перепишет титры). Здесь — только какие треки в каком настроении; плейлисты пишутся так же, как их пишет fetch_music.py. Комнаты берут настроение после перегенерации (локально — сразу при отправке).</div>`;
  $('#gdBar_music').innerHTML = gdBar('music');
}
function gdPlay(slug) {
  if (GD.audio) { GD.audio.pause(); GD.audio = null; }
  if (GD.sel.playing === slug || !slug) { GD.sel.playing = ''; return renderMusic(); }
  GD.audio = new Audio(A('res://assets/audio/music/' + GD.data.music.files[slug])); GD.audio.volume = 0.6;
  GD.audio.play().catch(e => toast('Не играет: ' + e.message, 'err')); GD.audio.onended = () => { GD.sel.playing = ''; renderMusic(); };
  GD.sel.playing = slug; renderMusic();
}
function gdTrackSet(slug, mood, on) {
  const t = GD.data.music.tracks.find(x => x.slug === slug); if (!t) return;
  const now = new Set(GD.music[slug] || t.playlists); if (on) now.add(mood); else now.delete(mood);
  const next = [...(GD.music[slug] || t.playlists).filter(p => now.has(p)), ...[...now].filter(p => !(GD.music[slug] || t.playlists).includes(p))];
  if (sameDraft(next, t.playlists)) delete GD.music[slug]; else GD.music[slug] = next;
  if (!next.length) toast('Трек больше ни в одном настроении — он останется в библиотеке, но не зазвучит');
  gdSaveStrings(); renderMusic();
}
function gdAmbEdit(fn) { const doc = structuredClone(gdDoc(GD_AMBIENCE)); fn(doc.rules); gdPut(GD_AMBIENCE, doc); renderMusic(); }
STUDIO_TABS.music = {
  label: 'Музыка', title: 'music and ambience', tip: 'Настроения и их треки, музыка каждой комнаты, живые детали (вороны, огоньки, молнии)',
  paths: p => p === GD_AMBIENCE || p === GD_ROOMS && Object.values(gdDoc(GD_ROOMS) || {}).some(r => 'music' in r), music: true,
  html: `<aside class="side lifeside" id="gdSide_music"></aside><main class="lifemain"><div class="lifebar" id="gdBar_music"></div><div id="gdMain_music" class="gdscroll"></div></main>`,
  render: renderMusic, enter: renderMusic,
};

/* ---------- «Забег»: items, relics, resonances, omens, vials, affixes and the deeds ---------- */
const GD_KINDS = { items: 'Предметы из сундуков', relics: 'Реликварий (за пепел)', resonances: 'Созвучия', omens: 'Знамения', vials: 'Чаши гнева', affixes: 'Аффиксы элитных', achievements: 'Подвиги' };
const GD_HINTS = {
  items: () => `effects: [{"type": "stat", "stat": …, "op": "add"|"mul", "value": …}], stat — механика из ITEM_STATS: ${GD.data.item_stats.join(', ')}`,
  relics: () => `effects: stat из BASE_STATS или {"type": "reroll"}; needs — id другой реликвии`,
  resonances: () => `needs: {"path": "grace"|"temptation"|"will", "count": N} или {"gifts": [дары разных путей]}; effects — stat из BASE_STATS`,
  omens: () => `rules: ${GD_RULES.omens.join(', ')} — что-то помогает и что-то вредит`,
  vials: () => `rules: ${GD_RULES.vials.join(', ')}; ash ≥ 1 — множитель пепла`,
  affixes: () => `mods: hp, damage, speed, cooldown — множители 0.5…2; armor — 0…0.3. Замах не трогается никогда.`,
  achievements: () => `unlock: ${GD_RULES.achievements.join(', ')}; deeds — счётчики ${GD.data.counters.join(', ')}; ash 0…50. id — имя в Steam: не переименовывать.`,
};
const GD_STRUCT = ['effects', 'rules', 'mods', 'needs', 'unlock'];
const gdKindFiles = kind => Object.keys(WORLD.data.files).filter(p => p.startsWith(`data/${kind}/`));
function gdKindEntries(kind) { return gdKindFiles(kind).flatMap(p => [].concat(gdDoc(p)).map((e, i) => ({ p, i, e }))); }
function gdNewEntry(kind, id) {
  const up = id.toUpperCase(), pre = { items: 'ITEM_', relics: 'RELIC_', resonances: 'RESONANCE_', omens: 'OMEN_', vials: 'VIAL_', affixes: 'AFFIX_', achievements: 'DEED_' }[kind];
  const named = { id, name: pre + up + (kind === 'items' ? '_NAME' : ''), description: pre + up + (kind === 'items' ? '_DESC' : '_DESC') };
  return { items: { ...named, rarity: 'common', icon: 'res://assets/icons/quest/curio_2.png', effects: [{ type: 'stat', stat: GD.data.item_stats[0], op: 'add', value: 1 }] },
    relics: { ...named, cost: 20, effects: [{ type: 'stat', stat: 'max_hp', op: 'add', value: 5 }] },
    resonances: { ...named, needs: { path: 'grace', count: 3 }, effects: [{ type: 'stat', stat: GD.data.stats[0], op: 'add', value: 0.1 }] },
    omens: { ...named, rules: { enemy_damage: 1.1, essence: 1.2 } },
    vials: { ...named, tier: 5, ash: 1.2, rules: {} },
    affixes: { id, name: pre + up, color: '#e0b060', mods: { hp: 1.2 } },
    achievements: { ...named, ash: 5, unlock: { nights: 1 } } }[kind];
}
function renderRun() {
  const kind = GD.sel.kind || 'items', rows = gdKindEntries(kind), cur = Math.min(GD.sel.entry || 0, rows.length - 1), r = rows[cur], ctx = gdCtx();
  if (kind === 'vials') ctx.tiers = rows.filter((x, i) => i !== cur).map(x => x.e.tier);
  const problemsAll = rows.map(x => gdProblems(kind, x.e, kind === 'vials' ? { ...ctx, tiers: rows.filter(y => y !== x).map(y => y.e.tier) } : ctx));
  $('#gdSide_run').innerHTML = `<label>Таблица<select id="gdKind">${Object.entries(GD_KINDS).map(([k, l]) => `<option value="${k}"${k === kind ? ' selected' : ''}>${l} (${gdKindEntries(k).length})${gdKindFiles(k).some(p => WORLD.work[p]) ? ' •' : ''}</option>`).join('')}</select></label>
    <div class="gdlist">${rows.map((x, i) => `<button class="sm ${i === cur ? 'on' : ''}" data-gd-pick="entry" data-i="${i}">${problemsAll[i].length ? '⚠ ' : ''}${esc(gdStr(x.e.name) || x.e.id)} <span class="muted">${esc(x.e.id)}</span></button>`).join('')}</div>
    <div class="row" style="margin:0;gap:6px"><input id="gdNewId" placeholder="id новой записи" class="grow"><button class="sm" data-gd="entry-add">+ Добавить</button></div>
    <div class="muted">${esc(GD_HINTS[kind]())}</div>`;
  if (!r) { $('#gdMain_run').innerHTML = '<div class="muted">Пусто</div>'; $('#gdBar_run').innerHTML = gdBar('run'); return; }
  const e = r.e, existed = [].concat(WORLD.data.files[r.p]).some(o => o.id === e.id);
  const scalar = Object.entries(e).filter(([k, v]) => !['id', 'name', 'description', ...GD_STRUCT].includes(k) && (typeof v !== 'object' || v === null));
  $('#gdMain_run').innerHTML = `<div class="row" style="gap:6px"><b class="grow">${esc(gdStr(e.name) || e.id)}</b><span class="muted">${esc(r.p)}</span>
      ${kind === 'achievements' && existed ? '<span class="muted" title="id подвига — имя в магазине; его нельзя ни переименовать, ни убрать">id навсегда</span>' : `<button class="sm" data-gd="entry-del">✕ Убрать</button>`}</div>
    <div class="gdfields"><label>id<input data-gd-entry="id" value="${esc(e.id)}"${existed ? ' disabled title="Сохранения и профиль хранят id"' : ''}></label>
      ${scalar.map(([k, v]) => `<label>${esc(k)}${k === 'color' ? `<input type="color" data-gd-entry="${esc(k)}" value="${esc(String(v).slice(0, 7))}">` : k === 'rarity' ? `<select data-gd-entry="rarity">${['common', 'rare'].map(o => `<option${o === v ? ' selected' : ''}>${o}</option>`).join('')}</select>` : `<input data-gd-entry="${esc(k)}" ${typeof v === 'number' ? 'type="number" step="any"' : ''} value="${esc(String(v))}">`}</label>`).join('')}</div>
    ${GD_STRUCT.filter(k => k in e).map(k => `<label>${k}<textarea class="gdjson" rows="${Math.min(10, JSON.stringify(e[k], null, 1).split('\n').length + 1)}" data-gd-entry-json="${k}">${esc(JSON.stringify(e[k], null, 1))}</textarea></label>`).join('')}
    ${kind === 'items' || kind === 'relics' || kind === 'resonances' ? gdCapsNote(e.effects) : ''}
    ${problemsAll[cur].map(p => `<div class="warn">${esc(p)}</div>`).join('')}
    ${gdStrFields(e.name, 'Название')}${e.description ? gdStrFields(e.description, 'Описание') : ''}`;
  $('#gdBar_run').innerHTML = gdBar('run');
  gdAutosize($('#gdMain_run'));
}
// AbilitySystem.CAPS: where each stat it touches stops, whatever piles up
function gdCapsNote(effects) {
  const rows = (effects || []).filter(f => f.type === 'stat' && GD.data.caps[f.stat]).map(f => `${f.stat}: ${f.op || 'add'} ${f.value} — потолок ${GD.data.caps[f.stat].join('…')}`);
  return rows.length ? `<div class="muted">${esc(rows.join(' · '))}</div>` : '';
}
function gdEntryEdit(fn) {
  const kind = GD.sel.kind || 'items', rows = gdKindEntries(kind), r = rows[Math.min(GD.sel.entry || 0, rows.length - 1)];
  const doc = structuredClone(gdDoc(r.p)), list = Array.isArray(doc) ? doc : null, e = list ? list[r.i] : doc;
  fn(e, list); gdPut(r.p, doc);
}
STUDIO_TABS.run = {
  label: 'Забег', title: 'run balance and deeds', tip: 'Предметы, реликвии, созвучия, знамения, чаши, аффиксы элитных и подвиги — с проверками валидатора',
  paths: p => Object.keys(GD_KINDS).some(k => p.startsWith(`data/${k}/`)), strings: true,
  html: `<aside class="side lifeside" id="gdSide_run"></aside><main class="lifemain"><div class="lifebar" id="gdBar_run"></div><div id="gdMain_run" class="gdscroll"></div></main>`,
  render: renderRun, enter: renderRun,
  problems() { const ctx = gdCtx(); return Object.keys(GD_KINDS).flatMap(k => { const rows = gdKindEntries(k); return rows.flatMap(x => gdProblems(k, x.e, k === 'vials' ? { ...ctx, tiers: rows.filter(y => y !== x).map(y => y.e.tier) } : ctx).map(p => `${x.e.id}: ${p}`)); }); },
};

/* ---------- «Сюжет»: the chapter, its forks, notes and every flag both ways ---------- */
function renderStory() {
  const files = WORLD.data.files, cur = Object.fromEntries(Object.keys(files).map(p => [p, gdDoc(p)]));
  const chapters = Object.keys(cur).filter(p => p.startsWith('data/chapters/')).flatMap(p => cur[p]);
  const forks = Object.keys(cur).filter(p => p.startsWith('data/forks/')).flatMap(p => cur[p]);
  const notes = Object.keys(cur).filter(p => p.startsWith('data/notes/')).flatMap(p => cur[p]);
  const rests = new Set((cur['data/rest_points/chapter1.json'] || []).map(r => r.id));
  const scene = s => String(s).replace('res://scenes/rooms/', '').replace('.tscn', '');
  const forkAfter = new Map(forks.map(f => [scene(f.after), f])), forkWay = new Map(forks.flatMap(f => Object.entries(f.options).map(([k, s]) => [scene(s), `${f.id}: ${k}`])));
  const rooms = (gdDoc(GD_ROOMS) || {});
  const flags = gdFlags(cur, { read: GD.data.flags_read_in_code, set: GD.data.flags_set_in_code, tests: GD.data.flags_for_tests, awaited: GD.data.flags_awaited });
  const ghosts = Object.entries(flags).filter(([, f]) => !f.set.length), orphans = Object.entries(flags).filter(([, f]) => !f.read.length);
  $('#gdSide_story').innerHTML = `<div class="card"><b>Флаги</b> <span class="muted">${Object.keys(flags).length}</span>
      <div class="${ghosts.length ? 'warn' : 'muted'}">Читаются, но нигде не ставятся (ветка недостижима — валидатор падает): ${ghosts.length ? esc(ghosts.map(([k]) => k).join(', ')) : 'нет'}</div>
      <div class="${orphans.length ? 'warn' : 'muted'}">Ставятся, но никто не читает (мир не отвечает на выбор): ${orphans.length ? esc(orphans.map(([k]) => k).join(', ')) : 'нет'}</div>
      <label>Фильтр<input id="gdFlagQ" value="${esc(GD.sel.flagq || '')}" placeholder="флаг или место"></label></div>
    <div class="card"><b>Записи</b>${notes.map(n => `<div>📜 ${esc(gdStr(n.name) || n.id)} <span class="muted">${esc(n.place || '')} · диалог ${esc(n.dialogue)}</span></div>`).join('')}</div>
    <div class="muted">Сюжет главы по сценам: docs/CHAPTER1.md. Диалоги правятся во вкладке «Диалоги», катсцены — в «Катсценах», привалы и сундуки — в «Местах».</div>`;
  const fq = (GD.sel.flagq || '').toLowerCase();
  $('#gdMain_story').innerHTML = `<div class="gdchapter">${chapters.map(c => `<div class="card" style="border-color:${esc(c.color || '#555')}"><b>${esc(gdStr(c.title) || c.id)}</b> <span class="muted">${esc(gdStr(c.subtitle) || '')}</span>
      <div class="gdrooms">${c.rooms.map(s => { const r = scene(s), f = forkAfter.get(r), way = forkWay.get(r), x = rooms[r] || {};
        return `<div class="gdroomcard">${esc(r)}${rests.has(r) ? ' <span title="привал">✚</span>' : ''}${way ? `<div class="muted">развилка ${esc(way)}</div>` : ''}
          ${x.intro_cutscene || GD.data.rooms[r] ? `<div class="muted">${x.intro_cutscene ? '🎬 ' + esc(x.intro_cutscene) : ''}${x.outro_cutscene ? ' → 🎬 ' + esc(x.outro_cutscene) : ''} ♪ ${esc(gdRoomMusic(r))}</div>` : ''}
          ${f ? `<div class="gdfork">⑂ ${esc(f.dialogue)}: ${Object.keys(f.options).map(esc).join(' / ')} → ${esc(scene(f.then))}</div>` : ''}</div>`; }).join('')}</div></div>`).join('')}</div>
    <table class="gdtable"><tr><th>Флаг</th><th>Ставят</th><th>Читают</th></tr>${Object.entries(flags).filter(([k, f]) => !fq || k.includes(fq) || [...f.set, ...f.read].some(w => w.toLowerCase().includes(fq))).sort().map(([k, f]) =>
      `<tr><td>${!f.set.length ? '⛔ ' : !f.read.length ? '⚠ ' : ''}<b>${esc(k)}</b></td><td class="muted">${esc(f.set.join(', ') || '—')}</td><td class="muted">${esc(f.read.join(', ') || '—')}</td></tr>`).join('')}</table>`;
  $('#gdBar_story').innerHTML = '<span class="muted grow">Карта главы, развилки, записи и все флаги в обе стороны — как их собирает валидатор.</span>';
}
STUDIO_TABS.story = {
  label: 'Сюжет', title: 'story map', tip: 'Карта главы: места, комнаты, развилки, записи и все флаги сюжета в обе стороны',
  paths: () => false,
  html: `<aside class="side lifeside" id="gdSide_story"></aside><main class="lifemain"><div class="lifebar" id="gdBar_story"></div><div id="gdMain_story" class="gdscroll"></div></main>`,
  render: renderStory, enter: renderStory,
};

/* ---------- «Места»: rest points and chests on the room map ---------- */
const GD_REST = 'data/rest_points/chapter1.json';
const gdPropIds = () => Object.keys(WORLD.data.files).filter(p => p.startsWith('data/props/')).map(p => p.slice(11, -5));
async function renderPlaces() {
  await loadCutData();
  const names = roomNames(), room = GD.sel.room && names.includes(GD.sel.room) ? GD.sel.room : names[0]; GD.sel.room = room;
  const rest = (gdDoc(GD_REST) || []).find(r => r.id === room), props = gdDoc(GD_ROOMS)?.[room]?.props || [], what = GD.sel.place || 'rest';
  const chests = gdPropIds().filter(id => /chest|cache|altar|reliquary|letters|book/.test(id)), propDoc = id => WORLD.data.files[`data/props/${id}.json`] || {};
  $('#gdSide_places').innerHTML = `<label>Комната<select id="gdPlaceRoom">${names.map(n => `<option${n === room ? ' selected' : ''}>${esc(n)}</option>`).join('')}</select></label>
    <div class="card"><b>Клик по полу ставит</b>
      <label><input type="radio" name="gdPlace" value="rest"${what === 'rest' ? ' checked' : ''}> привал ✚ (один на комнату)</label>
      <label><input type="radio" name="gdPlace" value="prop"${what === 'prop' ? ' checked' : ''}> вещь <select id="gdPlaceProp">${[...chests, ...gdPropIds().filter(id => !chests.includes(id))].map(id => `<option${id === GD.sel.prop ? ' selected' : ''}>${esc(id)}</option>`).join('')}</select></label>
      <div class="muted">${esc(gdPropNote(propDoc(GD.sel.prop || chests[0])))}</div></div>
    <div class="card"><b>Привал</b> ${rest ? `${rest.at.join(', ')} <button class="sm" data-gd="rest-del">✕</button><div class="muted">${esc(rest._comment || '')}</div><label>Где это<input id="gdRestNote" value="${esc(rest._comment || '')}" placeholder="у алтаря, у статуи…"></label>` : '<span class="muted">нет</span>'}
      <div class="muted">Привал ставится у алтаря или статуи, которые уже есть на картине. Там герой лечится, пополняет фляги, а простые враги комнаты встают снова.</div></div>
    <div class="card"><b>Вещи студии</b>${props.length ? props.map(([id, x, y], i) => `<div class="row" style="margin:0;gap:6px"><span class="grow">${esc(id)} <span class="muted">${x}, ${y}</span></span><button class="sm" data-gd="prop-del" data-i="${i}">✕</button></div>`).join('') : '<div class="muted">нет — вещи из таблиц комнаты не показаны</div>'}
      <div class="muted">Сундук с «item» даёт предмет раз за ночь; «curse» — проклятый; «requires_flag» прячет вещь до флага. Свойства вещи — во вкладке «Поведение» (data/props).</div></div>`;
  $('#gdBar_places').innerHTML = `<span class="muted grow">Зелёное — пол, красное — враги, золото — вещи студии, белый крест — привал. Комната перегенерируется после отправки (локально — сразу).</span>` + gdBar('places');
  gdPlacesDraw();
}
function gdPropNote(p) { const bits = []; if (p.item) bits.push(`предмет: ${p.item}`); if (p.curse) bits.push(`проклятие на ${p.curse} врагов`); if (p.requires_flag) bits.push(`ждёт флага ${p.requires_flag}`); if (p.ash) bits.push(`пепел ${p.ash}`); if (p.note) bits.push(`запись ${p.note}`); if (p.blood_price) bits.push(`цена кровью ${p.blood_price}`); return bits.join(' · ') || (p.kind ? `вид: ${p.kind}` : ''); }
async function gdPlacesDraw() {
  const room = await loadRoom(GD.sel.room), c = $('#gdCanvas_places'); if (!room || !c) return;
  GD.room = room;
  drawRoomOverview(c, room, null, '');
  const x = c.getContext('2d'), k = c.width / room.width;
  for (const [id, px, py] of gdDoc(GD_ROOMS)?.[room.name]?.props || []) { x.fillStyle = '#ffd75f'; x.fillRect(px * k - 4, py * k - 8, 8, 8); x.font = '11px system-ui'; x.fillText(id, px * k + 6, py * k - 6); }
  const rest = (gdDoc(GD_REST) || []).find(r => r.id === room.name);
  if (rest) { const [px, py] = rest.at; x.fillStyle = '#fff'; x.fillRect(px * k - 1.5, py * k - 14, 3, 12); x.fillRect(px * k - 5, py * k - 10, 10, 3); x.font = '11px system-ui'; x.fillText('привал', px * k + 8, py * k - 6); }
}
function gdPlaceAt(e) {
  const room = GD.room; if (!room) return;
  const rect = e.target.getBoundingClientRect(), px = (e.clientX - rect.left) / rect.width * room.width, py = (e.clientY - rect.top) / rect.height * room.height;
  const at = snapToSurface(room.surfaces, px, py); if (!at) return toast('Кликни над полом', 'err');
  const floor = at.y + 12;  // a rest point and a prop stand on the floor itself, an enemy's origin 12 px above it
  if ((GD.sel.place || 'rest') === 'rest') {
    const list = structuredClone(gdDoc(GD_REST) || []), r = list.find(o => o.id === room.name);
    if (r) r.at = [at.x, floor]; else list.push({ id: room.name, at: [at.x, floor] });
    gdPut(GD_REST, list);
  } else {
    const doc = structuredClone(gdDoc(GD_ROOMS) || {}), r = doc[room.name] ||= {};
    (r.props ||= []).push([GD.sel.prop || $('#gdPlaceProp').value, at.x, floor]); gdPut(GD_ROOMS, doc);
  }
  renderPlaces();
}
STUDIO_TABS.places = {
  label: 'Места', title: 'rest points and chests', tip: 'Привалы и сундуки на карте комнаты',
  paths: p => p === GD_REST || p === GD_ROOMS && Object.values(gdDoc(GD_ROOMS) || {}).some(r => r.props), strings: false,
  html: `<aside class="side lifeside" id="gdSide_places"></aside><main class="lifemain"><div class="lifebar" id="gdBar_places"></div><canvas id="gdCanvas_places" class="gdmap"></canvas></main>`,
  render: renderPlaces, enter: renderPlaces,
};

/* ---------- the tabs on the page ---------- */
// Puts every tab not yet on the page there: a file loaded after this one registers its tab and calls it again.
function gdInit() {
  const modes = $('.modes'); if (!modes) return;
  const ids = Object.keys(STUDIO_TABS).filter(m => !$('#gdLayout_' + m)); if (!ids.length) return;
  const style = document.createElement('style');
  style.textContent = ids.map(m => `body:not([data-mode=${m}]) #gdLayout_${m}`).join(',') + `{display:none!important}
    body:is(${ids.map(m => `[data-mode=${m}]`).join(',')}) :is(.layout,.bglayout,.cutlayout,.sndlayout,.riglayout,.lifelayout,.attacklayout,.shotlayout,.pfxlayout,.gorelayout,.dlglayout,.complayout){display:none!important}`;
  if (!$('#gdStyle')) style.textContent += `
    .gdlayout{display:grid;grid-template-columns:380px 1fr;height:calc(100vh - var(--hdr, 50px))}
    .gdlayout>main{min-width:0}.gdlayout>.side>*{flex:none}.gdscroll{flex:1;min-height:0;overflow:auto;padding:4px 8px}
    .gdstage{flex:1;min-height:0;width:100%;border-radius:6px;image-rendering:pixelated}.gdmap{width:100%;border-radius:6px;cursor:crosshair}
    .gdlist{display:flex;flex-wrap:wrap;gap:4px;max-height:34vh;overflow:auto}.gdlist .on{outline:2px solid #ffd75f}
    .gdloc{display:grid;grid-template-columns:44px 1fr;gap:6px;align-items:start;margin:2px 0}.gdloc span{font-size:11px;opacity:.7;padding-top:4px}.gdloc textarea{width:100%;resize:vertical;min-height:24px;font:inherit}
    .gdstr{margin:6px 0}.gdfields{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:4px 8px;margin:6px 0}.gdjson{width:100%;font:12px ui-monospace,monospace}
    .gdroom{display:grid;grid-template-columns:1fr 140px auto;gap:6px;align-items:center;margin:2px 0;font-size:12px}
    .gdamb{border-top:1px solid var(--line);padding:6px 0}.gdchips{display:flex;flex-wrap:wrap;gap:2px 10px;font-size:12px}.gdchips input,.gdlayout input[type=radio],.gdlayout input[type=checkbox]{width:auto;flex:none;margin:0 3px 0 0}
    .gdtable{width:100%;border-collapse:collapse;font-size:12px;margin:8px 0}.gdtable td,.gdtable th{border-bottom:1px solid var(--line);padding:3px 6px;text-align:left;vertical-align:top}
    .gdchapter{display:grid;gap:8px}.gdrooms{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}.gdroomcard{border:1px solid var(--line);border-radius:6px;padding:4px 8px;font-size:12px;min-width:150px}.gdfork{color:#ffd75f}
    @media (max-width:900px){.gdlayout{grid-template-columns:minmax(0,1fr);height:auto}.gdstage{min-height:260px}}`;
  if (!$('#gdStyle')) style.id = 'gdStyle';
  document.head.append(style);
  const anchor = [...document.querySelectorAll('.gdlayout')].pop() || $('#goreLayout');
  for (const m of ids) {
    const t = STUDIO_TABS[m], b = document.createElement('button');
    Object.assign(b.dataset, { act: 'mode', m }); b.textContent = t.label; b.title = t.tip; modes.append(b);
    const box = document.createElement('div'); box.id = 'gdLayout_' + m; box.className = 'gdlayout'; box.innerHTML = t.html; anchor.after(box);
    box.addEventListener('input', gdInput); box.addEventListener('change', gdInput); box.addEventListener('click', gdClick);
  }
  if (ids.includes('places')) $('#gdCanvas_places').addEventListener('click', gdPlaceAt);
}
async function gdEnter(m) {
  GD.tab = m;
  try { await gdLoad(); } catch (e) { $(`#gdLayout_${m} main`).innerHTML = `<div class="warn">Нет данных игры (import/gamedata.json, import/world.json): ${esc(e.message)}. Запусти tools/studio/build_data.py.</div>`; return; }
  trackChange(m); await STUDIO_TABS[m].enter();
}
function gdInput(e) {
  const el = e.target, m = GD.tab;
  if (el.dataset.gdStr) { gdSetStr(el.dataset.gdStr, el.dataset.loc, el.value); el.style.height = 'auto'; el.style.height = Math.min(160, el.scrollHeight + 2) + 'px';
    if (e.type === 'change') STUDIO_TABS[m].render(); return; }
  if (m === 'skins') {
    if (el.id === 'gdSkinAnim') { GD.sel.anim = el.value; return gdSkinSheet(); }
    if (el.id === 'gdSkinCompare') { GD.sel.compare = el.checked; return; }
    if (el.dataset.gdSkin && (e.type === 'change' || el.type === 'range' || el.type === 'color')) return gdSkinInput(el);
  }
  if (m === 'txt') {
    if (el.id === 'gdTxtQ') { GD.sel.q = el.value; clearTimeout(gdInput.t); gdInput.t = setTimeout(() => { renderTxt(); const q = $('#gdTxtQ'); q.focus(); q.setSelectionRange(q.value.length, q.value.length); }, 250); return; }
    if (el.id === 'gdTxtGroup') { GD.sel.group = el.value; return renderTxt(); }
    if (el.id === 'gdTxtOnly') { GD.sel.only = el.value; return renderTxt(); }
  }
  if (m === 'music' && e.type === 'change') {
    if (el.id === 'gdMood') { GD.sel.mood = el.value.replace(/ \(\d+\)$/, ''); return renderMusic(); }
    if (el.id === 'gdTrackAdd' && el.value) return gdTrackSet(el.value, GD.sel.mood, true);
    if (el.dataset.gdRoommusic) { const r = el.dataset.gdRoommusic, doc = structuredClone(gdDoc(GD_ROOMS) || {});
      if (el.value === GD.data.rooms[r]?.music) { if (doc[r]) { delete doc[r].music; if (!Object.keys(doc[r]).length) delete doc[r]; } } else (doc[r] ||= {}).music = el.value;
      gdPut(GD_ROOMS, doc); return renderMusic(); }
    if (el.dataset.gdAmb === 'match') return gdAmbEdit(rules => { rules[+el.dataset.i].match = el.value; });
    if (el.dataset.gdAmb === 'effect') return gdAmbEdit(rules => { const r = rules[+el.dataset.i], fx = new Set(r.effects || []); if (el.checked) fx.add(el.dataset.e); else fx.delete(el.dataset.e); r.effects = Object.keys(GD_EFFECTS).filter(x => fx.has(x)); });
  }
  if (m === 'run' && e.type === 'change') {
    if (el.id === 'gdKind') { GD.sel.kind = el.value; GD.sel.entry = 0; return renderRun(); }
    if (el.dataset.gdEntryJson) { try { const v = JSON.parse(el.value); gdEntryEdit(x => { x[el.dataset.gdEntryJson] = v; }); renderRun(); } catch (err) { toast('Не JSON: ' + err.message, 'err'); } return; }
    if (el.dataset.gdEntry) { const k = el.dataset.gdEntry; gdEntryEdit((x, list) => {
      if (k === 'id') { const id = el.value.trim(); if (!id || (list || []).some(o => o !== x && o.id === id)) return toast('Такой id уже есть', 'err');
        for (const f of ['name', 'description']) if (typeof x[f] === 'string' && x[f].includes(String(x.id).toUpperCase())) x[f] = x[f].replace(String(x.id).toUpperCase(), id.toUpperCase()); x.id = id; }
      else x[k] = el.type === 'number' ? +el.value : el.value; }); return renderRun(); }
  }
  if (m === 'story' && el.id === 'gdFlagQ') { GD.sel.flagq = el.value; clearTimeout(gdInput.t); gdInput.t = setTimeout(() => { renderStory(); const q = $('#gdFlagQ'); q.focus(); q.setSelectionRange(q.value.length, q.value.length); }, 250); return; }
  if (m === 'places' && e.type === 'change') {
    if (el.id === 'gdPlaceRoom') { GD.sel.room = el.value; return renderPlaces(); }
    if (el.name === 'gdPlace') { GD.sel.place = el.value; return; }
    if (el.id === 'gdPlaceProp') { GD.sel.prop = el.value; GD.sel.place = 'prop'; return renderPlaces(); }
    if (el.id === 'gdRestNote') { const list = structuredClone(gdDoc(GD_REST)), r = list.find(o => o.id === GD.sel.room); if (el.value) r._comment = el.value; else delete r._comment; gdPut(GD_REST, list); return renderPlaces(); }
  }
}
async function gdClick(e) {
  const b = e.target.closest('[data-gd],[data-gd-pick]'); if (!b) return;
  const m = GD.tab, act = b.dataset.gd;
  if (b.dataset.gdPick) { GD.sel[b.dataset.gdPick] = +b.dataset.i; return STUDIO_TABS[m].render(); }
  if (act === 'send') { try { await gdSend(m); } catch (err) { toast(err.message, 'err'); } return; }
  if (act === 'revert') { if (confirm('Отменить все несохранённые правки этой вкладки?')) gdRevert(m); return; }
  if (act === 'skin-add') { const list = structuredClone(gdDoc(GD_SKINS)); let n = 1; while (list.some(s => s.id === 'new_skin_' + n)) n++;
    const id = 'new_skin_' + n; list.push({ id, name: `SKIN_${id.toUpperCase()}_NAME`, description: `SKIN_${id.toUpperCase()}_DESC`, cloak: { hue: 0.6, saturation: 0.6, value: 0.85 }, unlock: { nights: 5 } });
    gdPut(GD_SKINS, list); GD.sel.skin = list.length - 1; return renderSkins(); }
  if (act === 'skin-del') { const list = structuredClone(gdDoc(GD_SKINS)); list.splice(GD.sel.skin || 0, 1); gdPut(GD_SKINS, list); GD.sel.skin = 0; return renderSkins(); }
  if (act === 'skin-kill-del') { gdSkinEdit(s => { delete s.unlock.kills[b.dataset.enemy]; if (!Object.keys(s.unlock.kills).length) delete s.unlock.kills; }); return renderSkins(); }
  if (act === 'txt-add') { const k = $('#gdTxtNew').value.trim().toUpperCase(); if (!/^[A-Z][A-Z0-9_]*$/.test(k)) return toast('Ключ: заглавные латинские, цифры, _', 'err'); if (gdHas(k)) { GD.sel.q = k; return renderTxt(); }
    gdSetStr(k, 'en', ''); GD.sel.q = k; GD.sel.group = ''; GD.sel.only = ''; return renderTxt(); }
  if (act === 'play') return gdPlay(b.dataset.slug);
  if (act === 'track-out') return gdTrackSet(b.dataset.slug, GD.sel.mood, false);
  if (act === 'amb-add') return gdAmbEdit(rules => rules.push({ match: 'room_name', effects: ['clouds'] }));
  if (act === 'amb-del') return gdAmbEdit(rules => rules.splice(+b.dataset.i, 1));
  if (act === 'amb-up') return gdAmbEdit(rules => { const i = +b.dataset.i; if (i > 0) [rules[i - 1], rules[i]] = [rules[i], rules[i - 1]]; });
  if (act === 'entry-add') {
    const kind = GD.sel.kind || 'items', id = $('#gdNewId').value.trim(), p = gdKindFiles(kind)[0];
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(id) || gdKindEntries(kind).some(x => x.e.id === id)) return toast('Нужен новый id: латиница, цифры, _', 'err');
    const doc = structuredClone(gdDoc(p)), entry = gdNewEntry(kind, id);
    if (kind === 'vials') entry.tier = [1, 2, 3, 4, 5].find(t => !gdKindEntries(kind).some(x => x.e.tier === t)) ?? 5;
    doc.push(entry); gdPut(p, doc);
    for (const k of [entry.name, entry.description]) if (k && !gdHas(k)) gdSetStr(k, 'en', '');
    GD.sel.entry = gdKindEntries(kind).length - 1; return renderRun();
  }
  if (act === 'entry-del') { if (!confirm('Убрать запись? Старые сохранения просто забудут её.')) return; gdEntryEdit((x, list) => list.splice(list.indexOf(x), 1)); GD.sel.entry = 0; return renderRun(); }
  if (act === 'rest-del') { gdPut(GD_REST, structuredClone(gdDoc(GD_REST)).filter(r => r.id !== GD.sel.room)); return renderPlaces(); }
  if (act === 'prop-del') { const doc = structuredClone(gdDoc(GD_ROOMS)), r = doc[GD.sel.room]; r.props.splice(+b.dataset.i, 1); if (!r.props.length) delete r.props; if (!Object.keys(r).length) delete doc[GD.sel.room]; gdPut(GD_ROOMS, doc); return renderPlaces(); }
}
if (typeof document !== 'undefined') gdInit();
