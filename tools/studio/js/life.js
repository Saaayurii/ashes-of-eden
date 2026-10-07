/* Sprite Studio — living backdrops (data/backdrops.json, docs/BACKDROP_LIFE.md).
 * The picture runs through the game's own shader (assets/shaders/backdrop_life.gdshaderinc,
 * ported to WebGL2 below), the zones are drawn and dragged over it, and «→ В игру» rewrites
 * only the rules she changed (lib.js setBackdropRule). */
'use strict';

const LIFE = { data: null, rules: null, key: null, sel: -1, edits: new Map(), pics: new Map(), gl: null, prog: null,
  showZones: true, still: false, mood: { wind: [0, 0, 0, 0], windAt: -9, exhaleAt: -9, flashAt: -9, rage: 0, dread: 0, lean: '', leanBy: 1 },
  t0: performance.now(), raf: 0 };
const LIFE_KIND_RU = { falls: 'Водопад', water: 'Вода', sway: 'Качается', glow: 'Свечение', lava: 'Лава', haze: 'Марево', stars: 'Звёзды', pulse: 'Пульс' };
const LIFE_KIND_TIP = {
  falls: 'бегущие вниз светлые струи по холодным пикселям', water: 'рябь и блики; двигается только то, что светлее «порога воды»',
  sway: 'знамя, мох, клетка, люстра, дерево; «стоит» — качается верх', glow: 'луна, витраж, окно, врата: свет дышит цветом',
  lava: 'течёт только раскалённое, камень вокруг стоит', haze: 'дрожание воздуха над огнём, сильнее внизу',
  stars: 'мерцают только яркие точки неба', pulse: 'красные вены бьются как сердце: два удара — пауза' };
const LIFE_COLOR = { falls: '#7fc4ff', water: '#4aa3ff', sway: '#9be27a', glow: '#ffe07a', lava: '#ff7a3a', haze: '#ffb36b', stars: '#d6e0ff', pulse: '#ff4f6a' };

/* ---------- data ---------- */
async function lifeLoad() {
  if (LIFE.data) return;
  LIFE.data = await (await fetch('import/life.json')).json();
  LIFE.rules = JSON.parse(await repoText('data/backdrops.json')).rooms || {};
  // an edit the game now has (her pull request was merged) is no longer hers to send
  try { for (const [k, v] of Object.entries(JSON.parse(localStorage.getItem('ss_life') || '{}'))) if (JSON.stringify(v) !== JSON.stringify(LIFE.rules[k])) LIFE.edits.set(k, v); } catch {}
}
const lifePic = key => LIFE.data.pictures.find(p => p.key === key);
const lifeRule = key => LIFE.edits.get(key) || LIFE.rules[key] || { family: lifeGuessFamily(key), zones: [] };
function lifeGuessFamily(key) { const f = Object.keys(LIFE.data.families); return f.find(n => key.includes(n)) || f[0]; }
function lifeEdit(fn) {
  const rule = structuredClone(lifeRule(LIFE.key)); fn(rule);
  if (JSON.stringify(rule) === JSON.stringify(LIFE.rules[LIFE.key])) LIFE.edits.delete(LIFE.key); else LIFE.edits.set(LIFE.key, rule);
  try { localStorage.setItem('ss_life', JSON.stringify(Object.fromEntries(LIFE.edits))); } catch {}
  lifeUpload(); renderLifeSide(); renderLifeList(); drawLifeZones();
}
// what the game would use: a family's flame unless the rule sets its own
function lifeFlame(rule) { const f = LIFE.data.families[rule.family] || {}; return [rule.flame ?? f.flame ?? 0.5, rule.flame_floor ?? f.flame_floor ?? 0.55]; }

