// Tests for the rig's pure half (tools/studio/js/rig-core.js).
//   node --test tools/studio/tests/
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { RIG } = require('../js/rig-core.js');

// A part sheet drawn in code: body (a block with a head), a straight leg, a
// straight arm and a long thin bow, magenta-free (alpha only), as the studio
// has it after keying.
function sheet() {
  const w = 400, h = 240, a = new Uint8Array(w * h);
  const rect = (x0, y0, x1, y1) => { for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) a[y * w + x] = 255; };
  rect(20, 10, 80, 120);  // body: torso + head, 60×110
  rect(110, 10, 130, 130); // leg: 20×120
  rect(160, 10, 175, 95);  // arm: 15×85
  rect(220, 20, 226, 200); // bow: 6×180, thin
  return { a, w, h };
}
// a curved bow: its box is wide, but it fills little of it
function bowSheet() {
  const { a, w, h } = sheet();
  for (let y = 20; y < 200; y++) for (let x = 220; x < 226; x++) a[y * w + x] = 0;
  for (let t = -1; t <= 1; t += 0.002) { const x = Math.round(240 + 60 * Math.cos(t)), y = Math.round(110 + 100 * Math.sin(t)); for (let k = 0; k < 4; k++) a[y * w + x + k] = 255; }
  return { a, w, h };
}
function rigOf() {
  const { a, w, h } = sheet(), { pieces, lab } = RIG.pieces(a, w, h), roles = RIG.guessRoles(pieces), parts = {};
  for (const [role, p] of Object.entries(roles)) {
    const al = new Uint8Array(p.w * p.h);
    for (let y = 0; y < p.h; y++) for (let x = 0; x < p.w; x++) al[y * p.w + x] = lab[(p.y0 + y) * w + p.x0 + x] === p.label ? 255 : 0;
    parts[role] = { alpha: al, w: p.w, h: p.h };
  }
  const joints = RIG.measureJoints(parts);
  return { roles, rig: { parts: Object.fromEntries(Object.entries(parts).map(([k, v]) => [k, { w: v.w, h: v.h }])), joints, place: { body: [0, 0] }, hand: 'far' } };
}
const near = (a, b, tol, msg) => assert.ok(Math.hypot(a[0] - b[0], a[1] - b[1]) <= tol, `${msg}: ${a} vs ${b}`);

test('a part sheet is cut into body, leg, arm and weapon by shape', () => {
  const { roles } = rigOf();
  assert.deepEqual([roles.body.w, roles.body.h], [60, 110]);
  assert.deepEqual([roles.leg.w, roles.leg.h], [20, 120]);
  assert.deepEqual([roles.arm.w, roles.arm.h], [15, 85]);
  assert.deepEqual([roles.weapon.w, roles.weapon.h], [6, 180]);
});

test('a curved bow is a weapon, not a leg, though its box is wide', () => {
  const { a, w, h } = bowSheet(), roles = RIG.guessRoles(RIG.pieces(a, w, h).pieces);
  assert.deepEqual([roles.leg.w, roles.leg.h], [20, 120]);
  assert.deepEqual([roles.arm.w, roles.arm.h], [15, 85]);
  assert.deepEqual([roles.weapon.w, roles.weapon.h], [32, 169]);
});

test('joints are measured on the drawings, hips low on the body, the knee halfway', () => {
  const { rig } = rigOf(), J = rig.joints;
  assert.ok(J.body.hipFar[1] > 95 && J.body.hipFar[0] < J.body.hipNear[0]);
  assert.equal(J.leg.knee[1], 60);
  assert.ok(Math.abs(J.leg.ankle[1] - 95) <= 1);
  assert.deepEqual(J.leg.toe, [19, 119]);
  assert.deepEqual(J.weapon.grip, [3, 90]);
});

test('the rest pose hangs the limbs from their joints, feet on the ground', () => {
  const { rig } = rigOf(), j = RIG.solvePose(rig, RIG.REST_POSE()).joints, g = RIG.restGround(rig);
  near(j.hipNear, RIG.restPoint(rig, 'hipNear'), 1e-9, 'hip');
  assert.ok(Math.abs(j.toeNear[1] - g) < 1e-9 && Math.abs(j.heelFar[1] - g) < 1e-9);
  assert.ok(Math.abs(j.kneeNear[0] - j.hipNear[0] - (rig.joints.leg.knee[0] - rig.joints.leg.root[0])) < 1e-9);
  assert.ok(RIG.rigHeight(rig) > 200 && RIG.rigHeight(rig) < 240);
});

