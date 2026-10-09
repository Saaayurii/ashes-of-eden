/* Sprite Studio — placing things in the game's rooms: an enemy on a floor, a
 * cutscene on a room's entry or clear. Both end up in tools/rooms/studio_rooms.json,
 * the room generator's input (its robot regenerates the scenes on a pull request). */
'use strict';

const roomCache = new Map();
async function loadRoom(name) {
  if (!roomCache.has(name)) roomCache.set(name, fetch(`import/rooms/room_${name}.bg.json`).then(r => r.json()).catch(() => null));
  return roomCache.get(name);
}
const roomNames = () => cutData?.room_order?.length ? cutData.room_order : bgs.filter(b => b.origin?.room).map(b => b.origin.room);

// The whole room at once, scaled to the canvas: layers at camera zero, the
// floors an enemy can stand on, the enemies already there, and the new spot.
const roomPics = new Map();  // url -> decoded picture, or null while it loads
function roomPic(url, redraw) {
  if (!roomPics.has(url)) { roomPics.set(url, null); loadImage(url).then(im => { roomPics.set(url, im); redraw(); }).catch(() => {}); }
  return roomPics.get(url);
}
function drawRoomOverview(c, room, spot, enemyId) {
  const W = c.clientWidth || 640, k = W / room.width, H = Math.round(room.height * k);
  if (c.width !== W || c.height !== H) { c.width = W; c.height = H; }
  const x = c.getContext('2d'), redraw = () => drawRoomOverview(c, room, spot, enemyId);
  x.fillStyle = '#000'; x.fillRect(0, 0, W, H);
  for (const l of room.layers || []) for (const it of l.items) {
    x.globalAlpha = l.opacity ?? 1;
    if (it.kind === 'rect') { x.fillStyle = rgba(it.color, 1); x.fillRect(it.x * k, it.y * k, it.w * k, it.h * k); continue; }
    const meta = room.images[it.img], im = meta && roomPic(meta.src || A(meta.url), redraw);
    if (im) x.drawImage(im, it.x * k, it.y * k, im.width * Math.abs(it.sx) * k, im.height * Math.abs(it.sy) * k);
  }
  x.globalAlpha = 1;
  x.fillStyle = 'rgba(124,195,107,.9)';
  for (const [sx, sy, sw] of room.surfaces || []) x.fillRect(sx * k, sy * k - 1, sw * k, 2);
  x.font = '11px system-ui';
  for (const [id, ex, ey, hang] of room.spawns || []) {
    if (id === enemyId && !hang) continue;
    x.fillStyle = '#e06464';
    if (hang) hangMark(x, ex * k, ey * k, k, 'rgba(224,100,100,.8)');
    x.beginPath(); x.arc(ex * k, (hang ? ey - HANG_LIFT_PX : ey) * k, 4, 0, 7); x.fill(); x.fillText(id, ex * k + 6, ey * k - 4);
  }
  if (spot) {
    const sy = spot.hang ? spot.y - HANG_LIFT_PX : spot.y;
    if (spot.hang) hangMark(x, spot.x * k, spot.y * k, k, 'rgba(106,168,255,.9)');
    x.fillStyle = '#6aa8ff'; x.beginPath(); x.arc(spot.x * k, sy * k, 6, 0, 7); x.fill(); x.fillStyle = '#fff'; x.fillText(enemyId || 'здесь', spot.x * k + 8, sy * k - 6);
  }
}

// A hanger on the map: the body a little over the floor, a rope going up into the dark.
const HANG_LIFT_PX = 50;
function hangMark(x, px, py, k, colour) {
  x.strokeStyle = colour; x.lineWidth = 1.5; x.setLineDash([3, 3]);
  x.beginPath(); x.moveTo(px, py - HANG_LIFT_PX * k); x.lineTo(px, py - (HANG_LIFT_PX + 170) * k); x.stroke();
  x.setLineDash([]);
}

// «🪢 Повесить»: an enemy that can hang ("hang" in its data, docs: Enemy._hang)
// on a noose over a floor she clicks; it waits there until the hero walks under
// it, then the rope snaps. Goes to tools/rooms/studio_rooms.json "hangers".
async function hangDialog() {
  try { enemyList ||= await (await fetch('import/enemies.json')).json(); } catch { enemyList = []; }
  const hangers = enemyList.filter(e => e.hang);
  if (!hangers.length) return dialog('<h3>Повесить</h3><p>Ни один враг в игре пока не умеет висеть.</p>');
  let getPlace = null, who = hangers[0].id;
  setTimeout(() => {
    const box = document.getElementById('hgPlace'); if (!box) return;
    getPlace = roomPicker(box, who, null, true);
    document.getElementById('hgWho').onchange = e => { who = e.target.value; };
  });
  await dialog(`<h3>🪢 Повесить в комнате</h3>
    <div class="note">Враг висит на верёвке над полом, куда ты кликнешь. Пока висит — его не ранить. Когда герой подходит близко, верёвка рвётся: он падает, секунду приходит в себя и нападает.</div>
    <div class="fgrid"><div><label>Кого</label><select id="hgWho">${hangers.map(e => `<option value="${esc(e.id)}">${esc(e.name?.ru || e.id)}</option>`).join('')}</select></div></div>
    <div id="hgPlace" style="margin-top:8px"></div>`,
    [['→ В игру', async () => {
      const place = getPlace && getPlace();
      if (!place) return toast('Выбери комнату и кликни по полу под верёвкой', 'err');
      sendToGame(async () => ({
        files: { 'tools/rooms/studio_rooms.json': mergeStudioRooms(await repoText('tools/rooms/studio_rooms.json'), { room: place.room, hanger: [who, place.x, place.y] }) },
        title: `Studio: ${who} висит в ${place.room}`,
        body: `Повешен **${who}** в комнате **${place.room}** над полом (${place.x}, ${place.y}): висит, пока герой не подойдёт, потом срывается.`,
        notes: ['Комнаты собирает генератор (tools/rooms/generate_rooms.py); робот студии пересоберёт сцену в этой же отправке.'],
      }));
    }, 'primary'], ['Отмена']]);
}
document.addEventListener('click', e => { if (e.target.closest('[data-act="chars-hang"]')) hangDialog(); });