/* ---------- the shader: backdrop_life.gdshaderinc, one zone loop instead of the cell grid ---------- */
const LIFE_FS = `#version 300 es
precision highp float;
uniform sampler2D tex, noiseTex;
uniform vec2 size;
uniform vec4 life_rect[24], life_shape[24], life_tint[24];
uniform int life_count;
uniform float t, life_flame, life_flame_floor, life_light, life_motion, life_exhale, life_flash, life_rage, life_dread;
uniform vec4 life_wind, life_lean;
uniform vec3 life_flash_tint;
in vec2 uv; out vec4 o;
const float REACH = 260.0;
float nz(vec2 p) { return textureLod(noiseTex, (p + 0.5) / 128.0, 0.0).r; }
float edge(vec2 px, vec4 r) { float f = clamp(min(r.z, r.w) * 0.25, 2.0, 24.0);
  vec2 a = smoothstep(r.xy, r.xy + f, px) * (1.0 - smoothstep(r.xy + r.zw - f, r.xy + r.zw, px)); return a.x * a.y; }
float beat(float x) { float c = fract(x); return exp(-pow((c - 0.10) * 22.0, 2.0)) + 0.6 * exp(-pow((c - 0.28) * 22.0, 2.0)); }
float lumi(vec4 c) { return dot(c.rgb, vec3(0.299, 0.587, 0.114)); }
vec4 at(vec2 px) { return textureLod(tex, (floor(px) + 0.5) / size, 0.0); }
void main() {
  vec2 px = uv * size;
  vec2 off = vec2(0.0), rip = vec2(0.0), melt = vec2(0.0); vec3 glow = vec3(0.0);
  float wet = 0.0, wetf = 0.0, molten = 0.0, falls = 0.0, glint = 0.0, lava = 0.0, stars = 0.0, pulse = 0.0; bool touched = false;
  for (int i = 0; i < 24; i++) {
    if (i >= life_count) break;
    vec4 r = life_rect[i];
    if (px.x < r.x || px.y < r.y || px.x > r.x + r.z || px.y > r.y + r.w) continue;
    float w = edge(px, r); touched = true;
    vec4 s = life_shape[i]; int kind = int(s.x + 0.5); float k = s.y, sp = s.z; vec2 loc = (px - r.xy) / r.zw;
    if (kind == 0) { off.x += (nz(vec2(px.x * 0.35, px.y * 0.06 - t * sp * 3.0)) - 0.5) * k * 1.2 * w;
      falls += w * k * smoothstep(0.55, 0.95, nz(vec2(px.x * 0.45, px.y * 0.035 - t * sp * 2.6))); }
    else if (kind == 1) { float stir = 1.0 + 2.0 * life_wind.z * clamp(1.0 - distance(px, life_wind.xy) / REACH, 0.0, 1.0);
      rip.x += sin(px.y * 0.85 + t * sp * 2.2 * stir + px.x * 0.015) * k * 1.1 * w * stir; wet = max(wet, w); wetf = s.w;
      float g = sin(px.x * 0.11 + t * sp * 1.9) * sin(px.y * 0.6 - t * sp * 1.3 + px.x * 0.03); glint += w * k * smoothstep(0.86, 1.0, g); }
    else if (kind == 2) { float along = s.w < 0.5 ? loc.y : 1.0 - loc.y; float ph = r.x * 0.013 + r.y * 0.007;
      float gust = 0.75 + 0.25 * sin(t * sp * 0.37 + ph * 3.0); off.x -= sin(t * sp + ph + loc.y * 1.4) * k * along * along * gust * w;
      float near = life_wind.z * clamp(1.0 - distance(r.xy + r.zw * 0.5, life_wind.xy) / REACH, 0.0, 1.0);
      float push = life_wind.w + (1.0 - abs(life_wind.w)) * sin(t * 8.0 + ph * 5.0); off.x -= push * near * k * 1.8 * along * along * w; }
    else if (kind == 3) { vec2 d = (loc - 0.5) * 2.0; float fall = clamp(1.0 - dot(d, d), 0.0, 1.0);
      float br = 0.55 + 0.3 * sin(t * sp) + 0.15 * nz(vec2(t * sp * 0.7, float(i)));
      glow += life_tint[i].rgb * (w * k * fall * (br * (1.0 + life_rage * 1.5) + life_exhale * 1.5)); }
    else if (kind == 4) { vec2 fl = vec2(nz(px * 0.045 + vec2(t * sp * 0.6, 0.0)), nz(px * 0.045 - vec2(0.0, t * sp * 0.9) + 7.0));
      melt += (fl - 0.5) * k * 1.6 * w; molten = max(molten, w);
      lava += w * k * (1.0 + life_rage) * (nz(px * 0.03 - vec2(t * sp * (0.25 + life_rage * 0.25), t * sp * 0.4)) - 0.35); }
    else if (kind == 5) { float rise = t * sp * 2.5; vec2 sh = vec2(nz(px * vec2(0.09, 0.05) + vec2(0.0, rise)), nz(px * vec2(0.05, 0.09) + vec2(3.0, rise)));
      off += (sh - 0.5) * k * 1.8 * (1.0 + life_rage * 0.4) * w * (0.35 + 0.65 * loc.y); }
    else if (kind == 6) { stars += w * k * (nz(floor(px / 2.0) * 0.9 + vec2(t * sp, 0.0)) - 0.5); }
    else if (kind == 7) { pulse += w * k * (1.0 + life_dread + life_rage) * beat(t * sp + loc.x * 0.15); }
  }
  off *= life_motion; rip *= life_motion; melt *= life_motion;
  vec4 col = at(px + off), wc = wet > 0.0 ? at(px + off + rip) : col, hc = molten > 0.0 ? at(px + off + melt) : col;
  if (wet > 0.0) { float here = smoothstep(wetf, wetf + 0.06, lumi(col)); col = mix(col, wc, here * smoothstep(wetf, wetf + 0.06, lumi(wc))); glint *= here; }
  if (molten > 0.0) { float h1 = smoothstep(0.3, 0.45, lumi(col)) * clamp((col.r - col.b) * 2.2, 0.0, 1.0);
    float h2 = smoothstep(0.3, 0.45, lumi(hc)) * clamp((hc.r - hc.b) * 2.2, 0.0, 1.0); col = mix(col, hc, h1 * h2); }
  float lum = lumi(col), warm = clamp((col.r - col.b) * 2.2, 0.0, 1.0);
  bool flame_like = life_flame > 0.0 && warm > 0.0 && lum > life_flame_floor - 0.2;
  if (!touched && !flame_like && life_flash <= 0.0) { o = col; return; }
  float cool = clamp((col.b - col.r) * 3.0, 0.0, 1.0);
  if (flame_like) { float fl = smoothstep(life_flame_floor, life_flame_floor + 0.25, lum) * warm;
    float fk = nz(px / 5.0 + vec2(t * 5.3, t * 1.7)) * 0.7 + nz(px / 11.0 - vec2(t * 2.1, 0.0)) * 0.3 - 0.5;
    col.rgb *= 1.0 + life_light * fl * (life_flame * (1.0 + life_rage * 0.6) * fk * 1.4 + life_exhale * 0.25);
    float halo = smoothstep(life_flame_floor - 0.2, life_flame_floor + 0.1, lum) * warm;
    col.rgb = mix(col.rgb, lumi(col) * life_lean.rgb * 1.5, halo * life_lean.a * 0.85); }
  col.rgb += vec3(0.72, 0.84, 1.0) * falls * smoothstep(0.18, 0.55, lum) * cool * 0.4 * life_light;
  col.rgb += vec3(0.85, 0.9, 1.0) * glint * smoothstep(0.08, 0.4, lum) * 0.35 * life_light;
  col.rgb += glow * (0.25 + lum) * life_light;
  col.rgb *= 1.0 + lava * warm * smoothstep(0.25, 0.7, lum) * life_light;
  col.rgb *= 1.0 + stars * smoothstep(0.5, 0.85, lum) * (1.0 - warm) * 2.0 * life_light;
  float red = smoothstep(0.08, 0.3, col.r - max(col.g, col.b));
  col.rgb *= 1.0 + pulse * red * 0.3 * life_light;
  col.rgb += life_flash_tint * life_flash * life_light * (0.15 + cool) * smoothstep(0.1, 0.55, lum) * 0.5;
  o = col;
}`;
const LIFE_VS = `#version 300 es
in vec2 p; out vec2 uv; void main() { uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5); gl_Position = vec4(p, 0.0, 1.0); }`;