test('two-bone IK puts the ankle on the target, knee forward, foot flat', () => {
  const { rig } = rigOf(), pose = { ...RIG.REST_POSE(), y: 12, rot: 4 };
  const hip = RIG.solvePose(rig, pose).joints.hipNear, target = [hip[0] + 20, hip[1] + 78];
  pose.legs.near = RIG.legIK(rig, 'near', pose, target);
  const j = RIG.solvePose(rig, pose).joints;
  near(j.ankleNear, target, 1e-6, 'ankle on target');
  assert.ok(j.kneeNear[0] > (hip[0] + target[0]) / 2, 'the knee bends forward');
  assert.ok(Math.abs(j.toeNear[1] - j.heelNear[1]) < 1e-6, 'the sole stays level');
  const armPose = { ...pose }; const sh = RIG.solvePose(rig, armPose).joints.shNear, hand = [sh[0] + 40, sh[1] + 50];
  armPose.arms = { ...armPose.arms, near: RIG.armIK(rig, 'near', armPose, hand) };
  near(RIG.solvePose(rig, armPose).joints.handNear, hand, 1e-6, 'hand on target');
});

test('a generated walk plants its feet, lifts them, and passes the measured checks', () => {
  const { rig } = rigOf(), { poses, travel } = RIG.walkCycle(rig, 8), trace = RIG.traceOf(rig, poses);
  const checks = RIG.rigChecks(rig, trace, { travel, loop: true, walk: true });
  for (const c of checks) assert.ok(c.ok, `${c.id}: ${c.msg} (${c.value})`);
  assert.ok(travel > 0);
});

test('the checks catch a sliding foot, a foot in the ground and a pop', () => {
  const { rig } = rigOf(), { poses, travel } = RIG.walkCycle(rig, 8), trace = RIG.traceOf(rig, poses);
  const bad = id => RIG.rigChecks(rig, trace, { travel: id === 'slide' ? travel * 3 : travel, loop: true, walk: true }).find(c => c.id === id);
  assert.equal(bad('slide').ok, false, 'a walk played at the wrong speed skates');
  const sunk = trace.map(f => ({ ...f, toeNear: [f.toeNear[0], f.toeNear[1] + 20] }));
  assert.equal(RIG.rigChecks(rig, sunk, { travel, loop: true }).find(c => c.id === 'ground').ok, false);
  const popped = trace.map((f, i) => i === 3 ? { ...f, handNear: [f.handNear[0] + 60, f.handNear[1]] } : f);
  const pop = RIG.rigChecks(rig, popped, { travel, loop: true }).find(c => c.id === 'pop');
  assert.equal(pop.ok, false); assert.match(pop.msg, /handNear, кадр 4/);
  const still = RIG.walkCycle(rig, 8, { lift: 0 }), st = RIG.traceOf(rig, still.poses);
  assert.equal(RIG.rigChecks(rig, st, { travel: still.travel, loop: true, walk: true }).find(c => c.id === 'lift').ok, false);
});

test('key poses ease between keys and wrap round a loop', () => {
  const a = RIG.REST_POSE(), b = { ...RIG.REST_POSE(), rot: 20 };
  const keys = [{ f: 0, pose: a }, { f: 4, pose: b }];
  assert.equal(RIG.samplePose(keys, 2, 8, true).rot, 10);
  assert.equal(RIG.samplePose(keys, 4, 8, true).rot, 20);
  assert.equal(RIG.samplePose(keys, 6, 8, true).rot, 10, 'back to the first key after the last');
  assert.equal(RIG.samplePose(keys, 6, 8, false).rot, 20, 'held when it does not loop');
  const idle = RIG.idleCycle(rigOf().rig, 6), tr = RIG.traceOf(rigOf().rig, idle.poses);
  for (const c of RIG.rigChecks(rigOf().rig, tr, { loop: true })) assert.ok(c.ok, c.msg);
});
