// es_mdt 2.1.0: the roadside forms, shown over the game without the MDT (mdt/client/roadside.lua):
//   ticket   /ticket: the kind, who (people close by) or what (a parked vehicle), charges from the penal code, notes
//   sign     the recipient: the ticket, Sign or Refuse, a countdown (no answer = unsigned)
//   paper    the paper ticket (the item, or after issuing): a printable view
//   impound  /mdtimpound: the impound form (the same one the MDT's vehicle page opens: window.MDT.impoundForm)
// Controller: every control is a button or a field (html/pad.js rings them; A on a field opens the keyboard).
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { post, esc, money } = M;
  let root = null, mode = null, timer = null;

  const fmtDate = (ts) => ts ? new Date(ts * 1000).toLocaleDateString(undefined, { day: '2-digit', month: 'short', year: 'numeric' }) : '—';
  const fmtTime = (ts) => ts ? new Date(ts * 1000).toLocaleString(undefined, { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—';
  const KINDS = { citation: ['Citation', '§'], parking: ['Parking ticket', 'P'], warning: ['Written warning', '!'] };
  const CAT = { infraction: 'Infraction', misdemeanor: 'Misdemeanor', felony: 'Felony' };

  function stopTimer() { if (timer) { clearInterval(timer); timer = null; } }
  function hide() { stopTimer(); if (root) { const r = root; r.classList.remove('shown'); setTimeout(() => r.remove(), 160); root = null; mode = null; } }
  function close() { post('rsClose'); }
  function frame(cls, inner) {
    hide();
    root = document.createElement('div');
    root.className = 'rs-wrap';
    root.innerHTML = `<div class="rs-card ${cls}" role="dialog" aria-modal="true">${inner}</div>`;
    document.body.appendChild(root);
    requestAnimationFrame(() => root && root.classList.add('shown'));
    return root;
  }
  const q = (s) => root && root.querySelector(s);
  const qa = (s) => root ? Array.from(root.querySelectorAll(s)) : [];
  function err(box, text) {
    let n = box.querySelector('.rs-err');
    if (!text) { if (n) n.remove(); return; }
    if (!n) { n = document.createElement('div'); n.className = 'rs-err'; box.querySelector('.rs-foot').before(n); }
    n.textContent = text;
  }

  // ---------------------------------------------------------------- the paper ticket (also the MDT's "Paper" view)
  function paperHtml(t) {
    const k = KINDS[t.kind] || [t.kindLabel || 'Ticket', '§'];
    const signed = t.sign === 'signed', unsigned = t.sign === 'unsigned' || t.sign === 'none';
    const charges = (t.charges || []).map((c) => `<tr><td class="mono">${esc(c.code || '')}</td><td>${esc(c.title)}${c.category ? `<span class="rs-cat">${esc(CAT[c.category] || c.category)}</span>` : ''}</td><td class="num">${(c.count || 1) > 1 ? '×' + c.count : ''}</td><td class="num">${t.kind === 'warning' ? '—' : money((c.fine || 0) * (c.count || 1))}</td></tr>`).join('');
    const status = t.status === 'dismissed' ? ['Dismissed', 'ok'] : t.status === 'void' ? ['Voided', 'ok'] : t.status === 'paid' || t.fineStatus === 'paid' ? ['Paid', 'ok']
      : t.contest && t.contest.status === 'open' ? ['Contested · payment paused', 'warn'] : t.kind === 'warning' ? ['Warning · nothing to pay', 'ok'] : t.fineStatus === 'unpaid' ? ['Unpaid', 'bad'] : ['', ''];
    return `<div class="rs-paper">
      <div class="rs-ph"><div class="rs-seal">★</div><div><div class="rs-pt">${esc(t.deptName || t.dept || 'Police')}</div><div class="rs-ps">State of San Andreas · ${esc(k[0])}</div></div>
        <div class="rs-pno"><span>No.</span><b class="mono">${esc(t.number || '')}</b></div></div>
      <div class="rs-pgrid">
        <div><i>Issued</i><b>${fmtTime(t.at)}</b></div>
        <div><i>Officer</i><b>${esc(t.officerName || '—')}</b></div>
        <div><i>${t.kind === 'parking' ? 'Registered owner' : 'Recipient'}</i><b>${esc(t.person || '—')}</b></div>
        <div><i>Vehicle</i><b>${t.plate ? `<span class="rs-plate">${esc(t.plate)}</span> ${esc(t.vehicleLabel || '')}` : '—'}</b></div>
        <div class="w2"><i>Location</i><b>${esc(t.location || '—')}</b></div>
      </div>
      <table class="rs-ptab"><thead><tr><th>Code</th><th>Violation</th><th></th><th class="num">Fine</th></tr></thead><tbody>${charges}</tbody>
        <tfoot><tr><td colspan="3">Total</td><td class="num">${t.kind === 'warning' ? 'No fine' : money(t.total || 0)}</td></tr></tfoot></table>
      ${t.notes ? `<div class="rs-pnotes"><i>Officer's notes</i>${esc(t.notes)}</div>` : ''}
      <div class="rs-pfoot">
        <div class="rs-sig ${signed ? 'ok' : unsigned ? 'no' : ''}"><span class="rs-sigline">${signed ? `<em>${esc(t.person || '')}</em>` : unsigned ? (t.kind === 'parking' ? 'Not signed (parking)' : 'REFUSED / NOT SIGNED') : t.sign === 'pending' ? 'Awaiting signature…' : ''}</span><i>Signature${t.signedTs ? ' · ' + fmtTime(t.signedTs) : ''}</i></div>
        <div class="rs-due">${t.kind === 'warning' ? '' : t.dueAt ? `<i>Due</i><b>${fmtDate(t.dueAt)}</b>` : t.contest && t.contest.status === 'open' ? '<i>Due</i><b>Paused</b>' : ''}
          ${status[0] ? `<span class="rs-st ${status[1]}">${esc(status[0])}</span>` : ''}</div>
      </div>
      <div class="rs-pfine">${t.kind === 'warning' ? 'This is a written warning. Nothing is owed.' : `Pay in the court portal (<b>/court</b> → Payments) by the due date, or it is taken from your bank account on that day.${unsigned && t.kind !== 'warning' ? ' This ticket was not signed: you may contest it in the court portal before the due date.' : ''}`}</div>
      ${t.contest ? `<div class="rs-pnotes"><i>Contest</i>${esc(t.contest.status === 'open' ? 'Filed ' + fmtDate(t.contest.at) + ' · waiting for a ruling' : 'Ruled: ' + (t.contest.ruling || '') + (t.contest.reducedTo ? ' to ' + money(t.contest.reducedTo) : ''))}</div>` : ''}
    </div>`;
  }
  M.ticketPaper = paperHtml;

  function openPaper(t) {
    mode = 'paper';
    frame('paper', `${paperHtml(t)}<div class="rs-foot"><button class="rs-btn ghost" id="rs-close" data-primary>Close</button></div>`);
    q('#rs-close').onclick = close;
  }

  // ---------------------------------------------------------------- the recipient signs
  function openSign(d) {
    mode = 'sign';
    const t = d.ticket || {};
    const left = () => Math.max(0, Math.ceil((end - Date.now()) / 1000));
    const end = Date.now() + (d.seconds || 45) * 1000;
    frame('sign', `<div class="rs-head"><div class="rs-ico warn">✎</div><div><div class="rs-title">Sign this ticket?</div><div class="rs-sub">${esc(t.officerName || 'An officer')} · ${esc(t.dept || '')}</div></div>
        <div class="rs-count" id="rs-count"><svg viewBox="0 0 36 36"><circle cx="18" cy="18" r="15.5" class="bg"/><circle cx="18" cy="18" r="15.5" class="fg" id="rs-arc"/></svg><b id="rs-left">${left()}</b></div></div>
      ${paperHtml(t)}
      <div class="rs-explain"><div><b>Sign</b> — you accept the ticket and will pay it.</div><div><b>Refuse</b> — it is filed unsigned${d.contests ? '; you may contest it before a judge in the court portal (/court)' : ' and must still be paid'}.</div><div class="hint">No answer in time is the same as refusing.</div></div>
      <div class="rs-foot"><button class="rs-btn ghost" id="rs-no">Refuse to sign</button><button class="rs-btn accent" id="rs-yes" data-primary>✎ Sign</button></div>`);
    const arc = q('#rs-arc'); const C = 2 * Math.PI * 15.5;
    arc.style.strokeDasharray = C;
    const tick = () => { const l = left(); const el = q('#rs-left'); if (!el) return stopTimer(); el.textContent = l; arc.style.strokeDashoffset = C * (1 - l / (d.seconds || 45)); if (l <= 0) { stopTimer(); answer(false); } };
    timer = setInterval(tick, 250); tick();
    let sent = false;
    async function answer(signed) {
      if (sent) return; sent = true; stopTimer();
      qa('.rs-foot button').forEach((b) => b.disabled = true);
      const r = await post('rsSign', { token: d.token, signed });
      const card = q('.rs-card'); if (!card) return;
      card.innerHTML = `<div class="rs-done"><div class="rs-big ${signed ? 'ok' : 'warn'}">${signed ? '✓' : '✕'}</div><div class="rs-title">${signed ? 'Signed' : 'Not signed'}</div>
        <p>${r && r.ok ? (signed ? 'You accepted the ticket. A copy is in your pockets and your court portal; pay it by the due date.' : `It is filed unsigned.${d.contests ? ' You can contest it in the court portal (/court → Payments).' : ''}`) : esc((r && r.why) || 'That did not work')}</p>
        <button class="rs-btn accent" id="rs-ok" data-primary>Close</button></div>`;
      card.querySelector('#rs-ok').onclick = close;
    }
    q('#rs-yes').onclick = () => answer(true);
    q('#rs-no').onclick = () => answer(false);
  }

  // ---------------------------------------------------------------- the officer's ticket form
  function openTicket(data, location) {
    mode = 'ticket';
    const st = { kind: 'citation', who: null, veh: null, charges: [], notes: '', q: '', loc: location || '' };
    frame('ticket', `<div class="rs-head"><div class="rs-ico">§</div><div><div class="rs-title">Roadside ticket</div><div class="rs-sub">${esc(data.officer || '')} · ${esc(data.dept || '')} · <span id="rs-loc">${esc(st.loc || 'Unknown location')}</span></div></div>
        <button class="rs-x" id="rs-x" title="Close (Esc)">✕</button></div>
      <div class="rs-seg" id="rs-kind">${(data.kinds || []).map((k) => `<button data-kind="${k.id}" class="${k.id === st.kind ? 'on' : ''}"><span class="rs-ki">${esc((KINDS[k.id] || ['', '•'])[1])}</span>${esc(k.label)}</button>`).join('')}</div>
      <div class="rs-cols">
        <div class="rs-col">
          <div class="rs-l"><span id="rs-who-l">Who</span><button class="rs-mini" id="rs-rescan" title="Look again">⟳ Rescan</button></div>
          <div class="rs-list" id="rs-who"></div>
          <div class="rs-l">Notes <span class="hint">(optional)</span></div>
          <textarea id="rs-notes" maxlength="500" rows="3" placeholder="e.g. 52 in a 35, Strawberry Ave northbound. Cooperative."></textarea>
        </div>
        <div class="rs-col">
          <div class="rs-l">Charges <span class="hint" id="rs-cmax"></span></div>
          <input class="rs-in" id="rs-q" type="search" placeholder="Search the penal code…" autocomplete="off" maxlength="40">
          <div class="rs-list pen" id="rs-pen"></div>
          <div class="rs-sel" id="rs-sel"></div>
        </div>
      </div>
      <div class="rs-foot"><div class="rs-total"><i>Total</i><b id="rs-tot">$0</b><span class="hint" id="rs-due"></span></div><button class="rs-btn ghost" id="rs-cancel">Cancel</button><button class="rs-btn accent" id="rs-go" data-primary disabled>Issue</button></div>`);
    q('#rs-x').onclick = close; q('#rs-cancel').onclick = close;

    const maxC = data.maxCharges || 6;
    const total = () => st.kind === 'warning' ? 0 : st.charges.reduce((a, c) => a + c.fine * c.count, 0);
    function drawWho() {
      const box = q('#rs-who'); if (!box) return;
      q('#rs-who-l').textContent = st.kind === 'parking' ? 'Vehicle (parked, close by)' : 'Person (close by)';
      if (st.kind === 'parking') {
        const vs = data.vehicles || [];
        box.innerHTML = vs.length ? vs.map((v) => `<button class="rs-item${st.veh === v.netId ? ' on' : ''}${v.ownerCharId ? '' : ' dim'}" data-veh="${v.netId}"${v.ownerCharId ? '' : ' disabled'}>
            <span class="rs-plate">${esc(v.plate || '?')}</span><span class="rs-im"><b>${esc(v.label || 'Vehicle')}</b><span class="hint">${v.ownerCharId ? 'Owner: ' + esc(v.owner || '') : 'Nobody owns it (tow it: /mdtimpound)'}${v.occupied ? ' · occupied' : ''}</span></span><span class="rs-d">${v.dist} m</span></button>`).join('')
          : '<div class="rs-empty">No vehicles close by. Walk up to it and press ⟳.</div>';
      } else {
        const ps = data.people || [];
        box.innerHTML = ps.length ? ps.map((p) => `<button class="rs-item${st.who === p.charId ? ' on' : ''}" data-who="${p.charId}">
            <span class="rs-av">${esc((p.name || '?').split(' ').map((x) => x[0]).join('').slice(0, 2))}</span><span class="rs-im"><b>${esc(p.name)}</b><span class="hint">${p.inVehicle ? 'In a vehicle' : 'On foot'}</span></span><span class="rs-d">${p.dist} m</span></button>`).join('')
          : '<div class="rs-empty">Nobody close by. Walk up to them and press ⟳.</div>';
      }
      qa('[data-who]').forEach((b) => b.onclick = () => { st.who = +b.dataset.who; drawWho(); ready(); });
      qa('[data-veh]').forEach((b) => b.onclick = () => { st.veh = +b.dataset.veh; drawWho(); ready(); });
    }
    function drawPen() {
      const box = q('#rs-pen'); if (!box) return;
      const s = st.q.toLowerCase();
      const list = (data.penal || []).filter((p) => !s || (p.code + ' ' + p.title).toLowerCase().includes(s)).slice(0, 40);
      box.innerHTML = list.length ? list.map((p) => `<button class="rs-pc" data-pen="${p.id}"><span class="mono">${esc(p.code)}</span><span class="rs-im"><b>${esc(p.title)}</b><span class="hint">${esc(CAT[p.category] || p.category)}</span></span><span class="rs-f">${st.kind === 'warning' ? '—' : money(p.fine)}</span><span class="rs-add">+</span></button>`).join('')
        : '<div class="rs-empty">No charge matches.</div>';
      qa('[data-pen]').forEach((b) => b.onclick = () => {
        const p = (data.penal || []).find((x) => x.id === +b.dataset.pen); if (!p) return;
        const have = st.charges.find((c) => c.id === p.id);
        if (have) have.count = Math.min(5, have.count + 1);
        else if (st.charges.length < maxC) st.charges.push({ id: p.id, code: p.code, title: p.title, fine: p.fine, count: 1 });
        drawSel(); ready();
      });
      q('#rs-cmax').textContent = `(${st.charges.length}/${maxC})`;
    }
    function drawSel() {
      const box = q('#rs-sel'); if (!box) return;
      box.innerHTML = st.charges.length ? st.charges.map((c, i) => `<div class="rs-ch"><span class="mono">${esc(c.code)}</span><b>${esc(c.title)}</b>
          <span class="rs-cnt"><button data-dec="${i}" title="Fewer">−</button><em>${c.count}</em><button data-inc="${i}" title="More">+</button></span><span class="rs-f">${st.kind === 'warning' ? '—' : money(c.fine * c.count)}</span><button class="rs-rm" data-rm="${i}" title="Remove">✕</button></div>`).join('')
        : '<div class="rs-empty">Pick charges from the list above.</div>';
      qa('[data-inc]').forEach((b) => b.onclick = () => { const c = st.charges[+b.dataset.inc]; c.count = Math.min(5, c.count + 1); drawSel(); });
      qa('[data-dec]').forEach((b) => b.onclick = () => { const c = st.charges[+b.dataset.dec]; c.count -= 1; if (c.count < 1) st.charges.splice(+b.dataset.dec, 1); drawSel(); ready(); });
      qa('[data-rm]').forEach((b) => b.onclick = () => { st.charges.splice(+b.dataset.rm, 1); drawSel(); ready(); });
      q('#rs-tot').textContent = st.kind === 'warning' ? 'No fine' : money(total());
      q('#rs-due').textContent = st.kind === 'warning' ? '' : data.dueDays != null ? `invoice, due in ${data.dueDays} day${data.dueDays === 1 ? '' : 's'}` : '';
      q('#rs-cmax').textContent = `(${st.charges.length}/${maxC})`;
    }
    function ready() {
      const okWho = st.kind === 'parking' ? !!st.veh : !!st.who;
      const go = q('#rs-go'); if (!go) return;
      go.disabled = !(okWho && st.charges.length);
      go.textContent = st.kind === 'citation' ? 'Issue · ask to sign' : st.kind === 'parking' ? 'Issue parking ticket' : 'Issue warning';
    }
    qa('[data-kind]').forEach((b) => b.onclick = () => { st.kind = b.dataset.kind; qa('[data-kind]').forEach((x) => x.classList.toggle('on', x === b)); drawWho(); drawPen(); drawSel(); ready(); });
    q('#rs-q').oninput = (e) => { st.q = e.target.value.trim(); drawPen(); };
    q('#rs-rescan').onclick = async () => {
      const n = await post('rsNearby');
      const r = await post('rsRefresh', { netIds: n && n.data ? n.data.netIds : [] });
      if (r && r.ok) { data.people = r.data.people; data.vehicles = r.data.vehicles; if (n && n.data && n.data.location) { st.loc = n.data.location; q('#rs-loc').textContent = st.loc; } drawWho(); }
    };
    q('#rs-go').onclick = async () => {
      const go = q('#rs-go'); if (go.disabled) return;
      go.disabled = true; go.textContent = 'Sending…'; err(q('.rs-card'), null);
      const r = await post('rsIssue', { kind: st.kind, charId: st.who, netId: st.kind === 'parking' ? st.veh : null, charges: st.charges.map((c) => ({ id: c.id, count: c.count })),
        notes: q('#rs-notes').value.trim(), location: st.loc });
      if (!r || !r.ok) { err(q('.rs-card'), (r && r.why) || 'That did not work'); ready(); return; }
      if (r.data.signing) waitSign(r.data); else issued(r.data.ticket || {});
    };
    drawWho(); drawPen(); drawSel(); ready();
  }

  function issued(t) {
    const card = q('.rs-card'); if (!card) return;
    card.className = 'rs-card paper';
    card.innerHTML = `<div class="rs-banner ok">✓ ${esc((KINDS[t.kind] || ['Ticket'])[0])} ${esc(t.number || '')} filed${t.sign === 'signed' ? ' · signed' : t.sign === 'unsigned' ? ' · unsigned' : ''}. A copy is in your pockets${t.kind === 'parking' ? '; the owner is texted' : ''}.</div>${paperHtml(t)}<div class="rs-foot"><button class="rs-btn accent" id="rs-close" data-primary>Done</button></div>`;
    card.querySelector('#rs-close').onclick = close;
  }

  function waitSign(d) {
    const card = q('.rs-card'); if (!card) return;
    const end = Date.now() + (d.seconds || 45) * 1000;
    card.className = 'rs-card wait';
    card.innerHTML = `<div class="rs-done"><div class="rs-pulse">✎</div><div class="rs-title">Waiting for the signature</div><p>Citation <b class="mono">${esc(d.number)}</b> · ${money(d.total)}. They have <b id="rs-wl">${d.seconds || 45}</b> s to sign or refuse; no answer files it unsigned.</p>
      <button class="rs-btn ghost" id="rs-bg">Close (it is filed either way)</button></div>`;
    card.querySelector('#rs-bg').onclick = close;
    let polling = false;
    timer = setInterval(async () => {
      const el = q('#rs-wl'); if (el) el.textContent = Math.max(0, Math.ceil((end - Date.now()) / 1000));
      if (polling) return; polling = true;
      const r = await post('rsStatus', { id: d.id }); polling = false;
      if (r && r.ok && r.data.sign && r.data.sign !== 'pending') { stopTimer(); issued(r.data); }
      if (Date.now() > end + 8000) stopTimer();
    }, 1500);
  }

  // ---------------------------------------------------------------- the impound form (street overlay AND the MDT)
  // d = impForm's answer. submit(body) -> { ok, data, why }. done(result) after success. cancel() to close.
  function impoundForm(box, d, submit, done, cancel) {
    const S = d.settings || {};
    if (d.unowned) {
      box.innerHTML = `<div class="rs-head"><div class="rs-ico tow">⛟</div><div><div class="rs-title">Tow abandoned vehicle</div><div class="rs-sub"><span class="rs-plate">${esc(d.plate || '?')}</span> ${esc(d.label || '')}</div></div>${cancel ? '<button class="rs-x" data-x2>✕</button>' : ''}</div>
        <div class="rs-checks">
          <div class="rs-ck ok">✓ <b>Not a player's car</b><span>Nobody owns it</span></div>
          <div class="rs-ck ${d.occupied ? 'bad' : 'ok'}">${d.occupied ? '✕' : '✓'} <b>Nobody in it</b><span>${d.occupied ? 'Someone is inside' : 'Empty'}</span></div>
          <div class="rs-ck ${d.temp ? 'bad' : 'ok'}">${d.temp ? '✕' : '✓'} <b>Not a rental or job vehicle</b></div>
          <div class="rs-ck info">… <b>Its last driver is not close by</b><span>Checked when you tow</span></div>
        </div>
        ${S.unowned ? `<div class="rs-note">You are paid <b>${money(S.unowned.payout)}</b> per tow (with a short wait between tows and a cap per shift).</div>` : '<div class="rs-note bad">Towing unowned cars is turned off on this server.</div>'}
        <div class="rs-foot">${cancel ? '<button class="rs-btn ghost" data-x2>Cancel</button>' : ''}<button class="rs-btn accent" id="if-go" data-primary${!S.unowned || d.occupied || d.temp ? ' disabled' : ''}>⛟ Tow it away</button></div>`;
      box.querySelectorAll('[data-x2]').forEach((b) => b.onclick = cancel);
      box.querySelector('#if-go').onclick = async (e) => {
        const b = e.currentTarget; if (b.disabled) return; b.disabled = true; b.textContent = 'Towing…'; err(box, null);
        const r = await submit({ netId: d.netId, tow: true });
        if (!r || !r.ok) { err(box, (r && r.why) || 'That did not work'); b.disabled = false; b.textContent = '⛟ Tow it away'; return; }
        done(r.data);
      };
      return;
    }
    const A = d.active;
    const where = d.state === 'garaged' ? `Stored (${esc(d.garage || 'garage')})` : d.spawned ? 'Out in the city' : 'Out (not in the world)';
    const marks = !d.street && d.state !== 'garaged' && d.spawned;
    const reasons = S.reasons || [];
    const st = { reason: reasons[0] || '', lot: (S.lots[0] || {}).key, fee: S.fee || 0, hold: 'none', days: 3, photo: '', notes: '' };
    box.innerHTML = `<div class="rs-head"><div class="rs-ico imp">⛍</div><div><div class="rs-title">${d.street ? 'Impound this vehicle' : 'Impound vehicle'}</div><div class="rs-sub"><span class="rs-plate">${esc(d.plate || '?')}</span> ${esc(d.label || '')}</div></div>${cancel ? '<button class="rs-x" data-x2>✕</button>' : ''}</div>
      <div class="rs-alerts">
        ${d.stolen ? '<div class="rs-alert bad">⚠ <b>Reported STOLEN</b><span>Flagged stolen in the MDT. Choose "Stolen vehicle recovered" if it is.</span></div>' : ''}
        ${(d.bolos || []).length ? `<div class="rs-alert bad">⚑ <b>Active BOLO${d.bolos.length > 1 ? 's' : ''}</b><span>${d.bolos.map((b) => esc(b.title)).join(' · ')} — closed when you impound it.</span></div>` : ''}
        ${A ? `<div class="rs-alert warn">⛍ <b>Already impounded</b><span>#${A.id} · ${esc(A.reason)} · ${A.status === 'pending' ? 'marked, waiting to be stored' : 'at ' + esc(A.lotLabel)}</span></div>` : ''}
        ${!d.street && !marks && !A ? `<div class="rs-alert info">ⓘ <b>${d.state === 'garaged' ? 'It is in a garage' : 'It is not out in the world'}</b><span>It is impounded <b>now</b>: moved straight to the lot you pick. The owner is texted.</span></div>` : ''}
        ${marks && !A ? '<div class="rs-alert info">ⓘ <b>It is out in the city right now</b><span>It is <b>marked</b>: it goes to the lot the next time it is stored or spawned, and cannot be taken out again until released. To take it now, stand by it and use /mdtimpound.</span></div>' : ''}
      </div>
      <div class="rs-facts">
        <div><i>Owner</i><b>${esc(d.owner || 'Nobody')}${d.ownerOnline ? ' <span class="rs-on">in the city</span>' : ''}</b></div>
        <div><i>Where</i><b>${where}</b></div>
        <div><i>Prior impounds</i><b class="${d.prior ? 'warnc' : ''}">${d.prior || 0}</b></div>
      </div>
      ${A ? '' : `<div class="rs-cols">
        <div class="rs-col">
          <div class="rs-l">Reason</div>
          <div class="rs-chips" id="if-reason">${reasons.map((x) => `<button data-r="${esc(x)}" class="${x === st.reason ? 'on' : ''}">${esc(x)}</button>`).join('')}</div>
          <div class="rs-row2">
            <div><div class="rs-l">Lot</div><select class="rs-in" id="if-lot">${(S.lots || []).map((l) => `<option value="${esc(l.key)}">${esc(l.label)}</option>`).join('')}</select></div>
            <div><div class="rs-l">Fee</div><input class="rs-in" id="if-fee" type="number" min="0" max="${S.maxFee || 5000}" step="50" value="${st.fee}"></div>
          </div>
          <div class="rs-l">Hold ${S.canHold ? '' : '<span class="hint">(your rank cannot hold vehicles)</span>'}</div>
          <div class="rs-seg small" id="if-hold"><button data-h="none" class="on">No hold</button><button data-h="days"${S.canHold ? '' : ' disabled'}>For days</button><button data-h="open"${S.canHold ? '' : ' disabled'}>Until released</button></div>
          <div class="rs-holddays hidden" id="if-days"><input class="rs-in" id="if-dn" type="number" min="1" max="${S.maxHoldDays || 30}" value="3"><span>days (at most ${S.maxHoldDays || 30})</span></div>
          <div class="rs-l">Notes</div>
          <textarea id="if-notes" maxlength="500" rows="3" placeholder="What happened, where it was, who saw it…"></textarea>
        </div>
        <div class="rs-col">
          <div class="rs-l">Photo link <span class="hint">(optional)</span></div>
          <input class="rs-in" id="if-photo" type="url" placeholder="https://… (a picture of the vehicle)" maxlength="500" autocomplete="off">
          <div class="rs-prev" id="if-prev"><span>A photo link shows here</span></div>
          <div class="rs-bill" id="if-bill"></div>
        </div>
      </div>`}
      <div class="rs-foot">${cancel ? '<button class="rs-btn ghost" data-x2>Cancel</button>' : ''}${A ? '' : `<button class="rs-btn danger" id="if-go" data-primary>${marks ? 'Mark for impound' : 'Impound'}</button>`}</div>`;
    box.querySelectorAll('[data-x2]').forEach((b) => b.onclick = cancel);
    if (A) return;
    const $b = (s) => box.querySelector(s);
    function bill() {
      const fee = Math.max(0, Math.min(S.maxFee || 5000, +$b('#if-fee').value || 0)); st.fee = fee;
      const cap = S.storageCap || 0, day = S.dailyFee || 0;
      $b('#if-bill').innerHTML = `<div class="rs-l">What the owner pays</div>
        <div class="rs-bl"><span>Impound fee</span><b>${money(fee)}</b></div>
        <div class="rs-bl"><span>Storage</span><b>${day ? money(day) + ' / day' : '—'}</b></div>
        ${day ? `<div class="rs-bl sub"><span>Storage is capped at</span><b>${money(cap)}</b></div>` : ''}
        <div class="rs-bl tot"><span>Today</span><b>${money(fee)}</b></div>
        ${day ? `<div class="rs-bl sub"><span>At most (any stay)</span><b>${money(fee + cap)}</b></div>` : ''}
        <div class="hint">${st.hold === 'none' ? 'They pay in the court portal (/court) and get it back at once.' : st.hold === 'open' ? 'Held until an officer releases it: they cannot pay it out before.' : `Held ${st.days} day(s): they can pay it out after that.`}</div>`;
    }
    box.querySelectorAll('[data-r]').forEach((b) => b.onclick = () => { st.reason = b.dataset.r; box.querySelectorAll('[data-r]').forEach((x) => x.classList.toggle('on', x === b)); });
    box.querySelectorAll('[data-h]').forEach((b) => b.onclick = () => { if (b.disabled) return; st.hold = b.dataset.h; box.querySelectorAll('[data-h]').forEach((x) => x.classList.toggle('on', x === b)); $b('#if-days').classList.toggle('hidden', st.hold !== 'days'); bill(); });
    $b('#if-fee').oninput = bill;
    $b('#if-dn').oninput = (e) => { st.days = Math.max(1, Math.min(S.maxHoldDays || 30, +e.target.value || 1)); bill(); };
    let pt = null;
    $b('#if-photo').oninput = (e) => {
      clearTimeout(pt);
      const u = e.target.value.trim(), prev = $b('#if-prev');
      if (!u) { prev.innerHTML = '<span>A photo link shows here</span>'; st.photo = ''; return; }
      if (!/^https:\/\/[\w.-]+\.[a-z]{2,}\//i.test(u)) { prev.innerHTML = '<span class="bad">An https link to a picture</span>'; st.photo = null; return; }
      prev.innerHTML = '<div class="spin"></div>';
      pt = setTimeout(() => {
        const img = new Image();
        img.onload = () => { st.photo = u; prev.innerHTML = ''; prev.appendChild(img); };
        img.onerror = () => { st.photo = null; prev.innerHTML = '<span class="bad">That link is not a picture (or it will not load)</span>'; };
        img.src = u;
      }, 350);
    };
    bill();
    $b('#if-go').onclick = async (e) => {
      const b = e.currentTarget; if (b.disabled) return;
      if (!st.reason) return err(box, 'Pick a reason');
      if (st.photo === null) return err(box, 'Fix the photo link, or clear it');
      b.disabled = true; const was = b.textContent; b.textContent = 'Saving…'; err(box, null);
      const r = await submit({ vehicleId: d.street ? null : d.vehicleId, netId: d.street ? d.netId : null, reason: st.reason, lot: $b('#if-lot').value, fee: st.fee,
        hold: st.hold, holdDays: st.days, notes: $b('#if-notes').value.trim(), photo: st.photo || '' });
      if (!r || !r.ok) { err(box, (r && r.why) || 'That did not work'); b.disabled = false; b.textContent = was; return; }
      done(r.data);
    };
  }
  M.impoundForm = impoundForm;
  M.rsErr = err;

  function openImpound(d) {
    mode = 'impound';
    frame('impound', '');
    const card = q('.rs-card');
    impoundForm(card, d, (body) => post('rsImpSave', body), (res) => {
      card.className = 'rs-card wait';
      card.innerHTML = res.towed
        ? `<div class="rs-done"><div class="rs-big ok">⛟</div><div class="rs-title">Towed</div><p>${res.payout ? `${money(res.payout)} is paid to your bank.` : 'Done.'}${res.left != null ? ` ${Math.max(0, res.left)} paid tow(s) left this shift.` : ''}</p><button class="rs-btn accent" id="rs-ok" data-primary>Done</button></div>`
        : `<div class="rs-done"><div class="rs-big ok">⛍</div><div class="rs-title">${res.status === 'pending' ? 'Marked for impound' : 'Impounded'}</div><p>${res.status === 'pending' ? 'It goes to the lot the next time it is stored.' : 'It is on its way to the lot.'}${res.bolosClosed ? ` ${res.bolosClosed} BOLO(s) closed.` : ''} The owner is texted.</p><button class="rs-btn accent" id="rs-ok" data-primary>Done</button></div>`;
      card.querySelector('#rs-ok').onclick = close;
    }, close);
  }

  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
    if (!m || !m.action) return;
    if (m.action === 'roadside') {
      if (m.mode === 'ticket') openTicket(m.data || {}, m.location);
      else if (m.mode === 'sign') openSign(m.data || {});
      else if (m.mode === 'paper') openPaper(m.data || {});
      else if (m.mode === 'impound') openImpound(m.data || {});
    } else if (m.action === 'roadsideClose') hide();
    else if (m.action === 'roadsideSignGone' && mode === 'sign') {
      const card = q('.rs-card'); if (card && !card.querySelector('.rs-done')) { stopTimer(); card.innerHTML = '<div class="rs-done"><div class="rs-big warn">⌛</div><div class="rs-title">Filed unsigned</div><p>The time ran out.</p><button class="rs-btn accent" id="rs-ok" data-primary>Close</button></div>'; card.querySelector('#rs-ok').onclick = close; }
    }
  });
  document.addEventListener('keydown', (e) => { if (root && e.key === 'Escape') { e.preventDefault(); close(); } });
})();
