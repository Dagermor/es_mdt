// es_mdt 1.5.0: Cases. A case ties reports, evidence (with photos and lab results), warrants and suspects together.
// Also: the case card + the case's evidence on every report page, a case picker (reports, evidence), and the
// full-screen photo viewer (lightbox.js) for evidence photos. The server checks everything again.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, toast, said, busy, ago, date, dateTime, modal, confirmBox, personPicker, pill, empty, can, P, go, VIEWS, HOOK, typeLabel } = M;
  const CST = { open: ['Open', 'on'], closed: ['Closed', 'accent'], archived: ['Archived', 'off'] };
  const KIND = { casing: ['Casing', '⁍'], blood: ['Blood', '🩸'], fragment: ['Fragment', '✶'], photo: ['Photo', '📷'], item: ['Item', '▣'], print: ['Fingerprint', '🖐'], weapon: ['Weapon', '🔫'] };
  const EST = { held: 'With an officer', lab: 'In the lab', locker: 'In a locker', stored: 'Stored', digital: 'In the MDT', released: 'Released', destroyed: 'Destroyed' };
  const ACT = { collected: 'Collected', lab_in: 'Into the lab', lab_out: 'Out of the lab', analyzed: 'Lab result', locker_in: 'Into a locker', locker_out: 'Out of a locker',
    locker_move: 'Moved locker', report: 'Attached to a report', unreport: 'Taken off a report', note: 'Note', destroyed: 'Destroyed', logged: 'Logged',
    case: 'Filed to a case', uncase: 'Taken off a case', purged: 'Purged (archived case)', matched: 'Print matched', handover: 'Handed over', taken: 'Taken', stashed: 'Put in a stash / boot', dropped: 'Dropped', released: 'Released' };
  // 1.11.3: whip_evidence timeline rows get their own titles. Newer rows have their own code (wev_*); rows written by
  // 1.11.0-1.11.2 were all 'evidence' and are recognised by their text, so old entries read right too.
  const WEVLOG = { wev_filed: ['Evidence filed', '📥'], wev_lab: ['Lab result', '🧪'], wev_sent: ['Sent to lab', '🧪'],
    wev_taken: ['Taken from locker', '📤'], wev_returned: ['Returned to locker', '↩'], wev_deleted: ['Evidence deleted', '🗑'] };
  function wevLog(l) {
    let code = l.what, d = l.detail || '';
    if (l.what === 'evidence') {
      let m;
      if ((m = /^From the lab: (.*)$/.exec(d))) { code = 'wev_lab'; d = m[1]; }
      else if (/^whip_evidence: (\d+) items? into the locker/.test(d)) { code = 'wev_filed'; d = d.replace(/^whip_evidence: /, ''); }
      else if (/^(Taken out of the whip_evidence locker|whip_evidence locker: taken)$/.test(d)) { code = 'wev_taken'; d = ''; }
      else if (/^(Returned to the whip_evidence locker|whip_evidence locker: returned)$/.test(d)) { code = 'wev_returned'; d = ''; }
      else if (/^(Evidence locker deleted in whip_evidence|whip_evidence locker: deleted)$/.test(d)) { code = 'wev_deleted'; d = 'The case locker was deleted in whip_evidence'; }
      else return null;
    }
    const w = WEVLOG[code]; if (!w) return null;
    return { t: w[0], ico: w[1], d };
  }
  const LOGW = { opened: 'Case opened', title: 'Renamed', notes: 'Notes edited', lead: 'Lead changed', closed: 'Closed', archived: 'Archived', reopened: 'Reopened',
    officer: 'Officer assigned', officer_off: 'Officer removed', suspect: 'Suspect added', suspect_off: 'Suspect removed', report: 'Report filed', report_off: 'Report removed',
    evidence: 'Evidence filed', evidence_off: 'Evidence removed', warrant: 'Warrant', warrant_off: 'Warrant removed', lab: 'Lab result', lab_match: 'Lab match', print_match: 'Print matched' };
  const stPill = (st) => pill((CST[st] || [st])[0], (CST[st] || ['', ''])[1]);
  const kindPill = (k) => `<span class="ev-k ev-${esc(k)}">${(KIND[k] || [k, '·'])[1]} ${esc((KIND[k] || [k])[0])}</span>`;
  const C = { q: '', status: 'open', mine: false };

  // ---------------------------------------------------------------- photos: thumbnails + the full-screen viewer
  const imgCache = {};
  async function imageOf(id) {
    if (imgCache[id]) return imgCache[id];
    const r = await call('evImage', { id });
    if (r.ok && r.data) { imgCache[id] = r.data.image; return r.data.image; }
    return null;
  }
  // fill every [data-evimg] thumbnail inside root, one at a time (each is a full picture)
  async function loadThumbs(root) {
    for (const el of $$('[data-evimg]', root)) {
      if (!el.isConnected) return;
      const src = await imageOf(+el.dataset.evimg);
      if (!el.isConnected) return;
      el.innerHTML = src ? `<img src="${src}" alt="">` : '<span class="hint">—</span>';
    }
  }
  const photoMeta = (e, caseNo) => ({
    title: `${e.code} · Photo`, sub: e.label,
    meta: [['Taken', dateTime(e.createdAt)], ['Where', e.street], ['Photographer', e.photographerName], ['Logged by', e.collector], ['Case', caseNo || e.caseNo], ['Note', e.note]],
    load: () => (e.image ? Promise.resolve(e.image) : imageOf(e.id)),
  });
  // a gallery: every photo among `items`, opened at `id`
  function openGallery(items, id, caseNo) {
    const photos = items.filter((e) => e.kind === 'photo');
    window.Lightbox.open(photos.map((e) => photoMeta(e, caseNo)), Math.max(0, photos.findIndex((e) => e.id === id)));
  }
  M.openPhoto = (e) => window.Lightbox.open([photoMeta(e)], 0);
  M.openGallery = openGallery; M.evImageOf = imageOf;

  // one evidence tile: photo preview, kind, status / place, lab result
  function evTile(e, opts) {
    const where = e.status === 'held' ? 'With ' + (e.holder || 'an officer') : e.status === 'locker' ? (e.statusText || e.place || 'In a locker') : e.status === 'stored' ? (e.place || 'Stored') : (EST[e.status] || e.statusText || e.status);
    const res = e.result ? `<div class="cs-res">🧪 ${esc(e.result)}</div>` : e.status === 'lab' ? `<div class="cs-res wait">🧪 In the lab${e.secondsLeft ? ' · result in about ' + Math.max(1, Math.ceil(e.secondsLeft / 60)) + ' min' : '…'}</div>` : '';
    return `<div class="cs-ev${e.kind === 'photo' ? ' photo' : ''}">
      ${e.kind === 'photo' ? `<div class="cs-ph" data-evimg="${e.id}" data-open="${e.id}" title="Open full screen"><div class="spin"></div></div>` : ''}
      <div class="cs-ev-body"><div class="row"><span class="ev-code">${esc(e.code)}</span>${kindPill(e.kind)}<span class="spacer"></span>${opts && opts.remove ? `<button class="btn small ghost" data-evoff="${e.id}" title="${esc((opts && opts.removeTitle) || 'Take it off the case')}">✕</button>` : ''}</div>
        <a class="lnk cs-ev-label" data-evgo="${e.id}">${esc(e.label)}${e.shots > 1 ? ` ×${e.shots}` : ''}</a>
        <div class="hint">${e.caliber && !String(e.label || '').includes(e.caliber) ? esc(e.caliber) + ' · ' : ''}${esc(e.street || '—')} · ${esc(where)}${e.collector ? ' · ' + esc(e.collector) : ''}${(e.collectedAt || e.createdAt) ? ' · ' + (e.kind === 'photo' ? 'taken ' : 'collected ') + ago(e.collectedAt || e.createdAt) : ''}</div>${res}
        ${e.note ? `<div class="hint cs-note">“${esc(e.note)}”</div>` : ''}</div></div>`;
  }
  function wireTiles(root, items, caseNo, onRemove) {
    $$('[data-open]', root).forEach((el) => el.onclick = () => openGallery(items, +el.dataset.open, caseNo));
    $$('[data-evgo]', root).forEach((a) => a.onclick = () => go('evidence', +a.dataset.evgo));
    if (onRemove) $$('[data-evoff]', root).forEach((b) => b.onclick = () => onRemove(+b.dataset.evoff, b));
    loadThumbs(root);
  }
  M.evTile = evTile; M.wireTiles = wireTiles;

  // ---------------------------------------------------------------- case picker (reports, evidence, report editor)
  // onPick({ id, number, title }) ; opts.allowNone: offer "No case"; opts.newTitle: the title a new case starts with
  function casePicker(onPick, opts) {
    opts = opts || {};
    const mayCreate = can('cases_create') || S.ctx.staff;
    modal(`<div class="m-title">${esc(opts.title || 'Pick a case')}</div>
      <input type="text" id="cp-q" placeholder="Search a case number or title…" autocomplete="off">
      <div id="cp-list" class="cs-pick"><div class="loading-row"><div class="spin"></div></div></div>
      ${mayCreate ? `<div class="cs-new"><div class="lbl">Or open a new case</div><div class="row"><input type="text" id="cp-new" maxlength="120" placeholder="Case title" value="${esc(opts.newTitle || '')}"><button class="btn accent" id="cp-make">+ Open case</button></div></div>` : '<p class="hint">Your rank cannot open new cases (rank 30+).</p>'}
      <div class="row end">${opts.allowNone ? '<button class="btn ghost" id="cp-none">No case</button>' : ''}<button class="btn ghost" data-x>Cancel</button></div>`, (card, closeIt) => {
      let t = null, seq = 0;
      const load = async () => {
        const my = ++seq;
        const r = await call('caseFind', { q: $('#cp-q', card).value.trim() });
        if (my !== seq || !card.isConnected) return;
        const list = (r.ok && r.data) || [];
        $('#cp-list', card).innerHTML = list.length ? list.map((k) => `<div class="li click" data-pick="${k.id}" data-no="${esc(k.number)}" data-t="${esc(k.title)}"><span class="cs-no">${esc(k.number)}</span><div class="li-main"><b>${esc(k.title)}</b></div>${stPill(k.status)}</div>`).join('')
          : empty('No case matches', '▣');
        $$('[data-pick]', card).forEach((el) => el.onclick = () => { closeIt(); onPick({ id: +el.dataset.pick, number: el.dataset.no, title: el.dataset.t }); });
      };
      $('#cp-q', card).oninput = () => { clearTimeout(t); t = setTimeout(load, 220); };
      if ($('#cp-none', card)) $('#cp-none', card).onclick = () => { closeIt(); onPick(null); };
      if ($('#cp-make', card)) $('#cp-make', card).onclick = (e) => busy(e.currentTarget, async () => {
        const title = $('#cp-new', card).value.trim();
        if (!title) { toast('Give the new case a title', 'err'); return; }
        if (opts.deferNew) { closeIt(); onPick({ id: 0, newTitle: title, number: 'new', title }); return; }
        const r = await call('caseSave', { title });
        if (said(r, 'Case ' + (r.data && r.data.number) + ' opened')) { closeIt(); onPick({ id: r.data.id, number: r.data.number, title }); }
      });
      load();
    });
  }
  M.casePicker = casePicker;

  // ---------------------------------------------------------------- the Cases tab
  VIEWS.cases = async (v, arg) => {
    if (arg) return caseView(v, +arg);
    const mayCreate = can('cases_create') || (S.ctx.staff && !S.ctx.readOnly);
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Cases</div><div class="hint">Investigations: reports, evidence, photos, warrants and suspects in one place</div></div>
      <div class="row">${(P().evidence_manage || S.ctx.staff) && !S.ctx.readOnly ? '<button class="btn ghost" id="cs-purge" title="Empty the evidence lockers of long-archived cases">🗄 Purge archived lockers</button>' : ''}${mayCreate ? '<button class="btn accent" id="cs-new" data-probe-press>+ New case</button>' : ''}</div></div>
      <div class="filters"><input type="text" id="cs-q" placeholder="Search C-number, title, suspect, notes or a report…" value="${esc(C.q)}">
        <div class="seg big">${[['open', 'Open'], ['closed', 'Closed'], ['archived', 'Archived'], ['', 'All']].map(([k, l]) => `<button data-cst="${k}" class="${C.status === k ? 'on' : ''}">${l}</button>`).join('')}</div>
        <label class="chip-t"><input type="checkbox" id="cs-mine"${C.mine ? ' checked' : ''}><span>Mine</span></label></div>
      <div id="cs-list"><div class="loading-row"><div class="spin"></div></div></div>`;
    const load = async () => {
      const r = await call('cases', C);
      const box = $('#cs-list'); if (!box) return;
      const list = (r.ok && r.data) || [];
      box.innerHTML = list.length ? `<div class="cs-grid">${list.map((k) => `<div class="cs-card click" data-case="${k.id}">
          <div class="row"><span class="cs-no">${esc(k.number)}</span>${stPill(k.status)}<span class="spacer"></span><span class="hint">${ago(k.updatedAt || k.createdAt)}</span></div>
          <div class="cs-title">${esc(k.title)}</div>
          <div class="hint">Lead: ${esc(k.lead || '—')} · opened ${date(k.createdAt)}</div>
          <div class="cs-counts"><span>☰ ${k.reports} report${k.reports === 1 ? '' : 's'}</span><span>⚲ ${k.evidence} evidence</span><span>☺ ${k.suspects} suspect${k.suspects === 1 ? '' : 's'}</span>${k.warrants ? `<span class="txt-bad">⚖ ${k.warrants} warrant${k.warrants === 1 ? '' : 's'}</span>` : ''}</div></div>`).join('')}</div>`
        : empty(r.ok ? (C.q ? 'No case matches' : 'No cases here yet.' + (mayCreate ? ' Open one with “+ New case”, or from a report.' : '')) : r.why, '▣');
      $$('[data-case]', box).forEach((el) => el.onclick = () => go('cases', +el.dataset.case));
    };
    let t = null;
    $('#cs-q').oninput = (e) => { C.q = e.target.value.trim(); clearTimeout(t); t = setTimeout(load, 250); };
    $$('[data-cst]').forEach((b) => b.onclick = () => { C.status = b.dataset.cst; $$('[data-cst]').forEach((x) => x.classList.toggle('on', x === b)); load(); });
    $('#cs-mine').onchange = (e) => { C.mine = e.target.checked; load(); };
    if ($('#cs-new')) $('#cs-new').onclick = () => editCase(null);
    if ($('#cs-purge')) $('#cs-purge').onclick = purgeModal;
    load();
  };

  function editCase(k, after) {
    let lead = k && k.leadCharId ? { charId: k.leadCharId, name: k.lead } : (k ? null : { charId: S.ctx.me.charId, name: S.ctx.me.name });
    modal(`<div class="m-title">${k ? 'Edit case ' + esc(k.number) : 'Open a new case'}</div>
      <div class="field"><label>Title</label><input id="ce-title" maxlength="120" placeholder="Armed robbery · Fleeca Route 68" value="${esc(k ? k.title : '')}"></div>
      <div class="field"><label>Lead detective</label><div id="ce-lead-pick"></div><div id="ce-lead" class="picked">${lead ? `<span class="pill accent">${esc(lead.name || '#' + lead.charId)}</span>` : '<span class="hint">Nobody yet</span>'}</div></div>
      <div class="field"><label>Notes</label><textarea id="ce-notes" maxlength="4000" rows="7" placeholder="What happened, leads, what is still to do…">${esc(k ? k.notes || '' : '')}</textarea></div>
      <p class="hint">${k ? 'Every change is in the case timeline.' : 'The case gets the next number (C-year-0001). Its evidence locker is made the first time it is opened.'}</p>
      <div id="ce-others" class="edit-others hidden"></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="ce-go" data-primary>${k ? 'Save' : 'Open case'}</button></div>`, (card, closeIt) => {
      if (k && M.watchEditing) M.watchEditing('case', k.id, () => !!$('#ce-go', card), $('#ce-others', card));
      personPicker($('#ce-lead-pick', card), 'Search the lead detective…', (p) => { lead = p; $('#ce-lead', card).innerHTML = `<span class="pill accent">${esc(p.name)}</span>`; });
      $('#ce-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('caseSave', { id: k ? k.id : undefined, title: $('#ce-title', card).value, notes: $('#ce-notes', card).value, leadCharId: lead ? lead.charId : null, ver: k ? k.ver || 0 : undefined });
        if (said(r, k ? 'Case saved' : 'Case ' + (r.data && r.data.number) + ' opened')) { closeIt(); if (after) after(r.data); else go('cases', r.data.id); }
      });
    });
  }

  function purgeModal() {
    modal(`<div class="m-title">Purge archived case lockers</div>
      <p class="m-text">Empties the evidence lockers of cases archived longer ago than this. Every bag in them is marked destroyed and the purge is in each item's chain of custody. Open and closed cases are never touched.</p>
      <div class="field"><label>Archived more than (days)</label><input id="pg-days" type="number" min="1" max="3650" placeholder="90 (the server's setting)"></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn danger" id="pg-go" data-primary>Purge</button></div>`, (card, closeIt) => {
      $('#pg-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('casePurge', { days: +$('#pg-days', card).value || 0 });
        if (r.ok) { toast(`Purged ${r.data.lockers} locker${r.data.lockers === 1 ? '' : 's'}: ${r.data.bags} bag${r.data.bags === 1 ? '' : 's'}, ${r.data.items} other item${r.data.items === 1 ? '' : 's'} (archived ${r.data.days}+ days)`, 'ok'); closeIt(); }
        else said(r);
      });
    });
  }

  // ---------------------------------------------------------------- one case
  async function caseView(v, cid) {
    const r = await call('case', { id: cid });
    if (S.view !== 'cases') return;
    if (!r.ok) { v.innerHTML = `<button class="btn small ghost" data-go="cases">← Cases</button>` + empty(r.why || 'Not found'); $$('[data-go]', v).forEach((b) => b.onclick = () => go('cases')); return; }
    const x = r.data, k = x.case, cn = x.can || {}, ev = x.evidence || { items: [] };
    const items = ev.items || [];
    const photos = items.filter((e) => e.kind === 'photo'), things = items.filter((e) => e.kind !== 'photo');
    const reload = () => caseView(v, cid);
    const tl = [];
    (x.log || []).forEach((l) => { const w = wevLog(l); tl.push({ at: l.at, ico: w ? w.ico : l.what === 'print_match' ? '🖐' : /^lab/.test(l.what) ? '🧪' : '▣', t: w ? w.t : (LOGW[l.what] || l.what), d: w ? w.d : l.detail, by: l.by }); });
    (ev.custody || []).filter((c) => c.action !== 'matched').forEach((c) => tl.push({ at: c.at, ico: '⚲', t: (c.code ? c.code + ' · ' : (c.itemLabel ? c.itemLabel + ' · ' : '')) + (ACT[c.action] || c.action), d: [c.fromWhere || c.toWhere ? `${c.fromWhere || '—'} → ${c.toWhere || '—'}` : '', c.note].filter(Boolean).join(' · '), by: c.by }));
    (x.reports || []).forEach((rp) => tl.push({ at: rp.createdAt, ico: '☰', t: `Report #${rp.id} written`, d: rp.visible ? rp.title : (rp.deptShort || 'another department'), by: rp.author }));
    (x.warrants || []).forEach((w) => tl.push({ at: w.createdAt, ico: '⚖', t: `Warrant #${w.id} · ${w.status}`, d: (w.name || '') + (w.reason ? ' · ' + w.reason : ''), by: w.requestedByName }));
    tl.sort((a, b) => (b.at || 0) - (a.at || 0));
    const lk = ev.locker || { items: [] };
    v.innerHTML = `<div class="v-head"><div><button class="btn small ghost" data-go="cases">← Cases</button>
        <div class="v-title"><span class="cs-no big">${esc(k.number)}</span> ${esc(k.title)}</div>
        <div class="hint">${stPill(k.status)} Lead: <b>${esc(k.lead || '—')}</b> · opened ${dateTime(k.createdAt)}${k.createdByName ? ' by ' + esc(k.createdByName) : ''}${k.closedAt ? ' · closed ' + date(k.closedAt) : ''}${k.archivedAt ? ' · archived ' + date(k.archivedAt) : ''}</div></div>
      <div class="row">${cn.edit ? '<button class="btn" id="cv-edit">Edit</button>' : ''}
        ${cn.close ? (k.status === 'open' ? '<button class="btn" data-cst="closed">Close case</button><button class="btn ghost" data-cst="archived">Archive</button>'
          : k.status === 'closed' ? '<button class="btn" data-cst="open">Reopen</button><button class="btn ghost" data-cst="archived">Archive</button>'
          : '<button class="btn" data-cst="open">Reopen</button>') : ''}</div></div>
      ${k.status === 'archived' ? '<div class="banner">This case is archived: read-only. Its evidence locker still opens in the evidence room.</div>' : ''}
      <div class="cols-main">
        <div>
          <div class="card"><div class="card-title">Notes</div><div class="narr">${esc(k.notes || '').replace(/\n/g, '<br>') || '<span class="hint">No notes yet.</span>'}</div></div>
          <div class="card"><div class="card-head"><div class="card-title">Reports <span class="hint">· ${(x.reports || []).length}</span></div>${cn.file && can('mdt_reports_write') ? '<button class="btn small" id="cv-rep">+ File a report</button>' : ''}</div>
            ${(x.reports || []).length ? x.reports.map((rp) => `<div class="li${rp.visible ? ' click' : ''}" ${rp.visible ? `data-rep="${rp.id}"` : ''}><b>#${rp.id}</b><span class="tag t-${esc(rp.type)}">${esc(typeLabel(rp.type))}</span>
              <div class="li-main">${rp.visible ? `<b>${esc(rp.title)}</b>` : `<span class="hint">${esc(rp.deptShort || 'Another department')} report (not yours to open)</span>`}<span class="hint">${esc(rp.author || '')} · ${date(rp.createdAt)}</span></div>
              ${cn.file && rp.visible && can('mdt_reports_write') ? `<button class="btn small ghost" data-repoff="${rp.id}" title="Take it off the case">✕</button>` : ''}</div>`).join('') : '<div class="hint">No reports yet. Open a report and use “Add to a case”, or file one here.</div>'}</div>
          ${ev.installed === false ? '' : `
          <div class="card"><div class="card-head"><div class="card-title">Evidence <span class="hint">· ${things.length} item${things.length === 1 ? '' : 's'}, ${photos.length} photo${photos.length === 1 ? '' : 's'}</span></div>${cn.file && ev.installed !== false ? '<button class="btn small" id="cv-ev">+ File evidence</button>' : ''}</div>
            ${ev.installed === false ? '<div class="hint">The evidence system (es_evidence) is not running.</div>' : ''}
            ${photos.length ? `<div class="lbl">Photos</div><div class="cs-photos">${photos.map((e) => evTile(e, { remove: cn.file })).join('')}</div>` : ''}
            ${things.length ? `<div class="lbl">Physical evidence</div><div class="cs-evs">${things.map((e) => evTile(e, { remove: cn.file })).join('')}</div>` : ''}
            ${!items.length ? '<div class="hint">Nothing filed yet. Bags put in this case’s locker are filed automatically; or use “+ File evidence”, or the Evidence tab.</div>' : ''}</div>
          <div class="card"><div class="card-title">Evidence locker <span class="hint">· ${lk.items.length} item${lk.items.length === 1 ? '' : 's'} · opened in the evidence room by case number</span></div>
            ${lk.items.length ? lk.items.map((it) => `<div class="li"><span class="hint">#${it.slot}</span><div class="li-main">${it.evidenceId ? `<a class="lnk" data-evgo="${it.evidenceId}">${esc(it.label)}</a>` : `<b>${esc(it.label)}</b>`}</div>${it.amount > 1 ? `<span class="hint">×${it.amount}</span>` : ''}</div>`).join('') : '<div class="hint">Empty.</div>'}</div>
          `}
          ${x.wev && x.wev.enabled ? '<div id="cv-wev"></div>' : ''}
          ${ev.installed === false ? '' : `
          <div class="card"><div class="card-head"><div class="card-title">Chain of custody <span class="hint">· everything in this case, newest first</span></div></div>
            <div class="ev-chain cs-chain">${(ev.custody || []).slice(0, 60).map((c) => `<div class="ev-step"><span class="ev-dot"></span><div><b>${c.code ? esc(c.code) + ' · ' : ''}${esc(ACT[c.action] || c.action)}</b>${c.fromWhere || c.toWhere ? ` <span class="hint">${esc(c.fromWhere || '—')} → ${esc(c.toWhere || '—')}</span>` : ''}
              ${c.itemLabel ? `<div class="hint">${esc(c.itemLabel)}${c.amount > 1 ? ' ×' + c.amount : ''}</div>` : ''}${c.note ? `<div class="hint">${esc(c.note)}</div>` : ''}<div class="hint">${c.by ? esc(c.by) + ' · ' : ''}${dateTime(c.at)}</div></div></div>`).join('') || '<div class="hint">Nothing logged yet.</div>'}</div></div>
          `}
        </div>
        <div>
          <div class="card"><div class="card-head"><div class="card-title">Investigators</div></div>
            <div class="li"><span class="pill accent">Lead</span><div class="li-main"><b>${esc(k.lead || '—')}</b></div></div>
            ${(x.officers || []).map((o) => `<div class="li"><span class="pill">Assigned</span><div class="li-main"><b>${esc(o.name || '#' + o.charId)}</b></div>${cn.edit ? `<button class="btn small ghost" data-offoff="${o.charId}">✕</button>` : ''}</div>`).join('')}
            ${cn.edit ? '<div id="cv-off-pick" class="mt"></div>' : ''}</div>
          <div class="card"><div class="card-head"><div class="card-title">Suspects</div></div>
            ${(x.suspects || []).map((s) => `<div class="li"><div class="li-main"><a class="lnk" data-person="${s.charId}"><b>${esc(s.name || '#' + s.charId)}</b></a>
                <span class="hint">${s.fromReport ? 'On report ' + (s.reports || []).map((n) => '#' + n).join(', ') : (s.note ? esc(s.note) : 'Added to the case')}${s.warrants ? ' · <span class="txt-bad">active warrant</span>' : ''}</span></div>
              ${cn.file && (can('warrants_issue') || can('warrants_request')) ? `<button class="btn small ghost" data-war="${s.charId}" data-name="${esc(s.name || '')}">Warrant</button>` : ''}
              ${cn.edit && s.added ? `<button class="btn small ghost" data-susoff="${s.charId}">✕</button>` : (cn.edit && s.fromReport ? `<button class="btn small ghost" data-susadd="${s.charId}" title="Add to the case itself">+</button>` : '')}</div>`).join('') || '<div class="hint">No suspects yet.</div>'}
            ${cn.edit ? '<div id="cv-sus-pick" class="mt"></div>' : ''}</div>
          <div class="card"><div class="card-title">Warrants</div>
            ${(x.warrants || []).map((w) => `<div class="li"><span class="pill ${w.status === 'active' ? 'bad' : w.status === 'requested' ? 'warn' : 'off'}">${esc(w.status)}</span><div class="li-main"><b>${esc(w.name || '')}</b><span class="hint">#${w.id} · ${esc(w.reason || '')}</span></div></div>`).join('') || '<div class="hint">No warrants.</div>'}</div>
          <div class="card"><div class="card-title">Timeline</div><div class="cs-tl">${tl.slice(0, 80).map((e) => `<div class="cs-tl-i"><span class="cs-tl-ico">${e.ico}</span><div><b>${esc(e.t)}</b>${e.d ? `<div class="hint">${esc(e.d)}</div>` : ''}<div class="hint">${e.by ? esc(e.by) + ' · ' : ''}${dateTime(e.at)}</div></div></div>`).join('') || '<div class="hint">Nothing yet.</div>'}</div></div>
        </div>
      </div>`;
    $$('[data-go]', v).forEach((b) => b.onclick = () => go(b.dataset.go));
    $$('[data-rep]', v).forEach((el) => el.onclick = () => go('reports', { view: +el.dataset.rep }));
    $$('[data-person]', v).forEach((a) => a.onclick = () => go('people', +a.dataset.person));
    $$('[data-evgo]', v).forEach((a) => a.onclick = () => go('evidence', +a.dataset.evgo));
    wireTiles(v, items, k.number, (eid, b) => busy(b, async () => {
      if (!await confirmBox('Take off the case', `Take EV-${String(eid).padStart(5, '0')} off case ${k.number}? It stays in the Evidence tab.`, 'Take off')) return;
      if (said(await call('caseLink', { kind: 'evidence', refId: eid, caseId: 0, fromCase: k.id }), 'Taken off the case')) reload();
    }));
    if ($('#cv-edit')) $('#cv-edit').onclick = () => editCase(k, reload);
    $$('[data-cst]', v).forEach((b) => b.onclick = async () => {
      const st = b.dataset.cst;
      const msg = st === 'archived' ? `Archive ${k.number}? It becomes read-only. Its locker stays readable, and after the purge period its locker can be emptied.` : st === 'closed' ? `Close ${k.number}? It can be reopened.` : `Reopen ${k.number}?`;
      if (!await confirmBox(st === 'open' ? 'Reopen case' : st === 'closed' ? 'Close case' : 'Archive case', msg, st === 'open' ? 'Reopen' : st === 'closed' ? 'Close' : 'Archive', st === 'archived')) return;
      const res = await call('caseStatus', { id: k.id, status: st });
      if (said(res, (res.data && res.data.warn) ? null : 'Case ' + (st === 'open' ? 'reopened' : st))) {
        if (res.data && res.data.warn) toast('Case ' + (st === 'open' ? 'reopened' : st) + ', but: ' + res.data.warn, 'err');
        reload();
      }
    });
    if ($('#cv-off-pick')) personPicker($('#cv-off-pick'), '+ Assign an officer…', async (p) => { if (said(await call('casePerson', { id: k.id, kind: 'officer', charId: p.charId }), p.name + ' assigned')) reload(); });
    if ($('#cv-sus-pick')) personPicker($('#cv-sus-pick'), '+ Add a suspect…', async (p) => { if (said(await call('casePerson', { id: k.id, kind: 'suspect', charId: p.charId }), p.name + ' added')) reload(); });
    $$('[data-offoff]', v).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('casePerson', { id: k.id, kind: 'officer', charId: +b.dataset.offoff, remove: true }), 'Removed')) reload(); }));
    $$('[data-susoff]', v).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('casePerson', { id: k.id, kind: 'suspect', charId: +b.dataset.susoff, remove: true }), 'Removed')) reload(); }));
    $$('[data-susadd]', v).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('casePerson', { id: k.id, kind: 'suspect', charId: +b.dataset.susadd }), 'Added')) reload(); }));
    $$('[data-war]', v).forEach((b) => b.onclick = () => M.warrantForm({ charId: +b.dataset.war, name: b.dataset.name }, reload, null, k.id));
    $$('[data-repoff]', v).forEach((b) => b.onclick = () => busy(b, async () => {
      if (!await confirmBox('Take off the case', `Take report #${b.dataset.repoff} off ${k.number}?`, 'Take off')) return;
      if (said(await call('caseLink', { kind: 'report', refId: +b.dataset.repoff, caseId: 0 }), 'Taken off')) reload();
    }));
    if ($('#cv-rep')) $('#cv-rep').onclick = () => reportPicker(async (rid) => { if (said(await call('caseLink', { kind: 'report', refId: rid, caseId: k.id }), `Report #${rid} filed to ${k.number}`)) reload(); });
    if ($('#cv-ev')) $('#cv-ev').onclick = () => evidencePicker(k, reload);
    if (HOOK.caseView) HOOK.caseView(v, x, reload);   // 1.11.0: whipev.js (whip_evidence locker)
  }

  function reportPicker(onPick) {
    modal(`<div class="m-title">File a report to this case</div><input type="text" id="rp-q" placeholder="Search a title, #number or a person…" autocomplete="off">
      <div id="rp-list" class="cs-pick"><div class="loading-row"><div class="spin"></div></div></div><div class="row end"><button class="btn ghost" data-x>Close</button></div>`, (card, closeIt) => {
      let t = null, seq = 0;
      const load = async () => {
        const my = ++seq;
        const r = await call('reports', { q: $('#rp-q', card).value.trim() });
        if (my !== seq || !card.isConnected) return;
        const list = (r.ok && r.data) || [];
        $('#rp-list', card).innerHTML = list.length ? list.map((x) => `<div class="li click" data-r="${x.id}"><b>#${x.id}</b><div class="li-main"><b>${esc(x.title)}</b><span class="hint">${esc(x.authorName || '')} · ${ago(x.createdAt)}</span></div></div>`).join('') : empty('No report matches');
        $$('[data-r]', card).forEach((el) => el.onclick = () => { closeIt(); onPick(+el.dataset.r); });
      };
      $('#rp-q', card).oninput = () => { clearTimeout(t); t = setTimeout(load, 220); };
      load();
    });
  }

  function evidencePicker(k, after) {
    modal(`<div class="m-title">File evidence to ${esc(k.number)}</div><input type="text" id="ep-q" placeholder="Search EV-number, street, serial, note…" autocomplete="off">
      <div id="ep-list" class="cs-pick"><div class="loading-row"><div class="spin"></div></div></div><div class="row end"><button class="btn ghost" data-x>Done</button></div>`, (card, closeIt) => {
      let t = null, seq = 0;
      const load = async () => {
        const my = ++seq;
        const r = await call('evList', { q: $('#ep-q', card).value.trim(), status: 'open', caseId: 'none' });
        if (my !== seq || !card.isConnected) return;
        const list = (r.ok && r.data) || [];
        $('#ep-list', card).innerHTML = list.length ? list.map((e) => `<div class="li"><span class="ev-code">${esc(e.code)}</span>${kindPill(e.kind)}<div class="li-main"><b>${esc(e.label)}</b><span class="hint">${esc(e.street || '—')} · ${ago(e.collectedAt || e.createdAt)}</span></div><button class="btn small accent" data-f="${e.id}">File</button></div>`).join('')
          : empty('No unfiled evidence matches (evidence already in a case is filed from its own page)');
        $$('[data-f]', card).forEach((b) => b.onclick = () => busy(b, async () => {
          if (said(await call('caseLink', { kind: 'evidence', refId: +b.dataset.f, caseId: k.id }), 'Filed')) { b.textContent = '✓ Filed'; b.disabled = true; }
        }));
      };
      $('#ep-q', card).oninput = () => { clearTimeout(t); t = setTimeout(load, 220); };
      $$('[data-x]', card).forEach((b) => b.addEventListener('click', () => after()));
      load();
    });
  }

  // ---------------------------------------------------------------- reports: the case card and the case's evidence
  async function reportCaseCard(v, x) {
    const r = await call('reportCase', { reportId: x.id });
    if (!v.isConnected || S.view !== 'reports') return;
    const d = (r.ok && r.data) || {};
    const k = d.case;
    const w = can('mdt_reports_write');
    const items = d.evidence || [];
    const on = d.onReport || [];
    const others = items.filter((e) => !on.includes(e.id));
    const html = `<div class="card cs-repcase" id="rv-case"><div class="card-head"><div class="card-title">Case</div>
        <div class="row">${w ? `<button class="btn small" id="rv-case-set">${k ? 'Change case' : '+ Add to a case'}</button>` : ''}</div></div>
      ${k ? `<div class="li click" data-casego="${k.id}"><span class="cs-no">${esc(k.number)}</span><div class="li-main"><b>${esc(k.title)}</b><span class="hint">${items.length} piece${items.length === 1 ? '' : 's'} of evidence in the case</span></div>${stPill(k.status)}</div>
        ${(S.ctx && S.ctx.config && S.ctx.config.esEvidence === false) ? '' : others.length ? `<div class="lbl mt">Other evidence in this case</div><div class="cs-evs rep">${others.map((e) => evTile(e)).join('')}</div>` : items.length ? '<div class="hint mt">All of the case\'s evidence is on this report (below).</div>' : '<div class="hint mt">No evidence filed to the case yet.</div>'}`
        : '<div class="hint">Not part of a case.</div>'}</div>`;
    const old = $('#rv-case', v);
    if (old) old.outerHTML = html;
    else {
      const ev = $('#rv-ev', v), main = $('.cols-main', v);
      if (ev) ev.insertAdjacentHTML('beforebegin', html); else if (main) main.insertAdjacentHTML('beforebegin', html); else v.insertAdjacentHTML('beforeend', html);
    }
    const box = $('#rv-case', v);
    if ($('[data-casego]', box)) $('[data-casego]', box).onclick = () => go('cases', k.id);
    wireTiles(box, others, k && k.number);
    if ($('#rv-case-set', box)) $('#rv-case-set', box).onclick = () => casePicker(async (pick) => {
      if (said(await call('caseLink', { kind: 'report', refId: x.id, caseId: pick ? pick.id : 0 }), pick ? `Filed to ${pick.number}` : 'Taken off the case')) reportCaseCard(v, x);
    }, { allowNone: !!k, newTitle: x.title, title: `Case for report #${x.id}` });
  }
  const prevReportView = HOOK.reportView;
  HOOK.reportView = (v, x, reload) => { if (prevReportView) prevReportView(v, x, reload); reportCaseCard(v, x); };

  // the report editor: pick a case (or a new one) while writing
  const prevEditor = HOOK.reportEditor;
  HOOK.reportEditor = (v, R, setType) => {
    if (prevEditor) prevEditor(v, R, setType);
    const loc = $('#re-loc', v);
    const anchor = loc && loc.closest('.field');
    if (!anchor) return;
    anchor.insertAdjacentHTML('afterend', `<div class="field" id="re-case-f"><label>Case</label><div class="row"><span id="re-case" class="hint">No case</span><button type="button" class="btn small" id="re-case-pick">Pick or open a case…</button></div></div>`);
    const show = () => { $('#re-case', v).innerHTML = R.casePick && R.casePick.none ? 'No case' : R.casePick ? (R.casePick.id ? `<span class="cs-no">${esc(R.casePick.number)}</span> ${esc(R.casePick.title)}` : `<span class="pill accent">New case</span> ${esc(R.casePick.newTitle)}`) : (R.caseNow ? `<span class="cs-no">${esc(R.caseNow.number)}</span> ${esc(R.caseNow.title)}` : 'No case'); };
    if (R.id) call('reportCase', { reportId: R.id }).then((r) => { if (r.ok && r.data && r.data.case) { R.caseNow = r.data.case; if ($('#re-case', v)) show(); } });
    $('#re-case-pick', v).onclick = () => casePicker((pick) => { R.casePick = pick || { none: true }; show(); },
      { allowNone: true, deferNew: true, newTitle: $('#re-title', v) ? $('#re-title', v).value : '', title: 'Case for this report' });
    show();
  };
  const prevAfter = HOOK.afterReportSave;
  HOOK.afterReportSave = async (rid, R) => {
    if (prevAfter) await prevAfter(rid, R);
    const p = R.casePick;
    if (!p || !rid) return;
    if (p.none) { if (R.caseNow) await call('caseLink', { kind: 'report', refId: rid, caseId: 0 }); return; }
    let cid = p.id;
    if (!cid && p.newTitle) {
      const r = await call('caseSave', { title: p.newTitle });
      if (!said(r)) return;
      cid = r.data.id; toast('Case ' + r.data.number + ' opened', 'ok');
    }
    if (cid) said(await call('caseLink', { kind: 'report', refId: rid, caseId: cid }));
  };
})();
