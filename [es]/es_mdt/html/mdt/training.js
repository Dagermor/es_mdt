// es_mdt 1.6.0 (1.6.3: sign-offs in place, open phases + scroll kept): Field Training. The department's training program (phases and items), Daily Observation Reports,
// sign-offs, the FTO dashboard, the trainee's own read-only view, the supervisor overview and the program editor.
// es_departments keeps the data and checks every call; this page only shows what the caller may do.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, said, busy, ago, date, dateTime, modal, confirmBox, pill, empty, can, RO, go, VIEWS } = M;
  const KIND = { ridealong: 'Ride-along', training: 'Training', evaluation: 'Evaluation' };
  const RATE_TXT = ['', 'Unacceptable', 'Needs work', 'Acceptable', 'Good', 'Excellent'];
  const ACT = { queued: ['➕', 'In training'], assigned: ['👤', 'FTO assigned'], unassigned: ['👤', 'FTO removed'], dor: ['📝', 'DOR written'],
    signed: ['✓', 'Signed off'], unsigned: ['↶', 'Sign-off taken back'], phase_done: ['🏁', 'Phase complete'], ready: ['⭐', 'Ready for final sign-off'],
    completed: ['🎓', 'Training complete'], promoted: ['⬆', 'Promoted'], left: ['✕', 'Left the department'], recommended: ['👍', 'Recommended for promotion'],
    rec_approve: ['⬆', 'Recommendation approved'], rec_deny: ['✕', 'Recommendation denied'], rec_withdraw: ['↶', 'Recommendation withdrawn'], program: ['⚙', 'Program edited'], test: ['🧪', 'Test'] };
  let H = null;   // the last training home
  // 1.6.3: re-renders keep the open phases (per trainee) and the scroll position
  const scroller = (el) => { for (let p = el && el.parentElement; p && p !== document.body; p = p.parentElement) { const o = getComputedStyle(p).overflowY; if ((o === 'auto' || o === 'scroll') && p.scrollHeight > p.clientHeight) return p; } return null; };
  const keepScroll = (el) => { const sc = scroller(el), top = sc ? sc.scrollTop : 0; return () => { if (sc) sc.scrollTop = top; }; };

  const flags = () => {
    const c = (H && H.can) || {}, st = S.ctx.staff;
    return { fto: !!(c.train || st), mgr: !!(c.manage || st), promote: !!(c.promote || st), ro: RO() };
  };
  const initials = (n) => String(n || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((x) => x[0].toUpperCase()).join('');
  const hrs = (m) => m >= 60 ? (Math.round(m / 6) / 10) + ' h' : (m || 0) + ' min';
  const dueTxt = (t) => {
    if (t.status !== 'training') return '';
    if (t.onLeave) return '<span class="hint">On leave: DOR clock paused</span>';
    if (!t.ftoCharId) return '<span class="txt-warn">Needs an FTO</span>';
    if (!t.dorDueAt) return '';
    const left = t.dorDueAt - Date.now() / 1000, d = Math.ceil(Math.abs(left) / 86400);
    return left < 0 ? `<span class="tr-over">DOR overdue · ${t.daysSinceDor} day${t.daysSinceDor === 1 ? '' : 's'} since the last</span>`
      : `<span class="hint">Next DOR due in ${left < 86400 ? 'under a day' : d + ' days'}</span>`;
  };
  const testTag = (t) => t.test ? '<span class="pill tr-test" title="Staff test trainee: no real character (/ftotest clear removes it)">TEST</span> ' : '';
  const statusPill = (t) => testTag(t) + (t.status === 'training' ? (t.overdue ? pill('DOR overdue', 'warn') : t.progress && t.progress.total && t.progress.done === t.progress.total ? pill('Ready to graduate', 'on') : pill('In training', 'accent'))
    : t.status === 'left' ? pill('Left', 'off') : pill(t.status === 'promoted' ? 'Graduated · promoted' : 'Graduated', 'on'));
  const phaseName = (t) => {
    const p = t.progress || {}; if (!p.phases) return '';
    const i = p.phases.findIndex((x) => x.key === p.current);
    return i >= 0 ? `Phase ${i + 1} of ${p.phases.length} · ${esc(p.phases[i].name)}` : (p.total ? 'Every phase done' : '');
  };
  const segBar = (t) => `<div class="tr-segs">${((t.progress || {}).phases || []).map((ph) => {
    const pct = ph.total ? Math.round((ph.done / ph.total) * 100) : 100;
    return `<div class="tr-seg${pct === 100 ? ' full' : ''}" title="${esc(ph.name)}: ${ph.done}/${ph.total}"><i style="width:${pct}%"></i></div>`;
  }).join('')}</div>`;
  const ring = (pct, size) => `<div class="tr-ring" style="--p:${pct};--s:${size || 74}px"><span>${pct}<small>%</small></span></div>`;

  async function home(force) {
    if (H && !force && Date.now() - H._at < 4000) return H;
    const r = await call('ftoHome');
    if (!r.ok) return { _err: r.why };
    H = r.data; H._at = Date.now();
    return H;
  }

  // ---------------------------------------------------------------- the view
  VIEWS.training = async (v, sub) => {
    v.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const h = await home(true);
    if (S.view !== 'training') return;
    if (h._err) { v.innerHTML = empty(h._err, '✎'); return; }
    const f = flags(), td = S.todo || {};
    const tabs = [];
    if (h.trainee) tabs.push(['me', '🎓 My training', '']);
    if (f.fto) tabs.push(['mine', 'My trainees', M.tabBadge(td.overdue, 'warn') || M.tabBadge(td.mine, 'accent')]);
    if (f.fto || f.mgr || f.promote) tabs.push(['all', 'All trainees', M.tabBadge(td.unclaimed, 'accent')]);
    if (f.mgr || f.promote) tabs.push(['stats', 'Overview', '']);
    if (f.fto || f.promote) tabs.push(['recs', 'Recommendations', M.tabBadge(td.recs, 'warn')]);
    if (f.fto || f.mgr || f.promote) tabs.push(['program', 'Program', '']);
    if (!tabs.length) { v.innerHTML = empty('Training is for FTOs, supervisors and trainees.', '✎'); return; }
    const isObj = sub && typeof sub === 'object';
    const cur = isObj ? null : (tabs.find((t) => t[0] === sub) ? sub : tabs[0][0]);
    S.ftoTab = cur || S.ftoTab;
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Field Training</div><div class="hint">${esc(h.program ? h.program.phases.length + ' phases · a DOR is due every ' + h.program.dorDays + ' day' + (h.program.dorDays === 1 ? '' : 's') : '')}</div></div>
        <div class="row">${f.mgr && !f.ro ? '<button class="btn" id="tr-start">+ Put someone in training</button>' : ''}</div></div>
      <div class="tabs">${tabs.map(([k, l, b]) => `<button class="tab${cur === k ? ' on' : ''}" data-trt="${k}" data-probe-press>${l}${b}</button>`).join('')}</div>
      <div id="t-body" class="tr-body"><div class="loading-row"><div class="spin"></div></div></div>`;
    $$('[data-trt]', v).forEach((b) => b.onclick = () => go('training', b.dataset.trt));
    if ($('#tr-start')) $('#tr-start').onclick = () => startPicker();
    if (isObj) return fileView(sub.charId);
    if (cur === 'me') return fileView(S.ctx.me.charId, true);
    if (cur === 'mine') return mineView();
    if (cur === 'all') return allView();
    if (cur === 'stats') return statsView();
    if (cur === 'recs') return M.ftoRecs();
    if (cur === 'program') return programView();
  };

  // ---------------------------------------------------------------- trainee cards
  function card(t) {
    const f = flags(), me = S.ctx.me.charId, p = t.progress || { pct: 0 };
    const training = t.status === 'training';
    const canDor = training && f.fto && !f.ro && t.charId !== me;
    const assign = training && f.mgr && !f.ro ? `<select class="small-sel" data-tassign="${t.charId}" title="Assign an FTO"><option value="">${t.ftoCharId ? 'Move to…' : 'Assign FTO…'}</option>${(H.ftos || []).filter((x) => x.charId !== t.charId && x.charId !== t.ftoCharId).map((x) => `<option value="${x.charId}">${esc(x.name)}</option>`).join('')}${t.ftoCharId ? '<option value="none">No FTO</option>' : ''}</select>` : '';
    return `<div class="tr-card${t.ftoCharId === me && training ? ' mine' : ''}${t.overdue ? ' over' : ''}" data-topen="${t.charId}">
      <div class="tr-top"><div class="tr-av">${esc(initials(t.name))}</div><div class="li-main"><b>${esc(t.name)}</b><span class="hint">${esc(t.roleName || '')}${t.hiredAt ? ' · since ' + date(t.hiredAt) : ''}</span></div>${statusPill(t)}</div>
      <div class="prog-l"><span>${phaseName(t) || '&nbsp;'}</span><b>${p.done || 0}/${p.total || 0}</b></div>
      ${segBar(t)}
      <div class="tr-meta"><span>👤 ${t.ftoName ? esc(t.ftoName) : '<span class="txt-warn">No FTO</span>'}</span><span>📝 ${t.sessions || 0} DOR${t.sessions === 1 ? '' : 's'}</span><span>⏱ ${hrs(t.minutes || 0)}</span>${t.lastSession ? `<span>Last ${ago(t.lastSession)}</span>` : ''}</div>
      <div class="tr-due">${training ? dueTxt(t) : t.doneAt ? `<span class="hint">Finished ${date(t.doneAt)}${t.doneByName ? ' · signed off by ' + esc(t.doneByName) : ''}${t.daysInTraining != null ? ' · ' + t.daysInTraining + ' days' : ''}</span>` : ''}</div>
      <div class="row wrap tr-act">${canDor && (t.ftoCharId === me || f.mgr) ? `<button class="btn small accent" data-tdor="${t.charId}">Write DOR</button>` : ''}
        ${training && f.fto && !f.ro && !t.ftoCharId && t.charId !== me ? `<button class="btn small accent-ghost" data-tclaim="${t.charId}">Claim</button>` : ''}${assign}
        <button class="btn small ghost" data-topen2="${t.charId}">Open file →</button></div></div>`;
  }
  function wireCards(box, after) {
    $$('[data-topen]', box).forEach((el) => el.onclick = (e) => { if (e.target.closest('button, select')) return; go('training', { charId: +el.dataset.topen }); });
    $$('[data-topen2]', box).forEach((b) => b.onclick = () => go('training', { charId: +b.dataset.topen2 }));
    $$('[data-tdor]', box).forEach((b) => b.onclick = () => { const t = H.list.find((x) => x.charId === +b.dataset.tdor); dorForm(t, after); });
    $$('[data-tclaim]', box).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('ftoAssign', { charId: +b.dataset.tclaim }), 'Trainee claimed: they are yours now')) after(); }));
    $$('[data-tassign]', box).forEach((s) => s.onchange = async () => {
      if (!s.value) return;
      if (said(await call('ftoAssign', { charId: +s.dataset.tassign, ftoCharId: s.value === 'none' ? false : +s.value }), s.value === 'none' ? 'FTO removed' : 'FTO assigned')) after();
    });
  }

  // ---------------------------------------------------------------- My trainees (the FTO dashboard)
  async function mineView() {
    const box = $('#t-body'); if (!box) return;
    const me = S.ctx.me.charId, list = (H.list || []).filter((t) => t.status === 'training');
    const mine = list.filter((t) => t.ftoCharId === me).sort((a, b) => (b.overdue ? 1 : 0) - (a.overdue ? 1 : 0) || (a.dorDueAt || 0) - (b.dorDueAt || 0));
    const over = mine.filter((t) => t.overdue), open = list.filter((t) => !t.ftoCharId && t.charId !== me);
    const dueSoon = mine.filter((t) => !t.overdue && t.dorDueAt && t.dorDueAt - Date.now() / 1000 < 86400);
    box.innerHTML = `<div class="kpis mb">
        <div class="kpi"><b>${mine.length}</b><span>my trainees</span></div>
        <div class="kpi${over.length ? ' tr-kbad' : ''}"><b>${over.length}</b><span>DORs overdue</span></div>
        <div class="kpi"><b>${dueSoon.length}</b><span>DORs due today</span></div>
        <div class="kpi click" id="tr-k-open"><b>${open.length}</b><span>waiting for an FTO →</span></div></div>
      ${M.ridesCard(H.rides)}
      ${over.length ? `<div class="tr-alert">⚠ <b>${over.length} trainee${over.length === 1 ? '' : 's'}</b> ${over.length === 1 ? 'has' : 'have'} gone more than ${H.program.dorDays} day${H.program.dorDays === 1 ? '' : 's'} without a DOR. Write one after your next shift together.</div>` : ''}
      ${mine.length ? `<div class="tr-grid">${mine.map(card).join('')}</div>` : `<div class="card">${empty(open.length ? `You have no trainees yet. ${open.length} ${open.length === 1 ? 'is' : 'are'} waiting for an FTO: claim one from All trainees.` : 'You have no trainees yet. When someone is hired into a recruit rank they show up under All trainees.', '🎓')}</div>`}
      ${howCard()}`;
    if ($('#tr-k-open')) $('#tr-k-open').onclick = () => { S.ftoFilter = 'nofto'; go('training', 'all'); };
    wireRides(box);
    wireCards(box, () => go('training', 'mine'));
  }
  function wireRides(box) {
    $$('[data-rlog]', box).forEach((b) => b.onclick = () => { const ride = (H.rides || []).find((r2) => r2.id === +b.dataset.rlog); if (ride) M.rideForm(ride, () => { M.loadBadges(); go('training', S.ftoTab); }); });
    $$('[data-rskip]', box).forEach((b) => b.onclick = async () => { if (await confirmBox('Dismiss ride-along', 'Drop this ride-along without a DOR? It is not saved to their training.', 'Dismiss', true)) { await call('rideSkip', { id: +b.dataset.rskip }); M.loadBadges(); go('training', S.ftoTab); } });
  }
  const howCard = () => `<div class="how small"><div class="how-title">How field training works</div><ol>
    <li><b>Recruits land here</b> when they are hired into a recruit rank (or a supervisor puts them in training).</li>
    <li><b>An FTO claims them</b>, or a supervisor assigns one.</li>
    <li>After each shift together the FTO writes a <b>Daily Observation Report</b>: ratings 1-5, notes, and the items they showed they can do.</li>
    <li>Each <b>phase fills up</b> as its items are signed off. No DOR for ${H.program ? H.program.dorDays : 3} days and they are flagged.</li>
    <li>When every phase is done a <b>supervisor gives the final sign-off</b> and they rank up.</li></ol></div>`;

  // ---------------------------------------------------------------- All trainees
  function allView() {
    const box = $('#t-body'); if (!box) return;
    const F = [['training', 'In training'], ['overdue', 'DOR overdue'], ['nofto', 'No FTO'], ['ready', 'Ready'], ['done', 'Graduated'], ['all', 'Everyone']];
    const flt = S.ftoFilter || 'training', q = (S.ftoQ || '').toLowerCase();
    const all = H.list || [];
    const test = {
      training: (t) => t.status === 'training', overdue: (t) => t.status === 'training' && t.overdue, nofto: (t) => t.status === 'training' && !t.ftoCharId,
      ready: (t) => t.status === 'training' && t.progress.total && t.progress.done === t.progress.total, done: (t) => t.status !== 'training', all: () => true,
    };
    const n = (k) => all.filter(test[k]).length;
    const list = all.filter(test[flt]).filter((t) => !q || (t.name || '').toLowerCase().includes(q) || (t.ftoName || '').toLowerCase().includes(q));
    box.innerHTML = `<div class="row between mb tr-filters"><div class="seg">${F.map(([k, l]) => `<button data-tf="${k}" class="${flt === k ? 'on' : ''}">${l} <span class="seg-n">${n(k)}</span></button>`).join('')}</div>
        <input class="tr-q" id="tr-q" placeholder="Search a name or FTO…" value="${esc(S.ftoQ || '')}"></div>
      ${list.length ? `<div class="tr-grid">${list.map(card).join('')}</div>` : `<div class="card">${empty(flt === 'training' ? 'Nobody is in training right now.' : 'Nobody here.', '🎓')}</div>`}`;
    $$('[data-tf]', box).forEach((b) => b.onclick = () => { S.ftoFilter = b.dataset.tf; allView(); });
    const qi = $('#tr-q'); qi.oninput = () => { S.ftoQ = qi.value; clearTimeout(S.ftoQT); S.ftoQT = setTimeout(() => { allView(); const x = $('#tr-q'); if (x) { x.focus(); x.setSelectionRange(x.value.length, x.value.length); } }, 200); };
    wireCards(box, () => go('training', 'all'));
  }

  // ---------------------------------------------------------------- Overview (the department head)
  async function statsView() {
    const box = $('#t-body'); if (!box) return;
    const r = await call('ftoStats');
    if (!$('#t-body')) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const s = r.data, maxAt = Math.max(1, ...s.phases.map((p) => p.at));
    const over = (H.list || []).filter((t) => t.status === 'training' && t.overdue);
    box.innerHTML = `<div class="kpis mb">
        <div class="kpi"><b>${s.training}</b><span>in training</span></div>
        <div class="kpi${s.overdue ? ' tr-kbad' : ''}"><b>${s.overdue}</b><span>DORs overdue</span></div>
        <div class="kpi${s.unassigned ? ' tr-kwarn' : ''}"><b>${s.unassigned}</b><span>without an FTO</span></div>
        <div class="kpi"><b>${s.avgPct == null ? '—' : s.avgPct + '%'}</b><span>average progress</span></div>
        <div class="kpi"><b>${s.completed30}</b><span>graduated (30 days)</span></div>
        <div class="kpi"><b>${s.avgDays == null ? '—' : s.avgDays}</b><span>days to graduate (avg)</span></div></div>
      <div class="cols2"><div class="card"><div class="card-title">Where trainees are</div>${s.phases.map((p, i) => `<div class="tr-fun"><span class="tr-fn">${i + 1}</span><span class="tr-fl">${esc(p.name)}</span><div class="tr-fb"><i style="width:${Math.round((p.at / maxAt) * 100)}%"></i></div><b>${p.at}</b></div>`).join('')}
          ${s.tests ? `<div class="hint mt">🧪 ${s.tests} staff test trainee${s.tests === 1 ? '' : 's'} not counted in these numbers</div>` : ''}
      ${s.left30 ? `<div class="hint mt">${s.left30} left the department during training in the last 30 days</div>` : ''}</div>
        <div class="card"><div class="card-title">FTOs (last 30 days)</div>${s.ftos.length ? `<table class="rows"><thead><tr><th>FTO</th><th>Trainees</th><th>DORs</th><th>Time</th><th>Last DOR</th></tr></thead><tbody>${s.ftos.map((x) => `<tr><td><b>${esc(x.name || '#' + x.charId)}</b></td><td>${x.trainees}${x.overdue ? ' ' + pill(x.overdue + ' overdue', 'warn') : ''}</td><td>${x.dors30}</td><td>${hrs(x.minutes30)}</td><td>${x.lastDor ? ago(x.lastDor) : '—'}</td></tr>`).join('')}</tbody></table>` : empty('No FTO activity yet')}</div></div>
      <div class="card mt"><div class="card-title">Overdue DORs</div>${over.length ? `<div class="tr-grid">${over.map(card).join('')}</div>` : empty('Every trainee has a recent DOR 👍')}</div>`;
    wireCards(box, () => go('training', 'stats'));
  }

  // ---------------------------------------------------------------- one trainee's file
  async function fileView(charId, self, quiet) {
    const box = $('#t-body'); if (!box) return;
    if (!quiet) box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('ftoFile', { charId });
    if (!$('#t-body') || box !== $('#t-body')) return;
    if (quiet && (box.dataset.file !== String(charId) || !$('#tf-phs', box))) return;   // they moved on
    const restore = quiet ? keepScroll(box) : () => {};
    if (!r.ok) { box.innerHTML = `${self ? '' : backBtn()}${empty(r.why, '🎓')}`; wireBack(box); return; }
    const F = r.data, t = F.trainee, P = H.program, f = flags(), me = S.ctx.me.charId;
    const ro = F.readOnly || self || f.ro || t.charId === me;
    const training = t.status === 'training', pr = t.progress;
    const signed = F.signed || {};
    const avg = {}, last = {};
    (P.ratings || []).forEach((k) => {
      const v = F.sessions.map((s) => (s.ratings || {})[k]).filter(Boolean);
      if (v.length) { avg[k] = v.reduce((a, b) => a + b, 0) / v.length; last[k] = v[0]; }
    });
    S.ftoOpen = S.ftoOpen || {};
    if (!S.ftoOpen[charId]) S.ftoOpen[charId] = new Set(pr.current ? [pr.current] : []);
    const openSet = S.ftoOpen[charId];
    const itemLbl = {}; P.phases.forEach((ph) => ph.items.forEach((it) => { itemLbl[it.key] = it.label; }));
    const canSign = training && !ro && (f.fto || f.mgr);
    const itemHtml = (it) => {
      const sg = signed[it.key];
      return `<div class="tr-it${sg ? ' on' : ''}" data-it="${it.key}"><span class="tr-ck">${sg ? '✓' : ''}</span><div class="li-main"><span>${esc(it.label)}</span>${sg ? `<span class="hint">Signed off by ${esc(sg.byName || '#' + sg.by)} · ${date(sg.at)}${sg.sessionId ? ' · DOR #' + sg.sessionId : ''}</span>` : ''}</div>
                ${canSign && !sg ? `<button class="btn small accent-ghost" data-sign="${it.key}">Sign off</button>` : ''}${canSign && sg && (sg.by === me || f.mgr) ? `<button class="btn small ghost" data-unsign="${it.key}" title="Take this sign-off back">Undo</button>` : ''}</div>`;
    };
    const phCount = (ph) => ({ done: ph.items.filter((it) => signed[it.key]).length, total: ph.items.length });
    box.innerHTML = `${self ? '' : backBtn()}
      <div class="tr-hero"><div class="tr-av big">${esc(initials(t.name))}</div>
        <div class="li-main"><div class="v-title">${esc(t.name)} ${statusPill(t)}</div>
          <div class="hint">${esc(t.roleName || '')}${t.hiredAt ? ' · in training since ' + date(t.hiredAt) : ''}${t.daysInTraining != null ? ' · ' + t.daysInTraining + ' day' + (t.daysInTraining === 1 ? '' : 's') : ''}</div>
          <div class="tr-meta"><span>👤 FTO: ${t.ftoName ? `<a class="lnk" data-officer="${t.ftoCharId}"><b>${esc(t.ftoName)}</b></a>` : '<span class="txt-warn">none yet</span>'}</span><span>📝 ${t.sessions} DOR${t.sessions === 1 ? '' : 's'}</span><span>⏱ ${hrs(t.minutes)}</span><span>${training ? dueTxt(t) : ''}</span></div>
          <div class="row wrap mt">${t.charId < 900000000 ? `<button class="btn ghost" data-go-officer="${t.charId}">👤 Profile</button>` : ''}${training && !ro && f.fto ? '<button class="btn accent" id="tf-dor">📝 Write DOR</button>' : ''}
            ${training && !ro && f.fto ? '<button class="btn" id="tf-rec">👍 Recommend promotion</button>' : ''}
            ${training && !ro && f.mgr ? `<select class="small-sel" id="tf-assign"><option value="">${t.ftoCharId ? 'Move to another FTO…' : 'Assign an FTO…'}</option>${(H.ftos || []).filter((x) => x.charId !== t.charId && x.charId !== t.ftoCharId).map((x) => `<option value="${x.charId}">${esc(x.name)}</option>`).join('')}${t.ftoCharId ? '<option value="none">No FTO</option>' : ''}</select>` : ''}
            ${training && !ro && f.fto && !t.ftoCharId && !f.mgr ? '<button class="btn accent-ghost" id="tf-claim">Claim</button>' : ''}
            ${training && !ro && f.mgr ? `<button class="btn ${pr.done === pr.total ? 'accent' : 'ghost'}" id="tf-done">🎓 Final sign-off</button>` : ''}</div></div>
        <div class="tr-hero-r" id="tf-ring">${ring(pr.pct, 96)}<span class="hint">${pr.done} of ${pr.total} items</span></div></div>
      ${t.overdue ? `<div class="tr-alert">⚠ No DOR for <b>${t.daysSinceDor} days</b>. The program asks for one every ${P.dorDays} day${P.dorDays === 1 ? '' : 's'}.</div>` : ''}
      ${self && training ? '<div class="tr-info">This is your training file. Your FTO signs items off as you show them; you can read everything here.</div>' : ''}
      ${!training ? `<div class="tr-done-b">🎓 ${t.status === 'left' ? 'Left the department' : 'Training complete'}${t.doneAt ? ' on ' + date(t.doneAt) : ''}${t.doneByName ? ' · signed off by ' + esc(t.doneByName) : ''}</div>` : ''}
      <div class="tr-cols"><div>
        <div class="card" id="tf-phs"><div class="card-title">Phases</div>${P.phases.map((ph, i) => {
          const pp = pr.phases.find((x) => x.key === ph.key) || { done: 0, total: ph.items.length };
          const full = pp.total && pp.done === pp.total, isOpen = openSet.has(ph.key);
          return `<div class="tr-ph${isOpen ? ' open' : ''}${full ? ' full' : ''}" data-phk="${ph.key}"><button class="tr-ph-h" data-ph="${ph.key}"><span class="tr-ph-n">${full ? '✓' : i + 1}</span><span class="tr-ph-t">${esc(ph.name)}</span>
              <span class="tr-ph-bar"><i style="width:${pp.total ? Math.round((pp.done / pp.total) * 100) : 100}%"></i></span><b>${pp.done}/${pp.total}</b><span class="tr-chev">▾</span></button>
            <div class="tr-ph-b">${ph.items.length ? ph.items.map(itemHtml).join('') : '<div class="hint">No items in this phase</div>'}</div></div>`;
        }).join('')}</div>
      </div><div>
        <div class="card"><div class="card-title">Ratings <span class="hint">average · ▲▼ last DOR</span></div>${(P.ratings || []).map((k) => `<div class="rate-row"><span>${esc(k)}</span><div class="stars">${[1, 2, 3, 4, 5].map((n) => `<i class="${avg[k] && avg[k] >= n - 0.25 ? 'on' : ''}">★</i>`).join('')}</div><span class="hint">${avg[k] ? avg[k].toFixed(1) : '—'}</span>${avg[k] && last[k] !== undefined && F.sessions.length > 1 ? (last[k] > avg[k] + 0.2 ? '<span class="tr-up">▲</span>' : last[k] < avg[k] - 0.2 ? '<span class="tr-down">▼</span>' : '') : ''}</div>`).join('')}</div>
        <div class="card mt"><div class="card-title">Daily Observation Reports</div>${F.sessions.length ? F.sessions.map((s) => {
          const vals = Object.values(s.ratings || {}), a = vals.length ? vals.reduce((x, y) => x + y, 0) / vals.length : 0;
          return `<div class="tr-dor"><div class="row between"><div><b>DOR #${s.id}</b> <span class="pill">${esc(KIND[s.kind] || s.kind)}</span></div><span class="tr-avg" title="Average rating">${a ? a.toFixed(1) + ' ★' : ''}</span></div>
            <div class="hint">${dateTime(s.sessionAt)} · ${s.minutes} min · ${s.ftoCharId ? `<a class="lnk" data-officer="${s.ftoCharId}" title="Officer profile">${esc(s.ftoName || '')}</a>` : esc(s.ftoName || '')}</div>
            <div class="chips mt">${Object.entries(s.ratings || {}).map(([k, n]) => `<span class="pill tr-r${n}">${esc(k)} ${n}</span>`).join('')}</div>
            ${s.notes ? `<div class="narr">${esc(s.notes).replace(/\n/g, '<br>')}</div>` : ''}
            ${(s.signed || []).length ? `<div class="chips mt">${s.signed.map((k) => `<span class="pill on">✓ ${esc(itemLbl[k] || k)}</span>`).join('')}</div>` : ''}
            ${Object.keys(s.checklist || {}).length ? `<div class="chips mt">${Object.keys(s.checklist).map((k) => `<span class="pill">✓ ${esc(k)}</span>`).join('')}</div>` : ''}</div>`;
        }).join('') : empty(training ? 'No DORs yet. The FTO writes one after each shift together.' : 'No DORs')}</div>
        <div class="card mt"><div class="card-title">History</div>${F.history.length ? `<div class="tr-tl">${F.history.map((x) => {
          const a = ACT[x.action] || ['•', x.action];
          return `<div class="tr-tl-i"><span class="tr-tl-d">${a[0]}</span><div class="li-main"><b>${esc(a[1])}</b>${x.detail ? `<span>${esc(x.detail)}</span>` : ''}<span class="hint">${dateTime(x.at)}${x.actorName ? ' · ' + esc(x.actorName) : ''}</span></div></div>`;
        }).join('')}</div>` : empty('Nothing yet')}</div>
      </div></div>`;
    box.dataset.file = String(charId);
    restore();
    wireBack(box);
    const again = () => { home(true).then(() => fileView(charId, self, true)); };
    // sign-offs update the row, the phase bar and the ring in place; a quiet refresh follows once the clicking stops
    let pending = 0, refreshT = null;
    const settle = () => { clearTimeout(refreshT); refreshT = setTimeout(() => { if (!pending) again(); }, 1500); };
    const paint = () => {
      let done = 0, total = 0;
      P.phases.forEach((ph) => {
        const el = $(`[data-phk="${ph.key}"]`, box); if (!el) return;
        const pp = phCount(ph), full = pp.total > 0 && pp.done === pp.total; done += pp.done; total += pp.total;
        el.classList.toggle('full', full);
        $('.tr-ph-n', el).textContent = full ? '✓' : String(P.phases.indexOf(ph) + 1);
        $('.tr-ph-bar i', el).style.width = (pp.total ? Math.round((pp.done / pp.total) * 100) : 100) + '%';
        $('.tr-ph-h > b', el).textContent = `${pp.done}/${pp.total}`;
      });
      const rg = $('#tf-ring', box), pct = total ? Math.round((done / total) * 100) : 0;
      if (rg) rg.innerHTML = `${ring(pct, 96)}<span class="hint">${done} of ${total} items</span>`;
      const fd = $('#tf-done', box); if (fd) { fd.classList.toggle('accent', done === total); fd.classList.toggle('ghost', done !== total); }
    };
    const setRow = (key) => { const row = $(`[data-it="${key}"]`, box); const it = P.phases.flatMap((ph) => ph.items).find((x) => x.key === key); if (row && it) row.outerHTML = itemHtml(it); };
    const flip = async (key, on) => {
      const ph = P.phases.find((x) => x.items.some((it) => it.key === key)); if (!ph) return;
      const was = signed[key], wasFull = phCount(ph).done === ph.items.length;
      if (on) signed[key] = { by: me, byName: S.ctx.me.name || 'you', at: Math.floor(Date.now() / 1000) }; else delete signed[key];
      setRow(key); paint();
      const nowFull = phCount(ph).done === ph.items.length;
      if (on && nowFull && !wasFull) {   // phase finished: fold it, open the next unfinished one
        openSet.delete(ph.key); const el = $(`[data-phk="${ph.key}"]`, box); if (el) el.classList.remove('open');
        const i = P.phases.indexOf(ph), nx = P.phases.slice(i + 1).concat(P.phases.slice(0, i)).find((x) => phCount(x).done < x.items.length);
        if (nx) { openSet.add(nx.key); const ne = $(`[data-phk="${nx.key}"]`, box); if (ne) ne.classList.add('open'); }
      }
      pending++;
      const r = await call('ftoSign', { charId, keys: [key], on });
      pending--;
      if (!said(r, on ? `✓ ${itemLbl[key]}${on && nowFull && !wasFull ? ` · ${ph.name} complete` : ''}` : 'Sign-off taken back')) {
        if (was) signed[key] = was; else delete signed[key];
        setRow(key); paint();
      }
      settle();
    };
    const phs = $('#tf-phs', box);
    if (phs) phs.onclick = async (e) => {
      const h = e.target.closest('[data-ph]'), sb = e.target.closest('[data-sign]'), ub = e.target.closest('[data-unsign]');
      if (sb) { sb.disabled = true; return flip(sb.dataset.sign, true); }
      if (ub) {
        const key = ub.dataset.unsign;
        if (!await confirmBox('Take back this sign-off?', `"${itemLbl[key]}" goes back to open for ${t.name}.`, 'Take back', true)) return;
        return flip(key, false);
      }
      if (h) { const k = h.dataset.ph, el = h.parentElement; if (openSet.has(k)) openSet.delete(k); else openSet.add(k); el.classList.toggle('open', openSet.has(k)); }
    };
    $$('[data-go-officer]', box).forEach((b) => b.onclick = () => go('officer', +b.dataset.goOfficer));
    if ($('#tf-dor')) $('#tf-dor').onclick = () => dorForm(t, again, { signed });
    if ($('#tf-claim')) $('#tf-claim').onclick = (e) => busy(e.currentTarget, async () => { if (said(await call('ftoAssign', { charId }), 'Trainee claimed')) again(); });
    if ($('#tf-assign')) $('#tf-assign').onchange = async (e) => { const s = e.currentTarget; if (!s.value) return; if (said(await call('ftoAssign', { charId, ftoCharId: s.value === 'none' ? false : +s.value }), 'Saved')) again(); };
    if ($('#tf-rec')) $('#tf-rec').onclick = () => modal(`<div class="m-title">Recommend ${esc(t.name)} for promotion</div>
      <p class="hint">Leaders who can promote see this and may promote them now, skipping the rest of the program.</p>
      <div class="field"><label>Why</label><textarea id="rc-why" maxlength="500" placeholder="What they showed you"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="rc-go" data-primary>Recommend</button></div>`, (cardEl, closeIt) => {
      $('#rc-go', cardEl).onclick = (e) => busy(e.currentTarget, async () => { if (said(await call('recommend', { charId, reason: $('#rc-why').value }), 'Recommendation sent to leaders')) { closeIt(); again(); } });
    });
    if ($('#tf-done')) $('#tf-done').onclick = () => completeForm(t, () => go('training', 'all'));
  }
  const backBtn = () => `<div class="tr-back"><button class="btn small ghost" data-tback>← ${esc({ mine: 'My trainees', all: 'All trainees', stats: 'Overview' }[S.ftoTab] || 'Back')}</button></div>`;
  const wireBack = (box) => $$('[data-tback]', box).forEach((b) => b.onclick = () => go('training', S.ftoTab || 'all'));

  // ---------------------------------------------------------------- the DOR
  async function dorForm(t, after, o) {
    o = o || {};
    if (!H || !H.program) await home(true);
    const P = H.program;
    let signed = o.signed;
    if (!signed) { const r = await call('ftoFile', { charId: t.charId }); signed = (r.ok && r.data.signed) || {}; }
    const ratings = {}, pick = new Set();
    const kinds = ['ridealong', 'training', 'evaluation'], k0 = kinds.includes(o.kind) ? o.kind : 'ridealong';
    const d0 = o.at ? new Date(o.at * 1000) : new Date();
    const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    const minD = new Date(Date.now() - 59 * 86400000);
    const openItems = P.phases.map((ph) => ph.items.filter((it) => !signed[it.key]).length);
    const firstOpen = openItems.findIndex((n) => n > 0);
    modal(`<div class="m-title">${esc(o.title || 'Daily Observation Report')}</div>
      <p class="hint">${o.title ? 'Write it up as a DOR for ' : 'Trainee: '}<b>${esc(t.name)}</b>${t.roleName ? ' · ' + esc(t.roleName) : ''}</p>
      <div class="seg mb" id="dr-kind">${kinds.map((k) => `<button data-k="${k}" class="${k === k0 ? 'on' : ''}">${KIND[k]}</button>`).join('')}</div>
      <div class="grid"><div class="field"><label>Date</label><input type="date" id="dr-date" value="${iso(d0)}" max="${iso(new Date())}" min="${iso(minD)}"${o.send ? ' disabled' : ''}></div>
        <div class="field"><label>How long</label><div class="row tr-mins"><input type="number" id="dr-min" min="1" max="1440" value="${o.minutes || 60}"><span class="hint">min</span>
          ${[30, 60, 90, 120, 180].map((m) => `<button class="btn small ghost" data-m="${m}">${m >= 60 ? m / 60 + 'h' : m + 'm'}</button>`).join('')}</div></div></div>
      <div class="field"><label>Ratings <span class="hint">click the stars · 1 unacceptable … 5 excellent</span></label><div class="tr-rates">${P.ratings.map((k) => `<div class="rate-row"><span>${esc(k)}</span><div class="stars pick" data-r="${esc(k)}">${[1, 2, 3, 4, 5].map((n) => `<i data-n="${n}">★</i>`).join('')}</div><span class="hint tr-rt" data-rt="${esc(k)}"></span></div>`).join('')}</div></div>
      <div class="field"><label>Sign off what they showed you <span class="hint" id="dr-cnt"></span></label><div class="tr-dphs">${P.phases.map((ph, i) => `<div class="tr-dph${i === firstOpen ? ' open' : ''}"><button class="tr-dph-h" data-dph><span>${i + 1}. ${esc(ph.name)}</span><span class="hint">${ph.items.length - openItems[i]}/${ph.items.length} signed</span><span class="tr-chev">▾</span></button>
          <div class="tr-dph-b chips">${ph.items.map((it) => `<label class="chip-t"><input type="checkbox" value="${it.key}"${signed[it.key] ? ' checked disabled' : ''}><span>${signed[it.key] ? '✓ ' : ''}${esc(it.label)}</span></label>`).join('')}</div></div>`).join('')}</div></div>
      <div class="field"><label>Notes</label><textarea id="dr-notes" maxlength="4000" rows="5" placeholder="What went well, what to work on, anything the next FTO should know"></textarea></div>
      <div class="row between"><span class="hint" id="dr-sum">Rate at least one category</span><div class="row"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="dr-go" data-primary>Save DOR</button></div></div>`, (cardEl, closeIt) => {
      cardEl.classList.add('wide', 'tr-xwide');
      let kind = k0;
      const sum = () => {
        const nr = Object.keys(ratings).length;
        $('#dr-cnt', cardEl).textContent = pick.size ? `· ${pick.size} selected` : '';
        $('#dr-sum', cardEl).textContent = nr ? `${nr} rating${nr === 1 ? '' : 's'}${pick.size ? ` · signs off ${pick.size} item${pick.size === 1 ? '' : 's'}` : ''}` : 'Rate at least one category';
      };
      $$('#dr-kind [data-k]', cardEl).forEach((b) => b.onclick = () => { kind = b.dataset.k; $$('#dr-kind [data-k]', cardEl).forEach((x) => x.classList.toggle('on', x === b)); });
      $$('[data-m]', cardEl).forEach((b) => b.onclick = () => { $('#dr-min', cardEl).value = b.dataset.m; });
      $$('.stars.pick', cardEl).forEach((row) => {
        const k = row.dataset.r, lab = $$('[data-rt]', cardEl).find((x) => x.dataset.rt === k);
        const show = (n) => { if (lab) lab.innerHTML = n ? `<b>${n}/5</b> ${RATE_TXT[n]}` : ''; };
        $$('i', row).forEach((st) => {
          st.title = `${st.dataset.n} · ${RATE_TXT[+st.dataset.n]}`;
          st.onmouseenter = () => { const n = +st.dataset.n; $$('i', row).forEach((x) => x.classList.toggle('hov', +x.dataset.n <= n)); show(n); };
          st.onclick = () => { const n = +st.dataset.n; ratings[k] = n; $$('i', row).forEach((x) => x.classList.toggle('on', +x.dataset.n <= n)); show(n); sum(); };
        });
        row.onmouseleave = () => { $$('i', row).forEach((x) => x.classList.remove('hov')); show(ratings[k] || 0); };
      });
      $$('[data-dph]', cardEl).forEach((b) => b.onclick = (e) => { e.preventDefault(); b.parentElement.classList.toggle('open'); });
      $$('.tr-dph-b input', cardEl).forEach((i) => i.onchange = () => { if (i.checked) pick.add(i.value); else pick.delete(i.value); sum(); });
      $('#dr-go', cardEl).onclick = (e) => busy(e.currentTarget, async () => {
        const minutes = +$('#dr-min', cardEl).value;
        if (!Object.keys(ratings).length) { M.toast('Rate at least one category', 'bad'); return; }
        if (!(minutes > 0)) { M.toast('How long was it?', 'bad'); return; }
        let at = 0;
        const dv = $('#dr-date', cardEl).value;
        if (!o.send && dv && dv !== iso(new Date())) { const [y, mo, da] = dv.split('-').map(Number); at = Math.floor(new Date(y, mo - 1, da, 12, 0, 0).getTime() / 1000); }
        const payload = { charId: t.charId, kind, minutes, notes: $('#dr-notes', cardEl).value, ratings, signed: Array.from(pick), at };
        if (said(await (o.send ? o.send(payload) : call('ftoLog', payload)), pick.size ? `DOR saved · ${pick.size} item${pick.size === 1 ? '' : 's'} signed off` : 'DOR saved')) { closeIt(); M.loadBadges(); after(); }
      });
    });
  }
  M.dorForm = dorForm;

  // ---------------------------------------------------------------- the final sign-off
  function completeForm(t, after) {
    const P = H.program, pr = t.progress, left = pr.total - pr.done, f = flags();
    const ranks = (H.ranks || []).slice().sort((a, b) => a.level - b.level);
    const grad = ranks.find((r) => r.roleId === P.completeRoleId);
    const others = ranks.filter((r) => r.roleId !== P.completeRoleId && r.roleId !== t.roleId && (S.ctx.staff || r.level < (H.myLevel || 0)));
    modal(`<div class="m-title">Final sign-off: ${esc(t.name)}</div>
      <div class="tr-cf"><span class="tr-cf-n">${pr.pct}%</span><div style="flex:1"><b>${pr.done} of ${pr.total} items signed off</b><div class="hint">${t.sessions} DORs · ${hrs(t.minutes)} with an FTO${t.daysInTraining != null ? ' · ' + t.daysInTraining + ' days in training' : ''}</div>${segBar(t)}</div></div>
      ${left ? `<div class="tr-alert">⚠ ${left} item${left === 1 ? ' is' : 's are'} still open.</div><label class="tr-chk"><input type="checkbox" id="cf-ovr"> Sign off anyway (say why below)</label>` : '<div class="tr-info">Every phase is complete. 🎉</div>'}
      <div class="field mt"><label>Rank</label><div class="tr-opts">
        ${grad ? `<label class="tr-opt"><input type="radio" name="cf-r" value="grad" checked><span><b>Promote to ${esc(grad.name)}</b><span class="hint">The program's graduation rank${P.autoRank ? ', done for you' : ' (needs your Promote right)'}</span></span></label>` : ''}
        ${f.promote && others.length ? `<label class="tr-opt"><input type="radio" name="cf-r" value="other"${grad ? '' : ' checked'}><span><b>Another rank</b> <select class="small-sel" id="cf-role">${others.map((r) => `<option value="${r.roleId}">${esc(r.name)}</option>`).join('')}</select><span class="hint">Uses your own Promote right</span></span></label>` : ''}
        <label class="tr-opt"><input type="radio" name="cf-r" value="keep"${grad || (f.promote && others.length) ? '' : ' checked'}><span><b>Keep ${esc(t.roleName || 'their rank')}</b><span class="hint">Mark training complete only</span></span></label></div></div>
      <div class="field"><label>Note <span class="hint">(optional${left ? ', needed when items are open' : ''})</span></label><textarea id="cf-note" maxlength="300" rows="2" placeholder="Anything for their file"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="cf-go" data-primary>🎓 Complete training</button></div>`, (cardEl, closeIt) => {
      $('#cf-go', cardEl).onclick = (e) => busy(e.currentTarget, async () => {
        const how = ($('input[name="cf-r"]:checked', cardEl) || {}).value || 'keep';
        const d = { charId: t.charId, promote: how !== 'keep', override: !!($('#cf-ovr', cardEl) || {}).checked, note: $('#cf-note', cardEl).value };
        if (how === 'other') d.roleId = +$('#cf-role', cardEl).value;
        if (left && !d.override) { M.toast('Tick "Sign off anyway" or finish the open items first', 'bad'); return; }
        if (said(await call('ftoComplete', d), `${t.name} has completed field training`)) { closeIt(); M.loadBadges(); after(); }
      });
    });
  }

  // ---------------------------------------------------------------- put someone in training (supervisor)
  function startPicker() {
    const inT = new Set((H.list || []).filter((t) => t.status === 'training').map((t) => t.charId));
    const list = (H.members || []).filter((m) => !inT.has(m.charId));
    modal(`<div class="m-title">Put someone in training</div><p class="hint">For members who were here before tracking, transfers, or a retrain. Recruits hired into a recruit rank are added on their own.</p>
      <input id="sp-q" class="mb" placeholder="Search a name…" style="width:100%"><div id="sp-list" class="tr-pick"></div>
      <div class="row end"><button class="btn ghost" data-x>Close</button></div>`, (cardEl, closeIt) => {
      const draw = () => {
        const q = $('#sp-q', cardEl).value.toLowerCase();
        const rows = list.filter((m) => !q || (m.name || '').toLowerCase().includes(q));
        $('#sp-list', cardEl).innerHTML = rows.length ? rows.map((m) => `<div class="li"><div class="tr-av sm">${esc(initials(m.name))}</div><div class="li-main"><b>${esc(m.name)}</b><span class="hint">${esc(m.roleName || '')}${m.callsign ? ' · ' + esc(m.callsign) : ''}</span></div><button class="btn small accent" data-sp="${m.charId}">Start training</button></div>`).join('') : empty('Nobody to add');
        $$('[data-sp]', cardEl).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('ftoStart', { charId: +b.dataset.sp }), 'They are in training now')) { closeIt(); go('training', 'all'); } }));
      };
      $('#sp-q', cardEl).oninput = draw; draw();
    });
  }

  // ---------------------------------------------------------------- the program (view, or edit for supervisors)
  function programView() {
    const box = $('#t-body'); if (!box) return;
    const f = flags(), edit = f.mgr && !f.ro;
    const ranks = (H.ranks || []).slice().sort((a, b) => a.level - b.level);
    const L = H.limits || { phases: 15, items: 25, ratings: 12, label: 80, name: 60 };
    const P = JSON.parse(JSON.stringify(H.program));
    P.recruitRoles = P.recruitRoles || [];
    let dirty = false;
    const mark = () => { dirty = true; S.dirty = true; const b = $('#pg-bar'); if (b) b.classList.add('on'); };
    if (!edit) {
      const rk = (id) => (ranks.find((r) => r.roleId === id) || {}).name || '—';
      box.innerHTML = `<div class="tr-info">Only training supervisors can change the program. This is what every trainee works through.</div>
        <div class="kpis mb"><div class="kpi"><b>${P.phases.length}</b><span>phases</span></div><div class="kpi"><b>${P.phases.reduce((n, p) => n + p.items.length, 0)}</b><span>items</span></div><div class="kpi"><b>${P.dorDays}</b><span>days between DORs</span></div><div class="kpi"><b>${esc(P.completeRoleId ? rk(P.completeRoleId) : '—')}</b><span>graduation rank</span></div></div>
        <div class="card mb"><div class="card-title">Recruit ranks</div><div class="chips">${P.recruitRoles.length ? P.recruitRoles.map((id) => pill(rk(id), 'accent')).join('') : '<span class="hint">Every new hire</span>'}</div></div>
        <div class="tr-pgrid">${P.phases.map((ph, i) => `<div class="card"><div class="card-title">${i + 1}. ${esc(ph.name)}</div>${ph.items.map((it) => `<div class="tr-li">○ ${esc(it.label)}</div>`).join('')}</div>`).join('')}</div>
        <div class="card mt"><div class="card-title">Rating categories</div><div class="chips">${P.ratings.map((r) => pill(r)).join('')}</div></div>`;
      return;
    }
    const draw = () => {
      const restore = keepScroll(box);
      box.innerHTML = `<div class="cols2 mb"><div class="card"><div class="card-title">Rules</div>
          <div class="field"><label>A DOR is due every</label><div class="row"><input type="number" id="pg-days" min="1" max="30" value="${P.dorDays}" style="width:90px"><span class="hint">days. Longer than that without one and the trainee is flagged (Training and Activity).</span></div></div>
          <div class="field"><label>Recruit / probationary ranks <span class="hint">a hire into one of these starts training</span></label><div class="chips">${ranks.map((r) => `<label class="chip-t"><input type="checkbox" data-rr="${r.roleId}"${P.recruitRoles.includes(r.roleId) ? ' checked' : ''}><span>${esc(r.name)}</span></label>`).join('')}</div>
            <span class="hint">${P.recruitRoles.length ? '' : 'None ticked: every new hire starts training.'}</span></div>
          <div class="field"><label>Graduation rank</label><select id="pg-grad"><option value="">Keep their rank</option>${ranks.map((r) => `<option value="${r.roleId}"${P.completeRoleId === r.roleId ? ' selected' : ''}${!S.ctx.staff && r.level >= (H.myLevel || 0) ? ' disabled' : ''}>${esc(r.name)}</option>`).join('')}</select></div>
          <label class="tr-chk"><input type="checkbox" id="pg-auto"${P.autoRank !== false ? ' checked' : ''}> Rank up automatically on the final sign-off <span class="hint">(otherwise the supervisor needs the Promote right)</span></label></div>
        <div class="card"><div class="card-title">Rating categories <span class="hint">1-5 on every DOR · ${P.ratings.length}/${L.ratings}</span></div>
          <div class="chips mb">${P.ratings.map((r, i) => `<span class="tr-tag">${esc(r)}<button data-rdel="${i}" title="Remove">×</button></span>`).join('')}</div>
          ${P.ratings.length < L.ratings ? `<div class="row"><input id="pg-rnew" maxlength="40" placeholder="New category, e.g. Navigation"><button class="btn small" id="pg-radd">Add</button></div>` : ''}</div></div>
        <div class="row between mb"><div class="card-title" style="margin:0">Phases <span class="hint">${P.phases.length}/${L.phases} · items are signed off on DORs; renaming keeps sign-offs</span></div></div>
        <div id="pg-phs">${P.phases.map((ph, i) => `<div class="card tr-pe mb"><div class="tr-pe-h"><span class="tr-ph-n">${i + 1}</span><input data-pn="${i}" maxlength="${L.name}" value="${esc(ph.name)}" placeholder="Phase name">
            <button class="btn small ghost" data-pmv="${i}:-1" ${i === 0 ? 'disabled' : ''} title="Move up">↑</button><button class="btn small ghost" data-pmv="${i}:1" ${i === P.phases.length - 1 ? 'disabled' : ''} title="Move down">↓</button><button class="btn small danger-ghost" data-pdel="${i}" title="Remove phase">✕</button></div>
          ${ph.items.map((it, j) => `<div class="tr-pe-i"><span class="hint">${i + 1}.${j + 1}</span><input data-in="${i}:${j}" maxlength="${L.label}" value="${esc(it.label)}" placeholder="What they must show">
            <button class="btn small ghost" data-imv="${i}:${j}:-1" ${j === 0 ? 'disabled' : ''}>↑</button><button class="btn small ghost" data-imv="${i}:${j}:1" ${j === ph.items.length - 1 ? 'disabled' : ''}>↓</button><button class="btn small danger-ghost" data-idel="${i}:${j}">✕</button></div>`).join('')}
          ${ph.items.length < L.items ? `<button class="btn small accent-ghost" data-iadd="${i}">+ Add item</button>` : ''}</div>`).join('')}</div>
        ${P.phases.length < L.phases ? '<button class="btn accent-ghost" id="pg-padd">+ Add phase</button>' : ''}
        <div class="tr-savebar${dirty ? ' on' : ''}" id="pg-bar"><span>Unsaved changes to the program</span><button class="btn ghost" id="pg-undo">Discard</button><button class="btn accent" id="pg-save">Save program</button></div>`;
      restore();
      $('#pg-days', box).oninput = (e) => { P.dorDays = +e.target.value; mark(); };
      $$('[data-rr]', box).forEach((c) => c.onchange = () => { const id = +c.dataset.rr; P.recruitRoles = c.checked ? P.recruitRoles.concat(id) : P.recruitRoles.filter((x) => x !== id); mark(); });
      $('#pg-grad', box).onchange = (e) => { P.completeRoleId = e.target.value ? +e.target.value : false; mark(); };
      $('#pg-auto', box).onchange = (e) => { P.autoRank = e.target.checked; mark(); };
      $$('[data-rdel]', box).forEach((b) => b.onclick = () => { P.ratings.splice(+b.dataset.rdel, 1); mark(); draw(); });
      const radd = () => { const i = $('#pg-rnew', box); const v = i.value.trim(); if (!v) return; if (!P.ratings.some((r) => r.toLowerCase() === v.toLowerCase())) P.ratings.push(v); mark(); draw(); const n = $('#pg-rnew', box); if (n) n.focus(); };
      if ($('#pg-radd', box)) { $('#pg-radd', box).onclick = radd; $('#pg-rnew', box).onkeydown = (e) => { if (e.key === 'Enter') radd(); }; }
      $$('[data-pn]', box).forEach((i) => i.oninput = () => { P.phases[+i.dataset.pn].name = i.value; mark(); });
      $$('[data-in]', box).forEach((i) => i.oninput = () => { const [a, b] = i.dataset.in.split(':').map(Number); P.phases[a].items[b].label = i.value; mark(); });
      $$('[data-pmv]', box).forEach((b) => b.onclick = () => { const [i, d] = b.dataset.pmv.split(':').map(Number); const x = P.phases.splice(i, 1)[0]; P.phases.splice(i + d, 0, x); mark(); draw(); });
      $$('[data-imv]', box).forEach((b) => b.onclick = () => { const [i, j, d] = b.dataset.imv.split(':').map(Number); const it = P.phases[i].items; const x = it.splice(j, 1)[0]; it.splice(j + d, 0, x); mark(); draw(); });
      $$('[data-pdel]', box).forEach((b) => b.onclick = async () => {
        const ph = P.phases[+b.dataset.pdel];
        if (ph.items.length && !await confirmBox('Remove this phase?', `"${ph.name}" and its ${ph.items.length} items go when you save. Sign-offs on them stop counting.`, 'Remove', true)) return;
        P.phases.splice(+b.dataset.pdel, 1); mark(); draw();
      });
      $$('[data-idel]', box).forEach((b) => b.onclick = () => { const [i, j] = b.dataset.idel.split(':').map(Number); P.phases[i].items.splice(j, 1); mark(); draw(); });
      $$('[data-iadd]', box).forEach((b) => b.onclick = () => { const i = +b.dataset.iadd; P.phases[i].items.push({ label: '' }); mark(); draw(); const ins = $$(`[data-in^="${i}:"]`, box); if (ins.length) ins[ins.length - 1].focus(); });
      if ($('#pg-padd', box)) $('#pg-padd', box).onclick = () => { P.phases.push({ name: '', items: [{ label: '' }] }); mark(); draw(); const ins = $$('[data-pn]', box); ins[ins.length - 1].focus(); };
      $('#pg-undo', box).onclick = () => { S.dirty = false; programView(); };
      $('#pg-save', box).onclick = (e) => busy(e.currentTarget, async () => {
        const bad = P.phases.find((p) => !p.name.trim());
        if (bad) { M.toast('Every phase needs a name', 'bad'); return; }
        const send = { phases: P.phases.map((p) => ({ key: p.key, name: p.name, items: p.items.filter((it) => (it.label || '').trim()).map((it) => ({ key: it.key, label: it.label })) })),
          ratings: P.ratings, dorDays: P.dorDays, recruitRoles: P.recruitRoles, completeRoleId: P.completeRoleId || null, autoRank: P.autoRank !== false };
        if (said(await call('ftoProgramSave', { program: send }), 'Training program saved')) { S.dirty = false; await home(true); programView(); }
      });
    };
    draw();
  }
})();
