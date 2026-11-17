// es_mdt 1.5.1: evidence in the report itself.
//  * Report editor: an Evidence section at the top. Pick from the bags you carry, what you collected in the last 24 h,
//    the report's case, a search by EV number, or your camera roll. Saved with the report (new or edited).
//  * One picker (M.evPicker) also used by "+ Add evidence" on a filed report.
//  * Process arrest: the evidence bags the officer carries are offered on the Review step.
(() => {
  const M = window.MDT;
  if (!M) return;
  const { S, $, $$, esc, call, toast, said, busy, ago, modal, empty, can, HOOK } = M;
  const KIND = { casing: ['Casing', '⁍'], fragment: ['Fragment', '◆'], blood: ['Blood', '🩸'], photo: ['Photo', '📷'], print: ['Fingerprint', '🖐'], weapon: ['Weapon', '🔫'] };
  const kindPill = (k) => `<span class="ev-k ev-${esc(k)}">${(KIND[k] || [k, '·'])[1]} ${esc((KIND[k] || [k])[0])}</span>`;
  const rollImg = {};
  async function rollImage(id) {
    if (rollImg[id]) return rollImg[id];
    const r = await call('evRollPhoto', { id });
    if (r.ok && r.data) { rollImg[id] = r.data.image; return r.data.image; }
    return null;
  }
  let evOn = null;
  async function installed() { if (evOn === null) { const r = await call('evStatus'); evOn = !!(r.ok && r.data && r.data.installed); } return evOn; }

  // ---------------------------------------------------------------- the picker
  // opts: { title, reportId, caseId, have: [evidenceIds already on], haveRoll: [photoIds], now: attach at once (filed report),
  //         onPick(kind 'ev'|'roll', item, on) for the editor, after() }
  function evPicker(opts) {
    const have = new Set(opts.have || []), haveRoll = new Set(opts.haveRoll || []);
    let tab = 'carrying', src = null, changed = false;
    modal(`<div class="m-title">${esc(opts.title || 'Add evidence')}</div>
      <div class="seg mb" id="ek-tabs">${[['carrying', '🎒 Bags I carry'], ['recent', '🕑 Collected today'], ['case', '▣ Case'], ['search', '🔎 Search'], ['roll', '📷 Camera roll']]
        .map(([k, l]) => `<button data-ek="${k}">${l} <span class="seg-n" data-ekn="${k}"></span></button>`).join('')}</div>
      <div id="ek-q-w" class="hidden"><input type="text" id="ek-q" placeholder="EV-number (EV-00012), street, serial…" autocomplete="off"></div>
      <div id="ek-list" class="ek-list"><div class="loading-row"><div class="spin"></div></div></div>
      <div class="row end"><span class="hint" id="ek-sum"></span><span class="spacer"></span><button class="btn accent" data-x>Done</button></div>`, (card, closeIt) => {
      card.classList.add('wide');
      const sum = () => { const n = have.size + haveRoll.size; $('#ek-sum', card).textContent = n ? `${n} on the report` : ''; };
      const rowHtml = (e) => {
        const on = have.has(e.id);
        const res = e.result ? `<div class="cs-res">🧪 ${esc(e.result)}</div>` : e.status === 'lab' ? '<div class="cs-res wait">🧪 In the lab…</div>' : '';
        return `<div class="ek-row${on ? ' on' : ''}">
          ${e.kind === 'photo' ? `<div class="ek-th" data-ekimg="${e.id}"><div class="spin"></div></div>` : `<div class="ek-th ico">${(KIND[e.kind] || ['', '·'])[1]}</div>`}
          <div class="ek-main"><div class="row"><span class="ev-code">${esc(e.code)}</span>${kindPill(e.kind)}${e.caseNo ? `<span class="cs-no sm">${esc(e.caseNo)}</span>` : ''}</div>
            <b>${esc(e.label)}${e.shots > 1 ? ` ×${e.shots}` : ''}</b>
            <span class="hint">${esc(e.street || '—')} · ${e.kind === 'photo' ? 'taken' : 'collected'} ${ago(e.collectedAt || e.createdAt)}${e.collector ? ' · ' + esc(e.collector) : ''}</span>${res}</div>
          <button class="btn small${on ? ' ghost' : ' accent'}" data-ekadd="${e.id}">${on ? '✓ Added' : '+ Add'}</button></div>`;
      };
      const rollHtml = (p) => {
        const on = p.evidenceId ? have.has(p.evidenceId) : haveRoll.has(p.id);
        return `<div class="ek-row${on ? ' on' : ''}"><div class="ek-th" data-ekroll="${p.id}"><div class="spin"></div></div>
          <div class="ek-main"><div class="row">${p.evidenceId ? `<span class="ev-code">EV-${String(p.evidenceId).padStart(5, '0')}</span>` : '<span class="pill">Not logged yet</span>'}</div>
            <b>Photo · ${esc(p.street || 'unknown street')}</b><span class="hint">taken ${ago(p.createdAt)}${p.evidenceId ? '' : ' · logged as evidence when you add it'}</span></div>
          <button class="btn small${on ? ' ghost' : ' accent'}" data-ekroll-add="${p.id}">${on ? '✓ Added' : '+ Add'}</button></div>`;
      };
      const all = () => [].concat((src && src.carrying) || [], (src && src.recent) || [], (src && src.case) || [], lastSearch);
      let lastSearch = [];
      const find = (id) => all().find((e) => e.id === id);
      const thumbs = async (box) => {
        for (const el of $$('[data-ekimg],[data-ekroll]', box)) {
          if (!el.isConnected) return;
          const src2 = el.dataset.ekimg ? await (M.evImageOf(+el.dataset.ekimg)) : await rollImage(+el.dataset.ekroll);
          if (!el.isConnected) return;
          el.innerHTML = src2 ? `<img src="${src2}" alt="">` : '<span class="hint">—</span>';
        }
      };
      const toggleEv = (e, b) => busy(b, async () => {
        const on = !have.has(e.id);
        if (opts.now) {
          if (!on) return;
          const r = await call('evAttachMany', { reportId: opts.reportId, ids: [e.id] });
          if (!said(r, `${e.code} added to the report`)) return;
          if (opts.after) opts.after();
        } else if (opts.onPick) opts.onPick('ev', e, on);
        on ? have.add(e.id) : have.delete(e.id); changed = true; draw();
      });
      const toggleRoll = (p, b) => busy(b, async () => {
        if (p.evidenceId) { const e = find(p.evidenceId) || { id: p.evidenceId, code: 'EV-' + String(p.evidenceId).padStart(5, '0'), kind: 'photo', label: 'Photo · ' + (p.street || ''), street: p.street, createdAt: p.createdAt, status: 'digital' }; return toggleEv(e, b); }
        const on = !haveRoll.has(p.id);
        if (opts.now) {
          if (!on) return;
          const r = await call('evAttachMany', { reportId: opts.reportId, photos: [p.id] });
          if (!said(r)) return;
          const made = (r.data.made || [])[0];
          if (!made) { toast((r.data.fails || [])[0] || 'Could not log that photo', 'err'); return; }
          toast(`Logged as ${made} and added`, 'ok');
          p.evidenceId = +made.replace(/\D/g, ''); have.add(p.evidenceId);
          if (opts.after) opts.after();
        } else { if (opts.onPick) opts.onPick('roll', p, on); on ? haveRoll.add(p.id) : haveRoll.delete(p.id); }
        changed = true; draw();
      });
      const draw = () => {
        const box = $('#ek-list', card); if (!box || !src) return;
        $$('[data-ek]', card).forEach((b) => b.classList.toggle('on', b.dataset.ek === tab));
        $('#ek-q-w', card).classList.toggle('hidden', tab !== 'search');
        const n = { carrying: src.carrying.length, recent: src.recent.length, case: src.case.length, roll: src.roll.length };
        $$('[data-ekn]', card).forEach((el) => { el.textContent = n[el.dataset.ekn] || ''; });
        let html;
        if (tab === 'roll') {
          html = !src.collect ? empty('Your rank cannot log camera photos as evidence.', '📷')
            : src.roll.length ? src.roll.map(rollHtml).join('') : empty('Your camera roll is empty. Raise the camera and left-click to take a photo.', '📷');
        } else {
          const list = tab === 'search' ? lastSearch : src[tab];
          const msg = { carrying: ['You are not carrying any evidence bags. Bag evidence at the scene (E) and it shows here.', '🎒'],
            recent: ['Nothing collected in the last 24 hours.', '🕑'], case: [src.caseId ? 'No evidence filed to this case yet.' : 'Pick a case for the report first, or this report has no case.', '▣'],
            search: ['Type an EV number, a street or a serial.', '🔎'] }[tab];
          html = list.length ? list.map(rowHtml).join('') : empty(msg[0], msg[1]);
        }
        box.innerHTML = html;
        $$('[data-ekadd]', box).forEach((b) => b.onclick = () => { const e = find(+b.dataset.ekadd); if (e) toggleEv(e, b); });
        $$('[data-ekroll-add]', box).forEach((b) => b.onclick = () => { const p = src.roll.find((x) => x.id === +b.dataset.ekrollAdd); if (p) toggleRoll(p, b); });
        // big preview on a thumbnail click
        $$('[data-ekimg]', box).forEach((el) => el.onclick = () => { const e = find(+el.dataset.ekimg); if (e && M.openPhoto) M.openPhoto(e); });
        $$('[data-ekroll]', box).forEach((el) => el.onclick = () => { const p = src.roll.find((x) => x.id === +el.dataset.ekroll); if (p && window.Lightbox) window.Lightbox.open([{ load: () => rollImage(p.id), title: 'Camera roll photo', sub: p.street || '', meta: [['Taken', M.dateTime(p.createdAt)], ['Where', p.street || '—']] }], 0); });
        thumbs(box); sum();
      };
      $$('[data-ek]', card).forEach((b) => b.onclick = () => { tab = b.dataset.ek; draw(); if (tab === 'search') $('#ek-q', card).focus(); });
      let t = null, seq = 0;
      $('#ek-q', card).oninput = (ev) => {
        clearTimeout(t);
        const q = ev.target.value.trim();
        t = setTimeout(async () => {
          const my = ++seq;
          const r = q ? await call('evList', { q, status: 'open' }) : { ok: true, data: [] };
          if (my !== seq) return;
          lastSearch = (r.ok && r.data) || []; draw();
        }, 250);
      };
      (async () => {
        const r = await call('evSources', { reportId: opts.reportId || undefined, caseId: opts.caseId || undefined });
        if (!card.isConnected) return;
        if (!r.ok) { $('#ek-list', card).innerHTML = empty(r.why || 'Could not load the evidence', '⚠'); return; }
        src = r.data; ['carrying', 'recent', 'case', 'roll'].forEach((k) => { src[k] = src[k] || []; });
        tab = src.carrying.length ? 'carrying' : src.case.length ? 'case' : src.recent.length ? 'recent' : 'search';
        draw();
      })();
    });
  }
  M.evPicker = evPicker;

  // ---------------------------------------------------------------- the report editor
  const prevEditor = HOOK.reportEditor;
  HOOK.reportEditor = (v, R, setType) => {
    if (prevEditor) prevEditor(v, R, setType);
    const main = $('.cols-main', v);
    if (!main) return;
    R.ev = R.ev || new Map();         // evidenceId -> row
    R.evRoll = R.evRoll || new Map(); // camera-roll photo id -> photo (logged as evidence on save)
    R.evInit = R.evInit || new Set(); // already on the report (editing)
    main.insertAdjacentHTML('beforebegin', `<div class="card hidden" id="re-ev"><div class="card-head"><div class="card-title">Evidence <span class="hint" id="re-ev-n"></span></div>
      <div class="row"><button type="button" class="btn small accent" id="re-ev-add">+ Add evidence</button></div></div>
      <div id="re-ev-sug"></div><div id="re-ev-list"></div></div>`);
    const box = $('#re-ev', v);
    const caseId = () => (R.casePick && R.casePick.id) || (!R.casePick && R.caseNow && R.caseNow.id) || 0;
    const draw = () => {
      if (!box.isConnected) return;
      const items = [...R.ev.values()], photos = [...R.evRoll.values()];
      $('#re-ev-n', v).textContent = items.length + photos.length ? '· ' + (items.length + photos.length) : '';
      $('#re-ev-list', v).innerHTML = items.length + photos.length
        ? `<div class="cs-evs rep">${items.map((e) => M.evTile ? M.evTile(e, { remove: true, removeTitle: 'Remove from this report' }) : `<div class="li"><span class="ev-code">${esc(e.code)}</span>${esc(e.label)}<button class="btn small ghost" data-evoff="${e.id}">✕</button></div>`).join('')}
          ${photos.map((p) => `<div class="cs-ev photo"><div class="cs-ph" data-reroll="${p.id}" title="Open full screen"><div class="spin"></div></div>
            <div class="cs-ev-body"><div class="row"><span class="pill accent">New photo</span><span class="spacer"></span><button class="btn small ghost" data-rerolloff="${p.id}" title="Remove from this report">✕</button></div>
            <b class="cs-ev-label">Photo · ${esc(p.street || 'unknown street')}</b><div class="hint">taken ${ago(p.createdAt)} · logged as evidence when you save</div></div></div>`).join('')}</div>`
        : '<div class="hint">Casings, blood, fragments, print lifts and photos for this report. They are saved with it, and filed to the report\'s case.</div>';
      const list = $('#re-ev-list', v);
      if (M.wireTiles) M.wireTiles(list, items, null, (id) => { R.ev.delete(id); draw(); sug(); });
      else $$('[data-evoff]', list).forEach((b) => b.onclick = () => { R.ev.delete(+b.dataset.evoff); draw(); });
      $$('[data-rerolloff]', list).forEach((b) => b.onclick = () => { R.evRoll.delete(+b.dataset.rerolloff); draw(); });
      $$('[data-reroll]', list).forEach(async (el) => {
        const p = R.evRoll.get(+el.dataset.reroll);
        el.onclick = () => window.Lightbox && window.Lightbox.open([{ load: () => rollImage(p.id), title: 'Camera roll photo', sub: p.street || '', meta: [['Taken', M.dateTime(p.createdAt)]] }], 0);
        const src = await rollImage(p.id); if (el.isConnected) el.innerHTML = src ? `<img src="${src}" alt="">` : '—';
      });
    };
    // bags in my pockets that are not on the report yet: offer them in one click
    let carrying = [];
    const sug = () => {
      const el = $('#re-ev-sug', v); if (!el) return;
      const left = carrying.filter((e) => !R.ev.has(e.id));
      el.innerHTML = left.length ? `<div class="banner ek-sug"><span>🎒 You are carrying <b>${left.length}</b> evidence bag${left.length > 1 ? 's' : ''}: ${left.slice(0, 4).map((e) => esc(e.code)).join(', ')}${left.length > 4 ? '…' : ''}</span>
        <button type="button" class="btn small accent" id="re-ev-all">Add ${left.length > 1 ? 'all ' + left.length : 'it'}</button></div>` : '';
      if ($('#re-ev-all', v)) $('#re-ev-all', v).onclick = () => { left.forEach((e) => R.ev.set(e.id, e)); R.evTouched = true; draw(); sug(); };
    };
    $('#re-ev-add', v).onclick = () => evPicker({
      title: R.id ? `Evidence for report #${R.id}` : 'Evidence for this report', reportId: R.id || 0, caseId: caseId(),
      have: [...R.ev.keys()], haveRoll: [...R.evRoll.keys()],
      onPick: (kind, item, on) => {
        R.evTouched = true;
        if (kind === 'ev') on ? R.ev.set(item.id, item) : R.ev.delete(item.id);
        else on ? R.evRoll.set(item.id, item) : R.evRoll.delete(item.id);
        draw(); sug();
      },
    });
    (async () => {
      if (!(await installed()) || !box.isConnected) return;
      box.classList.remove('hidden');
      if (R.id && !R.evLoaded) {
        const r = await call('evForReport', { reportId: R.id });
        ((r.ok && r.data) || []).forEach((e) => { R.ev.set(e.id, e); R.evInit.add(e.id); });
        R.evLoaded = true;
      }
      draw();
      const s = await call('evSources', { only: 'carrying' });
      if (s.ok && s.data) { carrying = s.data.carrying || []; sug(); }
    })();
  };

  // after the report (and its case, in cases.js) is saved: write the evidence links
  const prevAfter = HOOK.afterReportSave;
  HOOK.afterReportSave = async (rid, R) => {
    if (prevAfter) await prevAfter(rid, R);
    if (!rid || !R.ev || !(await installed())) return;
    const add = [...R.ev.keys()].filter((id) => !R.evInit.has(id));
    const gone = [...R.evInit].filter((id) => !R.ev.has(id));
    const photos = [...R.evRoll.keys()];
    for (const id of gone) await call('evUnlink', { reportId: rid, evidenceId: id });
    // always called: it also files the report's evidence to the report's case
    const r = await call('evAttachMany', { reportId: rid, ids: add, photos });
    if (!r.ok) { toast('Evidence not saved: ' + (r.why || 'error'), 'err'); return; }
    const d = r.data || {};
    if (d.linked || gone.length) toast(`${d.linked || 0} piece${d.linked === 1 ? '' : 's'} of evidence added${gone.length ? `, ${gone.length} removed` : ''}${d.filed ? ` · ${d.filed} filed to ${d.caseNo || 'the case'}` : ''}`, 'ok');
    (d.fails || []).slice(0, 2).forEach((f) => toast(f, 'err'));
    R.evInit = new Set(R.ev.keys()); R.evRoll = new Map();
  };

  // ---------------------------------------------------------------- Process arrest: the bags you carry
  M.arrestEvidence = async (box, A) => {
    if (!box || !(await installed())) return;
    const s = await call('evSources', { only: 'carrying' });
    if (!box.isConnected) return;
    const list = (s.ok && s.data && s.data.carrying) || [];
    if (!A.ev) A.ev = new Set(list.map((e) => e.id));
    box.innerHTML = list.length ? `<div class="lbl mt">Evidence you are carrying <span class="hint">· ticked bags go on the report</span></div>
      ${list.map((e) => `<label class="chip-t ek-arr"><input type="checkbox" data-arev="${e.id}"${A.ev.has(e.id) ? ' checked' : ''}><span><span class="ev-code">${esc(e.code)}</span> ${esc(e.label)}${e.shots > 1 ? ' ×' + e.shots : ''}${e.result ? ' · 🧪 result' : ''}</span></label>`).join('')}` : '';
    $$('[data-arev]', box).forEach((c) => c.onchange = () => { c.checked ? A.ev.add(+c.dataset.arev) : A.ev.delete(+c.dataset.arev); });
  };
  M.arrestEvidenceSave = async (rid, A) => {
    if (!rid || !A.ev || !A.ev.size) return;
    const r = await call('evAttachMany', { reportId: rid, ids: [...A.ev] });
    if (r.ok && r.data && r.data.linked) toast(`${r.data.linked} evidence bag${r.data.linked > 1 ? 's' : ''} added to the report`, 'ok');
  };
})();
