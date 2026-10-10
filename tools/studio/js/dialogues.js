/* Sprite Studio — the dialogues tab (data/dialogues/*.json, played by scripts/ui/dialogue_box.gd).
 * Every dialogue of the game, not only the ones a cutscene step reaches: the people on E, the
 * notes, the forks' questions at a door. Lines (speaker + text in all four locales), choices
 * (answer, what it weighs on the paths, the flags it sets, where it leads), routers (flag / path /
 * habit / vial / omen → node), and which window it is drawn in: the panel at the bottom
 * (blocking, the game waits, choices allowed) or captions at the top ("blocking": false, play
 * goes on, no choices). An NPC's blocking dialogue is drawn as bubbles over the heads instead
 * (DialogueBox.play_bubble). The preview draws each of the three as the game lays them out
 * (dialogue_box.tscn / _build_bubbles); keep the two in step. */
'use strict';

const DLG = { data: null, work: {}, strings: {}, sel: null, nid: null, look: 'auto', locale: 'ru', holds: {}, typed: 1, t0: 0, raf: 0, bg: null, hit: [], fonts: false, zh: null };
const DLG_LOCALES = [['ru', 'Русский'], ['en', 'English'], ['uk', 'Українська'], ['zh_CN', '中文']];
const DLG_TESTS = { flag: 'флаг', path: 'путь сейчас', habit: 'привычка (3 ночи)', vial: 'чаша ≥', omen: 'знамение' };
const DLG_PATHS = { grace: 'благодать', temptation: 'искушение', will: 'воля' };
const DLG_USER = { npcs: 'NPC (разговор на E)', notes: 'записка', forks: 'развилка у двери', props: 'предмет', rest_points: 'место отдыха' };
const DLG_TYPE_RATE = 55, DLG_TYPE_MAX = 1.4;   // DialogueBox.TYPE_RATE / TYPE_MAX

async function dlgLoad() {
  if (DLG.data) return;
  DLG.data = await loadCutData();
  try { const s = JSON.parse(localStorage.getItem('ss_dlg') || 'null'); if (s) { DLG.work = s.work || {}; DLG.strings = s.strings || {}; DLG.sel = s.sel || null; } } catch {}
  if (!library) { try { library = await (await fetch('import/library.json')).json(); } catch {} }
  DLG.zh = new Set([...Object.values(DLG.data.strings)].flatMap(v => [...(v.zh_CN || '')]));
  dlgFonts();
}
// the game's faces: EB Garamond for what is read, Forum for buttons (assets/ui/theme.tres)
async function dlgFonts() {
  for (const [name, res] of [['AoE Garamond', 'res://assets/fonts/EBGaramond-Variable.ttf'], ['AoE Forum', 'res://assets/fonts/Forum-Regular.ttf']]) {
    try { const f = new FontFace(name, await (await fetch(A(res))).arrayBuffer()); await f.load(); document.fonts.add(f); } catch {}
  }
  DLG.fonts = true;
}
const dlgSave = () => { try { localStorage.setItem('ss_dlg', JSON.stringify({ work: DLG.work, strings: DLG.strings, sel: DLG.sel })); } catch {} };
const dlgOrig = id => DLG.data.dialogues[id] || null;
const dlgGet = id => DLG.work[id] || dlgOrig(id);
const dlgCur = () => dlgGet(DLG.sel);
const dlgClean = d => { const c = JSON.parse(JSON.stringify(d)); delete c._file; return c; };
const dlgChanged = id => !!DLG.work[id] && (!dlgOrig(id) || JSON.stringify(dlgClean(DLG.work[id])) !== JSON.stringify(dlgClean(dlgOrig(id))));
const dlgStrChanged = k => { const a = DLG.strings[k], b = DLG.data.strings[k] || {}; if (a && !DLG.data.strings[k]) return true; return !!a && DLG_LOCALES.some(([l]) => (a[l] ?? '') !== (b[l] ?? '')); };
const dlgDirty = () => Object.keys(DLG.work).some(dlgChanged) || Object.keys(DLG.strings).some(dlgStrChanged);
// a line in a locale; an empty one falls back to English as the game's CSV does after mergeStrings
const dlgStr = (key, loc = DLG.locale) => { const s = DLG.strings[key] || DLG.data.strings[key]; return s ? (s[loc] || s.en || s.ru || key) : (key || ''); };
const dlgRaw = (key, loc) => (DLG.strings[key] || DLG.data.strings[key] || {})[loc] ?? '';
function dlgOwn() {   // the selected dialogue, copied into the working set before its first edit
  if (!DLG.work[DLG.sel]) DLG.work[DLG.sel] = JSON.parse(JSON.stringify(dlgOrig(DLG.sel)));
  return DLG.work[DLG.sel];
}
function dlgEdit(fn, rerender = true) { fn(dlgOwn()); dlgSave(); if (rerender) renderDlg(); else dlgMarks(); }
function dlgSetStr(key, loc, v) { DLG.strings[key] ||= Object.fromEntries(DLG_LOCALES.map(([l]) => [l, dlgRaw(key, l)])); DLG.strings[key][loc] = v; dlgSave(); dlgMarks(); }
const dlgUsers = id => [...(DLG.data.used_by?.[id] || []), ...(DLG.data.cutscenes || []).filter(c => (c.steps || []).some(s => s.do === 'dialogue' && s.id === id)).map(c => ({ kind: 'cutscene', name: c.id }))];
const dlgIsNpc = id => (DLG.data.used_by?.[id] || []).some(u => u.kind === 'npcs');
function dlgLook(d) {   // the window the game draws: DialogueBox.play, play_bubble
  if (DLG.look !== 'auto') return DLG.look;
  if (d.blocking === false) return 'caption';
  return dlgIsNpc(d.id) ? 'bubble' : 'panel';
}
function dlgSpeakers() {
  const s = new Set(DLG.data.speakers || []);
  for (const d of Object.values({ ...DLG.data.dialogues, ...DLG.work })) for (const n of Object.values(d.nodes || {})) if (n.speaker) s.add(n.speaker);
  return [...s].sort();
}
function dlgNewKey(base) {
  let k = base, i = 2; const have = k => DLG.data.strings[k] || DLG.strings[k];
  while (have(k)) k = `${base}_${i++}`;
  return k;
}
// who answers a line: Elian answers the others, the one he talks with most answers him
function dlgReplyBy(d, speaker) {
  if (speaker !== 'SPEAKER_ELIAN') return 'SPEAKER_ELIAN';
  const n = {}; for (const m of Object.values(d.nodes)) if (m.speaker && m.speaker !== 'SPEAKER_ELIAN') n[m.speaker] = (n[m.speaker] || 0) + 1;
  return Object.entries(n).sort((a, b) => b[1] - a[1])[0]?.[0] || speaker;
}
function dlgNewNid(d, base = 'l') { let n = Object.keys(d.nodes).length + 1, id; do { id = `${base}${n++}`; } while (d.nodes[id]); return id; }

