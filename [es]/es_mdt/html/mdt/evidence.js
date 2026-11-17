// es_mdt 1.4.0: the Evidence tab, evidence on reports, camera-roll photos (also for mugshots).
// The evidence lives in es_evidence; the MDT server reads it through its exports. This only draws and asks.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, toast, said, busy, ago, dateTime, modal, confirmBox, pill, empty, can, go, VIEWS, HOOK } = M;
  const KIND = { casing: ['Casing', '⁍'], blood: ['Blood', '🩸'], fragment: ['Fragment', '✶'], photo: ['Photo', '📷'], item: ['Item', '▣'], print: ['Fingerprint', '🖐'], weapon: ['Weapon', '🔫'] };
  const PQ = { full: ['Full print', 'on'], partial: ['Partial print', 'warn'], smudge: ['Smudged · gloves', 'off'] };
  const ST = { held: ['With officer', 'accent'], lab: ['In the lab', 'warn'], locker: ['In a locker', 'on'], stored: ['Stored', 'warn'], digital: ['Digital', 'accent'], released: ['Released', 'off'], destroyed: ['Destroyed', 'off'] };
  const ACT = { case: 'Filed to a case', uncase: 'Taken off a case', purged: 'Purged (archived case)', locker_move: 'Moved locker', collected: 'Collected', lab_in: 'Into the lab', lab_out: 'Out of the lab', analyzed: 'Lab result', locker_in: 'Into a locker', locker_out: 'Out of a locker',
    report: 'Attached to a report', handover: 'Handed over', taken: 'Taken', stashed: 'Put in a stash / boot', dropped: 'Dropped', unreport: 'Taken off a report', note: 'Note', destroyed: 'Destroyed', logged: 'Logged', matched: 'Print matched', released: 'Released' };
  const kindPill = (k) => `<span class="ev-k ev-${esc(k)}">${(KIND[k] || [k, '·'])[1]} ${esc((KIND[k] || [k])[0])}</span>`;
  // 1.5.2: the server says where it is now ("In locker · C-2026-0001", "With officer · C-…", "Stash #12")
  const stPill = (r) => { const s = ST[r.status] || [r.status, '']; return pill(r.statusText || (r.status === 'lab' && r.labState === 'done' ? 'Lab · result ready' : s[0]), r.statusTone || s[1]); };
  const repChips = (r) => (r.reports || []).length ? `<span class="pill ev-rep" title="On report ${(r.reports || []).map((n) => '#' + n).join(', ')}">📄 ${r.reports.length > 2 ? r.reports.length + ' reports' : r.reports.map((n) => '#' + n).join(' ')}</span>` : '';
  const E = { q: '', kind: '', status: 'open', sel: null, info: null, caseId: '' };

  async function status() {
    if (E.info) return E.info;
    const r = await call('evStatus');
    E.info = r.ok ? r.data : { installed: false };
    setTimeout(() => { E.info = null; }, 60000);
    return E.info;
  }

  // ---------------------------------------------------------------- the tab
  VIEWS.evidence = async (v, arg) => {
    if (arg) E.sel = +arg;
    const info = await status();
    if (!info.installed) { v.innerHTML = `<div class="v-head"><div class="v-title">Evidence</div></div>` + empty('The evidence system (es_evidence) is not running. An admin needs to run "refresh", then "ensure es_evidence".', '⚠'); return; }
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Evidence</div><div class="hint">Bagged at scenes, tested in the lab, kept in lockers · every hand-over is logged</div></div>
      <div class="row">${info.collect && !S.ctx.readOnly ? '<button class="btn" id="ev-photo" data-probe-press>📷 Add photo</button>' : ''}${info.collect || info.manage ? '<button class="btn" id="ev-lockers" data-probe-press>🗄 Lockers</button>' : ''}</div></div>
      <div class="filters"><input type="text" id="ev-q" placeholder="Search EV-number, street, serial, DNA / print id, note…" value="${esc(E.q)}">
        <div class="seg">${[['', 'All'], ['casing', 'Casings'], ['blood', 'Blood'], ['fragment', 'Fragments'], ['print', 'Prints'], ['weapon', 'Weapons'], ['photo', 'Photos']].map(([k, l]) => `<button data-evk="${k}" class="${E.kind === k ? 'on' : ''}">${l}</button>`).join('')}</div>
        <div class="seg">${[['open', 'Open'], ['held', 'With officers'], ['lab', 'In lab'], ['locker', 'In lockers'], ['results', 'Results'], ['destroyed', 'Destroyed']].map(([k, l]) => `<button data-evs="${k}" class="${E.status === k ? 'on' : ''}">${l}</button>`).join('')}</div>
        <select id="ev-case" title="Case"><option value="">Any case</option><option value="none"${E.caseId === 'none' ? ' selected' : ''}>No case</option></select></div>
      <div class="split wide"><div class="res-list" id="ev-list"><div class="loading-row"><div class="spin"></div></div></div>
        <div class="split-detail" id="ev-detail">${empty('Pick a piece of evidence', '🔎')}</div></div>`;
    let t = null;
    $('#ev-q').oninput = (e) => { clearTimeout(t); t = setTimeout(() => { E.q = e.target.value.trim(); list(); }, 250); };
    $$('[data-evk]', v).forEach((b) => b.onclick = () => { E.kind = b.dataset.evk; $$('[data-evk]', v).forEach((x) => x.classList.toggle('on', x === b)); list(); });
    $$('[data-evs]', v).forEach((b) => b.onclick = () => { E.status = b.dataset.evs; $$('[data-evs]', v).forEach((x) => x.classList.toggle('on', x === b)); list(); });
    // 1.5.2: case filter (open and recent cases)
    $('#ev-case').onchange = (e) => { E.caseId = e.target.value; list(); };
    call('caseFind', { q: '' }).then((r) => {
      const sel = $('#ev-case'); if (!sel || !r.ok) return;
      sel.insertAdjacentHTML('beforeend', (r.data || []).map((c) => `<option value="${c.id}"${String(E.caseId) === String(c.id) ? ' selected' : ''}>${esc(c.number)} · ${esc((c.title || '').slice(0, 40))}${c.status !== 'open' ? ' (' + esc(c.status) + ')' : ''}</option>`).join(''));
    });
    if ($('#ev-photo')) $('#ev-photo').onclick = () => photoModal({ after: (r) => { E.sel = r.id; go('evidence'); } });
    if ($('#ev-lockers')) $('#ev-lockers').onclick = () => lockersModal();
    await list();
    if (E.sel) detail(E.sel);
  };

  async function list() {
    const box = $('#ev-list'); if (!box) return;
    const r = await call('evList', { q: E.q, kind: E.kind, status: E.status, caseId: E.caseId || undefined });
    if (!$('#ev-list')) return;
    if (!r.ok) { box.innerHTML = empty(r.why || 'Could not load'); return; }
    const rows = r.data || [];
    box.innerHTML = rows.length ? rows.map((e) => `<div class="res click ev-row${E.sel === e.id ? ' sel' : ''}" data-ev="${e.id}">
        <div class="ev-main"><div class="ev-top"><span class="ev-code">${esc(e.code)}</span>${kindPill(e.kind)}${e.kind === 'print' && e.printQuality && PQ[e.printQuality] ? pill(PQ[e.printQuality][0], PQ[e.printQuality][1]) : ''}${e.hasResult ? '<span class="pill on">Result</span>' : ''}${e.caseNo ? `<span class="cs-no sm">${esc(e.caseNo)}</span>` : ''}${repChips(e)}</div>
        <div class="ev-label">${esc(e.label)}${e.shots > 1 ? ` <span class="hint">×${e.shots}</span>` : ''}</div>
        <div class="hint">${esc(e.street || '—')} · ${ago(e.collectedAt || e.createdAt)}</div></div>${stPill(e)}</div>`).join('')
      : empty(E.q ? 'Nothing matches' : 'No evidence here yet. Officers bag it at scenes (evidence mode or a flashlight).', '🔎');
    $$('[data-ev]', box).forEach((el) => el.onclick = () => { E.sel = +el.dataset.ev; $$('[data-ev]', box).forEach((x) => x.classList.toggle('sel', x === el)); detail(E.sel); });
  }

  async function detail(id) {
    const box = $('#ev-detail'); if (!box) return;
    box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('evGet', { id });
    if (!$('#ev-detail') || E.sel !== id) return;
    if (!r.ok) { box.innerHTML = empty(r.why || 'Not found'); return; }
    const e = r.data, info = await status();
    const where = e.status === 'held' ? 'With ' + (e.holder || 'an officer') + (e.caseNo ? ' · filed to ' + e.caseNo : '') : e.status === 'destroyed' ? 'Destroyed' : e.status === 'digital' ? 'In the MDT' : e.status === 'locker' ? (e.statusText || e.place || 'In a locker') : (e.place || e.statusText || '—');
    let lab = '';
    const cands = (e.candidates || []).length ? `<div class="ev-cands"><span class="hint">Candidates · not a positive match</span><div class="row wrap">${e.candidates.map((x) => `<a class="lnk ev-cand" data-person="${x.charId}">☺ ${esc(x.name)} <span class="hint">#${x.charId}</span></a>`).join('')}</div></div>` : '';
    const unid = e.kind === 'print' && e.result && !e.resultCharId && e.printQuality === 'full';
    if (e.result) lab = `<div class="ev-result${unid ? ' unid' : ''}"><div class="card-title">🧪 Lab result${unid ? ' <span class="pill warn">Unidentified</span>' : ''}</div><div class="ev-res-text">${esc(e.result)}</div>${cands}
        ${unid ? '<div class="hint">🖐 Matches by itself the moment this person\'s prints are taken (Process arrest, or Prints on their profile).</div>' : ''}
        <div class="row">${e.resultCharId ? `<a class="lnk" data-person="${e.resultCharId}">☺ Open ${esc(e.resultName || 'person')}</a>` : ''}${e.serial ? `<a class="lnk" data-wpn="${esc(e.serial)}">⌖ Weapon ${esc(e.serial)}</a>` : ''}
        <span class="hint">${e.labByName ? 'Tested by ' + esc(e.labByName) : ''}</span></div></div>`;
    else if (e.status === 'lab') lab = `<div class="ev-result wait"><div class="card-title">🧪 In the lab</div><div class="hint">Testing${e.secondsLeft != null ? ` · about ${Math.max(1, Math.ceil(e.secondsLeft / 60))} min left` : ''}${e.labByName ? ' · ' + esc(e.labByName) : ''}</div></div>`;
    else if (e.kind !== 'photo') lab = `<div class="ev-result none"><div class="hint">🧪 Not tested yet. Take the bag to the crime lab: ${e.kind === 'print' ? 'a fingerprint lift is checked against everyone whose prints are on file.' : e.kind === 'weapon' ? 'the weapon is run against the registry and any prints still on it are lifted and checked.' : 'casings and fragments give the gun\'s serial and owner, blood gives a DNA match, prints a match on file.'}</div></div>`;
    box.innerHTML = `<div class="card ev-head"><div class="row"><span class="ev-code big">${esc(e.code)}</span>${kindPill(e.kind)}${stPill(e)}<span class="spacer"></span><span class="hint">${dateTime(e.collectedAt || e.createdAt)}</span></div>
        <div class="v-title">${esc(e.label)}${e.shots > 1 ? ` <span class="hint">×${e.shots} rounds</span>` : ''}</div>
        ${e.image ? `<div class="ev-pic" id="ev-img"><img src="${e.image}" alt=""></div>` : ''}
        <div class="facts"><span><i>Found at</i>${esc(e.street || '—')}</span><span><i>Collected by</i>${esc(e.collector || '—')}</span>
          ${e.photographerName ? `<span><i>Photographer</i>${esc(e.photographerName)}</span>` : ''}${e.caliber ? `<span><i>Calibre</i>${esc(e.caliber)}</span>` : ''}${e.printSpot ? `<span><i>Lifted from</i>${esc(e.printSpot)}</span>` : ''}${e.kind === 'print' && PQ[e.printQuality] ? `<span><i>Quality</i>${esc(PQ[e.printQuality][0])}</span>` : ''}
          <span><i>Where now</i>${esc(where)}</span>${e.x != null ? `<span><i>Coords</i>${e.x}, ${e.y}</span>` : ''}</div></div>
      ${lab}
      <div class="card"><div class="card-title">Note</div><textarea id="ev-note" maxlength="500" placeholder="What it is, why it matters…"${info.collect && !S.ctx.readOnly ? '' : ' disabled'}>${esc(e.note || '')}</textarea>
        ${info.collect && !S.ctx.readOnly ? '<div class="row end"><button class="btn small" id="ev-note-save">Save note</button></div>' : ''}</div>
      <div class="card"><div class="card-head"><div class="card-title">Case</div>${!S.ctx.readOnly && M.casePicker && (info.collect || can('mdt_reports_write')) ? `<button class="btn small" id="ev-case-set">${e.caseId ? 'Change case' : '+ File to a case'}</button>` : ''}</div>
        ${e.caseId ? `<div class="li click" id="ev-case-go"><span class="cs-no">${esc(e.caseNo || '#' + e.caseId)}</span><div class="li-main"><b>Open the case</b><span class="hint">Reports, evidence, suspects and the timeline</span></div></div>` : '<div class="hint">Not filed to a case yet. Putting the bag in a case\'s locker files it too.</div>'}</div>
      <div class="card"><div class="card-head"><div class="card-title">Reports</div>${can('mdt_reports_write') ? '<button class="btn small" id="ev-attach">+ Attach to a report</button>' : ''}</div>
        ${(e.reports || []).length ? `<div class="row wrap">${e.reports.map((rid) => `<a class="lnk" data-rep="${rid}">☰ Report #${rid}</a>`).join('')}</div>` : '<div class="hint">Not on any report yet.</div>'}</div>
      <div class="card"><div class="card-title">Chain of custody <span class="hint">· every hand-over, oldest first</span></div>
        <div class="ev-chain">${(e.custody || []).map((c) => `<div class="ev-step"><span class="ev-dot"></span><div><b>${esc(ACT[c.action] || c.action)}</b>${c.fromWhere || c.toWhere ? ` <span class="hint">${esc(c.fromWhere || '—')} → ${esc(c.toWhere || '—')}</span>` : ''}
          ${c.note ? `<div class="hint">${esc(c.note)}</div>` : ''}<div class="hint">${c.by ? esc(c.by) + ' · ' : ''}${dateTime(c.at)}</div></div></div>`).join('') || '<div class="hint">Nothing logged</div>'}</div></div>
      ${info.manage && e.status !== 'destroyed' && !S.ctx.readOnly ? '<div class="row end"><button class="btn danger small" id="ev-destroy">Destroy / release…</button></div>' : ''}`;
    if ($('#ev-img')) $('#ev-img').onclick = () => (M.openPhoto ? M.openPhoto(e) : viewer(e.image));
    // 1.5.0: the case this evidence is filed to
    if ($('#ev-case-set')) $('#ev-case-set').onclick = () => M.casePicker(async (pick) => {
      if (said(await call('caseLink', { kind: 'evidence', refId: e.id, caseId: pick ? pick.id : 0, fromCase: e.caseId || 0 }), pick ? `Filed to ${pick.number}` : 'Taken off the case')) { detail(e.id); list(); }
    }, { allowNone: !!e.caseId, title: `Case for ${e.code}` });
    if ($('#ev-case-go')) $('#ev-case-go').onclick = () => go('cases', e.caseId);
    $$('[data-person]', box).forEach((a) => a.onclick = () => go('people', +a.dataset.person));
    $$('[data-wpn]', box).forEach((a) => a.onclick = () => go('weapons', a.dataset.wpn));
    $$('[data-rep]', box).forEach((a) => a.onclick = () => go('reports', { view: +a.dataset.rep }));
    if ($('#ev-note-save')) $('#ev-note-save').onclick = (ev) => busy(ev.currentTarget, async () => said(await call('evNote', { id: e.id, note: $('#ev-note').value }), 'Note saved') && detail(e.id));
    if ($('#ev-attach')) $('#ev-attach').onclick = () => attachToReport(e);
    if ($('#ev-destroy')) $('#ev-destroy').onclick = () => destroyModal(e);
  }

  function viewer(src) {
    modal(`<div class="ev-viewer"><img src="${src}" alt=""></div><div class="row end"><button class="btn ghost" data-x>Close</button></div>`, () => {});
  }

  function attachToReport(e) {
    modal(`<div class="m-title">Attach ${esc(e.code)} to a report</div>
      <div class="field"><label>Report number</label><input id="ea-id" type="number" min="1" placeholder="e.g. 128"></div>
      <div class="hint">Open the report and use "+ Attach evidence" there to pick from a list instead.</div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="ea-go" data-primary>Attach</button></div>`, (card, closeIt) => {
      $('#ea-go', card).onclick = (ev) => busy(ev.currentTarget, async () => {
        if (said(await call('evLink', { reportId: +$('#ea-id', card).value, evidenceId: e.id }), 'Attached')) { closeIt(); detail(e.id); }
      });
    });
  }

  function destroyModal(e) {
    const wpn = e.kind === 'weapon' && e.status !== 'released';
    modal(`<div class="m-title">Destroy or release ${esc(e.code)}</div>
      <p>The record stays in the MDT, marked destroyed, and the bag is taken out of the city. This cannot be undone.</p>
      ${wpn ? '<div class="hint">🔫 <b>Release</b> opens the bag and puts the weapon itself (same serial and attachments) in your pockets to hand back. Carry the bag yourself first: take it out of the locker.</div>' : ''}
      <div class="field"><label>Why</label><input id="ed-why" maxlength="200" placeholder="${wpn ? 'Released to owner · case closed · …' : 'Case closed · released to owner · …'}"></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button>${wpn ? '<button class="btn" id="ed-rel">Release weapon</button>' : ''}<button class="btn danger" id="ed-go" data-primary>Destroy</button></div>`, (card, closeIt) => {
      $('#ed-go', card).onclick = (ev) => busy(ev.currentTarget, async () => {
        if (said(await call('evDestroy', { id: e.id, reason: $('#ed-why', card).value }), 'Done')) { closeIt(); list(); detail(e.id); }
      });
      if ($('#ed-rel', card)) $('#ed-rel', card).onclick = (ev) => busy(ev.currentTarget, async () => {
        if (said(await call('evRelease', { id: e.id, reason: $('#ed-why', card).value }), 'Weapon released: it is in your pockets')) { closeIt(); list(); detail(e.id); }
      });
    });
  }

  // ---------------------------------------------------------------- 1.5.3: fingerprints (booking)
  // Take a person's prints: they go on file, and any unidentified lift of theirs matches at once. Used by the
  // profile's Prints button and Process arrest's booking step.
  async function takePrints(p, btn) {
    const r = await call('evPrintsTake', { charId: p.charId });
    if (!r.ok) { toast(r.why || 'Could not take the prints', 'err'); return null; }
    const m = (r.data.matched || []);
    toast(m.length ? `Prints on file (${r.data.fp}) · matched ${m.join(', ')}` : `Prints on file · ${r.data.fp}${r.data.again ? ' (taken again)' : ''}`, 'ok');
    return r.data;
  }
  M.takePrints = takePrints;
  const fpLine = (f) => f && f.onFile ? `${f.fp ? `<span class="ev-code">${esc(f.fp)}</span>` : ''}<span class="hint">${f.booked ? 'Taken ' + dateTime(f.at) + (f.by ? ' by ' + esc(f.by) : '') : 'Everyone is on file on this server'}${f.matches ? ` · matched on ${f.matches} lift${f.matches > 1 ? 's' : ''}` : ''}</span>` : '<span class="hint">Not on file. The lab cannot name them from a print until they are printed.</span>';
  M.fpLine = fpLine;
  const prevPerson = HOOK.person;
  HOOK.person = (box, p, reload) => {
    if (prevPerson) prevPerson(box, p, reload);
    const f = p.prints; if (!f) return;
    const tags = $('.res-tags', box);
    if (tags) tags.insertAdjacentHTML('beforeend', f.onFile ? pill('🖐 Prints on file', 'on') : pill('No prints on file', 'off'));
    const acts = $('.prof-actions', box);
    if (acts && can('mdt_reports_write') && !S.ctx.readOnly) {
      acts.insertAdjacentHTML('beforeend', `<button class="btn small" id="pa-prints" data-probe-press title="${f.booked ? 'Take their fingerprints again' : 'Take their fingerprints: they go on file'}">🖐 ${f.booked ? 'Prints ✓' : 'Prints'}</button>`);
      $('#pa-prints', box).onclick = () => modal(`<div class="m-title">Fingerprints · ${esc(p.name)}</div>
          <div class="fp-card"><div class="fp-ico">🖐</div><div class="fp-main">${fpLine(f)}</div></div>
          <p class="hint">Stand within a few metres of ${esc(p.name)}. Their prints go on file: the lab names them from any lift from now on, and lifts already tested that were Unidentified match straight away.</p>
          <div class="row end"><button class="btn ghost" data-x>Close</button><button class="btn accent" id="fp-go" data-primary data-probe-press>🖐 ${f.booked ? 'Take again' : 'Take prints'}</button></div>`, (card, closeIt) => {
        $('#fp-go', card).onclick = (ev) => busy(ev.currentTarget, async () => { if (await takePrints(p)) { closeIt(); if (reload) reload(); } });
      });
    }
  };

  // ---------------------------------------------------------------- lockers
  function lockersModal() {
    modal(`<div class="m-title">Evidence lockers</div><div id="el-body"><div class="loading-row"><div class="spin"></div></div></div>
      <div class="row end"><button class="btn ghost" data-x>Close</button></div>`, async (card, closeIt) => {
      const r = await call('evLockers');
      const box = $('#el-body', card); if (!box) return;
      if (!r.ok) { box.innerHTML = empty(r.why || 'Could not load'); return; }
      // 1.5.0: General / unassigned, then every case locker that holds something (one per case, no limit)
      const ls = r.data || [];
      box.innerHTML = `<p class="hint">Each case has its own locker, opened in the evidence room by case number. Empty case lockers are not listed.</p>
        <div class="ev-lockers">${ls.map((l) => `<div class="ev-lk${l.items.length ? ' used' : ''}"><div class="row">${l.general ? '<b>General / unassigned</b>' : `<a class="lnk" data-lkcase="${l.caseId}"><b>${esc(l.number || '')}</b></a>`}<span class="spacer"></span><span class="hint">${l.items.length ? l.items.length + ' item' + (l.items.length > 1 ? 's' : '') : 'Empty'}</span></div>
          ${l.general ? '' : `<div class="hint ev-lk-i">${esc((l.label || '').replace(/^Case [^·]*· /, ''))}${l.status && l.status !== 'open' ? ' · ' + esc(l.status) : ''}</div>`}
          ${l.items.map((it) => it.evidenceId ? `<a class="lnk ev-lk-i" data-evo="${it.evidenceId}">${esc(it.label)}</a>` : `<div class="hint ev-lk-i">${esc(it.label)}${it.amount > 1 ? ' ×' + it.amount : ''}</div>`).join('')}</div>`).join('')}</div>`;
      $$('[data-lkcase]', box).forEach((a) => a.onclick = () => { closeIt(); go('cases', +a.dataset.lkcase); });
      $$('[data-evo]', box).forEach((a) => a.onclick = () => { closeIt(); E.sel = +a.dataset.evo; E.status = 'locker'; go('evidence'); });
    });
  }

  // ---------------------------------------------------------------- camera roll picker (also used by mugshots)
  // Fills `box` with the officer's own camera-roll photos; onPick({ id, image }) when one is chosen (live preview in `prev`).
  async function rollPicker(box, prev, onPick) {
    box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('evRoll');
    if (!box.isConnected) return;
    const list = (r.ok && r.data) || [];
    if (!list.length) { box.innerHTML = empty('Your camera roll is empty. Use the camera item, then press the shutter key (left mouse) while looking through it.', '📷'); return; }
    box.innerHTML = `<div class="ev-roll">${list.map((p) => `<button class="ev-thumb" data-rp="${p.id}" data-rpev="${p.evidenceId || ''}" title="${esc(p.street || '')}"><span class="spin"></span><span class="ev-thumb-t">${dateTime(p.createdAt)}</span>${p.evidenceId ? `<span class="ev-thumb-ev" title="Already logged: picking it attaches this evidence">EV-${String(p.evidenceId).padStart(5, '0')}</span>` : ''}</button>`).join('')}</div>`;
    const imgs = {};
    $$('[data-rp]', box).forEach((b) => b.onclick = () => {
      const id = +b.dataset.rp; if (!imgs[id]) return;
      $$('[data-rp]', box).forEach((x) => x.classList.toggle('on', x === b));
      if (prev) prev.innerHTML = `<img src="${imgs[id]}" alt="">`;
      onPick({ id, image: imgs[id], evidenceId: +b.dataset.rpev || null });
    });
    for (const b of $$('[data-rp]', box)) {   // one at a time: each is a full picture
      const x = await call('evRollPhoto', { id: +b.dataset.rp });
      if (!b.isConnected) return;
      if (x.ok) { imgs[x.data.id] = x.data.image; b.querySelector('.spin').outerHTML = `<img src="${x.data.image}" alt="">`; } else b.querySelector('.spin').outerHTML = '<span class="hint">—</span>';
    }
  }
  M.rollPicker = rollPicker;

  // ---------------------------------------------------------------- add a photo as evidence
  function photoModal(o) {
    o = o || {};
    let tab = 'roll', pick = null;
    modal(`<div class="m-title">Add a photo as evidence${o.reportId ? ' · report #' + o.reportId : ''}</div>
      <div class="seg mb" id="ep-tab"><button data-ept="roll" class="on">🖼 My camera roll</button><button data-ept="link">🔗 From a link</button></div>
      <div class="ev-pick"><div id="ep-body"></div><div class="ev-prev" id="ep-prev"><span class="hint">The preview shows here</span></div></div>
      <div class="field"><label>Note <span class="hint">(optional)</span></label><input id="ep-note" maxlength="300" placeholder="What it shows"></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="ep-go" data-primary disabled>Log as evidence</button></div>`, (card, closeIt) => {
      const body = $('#ep-body', card), prev = $('#ep-prev', card), goBtn = $('#ep-go', card);
      const show = (t) => {
        tab = t; pick = null; goBtn.disabled = true; prev.innerHTML = '<span class="hint">The preview shows here</span>';
        $$('[data-ept]', card).forEach((b) => b.classList.toggle('on', b.dataset.ept === t));
        if (t === 'roll') { rollPicker(body, prev, (p) => {
          pick = { photoId: p.id }; goBtn.disabled = false;
          const evc = p.evidenceId ? 'EV-' + String(p.evidenceId).padStart(5, '0') : null;
          goBtn.textContent = evc ? (o.reportId ? `Attach ${evc}` : `Open ${evc}`) : (o.reportId ? 'Log and attach' : 'Log as evidence');
        }); return; }
        body.innerHTML = '<div class="field"><label>Picture link <span class="hint">(public http/https, jpg/png/webp, 300 KB at most)</span></label><input id="ep-url" maxlength="500" placeholder="https://…/photo.jpg"></div>';
        let t2 = null;
        $('#ep-url', card).oninput = (e) => { clearTimeout(t2); goBtn.disabled = true; t2 = setTimeout(() => {
          const u = e.target.value.trim();
          if (!/^https?:\/\/[^\s]+$/i.test(u)) { prev.innerHTML = `<span class="hint">${u ? 'A link starts with https://' : 'The preview shows here'}</span>`; return; }
          prev.innerHTML = '<div class="spin"></div>';
          const img = new Image();
          img.onload = () => { prev.innerHTML = ''; prev.appendChild(img); pick = { url: u }; goBtn.disabled = false; };
          img.onerror = () => { prev.innerHTML = '<span class="hint">The preview did not load here. You can still try: the server fetches it and checks it is a picture.</span>'; pick = { url: u }; goBtn.disabled = false; };
          img.src = u;
        }, 300); };
      };
      $$('[data-ept]', card).forEach((b) => b.onclick = () => show(b.dataset.ept));
      goBtn.onclick = (ev) => busy(ev.currentTarget, async () => {
        if (!pick) return;
        const r = await call('evPhoto', Object.assign({ note: $('#ep-note', card).value, reportId: o.reportId }, pick));
        const d = r.data || {};
        const msg = d.existing ? (o.reportId ? `${d.code} (already logged) attached to report #${o.reportId}` : `This photo is already evidence ${d.code}`)
          : 'Logged as ' + (d.code || 'evidence') + (o.reportId ? ` and attached to report #${o.reportId}` : '');
        if (said(r, msg)) { closeIt(); if (o.after) o.after(d); }
      });
      show(tab);
    });
  }
  M.evidencePhoto = photoModal;

  // ---------------------------------------------------------------- evidence on a report
  function attachPicker(reportId, after) {
    modal(`<div class="m-title">Attach evidence to report #${reportId}</div>
      <input type="text" id="ap-q" placeholder="Search EV-number, street, serial…" autocomplete="off">
      <div class="res-list ev-ap" id="ap-list"><div class="loading-row"><div class="spin"></div></div></div>
      <div class="row end"><button class="btn ghost" data-x>Done</button></div>`, (card) => {
      const load = async (q) => {
        const r = await call('evList', { q, status: 'open' });
        const box = $('#ap-list', card); if (!box) return;
        const rows = (r.ok && r.data) || [];
        box.innerHTML = rows.length ? rows.map((e) => `<div class="res ev-row"><div class="ev-main"><div class="ev-top"><span class="ev-code">${esc(e.code)}</span>${kindPill(e.kind)}</div>
          <div class="ev-label">${esc(e.label)}</div><div class="hint">${esc(e.street || '—')} · ${ago(e.collectedAt || e.createdAt)}</div></div><button class="btn small" data-apl="${e.id}">Attach</button></div>`).join('') : empty('Nothing found', '🔎');
        $$('[data-apl]', box).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('evLink', { reportId, evidenceId: +b.dataset.apl }), 'Attached')) { b.textContent = '✓ Attached'; b.disabled = true; if (after) after(); } }));
      };
      let t = null;
      $('#ap-q', card).oninput = (e) => { clearTimeout(t); t = setTimeout(() => load(e.target.value.trim()), 250); };
      load('');
    });
  }

  // 1.5.1: the report's evidence in full (photo previews, lab results), near the top of the report.
  // Refreshes itself while something on it is still in the lab, so a result shows up without reopening.
  async function evCard(v, x) {
    const info = await status();
    if (!info.installed || !v.isConnected) return;
    const r = await call('evForReport', { reportId: x.id });
    if (!v.isConnected || S.view !== 'reports') return;
    const rows = (r.ok && r.data) || [];
    const w = can('mdt_reports_write');
    const tiles = !!M.evTile;
    const html = `<div class="card" id="rv-ev"><div class="card-head"><div class="card-title">Evidence <span class="hint">· ${rows.length}</span></div>
      <div class="row">${w ? '<button class="btn small" id="rv-ev-add">+ Add evidence</button>' : ''}${w && info.collect ? '<button class="btn small" id="rv-ev-photo">📷 Upload photo</button>' : ''}</div></div>
      ${!rows.length ? '<div class="hint">No evidence on this report yet.</div>' : tiles
        ? `<div class="cs-evs rep">${rows.map((e) => M.evTile(e, { remove: w, removeTitle: 'Take it off this report' })).join('')}</div>`
        : rows.map((e) => `<div class="li"><span class="ev-code">${esc(e.code)}</span>${kindPill(e.kind)}<div class="li-main"><a class="lnk" data-evgo="${e.id}">${esc(e.label)}</a>
        <span class="hint">${esc(e.street || '—')}${e.hasResult ? ' · has a lab result' : ''}</span></div>${w ? `<button class="btn small ghost" data-evoff="${e.id}" title="Take it off this report">✕</button>` : ''}</div>`).join('')}</div>`;
    const old = $('#rv-ev', v);
    if (old) old.outerHTML = html;
    else {
      const cs = $('#rv-case', v), main = $('.cols-main', v);
      if (cs) cs.insertAdjacentHTML('afterend', html); else if (main) main.insertAdjacentHTML('beforebegin', html); else v.insertAdjacentHTML('beforeend', html);
    }
    const box = $('#rv-ev', v);
    const again = () => evCard(v, x);
    const off = (eid, b) => busy(b, async () => { if (said(await call('evUnlink', { reportId: x.id, evidenceId: eid }), 'Taken off the report')) again(); });
    if (tiles) M.wireTiles(box, rows, null, off);
    else {
      $$('[data-evgo]', box).forEach((a) => a.onclick = () => { E.sel = +a.dataset.evgo; E.status = 'all'; go('evidence'); });
      $$('[data-evoff]', box).forEach((b) => b.onclick = () => off(+b.dataset.evoff, b));
    }
    if ($('#rv-ev-add', v)) $('#rv-ev-add', v).onclick = () => (M.evPicker
      ? M.evPicker({ reportId: x.id, title: `Add evidence to report #${x.id}`, have: rows.map((e) => e.id), now: true, after: again })
      : attachPicker(x.id, again));
    if ($('#rv-ev-photo', v)) $('#rv-ev-photo', v).onclick = () => photoModal({ reportId: x.id, after: again });
    // a result still cooking in the lab: look again shortly
    clearTimeout(v._evPoll);
    if (rows.some((e) => e.status === 'lab' && !e.result)) {
      const me = x.id;
      v._evPoll = setTimeout(() => { if (v.isConnected && S.view === 'reports' && $('#rv-ev', v) && v._evRid === me) evCard(v, x); }, 15000);
    }
    v._evRid = x.id;
  }

  const prevReportView = HOOK.reportView;
  HOOK.reportView = (v, x, reload) => {
    if (prevReportView) prevReportView(v, x, reload);
    evCard(v, x);
  };
})();
