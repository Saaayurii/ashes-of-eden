/* Portable workspace: all drafts, pictures and audio; no login/API tokens. */
'use strict';
const WORKSPACE = { id: 'workspace', name: 'Весь проект', pendingPr: +(localStorage.getItem('ss_workspace_pr') || 0) || undefined };
const WORKSPACE_KEYS = ['ss_attacks','ss_shots','ss_pfx','ss_life','ss_dlg','ss_world','ss_world_file','ss_bases','ss_last','ss_mode','ss_lifekey','ss_live_base','ss_gd_strings','ss_gd_music'];
async function packWorkspace(value) {
  if (value instanceof Blob) return { $studioBlob: await blobToDataURL(value) };
  if (Array.isArray(value)) return Promise.all(value.map(packWorkspace));
  if (value && typeof value === 'object') return Object.fromEntries(await Promise.all(Object.entries(value).map(async ([k, v]) => [k, await packWorkspace(v)])));
  return value;
}
function unpackWorkspace(value) {
  if (value?.$studioBlob) return dataURLtoBlob(value.$studioBlob);
  if (Array.isArray(value)) return value.map(unpackWorkspace);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, unpackWorkspace(v)]));
  return value;
}
async function workspaceBundle() {
  if (P && dbOk) await persist();
  const stores = {};
  for (const store of ['projects','backgrounds','sounds','cutscenes']) stores[store] = await packWorkspace(await DB.all(store));
  // Merge loaded records over IndexedDB, including edits awaiting their timer.
  const loaded = { projects: projects, backgrounds: bgs, sounds: [...sndMods.values()], cutscenes: cuts };
  for (const [store, rows] of Object.entries(loaded)) {
    const all = new Map(stores[store].map(o => [o.id, o]));
    for (const row of rows) all.set(row.id, await packWorkspace(row));
    stores[store] = [...all.values()];
  }
  return { format: 'ashes-studio-workspace', version: 1, sha: META.sha, name: WORKSPACE.name, stores, local: Object.fromEntries(WORKSPACE_KEYS.map(k => [k, localStorage.getItem(k)]).filter(([,v]) => v !== null)) };
}
async function workspaceRestore(bundle) {
  if (bundle.format !== 'ashes-studio-workspace' || bundle.version !== 1 || !bundle.stores || !bundle.local) throw new Error('Это не проект студии');
  const records = {};
  for (const store of ['projects','backgrounds','sounds','cutscenes']) { records[store] = unpackWorkspace(bundle.stores[store] || []); if (!Array.isArray(records[store]) || records[store].some(o => !o?.id)) throw new Error('Повреждён раздел проекта: ' + store); }
  for (const k of WORKSPACE_KEYS) if (bundle.local[k] !== undefined && typeof bundle.local[k] !== 'string') throw new Error('Повреждён черновик: ' + k);
  // Merge projects by id; existing projects not in the imported file survive.
  for (const [store, rows] of Object.entries(records)) for (const row of rows) await DB.put(row, store);
  for (const k of WORKSPACE_KEYS) { if (bundle.local[k] === undefined) localStorage.removeItem(k); else localStorage.setItem(k, bundle.local[k]); }
  location.reload();
}
function workspaceStatus() {
  const n = ['ss_attacks','ss_shots','ss_pfx','ss_life','ss_dlg','ss_world','ss_gd_strings','ss_gd_music'].filter(k => { const v = localStorage.getItem(k); return v && v !== '{}' && v !== 'null'; }).length;
  const s = $('#workspaceStatus'); if (s) s.textContent = `Сохранено в браузере · ${n} разделов с черновиками · ${new Date().toLocaleTimeString()}`;
}
async function workspaceFiles() {
  const files = {}, del = [], notes = [], builders = [];
  for (const project of projects.filter(o => o.dirty)) builders.push(async () => { const old = P; try { P = project; await build(); return await charFiles(); } finally { P = old; await build(); } });
  for (const project of bgs.filter(o => o.dirty)) builders.push(async () => { const old = BG; try { BG = project; return await bgFiles(); } finally { BG = old; } });
  for (const project of cuts.filter(o => o.dirty)) builders.push(async () => { const old = CUT; try { CUT = project; return await cutFiles(); } finally { CUT = old; } });
  if (sndMods.size) builders.push(() => soundFiles());
  if (ATTACKS.data && (Object.keys(ATTACKS.work).length || SHOTS.edits.size)) builders.push(() => attacksFiles());
  if (SHOTS.data && shotsDirty()) builders.push(() => shotsFiles());
  if (PFX.data && !sameDraft(PFX.rules, PFX.data.rules)) builders.push(() => pfxFiles());
  if (LIFE.data && LIFE.edits.size) builders.push(() => lifeFiles());
  if (DLG.data && dlgDirty()) builders.push(() => dlgFiles());
  if (WORLD.data && Object.keys(WORLD.work).length) builders.push(() => worldFiles());
  if (typeof gdPending === 'function' && gdPending()) builders.push(async () => { await gdLoad(); return gdExtraFiles(true, true); });
  for (const build of builders) {
    const reader = repoText; let r;
    try { repoText = async path => typeof files[path] === 'string' ? files[path] : reader(path); r = await build(); } finally { repoText = reader; }
    del.push(...(r.del || [])); notes.push(...(r.notes || []));
    for (const [path, data] of Object.entries(r.files)) {
      if (!(path in files) || files[path] === data) { files[path] = data; continue; }
      if (path.endsWith('.json') && typeof data === 'string' && typeof files[path] === 'string') {
        files[path] = data;
      } else if (path.endsWith('.csv') && typeof data === 'string') {
        files[path] = data; // Each builder reads the previously prepared table and merges its own keys.
      } else throw new Error(`Два раздела меняют ${path}. Проверь изменения отдельно.`);
    }
  }
  if (!Object.keys(files).length && !del.length) throw new Error('Нет изменений для отправки');
  files['tools/studio/projects/workspaces/workspace.json'] = JSON.stringify(await workspaceBundle()) + '\n';
  return { files, del: [...new Set(del)], notes, title: 'Studio: workspace actions and game data', body: 'Changes from the shared Studio workspace. Portable source project included.' };
}
async function workspaceReview(result, allowSend = true) {
  const rows = [];
  for (const [path, value] of Object.entries(result.files)) {
    if (path.includes('/projects/')) { rows.push(`<details><summary>${esc(path)} — проект для продолжения работы</summary></details>`); continue; }
    let before = ''; try { before = await repoText(path); } catch {}
    if (typeof value === 'string') rows.push(`<details><summary>${esc(path)}</summary><div class="draftcompare" style="grid-template-columns:1fr 1fr"><div>В игре<pre>${esc(before)}</pre></div><div>После отправки<pre>${esc(value)}</pre></div></div></details>`);
    else {
      const after = await blobToDataURL(value);
      rows.push(`<details><summary>${esc(path)} — ${value.size} байт</summary>${value.type.startsWith('image/') ? `<div class="draftcompare"><img style="max-width:100%;image-rendering:pixelated" src="${esc(A(path))}"><img style="max-width:100%;image-rendering:pixelated" src="${esc(after)}"></div>` : value.type.startsWith('audio/') ? `<audio controls src="${esc(after)}"></audio>` : ''}</details>`);
    }
  }
  return new Promise(resolve => {
    dialog(`<h3>Изменения перед отправкой</h3><p>${Object.keys(result.files).length} файлов; удалений: ${result.del?.length || 0}.</p>${rows.join('')}<pre>${esc((result.del || []).map(p => 'Удалить: ' + p).join('\n'))}</pre>`, allowSend ? [['Назад', () => resolve(false)], ['Отправить', () => resolve(true)]] : [['Закрыть', () => resolve(false)]]);
    $('#dlg').addEventListener('cancel', () => resolve(false), { once: true });
  });
}
$('#workspaceExport').onclick = async () => { try { download(new Blob([JSON.stringify(await workspaceBundle())], { type: 'application/json' }), 'ashes-studio-project.json'); } catch (e) { toast(e.message, 'err'); } };
$('#workspaceImport').onchange = async e => { try { if (e.target.files[0]) await workspaceRestore(JSON.parse(await e.target.files[0].text())); } catch (e) { toast(e.message, 'err'); } };
$('#workspacePreview').onclick = async () => { try { await workspaceReview(await workspaceFiles(), false); } catch (e) { toast(e.message, 'err'); } };
$('#workspaceSend').onclick = async () => { await sendToGame(workspaceFiles, 'workspace'); if (sendToGame.last?.local) { for (const k of ['ss_attacks','ss_shots','ss_pfx','ss_life','ss_dlg','ss_world','ss_bases','ss_gd_strings','ss_gd_music']) localStorage.removeItem(k); for (const [store, rows] of Object.entries({ projects, backgrounds: bgs, cutscenes: cuts })) for (const o of rows) { o.dirty = false; await DB.put(o, store); } for (const id of sndMods.keys()) await DB.del(id, 'sounds'); location.reload(); } };
workspaceStatus();
