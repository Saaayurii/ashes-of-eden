/* Sprite Studio — «Риг»: a cut-out rig of the current character, posed and
 * baked into its animations as ordinary pixel frames. The maths is
 * js/rig-core.js (RIG); this is the page: the part sheet, its pieces and
 * their roles, joints dragged into place, poses per frame (feet and hands by
 * two-bone IK), generated walk and breath, the measured checks, and «Запечь».
 *
 * P.rig = { sheet, parts: {body|leg|arm|weapon: {src, w, h}}, joints, place, hand, weaponAngle,
 *           anims: {[animation id]: {keys: [{f, pose}], gen: 'walk'|'idle'|null, opts, travel}} } */
'use strict';

const rigUI = { frame: 0, editJoints: false, drag: null, playing: false, t0: 0, imgs: new Map(), view: null, pieces: null, sheetImg: null, lastBake: null };

const rigOf = () => P.rig || null;
const rigReady = () => { const r = rigOf(); return !!(r && r.parts?.body && r.parts?.leg && r.parts?.arm && r.joints?.leg); };
// The rig in the shape rig-core wants (sizes only; images stay here).
const rigModel = () => { const r = rigOf(); return { ...r, parts: Object.fromEntries(Object.entries(r.parts).map(([k, v]) => [k, { w: v.w, h: v.h }])) }; };
const rigAnim = () => { const a = curAnim(); if (!a || !rigOf()) return null; return (rigOf().anims ||= {})[a.id] ||= { keys: [], gen: null, opts: {}, travel: 0 }; };
const rigFrames = () => Math.max(1, curAnim()?.frames.length || 1);

/* ---------- images of the parts, plain and darkened (the far side) ---------- */
function rigImg(role, dark) {
  const p = rigOf()?.parts?.[role]; if (!p) return null;
  const key = role + (dark ? ':dark' : '') + ':' + p.src.length + ':' + p.src.slice(-24);
  if (rigUI.imgs.has(key)) return rigUI.imgs.get(key);
  const c = mk(p.w, p.h); rigUI.imgs.set(key, c);
  c._ready = loadImage(p.src).then(im => {
    const x = c.getContext('2d'); x.drawImage(im, 0, 0);
    if (dark) { x.globalCompositeOperation = 'source-atop'; x.fillStyle = 'rgba(8,6,14,0.38)'; x.fillRect(0, 0, p.w, p.h); }
    rigDraw();
  });
  return c;
}
// Every part image (plain and dark) drawn and ready: a bake must not paint a blank canvas.
async function rigImagesReady() {
  await Promise.all(Object.keys(rigOf().parts).flatMap(role => [false, true].map(d => rigImg(role, d)?._ready)));
}

/* ---------- the part sheet → pieces → parts ---------- */
async function rigLoadSheet(src) {
  if (!P) return;
  src = await normalizeImage(src);
  const img = await loadImage(src), { c, w, h, m } = maskImage(img, +P.settings.tolerance || 48, P.settings.bgMode);
  const { pieces, lab } = RIG.pieces(m, w, h, Math.max(30, (w * h) / 4000));
  if (!pieces.length) return toast('Не нашёл на листе ни одной части: проверь фон (пурпурный или прозрачный)', 'err');
  rigUI.pieces = { list: pieces.slice(0, 8), lab, w, h, canvas: c };
  const roles = RIG.guessRoles(pieces);
  P.rig = { ...(P.rig || {}), sheet: src, parts: {}, joints: null, place: { body: [0, 0] }, hand: P.rig?.hand || 'far', weaponAngle: P.rig?.weaponAngle ?? 0, anims: P.rig?.anims || {} };
  P.rig.roles = Object.fromEntries(rigUI.pieces.list.map((p, i) => [i, Object.entries(roles).find(([, q]) => q === p)?.[0] || '']));
  await rigCutParts();
  toast(`Нашёл частей: ${rigUI.pieces.list.length}. Проверь, где тело, нога, рука и оружие.`);
}
// Each piece with a role becomes a part image; joints are measured afresh.
async function rigCutParts() {
  const S = rigUI.pieces, R = P.rig; if (!S) return;
  const ctx = S.canvas.getContext('2d', { willReadFrequently: true }), all = ctx.getImageData(0, 0, S.w, S.h), parts = {}, alphas = {};
  S.list.forEach((p, i) => {
    const role = R.roles[i]; if (!role || parts[role]) return;
    const pad = 1, w = p.w + 2 * pad, h = p.h + 2 * pad, out = new ImageData(w, h), al = new Uint8Array(w * h);
    for (let y = 0; y < p.h; y++) for (let x = 0; x < p.w; x++) {
      const sp = (p.y0 + y) * S.w + p.x0 + x; if (S.lab[sp] !== p.label) continue;
      const o = ((y + pad) * w + x + pad) * 4; for (let k = 0; k < 4; k++) out.data[o + k] = all.data[sp * 4 + k];
      al[(y + pad) * w + x + pad] = all.data[sp * 4 + 3];
    }
    const c = mk(w, h); c.getContext('2d').putImageData(out, 0, 0);
    parts[role] = { src: c.toDataURL('image/png'), w, h }; alphas[role] = { alpha: al, w, h };
  });
  R.parts = parts;
  R.joints = RIG.measureJoints(alphas);
  if (R.joints.body) R.joints.body.top = [parts.body.w / 2, 1];
  rigUI.imgs.clear(); save(); renderRig();
}

