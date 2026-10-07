/* Sprite Studio — the rig's pure half: cutting a part sheet, joints, poses,
 * two-bone IK, gaits and the measured checks. No DOM; loaded by index.html
 * as a plain script (everything lands on window) and by the Node tests.
 *
 * The method is ref2game's (references/animation.md, templates/live/lib.js
 * twoBone, scripts/partrig.py), ported: a character is a body plus ONE drawing
 * of a leg and ONE of an arm (both sides use it, the far one darker), each
 * limb cut at its joints into thigh/shin/foot and upper/fore arm. Here the rig
 * is a frame generator, not the place art is judged: poses are rendered at the
 * part sheet's resolution, snapped to the pixel grid at the character's height
 * and handed to the studio as ordinary frames (js/rig.js «Запечь»).
 *
 * Angles are degrees, 0 = the drawing as it hangs, positive = clockwise on
 * screen (y down). The character faces right: a thigh swung forward is
 * negative, a knee bends with a positive a2, an elbow with a negative one. */
(function (g) {
'use strict';

const D2R = Math.PI / 180;

// ---- cutting a part sheet ----

// Connected pieces of a mask (4-neighbour), largest first: {x0, y0, x1, y1, w, h, area, label}.
// lab gets each pixel's piece number (1-based). Pieces under minArea are dropped.
function pieces(mask, w, h, minArea = 30) {
  const lab = new Int32Array(w * h), out = [], st = new Int32Array(w * h);
  let next = 0;
  for (let p0 = 0; p0 < w * h; p0++) {
    if (!mask[p0] || lab[p0]) continue;
    const id = ++next; let sp = 0, area = 0, x0 = w, y0 = h, x1 = -1, y1 = -1;
    st[sp++] = p0; lab[p0] = id;
    while (sp) {
      const p = st[--sp], x = p % w, y = (p - x) / w; area++;
      if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
      if (x > 0 && mask[p - 1] && !lab[p - 1]) { lab[p - 1] = id; st[sp++] = p - 1; }
      if (x < w - 1 && mask[p + 1] && !lab[p + 1]) { lab[p + 1] = id; st[sp++] = p + 1; }
      if (y > 0 && mask[p - w] && !lab[p - w]) { lab[p - w] = id; st[sp++] = p - w; }
      if (y < h - 1 && mask[p + w] && !lab[p + w]) { lab[p + w] = id; st[sp++] = p + w; }
    }
    if (area >= minArea) out.push({ x0, y0, x1, y1, w: x1 - x0 + 1, h: y1 - y0 + 1, area, label: id });
  }
  out.sort((a, b) => b.area - a.area);
  return { pieces: out, lab };
}

// Which piece is which, by shape: the biggest is the body; of the rest the
// longest upright one the leg, the next the arm, a long thin one the weapon.
// Small specks beyond four pieces are left out (an arrow, a strap: she can
// assign them by hand).
function guessRoles(list) {
  if (!list.length) return {};
  const roles = { body: list[0] }, rest = list.slice(1, 6);
  const thin = p => Math.max(p.w, p.h) / Math.max(1, Math.min(p.w, p.h));
  // a weapon is far thinner than a limb: 8:1 and more (a spear, a blade), or a thin curve
  // filling little of its box (a bow); a limb fills most of its box
  const fill = p => p.area / (p.w * p.h), wpnScore = p => Math.max(thin(p) / 8, 0.3 / fill(p));
  const wpn = rest.slice().sort((a, b) => wpnScore(b) - wpnScore(a))[0];
  if (wpn && wpnScore(wpn) >= 1) roles.weapon = wpn;
  const limbs = rest.filter(p => p !== roles.weapon && p.h >= p.w).sort((a, b) => b.h - a.h || b.area - a.area);
  if (limbs[0]) roles.leg = limbs[0];
  if (limbs[1]) roles.arm = limbs[1];
  return roles;
}
// Mean x of the opaque pixels of a row at fraction f of a part's height
// (partrig.py rows()), in the part's own pixels; and the row's extent.
function rowAt(alpha, w, h, f) {
  const y = Math.min(h - 1, Math.max(0, Math.round(f * (h - 1))));
  let s = 0, n = 0, x0 = -1, x1 = -1;
  for (let x = 0; x < w; x++) if (alpha[y * w + x] > 60) { s += x; n++; if (x0 < 0) x0 = x; x1 = x; }
  return { x: n ? s / n : w / 2, y, x0: x0 < 0 ? 0 : x0, x1: x1 < 0 ? w - 1 : x1 };
}
const lastRow = (alpha, w, h) => { for (let y = h - 1; y >= 0; y--) for (let x = 0; x < w; x++) if (alpha[y * w + x] > 60) return y; return h - 1; };

// Joints measured on the drawings (partrig.py), each in its own part's pixels:
// body {hipFar, hipNear, shFar, shNear}, leg {root, knee, ankle, toe, heel},
// arm {root, elbow, hand}, weapon {grip}. parts: {role: {alpha, w, h}}.
// A side view facing right: both hips and both shoulders close to the middle,
// the far ones a little behind (to the left).
function measureJoints(parts, o = {}) {
  const J = {}, hem = o.hem ?? 0.07;
  if (parts.body) {
    const { alpha, w, h } = parts.body, hip = rowAt(alpha, w, h, 1 - hem * 1.5), span = hip.x1 - hip.x0;
    J.body = { hipFar: [hip.x0 + 0.38 * span, hip.y], hipNear: [hip.x0 + 0.58 * span, hip.y] };
    let best = { span: -1, f: 0.3 };
    for (let f = 0.22; f <= 0.5; f += 0.01) { const r = rowAt(alpha, w, h, f); if (r.x1 - r.x0 > best.span) best = { span: r.x1 - r.x0, f, r }; }
    const r = best.r, y = Math.max(0, r.y - 0.03 * h);
    J.body.shFar = [r.x0 + 0.42 * (r.x1 - r.x0), y]; J.body.shNear = [r.x0 + 0.6 * (r.x1 - r.x0), y];
  }
  if (parts.leg) {
    const { alpha, w, h } = parts.leg, sole = lastRow(alpha, w, h), b = rowAt(alpha, w, h, sole / Math.max(1, h - 1));
    const at = f => { const r = rowAt(alpha, w, h, f); return [r.x, r.y]; };
    J.leg = { root: at(o.hipF ?? 0.03), knee: at(o.knee ?? 0.5), ankle: at(o.ankle ?? 0.8), toe: [b.x1, sole], heel: [b.x0, sole] };
  }
  if (parts.arm) {
    const { alpha, w, h } = parts.arm, at = f => { const r = rowAt(alpha, w, h, f); return [r.x, r.y]; };
    J.arm = { root: at(0.05), elbow: at(o.elbow ?? 0.47), hand: at(o.hand ?? 0.9) };
  }
  if (parts.weapon) J.weapon = { grip: [parts.weapon.w / 2, parts.weapon.h / 2] };
  return J;
}

// ---- 2D affine maths: [a, b, c, d, e, f] maps (x, y) to (a x + c y + e, b x + d y + f), like canvas setTransform ----
const M = {
  id: () => [1, 0, 0, 1, 0, 0],
  mul: (m, n) => [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]],
  t: (x, y) => [1, 0, 0, 1, x, y],
  r: deg => { const c = Math.cos(deg * D2R), s = Math.sin(deg * D2R); return [c, s, -s, c, 0, 0]; },
  ap: (m, p) => [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]],
  of: (...ms) => ms.reduce((a, b) => M.mul(a, b)),
};
// Rotation about a point.
const about = (p, deg) => M.of(M.t(p[0], p[1]), M.r(deg), M.t(-p[0], -p[1]));

