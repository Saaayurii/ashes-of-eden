/* Sprite Studio — start-up. Plain scripts share one global scope; index.html loads them in order. */
'use strict';

/* ---------- init ---------- */
(async function init() {
  await loadMeta();
  try { projects = (await DB.all()) || []; }
  catch (e) { dbOk = false; projects = []; toast('Браузер не даёт хранить данные. Работа не сохранится между запусками, сохраняй проект в .json.', 'err'); }
  // the game's characters come in by themselves: behind «Из игры» alone, off the edge of a narrow header,
  // somebody opening the studio saw only the blank 'archer' and thought the game had none
  const fromGame = !projects.some(p => p.origin?.kind === 'game') && await fetch('import/list.json', { method: 'HEAD' }).then(r => r.ok, () => false);
  if (fromGame) await importFromUrl('import/list.json');
  if (!projects.length) projects = [newProject('archer')];
  let last = null; try { last = localStorage.getItem('ss_last'); } catch {}
  P = projects.find(p => p.id === last);
  // a first visit, or a blank template left selected by an earlier one, opens on the hero
  const blank = q => !q.origin && !q.reference && q.animations.every(a => a.frames.every(f => !f.src));
  if (fromGame && (!P || blank(P))) { P = projects.find(p => p.id === 'elian'); try { if (P) localStorage.setItem('ss_last', P.id); } catch {} }
  P = migrate(P || projects.slice().sort((a, b) => b.updated - a.updated)[0]);
  await persist();
  if (typeof JSZip === 'undefined') toast('Не загрузилась библиотека для zip (нужен интернет). Экспорт не будет работать.', 'err');
  const imp = new URLSearchParams(location.search).get('import');
  if (imp) { history.replaceState(null, '', location.pathname); await importFromUrl(imp); }
  try { if (localStorage.getItem('ss_noside')) { $('.layout').classList.add('noside'); $('#bgLayout').classList.add('noside'); } } catch {}
  await bgInit();
  refreshSent();
  renderAll(); applyPvBg(); syncPvControls(); scheduleBuild(0); requestAnimationFrame(loop);
  window.SS = { get P() { return P; }, build, sliceStrip, exportGodot, assignFiles, processed: () => processed };
})();