/* ---------- view: fit the rest pose into the stage ---------- */
function rigFit(cv) {
  const rig = rigModel(), H = RIG.rigHeight(rig), g = RIG.restGround(rig), mid = RIG.restPoint(rig, 'hipNear')[0];
  const s = Math.min(cv.height * 0.8 / H, cv.width * 0.5 / H);
  rigUI.view = [s, 0, 0, s, cv.width / 2 - mid * s, cv.height * 0.9 - g * s];
}
const toRig = (x, y) => { const v = rigUI.view; return [(x - v[4]) / v[0], (y - v[5]) / v[3]]; };

// The pose of the current frame: a key's, else the generated one, else interpolated keys, else rest.
function rigPoseAt(i) {
  const st = rigAnim(); if (!st) return RIG.REST_POSE();
  if (st.gen && !st.keys.length) return rigGenerated(st)[i % rigFrames()] || RIG.REST_POSE();
  return RIG.samplePose(st.keys, i, rigFrames(), !!curAnim()?.loop);
}
function rigGenerated(st) {
  const n = rigFrames(), rig = rigModel();
  const r = st.gen === 'walk' ? RIG.walkCycle(rig, n, st.opts) : st.gen === 'idle' ? RIG.idleCycle(rig, n, st.opts) : { poses: [], travel: 0 };
  st.travel = r.travel; return r.poses;
}
// Edits stick to keys: a generated animation becomes one key per frame on its first edit.
function rigKeysForEdit() {
  const st = rigAnim(), n = rigFrames();
  if (st.gen && !st.keys.length) { st.keys = rigGenerated(st).map((pose, f) => ({ f, pose })); }
  let k = st.keys.find(k => k.f === rigUI.frame);
  if (!k) { k = { f: rigUI.frame, pose: rigPoseAt(rigUI.frame) }; st.keys.push(k); }
  return k;
}