// ---- the rig ----
// rig: { parts: {body, leg, arm, weapon?: {w, h}}, joints (measureJoints), place: {body: [x, y]} — where the body
//        drawing sits in rig space (its top-left), hand: 'near' | 'far' (which hand holds the weapon), weaponAngle }
// Rig space is the body drawing's space shifted by place.body; the ground is the rest sole line.

const SIDES = ['far', 'near'];
const REST_POSE = () => ({ x: 0, y: 0, rot: 0,
  legs: { far: { a1: 0, a2: 0, a3: 0 }, near: { a1: 0, a2: 0, a3: 0 } },
  arms: { far: { a1: 0, a2: 0 }, near: { a1: 0, a2: 0 } }, weapon: 0 });

// Where the body's joints are in rig space at rest.
function restPoint(rig, name) { const b = rig.joints.body[name], o = rig.place?.body || [0, 0]; return [b[0] + o[0], b[1] + o[1]]; }
// The rest ground: the lower of the two soles when the legs hang straight from their hips.
function restGround(rig) {
  const L = rig.joints.leg; return Math.max(...SIDES.map(s => restPoint(rig, 'hip' + cap(s))[1])) + (L.toe[1] - L.root[1]);
}
const cap = s => s[0].toUpperCase() + s.slice(1);

