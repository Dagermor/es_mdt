// es_doj court: the dashboard, the court calendar, hearings (and their transcripts), and judge review of warrants.
(function () {
  'use strict';
  const D = window.DOJ;
  const { S, $, $$, esc, money, call, toast, said, busy, ago, inTime, date, dateTime, timeOnly, pill, empty, cap, labelOf, R, has,
    caseNo, modal, confirmBox, form, answer, go, rerender, views } = D;

  // ---------------------------------------------------------------- dashboard
  views.dashboard = async (h, arg, alive) => {
    const r = await call('dashboard');
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = empty(r.why, '⚠'); return; }
    const d = r.data; S.counts = d.counts || {}; S.me = d.me; D.drawNav();
    const c = S.counts, me = d.me || {}, rr = me.r || {};
    const hr = new Date().getHours();
    const hello = hr < 12 ? 'Good morning' : hr < 18 ? 'Good afternoon' : 'Good evening';
    const k = (n, label, ico, view, arg2, hot) => `<div class="kpi click ${n ? (hot ? 'hot' : '') : 'zero'}" data-go="${view}" data-arg='${arg2 ? JSON.stringify(arg2) : ''}'><span class="k-ico">${ico}</span><b>${n || 0}</b><span>${esc(label)}</span></div>`;
    const tiles = [k(c.myCases, 'My open cases', '⚖', 'cases', { mine: true }), k(c.today, 'Hearings today', '▦', 'calendar')];
    if (rr.warrants || rr.judge) tiles.push(k(c.warrants, 'Warrants to sign', '✎', 'warrants', null, true));
    if (rr.judge || rr.defender || rr.attorney) tiles.push(k(c.pleas, 'Plea deals to answer', '✍', 'cases', { mine: true }, true));
    if (rr.judge) tiles.push(k(c.motions, 'Motions to rule on', '📄', 'cases', { mine: true }, true), k(c.subpoenas, 'Subpoena requests', '✉', 'cases', { mine: true }));
    if (rr.clerk || rr.judge || rr.seal) tiles.push(k(c.petitions, 'Petitions waiting', '✎', 'clerk', null, true));
    if (rr.permits) tiles.push(k(c.permits, 'Firearm permits', '◎', 'permits', null, true));
    if (rr.court || rr.staff) tiles.push(k(c.openCases, 'Open cases', '⚖', 'cases'), k(c.unassigned, 'Without a judge', '⚠', 'cases', null, true));
    const quick = [];
    if (has('cases', 'judge', 'prosecutor')) quick.push('<button class="todo-chip accent" data-q="newcase">＋ New case</button>');
    if (has('clerk', 'cases', 'judge')) quick.push('<button class="todo-chip" data-q="hearing">▦ Schedule a hearing</button>');
    if (has('warrants')) quick.push('<button class="todo-chip" data-q="warrant">✎ Issue a warrant</button>');
    quick.push('<button class="todo-chip" data-q="person">☺ Look up a person</button>');
    if (has('clerk', 'judge')) quick.push('<button class="todo-chip" data-q="bill">$ Bill someone</button>');
    h.innerHTML = `<div class="hero"><div style="font-size:42px">⚖</div><div class="flex1"><h1>${hello}, ${esc(me.label || me.name || '')}</h1>
        <p>${esc(me.roleName || '')}${me.bar && me.bar.number ? ' · Bar ' + esc(me.bar.number) : ''}${d.dept ? ' · ' + esc(d.dept.name) : ''}${rr.leo && !rr.member ? ' · Police view (read-only)' : ''}</p></div>
        ${c.owed && (rr.court || rr.staff) ? `<div class="right"><div class="lbl">Owed to the court</div><div class="v-title">${money(c.owed)}</div></div>` : ''}</div>
      ${RO() ? '' : `<div class="todo">${quick.join('')}</div>`}
      <div class="kpis">${tiles.join('')}</div>
      <div class="cols2">
        <div class="card"><div class="card-head"><div class="card-title">Upcoming hearings</div><span class="lnk" data-go="calendar">Calendar →</span></div>
          ${(d.hearings || []).length ? d.hearings.map((x) => `<div class="li click" data-h="${x.id}"><div class="li-main"><b>${esc(x.title || labelOf(S.lists.hearingKinds, x.kind))}</b>
            <span class="hint">${dateTime(x.startsAt)} · ${esc(x.room)}${x.judge ? ' · ' + esc(x.judge) : ''}${x.number ? ' · ' + esc(x.number) : ''}</span></div>${pill(inTime(x.startsAt), x.startsAt - Date.now() / 1000 < 3600 ? 'warn' : '')}</div>`).join('') : empty('Nothing coming up', '▦')}</div>
        <div class="card"><div class="card-title">On my cases lately</div>
          ${(d.recent || []).length ? d.recent.map((l) => `<div class="li click" data-case="${l.caseId}"><div class="li-main"><b>${esc(l.detail || cap(l.what))}</b><span class="hint">${esc(l.number)} · ${esc(l.byLabel || '')} · ${ago(l.at)}</span></div></div>`).join('') : empty('Nothing new on your cases', '◌')}</div>
      </div>
      ${!d.judgeOnly && (rr.warrants || rr.judge) ? '<div class="help">Warrants: police supervisors may also sign requests in the MDT (Config.Warrants.judgeOnly = false). Requests still show here for a judge.</div>' : ''}`;
    $$('[data-go]', h).forEach((b) => b.onclick = () => { const a = b.dataset.arg ? JSON.parse(b.dataset.arg) : null; go(b.dataset.go, a, { root: true }); });
    $$('[data-h]', h).forEach((b) => b.onclick = () => openHearing(+b.dataset.h));
    const Q = { newcase: () => D.newCase(), hearing: () => hearingForm({}), warrant: () => issueWarrant(), person: () => go('people', null, { root: true }), bill: () => D.billForm && D.billForm() };
    $$('[data-q]', h).forEach((b) => b.onclick = () => Q[b.dataset.q]());
  };
  const RO = D.RO;

  // ---------------------------------------------------------------- hearings
  async function hearingForm(pre) {
    pre = pre || {};
    const kinds = S.lists.hearingKinds || [];
    const start = pre.startsAt || (() => { const d = new Date(Date.now() + 86400000); d.setHours(18, 0, 0, 0); return Math.floor(d / 1000); })();
    const judgeF = await D.memberField('judge', 'Judge', 'judge', pre.judgeCharId, pre.judge);
    judgeF.span2 = false;
    const stageToKind = { filed: 'arraignment', arraignment: 'pretrial', pretrial: 'trial', trial: 'sentencing', sentencing: 'sentencing' };
    let caseId = pre.caseId || null;
    const fields = [
      pre.caseId ? { k: 'cs', type: 'html', span2: true, html: `<div class="help">Case <b>${esc(pre.number || '#' + pre.caseId)}</b>: everyone on it gets a notice.</div>` }
        : { k: 'cs', type: 'html', span2: true, html: '<div class="field"><label>Case <span class="hint">· optional: a case number, or leave empty for a non-case hearing</span></label><div class="picker-wrap"><input type="text" data-cq placeholder="CR-2026-…" autocomplete="off"><div class="pop hidden" data-cpop></div></div><div class="chosen" data-cch></div></div>' },
      { k: 'kind', label: 'Kind', type: 'select', value: pre.kind || stageToKind[pre.stage] || 'arraignment', opts: kinds.map((x) => ({ v: x.key, l: x.label })) },
      { k: 'room', label: 'Room', type: 'select', value: pre.room || (S.lists.rooms || [])[0], opts: S.lists.rooms || [] },
      { k: 'startsAt', label: 'When (your time)', type: 'datetime', value: D.isoLocal(start), req: true },
      { k: 'minutes', label: 'Minutes', type: 'number', value: pre.minutes || 30, min: 5, maxv: 480 },
      judgeF,
      { k: 'title', label: 'Title', value: pre.title || '', placeholder: 'blank = kind and case number' }];
    let force = false;
    return form(pre.id ? 'Move the hearing' : 'Schedule a hearing', fields, { ico: '▦', size: 'wide', yes: pre.id ? 'Save' : 'Schedule',
      onReady: (card) => {
        const q = $('[data-cq]', card); if (!q) return;
        const pop = $('[data-cpop]', card), ch = $('[data-cch]', card); let t = null;
        q.addEventListener('input', () => { clearTimeout(t); const s = q.value.trim(); if (s.length < 2) { pop.classList.add('hidden'); return; }
          t = setTimeout(async () => { const r = await call('cases', { q: s, status: 'open' }); const rows = (r.ok && r.data.rows) || [];
            pop.innerHTML = rows.length ? rows.slice(0, 8).map((k) => `<div class="pop-row" data-id="${k.id}" data-no="${esc(k.number)}">${caseNo(k)} <span class="ell">${esc(k.title)}</span></div>`).join('') : '<div class="pop-empty">No open case</div>';
            pop.classList.remove('hidden');
            $$('.pop-row', pop).forEach((row) => row.onmousedown = (e) => { e.preventDefault(); caseId = +row.dataset.id; pop.classList.add('hidden'); q.value = ''; ch.innerHTML = `<span class="chip">${esc(row.dataset.no)}<button type="button">✕</button></span>`; $('button', ch).onclick = () => { caseId = null; ch.innerHTML = ''; }; });
          }, 250); });
        q.addEventListener('blur', () => setTimeout(() => pop.classList.add('hidden'), 150));
      },
      onSubmit: async (v) => {
        const d = { id: pre.id, caseId, kind: v.kind, room: v.room, startsAt: v.startsAt, minutes: v.minutes, title: v.title, judgeCharId: D.pickedId(v.judge) || null, force };
        let r = await call('hearingSave', d);
        if (!r.ok && /Clashes/.test(r.why || '')) {
          if (!(await confirmBox('Double-booked', r.why, 'Book it anyway'))) return 'Pick another time or room';
          force = true; d.force = true; r = await call('hearingSave', d);
        }
        const a = answer(r, pre.id ? 'Hearing moved' : 'Hearing scheduled');
        if (a === true) setTimeout(rerender, 60);
        return a;
      } });
  }
  D.hearingForm = hearingForm;

  const SPEAKERS = ['The Court', 'Prosecution', 'Defense', 'Defendant', 'Plaintiff', 'Witness', 'Clerk', 'Bailiff'];
  async function openHearing(id) {
    const r = await call('transcript', { id });
    if (!r.ok) { toast(r.why, 'err'); return; }
    const x = r.data;
    const runs = has('clerk', 'judge', 'cases') && (x.status === 'scheduled' || x.status === 'adjourned');
    const canWrite = has('clerk', 'judge');
    const line = (l) => `<div class="tr-l"><span class="who">${esc(l.speaker)}</span><span class="t">${esc(l.text)}</span><span class="at">${timeOnly(l.at)}</span></div>`;
    modal(`<div class="m-title"><span class="m-ico">▦</span>${esc(x.title || labelOf(S.lists.hearingKinds, x.kind))}</div>
      <div class="row gap-s">${pill(cap(x.status), x.status === 'scheduled' ? 'gold' : x.status === 'held' ? 'on' : 'off')} <span class="hint">${dateTime(x.startsAt)} · ${esc(x.room)}${x.judge ? ' · ' + esc(x.judge) : ''}</span>
        ${x.caseId ? `<span class="lnk" data-gocase="${x.caseId}">Open the case →</span>` : ''}</div>
      ${x.outcome ? `<div class="help mt">Outcome: ${esc(x.outcome)}</div>` : ''}
      ${runs ? `<div class="row mt"><button class="btn small ok" data-h="held">✓ Held</button><button class="btn small" data-h="adjourned">Adjourned</button><button class="btn small" data-h="noshow">No-show</button><button class="btn small danger" data-h="cancelled">Cancel</button>${x.status === 'scheduled' ? '<button class="btn small ghost" data-move>Move</button>' : ''}</div>` : ''}
      <div class="card-title mt">Transcript</div>
      <div class="tr-box" data-tr>${(x.lines || []).map(line).join('') || '<div class="hint" data-none style="padding:8px">No lines yet.</div>'}</div>
      ${canWrite ? `<div class="row mt"><select data-sp style="width:160px">${SPEAKERS.map((s) => `<option>${s}</option>`).join('')}<option value="__">Someone else…</option></select>
        <input type="text" data-other placeholder="Name" style="width:150px" class="hidden"><input type="text" data-text class="flex1" placeholder="What was said… (Enter adds the line)" maxlength="1000"><button class="btn gold" data-add>Add</button></div>` : ''}
      <div class="row end"><button class="btn" data-x>Close</button></div>`, (card, closeIt) => {
      const box = $('[data-tr]', card); box.scrollTop = box.scrollHeight;
      const g = $('[data-gocase]', card); if (g) g.onclick = () => { closeIt(); go('case', +g.dataset.gocase, { parent: 'cases' }); };
      const mv = $('[data-move]', card); if (mv) mv.onclick = () => { closeIt(); setTimeout(() => hearingForm({ id: x.id, caseId: x.caseId, kind: x.kind, room: x.room, startsAt: x.startsAt, title: x.title, judgeCharId: x.judgeCharId, judge: x.judge, number: x.title }), 180); };
      $$('[data-h]', card).forEach((b) => b.onclick = () => { closeIt(); const act = b.dataset.h;
        setTimeout(() => form(`${cap(act)}: ${x.title || 'hearing'}`, [{ k: 'outcome', label: act === 'held' ? 'Outcome / what was decided' : 'Reason', type: 'textarea', rows: 3, span2: true, max: 500 }],
          { yes: 'Save', danger: act === 'cancelled', onSubmit: async (v) => { const a = answer(await call('hearingAct', { id: x.id, act, outcome: v.outcome }), 'Hearing ' + act); if (a === true) setTimeout(rerender, 60); return a; } }), 180); });
      if (!canWrite) return;
      const sp = $('[data-sp]', card), other = $('[data-other]', card), text = $('[data-text]', card), add = $('[data-add]', card);
      sp.onchange = () => other.classList.toggle('hidden', sp.value !== '__');
      const send = () => busy(add, async () => {
        const t = text.value.trim(); if (!t) return;
        const speaker = sp.value === '__' ? other.value.trim() : sp.value;
        const rr = await call('transcriptAdd', { id: x.id, speaker, text: t });
        if (!said(rr)) return;
        const n = $('[data-none]', box); if (n) n.remove();
        box.insertAdjacentHTML('beforeend', line(rr.data)); box.scrollTop = box.scrollHeight;
        text.value = ''; text.focus();
      });
      add.onclick = send;
      text.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); send(); } });
    }, 'xwide');
  }
  D.openHearing = openHearing;

  // ---------------------------------------------------------------- calendar (a week)
  const C = { start: null, mine: false, room: '', judge: '' };
  const weekStart = (t) => { const d = new Date(t * 1000); const wd = (d.getDay() + 6) % 7; d.setDate(d.getDate() - wd); d.setHours(0, 0, 0, 0); return Math.floor(d / 1000); };
  views.calendar = async (h, arg, alive) => {
    if (!C.start) C.start = weekStart(Date.now() / 1000);
    const end = C.start + 7 * 86400;
    const r = await call('calendar', { from: C.start, to: end, mine: C.mine, room: C.room, judgeCharId: C.judge ? +C.judge : null });
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = empty(r.why, '⚠'); return; }
    const rows = r.data.rows || [];
    const days = [];
    for (let i = 0; i < 7; i++) { const d = new Date(C.start * 1000); d.setDate(d.getDate() + i); days.push(d); }
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const canAdd = has('clerk', 'cases', 'judge');
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Court calendar</div><div class="v-sub">${days[0].toLocaleDateString(undefined, { month: 'long', day: 'numeric' })} – ${days[6].toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric' })} · your local time</div></div>
        <div class="row"><button class="btn small" data-w="-1">←</button><button class="btn small" data-w="0">This week</button><button class="btn small" data-w="1">→</button>${canAdd ? '<button class="btn gold" data-new>＋ Schedule</button>' : ''}</div></div>
      <div class="filters"><label class="ck-item"><input type="checkbox" data-mine ${C.mine ? 'checked' : ''}> Mine only</label>
        <select data-room class="small-sel"><option value="">All rooms</option>${(r.data.rooms || []).map((x) => `<option ${C.room === x ? 'selected' : ''}>${esc(x)}</option>`).join('')}</select>
        <select data-judge class="small-sel"><option value="">All judges</option>${(r.data.judges || []).map((j) => `<option value="${j.charId}" ${+C.judge === j.charId ? 'selected' : ''}>${esc(j.name)}</option>`).join('')}</select>
        <span class="hint">${rows.length} hearing${rows.length === 1 ? '' : 's'} this week</span></div>
      <div class="cal">${days.map((d) => { const t0 = Math.floor(d / 1000), t1 = t0 + 86400; const evs = rows.filter((x) => x.startsAt >= t0 && x.startsAt < t1);
        return `<div class="cal-day ${+d === +today ? 'today' : ''}"><div class="cal-dh"><b>${d.getDate()}</b><span>${d.toLocaleDateString(undefined, { weekday: 'short' })}</span></div>
          ${evs.map((x) => `<div class="cal-ev ${esc(x.status)} ${x.kind === 'trial' ? 'trial' : ''}" data-h="${x.id}" title="${esc(x.caseTitle || '')}"><b>${timeOnly(x.startsAt)} · ${esc(x.title || labelOf(S.lists.hearingKinds, x.kind))}</b>${esc(x.room)}${x.judge ? ' · ' + esc(x.judge) : ''}${x.defendant ? '<br>' + esc(x.defendant) : ''}</div>`).join('')}
          ${canAdd ? `<button class="btn small ghost cal-add" data-add="${t0}">＋ Add</button>` : ''}</div>`; }).join('')}</div>`;
    $$('[data-w]', h).forEach((b) => b.onclick = () => { const w = +b.dataset.w; C.start = w === 0 ? weekStart(Date.now() / 1000) : weekStart(C.start + w * 7 * 86400 + 3600 * 12); rerender(); });
    $('[data-mine]', h).onchange = (e) => { C.mine = e.target.checked; rerender(); };
    $('[data-room]', h).onchange = (e) => { C.room = e.target.value; rerender(); };
    $('[data-judge]', h).onchange = (e) => { C.judge = e.target.value; rerender(); };
    $$('[data-h]', h).forEach((b) => b.onclick = () => openHearing(+b.dataset.h));
    $$('[data-add]', h).forEach((b) => b.onclick = () => { const d = new Date(+b.dataset.add * 1000); d.setHours(18, 0, 0, 0); hearingForm({ startsAt: Math.floor(d / 1000) }); });
    const nb = $('[data-new]', h); if (nb) nb.onclick = () => hearingForm({});
  };

  // ---------------------------------------------------------------- warrants
  const W = { status: null, kind: '' };
  const W_ST = { requested: 'warn', active: 'bad', denied: 'off', served: 'on', void: 'off', expired: 'off', closed: 'off' };
  views.warrants = async (h, arg, alive) => {
    if (!W.status) W.status = R().warrants || R().judge ? 'requested' : 'mine';
    const r = await call('warrants', { status: W.status, kind: W.kind });
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = empty(r.why, '⚠'); return; }
    const rows = r.data.rows || [];
    const sign = has('warrants');
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Warrants</div><div class="v-sub">${sign ? 'Police ask in the MDT; you sign or deny. Signed warrants go live in the MDT at once.' : 'Warrant requests and their answers.'}</div></div>
        ${sign ? '<button class="btn gold" data-new>✎ Issue a warrant</button>' : ''}</div>
      <div class="filters"><div class="seg">${[['requested', `Waiting${r.data.waiting ? ' (' + r.data.waiting + ')' : ''}`], ['active', 'Active'], ['decided', 'Decided'], ['mine', 'Mine'], ['all', 'All']].map(([v, l]) => `<button data-st="${v}" class="${W.status === v ? 'on' : ''}">${l}</button>`).join('')}</div>
        <div class="seg">${[['', 'Any kind'], ['arrest', 'Arrest'], ['search', 'Search']].map(([v, l]) => `<button data-k="${v}" class="${W.kind === v ? 'on' : ''}">${l}</button>`).join('')}</div></div>
      ${rows.length ? rows.map((w) => `<div class="card wq"><div class="w-kind ${w.kind === 'search' ? 'search' : ''}">${w.kind === 'search' ? '⌕' : '⛓'}</div>
        <div class="w-body"><div class="row gap-s"><b class="lnk" data-person="${w.charId}">${esc(w.name)}</b> ${pill(w.kind === 'search' ? 'Search warrant' : 'Arrest warrant', w.kind === 'search' ? 'accent' : '')} ${pill(w.expired && w.status === 'active' ? 'Expired' : cap(w.status), W_ST[w.status])} ${w.auto ? pill('Automatic', 'off') : ''}<span class="hint">#${w.id}</span></div>
          <div class="w-reason">${esc(w.reason)}</div>${w.scope ? `<div class="hint">May search: ${esc(w.scope)}</div>` : ''}
          <div class="hint">Asked by ${esc(w.requestedByName)}${w.dept ? ' (' + esc(w.dept) + ')' : ''} · ${ago(w.createdAt)}${w.caseNo ? ' · police case ' + esc(w.caseNo) : ''}${w.reportId ? ' · report #' + w.reportId : ''}${w.expiresAt ? ' · expires ' + date(w.expiresAt) : ''}${w.judgeName ? ' · ' + esc(w.judgeName) : ''}${w.judgeNote ? ': “' + esc(w.judgeNote) + '”' : ''}</div></div>
        <div class="w-acts">${w.status === 'requested' && sign ? `<button class="btn small gold" data-rev="${w.id}">Review</button>` : `<button class="btn small" data-rev="${w.id}">Details</button>`}
          ${w.status === 'active' && sign ? `<button class="btn small danger" data-recall="${w.id}">Recall</button>` : ''}</div></div>`).join('') : empty(W.status === 'requested' ? 'No warrant waits for a judge' : 'No warrants here', '✎')}`;
    $$('[data-st]', h).forEach((b) => b.onclick = () => { W.status = b.dataset.st; rerender(); });
    $$('[data-k]', h).forEach((b) => b.onclick = () => { W.kind = b.dataset.k; rerender(); });
    $$('[data-rev]', h).forEach((b) => b.onclick = () => review(+b.dataset.rev));
    $$('[data-recall]', h).forEach((b) => b.onclick = () => form('Recall the warrant', [{ k: 'note', label: 'Reason', type: 'textarea', rows: 2, span2: true, req: true, max: 300 }],
      { danger: true, yes: 'Recall', onSubmit: async (v) => { const a = answer(await call('warrantRecall', { id: +b.dataset.recall, note: v.note }), 'Warrant recalled'); if (a === true) setTimeout(rerender, 60); return a; } }));
    const nb = $('[data-new]', h); if (nb) nb.onclick = () => issueWarrant();
  };
  async function review(id) {
    const r = await call('warrant', { id });
    if (!r.ok) { toast(r.why, 'err'); return; }
    const w = r.data, rec = w.record || {};
    const sign = has('warrants') && w.status === 'requested';
    modal(`<div class="m-title"><span class="m-ico">${w.kind === 'search' ? '⌕' : '⛓'}</span>${w.kind === 'search' ? 'Search' : 'Arrest'} warrant #${w.id} · ${esc(w.name)}</div>
      <div class="cols2 mt"><div>
        <div class="lbl">Reason</div><div class="narr" style="white-space:pre-wrap">${esc(w.reason)}</div>
        ${w.scope ? `<div class="lbl mt">May search</div><div>${esc(w.scope)}</div>` : ''}
        <div class="hint mt">Asked by ${esc(w.requestedByName)}${w.dept ? ' (' + esc(w.dept) + ')' : ''} · ${dateTime(w.createdAt)}</div>
        ${w.report ? `<div class="card mt"><div class="card-title">MDT report #${w.report.id} · ${esc(cap(w.report.type))}</div><b>${esc(w.report.title || '')}</b><div class="narr mt" style="white-space:pre-wrap;max-height:200px;overflow:auto">${esc(w.report.body || '')}</div>
          ${(w.charges || []).length ? `<div class="mt">${w.charges.map((g) => `<div class="chg"><span class="code">${esc(g.code)}</span><span class="cat c-${esc(g.category)}">${esc(cap(g.category))}</span><div class="li-main"><b>${esc(g.title)}${g.count > 1 ? ' ×' + g.count : ''}</b></div></div>`).join('')}</div>` : ''}</div>` : '<div class="help mt">No MDT report is attached: judge it on the reason alone.</div>'}
      </div><div>
        <div class="card"><div class="card-title">Court record</div><dl class="kv"><dt>Convictions</dt><dd>${rec.convictions || 0} (${rec.felonyConvictions || 0} felony)</dd><dt>Owes the court</dt><dd>${money(rec.owed)}</dd>
          <dt>Probation</dt><dd>${rec.probation ? 'until ' + date(rec.probation) : 'No'}</dd><dt>Service left</dt><dd>${rec.service || 0} tasks</dd></dl></div>
          ${(rec.cases || []).length ? `<div class="mt">${rec.cases.map((k) => `<div class="li"><div class="li-main"><b>${esc(k.number)}</b><span class="hint">${esc(k.title)} · ${esc(k.stageLabel)}${k.bail ? ' · bail ' + esc(k.bail) : ''}</span></div></div>`).join('')}</div>` : ''}</div>
        ${(w.others || []).length ? `<div class="card mt"><div class="card-title">Other open warrants</div>${w.others.map((o) => `<div class="li"><div class="li-main"><b>#${o.id} ${esc(cap(o.kind))}</b><span class="hint">${esc(o.reason)}</span></div>${pill(cap(o.status), W_ST[o.status])}</div>`).join('')}</div>` : ''}
      </div></div>
      ${sign ? `<div class="grid mt"><div class="field"><label>Valid for (days) <span class="hint">· 0 = keep the officer's</span></label><input type="number" data-days min="0" max="90" value="0"></div>
        <div class="field"><label>Note <span class="hint">· needed to deny: the officer reads it</span></label><input type="text" data-note maxlength="300"></div></div>
        <div class="form-err" data-err></div>
        <div class="row end"><button class="btn ghost" data-x>Close</button>${R().deny ? '<button class="btn danger" data-d="deny">Deny</button>' : ''}<button class="btn gold" data-d="approve">✎ Sign the warrant</button></div>`
        : '<div class="row end"><button class="btn" data-x>Close</button></div>'}`, (card, closeIt) => {
      $$('[data-d]', card).forEach((b) => b.onclick = () => busy(b, async () => {
        const rr = await call('warrantDecide', { id: w.id, decision: b.dataset.d, note: $('[data-note]', card).value.trim(), days: +$('[data-days]', card).value || 0 });
        if (!rr.ok) { $('[data-err]', card).textContent = rr.why; return; }
        closeIt(); toast(b.dataset.d === 'approve' ? 'Signed: the warrant is live in the MDT' : 'Denied: the officer is told', 'ok'); setTimeout(rerender, 200);
      }));
    }, 'xwide');
  }
  function issueWarrant(pre) {
    pre = pre || {};
    return form('Issue a warrant', [
      { k: 'who', label: 'Person', type: 'person', req: true, span2: true, value: pre.person },
      { k: 'kind', label: 'Kind', type: 'choice', span2: true, value: 'arrest', opts: [{ v: 'arrest', l: 'Arrest warrant', d: 'Police may arrest them' }, { v: 'search', l: 'Search warrant', d: 'Police may search what you name' }],
        onChange: (v, card) => { $('#f-scope', card).closest('.field').style.display = v === 'search' ? '' : 'none'; } },
      { k: 'reason', label: 'Reason', type: 'textarea', rows: 3, span2: true, req: true, max: 500 },
      { k: 'scope', label: 'May search', span2: true, max: 300, placeholder: 'Their house at 12 Grove St and the black Sultan, plate 46ABC123' },
      { k: 'days', label: 'Valid for (days)', type: 'number', value: 7, min: 0, maxv: 90 }],
    { ico: '✎', size: 'wide', yes: 'Issue', onReady: (card) => { $('#f-scope', card).closest('.field').style.display = 'none'; },
      onSubmit: async (v) => { const r = await call('warrantIssue', { charId: D.pickedId(v.who), kind: v.kind, reason: v.reason, scope: v.scope, days: v.days, courtCaseId: pre.caseId });
        const a = answer(r, r.ok ? `Warrant #${r.data.id} is live in the MDT` : null); if (a === true) setTimeout(rerender, 60); return a; } });
  }
  D.issueWarrant = issueWarrant;
})();
