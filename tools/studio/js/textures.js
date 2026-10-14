/* Sprite Studio — «Текстуры»: the room's pictures by hand. Every picture the generator laid (decor, terrain pieces,
 * cornices, the front plane) can be moved, stretched, turned, mirrored, tinted, swapped or hidden — a `retouch` of
 * its node — and any picture of the game's, or one of her own, can be laid anywhere on four layers — her `textures`.
 * Both are kept in tools/rooms/studio_rooms.json and laid over the scene by tools/rooms/studio_textures.py each time
 * the room is generated: txProblems mirrors its validate(), the drawing mirrors its Sprite2D properties. Change one,
 * change the other. import/rooms/room_<name>.bg.json (build_data.py room_project) carries each node as the scene has it. */
'use strict';

const TX_LAYERS = { back: 'за террасами', mid: 'с декором', front: 'перед ногами', top: 'поверх всего' };
const TX_LAYER_Z = { back: 0, mid: 0, front: 1, top: 3 };
const TX_BLENDS = { mix: 'обычное', add: 'свечение (add)', sub: 'вычитание', mul: 'умножение' };
const TX_FILTERS = { '': 'как в проекте (пиксели)', pixel: 'пиксели', smooth: 'сглаживание' };
const TX_REPEATS = { '': 'нет', tile: 'плиткой', mirror: 'зеркально' };
const TX_TEXTURE = /^(decor|levels|backgrounds|environment|cutscenes|props)\/[A-Za-z0-9_][A-Za-z0-9_./-]*\.png$/;
const TX_KEYS = ['tex', 'at', 'scale', 'rot', 'flip_h', 'flip_v', 'layer', 'z', 'tint', 'alpha', 'blend', 'region', 'repeat', 'filter', 'name'];
const TX_RETOUCH_KEYS = [...TX_KEYS.filter(k => k !== 'layer' && k !== 'name'), 'was', 'hidden'];
const TX_MAX = 200, TX_SCALE = [0.02, 40];
// where a scene's own layer stands in the tree (studio_textures.apply puts hers among them)
const TX_RANK = { Painting: 0, DepthWindows: 1, Sprites: 2, FogFar: 3, DecorBack: 3, back: 4, Terrain: 5, DecorMid: 6, DecorFront: 7, mid: 6.5, front: 8, Front: 9, top: 10 };

