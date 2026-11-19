// es_mdt 2.0.9: the Live map tab. Every unit on duty the viewer may see (callsign, name, department colour, status, in a
// car or on foot, heading, speed) and the active calls (priority colours, search areas, who is responding), live while
// the tab is open. Smooth pan and zoom, click a unit or a call for details and actions, filter by department.
// The server decides who sees what (Config.LiveMap, the Dispatch routing); this page only draws and asks.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, post, toast, said, busy, ago, empty, go, VIEWS, HOOK } = M;
  const cfg = () => (S.ctx && S.ctx.config) || {};
  const lmCfg = () => cfg().liveMap || { enabled: true, units: 'group', image: 'img/map.webp', calls: true, bolos: true };

  // GTA world -> the 4096 px map picture (the atlas layout img/map.webp uses)
  const SIZE = 4096;
  const toMap = (wx, wy) => [((0.02072 * wx + 117.3) / 256) * SIZE, ((-0.0205 * wy + 172.8) / 256) * SIZE];
  const metresToPx = (m) => (0.02072 * m / 256) * SIZE;
  const MIN_Z = 0.16, MAX_Z = 4;

  const L = {
    z: 0.5, x: 0, y: 0, tz: null,          // view: zoom, offset; tz = an animation going on
    data: null, timer: null, at: 0, busy: false, seq: 0,
    sel: null,                               // 'u:<charId>' | 'c:<id>' | 'b:<id>'
    follow: false,                           // keep the selected unit in the middle
    tab: 'units', q: '',
    show: { units: true, calls: true, areas: true, routes: true, bolos: true, labels: true },
    hidden: new Set(),                       // departments filtered out (by short name)
    style: localStorage.getItem('esmdt_map_style') || 'dark',
    pins: new Map(), centered: false,
  };
  const PRI_COL = { 1: '#ef4444', 2: '#f59e0b', 3: '#60a5fa' };
  const statusOf = (k) => M.statusOf ? M.statusOf(k) : { label: k, color: '#8a93a6' };
  const speedTxt = (ms, units) => ms == null ? '' : `${Math.round(ms * (units === 'kmh' ? 3.6 : 2.236936))} ${units === 'kmh' ? 'km/h' : 'mph'}`;
  const ICON = {
    car: '<svg viewBox="0 0 24 24" width="12" height="12"><path fill="currentColor" d="M5 11l1.5-4.5A2 2 0 0 1 8.4 5h7.2a2 2 0 0 1 1.9 1.5L19 11v6a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-1H8v1a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1zm2.2 0h9.6l-1-3.2a.6.6 0 0 0-.6-.4H8.8a.6.6 0 0 0-.6.4zM7.5 14.5a1.2 1.2 0 1 0 0-2.4 1.2 1.2 0 0 0 0 2.4m9 0a1.2 1.2 0 1 0 0-2.4 1.2 1.2 0 0 0 0 2.4"/></svg>',
    foot: '<svg viewBox="0 0 24 24" width="12" height="12"><path fill="currentColor" d="M13.5 5.5a2 2 0 1 0 0-4 2 2 0 0 0 0 4M9.8 8.9 7 23h2.1l1.8-8 2.1 2v6h2v-7.5l-2.1-2 .6-3A7.3 7.3 0 0 0 19 13v-2a5 5 0 0 1-4.3-2.4l-1-1.6a2 2 0 0 0-1.7-1c-.3 0-.5 0-.8.1L6 8.3V13h2V9.6z"/></svg>',
  };

  // ---------------------------------------------------------------- the page
  VIEWS.livemap = async (v) => {
    const lc = lmCfg();
    if (lc.enabled === false && !S.ctx.staff) { v.innerHTML = empty('The live map is turned off on this server'); return; }
    if (!(S.ctx.onDuty || S.ctx.staff)) { v.innerHTML = empty('Go on duty to see the live map'); return; }
    stop();
    L.pins = new Map();
    v.innerHTML = `<div class="lm">
      <div class="lm-map" id="lm-map" tabindex="0" aria-label="Live map: drag to move, scroll to zoom"><div class="lm-cross" aria-hidden="true"></div>
        <div class="lm-inner" id="lm-inner">
          <img id="lm-img" alt="" draggable="false">
          <svg class="lm-svg" id="lm-svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}"></svg>
          <div id="lm-pins"></div>
        </div>
        <div class="lm-top">
          <div class="lm-row1">
            <div class="lm-search"><span>⌕</span><input id="lm-q" placeholder="Find a unit or call" maxlength="40" value="${esc(L.q)}"></div>
            <button class="lm-chip" id="lm-layers-btn" data-probe-press>Layers ▾</button>
          </div>
          <div class="lm-depts hidden" id="lm-depts"></div>
          <div class="lm-layer-pop hidden" id="lm-layers">${[['units', 'Units'], ['calls', 'Calls'], ['areas', 'Search areas'], ['routes', 'Responding lines'], ['bolos', 'BOLO plates'], ['labels', 'Labels']]
            .filter(([k]) => (k !== 'bolos' || lc.bolos !== false) && (!['calls', 'areas', 'routes'].includes(k) || lc.calls !== false))
            .map(([k, l]) => `<button class="lm-tog${L.show[k] ? ' on' : ''}" data-layer="${k}" data-probe-press><i></i>${l}</button>`).join('')}</div>
        </div>
        <div class="lm-tools">
          <button class="lm-tool" data-z="1" title="Zoom in (+)" data-probe-press>+</button>
          <button class="lm-tool" data-z="-1" title="Zoom out (−)" data-probe-press>−</button>
          <button class="lm-tool" id="lm-me" title="Centre on me" data-probe-press>◎</button>
          <button class="lm-tool" id="lm-fit" title="Show everyone (0)" data-probe-press>⤢</button>
          <button class="lm-tool${L.style === 'atlas' ? ' on' : ''}" id="lm-style" title="Map style: dark / atlas" data-probe-press>◐</button>
        </div>
        <div class="lm-stamp" id="lm-stamp"><span class="lm-live"></span><span id="lm-stamp-t">Loading…</span></div>
      </div>
      <aside class="lm-side">
        <div class="lm-tabs"><button data-tab="units" class="${L.tab === 'units' ? 'on' : ''}" data-probe-press>Units <b id="lm-nu">0</b></button>
          <button data-tab="calls" class="${L.tab === 'calls' ? 'on' : ''}" data-probe-press>Calls <b id="lm-nc">0</b></button></div>
        <div class="lm-detail hidden" id="lm-detail"></div>
        <div class="lm-list" id="lm-list"><div class="loading-row"><div class="spin"></div></div></div>
        <div class="lm-foot hint" id="lm-foot"></div>
      </aside>
    </div>`;
    wire(v);
    poll(true);
  };

  // 2.0.10: the picture. GTA's map (the default) shows as a 2048 px copy (a quarter of the memory) until zoomed in, then
  // the full 4096 one; both are let go when the tab is left or the MDT closes. Any other picture is used as it is.
  const FULL = 'img/map.webp', LIGHT = 'img/map_2048.webp';
  function release() {
    if (L.img) { L.img.onerror = null; L.img.onload = null; L.img.removeAttribute('src'); L.img = null; }
    if (L.hi) { L.hi.onload = null; L.hi.src = ''; L.hi = null; }
    L.full = false;
  }
  function hiRes() {
    const img = L.img;
    if (!img || L.full || L.hi || !L.light || L.z <= 0.6) return;
    const hi = new Image();
    L.hi = hi;
    hi.onload = () => { if (L.img === img && L.hi === hi) { L.full = true; img.src = FULL; } L.hi = null; };
    hi.onerror = () => { L.hi = null; L.full = true; };   // the full one is missing: stay on the light one
    hi.src = FULL;
  }
  function stop() { clearTimeout(L.timer); L.timer = null; L.seq++; release(); }

  // ---------------------------------------------------------------- pan and zoom (smooth)
  const mapEl = () => $('#lm-map');
  function apply() {
    const inner = $('#lm-inner'); if (!inner) return;
    inner.style.transform = `translate3d(${L.x}px, ${L.y}px, 0) scale(${L.z})`;
    inner.style.setProperty('--inv', (1 / L.z).toFixed(4));
    inner.classList.toggle('far', L.z < 0.3);
    hiRes();
  }
  function clampView() {
    const m = mapEl(); if (!m) return;
    const w = m.clientWidth, h = m.clientHeight, s = SIZE * L.z, pad = 120;
    L.x = Math.min(w - pad, Math.max(pad - s, L.x));
    L.y = Math.min(h - pad, Math.max(pad - s, L.y));
  }
  /** animate to zoom z keeping screen point (cx, cy) still */
  function zoomTo(z, cx, cy, animate) {
    z = Math.max(MIN_Z, Math.min(MAX_Z, z));
    const k = z / L.z;
    const nx = cx - (cx - L.x) * k, ny = cy - (cy - L.y) * k;
    flyTo(z, nx, ny, animate === false ? 0 : 180);
  }
  function flyTo(z, x, y, ms) {
    cancelAnimationFrame(L.tz);
    const from = { z: L.z, x: L.x, y: L.y }, t0 = performance.now();
    if (!ms) { L.z = z; L.x = x; L.y = y; clampView(); apply(); return; }
    const step = (t) => {
      const p = Math.min(1, (t - t0) / ms), e = 1 - Math.pow(1 - p, 3);
      L.z = from.z + (z - from.z) * e; L.x = from.x + (x - from.x) * e; L.y = from.y + (y - from.y) * e;
      clampView(); apply();
      if (p < 1) L.tz = requestAnimationFrame(step);
    };
    L.tz = requestAnimationFrame(step);
  }
  function centreOn(wx, wy, z, ms) {
    const m = mapEl(); if (!m) return;
    z = z || L.z;
    const [px, py] = toMap(wx, wy);
    flyTo(z, m.clientWidth / 2 - px * z, m.clientHeight / 2 - py * z, ms == null ? 350 : ms);
  }
  function fitAll() {
    const d = L.data, m = mapEl(); if (!m) return;
    const pts = [];
    if (d) { visUnits().forEach((u) => pts.push(toMap(u.x, u.y))); if (L.show.calls) visCalls().forEach((c) => pts.push(toMap(c.x, c.y))); }
    if (pts.length < 2) { const p = pts[0]; if (p) { const z = 1; flyTo(z, m.clientWidth / 2 - p[0] * z, m.clientHeight / 2 - p[1] * z, 350); } else whole(); return; }
    const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
    const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
    const z = Math.max(MIN_Z, Math.min(1.6, Math.min((m.clientWidth - 160) / Math.max(1, x1 - x0), (m.clientHeight - 160) / Math.max(1, y1 - y0))));
    flyTo(z, m.clientWidth / 2 - ((x0 + x1) / 2) * z, m.clientHeight / 2 - ((y0 + y1) / 2) * z, 400);
  }
  function whole() { const m = mapEl(); if (!m) return; const z = Math.max(MIN_Z, Math.min(m.clientWidth, m.clientHeight) / SIZE * 1.15); flyTo(z, (m.clientWidth - SIZE * z) / 2, (m.clientHeight - SIZE * z) / 2 + 40, 350); }

  // ---------------------------------------------------------------- wiring
  function wire(v) {
    const m = mapEl();
    const img = $('#lm-img');
    const lc = lmCfg();
    const want = lc.image || FULL;
    L.img = img; L.full = false; L.light = want === FULL;
    img.onerror = () => {
      if (img.getAttribute('src') === LIGHT) { L.light = false; L.full = true; img.src = FULL; return; }   // no light copy: the full one
      if (!img.dataset.fallback && img.getAttribute('src') !== FULL) { img.dataset.fallback = '1'; L.light = false; L.full = true; img.src = FULL; }
      else { img.classList.add('none'); m.classList.add('no-img'); }
    };
    img.src = L.light ? LIGHT : want;
    m.classList.toggle('atlas', L.style === 'atlas');
    m.addEventListener('wheel', (e) => { e.preventDefault(); const r = m.getBoundingClientRect(); const f = Math.exp(-Math.max(-120, Math.min(120, e.deltaY)) * 0.0022); zoomTo(L.z * f, e.clientX - r.left, e.clientY - r.top); }, { passive: false });
    m.addEventListener('dblclick', (e) => { if (e.target.closest('.lp, .lm-top, .lm-tools')) return; const r = m.getBoundingClientRect(); zoomTo(L.z * 2, e.clientX - r.left, e.clientY - r.top); });
    let drag = null;
    m.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || e.target.closest('.lp, .lm-top, .lm-tools, .lm-stamp')) return;
      cancelAnimationFrame(L.tz);
      drag = { x: e.clientX, y: e.clientY, ox: L.x, oy: L.y, moved: false, id: e.pointerId };
      m.setPointerCapture(e.pointerId);
    });
    m.addEventListener('pointermove', (e) => {
      if (!drag) return;
      const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (!drag.moved && Math.abs(dx) + Math.abs(dy) < 4) return;
      if (!drag.moved) { drag.moved = true; m.classList.add('grab'); if (L.follow) setFollow(false); }
      L.x = drag.ox + dx; L.y = drag.oy + dy; clampView(); apply();
    });
    const end = (e) => { if (!drag) return; const was = drag.moved; drag = null; m.classList.remove('grab'); if (!was && !e.target.closest('.lp')) select(null); };
    m.addEventListener('pointerup', end); m.addEventListener('pointercancel', end);
    m.addEventListener('keydown', (e) => {
      const cx = m.clientWidth / 2, cy = m.clientHeight / 2;
      if (e.key === '+' || e.key === '=') zoomTo(L.z * 1.5, cx, cy);
      else if (e.key === '-' || e.key === '_') zoomTo(L.z / 1.5, cx, cy);
      else if (e.key === '0') fitAll();
      else if (e.key.startsWith('Arrow')) { const s = 120; flyTo(L.z, L.x + (e.key === 'ArrowLeft' ? s : e.key === 'ArrowRight' ? -s : 0), L.y + (e.key === 'ArrowUp' ? s : e.key === 'ArrowDown' ? -s : 0), 150); }
      else return;
      e.preventDefault();
    });
    $$('[data-z]', v).forEach((b) => b.onclick = () => zoomTo(L.z * (+b.dataset.z > 0 ? 1.6 : 1 / 1.6), m.clientWidth / 2, m.clientHeight / 2));
    $('#lm-me').onclick = () => { const me = mine(); if (me) { select('u:' + me.charId, true); } else toast('You are not on the map', 'bad'); };
    $('#lm-fit').onclick = () => fitAll();
    $('#lm-style').onclick = (e) => { L.style = L.style === 'dark' ? 'atlas' : 'dark'; localStorage.setItem('esmdt_map_style', L.style); m.classList.toggle('atlas', L.style === 'atlas'); e.currentTarget.classList.toggle('on', L.style === 'atlas'); };
    const lp = $('#lm-layers');
    $('#lm-layers-btn').onclick = (e) => { e.stopPropagation(); lp.classList.toggle('hidden'); e.currentTarget.classList.toggle('on', !lp.classList.contains('hidden')); };
    m.addEventListener('pointerdown', (e) => { if (!e.target.closest('#lm-layers, #lm-layers-btn')) { lp.classList.add('hidden'); $('#lm-layers-btn').classList.remove('on'); } });
    $$('[data-layer]', v).forEach((b) => b.onclick = () => { const k = b.dataset.layer; L.show[k] = !L.show[k]; b.classList.toggle('on', L.show[k]); m.classList.toggle('no-labels', !L.show.labels); draw(); });
    m.classList.toggle('no-labels', !L.show.labels);
    $$('[data-tab]', v).forEach((b) => b.onclick = () => { L.tab = b.dataset.tab; $$('[data-tab]', v).forEach((x) => x.classList.toggle('on', x === b)); list(); });
    let qT = null;
    $('#lm-q').oninput = (e) => { clearTimeout(qT); qT = setTimeout(() => { L.q = e.target.value.trim().toLowerCase(); list(); draw(); }, 120); };
    $('#lm-q').onkeydown = (e) => { if (e.key === 'Enter') { const first = $('#lm-list [data-sel]'); if (first) first.click(); } };
    window.addEventListener('resize', onResize);
    if (!L.centered) { L.z = 0.5; whole(); L.z = Math.max(MIN_Z, L.z); }
    flyTo(L.z, L.x, L.y, 0);
  }
  function onResize() { if (S.view !== 'livemap' || !mapEl()) { window.removeEventListener('resize', onResize); return; } clampView(); apply(); }

  // ---------------------------------------------------------------- data
  async function poll(first) {
    clearTimeout(L.timer);
    if (S.view !== 'livemap' || !mapEl()) { release(); return; }
    const seq = L.seq;
    if (S.open && !document.hidden && !L.busy) {
      L.busy = true;
      const r = await call('mapData');
      L.busy = false;
      if (seq !== L.seq || S.view !== 'livemap' || !mapEl()) return;
      if (r.ok) {
        L.data = r.data; L.at = Date.now();
        depts(); draw(); list(); detail();
        if (first && !L.centered) {
          L.centered = true;
          const me = mine();
          if (me) centreOn(me.x, me.y, Math.max(L.z, 0.55), 0); else fitAll();
        } else if (L.follow && L.sel && L.sel[0] === 'u') { const u = unitById(+L.sel.slice(2)); if (u) centreOn(u.x, u.y, null, 900); }
      } else if (first) { $('#lm-stamp-t').textContent = r.why || 'The map is not available'; $('#lm-list').innerHTML = empty(r.why || 'The map is not available'); }
    }
    stamp();
    L.timer = setTimeout(() => poll(false), Math.max(1000, cfg().mapRefreshMs || 2500));
  }
  setInterval(() => { if (S.view === 'livemap' && mapEl()) stamp(); }, 1000);
  function stamp() {
    const d = L.data; const el = $('#lm-stamp-t'); if (!el || !d) return;
    const secs = Math.max(0, Math.round((Date.now() - L.at) / 1000));
    el.textContent = `${visUnits().length} on duty · ${visCalls().length} active call${visCalls().length === 1 ? '' : 's'} · ${secs < 2 ? 'live' : secs + ' s ago'}`;
    $('#lm-stamp').classList.toggle('stale', secs > 10);
  }

  const unitById = (id) => ((L.data && L.data.units) || []).find((u) => u.charId === id);
  const callById = (id) => ((L.data && L.data.calls) || []).find((c) => c.id === id);
  const mine = () => L.data && unitById(L.data.me || S.ctx.me.charId);
  const matchQ = (s) => !L.q || String(s || '').toLowerCase().includes(L.q);
  const visUnits = () => ((L.data && L.data.units) || []).filter((u) => !L.hidden.has(u.deptShort || '?'));
  const visCalls = () => lmCfg().calls === false ? [] : ((L.data && L.data.calls) || []);

  function depts() {
    const box = $('#lm-depts'); if (!box) return;
    const seen = new Map();
    ((L.data && L.data.units) || []).forEach((u) => { const k = u.deptShort || '?'; const x = seen.get(k) || { n: 0, color: u.color1 || '#3b82f6', name: u.deptName || k }; x.n++; seen.set(k, x); });
    if (seen.size < 2 && !L.hidden.size) { box.innerHTML = ''; box.classList.add('hidden'); return; }
    box.classList.remove('hidden');
    box.innerHTML = [...seen.entries()].sort((a, b) => b[1].n - a[1].n).map(([k, x]) => `<button class="lm-dept${L.hidden.has(k) ? ' off' : ''}" data-dept="${esc(k)}" title="${esc(x.name)}: show / hide" style="--dc:${esc(x.color)}" data-probe-press><i></i>${esc(k)} <b>${x.n}</b></button>`).join('');
    $$('[data-dept]', box).forEach((b) => b.onclick = () => { const k = b.dataset.dept; if (L.hidden.has(k)) L.hidden.delete(k); else L.hidden.add(k); depts(); draw(); list(); });
  }

  // ---------------------------------------------------------------- drawing (kept pins move smoothly between updates)
  function pinEl(key, cls, html, x, y) {
    let el = L.pins.get(key);
    const host = $('#lm-pins');
    if (!el) {
      el = document.createElement('div'); el.dataset.k = key; el.className = cls;
      el.style.transform = `translate3d(${x}px, ${y}px, 0)`;
      el.addEventListener('click', (e) => { e.stopPropagation(); select(key, false); });
      host.appendChild(el); L.pins.set(key, el); el._html = '';
    } else {
      if (el.className !== cls) el.className = cls;
      el.style.transform = `translate3d(${x}px, ${y}px, 0)`;
    }
    if (el._html !== html) { el.innerHTML = html; el._html = html; }
    el._keep = true;
    return el;
  }
  function draw() {
    const host = $('#lm-pins'), svg = $('#lm-svg'); if (!host || !L.data) return;
    L.pins.forEach((el) => el._keep = false);
    const d = L.data, sel = L.sel, me = d.me || S.ctx.me.charId;
    const lines = [], areas = [];
    const calls = L.show.calls ? visCalls() : [];
    calls.forEach((c) => {
      const [x, y] = toMap(c.x, c.y);
      const hit = matchQ(`#${c.id} ${c.title} ${c.street}`);
      if (L.show.areas && c.radius) areas.push(`<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${metresToPx(c.radius).toFixed(1)}" class="lm-area p${c.priority}"/>`);
      const ico = c.kind === 'panic' ? '⚠' : c.kind === 'backup' ? '⇶' : (c.icon || '☎');
      const cls = `lp lp-call p${c.priority}${c.critical ? ' crit' : ''}${c.kind === 'panic' ? ' panic' : ''}${c.mine ? ' mine' : ''}${sel === 'c:' + c.id ? ' sel' : ''}${hit ? '' : ' dim'}`;
      pinEl('c:' + c.id, cls, `<div class="lp-b"><span class="lp-m">${esc(ico)}</span><span class="lp-l">#${c.id}${(c.units || []).length ? ` · ${(c.units || []).length}` : ''}${c.follows ? ' · live' : ''}${c.backup ? ' · backup' : ''}</span></div>`, x, y);
      // 2.0.15: backup asked on this call: the asking officer's live spot, linked to the call (which stays where it is)
      if (c.backup && c.backup.x != null) {
        const [bx, by] = toMap(c.backup.x, c.backup.y);
        lines.push(`<line x1="${x.toFixed(1)}" y1="${y.toFixed(1)}" x2="${bx.toFixed(1)}" y2="${by.toFixed(1)}" class="lm-bkline"/>`);
        const who = String(c.backup.by || '').split(' ')[0];
        pinEl('k:' + c.id, `lp lp-bk${sel === 'c:' + c.id ? ' sel' : ''}${hit ? '' : ' dim'}`, `<div class="lp-b"><span class="lp-m">🚨</span><span class="lp-l">Backup · ${esc(who)} · #${c.id}</span></div>`, bx, by);
      }
    });
    const units = L.show.units ? visUnits() : [];
    const byId = new Map(units.map((u) => [u.charId, u]));
    if (L.show.routes && L.show.calls) calls.forEach((c) => (c.units || []).forEach((cu) => {
      const u = byId.get(cu.charId); if (!u) return;
      const [x1, y1] = toMap(u.x, u.y), [x2, y2] = toMap(c.x, c.y);
      lines.push(`<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" class="lm-line p${c.priority}${L.sel === 'u:' + u.charId || L.sel === 'c:' + c.id ? ' sel' : ''}"/>`);
    }));
    units.forEach((u) => {
      const [x, y] = toMap(u.x, u.y);
      const st = statusOf(u.status);
      const hit = matchQ(`${u.callsign} ${u.name} ${u.deptShort}`);
      const cls = `lp lp-unit${u.car ? ' car' : ' foot'}${u.panic ? ' panic' : ''}${u.charId === me ? ' me' : ''}${sel === 'u:' + u.charId ? ' sel' : ''}${hit ? '' : ' dim'}`;
      const label = u.callsign || (u.name || '').split(' ')[0] || '?';
      pinEl('u:' + u.charId, cls, `<div class="lp-b" style="--gc:${esc(u.color1 || '#3b82f6')};--sc:${esc(st.color)}"><span class="lp-m"><i class="lp-h" style="transform:rotate(${-(u.h || 0)}deg)"></i>${u.car ? ICON.car : ICON.foot}</span><span class="lp-l">${esc(label)}</span></div>`, x, y);
    });
    if (L.show.bolos && lmCfg().bolos !== false) (d.bolos || []).forEach((b) => {
      const [x, y] = toMap(b.x, b.y);
      pinEl('b:' + b.id, `lp lp-bolo${sel === 'b:' + b.id ? ' sel' : ''}`, `<div class="lp-b"><span class="lp-m">⚑</span><span class="lp-l">${esc(b.plate || 'BOLO')}</span></div>`, x, y);
    });
    svg.innerHTML = areas.join('') + lines.join('');
    L.pins.forEach((el, k) => { if (!el._keep) { el.remove(); L.pins.delete(k); } });
    if (L.sel && !L.pins.has(L.sel)) { L.sel = null; L.follow = false; detail(); }
  }

  // ---------------------------------------------------------------- side list
  function list() {
    const box = $('#lm-list'); if (!box || !L.data) return;
    const d = L.data, units = visUnits(), calls = visCalls();
    $('#lm-nu').textContent = units.length; $('#lm-nc').textContent = calls.length;
    const units2 = units.filter((u) => matchQ(`${u.callsign} ${u.name} ${u.deptShort}`));
    const calls2 = calls.filter((c) => matchQ(`#${c.id} ${c.title} ${c.street}`));
    if (L.tab === 'units') {
      if (!units2.length) { box.innerHTML = empty(L.q ? 'Nobody matches' : 'Nobody on duty you can see'); }
      else {
        const groups = new Map();
        units2.sort((a, b) => String(a.callsign || a.name).localeCompare(String(b.callsign || b.name), undefined, { numeric: true }))
          .forEach((u) => { const k = u.deptShort || '?'; if (!groups.has(k)) groups.set(k, { color: u.color1, list: [] }); groups.get(k).list.push(u); });
        box.innerHTML = [...groups.entries()].map(([k, g]) => `<div class="lm-gh" style="--dc:${esc(g.color || '#3b82f6')}"><i></i>${esc(k)}<span>${g.list.length}</span></div>` + g.list.map((u) => {
          const st = statusOf(u.status);
          const c = u.callId && callById(u.callId);
          return `<button class="lm-row${L.sel === 'u:' + u.charId ? ' on' : ''}${u.panic ? ' panic' : ''}" data-sel="u:${u.charId}" data-probe-press>
            <span class="lm-ico" style="--gc:${esc(u.color1 || '#3b82f6')}">${u.car ? ICON.car : ICON.foot}</span>
            <span class="lm-rt"><b>${esc(u.callsign || '—')}</b> ${esc(u.name || '')}${u.charId === d.me ? ' <em class="lm-you">you</em>' : ''}
              <small><span class="lm-st" style="--sc:${esc(st.color)}">${esc(st.label)}</span>${c ? ` · #${c.id} ${esc(c.title)}` : ''}${u.panic ? ' · <b class="txt-bad">PANIC</b>' : ''}</small></span>
            ${u.car && u.speed != null ? `<span class="lm-spd">${speedTxt(u.speed, d.speedUnits)}</span>` : ''}</button>`;
        }).join('')).join('');
      }
    } else {
      if (!calls2.length) box.innerHTML = empty(L.q ? 'No call matches' : 'No active calls on the map');
      else box.innerHTML = calls2.slice().sort((a, b) => (b.critical ? 1 : 0) - (a.critical ? 1 : 0) || a.priority - b.priority || b.id - a.id).map((c) => `
        <button class="lm-row call${L.sel === 'c:' + c.id ? ' on' : ''}${c.critical ? ' crit' : ''}" data-sel="c:${c.id}" data-probe-press>
          <span class="lm-ico call p${c.priority}">${esc(c.kind === 'panic' ? '⚠' : c.kind === 'backup' ? '⇶' : (c.icon || '☎'))}</span>
          <span class="lm-rt"><b>#${c.id}</b> ${esc(c.title)}<small>${esc(c.street || '')} · ${ago(c.createdAt)}${c.follows ? ' · <span class="lm-livetag">follows officer</span>' : ''}</small></span>
          <span class="lm-resp${(c.units || []).length ? '' : ' none'}">${(c.units || []).length}</span></button>`).join('');
    }
    $$('[data-sel]', box).forEach((b) => b.onclick = () => select(b.dataset.sel, true));
    const mode = d.mode === 'all' ? 'every department' : d.mode === 'own' ? 'your department' : 'your dispatch group';
    $('#lm-foot').textContent = `Showing units of ${mode} · drag to move, scroll or + / − to zoom, 0 shows everyone`;
  }

  // ---------------------------------------------------------------- selection, details and actions
  function select(key, fly) {
    if (key && key[0] === 'k') key = 'c' + key.slice(1);   // 2.0.15: a backup marker opens its call
    L.sel = key;
    if (!key || key[0] !== 'u') L.follow = false;
    $$('.lp.sel').forEach((el) => el.classList.remove('sel'));
    if (key && L.pins.get(key)) L.pins.get(key).classList.add('sel');
    $$('#lm-list .lm-row').forEach((r) => r.classList.toggle('on', r.dataset.sel === key));
    if (L.data) draw();   // 2.0.10: the selected unit's / call's lines are the moving ones
    detail();
    if (key && fly) {
      const [k, id] = [key[0], +key.slice(2)];
      const t = k === 'u' ? unitById(id) : k === 'c' ? callById(id) : ((L.data && L.data.bolos) || []).find((b) => b.id === id);
      if (t) centreOn(t.x, t.y, Math.max(L.z, 1.1));
    }
  }
  function setFollow(on) { L.follow = on; const b = $('#lm-follow'); if (b) { b.classList.toggle('on', on); b.textContent = on ? '◉ Following' : '◎ Follow'; } }

  function detail() {
    const box = $('#lm-detail'); if (!box) return;
    const key = L.sel;
    if (!key || !L.data) { box.classList.add('hidden'); box.innerHTML = ''; return; }
    const k = key[0], id = +key.slice(2), d = L.data;
    let html = '';
    if (k === 'u') {
      const u = unitById(id); if (!u) { box.classList.add('hidden'); return; }
      const st = statusOf(u.status), c = u.callId && callById(u.callId);
      const meU = mine();
      const dist = meU && meU.charId !== u.charId ? Math.round(Math.hypot(meU.x - u.x, meU.y - u.y)) : null;
      html = `<div class="lm-dh" style="--gc:${esc(u.color1 || '#3b82f6')}"><span class="lm-ico big">${u.car ? ICON.car : ICON.foot}</span>
          <div><div class="lm-dt">${esc(u.callsign || '—')} · ${esc(u.name || '')}</div><div class="hint">${esc(u.deptName || u.deptShort || '')}</div></div>
          <button class="lm-x" data-close title="Close">✕</button></div>
        <div class="lm-facts"><span><i>Status</i><b style="color:${esc(st.color)}">${esc(st.label)}</b></span>
          <span><i>Moving</i><b>${u.car ? 'In a vehicle' : 'On foot'}${u.car && u.speed != null ? ' · ' + speedTxt(u.speed, d.speedUnits) : ''}</b></span>
          <span><i>Heading</i><b>${compass(u.h)}</b></span>${dist != null ? `<span><i>From you</i><b>${dist >= 1000 ? (dist / 1000).toFixed(1) + ' km' : dist + ' m'}</b></span>` : ''}
          ${c ? `<span class="wide"><i>On call</i><b><a data-opencall="${c.id}">#${c.id} ${esc(c.title)}</a></b></span>` : ''}${u.panic ? '<span class="wide"><b class="txt-bad">⚠ PANIC pressed</b></span>' : ''}</div>
        <div class="lm-acts"><button class="btn small" data-wp="${u.x},${u.y}" data-probe-press>⌖ Waypoint</button>
          <button class="btn small ghost${L.follow ? ' on' : ''}" id="lm-follow" data-probe-press>${L.follow ? '◉ Following' : '◎ Follow'}</button>
          <button class="btn small ghost" data-profile="${u.charId}" data-probe-press>Profile</button></div>`;
    } else if (k === 'c') {
      const c = callById(id); if (!c) { box.classList.add('hidden'); return; }
      const us = c.units || [];
      html = `<div class="lm-dh"><span class="lm-ico big call p${c.priority}">${esc(c.kind === 'panic' ? '⚠' : c.kind === 'backup' ? '⇶' : (c.icon || '☎'))}</span>
          <div><div class="lm-dt">#${c.id} ${esc(c.title)}</div><div class="hint">📍 ${esc(c.street || 'Unknown street')} · ${ago(c.createdAt)}</div></div>
          <button class="lm-x" data-close title="Close">✕</button></div>
        <div class="row lm-tags">${M.priPill ? M.priPill(c.priority) : 'P' + c.priority}${M.kindTag ? M.kindTag(c.kind) : ''}${c.critical ? '<span class="crit-tag">CRITICAL</span>' : ''}${(c.reports || 1) > 1 ? `<span class="rep-tag">×${c.reports} reports</span>` : ''}${c.follows ? '<span class="lm-livetag">Follows the officer</span>' : ''}${c.backup ? `<span class="bk-tag" title="Their live spot: the 🚨 marker">🚨 Backup · ${esc(c.backup.by || '')}</span>` : ''}${c.radius ? `<span class="pill">Search area ~${c.radius} m</span>` : ''}</div>
        <div class="lm-units">${us.length ? `<i>${us.length} responding</i>${us.map((x) => `<span>${esc(x.callsign || x.name || '#' + x.charId)}</span>`).join('')}` : '<i class="none">Nobody responding yet</i>'}</div>
        <div class="lm-acts">${c.mine ? '<span class="pill on">You are on this call</span>' : (S.ctx.onDuty ? `<button class="btn small accent" data-respond="${c.id}" data-probe-press>Respond + GPS</button>` : '')}
          <button class="btn small" data-gps="${c.id}" data-probe-press>⌖ GPS</button>
          <button class="btn small ghost" data-opencall="${c.id}" data-probe-press>Open call</button></div>`;
    } else {
      const b = ((d.bolos) || []).find((x) => x.id === id); if (!b) { box.classList.add('hidden'); return; }
      html = `<div class="lm-dh"><span class="lm-ico big bolo">⚑</span><div><div class="lm-dt">${esc(b.title)}</div><div class="hint">${b.plate ? 'Plate ' + esc(b.plate) + ' last read ' : 'Last seen '}${ago(b.seenAt)}</div></div><button class="lm-x" data-close title="Close">✕</button></div>
        <div class="lm-acts"><button class="btn small" data-wp="${b.x},${b.y}" data-probe-press>⌖ Waypoint</button>${b.plate ? `<button class="btn small ghost" data-veh="${esc(b.plate)}" data-probe-press>Vehicle</button>` : ''}</div>`;
    }
    box.innerHTML = html; box.classList.remove('hidden');
    $$('[data-close]', box).forEach((b) => b.onclick = () => select(null));
    $$('[data-wp]', box).forEach((b) => b.onclick = async () => { const [x, y] = b.dataset.wp.split(',').map(Number); said(await post('waypoint', { x, y }), 'Waypoint set'); });
    $$('[data-profile]', box).forEach((b) => b.onclick = () => go('people', +b.dataset.profile));
    $$('[data-veh]', box).forEach((b) => b.onclick = () => go('vehicles', b.dataset.veh));
    $$('[data-opencall]', box).forEach((b) => b.onclick = () => M.openCall ? M.openCall(+b.dataset.opencall) : go('dispatch', +b.dataset.opencall));
    $$('[data-respond]', box).forEach((b) => b.onclick = (e) => busy(e.currentTarget, async () => {
      const r = await call('callAttach', { id: +b.dataset.respond, route: true, from: 'map' });
      if (said(r, r.ok && r.data.units > 1 ? 'Responding with your partner · GPS set' : 'Responding · GPS set')) {
        const c = callById(+b.dataset.respond); if (c) { c.mine = true; c.units = (c.units || []).concat([{ charId: S.ctx.me.charId, callsign: S.ctx.me.callsign, name: S.ctx.me.name }]); }
        detail(); draw(); list(); setTimeout(() => poll(false), 300);
      }
    }));
    $$('[data-gps]', box).forEach((b) => b.onclick = async () => { const r = await call('callRoute', { id: +b.dataset.gps }); said(r, 'GPS set to the call'); });
    const fb = $('#lm-follow', box); if (fb) fb.onclick = () => { setFollow(!L.follow); if (L.follow) { const u = unitById(id); if (u) centreOn(u.x, u.y, Math.max(L.z, 1.1)); } };
  }
  const compass = (h) => { if (h == null) return '—'; const dirs = ['N', 'NW', 'W', 'SW', 'S', 'SE', 'E', 'NE']; return dirs[Math.round(((+h % 360) + 360) % 360 / 45) % 8]; };

  // the MDT closed / another tab: stop asking
  HOOK.liveMapStop = stop;
  window.addEventListener('message', (e) => { const m = e.data; if (m && m.action === 'close') stop(); if (m && m.action === 'callMoved' && L.data && S.view === 'livemap') { const c = callById(+m.call.id); if (c) { c.x = +m.call.x; c.y = +m.call.y; draw(); } } });
  document.addEventListener('visibilitychange', () => { if (!document.hidden && S.view === 'livemap' && mapEl()) poll(false); });
  M.liveMap = L;

  // 2.0.13: a controller (html/pad.js): left stick moves, right stick / triggers zoom about the middle, A picks the pin nearest
  // the cross in the middle, X fits everything, Y finds my unit
  window.ESPadMap = {
    active: () => S.open && S.view === 'livemap' && !!mapEl() && !document.querySelector('#modal:not(.hidden)'),
    pan(dx, dy) { cancelAnimationFrame(L.tz); if (L.follow) setFollow(false); L.x += dx; L.y += dy; clampView(); apply(); },
    zoom(f) {
      const m = mapEl(); if (!m) return;
      cancelAnimationFrame(L.tz);
      const z = Math.max(MIN_Z, Math.min(MAX_Z, L.z * f)), k = z / L.z, cx = m.clientWidth / 2, cy = m.clientHeight / 2;
      L.x = cx - (cx - L.x) * k; L.y = cy - (cy - L.y) * k; L.z = z; clampView(); apply();
    },
    nearest() {
      const m = mapEl(); if (!m) return;
      const r = m.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      let best = null, bd = Infinity;
      L.pins.forEach((el, key) => {
        if (!el.isConnected || el.offsetParent === null) return;
        const b = el.getBoundingClientRect(); if (!b.width) return;
        const d = Math.hypot(b.left + b.width / 2 - cx, b.top + b.height / 2 - cy);
        if (d < bd) { bd = d; best = key; }
      });
      if (!best) return toast('Nothing on the map yet', 'bad');
      select(best, true);
    },
    fit: () => fitAll(),
    me: () => { const b = $('#lm-me'); if (b) b.click(); },
  };
})();
