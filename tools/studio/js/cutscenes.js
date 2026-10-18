/* Sprite Studio — the cutscenes tab: steps, dialogue lines, the approximate preview. Plain scripts share one global scope; index.html loads them in order. */
'use strict';

/* ======================= ВКЛАДКА «КАТСЦЕНЫ» ======================= */
let cutData = null, cuts = [], CUT = null, cutStepSel = -1, cutRun = null, cutCur = -1, cutSkipped = new Set();
async function loadCutData() {
  if (cutData) return cutData;
  try { cutData = await (await fetch('import/cutscenes.json')).json(); }
  catch { cutData = { cutscenes: [], dialogues: {}, strings: {}, speakers: [], playlists: {} }; }
  return cutData;
}
const migrateCut = c => { c.kind = 'cutscene'; c.steps ||= []; c.dialogues ||= {}; c.strings ||= {}; c.images ||= {}; return c; };
let cutSaveTimer = null;
function saveCut() { if (!CUT) return; CUT.updated = Date.now(); CUT.dirty = true; trackChange('cut'); cutCheckSoon(); clearTimeout(cutSaveTimer); cutSaveTimer = setTimeout(() => { if (dbOk) DB.put(CUT, 'cutscenes').catch(() => {}); }, 400); }
async function cutUpsert(c) { const i = cuts.findIndex(x => x.id === c.id); if (i >= 0) cuts[i] = c; else cuts.push(c); if (dbOk) try { await DB.put(c, 'cutscenes'); } catch {} }
async function cutInit() { try { cuts = ((await DB.all('cutscenes')) || []).map(migrateCut); } catch { cuts = []; } let last = null; try { last = localStorage.getItem('ss_lastcut'); } catch {} CUT = cuts.find(c => c.id === last) || cuts[0] || null; }
async function importGameCutscenes() {
  const d = await loadCutData();
  if (!d.cutscenes.length) return toast('Катсцены игры недоступны: запусти студию из её папки и конвертер с --story', 'err');
  const kept = await mergeIncoming(d.cutscenes.map(c => JSON.parse(JSON.stringify(c))), cuts, c => cutUpsert(c), migrateCut);
  if (kept) toast(`Твои правки сохранены: ${kept}`);
  CUT = cuts.find(c => c.id === 'ch1_prologue') || cuts[0]; cutStepSel = -1; renderCutAll();
  toast(`Загружено катсцен: ${d.cutscenes.length}`);
}
const str = key => CUT?.strings[key]?.ru || cutData?.strings[key]?.ru || cutData?.strings[key]?.en || key || '';
const strEn = key => CUT?.strings[key]?.en ?? cutData?.strings[key]?.en ?? '';
const getDialogue = id => CUT?.dialogues[id] || cutData?.dialogues[id] || null;

