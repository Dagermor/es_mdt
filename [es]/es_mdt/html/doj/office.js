// es_doj office: records (people and their full court + police record, sealing), the clerk desk (petitions, bills,
// business licenses, notices), firearm permits, the bar, attorney clients, the penal code and the activity log.
(function () {
  'use strict';
  const D = window.DOJ;
  const { S, $, $$, esc, money, call, toast, said, busy, ago, date, dateTime, pill, empty, cap, R, has, caseNo, kindTag, verdictPill, statusPill,
    modal, confirmBox, form, answer, go, crumb, wireBack, rerender, views } = D;
  const reload = (a) => { if (a === true) setTimeout(rerender, 60); return a; };

  // ---------------------------------------------------------------- people search
  let lastQ = '';
  views.people = async (h) => {
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Records</div><div class="v-sub">A person's full record: court cases, police reports, warrants, bills, sentences, licenses.</div></div></div>
      <div class="search" style="max-width:none"><span class="s-ico">⌕</span><input type="text" data-q placeholder="Type a name or a citizen ID…" value="${esc(lastQ)}"></div><div data-res></div>`;
    const q = $('[data-q]', h), res = $('[data-res]', h); let t = null, seq = 0;
    const run = async () => {
      const s = q.value.trim(); lastQ = s;
      if (s.length < 2) { res.innerHTML = empty('Search someone to see their record', '☺'); return; }
      const my = ++seq; res.innerHTML = D.loading();
      const r = await call('people', { q: s });
      if (my !== seq) return;
      const rows = (r.ok && r.data) || [];
      res.innerHTML = rows.length ? `<div class="card flush">${rows.map((p) => `<div class="li click" data-person="${p.charId}" style="padding:12px 18px"><div class="li-main"><b>${esc(p.name)}</b><span class="hint">Citizen #${p.charId}${p.dob ? ' · born ' + esc(p.dob) : ''}</span></div><span class="lnk">Open →</span></div>`).join('')}</div>` : empty('Nobody found', '☺');
    };
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(run, 250); });
    q.focus(); run();
  };

  // ---------------------------------------------------------------- one person
  const MARK = { sealed: ['Sealed', 'sealed'], expunged: ['Expunged', 'off'] };
  views.person = async (h, cid, alive) => {
    const r = await call('person', { charId: cid });
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = crumb() + empty(r.why, '☺'); wireBack(h); return; }
    const p = r.data, s = p.summary || {};
    const owing = (p.fees || []).filter((f) => f.status === 'unpaid');
    h.innerHTML = `${crumb('Records')}
      <div class="pv-head"><div class="pv-photo" ${p.photo ? `style="background-image:url('${p.photo}')" data-photo` : ''}>${p.photo ? '' : '☺'}</div>
        <div class="flex1"><div class="pv-name">${esc(p.name)}</div><div class="hint">Citizen #${p.charId}${p.dob ? ' · born ' + esc(p.dob) : ''}${p.gender ? ' · ' + esc(cap(p.gender)) : ''}${p.phone ? ' · ☎ ' + esc(p.phone) : ''}</div>
          <div class="row mt gap-s">${p.jailed ? pill('In jail' + (p.jailLeft ? ' · ' + Math.ceil(p.jailLeft / 60) + ' min left' : ''), 'bad') : ''}${p.warrants.some((w) => w.status === 'active') ? pill('Active warrant', 'bad') : ''}
            ${s.probation ? pill('Probation until ' + date(s.probation), 'warn') : ''}${s.service ? pill(s.service + ' service tasks left', 'warn') : ''}
            ${p.permit && p.permit.license ? pill('Firearm permit: ' + p.permit.license.status, p.permit.license.status === 'active' ? 'on' : 'warn') : pill('No firearm permit', 'off')}
            ${p.bar ? pill('Bar ' + p.bar.number + ' · ' + p.bar.status, p.bar.status === 'active' ? 'gold' : 'off') : ''}</div></div>
        <div class="actbar">${p.canCharge ? '<button class="btn small gold" data-a="case">＋ New case</button>' : ''}${has('warrants') ? '<button class="btn small" data-a="warrant">✎ Warrant</button>' : ''}${has('clerk', 'judge') ? '<button class="btn small" data-a="bill">$ Bill</button>' : ''}${has('clerk', 'judge', 'cases', 'prosecutor', 'defender') ? '<button class="btn small" data-a="notice">✉ Notice</button>' : ''}${has('attorney', 'defender') ? '<button class="btn small" data-a="client">☷ Add as client</button>' : ''}</div></div>
      <div class="kpis"><div class="kpi"><b>${s.convictions || 0}</b><span>Convictions</span></div><div class="kpi ${s.felonyConvictions ? 'hot' : ''}"><b>${s.felonyConvictions || 0}</b><span>Felony convictions</span></div>
        <div class="kpi ${s.owed ? 'hot' : ''}"><b>${money(s.owed)}</b><span>Owes the court</span></div><div class="kpi"><b>${(p.cases || []).filter((k) => k.status === 'open').length}</b><span>Open cases</span></div></div>
      <div class="cols-main"><div>
        <div class="card"><div class="card-title">Court cases</div>${(p.cases || []).length ? p.cases.map((k) => `<div class="li click" data-case="${k.id}">${caseNo(k)}<div class="li-main"><b>${esc(k.title)}</b><span class="hint">${k.status === 'open' ? esc(k.stageLabel) : cap(k.status)} · ${date(k.createdAt)}</span></div>${verdictPill(k.verdict)}${k.sealed ? pill('Sealed', 'sealed') : ''}${k.court && MARK[k.court] ? pill(MARK[k.court][0], MARK[k.court][1]) : ''}${k.test ? pill('Test', 'test') : ''}
          ${p.canSeal && k.status !== 'open' ? `<button class="btn small ghost" data-seal="case:${k.id}">Seal / expunge</button>` : ''}</div>`).join('') : empty('No court cases', '⚖')}</div>
        <div class="card"><div class="card-title">Police reports${p.hiddenReports ? ` <span class="hint">· ${p.hiddenReports} sealed/expunged hidden</span>` : ''}</div>${(p.reports || []).length ? p.reports.map((x) => `<div class="li"><span class="tag t-${esc(x.type)}">${esc(cap(x.type))}</span><div class="li-main"><b>#${x.id} ${esc(x.title || '')}</b><span class="hint">${esc(cap(x.role))} · ${esc(x.dept || '')} · ${date(x.createdAt)}${x.charges ? ' · ' + esc(x.charges) : ''}</span></div>
          ${x.court && MARK[x.court] ? pill(MARK[x.court][0], MARK[x.court][1]) : ''}${x.courtCaseId ? `<span class="lnk" data-case="${x.courtCaseId}">Court case →</span>` : (p.canCharge && x.charges ? `<button class="btn small ghost" data-charge="${x.id}">Take to court</button>` : '')}
          ${p.canSeal ? `<button class="btn small ghost" data-seal="report:${x.id}">${x.court ? 'Change' : 'Seal / expunge'}</button>` : ''}</div>`).join('') : empty('No police reports', '◌')}</div>
      </div><div>
        <div class="card"><div class="card-title">Warrants</div>${(p.warrants || []).length ? p.warrants.map((w) => `<div class="li"><div class="li-main"><b>#${w.id} ${esc(cap(w.kind))}</b><span class="hint">${esc(w.reason)}${w.expiresAt ? ' · expires ' + date(w.expiresAt) : ''}</span></div>${pill(cap(w.status), w.status === 'active' ? 'bad' : 'warn')}</div>`).join('') : empty('None', '✎')}</div>
        <div class="card"><div class="card-title">Bills</div>${owing.length || (p.mdtFines || []).length ? owing.map((f) => `<div class="li"><div class="li-main"><b>${esc(cap(f.kind))} · ${money(f.amount)}</b><span class="hint">${esc(f.reason || '')}${f.dueAt ? ' · due ' + date(f.dueAt) : ''}</span></div>${f.dueAt && f.dueAt < Date.now() / 1000 ? pill('Overdue', 'bad') : pill('Unpaid', 'warn')}${has('clerk', 'judge') ? `<button class="btn small ghost" data-void="${f.id}">Waive</button>` : ''}</div>`).join('') + (p.mdtFines || []).map((f) => `<div class="li"><div class="li-main"><b>Police fine · ${money(f.amount)}</b><span class="hint">${esc(f.reason || '')} · ${date(f.createdAt)}</span></div>${pill('Unpaid', 'warn')}</div>`).join('') : empty('Owes nothing', '$')}</div>
        <div class="card"><div class="card-title">Sentences</div>${(p.sentences || []).length ? p.sentences.map((x) => `<div class="li click" data-case="${x.caseId}"><div class="li-main"><b>${esc(x.number)}</b><span class="hint">${[x.fine ? money(x.fine) : '', x.months ? x.months + ' mo' : '', x.service ? x.service + ' tasks' : '', x.probationDays ? x.probationDays + 'd probation' : ''].filter(Boolean).join(' · ') || 'No penalty'} · ${date(x.createdAt)}</span></div>${pill(cap(x.status), x.status === 'active' ? 'gold' : 'off')}</div>`).join('') : empty('None', '⚖')}</div>
        <div class="card"><div class="card-title">Lawyers and licenses</div>${(p.lawyers || []).map((l) => `<div class="li"><div class="li-main"><b>${esc(l.name || '#' + l.charId)}</b><span class="hint">Their lawyer</span></div></div>`).join('')}
          ${(p.businesses || []).map((b) => `<div class="li"><div class="li-main"><b>${esc(b.name)}</b><span class="hint">${esc(b.licenseNo)} · ${esc(b.kind || '')}${b.expiresAt ? ' · until ' + date(b.expiresAt) : ''}</span></div>${pill(cap(b.status), b.status === 'active' ? 'on' : 'warn')}</div>`).join('') || ((p.lawyers || []).length ? '' : empty('None', '⚑'))}</div>
      </div></div>`;
    wireBack(h);
    const ph = $('[data-photo]', h); if (ph) ph.onclick = () => D.lightbox(p.photo, p.name);
    const who = { charId: p.charId, name: p.name };
    const A = {
      case: () => D.newCase({ person: who }),
      warrant: () => D.issueWarrant({ person: who }),
      bill: () => billForm(who),
      notice: () => noticeForm(who),
      client: () => form('Add as a client', [{ k: 'note', label: 'Note (only you see it)', type: 'textarea', rows: 2, span2: true, max: 300 }],
        { intro: `${esc(p.name)} goes on your client list: you can then be put on their cases.`, yes: 'Add client', onSubmit: async (v) => answer(await call('clientAdd', { charId: p.charId, note: v.note }), 'Client added') }),
    };
    $$('[data-a]', h).forEach((b) => b.onclick = () => A[b.dataset.a]());
    $$('[data-charge]', h).forEach((b) => b.onclick = () => D.newCase({ reportId: +b.dataset.charge }));
    $$('[data-void]', h).forEach((b) => b.onclick = () => voidFee(+b.dataset.void));
    $$('[data-seal]', h).forEach((b) => b.onclick = () => { const [kind, id] = b.dataset.seal.split(':'); sealForm(kind, +id, p); });
  };
  function sealForm(kind, refId, p) {
    form(`${kind === 'case' ? 'Court case' : 'Police report'} #${refId}`, [
      { k: 'mode', label: 'Court order', type: 'choice', span2: true, opts: [{ v: 'sealed', l: 'Seal', d: 'Hidden from police and the public; the court still sees it' }, { v: 'expunged', l: 'Expunge', d: 'Cleared: not counted anywhere (MDT, permits)' }, { v: 'clear', l: 'Lift the order', d: 'Visible again' }] },
      { k: 'reason', label: 'Reason / order', type: 'textarea', rows: 3, span2: true, max: 300 }],
    { yes: 'Enter the order', onSubmit: async (v) => v.mode ? reload(answer(await call('recordSeal', { kind, refId, charId: p.charId, mode: v.mode, reason: v.reason }), 'Record updated')) : 'Pick an order' });
  }
  function voidFee(id) {
    return form('Waive the bill', [{ k: 'reason', label: 'Why', type: 'textarea', rows: 2, span2: true, req: true, max: 200 }],
      { danger: true, yes: 'Waive', onSubmit: async (v) => reload(answer(await call('feeVoid', { id, reason: v.reason }), 'Bill waived')) });
  }
  function billForm(who) {
    const kinds = [{ v: 'fee', l: 'Court fee' }, { v: 'copy', l: 'Record copy' }, { v: 'restitution', l: 'Restitution' }];
    if (R().judge) kinds.unshift({ v: 'fine', l: 'Court fine' });
    return form('Bill someone', [
      { k: 'who', label: 'Person', type: 'person', req: true, span2: true, value: who },
      { k: 'kind', label: 'Kind', type: 'select', opts: kinds },
      { k: 'amount', label: 'Amount', type: 'money', req: true },
      { k: 'reason', label: 'For', span2: true, req: true, max: 200, placeholder: 'Contempt of court' }],
    { ico: '$', intro: `They pay at the courthouse or in /${esc(S.lists.portal || 'court')}. Unpaid fines become an MDT warrant after ${(S.lists.fees || {}).dueDays || 14} days.`, yes: 'Send the bill',
      onSubmit: async (v) => reload(answer(await call('feeCreate', { charId: D.pickedId(v.who), kind: v.kind, amount: v.amount, reason: v.reason }), 'Bill sent')) });
  }
  D.billForm = billForm;
  function noticeForm(who) {
    return form('Send a court notice', [
      { k: 'who', label: 'To', type: 'person', req: true, span2: true, value: who },
      { k: 'title', label: 'Title', req: true, span2: true, max: 160 },
      { k: 'body', label: 'Message', type: 'textarea', rows: 4, span2: true, max: 1000 }],
    { ico: '✉', intro: `They see it in /${esc(S.lists.portal || 'court')} (and a pop-up when they are in the city).`, yes: 'Send',
      onSubmit: async (v) => answer(await call('noticeSend', { charId: D.pickedId(v.who), title: v.title, body: v.body }), 'Notice sent') });
  }

  // ---------------------------------------------------------------- clerk desk
  const CL = { tab: 'petitions', pst: 'pending', fst: 'unpaid', bst: '', bq: '' };
  const PET_ICO = { name_change: '✎', business: '🏢', expungement: '🧹' };
  views.clerk = async (h, arg, alive) => {
    const tabs = [['petitions', 'Petitions'], ['fees', 'Bills & payments'], ['businesses', 'Business licenses']];
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Clerk desk</div><div class="v-sub">Name changes, business licenses, expungements, bills and notices.</div></div>
      <div class="row">${has('clerk', 'judge') ? '<button class="btn" data-bill>$ Bill someone</button>' : ''}${has('clerk', 'judge', 'cases', 'prosecutor', 'defender') ? '<button class="btn" data-notice>✉ Send a notice</button>' : ''}${has('clerk', 'judge') ? '<button class="btn gold" data-biz>🏢 New business license</button>' : ''}</div></div>
      <div class="tabs">${tabs.map(([t, l]) => `<button class="tab ${CL.tab === t ? 'on' : ''}" data-tab="${t}">${l}${t === 'petitions' && S.counts.petitions ? ` <span class="pill warn">${S.counts.petitions}</span>` : ''}</button>`).join('')}</div><div data-body>${D.loading()}</div>`;
    $$('[data-tab]', h).forEach((b) => b.onclick = () => { CL.tab = b.dataset.tab; rerender(); });
    const bb = $('[data-bill]', h); if (bb) bb.onclick = () => billForm();
    const nb = $('[data-notice]', h); if (nb) nb.onclick = () => noticeForm();
    const zb = $('[data-biz]', h); if (zb) zb.onclick = () => bizForm();
    const body = $('[data-body]', h);
    await CLERK[CL.tab](body, alive);
  };
  const CLERK = {};
  CLERK.petitions = async (b, alive) => {
    const r = await call('petitions', { status: CL.pst });
    if (!alive()) return;
    const rows = (r.ok && r.data) || [];
    b.innerHTML = `<div class="filters mt"><div class="seg">${['pending', 'approved', 'denied', 'all'].map((s) => `<button data-st="${s}" class="${CL.pst === s ? 'on' : ''}">${cap(s)}</button>`).join('')}</div></div>
      <div class="card flush mt">${!r.ok ? empty(r.why, '⚠') : rows.length ? rows.map((p) => `<div class="li click" data-pet="${p.id}" style="padding:12px 18px"><span style="font-size:22px;width:30px;text-align:center">${PET_ICO[p.kind] || '✎'}</span>
        <div class="li-main"><b>${esc(p.label)} · ${esc(p.name || '#' + p.charId)}</b><span class="hint">${petSummary(p)} · ${ago(p.createdAt)}</span></div>
        ${p.fee ? pill(p.paid ? 'Fee paid' : money(p.fee) + ' unpaid', p.paid ? 'on' : 'warn') : ''} ${pill(cap(p.status), p.status === 'pending' ? 'gold' : p.status === 'approved' ? 'on' : 'off')} ${p.test ? pill('Test', 'test') : ''}</div>`).join('') : empty('No petitions here', '✎')}</div>`;
    $$('[data-st]', b).forEach((x) => x.onclick = () => { CL.pst = x.dataset.st; rerender(); });
    $$('[data-pet]', b).forEach((x) => x.onclick = () => petition(+x.dataset.pet));
  };
  function petSummary(p) {
    const d = p.data || {};
    if (p.kind === 'name_change') return `${esc(d.oldName || '?')} → <b>${esc((d.firstName || '') + ' ' + (d.lastName || ''))}</b>`;
    if (p.kind === 'business') return `<b>${esc(d.name || '')}</b>${d.kind ? ' · ' + esc(d.kind) : ''}`;
    if (p.kind === 'expungement') return `${(d.reports || []).length} report(s), ${(d.cases || []).length} case(s)`;
    return '';
  }
  async function petition(id) {
    const r = await call('petition', { id });
    if (!r.ok) { toast(r.why, 'err'); return; }
    const p = r.data, d = p.data || {};
    const pending = p.status === 'pending' && p.canDecide;
    const judge = R().judge;
    modal(`<div class="m-title"><span class="m-ico">${PET_ICO[p.kind] || '✎'}</span>${esc(p.label)} #${p.id}</div>
      <div class="row gap-s">${pill(cap(p.status), p.status === 'pending' ? 'gold' : p.status === 'approved' ? 'on' : 'off')} <b class="lnk" data-person="${p.charId}">${esc(p.name || '#' + p.charId)}</b><span class="hint">filed ${dateTime(p.createdAt)}</span>${p.test ? pill('Test', 'test') : ''}</div>
      <div class="card mt">${p.kind === 'name_change' ? `<div class="kv"><dt>Current name</dt><dd>${esc(d.oldName || '')}</dd><dt>New name</dt><dd><b>${esc(d.firstName + ' ' + d.lastName)}</b></dd></div>`
        : p.kind === 'business' ? `<div class="kv"><dt>Business</dt><dd><b>${esc(d.name)}</b></dd><dt>Kind</dt><dd>${esc(d.kind || '—')}</dd><dt>Address</dt><dd>${esc(d.address || '—')}</dd></div>`
        : `${(p.reports || []).map((x) => `<div class="li"><div class="li-main"><b>Report #${x.id} · ${esc(x.title || cap(x.type))}</b><span class="hint">${date(x.createdAt)}${x.charges ? ' · ' + esc(x.charges) : ''}</span></div></div>`).join('')}
           ${(p.cases || []).map((k) => `<div class="li"><div class="li-main"><b>${esc(k.number)} · ${esc(k.title)}</b><span class="hint">${esc(D.VERDICT[k.verdict] || k.verdict)}${k.closedAt ? ' · closed ' + date(k.closedAt) : ''}</span></div></div>`).join('')}
           ${p.record ? `<div class="hint mt">Their record: ${p.record.convictions} conviction(s), ${p.record.felonyConvictions} felony · owes ${money(p.record.owed)}${p.record.probation ? ' · on probation' : ''}</div>` : ''}`}
        <div class="lbl mt">Their reason</div><div class="narr" style="white-space:pre-wrap">${esc(p.reason || '—')}</div>
        <div class="hint mt">Fee: ${p.fee ? money(p.fee) + (p.paid ? ' · paid' : ' · <b class="txt-warn">not paid</b>') : 'none'}${p.decidedByLabel ? ' · decided by ' + esc(p.decidedByLabel) : ''}${p.decisionNote ? ': “' + esc(p.decisionNote) + '”' : ''}</div></div>
      ${pending ? `<div class="field mt"><label>Note <span class="hint">· needed to deny: they read it</span></label><input type="text" data-note maxlength="300"></div>
        ${!p.paid && !p.test && judge ? '<label class="ck-item"><input type="checkbox" data-waive> Waive the unpaid fee</label>' : ''}
        ${p.kind === 'name_change' && !p.test ? '<div class="help">Approving renames the character at once (everywhere in the city).</div>' : ''}
        <div class="form-err" data-err></div>
        <div class="row end"><button class="btn ghost" data-x>Close</button><button class="btn danger" data-d="deny">Deny</button><button class="btn gold" data-d="approve">Approve</button></div>`
        : '<div class="row end"><button class="btn" data-x>Close</button></div>'}`, (card, closeIt) => {
      $$('[data-d]', card).forEach((b) => b.onclick = () => busy(b, async () => {
        const w = $('[data-waive]', card);
        const rr = await call('petitionDecide', { id: p.id, decision: b.dataset.d, note: $('[data-note]', card).value.trim(), waive: !!(w && w.checked) });
        if (!rr.ok) { $('[data-err]', card).textContent = rr.why; return; }
        closeIt(); toast(b.dataset.d === 'approve' ? 'Approved' + (rr.data && rr.data.result ? ': ' + rr.data.result : '') : 'Denied', 'ok'); setTimeout(rerender, 200);
      }));
    }, 'wide');
  }
  const FEE_ST = { unpaid: 'warn', paying: 'warn', paid: 'on', refunded: 'off', void: 'off' };
  CLERK.fees = async (b, alive) => {
    const r = await call('fees', { status: CL.fst });
    if (!alive()) return;
    const rows = (r.ok && r.data.rows) || [];
    b.innerHTML = `<div class="filters mt"><div class="seg">${['unpaid', 'overdue', 'paid', 'all'].map((s) => `<button data-st="${s}" class="${CL.fst === s ? 'on' : ''}">${cap(s)}</button>`).join('')}</div>${r.ok && r.data.total ? `<span class="hint">Unpaid here: <b>${money(r.data.total)}</b></span>` : ''}</div>
      <div class="card flush mt">${!r.ok ? empty(r.why, '⚠') : rows.length ? `<table><thead><tr><th>#</th><th>Who</th><th>Bill</th><th class="num">Amount</th><th>Due</th><th>Status</th><th></th></tr></thead><tbody>${rows.map((f) => `<tr>
        <td class="hint">${f.id}</td><td><span class="lnk" data-person="${f.charId}">${esc(f.name || '#' + f.charId)}</span></td>
        <td>${esc(f.label)}${f.number ? ` · <span class="lnk" data-case="${f.caseId}">${esc(f.number)}</span>` : ''}<span class="sub">${esc(f.reason || '')}</span></td><td class="num">${money(f.amount)}</td>
        <td>${f.dueAt ? date(f.dueAt) : '—'}${f.status === 'unpaid' && f.dueAt && f.dueAt < Date.now() / 1000 ? ' ' + pill('Overdue', 'bad') : ''}${f.warrantId ? ' ' + pill('Warrant #' + f.warrantId, 'bad') : ''}</td>
        <td>${pill(cap(f.status), FEE_ST[f.status])}${f.method ? `<span class="sub">${esc(f.method)}${f.paidAt ? ' · ' + date(f.paidAt) : ''}</span>` : ''}${f.test ? ' ' + pill('Test', 'test') : ''}</td>
        <td>${f.status === 'unpaid' && has('clerk', 'judge') ? `<button class="btn small ghost" data-void="${f.id}">Waive</button>` : ''}</td></tr>`).join('')}</tbody></table>` : empty('No bills here', '$')}</div>
      <div class="help mt">People pay at the courthouse window or in /${esc(S.lists.portal || 'court')} → Payments (cash or bank). Anyone may pay someone else's bill${S.lists.bail ? ' or bail' : ''} there.</div>`;
    $$('[data-st]', b).forEach((x) => x.onclick = () => { CL.fst = x.dataset.st; rerender(); });
    $$('[data-void]', b).forEach((x) => x.onclick = () => voidFee(+x.dataset.void));
  };
  CLERK.businesses = async (b, alive) => {
    const r = await call('businesses', { q: CL.bq, status: CL.bst });
    if (!alive()) return;
    const rows = (r.ok && r.data) || [];
    const may = has('clerk', 'judge');
    b.innerHTML = `<div class="filters mt"><div class="seg">${[['', 'All'], ['active', 'Active'], ['suspended', 'Suspended'], ['revoked', 'Revoked'], ['expired', 'Expired']].map(([v, l]) => `<button data-st="${v}" class="${CL.bst === v ? 'on' : ''}">${l}</button>`).join('')}</div><input type="text" data-q placeholder="Name, license number or owner…" value="${esc(CL.bq)}"></div>
      <div class="card flush mt">${rows.length ? `<table><thead><tr><th>License</th><th>Business</th><th>Owner</th><th>Expires</th><th>Status</th><th></th></tr></thead><tbody>${rows.map((x) => `<tr>
        <td class="case-no">${esc(x.licenseNo)}</td><td><b>${esc(x.name)}</b><span class="sub">${esc(x.kind || '')}${x.address ? ' · ' + esc(x.address) : ''}</span></td>
        <td><span class="lnk" data-person="${x.ownerCharId}">${esc(x.owner || '#' + x.ownerCharId)}</span></td><td>${x.expiresAt ? date(x.expiresAt) : 'Never'}</td>
        <td>${pill(x.expired && x.status === 'active' ? 'Expired' : cap(x.status), x.status === 'active' && !x.expired ? 'on' : 'warn')}${x.test ? ' ' + pill('Test', 'test') : ''}${x.note ? `<span class="sub">${esc(x.note)}</span>` : ''}</td>
        <td>${may ? `<select class="small-sel" data-act="${x.id}"><option value="">Change…</option>${x.status === 'active' ? '<option value="suspend">Suspend</option><option value="revoke">Revoke</option>' : '<option value="reinstate">Reinstate</option>'}<option value="renew">Renew</option><option value="edit">Edit</option></select>` : ''}</td></tr>`).join('')}</tbody></table>` : empty('No business licenses', '🏢')}</div>`;
    $$('[data-st]', b).forEach((x) => x.onclick = () => { CL.bst = x.dataset.st; rerender(); });
    const q = $('[data-q]', b); let t = null; q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { CL.bq = q.value.trim(); rerender(); }, 400); });
    $$('[data-act]', b).forEach((s) => s.onchange = () => { const x = rows.find((y) => y.id === +s.dataset.act); const act = s.value; s.value = ''; if (act) bizAct(x, act); });
  };
  function bizAct(x, act) {
    if (act === 'edit') return form(`Edit ${x.licenseNo}`, [{ k: 'name', label: 'Name', value: x.name, req: true, span2: true }, { k: 'kind', label: 'Kind', value: x.kind || '' }, { k: 'address', label: 'Address', value: x.address || '' }],
      { onSubmit: async (v) => reload(answer(await call('businessAct', Object.assign({ id: x.id, act }, v)), 'Saved')) });
    if (act === 'renew' || act === 'reinstate') return confirmBox(cap(act), `${cap(act)} ${x.name} (${x.licenseNo})?`, cap(act)).then(async (y) => { if (y) said(await call('businessAct', { id: x.id, act }), 'Done') && rerender(); });
    return form(`${cap(act)} ${x.name}`, [{ k: 'note', label: 'Why', type: 'textarea', rows: 2, span2: true, req: true, max: 300 }], { danger: true, yes: cap(act),
      onSubmit: async (v) => reload(answer(await call('businessAct', { id: x.id, act, note: v.note }), 'Done')) });
  }
  function bizForm() {
    return form('New business license', [
      { k: 'who', label: 'Owner', type: 'person', req: true, span2: true },
      { k: 'name', label: 'Business name', req: true, max: 80 }, { k: 'kind', label: 'Kind', max: 40, placeholder: 'Mechanic shop' },
      { k: 'address', label: 'Address', span2: true, max: 160 }, { k: 'note', label: 'Note', span2: true, max: 300 }],
    { ico: '🏢', intro: 'Issued at once, without a fee. (Citizens who apply in the portal pay the license fee.)', yes: 'Issue the license',
      onSubmit: async (v) => { const r = await call('businessCreate', { charId: D.pickedId(v.who), name: v.name, kind: v.kind, address: v.address, note: v.note }); return reload(answer(r, r.ok ? 'License ' + r.data.licenseNo + ' issued' : null)); } });
  }

  // ---------------------------------------------------------------- firearm permits
  let PST = 'pending';
  views.permits = async (h, arg, alive) => {
    const r = await call('permits', { status: PST });
    if (!alive()) return;
    const rows = (r.ok && r.data) || [];
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Firearm permits</div><div class="v-sub">Civilian applications from the MDT. Approving makes their photo their MDT photo.</div></div></div>
      <div class="filters"><div class="seg">${['pending', 'approved', 'denied', 'all'].map((s) => `<button data-st="${s}" class="${PST === s ? 'on' : ''}">${cap(s)}</button>`).join('')}</div></div>
      ${!r.ok ? empty(r.why, '⚠') : rows.length ? rows.map((a) => `<div class="card wq">${a.hasPhoto ? `<div class="pm-photo" data-img="${a.id}" data-cap="${esc(a.firstName + ' ' + a.lastName)}"></div>` : '<div class="pm-photo" style="display:flex;align-items:center;justify-content:center">☺</div>'}
        <div class="w-body"><div class="row gap-s"><b class="lnk" data-person="${a.charId}">${esc(a.firstName + ' ' + a.lastName)}</b><span class="hint">#${a.charId}${a.dob ? ' · born ' + esc(a.dob) : ''} · application #${a.id} · ${ago(a.createdAt)}</span>${pill(cap(a.status), a.status === 'pending' ? 'gold' : a.status === 'approved' ? 'on' : 'off')}${a.fee ? pill(a.paid ? 'Fee paid' : money(a.fee) + ' due', a.paid ? 'on' : 'warn') : ''}</div>
          <div class="w-reason">${esc(a.reason)}</div>
          ${a.check ? `<div class="row gap-s">${(a.check.flags || []).length ? a.check.flags.map((f) => pill(f, 'bad')).join('') : pill('Background check clean', 'on')}<span class="hint">checked ${ago(a.check.at)}</span></div>` : ''}
          ${a.decidedByLabel ? `<div class="hint">${esc(cap(a.status))} by ${esc(a.decidedByLabel)}${a.decisionNote ? ': “' + esc(a.decisionNote) + '”' : ''}</div>` : ''}</div>
        <div class="w-acts">${a.status === 'pending' && has('permits') ? `<button class="btn small gold" data-dec="${a.id}">Review</button>` : ''}</div></div>`).join('') : empty('No applications here', '◎')}`;
    $$('[data-st]', h).forEach((b) => b.onclick = () => { PST = b.dataset.st; rerender(); });
    D.lazyThumbs(h, 'permitPhoto', (el) => ({ id: +el.dataset.img }));
    $$('[data-dec]', h).forEach((b) => b.onclick = () => permitReview(rows.find((a) => a.id === +b.dataset.dec)));
  };
  async function permitReview(a) {
    const r = await call('permitCheck', { charId: a.charId });
    const ck = (r.ok && r.data) || a.check || {};
    const photo = a.hasPhoto ? await D.imageOf('permitPhoto', { id: a.id }) : null;
    modal(`<div class="m-title"><span class="m-ico">◎</span>Firearm permit · ${esc(a.firstName + ' ' + a.lastName)}</div>
      <div class="cols2 mt"><div>${photo ? `<div class="up-prev"><img src="${photo}" alt=""></div>` : empty('No photo', '☺')}<div class="lbl mt">Why they want it</div><div class="narr">${esc(a.reason)}</div></div>
        <div><div class="card"><div class="card-title">Background check (now)</div><dl class="kv"><dt>Active warrants</dt><dd>${ck.warrants || 0}</dd><dt>Felony charges</dt><dd>${ck.felonies || 0}</dd>
          <dt>Felony convictions</dt><dd>${ck.convictions == null ? '—' : ck.convictions}</dd><dt>Arrests (${ck.arrestDays || 30} days)</dt><dd>${ck.arrests || 0}</dd><dt>In jail</dt><dd>${ck.jailed ? 'Yes' : 'No'}</dd></dl>
          <div class="row mt gap-s">${(ck.flags || []).length ? ck.flags.map((f) => pill(f, 'bad')).join('') : pill('Clean', 'on')}</div></div></div></div>
      <div class="field mt"><label>Note <span class="hint">· needed to deny: they read it</span></label><input type="text" data-note maxlength="300"></div>
      <div class="form-err" data-err></div>
      <div class="row end"><button class="btn ghost" data-x>Close</button><button class="btn danger" data-d="deny">Deny</button><button class="btn gold" data-d="approve">Approve permit</button></div>`, (card, closeIt) => {
      $$('[data-d]', card).forEach((b) => b.onclick = () => busy(b, async () => {
        const rr = await call('permitDecide', { id: a.id, decision: b.dataset.d, note: $('[data-note]', card).value.trim() });
        if (!rr.ok) { $('[data-err]', card).textContent = rr.why; return; }
        closeIt(); toast(b.dataset.d === 'approve' ? 'Permit issued' : 'Application denied', 'ok'); setTimeout(rerender, 200);
      }));
    }, 'wide');
  }

  // ---------------------------------------------------------------- bar and clients
  views.bar = async (h, arg, alive) => {
    const r = await call('bar');
    if (!alive()) return;
    const rows = (r.ok && r.data) || [];
    const may = has('bar');
    // 1.1.0: the attorneys, by office: the DA's office, the public defenders (both DOJ ranks) and private attorneys
    const KIND = { prosecutor: "District Attorney's Office", public: "Public Defender's Office", private: 'Private attorneys' };
    const SUB = { prosecutor: 'Prosecute cases, charge and offer plea deals', public: 'Defend anyone who cannot hire a lawyer', private: 'Hired by civilians at the courthouse or in /' + (S.lists.portal || 'court') };
    const row = (l) => `<tr>
        <td class="case-no">${esc(l.number)}</td><td><span class="lnk" data-person="${l.charId}">${esc(l.name)}</span> ${l.online ? '<span class="dot" style="background:#50c878" title="In the city"></span>' : ''}${l.rank ? `<span class="sub">${esc(l.rank)}</span>` : ''}</td>
        <td>${esc(l.firm || '—')}<span class="sub">${esc(l.phone || '')}</span></td><td class="num">${l.clients}</td>
        <td>${pill(cap(l.status), l.status === 'active' ? 'on' : 'bad')}${l.note ? `<span class="sub">${esc(l.note)}</span>` : ''}</td>
        <td>${may ? `<select class="small-sel" data-act="${l.charId}"><option value="">Change…</option>${l.status === 'active' ? '<option value="suspend">Suspend</option><option value="revoke">Revoke</option>' : '<option value="reinstate">Reinstate</option>'}<option value="edit">Edit</option></select>` : ''}</td></tr>`;
    const group = (kind) => { const list = rows.filter((l) => (KIND[l.kind] ? l.kind : 'private') === kind);
      return `<div class="card flush"><div class="card-head" style="padding:var(--ui-sp-5) var(--ui-sp-6) 0"><div><div class="card-title">${esc(KIND[kind])} <span class="count">${list.filter((l) => l.status === 'active').length}</span></div><div class="hint">${esc(SUB[kind])}</div></div></div>
        ${list.length ? `<table><thead><tr><th>Bar #</th><th>Attorney</th><th>Firm / phone</th><th class="num">Clients</th><th>Status</th><th></th></tr></thead><tbody>${list.map(row).join('')}</tbody></table>` : `<div style="padding:var(--ui-sp-5) var(--ui-sp-6)">${empty(kind === 'private' ? 'No private attorneys licensed yet' : 'Nobody yet: hire into this rank in Departments (the license comes with the job)', '⚑')}</div>`}</div>`; };
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Attorneys</div><div class="v-sub">Prosecutors and public defenders are DOJ ranks and are licensed with the job. Private attorneys get a license from the bar office.</div></div>${may ? '<button class="btn gold" data-new>＋ License an attorney</button>' : ''}</div>
      ${group('prosecutor')}${group('public')}${group('private')}`;
    const nb = $('[data-new]', h); if (nb) nb.onclick = () => form('License an attorney', [
      { k: 'who', label: 'Person', type: 'person', req: true, span2: true },
      { k: 'kind', label: 'Kind', type: 'select', opts: [{ v: 'private', l: 'Private attorney' }, { v: 'public', l: 'Public defender' }, { v: 'prosecutor', l: 'Prosecutor' }] },
      { k: 'firm', label: 'Firm', max: 80 }, { k: 'phone', label: 'Phone', max: 20 }, { k: 'note', label: 'Note', max: 300 }],
    { ico: '⚑', yes: 'Issue the license', onSubmit: async (v) => { const rr = await call('barIssue', { charId: D.pickedId(v.who), kind: v.kind, firm: v.firm, phone: v.phone, note: v.note }); return reload(answer(rr, rr.ok ? 'Licensed' + (rr.data && rr.data.number ? ': ' + rr.data.number : '') : null)); } });
    $$('[data-act]', h).forEach((s) => s.onchange = () => { const l = rows.find((x) => x.charId === +s.dataset.act); const act = s.value; s.value = ''; if (!act) return;
      if (act === 'edit') form(`Edit ${l.number}`, [{ k: 'kind', label: 'Kind', type: 'select', value: l.kind, opts: [{ v: 'private', l: 'Private attorney' }, { v: 'public', l: 'Public defender' }, { v: 'prosecutor', l: 'Prosecutor' }] }, { k: 'firm', label: 'Firm', value: l.firm || '' }, { k: 'phone', label: 'Phone', value: l.phone || '' }],
        { onSubmit: async (v) => reload(answer(await call('barAct', Object.assign({ charId: l.charId, act }, v)), 'Saved')) });
      else form(`${cap(act)} ${l.name}`, [{ k: 'note', label: act === 'reinstate' ? 'Note' : 'Why', type: 'textarea', rows: 2, span2: true, req: act !== 'reinstate', max: 300 }],
        { danger: act !== 'reinstate', yes: cap(act), onSubmit: async (v) => reload(answer(await call('barAct', { charId: l.charId, act, note: v.note }), 'Done')) }); });
  };
  views.clients = async (h, arg, alive) => {
    const r = await call('clients');
    if (!alive()) return;
    const rows = (r.ok && r.data) || [];
    const may = has('attorney', 'defender');
    h.innerHTML = `<div class="v-head"><div><div class="v-title">My clients</div><div class="v-sub">People you represent. Being on someone's list lets you put yourself on their cases.</div></div>${may ? '<button class="btn gold" data-new>＋ Add a client</button>' : ''}</div>
      ${!r.ok ? empty(r.why, '⚠') : rows.length ? `<div class="card flush">${rows.map((c) => `<div class="li" style="padding:12px 18px"><div class="li-main"><b class="lnk" data-person="${c.charId}">${esc(c.name)}</b> <span class="hint">${c.online ? '● in the city · ' : ''}since ${date(c.createdAt)}${c.note ? ' · ' + esc(c.note) : ''}${c.endedAt ? ' · ended ' + date(c.endedAt) : ''}</span>
        <div class="row gap-s mt">${(c.cases || []).map((k) => `<span class="lnk" data-case="${k.id}">${esc(k.number)} · ${esc(k.stageLabel)}</span>`).join(' ') || '<span class="hint">No open cases</span>'}</div></div>
        ${pill(cap(c.status), c.status === 'active' ? 'on' : 'off')}${c.status === 'active' && may ? `<button class="btn small ghost" data-end="${c.charId}">End</button>` : ''}</div>`).join('')}</div>` : empty('No clients yet. Clients ask you through the court portal; add them here.', '☷')}`;
    const nb = $('[data-new]', h); if (nb) nb.onclick = () => form('Add a client', [{ k: 'who', label: 'Client', type: 'person', req: true, span2: true }, { k: 'note', label: 'Note (only you see it)', type: 'textarea', rows: 2, span2: true, max: 300 }],
      { ico: '☷', yes: 'Add', onSubmit: async (v) => reload(answer(await call('clientAdd', { charId: D.pickedId(v.who), note: v.note }), 'Client added')) });
    $$('[data-end]', h).forEach((b) => b.onclick = async () => { if (await confirmBox('End representation', 'You come off their open cases too.', 'End', true)) said(await call('clientEnd', { charId: +b.dataset.end }), 'Ended') && rerender(); });
  };

  // ---------------------------------------------------------------- penal code
  let PQ = '', PALL = false;
  views.penal = async (h, arg, alive) => {
    const edit = has('penal');
    const r = await call('penal', { all: edit && PALL });
    if (!alive()) return;
    const rows = (r.ok && r.data) || [];
    const s = PQ.toLowerCase();
    const show = rows.filter((p) => !s || p.code.toLowerCase().includes(s) || p.title.toLowerCase().includes(s));
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Penal code</div><div class="v-sub">${edit ? 'You may edit it: changes apply to new charges in the MDT and in court.' : 'Read-only for your rank.'}</div></div>${edit ? '<button class="btn gold" data-new>＋ New charge</button>' : ''}</div>
      <div class="filters"><input type="text" data-q placeholder="Search code or title…" value="${esc(PQ)}">${edit ? `<label class="ck-item"><input type="checkbox" data-all ${PALL ? 'checked' : ''}> Show retired</label>` : ''}<span class="hint">${show.length} charges</span></div>
      <div class="card flush"><table><thead><tr><th>Code</th><th>Class</th><th>Charge</th><th class="num">Fine</th><th class="num">Months</th>${edit ? '<th></th>' : ''}</tr></thead><tbody>${show.map((p) => `<tr ${p.active === 0 ? 'style="opacity:.5"' : ''}>
        <td class="case-no">${esc(p.code)}</td><td><span class="cat c-${esc(p.category)}">${esc(cap(p.category))}</span></td><td><b>${esc(p.title)}</b>${p.description ? `<span class="sub">${esc(p.description)}</span>` : ''}${p.active === 0 ? ' ' + pill('Retired', 'off') : ''}</td>
        <td class="num">${money(p.fine)}</td><td class="num">${p.months}</td>${edit ? `<td><button class="btn small ghost" data-ed="${p.id}">Edit</button></td>` : ''}</tr>`).join('')}</tbody></table></div>`;
    const q = $('[data-q]', h); let t = null;
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { PQ = q.value.trim(); rerender().then(() => { const n = $('#view [data-q]'); if (n) { n.focus(); n.setSelectionRange(n.value.length, n.value.length); } }); }, 300); });
    const al = $('[data-all]', h); if (al) al.onchange = () => { PALL = al.checked; rerender(); };
    const pf = (p) => form(p ? `Edit ${p.code}` : 'New charge', [
      { k: 'code', label: 'Code', value: p ? p.code : '', req: true, max: 16, placeholder: 'F-320' },
      { k: 'category', label: 'Class', type: 'select', value: p ? p.category : 'misdemeanor', opts: [{ v: 'infraction', l: 'Infraction' }, { v: 'misdemeanor', l: 'Misdemeanor' }, { v: 'felony', l: 'Felony' }] },
      { k: 'title', label: 'Title', value: p ? p.title : '', req: true, span2: true, max: 120 },
      { k: 'fine', label: 'Fine', type: 'money', value: p ? p.fine : 0 }, { k: 'months', label: 'Jail (months)', type: 'number', value: p ? p.months : 0 },
      { k: 'description', label: 'Description', type: 'textarea', rows: 2, span2: true, max: 500, value: p && p.description || '' },
      { k: 'active', label: 'In force (untick to retire it)', type: 'check', value: p ? p.active !== 0 : true, span2: true }],
    { ico: '§', onSubmit: async (v) => { D.penalCodeReset && D.penalCodeReset(); return reload(answer(await call('penalSave', Object.assign({ id: p ? p.id : null }, v)), 'Penal code saved')); } });
    const nb = $('[data-new]', h); if (nb) nb.onclick = () => pf(null);
    $$('[data-ed]', h).forEach((b) => b.onclick = () => pf(rows.find((x) => x.id === +b.dataset.ed)));
  };

  // ---------------------------------------------------------------- activity
  let AQ = '';
  views.activity = async (h, arg, alive) => {
    const r = await call('activity', { q: AQ });
    if (!alive()) return;
    const rows = (r.ok && r.data) || [];
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Activity log</div><div class="v-sub">Everything the DOJ did, newest first.</div></div></div>
      <div class="filters"><input type="text" data-q placeholder="Search a name, case number or word…" value="${esc(AQ)}"></div>
      <div class="card">${!r.ok ? empty(r.why, '⚠') : rows.length ? `<div class="tl">${rows.map((l) => `<div class="tl-i"><b>${esc(l.detail || cap(l.what))}</b><span class="hint">${esc(l.byLabel || 'System')} · ${dateTime(l.at)}${l.number ? ` · <span class="lnk" data-case="${l.caseId}">${esc(l.number)}</span>` : ''}</span></div>`).join('')}</div>` : empty('Nothing yet', '≡')}</div>`;
    const q = $('[data-q]', h); let t = null;
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { AQ = q.value.trim(); rerender().then(() => { const n = $('#view [data-q]'); if (n) { n.focus(); n.setSelectionRange(n.value.length, n.value.length); } }); }, 400); });
  };
})();
