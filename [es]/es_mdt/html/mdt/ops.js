// es_mdt 1.3.0 page parts: Dispatch (911/311 calls), panic, live map, mugshots, Process arrest, announcements, report templates.
// Built on window.MDT (the toolbox app.js shares). The server decides everything; this only draws and asks.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, money, call, post, toast, said, busy, ago, dateTime, modal, confirmBox, personPicker, pill, empty, can, P, go, VIEWS, HOOK } = M;
  const cfg = () => (S.ctx && S.ctx.config) || {};
  const PRI = { 1: ['P1', 'bad', 'Emergency'], 2: ['P2', 'warn', 'Urgent'], 3: ['P3', 'accent', 'Routine'] };
  const KIND = { '911': '911', '311': '311', panic: 'PANIC', officer: 'Officer', alert: 'Alert', medical: 'Medical', shots: 'Shots fired', theft: 'Vehicle theft', backup: 'Backup',
    robbery: 'Robbery', drugs: 'Drugs', explosion: 'Explosion', fight: 'Fight', suspicious: 'Suspicious', down: 'Person down', speeding: 'Speeding' };
  // 2.0.7: critical tier, merged reports, "N responding", search circle, suspect details
  const GRADE_CLS = ['', 'g1', 'g2', 'g3', 'g4', 'g5'];
  const critTag = (c) => c.critical && c.status !== 'closed' ? '<span class="crit-tag" title="Critical: above P1">CRITICAL</span>' : '';
  const repTag = (c) => (c.reports || 1) > 1 ? `<span class="rep-tag" title="Repeat reports merged into this call">×${c.reports} reports</span>` : '';
  const respTag = (c) => c.status === 'closed' ? '' : `<span class="resp-tag${(c.units || []).length ? '' : ' none'}">${(c.units || []).length} responding</span>`;
  const iconOf = (c) => c.icon ? `<span class="c-ico">${esc(c.icon)}</span>` : '';
  const detailsHtml = (d) => {
    if (!d || typeof d !== 'object') return '';
    const out = [];
    if (d.plate) out.push(`<span class="sd"><i>Plate</i><b class="mono">${esc(d.plate)}</b></span>`);
    if (d.vehicle || d.color) out.push(`<span class="sd"><i>Vehicle</i><b>${esc([d.color, d.vehicle].filter(Boolean).join(' '))}</b></span>`);
    if (d.weapon) out.push(`<span class="sd ${GRADE_CLS[d.grade] || ''}"><i>Weapon</i><b>${esc(d.weapon)}</b>${d.gradeLabel ? `<em>${esc(d.gradeLabel)} threat</em>` : ''}</span>`);
    if (d.dir) out.push(`<span class="sd"><i>Heading</i><b>${esc(d.dir)}</b></span>`);
    if (d.desc) out.push(`<span class="sd wide"><i>Suspect</i><b>${esc(d.desc)}</b></span>`);
    return out.length ? `<div class="sdetails">${out.join('')}</div>` : '';
  };
  M.callDetailsHtml = detailsHtml;
  const priPill = (p) => { const x = PRI[p] || PRI[2]; return `<span class="pri p${p}" title="${x[2]}">${x[0]}</span>`; };
  const kindTag = (k) => `<span class="ck k-${esc(k)}">${esc(KIND[k] || k)}</span>`;
  // 2.0.4: call outcomes: the configured list (strings in old configs), a coloured badge for each
  const AUTO_NONE = 'Auto-closed – no response', AUTO_TIMEOUT = 'Auto-closed (timeout)';
  const OUT_FIXED = { [AUTO_NONE.toLowerCase()]: ['#e2557a', '⌛'], [AUTO_TIMEOUT.toLowerCase()]: ['#7c8aa5', '⏱'], expired: ['#7c8aa5', '⏱'] };
  const outs = () => (cfg().outcomes || []).map((o) => (typeof o === 'string' ? { label: o, note: o.toLowerCase() === 'other' ? 'required' : null } : o)).filter((o) => o && o.label);
  const rgb = (hex) => { let h = String(hex || '').replace('#', ''); if (h.length === 3) h = h.split('').map((c) => c + c).join(''); const n = parseInt(h, 16); return isNaN(n) || h.length !== 6 ? null : [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
  const outLook = (o) => {
    const t = String(o || 'Closed'), k = t.toLowerCase();
    const x = outs().find((q) => q.label.toLowerCase() === k);
    const f = OUT_FIXED[k];
    return { text: t, color: (x && x.color) || (f && f[0]) || '#8a93a6', icon: (x && x.icon) || (f && f[1]) || '■' };
  };
  const outBadge = (o, big) => {
    const L = outLook(o), c = rgb(L.color) || [138, 147, 166];
    return `<span class="ob${big ? ' big' : ''}" style="--ob:rgb(${c.join(',')});--obg:rgba(${c.join(',')},.16);--obr:rgba(${c.join(',')},.45)" title="Outcome: ${esc(L.text)}"><span class="ob-i">${esc(L.icon)}</span>${esc(L.text)}</span>`;
  };
  M.outBadge = outBadge;
  const UST = { enroute: ['→', 'En route'], scene: ['✓', 'On scene'] };
  // 2.0.6: went up a priority because nobody attached
  const escTag = (c) => c.escalations > 0 && c.status !== 'closed' ? `<span class="esc-tag" title="Raised ${c.escalations}× · no unit attached in time">↑ Escalated</span>` : '';
  const unitChip = (u) => { const st = UST[u.status]; return `<span class="uchip" style="--gc:${esc(u.color1 || '#3b4a6b')}" title="${esc(u.name)}${st ? ' · ' + st[1] : ''}">${esc(u.callsign || u.name.split(' ')[0])}${st ? ' ' + st[0] : ''}</span>`; };

  // ================================================================ DISPATCH
  const D = { status: 'active', sel: null, list: [] };

  VIEWS.dispatch = async (v, arg) => {
    if (arg) D.sel = +arg;
    const on = S.ctx.onDuty;
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Dispatch</div><div class="hint">911 and 311 calls, panic alarms and calls officers log · updates live</div></div>
      <div class="row">${on ? '<button class="btn" id="d-new" data-probe-press>+ Log a call</button>' : ''}${on ? '<button class="btn panic-btn" id="d-panic" data-probe-press title="Alert every unit on duty">⚠ PANIC</button>' : ''}</div></div>
      <div class="filters"><div class="seg big" id="d-seg"><button data-ds="active" class="${D.status === 'active' ? 'on' : ''}">Active <span class="seg-n" id="d-n"></span></button><button data-ds="closed" class="${D.status === 'closed' ? 'on' : ''}">Closed</button></div>
        <span class="hint">Click a call to see it, attach, route and close it.</span></div>
      <div class="split wide d-split"><div class="res-list" id="d-list"><div class="loading-row"><div class="spin"></div></div></div>
        <div class="split-detail" id="d-detail">${empty('Pick a call', '☎')}</div></div>`;
    $$('[data-ds]', v).forEach((b) => b.onclick = () => { D.status = b.dataset.ds; D.sel = null; go('dispatch'); });
    if ($('#d-new')) $('#d-new').onclick = () => callForm();
    if ($('#d-panic')) $('#d-panic').onclick = () => panicConfirm();
    await dList();
    if (D.sel) dDetail(D.sel);
  };
  HOOK.dispatchRefresh = () => { if (!$('#d-list')) return; dList(true); if (D.sel && $('#d-detail')) dDetail(D.sel, true); };

  async function dList(quiet) {
    const box = $('#d-list'); if (!box) return;
    const r = await call('calls', { status: D.status });
    if (!$('#d-list')) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    D.list = r.data.calls || [];
    if (D.status === 'active' && $('#d-n')) $('#d-n').textContent = D.list.length || '';
    box.innerHTML = D.list.length ? D.list.map((c) => `<div class="call res click p${c.priority}${c.kind === 'panic' ? ' is-panic' : ''}${c.critical && c.status !== 'closed' ? ' is-crit' : ''}${D.sel === c.id ? ' sel' : ''}" data-cpick="${c.id}">
        <div class="c-top">${critTag(c)}${priPill(c.priority)}${kindTag(c.kind)}${escTag(c)}${iconOf(c)}<b class="c-title">#${c.id} ${esc(c.title)}</b>${repTag(c)}<span class="hint c-age" data-age="${c.createdAt}">${ago(c.createdAt)}</span></div>
        ${c.message ? `<div class="c-msg">${esc(c.message)}</div>` : ''}
        <div class="c-foot"><span class="hint">📍 ${esc(c.street || (c.x != null ? 'See the map' : 'No location'))}${c.radius ? ` · ~${c.radius} m search area` : ''}</span>${respTag(c)}<span class="spacer"></span>
          ${c.status === 'closed' ? outBadge(c.outcome) : (c.units.length ? c.units.map(unitChip).join('') : '<span class="pill warn">No units</span>')}
          ${c.notes ? `<span class="hint">✎ ${c.notes}</span>` : ''}</div></div>`).join('')
      : empty(D.status === 'active' ? 'No active calls. Quiet shift.' : 'No closed calls yet', '☎');
    $$('[data-cpick]', box).forEach((el) => el.onclick = () => { D.sel = +el.dataset.cpick; $$('[data-cpick]', box).forEach((x) => x.classList.toggle('sel', x === el)); dDetail(D.sel); });
    if (!quiet && !D.sel && D.list.length && D.status === 'active') { D.sel = D.list[0].id; box.firstElementChild.classList.add('sel'); }
  }

  async function dDetail(id, quiet) {
    const box = $('#d-detail'); if (!box) return;
    if (!quiet) box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('call', { id });
    if (!$('#d-detail') || D.sel !== id) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const c = r.data, active = c.status === 'active', on = S.ctx.onDuty && !S.ctx.readOnly;
    const links = [['report', c.reportId], ['warrant', c.warrantId], ['case', c.caseId]].filter((x) => x[1]);
    box.innerHTML = `<div class="call-head p${c.priority}${c.kind === 'panic' ? ' is-panic' : ''}${c.critical && active ? ' is-crit' : ''}">
        <div class="row">${critTag(c)}${priPill(c.priority)}${kindTag(c.kind)}${escTag(c)}${repTag(c)}${respTag(c)}${active ? pill('Active', 'on') : pill('Closed', 'off') + outBadge(c.outcome, true)}<span class="spacer"></span><span class="hint">${dateTime(c.createdAt)} · ${ago(c.createdAt)}</span></div>
        <div class="v-title">${iconOf(c)}#${c.id} ${esc(c.title)}</div>
        ${c.parent ? `<div class="link-call" data-gocall="${c.parent.id}">⤴ Backup for call <b>#${c.parent.id}</b> ${esc(c.parent.title || '')}${c.parent.status === 'closed' ? ' · closed' : ''}</div>` : ''}
        ${(c.backups || []).length ? `<div class="link-row">${c.backups.map((b) => `<span class="link-call small${b.status === 'closed' ? ' off' : ''}" data-gocall="${b.id}">🚨 Backup #${b.id} · P${b.priority}${b.status === 'closed' ? ' · closed' : ''}</span>`).join('')}</div>` : ''}
        ${c.message ? `<div class="c-say">“${esc(c.message)}”</div>` : ''}
        <div class="facts"><span><i>Location</i>${esc(c.street || '—')}${c.radius ? ` <em class="hint">· search area ~${c.radius} m</em>` : ''}</span><span><i>Caller</i>${esc(c.callerName || '—')}</span><span><i>Phone</i>${esc(c.callerPhone || '—')}</span></div>
        ${detailsHtml(c.details)}
        <div class="link-row cl-links">${links.map(([k, v]) => `<span class="link-call small kept" title="Kept: a linked call is never removed by the call retention">🔗 ${k} #${v}${active || c.canClose ? ` <b data-unlink="${k}" title="Remove the link">×</b>` : ''}</span>`).join('')}
          ${!S.ctx.readOnly && (c.attached || c.canClose) ? '<span class="link-call small ghost" id="cd-link" title="Link a report, warrant or case: the call is then kept for good">＋ Link report / warrant / case</span>' : ''}</div>
        <div class="row">${c.x != null ? '<button class="btn" id="cd-route" data-probe-press>⌖ Set waypoint</button>' : ''}
          ${active && on ? (c.attached ? '<button class="btn ghost" id="cd-detach" data-probe-press>Detach</button>' : '<button class="btn accent" id="cd-attach" data-probe-press title="You and your partner attach together">＋ Attach &amp; route</button>') : ''}
          ${c.canBackup && !S.ctx.readOnly ? '<button class="btn warnb" id="cd-backup" data-probe-press title="A backup call at your position, linked to this one">🚨 Request backup</button>' : ''}
          <span class="spacer"></span>${c.canClose && !S.ctx.readOnly ? '<button class="btn danger" id="cd-close" data-probe-press>Close call</button>' : ''}</div></div>
      <div class="cols2">
        <div class="card"><div class="card-title">Units on this call <span class="hint">${c.units.length || ''}</span></div>${c.units.length ? c.units.map((u) => `<div class="li click" data-person="${u.charId}">${unitChip(u)}<div class="li-main"><b>${esc(u.name)}</b><span class="hint">${esc(u.callsign ? u.callsign + ' · ' : '')}${esc(u.deptShort || 'off duty')}${UST[u.status] ? ' · ' + UST[u.status][1] : ''}</span></div></div>`).join('') : empty('Nobody has attached yet')}</div>
        <div class="card"><div class="card-title">Notes &amp; timeline</div>
          <div class="tl">${(c.notesList || []).map((n) => `<div class="tl-i"><span class="tl-dot"></span><div><b>${esc(n.note)}</b><div class="hint">${esc(n.by)} · ${ago(n.createdAt)}</div></div></div>`).join('') || '<div class="hint">No notes yet.</div>'}
          ${!active ? `<div class="tl-i end"><span class="tl-dot"></span><div><div class="row tight"><b>Closed</b>${outBadge(c.outcome)}</div>${c.closeNote ? `<div class="tl-note">${esc(c.closeNote)}</div>` : ''}<div class="hint">${esc(c.closedByName || 'Automatically')} · ${c.closedAt ? dateTime(c.closedAt) + ' · ' + ago(c.closedAt) : ''}</div></div></div>` : ''}</div>
          ${active && !S.ctx.readOnly ? '<div class="note-add"><input type="text" id="cd-note" maxlength="500" placeholder="Add a note… (Enter)"><button class="btn small" id="cd-note-go">Add</button></div>' : ''}</div>
      </div>`;
    const reload = () => { dList(true); dDetail(id, true); };
    if ($('#cd-route')) $('#cd-route').onclick = (e) => busy(e.currentTarget, async () => said(await call('callRoute', { id }), 'Waypoint set'));
    if ($('#cd-attach')) $('#cd-attach').onclick = (e) => busy(e.currentTarget, async () => { const x = await call('callAttach', { id, route: true }); if (said(x, x.ok && x.data.units > 1 ? 'Attached with your partner · GPS set' : 'Attached · GPS set')) reload(); });
    if ($('#cd-detach')) $('#cd-detach').onclick = (e) => busy(e.currentTarget, async () => { if (said(await call('callDetach', { id }), 'Detached')) reload(); });
    if ($('#cd-close')) $('#cd-close').onclick = () => closeForm(c, reload);
    if ($('#cd-backup')) $('#cd-backup').onclick = (e) => busy(e.currentTarget, async () => {
      const x = await call('callBackup', { id });
      if (said(x, x.ok ? `Backup requested · P${x.data.priority} call #${x.data.id}` : '')) reload();
    });
    $$('[data-gocall]', box).forEach((n) => n.onclick = () => { const to = +n.dataset.gocall; D.sel = to; dList(true); dDetail(to); });
    // 2.0.7: links (report / warrant / case): a linked call is kept by the retention cleanup
    $$('[data-unlink]', box).forEach((n) => n.onclick = async (e) => { e.stopPropagation(); if (said(await call('callLink', { id, kind: n.dataset.unlink, ref: null }), 'Link removed')) reload(); });
    if ($('#cd-link')) $('#cd-link').onclick = () => {
      const close = modal(`<div class="m-title">Link call #${id}</div><p class="m-text hint">A linked call is kept for good (the call retention never removes it).</p>
        <div class="row"><select id="cl-kind"><option value="report">Report</option><option value="warrant">Warrant</option><option value="case">Case</option></select>
        <input type="number" id="cl-ref" min="1" placeholder="Its number (#)"></div>
        <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="cl-go" data-primary>Link</button></div>`);
      const go = async () => { const ref = +($('#cl-ref').value || 0); if (!ref) return toast('Type its number', 'err');
        if (said(await call('callLink', { id, kind: $('#cl-kind').value, ref }), 'Linked')) { close(); reload(); } };
      $('#cl-go').onclick = go; $('#cl-ref').onkeydown = (e) => { if (e.key === 'Enter') go(); };
    };
    const addNote = () => { const inp = $('#cd-note'); const t = inp.value.trim(); if (!t) return; busy($('#cd-note-go'), async () => { if (said(await call('callNote', { id, note: t }))) { inp.value = ''; reload(); } }); };
    if ($('#cd-note-go')) { $('#cd-note-go').onclick = addNote; $('#cd-note').onkeydown = (e) => { if (e.key === 'Enter') { e.preventDefault(); addNote(); } }; }
  }

  // 2.0.4: close a call: pick how it ended (big buttons, 1-6 on the keyboard); Other needs a note
  function closeForm(c, after) {
    const list = outs();
    let pick = null;
    modal(`<div class="m-title">Close call #${c.id}</div>
      <div class="co-call">${priPill(c.priority)}${kindTag(c.kind)}<b>${esc(c.title)}</b><span class="hint">📍 ${esc(c.street || 'No location')}</span></div>
      <div class="field"><label>How did it end?</label><div class="oc-grid" id="co-o">${list.map((o, i) => {
        const col = rgb(o.color) || [138, 147, 166];
        return `<button type="button" class="oc" data-o="${esc(o.label)}" style="--ob:rgb(${col.join(',')});--obg:rgba(${col.join(',')},.14)"><span class="oc-k">${i + 1}</span><span class="oc-i">${esc(o.icon || '■')}</span><span class="oc-l">${esc(o.label)}</span>${o.note === 'required' ? '<span class="oc-req">note needed</span>' : ''}</button>`; }).join('')}</div></div>
      <div class="field"><label>Closing note <span class="hint" id="co-nh">(optional)</span></label><textarea id="co-n" maxlength="500" placeholder="What happened, report number…"></textarea><div class="co-err" id="co-err"></div></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn danger" id="co-go" data-primary disabled>Pick an outcome</button></div>`, (card, closeIt) => {
      const go_ = $('#co-go', card), note = $('#co-n', card), err = $('#co-err', card), nh = $('#co-nh', card);
      const needNote = () => { const o = list.find((x) => x.label === pick); return !!(o && o.note === 'required'); };
      const check = () => {
        const need = needNote(), short = need && note.value.trim().length < 3;
        nh.textContent = need ? '(required)' : '(optional)'; nh.classList.toggle('req', need);
        note.placeholder = need ? 'Say what happened (required for Other)…' : 'What happened, report number…';
        err.textContent = pick && short ? 'Add a short note for “' + pick + '”.' : '';
        go_.disabled = !pick || short;
        go_.textContent = pick ? 'Close as ' + pick : 'Pick an outcome';
      };
      const choose = (label) => { pick = label; $$('[data-o]', card).forEach((x) => x.classList.toggle('on', x.dataset.o === label)); check(); if (needNote()) note.focus(); };
      $$('[data-o]', card).forEach((b) => b.onclick = () => choose(b.dataset.o));
      note.oninput = check;
      card.addEventListener('keydown', (e) => { if (e.target === note) return; const n = +e.key; if (n >= 1 && n <= list.length) { e.preventDefault(); choose(list[n - 1].label); } });
      go_.onclick = (e) => busy(e.currentTarget, async () => { if (said(await call('callClose', { id: c.id, outcome: pick, note: note.value }), 'Call closed · ' + pick)) { closeIt(); after(); } });
      check();
    });
  }

  function callForm() {
    let pri = 2;
    modal(`<div class="m-title">Log a call</div><p class="hint">For something you saw or were told in person. It is placed at your position and you are attached to it.</p>
      <div class="field"><label>Priority</label><div class="seg" id="cf-p"><button data-p="1">P1 Emergency</button><button data-p="2" class="on">P2 Urgent</button><button data-p="3">P3 Routine</button></div></div>
      <div class="field"><label>Title</label><input id="cf-t" maxlength="120" placeholder="Shots fired, Grove St"></div>
      <div class="field"><label>Details</label><textarea id="cf-m" maxlength="500" placeholder="What is happening, suspects, vehicles…"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="cf-go" data-primary>Log call</button></div>`, (card, closeIt) => {
      $$('[data-p]', card).forEach((b) => b.onclick = () => { pri = +b.dataset.p; $$('[data-p]', card).forEach((x) => x.classList.toggle('on', x === b)); });
      $('#cf-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('callCreate', { priority: pri, title: $('#cf-t', card).value, message: $('#cf-m', card).value });
        if (said(r, 'Call #' + (r.data && r.data.id) + ' logged')) { closeIt(); D.status = 'active'; D.sel = r.data.id; go('dispatch'); }
      });
    });
  }

  async function panicConfirm() {
    if (!await confirmBox('Press panic?', 'Every officer on duty, in every department, gets your callsign and location, a flashing blip and a priority-1 call.', '⚠ Send panic', true)) return;
    const r = await post('panicBtn', {});
    said(r, 'Panic sent');
  }

  // ages tick without reloading
  setInterval(() => { $$('[data-age]').forEach((el) => { el.textContent = ago(+el.dataset.age); }); }, 15000);

  // ================================================================ DASHBOARD (calls + announcements + panic)
  HOOK.dashboard = (v, x) => {
    const host = $('#dash-ops', v); if (!host) return;
    if (S.ctx.onDuty && !S.ctx.readOnly) {
      const head = $('.v-head', v);
      if (head) head.insertAdjacentHTML('beforeend', '<button class="btn panic-btn" id="dash-panic" data-probe-press title="Alert every unit on duty">⚠ PANIC</button>');
      if ($('#dash-panic')) $('#dash-panic').onclick = () => panicConfirm();
    }
    const calls = x.calls || [], ann = x.announcements || [];
    host.className = 'cols2';
    host.innerHTML = `<div class="card"><div class="card-head"><div class="card-title">Active calls ${calls.length ? `<span class="t-badge bad">${calls.length}</span>` : ''}</div><button class="btn small ghost" data-go="dispatch">Dispatch →</button></div>
        ${calls.length ? calls.map((c) => `<div class="li click call-li p${c.priority}" data-dcall="${c.id}">${priPill(c.priority)}${kindTag(c.kind)}<div class="li-main"><b>#${c.id} ${esc(c.title)}</b><span class="hint">📍 ${esc(c.street || '—')} · <span data-age="${c.createdAt}">${ago(c.createdAt)}</span></span></div>${c.units.length ? c.units.slice(0, 3).map(unitChip).join('') : '<span class="pill warn">No units</span>'}</div>`).join('') : empty('No active calls', '☎')}</div>
      <div class="card"><div class="card-head"><div class="card-title">Announcements</div>${x.canAnnounce && !S.ctx.readOnly ? '<button class="btn small accent" id="an-new" data-probe-press>+ Post</button>' : ''}</div>
        ${ann.length ? ann.map(annHtml).join('') : empty('Nothing from command right now', '📣')}</div>`;
    $$('[data-dcall]', host).forEach((el) => el.onclick = () => { D.status = 'active'; go('dispatch', +el.dataset.dcall); });
    if ($('#an-new')) $('#an-new').onclick = () => annForm();
    wireAnn(host);
  };

  // 2.0.4: announcements: priority (Normal / Important / Urgent), a body that keeps its lines, **bold** and "- " bullets
  const LVL = { normal: ['Normal', ''], important: ['Important', '❗'], urgent: ['Urgent', '🚨'] };
  const lvlOf = (a) => (LVL[a && a.level] ? a.level : 'normal');
  const annText = (t) => {
    const lines = esc(t || '').replace(/\*\*([^*\n]+)\*\*/g, '<b>$1</b>').split(/\r?\n/);
    let out = '', inList = false;
    lines.forEach((l) => {
      const m = l.match(/^\s*[-•*]\s+(.*)$/);
      if (m) { if (!inList) { out += '<ul>'; inList = true; } out += `<li>${m[1]}</li>`; return; }
      if (inList) { out += '</ul>'; inList = false; }
      out += l.trim() ? `<p>${l}</p>` : '<p class="gap"></p>';
    });
    return out + (inList ? '</ul>' : '');
  };
  M.annText = annText;
  const annHtml = (a) => { const lv = lvlOf(a); return `<div class="ann lv-${lv}${a.pinned ? ' pinned' : ''}"><div class="ann-top">${a.pinned ? '<span class="a-pin" title="Pinned">📌</span>' : ''}${lv !== 'normal' ? `<span class="ann-lv lv-${lv}">${LVL[lv][1]} ${LVL[lv][0]}</span>` : ''}<b class="ann-title">${esc(a.title)}</b>${a.all ? pill('All departments', 'accent') : ''}<span class="spacer"></span>
      ${a.canEdit && !S.ctx.readOnly ? `<button class="icon-btn" data-apin="${a.id}" title="${a.pinned ? 'Unpin' : 'Pin to the top'}">${a.pinned ? '⇣' : '📌'}</button><button class="icon-btn" data-adel="${a.id}" title="Remove">✕</button>` : ''}</div>
    ${a.body ? `<div class="ann-body">${annText(a.body)}</div>` : ''}
    <div class="ann-meta"><span class="ann-by">✎ ${esc(a.by)}${a.deptShort && !a.all ? ' · ' + esc(a.deptShort) : ''}</span><span title="${dateTime(a.createdAt)}">${dateTime(a.createdAt)} · ${ago(a.createdAt)}</span>${a.expiresAt ? `<span>until ${dateTime(a.expiresAt)}</span>` : ''}</div></div>`; };
  function wireAnn(host) {
    $$('[data-apin]', host).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('announceAct', { id: +b.dataset.apin, act: 'pin' }))) go('dashboard'); }));
    $$('[data-adel]', host).forEach((b) => b.onclick = async () => { if (await confirmBox('Remove announcement', 'Take this announcement down for everyone?', 'Remove', true)) if (said(await call('announceAct', { id: +b.dataset.adel, act: 'remove' }), 'Removed')) go('dashboard'); });
  }
  function annForm() {
    let hours = 0, level = 'normal';
    const H = [[0, 'Never'], [12, '12 hours'], [24, '1 day'], [72, '3 days'], [168, '1 week'], [720, '30 days']];
    modal(`<div class="m-title">Post an announcement</div><p class="hint">Shown on the ${S.ctx.staff ? 'chosen' : esc(S.ctx.dept.short)} Dashboard. Officers on duty get a notification.</p>
      <div class="field"><label>Title</label><input id="af-t" maxlength="120" placeholder="Briefing at 20:00, Mission Row"></div>
      <div class="field"><label>Priority</label><div class="lv-pick" id="af-l">${Object.keys(LVL).map((k) => `<button type="button" data-lv="${k}" class="lv-o lv-${k}${k === 'normal' ? ' on' : ''}"><b>${LVL[k][1]} ${LVL[k][0]}</b><span>${k === 'normal' ? 'On the Dashboard, a quiet notice' : k === 'important' ? 'Highlighted in amber' : 'Red banner + alert for everyone on duty'}</span></button>`).join('')}</div></div>
      <div class="field"><label>Message <span class="hint">· new lines stay · **bold** · start a line with "- " for a list</span></label><textarea id="af-b" maxlength="2000" rows="5" placeholder="Details…"></textarea></div>
      <div class="field"><label>Preview</label><div class="ann-prev" id="af-prev"></div></div>
      <div class="field"><label>Takes itself down after</label><div class="seg" id="af-h">${H.map(([h, l]) => `<button data-h="${h}" class="${h === 0 ? 'on' : ''}">${l}</button>`).join('')}</div></div>
      <div class="row"><label class="chip-t"><input type="checkbox" id="af-pin"><span>📌 Pin to the top</span></label>${S.ctx.staff ? '<label class="chip-t"><input type="checkbox" id="af-all"><span>All departments</span></label>' : ''}</div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="af-go" data-primary>Post</button></div>`, (card, closeIt) => {
      $$('[data-h]', card).forEach((b) => b.onclick = () => { hours = +b.dataset.h; $$('[data-h]', card).forEach((x) => x.classList.toggle('on', x === b)); });
      const prev = () => { $('#af-prev', card).innerHTML = annHtml({ id: 0, title: $('#af-t', card).value || 'Title', body: $('#af-b', card).value, level, by: S.ctx.me.name, deptShort: S.ctx.dept.short, createdAt: Math.floor(Date.now() / 1000), pinned: $('#af-pin', card).checked }); };
      $$('[data-lv]', card).forEach((b) => b.onclick = () => { level = b.dataset.lv; $$('[data-lv]', card).forEach((x) => x.classList.toggle('on', x === b)); prev(); });
      ['#af-t', '#af-b'].forEach((q) => $(q, card).addEventListener('input', prev)); $('#af-pin', card).addEventListener('change', prev); prev();
      $('#af-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const r = await call('announceSave', { title: $('#af-t', card).value, body: $('#af-b', card).value, hours, level, pinned: $('#af-pin', card).checked, all: !!($('#af-all', card) && $('#af-all', card).checked) });
        if (said(r, 'Posted')) { closeIt(); go('dashboard'); }
      });
    });
  }

  // ================================================================ 2.0.4: URGENT announcement banner
  const seenKey = () => 'es_mdt_urgent_seen_' + ((S.ctx && S.ctx.me && S.ctx.me.charId) || 0);
  const seenGet = () => { try { return JSON.parse(localStorage.getItem(seenKey()) || '[]'); } catch (e) { return []; } };
  const seenAdd = (id) => { try { const s = seenGet().filter((x) => x !== id); s.push(id); localStorage.setItem(seenKey(), JSON.stringify(s.slice(-50))); } catch (e) { /* no storage */ } };
  function urgentBanner(a) {
    if (!a || !$('.main')) return;
    let b = $('#urgent-banner');
    if (!b) { b = document.createElement('div'); b.id = 'urgent-banner'; b.className = 'urgent-banner'; $('.main').insertBefore(b, $('.main').children[1]); }
    b.innerHTML = `<span class="ub-ico">🚨</span><div class="li-main"><b>URGENT · ${esc(a.deptShort || '')} · ${esc(a.title)}</b>${a.body ? `<span class="ub-body">${esc(String(a.body).split(/\r?\n/)[0]).slice(0, 160)}</span>` : ''}<span class="hint">✎ ${esc(a.by || '')}${a.createdAt ? ' · ' + ago(a.createdAt) : ''}</span></div>
      <button class="btn" id="ub-view">Read</button><button class="btn ghost" id="ub-ok">Got it</button>`;
    b.classList.remove('hidden');
    seenAdd(a.id);
    $('#ub-view').onclick = () => { b.classList.add('hidden'); go('dashboard'); };
    $('#ub-ok').onclick = () => b.classList.add('hidden');
  }
  M.urgentBanner = urgentBanner;
  // the MDT opens: an urgent announcement this member has not seen yet (fresh ones only, the server picks them)
  function urgentOnOpen(ctx) {
    const list = (ctx && ctx.urgent) || [];
    if (!ctx || !ctx.onDuty || !list.length) return;
    const seen = seenGet();
    const fresh = list.filter((a) => !seen.includes(a.id));
    if (!fresh.length) return;
    urgentBanner(fresh[0]);
    toast(`🚨 Urgent announcement · ${fresh[0].title}${fresh.length > 1 ? ` (+${fresh.length - 1} more)` : ''}`, 'err');
    fresh.slice(1).forEach((a) => seenAdd(a.id));
  }
  M.urgentOnOpen = urgentOnOpen;

  // ================================================================ PANIC banner (inside the MDT)
  let panicT = null;
  function panicBanner(p) {
    let b = $('#panic-banner');
    if (!b) { b = document.createElement('div'); b.id = 'panic-banner'; b.className = 'panic-banner'; $('.main').insertBefore(b, $('.main').children[1]); }
    b.innerHTML = `<span class="pb-ico">⚠</span><div class="li-main"><b>PANIC · ${esc(p.callsign || '')} ${esc(p.name || '')} <span class="hint">(${esc(p.deptShort || '')})</span></b><span>📍 ${esc(p.street || 'Unknown location')}</span></div>
      <button class="btn" id="pb-route">⌖ Waypoint</button>${p.callId ? '<button class="btn ghost" id="pb-call">Open call</button>' : ''}<button class="icon-btn" id="pb-x" title="Dismiss">✕</button>`;
    b.classList.remove('hidden');
    $('#pb-route').onclick = async () => said(await post('waypoint', { x: p.x, y: p.y }), 'Waypoint set to the panic');
    if ($('#pb-call')) $('#pb-call').onclick = () => { D.status = 'active'; go('dispatch', p.callId); };
    $('#pb-x').onclick = () => b.classList.add('hidden');
    clearTimeout(panicT); panicT = setTimeout(() => b.classList.add('hidden'), (p.seconds || 90) * 1000);
  }

  // ================================================================ LIVE MAP
  // 2.0.9: the map is its own tab now (livemap.js). The Units page's Map button opens it.
  HOOK.unitsToggle = (mode) => `<div class="seg" id="u-mode"><button data-umode="list" class="${mode === 'list' ? 'on' : ''}" data-probe-press>☰ List</button><button data-umode="map" class="${mode === 'map' ? 'on' : ''}" data-probe-press>🗺 Live map</button></div>`;
  HOOK.unitsWire = (v) => $$('[data-umode]', v).forEach((b) => b.onclick = () => { if (b.dataset.umode === 'map') { S.unitsMode = 'list'; go('livemap'); } else { S.unitsMode = 'list'; go('units'); } });
  HOOK.unitsMap = () => { S.unitsMode = 'list'; go('livemap'); };
  M.openCall = (id) => { D.status = 'active'; go('dispatch', +id); };
  M.priPill = (p) => priPill(p);
  M.kindTag = (k) => kindTag(k);
  M.kindLabel = (k) => KIND[k] || k;

  // ================================================================ MUGSHOTS
  HOOK.person = (box, p, reload) => {
    const portrait = $('#p-portrait', box);
    if (portrait && p.mugshotCount) { portrait.insertAdjacentHTML('beforeend', `<span class="mug-n" title="Mugshot history">${p.mugshotCount}</span>`); portrait.classList.add('click'); portrait.onclick = () => mugModal(p, reload, 'history'); }
    if ($('#pa-mug')) $('#pa-mug').onclick = () => mugModal(p, reload, 'camera');
    const acts = $('.prof-actions', box);
    if (acts && can('mdt_reports_write')) {
      acts.insertAdjacentHTML('beforeend', '<button class="btn small" id="pa-arrest" data-probe-press title="Guided arrest: mugshot, charges, report, jail">⛓ Arrest</button>');
      $('#pa-arrest').onclick = () => go('arrest', { charId: p.charId, name: p.name });
    }
  };

  function mugModal(p, reload, tab, onDone) {
    modal(`<div class="m-title">Mugshot · ${esc(p.name)}</div>
      <div class="seg mb" id="mg-tab"><button data-mt="camera" class="${tab === 'camera' ? 'on' : ''}">📷 Camera</button><button data-mt="link" class="${tab === 'link' ? 'on' : ''}">🔗 From a link</button>${(S.ctx && S.ctx.config && S.ctx.config.esEvidence === false) ? '' : `<button data-mt="roll" class="${tab === 'roll' ? 'on' : ''}">🖼 Camera roll</button>`}<button data-mt="history" class="${tab === 'history' ? 'on' : ''}">🗂 History</button></div>
      <div id="mg-body"></div>
      <div class="row end"><button class="btn ghost" data-x>Done</button></div>`, (card, closeIt) => {
      const body = $('#mg-body', card);
      const done = (img) => { toast('Mugshot saved and set as their photo', 'ok'); if (reload) reload(); if (onDone) { onDone(img); closeIt(); } else show('history'); };
      const show = (t) => {
        $$('[data-mt]', card).forEach((b) => b.classList.toggle('on', b.dataset.mt === t));
        if (t === 'camera') {
          body.innerHTML = `<div class="mug-cam"><div class="mug-frame" id="mg-shot"><span>📷</span></div><div><p>Stand within <b>${Math.round((cfg().mugshotRange || 6))} m</b> of ${esc(p.name)}, facing them. The camera turns to their face for a moment and takes the picture (the MDT is not in it).</p>
            <p class="hint">It becomes their photo in the MDT. Older ones stay in History.</p><button class="btn accent" id="mg-take" data-primary data-probe-press>📷 Take mugshot</button></div></div>`;
          $('#mg-take', card).onclick = (e) => busy(e.currentTarget, async () => {
            const r = await post('mugshotCam', { charId: p.charId });
            if (!said(r)) return;
            $('#mg-shot', card).innerHTML = `<img src="${r.data.image}" alt="">`;
            done(r.data.image);
          });
        } else if (t === 'link') {
          body.innerHTML = `<div class="field"><label>Picture link <span class="hint">(public http/https, jpg/png/webp, 300 KB at most)</span></label><input id="mg-url" maxlength="500" placeholder="https://…/photo.jpg"></div>
            <div class="mug-prev" id="mg-prev"><span class="hint">The preview shows here</span></div>
            <div class="row end"><button class="btn accent" id="mg-use" data-primary disabled>Use this picture</button></div>`;
          const inp = $('#mg-url', card), prev = $('#mg-prev', card), use = $('#mg-use', card); let t2 = null;
          inp.oninput = () => { clearTimeout(t2); use.disabled = true; t2 = setTimeout(() => {
            const u = inp.value.trim();
            if (!/^https?:\/\/[^\s]+$/i.test(u)) { prev.innerHTML = `<span class="hint">${u ? 'A link starts with https://' : 'The preview shows here'}</span>`; return; }
            prev.innerHTML = '<div class="spin"></div>';
            const img = new Image();
            img.onload = () => { prev.innerHTML = ''; prev.appendChild(img); use.disabled = false; };
            img.onerror = () => { prev.innerHTML = '<span class="hint">The preview did not load here. You can still try: the server fetches it and checks it is a picture.</span>'; use.disabled = false; };
            img.src = u;
          }, 300); };
          use.onclick = (e) => busy(e.currentTarget, async () => { const r = await call('mugshotLink', { charId: p.charId, url: inp.value.trim() }); if (said(r)) done(r.data.image); });
        } else if (t === 'roll') {
          // 1.4.0: a photo the officer took with the camera item (es_evidence camera roll)
          body.innerHTML = `<p class="hint">Photos you took with the camera item. Pick one: it shows on the right before you use it.</p>
            <div class="ev-pick"><div id="mg-roll"></div><div class="ev-prev" id="mg-rprev"><span class="hint">The preview shows here</span></div></div>
            <div class="row end"><button class="btn accent" id="mg-ruse" data-primary disabled>Use this photo</button></div>`;
          let picked = null;
          const use = $('#mg-ruse', card);
          if (!M.rollPicker) { $('#mg-roll', card).innerHTML = empty('The camera roll did not load. An admin needs to run "refresh", then "ensure es_mdt".', '⚠'); return; }
          M.rollPicker($('#mg-roll', card), $('#mg-rprev', card), (ph) => { picked = ph; use.disabled = false; });
          use.onclick = (e) => busy(e.currentTarget, async () => { if (!picked) return; const r = await call('mugshotRoll', { charId: p.charId, photoId: picked.id }); if (said(r)) done(r.data.image); });
        } else {
          body.innerHTML = '<div class="mug-grid" id="mg-grid"><div class="loading-row"><div class="spin"></div></div></div>';
          call('mugshots', { charId: p.charId }).then(async (r) => {
            const g = $('#mg-grid', card); if (!g) return;
            const list = (r.ok && r.data) || [];
            if (!list.length) { g.innerHTML = empty('No mugshots yet', '📷'); return; }
            g.innerHTML = list.map((m) => `<div class="mug-i${m.profile ? ' on' : ''}"><div class="mug-img" data-mid="${m.id}"><div class="spin"></div></div>
              <div class="hint">${dateTime(m.createdAt)} · ${m.origin === 'link' ? 'link' : m.origin === 'roll' ? 'camera roll' : 'camera'}${m.by ? ' · ' + esc(m.by) : ''}</div>
              ${m.profile ? pill('Profile photo', 'on') : (can('mdt_reports_write') ? `<button class="btn small ghost" data-mprof="${m.id}">Set as photo</button>` : '')}</div>`).join('');
            $$('[data-mprof]', g).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('mugshotProfile', { id: +b.dataset.mprof, charId: p.charId }), 'Profile photo set')) { if (reload) reload(); show('history'); } }));
            for (const el of $$('[data-mid]', g)) {   // one at a time: each is a full picture
              const x = await call('mugshot', { id: +el.dataset.mid });
              if (!el.isConnected) return;
              el.innerHTML = x.ok ? `<img src="${x.data.image}" alt="">` : '<span class="hint">—</span>';
            }
          });
        }
      };
      $$('[data-mt]', card).forEach((b) => b.onclick = () => show(b.dataset.mt));
      show(tab);
    });
  }

  // ================================================================ REPORT TEMPLATES
  let TPL = null;
  async function templates(force) { if (TPL && !force) return TPL; const r = await call('templates'); TPL = r.ok && r.data && Array.isArray(r.data.list) ? r.data : { list: [], canEdit: false }; return TPL; }

  HOOK.reportEditor = async (v, R, setType) => {
    const t = await templates();
    const card = $('.cols-main .card', v); if (!card || !$('#re-body')) return;
    const bar = document.createElement('div'); bar.className = 'tpl-bar';
    bar.innerHTML = `<span class="lbl">Template</span>${t.list.map((x) => `<button class="chip-b" data-tpl="${esc(x.key)}" title="${esc(x.builtIn ? 'Built in' : 'Your department')}">${x.builtIn ? '' : '★ '}${esc(x.name)}</button>`).join('')}${t.canEdit ? '<button class="btn small ghost" id="tpl-man">Manage…</button>' : ''}`;
    card.insertBefore(bar, card.firstChild);
    $$('[data-tpl]', bar).forEach((b) => b.onclick = async () => {
      const x = t.list.find((y) => y.key === b.dataset.tpl); if (!x) return;
      const body = $('#re-body'), title = $('#re-title');
      if (body.value.trim() && body.value.trim() !== (S.lastTplBody || '').trim() && !await confirmBox('Use template', 'Replace the narrative you wrote with this template?', 'Replace')) return;
      body.value = x.body || ''; S.lastTplBody = x.body || '';
      if (!title.value.trim() || title.value === S.lastTplTitle) { title.value = x.title || ''; S.lastTplTitle = x.title || ''; }
      if (x.type) setType(x.type);
      $$('[data-tpl]', bar).forEach((y) => y.classList.toggle('on', y === b));
      title.focus(); title.setSelectionRange(title.value.length, title.value.length);
    });
    if ($('#tpl-man')) $('#tpl-man').onclick = () => tplManager();
  };

  async function tplManager() {
    const t = await templates(true);
    const mine = t.list.filter((x) => !x.builtIn);
    modal(`<div class="m-title">Report templates · ${esc(S.ctx.dept.short)}</div><p class="hint">Built-in templates are for every department. Yours show with a ★ for everyone in ${esc(S.ctx.dept.short)}.</p>
      <div id="tm-list">${mine.length ? mine.map((x) => `<div class="li"><span class="tag t-${esc(x.type)}">${esc(M.typeLabel(x.type))}</span><div class="li-main"><b>${esc(x.name)}</b><span class="hint">${esc(x.title || '')}</span></div><button class="btn small" data-tedit="${x.id}">Edit</button><button class="icon-btn" data-tdel="${x.id}" title="Delete">✕</button></div>`).join('') : empty('No department templates yet', '☰')}</div>
      <div class="row end"><button class="btn ghost" data-x>Close</button><button class="btn accent" id="tm-new" data-primary>+ New template</button></div>`, (card, closeIt) => {
      $('#tm-new', card).onclick = () => tplForm({}, closeIt);
      $$('[data-tedit]', card).forEach((b) => b.onclick = () => tplForm(mine.find((x) => x.id === +b.dataset.tedit), closeIt));
      $$('[data-tdel]', card).forEach((b) => b.onclick = async () => { if (said(await call('templateDelete', { id: +b.dataset.tdel }), 'Template deleted')) { TPL = null; tplManager(); } });
    });
  }
  function tplForm(x) {
    let type = x.type || 'incident';
    modal(`<div class="m-title">${x.id ? 'Edit template' : 'New template'}</div>
      <div class="grid"><div class="field"><label>Name</label><input id="tf-n" maxlength="60" value="${esc(x.name || '')}" placeholder="Bank robbery"></div>
        <div class="field"><label>Report type</label><div class="seg" id="tf-t">${(cfg().reportTypes || []).map((r) => `<button data-t="${r.key}" class="${r.key === type ? 'on' : ''}">${esc(r.label)}</button>`).join('')}</div></div></div>
      <div class="field"><label>Title starts with</label><input id="tf-ti" maxlength="120" value="${esc(x.title || '')}" placeholder="Bank robbery: "></div>
      <div class="field"><label>Narrative structure</label><textarea id="tf-b" class="tall" maxlength="6000" placeholder="HEADINGS:\n\nIN CAPITALS:\n">${esc(x.body || '')}</textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="tf-go" data-primary>Save template</button></div>`, (card, closeIt) => {
      $$('[data-t]', card).forEach((b) => b.onclick = () => { type = b.dataset.t; $$('[data-t]', card).forEach((y) => y.classList.toggle('on', y === b)); });
      $('#tf-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        if (said(await call('templateSave', { id: x.id, name: $('#tf-n', card).value, type, title: $('#tf-ti', card).value, body: $('#tf-b', card).value }), 'Template saved')) { closeIt(); TPL = null; setTimeout(tplManager, 180); }
      });
    });
  }

  // ================================================================ SEND TO JAIL (report view)
  let JAIL = null;
  async function jailInstalled() { const r = await call('jailStatus'); JAIL = !!(r.ok && r.data.installed); return JAIL; }
  async function sendToJail(reportId, charId, name) {
    const r = await call('sendToJail', { reportId, charId });
    if (!r.ok) { said(r); return false; }
    if (!r.data.installed) { toast(`No jail script connected: ${r.data.months} months recorded in the MDT (Jail tab)`, 'ok'); return true; }
    toast(`${name || 'They'} sent to jail for ${r.data.months} months`, 'ok');
    return true;
  }
  HOOK.reportView = (v, x) => {
    if (!can('mdt_reports_write')) return;
    const sus = x.people.filter((p) => p.role === 'suspect');
    const heads = $$('.sus .sus-head', v);
    sus.forEach((s, i) => {
      const months = x.charges.filter((c) => c.charId === s.charId).reduce((n, c) => n + c.months * c.count, 0);
      if (!months || !heads[i]) return;
      heads[i].insertAdjacentHTML('beforeend', `<button class="btn small jail-btn" data-jail="${s.charId}" data-name="${esc(s.name)}" title="Calls the jail system">⛓ Send to jail · ${months} mo</button>`);
    });
    $$('[data-jail]', v).forEach((b) => b.onclick = async () => {
      if (!await confirmBox('Send to jail', `Send ${b.dataset.name} to jail for the months on this report?`, '⛓ Send to jail', true)) return;
      busy(b, () => sendToJail(x.id, +b.dataset.jail, b.dataset.name));
    });
  };

  // ================================================================ PROCESS ARREST (stepper)
  const STEPS = ['Suspect', 'Booking', 'Charges', 'Review', 'Done'];
  let A = null;
  const fresh = () => ({ step: 0, person: null, mug: null, charges: [], title: '', location: '', body: '', jail: true, reportId: null, jailed: null, prints: null });
  const tplArrest = () => (cfg().reportTemplates || []).find((t) => t.key === 'arrest');

  VIEWS.arrest = async (v, arg) => {
    if (!A || (arg && arg.charId) || (A.step === 4 && !A.showDone)) A = fresh();
    if (arg && arg.charId) { A.person = { charId: arg.charId, name: arg.name }; A.step = 1; S.arg = null; }
    S.dirty = A.step > 0 && A.step < 4;
    if (JAIL === null) jailInstalled();
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Process arrest</div><div class="hint">Suspect → booking (mugshot, prints) → charges → review → filed. Nothing is saved until the last step.</div></div>
      ${A.step > 0 && A.step < 4 ? '<button class="btn ghost" id="ar-reset">Start over</button>' : ''}</div>
      <div class="stepbar">${STEPS.map((s, i) => `<div class="sb-i${i === A.step ? ' on' : ''}${i < A.step ? ' done' : ''}"><span class="sb-n">${i < A.step ? '✓' : i + 1}</span><span>${s}</span></div>`).join('<span class="sb-line"></span>')}</div>
      <div id="ar-body" class="card ar-card"></div>
      <div class="row between ar-nav"><button class="btn ghost" id="ar-back"${A.step === 0 || A.step === 4 ? ' disabled' : ''}>← Back</button><span class="hint" id="ar-msg"></span><button class="btn accent" id="ar-next" data-probe-press>${A.step === 3 ? '✓ File arrest report' : A.step === 4 ? 'Process another' : 'Next →'}</button></div>`;
    if ($('#ar-reset')) $('#ar-reset').onclick = async () => { if (await confirmBox('Start over', 'Clear this arrest and start again?', 'Start over', true)) { A = fresh(); go('arrest'); } };
    $('#ar-back').onclick = () => { A.step = Math.max(0, A.step - 1); go('arrest'); };
    const body = $('#ar-body'), next = $('#ar-next');
    const step = [stSuspect, stMug, stCharges, stReview, stDone][A.step];
    await step(body, next);
  };

  async function stSuspect(body, next) {
    body.innerHTML = `<div class="card-title">Who are you arresting?</div><div id="ar-pp"></div><div id="ar-who"></div>`;
    const draw = async () => {
      const box = $('#ar-who'); if (!box) return;
      if (!A.person) { box.innerHTML = '<p class="hint">Search their name, phone or ID.</p>'; next.disabled = true; return; }
      next.disabled = false;
      box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
      const r = await call('person', { charId: A.person.charId });
      if (!$('#ar-who')) return;
      const p = r.ok ? r.data : { name: A.person.name, firstName: '?', lastName: '' };
      A.person.photo = p.mugshot || p.portrait || null; A.person.warrants = (p.warrants || []).filter((w) => w.status === 'active');
      box.innerHTML = `<div class="prof-head mini"><div class="portrait">${A.person.photo ? `<img src="${A.person.photo}" alt="">` : `<span>${esc((p.firstName || '?')[0])}${esc((p.lastName || '')[0] || '')}</span>`}</div>
        <div class="prof-main"><div class="v-title">${esc(p.name)}</div><div class="facts"><span><i>ID</i>#${A.person.charId}</span><span><i>Born</i>${esc(p.dob || '—')}</span><span><i>Phone</i>${esc(p.phone || '—')}</span></div>
        <div class="res-tags">${A.person.warrants.length ? pill(A.person.warrants.length + ' active warrant' + (A.person.warrants.length > 1 ? 's' : ''), 'bad') : pill('No active warrants', 'off')}${(p.flags || []).map((f) => pill(f, 'warn')).join('')}</div></div>
        <button class="btn ghost small" id="ar-clear">Change</button></div>
        ${A.person.warrants.length ? `<div class="w-banner"><span class="w-ico">⚠</span><div><b>Active warrants</b><div>${A.person.warrants.map((w) => esc(w.reason)).join(' · ')}</div></div></div>` : ''}`;
      $('#ar-clear').onclick = () => { A.person = null; draw(); };
    };
    personPicker($('#ar-pp'), 'Search the suspect…', (p) => { A.person = { charId: p.charId, name: p.name }; A.mug = null; draw(); });
    next.onclick = () => { if (A.person) { A.step = 1; go('arrest'); } };
    draw();
  }

  async function stMug(body, next) {
    const photo = A.mug || A.person.photo;
    body.innerHTML = `<div class="card-title">Mugshot</div><div class="mug-cam"><div class="mug-frame">${photo ? `<img src="${photo}" alt="">` : '<span>📷</span>'}</div>
      <div><p>${A.mug ? '<b class="txt-ok">✓ Mugshot taken.</b> It is now their MDT photo.' : `Take a booking photo of <b>${esc(A.person.name)}</b>. Stand within a few metres, facing them.`}</p>
      <div class="row"><button class="btn accent" id="ar-cam" data-probe-press>📷 ${A.mug ? 'Retake' : 'Take mugshot'}</button><button class="btn" id="ar-link">🔗 From a link</button>${(S.ctx && S.ctx.config && S.ctx.config.esEvidence === false) ? '' : '<button class="btn" id="ar-roll">🖼 From camera roll</button>'}</div>
      <p class="hint">Optional: skip with Next if you cannot take one.</p></div></div>
      ${M.takePrints ? `<div class="fp-card ar-fp"><div class="fp-ico">🖐</div><div class="fp-main"><b>Fingerprints</b><div id="ar-fp-line">${A.prints ? `<b class="txt-ok">✓ Prints on file</b> <span class="ev-code">${esc(A.prints.fp || '')}</span>${(A.prints.matched || []).length ? ` <span class="pill warn">Matched ${A.prints.matched.map(esc).join(', ')}</span>` : ''}` : '<span class="hint">Checking…</span>'}</div>
        <div class="hint">Puts their prints on file: the lab names them from any lift, and earlier Unidentified lifts match now.</div></div>
        <button class="btn${A.prints ? '' : ' accent'}" id="ar-fp" data-probe-press>🖐 ${A.prints ? 'Take again' : 'Take prints'}</button></div>` : ''}`;
    if ($('#ar-fp')) {
      $('#ar-fp').onclick = (e) => busy(e.currentTarget, async () => { const r = await M.takePrints(A.person); if (r) { A.prints = r; go('arrest'); } });
      if (!A.prints) call('evPrintsOf', { charId: A.person.charId }).then((r) => {
        const el = $('#ar-fp-line'); if (!el || A.prints) return;
        el.innerHTML = r.ok && M.fpLine ? M.fpLine(r.data) : '<span class="hint">Not on file yet</span>';
      });
    }
    $('#ar-cam').onclick = (e) => busy(e.currentTarget, async () => { const r = await post('mugshotCam', { charId: A.person.charId }); if (said(r, 'Mugshot saved')) { A.mug = r.data.image; go('arrest'); } });
    $('#ar-link').onclick = () => mugModal({ charId: A.person.charId, name: A.person.name }, null, 'link', (img) => { A.mug = img; go('arrest'); });
    if ($('#ar-roll')) $('#ar-roll').onclick = () => mugModal({ charId: A.person.charId, name: A.person.name }, null, 'roll', (img) => { A.mug = img; go('arrest'); });
    next.onclick = () => { A.step = 2; go('arrest'); };
  }

  const maxOf = (p, k, mult) => Math.floor((p[k] || 0) * (((cfg().chargeOverride || {})[mult]) || 1) + 0.5);
  async function stCharges(body, next) {
    const list = await M.penal();
    if (!$('#ar-body')) return;
    body.innerHTML = `<div class="card-head"><div class="card-title">Charges for ${esc(A.person.name)}</div><span class="tot" id="ar-tot"></span></div>
      <div class="picker-wrap"><input type="text" id="ar-cq" placeholder="+ Add a charge: code or name (Enter adds the first)" autocomplete="off"><div class="pop hidden"></div></div>
      <div id="ar-ch"></div><p class="hint">Fine and jail time are per count. You can lower them${(cfg().chargeOverride || {}).maxFineMult > 1 ? ' or raise them up to ' + Math.round(cfg().chargeOverride.maxFineMult * 100) + '%' : ''}; every change is logged on the report.</p>`;
    const draw = () => {
      let tf = 0, tm = 0;
      $('#ar-ch').innerHTML = A.charges.length ? A.charges.map((c, i) => { const p = list.find((x) => x.id === c.penalId) || {};
        tf += c.fine * c.count; tm += c.months * c.count; const ed = c.fine !== (p.fine || 0) || c.months !== (p.months || 0);
        return `<div class="charge${ed ? ' edited' : ''}"><span class="cat c-${esc(p.category)}">${esc(p.code)}</span><span class="c-title">${esc(p.title)}</span><span class="spacer"></span>
          <label class="ov" title="Fine per count (0 to ${money(maxOf(p, 'fine', 'maxFineMult'))})">$<input type="number" min="0" max="${maxOf(p, 'fine', 'maxFineMult')}" value="${c.fine}" data-af="${i}"></label>
          <label class="ov" title="Jail months per count (0 to ${maxOf(p, 'months', 'maxMonthsMult')})"><input type="number" min="0" max="${maxOf(p, 'months', 'maxMonthsMult')}" value="${c.months}" data-am="${i}">mo</label>
          <span class="hint pc-def">${ed ? `<a class="lnk" data-ars="${i}">reset</a> · ` : ''}PC ${money(p.fine || 0)} · ${p.months || 0} mo</span>
          <div class="stepper"><button data-ad="${i}">−</button><span>${c.count}</span><button data-ai="${i}">+</button></div><button class="icon-btn" data-ax="${i}" title="Remove">✕</button></div>`; }).join('') : empty('No charges yet. Add them above.', '§');
      $('#ar-tot').innerHTML = `${money(tf)} · <b>${tm}</b> months`;
      next.disabled = !A.charges.length;
      const clamp = (el) => Math.max(0, Math.min(+el.max || 0, Math.floor(+el.value || 0)));
      $$('[data-af]').forEach((el) => el.onchange = () => { A.charges[+el.dataset.af].fine = clamp(el); draw(); });
      $$('[data-am]').forEach((el) => el.onchange = () => { A.charges[+el.dataset.am].months = clamp(el); draw(); });
      $$('[data-ars]').forEach((el) => el.onclick = () => { const c = A.charges[+el.dataset.ars], p = list.find((x) => x.id === c.penalId) || {}; c.fine = p.fine || 0; c.months = p.months || 0; draw(); });
      $$('[data-ai]').forEach((b) => b.onclick = () => { const c = A.charges[+b.dataset.ai]; c.count = Math.min(20, c.count + 1); draw(); });
      $$('[data-ad]').forEach((b) => b.onclick = () => { const c = A.charges[+b.dataset.ad]; if (c.count > 1) c.count--; draw(); });
      $$('[data-ax]').forEach((b) => b.onclick = () => { A.charges.splice(+b.dataset.ax, 1); draw(); });
    };
    const inp = $('#ar-cq'), pop = inp.nextElementSibling;
    const add = (p) => { const c = A.charges.find((x) => x.penalId === p.id); if (c) c.count = Math.min(20, c.count + 1); else A.charges.push({ penalId: p.id, count: 1, fine: p.fine || 0, months: p.months || 0 }); inp.value = ''; pop.classList.add('hidden'); draw(); inp.focus(); };
    inp.oninput = () => {
      const q = inp.value.trim().toLowerCase(); if (!q) { pop.classList.add('hidden'); return; }
      const hits = list.filter((p) => p.active !== 0 && p.active !== false && (p.code.toLowerCase().includes(q) || p.title.toLowerCase().includes(q))).slice(0, 8);
      pop.innerHTML = hits.map((p) => `<div class="pop-row" data-apc="${p.id}"><span class="cat c-${esc(p.category)}">${esc(p.code)}</span><b>${esc(p.title)}</b><span class="hint">${money(p.fine)} · ${p.months} mo</span></div>`).join('') || '<div class="pop-empty">No charge matches</div>';
      pop.classList.remove('hidden');
      $$('[data-apc]', pop).forEach((row) => row.onmousedown = (e) => { e.preventDefault(); add(list.find((x) => x.id === +row.dataset.apc)); });
    };
    inp.onkeydown = (e) => { if (e.key === 'Enter') { e.preventDefault(); const f = $('[data-apc]', pop); if (f) f.dispatchEvent(new MouseEvent('mousedown')); } };
    inp.onblur = () => setTimeout(() => pop.classList.add('hidden'), 150);
    next.onclick = () => { if (A.charges.length) { A.step = 3; go('arrest'); } };
    draw(); inp.focus();
  }

  async function stReview(body, next) {
    const list = await M.penal();
    if (!$('#ar-body')) return;
    const t = tplArrest();
    if (!A.title) A.title = ((t && t.title) || 'Arrest: ') + A.person.name;
    if (!A.body) A.body = (t && t.body) || '';
    const tf = A.charges.reduce((n, c) => n + c.fine * c.count, 0), tm = A.charges.reduce((n, c) => n + c.months * c.count, 0);
    const installed = await jailInstalled();
    if (!$('#ar-body')) return;
    body.innerHTML = `<div class="cols-main"><div>
        <div class="grid"><div class="field span2"><label>Title</label><input id="ar-t" maxlength="120" value="${esc(A.title)}"></div>
          <div class="field span2"><label>Location</label><input id="ar-l" maxlength="120" value="${esc(A.location)}" placeholder="Where the arrest happened"></div>
          <div class="field span2"><label>Narrative</label><textarea id="ar-n" class="tall">${esc(A.body)}</textarea></div></div></div>
      <div><div class="ar-sum"><div class="prof-head mini"><div class="portrait sm">${(A.mug || A.person.photo) ? `<img src="${A.mug || A.person.photo}" alt="">` : '<span>?</span>'}</div><div class="prof-main"><b>${esc(A.person.name)}</b><span class="hint">#${A.person.charId}${A.mug ? ' · mugshot taken' : ''}${A.prints ? ' · prints on file' : ''}</span></div></div>
        ${A.charges.map((c) => { const p = list.find((x) => x.id === c.penalId) || {}; return `<div class="charge"><span class="cat c-${esc(p.category)}">${esc(p.code)}</span><span>${esc(p.title)}</span><span class="spacer"></span><span class="hint">×${c.count} · ${money(c.fine * c.count)} · ${c.months * c.count} mo</span></div>`; }).join('')}
        <div class="ar-total"><span>Total</span><b>${money(tf)} · ${tm} months</b></div>
        ${tm > 0 ? (installed ? `<label class="chip-t big"><input type="checkbox" id="ar-jail"${A.jail ? ' checked' : ''}><span>⛓ Send to jail for ${tm} months after filing</span></label>`
          : '<div class="note warn">⛓ Jail system not installed yet. The report is filed; jail them by hand.</div>') : '<div class="hint">No jail time: no jail step.</div>'}
        <p class="hint">The fine is billed from the report like any other (Bill button on the report).</p><div id="ar-ev"></div></div></div></div>`;
    if (M.arrestEvidence) M.arrestEvidence($('#ar-ev'), A);
    const keep = () => { A.title = $('#ar-t').value; A.location = $('#ar-l').value; A.body = $('#ar-n').value; if ($('#ar-jail')) A.jail = $('#ar-jail').checked; };
    $('#ar-back').addEventListener('click', keep, true);
    next.onclick = () => busy(next, async () => {
      keep();
      if (!A.title.trim()) { toast('Give the report a title', 'err'); return; }
      const r = await call('reportSave', { type: 'arrest', title: A.title, location: A.location, body: A.body, people: [{ charId: A.person.charId, role: 'suspect' }], officers: [],
        charges: A.charges.map((c) => ({ charId: A.person.charId, penalId: c.penalId, count: c.count, fine: c.fine, months: c.months })), weapons: [] });
      if (!said(r)) return;
      A.reportId = r.data;
      if (M.arrestEvidenceSave) { try { await M.arrestEvidenceSave(A.reportId, A); } catch (e) { /* the report is filed either way */ } }
      if (tm > 0 && !installed) A.jailed = { ok: false, why: 'Jail system not installed yet' };
      else if (tm > 0 && A.jail) {
        const j = await call('sendToJail', { reportId: A.reportId, charId: A.person.charId });
        A.jailed = j.ok ? (j.data.installed ? { ok: true, months: j.data.months } : { ok: true, months: j.data.months, recorded: true }) : { ok: false, why: j.why };
      }
      A.step = 4; A.showDone = true; S.dirty = false; go('arrest');
    });
  }

  async function stDone(body, next) {
    const j = A.jailed;
    body.innerHTML = `<div class="ar-done"><div class="ar-check">✓</div><div class="v-title">Arrest report #${A.reportId} filed</div>
      <p>${esc(A.person.name)} · ${A.charges.length} charge${A.charges.length === 1 ? '' : 's'}</p>
      ${j ? (j.ok ? (j.recorded ? `<div class="note ok">⛓ ${j.months} months recorded in the MDT (no jail script is connected)</div>` : `<div class="note ok">⛓ Sent to jail for ${j.months} months</div>`) : `<div class="note warn">⛓ ${esc(j.why || 'Not sent to jail')}${j.why === 'Jail system not installed yet' ? '. The report is filed.' : ''}</div>`) : ''}
      <div class="row center"><button class="btn accent" data-report="${A.reportId}">Open report</button><button class="btn" data-person="${A.person.charId}">Open profile</button></div></div>`;
    S.dirty = false; A.showDone = false;
    next.onclick = () => { A = fresh(); go('arrest'); };
  }

  // ================================================================ messages from the game
  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
    if (!m || !m.action) return;
    if (m.action === 'go') { if (S.open && m.view) go(m.view, m.arg); }
    else if (m.action === 'call') {
      if (!S.open || !m.call) return;
      const c = m.call; M.loadBadges();
      toast(`${KIND[c.kind] || 'Call'} #${c.id} · ${c.message || c.title}${c.street ? ' · ' + c.street : ''}`, c.priority === 1 ? 'err' : 'ok');
    } else if (m.action === 'panic') {
      if (!S.open || !m.panic) return;
      panicBanner(m.panic); M.loadBadges();
    } else if (m.action === 'announce') {
      if (!S.open || !m.announce) return;
      const a = m.announce, lv = lvlOf(a);
      toast(`${lv === 'urgent' ? '🚨 URGENT' : lv === 'important' ? '❗ Important' : '📣'} ${a.deptShort || ''} · ${a.title}`, lv === 'urgent' ? 'err' : 'ok');
      if (lv === 'urgent') urgentBanner(a);
      if (S.view === 'dashboard' && !(M.modalOpen && M.modalOpen())) go('dashboard');
    } else if (m.action === 'callEscalated' || m.action === 'callMerged') {   // 2.0.6 / 2.0.7: quiet (the Dispatch tab refreshes by itself)
      if (S.open) M.loadBadges();
    } else if (m.action === 'open') { setTimeout(() => urgentOnOpen(S.ctx), 350);   // (the live map stops itself on close: livemap.js)
    }
  });
})();