function lifeGl() {
  if (LIFE.gl) return LIFE.gl;
  const c = $('#lifeCanvas'), gl = c.getContext('webgl2', { premultipliedAlpha: false });
  if (!gl) return null;
  const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const p = gl.createProgram(); gl.attachShader(p, sh(gl.VERTEX_SHADER, LIFE_VS)); gl.attachShader(p, sh(gl.FRAGMENT_SHADER, LIFE_FS)); gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  gl.useProgram(p);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer()); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(p, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  // the noise: 128 x 128 random values, repeated and filtered (BackdropLife.noise_texture)
  let seed = 0xA5E5; const rnd = () => (seed = (seed * 1103515245 + 12345) >>> 0) >>> 24;
  const noise = new Uint8Array(128 * 128).map(rnd);
  gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, 128, 128, 0, gl.RED, gl.UNSIGNED_BYTE, noise);
  for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.REPEAT], [gl.TEXTURE_WRAP_T, gl.REPEAT]]) gl.texParameteri(gl.TEXTURE_2D, k, v);
  gl.uniform1i(gl.getUniformLocation(p, 'noiseTex'), 1); gl.uniform1i(gl.getUniformLocation(p, 'tex'), 0);
  gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
  for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.NEAREST], [gl.TEXTURE_MAG_FILTER, gl.NEAREST], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, k, v);
  LIFE.prog = p; LIFE.u = n => gl.getUniformLocation(p, n);
  return (LIFE.gl = gl);
}
// the rule's zones into the uniforms (BackdropLife.configure)
function lifeUpload() {
  const gl = LIFE.gl; if (!gl || !LIFE.key) return;
  const rule = lifeRule(LIFE.key), rect = new Float32Array(96), shape = new Float32Array(96), tint = new Float32Array(96);
  const zones = rule.zones.slice(0, LIFE.data.max_zones);
  zones.forEach((z, i) => {
    const k = LIFE.data.kinds[z.kind]; if (!k) return;
    rect.set(z.rect, i * 4);
    const extra = k.index === 1 ? (z.floor ?? 0.12) : (z.anchor === 'stands' ? 1 : 0);
    shape.set([k.index, z.strength ?? k.strength, z.speed ?? k.speed, extra], i * 4);
    const c = hexRgb(z.tint || '#ffffff'); tint.set([c[0], c[1], c[2], 1], i * 4);
  });
  gl.uniform4fv(LIFE.u('life_rect'), rect); gl.uniform4fv(LIFE.u('life_shape'), shape); gl.uniform4fv(LIFE.u('life_tint'), tint);
  gl.uniform1i(LIFE.u('life_count'), zones.length);
  const [flame, floor] = lifeFlame(rule); gl.uniform1f(LIFE.u('life_flame'), flame); gl.uniform1f(LIFE.u('life_flame_floor'), floor);
}
function hexRgb(h) { const m = String(h).replace('#', ''); const n = parseInt(m.length === 3 ? m.replace(/./g, c => c + c) : m, 16); return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255]; }

