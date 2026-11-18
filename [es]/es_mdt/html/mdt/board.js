// es_mdt 2.0.7: the quick call board (hotkey, MDT closed). Lua (mdt/client/ops.lua) owns the data and the focus; this
// draws { action: 'board', show, calls, loading, error, key, myCall } and answers with boardAct / boardClose.
(() => {
  'use strict';
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const RES = (() => { try { return GetParentResourceName(); } catch (e) { return 'es_mdt'; } })();
  const post = (name, body) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) })
    .then((r) => r.json()).catch(() => ({ ok: false, why: 'The game did not answer' }));
  const KIND = { '911': '911', '311': '311', panic: 'PANIC', officer: 'Officer', alert: 'Alert', medical: 'Medical', shots: 'Shots', theft: 'Theft', backup: 'Backup',
    robbery: 'Robbery', drugs: 'Drugs', explosion: 'Explosion', fight: 'Fight', suspicious: 'Suspicious', down: 'Person down', speeding: 'Speeding' };
  const keyName = (k) => ({ DELETE: 'DEL', ESCAPE: 'ESC', RETURN: 'ENTER' }[String(k || '').toUpperCase()] || k || '');
  const ageTxt = (s) => s < 60 ? 'now' : s < 3600 ? `${Math.floor(s / 60)}m` : `${Math.floor(s / 3600)}h`;
  let el = null, B = { calls: [], now: 0, at: 0, key: 'O', myCall: null, busy: {}, note: null, error: null, loading: false };
  const box = () => { if (!el) { el = document.createElement('div'); el.id = 'cboard'; el.className = 'cb hidden'; document.body.appendChild(el); } return el; };

  function unitsTxt(c) {
    const u = Array.isArray(c.units) ? c.units : [];
    if (!u.length) return '<span class="cb-none">No units</span>';
    return `<span class="cb-n">${u.length} responding</span>` + u.slice(0, 3).map((x) => `<span class="cb-u${x.st === 'scene' ? ' sc' : x.st === 'enroute' ? ' er' : ''}">${esc(x.cs || (x.name || '').split(' ')[0])}</span>`).join('') + (u.length > 3 ? `<span class="cb-u">+${u.length - 3}</span>` : '');
  }
  function det(d) {
    if (!d) return '';
    const o = [];
    if (d.plate) o.push(`<b class="mono">${esc(d.plate)}</b>`);
    if (d.vehicle || d.color) o.push(esc([d.color, d.vehicle].filter(Boolean).join(' ')));
    if (d.weapon) o.push(`<span class="g${esc(d.grade || 2)}">${esc(d.weapon)}</span>`);
    return o.length ? `<div class="cb-det">${o.join(' · ')}</div>` : '';
  }
  function draw() {
    const root = box();
    const age = (c) => Math.max(0, (B.now || 0) + Math.floor((Date.now() - B.at) / 1000) - (c.createdAt || 0));
    const rows = (B.calls || []).map((c) => {
      const mine = c.mine || B.myCall === c.id, busy = B.busy[c.id];
      return `<div class="cb-row p${c.priority}${c.critical ? ' crit' : ''}${mine ? ' mine' : ''}" data-id="${c.id}">
        <div class="cb-l">
          <div class="cb-t">${c.critical ? '<span class="cb-crit">CRIT</span>' : ''}<span class="cb-p">P${esc(c.priority)}</span><span class="cb-k">${c.icon ? esc(c.icon) + ' ' : ''}${esc(KIND[c.kind] || c.kind)}</span>
            <b>#${c.id} ${esc(c.title)}</b>${(c.reports || 1) > 1 ? `<span class="cb-rep">×${esc(c.reports)}</span>` : ''}<span class="cb-age">${ageTxt(age(c))}</span></div>
          <div class="cb-s">📍 ${esc(c.street || (c.x != null ? 'On the map' : 'No location'))}${c.radius ? ` <span class="cb-area">◎ ~${esc(c.radius)} m</span>` : ''}</div>
          ${det(c.details)}
          <div class="cb-units">${unitsTxt(c)}</div>
        </div>
        <div class="cb-a">
          ${mine ? `<button class="cb-btn" data-act="route" ${busy ? 'disabled' : ''}>🧭 GPS</button><button class="cb-btn ghost" data-act="detach" ${busy ? 'disabled' : ''}>Leave</button>`
            : `<button class="cb-btn go" data-act="respond" ${busy ? 'disabled' : ''}>Respond</button>${c.x != null ? `<button class="cb-btn ghost" data-act="route" ${busy ? 'disabled' : ''}>🧭 Waypoint</button>` : ''}`}
          ${c.alarm ? '<button class="cb-btn warn" data-act="ack">Ack alarm</button>' : ''}
        </div></div>`;
    }).join('');
    root.innerHTML = `<div class="cb-card" role="dialog" aria-label="Call board">
      <div class="cb-head"><span class="cb-title">Call board</span><span class="cb-count">${(B.calls || []).length} active</span><span class="cb-sp"></span>
        <span class="cb-hint"><kbd>${esc(keyName(B.key) || 'ESC')}</kbd> / <kbd>ESC</kbd> close</span><button class="cb-x" data-close aria-label="Close">✕</button></div>
      ${B.note ? `<div class="cb-note ${B.note.ok ? 'ok' : 'bad'}">${esc(B.note.text)}</div>` : ''}
      <div class="cb-list">${B.error ? `<div class="cb-empty">${esc(B.error)}</div>` : B.loading && !(B.calls || []).length ? '<div class="cb-empty">Loading…</div>'
        : rows || '<div class="cb-empty">No active calls. Quiet shift.</div>'}</div></div>`;
    root.classList.remove('hidden');
  }
  let noteT = null;
  function note(text, ok) { B.note = { text, ok }; draw(); clearTimeout(noteT); noteT = setTimeout(() => { B.note = null; draw(); }, 2600); }
  function close() { post('boardClose'); }

  document.addEventListener('click', (e) => {
    if (!el || el.classList.contains('hidden') || !el.contains(e.target)) return;
    if (e.target.closest('[data-close]')) return close();
    const b = e.target.closest('[data-act]'); if (!b) return;
    const id = +b.closest('[data-id]').dataset.id, act = b.dataset.act;
    B.busy[id] = true; draw();
    post('boardAct', { id, act }).then((r) => {
      B.busy[id] = false;
      if (!r || r.ok === false) return note((r && r.why) || 'That did not work', false);
      note(act === 'respond' ? (r.units > 1 ? 'Attached with your partner · GPS set' : (r.gps ? 'Attached · GPS set' : 'Attached')) : act === 'route' ? 'Waypoint set' : act === 'detach' ? 'Left the call' : 'Alarm acknowledged', true);
    });
  });
  document.addEventListener('keydown', (e) => {
    if (!el || el.classList.contains('hidden')) return;
    const k = String(B.key || '').toUpperCase();
    if (e.key === 'Escape' || (k.length === 1 && e.key.toUpperCase() === k)) { e.preventDefault(); close(); }
  });
  setInterval(() => { if (el && !el.classList.contains('hidden') && B.calls.length) draw(); }, 30000);

  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
    if (!m || m.action !== 'board') return;
    if (!m.show) { B.calls = []; B.error = null; if (el) { el.classList.add('hidden'); el.innerHTML = ''; } return; }
    if (m.key) B.key = m.key;
    B.loading = !!m.loading; B.error = m.error || null;
    if (Array.isArray(m.calls)) { B.calls = m.calls; B.now = m.now || Math.floor(Date.now() / 1000); B.at = Date.now(); B.myCall = m.myCall || null; }
    draw();
  });
  window.EsBoard = { draw: (m) => window.postMessage(Object.assign({ action: 'board' }, m), '*') };
})();
