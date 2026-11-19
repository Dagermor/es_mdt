// es_mdt 1.3.0: the radar display (always on screen in a police car, on duty) and its remote (opens with focus).
// client/radar.lua does the measuring; this draws, beeps, and saves the officer's settings back to it (KVP).
(function () {
  'use strict';
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'es_mdt';
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const post = async (path, data) => { try { const r = await fetch(`https://${RES}/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }); return await r.json(); } catch (e) { return { ok: false }; } };

  const R = { s: null, units: 'MPH', shown: false, remote: false, hits: [], last: null };
  const MODES = { same: ['Same', '▲'], opp: ['Opposite', '▼'], both: ['Both', '▲▼'] };

  // ---------------------------------------------------------------- sound
  let ac = null;
  function beep(times, freq) {
    const vol = R.s ? R.s.volume : 0.6; if (vol <= 0 || (R.s && R.s.muted)) return;   // 2.0.11: muted in the pause menu / remote
    try {
      ac = ac || new (window.AudioContext || window.webkitAudioContext)();
      for (let i = 0; i < (times || 2); i++) {
        const o = ac.createOscillator(), g = ac.createGain(), t = ac.currentTime + i * 0.16;
        o.type = 'square'; o.frequency.value = freq || 1320;
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.12 * vol, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.11);
        o.connect(g); g.connect(ac.destination); o.start(t); o.stop(t + 0.12);
      }
    } catch (e) { /* no audio here */ }
  }

  // ---------------------------------------------------------------- the display
  const led = (v, cls) => `<div class="led ${cls || ''}"><span class="ghost">888</span><span class="val">${v == null ? '' : String(v).padStart(3, ' ')}</span></div>`;
  function antenna(name, a) {
    a = a || {};
    const m = MODES[a.mode] || MODES.both;
    const shownSpeed = a.lockSpeed != null ? a.lockSpeed : a.speed, shownFast = a.lockFast != null ? a.lockFast : a.fast;
    return `<div class="rd-ant${a.on ? '' : ' off'}${a.locked ? ' locked' : ''}">
      <div class="rd-lbl"><b>${name}</b><span class="rd-dir" title="${m[0]} direction">${a.on ? m[1] : '—'}</span><span class="rd-mode">${a.on ? m[0].toUpperCase() : 'OFF'}</span></div>
      <div class="rd-cell"><span class="cap">TARGET</span>${led(a.on ? shownSpeed : null, 'red')}</div>
      <div class="rd-cell"><span class="cap">FAST</span>${led(a.on ? shownFast : null, 'amber')}</div>
      <div class="rd-lock" title="Locked">${a.locked ? 'LOCK' : ''}</div></div>`;
  }
  function plate(name, p, locked) {
    const lv = p && p.level, txt = p && p.plate ? p.plate.trim() : '';
    const why = p && p.hits ? p.hits.filter((h) => h.level === lv).map((h) => h.text).join(' · ') : '';
    return `<div class="rd-plate ${lv || ''}${locked ? ' locked' : ''}"><span class="cap">${name}${locked ? ' · LOCK' : ''}</span>
      <div class="rd-pl">${txt ? esc(txt) : '<span class="dim">— — —</span>'}</div><div class="rd-why" title="${esc(why)}">${lv === 'high' ? '⚠ ' + esc(why) : lv === 'low' ? esc(why) : txt ? '✓ clear' : ''}</div></div>`;
  }
  function draw(d) {
    R.last = d;
    const el = $('#radar'); if (!el) return;
    el.innerHTML = `<div class="rd-body">
        <div class="rd-ants">${antenna('FRONT', d.front)}${antenna('REAR', d.rear)}</div>
        <div class="rd-patrol"><span class="cap">PATROL</span>${led(d.patrol, 'green')}<span class="rd-u">${R.units}</span><span class="rd-fl" title="Fast limit">LIMIT ${R.s ? R.s.fast : ''}</span></div>
      </div>
      ${R.s && R.s.plates ? `<div class="rd-plates">${plate('FRONT PLATE', d.front && d.front.plate, d.front && d.front.plateLocked)}${plate('REAR PLATE', d.rear && d.rear.plate, d.rear && d.rear.plateLocked)}</div>` : ''}
      ${R.remote ? '<div class="rd-drag">⠿ drag to move</div>' : ''}`;
    const hot = (d.front && d.front.plate && d.front.plate.level === 'high') || (d.rear && d.rear.plate && d.rear.plate.level === 'high');
    el.classList.toggle('hit', !!hot);
    if (d.beep && R.s && R.s.beep) beep(2, 1320);
  }
  function place() {
    const el = $('#radar'); if (!el || !R.s) return;
    el.style.setProperty('--rs', R.s.scale || 1);
    ['br', 'bl', 'tr', 'tl'].forEach((p) => el.classList.toggle('pos-' + p, (R.s.pos || 'br') === p && R.s.x == null));
    if (R.s.x != null && R.s.y != null) { el.style.left = (R.s.x * 100) + '%'; el.style.top = (R.s.y * 100) + '%'; el.style.right = 'auto'; el.style.bottom = 'auto'; }
    else { el.style.left = ''; el.style.top = ''; el.style.right = ''; el.style.bottom = ''; }   // 2.0.11: a corner (pos-*)
  }

  // drag (only while the remote is open: that is when the game gives us the mouse)
  let drag = null;
  document.addEventListener('mousedown', (e) => {
    const el = $('#radar'); if (!R.remote || !el || !el.contains(e.target)) return;
    const r = el.getBoundingClientRect(); drag = { dx: e.clientX - r.left, dy: e.clientY - r.top }; el.classList.add('dragging'); e.preventDefault();
  });
  document.addEventListener('mousemove', (e) => {
    if (!drag) return; const el = $('#radar');
    const x = Math.max(0, Math.min(window.innerWidth - 40, e.clientX - drag.dx)), y = Math.max(0, Math.min(window.innerHeight - 40, e.clientY - drag.dy));
    R.s.x = x / window.innerWidth; R.s.y = y / window.innerHeight; R.s.pos = 'custom'; place(); el.style.right = 'auto';
  });
  document.addEventListener('mouseup', () => { if (!drag) return; drag = null; const el = $('#radar'); if (el) el.classList.remove('dragging'); save(); });

  // ---------------------------------------------------------------- the remote
  let saveT = null;
  function save() { clearTimeout(saveT); saveT = setTimeout(() => post('radarSave', { settings: R.s }), 250); }
  const tog = (key, on, label) => `<button class="rm-tog${on ? ' on' : ''}" data-tog="${key}"><span class="sw"></span>${label}</button>`;
  const modeSeg = (ant) => `<div class="rm-seg">${Object.keys(MODES).map((k) => `<button data-mode="${ant}:${k}" class="${R.s[ant].mode === k ? 'on' : ''}" title="${MODES[k][0]} direction">${MODES[k][1]} ${MODES[k][0]}</button>`).join('')}</div>`;
  function remote() {
    const el = $('#radar-remote'); if (!el || !R.s) return;
    const s = R.s;
    el.innerHTML = `<div class="rm-card">
      <div class="rm-head"><div><b>Radar remote</b><div class="rm-sub">Speed radar + plate reader · ${R.units}</div></div><button class="rm-x" data-rm="close" title="Close (Esc)">✕</button></div>
      <div class="rm-sec"><div class="rm-t">Antennas</div>
        <div class="rm-ant"><div class="rm-al">${tog('front', s.front.on, 'Front')}</div>${modeSeg('front')}</div>
        <div class="rm-ant"><div class="rm-al">${tog('rear', s.rear.on, 'Rear')}</div>${modeSeg('rear')}</div></div>
      <div class="rm-sec"><div class="rm-t">Locks</div><div class="rm-grid4">
        <button class="rm-b" data-lock="front:speed">🔒 Front speed</button><button class="rm-b" data-lock="rear:speed">🔒 Rear speed</button>
        <button class="rm-b" data-lock="front:plate">🔒 Front plate</button><button class="rm-b" data-lock="rear:plate">🔒 Rear plate</button></div>
        <button class="rm-b wide" data-rm="reset">⟲ Clear all locks</button></div>
      <div class="rm-sec"><div class="rm-t">Fast limit</div>
        <div class="rm-row"><button class="rm-b sq" data-fast="-5">−</button><div class="rm-fast"><b id="rm-fast">${s.fast}</b> ${R.units}</div><button class="rm-b sq" data-fast="5">＋</button>
          <input type="range" min="10" max="200" step="1" value="${s.fast}" id="rm-fast-r"></div>
        <div class="rm-row">${tog('beep', s.beep, 'Beep over the limit')}${s.autoLockAllowed !== false ? tog('autoLock', s.autoLock, 'Auto-lock over the limit') : ''}</div></div>
      <div class="rm-sec"><div class="rm-t">Display</div>
        <div class="rm-row">${tog('shown', s.shown, 'Radar on')}${tog('plates', s.plates, 'Plate reader')}${tog('muted', s.muted, 'Mute')}</div>
        <label class="rm-sl"><span>Beep volume</span><input type="range" min="0" max="1" step="0.05" value="${s.volume}" data-sl="volume"><b>${Math.round(s.volume * 100)}%</b></label>
        <label class="rm-sl"><span>Size</span><input type="range" min="0.6" max="1.6" step="0.05" value="${s.scale}" data-sl="scale"><b>${Math.round(s.scale * 100)}%</b></label>
        <div class="rm-row"><span class="rm-hint">Drag the radar to move it.</span><button class="rm-b" data-rm="pos">Reset position</button><button class="rm-b" data-rm="test">♪ Test beep</button></div></div>
      <div class="rm-sec"><div class="rm-t">Plate hits <span class="rm-hint">· BOLO, stolen, owner warrant</span></div>
        ${R.hits.length ? R.hits.map((h) => `<div class="rm-hit"><span class="rd-pl sm">${esc(h.plate)}</span><span class="rm-why">${esc(h.text)}</span><button class="rm-b" data-open="${esc(h.plate)}">Open in MDT</button></div>`).join('') : '<div class="rm-hint">No hits yet this shift.</div>'}</div>
      <div class="rm-keys">Keys (GTA Settings › Key Bindings › FiveM): radar on/off, remote, lock front/rear speed, lock front/rear plate, reset. <b>/radaropen</b> opens the last hit. More in the pause menu: Settings › Server Settings › Radar, and in the MDT's Radar tab.</div>
    </div>`;
    const redraw = () => { remote(); place(); if (R.last) draw(R.last); save(); };
    $$('[data-tog]', el).forEach((b) => b.onclick = () => { const k = b.dataset.tog; if (k === 'front' || k === 'rear') s[k].on = !s[k].on; else s[k] = !s[k]; redraw(); });
    $$('[data-mode]', el).forEach((b) => b.onclick = () => { const [a, m] = b.dataset.mode.split(':'); s[a].mode = m; redraw(); });
    $$('[data-fast]', el).forEach((b) => b.onclick = () => { s.fast = Math.max(5, Math.min(250, s.fast + +b.dataset.fast)); redraw(); });
    $('#rm-fast-r', el).oninput = (e) => { s.fast = +e.target.value; $('#rm-fast', el).textContent = s.fast; if (R.last) draw(R.last); save(); };
    $$('[data-sl]', el).forEach((i) => i.oninput = () => { s[i.dataset.sl] = +i.value; i.nextElementSibling.textContent = Math.round(+i.value * 100) + '%'; place(); save(); });
    $$('[data-lock]', el).forEach((b) => b.onclick = () => { const [a, w] = b.dataset.lock.split(':'); post('radarLock', { antenna: a, what: w }); });
    $$('[data-open]', el).forEach((b) => b.onclick = () => post('radarOpenPlate', { plate: b.dataset.open }));
    $$('[data-rm]', el).forEach((b) => b.onclick = () => {
      const k = b.dataset.rm;
      if (k === 'close') post('radarClose');
      else if (k === 'reset') post('radarReset');
      else if (k === 'pos') { s.x = null; s.y = null; s.pos = 'br'; redraw(); }
      else if (k === 'test') beep(2, 1320);
    });
  }

  // Esc, or the remote's own key (F7 unless rebound: the game does not see keys while the remote has the focus)
  document.addEventListener('keydown', (e) => {
    if (!R.remote) return;
    const k = String(e.key || '').toUpperCase();
    if (k === 'ESCAPE' || (R.closeKey && k === String(R.closeKey).toUpperCase())) { e.preventDefault(); post('radarClose'); }
  });

  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
    if (!m || !m.action || m.action.indexOf('radar') !== 0) return;
    const el = $('#radar');
    if (m.action === 'radarSettings') { R.s = m.settings; R.units = m.units || 'MPH'; place(); if (R.remote) remote(); }
    else if (m.action === 'radarShow') { R.shown = !!m.show; el.classList.toggle('hidden', !R.shown); }
    else if (m.action === 'radar') { if (R.shown && m.data) draw(m.data); }
    else if (m.action === 'radarHit') {
      if (m.hit) { R.hits.unshift(m.hit); R.hits = R.hits.slice(0, 8); }
      if (!R.s || R.s.hitSound !== false) beep(3, 880);
      el.classList.add('flash'); setTimeout(() => el.classList.remove('flash'), 2400);
      if (R.remote) remote();
    } else if (m.action === 'radarRemote') {
      R.remote = !!m.open; if (Array.isArray(m.hits)) R.hits = m.hits; if (m.closeKey) R.closeKey = m.closeKey;
      $('#radar-remote').classList.toggle('hidden', !R.remote); el.classList.toggle('editing', R.remote);
      if (R.remote) remote();
      if (R.last) draw(R.last);
    }
  });
})();
