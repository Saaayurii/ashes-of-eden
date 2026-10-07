/* Sprite Studio: the repository side.
 *
 * How work reaches the game. Served by tools/studio/serve.py the page writes
 * straight into the working tree and can run the validator and Godot; hosted on
 * GitHub Pages it signs in with a GitHub token and opens a pull request, which
 * CI checks before anything lands on main. Either way the same files are built
 * here, and a file a generator owns (meta.json, from tools/check_generators.py)
 * is never written: CI would fail on it.
 */
'use strict';

let META = { repo: 'Saaayurii/ashes-of-eden', branch: 'main', assetBase: '../../', generated: [], generators: [] };
const A = u => !u || /^(data:|blob:|https?:)/.test(u) ? u : META.assetBase + String(u).replace(/^res:\/\//, '');
async function loadMeta() {
  try { META = { ...META, ...(await (await fetch('import/meta.json', { cache: 'no-store' })).json()) }; } catch {}
  await detectWriter();
}

/* ---------- who is writing ---------- */
const GH_KEY = 'ss_github';
let gh = null;
try { gh = JSON.parse(localStorage.getItem(GH_KEY) || 'null'); } catch {}
const Writer = { mode: null, info: null };
async function detectWriter() {
  // ?hosted shows the page as GitHub Pages serves it, even from serve.py
  if (!new URLSearchParams(location.search).has('hosted')) try {
    const r = await fetch('/api/ping', { cache: 'no-store' });
    if (r.ok) { const j = await r.json(); if (j.ok) { Writer.mode = 'local'; Writer.info = j; renderAuth(); return; } }
  } catch {}
  Writer.mode = gh?.token ? 'github' : null; renderAuth();
}
function renderAuth() {
  const b = document.getElementById('authBtn'); if (!b) return;
  if (Writer.mode === 'local') { b.textContent = `● локально · ${Writer.info.branch}`; b.title = 'Студия запущена из папки игры: изменения пишутся прямо в файлы'; b.className = 'ghost ok'; }
  else if (Writer.mode === 'github') { b.textContent = `● ${gh.login}`; b.title = 'Вход через GitHub: изменения уходят pull request’ом'; b.className = 'ghost ok'; }
  else { b.textContent = 'Войти'; b.title = 'Войти через GitHub, чтобы отправлять изменения в игру'; b.className = 'ghost'; }
}
async function ghApi(path, opts = {}, token = gh?.token) {
  const r = await fetch('https://api.github.com' + path, { ...opts, headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', ...(opts.headers || {}) } });
  if (opts.raw) { if (!r.ok) throw Object.assign(new Error('GitHub ' + r.status), { status: r.status }); return r.text(); }
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error(j.message || 'GitHub ' + r.status), { status: r.status });
  return j;
}
async function signIn(token) {
  token = token.trim();
  const me = await ghApi('/user', {}, token);
  const repo = await ghApi(`/repos/${META.repo}`, {}, token);
  if (!repo.permissions?.push) throw new Error(`У ${me.login} нет права записи в ${META.repo}. Владелец добавляет её: Settings → Collaborators → Add people, и она принимает приглашение.`);
  gh = { token, login: me.login }; try { localStorage.setItem(GH_KEY, JSON.stringify(gh)); } catch {}
  await detectWriter();
}
function signOut() { gh = null; try { localStorage.removeItem(GH_KEY); } catch {} detectWriter(); }

/* ---------- dialogs ---------- */
function dialog(html, buttons = [['Закрыть']]) {
  const d = document.getElementById('dlg');
  d.innerHTML = `<div class="dlgbody">${html}</div><div class="row dlgbtns">${buttons.map(([label, act, cls], i) => `<button data-dlg="${i}" class="${cls || ''}">${label}</button>`).join('')}</div>`;
  return new Promise(res => {
    d.onclick = e => { const b = e.target.closest('[data-dlg]'); if (!b) return; const [, act] = buttons[+b.dataset.dlg]; if (act) { const v = act(d); if (v === false) return; } d.close(); res(+b.dataset.dlg); };
    if (!d.open) d.showModal();
  });
}
function authDialog() {
  if (Writer.mode === 'local') return dialog(`<h3>Локальный режим</h3><p>Студия запущена из папки игры (<code>tools/studio/serve.py</code>), ветка <b>${esc(Writer.info.branch)}</b>. «→ В игру» пишет файлы прямо в репозиторий и запускает проверку данных${Writer.info.godot ? '' : ' (Godot не найден — задай переменную GODOT)'}.</p>`);
  if (Writer.mode === 'github') return dialog(`<h3>Вход через GitHub</h3><p>Ты вошла как <b>${esc(gh.login)}</b>. «→ В игру» создаёт ветку и pull request в <b>${esc(META.repo)}</b>; после проверки CI владелец вливает его, и через несколько минут изменения в игре и в студии.</p>`, [['Выйти', () => signOut(), 'danger'], ['Закрыть']]);
  const url = 'https://github.com/settings/tokens/new?scopes=public_repo&description=' + encodeURIComponent('Ashes of Eden Studio');
  return dialog(`<h3>Вход через GitHub</h3>
    <ol class="steps">
      <li>Нужен аккаунт GitHub с правом записи в <b>${esc(META.repo)}</b>: владелец добавляет тебя в <i>Settings → Collaborators</i>, ты принимаешь приглашение из почты.</li>
      <li>Создай ключ: <a href="${url}" target="_blank" rel="noopener">открыть страницу ключей GitHub</a> → срок (например, 90 дней) → внизу <b>Generate token</b>. Галочка <code>public_repo</code> уже стоит, больше ничего не нужно.</li>
      <li>Скопируй ключ (начинается с <code>ghp_</code>) и вставь сюда:</li>
    </ol>
    <input id="ghToken" type="password" placeholder="ghp_…" autocomplete="off">
    <div class="note">Ключ хранится только в этом браузере. Студия ничего не меняет в main напрямую: каждое изменение приходит владельцу pull request’ом.</div>
    <div class="warn" id="ghErr"></div>`, [['Войти', d => { const t = d.querySelector('#ghToken').value; if (!t) return false; d.querySelector('#ghErr').textContent = 'Проверяю…'; signIn(t).then(() => { d.close(); toast(`Вход выполнен: ${gh.login}`); }).catch(e => { d.querySelector('#ghErr').textContent = e.message; }); return false; }, 'primary'], ['Отмена']]);
}

/* ---------- reading and writing the repository ---------- */
const blobB64 = b => new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result).split(',')[1] || ''); r.onerror = () => rej(r.error); r.readAsDataURL(b instanceof Blob ? b : new Blob([b])); });
// The current text of a repository file, or '' when it does not exist yet.
async function repoText(path) {
  if (Writer.mode === 'github') {
    try { return await ghApi(`/repos/${META.repo}/contents/${path}?ref=${META.branch}`, { raw: true, headers: { Accept: 'application/vnd.github.raw' } }); }
    catch (e) { if (e.status === 404) return ''; throw e; }
  }
  const r = await fetch(A(path), { cache: 'no-store' });
  return r.ok ? r.text() : '';
}
const generatedSet = () => new Set(META.generated || []);
const ownerOf = path => (META.generators || []).find(g => g.paths.some(p => path === p || path.startsWith(p.replace(/\/?$/, '/'))));

