/* Sprite Studio — start-up. Plain scripts share one global scope; index.html loads them in order. */
'use strict';

/* ---------- init ---------- */
(async function init() {
  await loadMeta();
  try { projects = (await DB.all()) || []; }
  catch (e) { dbOk = false; projects = []; toast('Браузер не даёт хранить данные. Работа не сохранится между запусками, сохраняй проект в .json.', 'err'); }
  if (!projects.length) { projects = [newProject('archer')]; }
  let last = null; try { last = localStorage.getItem('ss_last'); } catch {}
  P = migrate(projects.find(p => p.id === last) || projects.slice().sort((a, b) => b.updated - a.updated)[0]);
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