/* ---------- drawing ---------- */
function rigPaint(ctx, view, pose, alpha = 1) {
  const R = rigOf(), rig = rigModel(), sol = RIG.solvePose(rig, pose);
  ctx.save(); ctx.globalAlpha = alpha;
  for (const it of sol.draw) {
    const img = rigImg(it.part, it.far && it.part !== 'body'); if (!img) continue;
    const m = RIG.M.mul(view, it.m); ctx.setTransform(m[0], m[1], m[2], m[3], m[4], m[5]);
    if (it.band) { const [y0, y1] = it.band, h = Math.max(1, Math.min(R.parts[it.part].h, y1) - Math.max(0, y0)); ctx.drawImage(img, 0, Math.max(0, y0), R.parts[it.part].w, h, 0, Math.max(0, y0), R.parts[it.part].w, h); }
    else ctx.drawImage(img, 0, 0);
  }
  ctx.restore();
  return sol;
}
const HANDLES_POSE = ['ankleNear', 'ankleFar', 'handNear', 'handFar', 'hip', 'head'];
function rigHandlesJoints() {
  // where each editable joint is, at rest, in rig space, and how to write it back
  const R = rigOf(), J = R.joints, rig = rigModel(), sol = RIG.solvePose(rig, RIG.REST_POSE()).joints, out = [];
  const body = (k) => ({ id: 'body.' + k, at: RIG.restPoint(rig, k), set: p => { const o = R.place.body; J.body[k] = [p[0] - o[0], p[1] - o[1]]; } });
  for (const k of ['hipFar', 'hipNear', 'shFar', 'shNear']) out.push(body(k));
  const legOff = [sol.hipNear[0] - J.leg.root[0], sol.hipNear[1] - J.leg.root[1]];
  for (const k of ['knee', 'ankle', 'toe', 'heel']) out.push({ id: 'leg.' + k, at: [J.leg[k][0] + legOff[0], J.leg[k][1] + legOff[1]], set: p => { J.leg[k] = [p[0] - legOff[0], p[1] - legOff[1]]; } });
  const armOff = [sol.shNear[0] - J.arm.root[0], sol.shNear[1] - J.arm.root[1]];
  for (const k of ['elbow', 'hand']) out.push({ id: 'arm.' + k, at: [J.arm[k][0] + armOff[0], J.arm[k][1] + armOff[1]], set: p => { J.arm[k] = [p[0] - armOff[0], p[1] - armOff[1]]; } });
  return out;
}
const JOINT_RU = { 'body.hipFar': 'бедро (дальнее)', 'body.hipNear': 'бедро', 'body.shFar': 'плечо (дальнее)', 'body.shNear': 'плечо', 'leg.knee': 'колено', 'leg.ankle': 'щиколотка', 'leg.toe': 'носок', 'leg.heel': 'пятка', 'arm.elbow': 'локоть', 'arm.hand': 'кисть',
  ankleNear: 'стопа', ankleFar: 'стопа (дальняя)', handNear: 'кисть', handFar: 'кисть (дальняя)', hip: 'таз — двигает тело', head: 'голова — наклон' };

function rigDraw() {
  const cv = $('#rigCanvas'); if (!cv || mode !== 'rig') return;
  const ctx = cv.getContext('2d'); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, cv.width, cv.height);
  if (!rigReady()) { ctx.fillStyle = '#8a8f9c'; ctx.font = '15px system-ui'; ctx.textAlign = 'center'; ctx.fillText('Загрузи лист частей: тело без рук и ног, одна нога, одна рука, оружие — на пурпурном фоне', cv.width / 2, cv.height / 2); return; }
  rigFit(cv);
  const v = rigUI.view, rig = rigModel(), g = RIG.restGround(rig);
  ctx.strokeStyle = '#3a4a3a'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(0, v[5] + g * v[3]); ctx.lineTo(cv.width, v[5] + g * v[3]); ctx.stroke();
  const n = rigFrames(), i = rigUI.playing ? Math.floor((performance.now() - rigUI.t0) / 1000 * (+curAnim()?.fps || 8)) % n : rigUI.frame;
  if (!rigUI.editJoints && !rigUI.playing && n > 1) rigPaint(ctx, v, rigPoseAt((i - 1 + n) % n), 0.22);
  const sol = rigPaint(ctx, v, rigUI.editJoints ? RIG.REST_POSE() : rigPoseAt(i));
  if (rigUI.playing) return;
  const handles = rigUI.editJoints ? rigHandlesJoints().map(h => ({ id: h.id, at: h.at })) : HANDLES_POSE.map(id => ({ id, at: sol.joints[id] }));
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  for (const h of handles) {
    const x = v[4] + h.at[0] * v[0], y = v[5] + h.at[1] * v[3];
    ctx.beginPath(); ctx.arc(x, y, 6, 0, 7); ctx.fillStyle = rigUI.drag?.id === h.id ? '#ffd166' : /far|Far/.test(h.id) ? '#7aa2ff88' : '#ff4fd8cc'; ctx.fill();
    ctx.lineWidth = 1.5; ctx.strokeStyle = '#000a'; ctx.stroke();
  }
  rigUI.handles = handles;
}

