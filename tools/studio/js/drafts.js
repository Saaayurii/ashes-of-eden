/* Three-way draft merging. Baselines travel with the project, never with credentials. */
'use strict';
const sameDraft = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const draftClone = a => a === undefined ? undefined : structuredClone(a);
function mergeDraft(base, mine, latest, path = '', conflicts = []) {
  if (sameDraft(mine, base)) return draftClone(latest);
  if (sameDraft(latest, base) || sameDraft(mine, latest)) return draftClone(mine);
  const obj = v => v && typeof v === 'object' && !Array.isArray(v);
  if ([base, mine, latest].every(Array.isArray) && base.length === mine.length && base.length === latest.length && base.every((v, i) => obj(v) && obj(mine[i]) && obj(latest[i]) && ['id','name','type','animation'].every(k => v[k] === mine[i][k] && v[k] === latest[i][k]))) {
    return base.map((v, i) => mergeDraft(v, mine[i], latest[i], path ? `${path}.${i}` : String(i), conflicts));
  }

  if (obj(base) && obj(mine) && obj(latest)) {
    const result = {};
    for (const k of new Set([...Object.keys(base), ...Object.keys(mine), ...Object.keys(latest)])) {
      const v = mergeDraft(base[k], mine[k], latest[k], path ? `${path}.${k}` : k, conflicts);
      if (v !== undefined) result[k] = v;
    }
    return result;
  }
  conflicts.push({ path, base: draftClone(base), mine: draftClone(mine), latest: draftClone(latest) });
  return draftClone(latest);
}
function draftPut(root, path, value) {
  if (!path) return draftClone(value);
  const keys = path.split('.'); let o = root;
  for (const k of keys.slice(0, -1)) o = o[k];
  if (value === undefined) delete o[keys.at(-1)]; else o[keys.at(-1)] = draftClone(value);
  return root;
}
async function resolveDraft(base, mine, latest, label, uncertain = false) {
  const conflicts = []; let result = mergeDraft(base, mine, latest, '', conflicts);
  if (uncertain && !sameDraft(mine, latest)) {
    conflicts.splice(0); conflicts.push({ path: '', base: undefined, mine, latest }); result = draftClone(latest);
  }
  if (!conflicts.length) return result;
  return new Promise((resolve, reject) => {
    const fmt = v => v === undefined ? 'удалено / неизвестно' : JSON.stringify(v, null, 2);
    dialog(`<h3>Совместить изменения: ${esc(label)}</h3><p>Данные игры изменились после начала работы. Выбери значение каждого спорного поля.${uncertain ? ' У старого черновика нет исходной версии: проверь его целиком.' : ''}</p>` +
      conflicts.map((c, i) => `<div class="card"><b>${esc(c.path || label)}</b><div class="draftcompare"><div>Было<pre>${esc(fmt(c.base))}</pre></div><div>В игре<pre>${esc(fmt(c.latest))}</pre></div><div>Мой черновик<pre>${esc(fmt(c.mine))}</pre></div></div><label>Сохранить<select data-conflict="${i}"><option value="latest">Из игры</option><option value="mine">Из черновика</option></select></label></div>`).join(''),
      [['Отмена', () => reject(new Error('Совмещение отменено; черновик сохранён.'))], ['Продолжить', () => { for (const [i, c] of conflicts.entries()) result = draftPut(result, c.path, c[$(`[data-conflict="${i}"]`).value]); resolve(result); }]]);
    $('#dlg').addEventListener('cancel', () => reject(new Error('Совмещение отменено')), { once: true });
  });
}
const BASES = (() => { try { return typeof localStorage === 'undefined' ? {} : JSON.parse(localStorage.getItem('ss_bases') || '{}'); } catch { return {}; } })();
function draftBase(key, value, legacy = false) {
  if (!BASES[key]) { BASES[key] = { value: draftClone(value), sha: typeof META !== 'undefined' ? META.sha : '', uncertain: legacy }; draftBasesSave(); }
  return BASES[key].value;
}
function draftBasesSave() { if (typeof localStorage !== 'undefined') localStorage.setItem('ss_bases', JSON.stringify(BASES)); }
function draftRebase(key, value) { BASES[key] = { value: draftClone(value), sha: META.sha }; draftBasesSave(); }
function draftHistory(m) { if (typeof trackChange === 'function') trackChange(m); if (typeof workspaceStatus === 'function') workspaceStatus(); if (typeof sandboxChanged === 'function') sandboxChanged(); }
// Named actions survive reordered lists. Unnamed actions match exactly first; ambiguous
// structural edits are rejected rather than applied at yesterday's numeric index.
function locateAction(items, base, index, oldItems) {
  if (base.name) { const matches = items.map((a, i) => a.name === base.name ? i : -1).filter(i => i >= 0); if (matches.length === 1) return matches[0]; }
  const exact = items.map((a, i) => sameDraft(a, base) ? i : -1).filter(i => i >= 0);
  if (exact.length === 1) return exact[0];
  if (items.length === oldItems.length && items.every((a, i) => a.type === oldItems[i].type && a.animation === oldItems[i].animation && a.name === oldItems[i].name)) return index;
  throw new Error('Список действий изменён или неоднозначен. Обнови исходный проект и совмести действия перед отправкой.');
}
if (typeof module !== 'undefined') module.exports = { mergeDraft, locateAction };
