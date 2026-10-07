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

Object.assign(g, { enemySlotFor, liveMessage, snapToSurface, mergeStudioRooms, contentKey, mergeDecision, prStatus, spriteFramesTres, csvParse, csvStringify, mergeStrings, mergeDialogueFile, insertBackdropRules, cutsceneJson, planSoundWrite, snapshot, unsnapshot, applyPatch, hsv, cornerColor, maskPixels, cropBox, copyCut, downscale, cdist, buildPalette, applyPalette, anchorX, edgeProfiles, P_STEP, trackLines, trackScore, peakThr, gridCurve, pickP, measuredStep, globalGridP, gridFor, gridSample, nativeSprite, mergeInnerGaps, toI16, encodeWav, EDIT_DEFAULT, isDefaultEdit, fmtJson });
})(typeof module !== 'undefined' ? module.exports : window);
