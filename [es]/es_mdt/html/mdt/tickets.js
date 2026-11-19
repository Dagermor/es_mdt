// es_mdt 2.1.0: the MDT's Tickets and Impound lot tabs, and what a vehicle's / person's page shows of them.
//   Tickets: mine / the department's / contested / unpaid / unsigned; a ticket opens as its paper, with its contest (the
//     citizen's reason, my statement) and Void.
//   Impound lot: everything on the lot or marked, what each owes now, holds; Release (charge as an invoice or waive),
//     change the hold (shorter than it was = an override: a reason, logged); released ones are the history.
//   A vehicle's page: Impound (the same form as /mdtimpound: MDT.impoundForm in roadside.js), its impound history
//     (released ones stay), its tickets. A person's page: their tickets.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, said, busy, ago, date, dateTime, modal, pill, empty, VIEWS, HOOK, toast, money, can, go } = M;
  const RO = () => !!(S.ctx && S.ctx.readOnly);
  const KIND = { citation: ['Citation', 'accent'], parking: ['Parking', ''], warning: ['Warning', 'off'] };
  const kindPill = (k) => { const x = KIND[k] || [k, '']; return pill(x[0], x[1]); };
  const signPill = (s) => s === 'signed' ? pill('Signed', 'on') : s === 'unsigned' ? pill('Refused / unsigned', 'warn') : s === 'none' ? pill('Unsigned', 'off') : s === 'pending' ? pill('Signing…', 'accent') : '';
  function statusPill(t) {
    if (t.status === 'dismissed') return pill('Dismissed', 'off');
    if (t.status === 'void') return pill('Void', 'off');
    if (t.contest === 'open' || (t.contest && t.contest.status === 'open')) return pill('Contested', 'warn');
    if (t.status === 'paid' || t.fineStatus === 'paid') return pill('Paid', 'on');
    if (t.kind === 'warning') return pill('Warning', 'off');
    if (t.fineStatus === 'unpaid') return t.dueAt && t.dueAt < Date.now() / 1000 ? pill('Overdue', 'bad') : pill('Unpaid', 'bad');
    return '';
  }
  const TABS = [['mine', 'Mine'], ['dept', 'Department'], ['contested', 'Contested'], ['unpaid', 'Unpaid'], ['unsigned', 'Unsigned']];

  function ticketRows(rows, opts) {
    opts = opts || {};
    if (!rows.length) return empty(opts.none || 'No tickets', '✎');
    return `<div class="tk-table"><div class="tk-tr th"><span>No.</span><span>Kind</span><span>${opts.noWho ? 'Officer' : 'Who'}</span><span class="num">Fine</span><span>Signature</span><span>Status</span><span>Issued</span></div>
      ${rows.map((t) => `<div class="tk-tr click" data-tk="${t.id}"><span class="mono">${esc(t.number)}</span><span>${kindPill(t.kind)}</span>
        <span class="tk-who">${opts.noWho ? esc(t.officerName || '') : `${t.person ? `<b>${esc(t.person)}</b>` : ''}${t.plate ? ` <span class="plate sm">${esc(t.plate)}</span>` : ''}`}</span>
        <span class="num">${t.kind === 'warning' ? '—' : money(t.total)}</span><span>${signPill(t.sign)}</span><span>${statusPill(t)}${t.contest === 'open' && !t.hasStatement ? ' <span class="tk-dot" title="Waiting for the officer\'s statement"></span>' : ''}</span>
        <span class="hint">${ago(t.at)}</span></div>`).join('')}</div>`;
  }

  // ---------------------------------------------------------------- one ticket
  async function ticketOpen(id, after) {
    const r = await call('ticket', { id });
    if (!r.ok) return said(r);
    const t = r.data, k = t.contest;
    modal(`<div class="tk-modal">
        <div class="m-title">${esc(t.kindLabel)} ${esc(t.number)} ${statusPill(Object.assign({}, t, { contest: k }))}</div>
        <div class="tk-mgrid">
          <div>${M.ticketPaper ? M.ticketPaper(t) : ''}</div>
          <div class="tk-side">
            ${k ? `<div class="card tk-contest"><div class="card-title">Contest ${k.status === 'open' ? pill('Open', 'warn') : pill('Ruled: ' + (k.ruling || ''), k.ruling === 'uphold' ? 'bad' : 'on')}</div>
              <div class="tk-q"><i>The citizen says</i>${esc(k.reason)}</div>
              ${k.statement ? `<div class="tk-q off"><i>Officer's statement · ${esc(k.statementBy || '')} ${ago(k.statementAt)}</i>${esc(k.statement)}</div>` : ''}
              ${k.status === 'open' ? `<div class="hint">A judge rules (DOJ tablet → Ticket contests). No ruling by <b>${dateTime(k.lapseAt)}</b> and it is dismissed.</div>` : `<div class="hint">${esc(k.judgeName || 'The court')} · ${dateTime(k.ruledAt)}${k.reducedTo ? ' · reduced to ' + money(k.reducedTo) : ''}${k.rulingNote ? ' · ' + esc(k.rulingNote) : ''}</div>`}
              ${t.canStatement && !RO() ? `<label class="lbl">${k.statement ? 'Change your statement' : 'Your statement for the judge'}</label><textarea id="tk-st" maxlength="1000" rows="5" placeholder="What you saw, the speed, the signs, anything the judge should know…">${esc(k.statement || '')}</textarea>
                <div class="row end"><button class="btn small accent" id="tk-st-go" data-primary>File statement</button></div>` : ''}</div>` : ''}
            ${t.contestable ? '<div class="hint">Not signed: the citizen may contest it in the court portal until the due date.</div>' : ''}
            ${t.canVoid && !RO() ? `<div class="card"><div class="card-title">Void this ticket</div><input type="text" id="tk-why" maxlength="200" placeholder="Why (e.g. wrong person, written in error)"><div class="row end"><button class="btn small danger" id="tk-void">Void</button></div></div>` : ''}
          </div>
        </div>
        <div class="row end"><button class="btn ghost" data-x>Close</button></div></div>`, (card, closeIt) => {
      card.classList.add('wide', 'tk-wide');
      const st = $('#tk-st-go', card);
      if (st) st.onclick = (e) => busy(e.currentTarget, async () => { const x = await call('tkStatement', { id: t.id, text: $('#tk-st', card).value }); said(x, 'Statement filed'); if (x.ok) { closeIt(); M.loadBadges(); if (after) after(); } });
      const vd = $('#tk-void', card);
      if (vd) vd.onclick = (e) => busy(e.currentTarget, async () => { const x = await call('tkVoid', { id: t.id, reason: $('#tk-why', card).value }); said(x, 'Voided'); if (x.ok) { closeIt(); if (after) after(); } });
    });
  }
  M.ticketOpen = ticketOpen;

  VIEWS.tickets = async (v) => {
    S.tkTab = S.tkTab || 'mine';
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Tickets</div><div class="hint">Citations, parking tickets and warnings written at the roadside${can('tickets_issue') ? ' · write one with <b>/ticket</b> (or its controller button)' : ''}</div></div></div>
      <div id="tk-need"></div>
      <div class="tabs" id="tk-tabs">${TABS.map(([k, l]) => `<button class="tab${S.tkTab === k ? ' on' : ''}" data-tt="${k}">${l}</button>`).join('')}</div>
      <div class="filters"><input type="text" id="tk-q" placeholder="Number, plate or officer…" autocomplete="off" maxlength="40" value="${esc(S.tkQ || '')}"></div>
      <div id="tk-body"><div class="loading-row"><div class="spin"></div></div></div>`;
    const load = async () => {
      const tab = S.tkTab;
      const r = await call('tickets', { scope: tab === 'mine' ? 'mine' : 'dept', filter: ['contested', 'unpaid', 'unsigned'].includes(tab) ? tab : null, q: S.tkQ || '' });
      if (S.view !== 'tickets' || !$('#tk-body')) return;
      if (!r.ok) { $('#tk-body').innerHTML = empty(r.why || 'Could not load', '✎'); return; }
      const D = r.data;
      $('#tk-need').innerHTML = D.needStatement ? `<div class="tk-banner">⚖ <b>${D.needStatement} contested ticket${D.needStatement > 1 ? 's' : ''}</b> of yours ${D.needStatement > 1 ? 'are' : 'is'} waiting for your statement. Open ${D.needStatement > 1 ? 'them' : 'it'} under Contested.</div>` : '';
      if (!D.contests && tab === 'contested') { $('#tk-body').innerHTML = empty('Contests are turned off: every ticket must be paid.', '⚖'); return; }
      $('#tk-body').innerHTML = ticketRows(D.rows, { none: tab === 'mine' ? 'You have not written a ticket yet' : 'Nothing here' });
      $$('[data-tk]', v).forEach((el) => el.onclick = () => ticketOpen(+el.dataset.tk, load));
    };
    $$('[data-tt]', v).forEach((b) => b.onclick = () => { S.tkTab = b.dataset.tt; $$('[data-tt]', v).forEach((x) => x.classList.toggle('on', x === b)); load(); });
    let qt = null;
    $('#tk-q').oninput = (e) => { clearTimeout(qt); qt = setTimeout(() => { S.tkQ = e.target.value.trim(); load(); }, 250); };
    load();
  };

  // ---------------------------------------------------------------- the impound lot
  const IMP_ST = { pending: ['Marked', 'accent'], held: ['On the lot', 'warn'], released: ['Released', 'on'], cancelled: ['Called off', 'off'] };
  const impPill = (s) => { const x = IMP_ST[s] || [s, '']; return pill(x[0], x[1]); };
  function holdLine(r) {
    if (r.status !== 'held' && r.status !== 'pending') return '';
    if (r.holdOpen) return '<span class="imp-hold open">⛓ Hold until released</span>';
    if (r.holdUntilTs) return `<span class="imp-hold">⛓ Hold until ${dateTime(r.holdUntilTs)}</span>`;
    return '';
  }
  function impCard(r) {
    const live = r.status === 'held' || r.status === 'pending';
    return `<div class="imp-card ${r.status}" data-imp="${r.id}">
      <div class="imp-top">${r.photo ? `<div class="imp-ph" data-ph="${esc(r.photo)}"><img src="${esc(r.photo)}" alt="" loading="lazy" onerror="this.parentNode.classList.add('none')"></div>` : '<div class="imp-ph none">⛍</div>'}
        <div class="imp-main"><div class="imp-l1"><span class="plate">${esc(r.plate || '?')}</span>${impPill(r.status)}${r.override ? pill('Override', 'bad') : ''}</div>
          <b>${esc(r.vehicleLabel || 'Vehicle')}</b><span class="hint">${r.owner ? 'Owner ' + esc(r.owner) : 'No owner'} · ${esc(r.lotLabel)}</span></div>
        ${live ? `<div class="imp-owe"><i>Owes now</i><b>${money(r.owe.total)}</b><span class="hint">${money(r.owe.fee)} fee${r.owe.storage ? ' + ' + money(r.owe.storage) + ' storage (' + r.owe.days + 'd)' : ''}</span></div>` : `<div class="imp-owe"><i>${r.paid ? 'Paid' : 'Fees'}</i><b>${r.paid ? money(r.paid) : '—'}</b></div>`}</div>
      <div class="imp-why"><b>${esc(r.reason)}</b>${r.notes ? ' · ' + esc(r.notes) : ''}</div>
      <div class="imp-foot"><span class="hint">${esc(r.officerName || '')} · ${esc(r.dept || '')} · ${ago(r.at)}${r.status === 'pending' ? ' · taken when next stored' : ''}${!live && r.releasedBy ? ' · released by ' + esc(r.releasedBy) + ' ' + ago(r.releasedTs) : ''}</span>${holdLine(r)}
        ${live && !RO() ? `<span class="imp-acts">${S.impSet && S.impSet.canHold ? `<button class="btn small" data-hold="${r.id}">⛓ Hold</button>` : ''}${S.impSet && S.impSet.canLot ? `<button class="btn small accent" data-rel="${r.id}">Release</button>` : ''}</span>` : ''}
        <button class="btn small ghost" data-veh="${r.vehicleId}">Vehicle →</button></div>
      ${!live && r.releaseNote ? `<div class="hint">${esc(r.releaseNote)}</div>` : ''}</div>`;
  }

  function releaseForm(r, after) {
    const set = S.impSet || {};
    const hold = r.held, owe = r.owe.total;
    modal(`<div class="m-title">Release ${esc(r.plate || '')} · ${esc(r.vehicleLabel || '')}</div>
      ${hold ? `<div class="imp-warn">⛓ It is on a hold${r.holdUntilTs ? ' until ' + dateTime(r.holdUntilTs) : ' until an officer releases it'}. Releasing it now is an <b>override</b>: ${set.canOverride ? 'give a reason; it is logged.' : 'your rank cannot do it.'}</div>` : ''}
      ${r.status === 'pending' ? '<p class="m-text">It never reached the lot: releasing calls the impound off (no fees).</p>' : `
      <div class="imp-bill"><div><span>Impound fee</span><b>${money(r.owe.fee)}</b></div><div><span>Storage (${r.owe.days} day${r.owe.days === 1 ? '' : 's'})</span><b>${money(r.owe.storage)}</b></div><div class="tot"><span>Owed now</span><b>${money(owe)}</b></div></div>
      <div class="seg" id="rl-fee"><button data-f="charge" class="on">Invoice the owner ${money(owe)}</button><button data-f="waive">Waive the fees</button></div>`}
      <label class="lbl">${hold ? 'Reason for the early release' : 'Note'} <span class="hint" id="rl-req">${hold ? '(required)' : '(required when waiving)'}</span></label>
      <input type="text" id="rl-note" maxlength="300" placeholder="${hold ? 'e.g. Evidence processed, case closed' : 'e.g. Wrongly towed'}">
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="rl-go" data-primary${hold && !set.canOverride ? ' disabled' : ''}>${hold ? 'Override and release' : 'Release'}</button></div>`, (card, closeIt) => {
      let fee = 'charge';
      $$('[data-f]', card).forEach((b) => b.onclick = () => { fee = b.dataset.f; $$('[data-f]', card).forEach((x) => x.classList.toggle('on', x === b)); });
      $('#rl-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const x = await call('impRelease', { id: r.id, fees: fee, note: $('#rl-note', card).value });
        said(x, x.ok ? (x.data.status === 'cancelled' ? 'Impound called off' : x.data.invoice ? `Released · ${money(x.data.amount)} invoiced to the owner` : 'Released') : null);
        if (x.ok) { closeIt(); if (after) after(); }
      });
    });
  }

  function holdForm(r, after) {
    const set = S.impSet || {};
    modal(`<div class="m-title">Hold · ${esc(r.plate || '')}</div>
      <p class="m-text">Now: ${r.holdOpen ? 'held until an officer releases it' : r.holdUntilTs ? 'held until ' + dateTime(r.holdUntilTs) : 'no hold'}. Making it shorter (or lifting it) is an override${set.canOverride ? ': give a reason.' : ', which your rank cannot do.'}</p>
      <div class="seg" id="hf-mode"><button data-m="none">No hold</button><button data-m="days" class="on">For days</button><button data-m="open">Until released</button></div>
      <div class="row" id="hf-days" style="margin-top:8px"><input type="number" id="hf-n" min="1" max="${set.maxHoldDays || 30}" value="3" style="width:90px"><span class="hint">days from now (at most ${set.maxHoldDays || 30})</span></div>
      <label class="lbl">Reason <span class="hint">(required for a shorter hold)</span></label><input type="text" id="hf-note" maxlength="300">
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="hf-go" data-primary>Save hold</button></div>`, (card, closeIt) => {
      let m = 'days';
      $$('[data-m]', card).forEach((b) => b.onclick = () => { m = b.dataset.m; $$('[data-m]', card).forEach((x) => x.classList.toggle('on', x === b)); $('#hf-days', card).style.display = m === 'days' ? '' : 'none'; });
      $('#hf-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const x = await call('impHold', { id: r.id, hold: m, holdDays: +$('#hf-n', card).value, note: $('#hf-note', card).value });
        said(x, 'Hold saved'); if (x.ok) { closeIt(); if (after) after(); }
      });
    });
  }

  VIEWS.impound = async (v) => {
    S.impTab = S.impTab || 'lot';
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Impound lot</div><div class="hint">Vehicles held or marked for impound and what each owes now · street impound with <b>/mdtimpound</b></div></div>
        <div class="imp-sum" id="imp-sum"></div></div>
      <div class="tabs" id="tk-tabs"><button class="tab${S.impTab === 'lot' ? ' on' : ''}" data-it="lot">On the lot</button><button class="tab${S.impTab === 'released' ? ' on' : ''}" data-it="released">Released (history)</button></div>
      <div class="filters"><input type="text" id="imp-q" placeholder="Plate or model…" autocomplete="off" maxlength="20" value="${esc(S.impQ || '')}"></div>
      <div id="imp-body"><div class="loading-row"><div class="spin"></div></div></div>`;
    const load = async () => {
      const r = await call('impList', { status: S.impTab === 'released' ? 'released' : 'lot', q: S.impQ || '' });
      if (S.view !== 'impound' || !$('#imp-body')) return;
      if (!r.ok) { $('#imp-body').innerHTML = empty(r.why || 'Could not load', '⛍'); return; }
      const D = r.data; S.impSet = D.settings; S.impRows = D.rows;
      if (!D.enabled) $('#imp-body').innerHTML = empty('Impound is turned off (/whip → Settings → MDT → Impound).', '⛍');
      const held = D.rows.filter((x) => x.status === 'held').length, marked = D.rows.filter((x) => x.status === 'pending').length;
      $('#imp-sum').innerHTML = S.impTab === 'lot' ? `<div class="imp-stat"><b>${held}</b><span>on the lot</span></div><div class="imp-stat"><b>${marked}</b><span>marked</span></div><div class="imp-stat gold"><b>${money(D.outstanding)}</b><span>outstanding fees</span></div>` : '';
      if (!D.enabled) return;
      $('#imp-body').innerHTML = D.rows.length ? `<div class="imp-grid">${D.rows.map(impCard).join('')}</div>` : empty(S.impTab === 'lot' ? 'The lot is empty' : 'No releases yet', '⛍');
      $$('[data-rel]', v).forEach((b) => b.onclick = (e) => { e.stopPropagation(); releaseForm(D.rows.find((x) => x.id === +b.dataset.rel), load); });
      $$('[data-hold]', v).forEach((b) => b.onclick = (e) => { e.stopPropagation(); holdForm(D.rows.find((x) => x.id === +b.dataset.hold), load); });
      $$('[data-veh]', v).forEach((b) => b.onclick = (e) => { e.stopPropagation(); go('vehicles', +b.dataset.veh); });
      $$('[data-ph]', v).forEach((b) => b.onclick = (e) => { e.stopPropagation(); if (window.Lightbox) window.Lightbox.open([{ src: b.dataset.ph, title: 'Impound photo' }], 0); });
    };
    $$('[data-it]', v).forEach((b) => b.onclick = () => { S.impTab = b.dataset.it; $$('[data-it]', v).forEach((x) => x.classList.toggle('on', x === b)); load(); });
    let qt = null;
    $('#imp-q').oninput = (e) => { clearTimeout(qt); qt = setTimeout(() => { S.impQ = e.target.value.trim(); load(); }, 250); };
    load();
  };

  // ---------------------------------------------------------------- the impound form from the MDT
  async function impoundFromMdt(vehicleId, after) {
    const r = await call('impForm', { vehicleId });
    if (!r.ok) return said(r);
    modal('<div></div>', (card, closeIt) => {
      card.classList.add('wide', 'rs-modal');
      M.impoundForm(card, r.data, (body) => call('impSave', body), (res) => {
        closeIt();
        toast(res.status === 'pending' ? 'Marked: it goes to the lot the next time it is stored' : 'Impounded' + (res.bolosClosed ? ` · ${res.bolosClosed} BOLO(s) closed` : ''), 'ok');
        if (after) after();
      }, closeIt);
    });
  }
  M.impoundFromMdt = impoundFromMdt;

  // a vehicle's page: Impound, its impound history (kept), its tickets
  const prevVehicle = HOOK.vehicle;
  HOOK.vehicle = async (box, x, reload) => {
    if (prevVehicle) prevVehicle(box, x, reload);
    const acts = $('.prof-actions', box);
    const [ri, rt] = await Promise.all([call('impVehicle', { vehicleId: x.vehicleId }), call('tickets', { vehicleId: x.vehicleId })]);
    if (!box.isConnected) return;
    const I = ri.ok ? ri.data : { rows: [] };
    S.impSet = I.settings || S.impSet;
    const active = (I.rows || []).find((r) => r.status === 'held' || r.status === 'pending');
    const tags = $('.res-tags', box);
    if (tags && active) tags.insertAdjacentHTML('afterbegin', active.status === 'pending' ? pill('Marked for impound', 'accent') : pill('Impounded', 'bad'));
    if (acts && I.canImpound && !RO() && !active) {
      acts.insertAdjacentHTML('afterbegin', '<button class="btn small danger" id="va-imp" data-probe-press>⛍ Impound</button>');
      $('#va-imp', box).onclick = () => impoundFromMdt(x.vehicleId, reload);
    }
    const tk = rt.ok ? rt.data.rows : [];
    box.insertAdjacentHTML('beforeend', `<div class="cols2 imp-vcols">
      <div class="card"><div class="card-title">Impounds ${I.rows.length ? `<span class="hint">${I.rows.length} on record</span>` : ''}</div>
        ${active ? `<div class="imp-now ${active.status}"><div><b>${active.status === 'pending' ? 'Marked: goes to the lot when it is next stored' : 'On the lot: ' + esc(active.lotLabel)}</b><span class="hint">${esc(active.reason)} · ${esc(active.officerName || '')} · ${ago(active.at)}</span>${holdLine(active)}</div>
          <div class="imp-owe sm"><i>Owes</i><b>${money(active.owe.total)}</b></div>
          ${!RO() ? `<div class="imp-acts">${S.impSet && S.impSet.canHold ? `<button class="btn small" id="vi-hold">⛓ Hold</button>` : ''}${S.impSet && S.impSet.canLot ? `<button class="btn small accent" id="vi-rel">Release</button>` : ''}</div>` : ''}</div>` : ''}
        ${(I.rows || []).filter((r) => r !== active).map((r) => `<div class="li"><span>${impPill(r.status)}</span><div class="li-main"><b>${esc(r.reason)}</b><span class="hint">${date(r.at)} · ${esc(r.officerName || '')}${r.releasedBy ? ' · released by ' + esc(r.releasedBy) : ''}${r.paid ? ' · ' + money(r.paid) + ' paid' : ''}${r.override ? ' · override' : ''}</span></div></div>`).join('')
          || (active ? '' : empty('Never impounded'))}</div>
      <div class="card"><div class="card-title">Tickets</div>${tk.length ? tk.map((t) => `<div class="li click" data-tk="${t.id}"><span class="mono">${esc(t.number)}</span><div class="li-main"><b>${esc(t.kindLabel)}${t.person ? ' · ' + esc(t.person) : ''}</b><span class="hint">${date(t.at)} · ${t.kind === 'warning' ? 'warning' : money(t.total)}</span></div>${statusPill(t)}</div>`).join('') : empty('No tickets')}</div>
    </div>`);
    if ($('#vi-rel', box)) $('#vi-rel', box).onclick = () => releaseForm(active, reload);
    if ($('#vi-hold', box)) $('#vi-hold', box).onclick = () => holdForm(active, reload);
    $$('[data-tk]', box).forEach((el) => el.onclick = () => ticketOpen(+el.dataset.tk, reload));
  };

  // a person's page: their tickets
  const prevPerson = HOOK.person;
  HOOK.person = async (box, p, reload) => {
    if (prevPerson) prevPerson(box, p, reload);
    const r = await call('tickets', { charId: p.charId });
    if (!r.ok || !box.isConnected || $('#pp-tickets', box)) return;
    const rows = r.data.rows || [];
    if (!rows.length) return;
    const owing = rows.filter((t) => t.fineStatus === 'unpaid').reduce((a, t) => a + t.total, 0);
    box.insertAdjacentHTML('beforeend', `<div class="card" id="pp-tickets"><div class="card-title">Tickets <span class="hint">${rows.length}${owing ? ' · ' + money(owing) + ' unpaid' : ''}</span></div>${ticketRows(rows.slice(0, 12), { noWho: true })}</div>`);
    $$('#pp-tickets [data-tk]', box).forEach((el) => el.onclick = () => ticketOpen(+el.dataset.tk, reload));
  };
})();
