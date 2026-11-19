// es_doj page core. Talks to client/main.lua ('call' -> es_doj:<name> on the tablet, es_doj:pub:<name> in the portal).
// The server decides everything; the page only asks and draws. Views live in cases.js, court.js, office.js and portal.js.
(function () {
  'use strict';
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'es_mdt';   // 2.0.0: one resource (es_mdt)
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');
  const S = { open: false, mode: null, me: null, dept: null, lists: {}, view: null, arg: null, back: [], logos: {}, counts: {}, home: null, dirty: false, extra: null };

  async function post(path, data) {
    try {
      const r = await fetch(`https://${RES}/doj_${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) });
      return await r.json();
    } catch (e) { return { ok: false, why: 'The game did not answer' }; }
  }
  const call = (name, data) => post('call', { name, data: data || {} });

  // ---------------------------------------------------------------- small tools
  let toastTimer = null;
  function toast(text, kind) {
    const t = $('#toast');
    t.innerHTML = `<span class="t-dot"></span><span>${esc(text)}</span>`;
    t.className = 'toast show ' + (kind || '');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 3600);
  }
  function said(r, okText) {
    if (r && r.ok) { if (okText) toast(okText, 'ok'); return true; }
    toast((r && r.why) || 'That did not work', 'err');
    return false;
  }
  async function busy(btn, fn) {
    if (btn && btn.disabled) return;
    if (btn) { btn.disabled = true; btn.classList.add('loading'); }
    try { return await fn(); } finally { if (btn) { btn.disabled = false; btn.classList.remove('loading'); } }
  }
  function ago(t) {
    if (!t) return '—';
    const s = Date.now() / 1000 - t;
    if (s < 0) return inTime(t);
    if (s < 60) return 'just now';
    if (s < 3600) return Math.floor(s / 60) + ' min ago';
    if (s < 86400) return Math.floor(s / 3600) + ' h ago';
    const d = Math.floor(s / 86400); return d === 1 ? 'yesterday' : d + ' days ago';
  }
  function inTime(t) {
    const s = t - Date.now() / 1000;
    if (s <= 0) return ago(t);
    if (s < 3600) return 'in ' + Math.max(1, Math.round(s / 60)) + ' min';
    if (s < 86400) return 'in ' + Math.round(s / 3600) + ' h';
    const d = Math.round(s / 86400); return d === 1 ? 'tomorrow' : 'in ' + d + ' days';
  }
  const date = (t) => t ? new Date(t * 1000).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) : '—';
  const dateTime = (t) => t ? new Date(t * 1000).toLocaleString(undefined, { weekday: 'short', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—';
  const timeOnly = (t) => t ? new Date(t * 1000).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' }) : '—';
  const pill = (txt, cls) => `<span class="pill ${cls || ''}">${esc(txt)}</span>`;
  const empty = (txt, ico) => `<div class="empty-state"><div class="es-ico">${ico || '◌'}</div>${esc(txt)}</div>`;
  const loading = () => '<div class="loading-row"><div class="spin"></div></div>';
  const cap = (s) => { s = String(s || '').replace(/_/g, ' '); return s.charAt(0).toUpperCase() + s.slice(1); };
  const labelOf = (list, key) => { const x = (list || []).find((i) => i.key === key); return x ? x.label : cap(key); };
  const kindTag = (k) => `<span class="kind k-${esc(k)}">${esc(labelOf(S.lists.caseKinds, k))}</span>`;
  const stageLabel = (k) => labelOf(S.lists.stages, k);
  const R = () => (S.me && S.me.r) || {};
  const RO = () => !!(S.me && S.me.readOnly);
  const has = (...keys) => !RO() && keys.some((k) => R()[k]);
  const isoLocal = (t) => { const d = new Date(t * 1000); const p = (n) => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; };
  const fromLocal = (v) => { const t = new Date(v).getTime(); return isNaN(t) ? 0 : Math.floor(t / 1000); };
  const VERDICT = { none: 'No verdict', guilty: 'Guilty', not_guilty: 'Not guilty', dismissed: 'Dismissed', plea: 'Plea deal', plaintiff: 'For the plaintiff',
    defendant: 'For the defendant', settled: 'Settled', affirmed: 'Affirmed', reversed: 'Reversed', remanded: 'Remanded' };
  const verdictPill = (v) => !v || v === 'none' ? '' : pill(VERDICT[v] || cap(v), ['guilty', 'plaintiff', 'affirmed', 'plea'].includes(v) ? 'bad' : ['not_guilty', 'reversed', 'dismissed', 'defendant'].includes(v) ? 'on' : 'warn');
  const statusPill = (s) => pill(cap(s), s === 'open' ? 'gold' : s === 'dismissed' ? 'off' : '');
  const caseNo = (k) => `<span class="case-no">${esc(k.number || '#' + k.id)}</span>`;

  // ---------------------------------------------------------------- dialogs
  function modal(html, onReady, size) {
    const m = $('#modal'), card = $('#modal-card');
    card.className = 'modal-card' + (size ? ' ' + size : ''); card.innerHTML = html; m.classList.remove('hidden');
    requestAnimationFrame(() => m.classList.add('shown'));
    let closed = false;
    const closeIt = () => { if (closed) return; closed = true; m.classList.remove('shown'); setTimeout(() => { if (closed && m._owner === closeIt) { m.classList.add('hidden'); card.innerHTML = ''; } }, 150); if (S.dirty) { S.dirty = false; setTimeout(rerender, 160); } };
    m._owner = closeIt;
    $$('[data-x]', card).forEach((b) => b.addEventListener('click', closeIt));
    if (onReady) onReady(card, closeIt);
    const first = $('input:not([type=checkbox]):not([type=file]), textarea, select', card); if (first) first.focus();
    return closeIt;
  }
  const modalOpen = () => !$('#modal').classList.contains('hidden');
  function closeModal() { const m = $('#modal'); if (m._owner) m._owner(); }

  function confirmBox(title, text, yes, danger) {
    return new Promise((res) => {
      let answered = false;
      modal(`<div class="m-title">${esc(title)}</div><p class="m-text">${esc(text)}</p>
        <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn ${danger ? 'danger' : 'gold'}" id="m-yes">${esc(yes || 'Yes')}</button></div>`,
      (card, closeIt) => {
        $('#m-yes', card).onclick = () => { answered = true; closeIt(); res(true); };
        $$('[data-x]', card).forEach((b) => b.addEventListener('click', () => { if (!answered) res(false); }));
      });
    });
  }

  // A search box that finds a person; onPick({charId, name})
  function personPicker(host, placeholder, onPick, opts) {
    opts = opts || {};
    host.innerHTML = `<div class="picker-wrap"><input type="text" class="pp-in" placeholder="${esc(placeholder || 'Search a name or citizen ID…')}" autocomplete="off" spellcheck="false"><div class="pop hidden"></div></div>`;
    const inp = $('.pp-in', host), pop = $('.pop', host);
    let t = null, seq = 0;
    const minLen = S.mode === 'portal' ? 3 : 2;
    inp.addEventListener('input', () => {
      clearTimeout(t);
      const q = inp.value.trim();
      if (q.length < minLen) { pop.classList.add('hidden'); return; }
      t = setTimeout(async () => {
        const my = ++seq;
        const r = await call('people', { q });
        if (my !== seq) return;
        const list = (r.ok && r.data) || [];
        pop.innerHTML = list.length ? list.map((p) => `<div class="pop-row" data-id="${p.charId}" data-name="${esc(p.name)}"><b>${esc(p.name)}</b><span class="hint">#${p.charId}${p.dob ? ' · ' + esc(p.dob) : ''}</span></div>`).join('')
          : `<div class="pop-empty">Nobody found${S.mode === 'portal' ? '' : ' (try the citizen ID)'}</div>`;
        pop.classList.remove('hidden');
        $$('.pop-row', pop).forEach((row) => row.onmousedown = (e) => { e.preventDefault(); pop.classList.add('hidden'); inp.value = opts.keep ? row.dataset.name : ''; onPick({ charId: +row.dataset.id, name: row.dataset.name }); });
      }, 220);
    });
    inp.addEventListener('blur', () => setTimeout(() => pop.classList.add('hidden'), 150));
    return inp;
  }

  // A form in a dialog. fields: [{k,label,type,value,req,hint,opts,span2,min,max,placeholder,rows}]
  // types: text, textarea, number, money, select, datetime, person, check, choice, html. onSubmit(values, card) -> true | string (error) | Promise of either
  function form(title, fields, opts) {
    opts = opts || {};
    const fld = (f) => {
      const id = 'f-' + f.k; const v = f.value == null ? '' : f.value;
      let input = '';
      switch (f.type) {
        case 'textarea': input = `<textarea id="${id}" rows="${f.rows || 4}" placeholder="${esc(f.placeholder || '')}" maxlength="${f.max || 4000}">${esc(v)}</textarea>`; break;
        case 'number': input = `<input id="${id}" type="number" min="${f.min != null ? f.min : 0}" ${f.maxv != null ? `max="${f.maxv}"` : ''} value="${esc(v)}" placeholder="${esc(f.placeholder || '')}">`; break;
        case 'money': input = `<div class="money-in"><input id="${id}" type="number" min="0" ${f.maxv != null ? `max="${f.maxv}"` : ''} value="${esc(v)}" placeholder="0"></div>`; break;
        case 'select': input = `<select id="${id}">${(f.opts || []).map((o) => { const ov = typeof o === 'object' ? o.v : o, ol = typeof o === 'object' ? o.l : o; return `<option value="${esc(ov)}" ${String(ov) === String(v) ? 'selected' : ''}>${esc(ol)}</option>`; }).join('')}</select>`; break;
        case 'datetime': input = `<input id="${id}" type="datetime-local" value="${esc(v)}">`; break;
        case 'person': input = `<div id="${id}" class="pp-host"></div><div class="chosen" id="${id}-chosen"></div>`; break;
        case 'check': return `<label class="ck-item ${f.span2 ? 'span2' : ''}"><input id="${id}" type="checkbox" ${v ? 'checked' : ''}> <span>${esc(f.label)}${f.hint ? ` <span class="hint">${esc(f.hint)}</span>` : ''}</span></label>`;
        case 'choice': input = `<div class="choice" id="${id}">${(f.opts || []).map((o) => `<button type="button" data-v="${esc(o.v)}" class="${String(o.v) === String(v) ? 'on' : ''}"><b>${esc(o.l)}</b>${o.d ? `<span>${esc(o.d)}</span>` : ''}</button>`).join('')}</div>`; break;
        case 'html': return `<div class="${f.span2 ? 'span2' : ''}" id="${id}">${f.html || ''}</div>`;
        default: input = `<input id="${id}" type="text" value="${esc(v)}" placeholder="${esc(f.placeholder || '')}" maxlength="${f.max || 160}">`;
      }
      return `<div class="field ${f.req ? 'req' : ''} ${f.span2 ? 'span2' : ''}"><label for="${id}">${esc(f.label || '')}${f.hint ? ` <span class="hint">· ${esc(f.hint)}</span>` : ''}</label>${input}</div>`;
    };
    return new Promise((res) => {
      let done = false;
      modal(`<div class="m-title">${opts.ico ? `<span class="m-ico">${opts.ico}</span>` : ''}${esc(title)}</div>${opts.intro ? `<p class="m-text">${opts.intro}</p>` : ''}
        <div class="${opts.grid === false ? '' : 'grid'}">${fields.map(fld).join('')}</div>
        <div class="form-err" id="f-err"></div>
        <div class="row end"><button class="btn ghost" data-x>Cancel</button><button class="btn ${opts.danger ? 'danger' : 'gold'}" id="f-ok">${esc(opts.yes || 'Save')}</button></div>`,
      (card, closeIt) => {
        const picked = {};
        fields.forEach((f) => {
          if (f.type === 'person') {
            const host = $('#f-' + f.k, card), chosen = $('#f-' + f.k + '-chosen', card);
            const show = () => { chosen.innerHTML = picked[f.k] ? `<span class="chip">${esc(picked[f.k].name)} <span class="hint">#${picked[f.k].charId}</span><button type="button" title="Remove">✕</button></span>` : ''; const b = $('button', chosen); if (b) b.onclick = () => { picked[f.k] = null; show(); }; };
            if (f.value && f.value.charId) picked[f.k] = f.value;
            personPicker(host, f.placeholder, (p) => { picked[f.k] = p; show(); if (f.onPick) f.onPick(p, card); });
            show();
          } else if (f.type === 'choice') {
            $$('#f-' + f.k + ' button', card).forEach((b) => b.onclick = () => { $$('#f-' + f.k + ' button', card).forEach((x) => x.classList.toggle('on', x === b)); if (f.onChange) f.onChange(b.dataset.v, card); });
          } else if (f.onChange) {
            const el = $('#f-' + f.k, card); if (el) el.addEventListener(f.type === 'select' ? 'change' : 'input', () => f.onChange(el.value, card));
          }
        });
        if (opts.onReady) opts.onReady(card);
        const read = () => {
          const v = {};
          fields.forEach((f) => {
            const el = $('#f-' + f.k, card);
            if (f.type === 'person') v[f.k] = picked[f.k] || null;
            else if (f.type === 'check') v[f.k] = el.checked;
            else if (f.type === 'number' || f.type === 'money') v[f.k] = el.value === '' ? 0 : Math.floor(+el.value || 0);
            else if (f.type === 'datetime') v[f.k] = fromLocal(el.value);
            else if (f.type === 'choice') { const on = $('button.on', el); v[f.k] = on ? on.dataset.v : null; }
            else if (f.type === 'html') v[f.k] = null;
            else v[f.k] = el.value.trim();
          });
          return v;
        };
        const err = $('#f-err', card);
        const ok = $('#f-ok', card);
        ok.onclick = () => busy(ok, async () => {
          const v = read();
          for (const f of fields) {
            if (!f.req) continue;
            const x = v[f.k];
            if (x == null || x === '' || x === 0 && f.type !== 'number') { err.textContent = `${f.label || 'This'} is needed`; return; }
          }
          err.textContent = '';
          const r = opts.onSubmit ? await opts.onSubmit(v, card) : true;
          if (r === true) { done = true; closeIt(); res(v); } else if (typeof r === 'string') err.textContent = r;
        });
        $$('input[type=text], input[type=number]', card).forEach((i) => i.addEventListener('keydown', (e) => { if (e.key === 'Enter') ok.click(); }));
        $$('[data-x]', card).forEach((b) => b.addEventListener('click', () => { if (!done) res(null); }));
      }, opts.size);
    });
  }
  // the server's answer as the form's result: true, or its reason
  const answer = (r, okText) => { if (r && r.ok) { if (okText) toast(okText, 'ok'); return true; } return (r && r.why) || 'That did not work'; };

  // ---------------------------------------------------------------- pictures
  const imgCache = {};
  async function imageOf(name, data) {
    const k = name + ':' + JSON.stringify(data);
    if (imgCache[k]) return imgCache[k];
    const r = await call(name, data);
    if (r.ok && typeof r.data === 'string') { imgCache[k] = r.data; return r.data; }
    return null;
  }
  function lightbox(src, caption) {
    const lb = $('#lightbox'), img = $('#lb-img');
    img.src = ''; $('#lb-cap').textContent = caption || '';
    lb.classList.remove('hidden');
    if (typeof src === 'function') { img.alt = 'Loading…'; Promise.resolve(src()).then((s) => { if (s) img.src = s; else { lb.classList.add('hidden'); toast('That picture is gone', 'err'); } }); }
    else img.src = src;
  }
  // fill .thumb[data-img] elements lazily
  function lazyThumbs(root, name, dataOf) {
    $$('[data-img]', root).forEach(async (el) => {
      const src = await imageOf(name, dataOf(el));
      if (src) { el.style.backgroundImage = `url("${src}")`; el.textContent = ''; el.onclick = () => lightbox(src, el.dataset.cap); }
      else el.textContent = '⚠';
    });
  }

  async function logoOf(d) {
    if (!d || !d.id) return null;
    const k = d.id + ':' + (d.logoVer || 0);
    if (S.logos[k] !== undefined) return S.logos[k];
    const r = await post('logo', { id: d.id, ver: d.logoVer });
    S.logos[k] = (r && r.ok && r.data) || null;
    return S.logos[k];
  }

  // ---------------------------------------------------------------- frame and router
  const views = {};
  const NAV = {
    tablet: [
      { key: 'dashboard', label: 'Dashboard', ico: '◧' },
      { head: 'Court' },
      { key: 'cases', label: 'Cases', ico: '⚖', badge: () => S.counts.myCases, badgeCls: 'accent' },
      { key: 'calendar', label: 'Calendar', ico: '▦', badge: () => S.counts.today },
      { key: 'warrants', label: 'Warrants', ico: '✎', show: () => R().warrants || R().judge || R().leo || R().member, badge: () => S.counts.warrants, badgeCls: 'bad' },
      { head: 'Office' },
      { key: 'people', label: 'Records', ico: '☺' },
      { key: 'clerk', label: 'Clerk desk', ico: '✉', show: () => R().clerk || R().judge || R().cases || R().seal, badge: () => S.counts.petitions, badgeCls: 'warn' },
      { key: 'permits', label: 'Firearm permits', ico: '◎', show: () => R().permits, badge: () => S.counts.permits, badgeCls: 'warn' },
      { key: 'contests', label: 'Ticket contests', ico: '✎', show: () => R().judge || R().clerk || R().cases, badge: () => S.counts.contests, badgeCls: () => S.counts.contestsSoon ? 'bad' : 'warn' },   // 2.1.0
      { key: 'clients', label: 'My clients', ico: '☷', show: () => R().attorney || R().defender || R().prosecutor },
      { key: 'bar', label: 'Attorneys', ico: '⚑' },
      { key: 'penal', label: 'Penal code', ico: '§' },
      { key: 'activity', label: 'Activity log', ico: '≡', show: () => R().member || R().staff },
    ],
    portal: [
      { key: 'home', label: 'Overview', ico: '⌂' },
      { key: 'mycases', label: 'My cases', ico: '⚖', badge: () => S.home && S.home.cases.filter((k) => k.status === 'open').length },
      { key: 'pay', label: 'Payments', ico: '$', badge: () => S.home && (S.home.fees.fees.length + S.home.fees.fines.length), badgeCls: 'warn' },
      { key: 'ptickets', label: 'My tickets', ico: '✎', badge: () => S.home && S.home.tk && S.home.tk.unpaid, badgeCls: 'warn' },          // 2.1.0 (tickets.js)
      { key: 'pimpound', label: 'Impounded vehicles', ico: 'Ⓟ', badge: () => S.home && S.home.tk && S.home.tk.impounded, badgeCls: 'bad' },
      { key: 'petitions', label: 'Petitions', ico: '✎' },
      { key: 'lawyers', label: 'Lawyers', ico: '⚑' },
      { key: 'records', label: 'Public records', ico: '⌕' },
      { key: 'notices', label: 'Notices', ico: '✉', badge: () => S.home && S.home.unread, badgeCls: 'bad' },
    ],
  };
  function drawNav() {
    const list = NAV[S.mode] || [];
    const out = [];
    let pendingHead = null;
    list.forEach((n) => {
      if (n.head) { pendingHead = n.head; return; }
      if (n.show && !n.show()) return;
      if (pendingHead) { out.push(`<div class="nav-head">${esc(pendingHead)}</div>`); pendingHead = null; }
      const b = n.badge ? n.badge() : 0;
      out.push(`<button class="nav-item ${S.view === n.key || (S.parent === n.key) ? 'on' : ''}" data-nav="${n.key}"><span class="n-ico">${n.ico}</span>${esc(n.label)}${b ? `<span class="n-badge ${(typeof n.badgeCls === 'function' ? n.badgeCls() : n.badgeCls) || ''}">${b}</span>` : ''}</button>`);
    });
    $('#nav').innerHTML = out.join('');
    $$('[data-nav]').forEach((b) => b.onclick = () => go(b.dataset.nav, null, { root: true }));
  }
  function drawMe() {
    const me = S.me || {};
    if (S.mode === 'portal') {
      $('#me').innerHTML = `<div class="me-name">${esc(me.name || '')}</div><div class="me-sub">Citizen #${esc(me.charId || '')}${S.extra && S.extra.desk ? ' · at the clerk window' : ''}</div>`;
      $('#duty').innerHTML = ''; $('#to-mdt').classList.add('hidden'); return;
    }
    $('#me').innerHTML = `<div class="me-name">${esc(me.name || '')}</div><div class="me-role">${esc(me.roleName || '')}</div>${me.bar && me.bar.number ? `<div class="me-sub">Bar ${esc(me.bar.number)}</div>` : ''}`;
    const d = $('#duty');
    if (R().member) { d.className = 'duty' + (me.onDuty ? '' : ' off'); d.innerHTML = `<span class="dot"></span>${me.onDuty ? 'On duty' : 'Off duty'}`; } else d.innerHTML = '';
    const tm = $('#to-mdt');
    if (me.police) { tm.textContent = '⛨ ' + (me.police.short || 'Police') + ' MDT'; tm.classList.remove('hidden'); } else tm.classList.add('hidden');
    const va = $('#viewas');
    if (me.viewAs) { va.textContent = 'Viewing as ' + me.viewAs + ' (/dojtest role off)'; va.classList.remove('hidden'); } else va.classList.add('hidden');
    const ro = $('#ro-banner');
    if (me.readOnly) { ro.textContent = R().leo && !R().member ? 'Police view: read-only. You can follow cases, the calendar and the warrants you asked for.' : 'You are off duty: the DOJ tablet is read-only.'; ro.classList.remove('hidden'); }
    else ro.classList.add('hidden');
  }
  async function drawBrand() {
    const shell = $('.shell');
    shell.classList.toggle('portal', S.mode === 'portal'); document.body.classList.toggle('portal', S.mode === 'portal');
    $('#gsearch-wrap').classList.toggle('hidden', S.mode === 'portal');
    if (S.mode === 'portal') {
      $('#brand-short').textContent = 'Court Services';
      $('#brand-name').textContent = 'Superior Court of San Andreas';
      $('#brand-logo').innerHTML = '⚖';
    } else {
      const d = S.dept || {};
      $('#brand-short').innerHTML = esc(d.short || 'DOJ') + ' <span class="mdt-tag">MDT</span>';
      $('#brand-name').textContent = d.name || 'Department of Justice';
      if (d.color1) shell.style.setProperty('--d1', d.color1);
      const logo = await logoOf(d);
      $('#brand-logo').innerHTML = logo ? `<img src="${logo}" alt="">` : '⚖';
    }
  }

  function host() { return $('#view'); }
  async function go(view, arg, o) {
    o = o || {};
    if (!views[view]) view = S.mode === 'portal' ? 'home' : 'dashboard';
    if (o.root) S.back = [];
    else if (!o.replace && S.view && (S.view !== view || JSON.stringify(S.arg) !== JSON.stringify(arg))) S.back.push({ view: S.view, arg: S.arg, parent: S.parent });
    if (S.back.length > 20) S.back.shift();
    S.view = view; S.arg = arg == null ? null : arg; S.parent = o.parent || (o.root ? null : S.parent);
    if (o.root) S.parent = null;
    drawNav();
    const h = host();
    h.innerHTML = loading();
    h.scrollTop = 0;
    const token = S.token = (S.token || 0) + 1;
    try { await views[view](h, S.arg, () => token === S.token); }
    catch (e) { h.innerHTML = empty('This page broke: ' + e.message, '⚠'); console.error(e); }
    h.classList.remove('fade-in'); void h.offsetWidth; h.classList.add('fade-in');
  }
  function goBack() {
    const b = S.back.pop();
    if (b) { S.parent = b.parent; go(b.view, b.arg, { replace: true, parent: b.parent }); }
    else go(S.mode === 'portal' ? 'home' : 'dashboard', null, { root: true });
  }
  // a back link at the top of a sub-page
  const crumb = (txt) => `<span class="crumb" data-back>← ${esc(txt || 'Back')}</span>`;
  function wireBack(root) { $$('[data-back]', root).forEach((b) => b.onclick = goBack); }
  async function rerender() {
    if (!S.open || !S.view) return;
    if (modalOpen()) { S.dirty = true; return; }
    const keep = host().scrollTop;
    const token = S.token = (S.token || 0) + 1;
    const tmp = document.createElement('div');
    try { await views[S.view](tmp, S.arg, () => token === S.token); } catch (e) { console.error(e); return; }
    if (token !== S.token) return;
    host().innerHTML = ''; while (tmp.firstChild) host().appendChild(tmp.firstChild);
    host().scrollTop = keep;
  }

  async function counts() {
    if (S.mode === 'portal') {
      const r = await call('home');
      if (r.ok) { S.home = r.data; drawNav(); }
      return;
    }
    const r = await call('dashboard');
    if (r.ok) { S.counts = r.data.counts || {}; S.me = r.data.me; S.dash = r.data; drawNav(); drawMe(); }
  }

  // ---------------------------------------------------------------- global search (tablet)
  function wireSearch() {
    const inp = $('#gsearch'), pop = $('#gsearch-pop');
    let t = null, seq = 0;
    inp.addEventListener('input', () => {
      clearTimeout(t);
      const q = inp.value.trim();
      if (q.length < 2) { pop.classList.add('hidden'); return; }
      t = setTimeout(async () => {
        const my = ++seq;
        const [p, k] = await Promise.all([call('people', { q }), call('cases', { q, status: 'all' })]);
        if (my !== seq) return;
        const people = (p.ok && p.data) || [], cases = ((k.ok && k.data && k.data.rows) || []).slice(0, 6);
        let html = '';
        if (people.length) html += '<div class="pop-h">People</div>' + people.slice(0, 6).map((x) => `<div class="pop-row" data-p="${x.charId}"><b>${esc(x.name)}</b><span class="hint">#${x.charId}${x.dob ? ' · ' + esc(x.dob) : ''}</span></div>`).join('');
        if (cases.length) html += '<div class="pop-h">Cases</div>' + cases.map((x) => `<div class="pop-row" data-k="${x.id}">${caseNo(x)} <span class="ell">${esc(x.title)}</span><span class="hint">${esc(x.defendant || '')}</span></div>`).join('');
        pop.innerHTML = html || '<div class="pop-empty">Nothing found</div>';
        pop.classList.remove('hidden');
        $$('[data-p]', pop).forEach((r) => r.onmousedown = (e) => { e.preventDefault(); pop.classList.add('hidden'); inp.value = ''; go('person', +r.dataset.p, { parent: 'people' }); });
        $$('[data-k]', pop).forEach((r) => r.onmousedown = (e) => { e.preventDefault(); pop.classList.add('hidden'); inp.value = ''; go('case', +r.dataset.k, { parent: 'cases' }); });
      }, 220);
    });
    inp.addEventListener('blur', () => setTimeout(() => pop.classList.add('hidden'), 150));
  }

  // ---------------------------------------------------------------- open / close / refresh
  function openUi(msg) {
    S.mode = msg.mode === 'portal' ? 'portal' : 'tablet';
    S.lists = msg.lists || {};
    S.extra = msg.extra || null;
    S.back = []; S.view = null; S.parent = null;
    if (S.mode === 'portal') { S.home = msg.data; S.me = msg.data.me; }
    else { S.dash = msg.data; S.me = msg.data.me; S.dept = msg.data.dept; S.counts = msg.data.counts || {}; }
    S.open = true;
    $('#app').classList.remove('hidden');
    requestAnimationFrame(() => $('#app').classList.add('shown'));
    drawBrand(); drawMe();
    const start = S.mode === 'portal' ? ((S.extra && S.extra.view) || 'home') : 'dashboard';
    go(start, null, { root: true });
  }
  function closeUi(tell) {
    if (!S.open) return;
    S.open = false;
    $('#app').classList.remove('shown');
    $('#lightbox').classList.add('hidden');
    const m = $('#modal'); m.classList.add('hidden'); m.classList.remove('shown'); $('#modal-card').innerHTML = '';
    setTimeout(() => { if (!S.open) { $('#app').classList.add('hidden'); host().innerHTML = ''; } }, 170);
    if (tell) post('close');
  }
  let refreshT = null; const pending = new Set();
  function onRefresh(what) {
    if (!S.open) return;
    pending.add(String(what || ''));
    clearTimeout(refreshT);
    refreshT = setTimeout(() => {
      const list = Array.from(pending); pending.clear();
      counts();
      const v = S.view, a = S.arg;
      const hit = list.some((w) => {
        if (w.startsWith('case:')) return (v === 'case' || v === 'pcase') && +w.slice(5) === +a || v === 'cases' || v === 'dashboard' || v === 'mycases';
        const map = { calendar: ['calendar', 'dashboard', 'case'], warrants: ['warrants', 'dashboard'], petitions: ['clerk', 'dashboard'], fees: ['clerk', 'person'],
          cases: ['cases', 'case', 'dashboard'], records: ['person'], bar: ['bar'], businesses: ['clerk'], notices: ['home', 'notices', 'ptickets'], permits: ['permits'], contests: ['contests', 'ptickets'] };
        return (map[w] || []).includes(v);
      });
      if (hit) rerender();
    }, 400);
  }
  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') openUi(m);
    else if (m.action === 'close') closeUi(false);
    else if (m.action === 'refresh') onRefresh(m.what);
  });
  document.addEventListener('keydown', (e) => {
    if (!S.open) return;
    if (e.key === 'Escape') {
      if (!$('#lightbox').classList.contains('hidden')) { $('#lightbox').classList.add('hidden'); return; }
      if (modalOpen()) { closeModal(); return; }
      closeUi(true);
    }
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k' && S.mode === 'tablet') { e.preventDefault(); $('#gsearch').focus(); }
  });
  document.addEventListener('click', (e) => {
    const a = e.target.closest('[data-act="close"]'); if (a) closeUi(true);
    if (e.target.closest('#to-mdt')) { closeUi(false); post('toMdt'); return; }
    const lb = e.target.closest('#lightbox'); if (lb && (e.target.id === 'lightbox' || e.target.closest('.lb-x'))) lb.classList.add('hidden');
    const k = e.target.closest('[data-case]'); if (k && !e.target.closest('button:not([data-case])')) { e.preventDefault(); go(S.mode === 'portal' ? 'pcase' : 'case', +k.dataset.case, { parent: S.mode === 'portal' ? 'mycases' : 'cases' }); }
    const p = e.target.closest('[data-person]'); if (p && S.mode === 'tablet' && !e.target.closest('button:not([data-person])')) { e.preventDefault(); go('person', +p.dataset.person, { parent: 'people' }); }
  });
  $('#modal').addEventListener('mousedown', (e) => { if (e.target.id === 'modal') closeModal(); });
  wireSearch();

  window.DOJ = { S, $, $$, esc, money, post, call, toast, said, busy, ago, inTime, date, dateTime, timeOnly, pill, empty, loading, cap, labelOf, kindTag, stageLabel,
    R, RO, has, isoLocal, fromLocal, VERDICT, verdictPill, statusPill, caseNo, modal, modalOpen, closeModal, confirmBox, personPicker, form, answer,
    imageOf, lightbox, lazyThumbs, views, go, goBack, crumb, wireBack, rerender, counts, drawNav, openUi, closeUi };
})();