// A room picker with a map, put inside a dialog that is already open.
// Returns a getter for what was chosen: {room, x, y} or null.
// [param hang]: the spot is a floor he will hang over (drawn with its rope).
function roomPicker(box, enemyId, initial, hang = false) {
  let pick = initial || null;
  const roomOptions = () => `<option value="">— не ставить в комнату —</option>${roomNames().map(n => `<option ${pick?.room === n ? 'selected' : ''}>${n}</option>`).join('')}`;
  box.innerHTML = `<div class="row" style="margin:0"><select class="rp-room" style="width:auto">${roomOptions()}</select>
    <span class="muted rp-info">${pick ? `${pick.room}: ${pick.x}, ${pick.y}` : 'Выбери комнату и кликни по полу, где ему стоять'}</span></div>
    <canvas class="rp-map" style="width:100%;display:none;margin-top:6px;border-radius:6px;cursor:crosshair"></canvas>
    <div class="note">Зелёное — пол, красные — враги, которые уже там стоят. Студия ставит точку на ближайший пол под кликом; дойти до врага игрок должен — это ещё раз проверит генератор комнат.</div>`;
  const sel = box.querySelector('.rp-room'), map = box.querySelector('.rp-map'), info = box.querySelector('.rp-info');
  let room = null;
  const show = async () => {
    room = sel.value ? await loadRoom(sel.value) : null;
    map.style.display = room ? '' : 'none';
    if (room) drawRoomOverview(map, room, pick?.room === sel.value ? pick : null, enemyId);
    if (!room) { pick = null; info.textContent = 'Не ставится в комнату — только тренировочный двор'; }
  };
  sel.onchange = show;
  map.onclick = e => {
    if (!room) return;
    const k = map.clientWidth / room.width, s = snapToSurface(room.surfaces, e.offsetX / k, e.offsetY / k);
    if (!s) { info.textContent = 'Здесь нет пола — кликни выше пола, на который его поставить'; return; }
    pick = { room: sel.value, ...s, hang }; info.textContent = `${pick.room}: ${pick.x}, ${pick.y}`;
    drawRoomOverview(map, room, pick, enemyId);
  };
  // The room list lives with the cutscenes and backgrounds tabs. The enemy
  // wizard opens from the characters tab too, before either has loaded — the
  // list was empty and the enemy could go into no room. Load the order here.
  if (roomNames().length) { if (pick) show(); }
  else loadCutData().then(() => { sel.innerHTML = roomOptions(); if (pick) show(); });
  return () => pick;
}

// A cutscene played by a room: on entry (intro) or once it is cleared (outro).
async function attachCutsceneDialog() {
  if (!CUT) return;
  await loadCutData();
  const now = Object.entries(cutData.played_in || {}).filter(([id]) => id === CUT.id).flatMap(([, rooms]) => rooms);
  const cur = CUT.attach;
  await dialog(`<h3>«${esc(CUT.id)}» — в какой комнате играет</h3>
    <div class="note">Сейчас: ${now.length ? esc(now.join(', ')) : 'ни в какой'}${cur ? ` · после отправки: ${esc(cur.room)} (${cur.when === 'outro_cutscene' ? 'после зачистки' : 'при входе'})` : ''}</div>
    <div class="fgrid">
      <div><label>Комната</label><select id="acRoom"><option value="">— не менять —</option>${roomNames().map(n => `<option ${cur?.room === n ? 'selected' : ''}>${n}</option>`).join('')}</select></div>
      <div><label>Когда</label><select id="acWhen"><option value="intro_cutscene" ${cur?.when !== 'outro_cutscene' ? 'selected' : ''}>при входе в комнату</option><option value="outro_cutscene" ${cur?.when === 'outro_cutscene' ? 'selected' : ''}>после зачистки</option></select></div>
    </div>
    <div class="note" id="acWarn"></div>`,
    [['Готово', d => {
      const room = d.querySelector('#acRoom').value, when = d.querySelector('#acWhen').value;
      CUT.attach = room ? { room, when } : null; saveCut();
      toast(room ? `Будет играть в ${room} — уйдёт с «→ В игру»` : 'Комната не меняется');
    }, 'primary'], ['Отмена']]);
}
document.addEventListener('input', async e => {
  if (e.target.id !== 'acRoom' && e.target.id !== 'acWhen') return;
  const room = document.getElementById('acRoom').value, when = document.getElementById('acWhen').value, warn = document.getElementById('acWarn');
  if (!room || !warn) return;
  const r = await loadRoom(room), had = r?.[when];
  warn.textContent = had && had !== CUT.id ? `Там сейчас играет «${had}» — она будет заменена.` : '';
});
document.addEventListener('click', e => { if (e.target.closest('[data-act="cut-attach"]')) attachCutsceneDialog(); });