/* ---------- drawing ---------- */
async function lifeOpen(key) {
  await lifeLoad();
  const pic = lifePic(key); if (!pic) return;
  LIFE.key = key; LIFE.sel = -1;
  try { localStorage.setItem('ss_lifekey', key); } catch {}
  const gl = lifeGl(); if (!gl) { $('#lifeTip').textContent = 'Этот браузер не умеет WebGL2 — оживление не показать.'; return; }
  renderLifeSide(); renderLifeList();
  let im = LIFE.pics.get(key);
  if (!im) { $('#lifeTip').textContent = 'Загружаю картину…'; im = await loadImage(A(pic.url)); LIFE.pics.set(key, im); }
  if (LIFE.key !== key) return;
  gl.activeTexture(gl.TEXTURE0); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, im);
  gl.uniform2f(LIFE.u('size'), pic.w, pic.h);
  lifeLayout(); lifeUpload(); drawLifeZones();
  $('#lifeTip').textContent = 'Тяни по пустому месту (или после «＋ Нарисовать» — где угодно) — новая зона. Зону двигают мышью и тянут за угол, стрелки сдвигают на пиксель, Delete удаляет. Shift+клик — порыв в этой точке.';
  if (!LIFE.raf) LIFE.raf = requestAnimationFrame(lifeFrame);
}
function lifeLayout() {
  const pic = LIFE.key && lifePic(LIFE.key); if (!pic) return;
  const stage = $('#lifeStage'), W = stage.clientWidth, H = stage.clientHeight, k = Math.min(W / pic.w, H / pic.h);
  for (const c of [$('#lifeCanvas'), $('#lifeOver')]) { c.style.width = pic.w * k + 'px'; c.style.height = pic.h * k + 'px'; }
  const g = $('#lifeCanvas'); if (g.width !== pic.w || g.height !== pic.h) { g.width = pic.w; g.height = pic.h; }
  const o = $('#lifeOver'), dpr = devicePixelRatio || 1; o.width = Math.round(pic.w * k * dpr); o.height = Math.round(pic.h * k * dpr);
  LIFE.k = k;
}
function lifeFrame(now) {
  LIFE.raf = 0;
  if (mode !== 'life' || !LIFE.gl || !LIFE.key) return;
  const gl = LIFE.gl, m = LIFE.mood, t = (now - LIFE.t0) / 1000, ago = at => t - at;
  gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
  gl.uniform1f(LIFE.u('t'), LIFE.still ? 0 : t);
  gl.uniform1f(LIFE.u('life_light'), LIFE.still ? 0 : 1); gl.uniform1f(LIFE.u('life_motion'), LIFE.still ? 0 : 1);
  const gust = Math.max(0, 1 - ago(m.windAt) / 1.4);   // Ambience lets a gust die over about a second
  gl.uniform4f(LIFE.u('life_wind'), m.wind[0], m.wind[1], gust * m.wind[2], m.wind[3]);
  gl.uniform1f(LIFE.u('life_exhale'), Math.max(0, 1 - ago(m.exhaleAt) / 4));
  gl.uniform1f(LIFE.u('life_flash'), Math.max(0, 1 - ago(m.flashAt) / 0.6));
  gl.uniform3f(LIFE.u('life_flash_tint'), 0.7, 0.78, 1.0);
  gl.uniform1f(LIFE.u('life_rage'), m.rage); gl.uniform1f(LIFE.u('life_dread'), m.dread);
  const lean = m.lean && LIFE.data.lean[m.lean] ? hexRgb(LIFE.data.lean[m.lean]) : [1, 1, 1];
  gl.uniform4f(LIFE.u('life_lean'), lean[0], lean[1], lean[2], m.lean ? m.leanBy : 0);
  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  LIFE.raf = requestAnimationFrame(lifeFrame);
}
function drawLifeZones() {
  const o = $('#lifeOver'); if (!o || !LIFE.key) return;
  const x = o.getContext('2d'), s = o.width / lifePic(LIFE.key).w;
  x.clearRect(0, 0, o.width, o.height);
  if (!LIFE.showZones) return;
  const zones = lifeRule(LIFE.key).zones;
  zones.forEach((z, i) => {
    const [rx, ry, rw, rh] = z.rect.map(v => v * s), on = i === LIFE.sel, c = LIFE_COLOR[z.kind] || '#fff';
    x.lineWidth = on ? 2.5 : 1.5; x.strokeStyle = c; x.setLineDash(on ? [] : [6, 4]); x.strokeRect(rx + .5, ry + .5, rw, rh);
    x.setLineDash([]); x.font = '600 12px system-ui'; const label = `${i + 1} ${LIFE_KIND_RU[z.kind] || z.kind}`;
    x.fillStyle = 'rgba(0,0,0,.6)'; x.fillRect(rx, ry, x.measureText(label).width + 8, 17); x.fillStyle = c; x.fillText(label, rx + 4, ry + 13);
    if (on) { x.fillStyle = c; x.fillRect(rx + rw - 5, ry + rh - 5, 10, 10); }
    if (i >= LIFE.data.max_zones) { x.fillStyle = 'rgba(255,60,60,.35)'; x.fillRect(rx, ry, rw, rh); }
  });
}

