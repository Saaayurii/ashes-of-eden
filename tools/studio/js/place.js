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
  for (const [id, ex, ey] of room.spawns || []) { if (id === enemyId) continue; x.fillStyle = '#e06464'; x.beginPath(); x.arc(ex * k, ey * k, 4, 0, 7); x.fill(); x.fillText(id, ex * k + 6, ey * k - 4); }
  if (spot) { x.fillStyle = '#6aa8ff'; x.beginPath(); x.arc(spot.x * k, spot.y * k, 6, 0, 7); x.fill(); x.fillStyle = '#fff'; x.fillText(enemyId || 'здесь', spot.x * k + 8, spot.y * k - 6); }
}

// A room picker with a map, put inside a dialog that is already open.
// Returns a getter for what was chosen: {room, x, y} or null.
function roomPicker(box, enemyId, initial) {
  let pick = initial || null;
  box.innerHTML = `<div class="row" style="margin:0"><select class="rp-room" style="width:auto"><option value="">— не ставить в комнату —</option>${roomNames().map(n => `<option ${pick?.room === n ? 'selected' : ''}>${n}</option>`).join('')}</select>
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
    pick = { room: sel.value, ...s }; info.textContent = `${pick.room}: ${pick.x}, ${pick.y}`;
    drawRoomOverview(map, room, pick, enemyId);
  };
  if (pick) show();
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
