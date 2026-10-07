/* Sprite Studio — shared helpers, presets, storage and the character state. Plain scripts share one global scope; index.html loads them in order. */
'use strict';

/* ---------- utils ---------- */
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const uid = () => Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-4);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tick = () => new Promise(r => setTimeout(r, 0));
const slug = s => (String(s || '').toLowerCase().replace(/[^a-z0-9_]+/g, '_').replace(/^_+|_+$/g, '') || 'sprite');
function mk(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, w); c.height = Math.max(1, h); return c; }
function loadImage(src) { return new Promise((res, rej) => { const i = new Image(); if (/^https?:/.test(src)) i.crossOrigin = 'anonymous'; i.onload = () => res(i); i.onerror = () => rej(new Error('Не удалось открыть изображение')); i.src = src; }); }
function blobToDataURL(b) { return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = () => rej(r.error); r.readAsDataURL(b); }); }
function dataURLtoBlob(d) { const [h, b] = d.split(','); const mime = (h.match(/:(.*?);/) || [, 'image/png'])[1]; const bin = atob(b); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return new Blob([u], { type: mime }); }
const canvasBlob = c => new Promise(r => c.toBlob(r, 'image/png'));
function fingerprint(s) { let h = s.length; const st = Math.max(1, (s.length / 211) | 0); for (let i = 0; i < s.length; i += st) h = (h * 31 + s.charCodeAt(i)) | 0; return h; }
async function normalizeImage(src, max = 1024) {
  const img = await loadImage(src);
  const s = Math.min(1, max / Math.max(img.width, img.height));
  if (s === 1 && src.startsWith('data:image/png')) return src;
  const c = mk(Math.round(img.width * s), Math.round(img.height * s));
  const x = c.getContext('2d'); x.imageSmoothingQuality = 'high'; x.drawImage(img, 0, 0, c.width, c.height);
  return c.toDataURL('image/png');
}
function download(blob, name) { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500); }
function toast(msg, kind = '') { const t = document.createElement('div'); t.className = 'toast ' + kind; t.textContent = msg; $('#toasts').appendChild(t); setTimeout(() => t.remove(), kind === 'err' ? 8000 : 3500); }
async function copyText(t) {
  try { await navigator.clipboard.writeText(t); }
  catch { const ta = document.createElement('textarea'); ta.value = t; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove(); }
  toast('Промпт скопирован');
}
function pickFiles(accept = 'image/*', multiple = true) {
  return new Promise(res => { const i = document.createElement('input'); i.type = 'file'; i.accept = accept; i.multiple = multiple; i.onchange = () => res([...i.files]); i.click(); });
}

/* ---------- presets ---------- */
const PRESETS = {
  idle: { fps: 5, loop: true, notes: 'subtle breathing loop, feet stay planted', poses: [
    'standing relaxed in a neutral stance, weapon held at rest',
    'inhale: chest and shoulders rise very slightly',
    'top of the breath, hair and cloth lift slightly',
    'exhale: shoulders lower slightly back toward neutral'] },
  walk: { fps: 10, loop: true, notes: 'calm walk cycle in place, no forward travel', poses: [
    'contact: right leg forward with heel on the ground, left leg back, arms swing opposite',
    'down: weight on the right leg, knee bent, body at its lowest point',
    'passing: left leg passes the right leg, body rising',
    'up: body at its highest, left leg reaching forward',
    'contact: left leg forward with heel on the ground, right leg back, arms swing opposite',
    'down: weight on the left leg, knee bent, body at its lowest point',
    'passing: right leg passes the left leg, body rising',
    'up: body at its highest, right leg reaching forward'] },
  run: { fps: 12, loop: true, notes: 'energetic run cycle in place, torso leaning forward, no forward travel', poses: [
    'contact: right foot striking the ground in front, left leg pushing behind, arms pumping opposite',
    'down: weight on the bent right leg, body lowest, left knee driving forward',
    'push-off: right leg pushing off the ground, left knee high in front',
    'flight: both feet off the ground, legs spread wide, body highest',
    'contact: left foot striking the ground in front, right leg pushing behind, arms pumping opposite',
    'down: weight on the bent left leg, body lowest, right knee driving forward',
    'push-off: left leg pushing off the ground, right knee high in front',
    'flight: both feet off the ground, legs spread wide, body highest'] },
  jump: { fps: 10, loop: false, notes: 'jump takeoff', poses: [
    'anticipation crouch, knees bent, arms swung back',
    'takeoff push, legs extending, arms swinging up',
    'rising in the air, knees tucked up',
    'apex, body compact, arms out for balance'] },
  fall: { fps: 8, loop: true, notes: 'falling loop', poses: [
    'falling, legs slightly apart and bent, arms raised for balance',
    'falling, legs shifted, arms raised, cloth and hair blown upward'] },
  land: { fps: 12, loop: false, notes: 'landing impact', poses: [
    'feet touching the ground, knees starting to bend',
    'deep crouch absorbing the impact',
    'rising back to a neutral stance'] },
  attack: { fps: 12, loop: false, notes: 'melee attack', poses: [
    'anticipation: wind-up, weapon pulled back',
    'swing start, body twisting forward',
    'strike: full extension, weapon at its furthest reach',
    'follow-through, weapon past the target',
    'recover back toward the neutral stance'] },
  shoot: { fps: 10, loop: false, notes: 'bow shot', poses: [
    'reach back over the shoulder and grab an arrow',
    'nock the arrow onto the bowstring, bow raised',
    'full draw: bow arm extended forward, string pulled to the cheek, aiming straight ahead',
    'release: string snapped forward, arrow just left the bow, slight recoil',
    'recover: lowering the bow toward neutral'] },
  hurt: { fps: 10, loop: false, notes: 'taking a hit', poses: [
    'recoil: head and torso snapped backward, pained face',
    'stagger back, knees slightly bent, arms loose'] },
  death: { fps: 8, loop: false, notes: 'death animation, ends lying on the ground', poses: [
    'hit hard, body arching backward',
    'knees buckling, weapon slipping from the hand',
    'falling backward toward the ground',
    'hitting the ground, body bounces slightly',
    'lying still on the ground, weapon dropped beside'] },
  custom: { fps: 8, loop: true, notes: '', poses: ['', '', '', ''] },
};
const PRESET_LABELS = { idle: 'Idle', walk: 'Walk', run: 'Run', jump: 'Jump', fall: 'Fall', land: 'Land', attack: 'Attack', shoot: 'Shoot (лук)', hurt: 'Hurt', death: 'Death', custom: 'Своя' };