/* ---------- what the validator would say (validate_data.gd, "dialogues") ---------- */
function dlgProblems(d) {
  const err = [], warn = [], nodes = d.nodes || {}, has = id => id in nodes;
  if (!has(d.start)) err.push(`Начало «${d.start || ''}» — нет такой реплики`);
  for (const [nid, n] of Object.entries(nodes)) {
    if (n.next && !has(n.next)) err.push(`${nid}: «дальше» ведёт в несуществующую «${n.next}»`);
    if (n.branches) {
      n.branches.forEach((b, i) => {
        const k = Object.keys(DLG_TESTS).find(k => k in b);
        if (!k || b[k] === '') err.push(`${nid}: условие ${i + 1} ничего не проверяет`);
        if (!has(b.next)) err.push(`${nid}: условие ${i + 1} ведёт в несуществующую «${b.next || ''}»`);
        if ('vial' in b && (+b.vial < 1 || +b.vial > 5)) err.push(`${nid}: чаша — от 1 до 5`);
      });
      continue;
    }
    if (!n.speaker) err.push(`${nid}: не указано, кто говорит`);
    if (!n.text) err.push(`${nid}: нет ключа текста`);
    else if (!dlgRaw(n.text, 'ru') && !dlgRaw(n.text, 'en')) warn.push(`${nid}: пустая реплика`);
    if (d.blocking === false && n.choices) err.push(`${nid}: в субтитрах не бывает выбора — смени окно на «панель внизу» или убери ответы`);
    (n.choices || []).forEach((c, i) => {
      if (!c.text) err.push(`${nid}: у ответа ${i + 1} нет текста`);
      if (c.next && !has(c.next)) err.push(`${nid}: ответ ${i + 1} ведёт в несуществующую «${c.next}»`);
    });
  }
  const seen = new Set(), walk = id => { if (!id || seen.has(id) || !nodes[id]) return; seen.add(id); const n = nodes[id]; walk(n.next); (n.choices || []).forEach(c => walk(c.next)); (n.branches || []).forEach(b => walk(b.next)); };
  walk(d.start);
  for (const nid of Object.keys(nodes)) if (!seen.has(nid)) warn.push(`${nid}: до этой реплики нельзя дойти`);
  const keys = new Set(Object.values(nodes).flatMap(n => [n.text, ...(n.choices || []).map(c => c.text)]).filter(Boolean));
  const extra = new Set([...keys].flatMap(k => [...(DLG.strings[k]?.zh_CN || '')]).filter(ch => ch.charCodeAt(0) > 0x2e7f && !DLG.zh.has(ch)));
  if (extra.size) warn.push(`В китайском новые иероглифы (${[...extra].slice(0, 12).join('')}…): шрифт нужно пересобрать — tools/art/make_cjk_font.py, иначе проверка не пройдёт`);
  return { err, warn };
}