/* ---------- pure helpers (tests/textures.test.js) ---------- */
const txNum = v => typeof v === 'number' && isFinite(v);
// studio_textures._problems: one entry, as sentences; `exists(tex)` false is a picture that is not there
function txEntryProblems(where, t, retouch, exists) {
  const out = [], keys = retouch ? TX_RETOUCH_KEYS : TX_KEYS;
  for (const k of Object.keys(t)) if (!keys.includes(k)) out.push(`${where}: лишний ключ ${k}`);
  for (const k of ['tex', 'was']) if (k in t) {
    if (typeof t[k] !== 'string' || !TX_TEXTURE.test(t[k]) || t[k].includes('..')) out.push(`${where}: ${k} — .png из assets/ (decor, levels, backgrounds, environment, cutscenes, props)`);
    else if (k === 'tex' && exists && !exists(t[k])) out.push(`${where}: нет картинки assets/${t[k]}`);
  }
  if (!retouch && !('tex' in t)) out.push(`${where}: нет картинки (tex)`);
  if (!retouch && !('at' in t)) out.push(`${where}: нет места (at)`);
  if ('at' in t && !(Array.isArray(t.at) && t.at.length === 2 && t.at.every(v => txNum(v) && Math.abs(v) <= 100000))) out.push(`${where}: at — [x, y]`);
  if ('scale' in t && !(Array.isArray(t.scale) && t.scale.length === 2 && t.scale.every(v => txNum(v) && v >= TX_SCALE[0] && v <= TX_SCALE[1]))) out.push(`${where}: scale — [sx, sy], каждый ${TX_SCALE[0]}…${TX_SCALE[1]}`);
  if ('rot' in t && !(txNum(t.rot) && Math.abs(t.rot) <= 360)) out.push(`${where}: rot — градусы, −360…360`);
  for (const k of ['flip_h', 'flip_v', 'hidden']) if (k in t && typeof t[k] !== 'boolean') out.push(`${where}: ${k} — да или нет`);
  if ('layer' in t && !(t.layer in TX_LAYERS)) out.push(`${where}: layer — ${Object.keys(TX_LAYERS).join(', ')}`);
  if ('z' in t && !(Number.isInteger(t.z) && Math.abs(t.z) <= 10)) out.push(`${where}: z — целое, −10…10`);
  if ('tint' in t && !/^#[0-9a-fA-F]{6}$/.test(String(t.tint))) out.push(`${where}: tint — #rrggbb`);
  if ('alpha' in t && !(txNum(t.alpha) && t.alpha >= 0 && t.alpha <= 1)) out.push(`${where}: alpha — 0…1`);
  if ('blend' in t && !(t.blend in TX_BLENDS)) out.push(`${where}: blend — ${Object.keys(TX_BLENDS).join(', ')}`);
  if ('region' in t && !(Array.isArray(t.region) && t.region.length === 4 && t.region.every(txNum) && t.region[2] > 0 && t.region[3] > 0 && Math.max(...t.region.map(Math.abs)) <= 16384)) out.push(`${where}: region — [x, y, w, h] в пикселях картинки`);
  if ('repeat' in t && !['tile', 'mirror'].includes(t.repeat)) out.push(`${where}: repeat — tile или mirror`);
  if ('filter' in t && !['pixel', 'smooth'].includes(t.filter)) out.push(`${where}: filter — pixel или smooth`);
  if ('name' in t && typeof t.name !== 'string') out.push(`${where}: name — текст`);
  return out;
}
// studio_textures.validate: a room's `textures` and `retouch`
function txProblems(room, entry, exists) {
  const out = [], textures = entry?.textures ?? [], retouch = entry?.retouch ?? {};
  if (!Array.isArray(textures)) out.push(`${room}: textures — список`);
  else {
    if (textures.length > TX_MAX) out.push(`${room}: не больше ${TX_MAX} текстур в комнате`);
    textures.forEach((t, i) => out.push(...(t && typeof t === 'object' && !Array.isArray(t) ? txEntryProblems(`${room}: текстура ${i + 1}`, t, false, exists) : [`${room}: текстура ${i + 1} — объект`])));
  }
  if (!retouch || typeof retouch !== 'object' || Array.isArray(retouch)) out.push(`${room}: retouch — путь узла → правка`);
  else for (const [path, t] of Object.entries(retouch)) {
    if (!/^([A-Za-z0-9_]+\/)*[A-Za-z0-9_]+$/.test(path)) out.push(`${room}: ${path} — не путь узла`);
    out.push(...(t && typeof t === 'object' && !Array.isArray(t) ? txEntryProblems(`${room}: правка ${path}`, t, true, exists) : [`${room}: правка ${path} — объект`]));
  }
  return out;
}
const txRad = d => d * Math.PI / 180;
// a local pixel of the sprite → the room: Godot's position · rotation · scale (a flip is a negative scale here)
function txMatrix(o) {
  const c = Math.cos(txRad(o.rot || 0)), s = Math.sin(txRad(o.rot || 0));
  const ex = o.scale[0] * (o.flip_h ? -1 : 1), ey = o.scale[1] * (o.flip_v ? -1 : 1);
  return [c * ex, s * ex, -s * ey, c * ey, o.at[0], o.at[1]];
}
const txApply = (m, x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
function txInverse(m, x, y) {
  const det = m[0] * m[3] - m[1] * m[2], dx = x - m[4], dy = y - m[5];
  return [(m[3] * dx - m[2] * dy) / det, (-m[1] * dx + m[0] * dy) / det];
}
// the sprite's own rectangle before it is scaled: [ox, oy, w, h] (the crop's size, centred unless it is not)
function txBox(o, imgW, imgH) {
  const w = o.region ? o.region[2] : imgW, h = o.region ? o.region[3] : imgH;
  return o.centered === false ? [0, 0, w, h] : [-w / 2, -h / 2, w, h];
}
const TX_HANDLES = { nw: [0, 0], n: [0.5, 0], ne: [1, 0], e: [1, 0.5], se: [1, 1], s: [0.5, 1], sw: [0, 1], w: [0, 0.5] };
// A handle dragged to P: the opposite one stays where it was. `how` 'scale' stretches the picture, 'region' grows the
// crop (a tiled picture gets more tiles, not bigger ones); `uniform` keeps the proportions. → {at, scale} or {at, region}
function txResize(o, box, handle, P, how = 'scale', uniform = false, imgW = box[2], imgH = box[3]) {
  const [fx, fy] = TX_HANDLES[handle], ax = 1 - fx, ay = 1 - fy;
  const lx = f => box[0] + f * box[2], ly = f => box[1] + f * box[3];
  const m = txMatrix(o), A = txApply(m, lx(ax), ly(ay));
  const c = Math.cos(txRad(o.rot || 0)), s = Math.sin(txRad(o.rot || 0)), px = P[0] - A[0], py = P[1] - A[1];
  const d = [c * px + s * py, -s * px + c * py];              // anchor → pointer, in the sprite's own turn
  const ex0 = o.scale[0] * (o.flip_h ? -1 : 1), ey0 = o.scale[1] * (o.flip_v ? -1 : 1);
  const spanX = (fx - ax) * box[2], spanY = (fy - ay) * box[3];  // anchor → handle, unscaled
  let kx = spanX ? d[0] / (ex0 * spanX) : 1, ky = spanY ? d[1] / (ey0 * spanY) : 1;  // how much longer each way
  if (uniform) {
    const vx = ex0 * spanX, vy = ey0 * spanY, k = (d[0] * vx + d[1] * vy) / (vx * vx + vy * vy || 1);
    kx = ky = k;
  }
  if (how === 'region') {
    const r = o.region ? [...o.region] : [0, 0, imgW, imgH];
    r[2] = Math.max(1, Math.round(r[2] * kx)); r[3] = Math.max(1, Math.round(r[3] * ky));
    const nb = txBox({ ...o, region: r }, imgW, imgH), na = [nb[0] + ax * nb[2], nb[1] + ay * nb[3]];
    return { at: txPlace(A, o.rot, ex0, ey0, na), region: r };
  }
  const lo = TX_SCALE[0], hi = TX_SCALE[1], clamp = v => Math.min(hi, Math.max(lo, v));
  const sx = clamp(o.scale[0] * kx), sy = clamp(o.scale[1] * ky);
  const ex = sx * (o.flip_h ? -1 : 1), ey = sy * (o.flip_v ? -1 : 1);
  return { at: txPlace(A, o.rot, ex, ey, [lx(ax), ly(ay)]), scale: [sx, sy] };
}
// where the origin goes so that a local point lands on A
function txPlace(A, rot, ex, ey, local) {
  const c = Math.cos(txRad(rot || 0)), s = Math.sin(txRad(rot || 0)), x = local[0] * ex, y = local[1] * ey;
  return [A[0] - (c * x - s * y), A[1] - (s * x + c * y)];
}
const txSame = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
const txRound = (v, d = 2) => Math.round(v * 10 ** d) / 10 ** d;
// A generated node's edit as the file keeps it: only what differs from the scene (a key already in the game stays, the
// scene shows its result), tint and alpha together (they replace the modulate whole), `was` what the generator laid.
function txRetouch(base, eff, committed) {
  const out = { was: committed?.was ?? base.tex }, keep = k => committed && k in committed;
  for (const k of ['tex', 'at', 'scale', 'rot', 'flip_h', 'flip_v', 'z', 'blend', 'region', 'repeat', 'filter', 'hidden'])
    if (eff[k] !== undefined && eff[k] !== null && eff[k] !== '' && (!txSame(eff[k], base[k]) || keep(k))) out[k] = eff[k];
  if (!txSame(eff.tint, base.tint) || !txSame(eff.alpha, base.alpha) || keep('tint') || keep('alpha')) { out.tint = eff.tint; out.alpha = eff.alpha; }
  return Object.keys(out).length > 1 ? out : null;
}
// her own picture as the file keeps it: what is not the default
function txTexture(o) {
  const out = { tex: o.tex, at: o.at.map(v => txRound(v)) };
  if (o.name) out.name = o.name;
  if (o.scale[0] !== 1 || o.scale[1] !== 1) out.scale = o.scale.map(v => txRound(v, 4));
  if (o.rot) out.rot = txRound(o.rot);
  if (o.flip_h) out.flip_h = true;
  if (o.flip_v) out.flip_v = true;
  if ((o.layer || 'mid') !== 'mid') out.layer = o.layer;
  if (o.z) out.z = o.z;
  if ((o.tint || '#ffffff').toLowerCase() !== '#ffffff') out.tint = o.tint.toLowerCase();
  if ((o.alpha ?? 1) !== 1) out.alpha = txRound(o.alpha, 3);
  if ((o.blend || 'mix') !== 'mix') out.blend = o.blend;
  if (o.region) out.region = o.region.map(v => Math.round(v));
  if (o.repeat) out.repeat = o.repeat;
  if (o.filter) out.filter = o.filter;
  return out;
}
if (typeof module !== 'undefined') module.exports = { txProblems, txEntryProblems, txMatrix, txApply, txInverse, txBox, txResize, txRetouch, txTexture, TX_HANDLES };

/* ---------- the tab ---------- */
const TX = { room: null, sel: null, view: null, drag: null, live: null, how: 'scale', lockPainting: true, showHidden: false, floors: false,
  q: '', lib: null, uploads: {}, images: new Map(), tinted: new Map(), space: false };
if (typeof window !== 'undefined') try { TX.uploads = JSON.parse(localStorage.getItem('ss_tx_uploads') || '{}'); } catch {}
const txSaveUploads = () => { try { localStorage.setItem('ss_tx_uploads', JSON.stringify(TX.uploads)); } catch { toast('Картинка не влезла в память браузера — отправь её поскорее', 'err'); } };
const txEntry = (room = TX.room?.name) => gdDoc(GD_ROOMS)?.[room] || {};
const txCommitted = (room = TX.room?.name) => WORLD.data.files[GD_ROOMS]?.[room] || {};
function txEdit(fn, room = TX.room.name) {
  const doc = structuredClone(gdDoc(GD_ROOMS) || {}), r = doc[room] ||= {};
  r.textures ||= []; r.retouch ||= {};
  fn(r);
  if (!r.textures.length) delete r.textures;
  if (!Object.keys(r.retouch).length) delete r.retouch;
  if (!Object.keys(r).length) delete doc[room];
  gdPut(GD_ROOMS, doc);
}
const txHex = c => '#' + c.slice(0, 3).map(v => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, '0')).join('');
const txFilterOf = n => n === 1 ? 'pixel' : n === 2 ? 'smooth' : '';
// the scene's own sprite, as it is, and the same with her edit on it
function txBase(it, layer) {
  const n = it.node;
  return { tex: n.tex, at: [...n.pos], scale: [Math.abs(it.sx), Math.abs(it.sy)], rot: n.rot, flip_h: it.flipH !== (it.sx < 0), flip_v: n.flipV !== (it.sy < 0),
    centered: n.centered, region: n.region, tint: txHex(it.modulate), alpha: txRound(it.modulate[3] ?? 1, 3), blend: n.blend, repeat: ['', '', 'tile', 'mirror'][n.repeat] || '',
    filter: txFilterOf(it.filter), z: n.z, hidden: !n.visible, layerName: layer.name, layerZ: layer.z || 0, name: it.name };
}
// everything the canvas shows, in drawing order: {key, gen, path | i, base?, …the effective properties}
function txObjects() {
  const room = TX.room, entry = txEntry(), retouch = entry.retouch || {}, out = [];
  let order = 0;
  for (const l of room.layers) {
    if (l.studio) continue;  // her pictures as the scene has them: drawn from the draft instead
    for (const it of l.items) {
      if (it.kind !== 'sprite' || !it.node) continue;
      const base = txBase(it, l), edit = retouch[it.node.path] || {};
      const o = { ...base, ...edit, key: 'n:' + it.node.path, gen: true, path: it.node.path, base, edited: !!retouch[it.node.path], order: order++ };
      if (TX.live?.key === o.key) Object.assign(o, TX.live.patch);
      o.zz = o.layerZ + (o.z || 0); o.rank = TX_RANK[l.name] ?? 5;
      out.push(o);
    }
  }
  (entry.textures || []).forEach((t, i) => {
    const o = { scale: [1, 1], rot: 0, flip_h: false, flip_v: false, layer: 'mid', z: 0, tint: '#ffffff', alpha: 1, blend: 'mix', region: null, repeat: '', filter: '', centered: true,
      ...t, key: 't:' + i, gen: false, i, order: order++ };
    if (TX.live?.key === o.key) Object.assign(o, TX.live.patch);
    o.zz = TX_LAYER_Z[o.layer] + (o.z || 0); o.rank = TX_RANK[o.layer];
    out.push(o);
  });
  return out.sort((a, b) => a.zz - b.zz || a.rank - b.rank || a.order - b.order);
}
const txUrl = tex => TX.uploads[tex] || A('assets/' + tex);
function txImage(tex) {
  const url = txUrl(tex);
  if (!TX.images.has(url)) { TX.images.set(url, null); loadImage(url).then(im => { TX.images.set(url, im); txDraw(); }).catch(() => TX.images.set(url, false)); }
  return TX.images.get(url);
}
// the picture multiplied by a tint, as modulate does, cached per picture and colour
function txTinted(im, tint) {
  if (!tint || tint.toLowerCase() === '#ffffff') return im;
  const k = im.src + tint;
  if (!TX.tinted.has(k)) {
    const c = mk(im.naturalWidth, im.naturalHeight), x = c.getContext('2d');
    x.drawImage(im, 0, 0); x.globalCompositeOperation = 'multiply'; x.fillStyle = tint; x.fillRect(0, 0, c.width, c.height);
    x.globalCompositeOperation = 'destination-in'; x.drawImage(im, 0, 0);
    TX.tinted.set(k, c);
  }
  return TX.tinted.get(k);
}
const TX_COMPOSITE = { mix: 'source-over', add: 'lighter', sub: 'difference', mul: 'multiply' };
function txDrawOne(x, o, im) {
  const w = im.naturalWidth, h = im.naturalHeight, box = txBox(o, w, h), m = txMatrix(o), src = txTinted(im, o.tint);
  x.save();
  x.transform(...m);
  x.globalAlpha = o.hidden ? 0.25 : o.alpha ?? 1;
  x.globalCompositeOperation = TX_COMPOSITE[o.blend] || 'source-over';
  x.imageSmoothingEnabled = o.filter === 'smooth';
  const r = o.region || [0, 0, w, h];
  if (o.repeat || r[0] < 0 || r[1] < 0 || r[0] + r[2] > w || r[1] + r[3] > h) {
    // a crop larger than the picture: tiled when it repeats, transparent past the edge when it does not
    if (o.repeat) {
      const pat = x.createPattern(src, 'repeat'); pat.setTransform(new DOMMatrix([1, 0, 0, 1, box[0] - r[0], box[1] - r[1]]));
      x.fillStyle = pat; x.fillRect(box[0], box[1], box[2], box[3]);
    } else {
      x.beginPath(); x.rect(box[0], box[1], box[2], box[3]); x.clip(); x.drawImage(src, box[0] - r[0], box[1] - r[1]);
    }
  } else x.drawImage(src, r[0], r[1], r[2], r[3], box[0], box[1], box[2], box[3]);
  x.restore();
}
function txView(c) {
  const W = c.clientWidth || 800, H = c.clientHeight || 450;
  if (c.width !== W || c.height !== H) { c.width = W; c.height = H; }
  if (!TX.view || TX.view.room !== TX.room.name) {
    const k = Math.min(W / TX.room.width, H / TX.room.height);
    TX.view = { room: TX.room.name, k, ox: (W - TX.room.width * k) / 2, oy: (H - TX.room.height * k) / 2 };
  }
  return TX.view;
}
const txToRoom = (e, c) => { const r = c.getBoundingClientRect(), v = TX.view; return [(e.clientX - r.left - v.ox) / v.k, (e.clientY - r.top - v.oy) / v.k]; };
function txCorners(o) {
  const im = txImage(o.tex); if (!im) return null;
  const box = txBox(o, im.naturalWidth, im.naturalHeight), m = txMatrix(o);
  return { box, im, m, at: (fx, fy) => txApply(m, box[0] + fx * box[2], box[1] + fy * box[3]) };
}
function txDraw() {
  const c = $('#txCanvas'); if (!c || !TX.room || mode !== 'tex') return;
  const v = txView(c), x = c.getContext('2d');
  x.setTransform(1, 0, 0, 1, 0, 0); x.fillStyle = '#111'; x.fillRect(0, 0, c.width, c.height);
  x.setTransform(v.k, 0, 0, v.k, v.ox, v.oy);
  x.fillStyle = '#000'; x.fillRect(0, 0, TX.room.width, TX.room.height);
  const objs = txObjects();
  for (const o of objs) {
    if (o.hidden && !TX.showHidden) continue;
    const im = txImage(o.tex); if (im) txDrawOne(x, o, im);
  }
  if (TX.floors) { x.fillStyle = 'rgba(124,195,107,.9)'; for (const [sx, sy, sw] of TX.room.surfaces || []) x.fillRect(sx, sy - 1 / v.k, sw, 2 / v.k); }
  x.setTransform(1, 0, 0, 1, 0, 0);
  const scr = p => [p[0] * v.k + v.ox, p[1] * v.k + v.oy];
  // her own pictures and the edited ones, outlined thinly so they can be found
  for (const o of objs) {
    if (o.key === TX.sel || !(o.edited || !o.gen)) continue;
    const q = txCorners(o); if (!q) continue;
    x.strokeStyle = o.gen ? 'rgba(106,168,255,.55)' : 'rgba(255,215,95,.55)'; x.setLineDash([4, 3]); x.lineWidth = 1;
    x.beginPath(); for (const [fx, fy] of [[0, 0], [1, 0], [1, 1], [0, 1]]) x.lineTo(...scr(q.at(fx, fy))); x.closePath(); x.stroke();
  }
  x.setLineDash([]);
  const o = objs.find(o => o.key === TX.sel), q = o && txCorners(o);
  if (q) {
    x.strokeStyle = '#ffd75f'; x.lineWidth = 1.5;
    x.beginPath(); for (const [fx, fy] of [[0, 0], [1, 0], [1, 1], [0, 1]]) x.lineTo(...scr(q.at(fx, fy))); x.closePath(); x.stroke();
    for (const [, [fx, fy]] of Object.entries(TX_HANDLES)) { const [hx, hy] = scr(q.at(fx, fy)); x.fillStyle = '#ffd75f'; x.fillRect(hx - 4, hy - 4, 8, 8); x.strokeStyle = '#000'; x.strokeRect(hx - 4, hy - 4, 8, 8); }
    const [rx, ry] = txRotHandle(q, scr);
    const [tx, ty] = scr(q.at(0.5, 0)); x.strokeStyle = '#ffd75f'; x.beginPath(); x.moveTo(tx, ty); x.lineTo(rx, ry); x.stroke();
    x.fillStyle = '#ffd75f'; x.beginPath(); x.arc(rx, ry, 5, 0, 7); x.fill();
    const [ox, oy] = scr(o.at); x.strokeStyle = '#fff'; x.beginPath(); x.moveTo(ox - 5, oy); x.lineTo(ox + 5, oy); x.moveTo(ox, oy - 5); x.lineTo(ox, oy + 5); x.stroke();
  }
  $('#txZoom') && ($('#txZoom').textContent = Math.round(v.k * 100) + '%');
}
// the turning knob: 24 px out from the top edge's middle, away from the centre
function txRotHandle(q, scr) {
  const [tx, ty] = scr(q.at(0.5, 0)), [cx, cy] = scr(q.at(0.5, 0.5)), len = Math.hypot(tx - cx, ty - cy) || 1;
  return [tx + (tx - cx) / len * 24, ty + (ty - cy) / len * 24];
}
function txHit(P) {
  const objs = txObjects().reverse();
  for (const o of objs) {
    if (o.hidden && !TX.showHidden) continue;
    if (TX.lockPainting && o.gen && (o.layerName === 'Painting' || o.layerName === 'Sprites')) continue;
    const q = txCorners(o); if (!q) continue;
    const [lx, ly] = txInverse(q.m, P[0], P[1]);
    if (lx >= q.box[0] && lx <= q.box[0] + q.box[2] && ly >= q.box[1] && ly <= q.box[1] + q.box[3]) return o;
  }
  return null;
}
function txHandleAt(e, c) {
  const o = txSelected(), q = o && txCorners(o); if (!q) return null;
  const r = c.getBoundingClientRect(), v = TX.view, sx = e.clientX - r.left, sy = e.clientY - r.top, scr = p => [p[0] * v.k + v.ox, p[1] * v.k + v.oy];
  const [rx, ry] = txRotHandle(q, scr); if (Math.hypot(sx - rx, sy - ry) < 8) return 'rot';
  for (const [h, [fx, fy]] of Object.entries(TX_HANDLES)) { const [hx, hy] = scr(q.at(fx, fy)); if (Math.abs(sx - hx) < 7 && Math.abs(sy - hy) < 7) return h; }
  return null;
}
const txSelected = () => TX.sel && txObjects().find(o => o.key === TX.sel);
// one picture changed: hers in place, a generated one as a retouch against what the scene has
function txSet(o, patch) {
  txEdit(r => {
    if (o.gen) {
      const eff = { ...o.base, ...(r.retouch[o.path] || {}), ...patch }, next = txRetouch(o.base, eff, txCommitted().retouch?.[o.path]);
      if (next) r.retouch[o.path] = next; else delete r.retouch[o.path];
    } else {
      const cur = { scale: [1, 1], rot: 0, layer: 'mid', z: 0, tint: '#ffffff', alpha: 1, blend: 'mix', region: null, repeat: '', filter: '', ...r.textures[o.i], ...patch };
      r.textures[o.i] = txTexture(cur);
    }
  });
}
function txAdd(tex, at, extra = {}) {
  const n = (txEntry().textures || []).length;
  if (n >= TX_MAX) return toast(`Не больше ${TX_MAX} текстур в комнате`, 'err');
  txEdit(r => r.textures.push(txTexture({ scale: [1, 1], rot: 0, ...extra, tex, at })));
  TX.sel = 't:' + n; renderTex();
}
function txViewCentre() { const c = $('#txCanvas'), v = TX.view; return [Math.round((c.width / 2 - v.ox) / v.k), Math.round((c.height / 2 - v.oy) / v.k)]; }
function txDuplicate() {
  const o = txSelected(); if (!o) return;
  const copy = { ...o, at: [o.at[0] + 16, o.at[1] + 16], layer: o.gen ? (o.layerZ >= 3 ? 'top' : o.layerZ >= 1 ? 'front' : o.layerName === 'Terrain' ? 'back' : 'mid') : o.layer, z: o.gen ? 0 : o.z };
  if (o.gen && o.centered === false) {  // hers are centred: the same place, measured from the middle
    const im = txImage(o.tex), box = txBox(o, im.naturalWidth, im.naturalHeight), m = txMatrix(o);
    copy.at = txApply(m, box[2] / 2, box[3] / 2).map(v => v + 16);
  }
  txAdd(o.tex, copy.at.map(v => txRound(v)), copy);
}
function txDelete() {
  const o = txSelected(); if (!o) return;
  if (o.gen) { txSet(o, { hidden: !o.hidden }); return renderTex(); }
  txEdit(r => r.textures.splice(o.i, 1)); TX.sel = null; renderTex();
}
function txReset() {
  const o = txSelected(); if (!o) return;
  if (o.gen) txEdit(r => { delete r.retouch[o.path]; });
  else txEdit(r => { r.textures[o.i] = txTexture({ scale: [1, 1], rot: 0, tex: o.tex, at: o.at, layer: o.layer }); });
  renderTex();
}
// what is wrong with the room's edits now: a node the generator no longer lays, a different picture there
function txStale() {
  const nodes = new Map(TX.room.layers.flatMap(l => l.items.filter(it => it.node).map(it => [it.node.path, it])));
  const out = [];
  for (const [path, e] of Object.entries(txEntry().retouch || {})) {
    const it = nodes.get(path);
    if (!it) out.push([path, 'такого узла в комнате больше нет — правка не ляжет']);
    else if (e.was && e.was !== it.node.tex && !txCommitted().retouch?.[path]?.tex) out.push([path, `генератор кладёт туда ${it.node.tex}, а не ${e.was} — правка не ляжет`]);
  }
  return out;
}
const txExists = tex => !!TX.uploads[tex] || tex.startsWith('props/') || TX.known?.has(tex);
async function txLibrary() {
  if (TX.lib) return TX.lib;
  try { TX.lib = (await (await fetch('import/library.json')).json()).map(e => ({ ...e, tex: e.res.replace(/^res:\/\/assets\//, '') })); }
  catch { TX.lib = []; }
  return TX.lib;
}
async function renderTex() {
  await loadCutData();
  const names = roomNames(), name = TX.room && names.includes(TX.room.name) ? TX.room.name : GD.sel.room && names.includes(GD.sel.room) ? GD.sel.room : names[0];
  if (TX.room?.name !== name) { TX.room = await loadRoom(name); TX.sel = null; }
  const lib = await txLibrary();
  TX.known = new Set([...lib.map(e => e.tex), ...Object.keys(TX.room?.images || {}).map(r => r.replace(/^res:\/\/assets\//, '')),
    ...Object.values(WORLD.data.files[GD_ROOMS] || {}).flatMap(r => (r.textures || []).map(t => t.tex))]);
  const side = $('#gdSide_tex'); if (!side) return;
  if (!TX.room) { side.innerHTML = `<div class="warn">Нет данных комнаты ${esc(name)} (import/rooms). Запусти tools/studio/build_data.py --rooms.</div>`; return; }
  const o = txSelected(), entry = txEntry(), stale = txStale();
  const num = (f, v, step = 1, extra = '') => `<label>${f[1]}<input type="number" step="${step}" data-tx="${f[0]}" value="${txRound(v, 3)}"${extra}></label>`;
  const opts = (map, cur) => Object.entries(map).map(([k, l]) => `<option value="${k}"${k === (cur || '') ? ' selected' : ''}>${esc(l)}</option>`).join('');
  const props = !o ? '<div class="muted">Кликни по картинке в комнате, чтобы её взять. Перетаскивай — двигать, квадраты по краям — растягивать (Shift — в пропорции), кружок сверху — вращать (Shift — по 15°). Колесо — масштаб, пробел или средняя кнопка — двигать вид.</div>' : `
    <div><b>${esc(o.gen ? o.path : o.name || 'текстура ' + (o.i + 1))}</b> ${o.gen ? `<span class="badge">${o.edited ? 'правка генерированной' : 'из генератора'}</span>` : '<span class="badge new">твоя</span>'}</div>
    <div class="muted" style="word-break:break-all">${esc(o.tex)}${o.gen && o.tex !== o.base.tex ? ` (была ${esc(o.base.tex)})` : ''}</div>
    ${o.gen ? '' : `<label>Имя<input data-tx="name" value="${esc(o.name || '')}" placeholder="для себя"></label>`}
    <div class="gdfields">${num(['x', 'X'], o.at[0])}${num(['y', 'Y'], o.at[1])}${num(['sx', 'Растянуть по X'], o.scale[0], 0.05)}${num(['sy', 'по Y'], o.scale[1], 0.05)}
      ${num(['rot', 'Поворот, °'], o.rot || 0, 1)}${num(['z', 'Z внутри слоя'], o.z || 0, 1, ' min="-10" max="10"')}</div>
    <div class="gdchips"><label><input type="checkbox" data-tx="flip_h"${o.flip_h ? ' checked' : ''}>отразить ↔</label><label><input type="checkbox" data-tx="flip_v"${o.flip_v ? ' checked' : ''}>отразить ↕</label>
      ${o.gen ? `<label><input type="checkbox" data-tx="hidden"${o.hidden ? ' checked' : ''}>спрятать</label>` : ''}</div>
    <div class="gdfields">
      ${o.gen ? '' : `<label>Слой<select data-tx="layer">${opts(TX_LAYERS, o.layer)}</select></label>`}
      <label>Цвет<input type="color" data-tx="tint" value="${esc(o.tint || '#ffffff')}"></label>
      <label>Непрозрачность<input type="range" min="0" max="1" step="0.01" data-tx="alpha" value="${o.alpha ?? 1}"></label>
      <label>Смешение<select data-tx="blend">${opts(TX_BLENDS, o.blend)}</select></label>
      <label>Фильтр<select data-tx="filter">${opts(TX_FILTERS, o.filter)}</select></label>
      <label>Повтор<select data-tx="repeat">${opts(TX_REPEATS, o.repeat)}</select></label></div>
    <div class="gdfields">${['rx', 'ry', 'rw', 'rh'].map((k, i) => `<label>${['Кроп x', 'y', 'ширина', 'высота'][i]}<input type="number" data-tx="${k}" value="${o.region ? o.region[i] : ''}" placeholder="${i < 2 ? 0 : 'вся'}"></label>`).join('')}</div>
    <div class="muted">Кроп — кусок картинки. Шире самой картинки и с повтором «плиткой» — замостит полосу (ручки в режиме «Область» наращивают её).</div>
    <div class="row" style="flex-wrap:wrap;gap:4px">
      <button class="sm" data-tx-act="dup" title="Ctrl+D">⧉ Копия</button>
      <button class="sm" data-tx-act="del" title="Delete">${o.gen ? (o.hidden ? '👁 Показать' : '🚫 Спрятать') : '✕ Убрать'}</button>
      <button class="sm" data-tx-act="reset">↺ Сбросить</button>
      <button class="sm" data-tx-act="swap" title="Выбери картинку в библиотеке ниже">⇄ Заменить картинку</button>
      ${o.gen ? '' : '<button class="sm" data-tx-act="up">▲ Выше</button><button class="sm" data-tx-act="down">▼ Ниже</button>'}</div>
    ${o.gen && txCommitted().retouch?.[o.path] && !entry.retouch?.[o.path] ? '<div class="muted">Правка снята: генератор вернёт своё после отправки (на холсте — пока как в игре).</div>' : ''}`;
  const q = TX.q.trim().toLowerCase(), libItems = lib.filter(e => !q || e.tex.toLowerCase().includes(q)).slice(0, 120);
  const ups = Object.keys(TX.uploads);
  side.innerHTML = `<label>Комната<select id="txRoom">${names.map(n => `<option${n === name ? ' selected' : ''}>${esc(n)}</option>`).join('')}</select></label>
    <div class="card"><b>Взятое</b>${props}</div>
    <div class="card"><b>Картинки</b> <span class="muted">клик — положить в центр вида${o ? ' (или заменить, если нажата ⇄)' : ''}</span>
      <div class="row" style="gap:4px;margin:4px 0"><input id="txQ" placeholder="поиск: grave, lantern, ruin…" value="${esc(TX.q)}"><button class="sm" data-tx-act="upload" title="PNG с компьютера → assets/decor/studio/">⇪ Свой PNG</button></div>
      <div class="gdlist txlib">${[...ups.map(tex => ({ tex, url: TX.uploads[tex], mine: true })), ...libItems].map(e => `<button class="txthumb${TX.swap ? ' swap' : ''}" data-tx-tex="${esc(e.tex)}" title="${esc(e.tex)}${e.w ? ` · ${e.w}×${e.h}` : ''}"><img loading="lazy" src="${esc(e.mine ? e.url : A(e.url))}"><span>${esc(e.tex.split('/').pop().replace(/\.png$/, ''))}</span></button>`).join('')}</div>
      ${lib.length ? '' : '<div class="warn">Библиотеки нет (import/library.json): запусти build_data.py --rooms.</div>'}</div>
    <div class="card"><b>Правки комнаты</b>
      ${(entry.textures || []).map((t, i) => `<div class="row txrow${TX.sel === 't:' + i ? ' on' : ''}" data-tx-pick="t:${i}"><span class="grow">◆ ${esc(t.name || t.tex.split('/').pop())} <span class="muted">${esc(TX_LAYERS[t.layer || 'mid'])}</span></span></div>`).join('')}
      ${Object.keys(entry.retouch || {}).map(p => `<div class="row txrow${TX.sel === 'n:' + p ? ' on' : ''}" data-tx-pick="n:${esc(p)}"><span class="grow">◇ ${esc(p)}${entry.retouch[p].hidden ? ' <span class="muted">спрятан</span>' : ''}</span></div>`).join('')}
      ${!(entry.textures || []).length && !Object.keys(entry.retouch || {}).length ? '<div class="muted">пока нет</div>' : ''}
      ${stale.map(([p, why]) => `<div class="warn">${esc(p)}: ${esc(why)}</div>`).join('')}</div>`;
  $('#gdBar_tex').innerHTML = `<span class="gdchips"><label title="Картину и шов не взять кликом — чтобы не сдвинуть фон случайно"><input type="checkbox" id="txLock"${TX.lockPainting ? ' checked' : ''}>картина заперта</label>
      <label><input type="checkbox" id="txHidden"${TX.showHidden ? ' checked' : ''}>показать спрятанное</label><label><input type="checkbox" id="txFloors"${TX.floors ? ' checked' : ''}>полы</label>
      <label title="Что делают ручки по краям">ручки: <select id="txHow"><option value="scale"${TX.how === 'scale' ? ' selected' : ''}>растягивают</option><option value="region"${TX.how === 'region' ? ' selected' : ''}>наращивают область</option></select></label></span>
    <span id="txZoom" class="muted"></span><button class="sm" data-tx-act="fit" title="Вся комната">⤢</button>
    <button class="sm" data-tx-act="run" title="Открыть комнату в Godot (локальная студия; сначала → В игру)">▶ В Godot</button>` + gdBar('tex');
  txDraw();
}
function txInput(e) {
  const el = e.target;
  if (el.id === 'txRoom' && e.type === 'change') { GD.sel.room = el.value; loadRoom(el.value).then(r => { TX.room = r; TX.sel = null; renderTex(); }); return true; }
  if (el.id === 'txQ') { TX.q = el.value; clearTimeout(txInput.t); txInput.t = setTimeout(() => { renderTex(); const q = $('#txQ'); q.focus(); q.setSelectionRange(q.value.length, q.value.length); }, 250); return true; }
  if (el.id === 'txLock') { TX.lockPainting = el.checked; return true; }
  if (el.id === 'txHidden') { TX.showHidden = el.checked; txDraw(); return true; }
  if (el.id === 'txFloors') { TX.floors = el.checked; txDraw(); return true; }
  if (el.id === 'txHow') { TX.how = el.value; return true; }
  const k = el.dataset.tx; if (!k) return false;
  const o = txSelected(); if (!o) return true;
  // a range and a colour move live; everything settles on change
  const patch = {};
  if (k === 'x' || k === 'y') patch.at = k === 'x' ? [+el.value, o.at[1]] : [o.at[0], +el.value];
  else if (k === 'sx' || k === 'sy') patch.scale = k === 'sx' ? [Math.max(0.02, +el.value), o.scale[1]] : [o.scale[0], Math.max(0.02, +el.value)];
  else if (k === 'rot') patch.rot = Math.max(-360, Math.min(360, +el.value));
  else if (k === 'z') patch.z = Math.max(-10, Math.min(10, Math.round(+el.value)));
  else if (['flip_h', 'flip_v', 'hidden'].includes(k)) patch[k] = el.checked;
  else if (k === 'alpha') patch.alpha = +el.value;
  else if (['rx', 'ry', 'rw', 'rh'].includes(k)) {
    const im = txImage(o.tex), r = o.region ? [...o.region] : [0, 0, im?.naturalWidth || 1, im?.naturalHeight || 1], i = ['rx', 'ry', 'rw', 'rh'].indexOf(k);
    if (el.value === '' && !o.gen) patch.region = null; else { r[i] = i < 2 ? +el.value : Math.max(1, +el.value); patch.region = r; }
  } else patch[k] = el.value;
  if (e.type === 'input' && (el.type === 'range' || el.type === 'color')) { TX.live = { key: o.key, patch }; txDraw(); return true; }
  if (e.type !== 'change') return true;
  TX.live = null; txSet(o, patch); renderTex(); return true;
}
async function txUpload() {
  const inp = document.createElement('input'); inp.type = 'file'; inp.accept = 'image/*';
  inp.onchange = async () => {
    const f = inp.files[0]; if (!f) return;
    try {
      const url = URL.createObjectURL(f), im = await loadImage(url); URL.revokeObjectURL(url);
      if (im.naturalWidth > 4096 || im.naturalHeight > 4096) return toast('Слишком большая картинка: до 4096 px по стороне', 'err');
      const c = mk(im.naturalWidth, im.naturalHeight); c.getContext('2d').drawImage(im, 0, 0);
      let name = slug(f.name.replace(/\.[^.]+$/, '')), tex = `decor/studio/${name}.png`, n = 2;
      while ((TX.uploads[tex] || TX.known.has(tex)) && n < 100) tex = `decor/studio/${name}_${n++}.png`;
      TX.uploads[tex] = c.toDataURL('image/png'); txSaveUploads();
      txAdd(tex, txViewCentre());
      toast(`Положено: ${tex}. Картинка уйдёт в игру вместе с комнатой.`);
    } catch (err) { toast(err.message, 'err'); }
  };
  inp.click();
}
async function txClick(e) {
  const pick = e.target.closest('[data-tx-pick]');
  if (pick) { TX.sel = pick.dataset.txPick; renderTex(); return true; }
  const t = e.target.closest('[data-tx-tex]');
  if (t) {
    const tex = t.dataset.txTex, o = txSelected();
    if (TX.swap && o) { TX.swap = false; txSet(o, { tex, region: o.gen ? o.region : null }); renderTex(); }
    else txAdd(tex, txViewCentre());
    return true;
  }
  const b = e.target.closest('[data-tx-act]'); if (!b) return false;
  const act = b.dataset.txAct, o = txSelected();
  if (act === 'dup') txDuplicate();
  else if (act === 'del') txDelete();
  else if (act === 'reset') txReset();
  else if (act === 'swap') { TX.swap = !TX.swap; toast(TX.swap ? 'Теперь клик по картинке в библиотеке заменит взятую' : 'Замена отменена'); renderTex(); }
  else if (act === 'upload') txUpload();
  else if (act === 'fit') { TX.view = null; txDraw(); }
  else if (act === 'run') runInGodot(TX.room.name, false);
  else if ((act === 'up' || act === 'down') && o && !o.gen) txEdit(r => {
    const j = o.i + (act === 'up' ? 1 : -1); if (j < 0 || j >= r.textures.length) return;
    [r.textures[o.i], r.textures[j]] = [r.textures[j], r.textures[o.i]]; TX.sel = 't:' + j;
  }), renderTex();
  return true;
}
function txPointer(c) {
  c.addEventListener('pointerdown', e => {
    c.setPointerCapture(e.pointerId);
    const P = txToRoom(e, c);
    if (e.button === 1 || TX.space) { TX.drag = { pan: true, sx: e.clientX, sy: e.clientY, ox: TX.view.ox, oy: TX.view.oy }; return; }
    const h = txHandleAt(e, c), o = txSelected();
    if (h && o) {
      const q = txCorners(o);
      TX.drag = { key: o.key, h, P0: P, o: structuredClone({ ...o, base: undefined }), box: q.box, iw: q.im.naturalWidth, ih: q.im.naturalHeight };
      return;
    }
    const hit = txHit(P);
    TX.sel = hit?.key || null;
    TX.swap = false;
    if (hit) TX.drag = { key: hit.key, move: true, P0: P, at0: [...hit.at] };
    renderTex();
  });
  c.addEventListener('pointermove', e => {
    const d = TX.drag;
    if (!d) { c.style.cursor = TX.space ? 'grab' : txHandleAt(e, c) ? 'pointer' : 'default'; return; }
    if (d.pan) { TX.view.ox = d.ox + e.clientX - d.sx; TX.view.oy = d.oy + e.clientY - d.sy; return txDraw(); }
    const P = txToRoom(e, c);
    if (d.move) {
      let dx = P[0] - d.P0[0], dy = P[1] - d.P0[1];
      if (e.shiftKey) { if (Math.abs(dx) > Math.abs(dy)) dy = 0; else dx = 0; }
      TX.live = { key: d.key, patch: { at: [Math.round(d.at0[0] + dx), Math.round(d.at0[1] + dy)] } };
    } else if (d.h === 'rot') {
      const cx = txApply(txMatrix(d.o), d.box[0] + d.box[2] / 2, d.box[1] + d.box[3] / 2);
      let a = Math.atan2(P[1] - cx[1], P[0] - cx[0]) * 180 / Math.PI + 90;
      a = ((a + 180) % 360 + 360) % 360 - 180;
      TX.live = { key: d.key, patch: { rot: e.shiftKey ? Math.round(a / 15) * 15 : txRound(a, 1) } };
    } else {
      const r = txResize(d.o, d.box, d.h, P, TX.how, e.shiftKey, d.iw, d.ih);
      const patch = { at: r.at.map(v => txRound(v, 1)) };
      if (r.scale) patch.scale = r.scale.map(v => txRound(v, 3)); else patch.region = r.region;
      TX.live = { key: d.key, patch };
    }
    txDraw();
  });
  const up = () => {
    const d = TX.drag; TX.drag = null; if (!d || d.pan) return;
    const live = TX.live; TX.live = null;
    if (live) { const o = txObjects().find(x => x.key === live.key); if (o) txSet(o, live.patch); }
    renderTex();
  };
  c.addEventListener('pointerup', up); c.addEventListener('pointercancel', up);
  c.addEventListener('wheel', e => {
    e.preventDefault();
    const r = c.getBoundingClientRect(), sx = e.clientX - r.left, sy = e.clientY - r.top, v = TX.view;
    const k = Math.min(16, Math.max(0.05, v.k * Math.exp(-e.deltaY * 0.0015)));
    v.ox = sx - (sx - v.ox) * k / v.k; v.oy = sy - (sy - v.oy) * k / v.k; v.k = k; txDraw();
  }, { passive: false });
}
if (typeof document !== 'undefined') document.addEventListener('keydown', e => {
  if (mode !== 'tex' || /INPUT|SELECT|TEXTAREA/.test(document.activeElement?.tagName || '') || document.getElementById('dlg')?.open) return;
  if (e.code === 'Space') { TX.space = true; e.preventDefault(); return; }
  const o = txSelected(); if (!o) return;
  const step = e.shiftKey ? 10 : 1, arrows = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
  if (arrows[e.key]) { e.preventDefault(); txSet(o, { at: [o.at[0] + arrows[e.key][0], o.at[1] + arrows[e.key][1]] }); return renderTex(); }
  if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); return txDelete(); }
  if ((e.ctrlKey || e.metaKey) && (e.key === 'd' || e.key === 'в')) { e.preventDefault(); return txDuplicate(); }
  if (e.key === 'h' || e.key === 'р') { txSet(o, { flip_h: !o.flip_h }); return renderTex(); }
  if (e.key === 'v' || e.key === 'м') { txSet(o, { flip_v: !o.flip_v }); return renderTex(); }
  if (e.key === 'Escape') { TX.sel = null; TX.swap = false; return renderTex(); }
});
if (typeof document !== 'undefined') {
  document.addEventListener('keyup', e => { if (e.code === 'Space') TX.space = false; });
  window.addEventListener('resize', () => { if (mode === 'tex') txDraw(); });
}

// does the draft differ from the game in her textures or retouches (and only those: the other keys are other tabs')
function txDirty() {
  const mine = gdDoc(GD_ROOMS) || {}, game = WORLD.data.files[GD_ROOMS] || {};
  return [...new Set([...Object.keys(mine), ...Object.keys(game)])].some(r => !txSame(mine[r]?.textures, game[r]?.textures) || !txSame(mine[r]?.retouch, game[r]?.retouch));
}
// the uploads a room still uses
const txUsedUploads = () => Object.keys(TX.uploads).filter(tex => Object.values(gdDoc(GD_ROOMS) || {}).some(r => (r.textures || []).some(t => t.tex === tex) || Object.values(r.retouch || {}).some(t => t.tex === tex)));
if (typeof STUDIO_TABS !== 'undefined') {
  STUDIO_TABS.tex = {
    label: 'Текстуры', title: 'room textures', tip: 'Картинки комнаты руками: двигать, растягивать, вращать, красить, свои',
    paths: p => p === GD_ROOMS && txDirty(), strings: false,
    html: `<aside class="side lifeside" id="gdSide_tex"></aside><main class="lifemain"><div class="lifebar" id="gdBar_tex"></div><canvas id="txCanvas" class="gdstage txstage"></canvas></main>`,
    problems: () => Object.entries(gdDoc(GD_ROOMS) || {}).flatMap(([room, r]) => txProblems(room, r, tex => !TX.known || txExists(tex))),
    // only her textures and retouches go back to the game's; the room's music and props stay as drafted
    revert: () => {
      const doc = structuredClone(gdDoc(GD_ROOMS) || {}), game = WORLD.data.files[GD_ROOMS] || {};
      for (const r of new Set([...Object.keys(doc), ...Object.keys(game)])) {
        const d = doc[r] ||= {};
        for (const k of ['textures', 'retouch']) { if (game[r]?.[k]) d[k] = structuredClone(game[r][k]); else delete d[k]; }
        if (!Object.keys(d).length) delete doc[r];
      }
      gdPut(GD_ROOMS, doc); TX.sel = null;
    },
    extraFiles: async () => {
      const used = txUsedUploads();
      return { files: Object.fromEntries(used.map(tex => ['assets/' + tex, dataURLtoBlob(TX.uploads[tex])])), what: used.map(tex => 'assets/' + tex) };
    },
    sent: () => { for (const tex of txUsedUploads()) delete TX.uploads[tex]; txSaveUploads(); TX.images.clear(); roomCache.delete(TX.room?.name); TX.room = null; },
    render: renderTex,
    enter: async () => {
      const c = $('#txCanvas');
      if (!c.dataset.ready) {
        c.dataset.ready = '1'; txPointer(c);
        const box = $('#gdLayout_tex');
        box.addEventListener('input', e => { if (txInput(e)) e.stopImmediatePropagation(); }, true);
        box.addEventListener('change', e => { if (txInput(e)) e.stopImmediatePropagation(); }, true);
        box.addEventListener('click', e => { const hit = e.target.closest('[data-tx-pick],[data-tx-tex],[data-tx-act]'); if (hit) { e.stopImmediatePropagation(); txClick(e); } }, true);
        const st = document.createElement('style');
        st.textContent = `.txstage{cursor:default;background:#111;image-rendering:auto}
          .txlib{max-height:30vh}.txthumb{display:flex;flex-direction:column;align-items:center;width:76px;padding:2px;font-size:10px;overflow:hidden}
          .txthumb img{width:68px;height:48px;object-fit:contain;image-rendering:pixelated;background:repeating-conic-gradient(#333 0 25%,#222 0 50%) 0 0/12px 12px}
          .txthumb span{max-width:72px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.txthumb.swap{outline:1px dashed #ffd75f}
          .txrow{cursor:pointer;margin:0;padding:1px 4px;border-radius:4px}.txrow.on{background:rgba(255,215,95,.15)}`;
        document.head.append(st);
      }
      await renderTex();
    },
  };
  if (typeof document !== 'undefined' && typeof gdInit === 'function') gdInit();
}