// files: {path: Blob|string}; del: [path]. Returns a link or a log to show.
async function commitFiles(files, del, title, body) {
  const gen = generatedSet(), paths = Object.keys(files);
  const blocked = [...paths, ...del].filter(p => gen.has(p));
  if (blocked.length) {
    const why = [...new Set(blocked.map(p => ownerOf(p)?.script).filter(Boolean))];
    throw new Error(`Эти файлы собирает генератор (${why.join(', ') || 'tools/check_generators.py'}), и CI не примет их правку руками:\n${blocked.slice(0, 8).join('\n')}\nСохрани работу как нового персонажа/звук или поправь исходники генератора.`);
  }
  // remember the files the studio adds inside a generator's folder, so the next edit is allowed
  const mine = paths.filter(p => ownerOf(p));
  if (mine.length) {
    const reg = JSON.parse((await repoText('tools/studio/projects/files.json')) || '{}');
    for (const p of mine) reg[p] = { by: Writer.mode === 'github' ? gh.login : 'local', at: new Date().toISOString().slice(0, 10) };
    for (const p of del) delete reg[p];
    files['tools/studio/projects/files.json'] = JSON.stringify(Object.fromEntries(Object.entries(reg).sort()), null, 2) + '\n';
  }
  if (Writer.mode === 'local') {
    const payload = { files: await Promise.all(Object.entries(files).map(async ([path, b]) => ({ path, b64: await blobB64(b) }))), delete: del };
    const r = await (await fetch('/api/write', { method: 'POST', body: JSON.stringify(payload) })).json();
    if (!r.ok) throw new Error(r.error);
    return { local: true, written: r.written, deleted: r.deleted };
  }
  if (Writer.mode !== 'github') throw new Error('Сначала войди через GitHub (кнопка справа вверху).');
  const R = `/repos/${META.repo}`, base = await ghApi(`${R}/git/ref/heads/${META.branch}`), head = await ghApi(`${R}/git/commits/${base.object.sha}`);
  const tree = [];
  for (const [path, b] of Object.entries(files)) {
    const blob = await ghApi(`${R}/git/blobs`, { method: 'POST', body: JSON.stringify({ content: await blobB64(b), encoding: 'base64' }) });
    tree.push({ path, mode: '100644', type: 'blob', sha: blob.sha });
  }
  for (const path of del) for (const p of [path, path + '.import']) {
    try { await ghApi(`${R}/contents/${p}?ref=${META.branch}`); tree.push({ path: p, mode: '100644', type: 'blob', sha: null }); } catch (e) { if (e.status !== 404) throw e; }
  }
  const t = await ghApi(`${R}/git/trees`, { method: 'POST', body: JSON.stringify({ base_tree: head.tree.sha, tree }) });
  const c = await ghApi(`${R}/git/commits`, { method: 'POST', body: JSON.stringify({ message: title, tree: t.sha, parents: [base.object.sha] }) });
  const branch = `studio/${gh.login}-${new Date().toISOString().replace(/[-:T]/g, '').slice(0, 12)}`;
  await ghApi(`${R}/git/refs`, { method: 'POST', body: JSON.stringify({ ref: 'refs/heads/' + branch, sha: c.sha }) });
  const pr = await ghApi(`${R}/pulls`, { method: 'POST', body: JSON.stringify({ title, head: branch, base: META.branch, body: body + '\n\n— отправлено из Sprite Studio (tools/studio)' }) });
  return { url: pr.html_url, number: pr.number };
}
// Which project a send belongs to, so the same pull request carries it and the
// studio can open it again from the branch — on this computer or another one.
const PROJECT_KIND = { chars: 'chars', bg: 'bgs', cut: 'cuts' };
async function projectFile(kind, obj) {
  const copy = JSON.parse(JSON.stringify(obj)); delete copy.shared; delete copy.pendingPr; delete copy.dirty;
  if (kind === 'chars') { copy.reference = await shrinkSrc(copy.reference); for (const a of copy.animations) for (const f of a.frames) f.src = await shrinkSrc(f.src); }
  return [`tools/studio/projects/${kind}/${slug(copy.id || copy.name)}.json`, JSON.stringify(copy) + '\n'];
}
async function sendToGame(build, tab) {
  if (!Writer.mode) { await authDialog(); if (!Writer.mode) return; }
  let r;
  const obj = tab && undoTarget(tab), kind = PROJECT_KIND[tab];
  try {
    const { files, del = [], title, body = '', notes = [] } = await build();
    if (obj && kind && !files[`tools/studio/projects/${kind}/${slug(obj.id || obj.name)}.json`]) { const [p, txt] = await projectFile(kind, obj); files[p] = txt; }
    toast('Отправляю…');
    r = await commitFiles(files, del, title, [body, ...notes].filter(Boolean).join('\n\n'));
    if (obj) { obj.dirty = false; if (r.url) obj.pendingPr = r.number; storeOf(tab)?.(obj); }
    rememberSend({ kind: tab, objId: obj?.id, title, url: r.url, number: r.number, local: !!r.local });
    if (r.url) return dialog(`<h3>Отправлено</h3><p>Создан pull request: <a href="${esc(r.url)}" target="_blank" rel="noopener">${esc(r.url)}</a></p><p>CI проверит данные; когда владелец его вольёт, изменения появятся в игре и в студии.</p>${notes.length ? `<div class="note">${notes.map(esc).join('<br>')}</div>` : ''}`);
    const box = `<h3>Записано в игру</h3><p>${r.written.length} файл(ов)${r.deleted.length ? `, удалено ${r.deleted.length}` : ''}:</p><pre class="log">${esc([...r.written, ...r.deleted.map(d => '− ' + d)].join('\n'))}</pre>${notes.length ? `<div class="note">${notes.map(esc).join('<br>')}</div>` : ''}<div id="valOut" class="note">Проверяю данные игры (validate_data.gd)…</div>`;
    dialog(box);
    validate().then(v => { const el = document.getElementById('valOut'); if (el) el.outerHTML = v; });
  } catch (e) { dialog(`<h3>Не получилось</h3><pre class="log">${esc(e.message)}</pre>`); }
}
async function validate() {
  if (Writer.mode !== 'local' || !Writer.info.godot) return '<div class="note">Проверку данных сделает CI.</div>';
  try {
    const v = await (await fetch('/api/validate', { method: 'POST', body: '{}' })).json();
    return v.ok ? '<div class="ok">✓ Проверка данных пройдена</div>' : `<div class="warn">✗ Проверка данных нашла ошибки:</div><pre class="log">${esc(v.log || v.error || '')}</pre>`;
  } catch (e) { return `<div class="warn">Проверка не запустилась: ${esc(e.message)}</div>`; }
}
async function runInGodot(room) {
  if (Writer.mode !== 'local') return dialog('<h3>Запуск в Godot</h3><p>Работает, когда студия открыта из папки игры: <code>python3 tools/studio/serve.py</code>. На сайте игру можно проверить после того, как изменения вольют.</p>');
  if (!room) return dialog('<h3>Запуск в Godot</h3><p>Эту катсцену не показывает ни одна комната. Её подключают полем <code>intro_cutscene</code> / <code>outro_cutscene</code> в таблице комнат (<code>tools/rooms/generate_rooms.py</code>).</p>');
  const r = await (await fetch('/api/run', { method: 'POST', body: JSON.stringify({ room }) })).json();
  toast(r.ok ? `Godot открывает комнату ${room}…` : 'Не запустилось: ' + r.error, r.ok ? '' : 'err');
}