/* ---------- the zones under the pointer ---------- */
function lifePoint(e) { const o = $('#lifeOver'), r = o.getBoundingClientRect(), pic = lifePic(LIFE.key); return [(e.clientX - r.left) / r.width * pic.w, (e.clientY - r.top) / r.height * pic.h]; }
function lifeHit(px, py) {
  const zones = lifeRule(LIFE.key).zones, grab = 10 / LIFE.k;
  if (LIFE.sel >= 0 && zones[LIFE.sel]) { const [x, y, w, h] = zones[LIFE.sel].rect; if (Math.abs(px - (x + w)) < grab && Math.abs(py - (y + h)) < grab) return [LIFE.sel, 'size']; }
  // the smallest zone under the pointer: a lantern inside a wall of haze is still reachable
  let best = -1, area = Infinity;
  zones.forEach((z, i) => { const [x, y, w, h] = z.rect; if (px >= x && py >= y && px <= x + w && py <= y + h && w * h < area) { best = i; area = w * h; } });
  return [best, 'move'];
}
function lifePointer() {
  const o = $('#lifeOver');
  o.addEventListener('pointerdown', e => {
    if (!LIFE.key) return;
    const [px, py] = lifePoint(e);
    if (e.shiftKey) { lifeGust(px, py, e.altKey ? -1 : 1); return; }
    const armed = LIFE.armed; LIFE.armed = false; $('#lifeDraw').classList.remove('on');
    const [i, how] = armed ? [-1, 'new'] : lifeHit(px, py), pic = lifePic(LIFE.key);
    o.setPointerCapture(e.pointerId);
    const start = { px, py, rule: structuredClone(lifeRule(LIFE.key)) };
    let drag;
    if (i >= 0) { LIFE.sel = i; drag = { i, how, rect: [...start.rule.zones[i].rect] }; renderLifeSide(); }
    else drag = { i: -1, how: 'new' };
    drawLifeZones();
    const clampRect = r => { let [x, y, w, h] = r.map(Math.round); w = Math.max(4, Math.min(w, pic.w)); h = Math.max(4, Math.min(h, pic.h)); x = Math.max(0, Math.min(x, pic.w - w)); y = Math.max(0, Math.min(y, pic.h - h)); return [x, y, w, h]; };
    const move = ev => {
      const [qx, qy] = lifePoint(ev), dx = qx - px, dy = qy - py;
      if (drag.how === 'new') {
        if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
        const rect = clampRect([Math.min(px, qx), Math.min(py, qy), Math.abs(dx), Math.abs(dy)]);
        const kind = $('#lifeNewKind').value, z = { kind, rect };
        if (kind === 'glow') z.tint = '#ffe0a0';
        if (drag.i < 0) { lifeEdit(r => { r.zones.push(z); }); drag.i = LIFE.sel = lifeRule(LIFE.key).zones.length - 1; }
        else lifeEdit(r => { r.zones[drag.i].rect = rect; });
        return;
      }
      const [x, y, w, h] = drag.rect;
      lifeEdit(r => { r.zones[drag.i].rect = drag.how === 'size' ? clampRect([x, y, w + dx, h + dy]) : clampRect([x + dx, y + dy, w, h]); });
    };
    const up = () => { o.removeEventListener('pointermove', move); o.removeEventListener('pointerup', up); renderLifeSide(); };
    o.addEventListener('pointermove', move); o.addEventListener('pointerup', up);
  });
  o.addEventListener('pointermove', e => { if (e.buttons || !LIFE.key) return; if (LIFE.armed) { o.style.cursor = 'crosshair'; return; } const [px, py] = lifePoint(e), [i, how] = lifeHit(px, py); o.style.cursor = how === 'size' ? 'nwse-resize' : i >= 0 ? 'move' : 'crosshair'; });
}
function lifeGust(x, y, push) { const m = LIFE.mood; m.wind = [x, y, 1, push]; m.windAt = (performance.now() - LIFE.t0) / 1000; }