/* ---------- dragging ---------- */
function rigPointer(e) {
  const cv = $('#rigCanvas'), r = cv.getBoundingClientRect();
  return [(e.clientX - r.left) * cv.width / r.width, (e.clientY - r.top) * cv.height / r.height];
}
function rigDown(e) {
  if (!rigReady() || rigUI.playing) return;
  const [x, y] = rigPointer(e), v = rigUI.view;
  let best = null, bd = 14 * 14;
  for (const h of rigUI.handles || []) { const d = (v[4] + h.at[0] * v[0] - x) ** 2 + (v[5] + h.at[1] * v[3] - y) ** 2; if (d < bd) { bd = d; best = h; } }
  if (!best) return;
  e.preventDefault(); $('#rigCanvas').setPointerCapture(e.pointerId);
  const pose = rigUI.editJoints ? null : rigPoseAt(rigUI.frame);
  rigUI.drag = { id: best.id, start: toRig(x, y), pose: pose && JSON.parse(JSON.stringify(pose)),
    feet: pose && Object.fromEntries(['Far', 'Near'].map(s => [s, RIG.solvePose(rigModel(), pose).joints['ankle' + s]])) };
  $('#rigTip').textContent = JOINT_RU[best.id] || best.id;
}
function rigMove(e) {
  const d = rigUI.drag; if (!d) return;
  const p = toRig(...rigPointer(e)), R = rigOf(), rig = rigModel();
  if (rigUI.editJoints) { rigHandlesJoints().find(h => h.id === d.id)?.set(p); rigDraw(); return; }
  const k = rigKeysForEdit(), pose = JSON.parse(JSON.stringify(d.pose));
  if (d.id === 'hip') {
    // the body moves, the planted feet stay where they were
    pose.x = d.pose.x + p[0] - d.start[0]; pose.y = d.pose.y + p[1] - d.start[1];
    for (const s of ['far', 'near']) pose.legs[s] = RIG.legIK(rig, s, pose, d.feet[s === 'far' ? 'Far' : 'Near']);
  } else if (d.id === 'head') {
    const hip = RIG.solvePose(rig, d.pose).joints.hipNear, a0 = Math.atan2(d.start[0] - hip[0], -(d.start[1] - hip[1])), a1 = Math.atan2(p[0] - hip[0], -(p[1] - hip[1]));
    pose.rot = d.pose.rot + (a1 - a0) / RIG.D2R;
    for (const s of ['far', 'near']) pose.legs[s] = RIG.legIK(rig, s, pose, d.feet[s === 'far' ? 'Far' : 'Near']);
  } else if (d.id.startsWith('ankle')) {
    const s = d.id === 'ankleFar' ? 'far' : 'near', g = RIG.restGround(rig), up = R.joints.leg.toe[1] - R.joints.leg.ankle[1];
    pose.legs[s] = RIG.legIK(rig, s, pose, [p[0], Math.min(p[1], g - up)]);   // never through the ground
  } else if (d.id.startsWith('hand')) {
    const s = d.id === 'handFar' ? 'far' : 'near'; pose.arms[s] = RIG.armIK(rig, s, pose, p);
  }
  k.pose = pose; rigDraw();
}
function rigUp() {
  if (!rigUI.drag) return;
  rigUI.drag = null; $('#rigTip').textContent = '';
  save(); renderRigSide(); rigDraw(); rigRunChecks();
}

