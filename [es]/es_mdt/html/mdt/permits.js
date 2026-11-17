// es_mdt 1.8.0: firearm permit applications. Civilians apply at a front desk (or /permit); the server runs a background
// check; anyone holding permits_manage approves (fee taken from the applicant's bank) or denies with a reason.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, said, busy, ago, date, dateTime, modal, pill, empty, VIEWS, toast, money, RO, P } = M;
  const arr = (x) => Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.values(x) : []);
  const ST = { pending: ['Waiting', 'warn'], processing: ['Being decided', 'warn'], approved: ['Approved', 'on'], denied: ['Denied', 'bad'], cancelled: ['Cancelled', 'off'] };
  const TABS = [['pending', 'Waiting'], ['approved', 'Approved'], ['denied', 'Denied'], ['all', 'All']];

  function checkBox(ck) {
    if (!ck) return '<div class="hint">No background check on file.</div>';
    const row = (ico, label, n, bad) => `<div class="pm-ck ${bad ? 'bad' : 'ok'}"><span>${bad ? '✕' : '✓'}</span><b>${esc(label)}</b><em>${esc(String(n))}</em></div>`;
    return `<div class="pm-cks">
      ${row('', 'Active warrants', ck.warrants || 0, (ck.warrants || 0) > 0)}
      ${row('', 'Felony charges on record', ck.felonies || 0, (ck.felonies || 0) > 0)}
      ${ck.convictions != null ? row('', 'Felony convictions (court)', ck.convictions, ck.convictions > 0) : ''}
      ${row('', `Arrests, last ${ck.arrestDays || 30} days`, ck.arrests || 0, (ck.arrests || 0) > 0)}
      ${row('', 'In jail or escaped', ck.jailed ? 'Yes' : 'No', !!ck.jailed)}
    </div><div class="hint">Checked ${ago(ck.at)}${ck.clear ? ' · <b class="txt-ok">clear</b>' : ''}</div>`;
  }

  VIEWS.permits = async (v) => {
    S.pmTab = S.pmTab || 'pending';
    const r = await call('permits', { status: S.pmTab });
    if (S.view !== 'permits') return;
    if (!r.ok) { v.innerHTML = `<div class="v-head"><div class="v-title">Firearm permits</div></div>${empty(r.why || 'Could not load', '✪')}`; return; }
    const D = r.data, list = arr(D.list);
    S.pmList = list;
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Firearm permits</div>
        <div class="hint">Civilians apply at a police front desk or with /permit (photo required) · a background check runs automatically · fee ${money(D.fee || 0)} on approval, from their bank</div>
        ${D.canDecide ? '' : `<div class="pm-view">👁 View only: ${esc(D.whyNot || 'Sergeant and above decide')}</div>`}</div></div>
      <div class="seg mb" id="pm-tabs">${TABS.map(([k, l]) => `<button data-pt="${k}" class="${S.pmTab === k ? 'on' : ''}">${esc(l)}${k === 'pending' && D.pending ? ` <span class="t-badge warn">${D.pending}</span>` : ''}</button>`).join('')}</div>
      <div class="pm-list">${list.length ? list.map((a) => {
        const ck = a.check || {}, st = ST[a.status] || [a.status, ''];
        return `<div class="pm-card ${a.status}" data-pa="${a.id}">
          <div class="pm-top">${a.photo ? `<img class="pm-photo" src="${a.photo}" alt="" data-pa-open="${a.status === 'pending' ? a.id : ''}">` : `<span class="pm-photo ph-none" data-lazy="${a.hasPhoto ? a.id : ''}">${a.hasPhoto ? '…' : '👤'}</span>`}<div style="flex:1;min-width:0"><b class="pm-name" data-person="${a.charId}">${esc(a.name)}</b><div class="hint">#${a.id} · applied ${ago(a.createdAt)}${a.dob ? ' · born ' + esc(a.dob) : ''}</div></div>
            <div class="res-tags">${pill(st[0], st[1])}${a.status === 'pending' ? (ck.clear ? pill('Check clear', 'on') : pill(`${arr(ck.flags).length} flag${arr(ck.flags).length === 1 ? '' : 's'}`, 'bad')) : ''}</div></div>
          <div class="pm-reason">“${esc(a.reason)}”</div>
          ${a.status === 'pending' && arr(ck.flags).length ? `<div class="pm-flags">${arr(ck.flags).map((f) => `<span>⚠ ${esc(f)}</span>`).join('')}</div>` : ''}
          ${a.status !== 'pending' ? `<div class="hint">${a.status === 'approved' ? 'Approved' : a.status === 'denied' ? 'Denied' : esc(a.status)} ${dateTime(a.decidedAt)}${a.decidedByName ? ' by ' + esc(a.decidedByName) : ''}${a.paid ? ' · ' + money(a.paid) + ' paid' : ''}${a.decisionNote ? ' · ' + esc(a.decisionNote) : ''}</div>` : ''}
          ${a.status === 'pending' ? `<div class="row end"><button class="btn small" data-pa-open="${a.id}">${D.canDecide ? 'Review →' : 'Open →'}</button></div>` : ''}
        </div>`;
      }).join('') : empty(S.pmTab === 'pending' ? 'No applications waiting. Nice.' : 'Nothing here', '✪')}</div>`;
    $$('[data-pt]', v).forEach((b) => b.onclick = () => { S.pmTab = b.dataset.pt; VIEWS.permits(v); });
    $$('[data-pa-open]', v).forEach((b) => { if (b.dataset.paOpen) b.onclick = () => review(list.find((x) => x.id === +b.dataset.paOpen), D, v); });
    (async () => {   // photos of decided applications load one by one
      for (const el of $$('[data-lazy]', v)) {
        if (!el.dataset.lazy) continue;
        const r2 = await call('permitPhoto', { id: +el.dataset.lazy });
        if (!el.isConnected) return;
        if (r2.ok && r2.data && r2.data.image) el.outerHTML = `<img class="pm-photo" src="${r2.data.image}" alt="">`;
      }
    })();
  };

  // ---------------------------------------------------------------- 1.8.0: staff test-data cleanup
  const TD_ICO = { case: '▣', report: '☰', warrant: '⚖', bolo: '⚑', trainee: '🎓', evidence: '⚲' };
  const TD_NAME = { case: 'Cases', report: 'Reports', warrant: 'Warrants', bolo: 'BOLOs', trainee: 'FTO test trainees', evidence: 'Evidence in test cases' };
  VIEWS.testdata = async (v) => {
    const r = await call('testData');
    if (S.view !== 'testdata') return;
    if (!r.ok) { v.innerHTML = `<div class="v-head"><div class="v-title">Test data</div></div>${empty(r.why || 'Could not load', '🧹')}`; return; }
    const list = arr(r.data.list);
    const groups = {};
    list.forEach((x) => { (groups[x.kind] = groups[x.kind] || []).push(x); });
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Test data</div>
        <div class="hint">Records that look like testing. Nothing is removed until you press Clear. Ticked = flagged as test; untick anything real.</div></div>
        <button class="btn danger" id="td-go" ${list.length ? '' : 'disabled'}>🧹 Clear ticked</button></div>
      <div class="tr-info">Test NPC suspects from <b>/cufftest</b> are never saved; <b>/cufftest clear</b> removes any still standing. Clearing a case un-links its reports and warrants (they stay unless ticked too); its evidence is marked destroyed with the reason "Test data cleared".</div>
      ${list.length ? Object.keys(TD_NAME).filter((k) => groups[k]).map((k) => `<div class="card"><div class="card-title">${TD_ICO[k]} ${esc(TD_NAME[k])} <span class="hint">· ${groups[k].length}</span></div>
        ${groups[k].map((x) => `<label class="td-row"><input type="checkbox" data-td="${esc(x.kind)}|${esc(String(x.id))}" ${x.flagged ? 'checked' : ''}><div class="li-main"><b>${esc(x.label)}</b><span class="hint">${esc(x.sub || '')} · ${esc(x.why)}</span></div></label>`).join('')}</div>`).join('')
        : empty('Nothing looks like test data. Clean!', '✨')}`;
    const sum = () => { const n = $$('[data-td]:checked', v).length; const b = $('#td-go', v); if (b) { b.disabled = !n; b.textContent = n ? `🧹 Clear ${n} ticked` : '🧹 Clear ticked'; } };
    $$('[data-td]', v).forEach((c) => c.onchange = sum); sum();
    if ($('#td-go', v)) $('#td-go', v).onclick = async (e) => {
      const btn = e.currentTarget;
      const items = $$('[data-td]:checked', v).map((c) => { const [kind, id] = c.dataset.td.split('|'); return { kind, id: /^\d+$/.test(id) ? +id : id }; });
      if (!items.length) return;
      if (!await M.confirmBox(`Clear ${items.length} record${items.length === 1 ? '' : 's'}?`, 'They are deleted for good (evidence is marked destroyed). This cannot be undone.', 'Clear them', true)) return;
      busy(btn, async () => {
        const r2 = await call('testClear', { items });
        if (said(r2, `Cleared ${r2.data ? r2.data.cleared : 0}`)) VIEWS.testdata(v);
      });
    };
  };

  function review(a, D, v) {
    if (!a) return;
    let decision = null;
    modal(`<div class="m-title">Permit application #${a.id} · ${esc(a.name)}</div>
      ${a.photo ? `<img class="pm-big-photo" src="${a.photo}" alt=""><div class="hint mb">Approving puts this photo on their MDT record (older photos stay in their history).</div>` : '<div class="tr-info warn mb">No photo with this application.</div>'}
      <div class="pm-reason big">“${esc(a.reason)}”</div>
      <div class="sub-h">Background check</div><div id="pm-ck">${checkBox(a.check)}</div>
      ${D.canDecide ? `<div class="row mb"><button class="btn small ghost" id="pm-re">↻ Run the check again</button></div>
      <div class="field"><label>Decision</label><div class="seg" id="pm-dec"><button data-d="approve">✓ Approve${D.fee ? ' · ' + money(D.fee) + ' fee' : ''}</button><button data-d="deny">✕ Deny</button></div></div>
      <div class="field"><label id="pm-note-l">Note (optional)</label><textarea id="pm-note" maxlength="300" rows="3" placeholder="Anything the applicant should know"></textarea></div>
      <div class="confirm-line" id="pm-sum">Pick approve or deny.</div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="pm-go" data-primary disabled>Confirm</button></div>` : `<div class="tr-info mb">👁 ${esc(D.whyNot || 'Only Sergeant and above approve or deny permits.')}</div><div class="row end"><button class="btn ghost" data-x>Close</button></div>`}`, (card, closeIt) => {
      if (!D.canDecide) return;
      const sum = () => {
        const go = $('#pm-go', card);
        go.disabled = !decision || RO();
        go.className = 'btn ' + (decision === 'deny' ? 'danger' : 'accent');
        $('#pm-note-l', card).textContent = decision === 'deny' ? 'Reason (the applicant sees it)' : 'Note (optional)';
        $('#pm-sum', card).innerHTML = !decision ? 'Pick approve or deny.' : decision === 'approve'
          ? `<b>${esc(a.name)}</b> gets a firearm permit${D.fee ? `; <b>${money(D.fee)}</b> comes out of their bank (refused if they cannot pay)` : ''}. They are told at once.`
          : `<b>${esc(a.name)}</b> is told it was denied, with your reason.`;
      };
      $$('[data-d]', card).forEach((b) => b.onclick = () => { decision = b.dataset.d; $$('[data-d]', card).forEach((x) => x.classList.toggle('on', x === b)); sum(); });
      $('#pm-re', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('permitRecheck', { id: a.id });
        if (said(r)) { a.check = r.data; $('#pm-ck', card).innerHTML = checkBox(r.data); }
      });
      $('#pm-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const note = $('#pm-note', card).value.trim();
        if (decision === 'deny' && note.length < 3) { toast('Say why it is denied', 'err'); return; }
        if (said(await call('permitDecide', { id: a.id, decision, note }), decision === 'approve' ? 'Permit issued' : 'Application denied')) { closeIt(); VIEWS.permits(v); M.loadBadges(); }
      });
    });
  }
})();
