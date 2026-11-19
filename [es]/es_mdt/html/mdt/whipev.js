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
    autopsy: ['Post-mortem report', '🩻'],   // 2.0.17: whip_evidence 4.2.3
  };
  const RES = { ammo: 'Ammo', weapon_serial: 'Weapon serial', fingerprint: 'Print', blood_type: 'Blood type', paint: 'Paint', gsr: 'GSR', ballistics: 'Ballistics', age: 'Age',
    // 2.0.16: whip_evidence 4.2 lab results
    shoe_profile: 'Sole pattern', shoe_size: 'Shoe size', tyre_profile: 'Tread pattern', tyre_width: 'Tyre', fiber: 'Glove fibres', cleaner: 'Cleaner', surface: 'Ground',
    cause: 'Cause of death', findings: 'Findings' };
  // 2.0.17: codes an officer may want to paste somewhere else (a person's file, a BOLO, a report): one tap copies them
  const COPY = { weapon_serial: 'serial number', fingerprint: 'fingerprint', blood_type: 'blood type', shoe_profile: 'sole pattern', tyre_profile: 'tread pattern', fiber: 'fibre code', ballistics: 'ballistics' };
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
  // ---------------------------------------------------------------- 2.0.17: copy to the clipboard
  // FiveM's browser has no async clipboard permission: a hidden textarea + execCommand('copy') works there; the
  // Clipboard API is only the fallback (a normal browser). The focus goes back where it was (keyboard / pad users).
  function copyText(t) {
    t = String(t == null ? '' : t);
    if (!t) return false;
    const prev = document.activeElement;
    let ok = false;
    try {
      const ta = document.createElement('textarea');
      ta.value = t; ta.setAttribute('readonly', ''); ta.setAttribute('data-pad-skip', '');
      ta.style.cssText = 'position:fixed;left:-9999px;top:0;width:1px;height:1px;opacity:0';
      document.body.appendChild(ta); ta.select(); ta.setSelectionRange(0, t.length);
      ok = document.execCommand('copy') === true;
      ta.remove();
    } catch (e) { ok = false; }
    if (!ok && navigator.clipboard && navigator.clipboard.writeText) { try { navigator.clipboard.writeText(t).catch(() => {}); ok = true; } catch (e) { ok = false; } }
    try { if (prev && prev.focus && prev !== document.body) prev.focus({ preventScroll: true }); } catch (e) { /* gone */ }
    return ok;
  }
  M.copyText = copyText;
  // drawn, not a font character: the game's browser may not have a font with ⧉ / 📋 in it
  const CP_ICO = '<svg class="cp-i" viewBox="0 0 16 16" aria-hidden="true"><rect x="5.5" y="5.5" width="8" height="8" rx="1.8" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M10.5 3.6V3.3A1.8 1.8 0 0 0 8.7 1.5H3.3A1.8 1.8 0 0 0 1.5 3.3v5.4a1.8 1.8 0 0 0 1.8 1.8h.3" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>';
  const cpBtn = (value, what, inner, cls) => `<button type="button" class="${cls || 'wev-r cp'}" data-copy="${esc(value)}" data-copy-what="${esc(what)}" title="Copy ${esc(what)}">${inner}${CP_ICO}</button>`;
  /** one delegated handler per box: [data-copy] copies, says so, and never toggles a label's checkbox */
  function wireCopy(box) {
    if (!box || box.dataset.cpWired) return;
    box.dataset.cpWired = '1';
    box.addEventListener('click', (ev) => {
      const b = ev.target.closest && ev.target.closest('[data-copy]');
      if (!b || !box.contains(b)) return;
      ev.preventDefault(); ev.stopPropagation();
      const v = b.dataset.copy || '', what = b.dataset.copyWhat || 'text';
      if (copyText(v)) {
        toast(`Copied ${what}${v.length <= 40 && !v.includes('\n') ? ': ' + v : ''}`, 'ok');
        b.classList.add('copied'); setTimeout(() => b.classList.remove('copied'), 1200);
      } else toast('Could not copy here: select the text and press Ctrl+C', 'err');
    }, true);
  }
  function resultChips(e, cp) {
    const out = [];
    const r = Object.assign({}, e.results || {});
    if (e.report) delete r.findings;   // the post-mortem card shows it in full (the cause stays as the tile's one-line summary)
    // 2.0.16: "quality" set = only partly readable ("?" stand for unreadable characters): a warning chip first
    const q = val(r.quality);
    if (q) out.push(`<span class="wev-r warn" title="Some characters could not be read (shown as ?)"><i>⚠ Quality</i>${esc(q)}</span>`);
    Object.keys(RES).forEach((k) => {
      const t = val(r[k]); if (!t) return;
      if (cp && COPY[k] && typeof r[k] === 'string') out.push(cpBtn(r[k], COPY[k], `<i>${esc(RES[k])}</i><span class="mono">${esc(t)}</span>`));
      else out.push(`<span class="wev-r"><i>${esc(RES[k])}</i>${esc(t)}</span>`);
    });
    Object.keys(r).filter((k) => !RES[k] && k !== 'quality').forEach((k) => { const t = val(r[k]); if (t) out.push(`<span class="wev-r"><i>${esc(niceKey(k))}</i>${esc(t)}</span>`); });
    if (e.serial) out.push(cp ? cpBtn(e.serial, 'serial number', `<i>Serial</i><span class="mono">${esc(e.serial)}</span>`) : `<span class="wev-r"><i>Serial</i>${esc(e.serial)}</span>`);
    if (e.caliber) out.push(`<span class="wev-r"><i>Caliber</i>${esc(e.caliber)}</span>`);
    if (e.ballistics && !r.ballistics) out.push(`<span class="wev-r"><i>Ballistics</i>${esc(val(e.ballistics) || '')}</span>`);
    if (e.entries && e.entries.length) out.push(`<span class="wev-r"><i>In frame</i>${e.entries.length} marker${e.entries.length === 1 ? '' : 's'}</span>`);
    if (e.cars && e.cars.length) {
      // 2.0.17: each vehicle's plate, as a code to copy (photos only list it when it was readable)
      const plates = cp ? e.cars.filter((c) => c && c.p && c.seen !== false) : [];
      if (plates.length) plates.slice(0, 8).forEach((c) => out.push(cpBtn(String(c.p).trim(), 'plate', `<i>🚗 ${esc(c.v || 'Plate')}</i><span class="mono">${esc(String(c.p).trim())}</span>`)));
      else out.push(`<span class="wev-r"><i>Vehicles</i>${e.cars.length}</span>`);
    }
    // 2.0.17: bodies in a crime scene photo (whip_evidence 4.2.3 entry.bodies)
    (e.bodies || []).slice(0, 6).forEach((b) => out.push(`<span class="wev-r body"><i>${esc(b.n)} ${esc(b.t || 'Body')}</i>${esc(b.i || '')}${b.d != null ? ` · ${esc(Math.round(b.d))} m` : ''}</span>`));
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

  // ---------------------------------------------------------------- 2.0.17: post-mortem (whip_evidence 4.2.3 'autopsy' report)
  const WOUND = { gunshot: 'Gunshot', stab: 'Stab / cut', blunt: 'Blunt force', vehicle: 'Vehicle', fall: 'Fall', burn: 'Burn', explosion: 'Explosion', other: 'Other' };
  const PART = { head: 'Head', torso: 'Torso', arms: 'Arms', legs: 'Legs' };
  const RANGE = { close: 'very close (under 2 m)', short: 'short range (2–10 m)', far: 'a distance (over 10 m)' };
  const wList = (l) => (l || []).map((x) => (WOUND[x.w] || x.w) + (x.n > 1 ? ' ×' + x.n : '')).join(', ');
  const dur = (s) => { s = Math.max(0, Math.round(+s || 0)); const m = Math.round(s / 60); if (m < 1) return 'under a minute'; if (m < 60) return m + ' min'; const h = Math.floor(m / 60); return h + ' h' + (m % 60 ? ' ' + (m % 60) + ' min' : ''); };
  /** "Body L4" for a bag taken from a body: by whip_evidence 4.2.3's entry.body, else its marker + "tested on" */
  function bodyOf(e) {
    if (!e || e.kind === 'autopsy') return null;
    if (e.body && e.marker) return 'Body ' + e.marker;
    if (e.body) return 'Body';
    if (e.marker && /^L\d+$/.test(e.marker) && e.testedOn && /^Body /.test(e.testedOn)) return e.testedOn;
    return null;
  }
  // where each hit is drawn: its part's area (centre x, y and half width, height); arms and legs alternate sides
  const AREA = { head: [[100, 44, 11, 12]], torso: [[100, 142, 22, 48]], arms: [[47, 152, 6, 40], [153, 152, 6, 40]], legs: [[84, 306, 8, 62], [116, 306, 8, 62]] };
  const MARK = {
    inside: '<circle r="6.5" fill="#ef4444" stroke="#fff" stroke-width="2"/>',
    through: '<circle r="5.6" fill="none" stroke="#f87171" stroke-width="2.6"/>',
    stab: '<path d="M-6 6L6-6" stroke="#fb923c" stroke-width="3.4" stroke-linecap="round"/>',
    blunt: '<path d="M0-6.5L6.5 0 0 6.5-6.5 0Z" fill="#facc15" stroke="#1f2937" stroke-width="1"/>',
    other: '<rect x="-5" y="-5" width="10" height="10" rx="2.5" fill="#a78bfa" stroke="#1f2937" stroke-width="1"/>',
  };
  const markKind = (m) => m.w === 'gunshot' ? (m.i ? 'inside' : 'through') : m.w === 'stab' ? 'stab' : m.w === 'blunt' ? 'blunt' : 'other';
  const MARK_LABEL = { inside: 'Gunshot · bullet still inside', through: 'Gunshot · went through', stab: 'Stab / cut', blunt: 'Blunt force', other: 'Other wound' };
  function bodyFigure(rep) {
    const marks = rep.marks || [];
    const seen = {}, perPart = {};
    marks.forEach((m) => { perPart[m.p] = (perPart[m.p] || 0) + 1; });
    const dots = marks.map((m, idx) => {
      const k = seen[m.p] = (seen[m.p] || 0) + 1;
      const areas = AREA[m.p] || AREA.torso, a = areas[(k - 1) % areas.length];
      const nth = Math.floor((k - 1) / areas.length), n = Math.ceil((perPart[m.p] || 1) / areas.length);
      // spread the hits of one part on a small spiral (golden angle): stable, never on top of each other
      const ang = nth * 2.39996 + 0.6, rr = n <= 1 ? 0.15 : Math.sqrt((nth + 0.5) / n);
      const x = a[0] + Math.cos(ang) * a[2] * rr, y = a[1] + Math.sin(ang) * a[3] * rr;
      const kind = markKind(m);
      const halo = m.f ? '<circle r="11.5" fill="none" stroke="#fde047" stroke-width="1.8" stroke-dasharray="3 2.4"/>' : '';
      return `<g class="pm-m" transform="translate(${x.toFixed(1)} ${y.toFixed(1)})"><title>${esc(PART[m.p] || m.p)}: ${esc(MARK_LABEL[kind])}${m.f ? ' (fatal)' : ''}</title>${halo}${MARK[kind]}</g>`;
    }).join('');
    const hit = (p) => perPart[p] ? ' hit' : '';
    const skin = 'class="pm-skin"';
    const svg = `<svg class="pm-svg" viewBox="0 0 200 410" role="img" aria-label="Body, front: ${marks.length} hit${marks.length === 1 ? '' : 's'}">
      <ellipse ${skin} data-part="head" class="pm-skin${hit('head')}" cx="100" cy="42" rx="23" ry="26"/>
      <path class="pm-skin${hit('torso')}" d="M91 66h18v12H91z"/>
      <path class="pm-skin${hit('torso')}" d="M64 84Q100 72 136 84L140 128Q136 170 134 204Q100 214 66 204Q64 170 60 128Z"/>
      <path class="pm-skin${hit('arms')}" d="M62 86Q48 90 44 104L36 196Q36 210 46 212Q54 212 56 200L64 126Z"/>
      <path class="pm-skin${hit('arms')}" d="M138 86Q152 90 156 104L164 196Q164 210 154 212Q146 212 144 200L136 126Z"/>
      <path class="pm-skin${hit('legs')}" d="M67 204L98 210L95 394Q86 400 76 394L70 300Z"/>
      <path class="pm-skin${hit('legs')}" d="M133 204L102 210L105 394Q114 400 124 394L130 300Z"/>
      ${dots}</svg>`;
    const used = new Set(marks.map(markKind));
    const legend = Object.keys(MARK).filter((k) => used.has(k) || k === 'inside' || k === 'through')
      .map((k) => `<span><svg viewBox="-9 -9 18 18" aria-hidden="true">${MARK[k]}</svg>${esc(MARK_LABEL[k])}</span>`).join('')
      + (marks.some((m) => m.f) ? '<span><svg viewBox="-13 -13 26 26" aria-hidden="true"><circle r="11.5" fill="none" stroke="#fde047" stroke-width="1.8" stroke-dasharray="3 2.4"/></svg>Fatal</span>' : '');
    return `<div class="pm-fig">${svg}<div class="pm-cap">FRONT</div><div class="pm-legend">${legend}</div></div>`;
  }
  function reportText(e, rep) {
    if (rep.text) return rep.text;
    const lines = [`Body L${rep.no || '?'}`, `Dead for ${dur(rep.age)}${rep.sex ? ' · ' + rep.sex : ''} · ${rep.kind === 'player' ? 'person' : 'passer-by'}`];
    if (rep.fatal) lines.push(`Cause of death: ${WOUND[rep.fatal.w] || rep.fatal.w}, ${rep.fatal.p}`);
    lines.push(`Wounds: ${wList(rep.wounds)} (${rep.hits || 0} hit(s))`);
    return lines.join('\n');
  }
  function postMortem(e, all) {
    const rep = e.report;
    const samples = all.filter((x) => x !== e && x.kind !== 'autopsy' && ((rep.id && x.body === rep.id) || (!x.body && rep.no && x.marker === 'L' + rep.no && bodyOf(x))));
    const rows = [];
    const row = (k, v, c) => rows.push(`<div class="pm-r${c ? ' ' + c : ''}"><span class="k">${k}</span><span class="v">${v}</span></div>`);
    row('Wounds', `${esc(wList(rep.wounds) || '—')} <span class="hint">(${rep.hits || 0} hit${rep.hits === 1 ? '' : 's'})</span>`);
    (rep.byPart || []).forEach((p) => row(`<span class="pm-sub">${esc(PART[p.p] || p.p)}</span>`, esc(wList(p.w))));
    if ((rep.ranges || []).length) row('Shot from', esc(rep.ranges.map((r) => RANGE[r] || r).join(', ')));
    if (rep.through || rep.bullets) row('Bullets', `${rep.bullets} still in the body · ${rep.through} went through`, rep.bullets ? 'red' : '');
    if (rep.defense) row('Defence wounds', 'on the arms: they fought back', 'warn');
    if (rep.armed) row('Weapon', 'had a weapon in hand', 'warn');
    if (rep.moved) row('Position', `moved about ${esc(rep.moved)} m after death`, 'warn');
    const sec = [rep.photo && '📷 photographed', rep.blood && '🩸 blood sample', rep.gsr && '💨 GSR test'].filter(Boolean);
    row('Secured at the scene', sec.length ? esc(sec.join(', ')) : 'nothing yet');
    const tod = rep.diedAt ? new Date(rep.diedAt * 1000).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' }) : null;
    const todDay = rep.diedAt ? new Date(rep.diedAt * 1000).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : '';
    const sub = [`Dead for ${dur(rep.age)} at the exam`, rep.sex, rep.kind === 'player' ? 'person' : 'passer-by'].filter(Boolean).map(esc).join(' · ');
    const sampleChips = samples.map((x) => `<button type="button" class="pm-sample" data-wevgo="${esc(x.ref)}" title="Show this item">${kindOf(x)[1]} ${title(x)}</button>`).join('');
    const sampleCodes = samples.map((x) => resultChips(x, true)).filter(Boolean).join('');
    const pad = window.ESPad && window.ESPad.state && window.ESPad.state().pad;
    return `<div class="pm-card${e.gone ? ' gone' : ''}" data-pmref="${esc(e.ref)}">
      <div class="pm-head"><div><div class="pm-kicker">POST-MORTEM FINDINGS</div><div class="pm-title">${esc(rep.title || ('Body L' + (rep.no || '?')))}</div><div class="hint">${sub}</div></div>
        <div class="row">${cpBtn(reportText(e, rep), 'post-mortem report', '<span>Copy report as text</span>', 'btn small ghost pm-copy')}</div></div>
      <div class="pm-grid">${bodyFigure(rep)}
        <div class="pm-main">
          ${rep.fatal ? `<div class="pm-cause"><div class="k">Cause of death</div><div class="v">${esc(WOUND[rep.fatal.w] || rep.fatal.w)}, ${esc((PART[rep.fatal.p] || rep.fatal.p).toLowerCase())}</div></div>` : ''}
          <div class="pm-tiles"><div class="pm-tile"><b>${rep.hits || 0}</b><span>hits</span></div>
            <div class="pm-tile${rep.bullets ? ' red' : ''}"><b>${rep.bullets || 0}</b><span>bullets inside</span></div>
            <div class="pm-tile"><b>${tod ? esc(tod) : esc(dur(rep.age))}</b><span>${tod ? 'time of death · ' + esc(todDay) : 'dead for'}</span></div></div>
          <div class="pm-rows">${rows.join('')}</div>
          ${samples.length ? `<div class="pm-samples"><div class="lbl">From this body · ${samples.length}</div><div class="row wrap">${sampleChips}</div>${sampleCodes ? `<div class="wev-rs mt">${sampleCodes}</div>` : ''}</div>` : ''}
          <div class="hint pm-foot">${rep.examinedBy ? 'Examined by ' + esc(rep.examinedBy) : 'Examined'}${rep.examinedAt ? ' · ' + esc(dateTime(rep.examinedAt)) : ''}${rep.street ? ' · ' + esc(rep.street) : ''}
            · ${pad && window.ESPad.glyph ? `${window.ESPad.glyph('a')} on a code copies it` : 'click a code to copy it'}</div>
        </div></div></div>`;
  }

  // ---------------------------------------------------------------- one saved entry
  function tile(e, w) {
    const t = w.taken && w.taken[e.ref];
    const custody = (e.custody || []).length ? `<details class="wev-cust"><summary>Chain of custody · ${e.custody.length} step${e.custody.length === 1 ? '' : 's'}</summary>
      <div class="ev-chain">${e.custody.map(step).join('')}</div></details>` : '';
    const photo = (e.kind === 'photo' || String(e.ref).startsWith('photo:')) ? `<div class="wev-thumb" data-wevimg="${esc(e.ref)}" data-wevph="${esc(e.ref)}" title="Open the photo"></div>` : '';
    return `<div class="wev-tile${e.gone ? ' gone' : ''}" data-wevref="${esc(e.ref)}">
      ${photo}
      <div class="wev-head">${ico(e)}<div class="wev-t"><b>${title(e)}</b><span class="hint">${esc(kindOf(e)[0])} · ${cpBtn(e.ref, 'item ref', `<span class="mono">${esc(e.ref)}</span>`, 'wev-ref cp')}</span></div>
        ${bodyOf(e) ? `<span class="wev-bodyp" title="Taken from this body">${esc(bodyOf(e))}</span>` : ''}</div>
      ${t ? `<div class="wev-out">Out of locker: taken by <b>${esc(t.by || 'someone')}</b>${t.at ? ' · ' + esc(ago(t.at > 1e11 ? t.at / 1000 : t.at)) : ''}${t.what ? ' · ' + esc(t.what) : ''}</div>` : ''}
      ${e.gone ? '<div class="wev-gone">No longer in the locker (deleted in whip_evidence) · saved copy</div>' : ''}
      ${meta(e) ? `<div class="hint wev-meta">${meta(e)}</div>` : ''}
      ${resultChips(e, true) ? `<div class="wev-rs">${resultChips(e, true)}</div>` : ''}
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
        <div class="card-title">Evidence locker <span class="wev-tag">whip_evidence</span> <span class="hint">· ${items.length} item${items.length === 1 ? '' : 's'}${out ? ` · ${out} out of the locker` : ''}</span>
          ${cpBtn(k.number, 'case number', `<span class="mono">${esc(k.number)}</span>`, 'wev-ref cp case')}</div>
        <div class="row">${w.closed ? '<span class="pill accent">Locker closed</span>' : ''}
          ${w.running ? '<button class="btn small ghost" id="wev-locker" title="Works when you stand at an evidence locker">Open locker</button>' : ''}
          ${canAdd ? '<button class="btn small" id="wev-add">+ Add evidence</button>' : ''}</div></div>
      ${!w.running ? '<div class="hint">whip_evidence is not running right now: showing the copies saved in the MDT.</div>' : ''}
      ${items.filter((e) => e.report).map((e) => postMortem(e, items)).join('')}
      ${items.length ? `<div class="wev-grid">${items.map((e) => tile(e, w)).join('')}</div>`
        : `<div class="empty-state wev-empty"><div class="es-ico">🗄️</div>Nothing uploaded yet.${canAdd ? ' Analysed items you carry can be added with “+ Add evidence”, or at the lab device with case number <b>' + esc(k.number) + '</b>.' : ''}</div>`}
    </div>`;
    const box = $('#cv-wev', v);
    wireCopy(box);
    $$('[data-wevgo]', box).forEach((b) => b.onclick = () => {
      const t = box.querySelector(`[data-wevref="${CSS.escape(b.dataset.wevgo)}"]`);
      if (t) { t.scrollIntoView({ block: 'center', behavior: 'smooth' }); t.classList.add('flash'); setTimeout(() => t.classList.remove('flash'), 1400); }
    });
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
