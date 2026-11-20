// es_mdt 2.5.0: the EMS side of the MDT (an EMS department's members). Server: mdt/server/ems.lua.
//   EMS dashboard: the medical calls (P1 first) and who is on each, attach & GPS in one press, the crew on duty, the calls
//     you still owe a report for. Patients: blood type, a short note, treatments and bills (whip_jobs), incident reports,
//     custody, a death record. Incident reports, Medical bills (supervisors waive), Death records, Roster & stats.
//   The police side gets a short line only: "Deceased" / "Treated by EMS" on a person, what EMS did on a call.
//   Kept simple on purpose (RP): no vitals, codes, prescriptions or insurance.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, said, busy, ago, date, dateTime, modal, confirmBox, pill, empty, VIEWS, HOOK, toast, money, can, go, statusOf, setBadge } = M;
  const RO = () => !!(S.ctx && S.ctx.readOnly);
  const EMS = () => !!(S.ctx && S.ctx.ems);
  const P = () => (S.ctx && S.ctx.perms) || {};
  const CFG = () => (S.ctx && S.ctx.emsCfg) || { actions: [], bloodTypes: [] };
  const staff = () => !!(S.ctx && S.ctx.staff);
  const ACT_CLS = { treated: 'accent', revived: 'on', transported: 'warn', refused: 'off', dead: 'bad' };
  const actLabel = (k) => { const a = (CFG().actions || []).find((x) => x.key === k); return a ? a.label : k; };
  const actPills = (list) => (list || []).map((k) => pill(actLabel(k), ACT_CLS[k] || '')).join(' ');
  const priTag = (p) => `<span class="em-pri p${p || 3}">P${p || 3}</span>`;
  const KIND_CLS = { revive: 'on', treat: 'accent', desk: 'accent', aid: '', respawn: 'off', note: 'off' };
  const head = (title, sub, right) => `<div class="v-head"><div><div class="v-title">${title}</div>${sub ? `<div class="hint">${sub}</div>` : ''}</div>${right ? `<div class="row">${right}</div>` : ''}</div>`;
  const kpi = (n, label, cls) => `<div class="kpi${cls ? ' ' + cls : ''}"><b>${n}</b><span>${esc(label)}</span></div>`;
  const loading = '<div class="loading-row"><div class="spin"></div></div>';
  const initials = (n) => String(n || '?').split(' ').map((x) => x[0] || '').join('').slice(0, 2).toUpperCase();
  function custodyPill(cu) {
    if (!cu || cu.state === 'unknown') return '';
    if (cu.state === 'jailed') return pill('In jail' + (cu.months ? ' · ' + cu.months + ' mo left' : ''), 'bad');
    if (cu.state === 'cuffed') return pill('In custody (cuffed)', 'warn');
    return pill('Not in custody', 'off');
  }

  // ---------------------------------------------------------------- badges (the calls you owe a report for)
  HOOK.badgesExtra = async () => {
    if (!EMS()) return;
    const r = await call('emsBadges', {});
    if (r.ok && r.data) { S.todo = S.todo || {}; S.todo.emsReports = r.data.reports || 0; setBadge('ems', S.todo.emsReports, 'warn'); setBadge('emsreports', S.todo.emsReports, 'warn'); }
  };

  // ---------------------------------------------------------------- 1) dashboard
  async function myStatus(key) {
    const r = await call('setStatus', { status: key });
    if (said(r, 'Status: ' + statusOf(key).label)) { if (S.ctx.me) S.ctx.me.status = key; if (M.renderFrame) M.renderFrame(); go('ems'); }
  }
  VIEWS.ems = async (v) => {
    if (!v.querySelector('#em-home')) v.innerHTML = head('EMS dashboard', 'Medical calls, the crew on duty and the reports you owe · updates live') + `<div id="em-home">${loading}</div>`;
    const r = await call('emsHome', {});
    if (S.view !== 'ems' || !$('#em-home')) return;
    if (!r.ok) { $('#em-home').innerHTML = empty(r.why || 'Could not load', '✚'); return; }
    const D = r.data, me = S.ctx.onDuty, cnt = D.counts || {};
    const p1 = D.calls.filter((c) => (c.priority || 3) <= 1).length;
    const sts = (S.ctx.config.statuses || []).slice(0, 5);
    $('#em-home').innerHTML = `
      ${me && sts.length ? `<div class="em-status"><span class="lbl">My status</span><div class="seg" id="em-st">${sts.map((s) => `<button data-st="${esc(s.key)}" class="${(D.crew.find((x) => x.me) || {}).status === s.key ? 'on' : ''}" style="--sc:${esc(s.color || '#8a93a6')}"><span class="dot"></span> ${esc(s.label)}</button>`).join('')}</div></div>` : ''}
      ${!me && !staff() ? '<div class="em-banner off">You are off duty. Go on duty at a station (or the Department tab) to take calls.</div>' : ''}
      ${D.needReport.length ? `<div class="em-banner warn"><b>✎ ${D.needReport.length} call${D.needReport.length > 1 ? 's' : ''} without your report</b>
        <div class="em-need">${D.needReport.map((c) => `<button class="btn small" data-rep-call="${c.id}" data-probe-press>${priTag(c.priority)} #${c.id} ${esc(c.title || 'Call')}</button>`).join('')}</div></div>` : ''}
      <div class="kpis">
        ${kpi(D.calls.length, 'Active medical calls', D.calls.length ? 'em-k-hot' : '')}
        ${kpi(p1, 'Priority 1', p1 ? 'em-k-hot' : '')}
        ${kpi(D.crew.length, 'Crew on duty')}
        ${kpi(cnt.reportsToday || 0, 'Reports · 24 h')}
        ${cnt.owed != null ? kpi(money(cnt.owed), (cnt.openBills || 0) + ' open bills') : ''}
      </div>
      <div class="em-grid">
        <div class="card"><div class="card-head"><div class="card-title">Medical calls</div><button class="btn ghost small" id="em-to-disp" data-probe-press>Dispatch board →</button></div>
          <div class="em-calls">${D.calls.length ? D.calls.map((c) => callCard(c, me)).join('') : empty('No active medical calls. Quiet shift.', '✚')}</div></div>
        <div class="em-side">
          <div class="card"><div class="card-title">Crew on duty <span class="hint">${D.crew.length || ''}</span></div>
            ${D.crew.length ? D.crew.map((u) => { const st = statusOf(u.status); return `<div class="li"><span class="em-av" style="--c:${esc(u.color1 || '#c0392b')}">${esc(u.callsign || initials(u.name))}</span>
              <div class="li-main"><b>${esc(u.name)}${u.me ? ' <span class="hint">(you)</span>' : ''}</b><span class="hint">${esc(u.roleName || '')}${u.dept ? ' · ' + esc(u.dept) : ''}${u.callId ? ' · on call #' + u.callId : ''}</span></div>
              <span class="em-st" style="--sc:${esc(st.color || '#8a93a6')}"><span class="dot"></span>${esc(st.label)}</span></div>`; }).join('') : empty('Nobody from EMS is on duty', '◌')}</div>
          <div class="card"><div class="card-head"><div class="card-title">Latest reports</div><button class="btn ghost small" id="em-to-reps" data-probe-press>All →</button></div>
            ${D.recent.length ? D.recent.map(repLi).join('') : empty('No reports yet', '✎')}</div>
        </div>
      </div>`;
    const box = $('#em-home');
    $$('[data-st]', box).forEach((b) => b.onclick = () => myStatus(b.dataset.st));
    $$('[data-rep-call]', box).forEach((b) => b.onclick = () => reportForm({ callId: +b.dataset.repCall }, () => go('ems')));
    $$('[data-attach]', box).forEach((b) => b.onclick = (e) => { e.stopPropagation(); busy(b, async () => { const x = await call('callAttach', { id: +b.dataset.attach, route: true }); if (said(x, 'Attached · en route · GPS set')) go('ems'); }); });
    $$('[data-route]', box).forEach((b) => b.onclick = (e) => { e.stopPropagation(); busy(b, async () => said(await call('callRoute', { id: +b.dataset.route }), 'GPS set to the call')); });
    $$('[data-call-rep]', box).forEach((b) => b.onclick = (e) => { e.stopPropagation(); reportForm({ callId: +b.dataset.callRep }, () => go('ems')); });
    $$('[data-rep]', box).forEach((el) => el.onclick = () => reportView(+el.dataset.rep, () => go('ems')));
    $('#em-to-disp').onclick = () => go('dispatch');
    $('#em-to-reps').onclick = () => go('emsreports');
  };
  function callCard(c, onDuty) {
    const units = c.units || [];
    return `<div class="em-call p${c.priority || 3}${c.mine ? ' mine' : ''}">
      <div class="em-call-top">${priTag(c.priority)}<b>${esc(c.title || 'Call')}</b><span class="hint">#${c.id} · ${ago(c.createdAt)}</span>${c.mine ? pill('On it', 'on') : ''}</div>
      ${c.street ? `<div class="em-call-loc">⌖ ${esc(c.street)}</div>` : ''}
      ${c.message ? `<div class="em-call-msg">${esc(String(c.message).slice(0, 160))}</div>` : ''}
      <div class="em-call-foot"><div class="em-units">${units.length ? units.map((u) => `<span class="em-unit" title="${esc(u.name)}">${esc(u.callsign || initials(u.name))}${u.deptShort ? ' <i>' + esc(u.deptShort) + '</i>' : ''}</span>`).join('') : '<span class="hint">No units yet</span>'}</div>
        <div class="row">${c.mine ? `<button class="btn small" data-route="${c.id}" data-probe-press>⌖ GPS</button><button class="btn small" data-call-rep="${c.id}" data-probe-press>✎ Report</button>`
          : (onDuty && !RO() ? `<button class="btn accent small" data-attach="${c.id}" data-probe-press data-primary>＋ Attach &amp; en route</button>` : '')}</div></div></div>`;
  }
  const repLi = (r) => `<div class="li click" data-rep="${r.id}"><div class="li-main"><b>${esc(r.patientName || 'Unknown patient')} · ${esc(r.what)}</b>
    <span class="hint">#${r.id}${r.callId ? ' · call #' + r.callId : ''} · ${esc(r.byName || '')} · ${ago(r.createdAt)}</span></div><div class="em-acts">${actPills(r.actionsList)}</div></div>`;

  // ---------------------------------------------------------------- 2) patients
  VIEWS.patients = async (v, arg) => {
    v.innerHTML = head('Patients', 'Blood type, a short note, treatments, bills and reports · police records stay with the police') + `
      <div class="split wide"><div class="split-list"><input type="text" id="em-pq" placeholder="Name, phone or ID…" autocomplete="off" maxlength="60" value="${esc(S.emPq || '')}">
        <div class="res-list" id="em-plist">${loading}</div></div><div class="split-detail" id="em-pd">${empty('Pick a patient', '♥')}</div></div>`;
    const list = $('#em-plist');
    const draw = (rows, title) => {
      list.innerHTML = (title ? `<div class="lbl em-lh">${esc(title)}</div>` : '') + (rows.length ? rows.map((p) => `<div class="res click${S.emPid === p.charId ? ' on' : ''}" data-pid="${p.charId}">
        <div><b>${esc(p.name || 'Unknown')}</b><div class="hint">#${p.charId}${p.dob ? ' · ' + esc(p.dob) : ''}${p.last ? ' · seen ' + ago(p.last) : ''}</div></div>
        <div class="res-tags">${p.deceased ? pill('Deceased', 'bad') : ''}${p.n ? pill(p.n + ' report' + (p.n > 1 ? 's' : ''), 'off') : ''}</div></div>`).join('') : empty(title ? 'No patients yet' : 'Nobody found', '♥'));
      $$('[data-pid]', list).forEach((el) => el.onclick = () => { S.emPid = +el.dataset.pid; $$('[data-pid]', list).forEach((x) => x.classList.toggle('on', x === el)); patient(S.emPid); });
    };
    const load = async () => {
      const q = (S.emPq || '').trim();
      if (q.length < 2) { const r = await call('emsRecent', {}); if (S.view === 'patients') draw((r.ok && r.data) || [], 'Recent patients'); return; }
      const r = await call('emsPeople', { q });
      if (S.view === 'patients') draw((r.ok && r.data) || []);
    };
    let t = null;
    $('#em-pq').oninput = (e) => { clearTimeout(t); t = setTimeout(() => { S.emPq = e.target.value; load(); }, 220); };
    load();
    if (arg) S.emPid = +arg;
    if (S.emPid) patient(S.emPid);
  };

  async function patient(cid) {
    const box = $('#em-pd'); if (!box) return;
    box.innerHTML = loading;
    const r = await call('emsPatient', { charId: cid });
    if (!$('#em-pd') || S.emPid !== cid) return;
    if (!r.ok) { box.innerHTML = empty(r.why || 'Could not load', '♥'); return; }
    const p = r.data, d = p.death, reload = () => patient(cid);
    const bloods = CFG().bloodTypes || [];
    box.innerHTML = `
      ${d ? `<div class="em-dead"><span class="em-dead-ico">✝</span><div><b>Deceased</b> · ${esc(d.cause)}<div class="hint">${dateTime(d.diedAt || d.createdAt)}${d.place ? ' · ' + esc(d.place) : ''} · recorded by ${esc(d.byName || '—')}${d.dept ? ' (' + esc(d.dept) + ')' : ''}</div></div>
        ${p.canDeath ? `<button class="btn small" id="em-undo" data-probe-press>Undo</button>` : ''}</div>` : ''}
      <div class="prof-head em-prof">
        <div class="portrait">${p.portrait ? `<img src="${p.portrait}" alt="">` : `<span>${esc(initials(p.name))}</span>`}</div>
        <div class="prof-main"><div class="v-title">${esc(p.name)}</div>
          <div class="facts"><span><i>ID</i>#${p.charId}</span><span><i>Born</i>${esc(p.dob || '—')}</span><span><i>Sex</i>${esc(p.gender || '—')}</span><span><i>Phone</i>${esc(p.phone || '—')}</span></div>
          <div class="res-tags">${p.owed ? pill(money(p.owed) + ' owed', 'warn') : ''}${custodyPill(p.custody)}${d ? pill('Deceased', 'bad') : ''}</div></div>
        <div class="em-blood" title="${p.bloodSet ? 'Blood type on file' : 'Blood type (from their ID; set it when you know)'}"><span>Blood</span><b>${esc(p.blood || '?')}</b>${p.bloodSet ? '' : '<i>unconfirmed</i>'}</div>
        <div class="prof-actions">
          ${can('ems_reports') ? '<button class="btn accent small" id="em-p-rep" data-probe-press data-primary>✎ Incident report</button>' : ''}
          ${p.canDeath && !d ? '<button class="btn small danger" id="em-p-dead" data-probe-press>✝ Record death</button>' : ''}
        </div></div>
      ${d && d.autopsy ? autopsyCard(d) : d && d.caseNumber ? `<div class="card"><div class="card-title">Post-mortem</div><div class="hint">Linked to case ${esc(d.caseNumber)}; the report is no longer in the MDT.</div></div>` : ''}
      <div class="cols2">
        <div class="card"><div class="card-title">Medical info</div>
          <div class="field"><label>Blood type</label><div class="seg em-bt" id="em-bt">${bloods.map((b) => `<button data-bt="${esc(b)}" class="${p.bloodSet && p.blood === b ? 'on' : ''}"${p.canEdit ? '' : ' disabled'}>${esc(b)}</button>`).join('')}</div></div>
          <div class="field"><label>Note <span class="hint">allergies, conditions, anything the next medic should know</span></label>
            <textarea id="em-note" rows="3" maxlength="300" placeholder="e.g. allergic to penicillin, asthma"${p.canEdit ? '' : ' disabled'}>${esc(p.note || '')}</textarea></div>
          <div class="row between"><span class="hint">${p.noteBy ? 'Updated by ' + esc(p.noteBy) + ' · ' + ago(p.noteAt) : ''}</span>${p.canEdit ? '<button class="btn small" id="em-save" data-probe-press>Save</button>' : ''}</div></div>
        <div class="card"><div class="card-head"><div class="card-title">Open bills</div>${p.owed ? `<b class="txt-warn">${money(p.owed)}</b>` : ''}</div>
          ${!p.med ? empty('Bills come from the job pack (whip_jobs 0.6.0+): not running', '＄') : p.bills.length ? p.bills.map((b) => `<div class="li"><div class="li-main"><b>${money(b.amount)} · ${esc(b.reason || 'Medical care')}</b><span class="hint">#${b.id}${b.dept ? ' · ' + esc(b.dept) : ''} · ${ago(b.at)}</span></div>
            ${p.canWaive ? `<button class="btn small ghost" data-waive="${b.id}" data-amt="${b.amount}" data-probe-press>Waive</button>` : ''}</div>`).join('') : empty('Nothing owed', '✓')}</div>
      </div>
      <div class="card"><div class="card-title">Treatments <span class="hint">${p.records.length || ''}</span></div>
        ${!p.med ? empty('Treatments come from the job pack (whip_jobs): not running', '✚') : p.records.length ? p.records.slice(0, 15).map((x) => `<div class="li"><span class="em-kind">${pill(x.kindLabel || x.kind, KIND_CLS[x.kind] || '')}</span>
          <div class="li-main"><b>${esc([x.injury, x.treatment].filter(Boolean).join(' → ') || x.kindLabel || x.kind)}</b><span class="hint">${esc(x.by || '—')}${x.dept ? ' · ' + esc(x.dept) : ''}${x.place ? ' · ' + esc(x.place) : ''} · ${ago(x.at)}${x.bill ? ' · billed ' + money(x.bill) : ''}</span>${x.notes ? `<span class="em-note-line">${esc(x.notes)}</span>` : ''}</div></div>`).join('') : empty('No treatments on file', '✚')}</div>
      <div class="card"><div class="card-title">Incident reports <span class="hint">${p.reports.length || ''}</span></div>${p.reports.length ? p.reports.map(repLi).join('') : empty('No reports on this patient', '✎')}</div>`;
    let blood = p.bloodSet ? p.blood : '';
    $$('[data-bt]', box).forEach((b) => b.onclick = () => { blood = blood === b.dataset.bt ? '' : b.dataset.bt; $$('[data-bt]', box).forEach((x) => x.classList.toggle('on', x.dataset.bt === blood)); });
    if ($('#em-save', box)) $('#em-save', box).onclick = (e) => busy(e.currentTarget, async () => { if (said(await call('emsPatientSave', { charId: cid, blood, note: $('#em-note', box).value }), 'Saved')) reload(); });
    if ($('#em-p-rep', box)) $('#em-p-rep', box).onclick = () => reportForm({ charId: cid, patientName: p.name }, reload);
    if ($('#em-p-dead', box)) $('#em-p-dead', box).onclick = () => deathForm({ charId: cid, name: p.name }, reload);
    if ($('#em-undo', box)) $('#em-undo', box).onclick = () => undoDeath(d, reload);
    $$('[data-waive]', box).forEach((b) => b.onclick = () => waive(+b.dataset.waive, +b.dataset.amt, p.name, reload));
    $$('[data-rep]', box).forEach((el) => el.onclick = () => reportView(+el.dataset.rep, reload));
  }
  function autopsyCard(d) {
    const a = d.autopsy;
    return `<div class="card em-pm"><div class="card-head"><div class="card-title">Post-mortem report</div><span class="hint">case ${esc(d.caseNumber || '#' + a.caseId)}</span></div>
      <div class="facts"><span><i>Title</i>${esc(a.title || 'Post-mortem')}</span>${a.examinedAt ? `<span><i>Examined</i>${dateTime(a.examinedAt)}</span>` : ''}${a.examinedBy ? `<span><i>By</i>${esc(a.examinedBy)}</span>` : ''}${a.street ? `<span><i>Where</i>${esc(a.street)}</span>` : ''}${a.fatal ? `<span><i>Fatal</i>${esc(a.fatal)}</span>` : ''}</div>
      ${a.text ? `<p class="em-pm-text">${esc(a.text)}</p>` : ''}</div>`;
  }

  // ---------------------------------------------------------------- 3) incident reports
  async function reportForm(pre, done) {
    pre = pre || {};
    let F = { actions: CFG().actions || [] };
    if (pre.callId) { const r = await call('emsReportForm', { callId: pre.callId }); if (!said(r)) return; F = r.data; }
    const k = F.call;
    let patient = pre.charId ? { charId: pre.charId, name: pre.patientName } : (k && k.callerCharId ? { charId: k.callerCharId, name: k.callerName } : null);
    const sel = new Set(pre.actions || []);
    const edit = !!pre.id;
    modal(`<div class="m-title">${edit ? 'Edit report #' + pre.id : 'EMS incident report'}</div>
      ${k ? `<div class="em-m-call">${priTag(k.priority)} <b>#${k.id} ${esc(k.title || 'Call')}</b><span class="hint">${esc(k.street || '')} · ${ago(k.createdAt)}</span></div>` : ''}
      <div class="field"><label>Patient</label><div id="em-f-pat"></div></div>
      <div class="field"><label>What happened</label><input type="text" id="em-f-what" maxlength="200" placeholder="e.g. Car crash on the highway, driver unconscious" value="${esc(pre.what || '')}"></div>
      <div class="field"><label>What was done</label><div class="chips" id="em-f-acts">${(F.actions || []).map((a) => `<label class="chip-t em-act a-${esc(a.key)}"><input type="checkbox" value="${esc(a.key)}"${sel.has(a.key) ? ' checked' : ''}><span>${esc(a.label)}</span></label>`).join('')}</div></div>
      <div class="field"><label>Notes <span class="hint">optional, one or two lines</span></label><textarea id="em-f-note" rows="2" maxlength="500" placeholder="Anything else worth writing down">${esc(pre.note || '')}</textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="em-f-save" data-primary>${edit ? 'Save' : 'File report'}</button></div>`,
    (card, closeIt) => {
      card.classList.add('wide');
      const host = $('#em-f-pat', card);
      const drawPat = () => {
        if (patient) {
          host.innerHTML = `<div class="em-picked"><b>${esc(patient.name || '#' + patient.charId)}</b><span class="hint">#${patient.charId || '—'}</span><button class="btn ghost small" id="em-f-clear" data-probe-press>Change</button></div>`;
          $('#em-f-clear', host).onclick = () => { patient = null; drawPat(); };
        } else {
          host.innerHTML = '<div id="em-f-pp"></div><input type="text" id="em-f-pname" maxlength="80" placeholder="…or a name / description if unknown (e.g. Unknown male, 30s)" value="' + esc(pre.charId ? '' : (pre.patientName || '')) + '">';
          M.personPicker($('#em-f-pp', host), 'Search the patient: name, phone or ID…', (x) => { patient = x; drawPat(); }, 'emsPeople');
        }
      };
      drawPat();
      $('#em-f-save', card).onclick = (e) => busy(e.currentTarget, async () => {
        const acts = $$('#em-f-acts input', card).filter((i) => i.checked).map((i) => i.value);
        const body = { id: pre.id, callId: k ? k.id : null, charId: patient ? patient.charId : null, patientName: patient ? patient.name : (($('#em-f-pname', card) || {}).value || ''),
          what: $('#em-f-what', card).value, actions: acts, note: $('#em-f-note', card).value };
        const r = await call('emsReportSave', body);
        if (said(r, edit ? 'Report saved' : 'Report filed' + (k ? ' on call #' + k.id : ''))) { closeIt(); M.loadBadges && M.loadBadges(); if (done) done(r.data); }
      });
    });
  }
  async function reportView(id, done) {
    const r = await call('emsReport', { id });
    if (!said(r)) return;
    const x = r.data;
    modal(`<div class="m-title">EMS report #${x.id}</div>
      <div class="facts em-rv"><span><i>Patient</i>${x.charId ? `<a class="em-link" data-go-p="${x.charId}">${esc(x.patientName || '#' + x.charId)}</a>` : esc(x.patientName || 'Unknown')}</span>
        ${x.call ? `<span><i>Call</i>${priTag(x.call.priority)} #${x.call.id} ${esc(x.call.title || '')}</span>` : ''}${x.street ? `<span><i>Where</i>${esc(x.street)}</span>` : ''}
        <span><i>By</i>${esc(x.byName || '—')}${x.deptShort ? ' · ' + esc(x.deptShort) : ''}</span><span><i>When</i>${dateTime(x.createdAt)}${x.updatedAt && x.updatedAt - x.createdAt > 60 ? ' (edited)' : ''}</span></div>
      <div class="field"><label>What happened</label><div class="em-rv-txt">${esc(x.what)}</div></div>
      <div class="field"><label>What was done</label><div>${actPills(x.actionsList) || '<span class="hint">—</span>'}</div></div>
      ${x.note ? `<div class="field"><label>Notes</label><div class="em-rv-txt">${esc(x.note)}</div></div>` : ''}
      <div class="row end"><button class="btn ghost" data-x>Close</button>${x.canEdit ? '<button class="btn accent" id="em-rv-edit" data-primary>Edit</button>' : ''}</div>`,
    (card, closeIt) => {
      if ($('[data-go-p]', card)) $('[data-go-p]', card).onclick = () => { closeIt(); S.emPid = x.charId; go('patients', x.charId); };
      if ($('#em-rv-edit', card)) $('#em-rv-edit', card).onclick = () => { closeIt(); setTimeout(() => reportForm({ id: x.id, charId: x.charId, patientName: x.patientName, what: x.what, actions: x.actionsList, note: x.note }, done), 170); };
    });
  }
  M.emsReportForm = reportForm;

  VIEWS.emsreports = async (v) => {
    S.emRs = S.emRs || 'dept';
    v.innerHTML = head('Incident reports', 'A short report after each call: what happened and what was done. It shows on the call and the patient.',
      can('ems_reports') ? '<button class="btn accent" id="em-new" data-probe-press data-primary>＋ New report</button>' : '') + `
      <div id="em-rneed"></div>
      <div class="tabs" id="ems-tabs">${[['dept', 'Department'], ['mine', 'Mine'], ['all', 'All EMS']].map(([k, l]) => `<button class="tab${S.emRs === k ? ' on' : ''}" data-rs="${k}">${l}</button>`).join('')}</div>
      <div class="filters"><input type="text" id="em-rq" placeholder="Patient, what happened, medic or call no.…" autocomplete="off" maxlength="60" value="${esc(S.emRq || '')}"></div>
      <div class="card flush" id="em-rlist">${loading}</div>`;
    const load = async () => {
      const r = await call('emsReports', { scope: S.emRs, q: S.emRq || '' });
      if (S.view !== 'emsreports' || !$('#em-rlist')) return;
      if (!r.ok) { $('#em-rlist').innerHTML = empty(r.why || 'Could not load', '✎'); return; }
      const D = r.data;
      $('#em-rneed').innerHTML = D.needReport.length ? `<div class="em-banner warn"><b>✎ Calls waiting for your report</b><div class="em-need">${D.needReport.map((c) => `<button class="btn small" data-rep-call="${c.id}" data-probe-press>${priTag(c.priority)} #${c.id} ${esc(c.title || 'Call')} · ${ago(c.createdAt)}</button>`).join('')}</div></div>` : '';
      $('#em-rlist').innerHTML = D.reports.length ? `<div class="em-table"><div class="em-tr th"><span>No.</span><span>Patient</span><span>What happened</span><span>Done</span><span>Medic</span><span>When</span></div>
        ${D.reports.map((x) => `<div class="em-tr click" data-rep="${x.id}"><span class="hint">#${x.id}${x.callId ? '<br>call #' + x.callId : ''}</span><span><b>${esc(x.patientName || 'Unknown')}</b></span><span>${esc(x.what)}</span><span>${actPills(x.actionsList)}</span><span>${esc(x.byName || '')}<br><span class="hint">${esc(x.deptShort || '')}</span></span><span class="hint">${ago(x.createdAt)}</span></div>`).join('')}</div>`
        : empty(S.emRs === 'mine' ? 'You have not written a report yet' : 'No reports', '✎');
      $$('[data-rep]', v).forEach((el) => el.onclick = () => reportView(+el.dataset.rep, load));
      $$('[data-rep-call]', v).forEach((b) => b.onclick = () => reportForm({ callId: +b.dataset.repCall }, load));
    };
    $$('[data-rs]', v).forEach((b) => b.onclick = () => { S.emRs = b.dataset.rs; $$('[data-rs]', v).forEach((x) => x.classList.toggle('on', x === b)); load(); });
    let t = null;
    $('#em-rq').oninput = (e) => { clearTimeout(t); t = setTimeout(() => { S.emRq = e.target.value.trim(); load(); }, 250); };
    if ($('#em-new')) $('#em-new').onclick = () => reportForm({}, load);
    load();
  };

  // ---------------------------------------------------------------- 4) bills
  function waive(id, amount, name, done) {
    modal(`<div class="m-title">Waive bill #${id}</div><p class="m-text">${esc(name || 'The patient')} will no longer owe <b>${money(amount)}</b> for this bill. It is logged.</p>
      <div class="field"><label>Reason <span class="hint">optional</span></label><input type="text" id="em-w-note" maxlength="120" placeholder="e.g. Charity case, wrong bill"></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="em-w-yes" data-primary>Waive ${money(amount)}</button></div>`,
    (card, closeIt) => {
      $('#em-w-yes', card).onclick = (e) => busy(e.currentTarget, async () => { if (said(await call('emsBillWaive', { id, note: $('#em-w-note', card).value }), 'Bill waived')) { closeIt(); if (done) done(); } });
    });
  }
  VIEWS.bills = async (v) => {
    S.emBs = S.emBs || 'unpaid';
    v.innerHTML = head('Medical bills', 'What patients owe for EMS care (billed in the field or at the hospital)') + `
      <div id="em-bk"></div>
      <div class="tabs" id="ems-tabs">${[['unpaid', 'Open'], ['paid', 'Paid'], ['waived', 'Waived'], ['all', 'All']].map(([k, l]) => `<button class="tab${S.emBs === k ? ' on' : ''}" data-bs="${k}">${l}</button>`).join('')}</div>
      <div class="card flush" id="em-blist">${loading}</div>`;
    const load = async () => {
      const r = await call('emsBills', { status: S.emBs });
      if (S.view !== 'bills' || !$('#em-blist')) return;
      if (!r.ok) { $('#em-blist').innerHTML = empty(r.why || 'Could not load', '＄'); return; }
      const D = r.data;
      if (!D.med) { $('#em-blist').innerHTML = empty('Bills come from the job pack (whip_jobs 0.6.0+), which is not running', '＄'); return; }
      $('#em-bk').innerHTML = `<div class="kpis">${kpi(money(D.owed), 'Owed (open bills)')}${kpi(D.people, 'Patients who owe')}${kpi(D.bills.length, S.emBs === 'unpaid' ? 'Open bills' : 'Bills shown')}</div>`;
      const stp = (s) => s === 'unpaid' ? pill('Open', 'warn') : s === 'paid' ? pill('Paid', 'on') : pill('Waived', 'off');
      $('#em-blist').innerHTML = D.bills.length ? `<div class="em-table bills"><div class="em-tr th"><span>No.</span><span>Patient</span><span>For</span><span class="num">Amount</span><span>Status</span><span></span></div>
        ${D.bills.map((b) => `<div class="em-tr"><span class="hint">#${b.id}</span><span><a class="em-link" data-go-p="${b.charId}">${esc(b.name || '#' + b.charId)}</a></span><span>${esc(b.reason || 'Medical care')}<br><span class="hint">${esc(b.dept || '')} · ${ago(b.at)}</span></span><span class="num"><b>${money(b.amount)}</b></span><span>${stp(b.status)}</span>
          <span>${D.canWaive && b.status === 'unpaid' ? `<button class="btn small ghost" data-waive="${b.id}" data-amt="${b.amount}" data-name="${esc(b.name || '')}" data-probe-press>Waive</button>` : ''}</span></div>`).join('')}</div>`
        : empty(S.emBs === 'unpaid' ? 'Nobody owes anything' : 'Nothing here', '✓');
      $$('[data-waive]', v).forEach((b) => b.onclick = () => waive(+b.dataset.waive, +b.dataset.amt, b.dataset.name, load));
      $$('[data-go-p]', v).forEach((a) => a.onclick = () => { S.emPid = +a.dataset.goP; go('patients', +a.dataset.goP); });
    };
    $$('[data-bs]', v).forEach((b) => b.onclick = () => { S.emBs = b.dataset.bs; $$('[data-bs]', v).forEach((x) => x.classList.toggle('on', x === b)); load(); });
    load();
  };

  // ---------------------------------------------------------------- 5) deaths
  async function deathForm(pre, done) {
    const ar = await call('emsAutopsies', {});
    const autopsies = (ar.ok && ar.data) || [];
    let person = pre && pre.charId ? pre : null, pick = null;
    const AGO = [[0, 'Just now'], [15, '15 min ago'], [30, '30 min ago'], [60, '1 h ago'], [180, '3 h ago'], [720, '12 h ago'], [1440, 'Yesterday']];
    modal(`<div class="m-title">Record a death</div><p class="m-text">The character is marked deceased in the MDT; police see it on their record. A supervisor can undo it.</p>
      <div class="field"><label>Who</label><div id="em-d-who"></div></div>
      <div class="field"><label>Cause of death</label><input type="text" id="em-d-cause" maxlength="200" placeholder="e.g. Multiple gunshot wounds"></div>
      <div class="cols2"><div class="field"><label>Where <span class="hint">optional</span></label><input type="text" id="em-d-place" maxlength="120" placeholder="e.g. Grove Street"></div>
        <div class="field"><label>When</label><div class="seg" id="em-d-when">${AGO.map(([m, l], i) => `<button data-ago="${m}" class="${i === 0 ? 'on' : ''}">${l}</button>`).join('')}</div></div></div>
      <div class="field"><label>Post-mortem report <span class="hint">whip_evidence reports uploaded to an MDT case</span></label>
        <div class="em-pm-list" id="em-d-pm"><div class="em-pm-row on" data-pm=""><b>None</b><span class="hint">no post-mortem (yet)</span></div>
        ${autopsies.map((a, i) => `<div class="em-pm-row" data-pm="${i}"><b>${esc(a.title || 'Post-mortem')}</b><span class="hint">case ${esc(a.caseNumber || '#' + a.caseId)}${a.street ? ' · ' + esc(a.street) : ''} · ${ago(a.examinedAt || a.uploadedAt)}</span></div>`).join('')}</div></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn danger" id="em-d-save" data-primary>✝ Record death</button></div>`,
    (card, closeIt) => {
      card.classList.add('wide');
      const host = $('#em-d-who', card);
      const drawWho = () => {
        if (person) { host.innerHTML = `<div class="em-picked"><b>${esc(person.name)}</b><span class="hint">#${person.charId}</span>${pre && pre.charId ? '' : '<button class="btn ghost small" id="em-d-ch" data-probe-press>Change</button>'}</div>`; if ($('#em-d-ch', host)) $('#em-d-ch', host).onclick = () => { person = null; drawWho(); }; }
        else M.personPicker(host, 'Search: name, phone or ID…', (x) => { person = x; drawWho(); }, 'emsPeople');
      };
      drawWho();
      let agoMin = 0;
      $$('[data-ago]', card).forEach((b) => b.onclick = () => { agoMin = +b.dataset.ago; $$('[data-ago]', card).forEach((x) => x.classList.toggle('on', x === b)); });
      $$('[data-pm]', card).forEach((el) => el.onclick = () => { pick = el.dataset.pm === '' ? null : autopsies[+el.dataset.pm]; $$('[data-pm]', card).forEach((x) => x.classList.toggle('on', x === el)); });
      $('#em-d-save', card).onclick = (e) => busy(e.currentTarget, async () => {
        if (!person) { toast('Pick the person', 'err'); return; }
        const r = await call('emsDeathSave', { charId: person.charId, cause: $('#em-d-cause', card).value, place: $('#em-d-place', card).value,
          diedAt: Math.floor(Date.now() / 1000) - agoMin * 60, caseId: pick ? pick.caseId : null, ref: pick ? pick.ref : '' });
        if (said(r, 'Death recorded')) { closeIt(); if (done) done(); }
      });
    });
  }
  function undoDeath(d, done) {
    modal(`<div class="m-title">Undo death record #${d.id}</div><p class="m-text">${esc(d.name || '')} is no longer marked deceased. The record is kept, struck out.</p>
      <div class="field"><label>Why</label><input type="text" id="em-u-note" maxlength="200" placeholder="e.g. Revived at Pillbox, recorded by mistake"></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="em-u-yes" data-primary>Undo</button></div>`,
    (card, closeIt) => { $('#em-u-yes', card).onclick = (e) => busy(e.currentTarget, async () => { if (said(await call('emsDeathRevoke', { id: d.id, note: $('#em-u-note', card).value }), 'Undone')) { closeIt(); if (done) done(); } }); });
  }
  VIEWS.deaths = async (v) => {
    v.innerHTML = head('Death records', 'Characters marked deceased, with the post-mortem report when there is one. Police see these.',
      '<label class="chip-t"><input type="checkbox" id="em-dall"' + (S.emDall ? ' checked' : '') + '><span>Show undone</span></label><span id="em-dnew"></span>') + `<div id="em-dlist">${loading}</div>`;
    const load = async () => {
      const r = await call('emsDeaths', { all: !!S.emDall });
      if (S.view !== 'deaths' || !$('#em-dlist')) return;
      if (!r.ok) { $('#em-dlist').innerHTML = empty(r.why || 'Could not load', '✝'); return; }
      const D = r.data;
      $('#em-dnew').innerHTML = D.canDeath ? '<button class="btn danger" id="em-dn" data-probe-press data-primary>✝ Record a death</button>' : '';
      if ($('#em-dn')) $('#em-dn').onclick = () => deathForm(null, load);
      $('#em-dlist').innerHTML = D.deaths.length ? `<div class="em-deaths">${D.deaths.map((x) => `<div class="em-death${x.revokedAt ? ' gone' : ''}">
        <div class="em-death-ico">✝</div><div class="li-main"><b><a class="em-link" data-go-p="${x.charId}">${esc(x.name || '#' + x.charId)}</a> · ${esc(x.cause)}</b>
          <span class="hint">${dateTime(x.diedAt || x.createdAt)}${x.place ? ' · ' + esc(x.place) : ''} · by ${esc(x.byName || '—')}${x.dept ? ' (' + esc(x.dept) + ')' : ''}${x.caseNumber ? ' · post-mortem in case ' + esc(x.caseNumber) : ''}</span>
          ${x.revokedAt ? `<span class="hint">Undone by ${esc(x.revokedBy || '—')} ${ago(x.revokedAt)}${x.revokeNote ? ': ' + esc(x.revokeNote) : ''}</span>` : ''}</div>
        ${x.caseNumber ? pill('Post-mortem', 'accent') : ''}${x.revokedAt ? pill('Undone', 'off') : D.canDeath ? `<button class="btn small ghost" data-undo="${x.id}" data-probe-press>Undo</button>` : ''}</div>`).join('')}</div>`
        : empty('No death records', '✝');
      $$('[data-go-p]', v).forEach((a) => a.onclick = () => { S.emPid = +a.dataset.goP; go('patients', +a.dataset.goP); });
      $$('[data-undo]', v).forEach((b) => b.onclick = () => undoDeath(D.deaths.find((x) => x.id === +b.dataset.undo), load));
    };
    $('#em-dall').onchange = (e) => { S.emDall = e.target.checked; load(); };
    load();
  };

  // ---------------------------------------------------------------- 7) roster and stats
  VIEWS.emsstats = async (v) => {
    S.emSd = S.emSd || 7;
    v.innerHTML = head('Roster & stats', 'Who did what: calls, treatments, revives and reports. Ranks, hiring and duty are on the Department tab.',
      `<div class="seg" id="ems-tabs">${[7, 30, 90].map((d) => `<button data-sd="${d}" class="${S.emSd === d ? 'on' : ''}">${d} days</button>`).join('')}</div><button class="btn small" id="em-to-dept" data-probe-press>Department →</button>`) + `<div id="em-sbody">${loading}</div>`;
    const load = async () => {
      const r = await call('emsStats', { days: S.emSd });
      if (S.view !== 'emsstats' || !$('#em-sbody')) return;
      if (!r.ok) { $('#em-sbody').innerHTML = empty(r.why || 'Could not load', '▤'); return; }
      const D = r.data, T = D.totals, top = D.members.filter((m) => m.score > 0).slice(0, 3);
      const medal = ['🥇', '🥈', '🥉'];
      $('#em-sbody').innerHTML = `<div class="kpis">${kpi(T.calls, 'Calls attended')}${kpi(T.treated, 'Treated')}${kpi(T.revived, 'Revived')}${kpi(T.reports, 'Reports')}${kpi(T.onDuty + ' / ' + T.members, 'On duty now')}${T.dutySeconds != null ? kpi(Math.round(T.dutySeconds / 360) / 10 + ' h', 'Duty time') : ''}</div>
        ${!D.med ? '<div class="em-banner off">Treatments and revives come from the job pack (whip_jobs 0.6.0+), which is not running: only calls and reports count.</div>' : ''}
        ${top.length ? `<div class="em-podium">${top.map((m, i) => `<div class="em-pod p${i + 1}"><span class="em-medal">${medal[i]}</span><b>${esc(m.name)}</b><span class="hint">${esc(m.callsign ? m.callsign + ' · ' : '')}${esc(m.roleName || '')}</span><span class="em-score">${m.score} pts</span><span class="hint">${m.revived} revives · ${m.treated} treated · ${m.calls} calls</span></div>`).join('')}</div>` : ''}
        <div class="card flush"><div class="em-table stats"><div class="em-tr th"><span>#</span><span>Member</span><span class="num">Calls</span><span class="num">Treated</span><span class="num">Revived</span><span class="num">Reports</span><span class="num">Deaths</span>${D.leader ? '<span class="num">Duty</span>' : ''}<span class="num">Score</span></div>
          ${D.members.map((m, i) => `<div class="em-tr${m.me ? ' me' : ''}"><span class="hint">${i + 1}</span><span><span class="dot" style="--sc:${m.onDuty ? '#3ecf8e' : '#666c78'}"></span> <b>${esc(m.name)}</b>${m.me ? ' <span class="hint">(you)</span>' : ''}<br><span class="hint">${esc(m.callsign ? m.callsign + ' · ' : '')}${esc(m.roleName || '')}</span></span>
            <span class="num">${m.calls}</span><span class="num">${m.treated}</span><span class="num">${m.revived}</span><span class="num">${m.reports}</span><span class="num">${m.deaths}</span>${D.leader ? `<span class="num">${Math.round((m.dutySeconds || 0) / 360) / 10} h</span>` : ''}<span class="num"><b>${m.score}</b></span></div>`).join('') || empty('No members', '◌')}</div></div>
        <div class="hint">Score: revive 3 · treatment 2 · call 1 · report 1.</div>`;
    };
    $$('[data-sd]', v).forEach((b) => b.onclick = () => { S.emSd = +b.dataset.sd; $$('[data-sd]', v).forEach((x) => x.classList.toggle('on', x === b)); load(); });
    $('#em-to-dept').onclick = () => go('department');
    load();
  };

  // ---------------------------------------------------------------- 6) sharing: the call card and a person's page
  HOOK.callEms = (c) => {
    const e = c.ems; if (!e) return '';
    if (!EMS()) return e.line ? `<div class="em-callline">✚ <b>EMS:</b> ${esc(e.line)}<span class="hint">${(e.depts || []).length ? ' · ' + esc(e.depts.join(', ')) : ''}${e.at ? ' · ' + ago(e.at) : ''}</span></div>` : '';
    return `<div class="em-callline ems">✚ <b>EMS:</b> ${e.line ? esc(e.line) + ` <span class="hint">· ${e.reports} report${e.reports > 1 ? 's' : ''}</span>` : '<span class="hint">no report yet</span>'}
      <span class="row">${e.mine ? `<button class="btn small" id="cd-ems-view" data-rid="${e.mine}" data-probe-press>My report</button>` : e.canReport ? '<button class="btn small accent" id="cd-ems-rep" data-probe-press>✎ Write EMS report</button>' : ''}</span></div>`;
  };
  HOOK.callEmsWire = (box, c, reload) => {
    if ($('#cd-ems-rep', box)) $('#cd-ems-rep', box).onclick = () => reportForm({ callId: c.id }, reload);
    if ($('#cd-ems-view', box)) $('#cd-ems-view', box).onclick = (e) => reportView(+e.currentTarget.dataset.rid, reload);
  };
  const prevPerson = HOOK.person;
  HOOK.person = (box, p, reload) => {
    const out = prevPerson ? prevPerson(box, p, reload) : null;
    const e = p && p.ems; if (!e) return out;
    if (e.deceased) {
      const d = e.deceased;
      box.insertAdjacentHTML('afterbegin', `<div class="em-dead"><span class="em-dead-ico">✝</span><div><b>Deceased</b> · ${esc(d.cause || '')}<div class="hint">${dateTime(d.at)}${d.place ? ' · ' + esc(d.place) : ''} · recorded by ${esc(d.by || 'EMS')}${d.dept ? ' (' + esc(d.dept) + ')' : ''}${d.caseNumber ? ' · post-mortem in case ' + esc(d.caseNumber) : ''}</div></div></div>`);
    }
    const tags = $('.res-tags', box);
    if (tags) {
      if (e.deceased) tags.insertAdjacentHTML('afterbegin', pill('✝ Deceased', 'bad'));
      if (e.treated) tags.insertAdjacentHTML('beforeend', `<span class="pill em-tr-pill" title="${esc(e.treated.what || '')}">✚ Treated by EMS · ${esc(ago(e.treated.at))}${e.treated.dept ? ' · ' + esc(e.treated.dept) : ''}</span>`);
    }
    return out;
  };
})();