// Segments of a limb drawing, as row bands [y0, y1) of the drawing, with a small overlap so no seam opens.
function limbBands(J, h, kind) {
  const ov = Math.max(2, Math.round(h * 0.02));
  if (kind === 'leg') return [[0, J.knee[1] + ov], [J.knee[1] - ov, J.ankle[1] + ov], [J.ankle[1] - ov, h]];
  return [[0, J.elbow[1] + ov], [J.elbow[1] - ov, h]];
}

// Every drawn piece of a pose and every joint, in rig space:
// { draw: [{part, band: [y0, y1] | null, m, far}], joints: {hipNear, kneeNear, ankleNear, toeNear, heelNear, …, head, grip} }
// in draw order: far arm (+ its weapon), far leg, body, near leg, near arm (+ its weapon).
function solvePose(rig, pose) {
  const J = rig.joints, P = { ...REST_POSE(), ...pose }, body = M.of(M.t(P.x, P.y), about(restPoint(rig, 'hipNear'), P.rot), M.t(...(rig.place?.body || [0, 0])));
  const joints = {}, limb = {};
  const chain = (kind, side) => {
    const Jl = J[kind], root = M.ap(body, J.body[(kind === 'leg' ? 'hip' : 'sh') + cap(side)]);
    const a = (kind === 'leg' ? P.legs : P.arms)[side] || {}, rot = P.rot;
    // segment k turns about its own top joint; the drawing hangs from root
    const tops = kind === 'leg' ? [Jl.root, Jl.knee, Jl.ankle] : [Jl.root, Jl.elbow];
    const angles = kind === 'leg' ? [a.a1 || 0, a.a2 || 0, a.a3 || 0] : [a.a1 || 0, a.a2 || 0];
    let m = M.of(M.t(root[0], root[1]), M.r(rot), M.t(-Jl.root[0], -Jl.root[1])), ms = [];
    angles.forEach((ang, k) => { m = M.mul(m, about(tops[k], ang)); ms.push(m); });
    const S = cap(side), bands = limbBands(Jl, rig.parts[kind].h, kind);
    if (kind === 'leg') {
      joints['hip' + S] = root; joints['knee' + S] = M.ap(ms[1], Jl.knee); joints['ankle' + S] = M.ap(ms[2], Jl.ankle);
      joints['toe' + S] = M.ap(ms[2], Jl.toe); joints['heel' + S] = M.ap(ms[2], Jl.heel);
    } else {
      joints['sh' + S] = root; joints['elbow' + S] = M.ap(ms[1], Jl.elbow); joints['hand' + S] = M.ap(ms[1], Jl.hand);
    }
    // lower segments first, so the upper one covers the seam
    limb[kind + S] = ms.map((mm, k) => ({ part: kind, band: bands[k], m: mm, far: side === 'far' })).reverse();
  };
  for (const s of SIDES) { chain('leg', s); chain('arm', s); }
  const items = [];
  const weapon = side => {
    if (!rig.parts.weapon || (rig.hand || 'near') !== side) return [];
    const hand = joints['hand' + cap(side)], gp = J.weapon.grip;
    const ang = P.rot + (P.arms[side]?.a1 || 0) + (P.arms[side]?.a2 || 0) + (rig.weaponAngle || 0) + (P.weapon || 0);
    const m = M.of(M.t(hand[0], hand[1]), M.r(ang), M.t(-gp[0], -gp[1]));
    joints.grip = hand; return [{ part: 'weapon', band: null, m, far: side === 'far' }];
  };
  items.push(...limb.armFar, ...weapon('far'), ...limb.legFar, { part: 'body', band: null, m: body, far: false }, ...limb.legNear, ...limb.armNear, ...weapon('near'));
  const bt = J.body.top || [rig.parts.body.w / 2, 0];
  joints.head = M.ap(body, [bt[0], bt[1] + rig.parts.body.h * 0.08]);
  joints.hip = [(joints.hipFar[0] + joints.hipNear[0]) / 2, (joints.hipFar[1] + joints.hipNear[1]) / 2];
  return { draw: items, joints };
}