/* ---------- checks and bake ---------- */
function rigTraceNow() {
  const st = rigAnim(), n = rigFrames(), poses = [...Array(n)].map((_, i) => rigPoseAt(i));
  return { poses, trace: RIG.traceOf(rigModel(), poses), travel: st?.gen === 'walk' && !st.keys.length ? st.travel : (st?.travel || 0) };
}
function rigRunChecks() {
  const box = $('#rigChecks'); if (!box) return [];
  if (!rigReady() || !curAnim()) { box.innerHTML = ''; return []; }
  const { trace, travel } = rigTraceNow(), a = curAnim();
  const checks = RIG.rigChecks(rigModel(), trace, { travel, loop: !!a.loop, walk: rigAnim().gen === 'walk' || /walk|run|ход|бег/i.test(a.name) });
  box.innerHTML = checks.map(c => `<div class="${c.ok ? 'ok' : 'bad'}">${c.ok ? '✓' : '✗'} ${esc(c.msg)}</div>`).join('');
  return checks;
}
// Every frame rendered at 8× the game's size, shrunk with the dominant colour of each cell (crisp pixels,
// no blur), feet on the cell's ground row, the hips in the middle. Written into the animation's frames.
async function rigBake() {
  if (!rigReady()) return toast('Сначала лист частей', 'err');
  const a = curAnim(); if (!a) return;
  await rigImagesReady();
  const bad = rigRunChecks().filter(c => !c.ok);
  if (bad.length && !confirm('Проверки не прошли:\n' + bad.map(c => '• ' + c.msg).join('\n') + '\n\nВсё равно запечь?')) return;
  const S = P.settings, W = +S.cellW, H = +S.cellH, K = 8, rig = rigModel(), n = rigFrames();
  const s = +S.contentH / RIG.rigHeight(rig), g = RIG.restGround(rig), mid = (RIG.restPoint(rig, 'hipFar')[0] + RIG.restPoint(rig, 'hipNear')[0]) / 2;
  // the view puts the ground on the row above bottomPad and the hips at the cell's middle
  const view = [s * K, 0, 0, s * K, W * K / 2 - mid * s * K, (H - (+S.bottomPad || 0)) * K - g * s * K];
  const srcs = [];
  for (let i = 0; i < n; i++) {
    const c = mk(W * K, H * K), x = c.getContext('2d', { willReadFrequently: true });
    x.imageSmoothingEnabled = true; rigPaint(x, view, rigPoseAt(i));
    const big = x.getImageData(0, 0, c.width, c.height), small = downscale({ data: big.data, w: c.width, h: c.height }, 1 / K, 'dominant');
    const out = mk(small.w, small.h); out.getContext('2d').putImageData(small.img, 0, 0); srcs.push(out.toDataURL('image/png'));
  }
  while (a.frames.length < n) a.frames.push(newFrame());
  a.frames.forEach((f, i) => { if (i < n) Object.assign(f, { src: srcs[i], baked: true, dx: 0, dy: 0, sc: 1, off: false }); });
  const st = rigAnim();
  if (st.travel > 0) {
    // game px the body travels a frame → the fps at which the feet keep their grip at a walker's speed
    const base = (typeof enemyList !== 'undefined' && enemyList || []).find(e => e.id === (typeof sandbox !== 'undefined' ? sandbox.base : 'cultist'));
    const speed = base?.speed || 60, perFrame = st.travel * s, want = Math.round(speed / perFrame);
    a.fps = Math.max(4, Math.min(16, want));
    toast(want > 16
      ? `Запечено ${n} кадров в «${a.name}». Для скорости ${speed} px/с ногам нужно ${want} кадров/с — поставил 16, ступни будут чуть скользить. Сделай шаг длиннее или кадров больше.`
      : `Запечено ${n} кадров в «${a.name}». За кадр тело проходит ${perFrame.toFixed(1)} px — при скорости ${speed} px/с это ${a.fps} кадров/с (поставил).`, want > 16 ? 'err' : '');
  } else toast(`Запечено ${n} кадров в «${a.name}»`);
  rigUI.lastBake = Date.now(); save(); renderTabs(); renderAnimBar(); renderFrames(); scheduleBuild(50);
}