/* ---------- what each part of the studio sends ---------- */
async function charFiles() {
  await build();
  const S = P.settings, W = +S.cellW, H = +S.cellH, name = slug(P.name), origin = P.origin || {};
  const base = String(S.resPath || 'res://assets/sprites/').replace(/\/*$/, '/'), used = new Set(), files = {}, anims = [], manifest = [], sheets = {};
  for (const a of P.animations) {
    const frames = a.frames.filter(f => !f.off && processed.has(f.id));
    if (!frames.length) continue;
    let an = slug(a.name), k = 2; while (used.has(an)) an = slug(a.name) + '_' + k++;
    used.add(an);
    // a character from the game keeps its own file names, so a zip round-trips
    const texPath = a.file || `${base}${name}_${an}.png`;
    const sheet = mk(W * frames.length, H), sx = sheet.getContext('2d');
    frames.forEach((f, i) => sx.drawImage(processed.get(f.id), i * W, 0));
    sheets[an] = { frames, blob: await canvasBlob(sheet) };
    files[texPath.replace('res://', '')] = sheets[an].blob;
    anims.push({ name: an, fps: +a.fps || 8, loop: !!a.loop, texPath, texId: `tex_${name}_${an}`, ids: frames.map((_, i) => `${name}_${an}_${i}`), durations: frames.map(f => +f.dur || 1) });
    manifest.push({ name: an, file: texPath, frames: frames.length, fps: +a.fps || 8, loop: !!a.loop, durations: frames.map(f => +f.dur || 1) });
  }
  if (!anims.length) throw new Error('Нет готовых кадров');
  const tres = origin.tres || `${base}${name}_frames.tres`;
  files[tres.replace('res://', '')] = spriteFramesTres(anims, W, H);
  return { name, files, sheets, manifest, tres, W, H, groundY: H - (+S.bottomPad), base,
    title: `Studio: ${name} — ${anims.length} animation(s)`,
    body: `Персонаж **${name}**: ${manifest.map(m => `${m.name} (${m.frames})`).join(', ')}. Кадр ${W}×${H}, SpriteFrames: \`${tres}\`.`,
    notes: origin.generator ? [`${name} собирается генератором ${origin.generator}; правка его PNG руками не пройдёт CI.`] : [`Чтобы ${name} появился в игре, его \`${tres}\` подключают к сцене персонажа или врага.`] };
}
async function bgFiles() {
  const name = slug(BG.name), dir = String(BG.resDir || `res://assets/backgrounds/${name}/`).replace(/\/*$/, '/').replace('res://', '');
  const files = {}, ext = new Map(), names = new Set(), num = v => String(+(+v).toFixed(3));
  const nodeName = (n, used) => { let b = String(n || 'node').replace(/[.:@\/"%]/g, '_'), k = b, i = 2; while (used.has(k)) k = `${b}_${i++}`; used.add(k); return k; };
  const tex = (key, hint) => {
    if (ext.has(key)) return ext.get(key).id;
    const meta = BG.images[key]; let path = meta.res;
    if (!path) { let f = `${hint}.png`, i = 2; while (names.has(f)) f = `${hint}_${i++}.png`; names.add(f); files[dir + f] = dataURLtoBlob(meta.src); path = 'res://' + dir + f; }
    const id = `tex_${ext.size + 1}`; ext.set(key, { id, path }); return id;
  };
  const top = new Set(), body = [], table = [];
  for (const l of BG.layers) {
    if (!l.items.length) continue;
    const ln = nodeName(l.name.replace(/\s+/g, '_'), top), para = l.repeatX || l.scroll[0] !== 1 || l.scroll[1] !== 1;
    let n = `[node name="${ln}" type="${para ? 'Parallax2D' : 'Node2D'}" parent="."]`;
    if (para) n += `\nscroll_scale = Vector2(${num(l.scroll[0])}, ${num(l.scroll[1])})`;
    if (l.repeatX) n += `\nrepeat_size = Vector2(${layerPeriod(l)}, 0)\nrepeat_times = 3`;
    if (l.z) n += `\nz_index = ${l.z}`;
    if (l.opacity < 1) n += `\nmodulate = Color(1, 1, 1, ${num(l.opacity)})`;
    if (!l.visible) n += `\nvisible = false`;
    body.push(n);
    const used = new Set();
    for (const it of l.items) {
      if (it.kind === 'rect') { body.push(`[node name="${nodeName(it.name || 'Rect', used)}" type="ColorRect" parent="${ln}"]\noffset_left = ${num(it.x)}\noffset_top = ${num(it.y)}\noffset_right = ${num(it.x + it.w)}\noffset_bottom = ${num(it.y + it.h)}\ncolor = Color(${it.color.map(num).join(', ')})\nmouse_filter = 2`); continue; }
      let t = `[node name="${nodeName(it.name || 'Sprite', used)}" type="Sprite2D" parent="${ln}"]`;
      if (it.modulate.some(v => v !== 1)) t += `\nmodulate = Color(${it.modulate.map(num).join(', ')})`;
      if (it.filter === 2) t += `\ntexture_filter = 2`;
      t += `\nposition = Vector2(${num(it.x)}, ${num(it.y)})`;
      if (Math.abs(it.sx) !== 1 || Math.abs(it.sy) !== 1) t += `\nscale = Vector2(${num(Math.abs(it.sx))}, ${num(Math.abs(it.sy))})`;
      t += `\ntexture = ExtResource("${tex(it.img, slug(l.name) + '_' + slug(it.name || 'img'))}")\ncentered = false`;
      if (it.flipH) t += `\nflip_h = true`;
      body.push(t);
    }
    table.push(`| ${l.name} | ${para ? 'Parallax2D' : 'Node2D'} | ${num(l.scroll[0])} × ${num(l.scroll[1])} | ${l.repeatX ? 'да' : 'нет'} | ${l.items.length} |`);
  }
  if (!body.length) throw new Error('В заднике нет ни одной картинки');
  const scene = `${dir}${name}_background.tscn`;
  files[scene] = `[gd_scene load_steps=${ext.size + 1} format=3]\n\n${[...ext.values()].map(e => `[ext_resource type="Texture2D" path="${e.path}" id="${e.id}"]`).join('\n')}\n\n[node name="${name}_background" type="Node2D"]\n\n${body.join('\n\n')}\n`;
  return { name, dir, scene, files, table,
    title: `Studio: background ${name}`,
    body: `Задник **${name}**: сцена \`${scene}\`, слоёв ${table.length}.`,
    notes: [BG.origin?.generator ? `Комнаты собирает ${BG.origin.generator}: задник лежит отдельной сценой; чтобы он заменил старый, его вписывают в таблицу комнаты и перегенерируют.` : 'Задник лежит отдельной сценой; в комнату его добавляет генератор (tools/rooms/generate_rooms.py).'] };
}
async function cutFiles() {
  const id = CUT.id, files = {}, notes = [];
  files[`data/cutscenes/${id}.json`] = cutsceneJson(id, CUT.steps);
  for (const [did, d] of Object.entries(CUT.dialogues)) {
    const path = `data/dialogues/${d._file || did + '.json'}`;
    files[path] = mergeDialogueFile(files[path] || await repoText(path), d);
  }
  const keys = Object.keys(CUT.strings);
  if (keys.length) {
    files['localization/strings.csv'] = mergeStrings(await repoText('localization/strings.csv'), CUT.strings);
    notes.push(`Строк: ${keys.length}. Где нет перевода на uk / zh_CN, пока стоит английский текст — их стоит перевести.`);
  }
  const rules = {};
  for (const [res, src] of Object.entries(CUT.images)) {
    files[res.replace('res://', '')] = dataURLtoBlob(src);
    rules[res.split('/').pop().replace(/\.[^.]+$/, '')] = CUT.families?.[res] || 'dusk';
  }
  if (Object.keys(rules).length) {
    files['data/backdrops.json'] = insertBackdropRules(await repoText('data/backdrops.json'), rules);
    notes.push('Для новых картин добавлены неподвижные правила в data/backdrops.json (зоны «оживления» можно дописать потом).');
  }
  const rooms = cutData?.played_in?.[id];
  notes.push(rooms ? `Катсцену показывает комната ${rooms.join(', ')}.` : 'Катсцену пока не показывает ни одна комната: её подключают полем intro_cutscene / outro_cutscene в tools/rooms/generate_rooms.py.');
  return { id, files, notes, title: `Studio: cutscene ${id}`, body: `Катсцена **${id}**: ${CUT.steps.length} шагов.` };
}
async function soundFiles() {
  await loadSndLib();
  const gen = generatedSet(), isGen = p => gen.has(p), files = {}, del = [], rows = [], refused = [];
  for (const m of sndMods.values()) {
    const e = sndEntry(m.id); if (!e) continue;
    for (const t of e.takes) {
      if (!takeChanged(t)) continue;
      const plan = planSoundWrite(e, t, isGen);
      if (plan.error) { refused.push(`${e.name}/${t.stem}`); continue; }
      const buf = renderEdits(await takeBuffer(t), t.mod.edits || {});
      files[plan.write] = plan.write.endsWith('.wav') ? encodeWav(buf) : encodeMp3(buf);
      del.push(...plan.delete);
      rows.push(`${plan.write}${plan.renamed ? ` (вместо ${t.stem}, который собирает генератор)` : ''}`);
    }
  }
  if (!rows.length) throw new Error(refused.length ? `Эти звуки собирает генератор, их нельзя заменить: ${refused.join(', ')}` : 'Нет изменённых звуков');
  return { files, del, rows, title: `Studio: ${rows.length} sound(s)`, body: 'Звуки:\n' + rows.map(r => '- ' + r).join('\n'),
    notes: [...(refused.length ? [`Пропущены (их собирает генератор): ${refused.join(', ')}`] : []), 'Своя запись — своя лицензия: добавь строку в assets/CREDITS.md, если звук чужой (принимается только CC0).'] };
}

/* ---------- shared projects: tools/studio/projects/<kind>/<id>.json ---------- */
async function shrinkSrc(src, max = 768) {
  if (!src || !src.startsWith('data:')) return src;
  const img = await loadImage(src), s = Math.min(1, max / Math.max(img.width, img.height));
  if (s === 1) return src;
  const c = mk(Math.round(img.width * s), Math.round(img.height * s)); c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
  return c.toDataURL('image/png');
}
async function shareProject(kind) {
  const tab = { chars: 'chars', bgs: 'bg', cuts: 'cut' }[kind], obj = undoTarget(tab);
  if (!obj) return;
  const [path, txt] = await projectFile(kind, obj);
  await sendToGame(async () => ({ files: { [path]: txt }, title: `Studio: share ${kind.slice(0, -1)} ${slug(obj.id || obj.name)}`,
    body: `Проект студии \`${path}\` — после вливания он появится у всех, кто открывает студию.` }), tab);
}

/* ---------- buttons ---------- */
document.addEventListener('click', e => {
  const b = e.target.closest('[data-act]'); if (!b) return;
  switch (b.dataset.act) {
    case 'auth': authDialog(); break;
    case 'chars-game': sendToGame(charFiles, 'chars'); break;
    case 'bg-game': sendToGame(bgFiles, 'bg'); break;
    case 'cut-game-send': sendToGame(cutFiles, 'cut'); break;
    case 'sent': sentDialog(); break;
    case 'snd-game': sendToGame(soundFiles); break;
    case 'chars-share': shareProject('chars'); break;
    case 'bg-share': shareProject('bgs'); break;
    case 'cut-share': shareProject('cuts'); break;
    case 'bg-run': runInGodot(BG?.origin?.room); break;
    case 'cut-run': runInGodot(cutData?.played_in?.[CUT?.id]?.[0]); break;
    case 'chars-from-game': importFromUrl('import/list.json').then(() => { renderAll(); scheduleBuild(0); }); break;
  }
});

/* ---------- my sends: what happened to them, and opening them again ---------- */
const SENT_KEY = 'ss_sent';
const loadSent = () => { try { return JSON.parse(localStorage.getItem(SENT_KEY) || '[]'); } catch { return []; } };
function rememberSend(e) {
  const list = [{ ...e, at: Date.now() }, ...loadSent()].slice(0, 60);
  try { localStorage.setItem(SENT_KEY, JSON.stringify(list)); } catch {}
  refreshSent();
}
const storeOf = tab => ({ chars: o => { if (o === P) persist(); else DB.put(o).catch(() => {}); },
  bg: o => DB.put(o, 'backgrounds').catch(() => {}), cut: o => DB.put(o, 'cutscenes').catch(() => {}) })[tab];
let sentCache = [];
// Her pull requests (the studio names its branches studio/<login>-…), with checks and whether the site has them.
async function fetchSent() {
  if (Writer.mode !== 'github') return loadSent().map(e => ({ ...e, status: e.local ? { key: 'local', label: 'записано в папку игры', tone: 'ok' } : null }));
  const R = `/repos/${META.repo}`;
  const prs = (await ghApi(`${R}/pulls?state=all&per_page=50&sort=created&direction=desc`)).filter(p => p.head.ref.startsWith(`studio/${gh.login}-`)).slice(0, 20);
  return Promise.all(prs.map(async p => {
    let checks = null, deployed = false;
    if (p.state === 'open') {
      try {
        const runs = (await ghApi(`${R}/commits/${p.head.sha}/check-runs?per_page=100`)).check_runs || [];
        checks = { total: runs.length, pending: runs.filter(r => r.status !== 'completed').length, failed: runs.filter(r => ['failure', 'timed_out', 'cancelled'].includes(r.conclusion)).length };
      } catch {}
    }
    if (p.merged_at && META.sha) {
      try { const c = await ghApi(`${R}/compare/${p.merge_commit_sha}...${META.sha}`); deployed = c.status === 'ahead' || c.status === 'identical'; } catch {}
    }
    return { number: p.number, url: p.html_url, title: p.title, at: Date.parse(p.created_at), head: p.head.sha, branch: p.head.ref,
      status: prStatus({ state: p.state, merged: !!p.merged_at, checks, deployed }) };
  }));
}
// A sent project stays hers until the game has it: then the game's copy is hers too.
function settlePending(list) {
  const done = new Map(list.filter(e => e.number && ['live', 'closed'].includes(e.status?.key)).map(e => [e.number, e.status.key]));
  for (const [tab, items] of [['chars', projects], ['bg', bgs], ['cut', cuts]]) for (const o of items) {
    if (!o.pendingPr || !done.has(o.pendingPr)) continue;
    if (done.get(o.pendingPr) === 'closed') o.dirty = true;  // not taken: keep it as her unsent work
    delete o.pendingPr; storeOf(tab)?.(o);
  }
}
async function refreshSent() {
  try { sentCache = await fetchSent(); settlePending(sentCache); } catch { return; }
  const open = sentCache.filter(e => ['checking', 'ready', 'failed', 'merged'].includes(e.status?.key)).length;
  const b = document.getElementById('sentBtn');
  if (b) { b.textContent = open ? `Мои отправки · ${open}` : 'Мои отправки'; b.classList.toggle('ok', !!sentCache.length && !open); }
}
const toneClass = t => t === 'ok' ? 'ok' : t === 'bad' ? 'warn' : 'muted';
async function sentDialog() {
  dialog('<h3>Мои отправки</h3><div class="note">Загружаю…</div>');
  await refreshSent();
  const rows = sentCache.map(e => `<div class="sentrow">
      <div><b>${esc(e.title || '')}</b><div class="muted" style="font-size:12px">${new Date(e.at).toLocaleString('ru')}${e.number ? ` · #${e.number}` : ''}</div></div>
      <span class="${toneClass(e.status?.tone)}">${esc(e.status?.label || '')}</span>
      ${e.url ? `<a href="${esc(e.url)}" target="_blank" rel="noopener">PR ↗</a>` : ''}
      ${e.number ? `<button class="sm" data-open-pr="${e.number}">Открыть в студии</button>` : ''}
    </div>`).join('') || '<div class="muted">Пока ничего не отправлено.</div>';
  await dialog(`<h3>Мои отправки</h3>
    <div class="note">«на проверке» — CI проверяет данные; «проверено» — ждёт, когда владелец вольёт; «в игре» — уже на сайте игры и в студии у всех. Через «Открыть в студии» можно вернуть отправленное и на другом компьютере.</div>
    <div class="sentlist">${rows}</div>`);
}
// Bring a sent project back from its branch (or from main once it is in).
async function openFromPr(number) {
  try {
    const R = `/repos/${META.repo}`, pr = await ghApi(`${R}/pulls/${number}`), ref = pr.merged_at ? META.branch : pr.head.sha;
    const files = (await ghApi(`${R}/pulls/${number}/files?per_page=100`)).map(f => f.filename).filter(f => /^tools\/studio\/projects\/(chars|bgs|cuts)\/[^/]+\.json$/.test(f));
    if (!files.length) return toast('В этой отправке нет проекта студии (это звуки или старая отправка)', 'err');
    for (const f of files) {
      const obj = JSON.parse(await ghApi(`${R}/contents/${f}?ref=${ref}`, { raw: true, headers: { Accept: 'application/vnd.github.raw' } }));
      const kind = f.split('/')[3];
      obj.pendingPr = pr.merged_at ? undefined : number; obj.dirty = false;
      if (kind === 'chars') { const p = migrate(obj), i = projects.findIndex(x => x.id === p.id); if (i >= 0) projects[i] = p; else projects.push(p); P = p; await persist(); setMode('chars'); renderAll(); scheduleBuild(0); }
      else if (kind === 'bgs') { BG = migrateBg(obj); await bgUpsert(BG); setMode('bg'); renderBgAll(); }
      else { CUT = migrateCut(obj); await cutUpsert(CUT); setMode('cut'); renderCutAll(); }
    }
    document.getElementById('dlg').close();
    toast(`Открыто из отправки #${number}`);
  } catch (e) { toast('Не получилось открыть: ' + e.message, 'err'); }
}
document.addEventListener('click', e => { const b = e.target.closest('[data-open-pr]'); if (b) openFromPr(+b.dataset.openPr); });