// ---- two-bone IK ----
// The thigh and shin angles (a1, a2) that put the ankle of a leg hanging from
// `hip` at `target`, knee forward (to the right). Also a3, keeping the foot flat.
// If the target is out of reach the leg points at it, straight.
function legIK(rig, side, pose, target) {
  const J = rig.joints.leg, hip = solvePose(rig, { ...pose, legs: { ...pose.legs, [side]: { a1: 0, a2: 0, a3: 0 } } }).joints['hip' + cap(side)];
  const v1 = [J.knee[0] - J.root[0], J.knee[1] - J.root[1]], v2 = [J.ankle[0] - J.knee[0], J.ankle[1] - J.knee[1]];
  const L1 = Math.hypot(...v1), L2 = Math.hypot(...v2), th1 = Math.atan2(-v1[0], v1[1]) / D2R, th2 = Math.atan2(-v2[0], v2[1]) / D2R;
  const dx = target[0] - hip[0], dy = target[1] - hip[1];
  const D = Math.min(L1 + L2 - 1e-6, Math.max(Math.abs(L1 - L2) + 1e-6, Math.hypot(dx, dy)));
  const phi = Math.atan2(-dx, dy) / D2R;
  const alpha = Math.acos(Math.min(1, Math.max(-1, (L1 * L1 + D * D - L2 * L2) / (2 * L1 * D)))) / D2R;
  const beta = Math.acos(Math.min(1, Math.max(-1, (L1 * L1 + L2 * L2 - D * D) / (2 * L1 * L2)))) / D2R;
  const rot = pose.rot || 0, a1 = phi - alpha - th1 - rot, a2 = (180 - beta) + th1 - th2;
  return { a1, a2, a3: -(rot + a1 + a2) };
}
// The same for an arm: hand at target, elbow bending forward-down (negative a2).
function armIK(rig, side, pose, target) {
  const J = rig.joints.arm, sh = solvePose(rig, pose).joints['sh' + cap(side)];
  const v1 = [J.elbow[0] - J.root[0], J.elbow[1] - J.root[1]], v2 = [J.hand[0] - J.elbow[0], J.hand[1] - J.elbow[1]];
  const L1 = Math.hypot(...v1), L2 = Math.hypot(...v2), th1 = Math.atan2(-v1[0], v1[1]) / D2R, th2 = Math.atan2(-v2[0], v2[1]) / D2R;
  const dx = target[0] - sh[0], dy = target[1] - sh[1];
  const D = Math.min(L1 + L2 - 1e-6, Math.max(Math.abs(L1 - L2) + 1e-6, Math.hypot(dx, dy)));
  const phi = Math.atan2(-dx, dy) / D2R;
  const alpha = Math.acos(Math.min(1, Math.max(-1, (L1 * L1 + D * D - L2 * L2) / (2 * L1 * D)))) / D2R;
  const beta = Math.acos(Math.min(1, Math.max(-1, (L1 * L1 + L2 * L2 - D * D) / (2 * L1 * L2)))) / D2R;
  const rot = pose.rot || 0, a1 = phi + alpha - th1 - rot, a2 = -(180 - beta) + th1 - th2;
  return { a1, a2 };
}

// ---- poses over time ----
const lerp = (a, b, t) => a + (b - a) * t;
function lerpPose(a, b, t) {
  const o = REST_POSE(), A = { ...REST_POSE(), ...a }, B = { ...REST_POSE(), ...b };
  for (const k of ['x', 'y', 'rot', 'weapon']) o[k] = lerp(A[k] || 0, B[k] || 0, t);
  for (const s of SIDES) {
    for (const k of ['a1', 'a2', 'a3']) o.legs[s][k] = lerp(A.legs[s]?.[k] || 0, B.legs[s]?.[k] || 0, t);
    for (const k of ['a1', 'a2']) o.arms[s][k] = lerp(A.arms[s]?.[k] || 0, B.arms[s]?.[k] || 0, t);
  }
  return o;
}
// keys: [{f, pose}] at frame indices; frame i of n, looping or held at the ends. Smooth (eased) between keys.
function samplePose(keys, i, n, loop) {
  if (!keys?.length) return REST_POSE();
  const ks = keys.slice().sort((a, b) => a.f - b.f);
  if (ks.length === 1) return lerpPose(ks[0].pose, ks[0].pose, 0);
  let a = null, b = null;
  for (const k of ks) { if (k.f <= i) a = k; if (k.f >= i && !b) b = k; }
  if (loop) { if (!a) a = { ...ks[ks.length - 1], f: ks[ks.length - 1].f - n }; if (!b) b = { ...ks[0], f: ks[0].f + n }; }
  else { a ||= ks[0]; b ||= ks[ks.length - 1]; }
  if (a.f === b.f) return lerpPose(a.pose, a.pose, 0);
  const t = (i - a.f) / (b.f - a.f), e = t * t * (3 - 2 * t);
  return lerpPose(a.pose, b.pose, e);
}