/* ---------- the page ---------- */
function renderRigSide() {
  const side = $('#rigSide'); if (!side || !P) return;
  const R = rigOf(), a = curAnim(), st = rigAnim(), S = rigUI.pieces;
  const roleSel = i => `<select data-rig-role="${i}">${[['', '—'], ['body', 'тело'], ['leg', 'нога'], ['arm', 'рука'], ['weapon', 'оружие']].map(([v, t]) => `<option value="${v}" ${R?.roles?.[i] === v ? 'selected' : ''}>${t}</option>`).join('')}</select>`;
  const H = rigReady() ? RIG.rigHeight(rigModel()) : 0;
  side.innerHTML = `
    <h3>Лист частей</h3>
    <div class="row" style="margin:0"><button class="sm" data-rig="sheet">📂 Загрузить…</button><button class="sm ghost" data-rig="from-ref" ${P.reference ? '' : 'disabled'} title="Взять референс персонажа как лист частей">Из референса</button></div>
    <div class="note">Тело с головой без рук и ног, одна нога целиком, одна рука целиком, оружие — отдельно, с широкими промежутками, на пурпурном фоне. Можно вставить Cmd/Ctrl+V.</div>
    ${S ? `<div class="rigpieces">${S.list.map((p, i) => `<div class="row" style="margin:2px 0"><span class="muted" style="width:120px">часть ${i + 1}: ${p.w}×${p.h}</span>${roleSel(i)}</div>`).join('')}</div>` : R?.parts?.body ? `<div class="muted">Части: ${Object.keys(R.parts).join(', ')}</div>` : ''}
    ${rigReady() ? `
    <h3 style="margin-top:10px">Суставы</h3>
    <label class="inline"><input type="checkbox" data-rig="joints" ${rigUI.editJoints ? 'checked' : ''}> Править суставы (поза покоя)</label>
    <div class="row" style="margin:4px 0"><span class="muted">Оружие в руке</span><select data-rig="hand"><option value="far" ${R.hand === 'far' ? 'selected' : ''}>дальней (лук)</option><option value="near" ${R.hand === 'near' ? 'selected' : ''}>ближней (меч)</option></select></div>
    <div class="row" style="margin:4px 0"><span class="muted">Угол оружия</span><input type="range" min="-180" max="180" value="${R.weaponAngle || 0}" data-rig="wangle"></div>
    <div class="muted">Рост рига ${H.toFixed(0)} px → в игре ${P.settings.contentH} px</div>` : ''}
    ${rigReady() && a ? `
    <h3 style="margin-top:10px">Анимация «${esc(a.name)}» · ${rigFrames()} кадр.</h3>
    <div class="row" style="margin:0;flex-wrap:wrap">
      <button class="sm" data-rig="gen-walk" title="Шаг на месте: ступни стоят на земле, таз едет на опорной ноге">🚶 Шаг</button>
      <button class="sm" data-rig="gen-idle" title="Дыхание: тело чуть опускается и поднимается">🫁 Дыхание</button>
      <button class="sm ghost" data-rig="clear" title="Убрать все ключи и генерацию">Сброс</button>
    </div>
    ${st.gen === 'walk' && !st.keys.length ? `<div class="row" style="margin:4px 0"><span class="muted" style="width:70px">Шаг</span><input type="range" min="0.12" max="0.45" step="0.01" value="${st.opts.stride ?? 0.3}" data-rig-opt="stride"></div>
      <div class="row" style="margin:4px 0"><span class="muted" style="width:70px">Подъём</span><input type="range" min="0" max="0.15" step="0.005" value="${st.opts.lift ?? 0.06}" data-rig-opt="lift"></div>
      <div class="row" style="margin:4px 0"><span class="muted" style="width:70px">Руки</span><input type="range" min="0" max="40" step="1" value="${st.opts.arm ?? 18}" data-rig-opt="arm"></div>` : ''}
    <div class="note">Тяни розовые точки: стопы и кисти (сустав посередине ставится сам), таз — двигает тело, ноги остаются на месте, голова — наклон. Правка превращает кадр в ключ; между ключами — плавно.</div>
    <h3 style="margin-top:10px">Проверки</h3><div id="rigChecks" class="rigchecks"></div>
    <button class="primary" data-rig="bake" style="margin-top:8px;width:100%">🔥 Запечь в «${esc(a.name)}»</button>` : ''}`;
  rigRunChecks();
}
function renderRigTimeline() {
  const tl = $('#rigTimeline'); if (!tl || !P) return;
  const st = rigAnim(), n = rigFrames(), keys = new Set((st?.keys || []).map(k => k.f));
  tl.innerHTML = [...Array(n)].map((_, i) => `<button class="sm ${i === rigUI.frame ? 'primary' : ''}" data-rig-frame="${i}">${keys.has(i) ? '◆' : ''}${i + 1}</button>`).join('') +
    `<span class="grow"></span><button class="sm" data-rig="play">${rigUI.playing ? '■' : '▶'}</button>
     <button class="sm ghost" data-rig="key-del" ${keys.has(rigUI.frame) ? '' : 'disabled'} title="Убрать ключ этого кадра">✕ ключ</button>`;
}
function renderRig() {
  if (!P) return;
  const sel = $('#rigAnim');
  if (sel) sel.innerHTML = P.animations.map(a => `<option value="${a.id}" ${a.id === P.current ? 'selected' : ''}>${esc(a.name)} (${a.frames.length})</option>`).join('');
  rigUI.frame = Math.min(rigUI.frame, rigFrames() - 1);
  renderRigSide(); renderRigTimeline(); rigDraw();
}
function rigLoop() { if (mode === 'rig' && rigUI.playing) rigDraw(); requestAnimationFrame(rigLoop); }
requestAnimationFrame(rigLoop);

