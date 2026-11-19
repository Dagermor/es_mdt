// es_mdt page. Talks to client/main.lua ('call' -> SecureCallback es_mdt:<name>); the server decides everything.
(function () {
  'use strict';
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'es_mdt';
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');
  const S = { open: false, ctx: null, view: 'dashboard', arg: null, logos: {}, penal: null, timer: null, dirty: false };

  async function post(path, data) {
    try {
      const r = await fetch(`https://${RES}/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) });
      return await r.json();
    } catch (e) { return { ok: false, why: 'The game did not answer' }; }
  }
  // 2.0.7: a burst of legitimate requests (the MDT reopening on a page, a live refresh arriving at the same moment) can
  // meet whip's per-callback limit: wait a moment and ask again (twice) instead of showing "Rate limited"
  const call = async (name, data) => {
    const body = { name, data: data || {} };
    let r = await post('call', body);
    for (let i = 0; i < 2 && r && r.ok === false && r.why === 'Rate limited'; i++) {
      await new Promise((ok) => setTimeout(ok, 450 + i * 500));
      r = await post('call', body);
    }
    return r;
  };

  // ---------------------------------------------------------------- small tools
  let toastTimer = null;
  function toast(text, kind) {
    const t = $('#toast');
    t.innerHTML = `<span class="t-dot"></span><span>${esc(text)}</span>`;
    t.className = 'toast show ' + (kind || '');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 3400);
  }
  function said(r, okText) {
    if (r && r.ok) { if (okText) toast(okText, 'ok'); return true; }
    toast((r && r.why) || 'That did not work', 'err');
    return false;
  }
  async function busy(btn, fn) {
    if (!btn || btn.disabled) return;
    btn.disabled = true; btn.classList.add('loading');
    try { return await fn(); } finally { btn.disabled = false; btn.classList.remove('loading'); }
  }
  function ago(t) {
    if (!t) return '—';
    const s = Math.max(0, Date.now() / 1000 - t);
    if (s < 60) return 'just now';
    if (s < 3600) return Math.floor(s / 60) + ' min ago';
    if (s < 86400) return Math.floor(s / 3600) + ' h ago';
    const d = Math.floor(s / 86400); return d === 1 ? 'yesterday' : d + ' days ago';
  }
  const date = (t) => t ? new Date(t * 1000).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) : '—';
  const dateTime = (t) => t ? new Date(t * 1000).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—';
  const hours = (s) => (Math.round((s || 0) / 360) / 10).toLocaleString('en-US');
  // a duration: minutes under an hour, else hours ('24 min', '3.5 h')
  const dur = (s) => { s = s || 0; if (s < 60) return s > 0 ? '<1 min' : '0 min'; if (s < 3600) return Math.round(s / 60) + ' min'; return hours(s) + ' h'; };
  // a calendar day stored as midnight on the server (leave dates): no time-zone shift
  const calDate = (t) => t ? new Date(t * 1000).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' }) : '—';
  const inDays = (t) => { const d = Math.ceil((t - Date.now() / 1000) / 86400); return d <= 0 ? 'expires today' : d === 1 ? 'expires tomorrow' : `expires in ${d} days`; };
  const BAD_FLAGS = ['Armed', 'Dangerous', 'Stolen', 'Wanted'];
  const flagCls = (f) => BAD_FLAGS.includes(f) ? 'bad' : 'warn';
  const isoDay = (d) => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  const P = () => (S.ctx && S.ctx.perms) || {};
  const RO = () => !!(S.ctx && S.ctx.readOnly);
  const can = (p) => !RO() && !!P()[p];
  const empty = (txt, ico) => `<div class="empty-state"><div class="es-ico">${ico || '◌'}</div>${esc(txt)}</div>`;
  const pill = (txt, cls) => `<span class="pill ${cls || ''}">${esc(txt)}</span>`;
  // 1.7.0: certification badges (roster, profile): valid / expiring (amber ring) / expired (struck out)
  // css vars for a colour (no color-mix in older game browsers): --cc, --cca (tint), --ccb (border), --cct (light text)
  const ccv = (hex) => {
    const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim()); const n = parseInt(m ? m[1] : '3b82f6', 16);
    const r = n >> 16 & 255, g = n >> 8 & 255, b = n & 255, l = (x) => Math.round(x + (255 - x) * 0.55);
    return `--cc:#${(m ? m[1] : '3b82f6')};--cca:rgba(${r},${g},${b},.2);--ccb:rgba(${r},${g},${b},.55);--cct:rgb(${l(r)},${l(g)},${l(b)})`;
  };
  const certBadges = (list, small) => (list || []).length ? `<span class="cert-row${small ? ' sm' : ''}">${list.map((c) => `<span class="cert-b ${c.state || 'valid'}" style="${ccv(c.color)}" title="${esc(c.name)}${c.state === 'expired' ? ' · expired' : c.state === 'expiring' ? ' · expires ' + new Date(c.expiresAt * 1000).toLocaleDateString() : c.expiresAt ? ' · until ' + new Date(c.expiresAt * 1000).toLocaleDateString() : ''}">${c.icon ? `<i>${esc(c.icon)}</i>` : ''}${small ? '' : esc(c.name)}</span>`).join('')}</span>` : '';
  const typeLabel = (k) => { const t = ((S.ctx && S.ctx.config.reportTypes) || []).find((x) => x.key === k); return t ? t.label : k; };
  const statusOf = (k) => ((S.ctx && S.ctx.config.statuses) || []).find((x) => x.key === k) || { label: k, color: '#8a93a6' };

  // A confirm / form dialog inside the page (no focus juggling with the game)
  function modal(html, onReady) {
    const m = $('#modal'), card = $('#modal-card');
    card.classList.remove('wide'); card.innerHTML = html; m.classList.remove('hidden');
    requestAnimationFrame(() => m.classList.add('shown'));
    const closeIt = () => { m.classList.remove('shown'); setTimeout(() => { m.classList.add('hidden'); card.innerHTML = ''; }, 150); };
    $$('[data-x]', card).forEach((b) => b.onclick = closeIt);
    if (onReady) onReady(card, closeIt);
    const first = $('input, textarea, select', card); if (first) first.focus();
    return closeIt;
  }
  function confirmBox(title, text, yes, danger) {
    return new Promise((res) => {
      modal(`<div class="m-title">${esc(title)}</div><p class="m-text">${esc(text)}</p>
        <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn ${danger ? 'danger' : 'accent'}" id="m-yes" data-primary>${esc(yes || 'Yes')}</button></div>`,
      (card, closeIt) => {
        $('#m-yes', card).onclick = () => { closeIt(); res(true); };
        $$('[data-x]', card).forEach((b) => b.addEventListener('click', () => res(false)));
      });
    });
  }
  const modalOpen = () => !$('#modal').classList.contains('hidden');

  async function logoOf(d) {
    if (!d || !d.id) return null;
    const k = d.id + ':' + (d.logoVer || 0);
    if (S.logos[k] !== undefined) return S.logos[k];
    const r = await post('logo', { id: d.id, ver: d.logoVer });
    S.logos[k] = (r && r.ok && r.data) || null;
    return S.logos[k];
  }

  // A search box that finds a person; onPick({charId, name})
  function personPicker(host, placeholder, onPick) {
    host.innerHTML = `<div class="picker-wrap"><input type="text" class="pp-in" placeholder="${esc(placeholder || 'Search a name or phone…')}" autocomplete="off"><div class="pop hidden"></div></div>`;
    const inp = $('.pp-in', host), pop = $('.pop', host);
    let t = null, seq = 0;
    inp.addEventListener('input', () => {
      clearTimeout(t);
      const q = inp.value.trim();
      if (q.length < 2) { pop.classList.add('hidden'); return; }
      t = setTimeout(async () => {
        const my = ++seq;
        const r = await call('people', { q });
        if (my !== seq) return;
        const list = (r.ok && r.data) || [];
        pop.innerHTML = list.length ? list.map((p) => `<div class="pop-row" data-id="${p.charId}" data-name="${esc(p.name)}"><b>${esc(p.name)}</b><span class="hint">#${p.charId}${p.dob ? ' · ' + esc(p.dob) : ''}${p.warrants ? ' · <span class="txt-bad">warrant</span>' : ''}</span></div>`).join('')
          : '<div class="pop-empty">Nobody found</div>';
        pop.classList.remove('hidden');
        $$('.pop-row', pop).forEach((row) => row.onclick = () => { pop.classList.add('hidden'); inp.value = ''; onPick({ charId: +row.dataset.id, name: row.dataset.name }); });
      }, 220);
    });
    inp.addEventListener('blur', () => setTimeout(() => pop.classList.add('hidden'), 180));
    return inp;
  }

  // ---------------------------------------------------------------- frame
  const NAV = [
    { head: 'Patrol' },
    { key: 'dashboard', label: 'Dashboard', ico: '◧' },
    { key: 'dispatch', label: 'Dispatch', ico: '☎' },
    { key: 'units', label: 'Active units', ico: '◉' },
    { key: 'livemap', label: 'Live map', ico: '⌖', show: () => (S.ctx.onDuty || S.ctx.staff) && ((S.ctx.config.liveMap || {}).enabled !== false || S.ctx.staff) },
    // 2.0.11: the in-car radar and plate reader (police, sheriff and state police, or staff; an admin can hide the tab)
    { key: 'radar', label: 'Radar', ico: '📡', show: () => { const r = (S.ctx.config || {}).radar; return !!(r && r.enabled !== false && r.tab !== false && (r.law || S.ctx.staff)); } },
    { key: 'arrest', label: 'Process arrest', ico: '⛓', show: () => !!P().mdt_reports_write },
    { key: 'bolos', label: 'BOLOs', ico: '⚑' },
    { key: 'jail', label: 'Jail', ico: '▥' },
    { head: 'Records' },
    { key: 'people', label: 'People', ico: '☺' },
    { key: 'vehicles', label: 'Vehicles', ico: '⛍' },
    { key: 'weapons', label: 'Weapons', ico: '◎' },
    { key: 'permits', label: 'Firearm permits', ico: '✪', show: () => !!(S.ctx.staff || P().permits_manage) },
    { key: 'evidence', label: 'Evidence', ico: '⚲', show: () => S.ctx.config.esEvidence !== false && !!(S.ctx.staff || P().evidence_collect || P().evidence_lab || P().evidence_manage || P().mdt_reports_write) },
    { key: 'cases', label: 'Cases', ico: '▣' },
    { key: 'reports', label: 'Reports', ico: '☰' },
    { key: 'warrants', label: 'Warrants', ico: '⚖' },
    { key: 'penal', label: 'Penal code', ico: '§' },
    { key: 'court', label: 'Court (DOJ)', ico: '⚖', show: () => !!S.ctx.court },
    { head: 'Department' },
    { key: 'stats', label: 'Stats', ico: '▤' },
    { key: 'department', label: 'Department', ico: '⛨', show: () => { const r = S.ctx.rights || {}; return S.ctx.staff || r.roster || r.hire || r.promote || r.fire || P().loa_manage; } },
    { key: 'training', label: 'Training (FTO)', ico: '✎', show: () => S.ctx.staff || P().fto_train || P().fto_manage || P().canPromote || S.ctx.trainee },
    { key: 'leave', label: 'My leave', ico: '☂' },
    { key: 'officer', label: 'My profile', ico: '☻' },
    { key: 'testdata', label: 'Admin · Test data', ico: '🧹', show: () => !!S.ctx.staff && S.ctx.config.devTools !== false },
  ];

  function renderFrame() {
    const c = S.ctx, d = c.dept;
    $('.shell').style.setProperty('--d1', d.color1 || '#1b2a5c');
    $('.shell').style.setProperty('--d2', d.color2 || '#f2c230');
    $('#brand-short').textContent = d.short; $('#brand-name').textContent = d.name;
    const bl = $('#brand-logo'); bl.innerHTML = `<span>${esc(d.short.slice(0, 2))}</span>`;
    logoOf(d).then((src) => { if (src) bl.innerHTML = `<img src="${src}" alt="">`; });
    const pick = $('#dept-pick');
    pick.classList.toggle('hidden', (c.depts || []).length < 2);
    pick.innerHTML = (c.depts || []).map((x) => `<option value="${x.id}"${x.id === d.id ? ' selected' : ''}>${esc(x.short)}${x.onDuty ? ' · on duty' : ''}</option>`).join('');
    $('#nav').innerHTML = NAV.filter((n) => n.head || !n.show || n.show()).map((n) => n.head ? `<div class="nav-head">${esc(n.head)}</div>`
      : `<button class="nav-item${S.view === n.key ? ' on' : ''}" data-nav="${n.key}" data-probe-press><span class="n-ico">${n.ico}</span><span>${n.label}</span><span class="n-badge hidden" data-badge="${n.key}"></span></button>`).join('');
    const st = statusOf(c.me.status);
    $('#me').innerHTML = `<div class="me-name">${esc(c.me.name)}</div>
      <div class="hint">${esc(c.me.roleName || '')}${c.me.callsign ? ' · ' + esc(c.me.callsign) : ''}</div>
      ${c.onDuty ? `<div class="me-status" style="--sc:${st.color}"><span class="dot"></span>${esc(st.label)}</div>` : '<div class="me-status off"><span class="dot"></span>Off duty</div>'}`;
    $('#duty').innerHTML = c.onDuty ? '<span class="pill on">On duty</span>' : (c.staff ? '<span class="pill">Admin</span>' : '<span class="pill off">Off duty · read-only</span>');
    $('#ro-banner').classList.toggle('hidden', !c.readOnly);
    applyBadges();
  }

  // ---------------------------------------------------------------- count badges (what is waiting)
  function applyBadges() {
    const t = S.todo || {};
    setBadge('warrants', t.warrantRequests || 0, 'warn');
    setBadge('department', (t.loa || 0) + (t.certs || 0), 'warn');
    setBadge('training', (t.unclaimed || 0) + (t.recs || 0) + (t.rides || 0) + (t.overdue || 0), t.overdue ? 'warn' : 'accent');
    setBadge('units', t.invites || 0, 'accent');
    setBadge('dispatch', t.calls || 0, 'bad');
    setBadge('permits', t.permits || 0, 'warn');
  }
  async function loadBadges() {
    const r = await call('badges');
    if (r.ok) { S.todo = r.data || {}; applyBadges(); }
  }
  const tabBadge = (n, cls) => n ? `<span class="t-badge ${cls || ''}">${n}</span>` : '';

  function setBadge(key, n, cls) {
    const b = $(`[data-badge="${key}"]`); if (!b) return;
    b.textContent = n; b.className = 'n-badge ' + (cls || '') + (n ? '' : ' hidden');
  }

  function go(view, arg) {
    S.view = view; S.arg = arg == null ? null : arg; S.dirty = false;
    $$('.nav-item').forEach((b) => b.classList.toggle('on', b.dataset.nav === view));
    const v = $('#view'); v.classList.remove('fade-in'); void v.offsetWidth; v.classList.add('fade-in');
    v.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const fn = VIEWS[view];
    if (!fn) {
      // 1.3.1: a tab whose script did not load (e.g. the server was not told about new files: run `refresh`) says so instead of spinning
      v.innerHTML = `<div class="v-head"><h1>${esc(view)}</h1></div>` + empty('This part of the MDT did not load. An admin needs to run "refresh" then "ensure es_mdt".', '⚠');
      return;
    }
    fn(v, S.arg);
  }

  const VIEWS = {};
  const HOOK = {};   // 1.3.0: ops.js (dispatch, map, mugshots, arrest, announcements, templates) plugs in here

  // ---------------------------------------------------------------- dashboard
  function statusSeg(cur) {
    return `<div class="seg status-seg">${(S.ctx.config.statuses || []).map((s) => `<button data-status="${s.key}" class="${s.key === cur ? 'on' : ''}" style="--sc:${s.color}" data-probe-press>${esc(s.label)}</button>`).join('')}</div>`;
  }
  function wireStatus(root, after) {
    $$('[data-status]', root).forEach((b) => b.onclick = () => busy(b, async () => {
      if (said(await call('setStatus', { status: b.dataset.status }), 'Status: ' + b.textContent)) { S.ctx.me.status = b.dataset.status; renderFrame(); if (after) after(); }
    }));
  }

  VIEWS.dashboard = async (v) => {
    const r = await call('dashboard');
    if (S.view !== 'dashboard') return;
    if (!r.ok) { v.innerHTML = empty(r.why); return; }
    const x = r.data, t = x.todo || {}, c = S.ctx;
    const mineDept = (x.units || []).find((g) => g.id === c.dept.id);
    const allUnits = (x.units || []).reduce((n, g) => n + (g.people || g.units.length), 0);
    const todos = [];
    if (t.warrantRequests) todos.push(['warrants', `${t.warrantRequests} warrant request${t.warrantRequests === 1 ? '' : 's'} to review`, 'warn']);
    if (t.permits) todos.push(['permits', `${t.permits} firearm permit application${t.permits === 1 ? '' : 's'} to review`, 'warn']);
    if (t.loa) todos.push(['department:leave', `${t.loa} leave request${t.loa === 1 ? '' : 's'} waiting`, 'warn']);
    if (t.recs) todos.push(['training:recs', `${t.recs} promotion recommendation${t.recs === 1 ? '' : 's'}`, 'accent']);
    if (t.unclaimed) todos.push(['training', `${t.unclaimed} new hire${t.unclaimed === 1 ? '' : 's'} need an FTO`, 'accent']);
    if (t.invites) todos.push(['units', 'A unit request is waiting for you', 'accent']);
    if (t.rides) todos.push(['training', `${t.rides} ride-along${t.rides === 1 ? '' : 's'} to write up`, 'accent']);
    if (t.inactive) todos.push(['department:activity', `${t.inactive} member${t.inactive === 1 ? '' : 's'} inactive`, 'bad']);
    const loa = (x.myLoa || [])[0];
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Good to see you, ${esc(c.me.name.split(' ')[0])}</div>
        <div class="hint">${esc(c.dept.name)}${loa ? ` · <b>you are on leave until ${calDate(loa.endsAt)}</b>` : ''}</div></div>
        ${c.onDuty ? statusSeg(c.me.status) : ''}</div>
      <div class="kpis">
        <div class="kpi"><b>${mineDept ? (mineDept.people || mineDept.units.length) : 0}</b><span>${esc(c.dept.short)} on duty</span></div>
        <div class="kpi"><b>${allUnits}</b><span>all units on duty</span></div>
        <div class="kpi"><b class="${(x.warrants || []).length ? 'txt-bad' : ''}">${(x.warrants || []).filter((w) => w.status === 'active').length}</b><span>active warrants</span></div>
        <div class="kpi"><b>${(x.bolos || []).length}</b><span>active BOLOs</span></div>
        <div class="kpi"><b>${dur(x.myDuty7)}</b><span>your duty time this week</span></div>
        <div class="kpi"><b>${x.myReports7 || 0}</b><span>your reports this week</span></div>
      </div>
      ${todos.length ? `<div class="todo">${todos.map(([to, txt, cls]) => `<button class="todo-chip ${cls}" data-go="${to}" data-probe-press>${esc(txt)} →</button>`).join('')}</div>` : ''}
      <div id="dash-ops"></div>
      <div class="cols3">
        <div class="card"><div class="card-head"><div class="card-title">Recent reports</div><button class="btn small ghost" data-go="reports">All →</button></div>
          ${(x.reports || []).length ? x.reports.map((rp) => `<div class="li click" data-report="${rp.id}"><span class="tag t-${esc(rp.type)}">${esc(typeLabel(rp.type))}</span><div class="li-main"><b>#${rp.id} ${esc(rp.title)}</b><span class="hint">${esc(rp.authorName || '')} · ${ago(rp.createdAt)}</span></div></div>`).join('') : empty('No reports yet')}
        </div>
        <div class="card"><div class="card-head"><div class="card-title">Warrants</div><button class="btn small ghost" data-go="warrants">All →</button></div>
          ${(x.warrants || []).length ? x.warrants.map((w) => `<div class="li click" data-person="${w.charId}"><span class="pill ${w.status === 'active' ? 'bad' : 'warn'}">${w.status === 'active' ? 'Active' : 'Requested'}</span><div class="li-main"><b>${esc(w.name || '#' + w.charId)}</b><span class="hint">${esc(w.reason)}</span></div></div>`).join('') : empty('No open warrants')}
        </div>
        <div class="card"><div class="card-head"><div class="card-title">BOLOs</div><button class="btn small ghost" data-go="bolos">All →</button></div>
          ${(x.bolos || []).length ? x.bolos.map((b) => `<div class="li${b.kind === 'weapon' && b.serial ? ' click' : ''}"${b.kind === 'weapon' && b.serial ? ` data-wpn="${esc(b.serial)}"` : ''}>${b.kind === 'vehicle' ? `<span class="plate">${esc(b.plate || '—')}</span>` : b.kind === 'weapon' ? (b.serial ? serialTag(b.serial) : '<span class="pill bad">Weapon</span>') : '<span class="pill">Person</span>'}<div class="li-main"><b>${esc(b.title)}</b><span class="hint">${esc(b.name || '')} ${ago(b.createdAt)}</span></div></div>`).join('') : empty('No active BOLOs')}
        </div>
      </div>
      <div class="card"><div class="card-head"><div class="card-title">On duty now</div><button class="btn small ghost" data-go="units">Units →</button></div>${unitsHtml(x.units, true)}</div>`;
    wireStatus(v, () => go('dashboard'));
    fillUnitLogos(v);
    S.todo = t; applyBadges();
    if (HOOK.dashboard) HOOK.dashboard(v, x);
  };

  // ---------------------------------------------------------------- units
  const TEAM_LBL = { patrol: 'Patrol unit', fto: 'FTO ride-along' };
  function unitActs(u, me, mineTeam) {
    const c = S.ctx, U = S.units || {};
    const statusSel = `<select class="small-sel" data-ustatus title="Set your unit's status">${(c.config.statuses || []).map((s2) => `<option value="${s2.key}"${s2.key === u.status ? ' selected' : ''}>${esc(s2.label)}</option>`).join('')}</select>`;
    if (me || mineTeam) return (c.onDuty ? statusSel : '') + (mineTeam ? '<button class="btn small danger-ghost" data-uleave title="Leave this unit">Leave unit</button>' : '');
    const gps = `<button class="btn small" data-gps="${u.charId}" data-name="${esc(u.team ? u.callsign : u.name)}" title="Set a GPS waypoint to this unit">⌖ GPS</button>`;
    const canPair = c.onDuty && U.onDuty && !U.teamId && !u.team && !U.invite;
    const pair = canPair ? `<button class="btn small accent-ghost" data-upair="${u.charId}" data-mode="invite" data-name="${esc(u.name)}" data-call="${esc(u.callsign || '')}" title="Invite them into your unit (you lead)">+ Invite</button>
      <button class="btn small" data-upair="${u.charId}" data-mode="join" data-name="${esc(u.name)}" data-call="${esc(u.callsign || '')}" title="Ask to join their unit (they lead)">Join</button>` : '';
    return gps + pair;
  }
  function unitsHtml(groups, compact) {
    if (!groups || !groups.length) return empty('Nobody is on duty', '◉');
    const myId = S.ctx && S.ctx.me.charId;
    return groups.map((g) => `<div class="u-group" style="--gc:${esc(g.color1)}"><div class="u-head"><span class="u-logo" data-ulogo="${g.id}" data-ver="${g.logoVer || 0}"></span><b>${esc(g.short)}</b><span class="hint">${g.people || g.units.length} on duty</span></div>
      <div class="u-grid${compact ? ' compact' : ''}">${g.units.map((u) => { const st = statusOf(u.status);
        if (u.team) {
          const ms = u.team.members, mine = ms.some((m) => m.charId === myId);
          const c1 = ms[0].color1 || g.color1, c2 = (ms[1] && ms[1].color1) || c1;
          return `<div class="unit team${mine ? ' mine' : ''}${u.panic ? ' panic' : ''}" style="--sc:${st.color};--gc1:${esc(c1)};--gc2:${esc(c2)}">
            <div class="u-call">${esc(u.callsign)}</div>
            <div class="u-who"><div class="u-type ${u.team.type}">${u.team.type === 'fto' ? '🎓 ' : '👥 '}${esc(TEAM_LBL[u.team.type] || 'Unit')}${!compact ? ` <span class="hint">· together ${dur(Math.max(60, Date.now() / 1000 - u.team.startedAt))}</span>` : ''}</div>
              ${ms.map((m) => `<div class="u-mem" data-person="${m.charId}"><span class="u-dot" style="background:${esc(m.color1 || g.color1)}" title="${esc(m.deptShort || '')}"></span><b>${esc(m.callsign || '—')}</b> ${esc(m.name)}${m.charId === myId ? ' <span class="pill accent">You</span>' : ''}<span class="hint"> · ${esc(m.role)}${m.deptShort && m.deptShort !== g.short ? ' · ' + esc(m.deptShort) : ''}</span></div>`).join('')}</div>
            <div class="u-side"><div class="u-st"><span class="dot"></span>${esc(st.label)}${u.since && !compact ? `<span class="hint"> · ${ago(u.since)}</span>` : ''}</div>
              ${compact ? '' : `<div class="u-act">${unitActs(u, false, mine)}</div>`}</div></div>`;
        }
        const me = u.charId === myId;
        return `<div class="unit${me ? ' mine' : ''}${u.panic ? ' panic' : ''}" style="--sc:${st.color}" data-person="${u.charId}">
        <div class="u-call">${esc(u.callsign || '—')}</div><div class="u-who"><b title="${esc(u.name)}">${esc(u.name)}${me ? ' <span class="pill accent">You</span>' : ''}</b><span class="hint">${esc(u.roleName || '')}</span></div>
        <div class="u-side"><div class="u-st"><span class="dot"></span>${esc(st.label)}${u.since && !compact ? `<span class="hint"> · ${ago(u.since)}</span>` : ''}</div>
          ${compact ? '' : `<div class="u-act">${unitActs(u, me, false)}</div>`}</div></div>`; }).join('')}</div></div>`).join('');
  }
  function pairModal(b) {
    const mode = b.dataset.mode, name = b.dataset.name, call2 = b.dataset.call, who = `${call2 ? call2 + ' ' : ''}${name}`;
    let kind = 'patrol';
    modal(`<div class="m-title">${mode === 'join' ? `Join ${esc(who)}'s unit` : `Invite ${esc(who)} to your unit`}</div>
      <p class="hint">${mode === 'join' ? `They lead: the unit shows as <b>${esc(call2 || '—')} / ${esc(S.ctx.me.callsign || '—')}</b>.` : `You lead: the unit shows as <b>${esc(S.ctx.me.callsign || '—')} / ${esc(call2 || '—')}</b>.`} They get a notification and accept in their MDT.</p>
      <div class="field"><label>What kind of unit</label><div class="pick2" id="pk">
        <button class="pick-o on" data-k="patrol"><b>👥 Patrol</b><span>Two officers on patrol together. Any departments.</span></button>
        <button class="pick-o" data-k="fto"><b>🎓 FTO ride-along</b><span>An FTO and a trainee in the same department. A training session starts, and the FTO writes it up when it ends.</span></button></div></div>
      <p class="hint">One status and one GPS mark for the unit. Duty time still counts for each of you. Either of you can leave any time; going off duty ends it.</p>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="pk-go" data-primary>${mode === 'join' ? 'Ask to join' : 'Send invite'}</button></div>`, (card, closeIt) => {
      $$('#pk [data-k]', card).forEach((o) => o.onclick = () => { kind = o.dataset.k; $$('#pk [data-k]', card).forEach((x) => x.classList.toggle('on', x === o)); });
      $('#pk-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        if (said(await call('unitInvite', { charId: +b.dataset.upair, mode, type: kind }), mode === 'join' ? 'Request sent to ' + name : 'Invite sent to ' + name)) { closeIt(); go(S.view, S.arg); }
      });
    });
  }
  function inviteBanner(U) {
    if (!U) return '';
    if (U.invite) {
      const i = U.invite, who = `${i.callsign ? esc(i.callsign) + ' ' : ''}<b>${esc(i.name)}</b>${i.deptShort ? ' <span class="hint">(' + esc(i.deptShort) + ')</span>' : ''}`;
      return `<div class="inv-banner"><span class="inv-ico">${i.type === 'fto' ? '🎓' : '👥'}</span><div class="li-main"><div>${who} ${i.mode === 'join' ? 'wants to join your unit' : 'invites you to their unit'}</div>
        <span class="hint">${esc(TEAM_LBL[i.type])} · answer within ${Math.max(1, Math.ceil((i.left || 0) / 60))} min</span></div>
        <button class="btn accent" data-uans="1">Accept</button><button class="btn ghost" data-uans="0">Decline</button></div>`;
    }
    if (U.sent) return `<div class="inv-banner sent"><span class="inv-ico">⏳</span><div class="li-main"><div>Waiting for <b>${esc(U.sent.name)}</b> to answer your ${U.sent.mode === 'join' ? 'join request' : 'invite'}</div><span class="hint">${esc(TEAM_LBL[U.sent.type])}</span></div><button class="btn ghost" data-ucancel>Cancel</button></div>`;
    return '';
  }
  function ridesCard(rides) {
    if (!rides || !rides.length) return '';
    return `<div class="card ride-card"><div class="card-title">🎓 Ride-alongs to write up</div>${rides.map((r) => `<div class="li"><div class="li-main"><b>${esc(r.traineeName || '#' + r.traineeCharId)}</b><span class="hint">${dateTime(r.startedAt)} · ${r.minutes} min</span></div>
      <button class="btn small accent" data-rlog="${r.id}">Write notes</button><button class="btn small ghost" data-rskip="${r.id}">Dismiss</button></div>`).join('')}</div>`;
  }
  function rideForm(ride, after) {
    // 1.6.0: the ride-along write-up is a Daily Observation Report (training.js)
    if (window.MDT && window.MDT.dorForm) {
      return window.MDT.dorForm({ charId: ride.traineeCharId, name: ride.traineeName || '#' + ride.traineeCharId }, after || (() => {}), {
        minutes: ride.minutes, kind: 'ridealong', at: ride.startedAt, title: `Ride-along with ${ride.traineeName || 'your trainee'} ended`,
        send: (payload) => call('rideLog', Object.assign(payload, { id: ride.id })),
      });
    }
    const F = (S.ctx.config.dept || {}).fto || { ratings: [], checklist: [], kinds: ['ridealong'] };
    ftoLogForm({ charId: ride.traineeCharId, name: ride.traineeName || '#' + ride.traineeCharId }, F, after || (() => {}), {
      minutes: ride.minutes, kind: 'ridealong', title: `Ride-along with ${ride.traineeName || 'your trainee'} ended`,
      send: (payload) => call('rideLog', Object.assign(payload, { id: ride.id })),
    });
  }
  function fillUnitLogos(root) {
    $$('[data-ulogo]', root).forEach((el) => logoOf({ id: +el.dataset.ulogo, logoVer: +el.dataset.ver }).then((src) => { if (src) el.innerHTML = `<img src="${src}" alt="">`; }));
  }

  VIEWS.units = async (v) => {
    if (S.unitsMode === 'map' && HOOK.unitsMap) return HOOK.unitsMap(v);
    const r = await call('units');
    if (S.view !== 'units') return;
    if (!r.ok) { v.innerHTML = empty(r.why); return; }
    S.units = r.data;
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Active units</div><div class="hint">Everyone clocked on right now, every department · updates live${r.data.onDuty && !r.data.teamId ? ' · pair up with <b>+ Invite</b> or <b>Join</b>' : ''}</div></div>
      <div class="row">${HOOK.unitsToggle ? HOOK.unitsToggle('list') : ''}${S.ctx.onDuty ? statusSeg(r.data.mine) : ''}</div></div>${inviteBanner(r.data)}${unitsHtml(r.data.groups)}`;
    if (HOOK.unitsWire) HOOK.unitsWire(v);
    wireStatus(v, () => go('units'));
    fillUnitLogos(v);
    $$('[data-ustatus]', v).forEach((sel) => sel.onchange = async () => {
      const lbl = sel.options[sel.selectedIndex].text;
      if (said(await call('setStatus', { status: sel.value }), 'Status: ' + lbl)) { S.ctx.me.status = sel.value; renderFrame(); go('units'); }
    });
  };

  // ---------------------------------------------------------------- people
  VIEWS.people = async (v, charId) => {
    v.innerHTML = `<div class="split"><div class="split-list">
        <div class="field"><input type="text" id="p-q" placeholder="Name, phone or ID…" autocomplete="off"></div>
        <div id="p-res" class="res-list">${empty('Search for someone', '☺')}</div></div>
      <div class="split-detail" id="p-detail">${charId ? '' : empty('Pick a person to see their record', '☺')}</div></div>`;
    const q = $('#p-q'); let t = null;
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => peopleSearch(q.value.trim()), 250); });
    if (S.lastPeopleQ) { q.value = S.lastPeopleQ; peopleSearch(S.lastPeopleQ); }
    if (charId) personDetail(charId); else { S.personId = null; q.focus(); }
  };
  async function peopleSearch(qv) {
    S.lastPeopleQ = qv;
    const box = $('#p-res'); if (!box) return;
    if (qv.length < 2) { box.innerHTML = empty('Type at least 2 letters', '☺'); return; }
    const r = await call('people', { q: qv });
    if (!$('#p-res')) return;
    const list = (r.ok && r.data) || [];
    box.innerHTML = list.length ? list.map((p) => `<div class="res click" data-pick="${p.charId}"><div><b>${esc(p.name)}</b><div class="hint">#${p.charId}${p.dob ? ' · born ' + esc(p.dob) : ''}${p.phone ? ' · ' + esc(p.phone) : ''}</div></div>
      <div class="res-tags">${p.warrants ? pill('Warrant', 'bad') : ''}${permitPill(p.permit, true)}${(p.flags || []).slice(0, 2).map((f) => pill(f, flagCls(f))).join('')}</div></div>`).join('') : empty('Nobody found');
    $$('[data-pick]', box).forEach((el) => el.onclick = () => personDetail(+el.dataset.pick));
  }

  async function personDetail(charId, quiet) {
    const box = $('#p-detail'); if (!box) return;
    S.personId = charId;
    $$('#p-res [data-pick]').forEach((el) => el.classList.toggle('sel', +el.dataset.pick === charId));
    if (!quiet) box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const keep = box.scrollTop;
    const r = await call('person', { charId });
    if (!$('#p-detail')) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const p = r.data, flagsAll = S.ctx.config.personFlags || [];
    const activeW = (p.warrants || []).filter((w) => w.status === 'active');
    box.innerHTML = `${activeW.length ? `<div class="w-banner"><span class="w-ico">⚠</span><div><b>${activeW.length} active warrant${activeW.length > 1 ? 's' : ''}</b><div>${activeW.map((w) => esc(w.reason)).join(' · ')}</div></div></div>` : ''}<div class="prof-head">
        <div class="portrait${p.mugshot ? ' mug' : ''}" id="p-portrait" title="${p.mugshot ? 'MDT mugshot' : 'Character portrait'}">${(p.mugshot || p.portrait) ? `<img src="${p.mugshot || p.portrait}" alt="">` : `<span>${esc(p.firstName[0] || '?')}${esc(p.lastName[0] || '')}</span>`}</div>
        <div class="prof-main"><div class="v-title">${esc(p.name)}</div>
          <div class="facts"><span><i>ID</i>#${p.charId}</span><span><i>Born</i>${esc(p.dob || '—')}</span><span><i>Sex</i>${esc(p.gender || '—')}</span><span><i>Phone</i>${esc(p.phone || '—')}</span></div>
          <div class="res-tags">${activeW.length ? pill(activeW.length + ' active warrant' + (activeW.length > 1 ? 's' : ''), 'bad') : ''}${p.owed ? pill(money(p.owed) + ' owed', 'warn') : ''}${permitPill(p.permit && p.permit.status)}${(p.bolos || []).length ? pill('BOLO', 'bad') : ''}${(p.departments || []).map((d) => pill(d.short + ' ' + (d.roleName || ''), 'accent')).join('')}</div>
        </div>
        <div class="prof-actions">
          ${can('mdt_reports_write') ? '<button class="btn accent small" id="pa-report" data-probe-press>+ Report</button>' : ''}
          ${(can('warrants_issue') || can('warrants_request')) ? `<button class="btn small" id="pa-warrant" data-probe-press>${P().warrants_issue ? 'Issue' : 'Request'} warrant</button>` : ''}
          ${can('fines_issue') ? '<button class="btn small" id="pa-fine" data-probe-press>Fine</button>' : ''}
          ${can('bolo_manage') ? '<button class="btn small" id="pa-bolo" data-probe-press>⚑ BOLO</button>' : ''}
          ${can('mdt_reports_write') ? '<button class="btn small" id="pa-mug" data-probe-press title="Take or upload a mugshot">📷 Mugshot</button>' : ''}
        </div></div>
      <div class="cols2">
        <div class="card"><div class="card-title">Flags &amp; notes</div>
          <div class="chips">${flagsAll.map((f) => `<label class="chip-t flag f-${flagCls(f)}"><input type="checkbox" value="${esc(f)}"${(p.flags || []).includes(f) ? ' checked' : ''}${can('mdt_reports_write') ? '' : ' disabled'}><span>${esc(f)}</span></label>`).join('')}</div>
          <textarea id="pf-notes" placeholder="Notes officers should know…"${can('mdt_reports_write') ? '' : ' disabled'}>${esc(p.notes || '')}</textarea>
          ${can('mdt_reports_write') ? '<div class="row end"><button class="btn small accent" id="pf-save" data-primary data-probe-press>Save notes</button></div>' : ''}
        </div>
        <div class="card"><div class="card-title">Warrants</div>
          ${(p.warrants || []).length ? p.warrants.map((w) => `<div class="li"><span class="pill ${w.status === 'active' ? 'bad' : w.status === 'requested' ? 'warn' : 'off'}">${esc(w.status)}</span><div class="li-main"><b>${esc(w.reason)}</b><span class="hint">#${w.id} · ${date(w.createdAt)}${w.expiresAt ? ' · ' + (w.status === 'active' ? inDays(w.expiresAt) : 'expires ' + date(w.expiresAt)) : ''}</span></div></div>`).join('') : empty('No warrants')}
        </div>
        <div class="card"><div class="card-head"><div class="card-title">Fines</div>${p.owed ? `<span class="pill warn">${money(p.owed)} owed</span>` : ''}</div>
          ${(p.fines || []).length ? p.fines.map((f) => `<div class="li"><span class="pill ${f.status === 'unpaid' ? 'warn' : f.status === 'paid' ? 'on' : 'off'}">${esc(f.status)}</span><div class="li-main"><b>${money(f.amount)}</b><span class="hint">${f.reportId ? `<a class="lnk" data-report="${f.reportId}">Report #${f.reportId}</a>` : 'Direct fine' + (f.reason && !/^Report #\d+$/.test(f.reason) ? ': ' + esc(f.reason) : '')} · ${date(f.createdAt)}</span></div>
            ${f.status === 'unpaid' && can('fines_issue') ? `<button class="btn small" data-fpay="${f.id}">Try again</button><button class="btn small ghost" data-fvoid="${f.id}">Void</button>` : ''}</div>`).join('') : empty('No fines')}
        </div>
        <div class="card"><div class="card-title">Vehicles</div>
          ${(p.vehicles || []).length ? p.vehicles.map((x) => `<div class="li click" data-veh="${x.vehicleId}"><span class="plate">${esc(x.plate)}</span><div class="li-main"><b>${esc(x.label)}</b><span class="hint">${esc(x.state)}</span></div></div>`).join('') : empty('No vehicles')}
        </div>
        ${personWeaponsCard(p)}
        <div class="card"><div class="card-title">Reports</div>
          ${(p.reports || []).length ? p.reports.map((x) => `<div class="li${x.visible ? ' click' : ''}" ${x.visible ? `data-report="${x.id}"` : ''}><span class="tag t-${esc(x.type)}">${esc(typeLabel(x.type))}</span><div class="li-main"><b>#${x.id} ${esc(x.title)}</b><span class="hint">${esc(x.role)} · ${esc(x.deptShort || '')} · ${date(x.createdAt)}${x.visible ? '' : ' · another department'}</span></div>${x.court ? `<span class="pill ${x.court === 'expunged' ? 'off' : 'warn'}" title="Court order (DOJ)">${x.court === 'expunged' ? 'Expunged' : 'Sealed'}</span>` : ''}</div>`).join('') : empty('No reports')}
        </div>
        ${p.court ? courtCard(p.court) : ''}
        <div class="card"><div class="card-title">Charge history</div>
          ${(p.charges || []).length ? p.charges.map((x) => `<div class="li"><span class="cat c-${esc(x.category)}">${esc(x.code)}</span><div class="li-main"><b>${esc(x.title)}</b></div><span class="count">×${x.n}</span></div>`).join('') : empty('A clean record')}
        </div>
      </div>`;
    if (quiet) box.scrollTop = keep;
    const who = { charId: p.charId, name: p.name };
    if ($('#pf-save')) $('#pf-save').onclick = (e) => busy(e.currentTarget, async () => {
      const flags = $$('.chips input:checked', box).map((i) => i.value);
      said(await call('profileSave', { charId: p.charId, notes: $('#pf-notes').value, flags }), 'Saved');
    });
    if ($('#pa-report')) $('#pa-report').onclick = () => go('reports', { edit: 0, people: [{ charId: p.charId, name: p.name, role: 'suspect' }] });
    if ($('#pa-warrant')) $('#pa-warrant').onclick = () => warrantForm(who, () => personDetail(p.charId));
    if ($('#pa-fine')) $('#pa-fine').onclick = () => fineForm(who, () => personDetail(p.charId));
    if ($('#pa-bolo')) $('#pa-bolo').onclick = () => boloForm({ kind: 'person', person: who }, () => personDetail(p.charId));
    if (HOOK.person) HOOK.person(box, p, () => personDetail(p.charId, true));
    if ($('#pw-reg')) $('#pw-reg').onclick = () => weaponRegisterForm({ person: who }, () => personDetail(p.charId, true));
    if ($('#pl-issue')) $('#pl-issue').onclick = () => licenseForm(who, 'issue', null, () => personDetail(p.charId, true), Object.fromEntries((p.licenses || []).map((l) => [l.type, l])));
    $$('[data-lact]', box).forEach((b) => b.onclick = () => licenseForm(who, b.dataset.lact, b.dataset.lt, () => personDetail(p.charId, true)));
    $$('[data-fpay]', box).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('fineAct', { id: +b.dataset.fpay, action: 'pay' }), 'Fine paid')) personDetail(p.charId); }));
    $$('[data-fvoid]', box).forEach((b) => b.onclick = async () => { if (await confirmBox('Void fine', 'Void this fine? It will no longer be owed.', 'Void', true)) if (said(await call('fineAct', { id: +b.dataset.fvoid, action: 'void' }), 'Fine voided')) personDetail(p.charId); });
  }

  // ---------------------------------------------------------------- vehicles
  VIEWS.vehicles = async (v, vehicleId) => {
    v.innerHTML = `<div class="split"><div class="split-list">
        <div class="field"><input type="text" id="v-q" placeholder="Plate…" autocomplete="off" maxlength="10" style="text-transform:uppercase"></div>
        <div id="v-res" class="res-list">${empty('Search a plate', '⛍')}</div></div>
      <div class="split-detail" id="v-detail">${vehicleId ? '' : empty('Pick a vehicle', '⛍')}</div></div>`;
    const q = $('#v-q'); let t = null;
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => plateSearch(q.value.trim()), 250); });
    if (typeof vehicleId === 'string') { q.value = vehicleId; plateSearch(vehicleId, true); }
    else if (vehicleId) vehicleDetail(vehicleId); else q.focus();
  };
  async function plateSearch(qv, openOne) {
    const box = $('#v-res'); if (!box) return;
    if (qv.length < 2) { box.innerHTML = empty('Type at least 2 characters', '⛍'); return; }
    const r = await call('vehicles', { q: qv });
    if (!$('#v-res')) return;
    const list = (r.ok && r.data) || [];
    box.innerHTML = list.length ? list.map((x) => `<div class="res click" ${x.vehicleId ? `data-vpick="${x.vehicleId}"` : ''}><div><span class="plate">${esc(x.plate)}</span> <b>${esc(x.label)}</b><div class="hint">${esc(x.owner || (x.boloOnly ? 'Not in the registry' : 'No owner'))}${x.state ? ' · ' + esc(x.state) : ''}</div></div>
      <div class="res-tags">${x.bolos ? pill('BOLO', 'bad') : ''}${(x.flags || []).slice(0, 2).map((f) => pill(f, 'warn')).join('')}</div></div>`).join('') : empty('No plate matches');
    $$('[data-vpick]', box).forEach((el) => el.onclick = () => vehicleDetail(+el.dataset.vpick));
    if (openOne && list.length === 1 && list[0].vehicleId) vehicleDetail(list[0].vehicleId);
  }
  async function vehicleDetail(vehicleId) {
    const box = $('#v-detail'); if (!box) return;
    $$('#v-res [data-vpick]').forEach((el) => el.classList.toggle('sel', +el.dataset.vpick === vehicleId));
    box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('vehicle', { vehicleId });
    if (!$('#v-detail')) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const x = r.data, flagsAll = S.ctx.config.vehicleFlags || [];
    box.innerHTML = `<div class="prof-head${(x.bolos || []).length ? ' wanted' : ''}">
        <div class="plate big">${esc(x.plate)}</div>
        <div class="prof-main"><div class="v-title">${esc(x.label)}</div>
          <div class="facts"><span><i>Owner</i>${x.owner ? `<a class="lnk" data-person="${x.ownerCharId}">${esc(x.owner)}</a>` : '—'}</span><span><i>State</i>${esc(x.state)}</span><span><i>Garage</i>${esc(x.garage || '—')}</span><span><i>Registered</i>${date(x.createdAt)}</span></div>
          <div class="res-tags">${(x.bolos || []).length ? pill('Active BOLO', 'bad') : ''}${(x.flags || []).map((f) => pill(f, 'warn')).join('')}</div></div>
        <div class="prof-actions">${can('bolo_manage') ? '<button class="btn small" id="va-bolo" data-probe-press>+ BOLO</button>' : ''}</div></div>
      <div class="cols2">
        <div class="card"><div class="card-title">Flags &amp; notes</div>
          <div class="chips">${flagsAll.map((f) => `<label class="chip-t"><input type="checkbox" value="${esc(f)}"${(x.flags || []).includes(f) ? ' checked' : ''}${can('mdt_reports_write') ? '' : ' disabled'}><span>${esc(f)}</span></label>`).join('')}</div>
          <textarea id="vf-notes" placeholder="Notes about this vehicle…"${can('mdt_reports_write') ? '' : ' disabled'}>${esc(x.notes || '')}</textarea>
          ${can('mdt_reports_write') ? '<div class="row end"><button class="btn small accent" id="vf-save" data-primary>Save</button></div>' : ''}</div>
        <div class="card"><div class="card-title">BOLOs</div>${(x.bolos || []).length ? x.bolos.map((b) => `<div class="li"><span class="pill bad">BOLO</span><div class="li-main"><b>${esc(b.title)}</b><span class="hint">${esc(b.description || '')} · ${ago(b.createdAt)}</span></div></div>`).join('') : empty('No BOLOs')}</div>
      </div>`;
    if ($('#vf-save')) $('#vf-save').onclick = (e) => busy(e.currentTarget, async () => {
      said(await call('vehicleSave', { vehicleId: x.vehicleId, notes: $('#vf-notes').value, flags: $$('.chips input:checked', box).map((i) => i.value) }), 'Saved');
    });
    if ($('#va-bolo')) $('#va-bolo').onclick = () => boloForm({ kind: 'vehicle', plate: x.plate }, () => vehicleDetail(x.vehicleId));
  }

  // ---------------------------------------------------------------- weapons
  const W_STATUS = { registered: ['Registered', 'on'], stolen: ['Stolen', 'bad'], seized: ['Seized', 'warn'], destroyed: ['Destroyed', 'off'] };
  const W_SRC = { shop: 'bought in a shop', given: 'given', officer: 'by an officer', admin: 'by an admin', found: 'found' };
  const W_ROLES = [['seized', 'Seized'], ['used', 'Used in crime'], ['found', 'Found'], ['evidence', 'Evidence']];
  const L_STATUS = { active: ['Active', 'on'], suspended: ['Suspended', 'warn'], revoked: ['Revoked', 'bad'] };
  const wPill = (st) => { const s = W_STATUS[st] || [st, '']; return pill(s[0], s[1]); };
  const lPill = (st) => { const s = L_STATUS[st] || [st, '']; return pill(s[0], s[1]); };
  const serialTag = (s, big) => `<span class="serial${big ? ' big' : ''}">${esc(s)}</span>`;
  const cleanSerial = (s) => String(s || '').toUpperCase().replace(/[^A-Z0-9-]/g, '').slice(0, 32);
  const wTypeLabel = (item) => { const t = (S.ctx.config.weaponTypes || []).find((x) => x.item === item); return t ? t.label : item; };

  VIEWS.weapons = async (v, serial) => {
    const st = S.wSt || '';
    S.wSerial = null;
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Weapons</div><div class="hint">Registry shared by every department · search a serial, an owner or a weapon type</div></div>
        ${can('weapons_register') ? '<button class="btn accent" id="w-reg" data-probe-press>+ Register weapon</button>' : ''}</div>
      <div class="filters"><input type="text" id="w-q" placeholder="Serial, owner or weapon type…" autocomplete="off" maxlength="40">
        <div class="seg big" id="w-st">${[['', 'All'], ['stolen', 'Stolen'], ['seized', 'Seized'], ['registered', 'Registered'], ['destroyed', 'Destroyed']].map(([k, l]) => `<button data-wst="${k}" class="${st === k ? 'on' : ''}">${l} <span class="seg-n" data-wn="${k}"></span></button>`).join('')}</div></div>
      <div class="split wide"><div class="split-list">
        <div id="w-res" class="res-list"><div class="loading-row"><div class="spin"></div></div></div></div>
      <div class="split-detail" id="w-detail"></div></div>`;
    const q = $('#w-q'); let t = null;
    q.value = S.wQ || '';
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { S.wQ = q.value.trim(); weaponSearch(); }, 250); });
    q.addEventListener('keydown', (e) => { if (e.key === 'Enter') { const s = cleanSerial(q.value); if (s.length >= 4) weaponDetail(s); } });
    $$('[data-wst]').forEach((b) => b.onclick = () => { S.wSt = b.dataset.wst; $$('[data-wst]').forEach((x) => x.classList.toggle('on', x === b)); weaponSearch(); });
    if ($('#w-reg')) $('#w-reg').onclick = () => weaponRegisterForm({ serial: cleanSerial(q.value) }, (s) => { weaponSearch(); weaponDetail(s); });
    weaponSearch();
    if (serial) weaponDetail(String(serial)); else { weaponOverview(); q.focus(); }
  };
  async function weaponOverview(quiet) {
    const box = $('#w-detail'); if (!box) return;
    S.wSerial = null;
    $$('#w-res [data-wpick]').forEach((el) => el.classList.remove('sel'));
    if (!quiet) box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('weaponOverview');
    if (!$('#w-detail') || S.wSerial) return;
    const o = (r.ok && r.data) || { counts: {}, recent: [] }, c = o.counts || {};
    const total = (c.registered || 0) + (c.stolen || 0) + (c.seized || 0) + (c.destroyed || 0);
    $$('[data-wn]').forEach((el) => { const n = el.dataset.wn ? (c[el.dataset.wn] || 0) : total; el.textContent = n ? n : ''; el.classList.toggle('hot', el.dataset.wn === 'stolen' && n > 0); });
    const LOGP = { registered: 'on', status: 'warn', bolo: 'bad', report: 'accent', owner: '', note: '' };
    box.innerHTML = `<div class="kpis">
        <div class="kpi click" data-wkpi="registered"><b>${c.registered || 0}</b><span>Registered</span></div>
        <div class="kpi click" data-wkpi="stolen"><b class="${c.stolen ? 'txt-bad' : ''}">${c.stolen || 0}</b><span>Stolen</span></div>
        <div class="kpi click" data-wkpi="seized"><b class="${c.seized ? 'txt-warn' : ''}">${c.seized || 0}</b><span>Seized</span></div>
        <div class="kpi"><b>${o.licenses || 0}</b><span>Licenses active</span></div></div>
      <div class="card"><div class="card-head"><div class="card-title">Recent activity</div><span class="hint">every department · newest first</span></div>
        ${(o.recent || []).length ? o.recent.map((l) => `<div class="li click${l.status === 'stolen' ? ' stolen' : ''}" data-wpn="${esc(l.serial)}"><span class="pill ${LOGP[l.what] || ''}">${esc(l.what)}</span>${serialTag(l.serial)}<div class="li-main"><b>${esc(l.label || l.item)} · ${esc(l.detail || '')}</b><span class="hint">${esc(l.byName || '')} · ${ago(l.at)}</span></div></div>`).join('')
          : empty('Nothing yet. Guns bought in a shop or given by an admin show up here by themselves.', '◎')}</div>`;
    $$('[data-wkpi]', box).forEach((k) => k.onclick = () => { const b = $(`[data-wst="${k.dataset.wkpi}"]`); if (b) b.click(); });
  }
  async function weaponSearch() {
    const box = $('#w-res'); if (!box) return;
    const qv = S.wQ || '';
    const r = await call('weapons', { q: qv.length >= 2 ? qv : '', status: S.wSt || undefined });
    if (!$('#w-res') || (S.wQ || '') !== qv) return;
    const list = (r.ok && r.data) || [];
    const sq = cleanSerial(qv), exact = list.some((x) => x.serial === sq);
    const look = !exact && sq.length >= 4 && !/\s/.test(qv) ? `<div class="res click look" data-wpick="${esc(sq)}"><div>${serialTag(sq)} <b>Check this serial</b><div class="hint">Not on the registry · see reports and BOLOs that name it</div></div><span class="hint">→</span></div>` : '';
    box.innerHTML = look + (list.length ? list.map((x) => `<div class="res click${x.status === 'stolen' ? ' stolen' : ''}" data-wpick="${esc(x.serial)}"><div>${serialTag(x.serial)} <b>${esc(x.label || x.item)}</b>
        <div class="hint">${x.owner ? esc(x.owner) : 'No owner on file'} · ${date(x.registeredAt)}</div></div>
        <div class="res-tags">${wPill(x.status)}${x.bolos ? pill('BOLO', 'bad') : ''}${x.noPermit ? `<span class="pill warn" title="The owner holds no active firearm permit">No permit</span>` : ''}</div></div>`).join('') : (look ? '' : empty(qv.length >= 2 ? 'Nothing matches' : 'No weapons on the registry yet', '⌖')));
    $$('[data-wpick]', box).forEach((el) => el.onclick = () => weaponDetail(el.dataset.wpick));
    if (S.wSerial) $$('[data-wpick]', box).forEach((el) => el.classList.toggle('sel', el.dataset.wpick === S.wSerial));
  }
  async function weaponDetail(serial, quiet) {
    const box = $('#w-detail'); if (!box) return;
    S.wSerial = serial;
    $$('#w-res [data-wpick]').forEach((el) => el.classList.toggle('sel', el.dataset.wpick === serial));
    if (!quiet) box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('weapon', { serial });
    if (!$('#w-detail') || S.wSerial !== serial) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const w = r.data, mng = can('weapons_manage'), dead = w.status === 'destroyed';
    const acts = !w.registered ? (can('weapons_register') ? '<button class="btn accent small" id="wa-reg" data-probe-press>+ Register it</button>' : '')
      : [mng && !dead && w.status !== 'stolen' ? '<button class="btn small danger" data-wact="stolen" data-probe-press>Mark stolen</button>' : '',
        mng && !dead && w.status !== 'seized' ? '<button class="btn small" data-wact="seized">Mark seized</button>' : '',
        mng && !dead && w.status !== 'registered' ? '<button class="btn small" data-wact="returned">Returned to owner</button>' : '',
        mng && !dead ? '<button class="btn small ghost" data-wact="transfer">Change owner</button>' : '',
        mng && !dead ? '<button class="btn small ghost" data-wact="destroyed">Destroyed</button>' : '',
        can('weapons_register') ? '<button class="btn small ghost" data-wact="note">+ Note</button>' : ''].join('');
    const LOGP = { registered: 'on', status: 'warn', bolo: 'bad', report: 'accent', owner: '', note: '' };
    box.innerHTML = `<div class="row"><button class="btn small ghost" id="w-ov">← Overview</button></div>${w.status === 'stolen' ? `<div class="w-banner"><span class="w-ico">⚠</span><div><b>Reported stolen</b><div>${(w.bolos || []).length ? 'Active BOLO: ' + esc(w.bolos[0].title) : 'Whoever carries it is not the owner.'}</div></div></div>` : ''}
      <div class="prof-head${w.status === 'stolen' ? ' wanted' : ''}">
        ${serialTag(w.serial, true)}
        <div class="prof-main"><div class="v-title">${w.registered ? esc(w.label || w.item) : 'Not on the registry'}</div>
          ${w.registered ? `<div class="facts"><span><i>Owner</i>${w.ownerCharId ? `<a class="lnk" data-person="${w.ownerCharId}">${esc(w.owner || '#' + w.ownerCharId)}</a>` : '—'}</span><span><i>Type</i>${esc(w.item)}</span><span><i>Registered</i>${date(w.registeredAt)} · ${esc(W_SRC[w.origin] || w.origin)}${w.registeredByName ? ' (' + esc(w.registeredByName) + ')' : ''}</span></div>`
            : '<div class="hint">No owner on file for this serial. If you have the gun, register it to its rightful owner, or attach it to a report as evidence.</div>'}
          <div class="res-tags">${w.registered ? wPill(w.status) : pill('Unregistered', 'warn')}${(w.bolos || []).length ? pill('Active BOLO', 'bad') : ''}${(w.licenses || []).map((l) => pill(l.type + ' license ' + (L_STATUS[l.status] || [l.status])[0].toLowerCase(), (L_STATUS[l.status] || ['', ''])[1])).join('')}${w.registered && w.ownerCharId && w.noPermit ? pill(`Owner has no ${(w.permitLabel || 'firearm permit').toLowerCase()}`, 'warn') : ''}</div>
        </div>
        <div class="prof-actions wrap">${acts}</div></div>
      ${w.notes ? `<div class="card"><div class="card-title">Registration notes</div><div class="narr">${esc(w.notes)}</div></div>` : ''}
      <div class="cols2">
        <div class="card"><div class="card-title">History <span class="hint">· newest first</span></div>
          ${(w.log || []).length ? w.log.map((l) => `<div class="li hist"><span class="pill ${LOGP[l.what] || ''}">${esc(l.what)}</span><div class="li-main"><b>${esc(l.detail || '')}</b><span class="hint">${esc(l.byName || '')} · ${dateTime(l.at)}${l.reportId ? ` · <a class="lnk" data-report="${l.reportId}">Report #${l.reportId}</a>` : ''}</span></div></div>`).join('') : empty(w.registered ? 'No history' : 'Not on the registry')}
        </div>
        <div>
          <div class="card"><div class="card-title">Reports</div>
            ${(w.reports || []).length ? w.reports.map((x) => `<div class="li${x.visible ? ' click' : ''}" ${x.visible ? `data-report="${x.id}"` : ''}><span class="pill ${x.role === 'seized' || x.role === 'used' ? 'bad' : ''}">${esc((W_ROLES.find((y) => y[0] === x.role) || [0, x.role])[1])}</span><div class="li-main"><b>#${x.id} ${esc(x.title)}</b><span class="hint">${esc(typeLabel(x.type))} · ${esc(x.deptShort || '')} · ${date(x.createdAt)}${x.visible ? '' : ' · another department'}</span></div></div>`).join('') : empty('Not on any report')}
          </div>
          <div class="card"><div class="card-title">BOLOs</div>
            ${(w.bolos || []).length ? w.bolos.map((b) => `<div class="li"><span class="pill bad">BOLO</span><div class="li-main"><b>${esc(b.title)}</b><span class="hint">${esc(b.description || '')} · ${ago(b.createdAt)}</span></div></div>`).join('') : empty('No active BOLOs')}
            ${can('bolo_manage') && !dead ? '<div class="row end"><button class="btn small ghost" id="wa-bolo">+ BOLO</button></div>' : ''}
          </div>
        </div>
      </div>`;
    const again = () => { weaponSearch(); weaponDetail(w.serial, true); };
    $('#w-ov').onclick = () => weaponOverview();
    if ($('#wa-reg')) $('#wa-reg').onclick = () => weaponRegisterForm({ serial: w.serial }, again);
    if ($('#wa-bolo')) $('#wa-bolo').onclick = () => boloForm({ kind: 'weapon', serial: w.serial, title: w.registered ? (w.label || w.item) + ' · ' + w.serial : '' }, again);
    $$('[data-wact]', box).forEach((b) => b.onclick = () => weaponActForm(w, b.dataset.wact, again));
  }
  function weaponActForm(w, action, after) {
    const A = {
      stolen: ['Mark stolen', `Mark ${w.serial} as stolen.${S.ctx.config.boloOnStolen ? ' A weapon BOLO is posted for every department.' : ''}`, 'Mark stolen', true, 'Where and when, who reported it…'],
      seized: ['Mark seized', `Mark ${w.serial} as seized by the police. Any BOLO on it is closed.`, 'Mark seized', false, 'Why, and where it is held (evidence locker #…)'],
      returned: ['Returned to owner', `${w.serial} goes back to Registered${w.owner ? ', with ' + w.owner : ''}. Any BOLO on it is closed.`, 'Mark returned', false, 'Optional note'],
      destroyed: ['Destroyed', `Mark ${w.serial} as destroyed. This is final.`, 'Mark destroyed', true, 'How and by whom'],
      transfer: ['Change owner', `Move ${w.serial} to a new registered owner (a legal sale or gift).`, 'Change owner', false, 'Optional note (sale price, receipt…)'],
      note: ['Add a note', `A note on ${w.serial}'s history, seen by every officer.`, 'Add note', false, 'What officers should know…'],
    }[action];
    let who = null;
    modal(`<div class="m-title">${esc(A[0])}</div><div class="hint mb">${esc(A[1])}</div>
      ${action === 'transfer' ? '<div class="field"><label>New owner</label><div id="wf-pp"></div><div id="wf-who" class="picked hidden"></div></div>' : ''}
      <div class="field"><label>Note${action === 'note' ? '' : ' <span class="hint">(optional)</span>'}</label><textarea id="wf-note" maxlength="500" placeholder="${esc(A[4])}"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn ${A[3] ? 'danger' : 'accent'}" id="wf-go" data-primary>${esc(A[2])}</button></div>`, (card, closeIt) => {
      if ($('#wf-pp', card)) personPicker($('#wf-pp', card), 'Search a name…', (p) => { who = p; $('#wf-who').textContent = p.name; $('#wf-who').classList.remove('hidden'); });
      $('#wf-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        if (action === 'transfer' && !who) { toast('Pick the new owner', 'err'); return; }
        const r = await call('weaponAct', { serial: w.serial, action, note: $('#wf-note').value, ownerCharId: who && who.charId });
        if (said(r, { stolen: 'Marked stolen', seized: 'Marked seized', returned: 'Returned to owner', destroyed: 'Marked destroyed', transfer: 'Owner changed', note: 'Note added' }[action])) { closeIt(); if (after) after(); }
      });
    });
  }
  function weaponRegisterForm(o, after) {
    let who = o.person || null;
    const types = S.ctx.config.weaponTypes || [];
    modal(`<div class="m-title">Register a weapon</div><div class="hint mb">The serial is on the gun's card in the inventory (hover the gun). A serial can only be registered once.</div>
      <div class="field"><label>Serial number</label><input id="wr-serial" maxlength="32" value="${esc(o.serial || '')}" placeholder="e.g. 7KQ2M9XB4C1D" style="text-transform:uppercase;font-family:'Courier New',monospace;letter-spacing:.08em"></div>
      <div class="field"><label>Weapon</label><select id="wr-item"><option value="">Pick the weapon…</option>${types.map((t) => `<option value="${esc(t.item)}">${esc(t.label)}</option>`).join('')}</select></div>
      <div class="field"><label>Owner</label>${who ? `<div class="picked"><b>${esc(who.name)}</b></div>` : '<div id="wr-pp"></div><div id="wr-who" class="picked hidden"></div><div class="hint">Leave empty if the owner is unknown.</div>'}</div>
      <div class="field"><label>Notes <span class="hint">(optional)</span></label><textarea id="wr-notes" maxlength="1000" placeholder="Where it came from, receipt, condition…"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="wr-go" data-primary>Register</button></div>`, (card, closeIt) => {
      if ($('#wr-pp', card)) personPicker($('#wr-pp', card), 'Search a name…', (p) => { who = p; $('#wr-who').textContent = p.name; $('#wr-who').classList.remove('hidden'); });
      $('#wr-serial', card).addEventListener('input', (e) => { const c = cleanSerial(e.target.value); if (c !== e.target.value) e.target.value = c; });
      if (!o.serial) $('#wr-serial', card).focus(); else $('#wr-item', card).focus();
      $('#wr-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const serial = cleanSerial($('#wr-serial').value);
        if (serial.length < 4) { toast('Type the serial', 'err'); return; }
        if (!$('#wr-item').value) { toast('Pick the weapon', 'err'); return; }
        const r = await call('weaponRegister', { serial, item: $('#wr-item').value, ownerCharId: who && who.charId, notes: $('#wr-notes').value });
        if (said(r, 'Weapon registered')) { closeIt(); if (after) after(r.data); }
      });
    });
  }
  function licenseForm(p, action, type, after, held) {
    const types = (S.ctx.config.licenseTypes || ['Firearm']).filter((t) => action !== 'issue' || type || !held || !held[t] || held[t].status === 'revoked');
    const T = { issue: ['Issue a weapon license', 'Issue', false], suspend: ['Suspend license', 'Suspend', true], revoke: ['Revoke license', 'Revoke', true], reinstate: ['Reinstate license', 'Reinstate', false] }[action];
    modal(`<div class="m-title">${T[0]}</div><div class="hint mb">${esc(p.name)} · they are told in game.</div>
      ${action === 'issue' && !type ? `<div class="field"><label>Type</label><div class="seg" id="lf-type">${types.map((t, i) => `<button data-lt="${esc(t)}" class="${(type ? t === type : i === 0) ? 'on' : ''}">${esc(t)}</button>`).join('')}</div></div>` : `<div class="field"><label>License</label><div class="picked"><b>${esc(type)}</b></div></div>`}
      <div class="field"><label>${action === 'suspend' || action === 'revoke' ? 'Reason' : 'Note <span class="hint">(optional)</span>'}</label><textarea id="lf-note" maxlength="300" placeholder="${action === 'issue' ? 'Test passed, background check clear…' : action === 'reinstate' ? 'Why it is back' : 'Why (shown on their record)'}"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn ${T[2] ? 'danger' : 'accent'}" id="lf-go" data-primary>${T[1]}</button></div>`, (card, closeIt) => {
      let ty = type || types[0];
      $$('#lf-type [data-lt]', card).forEach((b) => b.onclick = () => { ty = b.dataset.lt; $$('#lf-type [data-lt]', card).forEach((x) => x.classList.toggle('on', x === b)); });
      $('#lf-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('licenseAct', { charId: p.charId, type: ty, action, note: $('#lf-note').value });
        if (said(r, { issue: 'License issued', suspend: 'License suspended', revoke: 'License revoked', reinstate: 'License reinstated' }[action])) { closeIt(); if (after) after(); }
      });
    });
  }
  // 1.8.0: firearm permit pill ('active' | 'suspended' | 'revoked' | 'none'); short = search rows (hide 'none')
  function permitPill(st, short) {
    if (!st || (short && st === 'none')) return '';
    const m = { active: ['✪ Permit', 'on'], suspended: ['Permit suspended', 'warn'], revoked: ['Permit revoked', 'bad'], none: ['No firearm permit', ''] }[st] || [st, ''];
    return `<span class="pill ${m[1]}" title="Firearm permit: ${esc(st)}">${esc(m[0])}</span>`;
  }
  const ORIGIN = { department: 'Department · auto', application: 'Approved application', manual: 'Issued by an officer', court: 'Court order' };
  const APP_ST = { pending: ['Waiting for review', 'warn'], processing: ['Being decided', 'warn'], approved: ['Approved', 'on'], denied: ['Denied', 'bad'], cancelled: ['Cancelled', 'off'] };
  function personWeaponsCard(p) {
    const ws = p.weapons || [], ls = p.licenses || [], lm = can('licenses_manage');
    const has = {}; ls.forEach((l) => { has[l.type] = l; });
    const canIssue = lm && (S.ctx.config.licenseTypes || []).some((t) => !has[t] || has[t].status === 'revoked');
    return `<div class="card span2c"><div class="card-head"><div class="card-title">Weapons &amp; licenses</div><div class="row">
        ${can('weapons_register') ? '<button class="btn small ghost" id="pw-reg">+ Register weapon</button>' : ''}${canIssue ? '<button class="btn small ghost" id="pl-issue">+ Issue license</button>' : ''}</div></div>
      <div class="wl-grid"><div><div class="sub-h">Licenses</div>
        ${p.permit && p.permit.status !== 'active' && ws.some((w) => w.status !== 'destroyed') ? `<div class="tr-info warn mb">⚠ ${ws.filter((w) => w.status !== 'destroyed').length} weapon(s) registered but no active ${esc(p.permit.label || 'firearm permit')}.</div>` : ''}
        ${ls.length ? ls.map((l) => `<div class="lic ${l.status}"><div class="lic-top"><b>${esc(p.permit && l.type === p.permit.type ? (p.permit.label || l.type) : l.type)}</b>${lPill(l.status)}${l.origin ? `<span class="pill" title="Where it came from">${esc(ORIGIN[l.origin] || l.origin)}</span>` : ''}<span class="spacer"></span>
            ${lm && l.status === 'active' ? `<button class="btn small ghost" data-lact="suspend" data-lt="${esc(l.type)}">Suspend</button><button class="btn small ghost" data-lact="revoke" data-lt="${esc(l.type)}">Revoke</button>` : ''}
            ${lm && l.status === 'suspended' ? `<button class="btn small" data-lact="reinstate" data-lt="${esc(l.type)}">Reinstate</button><button class="btn small ghost" data-lact="revoke" data-lt="${esc(l.type)}">Revoke</button>` : ''}
            ${lm && l.status === 'revoked' ? `<button class="btn small ghost" data-lact="issue" data-lt="${esc(l.type)}">Issue again</button>` : ''}</div>
          <div class="hint">Issued ${date(l.issuedAt)}${l.issuedByName ? ' by ' + esc(l.issuedByName) : ''}${l.status !== 'active' && l.note ? ' · ' + esc(l.note) : ''}</div>
          ${(l.log || []).length > 1 ? `<details class="lic-log"><summary>History (${l.log.length})</summary>${l.log.map((x) => `<div class="hint">${dateTime(x.at)} · <b>${esc(x.action)}</b> by ${esc(x.byName)}${x.note ? ' · ' + esc(x.note) : ''}</div>`).join('')}</details>` : ''}</div>`).join('') : '<div class="hint pad-s">No weapon license on file.</div>'}
        ${(p.permitApps || []).length ? `<div class="sub-h" style="margin-top:10px">Permit applications</div>${p.permitApps.map((a) => `<div class="li${S.ctx.staff || P().permits_manage ? ' click' : ''}" ${S.ctx.staff || P().permits_manage ? 'data-go="permits"' : ''}><span class="pill ${(APP_ST[a.status] || ['', ''])[1]}">${esc((APP_ST[a.status] || [a.status])[0])}</span><div class="li-main"><b>#${a.id} · ${date(a.createdAt)}</b><span class="hint">${esc(a.reason || '')}${a.decisionNote ? ' · ' + esc(a.decisionNote) : ''}${a.decidedByLabel ? ' · ' + esc(a.decidedByLabel) : ''}</span></div></div>`).join('')}` : ''}
      </div><div><div class="sub-h">Registered weapons</div>
        ${ws.length ? ws.map((w) => `<div class="li click${w.status === 'stolen' ? ' stolen' : ''}" data-wpn="${esc(w.serial)}">${serialTag(w.serial)}<div class="li-main"><b>${esc(w.label || w.item)}</b><span class="hint">since ${date(w.registeredAt)}</span></div>${wPill(w.status)}</div>`).join('') : '<div class="hint pad-s">No weapons registered to them.</div>'}
      </div></div></div>`;
  }

  // ---------------------------------------------------------------- penal code
  async function penal(force) {
    if (S.penal && !force) return S.penal;
    const r = await call('penal');
    S.penal = (r.ok && r.data) || [];
    return S.penal;
  }
  const CATS = [['infraction', 'Infractions'], ['misdemeanor', 'Misdemeanors'], ['felony', 'Felonies']];

  VIEWS.penal = async (v) => {
    const list = await penal(true);
    if (S.view !== 'penal') return;
    const admin = S.ctx.staff;
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Penal code</div><div class="hint">${list.length} charges · click a charge for details${admin ? ' · you can edit (admin)' : ''}</div></div>
      <div class="row"><input type="text" id="pc-q" placeholder="Filter by code or words…" style="width:240px">${admin ? '<button class="btn accent" id="pc-new" data-probe-press>+ New charge</button>' : ''}</div></div>
      <div class="jump">${CATS.map(([k, l]) => `<button class="jump-chip c-${k}" data-jump="${k}">${l} <span>${list.filter((p) => p.category === k && (p.active || admin)).length}</span></button>`).join('')}</div>
      <div id="pc-list"></div>`;
    $$('[data-jump]', v).forEach((b) => b.onclick = () => { const el = $('#pc-sec-' + b.dataset.jump); if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' }); });
    const draw = () => {
      const q = ($('#pc-q').value || '').toLowerCase();
      $('#pc-list').innerHTML = CATS.map(([k, label]) => {
        const rows = list.filter((p) => p.category === k && (!q || (p.code + ' ' + p.title).toLowerCase().includes(q)));
        if (!rows.length) return '';
        return `<div class="card flush pc-sec" id="pc-sec-${k}"><div class="pc-head"><span class="cat c-${k}">${label}</span><span class="hint">${rows.length}</span></div><table class="pc-table"><colgroup><col style="width:90px"><col><col style="width:110px"><col style="width:90px"><col style="width:120px">${admin ? '<col style="width:70px">' : ''}</colgroup>
          <thead><tr><th>Code</th><th>Charge</th><th class="num">Fine</th><th class="num">Jail</th><th>Arrestable</th>${admin ? '<th></th>' : ''}</tr></thead><tbody>
          ${rows.map((p) => `<tr class="click ${p.active ? '' : 'muted'}" data-pinfo="${p.id}"><td><b>${esc(p.code)}</b></td><td>${esc(p.title)}${p.active ? '' : ' ' + pill('retired', 'off')}</td><td class="num">${money(p.fine)}</td><td class="num">${p.months ? p.months + ' mo' : '<span class="hint">—</span>'}</td><td>${p.months ? '<span class="pill bad">Yes</span>' : '<span class="pill off">Citation</span>'}</td>${admin ? `<td class="right"><button class="btn small ghost" data-pedit="${p.id}">Edit</button></td>` : ''}</tr>`).join('')}</tbody></table></div>`;
      }).join('') || empty('No charge matches');
      $$('[data-pedit]').forEach((b) => b.onclick = (e) => { e.stopPropagation(); penalForm(list.find((p) => p.id === +b.dataset.pedit)); });
      $$('[data-pinfo]').forEach((tr) => tr.onclick = () => {
        const p = list.find((x) => x.id === +tr.dataset.pinfo); if (!p) return;
        modal(`<div class="row"><span class="cat c-${esc(p.category)}">${esc(p.code)}</span><span class="hint">${esc((CATS.find((c) => c[0] === p.category) || ['', ''])[1].slice(0, -1))}</span></div>
          <div class="m-title">${esc(p.title)}</div>
          <div class="kpis"><div class="kpi"><b>${money(p.fine)}</b><span>fine</span></div><div class="kpi"><b>${p.months ? p.months + ' mo' : '—'}</b><span>jail time</span></div>
            <div class="kpi"><b class="${p.months ? 'txt-bad' : ''}">${p.months ? 'Yes' : 'No'}</b><span>${p.months ? 'arrestable (jail time)' : 'citation only'}</span></div></div>
          <div class="m-text">${p.description ? esc(p.description) : 'No description written for this charge yet.'}</div>
          ${p.fine || p.months ? `<p class="hint">On a report an officer may set the fine from $0 to ${money(Math.floor(p.fine * ((S.ctx.config.chargeOverride || {}).maxFineMult || 1)))} and jail from 0 to ${Math.floor(p.months * ((S.ctx.config.chargeOverride || {}).maxMonthsMult || 1))} months.</p>` : ''}
          <div class="row end"><button class="btn ghost" data-x>Close</button></div>`);
      });
    };
    $('#pc-q').addEventListener('input', draw); draw();
    if ($('#pc-new')) $('#pc-new').onclick = () => penalForm(null);
  };
  function penalForm(p) {
    p = p || { code: '', title: '', category: 'misdemeanor', fine: 0, months: 0, description: '', active: 1 };
    modal(`<div class="m-title">${p.id ? 'Edit charge' : 'New charge'}</div>
      <div class="grid"><div class="field"><label>Code</label><input id="pf-code" maxlength="16" value="${esc(p.code)}" placeholder="M-216"></div>
        <div class="field"><label>Category</label><select id="pf-cat">${CATS.map(([k, l]) => `<option value="${k}"${p.category === k ? ' selected' : ''}>${l.slice(0, -1)}</option>`).join('')}</select></div>
        <div class="field span2"><label>Charge</label><input id="pf-title" maxlength="120" value="${esc(p.title)}"></div>
        <div class="field"><label>Fine ($)</label><input id="pf-fine" type="number" min="0" value="${p.fine}"></div>
        <div class="field"><label>Months</label><input id="pf-months" type="number" min="0" value="${p.months}"></div>
        <div class="field span2"><label>Description <span class="hint">(optional)</span></label><input id="pf-desc" maxlength="500" value="${esc(p.description || '')}"></div>
        ${p.id ? `<label class="chip-t span2"><input type="checkbox" id="pf-active"${p.active ? ' checked' : ''}><span>In use (untick to retire it; old reports keep it)</span></label>` : ''}</div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="pf-go" data-primary>Save</button></div>`, (card, closeIt) => {
      $('#pf-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('penalSave', { id: p.id, code: $('#pf-code').value, title: $('#pf-title').value, category: $('#pf-cat').value,
          fine: +$('#pf-fine').value, months: +$('#pf-months').value, description: $('#pf-desc').value, active: $('#pf-active') ? $('#pf-active').checked : true });
        if (said(r, 'Charge saved')) { closeIt(); S.penal = null; go('penal'); }
      });
    });
  }

  // ---------------------------------------------------------------- reports
  VIEWS.reports = async (v, arg) => {
    if (arg && arg.edit !== undefined) return reportEditor(v, arg);
    if (arg && arg.view) return reportView(v, arg.view);
    const f = S.repFilter || (S.repFilter = { q: '', type: '', mine: false });
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Reports</div><div class="hint">${esc(S.ctx.dept.short)} reports</div></div>
      ${can('mdt_reports_write') ? '<button class="btn accent" id="r-new" data-probe-press>+ New report</button>' : ''}</div>
      <div class="filters"><input type="text" id="r-q" placeholder="Search title, #number or a person…" value="${esc(f.q)}">
        <div class="seg big">${[['', 'All']].concat((S.ctx.config.reportTypes || []).map((t) => [t.key, t.label])).map(([k, l]) => `<button data-rt="${k}" class="${f.type === k ? 'on' : ''}">${l}</button>`).join('')}</div>
        <label class="chip-t"><input type="checkbox" id="r-mine"${f.mine ? ' checked' : ''}><span>Mine</span></label></div>
      <div id="r-list"><div class="loading-row"><div class="spin"></div></div></div>`;
    const load = async () => {
      const r = await call('reports', f);
      const box = $('#r-list'); if (!box) return;
      const list = (r.ok && r.data) || [];
      const sub = (x) => {
        const bits = [];
        if (x.suspect) bits.push('Suspect: ' + esc(x.suspect) + (x.suspects > 1 ? ` +${x.suspects - 1}` : ''));
        else if (x.preview) bits.push(esc(String(x.preview).replace(/\s+/g, ' ').slice(0, 90)) + (String(x.preview).length > 90 ? '…' : ''));
        if (x.location) bits.push('📍 ' + esc(x.location));
        return bits.join(' · ');
      };
      const chg = (x) => !x.charges ? '<span class="hint">—</span>'
        : `<b>${x.charges}</b> · ${money(x.totalFine)}${x.totalMonths ? ` · ${x.totalMonths} mo` : ''}`;
      box.innerHTML = list.length ? `<div class="card flush"><table class="rows"><thead><tr><th>#</th><th>Type</th><th>Report</th><th class="num">People</th><th>Charges</th><th>Author</th><th>When</th></tr></thead><tbody>
        ${list.map((x) => `<tr class="click" data-report="${x.id}"><td><b>${x.id}</b></td><td><span class="tag t-${esc(x.type)}">${esc(typeLabel(x.type))}</span></td><td><b>${esc(x.title)}</b>${x.edits ? ` <span class="pill warn sm" title="Edited after filing ${x.edits} time${x.edits === 1 ? '' : 's'}">✎ Edited</span>` : ''}${sub(x) ? `<div class="hint ell">${sub(x)}</div>` : ''}</td><td class="num">${x.people}</td><td>${chg(x)}</td><td>${esc(x.authorName || '')}</td><td>${ago(x.createdAt)}</td></tr>`).join('')}</tbody></table></div>
        ${list.length < 40 ? `<div class="end-line">That's all ${list.length === 1 ? 'of it' : list.length + ' reports'}${f.q || f.type || f.mine ? ' for this filter' : ''}</div>` : ''}`
        : empty(r.ok ? 'No reports match' : r.why, '☰');
    };
    let t = null;
    $('#r-q').addEventListener('input', (e) => { f.q = e.target.value; clearTimeout(t); t = setTimeout(load, 250); });
    $$('[data-rt]').forEach((b) => b.onclick = () => { f.type = b.dataset.rt; $$('[data-rt]').forEach((x) => x.classList.toggle('on', x === b)); load(); });
    $('#r-mine').onchange = (e) => { f.mine = e.target.checked; load(); };
    if ($('#r-new')) $('#r-new').onclick = () => go('reports', { edit: 0 });
    load();
  };

  async function reportView(v, rid) {
    const r = await call('report', { id: rid });
    if (S.view !== 'reports') return;
    if (!r.ok) { v.innerHTML = empty(r.why); return; }
    const x = r.data;
    const suspects = x.people.filter((p) => p.role === 'suspect');
    const byPerson = {};
    x.charges.forEach((ch) => { (byPerson[ch.charId] = byPerson[ch.charId] || []).push(ch); });
    const fineOf = (cid) => x.fines.find((f) => f.charId === cid);
    v.innerHTML = `<div class="v-head"><div><button class="btn small ghost" data-go="reports">← Reports</button>
        <div class="v-title">#${x.id} ${esc(x.title)}</div>
        <div class="hint"><span class="tag t-${esc(x.type)}">${esc(typeLabel(x.type))}</span> <span class="pill filed">Filed</span>${x.edits ? ` <span class="pill warn" title="Every edit is in History below">✎ Edited ${x.edits}×${x.lastEdit ? ' · last by ' + esc(x.lastEdit.byName || '') + ' ' + ago(x.lastEdit.at) : ''}</span>` : ''} ${esc(x.deptShort || '')} · by <a class="lnk" data-officer="${x.authorCharId}" title="Officer profile">${esc(x.authorName || '')}</a> · ${dateTime(x.createdAt)}${x.location ? ' · ' + esc(x.location) : ''}</div></div>
      <div class="row">${x.canEdit ? `<button class="btn accent" id="rv-edit" data-probe-press title="Every change is logged in History">Edit${x.authorCharId !== S.ctx.me.charId && (S.ctx.staff || (S.ctx.me.roleLevel || 0) >= (S.ctx.config.highCommandLevel || 80)) ? ' (high command)' : ''}</button>` : ''}${x.canDelete ? '<button class="btn danger" id="rv-del" data-probe-press title="High command only">Delete</button>' : ''}</div></div>
      <div class="cols-main">
        <div class="card"><div class="card-title">Narrative</div><div class="narr">${esc(x.body || '').replace(/\n/g, '<br>') || '<span class="hint">No narrative written.</span>'}</div></div>
        <div>
          <div class="card"><div class="card-title">People</div>${x.people.length ? x.people.map((p) => `<div class="li click" data-person="${p.charId}"><span class="pill ${p.role === 'suspect' ? 'bad' : ''}">${esc(p.role)}</span><div class="li-main"><b>${esc(p.name)}</b></div></div>`).join('') : empty('Nobody added')}</div>
          <div class="card"><div class="card-title">Officers</div>${x.officers.map((o) => `<div class="li click" data-officer="${o.charId}" title="Officer profile"><span class="pill ${o.primary ? 'accent' : ''}">${o.primary ? 'Primary' : 'Assisting'}</span><div class="li-main"><b>${esc(o.name)}</b></div></div>`).join('')}</div>
          ${(x.weapons || []).length ? `<div class="card"><div class="card-title">Weapons</div>${x.weapons.map((w) => `<div class="li click${w.status === 'stolen' ? ' stolen' : ''}" data-wpn="${esc(w.serial)}"><span class="pill ${w.role === 'seized' || w.role === 'used' ? 'bad' : ''}">${esc((W_ROLES.find((y) => y[0] === w.role) || [0, w.role])[1])}</span><div class="li-main"><b>${serialTag(w.serial)} ${w.registered ? esc(w.label || w.item) : '<span class="hint">not on the registry</span>'}</b><span class="hint">${w.registered ? (w.owner ? 'Owner ' + esc(w.owner) : 'No owner on file') : ''}</span></div>${w.registered ? wPill(w.status) : ''}</div>`).join('')}</div>` : ''}
        </div>
      </div>
      ${suspects.length ? `<div class="card"><div class="card-title">Charges</div>${suspects.map((s) => {
        const chs = byPerson[s.charId] || []; const tf = chs.reduce((n, c) => n + c.fine * c.count, 0); const tm = chs.reduce((n, c) => n + c.months * c.count, 0); const f = fineOf(s.charId);
        return `<div class="sus"><div class="sus-head"><b>${esc(s.name)}</b><span class="hint">${chs.length} charge${chs.length === 1 ? '' : 's'}</span><span class="spacer"></span><span class="tot">${money(tf)} · ${tm} months</span>
          ${f ? pill('Fine ' + f.status + ' ' + money(f.amount), f.status === 'paid' ? 'on' : f.status === 'unpaid' ? 'warn' : 'off') : (tf > 0 && can('fines_issue') ? `<button class="btn small accent" data-bill="${s.charId}" data-probe-press>Bill ${money(tf)}</button>` : '')}
          ${(can('warrants_issue') || can('warrants_request')) ? `<button class="btn small ghost" data-rwar="${s.charId}" data-name="${esc(s.name)}">Warrant</button>` : ''}</div>
          ${chs.map((c) => { const changed = c.baseFine != null && (c.baseFine !== c.fine || c.baseMonths !== c.months);
            return `<div class="charge"><span class="cat c-${esc(c.category)}">${esc(c.code)}</span><span>${esc(c.title)}</span><span class="spacer"></span>
            ${changed ? `<span class="pill warn" title="Changed by the officer">edited · penal code ${money(c.baseFine)} · ${c.baseMonths} mo</span>` : ''}<span class="hint">×${c.count} · ${money(c.fine * c.count)} · ${c.months * c.count} mo</span></div>`; }).join('') || '<div class="hint">No charges</div>'}</div>`;
      }).join('')}</div>` : ''}
      ${(x.log || []).length ? `<div class="card"><div class="card-title">History <span class="hint">· every change after filing, newest first</span></div>${x.log.map((l) => `<div class="li hist ${l.what === 'change' ? 'sub' : ''}"><span class="pill ${l.what.startsWith('charge') ? 'warn' : l.what === 'edited' ? 'accent' : l.what === 'filed' ? 'on' : ''}">${esc({ filed: 'filed', edited: 'edited', change: 'changed', charge_edit: 'charge changed', charge_set: 'charge set' }[l.what] || l.what)}</span><div class="li-main"><b>${esc(l.detail)}</b><span class="hint">${esc(l.byName || '')} · ${dateTime(l.at)}</span></div></div>`).join('')}</div>` : ''}`;
    if ($('#rv-edit')) $('#rv-edit').onclick = () => go('reports', { edit: x.id, data: x });
    if ($('#rv-del')) $('#rv-del').onclick = async () => { if (await confirmBox('Delete report', `Delete report #${x.id}? It disappears from the MDT for everyone. A full copy is kept in the audit log.`, 'Delete', true)) if (said(await call('reportDelete', { id: x.id }), 'Report deleted')) go('reports'); };
    $$('[data-bill]', v).forEach((b) => b.onclick = async () => {
      const cid = +b.dataset.bill;
      if (!await confirmBox('Bill the fine', 'Take the fine from their bank account now? If they cannot pay, it stays owing.', 'Bill')) return;
      const res = await call('fineReport', { reportId: x.id, charId: cid });
      if (res.ok) { toast(res.data.paid ? 'Fine paid' : 'Fine issued, still owing: ' + (res.data.why || 'not enough money'), res.data.paid ? 'ok' : 'err'); reportView(v, x.id); } else said(res);
    });
    $$('[data-rwar]', v).forEach((b) => b.onclick = () => warrantForm({ charId: +b.dataset.rwar, name: b.dataset.name }, () => reportView(v, x.id), x.id));
    if (HOOK.reportView) HOOK.reportView(v, x, () => reportView(v, x.id));
  }

  async function reportEditor(v, arg) {
    const list = await penal();
    if (S.view !== 'reports') return;
    const src = arg.data || {};
    const R = {
      id: arg.edit || 0, type: src.type || 'incident', title: src.title || '', location: src.location || '', body: src.body || '',
      people: (src.people || arg.people || []).map((p) => ({ charId: p.charId, name: p.name, role: p.role || 'suspect' })),
      officers: (src.officers || []).filter((o) => !o.primary).map((o) => ({ charId: o.charId, name: o.name })),
      charges: (src.charges || []).map((c) => ({ charId: c.charId, penalId: c.penalId, count: c.count, fine: c.fine, months: c.months })),
      weapons: (src.weapons || arg.weapons || []).map((w) => ({ serial: w.serial, role: w.role || 'evidence', label: w.label || (w.item ? wTypeLabel(w.item) : ''), status: w.status, registered: w.registered !== false && !!(w.label || w.item) })),
    };
    S.dirty = true;
    R.ver = src.ver || 0;
    v.innerHTML = `<div id="re-others" class="edit-others hidden"></div><div class="v-head"><div><button class="btn small ghost" id="re-back">← ${R.id ? 'Back to report' : 'Reports'}</button><div class="v-title">${R.id ? 'Edit report #' + R.id : 'New report'}</div>${R.id ? '<div class="hint">This report is filed: every change you save is logged in its History with the old and new value.</div>' : ''}</div>
      <div class="row"><span class="hint">Ctrl+Enter saves</span><button class="btn accent" id="re-save" data-probe-press>${R.id ? 'Save changes' : 'File report'}</button></div></div>
      <div class="cols-main">
        <div class="card">
          <div class="seg" id="re-type">${(S.ctx.config.reportTypes || []).map((t) => `<button data-t="${t.key}" class="${R.type === t.key ? 'on' : ''}">${esc(t.label)}</button>`).join('')}</div>
          <div class="grid"><div class="field span2"><label>Title</label><input id="re-title" maxlength="120" value="${esc(R.title)}" placeholder="Armed robbery at Fleeca, Route 68"></div>
            <div class="field span2"><label>Location</label><input id="re-loc" maxlength="120" value="${esc(R.location)}" placeholder="Street, postal or landmark"></div>
            <div class="field span2"><label>Narrative</label><textarea id="re-body" class="tall" placeholder="What happened, in order. Who, what, when, where, why.">${esc(R.body)}</textarea></div></div>
        </div>
        <div>
          <div class="card"><div class="card-title">People</div><div id="re-people"></div><div id="re-pp"></div></div>
          <div class="card"><div class="card-title">Assisting officers</div><div class="hint">You are the primary officer.</div><div id="re-off"></div><div id="re-op"></div></div>
          <div class="card"><div class="card-title">Weapons <span class="hint">· by serial${can('weapons_manage') ? '; "Seized" also marks it seized on the registry' : ''}</span></div><div id="re-wpn"></div>
            <div class="picker-wrap"><input type="text" id="re-wq" placeholder="+ Add a weapon: serial, owner or type…" autocomplete="off" maxlength="40"><div class="pop hidden"></div></div></div>
        </div>
      </div>
      <div class="card"><div class="card-title">Charges <span class="hint">· per suspect, from the penal code. You can lower the fine and jail time of a charge${(S.ctx.config.chargeOverride || {}).maxFineMult > 1 ? ' or raise it up to ' + Math.round(S.ctx.config.chargeOverride.maxFineMult * 100) + '%' : ''}; every change is logged on the report.</span></div><div id="re-charges"></div></div>`;
    function maxFine(p) { return Math.floor((p.fine || 0) * (((S.ctx.config.chargeOverride || {}).maxFineMult) || 1) + 0.5); }
    function maxMonths(p) { return Math.floor((p.months || 0) * (((S.ctx.config.chargeOverride || {}).maxMonthsMult) || 1) + 0.5); }
    const drawPeople = () => {
      $('#re-people').innerHTML = R.people.length ? R.people.map((p, i) => `<div class="li"><div class="li-main"><b>${esc(p.name)}</b></div>
        <select data-prole="${i}">${['suspect', 'victim', 'witness', 'other'].map((r) => `<option${p.role === r ? ' selected' : ''}>${r}</option>`).join('')}</select>
        <button class="icon-btn" data-pdel="${i}" title="Remove">✕</button></div>`).join('') : '<div class="hint">Add the people involved.</div>';
      $$('[data-prole]').forEach((s) => s.onchange = () => { R.people[+s.dataset.prole].role = s.value; drawCharges(); });
      $$('[data-pdel]').forEach((b) => b.onclick = () => { const p = R.people.splice(+b.dataset.pdel, 1)[0]; R.charges = R.charges.filter((c) => c.charId !== p.charId); drawPeople(); drawCharges(); });
    };
    const drawOff = () => {
      $('#re-off').innerHTML = R.officers.map((o, i) => `<div class="li"><div class="li-main"><b>${esc(o.name)}</b></div><button class="icon-btn" data-odel="${i}">✕</button></div>`).join('');
      $$('[data-odel]').forEach((b) => b.onclick = () => { R.officers.splice(+b.dataset.odel, 1); drawOff(); });
    };
    const drawWpn = () => {
      $('#re-wpn').innerHTML = R.weapons.length ? R.weapons.map((w, i) => `<div class="li${w.status === 'stolen' ? ' stolen' : ''}">${serialTag(w.serial)}<div class="li-main"><b>${w.registered ? esc(w.label || '') : '<span class="hint">Not on the registry</span>'}</b>${w.status === 'stolen' ? '<span class="hint txt-bad">Reported stolen</span>' : ''}</div>
        <select data-wrole="${i}">${W_ROLES.map(([k, l]) => `<option value="${k}"${w.role === k ? ' selected' : ''}>${l}</option>`).join('')}</select>
        <button class="icon-btn" data-wdel="${i}" title="Remove">✕</button></div>`).join('') : '<div class="hint">Guns seized, used or found. Type a serial below.</div>';
      $$('[data-wrole]').forEach((s) => s.onchange = () => { R.weapons[+s.dataset.wrole].role = s.value; });
      $$('[data-wdel]').forEach((b) => b.onclick = () => { R.weapons.splice(+b.dataset.wdel, 1); drawWpn(); });
    };
    {
      const inp = $('#re-wq'), pop = inp.nextElementSibling; let wt = null, seq = 0;
      const addW = (w) => { if (!R.weapons.find((x) => x.serial === w.serial)) R.weapons.push(Object.assign({ role: R.type === 'arrest' ? 'seized' : 'evidence' }, w)); inp.value = ''; pop.classList.add('hidden'); drawWpn(); inp.focus(); };
      inp.addEventListener('input', () => {
        clearTimeout(wt); const q = inp.value.trim();
        if (q.length < 2) { pop.classList.add('hidden'); return; }
        wt = setTimeout(async () => {
          const my = ++seq; const r = await call('weapons', { q }); if (my !== seq) return;
          const list = ((r.ok && r.data) || []).slice(0, 7), sq = cleanSerial(q);
          const raw = sq.length >= 4 && !list.some((x) => x.serial === sq) && !/\s/.test(q) ? `<div class="pop-row" data-wadd="${esc(sq)}" data-wreg="0">${serialTag(sq)} <b>Add this serial</b><span class="hint">not on the registry</span></div>` : '';
          pop.innerHTML = list.map((x) => `<div class="pop-row" data-wadd="${esc(x.serial)}" data-wreg="1" data-wl="${esc(x.label || x.item)}" data-ws="${esc(x.status)}">${serialTag(x.serial)} <b>${esc(x.label || x.item)}</b><span class="hint">${esc(x.owner || 'no owner')}</span>${x.status !== 'registered' ? wPill(x.status) : ''}</div>`).join('') + raw || '<div class="pop-empty">Type the full serial to add it</div>';
          pop.classList.remove('hidden');
          $$('[data-wadd]', pop).forEach((row) => row.onmousedown = (e) => { e.preventDefault(); addW({ serial: row.dataset.wadd, registered: row.dataset.wreg === '1', label: row.dataset.wl || '', status: row.dataset.ws }); });
        }, 220);
      });
      inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); const first = $('[data-wadd]', pop); if (first && !pop.classList.contains('hidden')) first.dispatchEvent(new MouseEvent('mousedown')); else { const sq = cleanSerial(inp.value); if (sq.length >= 4) addW({ serial: sq, registered: false }); } } });
      inp.addEventListener('blur', () => setTimeout(() => pop.classList.add('hidden'), 150));
    }
    const drawCharges = () => {
      const sus = R.people.filter((p) => p.role === 'suspect');
      $('#re-charges').innerHTML = sus.length ? sus.map((s) => {
        const mine = R.charges.filter((c) => c.charId === s.charId);
        let tf = 0, tm = 0;
        const rows = mine.map((c) => { const p = list.find((x) => x.id === c.penalId) || {};
          if (c.fine == null) c.fine = p.fine || 0; if (c.months == null) c.months = p.months || 0;
          tf += c.fine * c.count; tm += c.months * c.count;
          const k = `${s.charId}:${c.penalId}`, mf = maxFine(p), mm = maxMonths(p);
          const ed = c.fine !== (p.fine || 0) || c.months !== (p.months || 0);
          return `<div class="charge${ed ? ' edited' : ''}"><span class="cat c-${esc(p.category)}">${esc(p.code)}</span><span class="c-title">${esc(p.title)}</span><span class="spacer"></span>
            <label class="ov" title="Fine per count (0 to ${money(mf)})">$<input type="number" min="0" max="${mf}" step="1" value="${c.fine}" data-cfine="${k}"></label>
            <label class="ov" title="Jail months per count (0 to ${mm})"><input type="number" min="0" max="${mm}" step="1" value="${c.months}" data-cmon="${k}">mo</label>
            <span class="hint pc-def" title="Penal code default">${ed ? `<a class="lnk" data-creset="${k}">reset</a> · ` : ''}PC ${money(p.fine || 0)} · ${p.months || 0} mo</span>
            <div class="stepper"><button data-cdec="${k}">−</button><span>${c.count}</span><button data-cinc="${k}">+</button></div>
            <span class="w90 tot-c">${money(c.fine * c.count)}</span><button class="icon-btn" data-cdel="${k}">✕</button></div>`; }).join('');
        return `<div class="sus"><div class="sus-head"><b>${esc(s.name)}</b><span class="spacer"></span><span class="tot">${money(tf)} · ${tm} months</span></div>${rows}
          <div class="picker-wrap"><input type="text" class="pc-pick" data-for="${s.charId}" placeholder="+ Add a charge: type a code or words…" autocomplete="off"><div class="pop hidden"></div></div></div>`;
      }).join('') : '<div class="hint">Mark someone as a suspect to charge them.</div>';
      const find = (k) => { const [cid, pid] = k.split(':').map(Number); return R.charges.find((c) => c.charId === cid && c.penalId === pid); };
      $$('[data-cinc]').forEach((b) => b.onclick = () => { const c = find(b.dataset.cinc); c.count = Math.min(20, c.count + 1); drawCharges(); });
      $$('[data-cdec]').forEach((b) => b.onclick = () => { const c = find(b.dataset.cdec); c.count = Math.max(1, c.count - 1); drawCharges(); });
      $$('[data-cdel]').forEach((b) => b.onclick = () => { const c = find(b.dataset.cdel); R.charges.splice(R.charges.indexOf(c), 1); drawCharges(); });
      const pOf = (c) => list.find((x) => x.id === c.penalId) || {};
      $$('[data-cfine]').forEach((inp) => inp.onchange = () => { const c = find(inp.dataset.cfine); c.fine = Math.max(0, Math.min(maxFine(pOf(c)), Math.floor(+inp.value || 0))); setTimeout(drawCharges, 0); });
      $$('[data-cmon]').forEach((inp) => inp.onchange = () => { const c = find(inp.dataset.cmon); c.months = Math.max(0, Math.min(maxMonths(pOf(c)), Math.floor(+inp.value || 0))); setTimeout(drawCharges, 0); });
      $$('[data-creset]').forEach((a) => a.onclick = () => { const c = find(a.dataset.creset); const p = pOf(c); c.fine = p.fine || 0; c.months = p.months || 0; drawCharges(); });
      $$('.pc-pick').forEach((inp) => {
        const pop = inp.nextElementSibling, cid = +inp.dataset.for;
        inp.addEventListener('input', () => {
          const q = inp.value.trim().toLowerCase();
          if (!q) { pop.classList.add('hidden'); return; }
          const hits = list.filter((p) => p.active && (p.code + ' ' + p.title).toLowerCase().includes(q)).slice(0, 8);
          pop.innerHTML = hits.length ? hits.map((p) => `<div class="pop-row" data-pid="${p.id}"><span class="cat c-${esc(p.category)}">${esc(p.code)}</span> <b>${esc(p.title)}</b><span class="hint">${money(p.fine)} · ${p.months} mo</span></div>`).join('') : '<div class="pop-empty">No charge matches</div>';
          pop.classList.remove('hidden');
          $$('.pop-row', pop).forEach((row) => row.onmousedown = (e) => { e.preventDefault();
            const pid = +row.dataset.pid; const have = R.charges.find((c) => c.charId === cid && c.penalId === pid);
            const pp = list.find((x) => x.id === pid) || {};
            if (have) have.count = Math.min(20, have.count + 1); else R.charges.push({ charId: cid, penalId: pid, count: 1, fine: Math.min(pp.fine || 0, maxFine(pp)), months: Math.min(pp.months || 0, maxMonths(pp)) });
            drawCharges(); const again = $(`.pc-pick[data-for="${cid}"]`); if (again) again.focus(); });
        });
        inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); const first = $('.pop-row', pop); if (first) first.dispatchEvent(new MouseEvent('mousedown')); } });
        inp.addEventListener('blur', () => setTimeout(() => pop.classList.add('hidden'), 150));
      });
    };
    personPicker($('#re-pp'), '+ Add a person…', (p) => { if (!R.people.find((x) => x.charId === p.charId)) R.people.push({ charId: p.charId, name: p.name, role: 'suspect' }); drawPeople(); drawCharges(); });
    personPicker($('#re-op'), '+ Add an officer…', (p) => { if (p.charId !== S.ctx.me.charId && !R.officers.find((x) => x.charId === p.charId)) R.officers.push(p); drawOff(); });
    drawPeople(); drawOff(); drawWpn(); drawCharges();
    $$('#re-type [data-t]').forEach((b) => b.onclick = () => { R.type = b.dataset.t; $$('#re-type [data-t]').forEach((x) => x.classList.toggle('on', x === b)); });
    $('#re-back').onclick = () => { S.dirty = false; go('reports', R.id ? { view: R.id } : null); };
    const save = () => busy($('#re-save'), async () => {
      R.title = $('#re-title').value.trim();
      if (!R.title) { toast('Give the report a title', 'err'); $('#re-title').focus(); return; }
      const r = await call('reportSave', { id: R.id || undefined, type: R.type, title: R.title, location: $('#re-loc').value, body: $('#re-body').value,
        people: R.people.map((p) => ({ charId: p.charId, role: p.role })), officers: R.officers.map((o) => o.charId), charges: R.charges, weapons: R.weapons.map((w) => ({ serial: w.serial, role: w.role })), ver: R.ver });
      if (r.ok && HOOK.afterReportSave) { try { await HOOK.afterReportSave(R.id || r.data, R); } catch (e) { /* the report is saved either way */ } }
      if (said(r, R.id ? 'Report saved' : 'Report #' + r.data + ' filed')) { S.dirty = false; go('reports', { view: r.data }); }
    });
    $('#re-save').onclick = save;
    if (HOOK.reportEditor) HOOK.reportEditor(v, R, (k) => { R.type = k; $$('#re-type [data-t]').forEach((x) => x.classList.toggle('on', x.dataset.t === k)); });
    v.onkeydown = (e) => { if (e.key === 'Enter' && e.ctrlKey) { e.preventDefault(); save(); } };
    $('#re-title').focus();
    if (R.id) watchEditing('report', R.id, () => $('#re-others') && $('#re-save') && S.view === 'reports', $('#re-others'));
  }

  // 1.8.0: who else has this open in an editor (pings every 15 s while the editor is up; stops by itself)
  function watchEditing(kind, id, alive, box) {
    let n = 0;
    const tick = async () => {
      if (!alive()) { call('editing', { kind, id, done: true }); return; }
      const r = await call('editing', { kind, id });
      const o = (r.ok && r.data && Array.isArray(r.data.others)) ? r.data.others : [];
      if (box && box.isConnected) {
        box.classList.toggle('hidden', !o.length);
        box.innerHTML = o.length ? `<span>✎</span><div><b>${o.map((x) => esc(x.name)).join(', ')} ${o.length === 1 ? 'is' : 'are'} editing this too</b><div class="hint">Whoever saves first wins; the other save is stopped so nothing is overwritten.</div></div>` : '';
      }
      if (++n < 400) setTimeout(tick, 15000);
    };
    tick();
  }

  // ---------------------------------------------------------------- warrants
  VIEWS.warrants = async (v) => {
    const st = S.warTab || 'open';
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Warrants</div><div class="hint">Shared by every department</div></div>
      ${(can('warrants_issue') || can('warrants_request')) ? `<button class="btn accent" id="w-new" data-probe-press>+ ${P().warrants_issue ? 'Issue' : 'Request'} warrant</button>` : ''}</div>
      <div class="seg big mb" id="w-tabs">${[['open', 'Open'], ['requested', 'Requested'], ['served', 'Served'], ['void', 'Void']].map(([k, l]) => `<button data-wt="${k}" class="${st === k ? 'on' : ''}">${l} <span class="seg-n" data-wn="${k}"></span></button>`).join('')}</div>
      <div id="w-list"><div class="loading-row"><div class="spin"></div></div></div>`;
    $$('[data-wt]').forEach((b) => b.onclick = () => { S.warTab = b.dataset.wt; go('warrants'); });
    if ($('#w-new')) $('#w-new').onclick = () => warrantForm(null, () => go('warrants'));
    call('warrantCounts').then((rc) => { if (rc.ok) $$('[data-wn]').forEach((el) => { const n = rc.data[el.dataset.wn] || 0; el.textContent = n ? n : ''; el.classList.toggle('hot', el.dataset.wn === 'requested' && n > 0); }); });
    const r = await call('warrants', { status: st === 'open' ? undefined : st });
    const box = $('#w-list'); if (!box) return;
    const list = (r.ok && r.data) || [];
    box.innerHTML = list.length ? list.map((w) => `<div class="wcard ${w.status}${w.expired ? ' expired' : ''}">
        <div class="w-status ${w.expired ? 'expired' : w.status}">${esc(w.expired ? 'Expired' : { active: 'Active', requested: 'Requested', served: 'Served', void: 'Void' }[w.status] || w.status)}</div>
        <div class="w-main"><div class="w-top"><a class="lnk person-lnk" data-person="${w.charId}" title="Open their profile"><b>${esc(w.name || '#' + w.charId)}</b> ›</a>${w.auto ? '<span class="pill accent" title="Made automatically for an unpaid fine">Auto</span>' : ''}${w.system ? '<span class="pill accent" title="Posted automatically by the prison">DOC</span>' : ''}<span class="hint">#${w.id} · ${esc(w.deptShort || '')}</span></div>
          <div class="w-reason">${esc(w.reason)}</div><div class="hint">${w.auto ? 'automatic' : 'by ' + (w.requestedBy && !w.system ? `<a class="lnk" data-officer="${w.requestedBy}" title="Officer profile">${esc(w.requestedByName || '')}</a>` : esc(w.requestedByName || ''))} · ${date(w.createdAt)}${w.expiresAt ? ' · ' + (w.status === 'active' && !w.expired ? `<b class="txt-warn">${inDays(w.expiresAt)}</b>` : 'expires ' + date(w.expiresAt)) : (w.status === 'active' ? ' · no expiry' : '')}${w.reportId ? ` · <a class="lnk" data-report="${w.reportId}">report #${w.reportId}</a>` : ''}</div></div>
        <div class="w-act">${w.status === 'requested' && can('warrants_issue') ? `<button class="btn small accent" data-wa="approve:${w.id}">Approve</button>` : ''}
          ${w.status === 'active' && !RO() ? `<button class="btn small" data-wa="serve:${w.id}">Served</button>` : ''}
          ${(w.status === 'active' || w.status === 'requested') && can('warrants_issue') ? `<button class="btn small danger" data-wa="void:${w.id}">Void</button>` : ''}</div></div>`).join('') : empty('No warrants here', '⚖');
    $$('[data-wa]', box).forEach((b) => b.onclick = () => busy(b, async () => {
      const [action, wid] = b.dataset.wa.split(':');
      if (action === 'void' && !await confirmBox('Void warrant', 'Void this warrant? It stops being active for every department. This cannot be undone.', 'Void warrant', true)) return;
      if (said(await call('warrantAct', { id: +wid, action }), 'Warrant ' + (action === 'approve' ? 'approved' : action === 'serve' ? 'served' : 'voided'))) go('warrants');
    }));
  };
  // 1.9.0: what the court (es_doj) has on this person
  function courtCard(k) {
    const cases = k.cases || [];
    return `<div class="card"><div class="card-head"><div class="card-title">⚖ Court</div>${k.convictions ? pill(k.convictions + ' conviction' + (k.convictions === 1 ? '' : 's'), 'bad') : pill('No convictions', 'on')}</div>
      ${k.owed ? `<div class="li"><span class="pill warn">${money(k.owed)}</span><div class="li-main"><b>Owed to the court</b><span class="hint">fines and fees, payable at the courthouse</span></div></div>` : ''}
      ${k.probation ? `<div class="li"><span class="pill warn">Probation</span><div class="li-main"><b>Until ${date(k.probation)}</b></div></div>` : ''}
      ${k.service ? `<div class="li"><span class="pill accent">Service</span><div class="li-main"><b>${k.service} community service task${k.service === 1 ? '' : 's'} left</b></div></div>` : ''}
      ${(k.sentences || []).map((x) => { const parts = []; if (x.months) parts.push(x.months + ' month' + (x.months === 1 ? '' : 's') + ' jail' + (x.jailed ? '' : ' (not served yet)')); if (x.fine) parts.push(money(x.fine) + ' fine'); if (x.restitution) parts.push(money(x.restitution) + ' restitution'); if (x.service) parts.push(x.service + ' service task' + (x.service === 1 ? '' : 's')); if (x.probationDays) parts.push(x.probationDays + ' days probation');
        return `<div class="li"><span class="pill bad">Sentence</span><div class="li-main"><b>Sentenced · ${esc(x.number)}</b><span class="hint" style="white-space:normal">${esc(parts.join(' · ') || 'no penalty')} · ${x.source === 'plea' ? 'plea deal · ' : ''}${date(x.createdAt)}</span></div></div>`; }).join('')}
      ${cases.length ? cases.map((x) => `<div class="li"><span class="pill ${x.status === 'open' ? 'accent' : 'off'}">${esc(x.stageLabel || x.status)}</span><div class="li-main"><b>${esc(x.number)} · ${esc(x.title)}</b><span class="hint">${x.verdict && x.verdict !== 'none' ? esc(x.verdict.replace('_', ' ')) + ' · ' : ''}${x.next ? 'next hearing ' + dateTime(x.next) + ' · ' : ''}${x.bail ? 'bail ' + esc(x.bail) + ' · ' : ''}${date(x.createdAt)}</span></div></div>`).join('') : empty('No court cases')}
    </div>`;
  }
  function warrantForm(person, after, reportId, caseId) {
    const issue = P().warrants_issue;
    let who = person;
    modal(`<div class="m-title">${issue ? 'Issue a warrant' : 'Request a warrant'}</div>
      ${issue ? '' : '<p class="hint">A supervisor with "Issue warrants" approves it.</p>'}
      <div class="field"><label>Person</label>${who ? `<div class="picked"><b>${esc(who.name)}</b></div>` : '<div id="wf-pp"></div><div id="wf-who" class="picked hidden"></div>'}</div>
      <div class="field"><label>Reason</label><textarea id="wf-reason" maxlength="500" placeholder="What they are wanted for"></textarea></div>
      <div class="field"><label>Expires</label><select id="wf-days"><option value="0">Never</option><option value="3">In 3 days</option><option value="7" selected>In 7 days</option><option value="14">In 14 days</option><option value="30">In 30 days</option></select></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="wf-go" data-primary>${issue ? 'Issue' : 'Request'}</button></div>`, (card, closeIt) => {
      if (!who) personPicker($('#wf-pp', card), 'Search a name…', (p) => { who = p; $('#wf-who').textContent = p.name; $('#wf-who').classList.remove('hidden'); });
      $('#wf-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        if (!who) { toast('Pick the person', 'err'); return; }
        const r = await call('warrantSave', { charId: who.charId, reason: $('#wf-reason').value, days: +$('#wf-days').value, reportId, caseId });
        if (said(r, r.ok && r.data.status === 'requested' ? 'Warrant requested' : 'Warrant issued')) { closeIt(); if (after) after(); }
      });
    });
  }
  function fineForm(person, after) {
    modal(`<div class="m-title">Fine ${esc(person.name)}</div>
      <div class="grid"><div class="field"><label>Amount ($)</label><input id="ff-amt" type="number" min="1" placeholder="250"></div>
      <div class="field span2"><label>What for</label><input id="ff-why" maxlength="200" placeholder="Speeding on Route 68"></div></div>
      <p class="hint">Taken from their bank now. If they cannot pay, it stays owing.</p>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="ff-go" data-primary>Fine</button></div>`, (card, closeIt) => {
      $('#ff-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('fineCustom', { charId: person.charId, amount: +$('#ff-amt').value, reason: $('#ff-why').value });
        if (r.ok) { toast(r.data.paid ? 'Fine paid' : 'Fine issued, still owing: ' + (r.data.why || ''), r.data.paid ? 'ok' : 'err'); closeIt(); if (after) after(); } else said(r);
      });
    });
  }

  // ---------------------------------------------------------------- BOLOs
  VIEWS.bolos = async (v) => {
    const closed = !!S.boloClosed;
    v.innerHTML = `<div class="v-head"><div><div class="v-title">BOLOs</div><div class="hint">Be on the lookout · shared by every department</div></div>
      ${can('bolo_manage') ? '<button class="btn accent" id="b-new" data-probe-press>+ New BOLO</button>' : ''}</div>
      <div class="seg mb"><button data-bc="0" class="${closed ? '' : 'on'}">Active</button><button data-bc="1" class="${closed ? 'on' : ''}">Closed</button></div>
      <div id="b-list" class="bolo-grid"><div class="loading-row"><div class="spin"></div></div></div>`;
    $$('[data-bc]').forEach((b) => b.onclick = () => { S.boloClosed = b.dataset.bc === '1'; go('bolos'); });
    if ($('#b-new')) $('#b-new').onclick = () => boloForm({ kind: 'vehicle' }, () => go('bolos'));
    const r = await call('bolos', { closed });
    const box = $('#b-list'); if (!box) return;
    const list = (r.ok && r.data) || [];
    box.innerHTML = list.length ? list.map((b) => `<div class="bolo${b.kind === 'person' ? ' b-person' : ''}">${b.kind === 'person' ? `<div class="b-face${b.photo ? '' : ' none'}"${b.charId ? ` data-person="${b.charId}"` : ''}>${b.photo ? `<img src="${esc(b.photo)}" alt="">` : '<span>👤</span>'}</div>` : ''}<div class="b-body"><div class="b-top">${b.kind === 'vehicle' ? `<span class="plate">${esc(b.plate || 'NO PLATE')}</span>` : b.kind === 'weapon' ? (b.serial ? `<a class="lnk" data-wpn="${esc(b.serial)}">⌖ ${serialTag(b.serial)}</a>` : '<span class="pill bad">⌖ Weapon</span>') : `<a class="lnk" data-person="${b.charId}">${esc(b.name || 'Person')}</a>`}<span class="hint">${esc(b.deptShort || '')} · ${ago(b.createdAt)}</span></div>
      <b>${esc(b.title)}</b><div class="b-desc">${esc(b.description || '')}</div>
      <div class="row between"><span class="hint">${esc(b.createdByName || 'Automatic')}${b.expiresAt ? ' · until ' + dateTime(b.expiresAt) : ''}</span>${!closed && !RO() ? `<button class="btn small ghost" data-bclose="${b.id}">Close</button>` : ''}</div></div></div>`).join('') : empty(closed ? 'No closed BOLOs' : 'No active BOLOs', '⚑');
    $$('[data-bclose]', box).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('boloClose', { id: +b.dataset.bclose }), 'BOLO closed')) go('bolos'); }));
  };
  function boloForm(o, after) {
    let kind = o.kind || 'vehicle', who = o.person || null;
    modal(`<div class="m-title">New BOLO</div>
      <div class="seg mb" id="bf-kind"><button data-k="vehicle" class="${kind === 'vehicle' ? 'on' : ''}">Vehicle</button><button data-k="person" class="${kind === 'person' ? 'on' : ''}">Person</button><button data-k="weapon" class="${kind === 'weapon' ? 'on' : ''}">Weapon</button></div>
      <div id="bf-wpn" class="field${kind === 'weapon' ? '' : ' hidden'}"><label>Serial <span class="hint">(if known)</span></label><input id="bf-serial" maxlength="32" value="${esc(o.serial || '')}" style="text-transform:uppercase;font-family:'Courier New',monospace"></div>
      <div id="bf-veh" class="field${kind === 'vehicle' ? '' : ' hidden'}"><label>Plate <span class="hint">(if known)</span></label><input id="bf-plate" maxlength="10" value="${esc(o.plate || '')}" style="text-transform:uppercase"></div>
      <div id="bf-per" class="field${kind === 'person' ? '' : ' hidden'}"><label>Person</label>${who ? `<div class="picked"><b>${esc(who.name)}</b></div>` : '<div id="bf-pp"></div><div id="bf-who" class="picked hidden"></div>'}</div>
      <div class="field"><label>Title</label><input id="bf-title" maxlength="120" value="${esc(o.title || '')}" placeholder="Black Sultan RS fled a robbery"></div>
      <div class="field"><label>Description</label><textarea id="bf-desc" maxlength="1000" placeholder="Colour, damage, direction of travel, clothing…"></textarea></div>
      <div class="field"><label>Lasts</label><select id="bf-hours"><option value="0">Until closed</option><option value="2">2 hours</option><option value="6">6 hours</option><option value="24" selected>24 hours</option><option value="72">3 days</option></select></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="bf-go" data-primary>Post BOLO</button></div>`, (card, closeIt) => {
      $$('#bf-kind [data-k]', card).forEach((b) => b.onclick = () => { kind = b.dataset.k; $$('#bf-kind [data-k]', card).forEach((x) => x.classList.toggle('on', x === b)); $('#bf-veh').classList.toggle('hidden', kind !== 'vehicle'); $('#bf-per').classList.toggle('hidden', kind !== 'person'); $('#bf-wpn').classList.toggle('hidden', kind !== 'weapon'); });
      if (!who && $('#bf-pp', card)) personPicker($('#bf-pp', card), 'Search a name…', (p) => { who = p; $('#bf-who').textContent = p.name; $('#bf-who').classList.remove('hidden'); });
      $('#bf-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('boloSave', { kind, plate: $('#bf-plate').value, serial: $('#bf-serial').value, charId: who && who.charId, title: $('#bf-title').value, description: $('#bf-desc').value, hours: +$('#bf-hours').value });
        if (said(r, 'BOLO posted')) { closeIt(); if (after) after(); }
      });
    });
  }

  // ---------------------------------------------------------------- stats
  const LV = [{ cls: 'ok', label: 'Active' }, { cls: 'note', label: 'Note' }, { cls: 'warn', label: 'Warning' }, { cls: 'act', label: 'Step in' }];
  const lvTag = (m) => m.onDuty ? pill('On duty', 'on') : (m.loa || m.onLeave) ? '<span class="pill leave">On leave</span>'
    : `<span class="lv lv-${LV[m.level || 0].cls}">${LV[m.level || 0].label}${m.level ? ' · ' + m.inactiveDays + 'd' : ''}</span>`;
  VIEWS.stats = async (v) => {
    const days = S.statDays || 30;
    const r = await call('stats', { days, tz: new Date().getTimezoneOffset() });
    if (S.view !== 'stats') return;
    if (!r.ok) { v.innerHTML = empty(r.why); return; }
    const s = r.data, t = s.totals || {};
    const board = (title, rows, fmt, emptyTxt) => {
      const tot = (rows || []).reduce((n, x) => n + (x.value || 0), 0) || 1;
      return `<div class="card"><div class="card-title">${title}</div>${(rows || []).length ? rows.map((x, i) => `<div class="li lb${x.charId ? ' click' : ''}" ${x.charId ? `data-officer="${x.charId}"` : ''}><span class="rank-n r${i + 1}">${i < 3 ? ['🥇', '🥈', '🥉'][i] : i + 1}</span><div class="li-main"><b>${esc(x.name)}</b><span class="hint">${esc(x.callsign || '')} ${esc(x.roleName || '')}</span>
        <div class="share"><div style="width:${Math.max(3, Math.round((x.value / tot) * 100))}%"></div></div></div><span class="big-n">${fmt(x.value)}</span></div>`).join('') : empty(emptyTxt)}</div>`;
    };
    const daily = s.daily || [];
    const maxD = Math.max(1, ...daily);
    const dayLbl = (i) => { const d = new Date(); d.setDate(d.getDate() - (daily.length - 1 - i)); return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };
    v.innerHTML = `<div class="v-head"><div><div class="v-title">${esc(S.ctx.dept.short)} stats</div><div class="hint">Duty tracked since ${date(s.trackingSince)}</div></div>
      <div class="seg big">${[7, 30, 90].map((d) => `<button data-sd="${d}" class="${d === days ? 'on' : ''}">${d} days</button>`).join('')}</div></div>
      <div class="kpis"><div class="kpi"><b>${t.members || 0}</b><span>members</span></div><div class="kpi"><b>${t.onDuty || 0}</b><span>on duty now</span></div>
        <div class="kpi"><b>${t.active || 0}</b><span>on duty in ${days} days</span></div><div class="kpi"><b>${dur(t.dutySeconds)}</b><span>time on duty</span></div>
        <div class="kpi"><b class="${t.act ? 'txt-bad' : t.note || t.warning ? 'txt-warn' : ''}">${(t.note || 0) + (t.warning || 0) + (t.act || 0)}</b><span>inactive &gt;${(s.thresholds || {}).note || 5}d</span></div></div>
      ${daily.length ? `<div class="card"><div class="card-head"><div class="card-title">Duty time per day</div><span class="hint">whole department · ${dur(daily.reduce((a, b) => a + b, 0))}</span></div>
        <div class="chart">${daily.map((x, i) => `<div class="bar-col" title="${dayLbl(i)}: ${dur(x)}"><div class="bar" style="height:${x ? Math.max(4, Math.round((x / maxD) * 100)) : 0}%"></div></div>`).join('')}</div>
        <div class="chart-x"><span>${dayLbl(0)}</span><span>${dayLbl(Math.floor(daily.length / 2))}</span><span>Today</span></div></div>` : ''}
      <div class="cols2">${board('Most time on duty', s.top && s.top.duty, (x) => dur(x), 'No duty time yet')}
        ${s.arrestsTracked ? board('Most arrests', s.top && s.top.arrests, (x) => x, 'No arrest reports yet') : `<div class="card"><div class="card-title">Most arrests</div>${empty('Counted from arrest reports')}</div>`}</div>
      ${s.members ? `<div class="card flush"><div class="card-head pad"><div class="card-title">Everyone</div><input type="text" id="st-q" placeholder="Search name or callsign…" style="width:220px"></div><div id="st-table"></div></div>` : ''}`;
    $$('[data-sd]').forEach((b) => b.onclick = () => { S.statDays = +b.dataset.sd; go('stats'); });
    if (!s.members) return;
    const cols = [['callsign', 'Callsign'], ['name', 'Name'], ['roleLevel', 'Rank'], ['dutySeconds', 'On duty', 'num']]
      .concat(s.arrestsTracked ? [['arrests', 'Arrests', 'num']] : []).concat([['lastDuty', 'Last on duty'], ['level', 'Status']]);
    S.statSort = S.statSort || { k: 'dutySeconds', d: -1 };
    const drawT = () => {
      const q = (($('#st-q') || {}).value || '').toLowerCase();
      const so = S.statSort;
      const val = (m, k) => k === 'lastDuty' ? (m.onDuty ? 9e12 : m.lastDuty || 0) : k === 'level' ? ((m.loa ? -1 : m.level) || 0) : m[k];
      const list = s.members.filter((m) => !q || (m.name + ' ' + (m.callsign || '')).toLowerCase().includes(q))
        .sort((a, b) => { const x = val(a, so.k), y = val(b, so.k); return (typeof x === 'string' ? String(x).localeCompare(String(y || '')) : (x || 0) - (y || 0)) * so.d; });
      $('#st-table').innerHTML = `<table class="rows"><thead><tr>${cols.map(([k, l, c]) => `<th class="sort ${c || ''}${so.k === k ? ' on' : ''}" data-sk="${k}">${l}${so.k === k ? (so.d > 0 ? ' ▲' : ' ▼') : ''}</th>`).join('')}</tr></thead><tbody>
        ${list.map((m) => `<tr class="click" data-officer="${m.charId}"><td><b>${esc(m.callsign || '—')}</b></td><td>${esc(m.name)}</td><td>${esc(m.roleName || '')}</td><td class="num">${dur(m.dutySeconds)}</td>${s.arrestsTracked ? `<td class="num">${m.arrests || 0}</td>` : ''}<td>${m.onDuty ? pill('On duty', 'on') : ago(m.lastDuty)}</td><td>${lvTag(m)}</td></tr>`).join('') || `<tr><td colspan="${cols.length}">${empty('Nobody matches')}</td></tr>`}</tbody></table>`;
      $$('[data-sk]').forEach((th) => th.onclick = () => { const k = th.dataset.sk; S.statSort = { k, d: so.k === k ? -so.d : (k === 'name' || k === 'callsign' ? 1 : -1) }; drawT(); });
    };
    $('#st-q').addEventListener('input', drawT); drawT();
  };

  // Officer card: stats, leave history, training
  // 1.7.0: names open the full officer profile (officer.js); the old card stays as a fallback
  async function officerCard(charId) {
    if (VIEWS.officer) { go('officer', charId); return; }
    const r = await call('officer', { charId, days: S.statDays || 30 });
    if (!r.ok) { said(r); return; }
    const x = r.data, m = x.member, ses = x.sessions || [];
    const lvl = { pending: 'warn', approved: 'on', denied: 'bad', ended: 'off', cancelled: 'off' };
    modal(`<div class="oc-head"><div class="portrait sm"><span>${esc((m.name || '?').split(' ').map((w) => w[0]).join('').slice(0, 2))}</span></div>
        <div><div class="m-title">${esc(m.name)}</div><div class="hint">${esc(m.callsign || '—')} · ${esc(m.roleName || '')}</div></div><span class="spacer"></span>${lvTag(m)}</div>
      <div class="kpis"><div class="kpi"><b>${dur(m.dutySeconds)}</b><span>on duty, ${x.days} days</span></div><div class="kpi"><b>${m.arrests == null ? '—' : m.arrests}</b><span>arrests</span></div>
        <div class="kpi"><b>${x.reports}</b><span>reports written</span></div><div class="kpi"><b>${m.onDuty ? 'now' : ago(m.lastDuty)}</b><span>last on duty</span></div></div>
      <div class="card"><div class="card-title">Leave history</div>${(x.loas || []).length ? x.loas.map((l) => `<div class="li"><span class="pill big ${lvl[l.status] || ''}">${esc(l.status)}</span><div class="li-main"><b>${calDate(l.startsAt)} → ${calDate(l.endsAt)}</b><span class="hint">${esc(l.reason || '')}${l.decidedByName ? ' · ' + esc(l.status) + ' by ' + esc(l.decidedByName) : ''}</span></div></div>`).join('') : empty('No leave')}</div>
      <div class="card"><div class="card-title">Training</div>${x.trainee ? `<div class="hint mb">${esc((x.trainee.status || '').replace('_', ' '))}${x.trainee.ftoName ? ' · FTO ' + esc(x.trainee.ftoName) : ''} · ${x.trainee.rideAlongs || 0} ride-alongs</div>` : ''}
        ${ses.length ? ses.slice(0, 6).map((s2) => `<div class="li"><span class="pill">${esc({ ridealong: 'Ride-along', training: 'Training', evaluation: 'Evaluation' }[s2.kind] || s2.kind)}</span><div class="li-main"><b>${dateTime(s2.sessionAt)} · ${s2.minutes} min</b><span class="hint">${esc(s2.ftoName || '')}${s2.notes ? ' · ' + esc(s2.notes.slice(0, 80)) : ''}</span></div></div>`).join('') : empty('No training sessions')}</div>
      <div class="row end"><button class="btn ghost" data-x>Close</button></div>`, (card) => card.classList.add('wide'));
  }

  // ---------------------------------------------------------------- department (leaders)
  VIEWS.department = async (v, sub) => {
    sub = sub || S.deptTab || 'roster';
    S.deptTab = sub;
    const t = S.todo || {};
    const tabs = [['roster', 'Roster', '']].concat(P().loa_manage || S.ctx.staff ? [['activity', 'Activity', tabBadge(t.inactive, 'bad')], ['leave', 'Leave requests', tabBadge(t.loa, 'warn')]] : [])
      .concat(S.ctx.staff || P().personnel_manage || P().canManage ? [['certs', 'Certifications', tabBadge(t.certs, 'warn')]] : []);
    v.innerHTML = `<div class="v-head"><div><div class="v-title">${esc(S.ctx.dept.name)}</div><div class="hint">Your rank: ${esc(S.ctx.me.roleName || '')}. You can manage people below your rank.</div></div></div>
      <div class="tabs">${tabs.map(([k, l, b]) => `<button class="tab${sub === k ? ' on' : ''}" data-dt="${k}" data-probe-press>${l}${b}</button>`).join('')}</div><div id="d-body"><div class="loading-row"><div class="spin"></div></div></div>`;
    $$('[data-dt]').forEach((b) => b.onclick = () => go('department', b.dataset.dt));
    if (sub === 'roster') return deptRoster();
    if (sub === 'activity') return deptActivity();
    if (sub === 'leave') return deptLeave();
    if (sub === 'certs') { if (HOOK.deptCerts) return HOOK.deptCerts($('#d-body')); $('#d-body').innerHTML = empty('This part of the MDT did not load. An admin needs to run "refresh" then "ensure es_mdt".', '⚠'); }
  };
  async function deptRoster() {
    const r = await call('dept');
    const box = $('#d-body'); if (!box) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const x = r.data, rt = x.rights || {}, my = x.myLevel || 0, staff = S.ctx.staff;
    const below = (lv) => staff || (lv || 0) < my;
    x.ranks.sort((a, b) => (b.level || 0) - (a.level || 0));
    S.deptData = x;
    const certList = x.certList || [];
    box.innerHTML = `<div class="row between"><div class="row"><input type="text" id="ro-q" placeholder="Search name or callsign…" style="width:260px" value="${esc(S.rosterQ || '')}">
        ${certList.length ? `<select id="ro-cert" class="small-sel" title="Show only people with this certification"><option value="">All certifications</option>${certList.map((c) => `<option value="${c.id}"${String(S.rosterCert || '') === String(c.id) ? ' selected' : ''}>${esc((c.icon ? c.icon + ' ' : '') + c.name)}</option>`).join('')}</select>` : ''}</div>
        ${rt.hire && !RO() ? '<button class="btn accent" id="h-open" data-probe-press>+ Hire someone</button>' : ''}</div><div id="ro-list"></div>`;
    const lastCell = (m) => m.onDuty ? pill('On duty', 'on') : m.onLeave ? '<span class="pill leave">On leave</span>'
      : `<span class="lv lv-${LV[m.level || 0].cls}">${m.lastDuty ? ago(m.lastDuty) : 'not yet'}</span>`;
    const draw = () => {
      const q = ($('#ro-q').value || '').toLowerCase(); S.rosterQ = $('#ro-q').value;
      const cf = $('#ro-cert') ? $('#ro-cert').value : ''; S.rosterCert = cf;
      const list = x.roster.filter((m) => (!q || (m.name + ' ' + (m.callsign || '') + ' ' + (m.badge || '')).toLowerCase().includes(q))
        && (!cf || (m.certs || []).some((c) => String(c.certId) === cf && c.state !== 'expired')));
      const groups = [];
      x.ranks.forEach((k) => { const ms = list.filter((m) => m.roleId === k.roleId); if (ms.length) groups.push([k.name, ms]); });
      const other = list.filter((m) => !x.ranks.find((k) => k.roleId === m.roleId)); if (other.length) groups.push(['Other', other]);
      $('#ro-list').innerHTML = groups.length ? groups.map(([name, ms]) => `<div class="card flush ro-group"><div class="pc-head"><b>${esc(name)}</b><span class="count-pill">${ms.length}</span></div>
        <table class="rows"><colgroup><col style="width:120px"><col><col style="width:150px"><col style="width:150px"><col style="width:110px"></colgroup><tbody>
        ${ms.map((m) => `<tr class="${m.charId === x.me ? 'me-row' : ''}"><td><b>${esc(m.callsign || m.badge || '—')}</b></td><td><a class="lnk ro-name" data-officer="${m.charId}" title="Open profile">${esc(m.name)}</a>${m.owner ? ' ' + pill('owner', 'accent') : ''}${m.charId === x.me ? ' ' + pill('you', '') : ''}${certBadges(m.certs, true)}</td>
          <td>${m.onDuty ? pill('On duty', 'on') : m.online ? pill('In city', '') : pill('Away', 'off')}</td><td title="Last on duty">${lastCell(m)}</td>
          <td class="right">${!RO() && (rt.roster || rt.promote || rt.fire) && (m.charId === x.me || (!m.owner && below(m.roleLevel))) ? `<button class="btn small" data-medit="${m.charId}">Manage ›</button>` : ''}</td></tr>`).join('')}</tbody></table></div>`).join('')
        : empty('Nobody matches');
      $$('[data-medit]', box).forEach((b) => b.onclick = () => memberPanel(x.roster.find((y) => y.charId === +b.dataset.medit), x));
    };
    $('#ro-q').addEventListener('input', draw); if ($('#ro-cert')) $('#ro-cert').onchange = draw; draw();
    if ($('#h-open')) $('#h-open').onclick = () => hirePicker(x);
  }

  // Hire: online players, nearest first, then a plain confirm
  async function hirePicker(x) {
    const r = await call('onlinePlayers');
    if (!r.ok) { said(r); return; }
    const list = r.data || [], my = x.myLevel || 0, staff = S.ctx.staff;
    const ranks = x.ranks.filter((k) => staff || (k.level || 0) < my);
    let pick = null;
    modal(`<div class="m-title">Hire someone</div><p class="hint">People in the city, nearest first. They join the FTO "Needs training" list.</p>
      <input type="text" id="hp-q" placeholder="Search name or server ID…">
      <div class="hp-list" id="hp-list"></div>
      <div class="field"><label>Starting rank</label><select id="hp-role">${ranks.slice().reverse().map((k, i) => `<option value="${k.roleId}"${i === 0 ? ' selected' : ''}>${esc(k.name)}</option>`).join('')}</select></div>
      <div class="confirm-line hidden" id="hp-sum"></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="hp-go" data-primary disabled>Hire</button></div>`, (card, closeIt) => {
      const sum = () => {
        const role = $('#hp-role', card); const rn = role.options[role.selectedIndex] ? role.options[role.selectedIndex].text : '';
        $('#hp-sum', card).classList.toggle('hidden', !pick);
        if (pick) $('#hp-sum', card).innerHTML = `You're hiring <b>${esc(pick.name)}</b> (ID ${pick.source}) as <b>${esc(rn)}</b>.`;
        $('#hp-go', card).disabled = !pick;
      };
      const draw = () => {
        const q = $('#hp-q', card).value.trim().toLowerCase();
        const rows = list.filter((p) => !q || p.name.toLowerCase().includes(q) || String(p.source) === q);
        $('#hp-list', card).innerHTML = rows.length ? rows.map((p) => `<div class="hp-row${p.member ? ' dis' : ''}${pick && pick.source === p.source ? ' sel' : ''}" data-hp="${p.source}">
            <span class="id-chip">ID ${p.source}</span><b>${esc(p.name)}</b><span class="spacer"></span>${p.member ? pill('already in ' + esc(S.ctx.dept.short), 'off') : p.dist != null ? `<span class="hint">${p.dist < 15 ? '<b class="txt-ok">near you</b> · ' : ''}${p.dist} m</span>` : ''}</div>`).join('')
          : empty(list.length ? 'Nobody matches' : 'Nobody else is in the city');
        $$('[data-hp]', card).forEach((el) => el.onclick = () => { const p = list.find((y) => y.source === +el.dataset.hp); if (!p || p.member) return; pick = p; draw(); sum(); });
      };
      $('#hp-q', card).addEventListener('input', draw); $('#hp-role', card).onchange = sum; draw();
      $('#hp-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        if (said(await call('hire', { target: pick.source, roleId: +$('#hp-role', card).value }), `${pick.name} hired`)) { closeIt(); deptRoster(); }
      });
    });
  }

  // Manage a member: side panel
  function memberPanel(m, x) {
    const rt = x.rights || {}, self = m.charId === x.me, staff = S.ctx.staff, my = x.myLevel || 0;
    const allowed = x.ranks.filter((k) => staff || (k.level || 0) < my);
    const asc = allowed.slice().sort((a, b) => a.level - b.level);
    const cur = x.ranks.find((k) => k.roleId === m.roleId) || { level: m.roleLevel || 0 };
    const up = asc.find((k) => k.level > (cur.level || 0)), down = asc.slice().reverse().find((k) => k.level < (cur.level || 0));
    drawer(`<div class="dr-head"><div><div class="m-title">${esc(m.name)}</div><div class="hint">${esc(m.roleName || '')} · ${esc(m.callsign || 'no callsign')}</div></div><span class="spacer"></span><button class="btn small" data-officer="${m.charId}" id="mp-prof">👤 Profile</button><button class="icon-btn" data-x>✕</button></div>
      <div class="dr-sec"><div class="lbl">Status</div><div class="row">${m.onDuty ? pill('On duty', 'on') : m.online ? pill('In city', '') : pill('Away', 'off')} <span class="hint">last on duty ${m.onDuty ? 'now' : ago(m.lastDuty)}</span></div></div>
      ${!self && rt.promote ? `<div class="dr-sec"><div class="lbl">Rank</div>
        <div class="row">${up ? `<button class="btn accent" data-rk="${up.roleId}">▲ Promote to ${esc(up.name)}</button>` : ''}${down ? `<button class="btn" data-rk="${down.roleId}">▼ Demote to ${esc(down.name)}</button>` : ''}</div>
        <div class="row"><select id="mp-rank">${allowed.map((k) => `<option value="${k.roleId}"${k.roleId === m.roleId ? ' selected' : ''}>${esc(k.name)}</option>`).join('')}</select><button class="btn" id="mp-rank-go">Set rank</button></div>
        <div class="field"><label>Reason <span class="hint">(optional, goes on their career timeline)</span></label><input id="mp-reason" maxlength="300" placeholder="e.g. Passed the sergeant's exam"></div>
        <div class="hint">You can only set ranks below your own.</div></div>` : ''}
      ${rt.roster ? `<div class="dr-sec"><div class="lbl">Callsign</div><div class="row"><input id="mp-call" maxlength="16" value="${esc(m.callsign || m.badge || '')}" placeholder="1-ADAM-12"><button class="btn" id="mp-call-go">Save</button></div>
        <div class="lbl">Notes</div><textarea id="mp-notes" maxlength="500" placeholder="Only leaders see these">${esc(m.notes || '')}</textarea><div class="row end"><button class="btn small" id="mp-notes-go">Save notes</button></div></div>` : ''}
      ${!self && rt.fire ? `<div class="dr-sec danger-zone"><div class="lbl">Danger zone</div><button class="btn danger" id="mp-fire">Fire from ${esc(S.ctx.dept.short)}</button></div>` : ''}`, (card, closeIt) => {
      const reason = () => ($('#mp-reason', card) ? $('#mp-reason', card).value.trim() : '');
      const setRank = (roleId, label) => async () => { if (said(await call('setRank', { charId: m.charId, roleId, reason: reason() }), label)) { closeIt(); deptRoster(); } };
      if ($('#mp-prof', card)) $('#mp-prof', card).onclick = () => { closeIt(); go('officer', m.charId); };
      $$('[data-rk]', card).forEach((b) => b.onclick = () => busy(b, setRank(+b.dataset.rk, b.textContent.replace(/^[▲▼] /, ''))));
      if ($('#mp-rank-go', card)) $('#mp-rank-go', card).onclick = (e) => busy(e.currentTarget, setRank(+$('#mp-rank', card).value, 'Rank changed'));
      if ($('#mp-call-go', card)) $('#mp-call-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const cs = $('#mp-call', card).value.trim();
        if (said(await call('memberInfo', { charId: m.charId, callsign: cs, badge: cs, notes: m.notes || '' }), 'Callsign saved')) { m.callsign = cs; deptRoster(); }
      });
      if ($('#mp-notes-go', card)) $('#mp-notes-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const n = $('#mp-notes', card).value;
        if (said(await call('memberInfo', { charId: m.charId, callsign: m.callsign || '', badge: m.badge || m.callsign || '', notes: n }), 'Notes saved')) m.notes = n;
      });
      if ($('#mp-fire', card)) $('#mp-fire', card).onclick = async () => {
        closeIt();
        if (await confirmBox('Fire ' + m.name, `Remove ${m.name} from ${S.ctx.dept.name}? They lose the job, its rank and access to the MDT.`, 'Fire', true)) if (said(await call('fire', { charId: m.charId }), m.name + ' removed')) deptRoster();
      };
    });
  }
  // A panel that slides in from the right (same behaviour as modal)
  function drawer(html, onReady) {
    const m = $('#modal'), rc = $('.shell').getBoundingClientRect();
    m.classList.add('as-drawer');
    Object.assign(m.style, { left: rc.left + 'px', top: rc.top + 'px', width: rc.width + 'px', height: rc.height + 'px', right: 'auto', bottom: 'auto', borderRadius: '14px', overflow: 'hidden' });
    const closeIt = modal(html, onReady);
    const obs = new MutationObserver(() => { if (m.classList.contains('hidden')) { m.classList.remove('as-drawer'); m.removeAttribute('style'); obs.disconnect(); } });
    obs.observe(m, { attributes: true, attributeFilter: ['class'] });
    return closeIt;
  }

  async function deptActivity() {
    const r = await call('activity');
    const box = $('#d-body'); if (!box) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const x = r.data, T = x.thresholds || {};
    box.innerHTML = `<div class="h-legend"><span class="lv lv-note">Note</span> off duty more than ${T.note} days <span class="lv lv-warn">Warning</span> more than ${T.warn} <span class="lv lv-act">Step in</span> ${T.act}+ <span class="pill leave">On leave</span> clock paused <span class="pill warn">🎓 no DOR</span> trainee overdue for a report · tracked since ${date(x.trackingSince)}</div>
      <div class="card flush"><table class="rows"><thead><tr><th>Name</th><th>Rank</th><th>Last on duty</th><th>Last in city</th><th>Status</th></tr></thead><tbody>
      ${(x.members || []).map((m) => `<tr class="click lvrow lv-${(m.loa && !m.onDuty) ? 'ok' : LV[m.level || 0].cls}" data-officer="${m.charId}"><td><b>${esc(m.name)}</b> <span class="hint">${esc(m.callsign || '')}</span></td><td>${esc(m.roleName || '')}</td>
        <td>${m.onDuty ? pill('On duty', 'on') : m.neverTracked ? '<span class="hint">not since tracking began</span>' : ago(m.lastDuty)}</td><td>${m.online ? pill('In city', '') : ago(m.lastPlayed)}</td>
        <td>${m.loa && !m.onDuty ? `<span class="pill leave">On leave until ${calDate(m.loa.endsAt)}</span>` : lvTag(m)}${m.loaPending ? ' ' + pill('leave request', 'warn') : ''}${m.training ? ' ' + (m.training.overdue ? pill(`🎓 no DOR ${m.training.days}d`, 'warn') : pill(`🎓 in training ${m.training.pct || 0}%`, '')) : ''}</td></tr>`).join('')}</tbody></table></div>`;
  }
  async function deptLeave() {
    const r = await call('loaList', {});
    const box = $('#d-body'); if (!box) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const list = r.data || [], now = Date.now() / 1000, me = S.ctx.me.charId;
    const pend = list.filter((l) => l.status === 'pending'), act = list.filter((l) => l.status === 'approved' && l.endsAt > now), rest = list.filter((l) => !pend.includes(l) && !act.includes(l));
    const days = (l) => Math.max(1, Math.round((l.endsAt - l.startsAt) / 86400));
    const row = (l, btns) => `<div class="li loa-row"><span class="pill big ${LOA_CLS[l.status] || ''}">${esc(LOA_LBL(l, now))}</span><div class="li-main"><b>${esc(l.name || '#' + l.charId)}</b><span class="hint">${calDate(l.startsAt)} → ${calDate(l.endsAt)} · ${days(l)} day${days(l) === 1 ? '' : 's'}${l.reason ? ' · “' + esc(l.reason) + '”' : ''}${l.decidedByName ? ' · ' + esc(l.status) + ' by ' + esc(l.decidedByName) : ''}</span></div>${btns}</div>`;
    box.innerHTML = `<div class="card"><div class="card-title">Waiting for a decision ${tabBadge(pend.length, 'warn')}</div>${pend.length ? pend.map((l) => row(l, RO() ? '' : l.charId === me ? '<span class="hint">Another leader or an admin decides your own leave</span>' : `<button class="btn small accent" data-la="approve:${l.id}">Approve</button><button class="btn small danger" data-la="deny:${l.id}">Deny</button>`)).join('') : empty('Nothing waiting')}</div>
      <div class="card"><div class="card-title">On leave or coming up</div>${act.length ? act.map((l) => row(l, RO() ? '' : `<button class="btn small ghost" data-la="end:${l.id}">${l.startsAt > now ? 'Cancel' : 'End early'}</button>`)).join('') : empty('Nobody on leave')}</div>
      <div class="card"><div class="card-title">History</div>${rest.length ? rest.map((l) => row(l, '')).join('') : empty('No history')}</div>`;
    $$('[data-la]', box).forEach((b) => b.onclick = () => busy(b, async () => {
      const [action, lid] = b.dataset.la.split(':');
      if (said(await call('loaAct', { id: +lid, action }), { approve: 'Leave approved', deny: 'Leave denied', end: 'Leave ended' }[action])) { deptLeave(); loadBadges(); }
    }));
  }
  const LOA_CLS = { pending: 'warn', approved: 'on', denied: 'bad', ended: 'off', cancelled: 'off' };
  const LOA_LBL = (l, now) => l.status === 'approved' && l.startsAt <= now && l.endsAt > now ? 'On leave' : ({ pending: 'Pending', approved: 'Approved', denied: 'Denied', ended: 'Ended', cancelled: 'Cancelled' }[l.status] || l.status);

  // ---------------------------------------------------------------- my leave
  VIEWS.leave = async (v) => {
    const r = await call('loaMine');
    if (S.view !== 'leave') return;
    const list = (r.ok && r.data) || [], now = Date.now() / 1000;
    const L = ((S.ctx.config.dept || {}).loa) || { maxDays: 60 };
    const today = new Date(); const later = new Date(Date.now() + 86400000 * 7);
    v.innerHTML = `<div class="v-head"><div><div class="v-title">My leave</div><div class="hint">Going away? File a leave of absence. While it is approved and running, your inactivity clock is paused; it starts again the day after it ends.</div></div></div>
      <div class="cols2"><div class="card"><div class="card-title">Request leave</div>
        <div class="grid"><div class="field"><label>First day</label><input type="date" id="l-start" value="${isoDay(today)}" min="${isoDay(today)}"></div>
          <div class="field"><label>Last day</label><input type="date" id="l-end" value="${isoDay(later)}" min="${isoDay(today)}"></div>
          <div class="field span2"><label>Reason <span class="hint">(optional, leaders see it)</span></label><input type="text" id="l-reason" maxlength="300" placeholder="Vacation, exams, moving house…"></div></div>
        <div class="row between"><span class="hint" id="l-len"></span><button class="btn accent" id="l-go" data-primary>Send request</button></div>
        <p class="hint">Up to ${L.maxDays} days. A leader approves it${S.ctx.me.roleLevel && P().loa_manage ? '; as a leader, yours goes to another leader or an admin' : ''}.</p></div>
      <div class="card"><div class="card-title">My requests</div>${list.length ? list.map((l) => {
        const running = l.status === 'approved' && l.startsAt <= now && l.endsAt > now;
        return `<div class="li loa-row"><span class="pill big ${LOA_CLS[l.status] || ''}">${esc(LOA_LBL(l, now))}</span><div class="li-main"><b>${calDate(l.startsAt)} → ${calDate(l.endsAt)}</b><span class="hint">${l.reason ? '“' + esc(l.reason) + '”' : 'No reason given'}${l.decidedByName ? ' · ' + esc(l.status) + ' by ' + esc(l.decidedByName) : l.status === 'pending' ? ' · waiting for a leader' : ''}${l.decisionNote ? ' · ' + esc(l.decisionNote) : ''}</span></div>
          ${l.status === 'pending' || (l.status === 'approved' && l.startsAt > now) ? `<button class="btn small ghost" data-lc="cancel:${l.id}">Cancel</button>` : running ? `<button class="btn small" data-lc="end:${l.id}">I'm back</button>` : ''}</div>`;
      }).join('') : empty('No leave yet', '☂')}</div></div>`;
    const len = () => { const a = new Date($('#l-start').value), b = new Date($('#l-end').value); const n = Math.round((b - a) / 86400000) + 1; $('#l-len').textContent = n > 0 ? n + ' day' + (n === 1 ? '' : 's') : 'The last day is before the first'; };
    $('#l-start').onchange = () => { if ($('#l-end').value < $('#l-start').value) $('#l-end').value = $('#l-start').value; $('#l-end').min = $('#l-start').value; len(); };
    $('#l-end').onchange = len; len();
    $('#l-go').onclick = (e) => busy(e.currentTarget, async () => {
      if (said(await call('loaFile', { startDate: $('#l-start').value, endDate: $('#l-end').value, reason: $('#l-reason').value }), 'Leave requested')) {
        $('#l-reason').value = ''; $('#l-start').value = isoDay(new Date()); $('#l-end').value = isoDay(new Date(Date.now() + 86400000 * 7)); go('leave');
      }
    });
    $$('[data-lc]', v).forEach((b) => b.onclick = () => busy(b, async () => {
      const [action, lid] = b.dataset.lc.split(':');
      if (said(await call('loaAct', { id: +lid, action }), action === 'end' ? 'Welcome back' : 'Cancelled')) go('leave');
    }));
  };

  // ---------------------------------------------------------------- training (FTO)
  VIEWS.training = async (v, sub) => {
    sub = sub || 'queue';
    const td = S.todo || {};
    const tabs = [['queue', 'Needs training' + tabBadge(td.trainees, 'accent')], ['recs', 'Recommendations' + tabBadge(td.recs, 'warn')], ['done', 'History']];
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Training</div><div class="hint">New hires land here automatically. Claim one, log ride-alongs, sign off, or recommend an immediate promotion.</div></div></div>
      <div class="tabs">${tabs.map(([k, l]) => `<button class="tab${(sub === k || (typeof sub === 'object' && k === 'queue')) ? ' on' : ''}" data-tt="${k}" data-probe-press>${l}</button>`).join('')}</div><div id="t-body"><div class="loading-row"><div class="spin"></div></div></div>`;
    $$('[data-tt]').forEach((b) => b.onclick = () => go('training', b.dataset.tt));
    if (typeof sub === 'object') return traineeDetail(sub.charId);
    if (sub === 'recs') return ftoRecs();
    return ftoQueue(sub === 'done');
  };
  async function ftoQueue(done) {
    const r = await call('trainees', { all: done });
    const box = $('#t-body'); if (!box) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const x = r.data, me = S.ctx.me.charId, isFto = can('fto_train');
    const list = done ? x.trainees.filter((t) => t.status !== 'training') : x.trainees;
    const how = `<div class="how${list.length ? ' small' : ''}"><div class="how-title">How training works</div>
      <ol><li><b>New hires show up here</b> on their own, with their hire date and rank.</li><li><b>An FTO claims them</b> (or a leader assigns one).</li>
      <li><b>Log every ride-along</b> with notes, 1-5 ratings and what you covered. ${x.required} ride-alongs make them ready.</li>
      <li><b>Sign them off</b>, or <b>recommend an instant promotion</b> if they don't need more.</li></ol></div>`;
    box.innerHTML = (done ? '' : ridesCard(x.rides)) + (done ? '' : how) + (list.length ? `<div class="t-grid">${list.map((t) => {
      const pct = Math.min(100, Math.round(((t.rideAlongs || 0) / (x.required || 3)) * 100));
      const ck = t.checkDone || [], ckT = t.checkTotal || (x.checklist || []).length;
      const ckPct = ckT ? Math.round((ck.length / ckT) * 100) : 0;
      return `<div class="tcard${t.ftoCharId === me ? ' mine' : ''}"><div class="t-top"><div><b>${esc(t.name)}</b><div class="hint">${esc(t.roleName || '')} · hired ${t.hiredAt ? date(t.hiredAt) : 'before tracking'}${t.origin === 'backfill' ? ' (existing member)' : ''}</div></div>
        ${done ? pill(t.status.replace('_', ' '), t.status === 'left' ? 'off' : 'on') : t.recommended ? pill('Recommended', 'accent') : t.ready ? pill('Ride-alongs done', 'on') : ''}</div>
        <div class="prog-l"><span>Ride-alongs</span><b>${t.rideAlongs || 0}/${x.required}</b></div><div class="prog"><div class="prog-bar" style="width:${pct}%"></div></div>
        ${ckT ? `<div class="prog-l"><span>Checklist</span><b>${ck.length}/${ckT}</b></div><div class="prog alt"><div class="prog-bar" style="width:${ckPct}%"></div></div>
        <div class="ck-row">${(x.checklist || []).map((k) => `<span class="ck${ck.includes(k) ? ' on' : ''}" title="${esc(k)}">${ck.includes(k) ? '✓' : '○'} ${esc(k)}</span>`).join('')}</div>` : ''}
        <div class="hint">${t.sessions || 0} session${t.sessions === 1 ? '' : 's'}${t.lastSession ? ' · last ' + ago(t.lastSession) : ''}</div>
        <div class="t-fto">${t.ftoName ? `FTO: <b>${esc(t.ftoName)}</b>` : '<span class="txt-warn">No FTO yet</span>'}</div>
        ${done ? '' : `<div class="row wrap">${isFto && !t.ftoCharId ? `<button class="btn small accent" data-claim="${t.charId}">Claim</button>` : ''}
          ${isFto ? `<select class="small-sel" data-assign="${t.charId}"><option value="">Assign to…</option>${x.ftos.filter((f) => f.charId !== t.charId).map((f) => `<option value="${f.charId}"${f.charId === t.ftoCharId ? ' selected' : ''}>${esc(f.name)}</option>`).join('')}${t.ftoCharId ? '<option value="none">Nobody</option>' : ''}</select>` : ''}
          <button class="btn small" data-open="${t.charId}">Open</button></div>`}</div>`;
    }).join('')}</div>` : empty(done ? 'No finished training yet' : 'Nobody needs training right now. Hire someone from the Department tab and they appear here.', '✎'));
    $$('[data-claim]', box).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('ftoAssign', { charId: +b.dataset.claim }), 'Trainee claimed')) ftoQueue(false); }));
    $$('[data-rlog]', box).forEach((b) => b.onclick = () => { const ride = (x.rides || []).find((r2) => r2.id === +b.dataset.rlog); if (ride) rideForm(ride, () => { loadBadges(); ftoQueue(false); }); });
    $$('[data-rskip]', box).forEach((b) => b.onclick = async () => { if (await confirmBox('Dismiss ride-along', 'Drop this ride-along without notes? It is not saved to their training.', 'Dismiss', true)) { await call('rideSkip', { id: +b.dataset.rskip }); loadBadges(); ftoQueue(false); } });
    $$('[data-assign]', box).forEach((s) => s.onchange = async () => {
      if (!s.value) return;
      const r2 = await call('ftoAssign', { charId: +s.dataset.assign, ftoCharId: s.value === 'none' ? false : +s.value });
      said(r2, s.value === 'none' ? 'Unassigned' : 'Assigned'); ftoQueue(false);
    });
    $$('[data-open]', box).forEach((b) => b.onclick = () => go('training', { charId: +b.dataset.open }));
  }
  async function traineeDetail(charId) {
    const [rq, rs] = await Promise.all([call('trainees', { all: true }), call('ftoSessions', { charId })]);
    const box = $('#t-body'); if (!box) return;
    if (!rq.ok) { box.innerHTML = empty(rq.why); return; }
    const t = rq.data.trainees.find((x) => x.charId === charId) || { charId, name: '#' + charId };
    const sessions = (rs.ok && rs.data) || [];
    const F = (S.ctx.config.dept || {}).fto || { ratings: [], checklist: [], kinds: ['ridealong'] };
    const done = {}; sessions.forEach((s) => Object.keys(s.checklist || {}).forEach((k) => { done[k] = true; }));
    const avg = {}; F.ratings.forEach((k) => { const v2 = sessions.map((s) => (s.ratings || {})[k]).filter(Boolean); if (v2.length) avg[k] = v2.reduce((a, b) => a + b, 0) / v2.length; });
    const isFto = can('fto_train'), training = t.status === 'training';
    box.innerHTML = `<div class="v-head"><div><button class="btn small ghost" data-tt="queue">← Needs training</button><div class="v-title">${esc(t.name)}</div>
        <div class="hint">${esc(t.roleName || '')} · ${t.rideAlongs || 0} of ${rq.data.required} ride-alongs${t.ftoName ? ' · FTO ' + esc(t.ftoName) : ''}${training ? '' : ' · ' + esc((t.status || '').replace('_', ' '))}</div></div>
      <div class="row">${isFto && training ? '<button class="btn accent" id="td-log">+ Log session</button><button class="btn" id="td-rec">Recommend promotion</button>' : ''}${training && (isFto || can('canPromote')) ? '<button class="btn ghost" id="td-sign">Sign off training</button>' : ''}</div></div>
      <div class="cols2"><div class="card"><div class="card-title">Checklist</div><div class="chips">${F.checklist.map((k) => `<span class="pill ${done[k] ? 'on' : 'off'}">${done[k] ? '✓ ' : ''}${esc(k)}</span>`).join('')}</div></div>
        <div class="card"><div class="card-title">Average ratings</div>${F.ratings.map((k) => `<div class="rate-row"><span>${esc(k)}</span><div class="stars">${[1, 2, 3, 4, 5].map((n) => `<i class="${avg[k] && avg[k] >= n - 0.25 ? 'on' : ''}">★</i>`).join('')}</div><span class="hint">${avg[k] ? avg[k].toFixed(1) : '—'}</span></div>`).join('')}</div></div>
      <div class="card"><div class="card-title">Sessions</div>${sessions.length ? sessions.map((s) => `<div class="sess"><div class="row between"><b>${esc({ ridealong: 'Ride-along', training: 'Training', evaluation: 'Evaluation' }[s.kind] || s.kind)}</b><span class="hint">${dateTime(s.sessionAt)} · ${s.minutes} min · ${esc(s.ftoName || '')}</span></div>
        ${s.notes ? `<div class="narr">${esc(s.notes).replace(/\n/g, '<br>')}</div>` : ''}<div class="chips">${Object.entries(s.ratings || {}).map(([k, n]) => `<span class="pill">${esc(k)} ${'★'.repeat(n)}</span>`).join('')}${Object.keys(s.checklist || {}).map((k) => `<span class="pill on">✓ ${esc(k)}</span>`).join('')}</div></div>`).join('') : empty('No sessions logged yet')}</div>`;
    $$('[data-tt]', box).forEach((b) => b.onclick = () => go('training', 'queue'));
    if ($('#td-log')) $('#td-log').onclick = () => ftoLogForm(t, F, () => traineeDetail(charId));
    if ($('#td-rec')) $('#td-rec').onclick = () => modal(`<div class="m-title">Recommend ${esc(t.name)} for promotion</div>
      <p class="hint">Leaders see this and can promote them now, skipping the remaining ride-alongs.</p>
      <div class="field"><label>Why</label><textarea id="rc-why" maxlength="500" placeholder="What they showed you"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="rc-go" data-primary>Recommend</button></div>`, (card, closeIt) => {
      $('#rc-go', card).onclick = (e) => busy(e.currentTarget, async () => { if (said(await call('recommend', { charId, reason: $('#rc-why').value }), 'Recommendation sent to leaders')) { closeIt(); traineeDetail(charId); } });
    });
    if ($('#td-sign')) $('#td-sign').onclick = async () => { if (await confirmBox('Sign off training', `Mark ${t.name}'s training as complete? They leave the Needs training list.`, 'Sign off')) if (said(await call('ftoSignOff', { charId }), 'Training signed off')) go('training', 'queue'); };
  }
  function ftoLogForm(t, F, after, o) {
    o = o || {};
    const ratings = {};
    const k0 = o.kind && F.kinds.includes(o.kind) ? o.kind : F.kinds[0];
    modal(`<div class="m-title">${esc(o.title || 'Log a session with ' + t.name)}</div>${o.title ? `<p class="hint">Write up how it went with <b>${esc(t.name)}</b>. The time is filled in from the ride-along.</p>` : ''}
      <div class="seg mb" id="fl-kind">${F.kinds.map((k) => `<button data-k="${k}" class="${k === k0 ? 'on' : ''}">${esc({ ridealong: 'Ride-along', training: 'Training', evaluation: 'Evaluation' }[k] || k)}</button>`).join('')}</div>
      <div class="grid"><div class="field"><label>How long (minutes)</label><input type="number" id="fl-min" min="0" max="1440" value="${o.minutes || 60}"></div></div>
      <div class="field"><label>Ratings <span class="hint">(click the stars)</span></label>${F.ratings.map((k) => `<div class="rate-row"><span>${esc(k)}</span><div class="stars pick" data-r="${esc(k)}">${[1, 2, 3, 4, 5].map((n) => `<i data-n="${n}">★</i>`).join('')}</div></div>`).join('')}</div>
      <div class="field"><label>Covered</label><div class="chips">${F.checklist.map((k) => `<label class="chip-t"><input type="checkbox" value="${esc(k)}"><span>${esc(k)}</span></label>`).join('')}</div></div>
      <div class="field"><label>Notes</label><textarea id="fl-notes" maxlength="4000" placeholder="What went well, what to work on"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="fl-go" data-primary>Save session</button></div>`, (card, closeIt) => {
      let kind = k0;
      $$('#fl-kind [data-k]', card).forEach((b) => b.onclick = () => { kind = b.dataset.k; $$('#fl-kind [data-k]', card).forEach((x) => x.classList.toggle('on', x === b)); });
      $$('.stars.pick', card).forEach((row) => $$('i', row).forEach((st) => st.onclick = () => { const n = +st.dataset.n; ratings[row.dataset.r] = n; $$('i', row).forEach((x) => x.classList.toggle('on', +x.dataset.n <= n)); }));
      $('#fl-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const checklist = {}; $$('.chips input:checked', card).forEach((i) => { checklist[i.value] = true; });
        const payload = { charId: t.charId, kind, minutes: +$('#fl-min').value, notes: $('#fl-notes').value, ratings, checklist };
        if (said(await (o.send ? o.send(payload) : call('ftoLog', payload)), 'Session saved')) { closeIt(); after(); }
      });
    });
  }
  async function ftoRecs() {
    const [r, rd] = await Promise.all([call('recs', {}), call('dept')]);
    const box = $('#t-body'); if (!box) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const ranks = ((rd.ok && rd.data.ranks) || []).slice().sort((a, b) => a.level - b.level), my = (rd.ok && rd.data.myLevel) || 0, leader = can('canPromote');
    box.innerHTML = (r.data || []).length ? r.data.map((x) => `<div class="li card"><div class="li-main"><b>${esc(x.traineeName || '#' + x.traineeCharId)}</b><span class="hint">recommended by ${esc(x.ftoName || '')} · ${ago(x.createdAt)}</span><div>${esc(x.reason || '')}</div></div>
      ${leader ? `<select class="small-sel" data-rrole="${x.id}"><option value="">Next rank up</option>${ranks.filter((k) => S.ctx.staff || k.level < my).map((k) => `<option value="${k.roleId}">${esc(k.name)}</option>`).join('')}</select>
        <button class="btn small accent" data-ra="approve:${x.id}">Promote</button><button class="btn small ghost" data-ra="deny:${x.id}">Deny</button>` : x.ftoCharId === S.ctx.me.charId && !RO() ? `<button class="btn small ghost" data-ra="withdraw:${x.id}">Withdraw</button>` : pill('Waiting for a leader', 'warn')}</div>`).join('') : empty('No recommendations waiting', '✎');
    $$('[data-ra]', box).forEach((b) => b.onclick = () => busy(b, async () => {
      const [action, rid] = b.dataset.ra.split(':');
      const sel = $(`[data-rrole="${rid}"]`);
      if (said(await call('recAct', { id: +rid, action, roleId: sel && sel.value ? +sel.value : undefined }), { approve: 'Promoted', deny: 'Denied', withdraw: 'Withdrawn' }[action])) ftoRecs();
    }));
  }

  // ---------------------------------------------------------------- 1.3.0: the toolbox ops.js builds on
  window.MDT = { S, $, $$, esc, money, call, post, toast, said, busy, ago, date, dateTime, modal, confirmBox, modalOpen, personPicker, pill, empty,
    can, P, RO, go, VIEWS, HOOK, watchEditing: (k, i, a, b) => watchEditing(k, i, a, b), dur, hours, isoDay, certBadges: (l, s) => certBadges(l, s), ccv, drawer: (h, f) => drawer(h, f), typeLabel, ridesCard, rideForm, ftoRecs, boloForm: (a, b) => boloForm(a, b), tabBadge, loadBadges, calDate: (t) => calDate(t), warrantForm, statusOf, renderFrame, setBadge, applyBadges, loadBadges, penal, serialTag, queueRefresh, logoOf };

  // ---------------------------------------------------------------- global search (Ctrl+K)
  let gsT = null, gsSeq = 0;
  $('#gsearch').addEventListener('input', (e) => {
    clearTimeout(gsT);
    const q = e.target.value.trim(), pop = $('#gsearch-pop');
    if (q.length < 2) { pop.classList.add('hidden'); return; }
    gsT = setTimeout(async () => {
      const my = ++gsSeq;
      const serialish = q.length >= 4 && !/\s/.test(q);
      const [rp, rv, rw] = await Promise.all([call('people', { q }), q.length <= 10 ? call('vehicles', { q }) : Promise.resolve({ ok: true, data: [] }),
        serialish ? call('weapons', { q }) : Promise.resolve({ ok: true, data: [] })]);
      if (my !== gsSeq) return;
      const ppl = (rp.ok && rp.data) || [], veh = (rv.ok && rv.data) || [];
      const sq = cleanSerial(q), wpn = (rw.ok && Array.isArray(rw.data) ? rw.data : []).filter((x) => x.serial.includes(sq));
      pop.innerHTML = (ppl.length ? `<div class="pop-h">People</div>${ppl.slice(0, 6).map((p) => `<div class="pop-row" data-gp="${p.charId}"><b>${esc(p.name)}</b><span class="hint">#${p.charId}${p.phone ? ' · ' + esc(p.phone) : ''}</span>${p.warrants ? pill('Warrant', 'bad') : ''}</div>`).join('')}` : '')
        + (veh.length ? `<div class="pop-h">Vehicles</div>${veh.slice(0, 6).map((x) => `<div class="pop-row" ${x.vehicleId ? `data-gv="${x.vehicleId}"` : `data-gvp="${esc(x.plate)}"`}><span class="plate">${esc(x.plate)}</span><b>${esc(x.label)}</b><span class="hint">${esc(x.owner || '')}</span>${x.bolos ? pill('BOLO', 'bad') : ''}</div>`).join('')}` : '')
        + (wpn.length ? `<div class="pop-h">Weapons</div>${wpn.slice(0, 6).map((x) => `<div class="pop-row${x.status === 'stolen' ? ' stolen' : ''}" data-gw="${esc(x.serial)}">${serialTag(x.serial)}<b>${esc(x.label || x.item)}</b><span class="hint">${esc(x.owner || '')}</span>${x.status !== 'registered' ? wPill(x.status) : ''}</div>`).join('')}` : '')
        + (serialish && !wpn.some((x) => x.serial === sq) && !ppl.length && !veh.length ? `<div class="pop-h">Weapons</div><div class="pop-row" data-gw="${esc(sq)}">${serialTag(sq)}<b>Check serial</b><span class="hint">not on the registry</span></div>` : '')
        || '<div class="pop-empty">Nothing found</div>';
      pop.classList.remove('hidden');
      $$('[data-gp]', pop).forEach((el) => el.onmousedown = () => { pop.classList.add('hidden'); $('#gsearch').value = ''; go('people', +el.dataset.gp); });
      $$('[data-gv]', pop).forEach((el) => el.onmousedown = () => { pop.classList.add('hidden'); $('#gsearch').value = ''; go('vehicles', +el.dataset.gv); });
      $$('[data-gvp]', pop).forEach((el) => el.onmousedown = () => { pop.classList.add('hidden'); $('#gsearch').value = ''; go('vehicles', el.dataset.gvp); });
      $$('[data-gw]', pop).forEach((el) => el.onmousedown = () => { pop.classList.add('hidden'); $('#gsearch').value = ''; go('weapons', el.dataset.gw); });
    }, 220);
  });
  $('#gsearch').addEventListener('blur', () => setTimeout(() => $('#gsearch-pop').classList.add('hidden'), 150));

  // ---------------------------------------------------------------- wiring
  document.addEventListener('click', (e) => {
    const t = e.target.closest ? e.target : null; if (!t) return;
    const act = t.closest('[data-act]');
    if (act && act.dataset.act === 'close') { post('close'); return; }
    const nav = t.closest('[data-nav]'); if (nav) { if (nav.dataset.nav === 'court') { post('toCourt'); return; } go(nav.dataset.nav); return; }
    const gps = t.closest('[data-gps]');
    if (gps) {
      busy(gps, async () => {
        const r = await call('unitGps', { charId: +gps.dataset.gps });
        if (!r.ok) { said(r); return; }
        const w = await post('waypoint', r.data);
        said(w, 'GPS set to ' + (gps.dataset.name || 'the unit'));
      });
      return;
    }
    const pr = t.closest('[data-upair]'); if (pr) { pairModal(pr); return; }
    const ua = t.closest('[data-uans]');
    if (ua) { busy(ua, async () => { const yes = ua.dataset.uans === '1'; if (said(await call('unitAnswer', { accept: yes }), yes ? 'You are paired up' : 'Declined')) { loadBadges(); go(S.view, S.arg); } }); return; }
    if (t.closest('[data-ucancel]')) { call('unitCancel').then(() => go(S.view, S.arg)); return; }
    const ul = t.closest('[data-uleave]');
    if (ul) { confirmBox('Leave unit', 'Leave this unit? You go back to patrolling on your own.', 'Leave unit', true).then((ok) => { if (ok) call('unitLeave').then((r) => { if (said(r, 'You left the unit')) go(S.view, S.arg); }); }); return; }
    const off = t.closest('[data-officer]');
    if (off && !t.closest('button, select, input')) {
      if (modalOpen()) { const x = $('#modal [data-x]'); if (x) x.click(); }
      officerCard(+off.dataset.officer); return;
    }
    const g = t.closest('[data-go]');
    if (g) { const [view, sub] = g.dataset.go.split(':'); go(view, sub || null); return; }
    const rep = t.closest('[data-report]'); if (rep && !t.closest('button')) { go('reports', { view: +rep.dataset.report }); return; }
    const per = t.closest('[data-person]'); if (per && !t.closest('button, select')) { go('people', +per.dataset.person); return; }
    const veh = t.closest('[data-veh]'); if (veh) { go('vehicles', +veh.dataset.veh); return; }
    const wpn = t.closest('[data-wpn]'); if (wpn && !t.closest('button, select')) { if (S.view === 'weapons' && $('#w-detail')) weaponDetail(wpn.dataset.wpn); else go('weapons', wpn.dataset.wpn); return; }
  });
  $('#dept-pick').addEventListener('change', async (e) => {
    const r = await call('pickDept', { id: +e.target.value });
    if (said(r) && r.data && r.data.doj) { post('toCourt'); return; }   // 1.10.0: the DOJ's side of the MDT
    if (r.ok) { S.ctx = r.data; S.penal = null; renderFrame(); go('dashboard'); }
  });
  document.addEventListener('keydown', (e) => {
    if (!S.open) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      if (modalOpen()) { $$('#modal [data-x]')[0] && $$('#modal [data-x]')[0].click(); return; }
      post('close'); return;
    }
    if ((e.ctrlKey || e.metaKey) && (e.key === 'k' || e.key === 'K')) { e.preventDefault(); $('#gsearch').focus(); return; }
    if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey && modalOpen()) {
      const tag = (e.target && e.target.tagName) || '';
      if (tag === 'TEXTAREA' || tag === 'BUTTON') return;
      const b = $('#modal [data-primary]'); if (b && !b.disabled) { e.preventDefault(); b.click(); }
    }
  });

  // Something changed somewhere (another officer filed, paid, issued...): reload what is on screen, quietly
  const WATCH = {
    units: ['units', 'dashboard'], invite: ['units', 'dashboard'], warrants: ['warrants', 'dashboard', 'people'], fines: ['people'], reports: ['reports', 'dashboard', 'people'],
    bolos: ['bolos', 'dashboard', 'people', 'vehicles', 'weapons'], people: ['people'], calls: ['dispatch', 'dashboard'], announce: ['dashboard'], weapons: ['weapons', 'people'], loa: ['leave', 'department', 'dashboard', 'stats'], training: ['training', 'dashboard'],
    evidence: ['evidence', 'cases', 'reports'], cases: ['cases', 'reports'], personnel: ['officer', 'department'],
    permits: ['permits', 'dashboard', 'people', 'weapons'],
  };
  let rfT = null; const rfWhat = new Set();
  function queueRefresh(what) {
    rfWhat.add(what); clearTimeout(rfT);
    rfT = setTimeout(() => {
      const whats = Array.from(rfWhat); rfWhat.clear();
      loadBadges();
      if (modalOpen() || S.dirty) return;
      const hit = whats.some((w) => (WATCH[w] || []).includes(S.view));
      if (!hit) return;
      if (S.view === 'people') { if (S.lastPeopleQ) peopleSearch(S.lastPeopleQ); if (S.personId && $('#p-detail')) personDetail(S.personId, true); return; }
      if (S.view === 'vehicles') return;
      if (S.view === 'units' && S.unitsMode === 'map') return;
      if (S.view === 'livemap') return;
      if (S.view === 'radar') return;
      if (S.view === 'arrest') return;
      if (S.view === 'dispatch' && HOOK.dispatchRefresh) { HOOK.dispatchRefresh(); return; }
      if (S.view === 'weapons') { weaponSearch(); if (!$('#w-detail')) return; if (S.wSerial) weaponDetail(S.wSerial, true); else weaponOverview(true); return; }
      if (S.view === 'reports' && S.arg && S.arg.edit !== undefined) return;
      if (S.view === 'department') { go('department', S.deptTab); return; }
      if (S.view === 'training' && S.arg && typeof S.arg === 'object') return;
      go(S.view, S.arg);
    }, 400);
  }

  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
    if (!m || !m.action) return;
    if (m.action === 'open') {
      S.open = true; S.ctx = m.data; S.penal = null;
      $('#app').classList.remove('hidden'); requestAnimationFrame(() => $('#app').classList.add('shown'));
      renderFrame(); go(S.view && S.view !== 'reports' ? S.view : 'dashboard', S.view === 'people' || S.view === 'vehicles' ? null : S.arg);
      clearInterval(S.timer);
      loadBadges();
      S.timer = setInterval(() => { if (!S.open) return; loadBadges(); if (!modalOpen() && ((S.view === 'units' && S.unitsMode !== 'map') || S.view === 'dashboard')) go(S.view); }, 30000);
    } else if (m.action === 'close') {
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      if (modalOpen()) { $('#modal').classList.add('hidden'); $('#modal-card').innerHTML = ''; }
      clearInterval(S.timer);
      S.open = false; $('#app').classList.remove('shown'); setTimeout(() => { if (!S.open) $('#app').classList.add('hidden'); }, 180);
    } else if (m.action === 'ride') {
      if (!S.open || !m.ride) return;
      loadBadges();
      toast(`Ride-along with ${m.ride.traineeName || 'your trainee'} ended`, 'ok');
      if (!modalOpen()) rideForm(m.ride, () => { loadBadges(); if (S.view === 'training') go('training', S.arg); });
    } else if (m.action === 'refresh') {
      if (!S.open) return;
      if (m.what === 'dept') { call('open').then((r) => { if (r.ok) { S.ctx = r.data; renderFrame(); } }); return; }
      queueRefresh(m.what);
    }
  });
})();
