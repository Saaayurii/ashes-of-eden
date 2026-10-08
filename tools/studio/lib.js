/* Sprite Studio: the pure part — image, grid, palette and audio maths, no DOM.
 * Loaded by index.html as a plain script (everything lands on window) and by
 * the Node tests (tests/*.test.js) through module.exports. */
(function (g) {
'use strict';

function hsv(r, g, b) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d) { if (mx === r) h = ((g - b) / d) % 6; else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4; h *= 60; if (h < 0) h += 360; }
  return [h, mx ? d / mx : 0, mx / 255];
}
function cornerColor(d, w, h) {
  const rs = [], gs = [], bs = [], k = Math.max(2, Math.min(8, (Math.min(w, h) / 20) | 0));
  for (const [cx, cy] of [[0, 0], [w - k, 0], [0, h - k], [w - k, h - k]])
    for (let y = cy; y < cy + k; y++) for (let x = cx; x < cx + k; x++) { const i = (y * w + x) * 4; rs.push(d[i]); gs.push(d[i + 1]); bs.push(d[i + 2]); }
  const med = a => a.slice().sort((p, q) => p - q)[a.length >> 1];
  const key = [med(rs), med(gs), med(bs)];
  // шум фона: медианное отклонение от цвета фона
  const dev = rs.map((r, i) => Math.hypot(r - key[0], gs[i] - key[1], bs[i] - key[2]));
  return [...key, med(dev)];
}
// Background removal on raw RGBA: clears the alpha of every background pixel in d
// and returns the character mask (1 = character).
function maskPixels(d, w, h, tol, mode) {
  const n = w * h;
  let tr = 0, sm = 0; for (let p = 0; p < n; p += 7) { sm++; if (d[p * 4 + 3] < 200) tr++; }
  const useAlpha = mode === 'alpha' || (mode === 'auto' && tr / sm > 0.02);
  const bg = new Uint8Array(n);
  if (useAlpha) { for (let p = 0; p < n; p++) if (d[p * 4 + 3] < 128) bg[p] = 1; }
  else {
    const key = cornerColor(d, w, h);
    const [kh, ks, kv] = hsv(key[0], key[1], key[2]);
    const chroma = ks > 0.5 && kv > 0.4;  // яркий пурпурный/зелёный фон
    // Для обычного (тёмного/серого/белого) фона допуск берём по шуму фона, а не 48:
    // иначе тёмный персонаж на тёмном фоне съедается целиком.
    const eff = chroma ? tol : Math.min(tol, Math.max(6, key[3] * 3 + 5));
    const t2 = eff * eff, l2 = Math.max(16, (eff * 0.6) ** 2);
    const dist2 = p => { const i = p * 4, r = d[i] - key[0], g = d[i + 1] - key[1], b = d[i + 2] - key[2]; return r * r + g * g + b * b; };
    const step2 = (p, q) => { const i = p * 4, j = q * 4, r = d[i] - d[j], g = d[i + 1] - d[j + 1], b = d[i + 2] - d[j + 2]; return r * r + g * g + b * b; };
    if (mode === 'global') { for (let p = 0; p < n; p++) if (d[p * 4 + 3] < 128 || dist2(p) <= t2) bg[p] = 1; }
    else {
      // Заливка от краёв «по градиенту»: идём только туда, где цвет меняется плавно,
      // и останавливаемся на любой ступеньке — то есть на контуре персонажа.
      const st = new Int32Array(n); let sp = 0;
      const push = (p, from) => {
        if (bg[p]) return;
        if (d[p * 4 + 3] < 128 || (dist2(p) <= t2 && (chroma || from < 0 || step2(p, from) <= l2))) { bg[p] = 1; st[sp++] = p; }
      };
      for (let xx = 0; xx < w; xx++) { push(xx, -1); push((h - 1) * w + xx, -1); }
      for (let yy = 0; yy < h; yy++) { push(yy * w, -1); push(yy * w + w - 1, -1); }
      while (sp) { const p = st[--sp], px = p % w; if (px > 0) push(p - 1, p); if (px < w - 1) push(p + 1, p); if (p >= w) push(p - w, p); if (p < n - w) push(p + w, p); }
      if (!chroma && mode !== 'flood') {
        // Замкнутые куски фона (между ногами, луком и телом): крупные однотонные
        // области цвета фона, до которых заливка не дошла.
        const tight = Math.max(16, (eff * 0.7) ** 2), minArea = Math.max(40, n * 0.0006), seen = new Uint8Array(n), comp = [];
        for (let s0 = 0; s0 < n; s0++) {
          if (bg[s0] || seen[s0] || dist2(s0) > tight) continue;
          comp.length = 0; sp = 0; st[sp++] = s0; seen[s0] = 1;
          while (sp) {
            const p = st[--sp], px = p % w; comp.push(p);
            for (const q of [px > 0 ? p - 1 : -1, px < w - 1 ? p + 1 : -1, p >= w ? p - w : -1, p < n - w ? p + w : -1])
              if (q >= 0 && !bg[q] && !seen[q] && dist2(q) <= tight && step2(p, q) <= l2) { seen[q] = 1; st[sp++] = q; }
          }
          if (comp.length >= minArea) for (const p of comp) bg[p] = 1;
        }
      }
    }
    if (chroma && mode !== 'flood') {
      // Яркий хромакей: убираем его оттенок везде — в замкнутых промежутках
      // (между тетивой и луком, ногами) и в тёмной кайме по контуру.
      const win = Math.max(8, tol * 0.45);
      for (let p = 0; p < n; p++) {
        if (bg[p]) continue;
        const i = p * 4, [h2, s2, v2] = hsv(d[i], d[i + 1], d[i + 2]);
        const dh = Math.abs(h2 - kh);
        if (Math.min(dh, 360 - dh) <= win && s2 > 0.4 && v2 > 0.25) bg[p] = 1;
      }
    }
    if (chroma) {
      // цветной ореол по краю — только для хромакея, иначе срежем тёмный контур
      const t3 = (tol * 1.6) ** 2, extra = [];
      for (let p = 0; p < n; p++) {
        if (bg[p] || dist2(p) > t3) continue;
        const px = p % w;
        if ((px > 0 && bg[p - 1]) || (px < w - 1 && bg[p + 1]) || (p >= w && bg[p - w]) || (p < n - w && bg[p + w])) extra.push(p);
      }
      for (const p of extra) bg[p] = 1;
    }
  }
  const m = new Uint8Array(n);
  for (let p = 0; p < n; p++) { if (bg[p]) d[p * 4 + 3] = 0; else { d[p * 4 + 3] = 255; m[p] = 1; } }
  return m;
}
// Bounding box of a mask: {x0, y0, x1, y1, cnt}, or null when it is empty.
function cropBox(m, w, h) {
  let x0 = w, y0 = h, x1 = -1, y1 = -1, cnt = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (m[y * w + x]) { cnt++; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  return x1 < 0 ? null : { x0, y0, x1, y1, cnt };
}
function copyCut(cut) { return { img: new ImageData(new Uint8ClampedArray(cut.data), cut.w, cut.h), w: cut.w, h: cut.h }; }
function downscale(cut, s, mode) {
  const sw = cut.w, sh = cut.h, sd = cut.data;
  const tw = Math.max(1, Math.round(sw * s)), th = Math.max(1, Math.round(sh * s));
  const img = new ImageData(tw, th), od = img.data, bucket = new Map();
  for (let ty = 0; ty < th; ty++) {
    const y0 = Math.floor(ty * sh / th), y1 = Math.max(y0 + 1, Math.floor((ty + 1) * sh / th));
    for (let tx = 0; tx < tw; tx++) {
      const x0 = Math.floor(tx * sw / tw), x1 = Math.max(x0 + 1, Math.floor((tx + 1) * sw / tw));
      let cnt = 0, op = 0, r = 0, g = 0, b = 0; bucket.clear();
      for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
        const i = (y * sw + x) * 4; cnt++;
        if (sd[i + 3] < 128) continue;
        op++;
        if (mode === 'average') { r += sd[i]; g += sd[i + 1]; b += sd[i + 2]; }
        else {
          const k = (sd[i] >> 4) << 8 | (sd[i + 1] >> 4) << 4 | (sd[i + 2] >> 4);
          let e = bucket.get(k); if (!e) bucket.set(k, e = [0, 0, 0, 0]);
          e[0]++; e[1] += sd[i]; e[2] += sd[i + 1]; e[3] += sd[i + 2];
        }
      }
      if (op * 2 < cnt) continue;
      const o = (ty * tw + tx) * 4;
      if (mode === 'average') { od[o] = r / op; od[o + 1] = g / op; od[o + 2] = b / op; }
      else { let best = null; for (const e of bucket.values()) if (!best || e[0] > best[0]) best = e; od[o] = best[1] / best[0]; od[o + 1] = best[2] / best[0]; od[o + 2] = best[3] / best[0]; }
      od[o + 3] = 255;
    }
  }
  return { img, w: tw, h: th };
}
const cdist = (r1, g1, b1, r2, g2, b2) => { const dr = r1 - r2, dg = g1 - g2, db = b1 - b2; return dr * dr * 3 + dg * dg * 4 + db * db * 2; };
function buildPalette(list, k) {
  let total = 0; for (const s of list) total += s.w * s.h;
  const step = Math.max(1, Math.floor(total / 60000)), pts = [];
  let idx = 0;
  for (const s of list) { const d = s.img.data; for (let i = 0; i < d.length; i += 4, idx++) if (d[i + 3] && idx % step === 0) pts.push(d[i], d[i + 1], d[i + 2]); }
  const n = pts.length / 3; if (!n) return null;
  k = Math.min(k, n);
  let mr = 0, mg = 0, mb = 0; for (let i = 0; i < n; i++) { mr += pts[i * 3]; mg += pts[i * 3 + 1]; mb += pts[i * 3 + 2]; }
  const C = [[mr / n, mg / n, mb / n]], md = new Float64Array(n).fill(Infinity);
  while (C.length < k) {
    const c = C[C.length - 1]; let bi = 0, bd = -1;
    for (let i = 0; i < n; i++) { const dd = cdist(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2], c[0], c[1], c[2]); if (dd < md[i]) md[i] = dd; if (md[i] > bd) { bd = md[i]; bi = i; } }
    if (bd <= 0) break;
    C.push([pts[bi * 3], pts[bi * 3 + 1], pts[bi * 3 + 2]]);
  }
  const asg = new Int32Array(n);
  for (let it = 0; it < 10; it++) {
    const acc = C.map(() => [0, 0, 0, 0]);
    for (let i = 0; i < n; i++) {
      const r = pts[i * 3], g = pts[i * 3 + 1], b = pts[i * 3 + 2]; let bj = 0, bd = Infinity;
      for (let j = 0; j < C.length; j++) { const dd = cdist(r, g, b, C[j][0], C[j][1], C[j][2]); if (dd < bd) { bd = dd; bj = j; } }
      asg[i] = bj; const a = acc[bj]; a[0] += r; a[1] += g; a[2] += b; a[3]++;
    }
    for (let j = 0; j < C.length; j++) if (acc[j][3]) C[j] = [acc[j][0] / acc[j][3], acc[j][1] / acc[j][3], acc[j][2] / acc[j][3]];
  }
  return C.map(c => c.map(Math.round));
}
function applyPalette(s, pal) {
  const d = s.img.data, cache = new Map();
  for (let i = 0; i < d.length; i += 4) {
    if (!d[i + 3]) continue;
    const key = d[i] << 16 | d[i + 1] << 8 | d[i + 2];
    let c = cache.get(key);
    if (!c) { let bd = Infinity; for (const p of pal) { const dd = cdist(d[i], d[i + 1], d[i + 2], p[0], p[1], p[2]); if (dd < bd) { bd = dd; c = p; } } cache.set(key, c); }
    d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2];
  }
}
function anchorX(s, mode) {
  if (mode === 'bbox') return s.w / 2;
  const d = s.img.data, yStart = mode === 'feet' ? Math.floor(s.h * 0.8) : 0;
  let sx = 0, c = 0;
  for (let y = yStart; y < s.h; y++) for (let x = 0; x < s.w; x++) if (d[(y * s.w + x) * 4 + 3]) { sx += x + 0.5; c++; }
  return c ? sx / c : s.w / 2;
}
// ---- пиксель-перфект ----
// Нейросеть рисует «пиксель-арт» крупными блоками почти одинакового размера.
// Ищем шаг и сдвиг этой сетки по резким перепадам цвета между соседними
// столбцами/строками, потом берём по одному цвету из середины каждого блока.
function edgeProfiles(cut) {
  const { w, h, data: d } = cut, ex = new Float32Array(w), ey = new Float32Array(h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * 4;
    if (x > 0) { const j = i - 4; if (d[i + 3] || d[j + 3]) ex[x] += Math.abs(d[i] - d[j]) + Math.abs(d[i + 1] - d[j + 1]) + Math.abs(d[i + 2] - d[j + 2]) + Math.abs(d[i + 3] - d[j + 3]); }
    if (y > 0) { const j = i - w * 4; if (d[i + 3] || d[j + 3]) ey[y] += Math.abs(d[i] - d[j]) + Math.abs(d[i + 1] - d[j + 1]) + Math.abs(d[i + 2] - d[j + 2]) + Math.abs(d[i + 3] - d[j + 3]); }
  }
  // размытый край блока даёт перепад на 2–3 соседних столбцах — оставляем только пики
  const peaks = e => { const o = new Float32Array(e.length); for (let i = 1; i < e.length - 1; i++) { const v = e[i - 1] + 2 * e[i] + e[i + 1]; if (e[i] >= e[i - 1] && e[i] >= e[i + 1]) o[i] = v; } return o; };
  return [peaks(ex), peaks(ey)];
}
const P_STEP = 0.05;
// У ChatGPT сетка «плывёт»: шаг чуть гуляет по картинке. Поэтому линии сетки не
// считаем ровными, а идём вдоль картинки шагами p и каждую линию притягиваем к
// ближайшей настоящей границе блоков (в пределах ±15% шага).
function trackLines(e, p, thr) {
  const n = e.length; let x = -1;
  for (let i = 0; i < n; i++) if (e[i] > thr) { x = i; break; }
  if (x < 0) return null;
  const lines = [x - p, x];
  while (x + p < n + p * 0.5) {
    const nx = x + p, a = Math.max(Math.floor(x) + 1, Math.round(nx - p * 0.15)), b = Math.min(n - 1, Math.round(nx + p * 0.15));
    let bi = -1, bv = thr;
    for (let i = a; i <= b; i++) if (e[i] > bv) { bv = e[i]; bi = i; }
    x = bi >= 0 ? bi : nx; lines.push(x);
  }
  return lines;
}
// score = средняя энергия на линиях × доля всей энергии, попавшей на линии
function trackScore(e, total, p, thr) {
  const L = trackLines(e, p, thr); if (!L || L.length < 4) return 0;
  let sum = 0; for (const x of L) { const xi = Math.round(x); if (xi >= 0 && xi < e.length) sum += e[xi]; }
  return (sum / L.length) * (sum / total) / (total / e.length);
}
const peakThr = e => { let s = 0, c = 0; for (const v of e) if (v > 0) { s += v; c++; } return c ? s / c * 0.3 : 0; };
// Кривая «насколько хорошо ложится сетка с шагом p» для одной картинки (кешируется).
function gridCurve(cut) {
  if (cut._curve) return cut._curve;
  const [ex, ey] = edgeProfiles(cut), tx = ex.reduce((a, b) => a + b, 0) || 1, ty = ey.reduce((a, b) => a + b, 0) || 1;
  const pMax = Math.min(64, Math.max(cut.w, cut.h) / 6), ps = [], sc = [], thx = peakThr(ex), thy = peakThr(ey);
  for (let p = 2; p <= pMax; p += P_STEP) { ps.push(p); sc.push(trackScore(ex, tx, p, thx) + trackScore(ey, ty, p, thy)); }
  return cut._curve = { ex, ey, tx, ty, thx, thy, ps, sc };
}
// Половина и четверть настоящего шага тоже ложатся на все границы блоков, поэтому
// из почти равных вариантов берём самый крупный шаг.
function pickP(ps, sc) {
  const mx = Math.max(...sc); let best = ps[0];
  for (let i = 0; i < ps.length; i++) if (sc[i] >= mx * 0.95) best = ps[i];
  return best;
}
// Подстройка прощает неточный шаг (±15%), поэтому настоящий шаг меряем по факту:
// медиана расстояний между соседними найденными границами блоков.
function measuredStep(cuts, p) {
  const d = [];
  for (const cut of cuts) {
    const c = gridCurve(cut);
    for (const [e, th] of [[c.ex, c.thx], [c.ey, c.thy]]) {
      const L = trackLines(e, p, th); if (!L) continue;
      for (let i = 2; i < L.length; i++) { const v = L[i] - L[i - 1]; if (Number.isInteger(L[i]) && Number.isInteger(L[i - 1])) d.push(v); }
    }
  }
  if (d.length < 5) return p;
  d.sort((a, b) => a - b);
  // среднее по средней половине — устойчиво к выбросам и даёт дробный шаг
  const q = d.slice(Math.floor(d.length / 4), Math.ceil(d.length * 3 / 4));
  return q.reduce((a, b) => a + b, 0) / q.length;
}
// Общий шаг для всех картинок персонажа: в одном чате ChatGPT он одинаковый.
function globalGridP(cuts) {
  const acc = new Map();
  for (const cut of cuts) {
    const c = gridCurve(cut), mx = Math.max(...c.sc) || 1;
    c.ps.forEach((p, i) => { const k = Math.round(p / P_STEP); acc.set(k, (acc.get(k) || 0) + c.sc[i] / mx); });
  }
  const keys = [...acc.keys()].sort((a, b) => a - b);
  let p = pickP(keys.map(k => k * P_STEP), keys.map(k => acc.get(k)));
  for (let i = 0; i < 3; i++) p = measuredStep(cuts, p);
  return p;
}
// Уточняем шаг для конкретного кадра в пределах ±10% от общего и находим сдвиг сетки.
function gridFor(cut, p0, exact) {
  const c = gridCurve(cut); let p = p0;
  if (!exact) {
    // Общий шаг — только подсказка: кадры из разных генераций бывают разного масштаба.
    // Если для этой картинки общий шаг ложится заметно хуже её собственного, берём свой.
    const at = q => c.sc[Math.max(0, Math.min(c.sc.length - 1, Math.round((q - 2) / P_STEP)))];
    let own = pickP(c.ps, c.sc); for (let i = 0; i < 3; i++) own = measuredStep([cut], own);
    p = p0 && at(p0) >= at(own) * 0.8 ? measuredStep([cut], p0) : own;
  }
  return { p, lx: trackLines(c.ex, p, c.thx) || [0, cut.w], ly: trackLines(c.ey, p, c.thy) || [0, cut.h] };
}
function gridSample(cut, g) {
  const { w, h, data: d } = cut, lx = g.lx, ly = g.ly, cols = lx.length - 1, rows = ly.length - 1;
  const img = new ImageData(cols, rows), od = img.data, bucket = new Map();
  for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
    const cx = (lx[i] + lx[i + 1]) / 2, cy = (ly[j] + ly[j + 1]) / 2;
    const rx = Math.max(0.5, (lx[i + 1] - lx[i]) * 0.3), ry = Math.max(0.5, (ly[j + 1] - ly[j]) * 0.3);
    const xa = Math.max(0, Math.floor(cx - rx)), xb = Math.min(w, Math.ceil(cx + rx)), ya = Math.max(0, Math.floor(cy - ry)), yb = Math.min(h, Math.ceil(cy + ry));
    let cnt = 0, op = 0; bucket.clear();
    for (let y = ya; y < yb; y++) for (let x = xa; x < xb; x++) {
      const k = (y * w + x) * 4; cnt++; if (d[k + 3] < 128) continue; op++;
      const key = (d[k] >> 3) << 10 | (d[k + 1] >> 3) << 5 | (d[k + 2] >> 3);
      let e = bucket.get(key); if (!e) bucket.set(key, e = [0, 0, 0, 0]); e[0]++; e[1] += d[k]; e[2] += d[k + 1]; e[3] += d[k + 2];
    }
    if (!cnt || op * 2 < cnt) continue;
    let b = null; for (const e of bucket.values()) if (!b || e[0] > b[0]) b = e;
    const o = (j * cols + i) * 4; od[o] = b[1] / b[0]; od[o + 1] = b[2] / b[0]; od[o + 2] = b[3] / b[0]; od[o + 3] = 255;
  }
  // обрезаем пустые края
  let mx = cols, my = rows, Mx = -1, My = -1;
  for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) if (od[(j * cols + i) * 4 + 3]) { mx = Math.min(mx, i); Mx = Math.max(Mx, i); my = Math.min(my, j); My = Math.max(My, j); }
  if (Mx < 0) return { img, w: cols, h: rows };
  const tw = Mx - mx + 1, th = My - my + 1, t = new ImageData(tw, th);
  for (let j = 0; j < th; j++) t.data.set(od.subarray(((j + my) * cols + mx) * 4, ((j + my) * cols + mx + tw) * 4), j * tw * 4);
  return { img: t, w: tw, h: th };
}
function nativeSprite(cut, p0, exact) {
  const key = p0.toFixed(3) + (exact ? '!' : '');
  if (cut._nkey !== key) { const g = gridFor(cut, p0, exact); cut._native = gridSample(cut, g); cut._native.grid = g.p; cut._nkey = key; }
  const s = copyCut({ data: cut._native.img.data, w: cut._native.w, h: cut._native.h });
  s.grid = cut._native.grid; return s;
}
// Промежутки между кадрами заметно шире, чем внутри фигуры (лук отдельно от тела,
// отлетевшая стрела). Ищем самый большой скачок среди отсортированных промежутков
// и склеиваем всё, что меньше него.
function mergeInnerGaps(segs) {
  if (segs.length < 3) return segs;
  const gaps = segs.slice(1).map((sg, i) => sg[0] - segs[i][1]);
  const sorted = [...gaps].sort((p, q) => p - q);
  let best = 0, thr = -1;
  for (let i = 0; i < sorted.length - 1; i++) { const r = (sorted[i + 1] + 1) / (sorted[i] + 1); if (r > best) { best = r; thr = sorted[i]; } }
  if (best < 1.8) return segs;
  const out = [segs[0].slice()];
  for (let i = 1; i < segs.length; i++) { if (gaps[i - 1] <= thr) out[out.length - 1][1] = segs[i][1]; else out.push(segs[i].slice()); }
  return out;
}
const toI16 = d => { const o = new Int16Array(d.length); for (let i = 0; i < d.length; i++) { const s = Math.max(-1, Math.min(1, d[i])); o[i] = s < 0 ? s * 0x8000 : s * 0x7fff; } return o; };
function encodeWav(buf) {
  const ch = Math.min(2, buf.numberOfChannels), sr = buf.sampleRate, n = buf.length, ab = new ArrayBuffer(44 + n * ch * 2), v = new DataView(ab);
  const w = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  w(0, 'RIFF'); v.setUint32(4, 36 + n * ch * 2, true); w(8, 'WAVE'); w(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true);
  v.setUint16(22, ch, true); v.setUint32(24, sr, true); v.setUint32(28, sr * ch * 2, true); v.setUint16(32, ch * 2, true); v.setUint16(34, 16, true);
  w(36, 'data'); v.setUint32(40, n * ch * 2, true);
  const chans = [...Array(ch)].map((_, c) => toI16(buf.getChannelData(c))); let o = 44;
  for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++) { v.setInt16(o, chans[c][i], true); o += 2; }
  return new Blob([ab], { type: 'audio/wav' });
}
const EDIT_DEFAULT = { start: 0, end: 0, gain: 0, fadeIn: 0, fadeOut: 0, normalize: false };
const isDefaultEdit = e => !e || Object.keys(EDIT_DEFAULT).every(k => (e[k] ?? EDIT_DEFAULT[k]) === EDIT_DEFAULT[k]);
function fmtJson(v) {
  if (Array.isArray(v)) return '[' + v.map(fmtJson).join(', ') + ']';
  if (v && typeof v === 'object') return '{' + Object.entries(v).map(([k, x]) => JSON.stringify(k) + ': ' + fmtJson(x)).join(', ') + '}';
  return JSON.stringify(v);
}
// ---- Godot / repository text formats ----

