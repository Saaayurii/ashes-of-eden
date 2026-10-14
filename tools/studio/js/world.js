/* Game data inspector: enemy behavior, gifts, props/rewards and room encounters. */
'use strict';
const WORLD = { data: null, work: {}, file: '', index: 0, query: '' };
async function worldLoad() {
  if (WORLD.data) return;
  WORLD.data = await (await fetch('import/world.json')).json();
  WORLD.work = JSON.parse(localStorage.getItem('ss_world') || '{}');
  draftBase('world', WORLD.data.files, Object.keys(WORLD.work).length > 0);
  WORLD.file = localStorage.getItem('ss_world_file') || Object.keys(WORLD.data.files)[0];
  if (!(WORLD.file in WORLD.data.files)) WORLD.file = Object.keys(WORLD.data.files)[0];
}
const worldDoc = () => WORLD.work[WORLD.file] ?? WORLD.data.files[WORLD.file];
const worldItem = () => worldDoc().actions ? Object.values(worldDoc().actions)[WORLD.index] : Array.isArray(worldDoc()) ? worldDoc()[WORLD.index] : worldDoc();
function worldSave() { localStorage.setItem('ss_world', JSON.stringify(WORLD.work)); localStorage.setItem('ss_world_file', WORLD.file); draftHistory('world'); }
function worldEdit(k, v) { const d = structuredClone(worldDoc()), item = d.actions ? Object.values(d.actions)[WORLD.index] : Array.isArray(d) ? d[WORLD.index] : d; item[k] = v; WORLD.work[WORLD.file] = d; worldSave(); renderWorld(); }
function renderWorld() {
  const files = Object.keys(WORLD.data.files).filter(f => f.includes(WORLD.query));
  $('#worldFiles').innerHTML = files.map(f => `<button class="sm ${f === WORLD.file ? 'on' : ''}" data-world-file="${esc(f)}">${esc(f.replace('data/', ''))}${WORLD.work[f] ? ' •' : ''}</button>`).join('');
  const doc = worldDoc(), a = worldItem();
  $('#worldTitle').textContent = WORLD.file;
  $('#worldItem').hidden = !Array.isArray(doc) && !doc.actions;
  $('#worldItem').innerHTML = doc.actions ? Object.keys(doc.actions).map((id, i) => `<option value="${i}">${esc(id)}</option>`).join('') : Array.isArray(doc) ? doc.map((a, i) => `<option value="${i}">${esc(a.id || a.name || i + 1)}</option>`).join('') : ''; $('#worldItem').value = WORLD.index;
  const labels = { hp: 'Здоровье', speed: 'Скорость', aggro_range: 'Радиус агрессии', armor: 'Броня (0…1)', damage: 'Контактный урон', stagger_chance: 'Шанс прервать атаку (0…1)', essence: 'Награда: эссенция', ash: 'Награда: пепел', attack_interval: 'Интервал атаки', from_hp: 'Фаза: ниже доли здоровья', unlock_nights: 'Доступно после ночи', cooldown: 'Перезарядка', multiplier: 'Множитель урона', knockback: 'Отбрасывание', animation_time: 'Длительность анимации, с', recovery: 'Перезарядка × базовая', hit_frame: 'Кадр удара (в JSON с 0)', radius: 'Радиус, px', stagger: 'Оглушение, с' };
  $('#worldProps').innerHTML = a && typeof a === 'object' ? Object.entries(labels).filter(([k]) => k in a).map(([k, label]) => `<label>${label}<input type="number" step="0.05" data-world-prop="${k}" value="${a[k]}"></label>`).join('') + (a.behaviour ? `<label>Поведение<select data-world-prop="behaviour">${[...new Set(['walker','caster','flyer','boss_ophanim','seal','dummy', a.behaviour])].map(v => `<option${v === a.behaviour ? ' selected' : ''}>${v}</option>`).join('')}</select></label>` : '') : '';
  $('#worldJson').value = JSON.stringify(doc, null, 2);
  $('#worldStatus').textContent = `${Object.keys(WORLD.work).length} изменённых файлов. Условия фаз и AI, эффекты способностей и награды редактируются также в JSON ниже.`;
}
async function worldFiles() {
  const files = {};
  for (const [path, mine] of Object.entries(WORLD.work)) {
    const text = await repoText(path), latest = JSON.parse(text), base = draftBase('world', WORLD.data.files)[path];
    const merged = await resolveDraft(base, mine, latest, path, BASES.world.uncertain);
    if (!sameDraft(merged, latest)) files[path] = path === 'tools/rooms/studio_rooms.json' ? fmtStudioRooms(merged) : gdText(text, merged);
  }
  if (!Object.keys(files).length) throw new Error('Нет изменений поведения.');
  return { files, title: 'Studio: game behavior and encounters', body: 'Game data edited in «Поведение»: ' + Object.keys(files).join(', ') };
}
async function worldEnter() { try { await worldLoad(); trackChange('world'); renderWorld(); await worldRooms(); } catch (e) { toast(e.message, 'err'); } }
async function worldRooms() {
  await loadCutData();
  $('#worldRoom').innerHTML = roomNames().map(n => `<option>${esc(n)}</option>`).join('');
  await worldRoomOpen();
}
async function worldRoomOpen() {
  const room = await loadRoom($('#worldRoom').value); if (!room) return;
  const doc = WORLD.work['tools/rooms/studio_rooms.json'] || WORLD.data.files['tools/rooms/studio_rooms.json'];
  const extra = doc[room.name] || {};
  $('#worldSpawns').value = JSON.stringify(extra.spawns_override || room.spawns, null, 2);
  $('#worldWaves').value = JSON.stringify(extra.waves || [], null, 2);
  drawRoomOverview($('#worldMap'), room, null, '');
  WORLD.room = room;
}
function worldRoomApply() {
  const spawns = JSON.parse($('#worldSpawns').value), waves = JSON.parse($('#worldWaves').value);
  const check = list => { if (!Array.isArray(list)) throw new Error('Нужен список размещений'); for (const row of list) if (!Array.isArray(row) || row.length !== 3 || !WORLD.data.enemies.includes(row[0]) || !Number.isFinite(row[1]) || !Number.isFinite(row[2])) throw new Error('Размещение: [существующий враг, x, y]'); };
  check(spawns); if (!Array.isArray(waves)) throw new Error('Нужен список волн'); waves.forEach(check);
  const path = 'tools/rooms/studio_rooms.json', doc = structuredClone(WORLD.work[path] || WORLD.data.files[path]);
  doc[WORLD.room.name] = { ...doc[WORLD.room.name], spawns_override: spawns, spawns: [], waves };
  WORLD.work[path] = doc; worldSave(); renderWorld(); drawRoomOverview($('#worldMap'), { ...WORLD.room, spawns }, null, ''); toast('Размещения и волны сохранены в черновике');
}
$('#worldSearch').oninput = e => { WORLD.query = e.target.value; renderWorld(); };
$('#worldFiles').onclick = e => { const b = e.target.closest('[data-world-file]'); if (!b) return; WORLD.file = b.dataset.worldFile; WORLD.index = 0; renderWorld(); localStorage.setItem('ss_world_file', WORLD.file); };
$('#worldItem').onchange = e => { WORLD.index = +e.target.value; renderWorld(); };
$('#worldProps').onchange = e => { const k = e.target.dataset.worldProp; if (k) worldEdit(k, e.target.type === 'number' ? +e.target.value : e.target.value); };
$('#worldApply').onclick = () => { try { const d = JSON.parse($('#worldJson').value); if (!d || typeof d !== 'object') throw new Error('Нужен объект или список'); WORLD.work[WORLD.file] = d; worldSave(); renderWorld(); } catch (e) { toast(e.message, 'err'); } };
$('#worldReset').onclick = () => { delete WORLD.work[WORLD.file]; worldSave(); renderWorld(); };
$('#worldRoom').onchange = worldRoomOpen;
$('#worldRoomApply').onclick = () => { try { worldRoomApply(); } catch (e) { toast(e.message, 'err'); } };
$('#worldMap').onclick = e => {
  const room = WORLD.room, rect = e.target.getBoundingClientRect(), at = snapToSurface(room.surfaces, (e.clientX - rect.left) / rect.width * room.width, (e.clientY - rect.top) / rect.height * room.height);
  if (!at) return toast('Выбери точку над полом', 'err');
  const list = JSON.parse($('#worldSpawns').value), i = +$('#worldSpawnIndex').value - 1;
  if (!list[i]) return toast('Укажи номер размещения с 1', 'err');
  list[i][1] = at.x; list[i][2] = at.y; $('#worldSpawns').value = JSON.stringify(list, null, 2); worldRoomApply();
};