/* ---------- the preview: the game's three windows ---------- */
const DLG_W = 640, DLG_H = 360;
function dlgWrap(x, text, width) {
  const out = [];
  for (const para of String(text).split('\n')) {
    const cjk = /[⺀-鿿]/.test(para), parts = cjk ? [...para] : para.split(' ');
    let line = '';
    for (const w of parts) { const t = line ? line + (cjk ? '' : ' ') + w : w; if (x.measureText(t).width > width && line) { out.push(line); line = w; } else line = t; }
    out.push(line);
  }
  return out;
}
function dlgRound(x, X, Y, W, H, r) { x.beginPath(); x.roundRect(X, Y, W, H, r); }
function dlgResolve(d, nid) {   // routers resolve as the preview's switches say (DialogueBox.branch_holds)
  let guard = 0;
  while (nid && d.nodes[nid]?.branches && guard++ < 50) {
    const n = d.nodes[nid], b = n.branches.find(b => DLG.holds[dlgTestKey(b)]);
    nid = b ? b.next : n.next;
  }
  return nid && d.nodes[nid] ? nid : null;
}
const dlgTestKey = b => { const k = Object.keys(DLG_TESTS).find(k => k in b); return k ? `${k}:${b[k]}` : ''; };
function dlgFace(size, display) { return `${size}px ${display ? '"AoE Forum", ' : ''}"AoE Garamond", "Noto Serif SC", Georgia, serif`; }
function dlgFrame(now) {
  DLG.raf = 0; if (mode !== 'dlg' || !DLG.data) return;
  const c = $('#dlgCanvas'), x = c.getContext('2d'), d = dlgCur();
  x.setTransform(c.width / DLG_W, 0, 0, c.height / DLG_H, 0, 0);
  x.fillStyle = '#0f0d14'; x.fillRect(0, 0, DLG_W, DLG_H);
  if (DLG.bg) { const s = Math.max(DLG_W / DLG.bg.width, DLG_H / DLG.bg.height); x.drawImage(DLG.bg, (DLG_W - DLG.bg.width * s) / 2, (DLG_H - DLG.bg.height * s) / 2, DLG.bg.width * s, DLG.bg.height * s); }
  else { const g = x.createLinearGradient(0, 0, 0, DLG_H); g.addColorStop(0, '#1b1826'); g.addColorStop(1, '#0c0b10'); x.fillStyle = g; x.fillRect(0, 0, DLG_W, DLG_H); x.fillStyle = '#1d1a24'; x.fillRect(0, 300, DLG_W, 60); }
  DLG.hit = [];
  const nid = d && dlgResolve(d, DLG.nid ?? d.start), n = nid && d.nodes[nid], look = d && dlgLook(d);
  if (!n) { x.fillStyle = '#cfd8e3'; x.font = dlgFace(14); x.textAlign = 'center'; x.fillText(d ? '— конец диалога — (щёлкни, чтобы начать заново)' : 'Выбери диалог слева', DLG_W / 2, DLG_H / 2); x.textAlign = 'left'; DLG.hit.push({ r: [0, 0, DLG_W, DLG_H], go: 'restart' }); }
  else if (look === 'caption') dlgDrawCaption(x, n, nid);
  else if (look === 'bubble') dlgDrawBubble(x, n, nid, now);
  else dlgDrawPanel(x, n, nid);
  if (n) { x.fillStyle = '#ffffff66'; x.font = '9px system-ui'; x.fillText(`${nid} · ${{ panel: 'панель внизу', caption: 'субтитры сверху', bubble: 'пузыри над головами' }[look]}`, 6, 11); }
  if (n && look === 'bubble' && DLG.typed < 1) DLG.raf = requestAnimationFrame(dlgFrame);
}
function dlgChoiceHits(n, rects) { (n.choices || []).forEach((ch, i) => DLG.hit.push({ r: rects[i], go: ch.next || null, choice: i })); }
function dlgDrawPanel(x, n) {   // dialogue_box.tscn: Panel 16..−16 × −128..−12, margins 12/8, Speaker 12 px gold, Text 16, Choices, Skip/Continue
  const X = 16, Y = DLG_H - 128, W = DLG_W - 32, H = 116;
  dlgRound(x, X, Y, W, H, 3); x.fillStyle = 'rgba(26,26,26,0.6)'; x.fill();
  x.textBaseline = 'top'; x.fillStyle = 'rgb(242,217,128)'; x.font = dlgFace(12); x.fillText(dlgStr(n.speaker), X + 12, Y + 8);
  x.fillStyle = '#eee'; x.font = dlgFace(16);
  const lines = dlgWrap(x, dlgStr(n.text), W - 24); let y = Y + 26;
  for (const l of lines) { x.fillText(l, X + 12, y); y += 19; }
  const rects = [];
  if (n.choices?.length) {
    x.font = dlgFace(15, true); y += 2;
    n.choices.forEach((ch, i) => { const t = `${i + 1}. ${dlgStr(ch.text)}`, w = x.measureText(t).width + 16; dlgRound(x, X + 12, y, w, 20, 3); x.fillStyle = 'rgba(40,40,46,0.85)'; x.fill(); x.fillStyle = '#ddd'; x.fillText(t, X + 20, y + 3); rects.push([X + 12, y, w, 20]); y += 22; });
    dlgChoiceHits(n, rects);
  } else {
    x.font = dlgFace(15, true); const cont = dlgStr('DLG_CONTINUE'), skip = dlgStr('DLG_SKIP'), cw = x.measureText(cont).width + 16, sw = x.measureText(skip).width + 12;
    const by = Y + H - 28, cx = X + W - 12 - cw;
    dlgRound(x, cx, by, cw, 22, 3); x.fillStyle = 'rgba(40,40,46,0.9)'; x.fill(); x.fillStyle = '#ddd'; x.fillText(cont, cx + 8, by + 4);
    x.fillStyle = '#aaa'; x.fillText(skip, cx - sw - 4, by + 4);
    DLG.hit.push({ r: [X, Y, W, H], go: n.next || null });
  }
  if (y > Y + H) { x.fillStyle = '#e06464'; x.font = '10px system-ui'; x.fillText('текст не влезает в панель', X + W - 140, Y - 14); }
  x.textBaseline = 'alphabetic';
}
function dlgDrawCaption(x, n) {   // Caption: 170..−148 × 24..60, 13 px, warm white, shadow, centred, "Speaker: text"
  const X = 170, W = DLG_W - 148 - X;
  x.font = dlgFace(13); x.textAlign = 'center'; x.textBaseline = 'top';
  const lines = dlgWrap(x, `${dlgStr(n.speaker)}: ${dlgStr(n.text)}`, W);
  lines.forEach((l, i) => { x.fillStyle = 'rgba(0,0,0,0.8)'; x.fillText(l, X + W / 2 + 1, 24 + i * 16 + 1); x.fillStyle = 'rgb(242,230,191)'; x.fillText(l, X + W / 2, 24 + i * 16); });
  if (lines.length > 3) { x.fillStyle = '#e06464'; x.font = '10px system-ui'; x.fillText('длинновато для субтитра', DLG_W / 2, 24 + lines.length * 16 + 4); }
  x.textAlign = 'left'; x.textBaseline = 'alphabetic';
  x.fillStyle = '#ffffff55'; x.font = '10px system-ui'; x.fillText('игра идёт; субтитр сменится сам — щёлкни, чтобы дальше', 170, DLG_H - 14);
  DLG.hit.push({ r: [0, 0, DLG_W, DLG_H], go: n.next || null });
}
function dlgFigure(x, cx, label, tint) {
  x.fillStyle = tint; x.fillRect(cx - 6, 262, 12, 38); x.beginPath(); x.arc(cx, 254, 7, 0, 7); x.fill();
  x.fillStyle = '#ffffff55'; x.font = '9px system-ui'; x.textAlign = 'center'; x.fillText(label, cx, 314); x.textAlign = 'left';
}
function dlgDrawBubble(x, n, nid, now) {   // _build_bubbles / _show_bubble: 7 px name, 8 px text, width clamp(len × 4.2, 64, 168)
  const S = 2;   // drawn at twice the game's pixels so it can be read here; the game shows it at 1× of 640×360
  const hero = 250, npc = 390, isHero = n.speaker === 'SPEAKER_ELIAN';
  dlgFigure(x, hero, 'Элиан', '#6b2f2f'); const who = (DLG.data.used_by?.[DLG.sel] || []).find(u => u.kind === 'npcs')?.name || (isHero ? '' : n.speaker);
  dlgFigure(x, npc, who ? dlgStr(who) : 'собеседник', '#4a4f63');
  const line = dlgStr(n.text), dur = Math.min(line.length / DLG_TYPE_RATE, DLG_TYPE_MAX) * 1000;
  DLG.typed = dur ? Math.min(1, (now - DLG.t0) / dur) : 1;
  const tw = Math.max(64, Math.min(168, line.length * 4.2)) * S;
  x.font = dlgFace(8 * S); const lines = dlgWrap(x, line.slice(0, Math.round(line.length * DLG.typed)), tw), full = dlgWrap(x, line, tw);
  const W = tw + 12 * S, H = (3 + 7 + 1 + full.length * 10 + 1 + 8 + 4) * S, ax = isHero ? hero : npc;
  const X = Math.max(4, Math.min(DLG_W - W - 4, ax - W / 2)), Y = 240 - H - 6;
  dlgRound(x, X, Y, W, H, 3 * S); x.fillStyle = 'rgba(15,13,18,0.93)'; x.fill(); x.strokeStyle = 'rgb(158,135,102)'; x.lineWidth = 1; x.stroke();
  x.beginPath(); x.moveTo(ax - 4 * S, Y + H); x.lineTo(ax + 4 * S, Y + H); x.lineTo(ax, Y + H + 5 * S); x.fillStyle = 'rgba(15,13,18,0.93)'; x.fill();
  x.textBaseline = 'top'; x.fillStyle = 'rgb(242,204,128)'; x.font = dlgFace(7 * S); x.fillText(dlgStr(n.speaker), X + 6 * S, Y + 3 * S);
  x.fillStyle = 'rgb(242,237,224)'; x.font = dlgFace(8 * S); lines.forEach((l, i) => x.fillText(l, X + 6 * S, Y + (11 + i * 10) * S));
  if (DLG.typed >= 1 && !n.choices?.length) { x.fillStyle = 'rgba(204,191,166,0.8)'; x.font = dlgFace(7 * S); x.textAlign = 'right'; x.fillText('E ›', X + W - 6 * S, Y + H - 11 * S); x.textAlign = 'left'; }
  if (DLG.typed >= 1 && n.choices?.length) {   // the answers float over Elian
    x.font = dlgFace(8 * S); const ts = n.choices.map((c, i) => `${i + 1}. ${dlgStr(c.text)}`), aw = Math.max(...ts.map(t => x.measureText(t).width)) + 12 * S, ah = (ts.length * 11 + 6) * S;
    // _place_bubbles: over Elian's head, and below the line being answered when they would overlap
    let AX = Math.max(4, Math.min(DLG_W - aw - 4, hero - aw / 2)), AY = 240 - ah - 5;
    if (AX < X + W && AX + aw > X && AY < Y + H && AY + ah > Y) AY = Y + H + 8;
    AY = Math.max(4, Math.min(DLG_H - ah - 4, AY));
    dlgRound(x, AX, AY, aw, ah, 3 * S); x.fillStyle = 'rgba(15,13,18,0.93)'; x.fill(); x.strokeStyle = 'rgb(191,173,140)'; x.stroke();
    const rects = ts.map((t, i) => { x.fillStyle = '#ece6d8'; x.fillText(t, AX + 6 * S, AY + (3 + i * 11) * S); return [AX, AY + (3 + i * 11) * S - 2, aw, 11 * S]; });
    dlgChoiceHits(n, rects);
  } else DLG.hit.push({ r: [0, 0, DLG_W, DLG_H], go: DLG.typed < 1 ? 'type' : (n.next || null) });
  x.textBaseline = 'alphabetic';
  x.fillStyle = '#ffffff55'; x.font = '10px system-ui'; x.fillText('пузыри показаны вдвое крупнее, чем в игре', 6, DLG_H - 6);
}
function dlgPreviewGo(nid) { DLG.nid = nid ?? '#end'; DLG.t0 = performance.now(); DLG.typed = 0; dlgPaint(); dlgMarkPreviewNode(); }
function dlgPaint() { if (!DLG.raf) DLG.raf = requestAnimationFrame(dlgFrame); }
function dlgCanvasClick(e) {
  const c = $('#dlgCanvas'), r = c.getBoundingClientRect(), d = dlgCur(); if (!d) return;
  // the canvas is drawn with object-fit: contain — find the picture inside the box
  const s = Math.min(r.width / DLG_W, r.height / DLG_H), ox = (r.width - DLG_W * s) / 2, oy = (r.height - DLG_H * s) / 2;
  const px = (e.clientX - r.left - ox) / s, py = (e.clientY - r.top - oy) / s;
  const h = DLG.hit.find(h => h.choice !== undefined && px >= h.r[0] && px <= h.r[0] + h.r[2] && py >= h.r[1] && py <= h.r[1] + h.r[3]) || DLG.hit.find(h => h.choice === undefined && px >= h.r[0] && px <= h.r[0] + h.r[2] && py >= h.r[1] && py <= h.r[1] + h.r[3]);
  if (!h) return;
  if (h.go === 'restart') return dlgPreviewGo(d.start);
  if (h.go === 'type') { DLG.t0 = -1e9; return dlgPaint(); }
  dlgPreviewGo(h.go);
}

