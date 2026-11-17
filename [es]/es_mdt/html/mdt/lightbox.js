// Full-screen photo viewer (shared by es_mdt and es_evidence; the same file in both).
//   Lightbox.open(items, index)  items: [{ src | load: async () => src, title, sub, meta: [[label, value], ...], actions: [{ label, run }] }]
// Click a photo to open it; wheel / + / - zoom (to the cursor), drag to pan, double-click to fit or 2x,
// arrows (keys or buttons) between photos, I toggles the side panel, Esc closes.
(function () {
  'use strict';
  if (window.Lightbox) return;
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  let root = null, items = [], idx = 0, z = 1, tx = 0, ty = 0, drag = null, panel = true, seq = 0;

  function build() {
    root = document.createElement('div');
    root.className = 'lbx hidden';
    root.innerHTML = `<div class="lbx-stage"><div class="lbx-spin"></div><img class="lbx-img" alt="" draggable="false"></div>
      <button class="lbx-btn lbx-prev" title="Previous (←)">‹</button><button class="lbx-btn lbx-next" title="Next (→)">›</button>
      <div class="lbx-top"><span class="lbx-count"></span><span class="lbx-sp"></span>
        <button class="lbx-tb" data-z="-1" title="Zoom out (-)">−</button><span class="lbx-zoom">100%</span><button class="lbx-tb" data-z="1" title="Zoom in (+)">+</button>
        <button class="lbx-tb" data-fit title="Fit (0)">Fit</button><button class="lbx-tb" data-info title="Details (I)">ⓘ</button><button class="lbx-tb lbx-x" title="Close (Esc)">✕</button></div>
      <aside class="lbx-side"></aside>`;
    document.body.appendChild(root);
    const stage = root.querySelector('.lbx-stage');
    root.querySelector('.lbx-prev').onclick = () => step(-1);
    root.querySelector('.lbx-next').onclick = () => step(1);
    root.querySelector('.lbx-x').onclick = close;
    root.querySelector('[data-fit]').onclick = fit;
    root.querySelector('[data-info]').onclick = () => { panel = !panel; root.classList.toggle('nopanel', !panel); };
    root.querySelectorAll('[data-z]').forEach((b) => b.onclick = () => zoomAt(+b.dataset.z > 0 ? 1.4 : 1 / 1.4));
    stage.addEventListener('wheel', (e) => { e.preventDefault(); zoomAt(e.deltaY < 0 ? 1.2 : 1 / 1.2, e.clientX, e.clientY); }, { passive: false });
    stage.addEventListener('mousedown', (e) => { if (e.button !== 0) return; drag = { x: e.clientX - tx, y: e.clientY - ty }; stage.classList.add('grab'); });
    window.addEventListener('mousemove', (e) => { if (!drag) return; tx = e.clientX - drag.x; ty = e.clientY - drag.y; apply(); });
    window.addEventListener('mouseup', () => { drag = null; stage.classList.remove('grab'); });
    stage.addEventListener('dblclick', (e) => { if (z > 1.05) fit(); else zoomAt(2, e.clientX, e.clientY); });
    stage.addEventListener('click', (e) => { if (e.target === stage && z <= 1.01) close(); });
    // capture phase: the page's own Esc (close the MDT / the modal) must not see it while this is open
    window.addEventListener('keydown', (e) => {
      if (!isOpen()) return;
      const k = e.key;
      if (k === 'Escape') close();
      else if (k === 'ArrowLeft') step(-1);
      else if (k === 'ArrowRight') step(1);
      else if (k === '+' || k === '=') zoomAt(1.4);
      else if (k === '-' || k === '_') zoomAt(1 / 1.4);
      else if (k === '0') fit();
      else if (k === 'i' || k === 'I') root.querySelector('[data-info]').click();
      else return;
      e.preventDefault(); e.stopImmediatePropagation();
    }, true);
  }
  const isOpen = () => root && !root.classList.contains('hidden');
  function apply() {
    const img = root.querySelector('.lbx-img');
    img.style.transform = `translate(${tx}px, ${ty}px) scale(${z})`;
    root.querySelector('.lbx-zoom').textContent = Math.round(z * 100) + '%';
    root.querySelector('.lbx-stage').classList.toggle('zoomed', z > 1.01);
  }
  function fit() { z = 1; tx = 0; ty = 0; apply(); }
  function zoomAt(f, cx, cy) {
    const stage = root.querySelector('.lbx-stage').getBoundingClientRect();
    const nz = Math.max(1, Math.min(8, z * f));
    if (cx == null) { cx = stage.left + stage.width / 2; cy = stage.top + stage.height / 2; }
    // keep the point under the cursor where it is
    const ox = cx - (stage.left + stage.width / 2), oy = cy - (stage.top + stage.height / 2);
    tx = ox - (ox - tx) * (nz / z); ty = oy - (oy - ty) * (nz / z);
    z = nz;
    if (z <= 1) { tx = 0; ty = 0; }
    apply();
  }
  async function show() {
    const it = items[idx] || {};
    const my = ++seq;
    const img = root.querySelector('.lbx-img');
    root.querySelector('.lbx-count').textContent = items.length > 1 ? `${idx + 1} / ${items.length}` : '';
    root.querySelector('.lbx-prev').style.display = items.length > 1 ? '' : 'none';
    root.querySelector('.lbx-next').style.display = items.length > 1 ? '' : 'none';
    const side = root.querySelector('.lbx-side');
    side.innerHTML = `<div class="lbx-title">${esc(it.title || 'Photo')}</div>${it.sub ? `<div class="lbx-sub">${esc(it.sub)}</div>` : ''}
      <div class="lbx-meta">${(it.meta || []).filter((m) => m && m[1] != null && m[1] !== '').map((m) => `<div><i>${esc(m[0])}</i><span>${esc(m[1])}</span></div>`).join('')}</div>
      <div class="lbx-dim hint"></div>
      ${(it.actions || []).length ? `<div class="lbx-acts">${it.actions.map((a, i) => `<button class="lbx-act" data-act="${i}">${esc(a.label)}</button>`).join('')}</div>` : ''}
      <div class="lbx-keys">Wheel or + / − zoom · drag to move · double-click 2× · ← → next · Esc close</div>`;
    side.querySelectorAll('[data-act]').forEach((b) => b.onclick = () => { const a = it.actions[+b.dataset.act]; if (a && a.run) a.run(close); });
    fit();
    root.classList.add('loading');
    img.removeAttribute('src');
    let src = it.src;
    if (!src && it.load) { try { src = await it.load(); } catch (e) { src = null; } }
    if (my !== seq) return;
    if (!src) { root.classList.remove('loading'); side.querySelector('.lbx-dim').textContent = 'The picture could not be loaded'; return; }
    it.src = src;
    img.onload = () => {
      if (my !== seq) return;
      root.classList.remove('loading');
      const kb = src.startsWith('data:') ? Math.round(src.length * 3 / 4 / 1024) : null;
      side.querySelector('.lbx-dim').textContent = `${img.naturalWidth} × ${img.naturalHeight}${kb ? ' · ' + (kb > 1024 ? (kb / 1024).toFixed(1) + ' MB' : kb + ' KB') : ''}`;
    };
    img.src = src;
  }
  function step(d) { if (items.length < 2) return; idx = (idx + d + items.length) % items.length; show(); }
  function open(list, start) {
    if (!root) build();
    items = (list || []).filter(Boolean); idx = Math.max(0, Math.min(items.length - 1, start || 0));
    if (!items.length) return;
    root.classList.remove('hidden'); root.classList.toggle('nopanel', !panel);
    requestAnimationFrame(() => root.classList.add('shown'));
    show();
  }
  function close() {
    if (!root) return;
    seq++;
    root.classList.remove('shown');
    setTimeout(() => { root.classList.add('hidden'); root.querySelector('.lbx-img').removeAttribute('src'); }, 140);
  }
  window.Lightbox = { open, close, isOpen };
})();
