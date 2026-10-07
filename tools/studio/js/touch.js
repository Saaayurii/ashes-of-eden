/* Sprite Studio — a tablet and a pencil (iPad + Apple Pencil, any pen tablet).
 *
 * The rules every drawing surface keeps:
 *   - touch-action: none, so Safari does not scroll or zoom the page mid-stroke;
 *   - one pointer at a time does the work; any other is ignored, so a palm resting
 *     on the glass does not drag or paint;
 *   - the pencil wins: a palm that landed first is let go (its handlers get a
 *     pointerup) the moment the pencil touches;
 *   - once a pencil has been seen on this device, a single finger no longer draws
 *     (that is what a palm is), and two fingers pinch and pan the view where the
 *     surface has one;
 *   - a pencil hovering over the glass (Apple Pencil Pro and iPad Pro M2+, which
 *     Safari reports as pen pointer moves with no button) can show where it would land.
 * Squeeze and double tap never reach a web page, so every tool has its button. */
'use strict';

const Ink = { penSeen: false };
try { Ink.penSeen = localStorage.getItem('ss_pen') === '1'; } catch {}
const notePen = e => { if (e.pointerType === 'pen' && !Ink.penSeen) { Ink.penSeen = true; try { localStorage.setItem('ss_pen', '1'); } catch {} } };

// Guards an element whose own pointer handlers expect one pointer (bg canvas, rig stage).
// o.fingers: 'use' (a finger works like the mouse) | 'ignore-after-pen' (a finger does nothing once a pencil was seen).
function palmGuard(el, o = {}) {
  let owner = null, ownerType = '';
  el.style.touchAction = 'none';
  const stop = e => { e.stopImmediatePropagation(); e.preventDefault(); };
  el.addEventListener('pointerdown', e => {
    notePen(e);
    if (e.pointerType === 'touch' && o.fingers === 'ignore-after-pen' && Ink.penSeen) return stop(e);
    if (owner !== null && e.pointerId !== owner) {
      // the pencil takes over from a palm that got there first
      if (e.pointerType === 'pen' && ownerType === 'touch') {
        el.dispatchEvent(new PointerEvent('pointerup', { pointerId: owner, pointerType: 'touch', bubbles: true, clientX: e.clientX, clientY: e.clientY }));
        owner = null;
      } else return stop(e);
    }
    owner = e.pointerId; ownerType = e.pointerType;
  }, true);
  for (const t of ['pointermove', 'pointerup', 'pointercancel']) el.addEventListener(t, e => {
    if (owner !== null && e.pointerId !== owner) return stop(e);
    if (t !== 'pointermove' && e.pointerId === owner) owner = null;
  }, true);
}

// A drawing surface with a view to pinch and pan: h = {
//   draw(e, phase)  phase 'down' | 'move' | 'up' — the pen, the mouse, or a finger when no pencil was ever seen;
//   hover(e | null) a pencil hovering, or gone;
//   view()          → {x, y, s} the surface's own pan and zoom; setView(v) applies it. }
function inkSurface(el, h) {
  const fingers = new Map(); let drawer = null, gesture = null;
  el.style.touchAction = 'none';
  const pinch = () => {
    const pts = [...fingers.values()], c = pts.reduce((a, p) => [a[0] + p[0] / pts.length, a[1] + p[1] / pts.length], [0, 0]);
    const d = pts.length > 1 ? Math.hypot(pts[0][0] - pts[1][0], pts[0][1] - pts[1][1]) : 0;
    return { c, d };
  };
  const startGesture = () => { const v = h.view?.(); if (!v) return; gesture = { v: { ...v }, ...pinch() }; };
  el.addEventListener('pointerdown', e => {
    notePen(e);
    if (e.pointerType === 'touch') {
      if (drawer !== null && drawer.type === 'pen') return;            // a palm under the pencil
      fingers.set(e.pointerId, [e.clientX, e.clientY]);
      if (fingers.size >= 2 || Ink.penSeen) {
        if (drawer !== null && drawer.type === 'touch') { h.draw(e, 'up'); drawer = null; }  // it was a pinch, not a stroke
        el.setPointerCapture(e.pointerId); startGesture(); return;
      }
    } else if (drawer !== null && drawer.type === 'touch') { h.draw(e, 'up'); drawer = null; }   // the pencil wins
    if (drawer !== null) return;
    drawer = { id: e.pointerId, type: e.pointerType };
    el.setPointerCapture(e.pointerId); h.hover?.(null); h.draw(e, 'down');
  });
  el.addEventListener('pointermove', e => {
    if (fingers.has(e.pointerId)) {
      fingers.set(e.pointerId, [e.clientX, e.clientY]);
      if (gesture) {
        const now = pinch(), s = gesture.d && now.d ? Math.max(0.5, Math.min(8, gesture.v.s * now.d / gesture.d)) : gesture.v.s, k = s / gesture.v.s;
        // the point under the fingers' centre stays under it
        h.setView?.({ s, x: now.c[0] - (gesture.c[0] - gesture.v.x) * k, y: now.c[1] - (gesture.c[1] - gesture.v.y) * k });
        return;
      }
    }
    if (drawer && e.pointerId === drawer.id) return h.draw(e, 'move');
    if (!drawer && e.pointerType === 'pen' && !e.buttons) h.hover?.(e);
  });
  const end = e => {
    if (fingers.delete(e.pointerId)) { if (fingers.size < 2 && gesture && !Ink.penSeen) gesture = null; if (!fingers.size) gesture = null; else if (gesture) startGesture(); }
    if (drawer && e.pointerId === drawer.id) { drawer = null; h.draw(e, 'up'); }
  };
  el.addEventListener('pointerup', end); el.addEventListener('pointercancel', end);
  el.addEventListener('pointerleave', e => { if (e.pointerType === 'pen' && !drawer) h.hover?.(null); });
}

// Where an event lands on an element, in the element's own pixels, whatever CSS scale it is shown at.
function localPoint(el, e) {
  const r = el.getBoundingClientRect();
  return [(e.clientX - r.left) * el.width / r.width, (e.clientY - r.top) * el.height / r.height];
}