/* ---------- panels ---------- */
function renderDlgList() {
  const q = ($('#dlgSearch').value || '').toLowerCase(), all = { ...DLG.data.dialogues, ...DLG.work };
  const byFile = {};
  for (const [id, d] of Object.entries(all)) {
    const hay = (id + ' ' + Object.values(d.nodes || {}).map(n => dlgStr(n.text, 'ru')).join(' ')).toLowerCase();
    if (q && !hay.includes(q)) continue;
    (byFile[d._file || id + '.json'] ||= []).push(id);
  }
  $('#dlgList').innerHTML = Object.keys(byFile).sort().map(f => `<div class="muted" style="margin-top:6px">${esc(f)}</div>` + byFile[f].map(id => {
    const d = all[id], u = dlgUsers(id)[0], ch = dlgChanged(id) || Object.values(d.nodes || {}).some(n => dlgStrChanged(n.text) || (n.choices || []).some(c => dlgStrChanged(c.text)));
    return `<div class="irow${id === DLG.sel ? ' on' : ''}" data-act="dg-sel" data-id="${esc(id)}"><span class="grow">${esc(id)}<br><span class="muted" style="font-size:11px">${d.blocking === false ? 'субтитры' : dlgIsNpc(id) ? 'пузыри' : 'панель'}${u ? ' · ' + esc(u.kind === 'cutscene' ? 'катсцена ' + u.name : (DLG_USER[u.kind] || u.kind) + ' ' + dlgStr(u.name)) : ''}</span></span>${!dlgOrig(id) ? '<span class="badge new">новый</span>' : ch ? '<span class="badge new">•</span>' : ''}</div>`;
  }).join('')).join('') || '<div class="muted">Ничего не найдено</div>';
}
function dlgNextSel(d, v, attr, blankLabel = '— конец —') {
  return `<select ${attr}><option value="">${blankLabel}</option>${Object.keys(d.nodes).map(k => `<option value="${esc(k)}"${k === v ? ' selected' : ''}>${esc(k)}${d.nodes[k].branches ? ' (развилка)' : ' — ' + esc(dlgStr(d.nodes[k].text, 'ru').slice(0, 30))}</option>`).join('')}</select>`;
}
function dlgTextFields(key, attr, rows = 2) {
  const [main, ...rest] = DLG_LOCALES;
  return `<textarea ${attr} data-loc="${main[0]}" data-key="${esc(key)}" rows="${rows}" placeholder="${main[1]}">${esc(dlgRaw(key, main[0]))}</textarea>
    <details><summary class="muted" style="font-size:11px">Другие языки${rest.filter(([l]) => !dlgRaw(key, l)).length ? ` <span class="warn" style="display:inline">· нет перевода: ${rest.filter(([l]) => !dlgRaw(key, l)).map(([l]) => l).join(', ')}</span>` : ''}</summary>
    ${rest.map(([l, name]) => `<textarea ${attr} data-loc="${l}" data-key="${esc(key)}" rows="1" placeholder="${name}">${esc(dlgRaw(key, l))}</textarea>`).join('')}</details>`;
}
function renderDlgNodes() {
  const d = dlgCur(), box = $('#dlgNodes');
  if (!d) { box.innerHTML = '<div class="note">Выбери диалог слева или создай новый.</div>'; return; }
  const sp = dlgSpeakers(), users = dlgUsers(d.id), fork = users.some(u => u.kind === 'forks'), pv = DLG.nid ?? d.start;
  const order = dialogueOrder(d);
  const nodeHtml = nid => {
    const n = d.nodes[nid], head = `<div class="row" style="margin:0"><b>${esc(nid)}</b>${nid === d.start ? '<span class="badge new">начало</span>' : `<button class="sm" data-act="dg-start" title="Диалог начинается здесь">⚑ начало</button>`}
      <span class="grow"></span><button class="sm" data-act="dg-here" title="Показать в превью с этой реплики">▶</button>
      <button class="sm" data-act="dg-rename" title="Переименовать (ссылки обновятся)">✎</button><button class="sm danger" data-act="dg-del-node" title="Удалить">✕</button></div>`;
    if (n.branches) return `<div class="card${nid === pv ? ' sel' : ''}" data-nid="${esc(nid)}" style="margin-top:8px">${head}
      <div class="muted" style="font-size:12px">Развилка: первое выполненное условие решает, куда дальше. Текста у неё нет.</div>
      ${n.branches.map((b, i) => { const k = Object.keys(DLG_TESTS).find(k => k in b) || 'flag', v = b[k] ?? '';
        const val = k === 'path' || k === 'habit' ? `<select data-dn="b.${i}.val">${Object.entries(DLG_PATHS).map(([p, l]) => `<option value="${p}"${p === v ? ' selected' : ''}>${l}</option>`).join('')}</select>`
          : k === 'vial' ? `<input type="number" min="1" max="5" data-dn="b.${i}.val" value="${esc(v)}" style="width:60px">` : `<input data-dn="b.${i}.val" value="${esc(v)}" list="${k === 'flag' ? 'dlgFlags' : ''}" placeholder="${k === 'flag' ? 'имя флага' : 'id знамения'}">`;
        return `<div class="row" data-bi="${i}"><span class="muted">если</span><select data-dn="b.${i}.kind">${Object.entries(DLG_TESTS).map(([t, l]) => `<option value="${t}"${t === k ? ' selected' : ''}>${l}</option>`).join('')}</select>${val}<span class="muted">→</span>${dlgNextSel(d, b.next, `data-dn="b.${i}.next"`, '— выбери —')}<button class="sm danger" data-act="dg-del-branch" data-i="${i}">✕</button></div>`; }).join('')}
      <div class="row"><button class="sm" data-act="dg-add-branch">＋ Условие</button><span class="muted">иначе →</span>${dlgNextSel(d, n.next, 'data-dn="next"')}</div></div>`;
    return `<div class="card${nid === pv ? ' sel' : ''}" data-nid="${esc(nid)}" style="margin-top:8px">${head}
      <div class="row" style="margin:0"><label style="margin:0">Кто говорит</label><input data-dn="speaker" list="dlgSpeakers" value="${esc(n.speaker || '')}" style="flex:1"><span class="muted">${esc(dlgStr(n.speaker, 'ru'))}</span>
        <button class="sm" data-act="dg-voice" title="Озвучка этой реплики">🔊</button></div>
      <div class="muted" style="font-size:11px">ключ ${esc(n.text || '—')}</div>
      ${n.text ? dlgTextFields(n.text, 'data-dt') : '<div class="warn">нет ключа текста</div>'}
      ${(n.choices || []).map((c, i) => `<div class="card" style="margin-top:6px;background:var(--panel2)" data-ci="${i}">
        <div class="row" style="margin:0"><b>Ответ ${i + 1}</b><span class="grow"></span>
          <label style="margin:0" title="${fork ? 'У развилки у двери id ответа — это путь из data/forks, не меняй его' : 'id ответа: его видят сохранения и логи'}">id <input data-dn="c.${i}.id" value="${esc(c.id || '')}" style="width:110px"${fork ? ' readonly' : ''}></label>
          <button class="sm" data-act="dg-ch-up" data-i="${i}" title="Выше">↑</button><button class="sm danger" data-act="dg-del-choice" data-i="${i}">✕</button></div>
        ${c.text ? dlgTextFields(c.text, 'data-dt', 1) : ''}
        <div class="row">${Object.entries(DLG_PATHS).map(([p, l]) => `<label style="margin:0" title="Сдвиг скрытого счётчика пути">${l} <input type="number" data-dn="c.${i}.eff.${p}" value="${c.effect?.[p] ?? ''}" style="width:48px" step="1"></label>`).join('')}</div>
        <div class="row"><label style="margin:0">ставит флаги <input data-dn="c.${i}.flags" value="${esc((c.effect?.set_flags || []).join(', '))}" placeholder="через запятую" list="dlgFlags"></label>
          <span class="muted">→</span>${dlgNextSel(d, c.next, `data-dn="c.${i}.next"`)}</div></div>`).join('')}
      <div class="row">${n.choices?.length ? '' : `<span class="muted">дальше →</span>${dlgNextSel(d, n.next, 'data-dn="next"')}`}
        <span class="grow"></span>${n.choices?.length ? '' : '<button class="sm" data-act="dg-add-after" title="Новая реплика сразу после этой — отвечает собеседник">＋ Реплика после</button>'}
        <button class="sm" data-act="dg-add-choice"${d.blocking === false ? ' disabled title="В субтитрах выбора не бывает"' : ''}>＋ Ответ</button></div></div>`;
  };
  const { err, warn } = dlgProblems(d);
  box.innerHTML = `${err.length ? `<div class="card" style="border-color:var(--err)">${err.map(m => `<div class="warn" style="color:var(--err)">✕ ${esc(m)}</div>`).join('')}</div>` : ''}
    ${warn.length ? `<div class="card">${warn.map(m => `<div class="warn">⚠ ${esc(m)}</div>`).join('')}</div>` : ''}
    ${order.map(nodeHtml).join('')}
    <div class="row"><button class="sm" data-act="dg-add-line">＋ Реплика</button><button class="sm" data-act="dg-add-router">＋ Развилка по флагам</button></div>`;
}
function renderDlgHead() {
  const d = dlgCur(), box = $('#dlgHead');
  if (!d) { box.innerHTML = ''; return; }
  const users = dlgUsers(d.id), npc = dlgIsNpc(d.id), flags = [...new Set(Object.values(d.nodes).flatMap(n => (n.branches || []).map(dlgTestKey)).filter(Boolean))];
  box.innerHTML = `<div class="row" style="margin:0"><b>${esc(d.id)}</b><span class="muted">${esc(d._file || d.id + '.json')}</span><span class="grow"></span>
      ${DLG.work[d.id] && dlgOrig(d.id) ? '<button class="sm" data-act="dg-revert" title="Вернуть этот диалог как в игре">↺ Как в игре</button>' : ''}</div>
    <div class="muted" style="font-size:12px">${users.length ? 'Звучит: ' + users.map(u => esc(u.kind === 'cutscene' ? 'катсцена ' + u.name : (DLG_USER[u.kind] || u.kind) + ' «' + dlgStr(u.name, 'ru') + '»')).join(', ') : 'Его запускает комната или код игры (или пока никто)'}</div>
    <label>Окно<select id="dlgBlocking">
      <option value="panel"${d.blocking !== false ? ' selected' : ''}>${npc ? 'Пузыри над головами (разговор на E)' : 'Панель внизу — игра ждёт, можно выбирать ответы'}</option>
      <option value="caption"${d.blocking === false ? ' selected' : ''}>Субтитры сверху — игра идёт, без ответов</option></select></label>
    ${flags.length ? `<div class="muted" style="font-size:12px;margin-top:6px">В превью считать выполненным:</div><div class="row" style="margin:0">${flags.map(f => `<label class="sm btnlike" style="margin:0"><input type="checkbox" data-hold="${esc(f)}"${DLG.holds[f] ? ' checked' : ''}> ${esc(f.replace(/^(\w+):/, (m, k) => DLG_TESTS[k] + ' '))}</label>`).join('')}</div>` : ''}`;
}
function dlgMarks() {   // the cheap part of a re-render: the dirty dot, the send button, the preview
  const send = $('#dlgSend'), dirty = dlgDirty(); send.disabled = !dirty; send.textContent = dirty ? '→ В игру •' : '→ В игру';
  DLG.t0 = -1e9; dlgPaint();
}
function dlgMarkPreviewNode() { const pv = DLG.nid ?? dlgCur()?.start; $$('#dlgNodes [data-nid]').forEach(el => el.classList.toggle('sel', el.dataset.nid === pv)); }
function renderDlg() {
  if (!DLG.data) return;
  if (DLG.sel && !dlgGet(DLG.sel)) DLG.sel = null;
  $('#dlgSpeakers').innerHTML = dlgSpeakers().map(k => `<option value="${esc(k)}">${esc(dlgStr(k, 'ru'))}</option>`).join('');
  $('#dlgFlags').innerHTML = [...new Set(Object.values({ ...DLG.data.dialogues, ...DLG.work }).flatMap(d => Object.values(d.nodes || {}).flatMap(n => [...(n.branches || []).map(b => b.flag), ...(n.choices || []).flatMap(c => c.effect?.set_flags || [])])).filter(Boolean))].sort().map(f => `<option value="${esc(f)}">`).join('');
  renderDlgList(); renderDlgHead(); renderDlgNodes(); dlgMarks();
}

