// es_doj cases: the case list, a new case (from an MDT report or by hand), and the full case page with every court action.
(function () {
  'use strict';
  const D = window.DOJ;
  const { S, $, $$, esc, money, call, toast, said, busy, ago, inTime, date, dateTime, pill, empty, cap, labelOf, kindTag, stageLabel, R, has,
    verdictPill, statusPill, caseNo, modal, confirmBox, form, answer, go, crumb, wireBack, rerender, views } = D;

  // ---------------------------------------------------------------- shared lists
  let penal = null, roster = null;
  async function penalCode() {
    if (penal) return penal;
    const r = await call('penal');
    penal = (r.ok && r.data) || [];
    setTimeout(() => { penal = null; }, 120000);
    return penal;
  }
  async function dojRoster() {
    if (roster) return roster;
    const r = await call('judges');
    roster = (r.ok && r.data) || [];
    setTimeout(() => { roster = null; }, 60000);
    return roster;
  }
  const ROLE_RX = { judge: /judge|justice/i, prosecutor: /prosecut|district attorney|\bda\b|\bada\b/i, defender: /defender/i };
  // a form field to pick a DOJ member of a role (a list when the roster has them, else search anyone)
  async function memberField(k, label, role, cur, curName) {
    const list = (await dojRoster()).filter((m) => ROLE_RX[role].test(m.roleName || ''));
    if (!list.length) return { k, label, type: 'person', value: cur ? { charId: cur, name: curName || '#' + cur } : null, placeholder: 'Search a name…', span2: true };
    const opts = [{ v: '', l: '— Nobody —' }].concat(list.map((m) => ({ v: m.charId, l: `${m.name} · ${m.roleName}${m.online ? ' ●' : ''}` })));
    if (cur && !list.some((m) => m.charId === cur)) opts.push({ v: cur, l: curName || '#' + cur });
    return { k, label, type: 'select', opts, value: cur || '', span2: true, hint: '● in the city now' };
  }
  const pickedId = (v) => v && typeof v === 'object' ? v.charId : (v ? +v : 0);

  // the charge picker: search the penal code, click to add, set counts
  async function chargePicker(hostEl, start) {
    const code = await penalCode();
    const chosen = new Map();   // penalId -> count
    (start || []).forEach((c) => chosen.set(c.penalId, c.count || 1));
    hostEl.innerHTML = `<input type="text" data-q placeholder="Search charges by code or name…"><div class="cp-list mt" data-list></div><div class="chosen" data-chosen></div><div class="totals" data-tot></div>`;
    const q = $('[data-q]', hostEl), listEl = $('[data-list]', hostEl), chEl = $('[data-chosen]', hostEl), tot = $('[data-tot]', hostEl);
    const byId = new Map(code.map((p) => [p.id, p]));
    const drawList = () => {
      const s = q.value.trim().toLowerCase();
      const rows = code.filter((p) => !s || p.code.toLowerCase().includes(s) || p.title.toLowerCase().includes(s)).slice(0, 80);
      listEl.innerHTML = rows.length ? rows.map((p) => `<div class="cp-row ${chosen.has(p.id) ? 'on' : ''}" data-id="${p.id}"><span class="code">${esc(p.code)}</span><span class="cat c-${esc(p.category)}">${esc(cap(p.category))}</span><span class="flex1">${esc(p.title)}</span><span class="hint">${money(p.fine)} · ${p.months} mo</span></div>`).join('')
        : '<div class="pop-empty">No charge matches</div>';
      $$('[data-id]', listEl).forEach((r) => r.onclick = () => { const id = +r.dataset.id; if (chosen.has(id)) chosen.delete(id); else chosen.set(id, 1); drawList(); drawChosen(); });
    };
    const drawChosen = () => {
      let fine = 0, months = 0;
      chEl.innerHTML = Array.from(chosen.entries()).map(([id, n]) => { const p = byId.get(id) || { code: '#' + id, title: '' }; fine += (p.fine || 0) * n; months += (p.months || 0) * n; return `<span class="chip" title="${esc(p.title)}">${esc(p.code)} ${esc(p.title)} ×<input type="number" min="1" max="20" value="${n}" data-n="${id}"><button type="button" data-rm="${id}">✕</button></span>`; }).join('');
      tot.innerHTML = chosen.size ? `<span>${chosen.size} charge${chosen.size === 1 ? '' : 's'}</span><span>Up to <b>${money(fine)}</b></span><span>Up to <b>${months} months</b></span>` : '<span class="muted">No charges picked yet</span>';
      $$('[data-rm]', chEl).forEach((b) => b.onclick = () => { chosen.delete(+b.dataset.rm); drawList(); drawChosen(); });
      $$('[data-n]', chEl).forEach((i) => i.onchange = () => { chosen.set(+i.dataset.n, Math.max(1, Math.min(20, +i.value || 1))); drawChosen(); });
    };
    q.addEventListener('input', drawList);
    drawList(); drawChosen();
    return { get: () => Array.from(chosen.entries()).map(([penalId, count]) => ({ penalId, count })) };
  }
  D.chargePicker = chargePicker;
  D.penalCode = penalCode;
  D.penalCodeReset = () => { penal = null; };
  D.memberField = memberField;
  D.pickedId = pickedId;

  // ---------------------------------------------------------------- the list
  const F = { status: 'open', kind: '', mine: false, q: '', page: 0 };
  views.cases = async (h, arg, alive) => {
    if (arg && arg.mine != null) F.mine = arg.mine;
    const r = await call('cases', { status: F.status, kind: F.kind, mine: F.mine, q: F.q, page: F.page });
    if (!alive()) return;
    const rows = (r.ok && r.data.rows) || [];
    const canNew = has('cases', 'judge', 'prosecutor');
    h.innerHTML = `<div class="v-head"><div><div class="v-title">Court cases</div><div class="v-sub">Every case before the court. Click one to open it.</div></div>
        <div class="row">${canNew ? '<button class="btn gold" data-new>＋ New case</button>' : ''}</div></div>
      <div class="filters">
        <div class="seg" data-st>${['open', 'closed', 'dismissed', 'all'].map((s) => `<button data-v="${s}" class="${F.status === s ? 'on' : ''}">${cap(s)}</button>`).join('')}</div>
        <select data-kind class="small-sel"><option value="">All kinds</option>${(S.lists.caseKinds || []).map((k) => `<option value="${k.key}" ${F.kind === k.key ? 'selected' : ''}>${esc(k.label)}</option>`).join('')}</select>
        <label class="ck-item"><input type="checkbox" data-mine ${F.mine ? 'checked' : ''}> Mine only</label>
        <input type="text" data-q placeholder="Case number, title or defendant…" value="${esc(F.q)}">
      </div>
      <div class="card flush">${rows.length ? `<table><thead><tr><th>Case</th><th>Title</th><th>Defendant</th><th>Stage</th><th>Judge</th><th>Next hearing</th><th class="num">Updated</th></tr></thead><tbody>
        ${rows.map((k) => `<tr class="click" data-case="${k.id}"><td>${caseNo(k)}<span class="sub">${kindTag(k.kind)}</span></td>
          <td><b>${esc(k.title)}</b> ${k.sealed ? pill('Sealed', 'sealed') : ''} ${k.test ? pill('Test', 'test') : ''}<span class="sub">${k.charges} charge${k.charges === 1 ? '' : 's'}</span></td>
          <td>${esc(k.defendant || '—')}</td>
          <td>${k.status === 'open' ? esc(stageLabel(k.stage)) : statusPill(k.status)} ${verdictPill(k.verdict)}</td>
          <td>${k.judge ? esc(k.judge) : '<span class="txt-warn">Unassigned</span>'}</td>
          <td>${k.nextHearing ? `${dateTime(k.nextHearing)}<span class="sub">${inTime(k.nextHearing)}</span>` : '<span class="muted">—</span>'}</td>
          <td class="num hint">${ago(k.updatedAt)}</td></tr>`).join('')}</tbody></table>` : empty(F.q ? 'No case matches that search' : 'No cases here yet', '⚖')}</div>
      <div class="row between">${F.page > 0 ? '<button class="btn small" data-prev>← Newer</button>' : '<span></span>'}${r.ok && r.data.more ? '<button class="btn small" data-next>Older →</button>' : ''}</div>`;
    $$('[data-st] button', h).forEach((b) => b.onclick = () => { F.status = b.dataset.v; F.page = 0; rerender(); });
    $('[data-kind]', h).onchange = (e) => { F.kind = e.target.value; F.page = 0; rerender(); };
    $('[data-mine]', h).onchange = (e) => { F.mine = e.target.checked; F.page = 0; rerender(); };
    let t = null; const q = $('[data-q]', h);
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { F.q = q.value.trim(); F.page = 0; rerender().then(() => { const n = $('[data-q]', h.isConnected ? h : document); if (n) { n.focus(); n.setSelectionRange(n.value.length, n.value.length); } }); }, 350); });
    const p = $('[data-prev]', h); if (p) p.onclick = () => { F.page--; rerender(); };
    const n = $('[data-next]', h); if (n) n.onclick = () => { F.page++; rerender(); };
    const nb = $('[data-new]', h); if (nb) nb.onclick = () => newCase();
  };

  // ---------------------------------------------------------------- a new case
  async function newCase(pre) {
    pre = pre || {};
    let mode = pre.reportId ? 'report' : 'manual';
    let report = null, who = pre.person || null, picker = null;
    const kinds = (S.lists.caseKinds || []).filter((k) => k.key !== 'appeal');
    const judgeF = await memberField('judge', 'Judge', 'judge', null);
    modal(`<div class="m-title"><span class="m-ico">⚖</span>New case</div>
      <div class="choice" data-mode style="grid-template-columns:1fr 1fr">
        <button type="button" data-v="report"><b>From an MDT report</b><span>Brings the police report's people and charges</span></button>
        <button type="button" data-v="manual"><b>File by hand</b><span>Pick the defendant and charges yourself</span></button></div>
      <div data-body class="mt"></div>
      <div class="form-err" data-err></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn gold" data-ok>File the case</button></div>`, (card, closeIt) => {
      const body = $('[data-body]', card), err = $('[data-err]', card);
      const common = () => `<div class="grid mt">
          <div class="field span2"><label>Title <span class="hint">· blank = "State of San Andreas v. …"</span></label><input type="text" data-title maxlength="160" placeholder="State of San Andreas v. …"></div>
          <div class="field"><label>Kind</label><select data-kind>${kinds.map((k) => `<option value="${k.key}">${esc(k.label)}</option>`).join('')}</select></div>
          <div class="field" data-judge></div>
          <div class="field span2"><label>Summary <span class="hint">· what the case is about</span></label><textarea data-summary rows="3" maxlength="4000"></textarea></div>
          ${R().staff || S.me.viewAs ? '<label class="ck-item span2"><input type="checkbox" data-test> <span>Test case <span class="hint">· you are the defendant; nothing real happens (fines, jail, warrants)</span></span></label>' : ''}
        </div>`;
      const judgeHtml = () => judgeF.type === 'select' ? `<label>Judge <span class="hint">· optional</span></label><select data-judgesel>${judgeF.opts.map((o) => `<option value="${o.v}">${esc(o.l)}</option>`).join('')}</select>`
        : '<label>Judge</label><div class="hint">Assign one on the case page</div>';
      const drawReport = () => {
        body.innerHTML = `<div class="row"><input type="number" data-rid placeholder="MDT report number" style="width:220px" value="${esc(pre.reportId || '')}"><button class="btn" data-look>Look up</button></div><div data-rep class="mt"></div>${common()}`;
        $('[data-judge]', body).innerHTML = judgeHtml();
        const look = $('[data-look]', body);
        const run = () => busy(look, async () => {
          const rid = +$('[data-rid]', body).value;
          const r = await call('reportLookup', { reportId: rid });
          const rep = $('[data-rep]', body);
          if (!r.ok) { report = null; rep.innerHTML = `<div class="help">${esc(r.why)}</div>`; return; }
          report = r.data; who = null;
          const ppl = report.people.filter((p) => p.role === 'suspect' || p.charges.length);
          rep.innerHTML = `<div class="help"><b>#${report.id} · ${esc(report.title || cap(report.type))}</b> · ${esc(report.dept || '')} · ${date(report.createdAt)}${report.caseId ? ' · police case #' + report.caseId : ''}</div>
            <div class="lbl mt">Who goes to court?</div>
            ${(ppl.length ? ppl : report.people).map((p) => `<label class="li click" style="cursor:pointer"><input type="radio" name="def" value="${p.charId}">
              <div class="li-main"><b>${esc(p.name)}</b><span class="hint">${esc(cap(p.role))} · ${p.charges.length ? p.charges.map((g) => esc(g.code + (g.count > 1 ? ' ×' + g.count : ''))).join(', ') : 'no charges on the report'}</span></div>
              ${p.courtCase ? pill('Already in ' + p.courtCase.number, 'warn') : ''}</label>`).join('') || empty('Nobody is on that report')}`;
          $$('input[name=def]', rep).forEach((i) => i.onchange = () => { const p = report.people.find((x) => x.charId === +i.value); who = { charId: p.charId, name: p.name }; const t = $('[data-title]', body); if (!t.value) t.placeholder = 'State of San Andreas v. ' + p.name; });
        });
        look.onclick = run;
        $('[data-rid]', body).addEventListener('keydown', (e) => { if (e.key === 'Enter') run(); });
        if (pre.reportId) run();
      };
      const drawManual = async () => {
        body.innerHTML = `<div class="field"><label>Defendant</label><div data-pp></div><div class="chosen" data-who></div></div>
          <div class="field"><label>Charges</label><div data-cp></div></div>${common()}`;
        $('[data-judge]', body).innerHTML = judgeHtml();
        const showWho = () => { $('[data-who]', body).innerHTML = who ? `<span class="chip">${esc(who.name)} <span class="hint">#${who.charId}</span><button type="button">✕</button></span>` : ''; const b = $('[data-who] button', body); if (b) b.onclick = () => { who = null; showWho(); }; };
        D.personPicker($('[data-pp]', body), 'Search the defendant…', (p) => { who = p; showWho(); const t = $('[data-title]', body); t.placeholder = 'State of San Andreas v. ' + p.name; });
        showWho();
        picker = await chargePicker($('[data-cp]', body), []);
      };
      const setMode = (m) => { mode = m; $$('[data-mode] button', card).forEach((b) => b.classList.toggle('on', b.dataset.v === m)); report = null; picker = null; if (m === 'report') drawReport(); else drawManual(); };
      $$('[data-mode] button', card).forEach((b) => b.onclick = () => setMode(b.dataset.v));
      setMode(mode);
      const ok = $('[data-ok]', card);
      ok.onclick = () => busy(ok, async () => {
        const test = !!($('[data-test]', body) && $('[data-test]', body).checked);
        const kind = $('[data-kind]', body).value;
        const d = { kind, title: $('[data-title]', body).value.trim(), summary: $('[data-summary]', body).value.trim(), test };
        const js = $('[data-judgesel]', body); if (js && js.value) d.judgeCharId = +js.value;
        if (mode === 'report') {
          if (!report) { err.textContent = 'Look up the MDT report first'; return; }
          if (!who && !test) { err.textContent = 'Pick who goes to court'; return; }
          d.reportId = report.id; if (who) d.defendantCharId = who.charId;
        } else {
          if (!who && !test && kind !== 'civil' && kind !== 'petition') { err.textContent = 'Pick the defendant'; return; }
          if (who) d.defendantCharId = who.charId;
          d.charges = picker ? picker.get() : [];
        }
        let r = await call('caseCreate', d);
        if (!r.ok && /already open/.test(r.why || '')) {
          if (!(await confirmBox('Already in court', r.why + '. File another case anyway?', 'File anyway'))) return;
          d.force = true; r = await call('caseCreate', d);
        }
        if (!r.ok) { err.textContent = r.why || 'That did not work'; return; }
        closeIt(); toast(`${r.data.number} filed`, 'ok');
        go('case', r.data.id, { parent: 'cases' });
      });
    }, 'wide');
  }
  D.newCase = newCase;

  // ---------------------------------------------------------------- the case page
  const TABS = [['overview', 'Overview'], ['hearings', 'Hearings'], ['filings', 'Filings & exhibits'], ['pleas', 'Plea deals'], ['money', 'Sentence & bail'], ['subpoenas', 'Subpoenas'], ['discovery', 'Police file'], ['docket', 'Docket']];
  const tabOf = {};
  views.case = async (h, id, alive) => {
    const r = await call('case', { id });
    if (!alive()) return;
    if (!r.ok) { h.innerHTML = `${crumb()}${empty(r.why, '🔒')}`; wireBack(h); return; }
    const k = r.data, c = k.can || {};
    const full = k.access === 'full';
    const tab = tabOf[k.id] || 'overview';
    const open = k.status === 'open';
    const stages = S.lists.stages || [];
    const si = stages.findIndex((s) => s.key === (open ? k.stage : 'closed'));
    const n = { hearings: k.hearings.length, filings: (k.filings || []).length, pleas: (k.pleas || []).length, subpoenas: (k.subpoenas || []).length };
    const pendingPlea = (k.pleas || []).find((p) => p.status === 'offered' || p.status === 'accepted');
    const pendingMotions = (k.filings || []).filter((f) => f.status === 'pending').length;
    const btn = (on, act, label, cls) => on ? `<button class="btn small ${cls || ''}" data-a="${act}">${label}</button>` : '';
    h.innerHTML = `${crumb('Cases')}
      <div class="case-head">
        <div class="flex1">
          <div class="case-meta">${caseNo(k)} ${kindTag(k.kind)} ${statusPill(k.status)} ${verdictPill(k.verdict)} ${k.sealed ? pill('Sealed', 'sealed') : ''} ${k.test ? pill('Test case', 'test') : ''} ${full ? '' : pill('Public view', 'off')}</div>
          <div class="case-title">${esc(k.title)}</div>
          <div class="hint">Filed ${date(k.createdAt)}${k.closedAt ? ' · closed ' + date(k.closedAt) : ''}${k.side ? ' · you are <b>' + esc(k.side === 'court' ? 'the court' : k.side) + '</b>' : ''}</div>
        </div>
        <div class="actbar">
          ${btn(c.schedule, 'schedule', '▦ Schedule hearing')}
          ${btn(c.file, 'file', '＋ File document')}
          ${btn(c.plea, 'plea', '✍ Offer plea deal')}
          ${btn(c.verdict, 'verdict', '⚖ Verdict', 'gold')}
          ${btn(c.sentence, 'sentence', '⚖ ' + (k.kind === 'civil' ? 'Judgment' : 'Sentence'), 'gold')}
          ${btn(c.appealRule, 'appealRule', '⚖ Rule on appeal', 'gold')}
          ${btn(c.bail, 'bail', '$ Bail')}
          ${btn(c.subpoena, 'subpoena', '✉ Subpoena')}
          ${btn(c.bench, 'bench', '⚠ Bench warrant')}
          ${btn(c.appeal, 'appeal', '↗ Appeal')}
          ${btn(c.close, 'close', open && k.side === 'prosecution' && !R().judge ? 'Drop charges' : 'Close case', 'danger')}
          ${btn(c.reopen, 'reopen', '↺ Reopen')}
          ${btn(c.seal, 'seal', k.sealed ? '🔓 Unseal' : '🔒 Seal')}
        </div>
      </div>
      <div class="stages">${stages.map((s, i) => `<span class="stg ${i < si || (!open && i <= si) ? 'done' : i === si ? 'now' : ''} ${c.stage && s.key !== 'closed' ? 'click' : ''}" data-stage="${s.key}"><i>${i < si || (!open && i <= si) ? '✓' : i + 1}</i>${esc(s.label)}</span>`).join('')}</div>
      ${banner(k)}
      <div class="parties">
        ${k.kind === 'civil' ? party('Plaintiff', k.plaintiff, k.plaintiffCharId) : ''}
        ${party(k.kind === 'civil' ? 'Defendant' : 'Defendant', k.defendant, k.defendantCharId, k.plea && k.plea !== 'none' ? 'Plea: ' + cap(k.plea) : '', c.pleaEntry && k.kind !== 'civil' ? 'pleaEntry' : null, 'Enter plea')}
        ${party('Judge', k.judge, k.judgeCharId, '', c.assignJudge ? 'assignJudge' : null, k.judge ? 'Change' : 'Assign')}
        ${k.kind === 'civil' ? '' : party('Prosecutor', k.prosecutor, k.prosecutorCharId, '', c.assignProsecutor ? 'assignProsecutor' : null, k.prosecutor ? 'Change' : 'Assign')}
        ${party('Defense', k.defense || (k.defenseKind === 'self' ? 'Self-represented' : k.defenseKind === 'public' && !k.defense ? 'Public defender requested' : null), k.defenseCharId, k.defenseKind && k.defenseKind !== 'none' && k.defense ? cap(k.defenseKind) : '', c.assignDefense ? 'assignDefense' : null, k.defense ? 'Change' : 'Assign')}
        ${k.kind !== 'civil' && k.defendantCharId ? `<div class="party"><span class="lbl">Bail</span><b>${bailText(k)}</b>${c.bail ? '<div class="p-act"><button class="btn small ghost" data-a="bail">Manage</button></div>' : ''}</div>` : ''}
      </div>
      ${full ? `<div class="tabs">${TABS.map(([t, l]) => `<button class="tab ${tab === t ? 'on' : ''}" data-tab="${t}">${l}${n[t] ? ` <span class="count">${n[t]}</span>` : ''}${t === 'pleas' && pendingPlea ? ' <span class="pill warn">open</span>' : ''}${t === 'filings' && pendingMotions ? ` <span class="pill warn">${pendingMotions} pending</span>` : ''}</button>`).join('')}</div>` : ''}
      <div data-tabbody></div>`;
    wireBack(h);
    const body = $('[data-tabbody]', h);
    const drawTab = (t) => { tabOf[k.id] = t; $$('[data-tab]', h).forEach((b) => b.classList.toggle('on', b.dataset.tab === t)); body.innerHTML = ''; (TAB[full ? t : 'public'] || TAB.overview)(body, k); };
    $$('[data-tab]', h).forEach((b) => b.onclick = () => drawTab(b.dataset.tab));
    drawTab(full ? tab : 'public');
    $$('[data-a]', h).forEach((b) => b.onclick = () => ACT[b.dataset.a] && ACT[b.dataset.a](k, b));
    if (c.stage) $$('[data-stage]', h).forEach((b) => b.onclick = async () => {
      const st = b.dataset.stage; if (st === 'closed' || st === k.stage) return;
      if (!(await confirmBox('Move the case', `Move ${k.number} to ${stageLabel(st)}?`, 'Move'))) return;
      if (!said(await call('caseUpdate', { id: k.id, stage: st }), 'Stage changed')) return;
      rerender();
      // 1.1.0: moving to Sentencing without a verdict: the verdict comes first
      if (st === 'sentencing' && (!k.verdict || k.verdict === 'none') && c.verdict) setTimeout(() => ACT.verdict(k), 400);
    });
  };

  function party(label, name, cid, sub, act, actLabel) {
    return `<div class="party ${cid && cid === (S.me || {}).charId ? 'me' : ''}"><span class="lbl">${esc(label)}</span>${name ? `<b ${cid ? `class="lnk" data-person="${cid}"` : ''}>${esc(name)}</b>` : '<b class="none">None</b>'}${sub ? `<span class="hint">${esc(sub)}</span>` : ''}${act ? `<div class="p-act"><button class="btn small ghost" data-a="${act}">${esc(actLabel)}</button></div>` : ''}</div>`;
  }
  function bailText(k) {
    const m = { none: 'Not set', set: `${money(k.bailAmount)} set · bond ${money(k.bond)}`, posted: 'Posted', denied: 'Denied (held)', ror: 'Own recognizance', revoked: 'Revoked', forfeited: 'Forfeited', returned: 'Returned' };
    return esc(m[k.bailStatus] || cap(k.bailStatus || 'none'));
  }
  function banner(k) {
    const c = k.can || {};
    if (k.status === 'open' && (!k.verdict || k.verdict === 'none')) {
      const seal = k.sealed ? `<div class="verdict-banner"><b>🔒 Sealed</b><span>${esc(k.sealReason || '')}</span></div>` : '';
      // 1.1.0: at trial or sentencing without a verdict, say what comes next (a sentence needs a verdict first)
      const late = k.stage === 'sentencing' || k.stage === 'trial';
      return seal + (late && k.kind !== 'appeal' ? `<div class="verdict-banner next"><b>Next step</b><span class="flex1">${k.stage === 'sentencing' ? 'No verdict yet: enter the verdict first, then the ' + (k.kind === 'civil' ? 'judgment' : 'sentence') + ' opens straight after.' : 'When the trial ends, enter the verdict. A guilty verdict opens the sentence.'}</span>${c.verdict ? '<button class="btn small gold" data-a="verdict">⚖ Enter the verdict</button>' : ''}</div>` : '');
    }
    const v = k.verdict || 'none';
    const bad = ['guilty', 'plaintiff', 'plea', 'affirmed'].includes(v), good = ['not_guilty', 'dismissed', 'reversed', 'defendant'].includes(v);
    const s = (k.sentences || []).filter((x) => x.status === 'active')[0];
    const st = s ? [s.fine ? money(s.fine) + ' fine' : '', s.months ? s.months + ' months' : '', s.service ? s.service + ' service tasks' : '', s.probationDays ? s.probationDays + ' days probation' : '', s.restitution ? money(s.restitution) + (k.kind === 'civil' ? ' award' : ' restitution') : ''].filter(Boolean).join(' · ') : '';
    return `<div class="verdict-banner ${bad ? 'bad' : good ? 'ok' : ''}"><b>${esc(D.VERDICT[v] || (k.status === 'open' ? 'Open' : cap(k.status)))}</b>
      <span class="flex1">${(v === 'guilty' || v === 'plaintiff') && k.status === 'open' && !s ? 'Waiting for the ' + (v === 'plaintiff' ? 'judgment.' : 'sentence.') : esc(st || (k.status !== 'open' ? 'Case ' + k.status + (k.closedAt ? ' on ' + date(k.closedAt) : '') : ''))}</span>
      ${c.sentence && !s ? `<button class="btn small gold" data-a="sentence">${v === 'plaintiff' ? '§ Enter the judgment' : '§ Pass sentence'}</button>` : ''}
      ${k.parent ? `<span class="lnk" data-case="${k.parent.id}">Appeal of ${esc(k.parent.number)}</span>` : ''}
      ${(k.appeals || []).map((a) => `<span class="lnk" data-case="${a.id}">Appeal ${esc(a.number)} (${esc(a.status === 'open' ? 'open' : D.VERDICT[a.verdict] || a.status)})</span>`).join(' ')}</div>`;
  }

  // ---------------------------------------------------------------- tabs
  const TAB = {};
  function chargeRows(k, opts) {
    opts = opts || {};
    const list = k.charges || [];
    if (!list.length) return empty('No charges', '§');
    let fine = 0, months = 0;
    const rows = list.map((g) => {
      const live = g.disposition !== 'dropped' && g.disposition !== 'dismissed' && g.disposition !== 'not_guilty' && g.disposition !== 'reversed';
      if (live) { fine += g.fine * g.count; months += g.months * g.count; }
      return `<div class="chg ${g.disposition === 'dropped' ? 'dropped' : ''}"><span class="code">${esc(g.code)}</span><span class="cat c-${esc(g.category)}">${esc(cap(g.category))}</span>
        <div class="li-main"><b>${esc(g.title)}${g.count > 1 ? ' ×' + g.count : ''}</b><span class="hint">${money(g.fine)} · ${g.months} mo each${g.plea && g.plea !== 'none' ? ' · plea ' + esc(cap(g.plea)) : ''}</span></div>
        <span class="disp ${esc(g.disposition)}">${esc(cap(g.disposition))}</span></div>`;
    }).join('');
    return rows + `<div class="totals"><span>Penal code guide for live charges:</span><span><b>${money(fine)}</b></span><span><b>${months} months</b></span></div>`;
  }
  TAB.public = (b, k) => {
    b.innerHTML = `<div class="cols-main"><div><div class="card"><div class="card-title">Charges</div>${chargeRows(k)}</div>
      <div class="card"><div class="card-title">Public filings</div>${(k.filings || []).length ? k.filings.map((f) => `<div class="li"><div class="li-main"><b>${esc(f.title)}</b><span class="hint">${esc(cap(f.kind))} · ${esc(f.byLabel || '')} · ${date(f.createdAt)}</span></div>${pill(cap(f.status))}</div>`).join('') : empty('Nothing public on file')}</div></div>
      <div><div class="card"><div class="card-title">Hearings</div>${hearingList(k, true)}</div><div class="help">You see the public part of this case. The parties and the court see the rest.</div></div></div>`;
  };
  TAB.overview = (b, k) => {
    const c = k.can;
    const next = k.hearings.filter((x) => x.status === 'scheduled' && x.startsAt > Date.now() / 1000 - 7200)[0];
    b.innerHTML = `<div class="cols-main"><div>
        <div class="card"><div class="card-head"><div class="card-title">Summary</div>${c.edit ? '<button class="btn small ghost" data-ed>Edit</button>' : ''}</div>
          <div class="narr" style="white-space:pre-wrap">${k.summary ? esc(k.summary) : '<span class="muted">No summary yet.</span>'}</div></div>
        <div class="card"><div class="card-head"><div class="card-title">Charges</div>${c.charges ? '<button class="btn small ghost" data-ch>Amend charges</button>' : ''}</div>${chargeRows(k)}</div>
      </div><div>
        <div class="card"><div class="card-title">Next hearing</div>${next ? `<div class="li click" data-h="${next.id}"><div class="li-main"><b>${esc(next.title || labelOf(S.lists.hearingKinds, next.kind))}</b><span class="hint">${dateTime(next.startsAt)} · ${esc(next.room)} · ${inTime(next.startsAt)}</span></div></div>` : empty('Nothing scheduled')}
          ${c.schedule ? '<button class="btn small mt" data-sch>▦ Schedule a hearing</button>' : ''}</div>
        <div class="card"><div class="card-title">Latest on the docket</div><div class="tl">${(k.log || []).slice(0, 6).map((l) => `<div class="tl-i"><b>${esc(l.detail || cap(l.what))}</b><span class="hint">${esc(l.byLabel || '')} · ${ago(l.at)}</span></div>`).join('') || empty('Nothing yet')}</div></div>
      </div></div>`;
    const ed = $('[data-ed]', b); if (ed) ed.onclick = () => ACT.edit(k);
    const ch = $('[data-ch]', b); if (ch) ch.onclick = () => ACT.charges(k);
    const sch = $('[data-sch]', b); if (sch) sch.onclick = () => ACT.schedule(k);
    $$('[data-h]', b).forEach((x) => x.onclick = () => D.openHearing(+x.dataset.h));
  };
  function hearingList(k, pub) {
    if (!k.hearings.length) return empty('No hearings yet', '▦');
    return k.hearings.map((x) => `<div class="li ${pub ? '' : 'click'}" data-h="${x.id}"><div class="li-main"><b>${esc(x.title || labelOf(S.lists.hearingKinds, x.kind))}</b>
      <span class="hint">${dateTime(x.startsAt)} · ${esc(x.room)} · ${x.minutes} min${x.judge ? ' · ' + esc(x.judge) : ''}${x.outcome ? ' · ' + esc(x.outcome) : ''}</span></div>
      ${x.lines ? pill(x.lines + ' transcript lines') : ''} ${pill(cap(x.status), x.status === 'scheduled' ? 'gold' : x.status === 'held' ? 'on' : 'off')}</div>`).join('');
  }
  TAB.hearings = (b, k) => {
    b.innerHTML = `<div class="card"><div class="card-head"><div class="card-title">Hearings</div>${k.can.schedule ? '<button class="btn small gold" data-sch>▦ Schedule</button>' : ''}</div>${hearingList(k)}</div>`;
    const sch = $('[data-sch]', b); if (sch) sch.onclick = () => ACT.schedule(k);
    $$('[data-h]', b).forEach((x) => x.onclick = () => D.openHearing(+x.dataset.h));
  };
  const VIS = { public: 'Public', parties: 'Parties', prosecution: 'Prosecution only', defense: 'Defense only', court: 'Court only' };
  TAB.filings = (b, k) => {
    const list = k.filings || [];
    b.innerHTML = `<div class="v-head"><div class="hint">Motions, briefs, exhibits and orders. Click a picture to enlarge it.</div>${k.can.file ? '<button class="btn small gold" data-new>＋ File a document</button>' : ''}</div>
      ${list.length ? `<div class="files mt">${list.map((f) => `<div class="file">
        ${f.hasImage ? `<div class="thumb" data-img="${f.id}" data-cap="${esc((f.exhibitNo ? f.exhibitNo + ' · ' : '') + f.title)}"><div class="spin"></div></div>` : `<div class="thumb doc">${f.kind === 'order' ? '⚖' : f.kind === 'exhibit' ? '▣' : '📄'}</div>`}
        <div class="f-body"><div class="row gap-s">${f.exhibitNo ? `<span class="exh">${esc(f.exhibitNo)}</span>` : ''}<span class="f-title flex1">${esc(f.title)}</span></div>
          <span class="hint">${esc(cap(f.kind))} · ${esc(f.byLabel || '')} · ${date(f.createdAt)}</span>
          ${f.body ? `<div class="f-text">${esc(f.body)}</div>` : ''}
          ${f.ruling ? `<div class="hint">Ruling: ${esc(f.ruling)}${f.ruledByName ? ' — ' + esc(f.ruledByName) : ''}</div>` : ''}
          <div class="f-foot">${pill(cap(f.status), f.status === 'pending' ? 'warn' : ['granted', 'admitted'].includes(f.status) ? 'on' : ['denied', 'excluded', 'struck'].includes(f.status) ? 'bad' : '')} ${pill(VIS[f.visibility] || f.visibility, 'off')}
            ${f.body && f.body.length > 160 ? `<button class="btn small ghost" data-read="${f.id}">Read</button>` : ''}
            ${k.can.rule && (f.status === 'pending' || f.kind === 'exhibit' && f.status === 'filed') ? `<button class="btn small" data-rule="${f.id}">Rule</button>` : ''}</div></div></div>`).join('')}</div>` : empty('Nothing filed yet', '📄')}
      ${(k.evidence || []).length && k.can.file ? `<div class="card mt"><div class="card-title">Police evidence you can enter as an exhibit</div>${k.evidence.map((e) => `<div class="li"><div class="li-main"><b>${esc(e.code || '#' + e.id)} · ${esc(e.label)}</b><span class="hint">${esc(cap(e.kind))}${e.result ? ' · ' + esc(e.result) : ''}</span></div><button class="btn small" data-ev="${e.id}" data-evl="${esc(e.label)}">Enter as exhibit</button></div>`).join('')}</div>` : ''}`;
    D.lazyThumbs(b, 'filingImage', (el) => ({ id: +el.dataset.img }));
    const nb = $('[data-new]', b); if (nb) nb.onclick = () => ACT.file(k);
    $$('[data-rule]', b).forEach((x) => x.onclick = () => ACT.rule(k, list.find((f) => f.id === +x.dataset.rule)));
    $$('[data-read]', b).forEach((x) => x.onclick = () => { const f = list.find((y) => y.id === +x.dataset.read); modal(`<div class="m-title">${esc(f.title)}</div><div class="narr" style="white-space:pre-wrap">${esc(f.body)}</div><div class="row end"><button class="btn" data-x>Close</button></div>`, null, 'wide'); });
    $$('[data-ev]', b).forEach((x) => x.onclick = () => ACT.file(k, { evidenceId: +x.dataset.ev, title: x.dataset.evl }));
  };
  const PLEA_ST = { offered: 'warn', accepted: 'gold', approved: 'on', rejected: 'bad', refused: 'bad', withdrawn: 'off' };
  TAB.pleas = (b, k) => {
    const c = k.can, list = k.pleas || [];
    const chg = new Map((k.charges || []).map((g) => [g.id, g]));
    b.innerHTML = `<div class="v-head"><div class="hint">The prosecution offers; the defense (or the defendant in /${esc(S.lists.portal || 'court')}) answers; the judge approves.</div>${c.plea ? '<button class="btn small gold" data-new>✍ Offer a plea deal</button>' : ''}</div>
      ${list.length ? list.map((p) => `<div class="card mt"><div class="card-head"><div class="card-title">Plea offer · ${date(p.createdAt)}</div>${pill(cap(p.status), PLEA_ST[p.status])}</div>
        <div class="narr" style="white-space:pre-wrap">${esc(p.terms)}</div>
        <div class="row mt">${p.fine ? pill(money(p.fine) + ' fine') : ''}${p.months ? pill(p.months + ' months') : ''}${p.service ? pill(p.service + ' service tasks') : ''}${p.probationDays ? pill(p.probationDays + ' days probation') : ''}</div>
        <div class="hint mt">Pleads to: ${(p.charges || []).map((id) => { const g = chg.get(id); return g ? esc(g.code + ' ' + g.title) : '#' + id; }).join(', ') || '—'}</div>
        <div class="hint">Offered by ${esc(p.offeredByLabel || '')}${p.respondedByName ? ' · answered by ' + esc(p.respondedByName) : ''}${p.decidedByName ? ' · decided by ' + esc(p.decidedByName) : ''}${p.note ? ' · “' + esc(p.note) + '”' : ''}</div>
        <div class="row end">
          ${p.status === 'offered' && c.pleaRespond ? `<button class="btn small danger" data-p="reject" data-id="${p.id}">Reject</button><button class="btn small ok" data-p="accept" data-id="${p.id}">Accept</button>` : ''}
          ${(p.status === 'offered' || p.status === 'accepted') && k.side === 'prosecution' ? `<button class="btn small ghost" data-p="withdraw" data-id="${p.id}">Withdraw</button>` : ''}
          ${p.status === 'accepted' && c.pleaApprove ? `<button class="btn small danger" data-p="refuse" data-id="${p.id}">Refuse</button><button class="btn small gold" data-p="approve" data-id="${p.id}">Approve &amp; sentence</button>` : ''}
        </div></div>`).join('') : empty('No plea deals offered', '✍')}`;
    const nb = $('[data-new]', b); if (nb) nb.onclick = () => ACT.plea(k);
    $$('[data-p]', b).forEach((x) => x.onclick = () => ACT.pleaAct(k, +x.dataset.id, x.dataset.p, x));
  };
  const FEE_ST = { unpaid: 'warn', paying: 'warn', paid: 'on', refunded: 'off', void: 'off' };
  TAB.money = (b, k) => {
    const fees = k.fees || [], sent = k.sentences || [];
    b.innerHTML = `<div class="cols2">
      <div class="card"><div class="card-head"><div class="card-title">Bail</div>${k.can.bail ? '<button class="btn small" data-bail>Manage bail</button>' : ''}</div>
        <div class="kv"><dt>Status</dt><dd>${bailText(k)}</dd>${k.bailAmount ? `<dt>Amount</dt><dd>${money(k.bailAmount)} <span class="hint">(or a ${money(k.bond)} bond, ${S.lists.bondPercent || 10}%, kept by the court)</span></dd>` : ''}</div>
        <div class="help mt">Bail paid in full is returned to whoever paid it when the case ends. A bond is cheaper but never returned. Forfeit bail when the defendant misses court.</div></div>
      <div class="card"><div class="card-title">Sentences and judgments</div>${sent.length ? sent.map((s) => `<div class="li"><div class="li-main"><b>${esc(cap(s.source))} · ${date(s.createdAt)}</b><span class="hint">${[s.fine ? money(s.fine) + ' fine' : '', s.months ? s.months + ' months' + (s.jailed ? ' (jailed)' : '') : '', s.service ? s.service + ' tasks' : '', s.probationDays ? s.probationDays + ' days probation' : '', s.restitution ? money(s.restitution) + ' restitution' : ''].filter(Boolean).join(' · ') || 'No penalty'}${s.notes ? ' · ' + esc(s.notes) : ''}</span></div>${pill(cap(s.status), s.status === 'active' ? 'gold' : 'off')}</div>`).join('') : empty('None yet')}</div>
    </div>
    <div class="card mt"><div class="card-title">Bills on this case</div>${fees.length ? `<table><thead><tr><th>Bill</th><th>For</th><th class="num">Amount</th><th>Due</th><th>Status</th></tr></thead><tbody>${fees.map((f) => `<tr><td>${esc(cap(f.kind))} #${f.id}</td><td>${esc(f.reason || '')}</td><td class="num">${money(f.amount)}</td><td>${f.dueAt ? date(f.dueAt) : '—'}</td><td>${pill(cap(f.status), FEE_ST[f.status])}${f.method ? ' <span class="hint">' + esc(f.method) + '</span>' : ''}</td></tr>`).join('')}</tbody></table>` : empty('No bills')}</div>`;
    const bb = $('[data-bail]', b); if (bb) bb.onclick = () => ACT.bail(k);
  };
  const SUB_ST = { requested: 'warn', issued: 'gold', served: 'gold', complied: 'on', ignored: 'bad', denied: 'off', quashed: 'off' };
  TAB.subpoenas = (b, k) => {
    const c = k.can, list = k.subpoenas || [];
    b.innerHTML = `<div class="v-head"><div class="hint">A party asks; the judge issues. The person is told in their court notices.</div>${c.subpoena ? '<button class="btn small gold" data-new>✉ Subpoena someone</button>' : ''}</div>
      <div class="card mt">${list.length ? list.map((s) => `<div class="li"><div class="li-main"><b class="lnk" data-person="${s.charId}">${esc(s.name || '#' + s.charId)}</b><span class="hint">${s.kind === 'documents' ? 'Produce documents' : 'Appear in court'}${s.details ? ' · ' + esc(s.details) : ''} · asked by ${esc(s.requestedByName || '?')} · ${date(s.createdAt)}</span></div>
        ${pill(cap(s.status), SUB_ST[s.status])}
        ${s.status === 'requested' && c.subpoenaIssue ? `<button class="btn small" data-s="deny" data-id="${s.id}">Deny</button><button class="btn small gold" data-s="issue" data-id="${s.id}">Issue</button>` : ''}
        ${(s.status === 'issued' || s.status === 'served') && c.subpoenaServe ? `${s.status === 'issued' ? `<button class="btn small" data-s="served" data-id="${s.id}">Served</button>` : ''}<button class="btn small ok" data-s="complied" data-id="${s.id}">Complied</button><button class="btn small danger" data-s="ignored" data-id="${s.id}">Ignored</button>` : ''}
        ${(s.status === 'issued' || s.status === 'served') && c.subpoenaIssue ? `<button class="btn small ghost" data-s="quash" data-id="${s.id}">Quash</button>` : ''}</div>`).join('') : empty('No subpoenas', '✉')}</div>`;
    const nb = $('[data-new]', b); if (nb) nb.onclick = () => ACT.subpoena(k);
    $$('[data-s]', b).forEach((x) => x.onclick = () => busy(x, async () => { said(await call('subpoenaAct', { id: +x.dataset.id, act: x.dataset.s }), 'Subpoena ' + x.dataset.s) && rerender(); }));
  };
  TAB.discovery = (b, k) => {
    const rp = k.report, ev = k.evidence || [];
    b.innerHTML = `<div class="cols-main"><div>
      <div class="card"><div class="card-title">MDT report</div>${rp ? `<div class="hint">#${rp.id} · ${esc(cap(rp.type))} · ${esc(rp.dept || '')} · ${esc(rp.author || '')} · ${date(rp.createdAt)}${rp.location ? ' · ' + esc(rp.location) : ''}</div>
        <div class="v-title mt" style="font-size:18px">${esc(rp.title || '')}</div><div class="narr mt" style="white-space:pre-wrap">${esc(rp.body || '')}</div>` : empty('This case did not come from an MDT report', '◌')}</div></div>
      <div><div class="card"><div class="card-title">Police case evidence${k.mdtCase ? ' · ' + esc(k.mdtCase.number) : ''}</div>
        ${ev.length ? ev.map((e) => `<div class="li">${e.hasPhoto ? `<div class="pm-photo" data-img="${e.id}" data-cap="${esc(e.label)}"></div>` : ''}<div class="li-main"><b>${esc(e.code || '#' + e.id)} · ${esc(e.label)}</b><span class="hint">${esc(cap(e.kind))} · ${esc(cap(e.status || ''))}${e.result ? ' · ' + esc(e.result) : ''}${e.note ? ' · ' + esc(e.note) : ''}</span></div></div>`).join('') : empty(k.mdtCaseId ? 'No evidence logged on the police case' : 'No police case linked', '▣')}</div></div></div>`;
    D.lazyThumbs(b, 'evidenceImage', (el) => ({ caseId: k.id, id: +el.dataset.img }));
  };
  TAB.docket = (b, k) => {
    b.innerHTML = `<div class="card"><div class="card-title">Docket (everything that happened, newest first)</div><div class="tl">${(k.log || []).map((l) => `<div class="tl-i"><b>${esc(l.detail || cap(l.what))}</b><span class="hint">${esc(l.byLabel || 'System')} · ${dateTime(l.at)}</span></div>`).join('') || empty('Empty')}</div></div>`;
  };

  // ---------------------------------------------------------------- actions
  const done = (r, txt) => { const a = answer(r, txt); if (a === true) setTimeout(rerender, 50); return a; };
  const ACT = {};
  ACT.edit = (k) => form('Edit the case', [
    { k: 'title', label: 'Title', value: k.title, req: true, span2: true },
    { k: 'summary', label: 'Summary', type: 'textarea', value: k.summary || '', rows: 8, span2: true }],
  { size: 'wide', onSubmit: async (v) => done(await call('caseUpdate', { id: k.id, title: v.title, summary: v.summary }), 'Saved') });

  async function assign(k, field, role, label, cur, curName) {
    const f = await memberField('who', label, role, cur, curName);
    const fields = [f];
    if (field === 'defenseCharId') fields.push({ k: 'kind', label: 'Representation', type: 'select', value: k.defenseKind && k.defenseKind !== 'none' ? k.defenseKind : (R().defender ? 'public' : 'private'), opts: [{ v: 'public', l: 'Public defender' }, { v: 'private', l: 'Private attorney' }, { v: 'self', l: 'Self-represented' }], span2: true });
    const intro = field === 'defenseCharId' ? 'A private attorney needs an active bar license and the defendant on their client list.' : '';
    form(`${label} for ${k.number}`, fields, {
      intro, yes: 'Save', onReady: (card) => {
        const row = document.createElement('div'); row.className = 'row';
        row.innerHTML = `<button type="button" class="btn small ghost">Put me on it</button>`;
        $('.grid', card).appendChild(row);
        row.firstChild.onclick = async () => { const d = { id: k.id }; d[field] = S.me.charId; if (field === 'defenseCharId') d.defenseKind = $('#f-kind', card).value; const r = await call('caseUpdate', d); if (r.ok) { D.closeModal(); toast('Assigned to you', 'ok'); rerender(); } else $('#f-err', card).textContent = r.why; };
      }, onSubmit: async (v) => {
        const d = { id: k.id }; const who = pickedId(v.who);
        d[field] = who || false;
        if (field === 'defenseCharId') { d.defenseKind = v.kind; if (v.kind === 'self') d.defenseCharId = false; }
        return done(await call('caseUpdate', d), 'Saved');
      } });
  }
  ACT.assignJudge = (k) => assign(k, 'judgeCharId', 'judge', 'Judge', k.judgeCharId, k.judge);
  ACT.assignProsecutor = (k) => assign(k, 'prosecutorCharId', 'prosecutor', 'Prosecutor', k.prosecutorCharId, k.prosecutor);
  ACT.assignDefense = (k) => assign(k, 'defenseCharId', 'defender', 'Defense attorney', k.defenseCharId, k.defense);
  ACT.pleaEntry = (k) => form('Enter the plea', [{ k: 'plea', label: 'The defendant pleads', type: 'choice', value: k.plea && k.plea !== 'none' ? k.plea : null, span2: true,
    opts: [{ v: 'guilty', l: 'Guilty' }, { v: 'not_guilty', l: 'Not guilty' }, { v: 'no_contest', l: 'No contest' }] }],
  { onSubmit: async (v) => v.plea ? done(await call('caseUpdate', { id: k.id, plea: v.plea }), 'Plea entered') : 'Pick a plea' });

  ACT.charges = async (k) => {
    let picker;
    const live = (k.charges || []);
    modal(`<div class="m-title"><span class="m-ico">§</span>Amend charges · ${esc(k.number)}</div>
      <div class="card-title mt">On the case</div>
      ${live.map((g) => `<div class="chg ${g.disposition === 'dropped' ? 'dropped' : ''}"><span class="code">${esc(g.code)}</span><div class="li-main"><b>${esc(g.title)}</b></div>
        ${g.disposition === 'pending' ? `<input type="number" min="1" max="20" value="${g.count}" data-cnt="${g.id}" style="width:64px"> <label class="ck-item"><input type="checkbox" data-drop="${g.id}"> Drop</label>` : g.disposition === 'dropped' ? `<label class="ck-item"><input type="checkbox" data-restore="${g.id}"> Restore</label>` : `<span class="disp">${esc(g.disposition)}</span>`}</div>`).join('') || '<div class="hint">None yet</div>'}
      <div class="card-title mt">Add charges</div><div data-cp></div>
      <div class="form-err" data-err></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn gold" data-ok>Save charges</button></div>`, async (card, closeIt) => {
      picker = await chargePicker($('[data-cp]', card), []);
      const ok = $('[data-ok]', card);
      ok.onclick = () => busy(ok, async () => {
        const counts = {}; let changed = false;
        $$('[data-cnt]', card).forEach((i) => { const g = live.find((x) => x.id === +i.dataset.cnt); if (g && +i.value !== g.count) { counts[g.id] = +i.value; changed = true; } });
        const d = { id: k.id, add: picker.get(), drop: $$('[data-drop]:checked', card).map((i) => +i.dataset.drop), restore: $$('[data-restore]:checked', card).map((i) => +i.dataset.restore) };
        if (changed) d.counts = counts;
        const r = await call('caseCharges', d);
        if (!r.ok) { $('[data-err]', card).textContent = r.why; return; }
        closeIt(); toast('Charges amended', 'ok'); rerender();
      });
    }, 'wide');
  };

  ACT.schedule = (k) => D.hearingForm({ caseId: k.id, judgeCharId: k.judgeCharId, number: k.number, stage: k.stage });

  ACT.file = (k, pre) => {
    pre = pre || {};
    const kinds = (S.lists.filingKinds || []).filter((f) => (f.key !== 'order' || R().judge));
    const visOpts = [{ v: 'parties', l: 'Parties and the court' }, { v: 'public', l: 'Public' }];
    if (k.side === 'prosecution' || k.side === 'court') visOpts.push({ v: 'prosecution', l: 'Prosecution only' });
    if (k.side === 'defense' || k.side === 'court') visOpts.push({ v: 'defense', l: 'Defense only' });
    if (k.side === 'court') visOpts.push({ v: 'court', l: 'Court only' });
    let pic = null;
    form(pre.evidenceId ? 'Enter evidence as an exhibit' : 'File a document', [
      { k: 'kind', label: 'Kind', type: 'select', value: pre.evidenceId ? 'exhibit' : 'motion', opts: kinds.map((f) => ({ v: f.key, l: f.label })) },
      { k: 'visibility', label: 'Who may read it', type: 'select', value: 'parties', opts: visOpts },
      { k: 'title', label: 'Title', req: true, span2: true, value: pre.title || '', placeholder: 'Motion to suppress the dashcam video' },
      { k: 'body', label: 'Text', type: 'textarea', rows: 6, span2: true, max: 8000, placeholder: 'What you ask the court, or what the exhibit shows…' },
      pre.evidenceId ? { k: 'ev', type: 'html', span2: true, html: '<div class="help">The police evidence (and its photo, when it has one) is attached as the next exhibit number.</div>' }
        : { k: 'pic', label: 'Picture (optional)', type: 'html', span2: true, html: '<div class="lbl">Picture <span class="hint">· optional: a photo exhibit, a scanned document</span></div><div data-pic class="mt"></div>' }],
    { size: 'wide', yes: 'File it', onReady: (card) => { const p = $('[data-pic]', card); if (p) pic = D.picture(p, { roll: true }); },
      onSubmit: async (v) => {
        const d = { caseId: k.id, kind: v.kind, visibility: v.visibility, title: v.title, body: v.body };
        if (pre.evidenceId) d.evidenceId = pre.evidenceId;
        else if (pic && pic.get()) Object.assign(d, pic.get());
        const r = await call('filingSave', d);
        return done(r, r.ok && r.data.exhibitNo ? `Filed as exhibit ${r.data.exhibitNo}` : 'Filed');
      } });
  };
  ACT.rule = (k, f) => {
    const ex = f.kind === 'exhibit';
    form(`Rule on: ${f.title}`, [
      { k: 'ruling', label: 'Ruling', type: 'choice', span2: true, opts: ex ? [{ v: 'admitted', l: 'Admit' }, { v: 'excluded', l: 'Exclude' }, { v: 'struck', l: 'Strike' }]
        : [{ v: 'granted', l: 'Grant' }, { v: 'denied', l: 'Deny' }, { v: 'withdrawn', l: 'Withdrawn' }] },
      { k: 'note', label: 'Reason', type: 'textarea', rows: 3, span2: true, max: 500 }],
    { onSubmit: async (v) => v.ruling ? done(await call('filingRule', { id: f.id, ruling: v.ruling, note: v.note }), 'Ruling entered') : 'Pick a ruling' });
  };

  ACT.plea = (k) => {
    const live = (k.charges || []).filter((g) => g.disposition === 'pending');
    form('Offer a plea deal', [
      { k: 'ch', type: 'html', span2: true, html: `<div class="lbl">They plead guilty to <span class="hint">· the rest are dropped</span></div><div class="ck-list mt">${live.map((g) => `<label class="ck-item"><input type="checkbox" data-g="${g.id}" data-f="${g.fine * g.count}" data-m="${g.months * g.count}"> <span class="code" style="font-family:monospace;font-weight:700">${esc(g.code)}</span> ${esc(g.title)}${g.count > 1 ? ' ×' + g.count : ''} <span class="hint">${money(g.fine * g.count)} · ${g.months * g.count} mo</span></label>`).join('') || '<div class="hint">No live charges</div>'}</div><div class="hint" data-guide></div>` },
      { k: 'fine', label: 'Fine', type: 'money', maxv: (S.lists.sentence || {}).maxFine },
      { k: 'months', label: 'Jail (months)', type: 'number', maxv: (S.lists.sentence || {}).maxMonths },
      { k: 'service', label: 'Community service (tasks)', type: 'number', maxv: (S.lists.sentence || {}).maxService },
      { k: 'probationDays', label: 'Probation (days)', type: 'number', maxv: (S.lists.sentence || {}).maxProbationDays },
      { k: 'terms', label: 'Terms (what they read)', type: 'textarea', rows: 3, span2: true, req: true, max: 1000, placeholder: 'Plead guilty to reckless driving; the evading charge is dropped. $1,500 fine, no jail.' }],
    { size: 'wide', yes: 'Send the offer', onReady: (card) => {
      const upd = () => { let f = 0, m = 0; $$('[data-g]:checked', card).forEach((i) => { f += +i.dataset.f; m += +i.dataset.m; }); $('[data-guide]', card).textContent = f || m ? `Penal code guide for these: ${money(f)} · ${m} months` : ''; };
      $$('[data-g]', card).forEach((i) => i.onchange = upd);
    }, onSubmit: async (v, card) => {
      const charges = $$('[data-g]:checked', card).map((i) => +i.dataset.g);
      if (!charges.length) return 'Pick the charges they plead to';
      return done(await call('pleaOffer', { caseId: k.id, charges, terms: v.terms, fine: v.fine, months: v.months, service: v.service, probationDays: v.probationDays }), 'Plea offer sent');
    } });
  };
  ACT.pleaAct = async (k, id, act, btnEl) => {
    const words = { accept: ['Accept the plea offer', 'The judge still has to approve it.', 'Accept'], reject: ['Reject the plea offer', '', 'Reject'], withdraw: ['Withdraw the offer', '', 'Withdraw'],
      approve: ['Approve the plea deal', 'The agreed sentence is applied now and the case closes.', 'Approve and sentence'], refuse: ['Refuse the plea deal', 'The case goes on.', 'Refuse'] };
    const w = words[act];
    const v = await form(w[0], [{ k: 'note', label: act === 'accept' || act === 'approve' ? 'Note (optional)' : 'Reason', type: 'textarea', rows: 3, span2: true, max: 300 }],
      { intro: esc(w[1]), yes: w[2], danger: act === 'reject' || act === 'refuse', onSubmit: async (vv) => {
        const r = await call('pleaAct', { id, act, note: vv.note });
        if (r.ok && r.data && r.data.sentence) toast('Sentenced: ' + r.data.sentence.text, 'ok');
        return done(r, r.data && r.data.sentence ? null : 'Done');
      } });
    return v;
  };

  ACT.verdict = (k) => {
    const civil = k.kind === 'civil';
    const live = (k.charges || []).filter((g) => g.disposition === 'pending');
    const opts = civil ? [{ v: 'plaintiff', l: 'For the plaintiff', d: 'Then set the judgment' }, { v: 'defendant', l: 'For the defendant', d: 'Case closes' }, { v: 'settled', l: 'Settled', d: 'Case closes' }, { v: 'dismissed', l: 'Dismissed', d: 'Case closes' }]
      : [{ v: 'guilty', l: 'Guilty', d: 'Per charge below; then sentence' }, { v: 'not_guilty', l: 'Not guilty', d: 'Acquitted; police fines voided' }, { v: 'dismissed', l: 'Dismissed', d: 'Case closes' }];
    form(`Verdict · ${k.number}`, [
      { k: 'verdict', label: 'Verdict', type: 'choice', span2: true, opts, onChange: (val, card) => { const p = $('[data-per]', card); if (p) p.style.display = val === 'guilty' ? '' : 'none'; } },
      civil ? null : { k: 'per', type: 'html', span2: true, html: `<div data-per style="display:none"><div class="lbl">Guilty of <span class="hint">· untick a charge for not guilty on it</span></div><div class="ck-list mt">${live.map((g) => `<label class="ck-item"><input type="checkbox" checked data-g="${g.id}"> <b style="font-family:monospace">${esc(g.code)}</b> ${esc(g.title)}${g.count > 1 ? ' ×' + g.count : ''}</label>`).join('')}</div></div>` },
      { k: 'note', label: 'Note for the record', type: 'textarea', rows: 3, span2: true, max: 500 }].filter(Boolean),
    { size: 'wide', yes: 'Enter the verdict', onSubmit: async (v, card) => {
      if (!v.verdict) return 'Pick a verdict';
      const d = { caseId: k.id, verdict: v.verdict, note: v.note };
      if (v.verdict === 'guilty') { d.charges = {}; $$('[data-g]', card).forEach((i) => { d.charges[i.dataset.g] = i.checked ? 'guilty' : 'not_guilty'; }); }
      const r = await call('verdict', d);
      if (r.ok && (r.data.verdict === 'guilty' || r.data.verdict === 'plaintiff')) {
        // 1.1.0: the sentence (or judgment) opens straight away with the penal code guide for what they were found guilty of
        setTimeout(async () => {
          const f = await call('case', { id: k.id });
          if (f.ok && f.data.can && f.data.can.sentence) { toast('Verdict entered. Now the ' + (civil ? 'judgment' : 'sentence') + '.', 'ok'); ACT.sentence(f.data); }
        }, 350);
      }
      return done(r, r.ok && r.data.verdict !== 'guilty' && r.data.verdict !== 'plaintiff' ? 'Verdict entered' : null);
    } });
  };
  ACT.sentence = (k) => {
    const civil = k.kind === 'civil';
    let fine = 0, months = 0;
    (k.charges || []).filter((g) => g.disposition === 'guilty').forEach((g) => { fine += g.fine * g.count; months += g.months * g.count; });
    const L = S.lists.sentence || {};
    const fields = civil ? [
      { k: 'restitution', label: 'Award to the plaintiff', type: 'money', req: true, maxv: L.maxFine, span2: true, hint: 'the defendant pays the court; the court pays the plaintiff' },
      { k: 'fine', label: 'Court costs / fine', type: 'money', maxv: L.maxFine },
      { k: 'notes', label: 'Judgment', type: 'textarea', rows: 3, span2: true, max: 500 }]
      : [
        { k: 'guide', type: 'html', span2: true, html: `<div class="help">Penal code guide for the guilty charges: <b>${money(fine)}</b> and <b>${months} months</b>. You may go above or below.</div>` },
        { k: 'fine', label: 'Fine', type: 'money', value: fine, maxv: L.maxFine },
        { k: 'months', label: 'Jail (months)', type: 'number', value: months, maxv: L.maxMonths, hint: 'sent to es_jail now' },
        { k: 'service', label: 'Community service (tasks)', type: 'number', maxv: L.maxService },
        { k: 'probationDays', label: 'Probation (days)', type: 'number', maxv: L.maxProbationDays },
        { k: 'restitution', label: 'Restitution', type: 'money', maxv: L.maxFine },
        { k: 'notes', label: 'Notes', type: 'textarea', rows: 2, span2: true, max: 500 }];
    form(`${civil ? 'Judgment' : 'Sentence'} · ${k.number}`, fields, { size: 'wide', yes: civil ? 'Enter judgment' : 'Pass sentence', intro: k.test ? '<b>Test case:</b> nothing real happens (no jail, no real bills).' : `Fines are due in ${(S.lists.fees || {}).dueDays || 14} days; unpaid ones become an MDT warrant.`,
      onSubmit: async (v) => {
        const r = await call('sentence', Object.assign({ caseId: k.id }, v));
        if (r.ok) toast((civil ? 'Judgment: ' : 'Sentenced: ') + r.data.text + (r.data.jailWhy ? ' · jail: ' + r.data.jailWhy : '') + ' · on the case, the MDT profile and in /' + (S.lists.portal || 'court'), r.data.jailWhy ? 'warn' : 'ok');
        if (r.ok) tabOf[k.id] = 'overview';
        return done(r);
      } });
  };
  ACT.bail = (k) => {
    const posted = k.bailStatus === 'posted', released = posted || k.bailStatus === 'ror';
    const opts = posted || released ? [{ v: 'revoke', l: 'Revoke release', d: posted ? 'Bail is returned' : 'Back in custody' }].concat(posted ? [{ v: 'forfeit', l: 'Forfeit bail', d: 'Missed court: the court keeps it' }] : [])
      : [{ v: 'set', l: 'Set bail', d: 'An amount (or a bond)' }, { v: 'ror', l: 'Own recognizance', d: 'Released free' }, { v: 'deny', l: 'Deny bail', d: 'Held until trial' }];
    form(`Bail · ${k.number}`, [
      { k: 'act', label: 'Decision', type: 'choice', span2: true, opts, value: opts[0].v, onChange: (val, card) => { const a = $('[data-amt]', card); if (a) a.style.display = val === 'set' ? '' : 'none'; } },
      released ? null : { k: 'amt', type: 'html', span2: true, html: `<div data-amt><div class="field"><label>Bail amount</label><div class="money-in"><input type="number" min="1" max="${S.lists.bailMax || 1000000}" id="f-amount" value="${k.bailAmount || ''}"></div></div><div class="hint" data-bond></div></div>` },
      { k: 'note', label: 'Note', type: 'textarea', rows: 2, span2: true, max: 300 }].filter(Boolean),
    { yes: 'Save', onReady: (card) => { const a = $('#f-amount', card); if (a) { const u = () => { $('[data-bond]', card).textContent = a.value ? `Bond: ${money(Math.ceil(a.value * (S.lists.bondPercent || 10) / 100))} (not returned). They pay at the courthouse or in /${S.lists.portal || 'court'}.` : ''; }; a.oninput = u; u(); } },
      onSubmit: async (v, card) => { const d = { caseId: k.id, act: v.act, note: v.note }; if (v.act === 'set') d.amount = +($('#f-amount', card).value || 0); return done(await call('bail', d), 'Bail updated'); } });
  };
  ACT.close = (k) => {
    const pros = k.side === 'prosecution' && !R().judge;
    form(pros ? 'Drop the charges (nolle prosequi)' : `Close ${k.number}`, [
      pros ? null : { k: 'status', label: 'How it ends', type: 'choice', span2: true, value: 'closed', opts: [{ v: 'closed', l: 'Closed', d: 'Finished' }, { v: 'dismissed', l: 'Dismissed', d: 'Pending charges dismissed' }] },
      k.kind === 'civil' ? null : { k: 'voidFines', label: 'Void the police fines and court bills from this case', type: 'check', span2: true, hint: '(dismissal only)' },
      { k: 'reason', label: 'Reason (on the record)', type: 'textarea', rows: 3, span2: true, req: true, max: 500 }].filter(Boolean),
    { danger: true, yes: pros ? 'Drop charges' : 'Close the case', onSubmit: async (v) => done(await call('caseClose', { caseId: k.id, status: pros ? 'dismissed' : v.status, reason: v.reason, voidFines: v.voidFines }), 'Case closed') });
  };
  ACT.reopen = (k) => form(`Reopen ${k.number}`, [{ k: 'reason', label: 'Reason', type: 'textarea', rows: 3, span2: true, req: true, max: 500 }],
    { yes: 'Reopen', onSubmit: async (v) => done(await call('caseReopen', { caseId: k.id, reason: v.reason }), 'Reopened') });
  ACT.appeal = (k) => form(`Appeal ${k.number}`, [{ k: 'reason', label: 'Grounds for the appeal', type: 'textarea', rows: 6, span2: true, req: true, max: 4000, placeholder: 'What the trial court got wrong…' }],
    { size: 'wide', intro: k.side === 'defense' && (S.lists.fees || {}).appeal ? `The defendant is billed the ${money(S.lists.fees.appeal)} appeal fee.` : '', yes: 'File the appeal',
      onSubmit: async (v) => { const r = await call('appealFile', { caseId: k.id, reason: v.reason }); if (r.ok) setTimeout(() => go('case', r.data.id, { parent: 'cases' }), 200); return answer(r, r.ok ? `Appeal ${r.data.number} filed` : null); } });
  ACT.appealRule = (k) => form(`Rule on ${k.number}`, [
    { k: 'ruling', label: 'Ruling', type: 'choice', span2: true, opts: [{ v: 'affirmed', l: 'Affirmed', d: 'The original stands' }, { v: 'reversed', l: 'Reversed', d: 'Conviction undone: fines voided, released' }, { v: 'remanded', l: 'Remanded', d: 'Original case reopens for a new trial' }] },
    { k: 'note', label: 'Opinion', type: 'textarea', rows: 4, span2: true, max: 500 }],
  { size: 'wide', yes: 'Enter ruling', onSubmit: async (v) => v.ruling ? done(await call('appealRule', { caseId: k.id, ruling: v.ruling, note: v.note }), 'Ruling entered') : 'Pick a ruling' });
  ACT.seal = (k) => k.sealed
    ? confirmBox('Unseal the case', `${k.number} becomes visible to the DOJ, police and lawyers again.`, 'Unseal').then(async (y) => { if (y) said(await call('caseSeal', { caseId: k.id, seal: false }), 'Unsealed') && rerender(); })
    : form(`Seal ${k.number}`, [{ k: 'reason', label: 'Court order / reason', type: 'textarea', rows: 3, span2: true, req: true, max: 300 }],
      { intro: 'Only judges, the records office and the case\'s own lawyers will see it.', yes: 'Seal', onSubmit: async (v) => done(await call('caseSeal', { caseId: k.id, seal: true, reason: v.reason }), 'Sealed') });
  ACT.subpoena = (k) => {
    const hs = (k.hearings || []).filter((x) => x.status === 'scheduled');
    form('Subpoena', [
      { k: 'who', label: 'Person', type: 'person', req: true, span2: true },
      { k: 'kind', label: 'They must', type: 'select', opts: [{ v: 'appear', l: 'Appear in court' }, { v: 'documents', l: 'Produce documents' }] },
      { k: 'hearingId', label: 'For the hearing', type: 'select', opts: [{ v: '', l: '— none —' }].concat(hs.map((x) => ({ v: x.id, l: `${x.title} · ${dateTime(x.startsAt)}` }))) },
      { k: 'details', label: 'Details', type: 'textarea', rows: 3, span2: true, max: 500 }],
    { intro: k.can.subpoenaIssue ? 'You are the judge: it is issued at once.' : 'The judge issues it.', yes: k.can.subpoenaIssue ? 'Issue' : 'Ask the judge',
      onSubmit: async (v) => done(await call('subpoenaSave', { caseId: k.id, charId: pickedId(v.who), kind: v.kind, hearingId: v.hearingId ? +v.hearingId : null, details: v.details }), 'Subpoena saved') });
  };
  ACT.bench = (k) => form('Bench warrant', [
    { k: 'reason', label: 'Reason', value: 'Failure to appear', span2: true, req: true, max: 400 },
    { k: 'days', label: 'Valid for (days)', type: 'number', value: 14, min: 1, maxv: 90 }],
  { intro: `An arrest warrant for <b>${esc(k.defendant || 'the defendant')}</b> goes on the MDT now.${k.test ? ' <b>Test case:</b> nothing is sent to the MDT.' : ''}`, yes: 'Issue the warrant', danger: true,
    onSubmit: async (v) => { const r = await call('benchWarrant', { caseId: k.id, reason: v.reason, days: v.days }); return done(r, r.ok ? (r.data.test ? 'Test: no warrant sent' : `Warrant #${r.data.id} is on the MDT`) : null); } });
  D.caseAct = ACT;
})();
