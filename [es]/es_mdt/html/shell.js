// es_mdt 2.0.2: routes the game's messages to the part they belong to ({ __app, m } from shared/env.lua), keeps
// them until that part's frame has loaded, and raises the part that holds the game's focus ({ __shell: 'focus' }).
// Anything else (whip_core's own messages) goes to every part. 2.0.2: each player's display size (below).
(function () {
  'use strict';
  const PARTS = ['mdt', 'departments', 'doj'];
  const frame = {}, ready = {}, queue = {};
  const focused = new Set();
  let top = null;

  PARTS.forEach((p) => {
    const f = document.getElementById('part-' + p);
    frame[p] = f; ready[p] = false; queue[p] = [];
    f.addEventListener('load', () => {
      ready[p] = true;
      const q = queue[p]; queue[p] = [];
      q.forEach((m) => f.contentWindow.postMessage(m, '*'));
    });
  });

  function send(p, m) {
    if (!frame[p]) return;
    if (ready[p]) frame[p].contentWindow.postMessage(m, '*');
    else queue[p].push(m);
  }
  function raise(p) {
    top = p;
    PARTS.forEach((x) => frame[x].classList.toggle('focus', x === p));
    if (p) { try { frame[p].contentWindow.focus(); } catch (e) { /* not loaded yet */ } }
  }
  function focus(p, on) {
    if (!frame[p]) return;
    if (on) { focused.delete(p); focused.add(p); raise(p); return; }
    focused.delete(p);
    if (top === p) raise(focused.size ? Array.from(focused).pop() : null);
  }

  // ---------------------------------------------------------------- 2.0.2: display size
  // Each player's own size (client/ui.lua keeps it in KVP). A page is scaled as a whole frame: the frame is 100/s %
  // of the screen and scaled by s, so it still fills the screen and nothing inside the page has to know.
  const SC = { scale: 1, min: 0.7, max: 1.5, def: 1, custom: false, known: false };
  const $ = (id) => document.getElementById(id);
  const pop = $('es-scale'), back = $('es-scale-back'), rng = $('es-scale-range');
  const res = (() => { try { return GetParentResourceName(); } catch (e) { return 'es_mdt'; } })();
  const pct = (v) => Math.round(v * 100);
  function post(name, body) {
    return fetch(`https://${res}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body || {}) })
      .then((r) => r.json());
  }
  function apply(v) {
    SC.scale = v;
    PARTS.forEach((p) => {
      const f = frame[p];
      if (Math.abs(v - 1) < 0.001) {
        f.classList.remove('scaled'); f.style.width = ''; f.style.height = ''; f.style.transform = '';
      } else {
        f.classList.add('scaled');
        f.style.width = (100 / v) + 'vw'; f.style.height = (100 / v) + 'vh'; f.style.transform = `scale(${v})`;
      }
    });
    draw();
  }
  function clamp(v) { v = Math.round(Number(v) * 100) / 100; if (!isFinite(v)) v = SC.def; return Math.min(SC.max, Math.max(SC.min, v)); }
  function takeState(d) {
    if (!d || typeof d !== 'object' || typeof d.scale !== 'number') return;
    SC.min = Number(d.min) || 0.7; SC.max = Number(d.max) || 1.5; SC.def = Number(d.def) || 1; SC.custom = !!d.custom; SC.known = true;
    apply(clamp(d.scale));
  }
  function ask() { post('esui_scale_get').then(takeState).catch(() => { /* client/ui.lua not ready yet: asked again on the next open */ }); }
  let saveT = null;
  function save(v) {
    clearTimeout(saveT);
    saveT = setTimeout(() => { post('esui_scale', { scale: v }).then((d) => { if (d && typeof d.scale === 'number') SC.custom = !!d.custom; draw(); }).catch(() => {}); }, 300);
  }
  function setScale(v, persist) {
    v = clamp(v);
    if (persist) { SC.custom = true; save(v); }
    apply(v);
  }
  function draw() {
    if (!pop) return;
    const lo = pct(SC.min), hi = pct(SC.max), now = pct(SC.scale);
    rng.min = lo; rng.max = hi; rng.value = now;
    rng.style.setProperty('--p', ((now - lo) / Math.max(1, hi - lo) * 100) + '%');
    $('es-scale-val').textContent = now + '%';
    $('es-scale-lo').textContent = lo + '%'; $('es-scale-hi').textContent = hi + '%';
    $('es-scale-minus').disabled = now <= lo; $('es-scale-plus').disabled = now >= hi;
    const d = pct(SC.def);
    $('es-scale-reset').disabled = now === d && !SC.custom;
    $('es-scale-reset').textContent = `Reset to ${d}%`;
    const want = [[Math.max(lo, 85), 'Small'], [d, 'Default'], [Math.min(hi, 115), 'Large'], [Math.min(hi, 130), 'Larger']];
    const seen = new Set(), chips = $('es-scale-chips');
    chips.innerHTML = '';
    want.forEach(([v, label]) => {
      if (seen.has(v)) return; seen.add(v);
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'chip' + (v === now ? ' on' : ''); b.textContent = `${label} ${v}%`;
      b.addEventListener('click', () => setScale(v / 100, true));
      chips.appendChild(b);
    });
  }
  function openPop(src, rect) {
    if (!pop || !top) return;
    let s = SC.scale, x = window.innerWidth / 2 + 160, y = 80;
    if (rect && isFinite(rect.right) && isFinite(rect.bottom)) { x = rect.right * s; y = rect.bottom * s + 8; }
    pop.hidden = false; back.hidden = false; draw();
    const w = pop.offsetWidth, h = pop.offsetHeight;
    pop.style.left = Math.max(8, Math.min(window.innerWidth - w - 8, x - w)) + 'px';
    pop.style.top = Math.max(8, Math.min(window.innerHeight - h - 8, y)) + 'px';
    requestAnimationFrame(() => pop.classList.add('on'));
    rng.focus();
  }
  function closePop() {
    if (!pop || pop.hidden) return;
    pop.classList.remove('on'); pop.hidden = true; back.hidden = true;
    if (top) { try { frame[top].contentWindow.focus(); } catch (e) { /* gone */ } }
  }
  if (pop) {
    rng.addEventListener('input', () => setScale(rng.value / 100, true));
    $('es-scale-minus').addEventListener('click', () => setScale(SC.scale - 0.05, true));
    $('es-scale-plus').addEventListener('click', () => setScale(SC.scale + 0.05, true));
    $('es-scale-reset').addEventListener('click', () => {
      clearTimeout(saveT); SC.custom = false; apply(SC.def);
      post('esui_scale', { reset: true }).then(takeState).catch(() => {});
    });
    back.addEventListener('mousedown', closePop);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !pop.hidden) { e.preventDefault(); closePop(); } });
  }
  ask();

  window.addEventListener('message', (ev) => {
    // a part's frame may only ask for the display-size popover
    if (ev.source && ev.source !== window && ev.source !== window.parent) {
      const p = PARTS.find((x) => frame[x].contentWindow === ev.source);
      const d = ev.data;
      if (p && p === top && d && d.__esScale === 'open') openPop(p, d.rect);
      return;
    }
    // otherwise only the game (no source, or this page) talks to the shell
    let d = ev.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { return; } }
    if (!d || typeof d !== 'object') return;
    if (d.__shell === 'focus') { focus(d.app, !!d.on); if (d.on && !SC.known) ask(); if (!top) closePop(); return; }
    if (d.__shell === 'scale') { takeState(d); return; }
    if (d.__app) { send(d.__app, d.m); return; }
    PARTS.forEach((p) => send(p, d));
  });

  window.EsShell = { send, focus, parts: PARTS, scale: () => SC.scale, setScale: (v) => setScale(v, false), openScale: () => openPop(top) };
})();