// ---- gaits: generated poses, feet planted ----
// A walk in place, n frames, one cycle (two steps): the stance foot slides back
// at exactly body speed, the swing foot arcs forward and lands; the hips ride
// the stance leg (lowest at double support); knees by IK; arms against the legs.
// o: {stride (fraction of height, a foot's travel in stance), lift (fraction), duty, arm (deg), lean (deg)}.
// Returns {poses, travel}: travel = how far the body moves per frame in rig px (for the foot-slide check and the game's speed).
function walkCycle(rig, n = 8, o = {}) {
  const H = rigHeight(rig), stride = (o.stride ?? 0.3) * H, lift = (o.lift ?? 0.06) * H, duty = o.duty ?? 0.5;
  const ground = restGround(rig), J = rig.joints.leg, ankleUp = J.toe[1] - J.ankle[1];
  const legLen = Math.hypot(J.knee[0] - J.root[0], J.knee[1] - J.root[1]) + Math.hypot(J.ankle[0] - J.knee[0], J.ankle[1] - J.knee[1]);
  const hips = Object.fromEntries(SIDES.map(s => [s, restPoint(rig, 'hip' + cap(s))])), restHipY = Math.max(hips.far[1], hips.near[1]);
  const ankleX = s => hips[s][0] + (J.ankle[0] - J.root[0]);
  const poses = [];
  for (let i = 0; i < n; i++) {
    const feet = {};
    for (const s of SIDES) {
      const p = ((i / n) + (s === 'near' ? 0 : 0.5)) % 1;
      if (p < duty) feet[s] = { x: ankleX(s) + stride / 2 - stride * (p / duty), y: ground - ankleUp, stance: true };
      else { const q = (p - duty) / (1 - duty), e = q * q * (3 - 2 * q); feet[s] = { x: ankleX(s) - stride / 2 + stride * e, y: ground - ankleUp - lift * Math.sin(Math.PI * q), stance: false }; }
    }
    // the hips as high as the planted legs allow (0.985 of full reach: a soft knee, never locked)
    let hipY = -Infinity;
    // every foot must stay in reach — a swing foot just off the ground behind is the one a stance-only rule forgets
    for (const s of SIDES) { const dx = feet[s].x - hips[s][0]; hipY = Math.max(hipY, feet[s].y - Math.sqrt(Math.max(0, (legLen * 0.985) ** 2 - dx * dx))); }
    const y = (isFinite(hipY) ? hipY : restHipY) - restHipY + (o.bob ?? 0);
    const pose = { ...REST_POSE(), y, rot: o.lean ?? 3 };
    for (const s of SIDES) pose.legs[s] = legIK(rig, s, pose, [feet[s].x, feet[s].y]);
    const ph = 2 * Math.PI * i / n, A = o.arm ?? 18;
    pose.arms.near = { a1: A * Math.sin(ph), a2: -8 - 10 * Math.max(0, Math.sin(ph)) };
    pose.arms.far = { a1: -A * Math.sin(ph), a2: -8 - 10 * Math.max(0, -Math.sin(ph)) };
    poses.push(pose);
  }
  return { poses, travel: stride / duty / n };
}
// Breathing in place: the body sinks and rises by `depth` game pixels' worth, arms follow a little.
function idleCycle(rig, n = 6, o = {}) {
  const H = rigHeight(rig), sink = (o.depth ?? 0.025) * H, poses = [];
  const ground = restGround(rig), J = rig.joints.leg, ankleUp = J.toe[1] - J.ankle[1];
  for (let i = 0; i < n; i++) {
    const b = (1 - Math.cos(2 * Math.PI * i / n)) / 2, pose = { ...REST_POSE(), y: sink * b };
    for (const s of SIDES) { const hip = restPoint(rig, 'hip' + cap(s)); pose.legs[s] = legIK(rig, s, pose, [hip[0] + (J.ankle[0] - J.root[0]), ground - ankleUp]); }
    pose.arms.near = { a1: -2 * b, a2: -4 * b }; pose.arms.far = { a1: 2 * b, a2: -4 * b };
    poses.push(pose);
  }
  return { poses, travel: 0 };
}