// A SpriteFrames .tres in the shape tools/art/build_elian_frames.py writes: one
// texture per animation strip, an AtlasTexture per cell, per-frame durations.
// anims: [{name, fps, loop, texPath, texId, ids, durations}]
function spriteFramesTres(anims, W, H) {
  const ext = [], subs = [], blocks = [];
  for (const a of anims) {
    ext.push(`[ext_resource type="Texture2D" path="${a.texPath}" id="${a.texId}"]`);
    a.ids.forEach((id, i) => subs.push(`[sub_resource type="AtlasTexture" id="${id}"]\natlas = ExtResource("${a.texId}")\nregion = Rect2(${i * W}, 0, ${W}, ${H})`));
    const frames = a.ids.map((id, i) => `{\n"duration": ${(+(a.durations?.[i] ?? 1)).toFixed(1)},\n"texture": SubResource("${id}")\n}`);
    blocks.push(`{\n"frames": [${frames.join(', ')}],\n"loop": ${a.loop ? 'true' : 'false'},\n"name": &"${a.name}",\n"speed": ${(+a.fps || 8).toFixed(1)}\n}`);
  }
  return `[gd_resource type="SpriteFrames" load_steps=${ext.length + subs.length + 1} format=3]\n\n${ext.join('\n')}\n\n${subs.join('\n\n')}\n\n[resource]\nanimations = [${blocks.join(', ')}]\n`;
}