document.addEventListener('click', async e => {
  const f = e.target.closest('[data-rig-frame]');
  if (f) { rigUI.frame = +f.dataset.rigFrame; rigUI.playing = false; renderRigTimeline(); rigDraw(); return; }
  const b = e.target.closest('[data-rig]'); if (!b || b.tagName === 'INPUT' || b.tagName === 'SELECT') return;
  const st = rigAnim();
  switch (b.dataset.rig) {
    case 'sheet': { const [file] = await pickFiles('image/*', false); if (file) await rigLoadSheet(await blobToDataURL(file)); break; }
    case 'from-ref': if (P.reference) await rigLoadSheet(P.reference); break;
    case 'gen-walk': if ((!st.keys.length || confirm('Заменить ключи шагом?'))) { st.keys = []; st.gen = 'walk'; save(); renderRig(); } break;
    case 'gen-idle': if ((!st.keys.length || confirm('Заменить ключи дыханием?'))) { st.keys = []; st.gen = 'idle'; save(); renderRig(); } break;
    case 'clear': if (confirm('Убрать ключи и генерацию этой анимации?')) { st.keys = []; st.gen = null; save(); renderRig(); } break;
    case 'key-del': st.keys = st.keys.filter(k => k.f !== rigUI.frame); save(); renderRig(); break;
    case 'play': rigUI.playing = !rigUI.playing; rigUI.t0 = performance.now(); renderRigTimeline(); rigDraw(); break;
    case 'bake': await rigBake(); renderRig(); break;
  }
});
document.addEventListener('change', async e => {
  const t = e.target;
  if (t.dataset.rigRole !== undefined) { P.rig.roles[t.dataset.rigRole] = t.value; await rigCutParts(); return; }
  if (t.id === 'rigAnim') { P.current = t.value; rigUI.frame = 0; save(); renderAll(); renderRig(); return; }
  if (t.dataset.rig === 'joints') { rigUI.editJoints = t.checked; rigDraw(); return; }
  if (t.dataset.rig === 'hand') { P.rig.hand = t.value; save(); rigDraw(); return; }
});
document.addEventListener('input', e => {
  const t = e.target;
  if (t.dataset.rig === 'wangle') { P.rig.weaponAngle = +t.value; save(); rigDraw(); }
  if (t.dataset.rigOpt) { rigAnim().opts[t.dataset.rigOpt] = +t.value; save(); rigDraw(); rigRunChecks(); }
});
// another character: its own rig, its own pieces
document.addEventListener('change', e => { if (e.target.id === 'projSel') { rigUI.pieces = null; rigUI.frame = 0; rigUI.imgs.clear(); if (mode === 'rig') renderRig(); } });
document.addEventListener('pointerdown', e => { if (e.target.id === 'rigCanvas') rigDown(e); });
document.addEventListener('pointermove', e => { if (rigUI.drag) rigMove(e); });
document.addEventListener('pointerup', rigUp);
document.addEventListener('pointercancel', rigUp);
