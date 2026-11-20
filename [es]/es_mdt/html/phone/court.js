// es_mdt 2.3.0: the court portal as a whip_phone app ("Court"). Registered by doj/client/phone.lua through
// exports.whip_phone:RegisterModule with ns 'es_doj:pub', so every request here is one of the portal's own
// SecureCallbacks (doj/server/civ.lua, doj/server/contests.lua): the same checks as /court, nothing new on the server.
// UI only, built from the phone's kit: every control is a data-act, so the controller reaches all of it
// (D-pad moves, A presses, B goes back, LB / RB switch tabs, X runs the screen's main action).
// No bail anywhere: bail bills, bail hearings and bail notices are left out, and a payment never sends `bond`.
(() => {
  const { kit: K, icons: I } = window.WhipPhone;
  const svg = (p, fill) => `<svg viewBox="0 0 24 24" ${fill ? 'fill="currentColor"' : 'fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"'}>${p}</svg>`;
  const IC = {
    app: svg('<path d="M12 2.8 13.6 4h5.1v1.8h-1.2l2.9 6.6c0 1.9-1.6 3.1-3.4 3.1s-3.4-1.2-3.4-3.1l2.9-6.6h-2.5v13.1h3.6V21H6.4v-2.1H10V5.8H7.5l2.9 6.6c0 1.9-1.6 3.1-3.4 3.1s-3.4-1.2-3.4-3.1l2.9-6.6H5.3V4h5.1zM17 7.6l-1.9 4.5h3.8zM7 7.6l-1.9 4.5h3.8z"/>', true),
    home: svg('<path d="M3.5 11 12 4l8.5 7"/><path d="M5.8 9.5V20h12.4V9.5"/><path d="M10 20v-5.5h4V20"/>'),
    cases: svg('<path d="M3.5 7.2c0-1 .8-1.8 1.8-1.8h4.1l2 2.2h7.3c1 0 1.8.8 1.8 1.8v8.8c0 1-.8 1.8-1.8 1.8H5.3c-1 0-1.8-.8-1.8-1.8z"/>'),
    pay: svg('<rect x="2.8" y="5.5" width="18.4" height="13" rx="2.4"/><path d="M2.8 10h18.4M6.5 15h3.5"/>'),
    bell: svg('<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.6 1.8H4.4z"/><path d="M10 20.5a2.2 2.2 0 0 0 4 0"/>'),
    more: svg('<circle cx="5.5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="18.5" cy="12" r="1.7"/>', true),
    ticket: svg('<path d="M4 5.5h16v4a2.5 2.5 0 0 0 0 5v4H4v-4a2.5 2.5 0 0 0 0-5z"/><path d="M9 9.5h6M9 14.5h4"/>'),
    car: svg('<path d="M4.5 16.5v-4l1.9-4.6c.3-.7.9-1.1 1.7-1.1h7.8c.8 0 1.4.4 1.7 1.1l1.9 4.6v4"/><path d="M3.5 16.5h17v2.3h-2.6v-2.3M6.1 16.5v2.3H3.5"/><circle cx="7.8" cy="13.6" r="1" fill="currentColor"/><circle cx="16.2" cy="13.6" r="1" fill="currentColor"/>'),
    pen: svg('<path d="M4 20h4L19.3 8.7a2.6 2.6 0 0 0-4-4L4 16z"/><path d="m13.5 6.5 4 4"/>'),
    brief: svg('<rect x="3" y="7.5" width="18" height="12" rx="2.2"/><path d="M9 7.5V5.6c0-.6.5-1.1 1.1-1.1h3.8c.6 0 1.1.5 1.1 1.1v1.9M3 12.5h18"/>'),
    search: svg('<circle cx="10.5" cy="10.5" r="6"/><path d="m15 15 5 5"/>'),
    scale: svg('<path d="M12 4v16M6 20h12M4.5 8h15"/><path d="m6.5 8-3 6.5a3 3 0 0 0 6 0zM17.5 8l-3 6.5a3 3 0 0 0 6 0z"/>'),
    clock: svg('<circle cx="12" cy="12" r="8.2"/><path d="M12 7.5V12l3 2"/>'),
    doc: svg('<path d="M6.5 3.5h7.5l4 4v13h-11.5z"/><path d="M13.5 3.5v4.5h4.5M9.5 12.5h5M9.5 16h5"/>'),
    user: svg('<circle cx="12" cy="8.5" r="3.8"/><path d="M4.8 20c.9-3.6 3.8-5.5 7.2-5.5s6.3 1.9 7.2 5.5"/>'),
    warn: svg('<path d="M12 4 2.8 19.5h18.4z"/><path d="M12 10v4.2M12 16.8v.1"/>'),
    broom: svg('<path d="M14.5 3.5 11 10"/><path d="M7.5 10.5h7l2 9.5H5z"/><path d="M9 14.5v5.5M12 14.5v5.5"/>'),
    mail: svg('<rect x="3" y="5.5" width="18" height="13" rx="2"/><path d="m3.5 6.5 8.5 6.5 8.5-6.5"/>'),
  };
  const TABS = [['home', 'Home', IC.home], ['cases', 'Cases', IC.cases], ['pay', 'Pay', IC.pay], ['notices', 'Notices', IC.bell], ['more', 'More', IC.more]];
  const PET = { name_change: 'Legal name change', business: 'Business license', expungement: 'Record expungement' };

  // ---------------------------------------------------------------- helpers
  const money = (n) => '$' + Math.floor(Math.abs(+n || 0)).toLocaleString('en-US');
  const cap = (s) => String(s || '').replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
  const nowS = () => Date.now() / 1000;
  const BAIL = /\bbail|\bbonds?\b/i;
  const noBail = (x) => x && x.kind !== 'bail' && !BAIL.test(String(x.title || '') + ' ' + String(x.body || '') + ' ' + String(x.reason || ''));
  const day = (t) => new Date(K.toMs(t)).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
  const when = (t) => (t ? `${day(t)} · ${K.fmtTime(t)}` : '');
  function inTime(t) {
    const s = t - nowS(), a = Math.abs(s), h = Math.round(a / 3600), d = Math.round(a / 86400), m = Math.max(1, Math.round(a / 60));
    const v = a < 3600 ? `${m} min` : a < 172800 ? `${h} h` : `${d} days`;
    return s >= 0 ? `in ${v}` : `${v} ago`;
  }
  const pill = (text, tone = '') => `<em class="ct-pill ${tone}">${K.esc(text)}</em>`;
  const area = ({ bind, value = '', placeholder = '', rows = 4, max = 1000 }) =>
    `<label class="row field-row ct-ta"><textarea data-bind="${bind}" rows="${rows}" maxlength="${max}" placeholder="${K.esc(placeholder)}" spellcheck="false">${K.esc(value)}</textarea></label>`;
  const blockBtn = (label, act, d = {}, kind = '') => `<div class="ct-go">${K.button({ label, act, d, kind, block: true })}</div>`;
  const busyBtn = (s, label, act, d = {}, kind = '') => blockBtn(s.busy ? 'Working…' : label, act, d, kind);
  const para = (t) => `<p class="ct-p">${t}</p>`;

  /** the portal's answer without anything about bail */
  function clean(h) {
    h = h || {};
    const f = h.fees || {};
    f.fees = (f.fees || []).filter((x) => x.kind !== 'bail');
    f.fines = f.fines || [];
    f.paid = (f.paid || []).filter((x) => x.kind !== 'bail' && x.method !== 'bond');
    h.fees = f;
    h.cases = h.cases || [];
    h.notices = (h.notices || []).filter(noBail);
    h.unread = h.notices.filter((n) => !n.readAt).length;
    h.lawyers = h.lawyers || []; h.petitions = h.petitions || []; h.businesses = h.businesses || []; h.subpoenas = h.subpoenas || [];
    h.tk = h.tk || {};
    return h;
  }
  const owed = (h) => h.fees.fees.reduce((a, f) => a + (+f.amount || 0), 0) + h.fees.fines.filter((f) => !f.contested).reduce((a, f) => a + (+f.amount || 0), 0);
  const offers = (h) => h.cases.filter((k) => k.status === 'open' && k.offers > 0).length;
  const billCount = (h) => h.fees.fees.length + h.fees.fines.filter((f) => !f.contested).length;

  async function ask(app, action, args, fail) {
    try { return await app.request(action, args || {}); }
    catch (e) { app.toast((e && e.reason) || fail || 'The court is not answering'); return null; }
  }
  async function loadHome(app) {
    const s = app.state;
    try { s.h = clean(await app.request('home', {})); s.err = null; }
    catch (e) { s.err = (e && e.reason) || 'The court is not answering'; }
    s.loaded = true;
  }
  async function loadCase(app, id) {
    const k = await ask(app, 'case', { id }, 'Could not open the case');
    if (k) {
      k.hearings = (k.hearings || []).filter((x) => x.kind !== 'bail' && !BAIL.test(x.title || ''));
      k.filings = (k.filings || []).filter((x) => x.kind !== 'bail' && !BAIL.test(x.title || ''));
      app.state.cases[id] = k;
    }
  }
  const cur = (s) => s.stack[s.stack.length - 1] || null;
  function push(app, p) { const s = app.state; s.sheet = null; s.stack.push(p); return enter(app, p); }
  function enter(app, p) {
    const s = app.state;
    switch (p.p) {
      case 'case': return loadCase(app, p.id);
      case 'contest': s.f = { reason: '' }; // falls through
      case 'tickets': case 'ticket': return ask(app, 'tickets').then((r) => { if (r) s.tickets = r; });
      case 'impounds': return ask(app, 'impounds').then((r) => { if (r) s.impounds = r.rows || []; });
      case 'lawyers': return ask(app, 'lawyers').then((r) => { if (r) s.lawyers = r; });
      case 'petition': s.f = { firstName: '', lastName: '', name: '', kind: '', address: '', reason: '', reports: [], cases: [] };
        return p.kind === 'expungement' ? ask(app, 'myRecords').then((r) => { s.myRecords = r || { reports: [], cases: [] }; }) : null;
      case 'civil': s.f = { title: '', summary: '' }; s.pick = null; s.q = ''; s.people = []; return null;
      case 'payfor': s.pick = null; s.q = ''; s.people = []; s.other = null; return null;
      case 'appeal': s.f = { reason: '' }; return null;
      case 'records': s.rq = s.rq || ''; return null;
      case 'hire': s.f = { message: '' }; return null;
      default: return null;
    }
  }
  let searchT = null;
  function searchSoon(app, which) {
    clearTimeout(searchT);
    searchT = setTimeout(async () => {
      const s = app.state;
      if (which === 'people') {
        if (s.q.trim().length < 3) { s.people = []; return app.render(); }
        s.people = (await ask(app, 'people', { q: s.q.trim() })) || [];
      } else {
        if (s.rq.trim().length < 3) { s.records = null; return app.render(); }
        s.records = await ask(app, 'records', { q: s.rq.trim() });
      }
      app.render();
    }, 320);
  }

  // ---------------------------------------------------------------- tabs
  function hero(h) {
    const o = owed(h), open = h.cases.filter((k) => k.status === 'open');
    const nextH = open.filter((k) => k.next).sort((a, b) => a.next - b.next)[0];
    return `<div class="ct-hero"><div class="ct-h-top"><span class="ct-seal">${IC.scale}</span><div><b>${K.esc(h.me ? h.me.name : '')}</b><span>Superior Court of San Andreas</span></div></div>
      <div class="ct-stats"><div><i>Owed</i><b class="${o ? 'warn' : ''}">${money(o)}</b></div><div><i>Open cases</i><b>${open.length}</b></div>
      <div><i>Next hearing</i><b class="sm">${nextH ? K.esc(inTime(nextH.next)) : 'None'}</b></div></div></div>`;
  }
  function homeTab(app) {
    const s = app.state, h = s.h;
    const alerts = [];
    h.cases.filter((k) => k.status === 'open' && k.offers > 0).forEach((k) => alerts.push(K.row({ icon: IC.pen, tone: 'ct-warn', label: `Plea deal waiting · ${k.number}`, sub: 'Read it, then accept or reject it', act: 'openCase', d: { id: k.id }, hint: 'Open' })));
    const o = owed(h);
    if (o) {
      const late = h.fees.fees.some((f) => f.dueAt && f.dueAt < nowS()) || h.fees.fines.some((f) => !f.contested && f.dueAt && f.dueAt < nowS());
      alerts.push(K.row({ icon: IC.pay, tone: late ? 'ct-bad' : 'ct-warn', label: `You owe ${money(o)}`, sub: late ? 'Something is overdue: an overdue court fine becomes a warrant' : 'Pay from your bank or in cash', act: 'goTab', d: { tab: 'pay' }, hint: 'Pay' }));
    }
    h.subpoenas.forEach((x) => alerts.push(K.row({ icon: IC.mail, tone: 'ct-bad', label: `Subpoena · ${x.number}`, sub: (x.kind === 'documents' ? 'Produce documents' : 'Appear in court') + (x.startsAt ? ' · ' + when(x.startsAt) + (x.room ? ' · ' + x.room : '') : ''), act: 'goTab', d: { tab: 'cases' }, hint: 'Cases' })));
    if (h.service) alerts.push(K.row({ icon: IC.broom, tone: 'ct-warn', label: `${h.service} community service task${h.service === 1 ? '' : 's'} left`, sub: 'Your spot is marked on the map' }));
    if (h.tk.impounded) alerts.push(K.row({ icon: IC.car, tone: 'ct-bad', label: `${h.tk.impounded} vehicle${h.tk.impounded === 1 ? '' : 's'} impounded`, sub: 'See the cost and get it back', act: 'page', d: { p: 'impounds' }, hint: 'Open' }));
    h.cases.filter((k) => k.status === 'open' && k.next).sort((a, b) => a.next - b.next).slice(0, 2)
      .forEach((k) => alerts.push(K.row({ icon: IC.clock, label: `Court ${inTime(k.next)} · ${k.number}`, sub: `${when(k.next)} · ${h.courthouse || 'Courthouse'}`, act: 'openCase', d: { id: k.id }, hint: 'Open' })));
    const quick = [
      K.row({ icon: IC.ticket, label: 'My tickets', sub: h.tk.unpaid ? `${h.tk.unpaid} unpaid${h.tk.contested ? ` · ${h.tk.contested} contested` : ''}` : 'Police tickets, contest one', act: 'page', d: { p: 'tickets' } }),
      K.row({ icon: IC.doc, label: 'Requests', sub: 'Name change, business license, expungement', act: 'page', d: { p: 'requests' } }),
      K.row({ icon: IC.brief, label: 'Lawyers', sub: h.lawyers.length ? `Your lawyer: ${h.lawyers[0].name || ''}` : 'Hire one or ask for a public defender', act: 'page', d: { p: 'lawyers' } }),
    ];
    const sum = h.summary && (h.summary.convictions || h.summary.probation)
      ? `<div class="list-f">Your record: ${h.summary.convictions} conviction${h.summary.convictions === 1 ? '' : 's'}${h.summary.probation ? ' · on probation until ' + K.esc(day(h.summary.probation)) : ''}. An expungement request can clear old records.</div>` : '';
    return hero(h) + (alerts.length ? K.list(alerts, { header: 'Needs you' }) : K.list([K.row({ icon: I.check, tone: 'ct-ok', label: 'All clear', sub: 'Nothing needs you right now' })], { header: 'Needs you' }))
      + K.list(quick, { header: 'Quick' }) + sum;
  }
  function casesTab(app) {
    const h = app.state.h;
    if (!h.cases.length) return K.empty({ icon: IC.cases, title: 'No cases', text: 'Cases you are a party to show here.' });
    const row = (k) => K.row({ icon: k.kind === 'civil' ? IC.scale : IC.cases, label: `${k.number} · ${k.title || cap(k.kind)}`,
      sub: `${cap(k.role)} · ${k.stageLabel}${k.next && k.status === 'open' ? ' · court ' + inTime(k.next) : ''}`,
      value: k.offers > 0 && k.status === 'open' ? 'Plea deal' : k.status === 'open' ? 'Open' : k.verdict ? cap(k.verdict) : 'Closed',
      tone: k.offers > 0 && k.status === 'open' ? 'ct-warn' : '', act: 'openCase', d: { id: k.id }, hint: 'Open' });
    const open = app.state.h.cases.filter((k) => k.status === 'open'), done = app.state.h.cases.filter((k) => k.status !== 'open');
    return (open.length ? K.list(open.map(row), { header: 'Open' }) : '') + (done.length ? K.list(done.map(row), { header: 'Closed' }) : '')
      + K.list([K.row({ icon: IC.scale, label: 'Sue someone', sub: 'File a civil lawsuit', act: 'page', d: { p: 'civil' } })]);
  }
  function billRows(b, forName) {
    const fees = b.fees.map((f) => K.row({ icon: IC.scale, label: `${f.label || cap(f.kind)}${f.number ? ' · ' + f.number : ''}`,
      sub: [f.reason, f.dueAt ? (f.dueAt < nowS() ? 'Overdue · ' : 'Due ') + day(f.dueAt) : '', f.test ? 'Test' : ''].filter(Boolean).join(' · '),
      value: money(f.amount), tone: f.dueAt && f.dueAt < nowS() ? 'ct-bad' : '', act: 'askPay', d: { kind: 'fee', id: f.id, who: forName || null }, hint: 'Pay' }));
    const fines = b.fines.map((f) => K.row({ icon: f.ticketId ? IC.ticket : f.kind === 'impound' ? IC.car : IC.warn,
      label: f.ticketId ? (f.reason || 'Police ticket') : `Police fine #${f.id}`,
      sub: [f.dept, f.ticketId ? '' : f.reason, f.contested ? 'Contested: paused until a judge rules' : f.dueAt ? (f.dueAt < nowS() ? 'Overdue · ' : 'Due ') + day(f.dueAt) : ''].filter(Boolean).join(' · '),
      value: money(f.amount), tone: f.contested ? 'ct-mute' : f.dueAt && f.dueAt < nowS() ? 'ct-bad' : '',
      act: f.contested ? '' : 'askPay', d: { kind: 'fine', id: f.id, who: forName || null }, hint: 'Pay' }));
    return fees.concat(fines);
  }
  function payTab(app) {
    const h = app.state.h, rows = billRows(h.fees);
    const o = owed(h);
    return `<div class="ct-total"><i>Total owed</i><b>${money(o)}</b><span>${o ? 'Pick a bill to pay it' : 'You owe the court nothing'}</span></div>`
      + (rows.length ? K.list(rows, { header: 'Unpaid' }) : '')
      + K.list([K.row({ icon: I.person, label: 'Pay for someone else', sub: 'A friend’s fine or court fee', act: 'page', d: { p: 'payfor' } }),
        K.row({ icon: IC.car, label: 'Impounded vehicles', act: 'page', d: { p: 'impounds' } })])
      + (h.fees.paid.length ? K.list(h.fees.paid.map((f) => K.row({ label: f.label || cap(f.kind), sub: `${cap(f.status)}${f.method ? ' · ' + cap(f.method) : ''}${f.paidAt ? ' · ' + K.fmtWhen(f.paidAt) : ''}`, value: money(f.amount) })), { header: 'Paid' }) : '');
  }
  function noticesTab(app) {
    const h = app.state.h;
    if (!h.notices.length) return K.empty({ icon: IC.mail, title: 'No notices', text: 'Letters from the court about your cases, bills and requests.' });
    return K.list(h.notices.map((n) => K.row({ icon: n.readAt ? IC.mail : `<span class="ct-dot"></span>`, label: n.title, sub: `${K.fmtWhen(n.at)}${n.test ? ' · Test' : ''}${n.body ? ' · ' + n.body : ''}`,
      tone: n.readAt ? 'ct-read' : 'ct-unread', act: 'openNotice', d: { id: n.id }, hint: 'Read' })), { header: h.unread ? `${h.unread} unread` : 'All read' });
  }
  function moreTab(app) {
    const h = app.state.h;
    return K.list([
      K.row({ icon: IC.ticket, label: 'My tickets', sub: 'See them, contest an unsigned one', act: 'page', d: { p: 'tickets' } }),
      K.row({ icon: IC.car, label: 'Impounded vehicles', sub: h.tk.impounded ? `${h.tk.impounded} held` : 'None held', act: 'page', d: { p: 'impounds' } }),
      K.row({ icon: IC.doc, label: 'Requests', sub: h.petitions.length ? `${h.petitions.length} filed` : 'Name change, business, expungement', act: 'page', d: { p: 'requests' } }),
      K.row({ icon: IC.brief, label: 'Lawyers', sub: h.lawyers.length ? `${h.lawyers.length} representing you` : 'Hire a licensed attorney', act: 'page', d: { p: 'lawyers' } }),
      K.row({ icon: IC.scale, label: 'Sue someone', sub: 'File a civil lawsuit', act: 'page', d: { p: 'civil' } }),
      K.row({ icon: IC.search, label: 'Public records', sub: 'Cases, businesses and attorneys', act: 'page', d: { p: 'records' } }),
    ]) + (h.businesses.length ? K.list(h.businesses.map((b) => K.row({ icon: IC.brief, label: b.name, sub: `${b.licenseNo || ''}${b.kind ? ' · ' + b.kind : ''}${b.expiresAt ? ' · expires ' + day(b.expiresAt) : ''}`, value: cap(b.status) })), { header: 'Your business licenses' }) : '');
  }

  // ---------------------------------------------------------------- pages
  function casePage(app, id) {
    const s = app.state, k = s.cases[id];
    if (!k) return K.empty({ title: 'Loading…' });
    const open = k.status === 'open', def = k.role === 'defendant';
    let out = `<div class="ct-case"><span class="ct-no">${K.esc(k.number)}</span><b>${K.esc(k.title || cap(k.kind))}</b>
      <div class="ct-pills">${pill(k.stageLabel, open ? 'on' : '')}${pill(cap(k.role))}${k.verdict ? pill(cap(k.verdict), k.verdict === 'guilty' ? 'bad' : 'on') : ''}${k.test ? pill('Test', 'warn') : ''}</div></div>`;
    const people = [K.row({ icon: IC.scale, label: 'Judge', value: k.judge || 'Not assigned yet' }),
      K.row({ icon: I.person, label: k.kind === 'civil' ? 'Plaintiff' : 'Prosecutor', value: (k.kind === 'civil' ? k.plaintiff : k.prosecutor) || '—' }),
      K.row({ icon: IC.user, label: 'Defendant', value: k.defendant || '—' }),
      K.row({ icon: IC.brief, label: 'Defense', value: k.defense || (k.defenseKind === 'public' ? 'Public defender asked for' : 'None') })];
    if (def && open && !k.defenseCharId && k.defenseKind !== 'public') people.push(K.row({ icon: I.plus, label: 'Ask for a public defender', sub: 'Free: the DOJ’s defenders are told', act: 'askPd', d: { id: k.id }, hint: 'Ask' }));
    out += K.list(people, { header: 'People' });
    const offered = (k.pleas || []).filter((p) => p.status === 'offered');
    offered.forEach((p) => {
      const terms = [p.fine ? money(p.fine) + ' fine' : '', p.months ? p.months + ' months' : '', p.service ? p.service + ' service tasks' : '', p.probationDays ? p.probationDays + ' days probation' : ''].filter(Boolean).join(' · ');
      out += `<div class="list-h">Plea deal from ${K.esc(p.offeredByLabel || 'the prosecution')}</div><div class="ct-card ct-plea"><p>${K.esc(p.terms || 'Plead guilty in exchange for these terms.')}</p>${terms ? `<b>${K.esc(terms)}</b>` : ''}
        <div class="ct-btns">${K.button({ label: 'Reject', act: 'askPlea', d: { id: p.id, a: 'reject' }, kind: 'gray', hint: 'Reject' })}${K.button({ label: 'Accept', act: 'askPlea', d: { id: p.id, a: 'accept' }, hint: 'Accept' })}</div></div>`;
    });
    if (k.hearings.length) out += K.list(k.hearings.map((x) => K.row({ icon: IC.clock, label: x.title || cap(x.kind), sub: `${when(x.startsAt)}${x.room ? ' · ' + x.room : ''}${x.outcome ? ' · ' + x.outcome : ''}`,
      value: x.status === 'scheduled' && x.startsAt > nowS() - 3600 ? inTime(x.startsAt) : cap(x.status), tone: x.status === 'scheduled' ? '' : 'ct-mute' })), { header: 'Hearings' });
    if ((k.charges || []).length) out += K.list(k.charges.map((c) => K.row({ label: `${c.code ? c.code + ' ' : ''}${c.title}${c.count > 1 ? ' ×' + c.count : ''}`,
      sub: [cap(c.category), c.plea ? 'Plea: ' + cap(c.plea) : '', c.disposition ? cap(c.disposition) : ''].filter(Boolean).join(' · ') })), { header: 'Charges' });
    if (k.filings.length) out += K.list(k.filings.map((f) => K.row({ icon: IC.doc, label: f.title || cap(f.kind), sub: `${cap(f.kind)}${f.byLabel ? ' · ' + f.byLabel : ''} · ${K.fmtWhen(f.createdAt)}${f.hasImage ? ' · picture' : ''}`,
      act: 'openFiling', d: { id: f.id, c: k.id }, hint: 'Read' })), { header: 'Filings' });
    if ((k.sentences || []).length) out += K.list(k.sentences.map((x) => K.row({ icon: IC.scale, label: [x.fine ? money(x.fine) + ' fine' : '', x.months ? x.months + ' months' : '', x.service ? x.service + ' service tasks' : '', x.probationDays ? x.probationDays + ' days probation' : '', x.restitution ? money(x.restitution) + ' restitution' : ''].filter(Boolean).join(' · ') || 'Sentence',
      sub: `${cap(x.source)} · ${cap(x.status)}${x.notes ? ' · ' + x.notes : ''}` })), { header: 'Sentence' });
    if (k.summary) out += `<div class="list-h">Summary</div><div class="ct-card"><p>${K.esc(k.summary)}</p></div>`;
    if (k.canAppeal) out += K.list([K.row({ icon: IC.pen, label: 'Appeal this case', sub: 'Ask a higher court to look again', act: 'page', d: { p: 'appeal', id: k.id } })]);
    return K.scroll(out);
  }
  function filingSheet(app) {
    const s = app.state, sh = s.sheet, k = s.cases[sh.c], f = k && k.filings.find((x) => x.id === sh.id);
    if (!f) return '';
    return K.sheet({ title: f.title || cap(f.kind), close: 'closeSheet', body: `<div class="ct-sheet-scroll">${f.body ? `<p class="ct-p">${K.esc(f.body)}</p>` : ''}${sh.img ? `<img class="ct-img" src="${K.esc(sh.img)}" alt="">` : f.hasImage ? para('Loading the picture…') : ''}
      ${f.ruling ? para('Ruling: ' + K.esc(f.ruling)) : ''}</div>${K.button({ label: 'Close', act: 'closeSheet', kind: 'gray', block: true })}` });
  }
  function ticketsPage(app) {
    const s = app.state, X = s.tickets;
    if (!X) return K.empty({ title: 'Loading…' });
    if (!X.rows.length) return K.empty({ icon: IC.ticket, title: 'No tickets', text: 'Police tickets written to you or your vehicles show here.' });
    const st = (t) => t.contest ? (t.contest.status === 'open' ? 'Contested' : 'Ruled: ' + cap(t.contest.ruling)) : t.kind === 'warning' ? 'Warning' : t.fineStatus === 'paid' ? 'Paid' : t.status === 'void' ? 'Void' : 'Unpaid';
    return K.scroll(K.list(X.rows.map((t) => K.row({ icon: IC.ticket, label: `${t.number} · ${(t.charges || []).map((c) => c.title).join(', ') || t.kindLabel}`,
      sub: `${t.kindLabel}${t.dept ? ' · ' + t.dept : ''} · ${K.fmtWhen(t.at)}${t.plate ? ' · ' + t.plate : ''}${t.sign === 'signed' ? ' · signed' : ''}`,
      value: t.kind === 'warning' ? st(t) : `${money(t.total)}`, tone: t.contestable ? 'ct-warn' : '', act: 'openTicket', d: { id: t.id }, hint: 'Open' })))
      + (X.contests ? `<div class="list-f">You can contest a ticket you did not sign. The payment pauses while a judge decides; no ruling in ${X.lapseDays} days and it is dismissed.</div>` : ''));
  }
  function ticketPage(app, id) {
    const s = app.state, t = s.tickets && s.tickets.rows.find((x) => x.id === id);
    if (!t) return K.empty({ title: 'Loading…' });
    const rows = [K.row({ label: 'Ticket', value: t.number }), K.row({ label: 'Kind', value: t.kindLabel }), K.row({ label: 'Fine', value: t.kind === 'warning' ? '—' : money(t.total) }),
      K.row({ label: 'Signed', value: t.sign === 'signed' ? 'Yes' : 'No' }), K.row({ label: 'Department', value: t.dept || '—' }), K.row({ label: 'Written', value: when(t.at) })];
    if (t.plate) rows.push(K.row({ label: 'Plate', value: t.plate }));
    if (t.dueAt && t.fineStatus === 'unpaid') rows.push(K.row({ label: 'Due', value: day(t.dueAt) }));
    let out = K.list(rows) + K.list((t.charges || []).map((c) => K.row({ label: `${c.code ? c.code + ' ' : ''}${c.title}${(c.count || 1) > 1 ? ' ×' + c.count : ''}`, value: c.fine ? money(c.fine) : null })), { header: 'Charges' });
    if (t.contest) out += `<div class="list-h">Your contest · ${t.contest.status === 'open' ? 'waiting for a judge' : 'ruled: ' + K.esc(cap(t.contest.ruling))}</div><div class="ct-card"><p>${K.esc(t.contest.reason || '')}</p>${t.contest.rulingNote ? `<b>${K.esc(t.contest.rulingNote)}</b>` : ''}</div>`;
    if (t.contestable) out += blockBtn('Contest this ticket', 'page', { p: 'contest', id: t.id });
    return K.scroll(out);
  }
  function contestPage(app, id) {
    const s = app.state, t = s.tickets && s.tickets.rows.find((x) => x.id === id);
    if (!t) return K.empty({ title: 'Loading…' });
    return K.scroll(`<div class="ct-card"><b>${K.esc(t.number)} · ${money(t.total)}</b><p>${K.esc((t.charges || []).map((c) => c.title).join(', '))}</p></div>`
      + `<div class="list-h">Why is this ticket wrong?</div>` + K.list([area({ bind: 'reason', value: s.f.reason || '', placeholder: 'Tell the judge what happened. The officer is asked for a statement too.', rows: 6 })])
      + `<div class="list-f">The payment is paused until a judge rules. Dismissed: you owe nothing. Reduced or upheld: you get the time that was left to pay.</div>` + busyBtn(s, 'File the contest', 'contest', { id: t.id }));
  }
  function impoundsPage(app) {
    const s = app.state, rows = s.impounds;
    if (!rows) return K.empty({ title: 'Loading…' });
    if (!rows.length) return K.empty({ icon: IC.car, title: 'Nothing impounded', text: 'None of your vehicles is at the lot.' });
    return K.scroll(rows.map((x) => {
      const live = x.status === 'held' || x.status === 'pending';
      const head = K.row({ icon: IC.car, label: `${x.vehicleLabel || 'Vehicle'} · ${x.plate || '?'}`, sub: `${x.reason || ''}${x.dept ? ' · ' + x.dept : ''} · ${K.fmtWhen(x.at)}`,
        value: x.status === 'pending' ? 'Marked' : x.status === 'held' ? 'At ' + (x.lotLabel || 'the lot') : x.status === 'cancelled' ? 'Called off' : 'Released' });
      if (!live) return K.list([head]);
      const o = x.owe || {};
      const r = [head, K.row({ label: 'Impound fee', value: money(o.fee) }), K.row({ label: `Storage · ${o.days || 0} day${o.days === 1 ? '' : 's'}`, value: money(o.storage) }), K.row({ label: 'To pay now', value: money(o.total), tone: 'ct-strong' })];
      if (x.status === 'pending') r.push(K.row({ icon: IC.clock, label: 'Marked for impound', sub: 'It goes to the lot the next time it is stored' }));
      else if (x.held) r.push(K.row({ icon: IC.warn, tone: 'ct-bad', label: 'Police hold' + (x.holdUntilTs ? ' until ' + when(x.holdUntilTs) : ''), sub: x.holdUntilTs ? 'You can pay and get it back after that' : 'Until an officer releases it' }));
      else r.push(K.row({ icon: IC.pay, label: `Pay ${money(o.total)} and release`, act: 'askImpound', d: { id: x.id }, hint: 'Pay', tone: 'ct-accent' }));
      return K.list(r);
    }).join(''));
  }
  function requestsPage(app) {
    const h = app.state.h, fee = (h.fees && h.fees.petitionFees) || {};
    const f = (n) => (n ? money(n) + ' filing fee' : 'No fee');
    const mine = h.petitions.map((p) => K.row({ icon: IC.doc, label: p.label || PET[p.kind] || cap(p.kind), sub: `Filed ${K.fmtWhen(p.createdAt)}${p.fee && !p.paid ? ' · fee unpaid' : ''}${p.decisionNote ? ' · ' + p.decisionNote : ''}`,
      value: cap(p.status), tone: p.status === 'approved' ? 'ct-ok' : p.status === 'denied' ? 'ct-bad' : '' }));
    return K.scroll(K.list([
      K.row({ icon: IC.user, label: 'Legal name change', sub: f(fee.name_change), act: 'page', d: { p: 'petition', kind: 'name_change' } }),
      K.row({ icon: IC.brief, label: 'Business license', sub: f(fee.business), act: 'page', d: { p: 'petition', kind: 'business' } }),
      K.row({ icon: IC.doc, label: 'Record expungement', sub: f(fee.expungement), act: 'page', d: { p: 'petition', kind: 'expungement' } }),
      K.row({ icon: IC.scale, label: 'Civil lawsuit', sub: f(fee.filing), act: 'page', d: { p: 'civil' } }),
    ], { header: 'New request', footer: 'A judge or the clerk decides. You get a notice either way.' }) + (mine.length ? K.list(mine, { header: 'Your requests' }) : ''));
  }
  function petitionPage(app, kind) {
    const s = app.state, f = s.f;
    let body = '';
    if (kind === 'name_change') body = K.list([K.field({ label: 'First name', bind: 'firstName', value: f.firstName, placeholder: 'New first name' }), K.field({ label: 'Last name', bind: 'lastName', value: f.lastName, placeholder: 'New last name' })], { header: 'Your new name' });
    if (kind === 'business') body = K.list([K.field({ label: 'Name', bind: 'bizName', value: f.name, placeholder: 'Business name' }), K.field({ label: 'Kind', bind: 'bizKind', value: f.kind, placeholder: 'Restaurant, garage…' }), K.field({ label: 'Address', bind: 'bizAddr', value: f.address, placeholder: 'Where it is' })], { header: 'The business' });
    if (kind === 'expungement') {
      const R = s.myRecords;
      if (!R) body = K.empty({ title: 'Loading your records…' });
      else {
        const reps = R.reports.map((r) => K.row({ label: r.title || cap(r.type), sub: `${r.charges || 'Report'} · ${K.fmtWhen(r.createdAt)}${r.sealed ? ' · sealed' : ''}`, toggle: f.reports.includes(r.id), act: 'pickRec', d: { t: 'reports', id: r.id }, hint: 'Pick' }));
        const cs = R.cases.map((k) => K.row({ label: `${k.number} · ${k.title}`, sub: `${cap(k.verdict || 'closed')}${k.closedAt ? ' · ' + K.fmtWhen(k.closedAt) : ''}`, toggle: f.cases.includes(k.id), act: 'pickRec', d: { t: 'cases', id: k.id }, hint: 'Pick' }));
        body = (reps.length ? K.list(reps, { header: 'Police reports' }) : '') + (cs.length ? K.list(cs, { header: 'Closed cases' }) : '') + (!reps.length && !cs.length ? K.empty({ title: 'Nothing to clear', text: 'You have no records that can be expunged.' }) : '');
      }
    }
    const fee = ((s.h.fees || {}).petitionFees || {})[kind];
    return K.scroll(body + `<div class="list-h">${kind === 'business' ? 'Anything the court should know' : 'Why'}</div>` + K.list([area({ bind: 'reason', value: f.reason, placeholder: kind === 'expungement' ? 'Why should the court clear them?' : 'Tell the court why', rows: 4 })])
      + `<div class="list-f">${fee ? `Filing fee ${money(fee)}: it is added to your bills under Pay.` : 'No filing fee.'}</div>` + busyBtn(s, 'File the request', 'petition', { kind }));
  }
  function personPicker(app, label) {
    const s = app.state;
    if (s.pick) return K.list([K.row({ av: K.avatar({ name: s.pick.name, size: 34 }), label: s.pick.name, sub: label, value: 'Change', act: 'unpick', hint: 'Change' })], { header: 'Person' });
    const rows = s.people.map((p) => K.row({ av: K.avatar({ name: p.name, size: 34 }), label: p.name, act: 'pickPerson', d: { id: p.charId, name: p.name }, hint: 'Pick' }));
    return `<div class="list-h">Person</div>` + K.search({ bind: 'q', value: s.q, placeholder: 'Their name (3 letters or more)' })
      + (rows.length ? K.list(rows) : s.q.trim().length >= 3 ? `<div class="list-f">Nobody by that name.</div>` : '');
  }
  function civilPage(app) {
    const s = app.state, fee = ((s.h.fees || {}).petitionFees || {}).filing;
    return K.scroll(personPicker(app, 'You are suing them') + K.list([K.field({ label: 'Title', bind: 'title', value: s.f.title, placeholder: 'e.g. Unpaid car repair' })], { header: 'The case' })
      + `<div class="list-h">What happened and what you ask for</div>` + K.list([area({ bind: 'summary', value: s.f.summary, placeholder: 'At least a few sentences', rows: 6, max: 4000 })])
      + `<div class="list-f">${fee ? `Filing fee ${money(fee)}.` : 'Filing is free.'} A judge is assigned and both sides are told.</div>` + busyBtn(s, 'File the lawsuit', 'civil'));
  }
  function payForPage(app) {
    const s = app.state;
    let out = personPicker(app, 'Paying for them');
    if (s.pick) {
      if (!s.other) out += K.empty({ title: 'Loading…' });
      else {
        const rows = billRows(s.other, s.other.name);
        out += rows.length ? K.list(rows, { header: `What ${s.other.name || 'they'} owe${s.other.name ? 's' : ''}` }) : K.empty({ icon: I.check, title: 'They owe nothing' });
      }
    }
    return K.scroll(out);
  }
  function appealPage(app, id) {
    const s = app.state, k = s.cases[id];
    return K.scroll(`<div class="ct-card"><b>${K.esc(k ? k.number : '')}</b><p>${K.esc(k ? k.title : '')}</p></div><div class="list-h">Grounds for the appeal</div>`
      + K.list([area({ bind: 'reason', value: s.f.reason, placeholder: 'What went wrong in the case? (a few sentences)', rows: 7, max: 4000 })])
      + `<div class="list-f">An appeal fee may be added to your bills. The other side is told.</div>` + busyBtn(s, 'File the appeal', 'appeal', { id }));
  }
  function lawyersPage(app) {
    const s = app.state, h = s.h, mineIds = new Set(h.lawyers.map((l) => l.charId));
    const mine = h.lawyers.map((l) => K.row({ av: K.avatar({ name: l.name, size: 34 }), label: l.name || 'Attorney', sub: [l.number, l.firm, l.phone ? K.fmtNumber(l.phone) : ''].filter(Boolean).join(' · '), value: 'End', act: 'askFire', d: { id: l.charId }, hint: 'End' }));
    const dir = (s.lawyers || []).filter((l) => !mineIds.has(l.charId)).map((l) => K.row({ av: K.avatar({ name: l.name, size: 34 }), label: l.name,
      sub: [l.rank || cap(l.kind), l.firm, l.online ? 'Online' : ''].filter(Boolean).join(' · '), value: l.online ? '●' : null, tone: l.online ? 'ct-online' : '', act: 'page', d: { p: 'hire', id: l.charId }, hint: 'Hire' }));
    return K.scroll((mine.length ? K.list(mine, { header: 'Representing you' }) : '')
      + (s.lawyers ? (dir.length ? K.list(dir, { header: 'Licensed attorneys', footer: 'A public defender is free: ask for one on an open case against you.' }) : K.empty({ title: 'No other attorneys', text: 'Nobody else holds a license right now.' })) : K.empty({ title: 'Loading…' })));
  }
  function hirePage(app, id) {
    const s = app.state, l = (s.lawyers || []).find((x) => x.charId === id);
    if (!l) return K.empty({ title: 'Loading…' });
    return K.scroll(`<div class="ct-lawyer">${K.avatar({ name: l.name, size: 64 })}<b>${K.esc(l.name)}</b><span>${K.esc([l.number, l.rank || cap(l.kind), l.firm].filter(Boolean).join(' · '))}</span>${l.phone ? `<span>${K.esc(K.fmtNumber(l.phone))}</span>` : ''}</div>`
      + `<div class="list-h">Message</div>` + K.list([area({ bind: 'message', value: s.f.message || '', placeholder: 'What you need help with', rows: 4, max: 300 })])
      + `<div class="list-f">They get a court notice and add you as a client to take it on.</div>` + busyBtn(s, 'Send the request', 'hire', { id }));
  }
  function recordsPage(app) {
    const s = app.state, R = s.records;
    let out = K.search({ bind: 'rq', value: s.rq, placeholder: 'Case number, title, business or attorney' });
    if (!R) out += `<div class="list-f">Type 3 letters or more. Sealed and test records are never shown.</div>`;
    else {
      if (R.cases && R.cases.length) out += K.list(R.cases.map((k) => K.row({ label: `${k.number} · ${k.title}`, sub: `${cap(k.kind)} · ${k.status === 'open' ? 'Open' : cap(k.verdict || k.status)}`, value: K.fmtWhen(k.createdAt) })), { header: 'Cases' });
      if (R.businesses && R.businesses.length) out += K.list(R.businesses.map((b) => K.row({ label: b.name, sub: `${b.licenseNo}${b.kind ? ' · ' + b.kind : ''}`, value: cap(b.status) })), { header: 'Businesses' });
      if (R.lawyers && R.lawyers.length) out += K.list(R.lawyers.map((l) => K.row({ label: l.name, sub: `${l.number || ''}${l.firm ? ' · ' + l.firm : ''}`, value: cap(l.status) })), { header: 'Attorneys' });
      if (!(R.cases || []).length && !(R.businesses || []).length && !(R.lawyers || []).length) out += K.empty({ icon: IC.search, title: 'Nothing found' });
    }
    return K.scroll(out);
  }
  const TITLES = { case: 'Case', tickets: 'Tickets', ticket: 'Ticket', contest: 'Contest', impounds: 'Impound', requests: 'Requests', petition: 'Request', civil: 'Lawsuit',
    payfor: 'Pay for someone', appeal: 'Appeal', lawyers: 'Lawyers', hire: 'Hire', records: 'Public records' };
  function pageBody(app, p) {
    switch (p.p) {
      case 'case': return casePage(app, p.id);
      case 'tickets': return ticketsPage(app);
      case 'ticket': return ticketPage(app, p.id);
      case 'contest': return contestPage(app, p.id);
      case 'impounds': return impoundsPage(app);
      case 'requests': return requestsPage(app);
      case 'petition': return petitionPage(app, p.kind);
      case 'civil': return civilPage(app);
      case 'payfor': return payForPage(app);
      case 'appeal': return appealPage(app, p.id);
      case 'lawyers': return lawyersPage(app);
      case 'hire': return hirePage(app, p.id);
      case 'records': return recordsPage(app);
      default: return '';
    }
  }
  function backLabel(s) {
    const prev = s.stack[s.stack.length - 2];
    if (prev) return prev.p === 'case' ? ((s.cases[prev.id] || {}).number || 'Case') : TITLES[prev.p] || 'Back';
    return (TABS.find((t) => t[0] === s.tab) || TABS[0])[1];
  }

  // ---------------------------------------------------------------- sheets
  function sheet(app) {
    const s = app.state, sh = s.sheet;
    if (!sh) return '';
    const two = (no, yes, act, d = {}, kind = '') => `<div class="ct-btns">${K.button({ label: no, act: 'closeSheet', kind: 'gray' })}${K.button({ label: s.busy ? 'Working…' : yes, act, d, kind })}</div>`;
    if (sh.kind === 'pay') {
      return K.sheet({ title: `Pay ${money(sh.amount)}`, close: 'closeSheet', body: K.list([K.row({ label: sh.title, sub: sh.sub || '' }), ...(sh.who ? [K.row({ label: 'For', value: sh.who })] : [])])
        + `<div class="list-h">Pay with</div>` + K.seg([['bank', 'Bank'], ['cash', 'Cash']], sh.method, 'payMethod') + two('Cancel', `Pay ${money(sh.amount)}`, 'pay') });
    }
    if (sh.kind === 'impound') {
      return K.sheet({ title: `Release ${sh.label}`, close: 'closeSheet', body: K.list([K.row({ label: 'To pay now', value: money(sh.amount) })])
        + `<div class="list-h">Pay with</div>` + K.seg([['bank', 'Bank'], ['cash', 'Cash']], sh.method, 'payMethod') + two('Cancel', `Pay ${money(sh.amount)}`, 'impoundPay') });
    }
    if (sh.kind === 'plea') {
      return K.sheet({ title: sh.a === 'accept' ? 'Accept the plea deal?' : 'Reject the plea deal?', close: 'closeSheet', body:
        para(sh.a === 'accept' ? 'You plead guilty on these terms and the judge sentences you on them. This cannot be undone here.' : 'The case goes on toward trial. The prosecution may offer another deal.')
        + two('Back', sh.a === 'accept' ? 'Accept' : 'Reject', 'plea', {}, sh.a === 'accept' ? '' : 'red') });
    }
    if (sh.kind === 'pd') return K.sheet({ title: 'Ask for a public defender?', close: 'closeSheet', body: para('The DOJ’s public defenders are told. One takes your case and you get a notice.') + two('Not now', 'Ask', 'publicDefender') });
    if (sh.kind === 'fire') return K.sheet({ title: `End ${sh.name}’s representation?`, close: 'closeSheet', body: para('They stop representing you and come off your open cases. They are told.') + two('Keep them', 'End it', 'fire', {}, 'red') });
    if (sh.kind === 'notice') {
      const n = s.h.notices.find((x) => x.id === sh.id);
      if (!n) return '';
      return K.sheet({ title: n.title, close: 'closeSheet', body: `<div class="ct-sheet-scroll"><div class="list-f">${K.esc(when(n.at))}</div>${n.body ? para(K.esc(n.body)) : ''}</div>`
        + (n.caseId ? `<div class="ct-btns">${K.button({ label: 'Close', act: 'closeSheet', kind: 'gray' })}${K.button({ label: 'Open the case', act: 'openCase', d: { id: n.caseId } })}</div>` : K.button({ label: 'Close', act: 'closeSheet', kind: 'gray', block: true })) });
    }
    if (sh.kind === 'filing') return filingSheet(app);
    return '';
  }

  // ---------------------------------------------------------------- the module
  WhipPhone.module({
    id: 'court', name: 'Court', version: '1.0.0', order: 60, icon: IC.app,
    css: `
.ct-hero{margin:4px 16px 20px;padding:16px 18px;border-radius:20px;color:#fff;background:linear-gradient(135deg,#1b2a4a 0%,#2c3f6b 55%,#6b5420 140%);box-shadow:0 10px 26px rgba(0,0,0,.3);position:relative;overflow:hidden}
.ct-hero:after{content:'';position:absolute;right:-30px;top:-30px;width:130px;height:130px;border-radius:50%;background:radial-gradient(circle,rgba(230,190,100,.35),transparent 70%)}
.ct-h-top{display:flex;align-items:center;gap:12px}
.ct-h-top b{display:block;font-size:17px;font-weight:700;letter-spacing:-.2px}
.ct-h-top span{font-size:12.5px;opacity:.75}
.ct-seal{width:40px;height:40px;border-radius:12px;display:grid;place-items:center;background:rgba(230,190,100,.2);color:#e8c46a;flex:none}
.ct-seal svg{width:24px;height:24px}
.ct-stats{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin-top:16px}
.ct-stats div{background:rgba(255,255,255,.09);border-radius:12px;padding:8px 10px}
.ct-stats i{display:block;font-style:normal;font-size:11px;opacity:.7;text-transform:uppercase;letter-spacing:.5px}
.ct-stats b{font-family:var(--font-display);font-size:20px;font-weight:700;font-variant-numeric:tabular-nums}
.ct-stats b.sm{font-size:15px;line-height:26px}
.ct-stats b.warn{color:#ffd27a}
.ct-total{display:flex;flex-direction:column;align-items:center;gap:2px;padding:6px 16px 20px;text-align:center}
.ct-total i{font-style:normal;font-size:14px;color:var(--text2);font-weight:600}
.ct-total b{font-family:var(--font-display);font-size:40px;font-weight:700;letter-spacing:-1px;font-variant-numeric:tabular-nums}
.ct-total span{font-size:13px;color:var(--text2)}
.row.ct-warn .r-ico{color:var(--orange)}
.row.ct-bad .r-ico,.row.ct-bad .r-val{color:var(--red)}
.row.ct-ok .r-ico,.row.ct-ok .r-val{color:var(--green)}
.row.ct-accent{color:var(--accent);font-weight:600}
.row.ct-mute{opacity:.6}
.row.ct-strong .r-val{font-weight:700;color:var(--text)}
.row.ct-online .r-val{color:var(--green);font-size:11px}
.row.ct-unread .r-main{font-weight:600}
.row.ct-read .r-ico{opacity:.5}
.ct-dot{display:block;width:10px;height:10px;border-radius:50%;background:var(--accent);margin:auto}
.ct-case{padding:2px 20px 16px}
.ct-case .ct-no{font-size:12.5px;font-weight:700;letter-spacing:.6px;color:var(--text2);font-variant-numeric:tabular-nums}
.ct-case b{display:block;font-family:var(--font-display);font-size:23px;font-weight:700;letter-spacing:-.4px;line-height:1.2;margin:2px 0 8px}
.ct-pills{display:flex;flex-wrap:wrap;gap:6px}
.ct-pill{font-style:normal;font-size:12px;font-weight:600;padding:3px 10px;border-radius:20px;background:var(--fill);color:var(--text2)}
.ct-pill.on{background:rgba(48,209,88,.18);color:var(--green)}
.ct-pill.bad{background:rgba(255,69,58,.18);color:var(--red)}
.ct-pill.warn{background:rgba(255,159,10,.18);color:var(--orange)}
.ct-card{margin:0 16px 20px;padding:13px 15px;border-radius:14px;background:var(--bg2)}
.ct-card p{margin:0 0 6px;font-size:14.5px;line-height:1.42;color:var(--text);white-space:pre-wrap}
.ct-card b{font-size:14px}
.ct-plea{border:1px solid rgba(255,159,10,.45)}
.ct-btns{display:flex;gap:10px;margin-top:10px}
.ct-btns .btn{flex:1}
.ct-go{padding:0 16px 22px}
.ct-p{font-size:14.5px;color:var(--text2);line-height:1.42;margin:0 2px 14px;white-space:pre-wrap}
.ct-ta{align-items:stretch;padding-top:10px;padding-bottom:10px}
.ct-ta textarea{width:100%;min-height:84px;font-size:15px;line-height:1.4}
.ct-sheet-scroll{max-height:52vh;overflow:auto;margin-bottom:12px}
.ct-img{display:block;max-width:100%;border-radius:12px;margin:4px 0 12px}
.ct-lawyer{display:flex;flex-direction:column;align-items:center;gap:4px;padding:6px 16px 20px;text-align:center}
.ct-lawyer b{font-size:20px;margin-top:6px}
.ct-lawyer span{font-size:13px;color:var(--text2)}
.sheet .seg{margin:0 0 12px}
.sheet .list{margin:0 0 14px}
.tabbar button svg{width:24px;height:24px;display:block;margin:0 auto 2px}
`,
    state: () => ({ h: null, loaded: false, err: null, tab: 'home', stack: [], sheet: null, busy: false, cases: {}, tickets: null, impounds: null, lawyers: null,
      records: null, rq: '', q: '', people: [], pick: null, other: null, myRecords: null, f: {} }),

    session(app) {
      Object.assign(app.state, { h: null, loaded: false, err: null, tab: 'home', stack: [], sheet: null, cases: {}, tickets: null, impounds: null, lawyers: null, records: null });
      return loadHome(app);
    },
    open(app, args = {}) {
      const s = app.state;
      const first = loadHome(app);
      if (args.caseId) { s.stack = []; return first.then(() => push(app, { p: 'case', id: +args.caseId })); }
      if (args.tab && TABS.some((t) => t[0] === args.tab)) { s.tab = args.tab; s.stack = []; s.sheet = null; }
      const p = cur(s);
      if (p) enter(app, p);
      return first;
    },
    route: (app) => { const s = app.state, p = cur(s); return s.sheet ? 'sheet-' + s.sheet.kind : p ? p.p : s.tab; },
    back(app) {
      const s = app.state;
      if (s.sheet) { s.sheet = null; return true; }
      if (s.stack.length) { s.stack.pop(); return true; }
      if (s.tab !== 'home') { s.tab = 'home'; return true; }
      return false;
    },
    tabLabel: () => 'Tabs',
    tab(app, dir) {
      const s = app.state;
      if (s.sheet || s.stack.length) return false;
      const i = TABS.findIndex((t) => t[0] === s.tab), n = (i + dir + TABS.length) % TABS.length;
      s.tab = TABS[n][0];
      return true;
    },
    x(app) {
      const s = app.state, p = cur(s);
      if (s.sheet || !s.h) return null;
      if (p) {
        if (p.p === 'case') return { label: 'Refresh', run: () => loadCase(app, p.id) };
        return null;
      }
      if (s.tab === 'notices' && s.h.unread) return { label: 'Mark all read', run: () => app.state.h && markAll(app) };
      if (s.tab === 'pay') return { label: 'Pay for someone', run: () => push(app, { p: 'payfor' }) };
      return { label: 'Refresh', run: () => loadHome(app) };
    },
    info(app) {
      const h = app.state.h;
      if (!h) return 'Your cases and bills';
      const o = owed(h);
      return h.unread ? `${h.unread} unread notice${h.unread === 1 ? '' : 's'}` : o ? `You owe ${money(o)}` : 'Nothing owed';
    },
    badge: (app) => (app.state.h ? app.state.h.unread + offers(app.state.h) : 0),

    render(app) {
      const s = app.state;
      if (!s.loaded) return K.screen('load', K.nav({ title: 'Court' }) + K.empty({ icon: IC.app, title: 'Loading…' }));
      if (!s.h) return K.screen('err', K.nav({ title: 'Court' }) + K.empty({ icon: IC.warn, title: 'The court is not answering', text: s.err || '', action: { act: 'reload', label: 'Try again' } }));
      const sh = sheet(app), p = cur(s);
      if (p) {
        const title = p.p === 'petition' ? PET[p.kind] || 'Request' : TITLES[p.p] || '';
        return K.screen(`p-${s.stack.length}-${p.p}-${p.id || p.kind || ''}`, K.nav({ back: backLabel(s), title }) + pageBody(app, p) + sh, { slide: true });
      }
      const h = s.h;
      const body = s.tab === 'cases' ? casesTab(app) : s.tab === 'pay' ? payTab(app) : s.tab === 'notices' ? noticesTab(app) : s.tab === 'more' ? moreTab(app) : homeTab(app);
      const right = s.tab === 'notices' && h.unread ? K.navBtn(I.check, 'markAll', {}, 'Mark all read') : '';
      const tabs = TABS.map(([v, l, ic]) => [v, l, ic, v === 'notices' ? h.unread : v === 'cases' ? offers(h) : v === 'pay' ? billCount(h) : 0]);
      return K.screen('t-' + s.tab, K.nav({ title: s.tab === 'home' ? 'Court' : (TABS.find((t) => t[0] === s.tab) || [])[1], right }) + K.scroll(body) + K.tabs(tabs, s.tab, 'goTab') + sh);
    },

    actions: {
      noop() {},
      reload(app) { app.state.loaded = false; return loadHome(app); },
      goTab(app, d) { const s = app.state; s.tab = d.tab || 'home'; s.stack = []; s.sheet = null; if (s.tab === 'home' || s.tab === 'pay' || s.tab === 'notices') return loadHome(app); },
      page(app, d) { return push(app, { p: d.p, id: d.id != null ? +d.id : undefined, kind: d.kind }); },
      openCase(app, d) { return push(app, { p: 'case', id: +d.id }); },
      openTicket(app, d) { return push(app, { p: 'ticket', id: +d.id }); },
      closeSheet(app) { app.state.sheet = null; },

      // ---- notices
      async openNotice(app, d) {
        const s = app.state, n = s.h.notices.find((x) => x.id === +d.id);
        if (!n) return;
        s.sheet = { kind: 'notice', id: n.id };
        if (!n.readAt) { n.readAt = nowS(); s.h.unread = s.h.notices.filter((x) => !x.readAt).length; await ask(app, 'noticeRead', { id: n.id }); }
      },
      markAll(app) { return markAll(app); },

      // ---- paying (never a bond)
      askPay(app, d) {
        const s = app.state, src = d.who ? s.other : s.h.fees;
        if (!src) return;
        const x = d.kind === 'fee' ? src.fees.find((f) => f.id === +d.id) : src.fines.find((f) => f.id === +d.id);
        if (!x || x.kind === 'bail') return;
        const title = d.kind === 'fee' ? `${x.label || cap(x.kind)}${x.number ? ' · ' + x.number : ''}` : x.ticketId ? (x.reason || 'Police ticket') : `Police fine #${x.id}`;
        s.sheet = { kind: 'pay', fine: d.kind === 'fine', id: x.id, amount: x.amount, title, sub: d.kind === 'fee' ? x.reason : x.dept, who: d.who || null, method: 'bank' };
      },
      payMethod(app, d) { if (app.state.sheet) app.state.sheet.method = d.v === 'cash' ? 'cash' : 'bank'; },
      async pay(app) {
        const s = app.state, sh = s.sheet;
        if (!sh || s.busy) return;
        s.busy = true;
        const r = await ask(app, sh.fine ? 'payFine' : 'pay', { id: sh.id, method: sh.method }, 'The payment did not go through');
        s.busy = false;
        if (!r) return;
        s.sheet = null;
        app.toast(`Paid ${money(r.amount || sh.amount)}${r.test ? ' (test)' : ''}`);
        if (sh.who && s.pick) s.other = await ask(app, 'billsFor', { charId: s.pick.id }).then((b) => (b ? cleanBills(b) : null));
        await loadHome(app);
      },
      askImpound(app, d) {
        const s = app.state, x = (s.impounds || []).find((i) => i.id === +d.id);
        if (x) s.sheet = { kind: 'impound', id: x.id, amount: (x.owe || {}).total || 0, label: x.plate || x.vehicleLabel || 'vehicle', method: 'bank' };
      },
      async impoundPay(app) {
        const s = app.state, sh = s.sheet;
        if (!sh || s.busy) return;
        s.busy = true;
        const r = await ask(app, 'impoundPay', { id: sh.id, method: sh.method }, 'The payment did not go through');
        s.busy = false;
        if (!r) return;
        s.sheet = null;
        app.toast(`Paid ${money(r.amount)}: pick it up at ${r.lot || 'the lot'}`);
        await enter(app, { p: 'impounds' });
        await loadHome(app);
      },

      // ---- someone else
      async pickPerson(app, d) {
        const s = app.state, p = cur(s);
        s.pick = { id: +d.id, name: d.name };
        if (p && p.p === 'payfor') { s.other = null; const b = await ask(app, 'billsFor', { charId: s.pick.id }); s.other = b ? cleanBills(b) : { fees: [], fines: [], name: d.name }; }
      },
      unpick(app) { const s = app.state; s.pick = null; s.other = null; },

      // ---- cases
      askPlea(app, d) { app.state.sheet = { kind: 'plea', id: +d.id, a: d.a === 'accept' ? 'accept' : 'reject' }; },
      async plea(app) {
        const s = app.state, sh = s.sheet, p = cur(s);
        if (!sh || s.busy) return;
        s.busy = true;
        const r = await ask(app, 'plea', { id: sh.id, act: sh.a }, 'Could not answer the offer');
        s.busy = false;
        if (!r) return;
        s.sheet = null;
        app.toast(sh.a === 'accept' ? 'Plea deal accepted' : 'Plea deal rejected');
        if (p && p.p === 'case') await loadCase(app, p.id);
        await loadHome(app);
      },
      askPd(app, d) { app.state.sheet = { kind: 'pd', id: +d.id }; },
      async publicDefender(app) {
        const s = app.state, sh = s.sheet;
        if (!sh || s.busy) return;
        s.busy = true;
        const r = await ask(app, 'publicDefender', { caseId: sh.id }, 'Could not ask for one');
        s.busy = false;
        if (!r) return;
        s.sheet = null;
        app.toast('A public defender has been asked for');
        await loadCase(app, sh.id);
      },
      async openFiling(app, d) {
        const s = app.state, k = s.cases[+d.c], f = k && k.filings.find((x) => x.id === +d.id);
        if (!f) return;
        s.sheet = { kind: 'filing', id: f.id, c: k.id, img: null };
        if (f.hasImage) {
          const img = await ask(app, 'filingImage', { id: f.id }, 'Could not load the picture');
          if (s.sheet && s.sheet.id === f.id && typeof img === 'string' && /^(data:image\/|https:\/\/)/.test(img)) s.sheet.img = img;
        }
      },
      async appeal(app, d) {
        const s = app.state;
        if (s.busy) return;
        if ((s.f.reason || '').trim().length < 20) return app.toast('Write the grounds (a few sentences)');
        s.busy = true;
        const r = await ask(app, 'appeal', { caseId: +d.id, reason: s.f.reason }, 'Could not file the appeal');
        s.busy = false;
        if (!r) return;
        app.toast(`Appeal ${r.number || ''} filed`);
        s.stack.pop();
        await loadHome(app);
        if (r.id) await push(app, { p: 'case', id: r.id });
      },
      async civil(app) {
        const s = app.state;
        if (s.busy) return;
        if (!s.pick) return app.toast('Pick who you are suing');
        if ((s.f.summary || '').trim().length < 20) return app.toast('Say what happened and what you ask for');
        s.busy = true;
        const r = await ask(app, 'civil', { defendantCharId: s.pick.id, title: s.f.title, summary: s.f.summary }, 'Could not file it');
        s.busy = false;
        if (!r) return;
        app.toast(`${r.number || 'Lawsuit'} filed`);
        s.stack = [];
        s.tab = 'cases';
        await loadHome(app);
      },

      // ---- tickets
      async contest(app, d) {
        const s = app.state;
        if (s.busy) return;
        if ((s.f.reason || '').trim().length < 5) return app.toast('Say why the ticket is wrong');
        s.busy = true;
        const r = await ask(app, 'contest', { id: +d.id, reason: s.f.reason }, 'Could not file the contest');
        s.busy = false;
        if (!r) return;
        app.toast('Contest filed: the payment is paused');
        s.f.reason = '';
        s.stack.pop();
        await enter(app, { p: 'tickets' });
        await loadHome(app);
      },

      // ---- requests
      pickRec(app, d) {
        const f = app.state.f, list = f[d.t === 'cases' ? 'cases' : 'reports'], id = +d.id, i = list.indexOf(id);
        if (i >= 0) list.splice(i, 1); else if (list.length < 20) list.push(id);
      },
      async petition(app, d) {
        const s = app.state, f = s.f, kind = d.kind;
        if (s.busy) return;
        let data = {};
        if (kind === 'name_change') data = { firstName: f.firstName.trim(), lastName: f.lastName.trim() };
        if (kind === 'business') data = { name: f.name.trim(), kind: f.kind.trim(), address: f.address.trim() };
        if (kind === 'expungement') data = { reports: f.reports.slice(), cases: f.cases.slice() };
        s.busy = true;
        const r = await ask(app, 'petition', { kind, data, reason: f.reason }, 'Could not file it');
        s.busy = false;
        if (!r) return;
        app.toast(r.fee ? `Filed: pay the ${money(r.fee)} fee under Pay` : 'Filed');
        s.stack.pop();
        await loadHome(app);
      },

      // ---- lawyers
      async hire(app, d) {
        const s = app.state;
        if (s.busy) return;
        s.busy = true;
        const r = await ask(app, 'hire', { charId: +d.id, message: s.f.message || '' }, 'Could not send it');
        s.busy = false;
        if (!r) return;
        app.toast('Sent: they get a court notice');
        s.f.message = '';
        s.stack.pop();
      },
      askFire(app, d) { const l = app.state.h.lawyers.find((x) => x.charId === +d.id); if (l) app.state.sheet = { kind: 'fire', id: l.charId, name: l.name || 'your lawyer' }; },
      async fire(app) {
        const s = app.state, sh = s.sheet;
        if (!sh || s.busy) return;
        s.busy = true;
        const r = await ask(app, 'fire', { charId: sh.id }, 'Could not end it');
        s.busy = false;
        if (!r) return;
        s.sheet = null;
        app.toast('Representation ended');
        await loadHome(app);
      },
    },
    bind: {
      reason(app, v) { app.state.f.reason = String(v).slice(0, 4000); },
      summary(app, v) { app.state.f.summary = String(v).slice(0, 4000); },
      title(app, v) { app.state.f.title = String(v).slice(0, 160); },
      message(app, v) { app.state.f.message = String(v).slice(0, 300); },
      firstName(app, v) { app.state.f.firstName = String(v).slice(0, 30); },
      lastName(app, v) { app.state.f.lastName = String(v).slice(0, 30); },
      bizName(app, v) { app.state.f.name = String(v).slice(0, 80); },
      bizKind(app, v) { app.state.f.kind = String(v).slice(0, 40); },
      bizAddr(app, v) { app.state.f.address = String(v).slice(0, 160); },
      q(app, v) { app.state.q = String(v).slice(0, 40); searchSoon(app, 'people'); },
      rq(app, v) { app.state.rq = String(v).slice(0, 60); searchSoon(app, 'records'); },
    },
    on: {
      /** es_mdt pushes this when the court writes this character a notice (DOJ.notice): read again, quietly (the
       *  framework's own notification already told them) */
      notice(app) { return loadHome(app).then(() => app.render()); },
    },
  });

  function cleanBills(b) {
    b.fees = (b.fees || []).filter((x) => x.kind !== 'bail');
    b.fines = b.fines || [];
    return b;
  }
  async function markAll(app) {
    const s = app.state;
    if (!s.h) return;
    s.h.notices.forEach((n) => { n.readAt = n.readAt || nowS(); });
    s.h.unread = 0;
    await ask(app, 'noticeRead', { all: true });
  }
})();