/* ---------- side panel ---------- */
function renderLifeList() {
  if (!LIFE.data) return;
  const groups = { room: 'Комнаты', scene: 'Меню и арена', picture: 'Катсцены и переходы' }, q = ($('#lifeSearch').value || '').toLowerCase();
  $('#lifeList').innerHTML = Object.entries(groups).map(([kind, title]) => {
    const rows = LIFE.data.pictures.filter(p => p.kind === kind && p.key.includes(q)).map(p => {
      const n = lifeRule(p.key).zones.length, edited = LIFE.edits.has(p.key);
      return `<div class="irow${p.key === LIFE.key ? ' on' : ''}" data-act="life-open" data-k="${esc(p.key)}"><span class="grow">${esc(p.key)}</span>${edited ? '<span class="badge">изменено</span>' : ''}<span class="muted">${p.has_rule || edited ? n + ' зон' : 'без правила'}</span></div>`;
    }).join('');
    return rows ? `<div class="muted" style="margin:8px 0 2px">${title}</div>${rows}` : '';
  }).join('');
  $('#lifeSend').disabled = !LIFE.edits.size;
  $('#lifeSend').textContent = LIFE.edits.size ? `→ В игру (${LIFE.edits.size})` : '→ В игру';
}
function renderLifeSide() {
  const box = $('#lifeProps'); if (!LIFE.key) { box.innerHTML = ''; return; }
  const rule = lifeRule(LIFE.key), [flame, floor] = lifeFlame(rule), fams = Object.keys(LIFE.data.families);
  const z = rule.zones[LIFE.sel], kinds = Object.keys(LIFE.data.kinds);
  const num = (k, v, step, min, max, hint) => `<label class="lifenum">${hint} <span class="muted">${(+v).toFixed(2)}</span><input type="range" data-life="${k}" min="${min}" max="${max}" step="${step}" value="${v}"></label>`;
  let html = `<div class="row" style="margin:0"><b class="grow">${esc(LIFE.key)}</b>${LIFE.edits.has(LIFE.key) ? '<button class="sm" data-act="life-revert" title="Вернуть как в игре">↺ Как в игре</button>' : ''}</div>
    <label>Семейство (как горят нарисованные огни)<select data-life="family">${fams.map(f => `<option${f === rule.family ? ' selected' : ''}>${esc(f)}</option>`).join('')}</select></label>
    ${num('flame', flame, 0.01, 0, 1, 'Мерцание огней')}${num('flame_floor', floor, 0.01, 0.3, 0.95, 'С какой яркости пиксель — огонь')}
    <div class="muted" style="margin:6px 0 2px">Зоны (${rule.zones.length}/${LIFE.data.max_zones})</div>
    <div class="ilist">${rule.zones.map((q, i) => `<div class="irow${i === LIFE.sel ? ' on' : ''}" data-act="life-zone" data-i="${i}"><span style="color:${LIFE_COLOR[q.kind]}">■</span><span class="grow">${i + 1}. ${esc(LIFE_KIND_RU[q.kind] || q.kind)}</span><span class="muted">${q.rect.join(', ')}</span></div>`).join('') || '<div class="muted">Пока нет — потяни мышью по картине.</div>'}</div>`;
  if (z) {
    const k = LIFE.data.kinds[z.kind] || {};
    html += `<div class="card" style="margin-top:8px"><div class="row" style="margin:0"><b class="grow">Зона ${LIFE.sel + 1}</b><button class="sm" data-act="life-dup">⧉</button><button class="sm danger" data-act="life-del">Удалить</button></div>
      <label>Вид<select data-life="z.kind">${kinds.map(n => `<option value="${n}"${n === z.kind ? ' selected' : ''}>${LIFE_KIND_RU[n] || n}</option>`).join('')}</select></label>
      <div class="note">${esc(LIFE_KIND_TIP[z.kind] || '')}</div>
      ${num('z.strength', z.strength ?? k.strength, 0.01, 0, z.kind === 'glow' || z.kind === 'stars' ? 1 : 4, 'Сила')}
      ${num('z.speed', z.speed ?? k.speed, 0.01, 0, 4, 'Скорость')}
      ${z.kind === 'sway' ? `<label>Качается<select data-life="z.anchor"><option value="hangs"${z.anchor !== 'stands' ? ' selected' : ''}>низ (висит)</option><option value="stands"${z.anchor === 'stands' ? ' selected' : ''}>верх (стоит)</option></select></label>` : ''}
      ${z.kind === 'water' ? num('z.floor', z.floor ?? 0.12, 0.01, 0, 0.6, 'Порог воды (что темнее — стоит)') : ''}
      ${z.kind === 'glow' ? `<label>Цвет света<input type="color" data-life="z.tint" value="${esc(z.tint || '#ffffff')}"></label>` : ''}
      <div class="muted">x ${z.rect[0]}, y ${z.rect[1]}, ${z.rect[2]}×${z.rect[3]}</div></div>`;
  }
  box.innerHTML = html;
}
function lifeInput(e) {
  const el = e.target.closest('[data-life]'); if (!el) return;
  const f = el.dataset.life, v = el.type === 'range' ? +el.value : el.value;
  if (el.type === 'range' && el.previousElementSibling) el.previousElementSibling.textContent = (+v).toFixed(2);
  const commit = e.type === 'change' || el.type !== 'range';
  const apply = r => {
    if (f.startsWith('z.')) { const z = r.zones[LIFE.sel], k = f.slice(2); z[k] = v; if (k === 'kind') { delete z.anchor; delete z.floor; if (v === 'glow' && !z.tint) z.tint = '#ffe0a0'; else if (v !== 'glow') delete z.tint; delete z.strength; delete z.speed; } }
    else if (f === 'family') { r.family = v; delete r.flame; delete r.flame_floor; }
    else { const fam = LIFE.data.families[r.family] || {}; if (Math.abs(v - (fam[f] ?? -1)) < 1e-6) delete r[f]; else r[f] = v; }
  };
  if (commit) lifeEdit(apply);
  else { const rule = structuredClone(lifeRule(LIFE.key)); apply(rule); LIFE.edits.set(LIFE.key, rule); lifeUpload(); drawLifeZones(); }   // live while dragging a slider
}

