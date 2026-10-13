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
// A picture or sound by its path: the engine's from assetBase, a game pack's own
// (content/…) from its repository (META.contentBase, docs/GAME_PACKS.md).
const A = u => {
  if (!u || /^(data:|blob:|https?:)/.test(u)) return u;
  const p = String(u).replace(/^res:\/\//, '');
  return META.contentBase && p.startsWith('content/') ? META.contentBase + p.slice(8) : META.assetBase + p;
};
// ?game=owner/name opens another game made on this engine: everything the page
// reads from import/ comes from that repository's studio-data branch, which its
// CI publishes (the engine's .github/workflows/game.yml), and sends go there.
const OPEN_GAME = (() => { const g = new URLSearchParams(location.search).get('game') || ''; return GAME_REPO.test(g) ? g : ''; })();
if (OPEN_GAME) {
  const base = gameDataBase(OPEN_GAME), plain = window.fetch.bind(window);
  window.fetch = (u, o) => plain(typeof u === 'string' && u.startsWith('import/') ? base + u.slice(7) : u, o);
}
async function loadMeta() {
  try { META = { ...META, ...(await (await fetch('import/meta.json', { cache: 'no-store' })).json()) }; }
  catch { if (OPEN_GAME) setTimeout(() => toast(`Нет данных студии у ${OPEN_GAME} (ветка studio-data): его CI ещё не собирал игру?`, 'err'), 0); }
  if (OPEN_GAME) META.repo = OPEN_GAME;
  await detectWriter();
  renderGame();
}
function renderGame() {
  const b = document.getElementById('gameBtn'); if (!b) return;
  const name = META.game?.name || (META.pack || OPEN_GAME ? META.repo : 'Ashes of Eden');
  b.textContent = `▣ ${name}`;
  b.title = META.pack ? `Игра на движке: ${META.repo} (движок ${META.pack.engine?.repo || ''})` : 'Открыть другую игру на этом движке';
}
function gameDialog() {
  if (Writer.mode === 'local') return dialog(`<h3>Игра</h3><p>Студия запущена локально и правит <b>${esc(Writer.info.game?.name || 'Ashes of Eden')}</b>${Writer.info.game?.path ? ` (<code>${esc(Writer.info.game.path)}</code>)` : ''}.</p><p>Другую игру открывает сервер: <code>python3 tools/studio/serve.py --game ../папка-игры</code>.</p>`);
  const here = location.pathname;
  return dialog(`<h3>Открыть игру</h3>
    <p>Игры на этом движке — отдельные репозитории (<code>make new-game</code>). Их CI выкладывает данные для студии в ветку <code>studio-data</code>; отправки отсюда уходят pull request’ом в репозиторий игры. Боёвку, сюжет, задники и звуки игры правишь так же, как у Ashes.</p>
    <input id="gameRepo" placeholder="владелец/репозиторий" value="${esc(OPEN_GAME)}" autocomplete="off">
    <div class="warn" id="gameErr"></div>`, [
    ['Открыть', d => {
      const v = d.querySelector('#gameRepo').value.trim().replace(/^https:\/\/github\.com\//, '').replace(/\/$/, '');
      if (!GAME_REPO.test(v)) { d.querySelector('#gameErr').textContent = 'Нужно «владелец/репозиторий», например Saaayurii/saints-of-rust'; return false; }
      location.href = `${here}?game=${encodeURIComponent(v)}`; return false;
    }, 'primary'],
    ...(OPEN_GAME ? [['Вернуться к Ashes of Eden', () => { location.href = here; }]] : []),
    ['Отмена']]);
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
let readRef = null;  // a pull request's branch while its fix is being built
// In a game pack a file is the pack's own copy when it has one, else the engine's
// (the one the pack inherits): a send then writes the pack's copy.
async function repoText(path) {
  const pack = META.pack, own = pack ? path.replace(/^content\//, '') : path;
  if (Writer.mode === 'github') {
    try { return await ghApi(`/repos/${META.repo}/contents/${own}?ref=${readRef || META.branch}`, { raw: true, headers: { Accept: 'application/vnd.github.raw' } }); }
    catch (e) { if (e.status !== 404) throw e; }
    if (!pack || path.startsWith('content/') || !pack.engine?.repo) return '';
    const r = await fetch(`https://raw.githubusercontent.com/${pack.engine.repo}/${pack.engine.sha || 'main'}/${path}`, { cache: 'no-store' });
    return r.ok ? r.text() : '';
  }
  if (pack && !path.startsWith('content/')) {
    const r = await fetch(A('content/' + own), { cache: 'no-store' });
    if (r.ok) return r.text();
  }
  const r = await fetch(A(path), { cache: 'no-store' });
  return r.ok ? r.text() : '';
}
const generatedSet = () => new Set(META.generated || []);
const ownerOf = path => (META.generators || []).find(g => g.paths.some(p => path === p || path.startsWith(p.replace(/\/?$/, '/'))));

// files: {path: Blob|string}; del: [path]. Returns a link or a log to show.
async function commitFiles(files, del, title, body, intoPr = null) {
  await convertToOverrides(files);  // a generated picture she edited goes beside its generator, never over it
  const gen = generatedSet(), paths = Object.keys(files);
  const blocked = [...paths, ...del].filter(p => gen.has(p));
  if (blocked.length) {
    const why = [...new Set(blocked.map(p => ownerOf(p)?.script).filter(Boolean))];
    throw new Error(`Эти файлы собирает генератор (${why.join(', ') || 'tools/check_generators.py'}), и CI не примет их правку руками:\n${blocked.slice(0, 8).join('\n')}\nСохрани работу как нового персонажа/звук или поправь исходники генератора.`);
  }
  // remember the files the studio adds inside a generator's folder, so the next edit is allowed
  // a generator's input file (META.generatorInputs) is the game's own, not one the studio made
  const mine = paths.filter(p => ownerOf(p) && !(META.generatorInputs || []).includes(p));
  if (mine.length) {
    const reg = JSON.parse((await repoText('tools/studio/projects/files.json')) || '{}');
    for (const p of mine) reg[p] = { by: Writer.mode === 'github' ? gh.login : 'local', at: new Date().toISOString().slice(0, 10) };
    for (const p of del) delete reg[p];
    files['tools/studio/projects/files.json'] = JSON.stringify(Object.fromEntries(Object.entries(reg).sort()), null, 2) + '\n';
  }
  if (META.pack) {
    // another game: every file goes into its repository (content/ when written locally)
    ({ files, del } = packFiles(files, del));
    if (Writer.mode === 'local') { files = Object.fromEntries(Object.entries(files).map(([p, b]) => ['content/' + p, b])); del = del.map(p => 'content/' + p); }
  }
  if (Writer.mode === 'local') {
    const payload = { files: await Promise.all(Object.entries(files).map(async ([path, b]) => ({ path, b64: await blobB64(b) }))), delete: del };
    const r = await (await fetch('/api/write', { method: 'POST', body: JSON.stringify(payload) })).json();
    if (!r.ok) throw new Error(r.error);
    return { local: true, written: r.written, deleted: r.deleted };
  }
  if (Writer.mode !== 'github') throw new Error('Сначала войди через GitHub (кнопка справа вверху).');
  const R = `/repos/${META.repo}`;
  // the same work already waiting in an open pull request: say so instead of opening a second one
  const fp = await filesFingerprint(await Promise.all(Object.entries(files).map(async ([p, b]) =>
    [p, typeof b === 'string' ? new TextEncoder().encode(b) : new Uint8Array(await b.arrayBuffer())])));
  if (!intoPr) {
    const open = await ghApi(`${R}/pulls?state=open&per_page=50`).catch(() => []);
    const twin = open.find(pr => pr.head.ref.startsWith('studio/') && (pr.body || '').includes(fingerprintMark(fp)));
    if (twin) return { url: twin.html_url, number: twin.number, duplicate: true };
  }
  const onto = intoPr ? intoPr.head.ref : META.branch;  // a fix goes on top of its own pull request
  const base = await ghApi(`${R}/git/ref/heads/${onto}`), head = await ghApi(`${R}/git/commits/${base.object.sha}`);
  const tree = [];
  for (const [path, b] of Object.entries(files)) {
    const blob = await ghApi(`${R}/git/blobs`, { method: 'POST', body: JSON.stringify({ content: await blobB64(b), encoding: 'base64' }) });
    tree.push({ path, mode: '100644', type: 'blob', sha: blob.sha });
  }
  for (const path of del) for (const p of [path, path + '.import']) {
    try { await ghApi(`${R}/contents/${p}?ref=${onto}`); tree.push({ path: p, mode: '100644', type: 'blob', sha: null }); } catch (e) { if (e.status !== 404) throw e; }
  }
  const t = await ghApi(`${R}/git/trees`, { method: 'POST', body: JSON.stringify({ base_tree: head.tree.sha, tree }) });
  const c = await ghApi(`${R}/git/commits`, { method: 'POST', body: JSON.stringify({ message: intoPr ? `${title} (исправления)` : title, tree: t.sha, parents: [base.object.sha] }) });
  if (intoPr) {
    await ghApi(`${R}/git/refs/heads/${onto}`, { method: 'PATCH', body: JSON.stringify({ sha: c.sha }) });
    return { url: intoPr.html_url, number: intoPr.number, updated: true };
  }
  const branch = `studio/${gh.login}-${new Date().toISOString().replace(/[-:T]/g, '').slice(0, 12)}`;
  await ghApi(`${R}/git/refs`, { method: 'POST', body: JSON.stringify({ ref: 'refs/heads/' + branch, sha: c.sha }) });
  const pr = await ghApi(`${R}/pulls`, { method: 'POST', body: JSON.stringify({ title, head: branch, base: META.branch, body: body + '\n\n— отправлено из Sprite Studio (tools/studio)\n' + fingerprintMark(fp) }) });
  return { url: pr.html_url, number: pr.number };
}
// Which project a send belongs to, so the same pull request carries it and the
// studio can open it again from the branch — on this computer or another one.
const PROJECT_KIND = { chars: 'chars', bg: 'bgs', cut: 'cuts', workspace: 'workspaces' };
// a cutscene is named by its id; a character or background by the name she gave it
const projectPath = (kind, o) => kind === 'workspaces' ? 'tools/studio/projects/workspaces/workspace.json' : `tools/studio/projects/${kind}/${slug(kind === 'cuts' ? o.id : (o.name || o.id))}.json`;
async function projectFile(kind, obj) {
  if (kind === 'workspaces') return ['tools/studio/projects/workspaces/workspace.json', JSON.stringify(await workspaceBundle()) + '\n'];
  const copy = JSON.parse(JSON.stringify(obj)); delete copy.shared; delete copy.pendingPr; delete copy.dirty;
  if (kind === 'chars') { copy.reference = await shrinkSrc(copy.reference); for (const a of copy.animations) for (const f of a.frames) f.src = await shrinkSrc(f.src); }
  return [projectPath(kind, obj), JSON.stringify(copy) + '\n'];
}
// A send already in flight: a second press (a double click, an impatient one) is not a second pull request.
let sending = false;
async function sendToGame(build, tab) {
  sendToGame.last = null;   // what the last send wrote, for a tab that clears its edits only when they went in
  if (sending) return toast('Уже отправляю — подожди немного', 'err');
  sending = true;
  try { await sendToGameOnce(build, tab); } finally { sending = false; }
}
// An open pull request that already carries this project: the one she sent from this browser, or —
// sent from another computer or before a reload — any open studio pull request with the same project file.
async function openPrOf(obj, kind) {
  const R = `/repos/${META.repo}`;
  if (obj?.pendingPr) { try { const pr = await ghApi(`${R}/pulls/${obj.pendingPr}`); if (pr.state === 'open') return pr; } catch {} }
  if (!obj || !kind) return null;
  const want = projectPath(kind, obj);
  for (const pr of (await ghApi(`${R}/pulls?state=open&per_page=50`).catch(() => [])).filter(p => p.head.ref.startsWith('studio/'))) {
    const files = await ghApi(`${R}/pulls/${pr.number}/files?per_page=100`).catch(() => []);
    if (files.some(f => f.filename === want)) return pr;
  }
  return null;
}
async function sendToGameOnce(build, tab) {
  if (!Writer.mode) { await authDialog(); if (!Writer.mode) return; }
  let r;
  const shared = ['attacksFiles','shotsFiles','pfxFiles','lifeFiles','dlgFiles','soundFiles'].includes(build.name);
  const obj = shared ? WORKSPACE : tab && undoTarget(tab), kind = shared ? 'workspaces' : PROJECT_KIND[tab];
  let intoPr = null;
  if (Writer.mode === 'github') {
    const pr = await openPrOf(obj, kind);
    if (pr && confirm(`«${obj.name || obj.id}» уже отправлен (#${pr.number}) и ждёт проверки. Добавить изменения в ту же отправку?\n\nOK — в ту же (так и нужно, если это исправления)\nОтмена — новой отправкой`)) intoPr = pr;
  }
  readRef = intoPr ? intoPr.head.ref : null;
  try {
    const { files, del = [], title, body = '', notes = [] } = await build();
    if (obj && kind && !files[projectPath(kind, obj)]) { const [p, txt] = await projectFile(kind, obj); files[p] = txt; }
    if (tab === 'workspace' && !(await workspaceReview({ files, del }))) return;
    toast('Отправляю…');
    r = await commitFiles(files, del, title, [body, ...notes].filter(Boolean).join('\n\n'), intoPr);
    sendToGame.last = r;
    if (obj) { obj.dirty = false; if (r.url) obj.pendingPr = r.number; storeOf(shared ? 'workspace' : tab)?.(obj); }
    if (!r.updated && !r.duplicate) rememberSend({ kind: tab, objId: obj?.id, title, url: r.url, number: r.number, local: !!r.local }); else refreshSent();
    if (r.duplicate) return void dialog(`<h3>Это уже отправлено</h3><p>Точно такие же изменения уже ждут проверки в <a href="${esc(r.url)}" target="_blank" rel="noopener">#${r.number}</a>. Вторая отправка не создана.</p>`);
    if (r.updated) return void dialog(`<h3>Исправления добавлены</h3><p>Они в той же отправке <a href="${esc(r.url)}" target="_blank" rel="noopener">#${r.number}</a>. CI проверит их заново, превью пересоберётся.</p>`);
    if (r.url) return void dialog(`<h3>Отправлено</h3><p>Создан pull request: <a href="${esc(r.url)}" target="_blank" rel="noopener">${esc(r.url)}</a></p><p>CI проверит данные; когда владелец его вольёт, изменения появятся в игре и в студии.</p>${notes.length ? `<div class="note">${notes.map(esc).join('<br>')}</div>` : ''}`);
    const box = `<h3>Записано в игру</h3><p>${r.written.length} файл(ов)${r.deleted.length ? `, удалено ${r.deleted.length}` : ''}:</p><pre class="log">${esc([...r.written, ...r.deleted.map(d => '− ' + d)].join('\n'))}</pre>${notes.length ? `<div class="note">${notes.map(esc).join('<br>')}</div>` : ''}<div id="valOut" class="note">Проверяю данные игры (validate_data.gd)…</div>`;
    dialog(box);
    validate().then(v => { const el = document.getElementById('valOut'); if (el) el.outerHTML = v; });
  } catch (e) { dialog(`<h3>Не получилось</h3><pre class="log">${esc(e.message)}</pre>`); }
  finally { readRef = null; }
}
async function validate() {
  if (Writer.mode !== 'local' || !Writer.info.godot) return '<div class="note">Проверку данных сделает CI.</div>';
  try {
    const v = await (await fetch('/api/validate', { method: 'POST', body: '{}' })).json();
    return v.ok ? '<div class="ok">✓ Проверка данных пройдена</div>' : `<div class="warn">✗ Проверка данных нашла ошибки:</div><pre class="log">${esc(v.log || v.error || '')}</pre>`;
  } catch (e) { return `<div class="warn">Проверка не запустилась: ${esc(e.message)}</div>`; }
}
async function runInGodot(room, composed = false) {
  if (Writer.mode !== 'local') return dialog('<h3>Запуск в Godot</h3><p>Работает, когда студия открыта из папки игры: <code>python3 tools/studio/serve.py</code>. На сайте игру можно проверить после того, как изменения вольют.</p>');
  if (!room) return dialog('<h3>Запуск в Godot</h3><p>Эту катсцену не показывает ни одна комната. Её подключают полем <code>intro_cutscene</code> / <code>outro_cutscene</code> в таблице комнат (<code>tools/rooms/generate_rooms.py</code>).</p>');
  const r = await (await fetch('/api/run', { method: 'POST', body: JSON.stringify({ room, composed }) })).json();
  toast(r.ok ? `Godot открывает ${composed ? 'черновик' : 'комнату'} ${room}…` : 'Не запустилось: ' + r.error, r.ok ? '' : 'err');
}

// The engine's own checks of a composed draft (serve.py /api/check): the bot walks it, stairs both
// ways, falls out of the map. Minutes, so the button says so; only from the game's folder.
async function checkInGodot(room) {
  if (Writer.mode !== 'local') return dialog('<h3>Проверка в Godot</h3><p>Настоящие проверки (бот проходит комнату, лестницы в обе стороны, падения за край) работают, когда студия открыта из папки игры: <code>python3 tools/studio/serve.py</code>. В отправке их проверяет CI.</p>');
  toast('Godot проверяет черновик: бот проходит комнату… это несколько минут');
  const r = await (await fetch('/api/check', { method: 'POST', body: JSON.stringify({ room }) })).json();
  if (r.error) return toast('Не проверилось: ' + r.error, 'err');
  const names = { reach_test: 'Бот прошёл до двери и обратно', stairs_test: 'Лестницы в обе стороны', void_fall_test: 'Падение за край — смерть' };
  dialog(`<h3>Проверка черновика ${esc(room)}</h3>` + r.results.map(t => `<details ${t.ok ? '' : 'open'}><summary class="${t.ok ? 'ok' : 'warn'}">${t.ok ? '✓' : '✗'} ${esc(names[t.test] || t.test)}</summary><pre class="log">${esc(t.log)}</pre></details>`).join(''));
}

/* ---------- edits of what a generator draws: overrides (lib.js frameEdits, tools/art/studio_overrides.py) ---------- */
const overridableSet = () => new Set(META.overridable || []);
async function pictureData(url) {
  const im = await loadImage(url), c = mk(im.naturalWidth, im.naturalHeight), x = c.getContext('2d', { willReadFrequently: true });
  x.drawImage(im, 0, 0); return { c, x, w: c.width, h: c.height, data: x.getImageData(0, 0, c.width, c.height).data };
}
// The mask of an edit already in the game, so a new one adds to it rather than undoing it.
async function oldMask(path, w, h) {
  const out = new Uint8Array(w * h);
  if (!META.overrides?.[path]) return out;
  try { const m = await pictureData(A(overrideFiles(path).mask)); if (m.w === w && m.h === h) for (let p = 0; p < w * h; p++) out[p] = m.data[p * 4] > 127 ? 1 : 0; } catch {}
  return out;
}
function maskBlob(mask, w, h) {
  const c = mk(w, h), x = c.getContext('2d'), id = x.createImageData(w, h);
  for (let p = 0; p < w * h; p++) { const v = mask[p] ? 255 : 0; id.data.set([v, v, v, 255], p * 4); }
  x.putImageData(id, 0, 0); return canvasBlob(c);
}
// pics: {path: {c (canvas of her picture), mask, w, h}} → the override files and the manifest, into files
async function addOverrides(files, pics) {
  const entries = {}, who = Writer.mode === 'github' ? gh.login : 'local', at = new Date().toISOString().slice(0, 10);
  for (const [path, t] of Object.entries(pics)) {
    if (!t.mask.some(v => v)) continue;
    const f = overrideFiles(path);
    files[f.edit] = await canvasBlob(t.c); files[f.mask] = await maskBlob(t.mask, t.w, t.h);
    entries[path] = { size: [t.w, t.h], by: who, at };
  }
  if (Object.keys(entries).length) files[OVERRIDE_DIR + 'overrides.json'] = mergeOverrides(await repoText(OVERRIDE_DIR + 'overrides.json'), entries);
  return Object.keys(entries);
}
// A character the game draws with a generator (the bestiary, the hero): only the frames she changed,
// laid into the game's own pictures where they lie (build_data's regions), as overrides.
async function gameCharOverrides() {
  const orig = await (await fetch(`import/chars/${encodeURIComponent(P.id)}.sprite.json`, { cache: 'no-store' })).json();
  // a bestiary enemy's strips are named in the archetype tree, which the studio may edit: an animation
  // with more or fewer frames than the game's becomes a strip of its own (resizedStrips), not an override
  const tree = P.origin.generator === 'tools/art/build_bestiary_assets.py';
  const all = frameEdits(P.animations, orig.animations, tree), pics = {}, direct = {};
  const edits = all.filter(e => !e.resize), resized = all.filter(e => e.resize);
  if (!all.length) throw new Error('Нечего отправлять: ни один кадр не отличается от игры. Поправь кадр (✎) или замени картинку.');
  // the studio's cell must be the game's, or every frame lands shifted and cut (the first cultist edit did)
  const cell = all.find(e => e.w !== +P.settings.cellW || e.h !== +P.settings.cellH);
  if (cell) throw new Error(`Кадр в студии ${P.settings.cellW}×${P.settings.cellH}, а в игре у ${P.name} ${cell.w}×${cell.h}. Верни «Ширину» и «Высоту кадра» как в игре (или «Из игры» заново) и отправь ещё раз.`);
  const opaque = (d, n = 0) => { for (let i = 3; i < d.length; i += 4) if (d[i]) n++; return n; };
  const thinner = [];
  for (const e of edits) {
    const path = e.res.replace('res://', '');
    let t = pics[path] || direct[path];
    if (!t) { t = await pictureData(A(path)); t.mask = await oldMask(path, t.w, t.h); (overridableSet().has(path) || generatedSet().has(path) ? pics : direct)[path] = t; }
    const proc = processed.get(e.frame); if (!proc) continue;
    if (e.whole) {
      // a frame replaced whole that keeps much less of the figure than the game has: moved off, cut or emptied
      const was = opaque(t.x.getImageData(e.x, e.y, e.w, e.h).data), now = opaque(proc.getContext('2d').getImageData(0, 0, e.w, e.h).data);
      const an = P.animations.find(a => a.frames.some(f => f.id === e.frame));
      if (was > 50 && now < was * 0.65) thinner.push(`${an?.name} #${an ? an.frames.findIndex(f => f.id === e.frame) + 1 : '?'}: было ${was} px, станет ${now}`);
      t.x.clearRect(e.x, e.y, e.w, e.h); t.x.drawImage(proc, 0, 0, e.w, e.h, e.x, e.y, e.w, e.h);
      for (let y = e.y; y < e.y + e.h; y++) for (let x = e.x; x < e.x + e.w; x++) t.mask[y * t.w + x] = 1;
    } else {
      const d = proc.getContext('2d').getImageData(0, 0, proc.width, proc.height).data;
      for (const [px, py] of e.pixels) {
        const i = (py * proc.width + px) * 4; t.x.clearRect(e.x + px, e.y + py, 1, 1);
        t.x.putImageData(new ImageData(new Uint8ClampedArray(d.slice(i, i + 4)), 1, 1), e.x + px, e.y + py);
        t.mask[(e.y + py) * t.w + e.x + px] = 1;
      }
    }
  }
  if (thinner.length && !confirm(`В игре от персонажа останется заметно меньше:\n${thinner.slice(0, 8).join('\n')}\n\nОбычно это значит, что кадр сдвинут за край или пустой. Проверь кадры (⟲ возвращает сдвиг). Всё равно отправить?`))
    throw new Error('Не отправлено: кадры почти пустые в игре. Поправь сдвиг (⟲) и отправь ещё раз.');
  const files = {};
  for (const [path, t] of Object.entries(direct)) files[path] = await canvasBlob(t.c);
  const done = await addOverrides(files, pics);
  const strips = await resizedStrips(files, resized, orig.animations);
  const frames = edits.length, name = P.name;
  const parts = [frames ? `${frames} кадр(ов) в ${[...done, ...Object.keys(direct)].map(p => '`' + p + '`').join(', ')}` : '',
    ...strips.map(s => `«${s.name}»: ${s.was} → ${s.now} кадр(ов), лента \`${s.path}\``)].filter(Boolean);
  return { files, title: `Studio: ${name} — ${[frames ? `правка ${frames} кадр(ов)` : '', ...strips.map(s => `${s.name} ${s.now} кадр(ов)`)].filter(Boolean).join(', ')}`,
    body: `Правка персонажа игры **${name}**: ${parts.join('; ')}.`,
    notes: [...done.length ? [`Картинки ${name} собирает генератор (${P.origin.generator}); правка лежит в tools/studio/overrides/, и генератор кладёт её поверх своей картинки. Робот студии пересоберёт их в этой же отправке.`] : [],
      ...strips.length ? [`Анимации другой длины (${strips.map(s => s.name).join(', ')}) — свои ленты студии; data/enemy_archetypes/tree.json теперь указывает на них. Если у атаки задан hit_frame, проверь, что такой кадр есть (проверка данных скажет).`] : []] };
}
// An animation of the bestiary with another number of frames than the game's: the whole strip, written
// as a file of the studio's own (a generator never writes it), and the archetype tree pointed at it.
// → [{name, was, now, path}]
async function resizedStrips(files, resized, origAnims) {
  if (!resized.length) return [];
  const TREE = 'data/enemy_archetypes/tree.json';
  let text = files[TREE] || await repoText(TREE);
  const at = JSON.parse(text).findIndex(e => e.id === P.id && e.sprite?.animations);
  if (at < 0) throw new Error(`${P.name} нет в ${TREE} — длину его анимаций студия поменять не может.`);
  const W = +P.settings.cellW, H = +P.settings.cellH, out = [], gen = generatedSet();
  for (const r of resized) {
    const a = P.animations.find(x => x.id === r.anim), fr = a.frames.filter(f => !f.off && processed.has(f.id));
    if (!fr.length) throw new Error(`В «${a.name}» нет готовых кадров.`);
    const sheet = mk(W * fr.length, H), sx = sheet.getContext('2d');
    fr.forEach((f, i) => sx.drawImage(processed.get(f.id), i * W, 0));
    // a strip the studio already made for it is written again; the generator's own is left alone
    const was = r.res.replace('res://', ''), path = gen.has(was) ? `assets/sprites/${slug(P.id)}_studio_${slug(r.name)}.png` : was;
    files[path] = await canvasBlob(sheet);
    if (path !== was) text = patchJson(text, [at, 'sprite', 'animations'], { [r.name]: 'res://' + path });
    out.push({ name: r.name, was: origAnims.find(x => x.id === r.anim).regions.length, now: fr.length, path });
  }
  files[TREE] = text;
  return out;
}
// Any other generated picture she replaced whole (a room's painting): what differs from the game's is hers.
async function convertToOverrides(files) {
  const pics = {};
  for (const path of Object.keys(files).filter(p => generatedSet().has(p) && overridableSet().has(p))) {
    const mine = await pictureData(await blobToDataURL(files[path])), theirs = await pictureData(A(path));
    delete files[path];
    if (mine.w !== theirs.w || mine.h !== theirs.h) throw new Error(`${path}: картинка ${mine.w}×${mine.h}, а в игре ${theirs.w}×${theirs.h}. Правка ложится поверх картинки генератора — размер должен совпадать.`);
    mine.mask = diffMask(mine.data, theirs.data, mine.w, mine.h, 8, await oldMask(path, mine.w, mine.h));
    pics[path] = mine;
  }
  return addOverrides(files, pics);
}

/* ---------- what each part of the studio sends ---------- */
// The red badge's checks (lib.js artChecks) asked once more before her work leaves.
const artOk = () => { const bad = (typeof artReport !== 'undefined' ? artReport : []).filter(c => c.bad);
  return !bad.length || confirm('Проверки нашли:\n' + bad.map(c => '• ' + c.msg).join('\n') + '\n\nВсё равно отправить?'); };

// zip: the strips as they are, for her own use; into the game: a generated character goes as overrides
async function charFiles(zip = false) {
  await build();
  if (!zip && P.origin?.kind === 'game' && P.origin.generator) return gameCharOverrides();
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
  if (CUT.attach) {
    files['tools/rooms/studio_rooms.json'] = mergeStudioRooms(files['tools/rooms/studio_rooms.json'] || await repoText('tools/rooms/studio_rooms.json'), { room: CUT.attach.room, [CUT.attach.when]: id });
    notes.push(`Будет играть в комнате ${CUT.attach.room} ${CUT.attach.when === 'outro_cutscene' ? 'после зачистки' : 'при входе'}; сцену пересоберёт робот студии.`);
  } else notes.push(rooms ? `Катсцену показывает комната ${rooms.join(', ')}.` : 'Катсцену пока не показывает ни одна комната — «🏠 В комнату», чтобы подключить.');
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
    case 'game': gameDialog(); break;
    case 'chars-game': if (artOk()) sendToGame(charFiles, 'chars'); break;
    case 'bg-game': sendToGame(bgFiles, 'bg'); break;
    case 'cut-game-send': sendToGame(cutFiles, 'cut'); break;
    case 'sent': sentDialog(); break;
    case 'chars-enemy': if (artOk()) enemyWizard(); break;
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
  workspace: o => { if (o.pendingPr) localStorage.setItem('ss_workspace_pr', o.pendingPr); },
  bg: o => DB.put(o, 'backgrounds').catch(() => {}), cut: o => DB.put(o, 'cutscenes').catch(() => {}) })[tab];
let sentCache = [];
// Her pull requests (the studio names its branches studio/<login>-…), with checks and whether the site has them.
async function fetchSent() {
  if (Writer.mode !== 'github') return loadSent().map(e => ({ ...e, status: e.local ? { key: 'local', label: 'записано в папку игры', tone: 'ok' } : null }));
  const R = `/repos/${META.repo}`;
  const prs = (await ghApi(`${R}/pulls?state=all&per_page=50&sort=created&direction=desc`)).filter(p => p.head.ref.startsWith(`studio/${gh.login}-`)).slice(0, 20);
  return Promise.all(prs.map(async p => {
    let checks = null, deployed = false, review = null, notes = [], preview = null;
    if (p.state === 'open') {
      try {
        const runs = (await ghApi(`${R}/commits/${p.head.sha}/check-runs?per_page=100`)).check_runs || [];
        checks = { total: runs.length, pending: runs.filter(r => r.status !== 'completed').length, failed: runs.filter(r => ['failure', 'timed_out', 'cancelled'].includes(r.conclusion)).length };
      } catch {}
      preview = await previewOf(p);
    }
    try {
      // what the owner said: reviews, comments on lines, and the conversation
      const [reviews, lineNotes, talk] = await Promise.all([ghApi(`${R}/pulls/${p.number}/reviews`), ghApi(`${R}/pulls/${p.number}/comments`), ghApi(`${R}/issues/${p.number}/comments`)]);
      review = [...reviews].reverse().find(v => v.state !== 'COMMENTED')?.state || null;
      notes = [...reviews.filter(v => v.body).map(v => ({ who: v.user.login, at: v.submitted_at, text: v.body, tag: v.state === 'CHANGES_REQUESTED' ? 'просит исправить' : v.state === 'APPROVED' ? 'одобрил' : '' })),
        ...lineNotes.map(c => ({ who: c.user.login, at: c.created_at, text: c.body, tag: c.path.split('/').pop() })),
        ...talk.filter(c => !/Sprite Studio|coderabbit/i.test(c.user.login + c.body.slice(0, 80))).map(c => ({ who: c.user.login, at: c.created_at, text: c.body }))]
        .filter(n => n.who !== gh.login || n.tag === undefined).sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
      notes = notes.concat(talk.filter(c => c.user.login === gh.login).map(c => ({ who: c.user.login, at: c.created_at, text: c.body, mine: true }))).sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
    } catch {}
    if (p.merged_at && META.sha) {
      try { const c = await ghApi(`${R}/compare/${p.merge_commit_sha}...${META.sha}`); deployed = c.status === 'ahead' || c.status === 'identical'; } catch {}
    }
    return { number: p.number, url: p.html_url, title: p.title, at: Date.parse(p.created_at), head: p.head.sha, branch: p.head.ref,
      notes: [...new Map(notes.map(n => [n.at + n.who + n.text, n])).values()], preview,
      status: prStatus({ state: p.state, merged: !!p.merged_at, checks, deployed, review }) };
  }));
}
// The playable preview pages.yml builds for an open studio pull request.
async function previewOf(p) {
  if (!META.site) return null;
  let room = null, practice = null, composed = false;
  try {
    const files = (await ghApi(`/repos/${META.repo}/pulls/${p.number}/files?per_page=100`)).map(f => f.filename);
    const scene = files.map(f => f.match(/^data\/cutscenes\/(.+)\.json$/)?.[1]).find(Boolean);
    room = scene && cutData?.played_in?.[scene]?.[0] || null;
    if (scene && files.includes('tools/rooms/studio_rooms.json')) {
      const table = JSON.parse(await ghApi(`/repos/${META.repo}/contents/tools/rooms/studio_rooms.json?ref=${p.head.sha}`, { raw: true, headers: { Accept: 'application/vnd.github.raw' } }));
      room = Object.keys(table).find(r => [table[r].intro_cutscene, table[r].outro_cutscene].includes(scene)) || room;
    }
    practice = files.map(f => f.match(/^data\/enemies\/(.+)\.json$/)?.[1]).find(Boolean) || null;
    // a room the «Конструктор» put together opens as its draft (run.gd, --composed) unless it went live
    if (!room && !practice && files.includes('tools/rooms/composed_rooms.json')) {
      const read = ref => ghApi(`/repos/${META.repo}/contents/tools/rooms/composed_rooms.json?ref=${ref}`, { raw: true, headers: { Accept: 'application/vnd.github.raw' } }).then(JSON.parse).catch(() => ({}));
      const [table, before] = await Promise.all([read(p.head.sha), read(p.base.sha)]);
      // the room this sending changed
      const name = Object.keys(table).find(n => JSON.stringify(table[n]) !== JSON.stringify(before[n])) || Object.keys(table)[0];
      if (name) { room = name; composed = !table[name].live; }
    }
  } catch {}
  const q = practice ? '?practice=' + practice : room ? '?room=' + room + (composed ? '&composed=1' : '') : '';
  try {
    const j = await (await fetch(`${META.site}preview/${p.number}.json`, { cache: 'no-store' })).json();
    return { ready: j.sha === p.head.sha, url: `${META.site}preview-${p.number}.html${q}`, room, practice, composed };
  } catch { return { ready: false, room, practice, composed }; }
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
      ${e.preview ? `<div class="wide">${e.preview.ready ? `<a href="${esc(e.preview.url)}" target="_blank" rel="noopener"><b>▶ Играть с моими правками</b></a>${e.preview.practice ? ` <span class="muted">(сразу на тренировку с ${esc(e.preview.practice)})</span>` : e.preview.room ? ` <span class="muted">(сразу в ${e.preview.composed ? 'собранную комнату' : 'комнату'} ${esc(e.preview.room)})</span>` : ''}` : '<span class="muted">превью игры собирается… (несколько минут после отправки)</span>'}</div>` : ''}
      ${e.notes?.length || e.status?.key === 'changes' || e.preview ? `<details class="wide" ${e.status?.key === 'changes' ? 'open' : ''}><summary>Замечания${e.notes?.length ? ` (${e.notes.length})` : ''}</summary>
        ${(e.notes || []).map(n => `<div class="note-item ${n.mine ? 'mine' : ''}"><b>${esc(n.who)}</b>${n.tag ? ` <span class="badge">${esc(n.tag)}</span>` : ''} <span class="muted">${new Date(n.at).toLocaleString('ru')}</span><div>${esc(n.text)}</div></div>`).join('') || '<div class="muted">Замечаний нет.</div>'}
        ${e.status?.key === 'changes' ? '<div class="note">Открой отправку в студии, поправь и нажми «→ В игру» — исправления лягут в эту же отправку.</div>' : ''}
        <div class="row"><textarea data-reply="${e.number}" rows="2" placeholder="Ответить…" style="flex:1"></textarea><button class="sm" data-send-reply="${e.number}">Ответить</button></div>
      </details>` : ''}
    </div>`).join('') || '<div class="muted">Пока ничего не отправлено.</div>';
  await dialog(`<h3>Мои отправки</h3>
    <div class="note">«на проверке» — CI проверяет данные; «проверено» — ждёт, когда владелец вольёт; «в игре» — уже на сайте игры и в студии у всех. Через «Открыть в студии» можно вернуть отправленное и на другом компьютере.</div>
    <div class="sentlist">${rows}</div>`);
}
// Bring a sent project back from its branch (or from main once it is in).
async function openFromPr(number) {
  try {
    const R = `/repos/${META.repo}`, pr = await ghApi(`${R}/pulls/${number}`), ref = pr.merged_at ? META.branch : pr.head.sha;
    const files = (await ghApi(`${R}/pulls/${number}/files?per_page=100`)).map(f => f.filename).filter(f => /^tools\/studio\/projects\/(chars|bgs|cuts|workspaces)\/[^/]+\.json$/.test(f));
    if (!files.length) return toast('В этой отправке нет проекта студии (это звуки или старая отправка)', 'err');
    for (const f of files) {
      if (f.includes('/workspaces/')) { if (!pr.merged_at) localStorage.setItem('ss_workspace_pr', number); await workspaceRestore(JSON.parse(await ghApi(`${R}/contents/${f}?ref=${ref}`, { raw: true, headers: { Accept: 'application/vnd.github.raw' } }))); return; }
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

document.addEventListener('click', async e => {
  const b = e.target.closest('[data-send-reply]'); if (!b) return;
  const n = b.dataset.sendReply, box = document.querySelector(`[data-reply="${n}"]`), text = box?.value.trim();
  if (!text) return;
  try { await ghApi(`/repos/${META.repo}/issues/${n}/comments`, { method: 'POST', body: JSON.stringify({ body: text }) }); box.value = ''; toast('Ответ отправлен'); sentDialog(); }
  catch (err) { toast('Не отправилось: ' + err.message, 'err'); }
});

/* ---------- a character becomes an enemy (its voice: <id>_<kind>_N.wav, Enemy._voice) ---------- */
const ENEMY_VOICES = [['alert', 'заметил'], ['attack', 'замах'], ['hurt', 'больно'], ['death', 'смерть']];
let ewVoices = {}, ewAvatar = null, ewRec = null;
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-ewv]'); if (!b) return;
  const row = b.closest('[data-ew-voice]'), kind = row?.dataset.ewVoice, state = row?.querySelector('.ewv-state');
  const mark = () => { if (state) state.textContent = ewVoices[kind] ? 'свой ✓' : 'как у образца'; };
  if (b.dataset.ewv === 'up') { const [f] = await pickFiles('audio/*,.wav,.mp3,.ogg', false); if (f) { try { await AC().decodeAudioData(await f.arrayBuffer()); ewVoices[kind] = f; } catch { toast('Не читается как звук', 'err'); } mark(); } }
  else if (b.dataset.ewv === 'play') { AC().resume?.(); const src = ewVoices[kind]; if (src) playBuf(await AC().decodeAudioData(await src.arrayBuffer())); else { const base = enemyList.find(x => x.id === document.getElementById('ewBase').value); const ent = sndEntry(`sfx/${base?.voice}_${kind}`); if (ent?.takes[0]) playBuf(await takeBuffer(ent.takes[0])); else toast('У образца нет такого звука'); } }
  else if (b.dataset.ewv === 'rec') {
    if (ewRec) { ewRec.stop(); return; }
    let stream; try { stream = await navigator.mediaDevices.getUserMedia({ audio: true }); } catch { return toast('Нет доступа к микрофону', 'err'); }
    const chunks = [], rec = new MediaRecorder(stream); ewRec = rec; b.textContent = '■ Стоп';
    rec.ondataavailable = ev => chunks.push(ev.data);
    rec.onstop = () => { stream.getTracks().forEach(t => t.stop()); ewRec = null; b.textContent = '● Запись'; ewVoices[kind] = new Blob(chunks, { type: rec.mimeType }); mark(); };
    rec.start();
  }
  else if (b.dataset.ewv === 'avatar') { const [f] = await pickFiles('image/*', false); if (f) { ewAvatar = await normalizeImage(await blobToDataURL(f), 128); document.getElementById('ewAvatar').textContent = 'своя картинка ✓'; } }
});
async function wavOf(blobOrUrl) {
  const buf = blobOrUrl instanceof Blob ? await AC().decodeAudioData(await blobOrUrl.arrayBuffer()) : await decodeUrl(A(blobOrUrl));
  return encodeWav(buf);
}

/* ---------- a character becomes an enemy: data/enemies/<id>.json that extends one the game has ---------- */
const ENEMY_SLOTS = [['idle', 'покой (обязательно)'], ['walk', 'ходьба'], ['attack', 'атака'], ['attack_alt', 'вторая атака'], ['special', 'особое'], ['hurt', 'боль'], ['death', 'смерть']];
const BEHAVIOUR_RU = { walker: 'ходит и бьёт', flyer: 'летает', caster: 'держит дистанцию и колдует' };
let enemyList = null;
async function enemyWizard() {
  if (!P) return;
  try { enemyList ||= await (await fetch('import/enemies.json')).json(); } catch { enemyList = []; }
  const bases = enemyList.filter(e => !e.boss && !e.extends && BEHAVIOUR_RU[e.behaviour] && e.bestiary !== false);
  if (!bases.length) return dialog('<h3>Сделать врагом</h3><p>Нет данных о врагах игры: запусти студию из папки игры или с сайта.</p>');
  const S = P.settings, id = slug(P.name), anims = P.animations;
  const pick = slot => enemySlotFor(anims, slot)?.id || '';
  const taken = enemyList.some(e => e.id === id);
  let getPlace = null; ewVoices = {}; ewAvatar = null;
  setTimeout(() => { const box = document.getElementById('ewPlace'); if (box) getPlace = roomPicker(box, id); });
  await dialog(`<h3>Сделать «${esc(P.name)}» врагом</h3>
    <div class="fgrid">
      <div><label>Имя файла (латиницей)</label><input id="ewId" value="${esc(taken ? id + '_2' : id)}"></div>
      <div><label>Похож по бою на…</label><select id="ewBase">${bases.map(e => `<option value="${e.id}">${esc(e.name.ru || e.id)} — ${BEHAVIOUR_RU[e.behaviour]}, ${e.attacks.join(' + ')}, ${e.hp} HP</option>`).join('')}</select></div>
      <div><label>Имя (рус.)</label><input id="ewNameRu" placeholder="Лучница"></div>
      <div><label>Имя (англ.)</label><input id="ewNameEn" placeholder="Archer"></div>
      <div class="wide"><label>Кто это (рус., для бестиария)</label><textarea id="ewLoreRu" rows="2"></textarea></div>
      <div class="wide"><label>Кто это (англ.)</label><textarea id="ewLoreEn" rows="2"></textarea></div>
      <div class="wide"><label>Как с ней драться — подсказка после смерти (рус.)</label><textarea id="ewTipRu" rows="2" placeholder="Стреляет после короткого замаха — перекатись сквозь стрелу и бей вблизи."></textarea></div>
      <div class="wide"><label>Подсказка (англ.)</label><textarea id="ewTipEn" rows="2"></textarea></div>
    </div>
    <h3 style="margin-top:12px">Анимации</h3>
    <div class="fgrid">${ENEMY_SLOTS.map(([slot, ru]) => `<div><label>${ru}</label><select data-ew-slot="${slot}"><option value="">— нет —</option>${anims.map(a => `<option value="${a.id}" ${pick(slot) === a.id ? 'selected' : ''}>${esc(a.name)}</option>`).join('')}</select></div>`).join('')}</div>
    ${+S.bottomPad !== 1 ? `<div class="warn" id="ewPad">У врагов ноги стоят на 1 px выше низа кадра (так ставит их enemy.gd), а у этого персонажа отступ снизу ${S.bottomPad}. <button class="sm" data-act="ew-pad">Поставить 1</button></div>` : ''}
    <h3 style="margin-top:12px">Голос</h3>
    <div class="ewvoice">${ENEMY_VOICES.map(([k, ru]) => `<div class="row" style="margin:2px 0" data-ew-voice="${k}"><span style="width:90px">${ru}</span>
      <button class="sm" data-ewv="up">⬆ Файл</button><button class="sm" data-ewv="rec">● Запись</button><button class="sm ghost" data-ewv="play">▶</button><span class="muted ewv-state">как у образца</span></div>`).join('')}</div>
    <div class="note">Без своих звуков враг кричит голосом того, на кого похож. Если дать хотя бы один — недостающие студия возьмёт у образца.</div>
    <h3 style="margin-top:12px">Портрет для бестиария</h3>
    <div class="row" style="margin:0"><button class="sm" data-ewv="avatar">⬆ Своя картинка</button><span class="muted" id="ewAvatar">по умолчанию — анимация покоя</span></div>
    <h3 style="margin-top:12px">Где появляется</h3>
    <div id="ewPlace"></div>
    <div class="note">Бой (здоровье, скорость, атаки) враг берёт у выбранного. Подраться с ним можно сразу на тренировочном дворе в превью.</div>
    <div class="warn" id="ewErr"></div>`,
    [['→ В игру', d => {
      const v = q => d.querySelector(q).value.trim(), form = { id: slug(v('#ewId')), base: v('#ewBase'), place: getPlace?.() || null, voices: { ...ewVoices }, avatar: ewAvatar,
        name: { ru: v('#ewNameRu'), en: v('#ewNameEn') }, lore: { ru: v('#ewLoreRu'), en: v('#ewLoreEn') }, tip: { ru: v('#ewTipRu'), en: v('#ewTipEn') },
        map: Object.fromEntries([...d.querySelectorAll('[data-ew-slot]')].map(x => [x.dataset.ewSlot, x.value])) };
      const err = !form.id ? 'Нужно имя файла' : enemyList.some(e => e.id === form.id) ? `Враг «${form.id}» в игре уже есть — выбери другое имя` : !form.map.idle ? 'Нужна анимация «покой»'
        : !(form.name.ru || form.name.en) ? 'Нужно имя' : !(form.tip.ru || form.tip.en) ? 'Нужна подсказка «как драться» — без неё игра не примет врага' : '';
      if (err) { d.querySelector('#ewErr').textContent = err; return false; }
      setTimeout(() => sendToGame(() => enemyFiles(form), 'chars'));
    }, 'primary'], ['Отмена']]);
}
document.addEventListener('click', e => { if (e.target.closest('[data-act="ew-pad"]')) { P.settings.bottomPad = 1; save(); renderSide(); scheduleBuild(0); document.getElementById('ewPad')?.remove(); toast('Отступ снизу: 1 px'); } });
async function enemyFiles(f) {
  await build();
  const S = P.settings, W = +S.cellW, H = +S.cellH, files = {}, animations = {};
  for (const [slot, animId] of Object.entries(f.map)) {
    const a = animId && P.animations.find(x => x.id === animId); if (!a) continue;
    const frames = a.frames.filter(fr => !fr.off && processed.has(fr.id)); if (!frames.length) continue;
    const sheet = mk(W * frames.length, H), x = sheet.getContext('2d');
    frames.forEach((fr, i) => x.drawImage(processed.get(fr.id), i * W, 0));
    const path = `assets/sprites/${f.id}_${slot}.png`;
    files[path] = await canvasBlob(sheet); animations[slot] = 'res://' + path;
  }
  if (!animations.idle) throw new Error('В анимации «покой» нет готовых кадров');
  const KEY = f.id.toUpperCase(), fps = +P.animations.find(x => x.id === f.map.idle)?.fps || 8;
  const entry = { id: f.id, extends: f.base, name: `ENEMY_${KEY}`, lore: `ENEMY_${KEY}_LORE`, tip: `TIP_${KEY}`, sprite: { cell: [W, H], fps, animations } };
  const baseVoice = enemyList.find(e => e.id === f.base)?.voice || f.base;
  if (Object.keys(f.voices || {}).length) {
    await loadSndLib();
    for (const [kind] of ENEMY_VOICES) {
      if (f.voices[kind]) { files[`assets/audio/sfx/${f.id}_${kind}_1.wav`] = await wavOf(f.voices[kind]); continue; }
      // a cue she did not record keeps the voice of the one it fights like
      const takes = sndEntry(`sfx/${baseVoice}_${kind}`)?.takes || [];
      for (const [i, t] of takes.filter(t => t.url).entries()) files[`assets/audio/sfx/${f.id}_${kind}_${i + 1}.wav`] = await wavOf(t.url);
    }
  } else entry.voice = baseVoice;
  if (f.avatar) { files[`assets/portraits/${f.id}.png`] = dataURLtoBlob(f.avatar); entry.avatar = `res://assets/portraits/${f.id}.png`; }
  files[`data/enemies/${f.id}.json`] = JSON.stringify(entry, null, 2) + '\n';
  const fill = v => ({ ru: v.ru || v.en, en: v.en || v.ru });
  files['localization/strings.csv'] = mergeStrings(await repoText('localization/strings.csv'),
    { [entry.name]: fill(f.name), [entry.lore]: fill(f.lore.ru || f.lore.en ? f.lore : { ru: '…', en: '…' }), [entry.tip]: fill(f.tip) });
  if (f.place) files['tools/rooms/studio_rooms.json'] = mergeStudioRooms(await repoText('tools/rooms/studio_rooms.json'), { room: f.place.room, spawn: [f.id, f.place.x, f.place.y] });
  return { files, title: `Studio: enemy ${f.id}`,
    body: `Новый враг **${f.id}** (бой как у \`${f.base}\`): анимации ${Object.keys(animations).join(', ')}, кадр ${W}×${H}.`,
    notes: [`Подраться с ним: превью этой отправки с ?practice=${f.id}.`,
      ...(['name', 'tip'].some(k => !f[k].en) ? ['Имя или подсказка без английского: в английской версии (и в uk / zh_CN) пока стоит русский текст — впиши «(англ.)» и отправь ещё раз.'] : []),
      f.place ? `Стоит в комнате ${f.place.room} (${f.place.x}, ${f.place.y}); сцену пересоберёт робот студии и проверит, что до врага можно дойти.` : 'В комнаты не поставлен — только тренировочный двор.'] };
}

/* ---------- pictures without a key in the browser ---------- */
// Local: tools/studio/serve.py runs generate_image.py with its own OPENAI_API_KEY.
async function localImage(req, refs) {
  const r = await (await fetch('/api/image', { method: 'POST', body: JSON.stringify({ ...req, refs }) })).json();
  if (!r.ok) throw new Error(r.error);
  return 'data:image/png;base64,' + r.b64;
}
// Hosted: a studio-gen/<login> branch = main + one commit with the request;
// .github/workflows/studio-images.yml answers with out.png beside it.
async function robotImage(req, refs) {
  const R = `/repos/${META.repo}`, branch = `studio-gen/${gh.login}`, id = uid(), dir = `tools/studio/requests/${id}`;
  const main = await ghApi(`${R}/git/ref/heads/${META.branch}`), head = await ghApi(`${R}/git/commits/${main.object.sha}`);
  const tree = [];
  for (const [i, d] of refs.entries()) {
    const b = await ghApi(`${R}/git/blobs`, { method: 'POST', body: JSON.stringify({ content: await blobB64(dataURLtoBlob(d)), encoding: 'base64' }) });
    tree.push({ path: `${dir}/ref${i}.png`, mode: '100644', type: 'blob', sha: b.sha });
  }
  tree.push({ path: `${dir}/request.json`, mode: '100644', type: 'blob', content: JSON.stringify({ ...req, refs: refs.map((_, i) => `ref${i}.png`), out: 'out.png' }, null, 2) });
  const t = await ghApi(`${R}/git/trees`, { method: 'POST', body: JSON.stringify({ base_tree: head.tree.sha, tree }) });
  const c = await ghApi(`${R}/git/commits`, { method: 'POST', body: JSON.stringify({ message: `Studio images: request ${id}`, tree: t.sha, parents: [main.object.sha] }) });
  try { await ghApi(`${R}/git/refs/heads/${branch}`, { method: 'PATCH', body: JSON.stringify({ sha: c.sha, force: true }) }); }
  catch (e) { if (e.status !== 422 && e.status !== 404) throw e; await ghApi(`${R}/git/refs`, { method: 'POST', body: JSON.stringify({ ref: 'refs/heads/' + branch, sha: c.sha }) }); }
  toast('Картинка заказана — робот GitHub рисует (обычно до минуты)…');
  const since = Date.now();
  while (Date.now() - since < 5 * 60e3) {
    await new Promise(r => setTimeout(r, 6000));
    const res = await fetch(`https://api.github.com${R}/contents/${dir}/out.png?ref=${encodeURIComponent(branch)}`, { headers: { Authorization: 'Bearer ' + gh.token, Accept: 'application/vnd.github.raw' }, cache: 'no-store' });
    if (res.ok) return blobToDataURL(await res.blob());
    const runs = (await ghApi(`${R}/actions/runs?branch=${encodeURIComponent(branch)}&head_sha=${c.sha}`)).workflow_runs || [];
    const failed = runs.find(x => x.conclusion === 'failure');
    if (failed) throw new Error(`робот не смог нарисовать: ${failed.html_url} (если там «OPENAI_API_KEY is not set» — владелец ещё не добавил ключ в секреты репозитория)`);
  }
  throw new Error('робот не ответил за 5 минут');
}
