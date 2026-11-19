// es_mdt 2.1.0: tickets and impound on the court side.
//   Tablet · Ticket contests: open contests (soonest to lapse first) with the ticket, the citizen's reason and the
//     officer's statement; a judge rules: dismiss, reduce (a new amount) or uphold. Ruled ones are the history.
//   Portal · My tickets: every ticket with its paper; an unsigned one can be contested before its due date (the payment
//     pauses). Portal · Impounded vehicles: what each owes now; pay and get it back once any police hold is over.
(function () {
  'use strict';
  const D = window.DOJ; if (!D) return;
  const { S, $, $$, esc, money, call, toast, busy, ago, date, dateTime, pill, empty, modal, views, R, RO, rerender } = D;
  const KIND = { citation: 'Citation', parking: 'Parking ticket', warning: 'Written warning' };
  const CAT = { infraction: 'Infraction', misdemeanor: 'Misdemeanor', felony: 'Felony' };
  const portalCmd = () => (S.lists && S.lists.portal) || 'court';

  function paper(t) {
    const signed = t.sign === 'signed', unsigned = t.sign === 'unsigned' || t.sign === 'none';
    return `<div class="rs-paper">
      <div class="rs-ph"><div class="rs-seal">★</div><div><div class="rs-pt">${esc(t.deptName || t.dept || 'Police')}</div><div class="rs-ps">State of San Andreas · ${esc(KIND[t.kind] || t.kindLabel || 'Ticket')}</div></div>
        <div class="rs-pno"><span>No.</span><b class="mono">${esc(t.number || '')}</b></div></div>
      <div class="rs-pgrid"><div><i>Issued</i><b>${dateTime(t.at || t.issuedAt)}</b></div><div><i>Officer</i><b>${esc(t.officerName || '—')}</b></div>
        <div><i>${t.kind === 'parking' ? 'Registered owner' : 'Recipient'}</i><b>${esc(t.person || '—')}</b></div><div><i>Vehicle</i><b>${t.plate ? `<span class="rs-plate">${esc(t.plate)}</span> ${esc(t.vehicleLabel || '')}` : '—'}</b></div>
        <div class="w2"><i>Location</i><b>${esc(t.location || '—')}</b></div></div>
      <table class="rs-ptab"><thead><tr><th>Code</th><th>Violation</th><th></th><th class="num">Fine</th></tr></thead><tbody>${(t.charges || []).map((c) => `<tr><td class="mono">${esc(c.code || '')}</td><td>${esc(c.title)}<span class="rs-cat">${esc(CAT[c.category] || '')}</span></td><td class="num">${(c.count || 1) > 1 ? '×' + c.count : ''}</td><td class="num">${t.kind === 'warning' ? '—' : money((c.fine || 0) * (c.count || 1))}</td></tr>`).join('')}</tbody>
        <tfoot><tr><td colspan="3">Total</td><td class="num">${t.kind === 'warning' ? 'No fine' : money(t.total || 0)}</td></tr></tfoot></table>
      ${t.notes ? `<div class="rs-pnotes"><i>Officer's notes</i>${esc(t.notes)}</div>` : ''}
      <div class="rs-pfoot"><div class="rs-sig ${signed ? 'ok' : unsigned ? 'no' : ''}"><span class="rs-sigline">${signed ? `<em>${esc(t.person || '')}</em>` : unsigned ? (t.kind === 'parking' ? 'Not signed (parking)' : 'REFUSED / NOT SIGNED') : ''}</span><i>Signature</i></div>
        <div class="rs-due">${t.dueAt ? `<i>Due</i><b>${date(t.dueAt)}</b>` : ''}</div></div></div>`;
  }
  const stPill = (t) => t.status === 'dismissed' ? pill('Dismissed', 'on') : t.status === 'void' ? pill('Void', 'off') : t.contest && t.contest.status === 'open' ? pill('Contested · paused', 'warn')
    : t.status === 'paid' || t.fineStatus === 'paid' ? pill('Paid', 'on') : t.kind === 'warning' ? pill('Warning', 'off') : t.fineStatus === 'unpaid' ? (t.dueAt && t.dueAt < Date.now() / 1000 ? pill('Overdue', 'bad') : pill('Unpaid', 'bad')) : '';

  // ---------------------------------------------------------------- tablet: contests
  views.contests = async (h, arg, alive) => {
    S.ctTab = S.ctTab || 'open';
    const r = await call('contests', { status: S.ctTab });
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = empty(r.why, '⚠'); return; }
    const X = r.data, now = Date.now() / 1000;
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Ticket contests</div><div class="v-sub">Unsigned police tickets the citizen contests. The payment is paused until you rule; no ruling in time and it is dismissed in their favour.</div></div></div>
      ${X.enabled === false ? '<div class="alert warn"><span class="a-ico">ⓘ</span><div class="li-main"><b>Contests are turned off</b><span class="hint">Tickets must be paid (/whip → Settings → MDT → Tickets).</span></div></div>' : ''}
      <div class="seg" id="ct-tabs"><button data-ct="open" class="${S.ctTab === 'open' ? 'on' : ''}">Waiting</button><button data-ct="ruled" class="${S.ctTab === 'ruled' ? 'on' : ''}">Ruled</button></div>
      <div class="ct-list">${X.rows.length ? X.rows.map((k) => {
        const left = k.lapseAt - now, soon = k.status === 'open' && left < 86400;
        return `<div class="card ct-card ${soon ? 'soon' : ''}" data-ct-id="${k.id}">
          <div class="ct-top"><span class="mono">${esc(k.number)}</span><b>${esc(k.kindLabel)} · ${money(k.total)}</b><span class="hint">${esc(k.person)} · ${esc(k.dept || '')} · ${esc(k.officerName || '')}</span>
            ${k.status === 'open' ? `<span class="ct-lapse ${soon ? 'bad' : ''}">${left > 0 ? 'Lapses ' + dateTime(k.lapseAt) : 'Lapsing now'}</span>` : pill(k.ruling === 'lapsed' ? 'Lapsed (dismissed)' : k.ruling, k.ruling === 'uphold' ? 'bad' : 'on')}</div>
          <div class="ct-body"><div class="ct-q"><i>The citizen</i>${esc(k.reason)}</div><div class="ct-q off"><i>The officer${k.statementBy ? ' · ' + esc(k.statementBy) : ''}</i>${k.statement ? esc(k.statement) : '<span class="muted">No statement yet</span>'}</div></div>
          ${k.status === 'open' ? `<div class="row end"><button class="btn small" data-ct-open="${k.id}">Read the ticket${X.canRule ? ' and rule' : ''}</button></div>` : `<div class="hint">${esc(k.judgeName || '')} · ${dateTime(k.ruledAt)}${k.reducedTo ? ' · reduced to ' + money(k.reducedTo) : ''}${k.rulingNote ? ' · ' + esc(k.rulingNote) : ''}</div>`}</div>`;
      }).join('') : empty(S.ctTab === 'open' ? 'No contests are waiting' : 'Nothing ruled yet', '⚖')}</div>`;
    $$('[data-ct]', h).forEach((b) => b.onclick = () => { S.ctTab = b.dataset.ct; rerender(); });
    $$('[data-ct-open]', h).forEach((b) => b.onclick = () => rule(X.rows.find((k) => k.id === +b.dataset.ctOpen), X.canRule));
  };

  function rule(k, canRule) {
    modal(`<div class="m-title"><span class="m-ico">⚖</span>Contest of ${esc(k.number)}</div>
      <div class="ct-mgrid"><div>${paper({ ...k, at: k.issuedAt, dueAt: null })}</div>
        <div><div class="ct-q"><i>The citizen says</i>${esc(k.reason)}</div><div class="ct-q off"><i>The officer says</i>${k.statement ? esc(k.statement) : '<span class="muted">No statement filed (the officer was asked).</span>'}</div>
          ${canRule ? `<div class="lbl mt">Ruling</div><div class="choice" data-rul style="grid-template-columns:1fr 1fr 1fr"><button type="button" data-v="dismiss"><b>Dismiss</b><span>Nothing is owed</span></button><button type="button" data-v="reduce"><b>Reduce</b><span>A lower fine</span></button><button type="button" data-v="uphold"><b>Uphold</b><span>${money(k.total)} is due</span></button></div>
          <div class="hidden mt" data-amt><div class="lbl">New amount</div><div class="money-in"><input type="number" min="1" max="${Math.max(1, k.total - 1)}" id="ct-amt" placeholder="0"></div></div>
          <div class="lbl mt">Note to both sides <span class="hint">(optional)</span></div><textarea id="ct-note" rows="3" maxlength="500"></textarea>
          <div class="hint mt">Upheld or reduced: the citizen gets the time that was left before the contest (at least a day) to pay.</div>` : '<div class="help mt">Only a judge rules.</div>'}
          <div class="form-err" data-err></div></div></div>
      <div class="row end"><button class="btn ghost" data-x>Close</button>${canRule ? '<button class="btn gold" data-ok disabled>Rule</button>' : ''}</div>`, (card, closeIt) => {
      let v = null;
      $$('[data-rul] button', card).forEach((b) => b.onclick = () => { v = b.dataset.v; $$('[data-rul] button', card).forEach((x) => x.classList.toggle('on', x === b)); $('[data-amt]', card).classList.toggle('hidden', v !== 'reduce'); $('[data-ok]', card).disabled = false; });
      const ok = $('[data-ok]', card);
      if (ok) ok.onclick = () => busy(ok, async () => {
        const r = await call('contestRule', { id: k.id, ruling: v, amount: v === 'reduce' ? +$('#ct-amt', card).value : null, note: $('#ct-note', card).value });
        if (!r.ok) { $('[data-err]', card).textContent = r.why; return; }
        closeIt(); toast('Ruled: ' + v, 'ok'); setTimeout(rerender, 150);
      });
    }, 'wide');
  }

  // ---------------------------------------------------------------- portal: my tickets
  views.ptickets = async (h, arg, alive) => {
    const r = await call('tickets');
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = empty(r.why, '⚠'); return; }
    const X = r.data;
    h.innerHTML = `<div class="v-head"><div><div class="v-title">My tickets</div><div class="v-sub">Police tickets written to you or your vehicles. Pay them under Payments by the due date${X.contests ? '; an unsigned ticket can be contested before then' : ''}.</div></div></div>
      <div class="card flush">${X.rows.length ? `<table><thead><tr><th>Ticket</th><th>What</th><th>Fine</th><th>Signed</th><th>Due</th><th>Status</th><th></th></tr></thead><tbody>${X.rows.map((t) => `<tr class="click" data-pt="${t.id}">
          <td><span class="mono">${esc(t.number)}</span><span class="sub">${esc(t.kindLabel)}</span></td><td><b>${esc((t.charges || []).map((c) => c.title).join(', '))}</b><span class="sub">${esc(t.dept || '')} · ${date(t.at)}${t.plate ? ' · ' + esc(t.plate) : ''}</span></td>
          <td>${t.kind === 'warning' ? '—' : money(t.total)}</td><td>${t.sign === 'signed' ? pill('Signed', 'on') : t.kind === 'warning' ? '' : pill('Not signed', 'warn')}</td>
          <td>${t.dueAt && t.fineStatus === 'unpaid' ? date(t.dueAt) : t.contest && t.contest.status === 'open' ? 'Paused' : '—'}</td><td>${stPill(t)}</td>
          <td>${t.contestable ? `<button class="btn small gold" data-contest="${t.id}">Contest</button>` : ''}</td></tr>`).join('')}</tbody></table>` : empty('You have no tickets', '✓')}</div>
      ${X.contests ? `<div class="help">You can contest a ticket you did <b>not</b> sign. The payment pauses while a judge decides; if no judge rules within ${X.lapseDays} days, it is dismissed in your favour. A signed ticket can only be paid.</div>` : ''}`;
    $$('[data-pt]', h).forEach((tr) => tr.onclick = (e) => { if (e.target.closest('[data-contest]')) return; const t = X.rows.find((x) => x.id === +tr.dataset.pt); modal(`${paper(t)}${t.contest ? `<div class="ct-q mt"><i>Your contest · ${t.contest.status === 'open' ? 'waiting for a judge' : 'ruled: ' + esc(t.contest.ruling)}</i>${esc(t.contest.reason)}</div>` : ''}<div class="row end mt"><button class="btn ghost" data-x>Close</button></div>`, null, 'wide'); });
    $$('[data-contest]', h).forEach((b) => b.onclick = () => contest(X.rows.find((x) => x.id === +b.dataset.contest), X.lapseDays));
  };

  function contest(t, lapseDays) {
    modal(`<div class="m-title"><span class="m-ico">⚖</span>Contest ${esc(t.number)}</div>
      <div class="help">${esc(t.kindLabel)} · ${money(t.total)} · ${esc((t.charges || []).map((c) => c.title).join(', '))}</div>
      <div class="lbl mt">Why is this ticket wrong?</div><textarea id="pc-why" rows="6" maxlength="1000" placeholder="Tell the judge what happened. The officer is asked for a statement too."></textarea>
      <div class="hint">The payment is paused until a judge rules (at the latest ${lapseDays} days; no ruling and it is dismissed). Dismissed: you owe nothing. Reduced or upheld: you get the time that was left to pay.</div>
      <div class="form-err" data-err></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn gold" data-ok>File the contest</button></div>`, (card, closeIt) => {
      const ok = $('[data-ok]', card);
      ok.onclick = () => busy(ok, async () => {
        const r = await call('contest', { id: t.id, reason: $('#pc-why', card).value });
        if (!r.ok) { $('[data-err]', card).textContent = r.why; return; }
        closeIt(); toast('Contest filed: the payment is paused', 'ok'); setTimeout(rerender, 150);
      });
    });
  }

  // ---------------------------------------------------------------- portal: impounded vehicles
  views.pimpound = async (h, arg, alive) => {
    const r = await call('impounds');
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = empty(r.why, '⚠'); return; }
    const rows = r.data.rows || [];
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Impounded vehicles</div><div class="v-sub">Your vehicles the police took. Pay the fees to get one back once any police hold is over.</div></div></div>
      <div class="pi-grid">${rows.length ? rows.map((x) => {
        const live = x.status === 'held' || x.status === 'pending';
        return `<div class="card pi-card ${x.status}"><div class="pi-top"><span class="rs-plate">${esc(x.plate || '?')}</span><b>${esc(x.vehicleLabel || 'Vehicle')}</b>
            ${x.status === 'pending' ? pill('Marked', 'warn') : x.status === 'held' ? pill('At ' + x.lotLabel, 'bad') : pill(x.status === 'cancelled' ? 'Called off' : 'Released', 'on')}</div>
          <div class="hint">${esc(x.reason)} · ${esc(x.dept || '')} · ${date(x.at)}</div>
          ${live ? `<div class="pi-bill"><div><span>Impound fee</span><b>${money(x.owe.fee)}</b></div><div><span>Storage · ${x.owe.days} day${x.owe.days === 1 ? '' : 's'} (${money(x.dailyFee)}/day, at most ${money(x.storageCap)})</span><b>${money(x.owe.storage)}</b></div><div class="tot"><span>To pay now</span><b>${money(x.owe.total)}</b></div></div>
            ${x.status === 'pending' ? '<div class="alert"><span class="a-ico">ⓘ</span><div class="li-main"><b>Marked for impound</b><span class="hint">It goes to the lot the next time it is stored; it cannot be taken out until then.</span></div></div>'
              : x.held ? `<div class="alert bad"><span class="a-ico">⛓</span><div class="li-main"><b>Police hold${x.holdUntilTs ? ' until ' + dateTime(x.holdUntilTs) : ''}</b><span class="hint">${x.holdUntilTs ? 'You can pay and get it back after that.' : 'Until an officer releases it.'}</span></div></div>`
              : `<div class="row end"><div class="seg" data-pm="${x.id}"><button class="on" data-v="bank">Bank</button><button data-v="cash">Cash</button></div><button class="btn gold" data-ipay="${x.id}">Pay ${money(x.owe.total)} and release</button></div>`}` : `<div class="hint">${x.paid ? money(x.paid) + ' paid · ' : ''}${x.releasedTs ? 'released ' + date(x.releasedTs) : ''}</div>`}
          <div class="form-err" data-ierr="${x.id}"></div></div>`;
      }).join('') : empty('None of your vehicles is impounded', '✓')}</div>`;
    $$('[data-pm]', h).forEach((s) => $$('button', s).forEach((b) => b.onclick = () => $$('button', s).forEach((x) => x.classList.toggle('on', x === b))));
    $$('[data-ipay]', h).forEach((b) => b.onclick = () => busy(b, async () => {
      const id = +b.dataset.ipay, m = $(`[data-pm="${id}"] button.on`, h);
      const x = await call('impoundPay', { id, method: m ? m.dataset.v : 'bank' });
      if (!x.ok) { $(`[data-ierr="${id}"]`, h).textContent = x.why; return; }
      toast(`Paid ${money(x.data.amount)}: pick it up at ${x.data.lot}`, 'ok'); setTimeout(rerender, 150);
    }));
  };
})();
