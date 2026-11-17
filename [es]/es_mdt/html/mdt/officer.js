// es_mdt 1.7.0: officer profiles (personnel files) and the department's certifications.
// es_departments decides what each viewer sees (super / self / peer); this page only draws it.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, said, busy, ago, date, dateTime, modal, confirmBox, pill, empty, go, VIEWS, HOOK, toast, dur, isoDay, certBadges, ccv, tabBadge, RO, P } = M;
  const arr = (x) => Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.values(x) : []);
  const hrs = (s) => { const h = (s || 0) / 3600; return h >= 10 ? Math.round(h) + ' h' : (Math.round(h * 10) / 10) + ' h'; };
  const initials = (n) => String(n || '?').split(' ').filter(Boolean).map((w) => w[0]).join('').slice(0, 2).toUpperCase();
  const span = (t) => {   // "1 year 2 months", "3 weeks", "5 days"
    if (!t) return '—';
    const d = Math.max(0, Math.floor((Date.now() / 1000 - t) / 86400));
    if (d < 1) return 'today';
    if (d < 14) return d + ' day' + (d === 1 ? '' : 's');
    if (d < 60) return Math.floor(d / 7) + ' weeks';
    const mo = Math.floor(d / 30.4);
    if (mo < 12) return mo + ' months';
    const y = Math.floor(mo / 12), r = mo % 12;
    return y + ' year' + (y === 1 ? '' : 's') + (r ? ' ' + r + ' month' + (r === 1 ? '' : 's') : '');
  };
  const LVL = ['', 'Note', 'Warning', 'Step in'];
  const ENTRY = { commend: ['🏅', 'Commendation', 'on'], warning: ['⚠', 'Written warning', 'warn'], suspension: ['⛔', 'Suspension', 'bad'], note: ['📝', 'Note', ''] };
  const TL_ICO = { hired: '➕', left: '🚪', promoted: '⬆', demoted: '⬇', rank: '⇄', cert_grant: '🎖', cert_renew: '🔁', cert_revoke: '✕', cert_expired: '⌛', inactive: '💤', loa: '☂',
    entry_commend: '🏅', entry_warning: '⚠', entry_suspension: '⛔', entry_note: '📝', fto_queued: '🎓', fto_assigned: '👤', fto_phase_done: '🏁', fto_ready: '⭐', fto_completed: '🎓', fto_promoted: '⬆', fto_left: '✕', fto_recommended: '👍' };
  const TL_CLS = { promoted: 'up', fto_completed: 'up', entry_commend: 'up', cert_grant: 'cert', cert_renew: 'cert', demoted: 'down', entry_warning: 'warn', entry_suspension: 'down', cert_revoke: 'down', cert_expired: 'warn', inactive: 'warn', left: 'down' };
  const TL_GROUP = (k) => /^(hired|left|promoted|demoted|rank)$/.test(k) ? 'rank' : /^fto_/.test(k) ? 'training' : /^cert_/.test(k) ? 'certs' : /^entry_/.test(k) ? 'record' : 'other';

  // ---------------------------------------------------------------- the profile
  VIEWS.officer = async (v, arg) => {
    const charId = +arg || (S.ctx && S.ctx.me.charId);
    const r = await call('officerProfile', { charId });
    if (S.view !== 'officer') return;
    if (!r.ok) { v.innerHTML = `<div class="v-head"><div class="v-title">Officer profile</div></div>${empty(r.why || 'Could not open that profile', '👤')}`; return; }
    const F = r.data;
    ['depts', 'timeline', 'training', 'certs', 'certDefs'].forEach((k) => { F[k] = arr(F[k]); });
    F.certDefs.forEach((c) => { c.prereqs = arr(c.prereqs); });
    if (F.view === 'self') F.timeline.forEach((x) => { if (x.training) x.training.self = true; });
    F.duty = F.duty || {}; F.duty.weeks = arr(F.duty.weeks);
    S.offTab = S.offTab && S.offFor === charId ? S.offTab : 'overview'; S.offFor = charId;
    draw(v, F, charId);
  };

  function statusPill(m) {
    if (m.former) return pill('Former member', 'off');
    if (m.onDuty) return pill('On duty', 'on');
    if (m.onLeave) return '<span class="pill leave">On leave</span>';
    if (m.level) return `<span class="lv lv-${['', 'note', 'warn', 'act'][m.level]}" title="${m.inactiveDays} days off duty">💤 ${LVL[m.level]} · ${m.inactiveDays} d</span>`;
    return pill('Off duty', 'off');
  }

  function draw(v, F, charId) {
    const m = F.member, full = F.view !== 'peer', can = F.can || {}, self = F.view === 'self';
    const tabs = [['overview', 'Overview'], ['timeline', 'Career'], ['certs', 'Certifications', (F.certs || []).filter((c) => c.state === 'expiring' || c.state === 'expired').length]]
      .concat(full ? [['record', 'Commendations & discipline', 0]] : []).concat([['training', 'Training']]);
    const photo = F.photo && F.photo.image;
    const active = (F.certs || []).filter((c) => !c.revokedAt);
    v.innerHTML = `
      <div class="of-hero" style="--d1:${esc(F.dept.color1 || '#1b2a5c')};--d2:${esc(F.dept.color2 || '#f2c230')}">
        <div class="of-photo${can.photo ? ' edit' : ''}" id="of-photo" title="${photo ? (F.photo.from === 'photo' ? 'Profile photo' : F.photo.from === 'mugshot' ? 'From their MDT mugshot' : 'Character portrait') : 'No photo yet'}">
          ${photo ? `<img src="${photo}" alt="">` : `<span>${esc(initials(m.name))}</span>`}${can.photo ? '<b class="of-cam">📷 Change</b>' : ''}</div>
        <div class="of-main">
          <div class="of-name">${esc(m.name)} ${statusPill(m)} ${self ? pill('you', '') : ''} ${F.view === 'super' ? '<span class="pill accent" title="You see the full file">Supervisor view</span>' : ''}</div>
          <div class="of-sub">${m.callsign ? `<span class="of-tag">📟 ${esc(m.callsign)}</span>` : ''}${m.badge && m.badge !== m.callsign ? `<span class="of-tag">🛡 Badge ${esc(m.badge)}</span>` : ''}
            ${m.roleName ? `<span class="of-tag rank">${esc(m.roleName)}</span>` : ''}${(F.depts || []).map((x) => `<span class="of-dept" style="${ccv(x.color2).replace(/--cc/g, '--dc')}" title="${esc(x.name)}${x.roleName ? ' · ' + esc(x.roleName) : ''}">${esc(x.short)}${x.id !== F.dept.id && x.roleName ? ' · ' + esc(x.roleName) : ''}</span>`).join('')}</div>
          <div class="of-meta">
            <div><span>Hired</span><b>${m.hiredAt ? date(m.hiredAt) : '—'}</b><i>${m.hiredAt ? span(m.hiredAt) : ''}</i></div>
            <div><span>Time in rank</span><b>${m.rankSince ? span(m.rankSince) : '—'}</b><i>${m.rankSince ? 'since ' + date(m.rankSince) : ''}</i></div>
            <div><span>Last on duty</span><b>${m.onDuty ? 'Now' : m.lastDuty ? ago(m.lastDuty) : 'Never'}</b><i>${!m.onDuty && m.lastDuty ? dateTime(m.lastDuty) : ''}</i></div>
            <div><span>Total on duty</span><b>${hrs(F.duty.all)}</b><i>${hrs(F.duty.d30)} in 30 days</i></div>
          </div>
          ${active.length ? `<div class="of-certs">${certBadges(active)}</div>` : ''}
        </div>
        <div class="of-act">
          ${can.certs ? '<button class="btn accent" id="of-grant">🎖 Certification</button>' : ''}
          ${can.entries ? '<button class="btn" id="of-entry">🏅 Add to record</button>' : ''}
          ${(F.training || []).some((t) => t.deptId === S.ctx.dept.id) && (S.ctx.staff || P().fto_train || P().fto_manage || self) ? '<button class="btn ghost" id="of-train">🎓 Training file</button>' : ''}
        </div>
      </div>
      <div class="tabs">${tabs.map(([k, l, n]) => `<button class="tab${S.offTab === k ? ' on' : ''}" data-oft="${k}">${l}${n ? tabBadge(n, 'warn') : ''}</button>`).join('')}</div>
      <div id="of-body"></div>`;
    $$('[data-oft]', v).forEach((b) => b.onclick = () => { S.offTab = b.dataset.oft; $$('[data-oft]', v).forEach((x) => x.classList.toggle('on', x === b)); body(F, charId); });
    const reload = () => { if (S.view === 'officer') VIEWS.officer($('#view'), charId); };
    if (can.photo) $('#of-photo').onclick = () => photoModal(F, charId, reload);
    if ($('#of-grant')) $('#of-grant').onclick = () => grantModal(F, charId, reload);
    if ($('#of-entry')) $('#of-entry').onclick = () => entryModal(F, charId, reload);
    if ($('#of-train')) $('#of-train').onclick = () => go('training', self ? 'me' : { charId });
    body(F, charId);
  }

  function body(F, charId) {
    const box = $('#of-body'); if (!box) return;
    const t = S.offTab;
    const reload = () => { if (S.view === 'officer') VIEWS.officer($('#view'), charId); };
    if (t === 'overview') box.innerHTML = overview(F);
    else if (t === 'timeline') { box.innerHTML = timelineView(F); wireTimeline(box, F); }
    else if (t === 'certs') { box.innerHTML = certsView(F); wireCerts(box, F, charId, reload); }
    else if (t === 'record') { box.innerHTML = recordView(F); wireRecord(box, F, charId, reload); }
    else if (t === 'training') box.innerHTML = trainingView(F);
    $$('[data-oft-go]', box).forEach((b) => b.onclick = () => { S.offTab = b.dataset.oftGo; $$('[data-oft]').forEach((x) => x.classList.toggle('on', x.dataset.oft === S.offTab)); body(F, charId); });
    $$('[data-tfile]', box).forEach((b) => b.onclick = () => go('training', F.view === 'self' ? 'me' : { charId }));
  }

  // ---------------------------------------------------------------- overview: numbers, the weekly chart, the latest lines
  function overview(F) {
    const s = F.stats || {}, d = F.duty || {};
    const k = (key, label, ico) => s[key] ? `<div class="of-kpi"><span class="of-ki">${ico}</span><b>${s[key].all}</b><span>${label}</span><i>${s[key].d30} in 30 days</i></div>` : '';
    const weeks = d.weeks || [], max = Math.max(3600, ...weeks);
    const wk = (i) => { const end = new Date(Date.now() - (12 - i - 1) * 7 * 86400000); return end.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };
    const recent = (F.timeline || []).slice(0, 6);
    const c = F.counts;
    return `<div class="of-grid">
      <div>
        <div class="card"><div class="card-title">Hours on duty</div>
          <div class="of-hours"><div><b>${hrs(d.all)}</b><span>all time</span></div><div><b>${hrs(d.d30)}</b><span>last 30 days</span></div><div><b>${hrs(d.d7)}</b><span>last 7 days</span></div></div>
          <div class="of-chart" title="Hours on duty per week, the last 12 weeks">${weeks.map((x, i) => `<div class="of-bar" title="Week to ${wk(i)}: ${hrs(x)}"><i style="height:${Math.max(x ? 4 : 0, Math.round((x / max) * 100))}%"></i><span>${i % 2 === 1 ? wk(i) : ''}</span></div>`).join('')}</div>
          <div class="hint">Each bar is one week, newest on the right. Hover a bar for its hours.</div></div>
        <div class="card mt"><div class="card-title">On the job</div><div class="of-kpis">
          ${k('arrests', 'arrests', '⛓')}${k('citations', 'citations', '🧾')}${k('reports', 'reports written', '📄')}${k('warrants', 'warrants issued', '⚖')}
          ${k('evidence', 'evidence collected', '🔍')}${k('jail', 'jail sentences', '▥')}${k('calls', 'calls responded', '☎')}</div></div>
      </div>
      <div>
        ${c ? `<div class="card"><div class="card-title">Record</div><div class="of-rec">
          <div class="on"><b>${c.commend}</b><span>🏅 commendations</span></div><div class="warn"><b>${c.warning}</b><span>⚠ warnings</span></div>
          <div class="bad"><b>${c.suspension}</b><span>⛔ suspensions</span></div>${F.view === 'super' ? `<div><b>${c.note}</b><span>📝 notes</span></div>` : ''}</div>
          <button class="btn small ghost mt" data-oft-go="record">Open the record ›</button></div>` : ''}
        <div class="card${c ? ' mt' : ''}"><div class="card-title">Latest</div>${recent.length ? `<div class="of-tl">${recent.map(tlItem).join('')}</div><button class="btn small ghost mt" data-oft-go="timeline">Full career ›</button>` : empty('Nothing on file yet')}</div>
        ${F.asFto && (F.asFto.dors || F.asFto.current) ? `<div class="card mt"><div class="card-title">As an FTO</div><div class="of-rec">
          <div><b>${F.asFto.trainees}</b><span>trainees</span></div><div class="on"><b>${F.asFto.graduated}</b><span>graduated</span></div><div><b>${F.asFto.dors}</b><span>DORs written</span></div><div><b>${hrs(F.asFto.minutes * 60)}</b><span>training</span></div></div></div>` : ''}
      </div></div>`;
  }

  function tlItem(x) {
    const ico = TL_ICO[x.kind] || '•', cls = TL_CLS[x.kind] || '';
    return `<div class="of-tli ${cls}"><span class="of-tld">${ico}</span><div class="li-main">
      <b>${esc(x.title)}${x.private ? ' <span class="pill" title="Only supervisors see this">🔒 private</span>' : ''}${x.days ? ` <span class="pill bad">${x.days} day${x.days === 1 ? '' : 's'}</span>` : ''}</b>
      ${x.detail ? `<span>${esc(x.detail)}</span>` : ''}${x.reason ? `<span class="of-why">“${esc(x.reason)}”</span>` : ''}
      <span class="hint">${date(x.at)}${x.dept ? ' · ' + esc(x.dept) : ''}${x.by ? ' · by ' + esc(x.by) : ''}${x.backfill ? ' · from records' : ''}${x.training && S.ctx && x.training.deptId === S.ctx.dept.id && (S.ctx.staff || P().fto_train || P().fto_manage || x.training.self) ? ' · <a class="lnk" data-tfile>training file ›</a>' : ''}</span></div></div>`;
  }

  // ---------------------------------------------------------------- career timeline
  function timelineView(F) {
    const groups = [['all', 'Everything'], ['rank', '⬆ Rank'], ['training', '🎓 Training'], ['certs', '🎖 Certifications']]
      .concat(F.view !== 'peer' ? [['record', '🏅 Record'], ['other', '☂ Leave & activity']] : []);
    S.offTlF = S.offTlF || 'all';
    return `<div class="card"><div class="row between mb"><div class="seg" id="of-tlf">${groups.map(([k, l]) => `<button data-tlf="${k}" class="${S.offTlF === k ? 'on' : ''}">${l}</button>`).join('')}</div>
      <span class="hint">${F.view === 'peer' ? 'Colleagues see rank, training and certifications. The rest is for the officer and supervisors.' : 'Newest first'}</span></div><div class="of-tl big" id="of-tl"></div></div>`;
  }
  function wireTimeline(box, F) {
    const fill = () => {
      const list = (F.timeline || []).filter((x) => S.offTlF === 'all' || TL_GROUP(x.kind) === S.offTlF);
      $('#of-tl', box).innerHTML = list.length ? list.map(tlItem).join('') : empty('Nothing here');
      $$('[data-tfile]', box).forEach((b) => b.onclick = () => go('training', F.view === 'self' ? 'me' : { charId: F.member.charId }));
    };
    $$('[data-tlf]', box).forEach((b) => b.onclick = () => { S.offTlF = b.dataset.tlf; $$('[data-tlf]', box).forEach((x) => x.classList.toggle('on', x === b)); fill(); });
    fill();
  }

  // ---------------------------------------------------------------- certifications on the profile
  const ST = { valid: ['Valid', 'on'], expiring: ['Expiring', 'warn'], expired: ['Expired', 'bad'], revoked: ['Revoked', 'off'] };
  function certsView(F) {
    const list = F.certs || [], act = list.filter((c) => !c.revokedAt), old = list.filter((c) => c.revokedAt);
    const row = (c) => `<div class="of-cert ${c.state}" style="${ccv(c.color)}"><span class="of-cert-i">${esc(c.icon || '🎖')}</span>
      <div class="li-main"><b>${esc(c.name)} <span class="pill ${ST[c.state][1]}">${ST[c.state][0]}</span></b>
        <span class="hint">Granted ${date(c.grantedAt)}${c.grantedByName ? ' by ' + esc(c.grantedByName) : c.auto ? ' automatically' : ''}${c.expiresAt ? ` · ${c.state === 'expired' ? 'expired' : 'valid until'} <b>${date(c.expiresAt)}</b>` : ' · no expiry'}</span>
        ${c.note ? `<span class="of-why">“${esc(c.note)}”</span>` : ''}${c.revokedAt ? `<span class="hint">Revoked ${date(c.revokedAt)}${c.revokedByName ? ' by ' + esc(c.revokedByName) : ''}${c.revokeNote ? ' · ' + esc(c.revokeNote) : ''}</span>` : ''}</div>
      ${F.can.certs && !c.revokedAt ? `<div class="row"><button class="btn small" data-renew="${c.certId}">Renew</button><button class="btn small danger" data-revoke="${c.id}" data-cname="${esc(c.name)}">Revoke</button></div>` : ''}</div>`;
    return `<div class="card"><div class="row between mb"><div class="card-title" style="margin:0">Certifications</div>${F.can.certs ? '<button class="btn accent" id="of-grant2">+ Grant a certification</button>' : ''}</div>
      ${act.length ? act.map(row).join('') : empty(F.can.certs ? 'No certifications yet. Grant one with the button above.' : 'No certifications yet', '🎖')}</div>
      ${old.length ? `<div class="card mt"><div class="card-title">History</div>${old.map(row).join('')}</div>` : ''}`;
  }
  function wireCerts(box, F, charId, reload) {
    if ($('#of-grant2', box)) $('#of-grant2', box).onclick = () => grantModal(F, charId, reload);
    $$('[data-renew]', box).forEach((b) => b.onclick = () => grantModal(F, charId, reload, +b.dataset.renew));
    $$('[data-revoke]', box).forEach((b) => b.onclick = () => revokeModal(+b.dataset.revoke, b.dataset.cname, F.member.name, reload));
  }

  function grantModal(F, charId, reload, preset) {
    const defs = F.certDefs || [], held = {};
    (F.certs || []).forEach((c) => { if (!c.revokedAt && c.state !== 'expired') held[c.certId] = c; });
    const lvl = F.member.roleLevel || 0;
    const why = (c) => {
      if (c.minLevel && lvl < c.minLevel && !F.member.owner) return 'Rank too low';
      const miss = (c.prereqs || []).filter((p) => !held[p]).map((p) => (defs.find((d) => d.id === p) || {}).name).filter(Boolean);
      return miss.length ? 'Needs ' + miss.join(', ') : '';
    };
    let pick = preset ? defs.find((c) => c.id === preset) : null;
    modal(`<div class="m-title">${preset ? 'Renew' : 'Grant'} a certification · ${esc(F.member.name)}</div>
      <div class="of-cpick" id="gc-list">${defs.map((c) => { const w = why(c), h = held[c.id]; return `<button class="of-cp${w ? ' blocked' : ''}${pick && pick.id === c.id ? ' on' : ''}" data-gc="${c.id}" style="${ccv(c.color)}" title="${esc(w || (h ? 'Held: picking it renews it' : ''))}">
        <span class="of-cert-i">${esc(c.icon || '🎖')}</span><b>${esc(c.name)}</b><span class="hint">${h ? '✓ held · renew' : w ? '⚠ ' + esc(w) : c.months ? c.months + ' months' : 'no expiry'}</span></button>`; }).join('') || empty('This department has no certifications yet. Add them in Department → Certifications.')}</div>
      <div id="gc-form" class="${pick ? '' : 'hidden'}">
        <div class="grid"><div class="field"><label>Valid until</label><input type="date" id="gc-exp" min="${isoDay(new Date(Date.now() + 86400000))}"></div>
          <div class="field"><label>&nbsp;</label><label class="tr-chk"><input type="checkbox" id="gc-none"> No expiry</label></div></div>
        <div class="field"><label>Note <span class="hint">(optional: course, instructor, score…)</span></label><input id="gc-note" maxlength="300" placeholder="e.g. Passed the SWAT selection course"></div>
        <div class="confirm-line" id="gc-sum"></div>
      </div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="gc-go" data-primary disabled>${preset ? 'Renew' : 'Grant'}</button></div>`, (card, closeIt) => {
      card.classList.add('wide');
      const setPick = (c) => {
        pick = c; $$('[data-gc]', card).forEach((b) => b.classList.toggle('on', +b.dataset.gc === c.id));
        $('#gc-form', card).classList.remove('hidden'); $('#gc-go', card).disabled = false;
        $('#gc-none', card).checked = !c.months; $('#gc-exp', card).disabled = !c.months;
        $('#gc-exp', card).value = c.months ? isoDay(new Date(Date.now() + c.months * 30 * 86400000)) : '';
        sum();
      };
      const sum = () => {
        if (!pick) return;
        const w = why(pick), none = $('#gc-none', card).checked, ex = $('#gc-exp', card).value;
        $('#gc-sum', card).innerHTML = `${held[pick.id] ? 'Renewing' : 'Granting'} <b>${esc(pick.icon || '')} ${esc(pick.name)}</b> to <b>${esc(F.member.name)}</b>${none || !ex ? ', no expiry' : `, valid until <b>${new Date(ex + 'T12:00:00').toLocaleDateString()}</b>`}.${w ? ` <span class="txt-warn">⚠ ${esc(w)}: the server will refuse it.</span>` : ''}`;
      };
      $$('[data-gc]', card).forEach((b) => b.onclick = () => setPick(defs.find((c) => c.id === +b.dataset.gc)));
      $('#gc-none', card).onchange = () => { $('#gc-exp', card).disabled = $('#gc-none', card).checked; sum(); };
      $('#gc-exp', card).oninput = sum;
      if (pick) setPick(pick);
      $('#gc-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const none = $('#gc-none', card).checked, ex = $('#gc-exp', card).value;
        if (!none && !ex) { toast('Pick an expiry date or tick "No expiry"', 'err'); return; }
        if (said(await call('certGrant', { charId, certId: pick.id, note: $('#gc-note', card).value.trim(), expires: none ? null : ex, noExpiry: none }), `${pick.name} ${held[pick.id] ? 'renewed' : 'granted'}`)) { closeIt(); reload(); }
      });
    });
  }

  function revokeModal(holderId, cname, who, reload) {
    modal(`<div class="m-title">Revoke ${esc(cname)}</div><p class="hint">${esc(who)} loses the ${esc(cname)} certification now. It stays in their history with your reason.</p>
      <div class="field"><label>Reason</label><textarea id="rv-why" maxlength="300" rows="3" placeholder="Why it is revoked"></textarea></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn danger" id="rv-go" data-primary>Revoke</button></div>`, (card, closeIt) => {
      $('#rv-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const n = $('#rv-why', card).value.trim();
        if (n.length < 3) { toast('Say why it is revoked', 'err'); return; }
        if (said(await call('certRevoke', { holderId, note: n }), cname + ' revoked')) { closeIt(); reload(); }
      });
    });
  }

  // ---------------------------------------------------------------- commendations & discipline
  function recordView(F) {
    const list = (F.timeline || []).filter((x) => /^entry_/.test(x.kind));
    return `<div class="card"><div class="row between mb"><div class="card-title" style="margin:0">Commendations & discipline</div>${F.can.entries ? '<button class="btn accent" id="of-entry2">+ Add to record</button>' : ''}</div>
      ${F.view === 'self' ? '<div class="tr-info mb">This is your record. Private supervisor notes are not shown to you.</div>' : ''}
      ${list.length ? list.map((x) => `<div class="of-entry ${(ENTRY[x.kind.slice(6)] || [])[2] || ''}"><span class="of-tld">${(ENTRY[x.kind.slice(6)] || ['•'])[0]}</span><div class="li-main">
        <b>${esc(x.title)}${x.private ? ' <span class="pill" title="Only supervisors see this">🔒 supervisors only</span>' : ''}${x.days ? ` <span class="pill bad">${x.days} day${x.days === 1 ? '' : 's'}</span>` : ''}</b>
        ${x.reason ? `<div class="narr">${esc(x.reason).replace(/\n/g, '<br>')}</div>` : ''}<span class="hint">${dateTime(x.at)}${x.dept ? ' · ' + esc(x.dept) : ''}${x.by ? ' · by ' + esc(x.by) : ''}</span></div>
        ${F.can.entries ? `<button class="icon-btn" data-edel="${x.entryId}" title="Remove from the record">✕</button>` : ''}</div>`).join('') : empty('Nothing on the record', '🏅')}</div>`;
  }
  function wireRecord(box, F, charId, reload) {
    if ($('#of-entry2', box)) $('#of-entry2', box).onclick = () => entryModal(F, charId, reload);
    $$('[data-edel]', box).forEach((b) => b.onclick = async () => {
      if (!await confirmBox('Remove this entry?', 'It disappears from their record (the removal is logged).', 'Remove', true)) return;
      if (said(await call('personnelRemove', { id: +b.dataset.edel }), 'Entry removed')) reload();
    });
  }

  function entryModal(F, charId, reload) {
    let kind = 'commend';
    modal(`<div class="m-title">Add to ${esc(F.member.name)}'s record</div>
      <div class="of-kinds" id="en-kind">${Object.entries(ENTRY).map(([k, x]) => `<button data-ek="${k}" class="of-kind ${x[2]}${k === kind ? ' on' : ''}"><span>${x[0]}</span>${x[1]}</button>`).join('')}</div>
      <div class="field"><label>Title</label><input id="en-title" maxlength="100" placeholder="e.g. Outstanding pursuit termination"></div>
      <div class="field hidden" id="en-days-f"><label>Suspension length</label><div class="row"><input type="number" id="en-days" min="1" max="365" value="3" style="width:90px"><span class="hint">days</span></div></div>
      <div class="field"><label>Details</label><textarea id="en-body" maxlength="1000" rows="4" placeholder="What happened, when, who saw it"></textarea></div>
      <div class="field"><label>Who can see it</label><div class="seg" id="en-vis"><button data-vis="officer" class="on">👁 The officer and supervisors</button><button data-vis="supervisors">🔒 Supervisors only</button></div></div>
      <div class="confirm-line" id="en-sum"></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="en-go" data-primary>Add to record</button></div>`, (card, closeIt) => {
      let vis = 'officer';
      const sum = () => {
        const x = ENTRY[kind];
        $('#en-sum', card).innerHTML = `${x[0]} <b>${x[1]}</b> for <b>${esc(F.member.name)}</b> · ${vis === 'officer' ? 'they are told and can read it in My profile' : 'only supervisors see it'}.`;
      };
      const setVis = (v2) => { vis = v2; $$('[data-vis]', card).forEach((b) => b.classList.toggle('on', b.dataset.vis === v2)); sum(); };
      $$('[data-ek]', card).forEach((b) => b.onclick = () => {
        kind = b.dataset.ek; $$('[data-ek]', card).forEach((x) => x.classList.toggle('on', x === b));
        $('#en-days-f', card).classList.toggle('hidden', kind !== 'suspension');
        setVis(kind === 'note' ? 'supervisors' : 'officer');
      });
      $$('[data-vis]', card).forEach((b) => b.onclick = () => setVis(b.dataset.vis));
      sum();
      $('#en-go', card).onclick = (e) => busy(e.currentTarget, async () => {
        const title = $('#en-title', card).value.trim();
        if (title.length < 3) { toast('Give it a short title', 'err'); return; }
        if (said(await call('personnelAdd', { charId, kind, title, body: $('#en-body', card).value, visibility: vis, days: +$('#en-days', card).value || 0 }), ENTRY[kind][1] + ' added')) { closeIt(); S.offTab = 'record'; reload(); }
      });
    });
  }

  // ---------------------------------------------------------------- training
  function trainingView(F) {
    const T = F.training || [], A = F.asFto || {};
    const ST2 = { training: ['In training', 'warn'], promoted: ['Graduated', 'on'], signed_off: ['Graduated', 'on'], left: ['Left', 'off'] };
    return `<div class="cols2"><div class="card"><div class="card-title">Field training</div>${T.length ? T.map((t) => `<div class="of-trn">
        <div class="row between"><b>${esc(t.dept)} field training</b><span class="pill ${(ST2[t.status] || ['', ''])[1]}">${(ST2[t.status] || [t.status])[0]}</span></div>
        ${t.pct != null ? `<div class="of-prog"><i style="width:${t.pct}%"></i></div><span class="hint">${t.pct}% of the program signed off</span>` : ''}
        <div class="hint">Started ${date(t.startedAt)}${t.ftoName ? ` · FTO <a class="lnk" data-officer="${t.ftoCharId}">${esc(t.ftoName)}</a>` : ''}${t.doneAt ? ` · ${t.status === 'left' ? 'ended' : 'graduated'} ${date(t.doneAt)}${t.doneByName ? ' by ' + esc(t.doneByName) : ''}` : ''}</div>
        ${t.deptId === S.ctx.dept.id && (S.ctx.staff || P().fto_train || P().fto_manage || F.view === 'self') ? '<button class="btn small ghost mt" data-tfile>Open the training file ›</button>' : ''}</div>`).join('') : empty('No field training on file', '🎓')}</div>
      <div class="card"><div class="card-title">As an FTO</div>${A.dors || A.current ? `<div class="of-rec">
        <div><b>${A.trainees}</b><span>trainees</span></div><div class="on"><b>${A.graduated}</b><span>graduated</span></div><div><b>${A.current}</b><span>training now</span></div>
        <div><b>${A.dors}</b><span>DORs written</span></div><div><b>${hrs(A.minutes * 60)}</b><span>in training</span></div></div>${A.last ? `<div class="hint mt">Last DOR ${ago(A.last)}</div>` : ''}` : empty('Has not trained anyone yet', '👤')}</div></div>`;
  }

  // ---------------------------------------------------------------- the photo (live preview before anything is saved)
  function shrink(src, max) {
    return new Promise((res) => {
      const img = new Image();
      img.onload = () => {
        try {
          const k = Math.min(1, max / Math.max(img.width, img.height));
          const cv = document.createElement('canvas'); cv.width = Math.round(img.width * k); cv.height = Math.round(img.height * k);
          cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
          res(cv.toDataURL('image/jpeg', 0.86));
        } catch (e) { res(null); }   // a picture from another site may not be readable here: the server fetches it instead
      };
      img.onerror = () => res(null);
      img.crossOrigin = 'anonymous';
      img.src = src;
    });
  }
  function photoModal(F, charId, reload) {
    let ready = null, mode = 'upload', url = '';
    modal(`<div class="m-title">Profile photo · ${esc(F.member.name)}</div>
      <div class="seg mb" id="ph-tab"><button data-pt="upload" class="on">⬆ Upload</button><button data-pt="link">🔗 From a link</button>${(S.ctx && S.ctx.config && S.ctx.config.esEvidence === false) ? '' : '<button data-pt="roll">🖼 Camera roll</button>'}<button data-pt="reset">↺ Default</button></div>
      <div class="of-ph"><div id="ph-body"></div><div class="of-ph-prev" id="ph-prev">${F.photo && F.photo.image ? `<img src="${F.photo.image}" alt=""><span class="hint">Current</span>` : '<span class="hint">The preview shows here</span>'}</div></div>
      <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="ph-go" data-primary disabled>Use this photo</button></div>`, (card, closeIt) => {
      card.classList.add('wide');
      const prev = $('#ph-prev', card), go2 = $('#ph-go', card), bodyEl = $('#ph-body', card);
      const show = (src, note) => { prev.innerHTML = `<img src="${src}" alt=""><span class="hint">${note || 'Preview'}</span>`; };
      const setReady = (img, m2) => { ready = img; mode = m2 || mode; go2.disabled = !(ready || mode === 'link-server'); };
      const tab = (t) => {
        $$('[data-pt]', card).forEach((b) => b.classList.toggle('on', b.dataset.pt === t));
        ready = null; go2.disabled = true; go2.textContent = 'Use this photo'; go2.classList.remove('danger');
        if (t === 'upload') {
          mode = 'upload';
          bodyEl.innerHTML = `<label class="of-drop" id="ph-drop"><input type="file" id="ph-file" accept="image/png,image/jpeg,image/webp"><b>Choose a picture</b><span class="hint">or drop one here · PNG, JPG or WebP · it is resized for you</span></label>`;
          const take = async (file) => {
            if (!file || !/^image\//.test(file.type)) { toast('That is not a picture', 'err'); return; }
            const rd = new FileReader();
            rd.onload = async () => { const img = await shrink(rd.result, 640); if (!img) { toast('That picture could not be read', 'err'); return; } show(img, `${Math.round(img.length * 0.75 / 1024)} KB · ready`); setReady(img, 'upload'); };
            rd.readAsDataURL(file);
          };
          $('#ph-file', card).onchange = (e) => take(e.target.files[0]);
          const dz = $('#ph-drop', card);
          dz.ondragover = (e) => { e.preventDefault(); dz.classList.add('over'); };
          dz.ondragleave = () => dz.classList.remove('over');
          dz.ondrop = (e) => { e.preventDefault(); dz.classList.remove('over'); take(e.dataTransfer.files[0]); };
        } else if (t === 'link') {
          mode = 'link';
          bodyEl.innerHTML = `<div class="field"><label>Picture link <span class="hint">(https, jpg/png/webp)</span></label><input id="ph-url" maxlength="500" placeholder="https://…/photo.jpg"></div><p class="hint">The preview loads as you paste. Right-click a picture online and copy its image address.</p>`;
          let tm = null;
          $('#ph-url', card).oninput = (e) => { clearTimeout(tm); go2.disabled = true; tm = setTimeout(async () => {
            url = e.target.value.trim();
            if (!/^https?:\/\/\S+$/i.test(url)) { prev.innerHTML = `<span class="hint">${url ? 'A link starts with https://' : 'The preview shows here'}</span>`; return; }
            prev.innerHTML = '<div class="spin"></div>';
            const img = await shrink(url, 640);
            if (img) { show(img, 'Preview · ready'); setReady(img, 'upload'); return; }
            const probe = new Image();
            probe.onload = () => { prev.innerHTML = ''; prev.appendChild(probe); prev.insertAdjacentHTML('beforeend', '<span class="hint">Preview · the server fetches it</span>'); mode = 'link-server'; go2.disabled = false; };
            probe.onerror = () => { prev.innerHTML = '<span class="hint">The preview did not load. You can still try: the server checks it is a picture.</span>'; mode = 'link-server'; go2.disabled = false; };
            probe.src = url;
          }, 300); };
        } else if (t === 'roll') {
          mode = 'upload';
          bodyEl.innerHTML = '<p class="hint">Photos you took with the camera item. Pick one: it shows on the right.</p><div id="ph-roll"></div>';
          if (!M.rollPicker) { $('#ph-roll', card).innerHTML = empty('The camera roll is not available (es_evidence)', '⚠'); return; }
          M.rollPicker($('#ph-roll', card), null, async (p) => { const img = await shrink(p.image, 640); if (img) { show(img, 'Preview · ready'); setReady(img, 'upload'); } });
        } else {
          mode = 'clear';
          bodyEl.innerHTML = '<p>Remove the profile photo. The profile then shows their latest MDT mugshot, or their character portrait.</p>';
          prev.innerHTML = '<span class="hint">Mugshot or portrait</span>';
          go2.disabled = false; go2.textContent = 'Remove photo'; go2.classList.add('danger');
        }
      };
      $$('[data-pt]', card).forEach((b) => b.onclick = () => tab(b.dataset.pt));
      tab('upload');
      go2.onclick = (e) => busy(e.currentTarget, async () => {
        const payload = mode === 'clear' ? { charId, mode: 'clear' } : mode === 'link-server' ? { charId, mode: 'link', url } : { charId, mode: 'upload', image: ready };
        if (said(await call('officerPhoto', payload), mode === 'clear' ? 'Photo removed' : 'Photo saved')) { closeIt(); reload(); }
      });
    });
  }

  // ---------------------------------------------------------------- Department → Certifications (the list, and what is expiring)
  const ICONS = ['🎓', '🛡', '🐕', '🚁', '⚓', '🏍', '🕵', '🗣', '🎯', '🚓', '⛑', '⭐', '🚒', '🔫', '📡', '🧪', '🚨', '🧭', '🏅', '🔧'];
  HOOK.deptCerts = async (box) => {
    box.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
    const r = await call('certs');
    if (!box.isConnected) return;
    if (!r.ok) { box.innerHTML = empty(r.why); return; }
    const X = r.data; X.list = arr(X.list); const ranks = arr(X.ranks).slice().sort((a, b) => (a.level || 0) - (b.level || 0));
    const L = X.list.map((c) => Object.assign({}, c, { prereqs: arr(c.prereqs).slice() }));
    let dirty = false;
    const alerts = arr(X.alerts);
    const draw = () => {
      const edit = X.canEdit && !RO();
      box.innerHTML = `${alerts.length ? `<div class="card mb"><div class="card-title">Expiring within ${X.alertDays} days, or expired ${tabBadge(alerts.length, 'warn')}</div>
          ${alerts.map((a) => `<div class="li click" data-officer="${a.charId}"><span class="cert-b ${a.state}" style="${ccv(a.color)}"><i>${esc(a.icon || '🎖')}</i>${esc(a.name)}</span><div class="li-main"><b>${esc(a.officer)}</b>
            <span class="hint">${a.state === 'expired' ? 'expired' : 'expires'} ${date(a.expiresAt)} · ${a.state === 'expired' ? 'renew or revoke it on their profile' : Math.max(0, Math.ceil((a.expiresAt - Date.now() / 1000) / 86400)) + ' days left'}</span></div>${pill(a.state === 'expired' ? 'Expired' : 'Expiring', a.state === 'expired' ? 'bad' : 'warn')}</div>`).join('')}</div>` : ''}
        <div class="card"><div class="row between mb"><div><div class="card-title" style="margin:0">Certifications</div><div class="hint">Each officer's certifications show on their profile and the roster. ${X.gateFto ? `<b>FTO gate is ON:</b> being an FTO also needs a valid "${esc(X.ftoCert)}" cert.` : 'Grant them from an officer\'s profile.'}</div></div>
          ${edit ? '<button class="btn accent-ghost" id="ct-add">+ Add certification</button>' : ''}</div>
          <div class="ct-list">${L.map((c, i) => `<div class="ct-row" style="${ccv(c.color)}">
            <div class="ct-top"><button class="ct-ico" data-ico="${i}" ${edit ? '' : 'disabled'} title="Pick an icon">${esc(c.icon || '🎖')}</button>
              <input data-cn="${i}" maxlength="40" value="${esc(c.name)}" ${edit ? '' : 'disabled'} placeholder="Name">
              <input type="color" data-cc="${i}" value="${esc(c.color || '#3b82f6')}" ${edit ? '' : 'disabled'} title="Colour">
              <span class="hint ct-n" title="Officers holding it">${c.holders || 0} held${c.soon ? ` · <b class="txt-warn">${c.soon} expiring</b>` : ''}${c.expired ? ` · <b class="txt-bad">${c.expired} expired</b>` : ''}</span>
              ${edit ? `<button class="btn small ghost" data-cm="${i}:-1" ${i === 0 ? 'disabled' : ''}>↑</button><button class="btn small ghost" data-cm="${i}:1" ${i === L.length - 1 ? 'disabled' : ''}>↓</button><button class="icon-btn" data-cdel="${i}" title="Retire it">✕</button>` : ''}</div>
            <div class="ct-opts">
              <label>Expires after <input type="number" data-cmo="${i}" min="1" max="120" value="${c.months || ''}" placeholder="never" ${edit ? '' : 'disabled'}> months</label>
              <label>Needs rank <select data-crk="${i}" ${edit ? '' : 'disabled'}><option value="">Any rank</option>${ranks.map((k) => `<option value="${k.level}"${c.minLevel === k.level ? ' selected' : ''}>${esc(k.name)}+</option>`).join('')}</select></label>
              <label>Given automatically <select data-cau="${i}" ${edit ? '' : 'disabled'}><option value="">No</option><option value="graduate"${c.auto === 'graduate' ? ' selected' : ''}>On graduating training</option><option value="fto"${c.auto === 'fto' ? ' selected' : ''}>When made an FTO</option></select></label>
              <span class="ct-pre"><span class="lbl">Needs first</span>${L.filter((o, j) => j !== i && o.name).map((o) => `<label class="chip-t"><input type="checkbox" data-cpre="${i}" value="${o.id || 'n:' + o.name}"${c.prereqs.some((p) => p === o.id || p === o.name) ? ' checked' : ''} ${edit ? '' : 'disabled'}><span>${esc(o.icon || '')} ${esc(o.name)}</span></label>`).join('') || '<span class="hint">—</span>'}</span>
            </div></div>`).join('') || empty('No certifications yet')}</div>
          ${edit ? `<div class="tr-savebar${dirty ? ' on' : ''}" id="ct-bar"><span>Unsaved changes</span><button class="btn ghost" id="ct-undo">Undo</button><button class="btn accent" id="ct-save">Save certifications</button></div>` : ''}</div>`;
      if (!edit) return;
      const mark = () => { dirty = true; S.dirty = true; const b = $('#ct-bar', box); if (b) b.classList.add('on'); };
      $$('[data-cn]', box).forEach((el) => el.oninput = () => { L[+el.dataset.cn].name = el.value; mark(); });
      $$('[data-cc]', box).forEach((el) => el.oninput = () => { L[+el.dataset.cc].color = el.value; el.closest('.ct-row').setAttribute('style', ccv(el.value)); mark(); });
      $$('[data-cmo]', box).forEach((el) => el.oninput = () => { L[+el.dataset.cmo].months = el.value ? +el.value : null; mark(); });
      $$('[data-crk]', box).forEach((el) => el.onchange = () => { L[+el.dataset.crk].minLevel = el.value ? +el.value : null; mark(); });
      $$('[data-cau]', box).forEach((el) => el.onchange = () => { L[+el.dataset.cau].auto = el.value || null; mark(); });
      $$('[data-cpre]', box).forEach((el) => el.onchange = () => {
        const c = L[+el.dataset.cpre], v2 = el.value.startsWith('n:') ? el.value.slice(2) : +el.value;
        c.prereqs = c.prereqs.filter((p) => p !== v2); if (el.checked) c.prereqs.push(v2); mark();
      });
      $$('[data-ico]', box).forEach((b) => b.onclick = () => {
        const i = +b.dataset.ico;
        modal(`<div class="m-title">Pick an icon</div><div class="ct-icons">${ICONS.map((x) => `<button data-pi="${x}">${x}</button>`).join('')}</div>
          <div class="field"><label>Or type one</label><input id="pi-own" maxlength="4" placeholder="🔰"></div><div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn accent" id="pi-go" data-primary>Use it</button></div>`, (card, closeIt) => {
          $$('[data-pi]', card).forEach((x) => x.onclick = () => { L[i].icon = x.dataset.pi; mark(); closeIt(); draw(); });
          $('#pi-go', card).onclick = () => { const v2 = $('#pi-own', card).value.trim(); if (v2) { L[i].icon = v2; mark(); } closeIt(); draw(); };
        });
      });
      $$('[data-cm]', box).forEach((b) => b.onclick = () => { const [i, dd] = b.dataset.cm.split(':').map(Number); const j = i + dd; if (j < 0 || j >= L.length) return; [L[i], L[j]] = [L[j], L[i]]; mark(); draw(); });
      $$('[data-cdel]', box).forEach((b) => b.onclick = async () => {
        const c = L[+b.dataset.cdel];
        if (c.holders && !await confirmBox('Retire ' + c.name + '?', `${c.holders} officer${c.holders === 1 ? '' : 's'} hold it. It disappears from their profiles and the roster when you save (history stays).`, 'Retire', true)) return;
        L.splice(+b.dataset.cdel, 1); L.forEach((o) => { o.prereqs = o.prereqs.filter((p) => p !== c.id && p !== c.name); }); mark(); draw();
      });
      if ($('#ct-add', box)) $('#ct-add', box).onclick = () => { L.push({ name: '', icon: '🎖', color: '#3b82f6', months: 12, minLevel: null, auto: null, prereqs: [] }); mark(); draw(); const ins = $$('[data-cn]', box); ins[ins.length - 1].focus(); };
      $('#ct-undo', box).onclick = () => { S.dirty = false; HOOK.deptCerts(box); };
      $('#ct-save', box).onclick = (e) => busy(e.currentTarget, async () => {
        if (L.some((c) => !(c.name || '').trim())) { toast('Every certification needs a name', 'err'); return; }
        const list = L.map((c) => ({ id: c.id, name: c.name.trim(), icon: c.icon, color: c.color, months: c.months || null, minLevel: c.minLevel || null, auto: c.auto || null, prereqs: c.prereqs }));
        if (said(await call('certsSave', { list }), 'Certifications saved')) { S.dirty = false; HOOK.deptCerts(box); }
      });
    };
    draw();
  };
})();