const B3 = [['', '—'], ['true', 'да'], ['false', 'нет']];
const STEP_TYPES = {
  hold: { label: 'Забрать управление', fields: [] },
  release: { label: 'Вернуть управление', fields: [] },
  letterbox: { label: 'Кино-полосы', fields: [['on', 'bool', 'Показать'], ['time', 'num', 'Время, с']] },
  wait: { label: 'Пауза', fields: [['time', 'num', 'Время, с']] },
  camera: { label: 'Камера', fields: [['to', 'actor', 'К кому / точке'], ['between', 'json', 'Между двумя: ["player","boss"]'], ['zoom', 'num', 'Зум'], ['time', 'num', 'Время, с'], ['offset', 'point', 'Смещение']] },
  move: { label: 'Сдвинуть', fields: [['who', 'actor', 'Кого'], ['to', 'actor', 'Куда (актёр или [x,y])'], ['by', 'point', 'На сколько'], ['offset', 'point', 'Смещение'], ['time', 'num', 'Время, с'], ['ease', 'select', 'Плавность', [['', '—'], ['in', 'in'], ['out', 'out'], ['in_out', 'in_out']]]] },
  walk: { label: 'Идти', fields: [['who', 'actor', 'Кто'], ['to', 'actor', 'Куда'], ['by', 'point', 'На сколько'], ['offset', 'point', 'Смещение'], ['time', 'num', 'Время, с'], ['run', 'bool', 'Бегом']] },
  anim: { label: 'Анимация', fields: [['who', 'actor', 'Кто'], ['anim', 'text', 'Анимация (idle, draw, attack…)'], ['hold', 'bool', 'Замереть на 1-м кадре']] },
  face: { label: 'Повернуться', fields: [['who', 'actor', 'Кто'], ['dir', 'select', 'Куда', [['1', 'вправо'], ['-1', 'влево']]]] },
  dialogue: { label: 'Диалог', fields: [['id', 'dialogue', 'Диалог'], ['wait', 'bool', 'Ждать конца'], ['cast', 'json', 'Камера на говорящих: {"SPEAKER_ELIAN":"player"}'], ['zoom', 'num', 'Зум на говорящего']] },
  title: { label: 'Титр (имя босса)', fields: [['who', 'actor', 'Кто'], ['name', 'text', 'Своё имя (ключ строки)'], ['subtitle', 'text', 'Подзаголовок'], ['at', 'select', 'Где', [['', 'сверху'], ['top', 'сверху'], ['bottom', 'снизу']]], ['time', 'num', 'Время, с'], ['wait', 'bool', 'Ждать'], ['sound', 'sound', 'Звук']] },
  flash: { label: 'Вспышка', fields: [['color', 'color', 'Цвет'], ['strength', 'num', 'Сила 0–1'], ['time', 'num', 'Время, с']] },
  presence: { label: 'Присутствие во тьме', fields: [['at', 'actor', 'Где'], ['offset', 'point', 'Смещение'], ['color', 'color', 'Цвет'], ['radius', 'num', 'Радиус'], ['strength', 'num', 'Сила'], ['eyes', 'bool', 'Глаза'], ['time', 'num', 'Время, с'], ['on', 'bool', 'Показать']] },
  fx: { label: 'Эффект', fields: [['kind', 'select', 'Тип', [['ash', 'пепел'], ['sparkle', 'искры'], ['dust', 'пыль'], ['puff', 'дымок'], ['debris', 'обломки'], ['light', 'свет']]], ['at', 'actor', 'Где'], ['offset', 'point', 'Смещение'], ['color', 'color', 'Цвет'], ['amount', 'num', 'Количество']] },
  panel: { label: 'Картина на экран', fields: [['image', 'image', 'Картинка'], ['time', 'num', 'Появление, с'], ['drift', 'num', 'Наплыв (0.05)'], ['drift_time', 'num', 'Время наплыва, с'], ['pan', 'point', 'Панорама [x,y]']] },
  panel_clear: { label: 'Убрать картину', fields: [['time', 'num', 'Время, с']] },
  shake: { label: 'Тряска', fields: [['strength', 'num', 'Сила']] },
  sound: { label: 'Звук', fields: [['name', 'sound', 'Звук'], ['volume', 'num', 'Громкость, дБ']] },
  music: { label: 'Музыка', fields: [['name', 'music', 'Трек или настроение']] },
  fade: { label: 'Затемнение', fields: [['to', 'num', 'До (0 — убрать, 1 — чёрный)'], ['time', 'num', 'Время, с'], ['color', 'color', 'Цвет']] },
  appear: { label: 'Появиться', fields: [['who', 'actor', 'Кто'], ['time', 'num', 'Время, с']] },
  vanish: { label: 'Исчезнуть', fields: [['who', 'actor', 'Кто'], ['time', 'num', 'Время, с'], ['ash', 'bool', 'Рассыпаться пеплом']] },
};
const COND_FIELDS = [['if', 'list', 'Только если флаг (через запятую)'], ['unless', 'list', 'Только если НЕТ флагов'], ['path', 'select', 'Только на пути', [['', '—'], ['grace', 'благодать'], ['temptation', 'искушение'], ['will', 'воля']]]];
const pt = v => Array.isArray(v) ? `[${v.join(', ')}]` : (v ?? '');
function stepSummary(s) {
  const t = s.time != null ? ` · ${s.time}с` : '';
  switch (s.do) {
    case 'letterbox': return `${s.on === false ? 'убрать' : 'показать'}${t}`;
    case 'wait': return `${s.time ?? 0} с`;
    case 'camera': return `→ ${s.between ? JSON.stringify(s.between) : pt(s.to) || '—'}${s.zoom ? ' ×' + s.zoom : ''}${t}`;
    case 'move': case 'walk': return `${s.who || '?'} ${s.to ? '→ ' + pt(s.to) : s.by ? 'на ' + pt(s.by) : ''}${t}`;
    case 'anim': return `${s.who || '?'}: ${s.anim || ''}`;
    case 'face': return `${s.who || '?'} ${+s.dir < 0 ? '←' : '→'}`;
    case 'dialogue': { const d = getDialogue(s.id), n = d?.nodes?.[d.start]; return `${s.id}${n?.text ? ' — «' + str(n.text).slice(0, 40) + '…»' : ''}`; }
    case 'title': return s.name ? str(s.name) : (s.who || '');
    case 'flash': return `${s.color || '#fff'} ${s.strength ?? ''}${t}`;
    case 'fx': return `${s.kind || ''} @ ${pt(s.at)}`;
    case 'panel': return `${String(s.image || '').split('/').pop()}${t}`;
    case 'sound': case 'music': return `${s.name || ''}${s.volume != null ? ' ' + s.volume + ' дБ' : ''}`;
    case 'fade': return `до ${s.to ?? 1}${t}`;
    case 'shake': return `${s.strength ?? ''}`;
    case 'appear': case 'vanish': return `${s.who || ''}${s.ash ? ' пеплом' : ''}${t}`;
    default: return '';
  }
}
function renderCutSel() {
  $('#cutSel').innerHTML = cuts.slice().sort((a, b) => a.id.localeCompare(b.id)).map(c => `<option value="${esc(c.id)}" ${c === CUT ? 'selected' : ''}>${esc(c.id)}</option>`).join('') || '<option>—</option>';
}
function renderCutAll() { trackChange('cut'); renderCutSel(); $('#cutEmpty').style.display = CUT ? 'none' : ''; renderCutBgSel(); renderSteps(); renderStepEditor(); drawCutFrame(); cutCheck(); }
/* what validate_data.gd would refuse, before she sends it (lib.js cutProblems over the whole game's flags, this scene in it) */
let cutCheckTimer = 0;
function cutCheckSoon() { clearTimeout(cutCheckTimer); cutCheckTimer = setTimeout(cutCheck, 300); }
const cutDialogue = id => CUT?.dialogues[id] || DLG.work?.[id] || getDialogue(id);
const cutHasText = k => !!(CUT?.strings[k]?.ru || CUT?.strings[k]?.en || cutData?.strings[k]?.ru || cutData?.strings[k]?.en);
async function cutCheck() {
  const box = $('#cutChecks'); if (!box) return;
  if (!CUT) { box.innerHTML = ''; return; }
  let world = null; try { await gdLoad(); world = WORLD.data.files; } catch {}
  const files = {}, own = new Set(Object.keys(CUT.dialogues));
  for (const [p, doc] of Object.entries({ ...(world || {}), ...(WORLD?.work || {}) })) {
    if (p.startsWith('data/dialogues/')) { const keep = [].concat(doc).filter(d => !own.has(d?.id)); if (keep.length) files[p] = keep; continue; }
    files[p] = doc;
  }
  files[`data/cutscenes/${CUT.id}.json`] = { id: CUT.id, steps: CUT.steps };
  files['data/dialogues/~studio.json'] = Object.values(CUT.dialogues);
  const flags = world ? gdFlags(files, { read: GD.data.flags_read_in_code, set: GD.data.flags_set_in_code, tests: GD.data.flags_for_tests, awaited: GD.data.flags_awaited }) : null;
  const npcs = world ? new Set(Object.entries(files).filter(([p]) => p.startsWith('data/npcs/')).flatMap(([, d]) => [].concat(d).map(n => n?.id)).filter(Boolean)) : null;
  const known = new Set((library || []).map(e => e.res));
  const { err, warn } = cutProblems(CUT.steps, { dialogue: cutDialogue, key: cutHasText, npcs, flags,
    image: res => !!CUT.images[res] || !library || known.has(res) });
  box.innerHTML = !err.length && !warn.length ? '<div class="muted" style="padding:4px 2px">✓ Проверка: ошибок нет</div>'
    : `<div class="card" style="margin:6px 0;${err.length ? 'border-color:var(--err)' : ''}"><b>Проверка</b> <span class="muted">${err.length ? `ошибок: ${err.length} — игра не примет сцену, пока их не исправить` : 'ошибок нет, есть замечания'}</span>
      ${err.map(m => `<div class="warn" style="color:var(--err)">✕ ${esc(m)}</div>`).join('')}${warn.map(m => `<div class="warn">⚠ ${esc(m)}</div>`).join('')}</div>`;
}
function renderSteps() {
  if (!CUT) { $('#stepList').innerHTML = ''; return; }
  $('#stepList').innerHTML = CUT.steps.map((s, i) => {
    const cond = s.if || s.unless || s.path;
    return `<div class="srow ${i === cutStepSel ? 'on' : ''} ${i === cutCur ? 'play' : ''} ${cutSkipped.has(i) ? 'skipd' : ''}" data-act="cut-step" data-i="${i}"${cutSkipped.has(i) ? ' title="В этом просмотре условие не выполнилось — шаг пропущен"' : ''}>
      <span class="sn">${i + 1}</span><b>${esc(STEP_TYPES[s.do]?.label || s.do)}</b>
      <span class="ss">${esc(stepSummary(s))}</span>${cond ? `<span class="badge" title="${esc(JSON.stringify({ if: s.if, unless: s.unless, path: s.path }))}">условие</span>` : ''}
      <span class="grow"></span>
      <button class="sm ghost" data-act="cut-sup" title="Выше">▲</button><button class="sm ghost" data-act="cut-sdown" title="Ниже">▼</button>
      <button class="sm ghost" data-act="cut-sdup" title="Копия">⧉</button><button class="sm ghost danger" data-act="cut-sdel" title="Удалить">✕</button>
    </div>`;
  }).join('') || '<div class="muted" style="padding:8px">Шагов нет — добавь первый ниже</div>';
}
function fieldHtml(s, [k, type, label, opts]) {
  const v = s[k];
  const lab = `<label>${esc(label)}</label>`;
  switch (type) {
    case 'num': return `<div>${lab}<input type="number" step="any" data-sf="${k}" data-ft="num" value="${v ?? ''}"></div>`;
    case 'bool': return `<div>${lab}<select data-sf="${k}" data-ft="bool">${B3.map(([o, l]) => `<option value="${o}" ${String(v ?? '') === o ? 'selected' : ''}>${l}</option>`).join('')}</select></div>`;
    case 'select': return `<div>${lab}<select data-sf="${k}" data-ft="select">${opts.map(([o, l]) => `<option value="${esc(o)}" ${String(v ?? '') === o ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>`;
    case 'point': { const a = Array.isArray(v) ? v : ['', '']; return `<div>${lab}<div class="row" style="margin:0"><input type="number" step="any" data-sf="${k}" data-ft="point" data-pi="0" value="${a[0] ?? ''}" placeholder="x"><input type="number" step="any" data-sf="${k}" data-ft="point" data-pi="1" value="${a[1] ?? ''}" placeholder="y"></div></div>`; }
    case 'color': return `<div>${lab}<div class="row" style="margin:0"><input type="color" data-sf="${k}" data-ft="color" value="${/^#[0-9a-f]{6}$/i.test(v || '') ? v : '#ffffff'}" style="width:44px;height:30px;padding:2px"><input data-sf="${k}" data-ft="text" value="${esc(v ?? '')}" placeholder="#ffffff"></div></div>`;
    case 'json': return `<div class="wide">${lab}<input data-sf="${k}" data-ft="json" value="${esc(v != null ? JSON.stringify(v) : '')}"></div>`;
    case 'list': return `<div>${lab}<input data-sf="${k}" data-ft="list" list="dlCutFlags" value="${esc(Array.isArray(v) ? v.join(', ') : v ?? '')}"></div>`;
    case 'actor': return `<div>${lab}<input data-sf="${k}" data-ft="actor" list="dlActors" value="${esc(Array.isArray(v) ? JSON.stringify(v) : v ?? '')}"></div>`;
    case 'sound': return `<div>${lab}<div class="row" style="margin:0"><input data-sf="${k}" data-ft="text" list="dlSfx" value="${esc(v ?? '')}"><button class="sm" data-act="cut-try-sound" data-k="${k}">▶</button></div></div>`;
    case 'music': return `<div>${lab}<div class="row" style="margin:0"><input data-sf="${k}" data-ft="text" list="dlMusic" value="${esc(v ?? '')}"><button class="sm" data-act="cut-try-music" data-k="${k}">▶</button></div></div>`;
    case 'dialogue': return `<div class="wide">${lab}<div class="row" style="margin:0"><input data-sf="${k}" data-ft="text" list="dlDialogues" value="${esc(v ?? '')}"><button class="sm" data-act="cut-new-dlg">+ Новый диалог</button></div></div>`;
    case 'image': return `<div class="wide">${lab}<div class="row" style="margin:0"><input data-sf="${k}" data-ft="text" list="dlImages" value="${esc(v ?? '')}"><button class="sm" data-act="cut-img-up">⬆ Своя</button></div></div>`;
    default: return `<div>${lab}<input data-sf="${k}" data-ft="text" value="${esc(v ?? '')}"></div>`;
  }
}
function renderStepEditor() {
  const box = $('#stepEditor'), s = CUT?.steps[cutStepSel];
  if (!s) { box.innerHTML = '<div class="note">Выбери шаг слева, чтобы изменить его. «▶ С начала» — посмотреть всю катсцену, «▶ С шага» — с выбранного.</div>'; return; }
  const T = STEP_TYPES[s.do];
  box.innerHTML = `
    <div class="row" style="margin:0 0 6px"><h3 style="margin:0">Шаг ${cutStepSel + 1}</h3>
      <select data-sf="do" data-ft="do" style="width:auto">${Object.entries(STEP_TYPES).map(([k, v]) => `<option value="${k}" ${k === s.do ? 'selected' : ''}>${v.label} (${k})</option>`).join('')}${T ? '' : `<option selected>${esc(s.do)}</option>`}</select>
    </div>
    <div class="fgrid">${(T?.fields || []).map(f => fieldHtml(s, f)).join('')}</div>
    <details ${s.if || s.unless || s.path ? 'open' : ''}><summary class="muted">Условия</summary><div class="fgrid">${COND_FIELDS.map(f => fieldHtml(s, f)).join('')}</div></details>
    ${s.do === 'dialogue' ? '<div id="dlgEditor"></div>' : ''}
    ${s.do === 'panel' && s.image ? `<img class="ithumb" src="${esc(imgUrl(s.image))}" alt="" style="margin-top:8px">` : ''}
    <details><summary class="muted">JSON шага</summary><textarea id="stepJson" rows="4" spellcheck="false">${esc(JSON.stringify(s))}</textarea></details>`;
  if (s.do === 'dialogue') renderDialogueEditor(s.id);
}
function dialogueOrder(d) {
  const order = [], seen = new Set(), walk = id => { if (!id || seen.has(id) || !d.nodes[id]) return; seen.add(id); order.push(id); const n = d.nodes[id]; walk(n.next); (n.choices || []).forEach(c => walk(c.next)); (n.branches || []).forEach(b => walk(b.next)); };
  walk(d.start); Object.keys(d.nodes).forEach(walk); return order;
}
// who leads to a line: «после l3 · ответ 2» — so a branch reads as one
function dialogueIncoming(d) {
  const inc = {};
  for (const [k, n] of Object.entries(d.nodes)) {
    if (n.next) (inc[n.next] ||= []).push(k);
    (n.choices || []).forEach((c, i) => { if (c.next) (inc[c.next] ||= []).push(`${k} · ответ ${i + 1}`); });
    (n.branches || []).forEach(b => { if (b.next) (inc[b.next] ||= []).push(`${k} · развилка`); });
  }
  return inc;
}
const CUT_PATHS = [['grace', 'благодать'], ['temptation', 'искушение'], ['will', 'воля']];
const cutLineText = (key, loc) => { const v = loc === 'en' ? strEn(key) : str(key); return v === key ? '' : v; };
function cutNextSel(d, v, attr, self) {
  return `<select ${attr} style="width:auto;max-width:260px"><option value="">— конец диалога —</option>${Object.keys(d.nodes).filter(k => k !== self).map(k => `<option value="${esc(k)}"${k === v ? ' selected' : ''}>${esc(k)}${d.nodes[k].branches ? ' (развилка)' : ' — ' + esc(cutLineText(d.nodes[k].text, 'ru').slice(0, 30) || '(пусто)')}</option>`).join('')}</select>`;
}
function cutKnownFlags() {
  const f = new Set();
  const take = d => Object.values(d?.nodes || {}).forEach(n => { (n.branches || []).forEach(b => b.flag && f.add(b.flag)); (n.choices || []).forEach(c => (c.effect?.set_flags || []).forEach(x => f.add(x))); });
  Object.values(cutData?.dialogues || {}).forEach(take); cuts.forEach(c => { Object.values(c.dialogues).forEach(take); c.steps.forEach(s => [...cutFlagList(s.if), ...cutFlagList(s.unless)].forEach(x => f.add(x))); });
  return [...f].sort();
}
function renderDialogueEditor(id) {
  const box = $('#dlgEditor'), d = getDialogue(id); if (!box) return;
  if (!d) { box.innerHTML = `<div class="note">Диалога «${esc(id || '')}» нет. Нажми «+ Новый диалог».</div>`; return; }
  const sp = cutData?.speakers || [], inc = dialogueIncoming(d), caption = d.blocking === false;
  box.innerHTML = `<h3 style="margin:12px 0 4px">Реплики «${esc(d.id)}»${caption ? ' <span class="muted">(субтитры поверх игры — ответов в них не бывает)</span>' : ''}</h3>
    ${dialogueOrder(d).map(nid => {
      const n = d.nodes[nid], from = nid === d.start ? 'начало' : inc[nid] ? 'после ' + inc[nid].join(', ') : 'ни откуда не ведут';
      if (n.branches) return `<div class="dline muted">↳ ${esc(nid)}: развилка по флагам ${esc(n.branches.map(b => (b.flag ?? Object.values(b)[0]) + '→' + b.next).join(', '))}${n.next ? ', иначе → ' + esc(n.next) : ''}</div>`;
      return `<div class="dline" data-nid="${esc(nid)}">
        <div class="row" style="margin:0"><span class="muted">${esc(nid)}</span>
          <select data-dl="speaker" style="width:auto">${[n.speaker, ...sp.filter(x => x !== n.speaker)].filter(Boolean).map(k => `<option value="${esc(k)}">${esc(str(k))} (${esc(k)})</option>`).join('')}</select>
          <span class="muted" style="font-size:11px">${esc(from)}</span><span class="grow"></span>
          <button class="sm" data-act="dlg-voice" title="Озвучка этой реплики">🔊</button><button class="sm ghost danger" data-act="dlg-del-line" title="Удалить реплику (то, что вело в неё, поведёт дальше)">✕</button></div>
        <textarea data-dl="ru" rows="2" placeholder="Текст по-русски">${esc(cutLineText(n.text, 'ru'))}</textarea>
        <textarea data-dl="en" rows="1" placeholder="English">${esc(cutLineText(n.text, 'en'))}</textarea>
        ${(n.choices || []).map((c, i) => `<div class="card" style="margin:6px 0 0 18px;padding:6px 8px;background:var(--panel2)" data-ci="${i}">
          <div class="row" style="margin:0"><b>Ответ ${i + 1}</b><span class="grow"></span><button class="sm ghost danger" data-act="dlg-del-choice" title="Убрать ответ">✕</button></div>
          <textarea data-dc="ru" rows="1" placeholder="Ответ по-русски">${esc(cutLineText(c.text, 'ru'))}</textarea>
          <textarea data-dc="en" rows="1" placeholder="Answer in English">${esc(cutLineText(c.text, 'en'))}</textarea>
          <div class="row" style="margin:2px 0 0"><label style="margin:0" title="Флаг запоминает выбор: шаги катсцены после диалога могут идти только при нём («Условия» шага), его видят и другие диалоги">ставит флаги <input data-dc="flags" list="dlCutFlags" value="${esc((c.effect?.set_flags || []).join(', '))}" placeholder="например stayed_with_agnes" style="width:200px"></label>
            <span class="muted">→</span>${cutNextSel(d, c.next, 'data-dc="next"', nid)}
            <button class="sm" data-act="dlg-after-choice" title="Новая реплика, которую услышат только после этого ответа">＋ Реплика после ответа</button></div>
          <div class="row" style="margin:2px 0 0"><span class="muted" title="Сколько этот ответ добавляет к скрытому счётчику пути; шаги «Только на пути» и ауру героя решает тот, что впереди">путь:</span>${CUT_PATHS.map(([p, l]) => `<label style="margin:0">${l} <input type="number" step="1" data-dc="eff.${p}" value="${c.effect?.[p] ?? ''}" style="width:52px"></label>`).join('')}</div>
        </div>`).join('')}
        <div class="row" style="margin:4px 0 0">${n.choices?.length ? '' : `<span class="muted">дальше →</span>${cutNextSel(d, n.next, 'data-dl="next"', nid)}<button class="sm" data-act="dlg-after" title="Новая реплика сразу после этой">＋ Реплика после</button>`}
          <button class="sm" data-act="dlg-add-choice"${caption ? ' disabled title="В субтитрах выбора не бывает"' : ' title="Игрок выберет ответ; у каждого ответа — свои реплики и свои флаги"'}>＋ Ответ</button></div>
      </div>`;
    }).join('')}
    ${cutData?.dialogues[d.id] ? '' : `<div class="row"><label style="margin:0">Стиль окна <select data-dlook="style">${Object.entries((DLG.looks || cutData?.looks)?.styles || { default: {} }).map(([k, v]) => `<option value="${esc(k)}"${k === (d.look?.style || 'default') ? ' selected' : ''}>${esc(v.name || (k === 'default' ? 'как в игре' : k))}</option>`).join('')}</select></label>
      <label style="margin:0"><input type="checkbox" data-dlook="portrait"${Array.isArray(d.look?.portrait) ? ' checked' : ''}> окно портрета</label></div>`}
    <div class="note">Развилка сюжета: у реплики «＋ Ответ», у ответа — свои реплики («＋ Реплика после ответа») и флаг. Чтобы и дальше катсцена шла по-разному, открой нужный шаг после диалога → «Условия» → «Только если флаг» (или «Только если НЕТ флагов»). Ветки могут снова сойтись: выбери в «дальше →» общую реплику.</div>
    <div class="row"><button class="sm" data-act="dlg-add">+ Реплика в конец</button>${cutData?.dialogues[d.id] ? `<button class="sm" data-act="dg-open" data-id="${esc(d.id)}" title="Ответы, развилки, все четыре языка; окна перетаскиваются, стиль и портреты">Открыть во вкладке «Диалоги» (окна, стиль, портрет)</button>` : ''}</div>`;
}
// a fresh string key for a new line or answer, unused in the scene and in the game
function cutNewKey(base) { let k = base, i = 2; while (CUT.strings[k] || cutData?.strings[k]) k = `${base}_${i++}`; CUT.strings[k] = { ru: '', en: '' }; return k; }
function cutNewLine(d, speaker) {
  let n = Object.keys(d.nodes).length + 1, nid; do { nid = `l${n++}`; } while (d.nodes[nid]);
  d.nodes[nid] = { speaker: speaker || 'SPEAKER_ELIAN', text: cutNewKey(`DLG_${String(d.id).toUpperCase()}_${nid.toUpperCase()}`) };
  return nid;
}
function ownDialogue(id) {
  if (!CUT.dialogues[id]) { const src = getDialogue(id); if (!src) return null; CUT.dialogues[id] = JSON.parse(JSON.stringify(src)); }
  return CUT.dialogues[id];
}
const imgUrl = res => CUT?.images[res] || A(res);

/* ---- просмотр ---- */
const CW = 640, CH2 = 360;
const cs = { zoom: 1, bars: 0, fadeA: 0, fadeColor: '#000', flashA: 0, flashColor: '#fff', panel: null, title: null, line: null, choices: null, presence: null, shake: 0, label: '' };
let tweens = [], cutBgImg = null, musicSrc = null;
function tween(obj, key, to, dur) {
  tweens = tweens.filter(t => !(t.obj === obj && t.key === key));
  if (!dur) { obj[key] = to; return; }
  tweens.push({ obj, key, from: obj[key], to, t0: performance.now(), dur: dur * 1000 });
}
function resetCs() { Object.assign(cs, { zoom: 1, bars: 0, fadeA: 0, fadeColor: '#000', flashA: 0, panel: null, title: null, line: null, choices: null, presence: null, shake: 0, label: '' }); tweens = []; }
const imgCache = new Map();
function loadImg(src) { if (!imgCache.has(src)) imgCache.set(src, loadImage(src).catch(() => null)); return imgCache.get(src); }
function cover(x, im, scale = 1, px = 0, py = 0) {
  const k = Math.max(CW / im.width, CH2 / im.height) * scale, w = im.width * k, h = im.height * k;
  x.drawImage(im, (CW - w) / 2 + px, (CH2 - h) / 2 + py, w, h);
}
function wrap(x, text, maxW) {
  const words = String(text).split(/\s+/), lines = []; let cur = '';
  for (const w of words) { const t = cur ? cur + ' ' + w : w; if (x.measureText(t).width > maxW && cur) { lines.push(cur); cur = w; } else cur = t; }
  if (cur) lines.push(cur); return lines;
}
function drawCutFrame() {
  const c = $('#cutCanvas'); if (!c) return;
  if (c.width !== CW) { c.width = CW; c.height = CH2; }
  const x = c.getContext('2d'), now = performance.now();
  tweens = tweens.filter(t => { const k = Math.min(1, (now - t.t0) / t.dur); t.obj[t.key] = t.from + (t.to - t.from) * k; return k < 1; });
  x.save(); x.fillStyle = '#000'; x.fillRect(0, 0, CW, CH2);
  if (cs.shake > 0.1) { x.translate((Math.random() - 0.5) * cs.shake * 2, (Math.random() - 0.5) * cs.shake * 2); cs.shake *= 0.9; }
  if (cutBgImg) cover(x, cutBgImg, cs.zoom);
  else { x.fillStyle = '#1b1d24'; x.fillRect(0, 0, CW, CH2); x.fillStyle = '#3a3f4d'; x.font = '14px system-ui'; x.textAlign = 'center'; x.fillText('фон комнаты не выбран', CW / 2, CH2 / 2); }
  if (cs.panel?.img) { x.globalAlpha = cs.panel.alpha; const p = cs.panel, k = Math.min(1, (now - p.t0) / (p.driftTime * 1000)); cover(x, p.img, 1 + p.drift * k, (p.pan?.[0] || 0) * k, (p.pan?.[1] || 0) * k); x.globalAlpha = 1; }
  if (cs.fadeA > 0) { x.globalAlpha = Math.min(1, cs.fadeA); x.fillStyle = cs.fadeColor; x.fillRect(0, 0, CW, CH2); x.globalAlpha = 1; }
  if (cs.presence && cs.presence.a > 0) {
    const p = cs.presence, r = p.radius * (1 + 0.06 * Math.sin(now / 500)), g = x.createRadialGradient(CW / 2, CH2 * 0.45, 0, CW / 2, CH2 * 0.45, r);
    g.addColorStop(0, p.color); g.addColorStop(1, 'transparent'); x.globalAlpha = p.a; x.fillStyle = g; x.fillRect(0, 0, CW, CH2);
    if (p.eyes) { x.fillStyle = '#fff'; x.fillRect(CW / 2 - 14, CH2 * 0.45, 8, 2); x.fillRect(CW / 2 + 6, CH2 * 0.45, 8, 2); }
    x.globalAlpha = 1;
  }
  if (cs.flashA > 0) { x.globalAlpha = cs.flashA; x.fillStyle = cs.flashColor; x.fillRect(0, 0, CW, CH2); x.globalAlpha = 1; }
  const bh = CH2 * 0.1 * cs.bars; x.fillStyle = '#000'; x.fillRect(0, 0, CW, bh); x.fillRect(0, CH2 - bh, CW, bh);
  if (cs.title) {
    const y = cs.title.at === 'bottom' ? CH2 * 0.72 : CH2 * 0.3;
    x.textAlign = 'center'; x.fillStyle = '#f2e3b3'; x.font = '600 26px Georgia, serif'; x.fillText(cs.title.name, CW / 2, y);
    x.fillStyle = '#c9a85a'; x.fillRect(CW / 2 - 90, y + 9, 180, 1);
    if (cs.title.sub) { x.font = 'italic 13px Georgia, serif'; x.fillStyle = '#d8ccb0'; x.fillText(cs.title.sub, CW / 2, y + 28); }
  }
  // the line in the game's own window, with the dialogue's look (style, windows, portrait): the «Диалоги» tab draws it
  if (cs.line) {
    x.textAlign = 'left'; DLG.hit = []; DLG.win = [];
    dlgDrawLine(x, cs.line.d, cs.line.nid, cs.line.d.blocking === false ? 'caption' : 'panel', { S: str, hits: true });
    cutHits = DLG.hit; DLG.hit = []; DLG.win = [];
  }
  if (cs.label) { x.textAlign = 'left'; x.font = '11px system-ui'; x.fillStyle = 'rgba(0,0,0,.6)'; const w = x.measureText(cs.label).width; x.fillRect(6, 6, w + 12, 18); x.fillStyle = '#9fd4ff'; x.fillText(cs.label, 12, 19); }
  x.restore();
}
function cutLoop() { requestAnimationFrame(cutLoop); if (mode === 'cut') drawCutFrame(); }
function sleepTok(sec, tok) { return new Promise(r => { if (tok.stop || tok.instant || !sec) return r(); const t = setTimeout(r, sec * 1000); tok.wake.push(() => { clearTimeout(t); r(); }); }); }
// «⏭ Пропустить сцену»: what two presses do in the game — the step in hand cut short, a dialogue closed unanswered, the rest applied at once
function cutSkip() {
  if (!cutRun) return cutPlay(Math.max(0, cutStepSel), true);
  cutRun.instant = true; tweens.forEach(t => { t.obj[t.key] = t.to; }); tweens = []; cs.title = null; cs.flashA = 0;
  const w = cutRun.wake; cutRun.wake = []; w.forEach(f => f());
}
function cutStop() { if (cutRun) { cutRun.stop = true; cutRun.wake.forEach(f => f()); } cutRun = null; cutCur = -1; cutWaiter = null; cutHits = []; stopPreview(); stopMusic(); }
function stopMusic() { try { musicSrc?.stop(); } catch {} musicSrc = null; }
async function sfxUrl(name) {
  await loadSndLib();
  const e = sndEntry('sfx/' + name); if (!e) return null;
  const t = e.takes[Math.floor(Math.random() * e.takes.length)];
  return t.mod?.src ? { t } : t.url ? { t } : null;
}
async function playSfx(name, db = 0) {
  const r = await sfxUrl(name); if (!r) return 0;
  try { const buf = renderEdits(await takeBuffer(r.t), r.t.mod?.edits || {}); playBuf(buf, db, false); return buf.duration; } catch { return 0; }
}
async function playMusic(name) {
  await loadSndLib(); stopMusic();
  const track = (cutData?.playlists?.[name] || [name])[0];
  const e = sndEntry('music/' + track) || sndEntry('music/' + name); if (!e) return;
  try { const t = e.takes[0], buf = renderEdits(await takeBuffer(t), t.mod?.edits || {}); const s = playBuf(buf, -8, false); s.loop = true; musicSrc = s; } catch {}
}
async function voiceFor(key) {
  await loadSndLib(); const e = sndEntry('voice/ru/' + key); if (!e?.takes.length) return null;
  try { const t = e.takes[0]; return renderEdits(await takeBuffer(t), t.mod?.edits || {}); } catch { return null; }
}
/* the preview's story: what the answers chose so far — the steps' if / unless / path and the dialogues' routers read it (Cutscene._passes) */
const cutStory = { flags: new Set(), align: { grace: 0, temptation: 0, will: 0 }, lean: '' };
function cutResetStory() {
  const f = ($('#cutFlags')?.value || '').split(',').map(x => x.trim()).filter(Boolean);
  cutStory.flags = new Set(f); cutStory.align = { grace: 0, temptation: 0, will: 0 }; cutStory.lean = $('#cutPath')?.value || '';
}
function cutDominant() {   // Game.dominant_path: will unless another is ahead
  if (cutStory.lean) return cutStory.lean;
  let best = 'will'; for (const p of ['grace', 'temptation']) if (cutStory.align[p] > cutStory.align[best]) best = p; return best;
}
const cutFlagList = v => Array.isArray(v) ? v : (v == null || String(v) === '' ? [] : [String(v)]);
function cutPasses(s) {
  return cutFlagList(s.if).every(f => cutStory.flags.has(f)) && !cutFlagList(s.unless).some(f => cutStory.flags.has(f)) && (!s.path || cutDominant() === s.path);
}
function cutBranchHolds(b) {   // DialogueBox.branch_holds, as far as a preview knows: flags and the path
  if ('flag' in b) return cutStory.flags.has(b.flag);
  if ('path' in b) return cutDominant() === b.path;
  return false;
}
function cutChoose(ch) {
  const e = ch.effect || {};
  for (const f of e.set_flags || []) cutStory.flags.add(f);
  for (const p of ['grace', 'temptation', 'will']) if (e[p]) cutStory.align[p] += +e[p] || 0;
  cutShowStory();
}
function cutShowStory() { const el = $('#cutStoryNow'); if (el) el.textContent = cutStory.flags.size ? 'сейчас: ' + [...cutStory.flags].join(', ') : 'флагов пока нет'; }
/* a line waits for her, as the game does: «Дальше» (the panel, Space), «Пропустить», an answer (a click, 1–9); a caption also moves on by itself */
let cutWaiter = null, cutHits = [];
function cutAwait(tok, sec) {
  return new Promise(r => {
    let t = 0; const done = v => { clearTimeout(t); if (cutWaiter?.done === done) cutWaiter = null; r(v); };
    if (tok.stop) return r({ kind: 'stop' });
    if (sec) t = setTimeout(() => done({ kind: 'next' }), sec * 1000);
    cutWaiter = { done }; tok.wake.push(() => done({ kind: 'stop' }));
  });
}
function cutAnswer(v) { if (cutWaiter) cutWaiter.done(v); }
function cutCanvasClick(e) {
  if (!cutWaiter) return;
  const c = $('#cutCanvas'), r = c.getBoundingClientRect(), px = (e.clientX - r.left) * CW / r.width, py = (e.clientY - r.top) * CH2 / r.height;
  const inside = h => px >= h.r[0] && px <= h.r[0] + h.r[2] && py >= h.r[1] && py <= h.r[1] + h.r[3];
  const h = cutHits.find(h => h.choice !== undefined && inside(h)) || cutHits.find(h => h.choice === undefined && inside(h));
  if (!h) return;
  cutAnswer(h.choice !== undefined ? { kind: 'choice', i: h.choice } : h.skip ? { kind: 'skip' } : { kind: 'next' });
}
async function playDialogue(id, tok) {
  await dlgLoad().catch(() => {});   // the windows' looks, the portraits and the game's fonts
  // what the «Диалоги» tab has changed and not sent yet is what the scene shows
  const d = CUT?.dialogues[id] || DLG.work?.[id] || getDialogue(id); if (!d) { cs.label = `диалог «${id}» не найден`; await sleepTok(1, tok); return; }
  const caption = d.blocking === false;
  let nid = d.start, guard = 0;
  while (nid && !tok.stop && guard++ < 200) {
    const n = d.nodes[nid]; if (!n) break;
    if (n.branches) { const b = n.branches.find(cutBranchHolds); nid = b ? b.next : n.next; continue; }
    cs.line = { d, nid, speaker: str(n.speaker), text: str(n.text) };
    const vb = await voiceFor(n.text);
    let dur = Math.max(1.6, cs.line.text.length * 0.05);
    if (vb) { playBuf(vb, 0, true); dur = vb.duration + 0.3; }
    const hint = n.choices?.length ? 'выбери ответ (щелчок или 1–9)' : 'щёлкни «Дальше» или пробел';
    cs.label = caption ? `${d.id}: субтитр сменится сам` : `${d.id}: ${hint}`;
    let a; do a = await cutAwait(tok, caption ? dur : 0); while (n.choices?.length && a.kind !== 'stop' && a.kind !== 'skip' && !n.choices[a.i]);   // «дальше» does not answer
    if (a.kind === 'stop' || a.kind === 'skip') break;
    if (n.choices?.length) { const ch = n.choices[a.i]; cutChoose(ch); nid = ch.next; }
    else nid = n.next;
  }
  cs.line = null; cutHits = [];
}
async function runStep(s, tok) {
  const I = tok.instant, T = I ? 0 : s.time ?? 0;   // a skip: what is left applies at once, nothing is shown or heard (Cutscene._run instant)
  if (I && ['wait', 'dialogue', 'title', 'flash', 'shake', 'sound', 'fx'].includes(s.do)) return;
  cs.label = `${STEP_TYPES[s.do]?.label || s.do}: ${stepSummary(s)}${s.if || s.unless || s.path ? '  (с условием)' : ''}`;
  switch (s.do) {
    case 'letterbox': tween(cs, 'bars', s.on === false ? 0 : 1, T); return sleepTok(T, tok);
    case 'wait': return sleepTok(T, tok);
    case 'camera': tween(cs, 'zoom', s.to === 'player' ? 1 : (s.zoom ?? cs.zoom), T); return sleepTok(T, tok);
    case 'move': case 'walk': case 'appear': case 'vanish': return sleepTok(T, tok);
    case 'anim': case 'face': case 'hold': case 'release': case 'fx': return sleepTok(0.15, tok);
    case 'dialogue': {   // a dialogue in the bottom panel holds the scene whatever «wait» says (Cutscene._dialogue)
      const d = CUT?.dialogues[s.id] || DLG.work?.[s.id] || getDialogue(s.id), p = playDialogue(s.id, tok);
      if (s.wait !== false || d?.blocking !== false) await p; return;
    }
    case 'title': {
      cs.title = { name: s.name ? str(s.name) : s.who === 'boss' ? '«Имя босса»' : (s.who || ''), sub: s.subtitle ? str(s.subtitle) : s.who === 'boss' ? 'эпитет босса' : '', at: s.at };
      if (s.sound) playSfx(s.sound);
      const done = sleepTok(T || 1.8, tok).then(() => { cs.title = null; });
      if (s.wait !== false) await done; return;
    }
    case 'flash': cs.flashColor = s.color || '#fff'; cs.flashA = s.strength ?? 0.6; tween(cs, 'flashA', 0, T || 0.4); return;
    case 'shake': cs.shake = (s.strength ?? 4) * 1.5; return;
    case 'sound': playSfx(s.name, s.volume || 0); return;
    case 'music': playMusic(s.name); return;
    case 'fade': cs.fadeColor = s.color || '#000'; tween(cs, 'fadeA', s.to ?? 1, T); return sleepTok(T, tok);
    case 'panel': {
      const im = await loadImg(imgUrl(s.image));
      cs.panel = { img: im, alpha: T ? 0 : 1, drift: s.drift ?? 0.05, driftTime: s.drift_time ?? 8, pan: s.pan, t0: performance.now() };
      if (T) tween(cs.panel, 'alpha', 1, T); return sleepTok(T, tok);
    }
    case 'panel_clear': if (cs.panel) tween(cs.panel, 'alpha', 0, I ? 0 : T || 0.5); await sleepTok(T || 0.5, tok); cs.panel = null; return;
    case 'presence':
      if (s.on === false) { if (cs.presence) tween(cs.presence, 'a', 0, I ? 0 : T || 0.6); return sleepTok(T, tok); }
      cs.presence = { a: 0, color: s.color || '#d9e8ff', radius: s.radius || 90, eyes: s.eyes !== false }; tween(cs.presence, 'a', s.strength ?? 0.8, I ? 0 : T || 1); return sleepTok(T, tok);
    default: return sleepTok(0.1, tok);
  }
}
async function cutPlay(from = 0, instant = false) {
  if (!CUT) return;
  cutStop(); resetCs(); AC().resume?.();
  const tok = cutRun = { stop: false, wake: [], instant };
  cutResetStory(); cutShowStory(); cutSkipped = new Set();
  for (let i = from; i < CUT.steps.length && !tok.stop; i++) {
    cutCur = i;
    if (!cutPasses(CUT.steps[i])) { cutSkipped.add(i); renderSteps(); continue; }   // its condition does not hold: the game passes it by
    renderSteps(); await runStep(CUT.steps[i], tok);
  }
  if (cutRun === tok) { cutCur = -1; cs.label = tok.stop ? '' : tok.instant ? '⏭ сцена пропущена — так её оставит игра; ответов не было' : '■ конец катсцены'; cutRun = null; renderSteps(); setTimeout(stopMusic, 1500); }
}
function renderCutBgSel() {
  const sel = $('#cutBg'); if (!sel || sel.options.length > 1 || !library) return;
  sel.innerHTML = '<option value="">— без фона —</option>' + library.filter(e => e.cat === 'backgrounds' || e.cat === 'levels').map(e => `<option value="${esc(A(e.url))}">${esc(e.res.replace('res://assets/', ''))}</option>`).join('');
}
function fillFlagList() { const el = $('#dlCutFlags'); if (el) el.innerHTML = cutKnownFlags().map(v => `<option value="${esc(v)}">`).join(''); }
function fillDatalists() {
  fillFlagList();
  $('#dlActors').innerHTML = ['player', 'boss', 'door'].map(v => `<option value="${v}">`).join('');
  if (sndLib) {
    $('#dlSfx').innerHTML = [...new Set(sndLib.filter(e => e.cat === 'sfx').map(e => e.name))].map(v => `<option value="${esc(v)}">`).join('');
    $('#dlMusic').innerHTML = [...Object.keys(cutData?.playlists || {}), ...sndLib.filter(e => e.cat === 'music').map(e => e.name)].map(v => `<option value="${esc(v)}">`).join('');
  }
  if (cutData) $('#dlDialogues').innerHTML = [...new Set([...Object.keys(cutData.dialogues), ...cuts.flatMap(c => Object.keys(c.dialogues))])].map(v => `<option value="${esc(v)}">`).join('');
  if (library) $('#dlImages').innerHTML = library.filter(e => ['backgrounds', 'levels', 'cutscenes'].includes(e.cat) || e.res.includes('/cutscenes/')).map(e => `<option value="${esc(e.res)}">`).join('');
}

/* ---- экспорт катсцены ---- */
async function exportCut() {
  if (!CUT) return; if (typeof JSZip === 'undefined') return toast('Нет zip-библиотеки (нужен интернет)', 'err');
  const r = await cutFiles(), zip = new JSZip();
  for (const [path, b] of Object.entries(r.files)) zip.file(path, b);
  zip.file('README.md', [`# Катсцена ${r.id}`, '', 'Файлы разложены по путям игры (относительно корня репозитория) и уже слиты с текущими: strings.csv, диалоги и data/backdrops.json можно класть поверх.', '', ...r.notes, '', 'После — проверка данных: scripts/tools/validate_data.gd.'].join('\n'));
  download(await zip.generateAsync({ type: 'blob' }), `${r.id}_cutscene.zip`);
  toast('Катсцена экспортирована');
}

/* ---- события звуков и катсцен ---- */
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-act]'); if (!b) return;
  const act = b.dataset.act;
  if (act.startsWith('snd-')) {
    const row = e.target.closest('[data-key]'); const key = row?.dataset.key || sndSel;
    const ent = key && sndEntry(key), take = e.target.closest('[data-stem]')?.dataset.stem;
    const t = ent?.takes.find(x => x.stem === (take || sndTake));
    AC().resume?.();
    switch (act) {
      case 'snd-cat': sndCat = b.dataset.c; renderSndList(); break;
      case 'snd-sel': sndSel = key; sndTake = null; renderSndList(); renderSndMain(); break;
      case 'snd-quick': { e.stopPropagation(); const tk = ent.takes[Math.floor(Math.random() * ent.takes.length)]; try { playBuf(renderEdits(await takeBuffer(tk), tk.mod?.edits || {})); } catch (err) { toast(err.message, 'err'); } break; }
      case 'snd-take': sndTake = take; renderSndMain(); break;
      case 'snd-play-orig': try { playBuf(await decodeUrl(A(t.url))); } catch (err) { toast(err.message, 'err'); } break;
      case 'snd-play-cur': case 'snd-play-edit': try { playBuf(renderEdits(await takeBuffer(t), t.mod?.edits || {})); } catch (err) { toast(err.message, 'err'); } break;
      case 'snd-stop': stopPreview(); break;
      case 'snd-up': { const [f] = await pickFiles('audio/*,.wav,.mp3,.ogg', false); if (f) await sndSetSrc(ent, t.stem, f); break; }
      case 'snd-rec': await toggleRecord(ent, t.stem); break;
      case 'snd-reset': { const m = sndMods.get(ent.key); if (m) { if (t.orig) delete m.takes[t.stem]; else m.takes[t.stem] = { src: null, edits: { ...EDIT_DEFAULT } }; saveSnd(m); } renderSndList(); renderSndMain(); break; }
      case 'snd-del-take': { const m = sndMods.get(ent.key); delete m.takes[t.stem]; saveSnd(m); sndTake = null; renderSndList(); renderSndMain(); break; }
      case 'snd-add-take': {
        const used = new Set(ent.takes.map(x => x.stem)); let n = 1; while (used.has(`${ent.name}_${n}`)) n++;
        const m = sndMod(ent); m.takes[`${ent.name}_${n}`] = { src: null, edits: { ...EDIT_DEFAULT } }; saveSnd(m); sndTake = `${ent.name}_${n}`; renderSndMain(); toast('Вариант добавлен — загрузи файл или запиши'); break;
      }
      case 'snd-new': {
        const name = prompt(sndCat === 'voice' ? 'Ключ реплики (например DLG_CH1_MY_LINE):' : sndCat === 'music' ? 'Имя трека латиницей:' : 'Имя звука латиницей (например archer_attack):'); if (!name) return;
        const nm = sndCat === 'voice' ? name.trim() : slug(name), loc = sndCat === 'voice' ? $('#sndLocale').value : null;
        const keyN = sndCat === 'voice' ? `voice/${loc}/${nm}` : `${sndCat}/${nm}`;
        if (sndEntry(keyN)) { sndSel = keyN; renderSndList(); renderSndMain(); return toast('Такой звук уже есть — открыл его'); }
        const m = { id: keyN, cat: sndCat, name: nm, locale: loc, isNew: true, takes: { [nm]: { src: null, edits: { ...EDIT_DEFAULT } } } };
        sndMods.set(keyN, m); saveSnd(m); sndSel = keyN; sndTake = nm; renderSndList(); renderSndMain(); break;
      }
      case 'snd-export': exportSounds().catch(err => toast('Ошибка экспорта: ' + err.message, 'err')); break;
    }
    return;
  }
  if (!act.startsWith('cut-') && !act.startsWith('dlg-')) return;
  const s = CUT?.steps[cutStepSel];
  switch (act) {
    case 'cut-new': {
      const id = prompt('Имя катсцены латиницей:', 'my_cutscene'); if (!id) return;
      CUT = migrateCut({ id: slug(id), steps: [{ do: 'hold' }, { do: 'letterbox', on: true, time: 0.4 }, { do: 'wait', time: 1 }, { do: 'letterbox', on: false, time: 0.3 }, { do: 'release' }], updated: Date.now() });
      await cutUpsert(CUT); cutStepSel = -1; renderCutAll(); break;
    }
    case 'cut-del':
      if (!CUT || !confirm(`Удалить катсцену «${CUT.id}» из студии?`)) return;
      try { await DB.del(CUT.id, 'cutscenes'); } catch {}
      cuts = cuts.filter(c => c !== CUT); CUT = cuts[0] || null; cutStepSel = -1; renderCutAll(); break;
    case 'cut-game': await importGameCutscenes(); fillDatalists(); break;
    case 'cut-save': if (CUT) download(new Blob([JSON.stringify(CUT)], { type: 'application/json' }), `${CUT.id}.cutscene.json`); break;
    case 'cut-open': {
      const [f] = await pickFiles('.json,application/json', false); if (!f) return;
      let c; try { c = JSON.parse(await f.text()); } catch (err) { return toast('Не прочитать файл: ' + err.message, 'err'); }
      if (!Array.isArray(c.steps)) return toast('Это не катсцена', 'err');
      if (!c.id) c.id = slug(f.name.replace(/\..*$/, ''));
      CUT = migrateCut(c); await cutUpsert(CUT); renderCutAll(); toast('Катсцена открыта'); break;
    }
    case 'cut-export': exportCut().catch(err => toast('Ошибка экспорта: ' + err.message, 'err')); break;
    case 'cut-play': cutPlay(0); break;
    case 'cut-play-from': cutPlay(Math.max(0, cutStepSel)); break;
    case 'cut-stop': cutStop(); resetCs(); renderSteps(); break;
    case 'cut-skip': cutSkip(); break;
    case 'cut-step': cutStepSel = +b.dataset.i; renderSteps(); renderStepEditor(); break;
    case 'cut-sup': case 'cut-sdown': case 'cut-sdup': case 'cut-sdel': {
      const i = +e.target.closest('[data-i]').dataset.i, st = CUT.steps;
      if (act === 'cut-sdel') { st.splice(i, 1); cutStepSel = Math.min(cutStepSel, st.length - 1); }
      else if (act === 'cut-sdup') { st.splice(i + 1, 0, JSON.parse(JSON.stringify(st[i]))); cutStepSel = i + 1; }
      else { const j = i + (act === 'cut-sup' ? -1 : 1); if (j < 0 || j >= st.length) return; [st[i], st[j]] = [st[j], st[i]]; cutStepSel = j; }
      saveCut(); renderSteps(); renderStepEditor(); break;
    }
    case 'cut-add': {
      const type = $('#stepType').value, ns = { do: type };
      Object.assign(ns, { letterbox: { on: true, time: 0.4 }, wait: { time: 1 }, camera: { to: 'player', zoom: 1.2, time: 1 }, flash: { color: '#ffffff', strength: 0.6, time: 0.4 }, fade: { to: 1, time: 0.6 }, sound: { name: 'bell', volume: 0 }, shake: { strength: 4 }, panel: { image: '', time: 0.6, drift: 0.05 }, title: { who: 'boss', time: 1.8 }, dialogue: { id: '' } }[type] || {});
      const at = cutStepSel >= 0 ? cutStepSel + 1 : CUT.steps.length;
      CUT.steps.splice(at, 0, ns); cutStepSel = at; saveCut(); renderSteps(); renderStepEditor(); break;
    }
    case 'cut-try-sound': AC().resume?.(); playSfx(s?.[b.dataset.k] || ''); break;
    case 'cut-try-music': AC().resume?.(); playMusic(s?.[b.dataset.k] || ''); setTimeout(stopMusic, 8000); break;
    case 'cut-img-up': {
      const [f] = await pickFiles('image/*', false); if (!f) return;
      const src = await normalizeImage(await blobToDataURL(f), 1280);
      let n = 1, res; do { res = `res://assets/cutscenes/${CUT.id}_${n++}.png`; } while (CUT.images[res]);
      CUT.images[res] = src; s.image = res; saveCut(); renderSteps(); renderStepEditor(); break;
    }
    case 'cut-new-dlg': {
      let n = 1, id; do { id = `${CUT.id}_dlg${n++}`; } while (getDialogue(id));
      const key = `DLG_${id.toUpperCase()}_1`;
      CUT.dialogues[id] = { id, start: 'l1', nodes: { l1: { speaker: 'SPEAKER_ELIAN', text: key } } };
      CUT.strings[key] = { ru: '', en: '' }; s.id = id; saveCut(); fillDatalists(); renderSteps(); renderStepEditor(); break;
    }
    case 'dlg-add': {
      const d = ownDialogue(s.id), order = dialogueOrder(d); let last = order.reverse().find(k => !d.nodes[k].choices && !d.nodes[k].branches && !d.nodes[k].next);
      let n = Object.keys(d.nodes).length + 1, nid; do { nid = `l${n++}`; } while (d.nodes[nid]);
      const key = `DLG_${String(d.id).toUpperCase()}_${nid.toUpperCase()}`;
      d.nodes[nid] = { speaker: (last && d.nodes[last].speaker) || 'SPEAKER_ELIAN', text: key };
      if (last) d.nodes[last].next = nid; else if (!d.start) d.start = nid;
      CUT.strings[key] = { ru: '', en: '' }; saveCut(); renderDialogueEditor(s.id); break;
    }
    case 'dlg-add-choice': case 'dlg-del-choice': case 'dlg-after': case 'dlg-after-choice': case 'dlg-del-line': {
      const nid = e.target.closest('[data-nid]').dataset.nid, ci = +(e.target.closest('[data-ci]')?.dataset.ci ?? -1), d = ownDialogue(s.id), n = d.nodes[nid];
      if (act === 'dlg-add-choice') {
        n.choices ||= []; const i = n.choices.length + 1;
        n.choices.push({ id: `answer${i}`, text: cutNewKey(`${n.text || 'DLG_' + String(d.id).toUpperCase() + '_' + nid.toUpperCase()}_ANS${i}`), ...(n.next ? { next: n.next } : {}) });
        delete n.next;
      } else if (act === 'dlg-del-choice') {
        const [c] = n.choices.splice(ci, 1); if (!n.choices.length) { delete n.choices; if (c.next) n.next = c.next; }
      } else if (act === 'dlg-after') {
        const id = cutNewLine(d, dlgReplyBy(d, n.speaker)); if (n.next) d.nodes[id].next = n.next; n.next = id;
      } else if (act === 'dlg-after-choice') {
        const c = n.choices[ci], id = cutNewLine(d, dlgReplyBy(d, n.speaker)); if (c.next) d.nodes[id].next = c.next; c.next = id;
      } else {
        if (!confirm(`Удалить реплику ${nid}?`)) return;
        const to = n.next || ''; delete d.nodes[nid]; dlgRenameRefs(d, nid, to);
        const clean = o => { if (o.next === '') delete o.next; }; Object.values(d.nodes).forEach(m => { clean(m); (m.choices || []).forEach(clean); (m.branches || []).forEach(clean); });
        if (d.start === nid) d.start = to || Object.keys(d.nodes)[0] || '';
      }
      saveCut(); renderSteps(); renderDialogueEditor(s.id); break;
    }
    case 'dlg-voice': {
      const nid = e.target.closest('[data-nid]').dataset.nid, d = getDialogue(s.id), key = d.nodes[nid].text;
      setMode('snd'); await loadSndLib(); sndCat = 'voice'; $('#sndLocale').value = 'ru';
      const k = `voice/ru/${key}`;
      if (!sndEntry(k)) { const m = { id: k, cat: 'voice', name: key, locale: 'ru', isNew: true, takes: { [key]: { src: null, edits: { ...EDIT_DEFAULT } } } }; sndMods.set(k, m); saveSnd(m); }
      sndSel = k; sndTake = null; renderSndList(); renderSndMain(); break;
    }
  }
});
document.addEventListener('input', e => {
  const t = e.target;
  if (t.id === 'sndSearch' || t.id === 'sndOnlyMod' || t.id === 'sndLocale') return renderSndList();
  if (t.dataset.se) {
    const ent = sndEntry(sndSel), tk = ent?.takes.find(x => x.stem === sndTake); if (!tk) return;
    const m = sndMod(ent); m.takes[tk.stem] ||= { src: null, edits: { ...EDIT_DEFAULT } };
    const ed = m.takes[tk.stem].edits ||= { ...EDIT_DEFAULT };
    ed[t.dataset.se] = t.type === 'checkbox' ? t.checked : (+t.value || 0); saveSnd(m);
    takeBuffer({ ...tk, mod: m.takes[tk.stem] }).then(buf => drawWave(buf, ed)).catch(() => {});
    renderSndList(); return;
  }
  if (t.id === 'cutBg') { cutBgImg = null; if (t.value) loadImg(t.value).then(im => { cutBgImg = im; }); try { localStorage.setItem('ss_cutbg', t.value); } catch {} return; }
  if (!CUT) return;
  const s = CUT.steps[cutStepSel];
  if (t.id === 'stepJson') { try { const v = JSON.parse(t.value); if (v && v.do) { CUT.steps[cutStepSel] = v; saveCut(); renderSteps(); t.style.outline = ''; } } catch { t.style.outline = '1px solid var(--err)'; } return; }
  if (t.dataset.sf && s) {
    const k = t.dataset.sf, ft = t.dataset.ft; let v = t.value;
    if (ft === 'do') { CUT.steps[cutStepSel] = { do: v }; saveCut(); renderSteps(); renderStepEditor(); return; }
    if (ft === 'num') v = v === '' ? undefined : +v;
    else if (ft === 'bool') v = v === '' ? undefined : v === 'true';
    else if (ft === 'select') v = v === '' ? undefined : (k === 'dir' ? +v : v);
    else if (ft === 'point') { const a = Array.isArray(s[k]) ? [...s[k]] : [0, 0]; a[+t.dataset.pi] = +t.value || 0; v = a; }
    else if (ft === 'json') { if (v.trim() === '') v = undefined; else { try { v = JSON.parse(v); t.style.outline = ''; } catch { t.style.outline = '1px solid var(--err)'; return; } } }
    else if (ft === 'list') { const a = v.split(',').map(x => x.trim()).filter(Boolean); v = a.length ? (k === 'if' && a.length === 1 ? a[0] : a) : undefined; }
    else if (ft === 'actor') { v = v.trim(); if (v.startsWith('[')) { try { v = JSON.parse(v); } catch {} } if (v === '') v = undefined; }
    else if (ft === 'color') { const tx = t.parentElement.querySelector('[data-ft="text"]'); if (tx) tx.value = v; }
    else v = v === '' ? undefined : v;
    if (v === undefined) delete s[k]; else s[k] = v;
    saveCut(); renderSteps();
    const js = $('#stepJson'); if (js) js.value = JSON.stringify(s);
    if (k === 'id' && s.do === 'dialogue') renderDialogueEditor(s.id);
    return;
  }
  if (t.dataset.dlook && s?.do === 'dialogue') {   // a scene's own dialogue: its window's style and portrait
    const d = ownDialogue(s.id); d.look ||= {};
    if (t.dataset.dlook === 'style') { if (t.value === 'default') delete d.look.style; else d.look.style = t.value; }
    else if (t.checked) d.look.portrait = [...LOOK_HOME.portrait]; else delete d.look.portrait;
    if (!Object.keys(d.look).length) delete d.look;
    saveCut(); return;
  }
  if (t.dataset.dc && s?.do === 'dialogue') {
    const nid = t.closest('[data-nid]').dataset.nid, d = ownDialogue(s.id), c = d.nodes[nid].choices[+t.closest('[data-ci]').dataset.ci], f = t.dataset.dc;
    if (f === 'next') { if (t.value) c.next = t.value; else delete c.next; saveCut(); renderDialogueEditor(s.id); return; }
    if (f.startsWith('eff.')) {
      const p = f.slice(4), v = t.value.trim() === '' ? 0 : Math.round(+t.value) || 0; c.effect ||= {};
      if (v) c.effect[p] = v; else delete c.effect[p];
      if (!Object.keys(c.effect).length) delete c.effect;
      saveCut(); cutCheck(); return;
    }
    if (f === 'flags') {
      const a = t.value.split(',').map(x => x.trim()).filter(Boolean); c.effect ||= {};
      if (a.length) c.effect.set_flags = a; else delete c.effect.set_flags;
      if (!Object.keys(c.effect).length) delete c.effect;
      saveCut(); fillFlagList(); return;
    }
    const key = c.text; CUT.strings[key] ||= { ru: cutData?.strings[key]?.ru ?? '', en: cutData?.strings[key]?.en ?? '' }; CUT.strings[key][f] = t.value;
    saveCut(); return;
  }
  if (t.dataset.dl === 'next' && s?.do === 'dialogue') {
    const n = ownDialogue(s.id).nodes[t.closest('[data-nid]').dataset.nid]; if (t.value) n.next = t.value; else delete n.next;
    saveCut(); renderDialogueEditor(s.id); return;
  }
  if (t.dataset.dl && s?.do === 'dialogue') {
    const nid = t.closest('[data-nid]').dataset.nid, d = ownDialogue(s.id), n = d.nodes[nid];
    if (t.dataset.dl === 'speaker') n.speaker = t.value;
    else { const key = n.text; CUT.strings[key] ||= { ru: cutData?.strings[key]?.ru ?? '', en: cutData?.strings[key]?.en ?? '' }; CUT.strings[key][t.dataset.dl] = t.value; }
    saveCut(); renderSteps();
  }
});
$('#cutCanvas').addEventListener('click', cutCanvasClick);
document.addEventListener('keydown', e => {
  if (mode !== 'cut' || !cutWaiter || e.target.closest?.('input,textarea,select')) return;
  if (/^[1-9]$/.test(e.key)) { e.preventDefault(); cutAnswer({ kind: 'choice', i: +e.key - 1 }); }
  else if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); cutAnswer({ kind: 'next' }); }
  else if (e.key === 'Escape') cutAnswer({ kind: 'skip' });
});
$('#cutSel').addEventListener('change', e => { const c = cuts.find(x => x.id === e.target.value); if (!c) return; cutStop(); CUT = c; cutStepSel = -1; try { localStorage.setItem('ss_lastcut', c.id); } catch {} renderCutAll(); });
async function enterStoryMode(m) {
  if (m === 'snd') { await loadSndLib(); await loadCutData(); trackChange('snd'); renderSndList(); renderSndMain(); }
  if (m === 'cut') {
    await loadCutData(); await loadSndLib();
    if (!library) { try { library = await (await fetch('import/library.json')).json(); } catch {} }
    if (!cuts.length && cutData.cutscenes.length && !enterStoryMode.tried) { enterStoryMode.tried = true; await importGameCutscenes(); }
    fillDatalists(); renderCutAll();
    try { const bg = localStorage.getItem('ss_cutbg'); if (bg && $('#cutBg').value !== bg) { $('#cutBg').value = bg; if ($('#cutBg').value) loadImg(bg).then(im => { cutBgImg = im; }); } } catch {}
  }
}
