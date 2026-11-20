// es_doj portal (/court and the courthouse window): a citizen's cases, notices, payments, petitions, lawyers, public records.
(function () {
  'use strict';
  const D = window.DOJ;
  const { S, $, $$, esc, money, call, toast, said, busy, ago, inTime, date, dateTime, pill, empty, cap, labelOf, kindTag, caseNo, verdictPill, statusPill,
    modal, confirmBox, form, answer, go, crumb, wireBack, rerender, views } = D;
  const H = () => S.home || { cases: [], fees: { fees: [], fines: [], paid: [] }, notices: [], lawyers: [], petitions: [], businesses: [], subpoenas: [] };
  async function fresh() { const r = await call('home'); if (r.ok) { S.home = r.data; D.drawNav(); } return H(); }
  const reload = (a) => { if (a === true) setTimeout(rerender, 60); return a; };
  const portal = () => S.lists.portal || 'court';

  // ---------------------------------------------------------------- overview
  views.home = async (h, arg, alive) => {
    const d = await fresh();
    if (!alive()) return;
    const owed = d.fees.fees.filter((f) => f.kind !== 'bail').reduce((a, f) => a + f.amount, 0) + d.fees.fines.reduce((a, f) => a + f.amount, 0);
    const open = d.cases.filter((k) => k.status === 'open');
    const nextH = open.filter((k) => k.next).sort((a, b) => a.next - b.next)[0];
    const alerts = [];
    d.cases.filter((k) => k.offers > 0 && k.status === 'open').forEach((k) => alerts.push(['warn', '✍', `A plea deal is waiting for your answer in ${k.number}`, 'Read it and accept or reject it.', 'pcase', k.id]));
    if (S.lists.bail) d.fees.fees.filter((f) => f.kind === 'bail').forEach((f) => alerts.push(['warn', '$', `Bail ${money(f.amount)} (or a ${money(f.bond)} bond) in ${f.number || 'your case'}`, 'Pay it to be released until trial. Anyone may pay it for you.', 'pay']));
    if (owed) alerts.push([d.fees.fees.some((f) => f.dueAt && f.dueAt < Date.now() / 1000) ? 'bad' : 'warn', '$', `You owe ${money(owed)}`, 'Unpaid court fines become a warrant when they are overdue.', 'pay']);
    (d.subpoenas || []).forEach((s) => alerts.push(['bad', '✉', `Subpoena in ${s.number}: ${s.kind === 'documents' ? 'produce documents' : 'appear in court'}`, (s.startsAt ? dateTime(s.startsAt) + (s.room ? ' · ' + s.room : '') + ' · ' : '') + (s.details || ''), 'mycases']));
    if (d.service) alerts.push(['warn', '🧹', `${d.service} community service task${d.service === 1 ? '' : 's'} left`, 'Your spot is marked on the map. Go there and press E.', null]);
    const tk = d.tk || {};
    if (tk.impounded) alerts.push(['bad', '⛍', `${tk.impounded} of your vehicles ${tk.impounded === 1 ? 'is' : 'are'} impounded`, 'See what it costs to get it back and pay for it.', 'pimpound']);
    if (nextH) alerts.push(['', '▦', `Court: ${nextH.number} ${inTime(nextH.next)}`, dateTime(nextH.next) + ' at the ' + (d.courthouse || 'courthouse'), 'pcase', nextH.id]);
    const tile = (view, ico, title, sub) => `<div class="tile" data-go="${view}"><span class="t-ico">${ico}</span><b>${title}</b><span>${sub}</span></div>`;
    h.innerHTML = `<div class="hero"><div style="font-size:42px">⚖</div><div class="flex1"><h1>Welcome, ${esc(d.me.name)}</h1><p>Superior Court of San Andreas · your cases, bills and requests in one place.${S.extra && S.extra.desk ? ' You are at the clerk window.' : ''}</p></div></div>
      ${alerts.length ? alerts.map((a) => `<div class="alert ${a[0]} ${a[4] ? 'tile' : ''}" ${a[4] ? `data-go="${a[4]}" data-arg="${a[5] || ''}"` : ''} style="${a[4] ? 'flex-direction:row;padding:14px 18px' : ''}"><span class="a-ico">${a[1]}</span><div class="li-main"><b>${esc(a[2])}</b><span class="hint">${esc(a[3])}</span></div>${a[4] ? '<span class="lnk">Open →</span>' : ''}</div>`).join('') : '<div class="alert"><span class="a-ico">✓</span><div class="li-main"><b>Nothing needs you right now</b><span class="hint">No open bills, plea offers or subpoenas.</span></div></div>'}
      <div class="tiles">
        ${tile('mycases', '⚖', 'My cases', open.length ? `${open.length} open` : 'Cases you are part of')}
        ${tile('pay', '$', 'Payments', owed ? money(owed) + ' owed' : (S.lists.bail ? 'Fines, fees and bail' : 'Fines and fees') + ' · pay for someone')}
        ${tile('ptickets', '✎', 'My tickets', tk.unpaid ? tk.unpaid + ' to pay' + (tk.contested ? ' · ' + tk.contested + ' contested' : '') : 'Police tickets · contest an unsigned one')}
        ${tile('pimpound', 'Ⓟ', 'Impounded vehicles', tk.impounded ? tk.impounded + ' at the lot' : 'Get an impounded car back')}
        ${tile('petitions', '✎', 'Petitions', 'Name change, business license, expungement, lawsuit')}
        ${tile('lawyers', '⚑', 'Lawyers', d.lawyers.length ? 'Your lawyer: ' + esc(d.lawyers[0].name || '') : 'Hire one or ask for a public defender')}
        ${tile('records', '⌕', 'Public records', 'Cases, businesses, attorneys')}
        ${tile('notices', '✉', 'Notices', d.unread ? d.unread + ' unread' : 'Letters from the court')}
      </div>
      ${d.summary && (d.summary.convictions || d.summary.probation) ? `<div class="help">Your record: ${d.summary.convictions} conviction(s)${d.summary.probation ? ' · on probation until ' + date(d.summary.probation) : ''}. Old records can be cleared with an expungement petition.</div>` : ''}`;
    $$('[data-go]', h).forEach((b) => b.onclick = () => { const v = b.dataset.go; const a = b.dataset.arg ? +b.dataset.arg : null; go(v, a, v === 'pcase' ? { parent: 'mycases' } : { root: true }); });
  };

  // ---------------------------------------------------------------- my cases
  views.mycases = async (h, arg, alive) => {
    const d = await fresh();
    if (!alive()) return;
    h.innerHTML = `<div class="v-head"><div><div class="v-title">My cases</div><div class="v-sub">Cases against you and lawsuits you filed.</div></div><button class="btn gold" data-sue>＋ File a lawsuit</button></div>
      <div class="card flush">${d.cases.length ? `<table><thead><tr><th>Case</th><th>Title</th><th>You are</th><th>Status</th><th>Lawyer</th><th>Next hearing</th></tr></thead><tbody>${d.cases.map((k) => `<tr class="click" data-case="${k.id}">
        <td>${caseNo(k)}<span class="sub">${kindTag(k.kind)}</span></td><td><b>${esc(k.title)}</b>${k.offers ? ' ' + pill('Plea offer', 'warn') : ''}${k.test ? ' ' + pill('Test', 'test') : ''}</td>
        <td>${esc(cap(k.role))}</td><td>${esc(k.stageLabel)} ${verdictPill(k.verdict)}</td><td>${esc(k.defense || (k.defenseKind === 'public' ? 'Public defender asked' : '—'))}</td>
        <td>${k.next ? dateTime(k.next) + `<span class="sub">${inTime(k.next)}</span>` : '<span class="muted">—</span>'}</td></tr>`).join('')}</tbody></table>` : empty('You are not part of any court case', '⚖')}</div>`;
    $('[data-sue]', h).onclick = () => sue();
  };
  views.pcase = async (h, id, alive) => {
    const r = await call('case', { id });
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = crumb('My cases') + empty(r.why, '🔒'); wireBack(h); return; }
    const k = r.data;
    const open = k.status === 'open', def = k.role === 'defendant';
    const bill = S.lists.bail && H().fees.fees.find((f) => f.kind === 'bail' && f.caseId === k.id);
    h.innerHTML = `${crumb('My cases')}
      <div class="case-head"><div class="flex1"><div class="case-meta">${caseNo(k)} ${kindTag(k.kind)} ${statusPill(k.status)} ${verdictPill(k.verdict)} ${k.test ? pill('Test case', 'test') : ''}</div>
        <div class="case-title">${esc(k.title)}</div><div class="hint">${esc(k.stageLabel)} · filed ${date(k.createdAt)} · you are the ${esc(k.role)}</div></div>
        <div class="actbar">${open && def && !k.defenseCharId && k.defenseKind !== 'public' ? '<button class="btn small" data-pd>Ask for a public defender</button>' : ''}${open && def && !k.defenseCharId ? '<button class="btn small" data-hire>Hire a lawyer</button>' : ''}${k.canAppeal ? '<button class="btn small gold" data-appeal>↗ Appeal</button>' : ''}</div></div>
      <div class="parties">
        <div class="party"><span class="lbl">Judge</span>${k.judge ? `<b>${esc(k.judge)}</b>` : '<b class="none">Not yet assigned</b>'}</div>
        ${k.kind === 'civil' ? `<div class="party"><span class="lbl">Plaintiff</span><b>${esc(k.plaintiff || '—')}</b></div>` : `<div class="party"><span class="lbl">Prosecutor</span>${k.prosecutor ? `<b>${esc(k.prosecutor)}</b>` : '<b class="none">—</b>'}</div>`}
        <div class="party"><span class="lbl">Defendant</span><b>${esc(k.defendant || '—')}</b></div>
        <div class="party"><span class="lbl">Defense</span>${k.defense ? `<b>${esc(k.defense)}</b><span class="hint">${esc(cap(k.defenseKind))}</span>` : `<b class="none">${k.defenseKind === 'public' ? 'Public defender asked' : k.defenseKind === 'self' ? 'Yourself' : 'None'}</b>`}</div>
        ${S.lists.bail && k.kind !== 'civil' ? `<div class="party"><span class="lbl">Bail</span><b>${esc({ none: 'Not set', set: money(k.bailAmount) + ' set', posted: 'Posted', denied: 'Denied', ror: 'Own recognizance', revoked: 'Revoked', forfeited: 'Forfeited', returned: 'Returned' }[k.bailStatus] || cap(k.bailStatus))}</b>${bill ? '<div class="p-act"><button class="btn small gold" data-paybail>Pay bail</button></div>' : ''}</div>` : ''}
      </div>
      ${(k.pleas || []).filter((p) => p.status === 'offered').map((p) => `<div class="card" style="border-color:var(--gold-b)"><div class="card-head"><div class="card-title">Plea deal offered · ${date(p.createdAt)}</div>${pill('Waiting for you', 'warn')}</div>
        <div class="narr" style="white-space:pre-wrap">${esc(p.terms)}</div><div class="row mt">${p.fine ? pill(money(p.fine) + ' fine') : ''}${p.months ? pill(p.months + ' months jail') : ''}${p.service ? pill(p.service + ' service tasks') : ''}${p.probationDays ? pill(p.probationDays + ' days probation') : ''}</div>
        <div class="help mt">If you accept, the judge still has to approve it. Then the case closes with this sentence. Talk to your lawyer first if you have one.</div>
        <div class="row end"><button class="btn danger" data-plea="reject" data-id="${p.id}">Reject</button><button class="btn ok" data-plea="accept" data-id="${p.id}">Accept the deal</button></div></div>`).join('')}
      <div class="cols-main"><div>
        <div class="card"><div class="card-title">Charges</div>${(k.charges || []).length ? k.charges.map((g) => `<div class="chg ${g.disposition === 'dropped' ? 'dropped' : ''}"><span class="code">${esc(g.code)}</span><span class="cat c-${esc(g.category)}">${esc(cap(g.category))}</span><div class="li-main"><b>${esc(g.title)}${g.count > 1 ? ' ×' + g.count : ''}</b></div><span class="disp ${esc(g.disposition)}">${esc(cap(g.disposition))}</span></div>`).join('') : empty('No charges', '§')}</div>
        ${k.summary ? `<div class="card"><div class="card-title">About the case</div><div class="narr" style="white-space:pre-wrap">${esc(k.summary)}</div></div>` : ''}
        <div class="card"><div class="card-title">Documents</div>${(k.filings || []).length ? `<div class="files">${k.filings.map((f) => `<div class="file">${f.hasImage ? `<div class="thumb" data-img="${f.id}" data-cap="${esc(f.title)}"><div class="spin"></div></div>` : ''}<div class="f-body"><div class="row gap-s">${f.exhibitNo ? `<span class="exh">${esc(f.exhibitNo)}</span>` : ''}<span class="f-title">${esc(f.title)}</span></div><span class="hint">${esc(cap(f.kind))} · ${esc(f.byLabel || '')} · ${date(f.createdAt)}</span>${f.body ? `<div class="f-text">${esc(f.body)}</div>` : ''}<div class="f-foot">${pill(cap(f.status))}${f.ruling ? '<span class="hint">' + esc(f.ruling) + '</span>' : ''}</div></div></div>`).join('')}</div>` : empty('Nothing filed that you may read', '📄')}</div>
      </div><div>
        <div class="card"><div class="card-title">Hearings</div>${(k.hearings || []).length ? k.hearings.map((x) => `<div class="li"><div class="li-main"><b>${esc(x.title || labelOf(S.lists.hearingKinds, x.kind))}</b><span class="hint">${dateTime(x.startsAt)} · ${esc(x.room)}${x.status === 'scheduled' ? ' · ' + inTime(x.startsAt) : ''}${x.outcome ? ' · ' + esc(x.outcome) : ''}</span></div>${pill(cap(x.status), x.status === 'scheduled' ? 'gold' : 'off')}</div>`).join('') : empty('None scheduled yet', '▦')}
          <div class="hint mt">Go to the ${esc(S.lists.courthouse || 'courthouse')} on time. Missing court can ${S.lists.bail ? 'cost your bail and ' : ''}bring a warrant.</div></div>
        ${(k.sentences || []).length ? `<div class="card"><div class="card-title">${k.kind === 'civil' ? 'Judgment' : 'Sentence'}</div>${k.sentences.map((s) => `<div class="li"><div class="li-main"><b>${[s.fine ? money(s.fine) + ' fine' : '', s.months ? s.months + ' months' : '', s.service ? s.service + ' service tasks' : '', s.probationDays ? s.probationDays + ' days probation' : '', s.restitution ? money(s.restitution) + (k.kind === 'civil' ? ' award' : ' restitution') : ''].filter(Boolean).join(' · ') || 'No penalty'}</b><span class="hint">${date(s.createdAt)}${s.notes ? ' · ' + esc(s.notes) : ''}</span></div>${pill(cap(s.status))}</div>`).join('')}</div>` : ''}
      </div></div>`;
    wireBack(h);
    D.lazyThumbs(h, 'filingImage', (el) => ({ id: +el.dataset.img }));
    $$('[data-plea]', h).forEach((b) => b.onclick = async () => {
      const act = b.dataset.plea;
      form(act === 'accept' ? 'Accept the plea deal' : 'Reject the plea deal', [{ k: 'note', label: act === 'accept' ? 'Message (optional)' : 'Why (optional)', type: 'textarea', rows: 2, span2: true, max: 300 }],
        { yes: act === 'accept' ? 'Accept' : 'Reject', danger: act === 'reject', onSubmit: async (v) => reload(answer(await call('plea', { id: +b.dataset.id, act, note: v.note }), act === 'accept' ? 'Accepted: the judge decides next' : 'Rejected')) });
    });
    const pd = $('[data-pd]', h); if (pd) pd.onclick = async () => { if (await confirmBox('Public defender', 'The court assigns a public defender to your case for free. Public defenders in the city are told now.', 'Ask for one')) said(await call('publicDefender', { caseId: k.id }), 'Asked: a public defender will take your case') && rerender(); };
    const hb = $('[data-hire]', h); if (hb) hb.onclick = () => go('lawyers', null, { root: true });
    const pb = $('[data-paybail]', h); if (pb) pb.onclick = () => payDialog(bill);
    const ab = $('[data-appeal]', h); if (ab) ab.onclick = () => form(`Appeal ${k.number}`, [{ k: 'reason', label: 'Why the decision was wrong', type: 'textarea', rows: 6, span2: true, req: true, max: 4000 }],
      { size: 'wide', intro: (S.lists.fees || {}).appeal ? `The appeal fee is ${money(S.lists.fees.appeal)}.` : '', yes: 'File the appeal',
        onSubmit: async (v) => { const rr = await call('appeal', { caseId: k.id, reason: v.reason }); return reload(answer(rr, rr.ok ? `Appeal ${rr.data.number} filed` : null)); } });
  };
  function sue() {
    return form('File a lawsuit', [
      { k: 'who', label: 'Who are you suing?', type: 'person', req: true, span2: true },
      { k: 'title', label: 'Title', span2: true, max: 160, placeholder: 'blank = "Your name v. their name"' },
      { k: 'summary', label: 'What happened and what you ask for', type: 'textarea', rows: 6, span2: true, req: true, max: 4000 }],
    { ico: '⚖', size: 'wide', intro: (S.lists.fees || {}).filing ? `Filing fee: ${money(S.lists.fees.filing)}.` : 'Filing is free. A judge will be assigned and both sides told.', yes: 'File',
      onSubmit: async (v) => { const r = await call('civil', { defendantCharId: D.pickedId(v.who), title: v.title, summary: v.summary }); return reload(answer(r, r.ok ? `${r.data.number} filed` : null)); } });
  }

  // ---------------------------------------------------------------- payments
  function payDialog(f, isFine, forName) {
    const bail = !!S.lists.bail && f.kind === 'bail';
    modal(`<div class="m-title"><span class="m-ico">$</span>Pay ${esc(isFine ? 'police fine #' + f.id : (f.label || cap(f.kind)) + (f.number ? ' · ' + f.number : ' #' + f.id))}</div>
      ${forName ? `<div class="help">You are paying for <b>${esc(forName)}</b>.</div>` : ''}
      ${bail ? `<div class="choice mt" data-bond style="grid-template-columns:1fr 1fr"><button type="button" class="on" data-v="0"><b>Full bail · ${money(f.amount)}</b><span>Returned to you when the case ends</span></button><button type="button" data-v="1"><b>Bond · ${money(f.bond)}</b><span>${H().fees.bondPercent || 10}%, never returned</span></button></div>`
        : `<div class="v-title mt">${money(f.amount)}</div><div class="hint">${esc(f.reason || '')}</div>`}
      <div class="lbl mt">Pay with</div><div class="seg mt" data-m><button class="on" data-v="bank">Bank</button><button data-v="cash">Cash</button></div>
      <div class="form-err" data-err></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn gold" data-ok>Pay now</button></div>`, (card, closeIt) => {
      let method = 'bank', bond = false;
      $$('[data-m] button', card).forEach((b) => b.onclick = () => { method = b.dataset.v; $$('[data-m] button', card).forEach((x) => x.classList.toggle('on', x === b)); });
      $$('[data-bond] button', card).forEach((b) => b.onclick = () => { bond = b.dataset.v === '1'; $$('[data-bond] button', card).forEach((x) => x.classList.toggle('on', x === b)); });
      const ok = $('[data-ok]', card);
      ok.onclick = () => busy(ok, async () => {
        const r = await call(isFine ? 'payFine' : 'pay', { id: f.id, method, bond: bail && bond });
        if (!r.ok) { $('[data-err]', card).textContent = r.why; return; }
        closeIt(); toast(`Paid ${money(r.data.amount)}${r.data.test ? ' (test: no money moved)' : ''}`, 'ok'); setTimeout(rerender, 150);
      });
    });
  }
  const billRows = (b, other) => {
    const rows = b.fees.map((f) => `<div class="bill"><span class="a-ico" style="font-size:20px">${f.kind === 'bail' ? '⛓' : '⚖'}</span><div class="li-main"><b>${esc(f.label)}${f.number ? ' · ' + esc(f.number) : ''}</b><span class="hint">${esc(f.reason || '')}${f.dueAt ? ' · due ' + date(f.dueAt) : ''}${f.test ? ' · test' : ''}</span></div>
      ${f.dueAt && f.dueAt < Date.now() / 1000 ? pill('Overdue', 'bad') : ''}<span class="amt">${money(f.amount)}</span><button class="btn gold" data-pay="${f.id}">Pay</button></div>`)
      .concat(b.fines.map((f) => `<div class="bill"><span class="a-ico" style="font-size:20px">${f.ticketId ? '✎' : f.kind === 'impound' ? '⛍' : '🚓'}</span><div class="li-main"><b>${f.ticketId ? esc(f.reason || 'Police ticket') : 'Police fine #' + f.id}${f.dept ? ' · ' + esc(f.dept) : ''}</b><span class="hint">${f.ticketId ? '' : esc(f.reason || '') + ' · '}${date(f.createdAt)}${f.dueAt ? ' · due ' + date(f.dueAt) : ''}</span></div>
        ${f.contested ? pill('Contested · paused', 'warn') : f.dueAt && f.dueAt < Date.now() / 1000 ? pill('Overdue', 'bad') : ''}<span class="amt">${money(f.amount)}</span>${f.contested ? '' : `<button class="btn gold" data-fine="${f.id}">Pay</button>`}</div>`));
    return rows.length ? rows.join('') : empty(other ? 'They owe nothing' : 'You owe nothing. Nice.', '✓');
  };
  views.pay = async (h, arg, alive) => {
    const d = await fresh();
    if (!alive()) return;
    const b = d.fees;
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Payments</div><div class="v-sub">Court fines, fees${S.lists.bail ? ', bail' : ''} and police fines. Pay by bank or cash.</div></div></div>
      <div class="card"><div class="card-title">What you owe</div>${billRows(b)}</div>
      <div class="card"><div class="card-title">Pay for someone else <span class="hint">· ${S.lists.bail ? 'bail for a friend, ' : ''}a friend's or family member's fine</span></div><div data-pp></div><div data-other class="mt"></div></div>
      ${(b.paid || []).length ? `<div class="card"><div class="card-title">Paid recently</div>${b.paid.map((f) => `<div class="li"><div class="li-main"><b>${esc(f.label)} · ${money(f.amount)}</b><span class="hint">${esc(f.reason || '')} · ${date(f.paidAt)} · ${esc(f.method || '')}</span></div>${pill(cap(f.status), f.status === 'paid' ? 'on' : 'off')}</div>`).join('')}</div>` : ''}`;
    const wire = (root, bills, name) => {
      $$('[data-pay]', root).forEach((x) => x.onclick = () => payDialog(bills.fees.find((f) => f.id === +x.dataset.pay), false, name));
      $$('[data-fine]', root).forEach((x) => x.onclick = () => payDialog(bills.fines.find((f) => f.id === +x.dataset.fine), true, name));
    };
    wire($('.card', h), b);
    D.personPicker($('[data-pp]', h), 'Type their name (3+ letters)…', async (p) => {
      const o = $('[data-other]', h); o.innerHTML = D.loading();
      const r = await call('billsFor', { charId: p.charId });
      if (!r.ok) { o.innerHTML = empty(r.why, '⚠'); return; }
      o.innerHTML = `<div class="lbl">${esc(r.data.name || p.name)}</div>${billRows(r.data, true)}`;
      wire(o, r.data, r.data.name || p.name);
    });
  };

  // ---------------------------------------------------------------- petitions
  views.petitions = async (h, arg, alive) => {
    const d = await fresh();
    if (!alive()) return;
    const pf = d.fees.petitionFees || {};
    const fee = (n) => n ? money(n) : 'Free';
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Petitions</div><div class="v-sub">Ask the court for something. The clerk or a judge decides; you get a notice.</div></div></div>
      <div class="tiles">
        <div class="tile" data-p="name_change"><span class="t-ico">✎</span><b>Change my name</b><span>Legal name change · ${fee(pf.name_change)}</span></div>
        <div class="tile" data-p="business"><span class="t-ico">🏢</span><b>Business license</b><span>Register a business · ${fee(pf.business)}</span></div>
        <div class="tile" data-p="expungement"><span class="t-ico">🧹</span><b>Clear my record</b><span>Expunge old reports and cases · ${fee(pf.expungement)}</span></div>
        <div class="tile" data-p="civil"><span class="t-ico">⚖</span><b>Sue someone</b><span>A civil lawsuit · ${fee(pf.filing)}</span></div>
      </div>
      <div class="card"><div class="card-title">My petitions</div>${d.petitions.length ? d.petitions.map((p) => `<div class="li"><div class="li-main"><b>${esc(p.label)} #${p.id}</b><span class="hint">${date(p.createdAt)}${p.decisionNote ? ' · “' + esc(p.decisionNote) + '”' : ''}</span></div>
        ${p.fee ? pill(p.paid ? 'Fee paid' : money(p.fee) + ' to pay', p.paid ? 'on' : 'warn') : ''} ${pill(cap(p.status), p.status === 'pending' ? 'gold' : p.status === 'approved' ? 'on' : 'off')}</div>`).join('') : empty('None yet', '✎')}</div>
      ${d.businesses.length ? `<div class="card"><div class="card-title">My businesses</div>${d.businesses.map((b) => `<div class="li"><div class="li-main"><b>${esc(b.name)}</b><span class="hint">${esc(b.licenseNo)}${b.expiresAt ? ' · until ' + date(b.expiresAt) : ''}</span></div>${pill(cap(b.status), b.status === 'active' ? 'on' : 'warn')}</div>`).join('')}</div>` : ''}`;
    const feeNote = (n) => n ? `The ${money(n)} fee goes on your bills (Payments). The clerk decides once it is paid. Not refunded if denied after paying.` : '';
    const sent = (r) => reload(answer(r, r.ok ? (r.data.fee ? `Filed. Pay the ${money(r.data.fee)} fee in Payments.` : 'Filed') : null));
    const P = {
      name_change: () => form('Change my name', [
        { k: 'firstName', label: 'New first name', req: true, max: 30 }, { k: 'lastName', label: 'New last name', req: true, max: 30 },
        { k: 'reason', label: 'Why', type: 'textarea', rows: 3, span2: true, req: true, max: 1000 }],
      { ico: '✎', intro: `Your current name: <b>${esc(d.me.name)}</b>. ${feeNote(pf.name_change)}`, yes: 'File the petition',
        onSubmit: async (v) => sent(await call('petition', { kind: 'name_change', data: { firstName: v.firstName, lastName: v.lastName }, reason: v.reason })) }),
      business: () => form('Business license', [
        { k: 'name', label: 'Business name', req: true, span2: true, max: 80 }, { k: 'kind', label: 'What it does', max: 40, placeholder: 'Car repair' }, { k: 'address', label: 'Address', max: 160 },
        { k: 'reason', label: 'Anything the clerk should know', type: 'textarea', rows: 2, span2: true, max: 1000 }],
      { ico: '🏢', intro: feeNote(pf.business), yes: 'Apply', onSubmit: async (v) => sent(await call('petition', { kind: 'business', data: { name: v.name, kind: v.kind, address: v.address }, reason: v.reason })) }),
      expungement: async () => {
        const r = await call('myRecords');
        if (!r.ok) { toast(r.why, 'err'); return; }
        const rep = r.data.reports || [], cs = r.data.cases || [];
        if (!rep.length && !cs.length) { toast('You have nothing on record to clear', 'ok'); return; }
        form('Clear my record (expungement)', [
          { k: 'pick', type: 'html', span2: true, html: `<div class="lbl">Pick what to clear</div><div class="ck-list mt">${rep.map((x) => `<label class="ck-item"><input type="checkbox" data-r="${x.id}"> Police report #${x.id} · ${esc(x.title || cap(x.type))} <span class="hint">${date(x.createdAt)}${x.charges ? ' · ' + esc(x.charges) : ''}${x.sealed ? ' · sealed' : ''}</span></label>`).join('')}
            ${cs.map((k) => `<label class="ck-item"><input type="checkbox" data-c="${k.id}"> Court case ${esc(k.number)} · ${esc(k.title)} <span class="hint">${esc(D.VERDICT[k.verdict] || k.verdict)}${k.closedAt ? ' · ' + date(k.closedAt) : ''}</span></label>`).join('')}</div>` },
          { k: 'reason', label: 'Why the court should clear them', type: 'textarea', rows: 3, span2: true, req: true, max: 1000 }],
        { ico: '🧹', size: 'wide', intro: 'A judge decides. Only closed cases can be cleared. ' + feeNote(pf.expungement), yes: 'File the petition',
          onSubmit: async (v, card) => {
            const reports = $$('[data-r]:checked', card).map((i) => +i.dataset.r), cases = $$('[data-c]:checked', card).map((i) => +i.dataset.c);
            if (!reports.length && !cases.length) return 'Tick at least one record';
            return sent(await call('petition', { kind: 'expungement', data: { reports, cases }, reason: v.reason }));
          } });
      },
      civil: () => sue(),
    };
    $$('[data-p]', h).forEach((b) => b.onclick = () => P[b.dataset.p]());
  };

  // ---------------------------------------------------------------- lawyers
  views.lawyers = async (h, arg, alive) => {
    const [d, r] = await Promise.all([fresh(), call('lawyers')]);
    if (!alive()) return;
    const rows = (r.ok && r.data) || [];
    const mine = new Set(d.lawyers.map((l) => l.charId));
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Lawyers</div><div class="v-sub">Licensed attorneys of San Andreas. Hiring sends them a request; they add you as a client.</div></div></div>
      ${d.lawyers.length ? `<div class="card"><div class="card-title">My lawyers</div>${d.lawyers.map((l) => `<div class="li"><div class="li-main"><b>${esc(l.name || '#' + l.charId)}</b><span class="hint">${esc(l.number || '')}${l.firm ? ' · ' + esc(l.firm) : ''}${l.phone ? ' · ☎ ' + esc(l.phone) : ''}</span></div><button class="btn small ghost" data-fire="${l.charId}">Let go</button></div>`).join('')}</div>` : ''}
      <div class="card flush">${rows.length ? rows.map((l) => `<div class="li" style="padding:12px 18px"><div class="li-main"><b>${esc(l.name)} ${l.online ? '<span class="pill on">In the city</span>' : ''}</b><span class="hint">${esc(l.number)} · ${esc(l.kind === 'public' ? 'Public defender' : l.kind === 'prosecutor' ? 'Prosecutor' : 'Private attorney')}${l.firm ? ' · ' + esc(l.firm) : ''}${l.phone ? ' · ☎ ' + esc(l.phone) : ''}</span></div>
        ${l.kind === 'private' && !mine.has(l.charId) ? `<button class="btn small gold" data-hire="${l.charId}" data-n="${esc(l.name)}">Hire</button>` : mine.has(l.charId) ? pill('Your lawyer', 'on') : ''}</div>`).join('') : empty('No attorneys are licensed yet. On a case you can ask for a free public defender.', '⚑')}</div>`;
    $$('[data-hire]', h).forEach((b) => b.onclick = () => form(`Hire ${b.dataset.n}`, [{ k: 'message', label: 'Message', type: 'textarea', rows: 3, span2: true, max: 300, placeholder: 'I have a hearing on Friday for CR-2026-0012…' }],
      { yes: 'Send the request', onSubmit: async (v) => answer(await call('hire', { charId: +b.dataset.hire, message: v.message }), 'Sent: they will add you as a client') }));
    $$('[data-fire]', h).forEach((b) => b.onclick = async () => { if (await confirmBox('Let your lawyer go', 'They come off your open cases.', 'Let go', true)) said(await call('fire', { charId: +b.dataset.fire }), 'Done') && rerender(); });
  };

  // ---------------------------------------------------------------- public records
  let RQ = '';
  views.records = async (h) => {
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Public records</div><div class="v-sub">Court cases, licensed businesses and attorneys. Sealed records are not shown.</div></div></div>
      <div class="search" style="max-width:none"><span class="s-ico">⌕</span><input type="text" data-q placeholder="A case number, a name, a business… (3+ letters)" value="${esc(RQ)}"></div><div data-res class="mt"></div>`;
    const q = $('[data-q]', h), res = $('[data-res]', h); let t = null, seq = 0;
    const run = async () => {
      const s = q.value.trim(); RQ = s;
      if (s.length < 3) { res.innerHTML = empty('Type at least 3 letters', '⌕'); return; }
      const my = ++seq; res.innerHTML = D.loading();
      const r = await call('records', { q: s });
      if (my !== seq) return;
      const d = (r.ok && r.data) || { cases: [], businesses: [], lawyers: [] };
      res.innerHTML = `<div class="cols3"><div class="card"><div class="card-title">Cases</div>${d.cases.map((k) => `<div class="li"><div class="li-main"><b>${esc(k.number)}</b><span class="hint">${esc(k.title)} · ${k.status === 'open' ? 'open' : esc(D.VERDICT[k.verdict] || k.status)} · ${date(k.createdAt)}</span></div></div>`).join('') || empty('None')}</div>
        <div class="card"><div class="card-title">Businesses</div>${d.businesses.map((b) => `<div class="li"><div class="li-main"><b>${esc(b.name)}</b><span class="hint">${esc(b.licenseNo)} · ${esc(b.kind || '')}</span></div>${pill(cap(b.status), b.status === 'active' ? 'on' : 'warn')}</div>`).join('') || empty('None')}</div>
        <div class="card"><div class="card-title">Attorneys</div>${d.lawyers.map((l) => `<div class="li"><div class="li-main"><b>${esc(l.name)}</b><span class="hint">${esc(l.number)}${l.firm ? ' · ' + esc(l.firm) : ''}</span></div>${pill(cap(l.status), l.status === 'active' ? 'on' : 'bad')}</div>`).join('') || empty('None')}</div></div>`;
    };
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(run, 300); });
    q.focus(); run();
  };

  // ---------------------------------------------------------------- notices
  views.notices = async (h, arg, alive) => {
    const d = await fresh();
    if (!alive()) return;
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Notices</div><div class="v-sub">Letters from the court about your cases, bills and requests.</div></div>${d.unread ? '<button class="btn" data-all>Mark all read</button>' : ''}</div>
      <div class="card">${d.notices.length ? d.notices.map((n) => `<div class="notice ${n.readAt ? 'read' : 'unread'}" data-n="${n.id}"><span class="n-dot"></span><div class="flex1"><b>${esc(n.title)}</b> ${n.test ? pill('Test', 'test') : ''}<span class="hint"> · ${ago(n.at)}</span>
        ${n.body ? `<div class="n-body">${esc(n.body)}</div>` : ''}${n.caseId ? `<span class="lnk" data-case="${n.caseId}">Open the case →</span>` : ''}</div></div>`).join('') : empty('No notices', '✉')}</div>`;
    const all = $('[data-all]', h); if (all) all.onclick = async () => { await call('noticeRead', { all: true }); rerender(); };
    $$('.notice.unread', h).forEach((el) => el.addEventListener('mouseenter', async () => { if (el.classList.contains('read')) return; el.classList.replace('unread', 'read'); await call('noticeRead', { id: +el.dataset.n }); fresh(); }, { once: true }));
  };
})();
