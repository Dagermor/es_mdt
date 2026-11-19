// es_mdt 1.11.0: the optional whip_evidence locker (Config.WhipEvidence). whip_evidence keeps the things, the MDT
// keeps the case; the case number is the link. Shown only when the server says the integration is on.
// Case page: "Evidence locker (whip_evidence)" card (add evidence, open locker, entries with results + custody,
// lazy photos). Report page: the case's whip_evidence entries as chips. The server checks everything again.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, post, toast, said, busy, ago, dateTime, modal, can, HOOK } = M;

  const KIND = {
    casing: ['Casing', '⁍'], bullet: ['Bullet', '•'], blood: ['Blood', '🩸'], fingerprint: ['Fingerprint', '🖐'],
    vehicle_fragment: ['Vehicle fragment', '🚗'], gsr: ['Gunshot residue', '💨'], reference: ['Reference sample', '🧬'],
    photo: ['Photo', '📷'], gun: ['Weapon', '🔫'], weapon: ['Weapon', '🔫'], item: ['Item', '▣'],
    // 2.0.16: whip_evidence 4.2
    shoeprint: ['Shoe print', '👟'], tyre_track: ['Tyre track', '🛞'], fiber: ['Glove fibres', '🧤'],
    cleaned: ['Cleaned spot', '🧴'], serial: ['Serial report', '🔢'],
  };
  const RES = { ammo: 'Ammo', weapon_serial: 'Weapon serial', fingerprint: 'Print', blood_type: 'Blood type', paint: 'Paint', gsr: 'GSR', ballistics: 'Ballistics', age: 'Age',
    // 2.0.16: whip_evidence 4.2 lab results
    shoe_profile: 'Sole pattern', shoe_size: 'Shoe size', tyre_profile: 'Tread pattern', tyre_width: 'Tyre', fiber: 'Glove fibres', cleaner: 'Cleaner', surface: 'Ground' };
  // any other field whip_evidence adds later: "some_field" -> "Some field"
  const niceKey = (k) => { const s = String(k).replace(/_/g, ' ').trim(); return s.charAt(0).toUpperCase() + s.slice(1); };
  const kindOf = (e) => KIND[e.kind] || (String(e.ref || '').startsWith('photo:') ? KIND.photo : String(e.ref || '').startsWith('gun:') ? KIND.gun : KIND.item);
  const ico = (e) => `<span class="wev-ico wev-k-${esc(e.kind || 'item')}">${kindOf(e)[1]}</span>`;
  const val = (v) => {
    if (v === true) return 'Positive'; if (v === false) return 'Negative';
    if (v === null || v === undefined || v === '' || v === '???') return null;   // '???' = whip_evidence: lab not run yet
    if (typeof v === 'object') { try { return Object.entries(v).map(([a, b]) => `${a}: ${b}`).join(', ').slice(0, 80); } catch (e) { return null; } }
    return String(v).slice(0, 80);
  };
  function resultChips(e) {
    const out = [];
    const r = e.results || {};
    // 2.0.16: "quality" set = only partly readable ("?" stand for unreadable characters): a warning chip first
    const q = val(r.quality);
    if (q) out.push(`<span class="wev-r warn" title="Some characters could not be read (shown as ?)"><i>⚠ Quality</i>${esc(q)}</span>`);
    Object.keys(RES).forEach((k) => { const t = val(r[k]); if (t) out.push(`<span class="wev-r"><i>${esc(RES[k])}</i>${esc(t)}</span>`); });
    Object.keys(r).filter((k) => !RES[k] && k !== 'quality').forEach((k) => { const t = val(r[k]); if (t) out.push(`<span class="wev-r"><i>${esc(niceKey(k))}</i>${esc(t)}</span>`); });
    if (e.serial) out.push(`<span class="wev-r"><i>Serial</i>${esc(e.serial)}</span>`);
    if (e.caliber) out.push(`<span class="wev-r"><i>Caliber</i>${esc(e.caliber)}</span>`);
    if (e.ballistics && !r.ballistics) out.push(`<span class="wev-r"><i>Ballistics</i>${esc(val(e.ballistics) || '')}</span>`);
    if (e.entries && e.entries.length) out.push(`<span class="wev-r"><i>In frame</i>${e.entries.length} marker${e.entries.length === 1 ? '' : 's'}</span>`);
    if (e.cars && e.cars.length) out.push(`<span class="wev-r"><i>Vehicles</i>${e.cars.length}</span>`);
    return out.join('');
  }
  function meta(e) {
    const bits = [];
    if (e.street) bits.push(esc(e.street));
    if (e.time) bits.push(esc(typeof e.time === 'number' ? dateTime(e.time > 1e11 ? Math.floor(e.time / 1000) : e.time) : e.time));
    if (e.collectedBy) bits.push('collected by ' + esc(e.collectedBy));
    if (e.takenBy) bits.push('taken by ' + esc(e.takenBy));
    if (e.marker) bits.push('marker ' + esc(e.marker));
    if (e.testedOn) bits.push('tested ' + esc(e.testedOn));
    return bits.join(' · ');
  }
  const title = (e) => esc(e.label || e.type || e.item || e.ref);
  // 1.11.3: custody steps come as { at, what, who } (at = epoch, read from whip_evidence's server-clock text), shown in
  // the officer's own time like every other MDT time; plain strings (older servers) are shown as they are.
  const step = (c) => typeof c === 'string'
    ? `<div class="ev-step"><span class="ev-dot"></span><div>${esc(c)}</div></div>`
    : `<div class="ev-step"><span class="ev-dot"></span><div>${c.at ? `<b class="wev-when">${esc(dateTime(c.at))}</b> ` : ''}${esc(c.what || '')}${c.who ? ` <span class="hint">· ${esc(c.who)}</span>` : ''}</div></div>`;

  // ---------------------------------------------------------------- photos: our copy first, theirs on demand
  const pics = {};
  async function photoOf(caseId, ref) {
    const key = caseId + '|' + ref;
    if (pics[key]) return pics[key];
    const r = await call('wevPhoto', { caseId, ref });
    if (r.ok && r.data && r.data.image) { pics[key] = r.data.image; return r.data.image; }
    return null;
  }
  function lazyPhotos(root, caseId) {
    const els = $$('[data-wevimg]', root);
    if (!els.length) return;
    const load = async (el) => {
      if (el.dataset.loaded) return; el.dataset.loaded = '1';
      const src = await photoOf(caseId, el.dataset.wevimg);
      if (!el.isConnected) return;
      if (src) { el.style.backgroundImage = `url("${src}")`; el.classList.add('has'); }
      else { el.classList.add('none'); el.textContent = 'Picture expired'; }
    };
    if ('IntersectionObserver' in window) {
      const io = new IntersectionObserver((list) => list.forEach((x) => { if (x.isIntersecting) { io.unobserve(x.target); load(x.target); } }), { rootMargin: '200px' });
      els.forEach((el) => io.observe(el));
    } else els.forEach(load);
  }
  function openPhotos(list, i, caseId) {
    if (!window.Lightbox) return;
    window.Lightbox.open(list.map((e) => ({
      title: e.label || 'Photo', sub: e.scene || e.street || '',
      meta: [['Ref', e.ref], ['Street', e.street], ['Taken by', e.takenBy], ['Time', e.time && (typeof e.time === 'number' ? dateTime(e.time) : e.time)]].filter((m) => m[1]),
      load: () => photoOf(caseId, e.ref),
    })), i);
  }

  // ---------------------------------------------------------------- one saved entry
  function tile(e, w) {
    const t = w.taken && w.taken[e.ref];
    const custody = (e.custody || []).length ? `<details class="wev-cust"><summary>Chain of custody · ${e.custody.length} step${e.custody.length === 1 ? '' : 's'}</summary>
      <div class="ev-chain">${e.custody.map(step).join('')}</div></details>` : '';
    const photo = (e.kind === 'photo' || String(e.ref).startsWith('photo:')) ? `<div class="wev-thumb" data-wevimg="${esc(e.ref)}" data-wevph="${esc(e.ref)}" title="Open the photo"></div>` : '';
    return `<div class="wev-tile${e.gone ? ' gone' : ''}" data-wevref="${esc(e.ref)}">
      ${photo}
      <div class="wev-head">${ico(e)}<div class="wev-t"><b>${title(e)}</b><span class="hint">${esc(kindOf(e)[0])} · <span class="mono">${esc(e.ref)}</span></span></div></div>
      ${t ? `<div class="wev-out">Out of locker: taken by <b>${esc(t.by || 'someone')}</b>${t.at ? ' · ' + esc(ago(t.at > 1e11 ? t.at / 1000 : t.at)) : ''}${t.what ? ' · ' + esc(t.what) : ''}</div>` : ''}
      ${e.gone ? '<div class="wev-gone">No longer in the locker (deleted in whip_evidence) · saved copy</div>' : ''}
      ${meta(e) ? `<div class="hint wev-meta">${meta(e)}</div>` : ''}
      ${resultChips(e) ? `<div class="wev-rs">${resultChips(e)}</div>` : ''}
      ${custody}
      ${e.uploadedBy ? `<div class="hint wev-up">Uploaded by ${esc(e.uploadedBy)}${e.uploadedAt ? ' · ' + esc(dateTime(e.uploadedAt)) : ''}</div>` : ''}
    </div>`;
  }

  // ---------------------------------------------------------------- the case card
  function caseCard(v, x, reload) {
    const slot = $('#cv-wev', v); const w = x.wev;
    if (!slot || !w || !w.enabled) return;
    const k = x.case, cn = x.can || {};
    const items = w.items || [];
    const out = items.filter((e) => w.taken && w.taken[e.ref]).length;
    const canAdd = w.running && cn.file && k.status === 'open';
    slot.outerHTML = `<div class="card wev-card" id="cv-wev"><div class="card-head">
        <div class="card-title">Evidence locker <span class="wev-tag">whip_evidence</span> <span class="hint">· ${items.length} item${items.length === 1 ? '' : 's'}${out ? ` · ${out} out of the locker` : ''}</span></div>
        <div class="row">${w.closed ? '<span class="pill accent">Locker closed</span>' : ''}
          ${w.running ? '<button class="btn small ghost" id="wev-locker" title="Works when you stand at an evidence locker">Open locker</button>' : ''}
          ${canAdd ? '<button class="btn small" id="wev-add">+ Add evidence</button>' : ''}</div></div>
      ${!w.running ? '<div class="hint">whip_evidence is not running right now: showing the copies saved in the MDT.</div>' : ''}
      ${items.length ? `<div class="wev-grid">${items.map((e) => tile(e, w)).join('')}</div>`
        : `<div class="empty-state wev-empty"><div class="es-ico">🗄️</div>Nothing uploaded yet.${canAdd ? ' Analysed items you carry can be added with “+ Add evidence”, or at the lab device with case number <b>' + esc(k.number) + '</b>.' : ''}</div>`}
    </div>`;
    const box = $('#cv-wev', v);
    lazyPhotos(box, k.id);
    const photos = items.filter((e) => e.kind === 'photo' || String(e.ref).startsWith('photo:'));
    $$('[data-wevph]', box).forEach((el) => el.onclick = () => openPhotos(photos, photos.findIndex((p) => p.ref === el.dataset.wevph), k.id));
    if ($('#wev-add', box)) $('#wev-add', box).onclick = () => addModal(k, reload);
    // 2.0.7: the stash cannot open over the MDT (whip_core refuses an inventory while another screen is up), so the
    // game closes the MDT first and then asks for the locker (mdt/client/main.lua wevLockerOpen). One press, one request.
    if ($('#wev-locker', box)) $('#wev-locker', box).onclick = (ev) => {
      const b = ev.currentTarget; if (b.disabled) return;
      b.disabled = true;
      post('wevLockerOpen', { caseId: k.id, number: k.number }).then((r) => {
        if (!r || r.ok === false) { b.disabled = false; toast((r && r.why) || 'The locker could not be opened', 'err'); }
      });
    };
  }

  // ---------------------------------------------------------------- "Add evidence": pick what you carry
  function addModal(k, reload) {
    let list = [], tab = 'ready', picked = new Set(), done = {}, changed = false;
    const close = modal(`<div class="m-title">Add evidence to ${esc(k.number)}</div>
      <p class="m-text hint">From your pockets and evidence case. Only analysed items can go in; an item belongs to one case for good.</p>
      <div class="wev-bar"><input type="text" id="wev-q" placeholder="Search a type, street, serial, ref…" autocomplete="off">
        <div class="seg" id="wev-tabs"></div></div>
      <div id="wev-list" class="wev-list"><div class="loading-row"><div class="spin"></div></div></div>
      <div class="row between wev-foot"><label class="wev-all"><input type="checkbox" id="wev-all"> Select all ready</label>
        <div class="row"><button class="btn ghost" data-x>Close</button><button class="btn accent" id="wev-go" disabled>Upload</button></div></div>`, (card, closeIt) => {
      card.classList.add('wide');
      $$('[data-x]', card).forEach((b) => b.addEventListener('click', () => { if (changed) setTimeout(reload, 200); }));
    });
    const card = $('#modal-card');
    const state = (e) => done[e.ref] ? (done[e.ref].ok ? 'done' : 'fail') : e.onCase ? 'on' : e.canAdd ? 'ready' : e.otherCase ? 'other' : 'lab';
    const counts = () => { const c = { all: list.length, ready: 0, lab: 0, other: 0 }; list.forEach((e) => { const s = state(e); if (s === 'ready' || s === 'on' || s === 'fail') c.ready++; else if (s === 'lab') c.lab++; else if (s === 'other') c.other++; }); return c; };
    const render = () => {
      if (!card.isConnected) return;
      const c = counts();
      $('#wev-tabs', card).innerHTML = [['ready', 'Ready', c.ready], ['lab', 'Lab first', c.lab], ['other', 'Other case', c.other], ['all', 'All', c.all]]
        .map(([key, lbl, n]) => `<button class="seg-b${tab === key ? ' on' : ''}" data-tab="${key}">${lbl} <span class="hint">${n}</span></button>`).join('');
      $$('[data-tab]', card).forEach((b) => b.onclick = () => { tab = b.dataset.tab; render(); });
      const q = ($('#wev-q', card).value || '').trim().toLowerCase();
      const rows = list.filter((e) => {
        const s = state(e);
        if (tab === 'ready' && !(s === 'ready' || s === 'on' || s === 'fail' || s === 'done')) return false;
        if (tab === 'lab' && s !== 'lab') return false;
        if (tab === 'other' && s !== 'other') return false;
        return !q || [e.label, e.item, e.type, e.street, e.ref, e.serial, e.kind].some((t) => t && String(t).toLowerCase().includes(q));
      });
      $('#wev-list', card).innerHTML = rows.length ? rows.map((e) => {
        const s = state(e), sel = picked.has(e.ref), off = !(s === 'ready' || s === 'on' || s === 'fail');
        const badge = s === 'lab' ? '<span class="wev-b lab">Lab first</span>' : s === 'other' ? `<span class="wev-b other">Belongs to case ${esc(e.otherCase)}</span>`
          : s === 'on' ? '<span class="wev-b on">Already in this case · re-upload updates it</span>' : s === 'done' ? '<span class="wev-b ok">✓ Uploaded</span>'
          : s === 'fail' ? `<span class="wev-b fail">✕ ${esc(done[e.ref].why || 'Not uploaded')}</span>` : '<span class="wev-b ready">Analysed</span>';
        return `<label class="wev-row ${s}${sel ? ' sel' : ''}${off ? ' off' : ''}">
          <input type="checkbox" data-pick="${esc(e.ref)}"${sel ? ' checked' : ''}${off ? ' disabled' : ''}>
          ${ico(e)}<div class="wev-t"><b>${title(e)}</b><span class="hint">${esc(kindOf(e)[0])} · <span class="mono">${esc(e.ref)}</span>${meta(e) ? ' · ' + meta(e) : ''}</span>
          ${resultChips(e) ? `<div class="wev-rs">${resultChips(e)}</div>` : ''}</div>${badge}</label>`;
      }).join('') : `<div class="empty-state"><div class="es-ico">🧳</div>${list.length ? 'Nothing here.' : 'You are not carrying any evidence. Bags, photos and weapons you carry show up here.'}</div>`;
      $$('[data-pick]', card).forEach((b) => b.onchange = () => { if (b.checked) picked.add(b.dataset.pick); else picked.delete(b.dataset.pick); render(); });
      const ready = list.filter((e) => ['ready', 'on', 'fail'].includes(state(e)));
      $('#wev-all', card).checked = ready.length > 0 && ready.every((e) => picked.has(e.ref));
      $('#wev-all', card).disabled = !ready.length;
      const go = $('#wev-go', card);
      go.disabled = !picked.size; go.textContent = picked.size ? `Upload ${picked.size} item${picked.size === 1 ? '' : 's'}` : 'Upload';
    };
    const load = async () => {
      const r = await call('wevList', { caseId: k.id });
      if (!card.isConnected) return;
      if (!r.ok) { $('#wev-list', card).innerHTML = `<div class="empty-state"><div class="es-ico">⚠️</div>${esc(r.why || 'whip_evidence did not answer')}</div>`; return; }
      list = r.data.items || [];
      if (!list.some((e) => e.canAdd) && list.length) tab = 'all';
      render();
    };
    $('#wev-q', card).oninput = render;
    $('#wev-all', card).onchange = (ev) => {
      list.filter((e) => ['ready', 'on', 'fail'].includes(state(e))).forEach((e) => { if (ev.target.checked) picked.add(e.ref); else picked.delete(e.ref); });
      render();
    };
    $('#wev-go', card).onclick = (ev) => busy(ev.currentTarget, async () => {
      const refs = Array.from(picked);
      const r = await call('wevUpload', { caseId: k.id, refs });
      if (!r.ok) { toast(r.why || 'Upload failed', 'err'); return; }
      let ok = 0, bad = 0;
      (r.data.results || []).forEach((x) => { done[x.ref] = x; if (x.ok) ok++; else bad++; });
      picked = new Set(); changed = changed || ok > 0;
      if (!bad) { toast(`${ok} item${ok === 1 ? '' : 's'} added to ${k.number}`, 'ok'); close(); reload(); return; }
      toast(ok ? `${ok} added, ${bad} not: see why on each item` : `Nothing added: see why on each item`, 'err');
      tab = 'ready'; render();
    });
    load();
  }

  // ---------------------------------------------------------------- reports: chips of the case's entries
  async function reportCard(v, x) {
    const r = await call('wevReport', { reportId: x.id });
    if (!v.isConnected || S.view !== 'reports' || !r.ok || !r.data || !r.data.enabled) return;
    const d = r.data, w = can('mdt_reports_write');
    const items = d.items || [], avail = d.available || [];
    if (!items.length && !avail.length && !d.caseId) return;   // nothing to show and no case: stay out of the way
    const chip = (e, on) => `<span class="wev-chip${e.gone ? ' gone' : ''}" title="${esc(e.ref)}">${kindOf(e)[1]} ${title(e)}${resultChips(e) ? ` <span class="hint">· ${esc(Object.keys(e.results || {}).length ? val(Object.values(e.results).find((t) => val(t))) || '' : e.serial || '')}</span>` : ''}
      ${w ? (on ? `<button class="wev-x" data-wevun="${esc(e.ref)}" title="Take off the report">✕</button>` : `<button class="wev-plus" data-wevadd="${esc(e.ref)}" title="Attach to the report">+</button>`) : ''}</span>`;
    const html = `<div class="card wev-card" id="rv-wev"><div class="card-head"><div class="card-title">Evidence locker <span class="wev-tag">whip_evidence</span> <span class="hint">· ${items.length} on this report</span></div></div>
      ${items.length ? `<div class="wev-chips">${items.map((e) => chip(e, true)).join('')}</div>` : '<div class="hint">None attached.</div>'}
      ${w && avail.length ? `<div class="lbl mt">In the case’s locker</div><div class="wev-chips">${avail.map((e) => chip(e, false)).join('')}</div>` : ''}
      ${!d.caseId ? '<div class="hint mt">File this report to a case to attach whip_evidence items.</div>' : ''}</div>`;
    const old = $('#rv-wev', v);
    if (old) old.outerHTML = html;
    else { const anchor = $('#rv-ev', v) || $('#rv-case', v); if (anchor) anchor.insertAdjacentHTML('afterend', html); else v.insertAdjacentHTML('beforeend', html); }
    const box = $('#rv-wev', v);
    $$('[data-wevadd]', box).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('wevReportLink', { reportId: x.id, ref: b.dataset.wevadd }), 'Attached')) reportCard(v, x); }));
    $$('[data-wevun]', box).forEach((b) => b.onclick = () => busy(b, async () => { if (said(await call('wevReportLink', { reportId: x.id, ref: b.dataset.wevun, remove: true }), 'Taken off')) reportCard(v, x); }));
  }

  const prevCase = HOOK.caseView;
  HOOK.caseView = (v, x, reload) => { if (prevCase) prevCase(v, x, reload); caseCard(v, x, reload); };
  const prevRep = HOOK.reportView;
  HOOK.reportView = (v, x, reload) => { if (prevRep) prevRep(v, x, reload); reportCard(v, x); };
})();