// Standing height in rig px: from the top of the body drawing to the rest ground.
function rigHeight(rig) { return restGround(rig) - (rig.place?.body?.[1] || 0) - (rig.joints.body.top?.[1] || 0); }

// ---- measured checks on the joint trace (ref2game qa.mjs, animation.md §14) ----
// poses → trace: per frame, every joint in rig space.
const traceOf = (rig, poses) => poses.map(p => solvePose(rig, p).joints);
// o: {travel (rig px per frame the body moves forward), loop, walk (expects lifted feet)}
// → [{id, ok, value, limit, msg}] — msg in Russian, for her.
function rigChecks(rig, trace, o = {}) {
  const H = rigHeight(rig), ground = restGround(rig), n = trace.length, out = [], travel = o.travel || 0;
  const add = (id, ok, value, limit, msg) => out.push({ id, ok, value: +value.toFixed(3), limit, msg });
  if (!n) return out;
  // foot slide: a planted foot (its sole on the ground) must stay put in the world
  let slide = 0;
  for (const s of ['Far', 'Near']) for (const pt of ['toe', 'heel']) {
    for (let i = 0; i < (o.loop ? n : n - 1); i++) {
      const a = trace[i][pt + s], b = trace[(i + 1) % n][pt + s], tol = H * 0.012;
      if (Math.abs(a[1] - ground) < tol && Math.abs(b[1] - ground) < tol) slide = Math.max(slide, Math.abs((b[0] + travel) - a[0]) / H);
    }
  }
  add('slide', slide <= 0.02, slide, 0.02, slide <= 0.02 ? 'Ступни не скользят' : `Ступня на земле скользит (${(slide * 100).toFixed(1)}% роста за кадр)`);
  // ground: nothing of a foot below the ground line
  let under = 0;
  for (const f of trace) for (const k of ['toeFar', 'heelFar', 'toeNear', 'heelNear']) under = Math.max(under, (f[k][1] - ground) / H);
  add('ground', under <= 0.015, under, 0.015, under <= 0.015 ? 'Ноги не проваливаются в землю' : `Нога уходит под землю на ${(under * 100).toFixed(1)}% роста`);
  // stride: the ankles not wider apart than a body can step
  let spread = 0;
  for (const f of trace) spread = Math.max(spread, Math.abs(f.ankleFar[0] - f.ankleNear[0]) / H);
  add('stride', spread <= 0.6, spread, 0.6, spread <= 0.6 ? 'Шаг по росту' : `Шаг слишком широкий (${(spread * 100).toFixed(0)}% роста)`);
  // lift: in a walk every foot clearly leaves the ground once
  if (o.walk) {
    let lowest = Infinity;
    for (const s of ['Far', 'Near']) { let top = 0; for (const f of trace) top = Math.max(top, (ground - Math.min(f['toe' + s][1], f['heel' + s][1])) / H); lowest = Math.min(lowest, top); }
    add('lift', lowest >= 0.02, lowest, 0.02, lowest >= 0.02 ? 'Ноги отрываются от земли' : 'Одна нога не отрывается от земли — походка «скользит»');
  }
  // pops: a joint jumping between frames more than its neighbours explain. Sprite cycles sample
  // 6–12 frames a cycle, not ref2game's 60 a second, so the bar is per frame of an 8-frame cycle.
  let pop = 0, worst = '';
  if (n >= 3) for (const k of Object.keys(trace[0])) for (let i = o.loop ? 0 : 1; i < (o.loop ? n : n - 1); i++) {
    const a = trace[(i - 1 + n) % n][k], b = trace[i][k], c = trace[(i + 1) % n][k];
    const d = Math.hypot(a[0] - 2 * b[0] + c[0], a[1] - 2 * b[1] + c[1]) / H;
    if (d > pop) { pop = d; worst = `${k}, кадр ${i + 1}`; }
  }
  const popMax = 0.15 * Math.min(1, 8 / n);
  add('pop', pop <= popMax, pop, popMax, pop <= popMax ? 'Движение без рывков' : `Рывок: ${worst}`);
  return out;
}

Object.assign(g, { RIG: { D2R, M, about, pieces, guessRoles, rowAt, measureJoints, REST_POSE, SIDES, restPoint, restGround, rigHeight, limbBands,
  solvePose, legIK, armIK, lerpPose, samplePose, walkCycle, idleCycle, traceOf, rigChecks } });
})(typeof module !== 'undefined' ? module.exports : window);