const DEFAULT_SETTINGS = {
  cellW: 128, cellH: 64, contentH: 44, bottomPad: 0, palette: 32, tolerance: 48, pixelSize: 0,
  bgMode: 'auto', scaleMode: 'gridfit', anchor: 'mass', downMode: 'dominant',
  style: 'pixel art game sprite, crisp hard-edged pixels, no anti-aliasing, limited color palette, clean dark outline, dark fantasy',
  view: 'side view, character facing right',
  resPath: 'res://assets/sprites/',
};
const newFrame = (pose = '') => ({ id: uid(), pose, src: null, dx: 0, dy: 0, sc: 1, off: false });
function newAnim(name, preset) { const p = PRESETS[preset] || PRESETS.custom; return { id: uid(), name, fps: p.fps, loop: p.loop, scale: 1, notes: p.notes, frames: p.poses.map(newFrame) }; }
function newProject(name) { const a = [newAnim('idle', 'idle'), newAnim('run', 'run')]; return { id: uid(), name, description: '', reference: null, settings: { ...DEFAULT_SETTINGS }, animations: a, current: a[0].id, updated: Date.now() }; }
function migrate(p) {
  p.settings = { ...DEFAULT_SETTINGS, ...(p.settings || {}) };
  // «Сетка 1:1» оставляет персонажа в размере ChatGPT (часто крупнее кадра) — переводим один раз на подгонку роста
  if (p.settings.scaleMode === 'grid' && !p.settings.gridfitMigrated) p.settings.scaleMode = 'gridfit';
  p.settings.gridfitMigrated = true;
  p.animations = p.animations || [];
  for (const a of p.animations) { a.scale ??= 1; a.frames = (a.frames || []).map(f => ({ ...newFrame(), ...f })); }
  if (!p.animations.find(a => a.id === p.current)) p.current = p.animations[0]?.id || null;
  return p;
}

/* ---------- storage ---------- */
const DB = {
  db: null,
  async open() {
    if (this.db) return this.db;
    this.db = await new Promise((res, rej) => {
      const r = indexedDB.open('sprite-studio', 3);
      r.onupgradeneeded = () => { for (const st of ['projects', 'backgrounds', 'sounds', 'cutscenes']) if (!r.result.objectStoreNames.contains(st)) r.result.createObjectStore(st, { keyPath: 'id' }); };
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
    return this.db;
  },
  async run(mode, fn, store = 'projects') { const db = await this.open(); return new Promise((res, rej) => { const t = db.transaction(store, mode); const req = fn(t.objectStore(store)); t.oncomplete = () => res(req && req.result); t.onerror = () => rej(t.error); }); },
  all(store) { return this.run('readonly', s => s.getAll(), store); },
  put(p, store) { return this.run('readwrite', s => s.put(p), store); },
  del(id, store) { return this.run('readwrite', s => s.delete(id), store); },
};
let dbOk = true, saveTimer = null;
function save() { P.updated = Date.now(); P.dirty = true; trackChange('chars'); clearTimeout(saveTimer); saveTimer = setTimeout(persist, 400); }
async function persist() { if (!dbOk) return; try { await DB.put(P); } catch (e) { dbOk = false; toast('Не получилось сохранить в браузере: ' + e.message + '. Сохрани проект в .json вручную.', 'err'); } }

const API_DEFAULT = { key: '', model: 'gpt-image-1', quality: 'medium', transparent: true, fidelity: true, chain: true };
let api = { ...API_DEFAULT };
try { api = { ...API_DEFAULT, ...JSON.parse(localStorage.getItem('ss_api') || '{}') }; } catch {}
const saveApi = () => { try { localStorage.setItem('ss_api', JSON.stringify(api)); } catch {} };

/* ---------- state ---------- */
let projects = [], P = null, selected = null; // selected: {type:'ref'} | {type:'frame', id}
const busy = new Set();
let genStop = false, genRunning = false;
const curAnim = () => P.animations.find(a => a.id === P.current) || null;
function findFrame(id) { for (const a of P.animations) { const f = a.frames.find(f => f.id === id); if (f) return { a, f }; } return {}; }