// localization/strings.csv: header line bare, every row "key,"quoted","quoted"...
function csvParse(text) {
  const rows = []; let row = [], f = '', q = false, i = 0;
  for (; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c; }
    else if (c === '"') { q = true; if (!row.length && f === '') row.quoted = true; }  // keep how the key was written
    else if (c === ',') { row.push(f); f = ''; }
    else if (c === '\n') { row.push(f); rows.push(row); row = []; f = ''; }
    else if (c !== '\r') f += c;
  }
  if (f !== '' || row.length) { row.push(f); rows.push(row); }
  return rows;
}
function csvStringify(rows) {
  const q = v => '"' + String(v ?? '').replace(/"/g, '""') + '"';
  return rows.map((r, i) => i === 0 ? r.join(',') : [r.quoted || /[",\n]/.test(r[0]) ? q(r[0]) : r[0], ...r.slice(1).map(q)].join(',')).join('\n') + '\n';
}
// updates: {KEY: {en, ru, ...}}. A new key gets every column; a locale nobody
// wrote yet borrows the English line (the validator wants all four filled).
function mergeStrings(text, updates) {
  const rows = csvParse(text), head = rows[0], at = new Map(rows.map((r, i) => [r[0], i]));
  const en = head.indexOf('en');
  for (const [key, vals] of Object.entries(updates)) {
    let i = at.get(key);
    if (i === undefined) { rows.push([key, ...head.slice(1).map(() => '')]); i = rows.length - 1; at.set(key, i); }
    const r = rows[i];
    head.forEach((loc, j) => { if (j && vals[loc] != null && vals[loc] !== '') r[j] = vals[loc]; });
    head.forEach((loc, j) => { if (j && r[j] === '') r[j] = r[en] || vals.ru || ''; });
  }
  return csvStringify(rows);
}
// data/dialogues/*.json is laid out by hand (some nodes one per line, some
// expanded), so a dialogue is written back by replacing only its own object in
// the file, in the style it had; every other byte stays as it was.
function jsonSpan(text, at) {  // [start, end) of the {...} or [...] opening at index `at`
  let depth = 0, str = false;
  for (let i = at; i < text.length; i++) {
    const c = text[i];
    if (str) { if (c === '\\') i++; else if (c === '"') str = false; continue; }
    if (c === '"') str = true;
    else if (c === '{' || c === '[') depth++;
    else if (c === '}' || c === ']') { depth--; if (!depth) return [at, i + 1]; }
  }
  return null;
}
function dialogueSpan(text, id) {
  const m = new RegExp(`"id":\\s*${JSON.stringify(id).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`).exec(text);
  if (!m) return null;
  let depth = 0, str = false, open = -1;
  for (let i = m.index; i >= 0; i--) {  // the nearest unclosed '{' before the id
    const c = text[i];
    if (c === '}') depth++;
    else if (c === '{') { if (!depth) { open = i; break; } depth--; }
  }
  return open < 0 ? null : jsonSpan(text, open);
}
function fmtDialogue(d, compact, indent) {
  const pad = ' '.repeat(indent), keys = Object.keys(d).filter(k => k !== '_file');
  if (!compact) return JSON.stringify(Object.fromEntries(keys.map(k => [k, d[k]])), null, 2).split('\n').join('\n' + pad);
  const lines = keys.map(k => k !== 'nodes' ? `${pad}  ${JSON.stringify(k)}: ${fmtJson(d[k])}`
    : `${pad}  "nodes": {\n${Object.entries(d.nodes).map(([n, v]) => `${pad}    ${JSON.stringify(n)}: ${fmtJson(v)}`).join(',\n')}\n${pad}  }`);
  return `{\n${lines.join(',\n')}\n${pad}}`;
}
function mergeDialogueFile(text, dialogue) {
  const clean = JSON.parse(JSON.stringify(dialogue)); delete clean._file;
  if (!text) return fmtDialogue(clean, true, 0) + '\n';
  const span = dialogueSpan(text, clean.id);
  if (!span) {  // a new dialogue for an existing file: append to the list
    const cur = JSON.parse(text), list = Array.isArray(cur) ? cur : [cur];
    return JSON.stringify([...list, clean], null, 2) + '\n';
  }
  const old = text.slice(span[0], span[1]), lineStart = text.lastIndexOf('\n', span[0]) + 1;
  const compact = /\n\s+"[^"]+": \{"[^\n]*\},?\n/.test(old);
  return text.slice(0, span[0]) + fmtDialogue(clean, compact, span[0] - lineStart) + text.slice(span[1]);
}
// data/backdrops.json: a still rule for each new picture, written in by text so
// the hand-laid zones of every other picture keep their layout.
function insertBackdropRules(text, rules) {
  const have = new Set(Object.keys(JSON.parse(text).rooms || {}));
  const lines = Object.entries(rules).filter(([n]) => !have.has(n)).map(([n, fam]) => `    ${JSON.stringify(n)}: {"family": ${JSON.stringify(fam)}, "zones": []},`);
  if (!lines.length) return text;
  return text.replace(/("rooms":\s*\{\n)/, `$1${lines.join('\n')}\n`);
}
// An image model's edit drifts: a few pixels aside, a percent or two bigger, a shade
// warmer (ref2game's variantfix.py). These put an edit back onto its base using only
// the parts that were meant to stay (keep(x, y)), so a repainted seam meets its sides.
// Images are {data: RGBA, w, h} of the same size.
function lumOf(img) { const l = new Float32Array(img.w * img.h); for (let i = 0; i < l.length; i++) l[i] = img.data[i * 4] * 0.299 + img.data[i * 4 + 1] * 0.587 + img.data[i * 4 + 2] * 0.114; return l; }
function shrink(l, w, h, f) {
  const W = Math.floor(w / f), H = Math.floor(h / f), o = new Float32Array(W * H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { let s = 0; for (let j = 0; j < f; j++) for (let i = 0; i < f; i++) s += l[(y * f + j) * w + x * f + i]; o[y * W + x] = s / (f * f); }
  return { l: o, w: W, h: H };
}
// the edit scaled by sc about the centre and moved by (dx, dy), read at (x, y): nearest neighbour
const warpAt = (w, h, sc, dx, dy) => (x, y) => [Math.round((x - dx - w / 2) / sc + w / 2), Math.round((y - dy - h / 2) / sc + h / 2)];
function warpError(base, edit, w, h, sc, dx, dy, keep, f) {
  const at = warpAt(w, h, sc, dx, dy); let e = 0, n = 0;
  for (let y = 0; y < h; y += 1) for (let x = 0; x < w; x += 1) {
    if (!keep(x * f, y * f)) continue;
    const [sx, sy] = at(x, y); if (sx < 0 || sy < 0 || sx >= w || sy >= h) { e += 64; n++; continue; }
    e += Math.abs(base[y * w + x] - edit[sy * w + sx]); n++;
  }
  return n ? e / n : Infinity;
}
function alignEdit(base, edit, keep, { scales = [0.97, 0.98, 0.99, 1, 1.01, 1.02, 1.03], reach = 16 } = {}) {
  const f = 4, b4 = shrink(lumOf(base), base.w, base.h, f), e4 = shrink(lumOf(edit), edit.w, edit.h, f);
  let best = { err: Infinity, sc: 1, dx: 0, dy: 0 };
  const r4 = Math.ceil(reach / f);
  for (const sc of scales) for (let dy = -r4; dy <= r4; dy++) for (let dx = -r4; dx <= r4; dx++) {
    const err = warpError(b4.l, e4.l, b4.w, b4.h, sc, dx, dy, keep, f);
    if (err < best.err) best = { err, sc, dx: dx * f, dy: dy * f };
  }
  // refine at full size around the coarse answer
  const bl = lumOf(base), el = lumOf(edit), c = { ...best }; best = { ...c, err: Infinity };
  const r = f / 2 + 1;   // the coarse step was f: the answer lies within half of it, give or take its rounding
  for (let dy = c.dy - r; dy <= c.dy + r; dy++) for (let dx = c.dx - r; dx <= c.dx + r; dx++) {
    const err = warpError(bl, el, base.w, base.h, c.sc, dx, dy, keep, 1);
    if (err < best.err) best = { err, sc: c.sc, dx, dy };
  }
  return best;
}
function warpEdit(edit, { sc, dx, dy }) {
  const { w, h } = edit, out = new Uint8ClampedArray(w * h * 4), at = warpAt(w, h, sc, dx, dy);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let [sx, sy] = at(x, y); sx = Math.min(w - 1, Math.max(0, sx)); sy = Math.min(h - 1, Math.max(0, sy));
    out.set(edit.data.subarray((sy * w + sx) * 4, (sy * w + sx) * 4 + 4), (y * w + x) * 4);
  }
  return { data: out, w, h };
}
// each channel's mean and spread brought to the base's, measured where both are meant to agree
function matchColours(base, img, keep) {
  const out = new Uint8ClampedArray(img.data), stats = [];
  for (let ch = 0; ch < 3; ch++) {
    let n = 0, sb = 0, si = 0, qb = 0, qi = 0;
    for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) {
      if (!keep(x, y)) continue; const i = (y * img.w + x) * 4 + ch, b = base.data[i], v = img.data[i];
      n++; sb += b; si += v; qb += b * b; qi += v * v;
    }
    if (!n) return { data: out, w: img.w, h: img.h };
    const mb = sb / n, mi = si / n, db = Math.sqrt(Math.max(0, qb / n - mb * mb)), di = Math.sqrt(Math.max(0, qi / n - mi * mi)) || 1;
    for (let i = ch; i < out.length; i += 4) out[i] = (img.data[i] - mi) / di * db + mb;
    stats.push([mi - mb, di / (db || 1)]);
  }
  return { data: out, w: img.w, h: img.h, stats };
}
// data/enemies and data/abilities are Python's json.dumps(indent=2): "6.0" stays a float there,
// which JSON.parse would forget. So an edit changes only the values it touches, in place,
// and a new key goes in written the way Python would write it (jsonSpans, patchJson).
function jsonSpans(text) {
  let i = 0;
  const ws = () => { while (i < text.length && ' \t\r\n'.includes(text[i])) i++; };
  const value = () => {
    ws(); const start = i, c = text[i];
    if (c === '{') {
      i++; const members = []; ws();
      if (text[i] === '}') { i++; return { type: 'object', start, end: i, members }; }
      for (;;) {
        ws(); const keyStart = i, key = JSON.parse(text.slice(i, (str(), i))); ws(); i++;   // the ':'
        const v = value(); members.push({ key, keyStart, value: v }); ws();
        if (text[i] === ',') { i++; continue; }
        i++; return { type: 'object', start, end: i, members };
      }
    }
    if (c === '[') {
      i++; const items = []; ws();
      if (text[i] === ']') { i++; return { type: 'array', start, end: i, items }; }
      for (;;) { items.push(value()); ws(); if (text[i] === ',') { i++; continue; } i++; return { type: 'array', start, end: i, items }; }
    }
    if (c === '"') { str(); return { type: 'string', start, end: i }; }
    while (i < text.length && !',]} \t\r\n'.includes(text[i])) i++;
    return { type: 'literal', start, end: i, raw: text.slice(start, i) };
  };
  const str = () => { i++; while (text[i] !== '"') i += text[i] === '\\' ? 2 : 1; i++; };
  return value();
}
// a value written the way Python's json.dumps(indent=2, ensure_ascii=False) writes it, at depth `level`
function pyJson(v, level = 0, float = false) {
  if (v && v.__raw !== undefined) return v.__raw;   // text already written for this place (setJsonList)
  const pad = n => '  '.repeat(n);
  if (Array.isArray(v)) return v.length ? '[\n' + v.map(x => pad(level + 1) + pyJson(x, level + 1)).join(',\n') + '\n' + pad(level) + ']' : '[]';
  if (v && typeof v === 'object') { const e = Object.entries(v).filter(([, x]) => x !== undefined); return e.length ? '{\n' + e.map(([k, x]) => pad(level + 1) + JSON.stringify(k) + ': ' + pyJson(x, level + 1)).join(',\n') + '\n' + pad(level) + '}' : '{}'; }
  if (typeof v === 'number' && float && Number.isInteger(v)) return v.toFixed(1);
  return JSON.stringify(v);
}
function jsonAt(node, path) {
  for (const k of path) node = node.type === 'object' ? node.members.find(m => m.key === k)?.value : node.items?.[k];
  return node;
}
// set (or, with undefined, remove) keys of the object at `path`; everything else stays as it was
function patchJson(text, path, changes) {
  // removals one at a time, each on the text the last one left: neighbours share their commas
  for (const [k, v] of Object.entries(changes)) if (v === undefined) text = patchJsonOnce(text, path, { [k]: undefined });
  const set = Object.fromEntries(Object.entries(changes).filter(([, v]) => v !== undefined));
  return Object.keys(set).length ? patchJsonOnce(text, path, set) : text;
}
function patchJsonOnce(text, path, changes) {
  const edits = [], obj = jsonAt(jsonSpans(text), path);
  if (!obj || obj.type !== 'object') throw new Error('no object at ' + JSON.stringify(path));
  const lineStart = at => text.lastIndexOf('\n', at - 1) + 1;
  const level = m => Math.round((m.keyStart - lineStart(m.keyStart)) / 2);
  const adds = [];
  for (const [key, v] of Object.entries(changes)) {
    const k = obj.members.findIndex(m => m.key === key), m = obj.members[k];
    if (v === undefined) {
      if (!m) continue;
      // the member's line, and the comma before it if it was the last one
      const from = k === obj.members.length - 1 && k > 0 ? obj.members[k - 1].value.end : lineStart(m.keyStart) - 1;
      const to = k === obj.members.length - 1 ? m.value.end : obj.members[k + 1].keyStart - (obj.members[k + 1].keyStart - lineStart(obj.members[k + 1].keyStart)) - 1;
      edits.push([from, to, '']);
    } else if (m) {
      const was = m.value.type === 'literal' && /[.eE]/.test(m.value.raw);
      const out = pyJson(v, level(m), was);
      if (text.slice(m.value.start, m.value.end) !== out && JSON.stringify(JSON.parse(text.slice(m.value.start, m.value.end))) !== JSON.stringify(v)) edits.push([m.value.start, m.value.end, out]);
    } else adds.push([key, v]);
  }
  if (adds.length) {
    const last = obj.members.at(-1), lvl = last ? level(last) : jsonAt.depth ?? 1, pad = '  '.repeat(lvl);
    const body = adds.map(([k, v]) => pad + JSON.stringify(k) + ': ' + pyJson(v, lvl)).join(',\n');
    if (last) edits.push([last.value.end, last.value.end, ',\n' + body]);
    else edits.push([obj.start + 1, obj.end - 1, '\n' + body + '\n' + '  '.repeat(Math.max(0, lvl - 1))]);
  }
  edits.sort((a, b) => b[0] - a[0]);
  for (const [a, b, t] of edits) text = text.slice(0, a) + t + text.slice(b);
  return text;
}
// A list rewritten whole, but each item it keeps as the very text it was (a "6.0" stays a "6.0"):
// items are {raw, level} taken from some file by jsonItems, or plain values written anew.
// drop: keys of the same object to remove (an enemy's single "attack" that became a list).
function jsonItems(text, path) {
  const node = jsonAt(jsonSpans(text), path);
  if (!node) return [];
  const one = n => { const raw = text.slice(n.start, n.end), last = raw.lastIndexOf('\n');
    return { raw, level: last < 0 ? 0 : Math.round((raw.length - last - 2) / 2) }; };   // the closing bracket's indent
  return node.type === 'array' ? node.items.map(one) : [one(node)];
}
function reindent(raw, from, to) {
  const d = to - from; if (!d) return raw;
  return raw.split('\n').map((l, i) => i === 0 ? l : d > 0 ? '  '.repeat(d) + l : l.slice(-2 * d)).join('\n');
}
function setJsonList(text, path, key, items, drop = []) {
  const obj = jsonAt(jsonSpans(text), path);
  if (!obj || obj.type !== 'object') throw new Error('no object at ' + JSON.stringify(path));
  const lineStart = at => text.lastIndexOf('\n', at - 1) + 1, m = obj.members.find(x => x.key === key) || obj.members.at(-1);
  const lvl = m ? Math.round((m.keyStart - lineStart(m.keyStart)) / 2) : path.length + 1, pad = n => '  '.repeat(n);
  const body = items.map(it => pad(lvl + 1) + (it && it.raw !== undefined ? reindent(it.raw, it.level, lvl + 1) : pyJson(it, lvl + 1))).join(',\n');
  text = patchJsonOnce(text, path, { [key]: { __raw: items.length ? '[\n' + body + '\n' + pad(lvl) + ']' : '[]' } });
  for (const k of drop) text = patchJson(text, path, { [k]: undefined });
  return text;
}
// One picture's rule in data/backdrops.json, rewritten in the file's own style
// (a zone a line, floats keep their ".0", the other rules untouched); a key it
// does not have yet goes at the top of "rooms". rule = {family, flame?, flame_floor?, zones}.
const LIFE_FLOATS = new Set(['strength', 'speed', 'floor', 'flame', 'flame_floor']);
function lifeValue(k, v) {
  if (Array.isArray(v)) return '[' + v.map(x => lifeValue('', x)).join(', ') + ']';
  if (LIFE_FLOATS.has(k) && typeof v === 'number' && Number.isInteger(v)) return v.toFixed(1);
  return JSON.stringify(v);
}
function lifeObject(o) {
  return '{' + Object.entries(o).filter(([, v]) => v !== undefined).map(([k, v]) => JSON.stringify(k) + ': ' + lifeValue(k, v)).join(', ') + '}';
}
function lifeEntry(key, rule) {
  const { zones = [], ...head } = rule;
  const top = lifeObject(head).slice(0, -1);
  const lead = `    ${JSON.stringify(key)}: ${top}${top.length > 1 ? ', ' : ''}"zones": `;
  if (!zones.length) return lead + '[]}';
  return lead + '[\n' + zones.map(z => '      ' + lifeObject(z)).join(',\n') + '\n    ]}';
}
function setBackdropRule(text, key, rule) {
  const at = text.indexOf(`\n    ${JSON.stringify(key)}: {`, text.indexOf('"rooms": {'));   // a family may share the name
  if (at < 0) return text.replace(/("rooms":\s*\{\n)/, `$1${lifeEntry(key, rule)},\n`);
  const start = at + 1;
  // the entry ends where the next rule (or the end of "rooms") begins
  const next = text.slice(start + 1).search(/\n(    "[^"]+": \{|  \})/);
  let end = start + 1 + next;
  const comma = text[end - 1] === ',';
  if (comma) end -= 1;
  return text.slice(0, start) + lifeEntry(key, rule) + text.slice(end);
}
// data/cutscenes writes these as floats ("time": 1.0; a shake's strength is whole); JSON.parse forgets the ".0"
const CUTSCENE_FLOATS = new Set(['time', 'zoom', 'strength', 'to', 'drift', 'drift_time']);
function fmtStep(s) {
  return '{' + Object.entries(s).map(([k, v]) => JSON.stringify(k) + ': ' +
    (CUTSCENE_FLOATS.has(k) && !(s.do === 'shake' && k === 'strength') && typeof v === 'number' && Number.isInteger(v) ? v.toFixed(1) : fmtJson(v))).join(', ') + '}';
}
function cutsceneJson(id, steps) {
  return `{\n  "id": ${JSON.stringify(id)},\n  "steps": [\n${steps.map(s => '    ' + fmtStep(s)).join(',\n')}\n  ]\n}\n`;
}

// Where one changed take of a sound goes so that CI stays green: a file a
// generator writes (tools/check_generators.py) is never rewritten — a numbered
// take beside it wins in Audio._clip, and dropping a generated take is allowed.
// take: {stem, orig}, entry: {cat, name, locale, takes:[{stem, ext}]}
function planSoundWrite(entry, take, isGenerated) {
  const dir = entry.cat === 'voice' ? `assets/audio/voice/${entry.locale}/` : `assets/audio/${entry.cat}/`;
  const ext = entry.cat === 'sfx' ? 'wav' : 'mp3';
  const files = (entry.takes || []).filter(t => t.ext);
  const sameStem = files.filter(t => t.stem === take.stem).map(t => `${dir}${t.stem}.${t.ext}`);
  if (entry.cat !== 'sfx') {
    const path = `${dir}${take.stem}.${ext}`;
    if (isGenerated(path) || sameStem.some(isGenerated)) return { error: 'generated' };
    return { write: path, delete: sameStem.filter(p => p !== path) };
  }
  const path = `${dir}${take.stem}.wav`;
  if (!sameStem.some(isGenerated) && !isGenerated(path)) return { write: path, delete: sameStem.filter(p => p !== path) };
  // a generated take: write the next free number and drop the generated one if it is a take
  const used = new Set(files.map(t => t.stem));
  let n = 1; while (used.has(`${entry.name}_${n}`)) n++;
  const numbered = /_\d+$/.test(take.stem) && take.stem !== entry.name;
  return { write: `${dir}${entry.name}_${n}.wav`, delete: numbered ? sameStem : [], renamed: `${entry.name}_${n}` };
}

// ---- undo snapshots: long strings (pictures) are kept once, by reference ----
function snapshot(obj, table) {
  return JSON.stringify(obj, (k, v) => {
    if (typeof v === 'string' && v.length > 2048) { let i = table.ids.get(v); if (i === undefined) { i = table.list.length; table.list.push(v); table.ids.set(v, i); } return '\u0000' + i; }
    return v;
  });
}
function unsnapshot(text, table) {
  return JSON.parse(text, (k, v) => typeof v === 'string' && v.charCodeAt(0) === 0 ? table.list[+v.slice(1)] : v);
}

// ---- hand touch-ups over a processed frame: {"x,y": [r,g,b,a]} ----
function applyPatch(data, w, h, patch) {
  for (const [k, c] of Object.entries(patch || {})) {
    const [x, y] = k.split(',').map(Number); if (x < 0 || y < 0 || x >= w || y >= h) continue;
    const i = (y * w + x) * 4; data[i] = c[0]; data[i + 1] = c[1]; data[i + 2] = c[2]; data[i + 3] = c[3];
  }
}

// ---- keeping her work when the game (or a shared project) brings a newer copy ----

// The part of a project that is the work itself, not where the editor stood.
function contentKey(o) {
  if (!o) return '';
  const pick = o.kind === 'bg' ? ['width', 'height', 'layers', 'images', 'ambient']
    : o.kind === 'cutscene' ? ['steps', 'dialogues', 'strings', 'images']
    : ['animations', 'settings', 'reference', 'description'];
  return JSON.stringify(pick.map(k => o[k] ?? null), (k, v) => k === 'busy' ? undefined : v);
}
// local: what this browser has (dirty = edited here, pendingPr = sent and not yet
// in the game, base = the game revision it was taken from); incoming: the game's
// or a shared copy (rev = revision). -> 'take' | 'keep' | 'conflict'
function mergeDecision(local, incoming) {
  if (!local) return 'take';
  if (local.pendingPr) return 'keep';  // her change is on its way; main does not have it yet
  if (!local.dirty || contentKey(local) === contentKey(incoming)) return 'take';
  if (local.base != null && incoming.rev != null && local.base !== incoming.rev) return 'conflict';
  return 'keep';
}

// One line for a pull request the studio opened. checks: {total, failed, pending}.
// review: the latest review state ('CHANGES_REQUESTED', 'APPROVED', …).
function prStatus({ state, merged, checks, deployed, review }) {
  if (merged) return deployed ? { key: 'live', label: 'в игре', tone: 'ok' } : { key: 'merged', label: 'влито, публикуется…', tone: 'wait' };
  if (state === 'closed') return { key: 'closed', label: 'закрыто без вливания', tone: 'bad' };
  if (review === 'CHANGES_REQUESTED') return { key: 'changes', label: 'просят исправить', tone: 'bad' };
  if (checks?.failed) return { key: 'failed', label: 'проверка нашла ошибки', tone: 'bad' };
  if (checks?.pending || !checks?.total) return { key: 'checking', label: 'на проверке', tone: 'wait' };
  return { key: 'ready', label: 'проверено, ждёт владельца', tone: 'ok' };
}

// ---- placing in rooms: tools/rooms/studio_rooms.json, the room generator's input ----

// The floor under a point, by the rule check_reach (tools/rooms/painted_rooms.py)
// uses: a surface [x, top, width] reaching the point's x (±8 px) whose top is
// below its feet; an enemy's origin stands 12 px above that top.
function snapToSurface(surfaces, x, y) {
  let best = null;
  for (const [sx, sy, sw] of surfaces || []) if (sx - 8 <= x && x <= sx + sw + 8 && sy >= y + 12 - 4 && (!best || sy < best[1])) best = [sx, sy, sw];
  return best ? { x: Math.round(x), y: Math.round(best[1] - 12) } : null;
}
// change: {room, spawn: [id, x, y]} or {room, intro_cutscene | outro_cutscene: id}.
// An enemy is placed once per room (placing it again moves it).
function mergeStudioRooms(text, change) {
  const all = text ? JSON.parse(text) : {}, r = all[change.room] ||= {};
  if (change.spawn) { r.spawns = (r.spawns || []).filter(s => s[0] !== change.spawn[0]); r.spawns.push(change.spawn); }
  for (const k of ['intro_cutscene', 'outro_cutscene']) if (change[k] !== undefined) r[k] = change[k];
  const sorted = Object.fromEntries(Object.keys(all).sort().map(k => [k, all[k]]));
  return JSON.stringify(sorted, null, 2).replace(/\[\n\s+("[^"]*"),\n\s+(-?[\d.]+),\n\s+(-?[\d.]+)\n\s+\]/g, '[$1, $2, $3]') + '\n';
}

// ---- prompts for an image model (ChatGPT in the browser, or the API) ----
//
// What an image model does with a sprite request, observed: it ignores an exact
// height or block size (asked for 44 px in 16×16 blocks, it drew 87 and 55), and
// over a long chat it drifts the character. So the prompt never asks for a size —
// the studio fixes scale in code (grid recovery + "fit to height") — every
// attached image is named with the one thing it is for, and a frame after the
// first is an edit of the approved one, not a new drawing.
const REF_ROLES = {
  design: 'the CHARACTER DESIGN: copy its proportions, outfit, colours, hair, weapon and silhouette exactly',
  style: 'STYLE AND SCALE ONLY (the game\'s hero): match its pixel size, outline, palette darkness and how much detail a body this small carries. Do NOT draw this knight, do not copy his armour, cloak or sword',
  approved: 'the APPROVED FRAME of this animation: the same character at the right scale',
};
// refs: the roles attached, in the order they are attached (['design', 'style', 'approved']).
function refLines(refs) {
  if (!refs.length) return [];
  return ['Attached images, in order:', ...refs.map((r, i) => `Image ${i + 1}: ${REF_ROLES[r]}.`)];
}
const PIXEL_CLAUSE = 'Pixel art: crisp square pixels on one even grid, hard edges, no anti-aliasing, no blur, no gradients, a small palette. Chunky low-resolution pixels, not fine detail. Do not aim for any exact pixel count: the game rescales the picture itself.';
const bgLine = transparent => transparent
  ? 'Transparent background, no floor, no shadow.'
  : 'Background: solid flat pure magenta (#FF00FF), perfectly uniform, no gradient, no floor, no shadow.';
// o: { kind: 'frame' | 'strip', description, style, view, anim: {name, notes, poses: [...]},
//      index (frame), refs (roles attached), transparent }
// A frame with 'approved' among its refs is an edit of that frame.
function spritePrompt(o) {
  const refs = o.refs || [], img = r => `Image ${refs.indexOf(r) + 1}`;
  const who = o.description || (refs.includes('design') ? `the character in ${img('design')}` : 'the character');
  const a = o.anim, poses = a.poses || [], name = `"${a.name}"${a.notes ? ` (${a.notes})` : ''}`;
  const out = refLines(refs);
  if (o.kind === 'strip') {
    out.push(
      `Create a sprite strip: exactly ${poses.length} animation frames of the SAME character in ONE horizontal row, left to right.`,
      `Character: ${who}.`, `Style: ${o.style}.`,
      `View: ${o.view}, full body in every frame. All frames have the same scale, the feet stand on the same ground line, frames are evenly spaced with clear empty gaps between them and nothing overlaps.`,
      PIXEL_CLAUSE,
      `Animation ${name}:`, ...poses.map((p, i) => `${i + 1}. ${p || 'next pose of the motion'}`),
      bgLine(o.transparent),
      'No text, no numbers, no labels, no grid lines, no frame borders, no motion blur.');
  } else if (refs.includes('approved')) {
    out.push(
      `Edit ${img('approved')}: change ONLY the pose, to frame ${o.index + 1} of ${poses.length} of the animation ${name}: ${poses[o.index] || 'the next pose of the motion'}.`,
      'Keep everything else identical: the same character, outfit and colours, the same size in the picture, the same pixel size and palette, the feet on the same ground line, the same background. Do not redraw the character from scratch and do not change the camera.',
      'Only one character. No text, no labels, no frame border, no motion blur, no effects.');
  } else {
    out.push(
      'Create ONE frame of a 2D game sprite animation.',
      `Character: ${who}.`, `Style: ${o.style}.`,
      `View: ${o.view}, full body visible, centered, the figure about two thirds of the picture's height, feet on a ground line near the bottom.`,
      PIXEL_CLAUSE,
      `Animation ${name}, frame ${o.index + 1} of ${poses.length}: ${poses[o.index] || 'the next pose of the motion'}.`,
      bgLine(o.transparent),
      'Only one character. No text, no labels, no frame border, no motion blur, no effects.');
  }
  return out.join('\n');
}

// ---- the sandbox («Песочница»): what the studio posts to the game (StudioLive) ----

// The animation that plays an enemy's slot: one named like it, or for the attack
// any "attack…"/"shoot…" (the enemy wizard's rule).
function enemySlotFor(anims, slot) {
  return anims.find(a => a.name === slot) || (slot === 'attack' && anims.find(a => /attack|shoot/.test(a.name))) || null;
}
// The post itself; strips: {slot: data URL of a strip of whole cells}.
function liveMessage({ name, base, cell, fps, strips }) {
  return { type: 'ashes-live', name: name || '', extends: base || 'cultist', cell: [+cell[0], +cell[1]], fps: +fps || 8, strips };
}

// ---- checks before a character is sent (the red badge on «→ В игру») ----
//
// What the eye misses in a strip of small frames and the game shows at once:
// a character of the wrong size beside the hero, feet that hop between frames,
// a figure that jumps sideways, a palette that has grown past the game's look,
// and a fringe of the chroma key or soft alpha left round the edges.
const HERO_H = 44;
// Only the cycles that should stand still in place are held to a line and a centre: an attack, a roll,
// a death or a landing moves the body on purpose (the game's own art does).
const STEADY = /^(idle|walk|run|rest)$|поко|ходь|бег/i;
function frameStats(fr) {
  const { data: d, w, h } = fr; let top = h, bottom = -1, cx = 0, cy = 0, n = 0, soft = 0, halo = 0;
  const colours = new Set(), [kh, keySat] = fr.key ? hsv(...fr.key) : [0, 0];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * 4, a = d[i + 3]; if (!a) continue;
    if (a < 255) soft++;
    n++; cx += x; cy += y; if (y < top) top = y; if (y > bottom) bottom = y;
    colours.add(d[i] << 16 | d[i + 1] << 8 | d[i + 2]);
    // the background's colour left on the silhouette's edge: close to the key, or its tint over a dark outline
    if (fr.key) {
      const near = cdist(d[i], d[i + 1], d[i + 2], ...fr.key) < 3 * 70 * 70, [hu, sa] = hsv(d[i], d[i + 1], d[i + 2]), dh = Math.abs(hu - kh);
      if (near || (keySat > 0.5 && sa > 0.45 && Math.min(dh, 360 - dh) < 18)) {
        const clear = (xx, yy) => xx < 0 || yy < 0 || xx >= w || yy >= h || !d[(yy * w + xx) * 4 + 3];
        if (clear(x - 1, y) || clear(x + 1, y) || clear(x, y - 1) || clear(x, y + 1)) halo++;
      }
    }
  }
  if (!n) return null;
  // where the body stands: the centre of its lower 40 % (the legs), which a swung blade or a cape does not drag about
  const from = bottom - Math.round((bottom - top + 1) * 0.4); let lx = 0, ly = 0, ln = 0;
  for (let y = Math.max(top, from); y <= bottom; y++) for (let x = 0; x < w; x++) if (d[(y * w + x) * 4 + 3]) { lx += x; ly += y; ln++; }
  return { height: bottom - top + 1, top, bottom, cx: lx / ln, cy: ly / ln, n, soft, halo, colours };
}
// anims: [{name, loop, frames: [{data, w, h, key}]}]; o: {contentH, palette (the limit she set, 0 = none),
// fit (false: the studio does not scale this one, its height is the game's), flyer (no ground under it)}.
// → [{id, bad, anim, msg}] — bad ones turn the badge red, the rest are said for information.
function artChecks(anims, o = {}) {
  const out = [], CH = +o.contentH || HERO_H, all = new Set();
  const add = (id, bad, anim, msg) => out.push({ id, bad, anim, msg });
  const stats = anims.map(a => ({ a, st: a.frames.map(frameStats) })).filter(x => x.st.some(Boolean));
  // a flyer hovers: its idle's lowest row moves, and nothing of it stands on a line
  const idle = stats.find(x => /^idle$|поко/i.test(x.a.name)) || stats[0];
  const bottoms = s => s.st.filter(Boolean).map(f => f.bottom), spreadOf = s => { const b = bottoms(s); return Math.max(...b) - Math.min(...b); };
  const flyer = !!o.flyer || (!!idle && spreadOf(idle) > 1);
  for (const { a, st } of stats) {
    const ok = st.filter(Boolean);
    for (const s of ok) for (const c of s.colours) all.add(c);
    const hmax = Math.max(...ok.map(s => s.height));
    if (STEADY.test(a.name) && !flyer && ok.length > 1) {
      const spread = spreadOf({ st });
      if (spread > 1) add('feet', true, a.name, `«${a.name}»: ноги не на одной линии — низ гуляет на ${spread} px между кадрами`);
    }
    if (STEADY.test(a.name) && !flyer) {
      const jump = Math.max(4, hmax * 0.2), seq = st.map((s, i) => [s, i]).filter(([s]) => s);
      for (let k = 1; k < seq.length + (a.loop && seq.length > 2 ? 1 : 0); k++) {
        const [p, i] = seq[k - 1], [q, j] = seq[k % seq.length], d = Math.hypot(q.cx - p.cx, q.cy - p.cy);
        if (d > jump) { add('jump', true, a.name, `«${a.name}»: между кадрами ${i + 1} и ${j + 1} персонаж прыгает на ${d.toFixed(0)} px`); break; }
      }
    }
    const halo = ok.reduce((t, s) => t + s.halo, 0), soft = ok.reduce((t, s) => t + s.soft, 0);
    if (halo) add('halo', true, a.name, `«${a.name}»: по краю остался цвет фона (${halo} px) — подними «Допуск фона» или поправь ✎`);
    if (soft) add('soft', true, a.name, `«${a.name}»: полупрозрачные пиксели (${soft}) — в пиксель-арте край или есть, или нет`);
  }
  // height: of the idle (a raised blade in an attack is not the body's height)
  const tall = idle ? Math.max(...idle.st.filter(Boolean).map(f => f.height)) : 0;
  if (tall) {
    if (o.fit !== false && Math.abs(tall - CH) > 2) add('height', true, '', `Рост ${tall} px, а задан ${CH} px — нажми «Сетка пикселей + подогнать рост»`);
    else if (Math.abs(tall - HERO_H) > 2) add('hero', false, '', `Рост ${tall} px — ${tall > HERO_H ? 'выше' : 'ниже'} героя (${HERO_H} px) в ${(tall > HERO_H ? tall / HERO_H : HERO_H / tall).toFixed(1)} раза`);
    else add('hero', false, '', `Рост ${tall} px — как у героя`);
  }
  // the game's own sprites are not strict palettes (the hero has thousands of colours), so only a palette
  // she asked for and did not get is an error; without one the count is said for information
  if (+o.palette > 0 && all.size > +o.palette) add('palette', true, '', `Цветов ${all.size} — больше, чем задано в палитре (${o.palette})`);
  else if (all.size) add('palette', false, '', `Цветов: ${all.size}${+o.palette > 0 ? ` (палитра ${o.palette})` : ' — палитра выключена'}`);
  return out;
}

// ---- editing what a generator draws: overrides (tools/art/studio_overrides.py) ----
//
// A generated picture is never written by the studio. Her edit goes beside the
// generator — her picture whole, a mask of what she changed, a line in
// tools/studio/overrides/overrides.json — and the generator lays it over its
// own picture. The mask must hold only what she changed: the studio's own
// processing does not give back a game sprite pixel for pixel (soft alpha
// becomes hard), so an untouched frame stays out of it.
const OVERRIDE_DIR = 'tools/studio/overrides/';
const overrideFiles = path => ({ edit: OVERRIDE_DIR + path, mask: OVERRIDE_DIR + path.replace(/\.png$/i, '') + '.mask.png' });
// What she changed in a character from the game, slot by slot against what the game has
// (the studio's import of it): a frame replaced or moved is its whole region, a touch-up its pixels.
// anims / orig: [{id, frames: [{id, src, dx, dy, sc, patch, off}], regions: [[res, x, y, w, h]]}]
// → [{res, x, y, w, h, frame, whole, pixels: [[x, y]]}] (pixels in the frame's own cell); throws on what an
// override cannot hold (a frame added past the strip, an animation the game does not have).
function frameEdits(anims, orig) {
  const out = [];
  for (const a of anims) {
    const o = orig.find(x => x.id === a.id);
    if (!o) throw new Error(`Анимации «${a.name}» нет у этого персонажа в игре — новую анимацию добавляют новым персонажем.`);
    if (a.frames.length > (o.regions || []).length) throw new Error(`В «${a.name}» кадров больше, чем в игре (${o.regions.length}): ленту, которую собирает генератор, можно править, но не удлинять.`);
    a.frames.forEach((f, i) => {
      if (f.off) return;
      const of = o.frames[i], [res, x, y, w, h] = o.regions[i];
      const whole = !of || f.id !== of.id || f.src !== of.src || (+f.dx || 0) !== (+of.dx || 0) || (+f.dy || 0) !== (+of.dy || 0) || (+f.sc || 1) !== (+of.sc || 1);
      const pixels = whole ? [] : Object.keys(f.patch || {}).map(k => k.split(',').map(Number)).filter(([px, py]) => px >= 0 && py >= 0 && px < w && py < h);
      if (whole || pixels.length) out.push({ res, x, y, w, h, frame: f.id, whole, pixels });
    });
  }
  return out;
}
// A mask (1 = hers) of where two RGBA pictures differ by more than tol in any channel, OR'd into `into`.
function diffMask(a, b, w, h, tol = 8, into = new Uint8Array(w * h)) {
  for (let p = 0; p < w * h; p++) {
    const i = p * 4;
    if (Math.abs(a[i] - b[i]) > tol || Math.abs(a[i + 1] - b[i + 1]) > tol || Math.abs(a[i + 2] - b[i + 2]) > tol || Math.abs(a[i + 3] - b[i + 3]) > tol) into[p] = 1;
  }
  return into;
}
// The manifest with these entries set, in the shape the Python side writes (sorted, two spaces).
// An edit made again keeps the base it was first drawn on; a stale one she has now looked at and
// drawn again is no longer stale, and its base is left for the generator to record anew.
function mergeOverrides(text, entries) {
  const all = text ? JSON.parse(text) : {};
  for (const [path, e] of Object.entries(entries)) {
    const was = all[path] || {};
    all[path] = { size: e.size, base: was.stale ? null : (was.base ?? null), by: e.by, at: e.at };
  }
  const sorted = Object.fromEntries(Object.keys(all).sort().map(k => [k, all[k]]));
  return JSON.stringify(sorted, null, 2) + '\n';
}

// ---- one send, one pull request ----
// A fingerprint of what a send writes (the studio project itself left out: it carries
// timestamps), so the same work sent twice is found instead of opening a second pull request.
// entries: [[path, Uint8Array]]
async function filesFingerprint(entries) {
  const enc = new TextEncoder(), parts = [];
  for (const [path, bytes] of entries.filter(([p]) => !p.startsWith('tools/studio/projects/')).sort((a, b) => a[0] < b[0] ? -1 : 1)) {
    parts.push(enc.encode(path + '\n'), new Uint8Array(await globalThis.crypto.subtle.digest('SHA-256', bytes)));
  }
  const all = new Uint8Array(parts.reduce((n, p) => n + p.length, 0)); let o = 0;
  for (const p of parts) { all.set(p, o); o += p.length; }
  return [...new Uint8Array(await globalThis.crypto.subtle.digest('SHA-256', all))].slice(0, 12).map(b => b.toString(16).padStart(2, '0')).join('');
}
const fingerprintMark = fp => `<!-- studio-files:${fp} -->`;

Object.assign(g, { filesFingerprint, fingerprintMark, REF_ROLES, spritePrompt, OVERRIDE_DIR, overrideFiles, frameEdits, diffMask, mergeOverrides, HERO_H, STEADY, frameStats, artChecks, enemySlotFor, liveMessage, snapToSurface, mergeStudioRooms, contentKey, mergeDecision, prStatus, spriteFramesTres, csvParse, csvStringify, mergeStrings, mergeDialogueFile, insertBackdropRules, setBackdropRule, alignEdit, warpEdit, matchColours, jsonSpans, pyJson, patchJson, jsonItems, setJsonList, lifeEntry, cutsceneJson, planSoundWrite, snapshot, unsnapshot, applyPatch, hsv, cornerColor, maskPixels, cropBox, copyCut, downscale, cdist, buildPalette, applyPalette, anchorX, edgeProfiles, P_STEP, trackLines, trackScore, peakThr, gridCurve, pickP, measuredStep, globalGridP, gridFor, gridSample, nativeSprite, mergeInnerGaps, toI16, encodeWav, EDIT_DEFAULT, isDefaultEdit, fmtJson });
})(typeof module !== 'undefined' ? module.exports : window);