/* ---------- into the game ---------- */
async function lifeFiles() {
  let text = await repoText('data/backdrops.json');
  const keys = [...LIFE.edits.keys()];
  for (const k of keys) text = setBackdropRule(text, k, LIFE.edits.get(k));
  JSON.parse(text);   // never send a broken file
  const big = keys.filter(k => LIFE.edits.get(k).zones.length > LIFE.data.max_zones);
  if (big.length) throw new Error(`Больше ${LIFE.data.max_zones} зон: ${big.join(', ')} — шейдер оживит только первые ${LIFE.data.max_zones}.`);
  return { files: { 'data/backdrops.json': text }, title: `Studio: living backdrops — ${keys.join(', ')}`,
    body: `Zones of ${keys.map(k => '`' + k + '`').join(', ')} in data/backdrops.json, drawn in the studio's «Оживление» tab (docs/BACKDROP_LIFE.md).` };
}
async function lifeSend() {
  await sendToGame(lifeFiles, null);
  // what was sent is now the game's own (locally) or waits in a pull request
  const sent = [...LIFE.edits.keys()];
  if (Writer.mode === 'local') { for (const k of sent) LIFE.rules[k] = LIFE.edits.get(k); LIFE.edits.clear(); try { localStorage.removeItem('ss_life'); } catch {} }
  renderLifeList(); renderLifeSide();
}

