// es_departments page. Talks to client/main.lua through NUI callbacks; the server decides everything.
(function () {
  'use strict';
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'es_mdt';   // 2.0.0: one resource (es_mdt)
  const $ = (s, r) => (r || document).querySelector(s);
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const MAX_BYTES = 192 * 1024, SIDE = 256;

  const S = { open: false, meta: null, list: [], cur: null, tab: 'overview', logos: {}, rankSel: null, memberSel: null,
    dirty: false, picker: null };

  async function nui(name, data) {
    try {
      const r = await fetch(`https://${RES}/dept_${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) });
      return await r.json();
    } catch (e) { return { ok: false, why: 'The game did not answer' }; }
  }

  // ---------------------------------------------------------------- toasts
  let toastTimer = null;
  function toast(text, kind) {
    const t = $('#toast');
    t.innerHTML = `<span class="t-dot"></span><span>${esc(text)}</span>`;
    t.className = 'toast show ' + (kind || '');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 3200);
  }
  function said(r, okText) {
    if (r && r.ok) { if (okText) toast(okText, 'ok'); return true; }
    if (r && !r.quiet) toast((r && r.why) || 'That did not work', 'err');
    return false;
  }
  async function busy(btn, fn) {
    if (!btn || btn.disabled) return;
    const label = btn.innerHTML; btn.disabled = true; btn.classList.add('loading');
    try { return await fn(); } finally { btn.disabled = false; btn.classList.remove('loading'); btn.innerHTML = label; }
  }

  // ---------------------------------------------------------------- inline validation
  function fieldError(input, msg) {
    const f = input.closest('.field'); if (!f) return;
    let e = f.querySelector('.f-err');
    if (!e) { e = document.createElement('div'); e.className = 'f-err'; f.appendChild(e); }
    e.textContent = msg || ''; f.classList.toggle('invalid', !!msg);
  }
  function validate(rules) {   // [[input, fn -> message|null], ...]; returns true when all pass
    let ok = true;
    rules.forEach(([input, fn]) => { const m = fn(input.value); fieldError(input, m); if (m) ok = false; });
    return ok;
  }
  function live(rules) { rules.forEach(([input, fn]) => input.addEventListener('input', () => fieldError(input, fn(input.value)))); }

  // ---------------------------------------------------------------- logos (saved ones)
  async function logoOf(d) {
    if (!d || !d.logoVer) return null;
    const have = S.logos[d.id];
    if (have && have.ver === d.logoVer) return have.data;
    const r = await nui('logoFetch', { id: d.id, ver: d.logoVer });
    if (r && r.ok && r.data) { S.logos[d.id] = { ver: d.logoVer, data: r.data }; return r.data; }
    return null;
  }

  // ---------------------------------------------------------------- the logo picker
  // Choose a file, drop one, paste one (Ctrl+V) or paste a link. Shows the logo exactly as it will be saved.
  function loadImg(src) {
    return new Promise((res, rej) => { const im = new Image(); im.onload = () => res(im); im.onerror = () => rej(new Error('That is not a picture this screen can read')); im.src = src; });
  }
  function cutBackground(ctx) {
    const img = ctx.getImageData(0, 0, SIDE, SIDE), p = img.data;
    let seed = -1;
    for (const [x, y] of [[1, 1], [SIDE - 2, 1], [1, SIDE - 2], [SIDE - 2, SIDE - 2]]) { const i = (y * SIDE + x) * 4; if (p[i + 3] > 200) { seed = i; break; } }
    if (seed < 0) return false;
    const c = [p[seed], p[seed + 1], p[seed + 2]];
    const near = (i) => Math.abs(p[i] - c[0]) + Math.abs(p[i + 1] - c[1]) + Math.abs(p[i + 2] - c[2]) < 90;
    const seen = new Uint8Array(SIDE * SIDE), stack = [];
    for (let i = 0; i < SIDE; i++) stack.push(i, 0, i, SIDE - 1, 0, i, SIDE - 1, i);
    while (stack.length) {
      const y = stack.pop(), x = stack.pop();
      if (x < 0 || y < 0 || x >= SIDE || y >= SIDE) continue;
      const k = y * SIDE + x; if (seen[k]) continue; seen[k] = 1;
      const i = k * 4; if (p[i + 3] === 0) { stack.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1); continue; }
      if (!near(i)) continue;
      p[i + 3] = 0;
      stack.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1);
    }
    ctx.putImageData(img, 0, 0);
    return true;
  }
  const bytesOf = (u) => Math.floor((u.length - u.indexOf(',') - 1) * 3 / 4);
  function render(im, cut, format) {
    const cv = document.createElement('canvas'); cv.width = SIDE; cv.height = SIDE;
    const ctx = cv.getContext('2d');
    const s = Math.min(SIDE / im.width, SIDE / im.height);
    const w = Math.round(im.width * s), h = Math.round(im.height * s);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(im, Math.round((SIDE - w) / 2), Math.round((SIDE - h) / 2), w, h);
    if (cut) cutBackground(ctx);
    if (format !== 'png') {
      for (const q of [0.92, 0.85, 0.75, 0.6, 0.45]) {
        const u = cv.toDataURL('image/webp', q);
        if (u.indexOf('data:image/webp') === 0 && bytesOf(u) <= MAX_BYTES) return u;
      }
    }
    const png = cv.toDataURL('image/png');
    if (bytesOf(png) <= MAX_BYTES) return png;
    throw new Error('Even shrunk, that picture is over 192 KB. Try WebP.');
  }

  function makePicker(host, opts) {
    const P = { src: null, out: null, saved: opts.current || null, dirty: false, deptId: opts.deptId || 0, token: 0 };
    host.innerHTML = `
      <div class="picker">
        <div class="drop" tabindex="0" data-probe-press>
          <div class="drop-preview"></div>
          <div class="drop-state"></div>
        </div>
        <div class="pick-side">
          <div class="row">
            <button class="btn" data-pick="file" data-probe-press>📁 Choose picture</button>
            <input type="file" accept="image/*" class="hidden">
            <button class="btn ghost" data-pick="clear" data-probe-press>Clear</button>
          </div>
          <div class="url-row">
            <input type="text" placeholder="…or paste an image link (https://…)" data-pick="url">
            <button class="btn" data-pick="load" data-probe-press>Load</button>
          </div>
          <div class="row opts">
            <label class="switch"><input type="checkbox" data-pick="cut"><span></span> Remove plain background</label>
            <div class="seg" data-pick="fmt"><button data-v="webp" class="on">WebP</button><button data-v="png">PNG</button></div>
          </div>
          <div class="hint pick-info"></div>
        </div>
      </div>`;
    const drop = $('.drop', host), prev = $('.drop-preview', host), state = $('.drop-state', host), info = $('.pick-info', host);
    const file = $('input[type=file]', host), url = $('[data-pick=url]', host), cut = $('[data-pick=cut]', host);
    let fmt = opts.format || 'webp';
    host.querySelectorAll('.seg button').forEach((b) => b.classList.toggle('on', b.dataset.v === fmt));

    function show(kind, msg) {
      drop.className = 'drop ' + kind;
      const img = P.out || (kind === 'saved' ? P.saved : null);
      prev.innerHTML = img ? `<img src="${img}" alt="">` : '';
      if (kind === 'loading') state.innerHTML = '<div class="spin"></div><div>Loading picture…</div>';
      else if (kind === 'error') state.innerHTML = `<div class="err-ico">!</div><div>${esc(msg)}</div><div class="hint">Try another link, a file, or Ctrl+V</div>`;
      else if (kind === 'empty') state.innerHTML = '<div class="drop-ico">⬆</div><div><b>Drop a picture here</b></div><div class="hint">or paste one with Ctrl+V</div>';
      else state.innerHTML = '';
      if (P.out) info.textContent = `Preview: ${SIDE}×${SIDE} · ${P.out.indexOf('image/png') > 0 ? 'PNG' : 'WebP'} · ${Math.ceil(bytesOf(P.out) / 1024)} KB · not saved yet`;
      else if (P.saved) info.textContent = 'This is the saved logo.';
      else info.textContent = `Any picture works. It is shrunk to ${SIDE}×${SIDE}, up to 192 KB.`;
      opts.onChange && opts.onChange(P);
    }
    function process() {
      if (!P.src) return;
      try { P.out = render(P.src, cut.checked, fmt); P.dirty = true; show('ready'); }
      catch (e) { P.out = null; P.dirty = false; show('error', e.message); }
    }
    async function useSrc(srcUrl) {
      const t = ++P.token; show('loading');
      try { const im = await loadImg(srcUrl); if (t !== P.token) return; P.src = im; process(); }
      catch (e) { if (t === P.token) { P.out = null; P.src = null; show('error', e.message); } }
    }
    function useFile(f) {
      if (!f) return;
      if (!f.type || f.type.indexOf('image/') !== 0) { show('error', 'That file is not a picture'); return; }
      useSrc(URL.createObjectURL(f));
    }
    async function useUrl(u) {
      u = (u || '').trim();
      if (u.indexOf('data:image/') === 0) { useSrc(u); return; }
      if (!/^https?:\/\/\S+$/i.test(u)) { show('error', 'A link starts with https://'); return; }
      const t = ++P.token; show('loading');
      // First the browser itself (works when the site allows it), then the server fetches it
      try {
        const r = await fetch(u, { mode: 'cors' });
        if (r.ok) {
          const b = await r.blob();
          if (b.type && b.type.indexOf('image/') === 0) { if (t !== P.token) return; return useSrc(URL.createObjectURL(b)); }
        }
      } catch (e) { /* not allowed from here: ask the server */ }
      const r = await nui('urlFetch', { id: P.deptId, url: u });
      if (t !== P.token) return;
      if (r && r.ok && r.data) return useSrc(r.data);
      P.out = null; P.src = null; show('error', (r && r.why) || 'That link did not load');
    }
    P.useFile = useFile; P.useUrl = useUrl;
    P.clear = () => { P.token++; P.src = null; P.out = null; P.dirty = false; url.value = ''; show(P.saved ? 'saved' : 'empty'); };
    P.value = () => P.out;
    P.markSaved = (u) => { P.saved = u; P.src = null; P.out = null; P.dirty = false; show('saved'); };

    $('[data-pick=file]', host).onclick = () => file.click();
    file.onchange = (e) => { useFile(e.target.files && e.target.files[0]); e.target.value = ''; };
    $('[data-pick=clear]', host).onclick = P.clear;
    $('[data-pick=load]', host).onclick = () => useUrl(url.value);
    url.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); useUrl(url.value); } });
    url.addEventListener('paste', (e) => e.stopPropagation());   // a link typed into the box stays a link
    cut.onchange = process;
    host.querySelectorAll('.seg button').forEach((b) => b.onclick = () => { fmt = b.dataset.v; host.querySelectorAll('.seg button').forEach((x) => x.classList.toggle('on', x === b)); process(); });
    drop.onclick = () => file.click();
    ['dragenter', 'dragover'].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('hover'); }));
    ['dragleave', 'drop'].forEach((ev) => drop.addEventListener(ev, () => drop.classList.remove('hover')));
    drop.addEventListener('drop', (e) => {
      e.preventDefault();
      const dt = e.dataTransfer; if (!dt) return;
      if (dt.files && dt.files.length) return useFile(dt.files[0]);
      const link = dt.getData('text/uri-list') || dt.getData('text/plain');
      if (link) { url.value = link.split('\n')[0].trim(); useUrl(url.value); }
    });
    S.picker = P;
    show(P.saved ? 'saved' : 'empty');
    return P;
  }

  // Ctrl+V anywhere: a picture goes to the picker on screen; a link too
  document.addEventListener('paste', (e) => {
    const P = S.picker; if (!S.open || !P || !document.body.contains($('.picker'))) return;
    const items = (e.clipboardData && e.clipboardData.items) || [];
    for (const it of items) { if (it.type && it.type.indexOf('image/') === 0) { e.preventDefault(); P.useFile(it.getAsFile()); return; } }
    const text = e.clipboardData && e.clipboardData.getData('text/plain');
    const tag = (e.target && e.target.tagName) || '';
    if (text && /^https?:\/\//i.test(text.trim()) && tag !== 'INPUT' && tag !== 'TEXTAREA') { $('[data-pick=url]').value = text.trim(); P.useUrl(text); }
  });

  async function uploadLogo(id, dataUrl) {
    const r = await nui('logo', { id, dataUrl });
    if (r && r.ok) S.logos[id] = { ver: r.data.logoVer, data: dataUrl };
    return r;
  }

  // ---------------------------------------------------------------- list
  function renderList() {
    const box = $('#dept-list');
    box.innerHTML = '';
    if (!S.list.length) {
      box.innerHTML = `<div class="list-empty">No departments yet.${S.meta && S.meta.admin ? '<br>Create the first one below.' : ''}</div>`;
    }
    S.list.forEach((d) => {
      const el = document.createElement('div');
      el.className = 'dept-item' + (S.cur && S.cur.id === d.id ? ' on' : '');
      el.style.setProperty('--c1', d.color1);
      el.setAttribute('data-probe-press', '');
      el.innerHTML = `<div class="ph">${esc(d.short.slice(0, 2))}</div><div class="di-text"><div class="s">${esc(d.short)}</div><div class="n">${esc(d.name)}</div></div>`;
      el.onclick = () => select(d.id);
      box.appendChild(el);
      logoOf(d).then((src) => { if (src) { const i = document.createElement('img'); i.src = src; el.replaceChild(i, el.firstChild); } });
    });
    $('#btn-new').classList.toggle('hidden', !(S.meta && S.meta.admin));
    $('#btn-health').classList.toggle('hidden', !(S.meta && S.meta.health));
  }

  async function reloadList() {
    const r = await nui('reload');
    if (!r.ok) { toast(r.why, 'err'); return; }
    S.meta = r.data; S.list = r.data.departments || [];
    renderList();
  }

  function showPane(which) {
    ['empty', 'dept', 'create', 'health'].forEach((p) => $('#' + p).classList.toggle('hidden', p !== which));
    $('#btn-health').classList.toggle('on', which === 'health');
    const el = $('#' + which); el.classList.remove('fade-in'); void el.offsetWidth; el.classList.add('fade-in');
  }

  async function select(id, keepTab) {
    const r = await nui('get', { id });
    if (!r.ok) { toast(r.why, 'err'); return; }
    const same = S.cur && S.cur.id === id;
    S.cur = r.data; S.dirty = false;
    if (!keepTab) { S.tab = 'overview'; S.rankSel = null; S.memberSel = null; }
    if (!same || !keepTab) showPane('dept');
    renderList(); renderDept();
  }

  // ---------------------------------------------------------------- department
  function typeLabel(k) { const t = (S.meta.types || []).find((x) => x.key === k); return t ? t.label : k; }

  function renderDept() {
    const d = S.cur, rt = d.rights || {};
    const shell = $('.shell');
    shell.style.setProperty('--dept1', d.color1); shell.style.setProperty('--dept2', d.color2);
    $('#d-short').textContent = d.short; $('#d-name').textContent = d.name;
    const onDuty = (d.roster || []).filter((m) => m.onDuty).length;
    const n = (d.roster || []).length;
    $('#d-meta').innerHTML = `<span class="chip">${esc(typeLabel(d.type))}</span><span class="chip">${n} ${n === 1 ? 'member' : 'members'}</span><span class="chip ${onDuty ? 'live' : ''}">${onDuty} on duty</span>`;
    const img = $('#d-logo');
    img.classList.add('hidden'); $('#d-logo-none').classList.remove('hidden');
    logoOf(d).then((src) => { if (src && S.cur === d) { img.src = src; img.classList.remove('hidden'); $('#d-logo-none').classList.add('hidden'); } });
    document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('on', t.dataset.tab === S.tab));
    ['overview', 'ranks', 'roster'].forEach((t) => $('#tab-' + t).classList.toggle('hidden', t !== S.tab));
    const body = $('#tab-' + S.tab); body.classList.remove('fade-in'); void body.offsetWidth; body.classList.add('fade-in');
    S.picker = null;
    if (S.tab === 'overview') renderOverview(d, rt);
    if (S.tab === 'ranks') renderRanks(d, rt);
    if (S.tab === 'roster') renderRoster(d, rt);
  }

  function typeOptions(sel) {
    return (S.meta.types || []).map((t) => `<option value="${esc(t.key)}"${t.key === sel ? ' selected' : ''}>${esc(t.label)}</option>`).join('');
  }

  const rulesFor = (shortEl, nameEl, selfId) => [
    [shortEl, (v) => !v.trim() ? 'Give it a short name, like LSPD' : v.trim().length > 12 ? '12 characters at most'
      : S.list.some((x) => x.id !== selfId && x.short.toLowerCase() === v.trim().toLowerCase()) ? 'Another department already uses this' : null],
    [nameEl, (v) => !v.trim() ? 'Give it a full name' : null],
  ];

  function renderOverview(d, rt) {
    const dis = rt.edit ? '' : ' disabled';
    const box = $('#tab-overview');
    box.innerHTML = `
      <div class="card">
        <div class="card-title">Details</div>
        <div class="grid">
          <div class="field"><label>Short name</label><input type="text" id="o-short" maxlength="12" value="${esc(d.short)}"${dis}></div>
          <div class="field"><label>Full name</label><input type="text" id="o-name" maxlength="80" value="${esc(d.name)}"${dis}></div>
          <div class="field"><label>Type</label><select id="o-type"${rt.admin ? '' : ' disabled'}>${typeOptions(d.type)}</select>${rt.admin ? '' : '<div class="hint">Only full admins can change this</div>'}</div>
          <div class="field"><label>Position in the list</label><input type="number" id="o-sort" min="0" max="999" value="${d.sort || 0}"${rt.staff ? '' : ' disabled'}></div>
          <div class="field"><label>Colours</label><div class="row"><label class="swatch"><input type="color" id="o-c1" value="${esc(d.color1)}"${dis}><span>Main</span></label><label class="swatch"><input type="color" id="o-c2" value="${esc(d.color2)}"${dis}><span>Trim</span></label></div></div>
          <div class="field"><label>Job ID</label><input type="text" value="${esc(d.key)}" disabled><div class="hint">What scripts use to find this department</div></div>
        </div>
        ${rt.edit ? '<div class="row actions"><button class="btn accent" id="o-save" data-primary data-probe-press>Save changes</button><span class="hint">Enter saves</span></div>' : ''}
      </div>
      <div class="card">
        <div class="card-title">Logo</div>
        ${rt.edit ? `<div id="o-picker"></div><div class="row actions"><button class="btn accent" id="o-logo-save" disabled data-probe-press>Save logo</button><span class="hint" id="o-logo-hint">Pick, drop, paste or link a picture to see it here first</span></div>`
          : '<div class="logo-box" id="o-logo-box"><span class="hint">No logo</span></div><p class="hint">Only the department\'s leaders can change it.</p>'}
      </div>
      ${rt.admin ? `<div class="card danger-zone"><div class="card-title">Delete department</div><div class="row">
        <label class="switch"><input type="checkbox" id="o-alsojob"><span></span> Also delete its job, ranks and member list</label>
        <button class="btn danger" id="o-del" data-probe-press>Delete department</button></div></div>` : ''}`;
    if (rt.edit) {
      const shortEl = $('#o-short'), nameEl = $('#o-name');
      const rules = rulesFor(shortEl, nameEl, d.id); live(rules);
      $('#o-save').onclick = (e) => busy(e.currentTarget, async () => {
        if (!validate(rules)) return;
        const data = { short: shortEl.value.trim(), name: nameEl.value.trim(), type: $('#o-type').value,
          color1: $('#o-c1').value, color2: $('#o-c2').value, sort: parseInt($('#o-sort').value, 10) || 0 };
        if (said(await nui('update', { id: d.id, data }), 'Changes saved')) { await reloadList(); select(d.id, true); }
      });
      logoOf(d).then((src) => {
        if (S.cur !== d || S.tab !== 'overview') return;
        const P = makePicker($('#o-picker'), { deptId: d.id, current: src, onChange: (p) => {
          $('#o-logo-save').disabled = !p.out;
          $('#o-logo-hint').textContent = p.out ? 'Looks good? Save it. Clear puts the old one back.' : 'Pick, drop, paste or link a picture to see it here first';
          if (p.out) S.dirty = true;
        } });
        $('#o-logo-save').onclick = (e) => busy(e.currentTarget, async () => {
          const u = P.value(); if (!u) return;
          const r = await uploadLogo(d.id, u);
          if (said(r, 'Logo saved')) { P.markSaved(u); S.dirty = false; await reloadList(); select(d.id, true); }
        });
      });
    } else {
      logoOf(d).then((src) => { if (src && $('#o-logo-box')) $('#o-logo-box').innerHTML = `<img src="${src}">`; });
    }
    if (rt.admin) {
      $('#o-del').onclick = (e) => busy(e.currentTarget, async () => {
        const r = await nui('delete', { id: d.id, alsoJob: $('#o-alsojob').checked });
        if (said(r, 'Department deleted')) { S.cur = null; showPane('empty'); reloadList(); }
      });
    }
  }

  // ---------------------------------------------------------------- ranks
  function permsFor(type) { return (S.meta.permissions || {})[type] || []; }

  function renderRanks(d, rt) {
    const box = $('#tab-ranks');
    const ranks = d.ranks || [];
    const rows = ranks.map((r) => {
      const held = (d.roster || []).filter((m) => m.roleId === r.roleId).length;
      const count = Object.keys(r.permissions || {}).filter((k) => r.permissions[k] === true).length;
      return `<tr class="click${S.rankSel === r.roleId ? ' sel' : ''}" data-role="${r.roleId}" data-probe-press>
        <td><span class="lvl">${r.level}</span></td><td><b>${esc(r.name)}</b></td><td>${esc(r.abbr || '')}</td><td>${esc(r.insignia && r.insignia !== 'none' ? r.insignia : '')}</td>
        <td>${esc(r.callsignPrefix || '')}</td><td>${r.level >= 100 ? 'All' : count}</td><td>${held}</td></tr>`;
    }).join('');
    box.innerHTML = `<div class="card">
      <div class="card-head"><div class="card-title">Ranks</div>${rt.ranks ? '<button class="btn" id="r-new" data-probe-press>+ New rank</button>' : ''}</div>
      ${ranks.length ? `<table><thead><tr><th>Level</th><th>Rank</th><th>Short</th><th>Insignia</th><th>Callsign start</th><th>Permissions</th><th>People</th></tr></thead><tbody>${rows}</tbody></table>
        <p class="hint" style="margin-top:8px">Click a rank to see or change what it can do.</p>`
        : '<div class="empty-state">No ranks yet. Add the first one with “New rank”.</div>'}
      </div><div id="r-editor"></div>`;
    box.querySelectorAll('tr[data-role]').forEach((tr) => tr.onclick = () => { S.rankSel = +tr.dataset.role; renderRanks(d, rt); });
    if (rt.ranks) $('#r-new').onclick = () => { S.rankSel = 0; renderRanks(d, rt); };
    if (S.rankSel !== null) rankEditor(d, rt, S.rankSel === 0 ? null : ranks.find((r) => r.roleId === S.rankSel));
  }

  function rankEditor(d, rt, r) {
    const ed = $('#r-editor');
    const dis = rt.ranks ? '' : ' disabled';
    const p = (r && r.permissions) || {};
    const top = r && r.level >= 100;
    const tog = (k, label) => `<label class="toggle"><span class="switch"><input type="checkbox" data-perm="${esc(k)}"${(top || p[k]) ? ' checked' : ''}${(dis || top) ? ' disabled' : ''}><span></span></span> ${esc(label)}</label>`;
    const banks = [['none', 'No access'], ['view', 'Can view'], ['deposit', 'Can deposit'], ['withdraw', 'Can withdraw'], ['manager', 'Full control']];
    ed.innerHTML = `<div class="card fade-in">
      <div class="card-head"><div class="card-title">${r ? 'Edit ' + esc(r.name) : 'New rank'}</div><button class="icon-btn" id="r-x" title="Close">✕</button></div>
      <div class="grid">
        <div class="field"><label>Rank name</label><input type="text" id="r-name" maxlength="60" value="${esc(r ? r.name : '')}" placeholder="Sergeant"${dis}></div>
        <div class="field"><label>Level</label><input type="number" id="r-level" min="1" max="100" value="${r ? r.level : 10}"${dis}><div class="hint">1 to 100. Higher ranks manage lower ones; 100 can do everything.</div></div>
        <div class="field"><label>Short name</label><input type="text" id="r-abbr" maxlength="8" value="${esc(r ? r.abbr || '' : '')}" placeholder="SGT"${dis}></div>
        <div class="field"><label>Insignia</label><select id="r-ins"${dis}>${(S.meta.insignia || []).map((i) => `<option${r && r.insignia === i ? ' selected' : ''}>${esc(i)}</option>`).join('')}</select></div>
        <div class="field"><label>Callsign start</label><input type="text" id="r-pre" maxlength="8" value="${esc(r ? r.callsignPrefix || '' : '')}" placeholder="2-"${dis}></div>
        <div class="field"><label>Department bank account</label><select id="r-bank"${(dis || top) ? ' disabled' : ''}>${banks.map(([b, l]) => `<option value="${b}"${(p.bankAccess || 'none') === b ? ' selected' : ''}>${l}</option>`).join('')}</select></div>
      </div>
      <div class="section"><div class="lbl">What this rank can do</div><div class="perm-grid">${permsFor(d.type).map((x) => tog(x.key, x.label)).join('')}</div></div>
      <div class="section"><div class="lbl">Managing people</div><div class="perm-grid">${(S.meta.builtins || []).map((x) => tog(x.key, x.label)).join('')}</div></div>
      ${top ? '<p class="hint section">A level 100 rank can do everything.</p>' : ''}
      ${rt.ranks ? `<div class="row actions"><button class="btn accent" id="r-save" data-primary data-probe-press>${r ? 'Save rank' : 'Create rank'}</button>
        ${r ? '<button class="btn danger" id="r-del" data-probe-press>Delete rank</button>' : ''}<span class="hint">Enter saves</span></div>` : ''}
    </div>`;
    $('#r-x').onclick = () => { S.rankSel = null; renderRanks(d, rt); };
    if (!rt.ranks) return;
    const nameEl = $('#r-name'), lvlEl = $('#r-level');
    const rules = [[nameEl, (v) => !v.trim() ? 'Give the rank a name' : (d.ranks || []).some((x) => (!r || x.roleId !== r.roleId) && x.name.toLowerCase() === v.trim().toLowerCase()) ? 'There is already a rank with this name' : null],
      [lvlEl, (v) => { const n = Number(v); return (!Number.isInteger(n) || n < 1 || n > 100) ? 'A whole number from 1 to 100' : null; }]];
    live(rules);
    $('#r-save').onclick = (e) => busy(e.currentTarget, async () => {
      if (!validate(rules)) return;
      const perms = Array.from(ed.querySelectorAll('input[data-perm]')).filter((i) => i.checked && !i.disabled).map((i) => i.dataset.perm);
      const data = { name: nameEl.value.trim(), level: parseInt(lvlEl.value, 10) || 1, abbr: $('#r-abbr').value,
        insignia: $('#r-ins').value, callsignPrefix: $('#r-pre').value, bankAccess: $('#r-bank').value };
      const res = await nui('rankSave', { id: d.id, roleId: r ? r.roleId : 0, data, perms });
      if (said(res, r ? 'Rank saved' : 'Rank created')) { S.rankSel = res.data; select(d.id, true); }
    });
    if (r) $('#r-del').onclick = (e) => busy(e.currentTarget, async () => { if (said(await nui('rankDelete', { id: d.id, roleId: r.roleId }), 'Rank deleted')) { S.rankSel = null; select(d.id, true); } });
  }

  // ---------------------------------------------------------------- roster
  function rankOptions(d, sel) {
    return (d.ranks || []).map((r) => `<option value="${r.roleId}"${r.roleId === sel ? ' selected' : ''}>${esc(r.name)} (${r.level})</option>`).join('');
  }

  function renderRoster(d, rt) {
    const box = $('#tab-roster');
    const roster = d.roster || [];
    const rows = roster.map((m) => `<tr class="click${S.memberSel === m.charId ? ' sel' : ''}" data-char="${m.charId}" data-probe-press>
      <td><b>${esc(m.callsign || '—')}</b></td><td>${esc(m.name)}${m.owner ? ' <span class="pill">owner</span>' : ''}</td>
      <td>${esc(m.roleName || '')}${m.abbr ? ` <span class="hint">${esc(m.abbr)}</span>` : ''}</td><td>${esc(m.badge || '')}</td>
      <td>${m.onDuty ? '<span class="pill on">On duty</span>' : '<span class="pill off">Off duty</span>'}</td>
      <td>${m.online ? `<span class="pill">In city${m.source ? ' · ID ' + m.source : ''}</span>` : '<span class="pill off">Away</span>'}</td></tr>`).join('');
    box.innerHTML = `<div class="card">
      <div class="card-head"><div class="card-title">Members</div></div>
      ${roster.length ? `<table><thead><tr><th>Callsign</th><th>Name</th><th>Rank</th><th>Badge</th><th>Duty</th><th>Status</th></tr></thead><tbody>${rows}</tbody></table>
        <p class="hint" style="margin-top:8px">Click someone to set their callsign, badge, rank or notes.</p>`
        : '<div class="empty-state">Nobody here yet. Add someone who is in the city below.</div>'}
      </div>
      ${rt.hire ? `<div class="card"><div class="card-title">Add a member</div><div class="row">
        <div class="field"><label>Their server ID</label><input type="number" id="h-id" min="1" placeholder="e.g. 12" style="width:140px"></div>
        <div class="field"><label>Starting rank</label><select id="h-role">${rankOptions(d, (d.ranks || []).length ? d.ranks[d.ranks.length - 1].roleId : 0)}</select></div>
        <button class="btn accent" id="h-go" data-primary data-probe-press style="align-self:flex-end">Add to department</button></div>
        <div class="hint">They must be in the city. Their server ID is shown in the player list.</div></div>` : ''}
      <div id="m-editor"></div>`;
    box.querySelectorAll('tr[data-char]').forEach((tr) => tr.onclick = () => { S.memberSel = +tr.dataset.char; renderRoster(d, rt); });
    if (rt.hire) {
      const idEl = $('#h-id');
      const rules = [[idEl, (v) => (!v || !(parseInt(v, 10) > 0)) ? 'Type their server ID' : null]];
      $('#h-go').onclick = (e) => busy(e.currentTarget, async () => {
        if (!validate(rules)) return;
        if (said(await nui('hire', { id: d.id, target: parseInt(idEl.value, 10), roleId: +$('#h-role').value }), 'Added to ' + d.short)) select(d.id, true);
      });
    }
    const m = roster.find((x) => x.charId === S.memberSel);
    if (m) memberEditor(d, rt, m);
  }

  function memberEditor(d, rt, m) {
    const ed = $('#m-editor');
    const dis = rt.roster ? '' : ' disabled';
    ed.innerHTML = `<div class="card fade-in">
      <div class="card-head"><div class="card-title">${esc(m.name)}</div><button class="icon-btn" id="m-x" title="Close">✕</button></div>
      <div class="grid">
        <div class="field"><label>Callsign</label><input type="text" id="m-call" maxlength="16" value="${esc(m.callsign || '')}" placeholder="1-ADAM-12"${dis}></div>
        <div class="field"><label>Badge number</label><input type="text" id="m-badge" maxlength="12" value="${esc(m.badge || '')}" placeholder="4021"${dis}></div>
        <div class="field" style="grid-column: span 2"><label>Notes</label><textarea id="m-notes" maxlength="500" placeholder="Training, certifications…"${dis}>${esc(m.notes || '')}</textarea></div>
        <div class="field"><label>Rank</label><select id="m-rank"${(rt.promote && !m.owner) ? '' : ' disabled'}>${rankOptions(d, m.roleId)}</select></div>
      </div>
      <div class="row actions">
        ${rt.roster ? '<button class="btn accent" id="m-save" data-primary data-probe-press>Save</button>' : ''}
        ${(rt.promote && !m.owner) ? '<button class="btn" id="m-rank-go" data-probe-press>Change rank</button>' : ''}
        ${(rt.fire && !m.owner) ? '<button class="btn danger" id="m-fire" data-probe-press>Remove from department</button>' : ''}
      </div>
      ${m.owner ? '<p class="hint">The owner always holds the top rank. Change the owner in /whip → Jobs.</p>' : ''}
    </div>`;
    $('#m-x').onclick = () => { S.memberSel = null; renderRoster(d, rt); };
    if (rt.roster) $('#m-save').onclick = (e) => busy(e.currentTarget, async () => {
      const data = { callsign: $('#m-call').value, badge: $('#m-badge').value, notes: $('#m-notes').value };
      if (said(await nui('member', { id: d.id, charId: m.charId, data }), 'Saved')) select(d.id, true);
    });
    if (rt.promote && !m.owner) $('#m-rank-go').onclick = (e) => busy(e.currentTarget, async () => {
      if (said(await nui('setRank', { id: d.id, charId: m.charId, roleId: +$('#m-rank').value }), 'Rank changed')) select(d.id, true);
    });
    if (rt.fire && !m.owner) $('#m-fire').onclick = (e) => busy(e.currentTarget, async () => {
      if (said(await nui('fire', { id: d.id, charId: m.charId }), 'Removed')) { S.memberSel = null; select(d.id, true); }
    });
  }

  // ---------------------------------------------------------------- create
  function renderCreate() {
    S.cur = null; renderList();
    $('.shell').style.removeProperty('--dept1'); $('.shell').style.removeProperty('--dept2');
    const box = $('#create');
    box.innerHTML = `<div class="create-head"><div class="title">New department</div>
      <p class="hint">Fill in the basics and add a logo. You can change everything later.</p></div>
      <div class="card"><div class="card-title">Basics</div>
        <div class="grid">
          <div class="field"><label>Short name</label><input type="text" id="c-short" maxlength="12" placeholder="SASP"></div>
          <div class="field"><label>Full name</label><input type="text" id="c-name" maxlength="80" placeholder="San Andreas State Police"></div>
          <div class="field"><label>Type</label><select id="c-type">${typeOptions('police')}</select><div class="hint">Sets which permissions its ranks get</div></div>
          <div class="field"><label>Job ID</label><input type="text" id="c-key" maxlength="50" placeholder="sasp"><div class="hint">Filled in for you. Use an existing job's ID to turn that job into a department.</div></div>
          <div class="field"><label>Colours</label><div class="row"><label class="swatch"><input type="color" id="c-c1" value="#1b2a5c"><span>Main</span></label><label class="swatch"><input type="color" id="c-c2" value="#f2c230"><span>Trim</span></label></div></div>
        </div>
      </div>
      <div class="card"><div class="card-title">Logo <span class="hint">(optional)</span></div><div id="c-picker"></div></div>
      <div class="row actions"><button class="btn accent" id="c-go" data-primary data-probe-press>Create department</button><button class="btn ghost" id="c-cancel" data-probe-press>Cancel</button><span class="hint">Enter creates · Esc closes</span></div>`;
    showPane('create');
    const shortEl = $('#c-short'), nameEl = $('#c-name'), keyEl = $('#c-key');
    const rules = rulesFor(shortEl, nameEl, -1).concat([[keyEl, (v) => !v.trim() ? 'Needs a job ID' : !/^[a-z_][a-z0-9_]*$/.test(v.trim()) ? 'Lowercase letters, numbers and _ only, not starting with a number'
      : S.list.some((x) => x.key === v.trim()) ? 'A department already uses this job' : null]]);
    live(rules);
    shortEl.addEventListener('input', () => { if (!keyEl.dataset.touched) { keyEl.value = shortEl.value.toLowerCase().replace(/[^a-z0-9_]/g, ''); fieldError(keyEl, null); } });
    keyEl.addEventListener('input', () => { keyEl.dataset.touched = '1'; });
    const P = makePicker($('#c-picker'), { deptId: 0 });
    shortEl.focus();
    $('#c-cancel').onclick = () => { S.picker = null; showPane('empty'); };
    $('#c-go').onclick = (e) => busy(e.currentTarget, async () => {
      if (!validate(rules)) { toast('Check the highlighted fields', 'err'); return; }
      const data = { short: shortEl.value.trim(), name: nameEl.value.trim(), key: keyEl.value.trim().toLowerCase(),
        type: $('#c-type').value, color1: $('#c-c1').value, color2: $('#c-c2').value };
      const r = await nui('create', { data });
      if (!said(r)) return;
      const logo = P.value();
      if (logo) {
        const lr = await uploadLogo(r.data, logo);
        if (!lr || !lr.ok) toast('Department created, but the logo did not save: ' + ((lr && lr.why) || 'try again on Overview'), 'err');
        else toast(data.short + ' created with its logo', 'ok');
      } else toast(data.short + ' created', 'ok');
      S.picker = null;
      await reloadList(); select(r.data);
    });
  }


  // ---------------------------------------------------------------- health (admins)
  const LV = [
    { cls: 'ok', label: 'Active' },
    { cls: 'note', label: 'Note' },
    { cls: 'warn', label: 'Warning' },
    { cls: 'act', label: 'Step in' },
  ];
  function ago(t, nowT) {
    if (!t) return 'never';
    const s = Math.max(0, nowT - t);
    if (s < 120) return 'now';
    if (s < 3600) return Math.floor(s / 60) + ' min ago';
    if (s < 86400) return Math.floor(s / 3600) + ' h ago';
    const d = Math.floor(s / 86400);
    return d === 1 ? 'yesterday' : d + ' days ago';
  }
  function dateOf(t) { return new Date(t * 1000).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); }

  function setHealthBadge(h) {
    const b = $('#hn-badge');
    let worst = 0, n = 0;
    (h.departments || []).forEach((d) => (d.heads || []).forEach((x) => { if (x.level > 0) { n++; worst = Math.max(worst, x.level); } }));
    b.className = 'hn-badge' + (n ? ' ' + LV[worst].cls : ' hidden');
    b.textContent = n;
  }

  async function renderHealth(quiet) {
    S.cur = null; S.picker = null; renderList();
    $('.shell').style.removeProperty('--dept1'); $('.shell').style.removeProperty('--dept2');
    const box = $('#health');
    if (!quiet) { box.innerHTML = '<div class="h-loading"><div class="spin"></div>Checking departments…</div>'; showPane('health'); }
    const r = await nui('health');
    if (!r.ok) { box.innerHTML = `<div class="empty-state">${esc(r.why || 'Could not load department health')}</div>`; return; }
    const h = r.data, T = h.thresholds || {};
    S.health = h; setHealthBadge(h);
    const all = h.departments || [];
    const flagged = [];
    all.forEach((d) => (d.heads || []).forEach((x) => { if (x.level > 0) flagged.push({ d, x }); }));
    flagged.sort((a, b) => b.x.level - a.x.level);
    const tracked = `Duty tracked since ${dateOf(h.trackingSince)}`;
    const head = (x) => {
      const lv = LV[x.level] || LV[0];
      const dutyTxt = x.onDuty ? '<span class="pill on">On duty now</span>'
        : x.loa ? `<span class="pill">On leave until ${dateOf(x.loa.endsAt)}</span>`
        : x.neverTracked ? `<span class="hint">No duty since tracking began</span>` : `<span>${ago(x.lastDuty, h.now)}</span>`;
      return `<div class="h-head lv-${lv.cls}">
        <div class="h-who"><div class="h-name">${esc(x.name)}${x.owner ? ' <span class="pill">owner</span>' : ''}</div>
          <div class="hint">${esc(x.roleName || 'Head')}${x.callsign ? ' · ' + esc(x.callsign) : ''}</div></div>
        <div class="h-cell"><div class="lbl">Last on duty</div>${dutyTxt}</div>
        <div class="h-cell"><div class="lbl">Last in city</div>${x.online ? '<span class="pill">In city now</span>' : `<span>${ago(x.lastPlayed, h.now)}</span>`}</div>
        <div class="h-status"><span class="lv lv-${lv.cls}">${x.loa && !x.onDuty ? 'On leave' : lv.label}${x.level > 0 ? ` · ${x.days}d` : ''}</span></div>
      </div>`;
    };
    const cards = all.map((d) => {
      const lv = LV[d.worst || 0];
      const c = d.counts || {};
      return `<div class="h-card lv-${lv.cls}" style="--c1:${esc(d.color1)}" data-dept="${d.id}">
        <div class="h-card-head">
          <div class="h-logo" data-logo="${d.id}"><span>${esc(d.short.slice(0, 2))}</span></div>
          <div class="h-title"><div class="s">${esc(d.short)}</div><div class="hint">${esc(d.name)}</div></div>
          <span class="lv lv-${lv.cls}">${d.worst ? lv.label : 'Healthy'}</span>
          <button class="btn small ghost" data-open="${d.id}" data-probe-press>Open →</button>
        </div>
        <div class="h-stats">
          <div><b>${c.members || 0}</b><span>members</span></div>
          <div><b class="${c.onDuty ? 'live' : ''}">${c.onDuty || 0}</b><span>on duty now</span></div>
          <div><b>${c.active7 || 0}</b><span>on duty this week</span></div>
          <div><b>${c.hours7 || 0}</b><span>hours this week</span></div>
          <div><b class="${c.act ? 'bad' : c.inactive ? 'warn' : ''}">${c.inactive || 0}</b><span>inactive &gt;${T.note}d${c.act ? ` · ${c.act} red` : ''}</span></div>
          <div><b>${c.loa || 0}</b><span>on leave${c.loaPending ? ` · ${c.loaPending} waiting` : ''}</span></div>
        </div>
        <div class="h-heads">${(d.heads || []).length ? d.heads.map(head).join('') : '<div class="hint">No head yet: nobody holds the top rank.</div>'}</div>
      </div>`;
    }).join('');
    const banner = flagged.length
      ? `<div class="h-banner lv-${LV[flagged[0].x.level].cls}"><b>${flagged.length} department head${flagged.length === 1 ? '' : 's'} need${flagged.length === 1 ? 's' : ''} a look.</b>
          ${esc(flagged[0].d.short)} ${esc(flagged[0].x.name)} hasn't been on duty for ${flagged[0].x.days} days${flagged[0].x.level === 3 ? ': an admin should step in' : ''}.</div>`
      : `<div class="h-banner lv-ok"><b>All department heads are active.</b> Nobody has been off duty for more than ${T.note} days.</div>`;
    box.innerHTML = `<div class="h-top">
        <div><div class="title">Department health</div><div class="hint">${tracked} · updates live while open</div></div>
        <button class="btn small" id="h-refresh" data-probe-press>↻ Refresh</button>
      </div>
      ${banner}
      <div class="h-legend"><span class="lv lv-note">Note</span> off duty more than ${T.note} days
        <span class="lv lv-warn">Warning</span> more than ${T.warn} days <span class="lv lv-act">Step in</span> ${T.act} days or more
        <span class="h-legend-note">· applies to every member (leaders see theirs in the MDT); approved leave pauses the clock</span></div>
      <div class="h-grid">${cards || '<div class="empty-state">No departments yet.</div>'}</div>`;
    if (!quiet) showPane('health');
    box.querySelectorAll('[data-logo]').forEach((el) => {
      const d = all.find((x) => x.id === +el.dataset.logo);
      if (d) logoOf(d).then((src) => { if (src) { el.innerHTML = `<img src="${src}" alt="">`; el.style.background = 'none'; } });
    });
    box.querySelectorAll('[data-open]').forEach((b) => b.onclick = () => select(+b.dataset.open));
    $('#h-refresh').onclick = (e) => busy(e.currentTarget, () => renderHealth(true));
  }

  // ---------------------------------------------------------------- wiring
  document.addEventListener('click', (e) => {
    const act = e.target.closest && e.target.closest('[data-act]');
    if (act && act.dataset.act === 'close') nui('close');
    if (act && act.dataset.act === 'new') renderCreate();
    if (act && act.dataset.act === 'health') renderHealth();
    const tab = e.target.closest && e.target.closest('.tab');
    if (tab && S.cur) { S.tab = tab.dataset.tab; renderDept(); }
  });
  document.addEventListener('input', (e) => { if (e.target.closest && e.target.closest('.tab-body, #create')) S.dirty = true; });
  document.addEventListener('keydown', (e) => {
    if (!S.open) return;
    if (e.key === 'Escape') { e.preventDefault(); nui('close'); return; }
    if (e.key === 'Enter' && !e.shiftKey) {
      const t = e.target, tag = (t && t.tagName) || '';
      if (tag === 'TEXTAREA' || tag === 'BUTTON') return;
      const scope = (t.closest && t.closest('.card, #create')) || null;
      const btn = (scope && (scope.querySelector('[data-primary]') || (scope.closest('#create') && $('#c-go')))) || null;
      if (btn && !btn.disabled) { e.preventDefault(); btn.click(); }
    }
  });
  // A dropped file outside a drop zone must not open in the page
  ['dragover', 'drop'].forEach((ev) => window.addEventListener(ev, (e) => { if (!(e.target.closest && e.target.closest('.drop'))) e.preventDefault(); }));

  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
    if (!m || !m.action) return;
    if (m.action === 'open') {
      S.open = true; S.meta = m.data; S.list = m.data.departments || []; S.cur = null; S.picker = null;
      $('#app').classList.remove('hidden'); requestAnimationFrame(() => $('#app').classList.add('shown'));
      showPane('empty');
      renderList();
      if (S.meta.health) renderHealth();            // admins land on Health
      else if (S.list.length === 1) select(S.list[0].id);
    } else if (m.action === 'close') {
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      S.open = false; $('#app').classList.remove('shown'); setTimeout(() => { if (!S.open) $('#app').classList.add('hidden'); }, 180);
    } else if (m.action === 'changed') {
      reloadList().then(() => {
        if (!S.cur && S.health && !$('#health').classList.contains('hidden')) { renderHealth(true); return; }
        if (!S.cur) return;
        if (!S.list.find((d) => d.id === S.cur.id)) { S.cur = null; showPane('empty'); toast('That department was deleted', 'err'); return; }
        if (m.id === S.cur.id && !S.dirty) select(S.cur.id, true);
      });
    }
  });
})();
