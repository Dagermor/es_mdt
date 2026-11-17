// es_mdt 2.0.0: routes the game's messages to the part they belong to ({ __app, m } from shared/env.lua), keeps
// them until that part's frame has loaded, and raises the part that holds the game's focus ({ __shell: 'focus' }).
// Anything else (whip_core's own messages) goes to every part.
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

  window.addEventListener('message', (ev) => {
    // only the game (no source, or this page) talks to the shell; a part's frame never does
    if (ev.source && ev.source !== window && ev.source !== window.parent) return;
    let d = ev.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { return; } }
    if (!d || typeof d !== 'object') return;
    if (d.__shell === 'focus') { focus(d.app, !!d.on); return; }
    if (d.__app) { send(d.__app, d.m); return; }
    PARTS.forEach((p) => send(p, d));
  });

  window.EsShell = { send, focus, parts: PARTS };
})();