/* ---------- edits ---------- */
function dlgRenameRefs(d, from, to) {
  if (d.start === from) d.start = to;
  for (const n of Object.values(d.nodes)) { if (n.next === from) n.next = to; (n.choices || []).forEach(c => { if (c.next === from) c.next = to; }); (n.branches || []).forEach(b => { if (b.next === from) b.next = to; }); }
}
function dlgNodeInput(e) {
  const el = e.target, card = el.closest('[data-nid]'), nid = card?.dataset.nid;
  if (el.dataset.dt !== undefined) return dlgSetStr(el.dataset.key, el.dataset.loc, el.value);
  if (!nid || !el.dataset.dn) return;
  const f = el.dataset.dn.split('.'), commit = e.type === 'change';
  dlgEdit(d => {
    const n = d.nodes[nid], v = el.value;
    if (f[0] === 'speaker') n.speaker = v.trim();
    else if (f[0] === 'next') { if (v) n.next = v; else delete n.next; }
    else if (f[0] === 'b') {
      const b = n.branches[+f[1]];
      if (f[2] === 'next') b.next = v;
      else if (f[2] === 'kind') { const old = Object.keys(DLG_TESTS).find(k => k in b); delete b[old]; b[v] = v === 'vial' ? 1 : v === 'path' || v === 'habit' ? 'grace' : ''; }
      else { const k = Object.keys(DLG_TESTS).find(k => k in b) || 'flag'; b[k] = k === 'vial' ? +v : v.trim(); }
    } else if (f[0] === 'c') {
      const c = n.choices[+f[1]];
      if (f[2] === 'id') c.id = v.trim();
      else if (f[2] === 'next') { if (v) c.next = v; else delete c.next; }
      else if (f[2] === 'flags') { const a = v.split(',').map(s => s.trim()).filter(Boolean); c.effect ||= {}; if (a.length) c.effect.set_flags = a; else delete c.effect.set_flags; }
      else if (f[2] === 'eff') { c.effect ||= {}; if (v === '' || +v === 0) delete c.effect[f[3]]; else c.effect[f[3]] = +v; }
      if (c.effect && !Object.keys(c.effect).length) delete c.effect;
    }
  }, commit && (el.tagName === 'SELECT' || f[0] === 'b'));
  if (commit) { renderDlgList(); if (el.tagName !== 'SELECT') renderDlgNodes(); }
}
async function dlgAct(e) {
  const b = e.target.closest('[data-act^="dg-"]'); if (!b) return;
  if (b.dataset.act === 'dg-open') { setMode('dlg'); await dlgLoad(); DLG.sel = b.dataset.id; DLG.nid = undefined; dlgSave(); return renderDlg(); }
  if (mode !== 'dlg') return;
  const act = b.dataset.act, nid = b.closest('[data-nid]')?.dataset.nid;
  const lineKey = (d, n) => dlgNewKey(`DLG_${String(d.id).toUpperCase().replace(/[^A-Z0-9]+/g, '_')}_${n.toUpperCase()}`);
  const newLine = (d, speaker) => { const id = dlgNewNid(d); const key = lineKey(d, id); d.nodes[id] = { speaker: speaker || 'SPEAKER_ELIAN', text: key }; DLG.strings[key] = { ru: '', en: '', uk: '', zh_CN: '' }; return id; };
  switch (act) {
    case 'dg-sel': DLG.sel = b.dataset.id; DLG.nid = null; DLG.look = 'auto'; $('#dlgLook').value = 'auto'; DLG.t0 = performance.now(); dlgSave(); return renderDlg();
    case 'dg-new': {
      const raw = prompt('Имя диалога латиницей (например npc_smith или ch1_well):', 'ch1_'); if (!raw) return;
      const id = slug(raw).replace(/-/g, '_'); if (dlgGet(id)) return toast('Такой диалог уже есть', 'err');
      const d = { id, start: 'l1', nodes: {} }, key = dlgNewKey(`DLG_${id.toUpperCase()}_L1`);
      d.nodes.l1 = { speaker: 'SPEAKER_ELIAN', text: key }; DLG.strings[key] = { ru: '', en: '', uk: '', zh_CN: '' };
      d._file = id + '.json'; DLG.work[id] = d; DLG.sel = id; DLG.nid = null; dlgSave(); return renderDlg();
    }
    case 'dg-revert': if (!confirm('Вернуть диалог как в игре? Правки текста реплик тоже сбросятся.')) return;
      for (const n of Object.values(dlgOrig(DLG.sel).nodes)) { delete DLG.strings[n.text]; (n.choices || []).forEach(c => delete DLG.strings[c.text]); }
      delete DLG.work[DLG.sel]; dlgSave(); return renderDlg();
    case 'dg-revert-all': if (!confirm('Сбросить все несохранённые правки диалогов?')) return;
      DLG.work = {}; DLG.strings = {}; dlgSave(); return renderDlg();
    case 'dg-start': return dlgEdit(d => { d.start = nid; });
    case 'dg-here': return dlgPreviewGo(nid);
    case 'dg-rename': {
      const to = (prompt('Новое имя реплики (латиница):', nid) || '').trim().replace(/[^\w]/g, '_'); if (!to || to === nid) return;
      if (dlgCur().nodes[to]) return toast('Такое имя уже есть', 'err');
      return dlgEdit(d => { d.nodes = Object.fromEntries(Object.entries(d.nodes).map(([k, v]) => [k === nid ? to : k, v])); dlgRenameRefs(d, nid, to); });
    }
    case 'dg-del-node': if (!confirm(`Удалить реплику «${nid}»? Ссылки на неё поведут туда же, куда вела она.`)) return;
      return dlgEdit(d => { const n = d.nodes[nid], to = n.next || ''; delete d.nodes[nid]; dlgRenameRefs(d, nid, to);
        const clean = o => { if (o.next === '') delete o.next; }; clean(d); Object.values(d.nodes).forEach(m => { clean(m); (m.choices || []).forEach(clean); });
        if (!d.start || !d.nodes[d.start]) d.start = Object.keys(d.nodes)[0] || ''; });
    case 'dg-add-line': return dlgEdit(d => { const order = dialogueOrder(d), last = [...order].reverse().find(k => !d.nodes[k].branches && !d.nodes[k].choices && !d.nodes[k].next);
      const id = newLine(d, last && d.nodes[last].speaker); if (last) d.nodes[last].next = id; else if (!d.nodes[d.start]) d.start = id; });
    case 'dg-add-after': return dlgEdit(d => { const n = d.nodes[nid], id = newLine(d, dlgReplyBy(d, n.speaker)); if (n.next) d.nodes[id].next = n.next; n.next = id; });
    case 'dg-add-router': return dlgEdit(d => { const id = dlgNewNid(d, 'r'); d.nodes[id] = { branches: [{ flag: '', next: d.start }], next: d.start }; d.start = id; });
    case 'dg-add-branch': return dlgEdit(d => { d.nodes[nid].branches.push({ flag: '', next: d.nodes[nid].next || d.start }); });
    case 'dg-del-branch': return dlgEdit(d => { d.nodes[nid].branches.splice(+b.dataset.i, 1); });
    case 'dg-add-choice': return dlgEdit(d => { const n = d.nodes[nid]; n.choices ||= []; const i = n.choices.length + 1, key = dlgNewKey(`${n.text || lineKey(d, nid)}_ANS${i}`);
      DLG.strings[key] = { ru: '', en: '', uk: '', zh_CN: '' }; n.choices.push({ id: `answer${i}`, text: key, ...(n.next ? { next: n.next } : {}) }); delete n.next; });
    case 'dg-del-choice': return dlgEdit(d => { const n = d.nodes[nid], [c] = n.choices.splice(+b.dataset.i, 1); if (!n.choices.length) { delete n.choices; if (c.next) n.next = c.next; } });
    case 'dg-ch-up': return dlgEdit(d => { const a = d.nodes[nid].choices, i = +b.dataset.i; if (i > 0) [a[i - 1], a[i]] = [a[i], a[i - 1]]; });
    case 'dg-voice': {
      const key = dlgCur().nodes[nid].text; setMode('snd'); await loadSndLib(); sndCat = 'voice'; $('#sndLocale').value = 'ru';
      const k = `voice/ru/${key}`;
      if (!sndEntry(k)) { const m = { id: k, cat: 'voice', name: key, locale: 'ru', isNew: true, takes: { [key]: { src: null, edits: { ...EDIT_DEFAULT } } } }; sndMods.set(k, m); saveSnd(m); }
      sndSel = k; sndTake = null; renderSndList(); renderSndMain(); return;
    }
    case 'dg-send': {
      const bad = Object.keys(DLG.work).filter(dlgChanged).filter(id => dlgProblems(DLG.work[id]).err.length);
      if (bad.length && !confirm(`В диалогах ${bad.join(', ')} есть ошибки (красным) — проверка игры их не пропустит. Всё равно отправить?`)) return;
      await sendToGame(dlgFiles, null);
      if (sendToGame.last?.local) { for (const [id, d] of Object.entries(DLG.work)) DLG.data.dialogues[id] = JSON.parse(JSON.stringify(d)); for (const [k, v] of Object.entries(DLG.strings)) DLG.data.strings[k] = { ...v }; DLG.work = {}; DLG.strings = {}; dlgSave(); renderDlg(); }
    }
  }
}
async function dlgFiles() {
  const files = {}, ids = Object.keys(DLG.work).filter(dlgChanged), keys = Object.keys(DLG.strings).filter(dlgStrChanged), notes = [];
  for (const id of ids) {
    const d = DLG.work[id], path = `data/dialogues/${d._file || id + '.json'}`;
    files[path] = mergeDialogueFile(files[path] ?? await repoText(path), d);
  }
  if (keys.length) {
    files['localization/strings.csv'] = mergeStrings(await repoText('localization/strings.csv'), Object.fromEntries(keys.map(k => [k, DLG.strings[k]])));
    const missing = keys.filter(k => DLG_LOCALES.some(([l]) => !DLG.strings[k][l]));
    if (missing.length) notes.push(`Где нет перевода (${missing.length} строк), пока стоит английский или русский текст — их стоит перевести.`);
  }
  if (!ids.length && !keys.length) throw new Error('Нет изменённых диалогов');
  const fresh = ids.filter(id => !dlgOrig(id));
  if (fresh.length) notes.push(`Новые диалоги (${fresh.join(', ')}) пока никто не запускает: подключи их шагом «Диалог» в катсцене или полем "dialogue" у NPC.`);
  const names = [...new Set([...ids, ...keys.map(k => Object.entries({ ...DLG.data.dialogues, ...DLG.work }).find(([, d]) => Object.values(d.nodes || {}).some(n => n.text === k || (n.choices || []).some(c => c.text === k)))?.[0]).filter(Boolean)])];
  return { files, notes, title: `Studio: dialogue ${names.slice(0, 3).join(', ')}${names.length > 3 ? ` +${names.length - 3}` : ''}`,
    body: `Dialogues from the studio's «Диалоги»: ${names.join(', ')}.\n\n${ids.length} dialogue file edit(s), ${keys.length} string(s).` };
}
async function dlgEnter() {
  try { await dlgLoad(); } catch (e) { $('#dlgNodes').innerHTML = `<div class="warn">Нет данных (import/cutscenes.json): ${esc(e.message)}</div>`; return; }
  const sel = $('#dlgBg');
  if (sel.options.length <= 1 && library) sel.innerHTML = '<option value="">— без фона —</option>' + library.filter(e => e.cat === 'backgrounds' || e.cat === 'levels').map(e => `<option value="${esc(A(e.url))}">${esc(e.res.replace('res://assets/', ''))}</option>`).join('');
  try { const bg = localStorage.getItem('ss_dlgbg'); if (bg && !DLG.bg) { sel.value = bg; if (sel.value) loadImg(bg).then(im => { DLG.bg = im; dlgPaint(); }); } } catch {}
  if (!DLG.sel) DLG.sel = 'npc_matthew' in DLG.data.dialogues ? 'npc_matthew' : Object.keys(DLG.data.dialogues)[0] || null;
  const c = $('#dlgCanvas'); c.width = 1280; c.height = 720;
  renderDlg();
  document.fonts?.ready.then(dlgPaint);
}
function dlgInit() {
  if (!$('#dlgLayout')) return;
  $('#dlgSearch').addEventListener('input', renderDlgList);
  $('#dlgNodes').addEventListener('input', dlgNodeInput); $('#dlgNodes').addEventListener('change', dlgNodeInput);
  $('#dlgHead').addEventListener('change', e => {
    if (e.target.id === 'dlgBlocking') {
      const cap = e.target.value === 'caption', d = dlgCur();
      if (cap && Object.values(d.nodes).some(n => n.choices) && !confirm('В субтитрах не бывает ответов: проверка не пропустит диалог, пока они есть. Всё равно сменить?')) { e.target.value = 'panel'; return; }
      return dlgEdit(d => { if (cap) d.blocking = false; else delete d.blocking; });
    }
    if (e.target.dataset.hold) { DLG.holds[e.target.dataset.hold] = e.target.checked; DLG.nid = undefined; DLG.t0 = performance.now(); dlgPaint(); dlgMarkPreviewNode(); }
  });
  $('#dlgLook').addEventListener('change', e => { DLG.look = e.target.value; DLG.t0 = performance.now(); dlgPaint(); });
  $('#dlgLocale').addEventListener('change', e => { DLG.locale = e.target.value; dlgPaint(); });
  $('#dlgBg').addEventListener('change', e => { DLG.bg = null; try { localStorage.setItem('ss_dlgbg', e.target.value); } catch {} if (e.target.value) loadImg(e.target.value).then(im => { DLG.bg = im; dlgPaint(); }); else dlgPaint(); });
  $('#dlgCanvas').addEventListener('click', dlgCanvasClick);
  document.addEventListener('click', dlgAct);
  document.addEventListener('keydown', e => {
    if (mode !== 'dlg' || /INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName)) return;
    const d = dlgCur(), nid = d && dlgResolve(d, DLG.nid ?? d.start), n = nid && d.nodes[nid]; if (!d) return;
    if (/^[1-9]$/.test(e.key) && n?.choices?.[+e.key - 1]) dlgPreviewGo(n.choices[+e.key - 1].next || null);
    else if ((e.key === ' ' || e.key === 'Enter' || e.key === 'e') && n && !n.choices) { e.preventDefault(); dlgPreviewGo(n.next || null); }
    else if (e.key === 'Home') dlgPreviewGo(d.start);
  });
}
dlgInit();