async function lifeEnter() {
  try { await lifeLoad(); }
  catch (e) { $('#lifeTip').textContent = 'Нет данных оживления (import/life.json): ' + e.message; return; }
  renderLifeList();
  let key = LIFE.key; try { key = key || localStorage.getItem('ss_lifekey'); } catch {}
  await lifeOpen(lifePic(key) ? key : LIFE.data.pictures[0]?.key);
}
function lifeInit() {
  if (!$('#lifeLayout')) return;
  lifePointer();
  $('#lifeSide').addEventListener('input', lifeInput); $('#lifeSide').addEventListener('change', lifeInput);
  $('#lifeSearch').addEventListener('input', renderLifeList);
  $('#lifeNewKind').innerHTML = Object.entries(LIFE_KIND_RU).map(([k, v]) => `<option value="${k}">${v}</option>`).join('');
  new ResizeObserver(() => { if (mode === 'life') { lifeLayout(); drawLifeZones(); } }).observe($('#lifeStage'));
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act^="life-"]'); if (!b) return;
    const act = b.dataset.act, m = LIFE.mood, now = (performance.now() - LIFE.t0) / 1000;
    if (act === 'life-open') return lifeOpen(b.dataset.k);
    if (act === 'life-zone') { LIFE.sel = +b.dataset.i; renderLifeSide(); return drawLifeZones(); }
    if (act === 'life-del') { const i = LIFE.sel; LIFE.sel = -1; return lifeEdit(r => { r.zones.splice(i, 1); }); }
    if (act === 'life-dup') { const i = LIFE.sel; lifeEdit(r => { const z = structuredClone(r.zones[i]); z.rect[0] += 12; z.rect[1] += 12; r.zones.splice(i + 1, 0, z); }); LIFE.sel = i + 1; renderLifeSide(); return drawLifeZones(); }
    if (act === 'life-revert') { LIFE.edits.delete(LIFE.key); LIFE.sel = -1; return lifeEdit(() => {}); }
    if (act === 'life-draw') { LIFE.armed = !LIFE.armed; b.classList.toggle('on', LIFE.armed); return; }
    if (act === 'life-zones') { LIFE.showZones = !LIFE.showZones; b.classList.toggle('on', LIFE.showZones); return drawLifeZones(); }
    if (act === 'life-still') { LIFE.still = !LIFE.still; b.classList.toggle('on', LIFE.still); return; }
    if (act === 'life-gust') { const p = lifePic(LIFE.key); return lifeGust(p.w / 2, p.h * 0.7, 0); }
    if (act === 'life-flash') { m.flashAt = now; return; }
    if (act === 'life-exhale') { m.exhaleAt = now; return; }
    if (act === 'life-send') return lifeSend();
  });
  $('#lifeRage').addEventListener('input', e => { LIFE.mood.rage = +e.target.value; });
  $('#lifeDread').addEventListener('input', e => { LIFE.mood.dread = +e.target.value; });
  $('#lifeLean').addEventListener('change', e => { LIFE.mood.lean = e.target.value; });
  document.addEventListener('keydown', e => {
    if (mode !== 'life' || LIFE.sel < 0 || /INPUT|SELECT|TEXTAREA/.test(document.activeElement?.tagName)) return;
    if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); const i = LIFE.sel; LIFE.sel = -1; lifeEdit(r => { r.zones.splice(i, 1); }); }
    const arrow = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    if (arrow) { e.preventDefault(); const s = e.shiftKey ? 10 : 1, i = LIFE.sel; lifeEdit(r => { r.zones[i].rect[0] += arrow[0] * s; r.zones[i].rect[1] += arrow[1] * s; }); }
  });
}
lifeInit();
