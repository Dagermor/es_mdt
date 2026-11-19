// es_mdt 2.0.11: the Radar tab. The in-car radar (client/radar.lua) in the MDT: turn it on or off, each antenna's
// direction, the live readout, locks, the speed alert, the plate reader. Plus this shift's plate reads and the server's
// plate hits, each with Look up / BOLO / Profile / Map. The readout is the same message the in-car panel gets, sent only
// when something changed (2.0.10), so the tab costs nothing more; the reads come only while this tab is on screen.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, post, toast, said, busy, ago, empty, go, VIEWS, can } = M;
  const MODES = { same: ['Same', '▲'], opp: ['Opposite', '▼'], both: ['Both', '▲▼'] };
  const rc = () => (S.ctx && S.ctx.config && S.ctx.config.radar) || { enabled: true, tab: true, law: true, units: 'mph', fastLimit: 70, autoLock: true };
  const T = { st: null, d: null, side: 'reads', mine: false, hits: null, q: '', open: false, lookup: null };
  M.radarTabVisible = () => !!(S.ctx && rc().tab !== false && (rc().law || S.ctx.staff));

  const LV = { high: ['bad', '⚠ Hit'], low: ['warn', 'Note'] };
  const unitTxt = () => (T.st && T.st.units === 'KMH') ? 'km/h' : 'mph';
  const tsAgo = (t) => t ? ago(t) : '';
  const mapOk = () => (S.ctx.onDuty || S.ctx.staff) && (((S.ctx.config || {}).liveMap || {}).enabled !== false || S.ctx.staff);

  // ---------------------------------------------------------------- the page
  VIEWS.radar = async (v) => {
    if (!M.radarTabVisible()) { v.innerHTML = empty(rc().tab === false ? 'The radar tab is turned off on this server' : 'The radar is for police, sheriff and state police', '📡'); return; }
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Radar</div><div class="hint">Speed radar and plate reader · the same radar as in your car (F5 on / off, F7 remote)</div></div>
        <div class="row"><span id="rt-status" class="rt-status">…</span><button class="rt-power" id="rt-power" data-probe-press><span class="sw"></span><b>Radar</b></button></div></div>
      <div class="rt">
        <section class="rt-live" id="rt-live"><div class="loading-row"><div class="spin"></div></div></section>
        <aside class="rt-side">
          <div class="rt-look"><input id="rt-q" maxlength="10" placeholder="Check a plate…" autocomplete="off" style="text-transform:uppercase"><button class="btn small accent" id="rt-check" data-probe-press>Check</button></div>
          <div id="rt-lookup"></div>
          <div class="seg rt-tabs"><button data-side="reads" class="${T.side === 'reads' ? 'on' : ''}" data-probe-press>Read this shift <b id="rt-nr">0</b></button><button data-side="hits" class="${T.side === 'hits' ? 'on' : ''}" data-probe-press>Plate hits <b id="rt-nh"></b></button></div>
          <div class="rt-filter" id="rt-filter"></div>
          <div class="rt-list" id="rt-list"><div class="loading-row"><div class="spin"></div></div></div>
        </aside>
      </div>`;
    $$('[data-side]', v).forEach((b) => b.onclick = () => { T.side = b.dataset.side; $$('[data-side]', v).forEach((x) => x.classList.toggle('on', x === b)); side(); });
    const q = $('#rt-q', v);
    const check = () => busy($('#rt-check'), async () => {
      const p = q.value.trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
      if (!p) return;
      const r = await call('radarPlate', { plate: p });
      if (!$('#rt-lookup')) return;
      if (!r.ok) { toast(r.why || 'The plate could not be checked', 'error'); return; }
      T.lookup = r.data; lookup();
    });
    $('#rt-check', v).onclick = check;
    q.onkeydown = (e) => { if (e.key === 'Enter') check(); };
    $('#rt-power', v).onclick = (e) => busy(e.currentTarget, async () => {
      const on = !(T.st && T.st.settings && T.st.settings.shown);
      const r = await post('radarPower', { on });
      if (r && r.ok) { T.st = r.data; build(); } else toast((r && r.why) || 'The radar did not answer', 'error');
    });
    T.open = true;
    const r = await post('radarTab', { open: true });
    if (S.view !== 'radar') return;
    T.st = (r && r.ok && r.data) || { enabled: true, inCar: false, allowed: false, live: false, settings: null, reads: [], hits: [] };
    build(); side(); lookup();
  };

  function statusTxt() {
    const s = T.st || {};
    if (s.enabled === false) return ['off', 'Turned off on this server'];
    if (!s.inCar) return ['idle', 'Not in a police vehicle'];
    if (!s.allowed) return ['idle', 'Go on duty to use it'];
    if (!(s.settings && s.settings.shown)) return ['off', 'Off'];
    return ['live', 'Live'];
  }

  // ---------------------------------------------------------------- the live side (built on a change of settings / state,
  // painted on each readout: only numbers and classes change, so a readout costs a few text updates)
  const ant = (a, set) => `<div class="rt-ant" data-ant="${a}">
      <div class="rt-ah"><button class="rt-tog${set[a].on ? ' on' : ''}" data-ton="${a}" data-probe-press><span class="sw"></span><b>${a === 'front' ? 'Front' : 'Rear'}</b></button>
        <div class="seg rt-mode">${Object.keys(MODES).map((k) => `<button data-mode="${a}:${k}" class="${set[a].mode === k ? 'on' : ''}" title="${MODES[k][0]} direction" data-probe-press>${MODES[k][1]} ${MODES[k][0]}</button>`).join('')}</div></div>
      <div class="rt-nums"><div class="rt-n"><i>Target</i><b data-v="${a}.speed">—</b></div><div class="rt-n fast"><i>Fast</i><b data-v="${a}.fast">—</b></div>
        <button class="btn small rt-lock" data-lock="${a}:speed" data-probe-press>🔒 Lock speed</button></div>
      <div class="rt-plate" data-pl="${a}"><div><i>Plate</i><span class="plate big" data-v="${a}.plate">— — —</span><div class="rt-why" data-v="${a}.why"></div></div>
        <div class="rt-pacts"><button class="btn small" data-lock="${a}:plate" data-probe-press>🔒 Lock plate</button><span class="rt-pa" data-pa="${a}"></span></div></div>
    </div>`;
  function build() {
    const box = $('#rt-live'); if (!box || !T.st) return;
    const [cls, txt] = statusTxt();
    const st = $('#rt-status'); st.className = 'rt-status ' + cls; st.textContent = txt;
    const pw = $('#rt-power'); const on = !!(T.st.settings && T.st.settings.shown);
    pw.classList.toggle('on', on); pw.disabled = T.st.enabled === false; pw.querySelector('b').textContent = on ? 'Radar on' : 'Radar off';
    const set = T.st.settings;
    if (!set) { box.innerHTML = empty('The radar did not answer. Try again in a moment.', '📡'); return; }
    const why = cls === 'live' ? '' : T.st.enabled === false ? 'An admin has turned the radar off.' : !T.st.inCar ? 'Get in a police vehicle to see live speeds and plates. Your settings below still apply.' : !T.st.allowed ? 'Clock on in a police, sheriff or state police department.' : 'Turn the radar on to measure.';
    box.innerHTML = `${why ? `<div class="rt-note">${esc(why)}</div>` : ''}
      <div class="rt-top"><div class="rt-patrol"><i>Your speed</i><b data-v="patrol">—</b><span>${unitTxt()}</span></div>
        <div class="rt-alert"><i>Speed alert</i><div class="row"><button class="btn small" data-fast="-5" data-probe-press>−</button><b id="rt-fast">${set.fast}</b><span>${unitTxt()}</span><button class="btn small" data-fast="5" data-probe-press>＋</button></div>
          <input type="range" min="10" max="200" step="1" value="${set.fast}" id="rt-fast-r" aria-label="Speed alert"></div></div>
      <div class="rt-ants${cls === 'live' ? '' : ' idle'}">${ant('front', set)}${ant('rear', set)}</div>
      <div class="rt-opts">
        <button class="rt-tog${set.beep ? ' on' : ''}" data-opt="beep" data-probe-press><span class="sw"></span>Beep over the alert</button>
        ${set.autoLockAllowed !== false ? `<button class="rt-tog${set.autoLock ? ' on' : ''}" data-opt="autoLock" data-probe-press><span class="sw"></span>Auto-lock over the alert</button>` : ''}
        <button class="rt-tog${set.plates ? ' on' : ''}" data-opt="plates" data-probe-press><span class="sw"></span>Plate reader</button>
        <button class="rt-tog${set.muted ? ' on' : ''}" data-opt="muted" data-probe-press><span class="sw"></span>Mute</button>
        <button class="btn small ghost" id="rt-reset" data-probe-press>⟲ Clear all locks</button></div>
      <div class="hint rt-more">Volume, panel size and position, units and auto-on: pause menu › Settings › Server Settings › Radar.</div>`;
    const save = (redraw) => { post('radarSave', { settings: set }).then((r) => { if (r && r.ok && r.data && T.st) { T.st.settings = r.data; if (redraw) build(); } }); };
    $$('[data-ton]', box).forEach((b) => b.onclick = () => { const a = b.dataset.ton; set[a].on = !set[a].on; build(); save(); });
    $$('[data-mode]', box).forEach((b) => b.onclick = () => { const [a, m] = b.dataset.mode.split(':'); set[a].mode = m; build(); save(); });
    $$('[data-opt]', box).forEach((b) => b.onclick = () => { const k = b.dataset.opt; set[k] = !set[k]; build(); save(); });
    let fT = null;
    const setFast = (n) => { set.fast = Math.max(10, Math.min(200, n)); $('#rt-fast').textContent = set.fast; $('#rt-fast-r').value = set.fast; clearTimeout(fT); fT = setTimeout(() => save(), 300); };
    $$('[data-fast]', box).forEach((b) => b.onclick = () => setFast(set.fast + +b.dataset.fast));
    $('#rt-fast-r', box).oninput = (e) => setFast(+e.target.value);
    $$('[data-lock]', box).forEach((b) => b.onclick = (e) => busy(e.currentTarget, async () => {
      const [a, w] = b.dataset.lock.split(':');
      const r = await post('radarLock', { antenna: a, what: w });
      if (!r || !r.ok) toast((r && r.why) || 'Nothing to lock', 'error');
    }));
    $('#rt-reset', box).onclick = async () => { await post('radarReset'); toast('Locks cleared', 'success'); };
    if (cls !== 'live') T.d = null;   // not measuring: no old numbers left on screen
    else if (T.d) paint(T.d);
  }
  function paint(d) {
    T.d = d;
    const box = $('#rt-live'); if (!box) return;
    const put = (k, val) => { const el = $(`[data-v="${k}"]`, box); if (el && el.textContent !== String(val)) el.textContent = val; };
    put('patrol', d.patrol == null ? '—' : d.patrol);
    ['front', 'rear'].forEach((a) => {
      const x = d[a] || {};
      const sp = x.lockSpeed != null ? x.lockSpeed : x.speed, fa = x.lockFast != null ? x.lockFast : x.fast;
      put(a + '.speed', x.on && sp != null ? sp : '—'); put(a + '.fast', x.on && fa != null ? fa : '—');
      const el = $(`[data-ant="${a}"]`, box); if (!el) return;
      el.classList.toggle('locked', !!x.locked);
      el.classList.toggle('over', !!(x.on && T.st && T.st.settings && Math.max(sp || 0, fa || 0) >= T.st.settings.fast));
      const lb = $(`[data-lock="${a}:speed"]`, el); if (lb) lb.textContent = x.locked ? '🔓 Unlock speed' : '🔒 Lock speed';
      const p = x.plate, pl = $(`[data-pl="${a}"]`, el);
      put(a + '.plate', p && p.plate ? p.plate.trim() : '— — —');
      const why = p && p.hits ? p.hits.filter((h) => h.level === p.level).map((h) => h.text).join(' · ') : '';
      put(a + '.why', p && p.plate ? (p.level === 'high' ? '⚠ ' + why : p.level === 'low' ? why : !p.done ? 'Checking…' : '✓ Clear') : '');
      pl.className = 'rt-plate' + (p && p.level ? ' ' + p.level : '') + (x.plateLocked ? ' locked' : '');
      const pb = $(`[data-lock="${a}:plate"]`, el); if (pb) pb.textContent = x.plateLocked ? '🔓 Unlock plate' : '🔒 Lock plate';
      const pa = $(`[data-pa="${a}"]`, el);
      const key = p && p.plate ? p.plate.trim().replace(/[^A-Z0-9]/gi, '').toUpperCase() : '';
      if (pa && pa.dataset.k !== key) {
        pa.dataset.k = key;
        pa.innerHTML = key ? `<button class="btn small ghost" data-look="${esc(key)}" data-probe-press>Look up</button>` : '';
        $$('[data-look]', pa).forEach((b) => b.onclick = () => go('vehicles', b.dataset.look));
      }
    });
  }

  // ---------------------------------------------------------------- the side: this shift's reads, the server's plate hits
  function actions(x) {
    const out = [`<button class="btn small" data-look="${esc(x.plate)}" data-probe-press>Look up</button>`];
    if (can('bolo_manage') && !x.boloId) out.push(`<button class="btn small ghost" data-bolo="${esc(x.plate)}" data-btitle="${esc([x.label, x.plate].filter(Boolean).join(' · '))}" data-probe-press>⚑ BOLO</button>`);
    if (x.ownerCharId) out.push(`<button class="btn small ghost" data-prof="${x.ownerCharId}" data-probe-press>Owner</button>`);
    if (x.x != null && x.y != null) out.push(mapOk() ? `<button class="btn small ghost" data-map="${x.x},${x.y}" data-lbl="${esc(x.plate)}" data-probe-press>⌖ Map</button>`
      : `<button class="btn small ghost" data-wp="${x.x},${x.y}" data-probe-press>⌖ Waypoint</button>`);
    return out.join('');
  }
  function wireActs(root) {
    $$('[data-look]', root).forEach((b) => b.onclick = () => go('vehicles', b.dataset.look));
    $$('[data-bolo]', root).forEach((b) => b.onclick = () => M.boloForm ? M.boloForm({ kind: 'vehicle', plate: b.dataset.bolo, title: b.dataset.btitle || '' }, () => { toast('BOLO saved', 'success'); if (T.side === 'hits') loadHits(); }) : go('bolos'));
    $$('[data-prof]', root).forEach((b) => b.onclick = () => go('people', +b.dataset.prof));
    $$('[data-map]', root).forEach((b) => b.onclick = () => { const [x, y] = b.dataset.map.split(',').map(Number); go('livemap', { point: { x, y, label: b.dataset.lbl, kind: 'read' } }); });
    $$('[data-wp]', root).forEach((b) => b.onclick = async () => { const [x, y] = b.dataset.wp.split(',').map(Number); said(await post('waypoint', { x, y }), 'Waypoint set'); });
  }
  function row(x, extra) {
    const lv = LV[x.level];
    return `<div class="rt-row${x.level === 'high' ? ' hot' : ''}"><div class="rt-rh"><span class="plate">${esc(x.plate)}</span>${lv ? `<span class="pill ${lv[0]}">${lv[1]}</span>` : '<span class="pill on">Clear</span>'}
        <span class="hint rt-when">${esc(extra || '')}</span></div>
      ${x.why || x.detail ? `<div class="rt-rwhy">${esc(x.why || x.detail)}</div>` : ''}
      ${x.label || x.owner ? `<div class="hint">${esc([x.label, x.owner ? 'Owner ' + x.owner : null].filter(Boolean).join(' · '))}</div>` : ''}
      <div class="rt-racts">${actions(x)}</div></div>`;
  }
  function side() {
    const list = $('#rt-list'), f = $('#rt-filter'); if (!list) return;
    const reads = (T.st && T.st.reads) || [];
    $('#rt-nr').textContent = reads.length;
    if (T.side === 'reads') {
      f.innerHTML = reads.length ? `<span class="hint">Plates your reader saw this shift, on this PC · newest first</span><button class="btn small ghost" id="rt-clear" data-probe-press>Clear</button>` : '';
      if ($('#rt-clear')) $('#rt-clear').onclick = async () => { const r = await post('radarClearReads'); if (r && r.ok) { T.st = r.data; side(); } };
      list.innerHTML = reads.length ? reads.map((x) => row(x, `${x.ant ? (x.ant === 'front' ? 'Front' : 'Rear') + ' · ' : ''}${tsAgo(x.at)}`)).join('')
        : empty('No plates read yet. Drive with the plate reader on: every plate it reads lands here.', '🚘');
      wireActs(list);
    } else {
      f.innerHTML = `<div class="seg"><button data-mine="0" class="${T.mine ? '' : 'on'}" data-probe-press>Everyone</button><button data-mine="1" class="${T.mine ? 'on' : ''}" data-probe-press>Mine</button></div>
        <span class="hint">BOLO, stolen and warrant reads${rc().keepDays ? ` · kept ${rc().keepDays} days` : ''}</span>`;
      $$('[data-mine]', f).forEach((b) => b.onclick = () => { T.mine = b.dataset.mine === '1'; loadHits(); });
      if (!T.hits) loadHits(); else drawHits();
    }
  }
  async function loadHits() {
    const list = $('#rt-list'); if (!list) return;
    list.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('radarHistory', { mine: T.mine });
    if (!$('#rt-list') || T.side !== 'hits') return;
    if (!r.ok) { list.innerHTML = empty(r.why || 'The plate hits could not be loaded', '⚠'); return; }
    T.hits = r.data.hits || []; side();
  }
  function drawHits() {
    const list = $('#rt-list'); if (!list) return;
    $('#rt-nh').textContent = T.hits.length || '';
    list.innerHTML = T.hits.length ? T.hits.map((h) => row({ plate: h.plate, level: 'high', detail: h.detail, x: h.x, y: h.y },
      `${h.mine ? 'You' : esc(h.by || 'A reader')} · ${tsAgo(h.at)}`)).join('') : empty(T.mine ? 'Your reader has no hits yet' : 'No plate hits yet', '✓');
    wireActs(list);
  }
  function lookup() {
    const box = $('#rt-lookup'); if (!box) return;
    const x = T.lookup;
    if (!x) { box.innerHTML = ''; return; }
    const why = (x.hits || []).map((h) => h.text).join(' · ');
    box.innerHTML = `<div class="rt-lk">${row({ plate: x.plate, level: x.level, why, label: x.label, owner: x.owner, ownerCharId: x.ownerCharId, boloId: x.boloId }, 'Checked now')}<button class="lm-x rt-lkx" title="Close" data-probe-press>✕</button></div>`;
    wireActs(box);
    $('.rt-lkx', box).onclick = () => { T.lookup = null; lookup(); };
  }

  // ---------------------------------------------------------------- live messages (the same the in-car panel gets)
  function leave() { if (T.open) { T.open = false; post('radarTab', { open: false }); } }
  setInterval(() => { if (T.open && (S.view !== 'radar' || !S.open)) leave(); }, 1500);
  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? (() => { try { return JSON.parse(e.data); } catch (x) { return null; } })() : e.data;
    if (!m || !m.action) return;
    if (m.action === 'close') { leave(); return; }
    if (m.action.indexOf('radar') !== 0 || S.view !== 'radar' || !$('#rt-live')) return;
    if (m.action === 'radar' && m.data) paint(m.data);
    else if (m.action === 'radarState' && m.state) { T.st = m.state; build(); side(); }
    else if (m.action === 'radarSettings' && T.st) { T.st.settings = m.settings; T.st.units = m.units; build(); }
    else if (m.action === 'radarReads' && T.st) { T.st.reads = m.reads || []; T.st.hits = m.hits || []; if (T.side === 'reads') side(); else $('#rt-nr').textContent = T.st.reads.length; }
    else if (m.action === 'radarHit' && T.side === 'hits') setTimeout(loadHits, 800);
  });
  M.radarTab = T;
})();