// ---------------------------------------------------------------- 1.3.2: call card (MDT closed)
// Lua owns the queue and timing (client/ops.lua); this only draws what it is told: { action: 'cpop', show, call, ... }.
(() => {
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const CODE = { '911': '911', '311': '311', panic: 'PANIC', officer: 'OFFICER', alert: 'ALERT', medical: 'MEDICAL', shots: 'SHOTS', theft: 'THEFT', backup: 'BACKUP',
    robbery: 'ROBBERY', drugs: 'DRUGS', explosion: 'EXPLOSION', fight: 'FIGHT', suspicious: 'SUSPICIOUS', down: 'PERSON DOWN', speeding: 'SPEEDING' };
  // 2.0.7: suspect details on the card (one line of chips)
  const detChips = (d) => {
    if (!d || typeof d !== 'object') return '';
    const o = [];
    if (d.plate) o.push(`<span class="cp-d"><i>Plate</i><b class="mono">${esc(d.plate)}</b></span>`);
    if (d.vehicle || d.color) o.push(`<span class="cp-d"><i>Veh</i><b>${esc([d.color, d.vehicle].filter(Boolean).join(' '))}</b></span>`);
    if (d.weapon) o.push(`<span class="cp-d g${esc(d.grade || 2)}"><i>Weapon</i><b>${esc(d.weapon)}</b></span>`);
    if (d.desc) o.push(`<span class="cp-d wide"><i>Suspect</i><b>${esc(d.desc)}</b></span>`);
    return o.length ? `<div class="cp-det">${o.join('')}</div>` : '';
  };
  const PRI = { 1: 'P1', 2: 'P2', 3: 'P3' };
  const keyName = (k) => ({ DELETE: 'DEL', BACK: '⌫', RETURN: 'ENTER', ESCAPE: 'ESC' }[String(k).toUpperCase()] || k);
  const distTxt = (m) => m == null ? '' : m < 1000 ? `${Math.round(m / 10) * 10} m` : `${(m / 1000).toFixed(m < 10000 ? 1 : 0)} km`;
  const ageTxt = (s) => s < 30 ? 'just now' : s < 90 ? '1 min ago' : `${Math.round(s / 60)} min ago`;
  // 1.3.4: the card is built once per call. Distance, time ago and units change in place; the entry animation plays
  // once (new call only); the countdown bar is one CSS transition started when the card (or its hold) begins.
  let el = null, cur = { seq: -1, sig: '' };
  const box = () => { if (!el) { el = document.createElement('div'); el.id = 'cpop'; el.className = 'cpop hidden'; document.body.appendChild(el); } return el; };
  const unitsHtml = (c) => {
    const units = Array.isArray(c.units) ? c.units : [];
    // 2.0.6: { cs, name, st, dept } per unit (callsign + short name + status); plain text from older servers still works
    const short = (n) => { const p = String(n || '').trim().split(/\s+/); return p.length > 1 ? `${p[0][0]}. ${p[p.length - 1]}` : (p[0] || ''); };
    const one = (u) => {
      if (typeof u !== 'object' || !u) return `<span class="cp-u">${esc(u)}</span>`;
      const st = u.st === 'scene' ? ['sc', '✓'] : u.st === 'enroute' ? ['er', '→'] : ['', ''];
      return `<span class="cp-u${st[0] ? ' ' + st[0] : ''}" title="${esc(u.name || '')}${u.dept ? ' · ' + esc(u.dept) : ''}">${u.cs ? `<b>${esc(u.cs)}</b>` : ''}${u.name ? `<span class="cp-un">${esc(short(u.name))}</span>` : ''}${st[1] ? `<i>${st[1]}</i>` : ''}</span>`;
    };
    return (units.length ? `<span class="cp-ul">${units.length} responding</span>${units.slice(0, 4).map(one).join('')}${units.length > 4 ? `<span class="cp-u">+${units.length - 4}</span>` : ''}`
      : `<span class="cp-ul none">No units yet</span>`) + (c.callerName ? `<span class="cp-caller">Caller: ${esc(c.callerName)}</span>` : '');
  };
  const setText = (root, sel, txt) => { const n = root.querySelector(sel); if (n && n.textContent !== txt) n.textContent = txt; };
  const startBar = (root, ms) => {
    const bar = root.querySelector('.cp-bar i'); if (!bar) return;
    bar.style.transition = 'none'; bar.style.transform = 'scaleX(1)';
    void bar.offsetWidth;
    bar.style.transition = `transform ${Math.max(0, ms)}ms linear`; bar.style.transform = 'scaleX(0)';
  };

  function build(m, enter) {
    const root = box(), c = m.call, k = m.keys || {};
    const panic = c.kind === 'panic';
    const state = m.state || (c.closed ? 'closed' : c.mine ? 'mine' : 'new');
    let foot;
    if (m.state === 'attached') foot = `<div class="cp-flash ok">✓ ${esc(m.note || 'Attached · GPS set')}</div>`;
    else if (m.state === 'closed' || c.closed) foot = `<div class="cp-flash off">${esc(m.note || ('Closed' + (c.outcome ? ' · ' + c.outcome : '')))}</div>`;
    else if (m.state === 'error') foot = `<div class="cp-flash bad">${esc(m.note || 'That did not work')}</div>`;
    else foot = `<div class="cp-keys">
        <span class="cp-k cp-go"><kbd>${esc(keyName(k.attend || 'E'))}</kbd>${c.mine ? 'GPS again' : 'Respond + GPS'}</span>
        <span class="cp-k"><kbd>${esc(keyName(k.dismiss || 'DEL'))}</kbd>${m.more ? 'Next' : 'Hide'}</span>
        ${c.mine ? `<span class="cp-k dim">${esc(k.detach || '/detach')} to leave</span>` : `<span class="cp-k dim">${esc(k.recall || '/calls')}</span>`}
      </div>`;
    root.innerHTML = `<div class="cp-card cp-p${c.priority || 2}${panic ? ' panic' : ''}${c.critical && !c.closed ? ' crit' : ''} st-${state}${enter ? ' enter' : ''}">
      <div class="cp-top">
        ${c.critical && !c.closed ? `<span class="cp-crit${c.alarm ? ' ring' : ''}" title="Critical: above P1">CRITICAL</span>` : ''}
        <span class="cp-code k-${esc(c.kind)}">${c.icon ? `<span class="cp-ico">${esc(c.icon)}</span>` : ''}${esc(CODE[c.kind] || 'CALL')}</span>
        <span class="cp-pri">${esc(PRI[c.priority] || 'P2')}</span>
        ${(c.reports || 1) > 1 ? `<span class="cp-rep" title="Repeat reports merged into this call">×${esc(c.reports)} reports</span>` : ''}
        ${c.escalated ? `<span class="cp-esc" title="No unit yet: raised from P${esc(c.escalated)}">↑ from P${esc(c.escalated)}</span>` : ''}
        <span class="cp-id">#${esc(c.id)}</span>
        <span class="cp-sp"></span>
        ${m.more ? `<span class="cp-more">+${m.more} more</span>` : ''}
        <span class="cp-age">${esc(ageTxt(m.age || 0))}</span>
      </div>
      <div class="cp-title">${esc(c.title || 'Call')}</div>
      ${c.parentId ? `<div class="cp-link">⤴ Backup for call #${esc(c.parentId)}</div>` : ''}
      ${c.message && c.message !== c.title ? `<div class="cp-msg">${esc(c.message)}</div>` : ''}
      <div class="cp-meta">
        <span class="cp-loc">📍 ${esc(c.street || 'Location on your map')}</span>
        ${c.radius ? `<span class="cp-area" title="A witness report: the spot is somewhere in this circle">◎ ~${esc(c.radius)} m area</span>` : ''}
        <span class="cp-dist${m.dist == null ? ' hidden' : ''}">${esc(distTxt(m.dist))}</span>
      </div>
      ${detChips(c.details)}
      <div class="cp-units">${unitsHtml(c)}</div>
      ${foot}
      <div class="cp-bar"><i></i></div>
    </div>`;
    root.classList.remove('hidden');
    const card = root.querySelector('.cp-card');
    if (enter) card.addEventListener('animationend', (e) => { if (e.animationName === 'cpIn') card.classList.remove('enter'); }, { once: false });
    startBar(root, m.left || 0);
  }

  function draw(m) {
    const root = box();
    if (!m.show || !m.call) { root.classList.add('hidden'); root.innerHTML = ''; cur = { seq: -1, sig: '' }; return; }
    const c = m.call, k = m.keys || {};
    // what changes the card's shape; units, distance and age do not
    const sig = [c.id, c.kind, c.priority, c.escalated || '', c.parentId || '', c.title, c.message, c.street, c.callerName, !!c.closed, c.outcome || '', !!c.mine, m.more || 0,
      !!c.critical, c.icon || '', c.reports || 1, c.radius || 0, JSON.stringify(c.details || null), !!c.alarm,
      m.state || '', m.note || '', k.attend, k.dismiss, k.recall, k.detach].join('|');
    const fresh = m.seq !== cur.seq || !root.querySelector('.cp-card');
    if (fresh) build(m, true);                 // a new call: build, slide in once, bar from full
    else if (sig !== cur.sig) build(m, false); // same call, new state (attached / closed / queue): rebuild still, bar for what is left
    else {                                     // same card: only the live bits
      const u = root.querySelector('.cp-units'); const h = unitsHtml(c); if (u && u.innerHTML !== h) u.innerHTML = h;
      live(m);
    }
    cur = { seq: m.seq, sig };
  }

  function live(m) {
    const root = box();
    if (m.seq !== cur.seq && cur.seq !== -1 && m.action === 'cpopLive') return;
    setText(root, '.cp-age', ageTxt(m.age || 0));
    const d = root.querySelector('.cp-dist');
    if (d) { d.classList.toggle('hidden', m.dist == null); setText(root, '.cp-dist', distTxt(m.dist)); }
  }

  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
    if (m && m.action === 'cpop') draw(m);
    else if (m && m.action === 'cpopLive') live(m);
  });
})();
