// es_mdt 1.8.0: the civilian firearm permit application (front desk prompt or /permit). Reason + a required photo of
// yourself (upload, drop, link or camera roll) with a live preview; the picture is resized here before it is sent.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { post, esc } = M;
  const MAXPX = 560;
  let root = null, st = null, photo = null;   // photo = { mode, image?, url?, photoId? }

  function shrink(src) {
    return new Promise((res) => {
      const img = new Image();
      img.onload = () => {
        try {
          const k = Math.min(1, MAXPX / Math.max(img.width, img.height));
          const cv = document.createElement('canvas'); cv.width = Math.round(img.width * k); cv.height = Math.round(img.height * k);
          cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
          res(cv.toDataURL('image/jpeg', 0.85));
        } catch (e) { res(null); }
      };
      img.onerror = () => res(null);
      img.crossOrigin = 'anonymous';
      img.src = src;
    });
  }

  const STATUS = { pending: ['Waiting for review', 'warn'], approved: ['Approved', 'on'], denied: ['Denied', 'bad'], processing: ['Being decided', 'warn'], cancelled: ['Cancelled', 'off'] };
  function close() { post('permitClose'); }
  function hide() { if (root) { root.classList.remove('shown'); const r = root; setTimeout(() => { r.remove(); }, 160); root = null; } }

  function open(data) {
    hide();
    st = data.status || {}; photo = null;
    const lic = st.license, apps = st.apps || [], last = apps[0];
    const blocked = (lic && (lic.status === 'active' || lic.status === 'suspended')) || (last && last.status === 'pending');
    root = document.createElement('div');
    root.className = 'pa-wrap';
    root.innerHTML = `<div class="pa-card">
      <div class="pa-head"><div class="pa-ico">✪</div><div><div class="pa-title">${esc(st.label || 'Firearm permit')}</div><div class="pa-sub">San Andreas · application${st.fee ? ' · ' + M.money(st.fee) + ' fee when approved' : ''}</div></div><button class="pa-x" id="pa-x" title="Close (Esc)">✕</button></div>
      <div class="pa-status ${lic && lic.status === 'active' ? 'on' : last ? (STATUS[last.status] || ['', ''])[1] : ''}">${esc(data.text || '')}</div>
      ${apps.length ? `<details class="pa-hist"><summary>Your applications (${apps.length})</summary>${apps.map((a) => `<div class="pa-hrow"><span class="pill ${(STATUS[a.status] || ['', ''])[1]}">${esc((STATUS[a.status] || [a.status])[0])}</span><span>#${a.id} · ${M.date(a.createdAt)}${a.decisionNote ? ' · ' + esc(a.decisionNote) : ''}</span></div>`).join('')}</details>` : ''}
      ${blocked ? '' : `
      <div class="pa-grid">
        <div>
          <label class="pa-l">Why do you want a permit?</label>
          <textarea id="pa-reason" maxlength="500" rows="5" placeholder="e.g. Self defence: I run a store in Strawberry and close late."></textarea>
          <div class="pa-hint"><span id="pa-n">0</span>/500 · at least 10 letters</div>
          <label class="pa-l">Your photo <b class="pa-req">required</b></label>
          <div class="pa-tabs" id="pa-tabs"><button data-pt="upload" class="on">⬆ Upload</button><button data-pt="link">🔗 Link</button>${data.roll === false ? '' : '<button data-pt="roll">🖼 Camera roll</button>'}</div>
          <div id="pa-body"></div>
        </div>
        <div class="pa-prev" id="pa-prev"><span>Your photo shows here</span></div>
      </div>
      <div class="pa-note">A background check (warrants, felony record, recent arrests) runs when you apply. A sergeant or above decides; you are told the result, and your photo goes on your record.</div>`}
      <div class="pa-foot"><button class="pa-btn ghost" id="pa-cancel">${blocked ? 'Close' : 'Cancel'}</button>${blocked ? '' : '<button class="pa-btn accent" id="pa-go" disabled>Apply</button>'}</div>
    </div>`;
    document.body.appendChild(root);
    requestAnimationFrame(() => root && root.classList.add('shown'));
    const $ = (s) => root.querySelector(s);
    $('#pa-x').onclick = close; $('#pa-cancel').onclick = close;
    if (blocked) return;
    const prev = $('#pa-prev'), body = $('#pa-body'), go = $('#pa-go'), reason = $('#pa-reason');
    const ready = () => { go.disabled = !(photo && reason.value.trim().length >= 10); };
    reason.oninput = () => { $('#pa-n').textContent = reason.value.length; ready(); };
    const show = (src, note) => { prev.innerHTML = `<img src="${src}" alt=""><span>${esc(note || 'Preview')}</span>`; };
    const tab = (t) => {
      root.querySelectorAll('[data-pt]').forEach((b) => b.classList.toggle('on', b.dataset.pt === t));
      photo = null; ready(); prev.innerHTML = '<span>Your photo shows here</span>';
      if (t === 'upload') {
        body.innerHTML = '<label class="pa-drop" id="pa-drop"><input type="file" id="pa-file" accept="image/png,image/jpeg,image/webp"><b>Choose a picture</b><span>or drop one here · it is resized for you</span></label>';
        const take = (file) => {
          if (!file || !/^image\//.test(file.type)) { prev.innerHTML = '<span class="bad">That is not a picture</span>'; return; }
          const rd = new FileReader();
          rd.onload = async () => { const img = await shrink(rd.result); if (!img) { prev.innerHTML = '<span class="bad">That picture could not be read</span>'; return; } show(img, Math.round(img.length * 0.75 / 1024) + ' KB · ready'); photo = { mode: 'upload', image: img }; ready(); };
          rd.readAsDataURL(file);
        };
        $('#pa-file').onchange = (e) => take(e.target.files[0]);
        const dz = $('#pa-drop');
        dz.ondragover = (e) => { e.preventDefault(); dz.classList.add('over'); };
        dz.ondragleave = () => dz.classList.remove('over');
        dz.ondrop = (e) => { e.preventDefault(); dz.classList.remove('over'); take(e.dataTransfer.files[0]); };
      } else if (t === 'link') {
        body.innerHTML = '<input id="pa-url" class="pa-in" maxlength="500" placeholder="https://…/photo.jpg"><div class="pa-hint">Paste a picture link: the preview loads as you paste.</div>';
        let tm = null;
        $('#pa-url').oninput = (e) => { clearTimeout(tm); photo = null; ready(); tm = setTimeout(async () => {
          const url = e.target.value.trim();
          if (!/^https?:\/\/\S+$/i.test(url)) { prev.innerHTML = `<span>${url ? 'A link starts with https://' : 'Your photo shows here'}</span>`; return; }
          prev.innerHTML = '<div class="spin"></div>';
          const img = await shrink(url);
          if (img) { show(img, 'Preview · ready'); photo = { mode: 'upload', image: img }; ready(); return; }
          const probe = new Image();
          probe.onload = () => { prev.innerHTML = ''; prev.appendChild(probe); prev.insertAdjacentHTML('beforeend', '<span>Preview · checked when you apply</span>'); photo = { mode: 'link', url }; ready(); };
          probe.onerror = () => { prev.innerHTML = '<span class="bad">That link did not load as a picture</span>'; };
          probe.src = url;
        }, 300); };
      } else {
        body.innerHTML = '<div class="pa-roll" id="pa-roll"><div class="spin"></div></div>';
        (async () => {
          const r = await post('permitRoll', {});
          const box = $('#pa-roll'); if (!box) return;
          const list = (r && r.ok && Array.isArray(r.data)) ? r.data : [];
          if (!list.length) { box.innerHTML = '<div class="pa-hint">Your camera roll is empty. Take a selfie with the camera item first.</div>'; return; }
          box.innerHTML = list.slice(0, 24).map((p) => `<button class="pa-thumb" data-rid="${p.id}"><div class="spin"></div></button>`).join('');
          const imgs = {};
          box.querySelectorAll('[data-rid]').forEach((b) => b.onclick = () => {
            const id = +b.dataset.rid; if (!imgs[id]) return;
            box.querySelectorAll('[data-rid]').forEach((x) => x.classList.toggle('on', x === b));
            show(imgs[id], 'From your camera roll'); photo = { mode: 'roll', photoId: id }; ready();
          });
          for (const b of box.querySelectorAll('[data-rid]')) {
            const x = await post('permitRoll', { id: +b.dataset.rid });
            if (!b.isConnected) return;
            if (x && x.ok && x.data) { imgs[x.data.id] = x.data.image; b.innerHTML = `<img src="${x.data.image}" alt="">`; } else b.innerHTML = '—';
          }
        })();
      }
    };
    root.querySelectorAll('[data-pt]').forEach((b) => b.onclick = () => tab(b.dataset.pt));
    tab('upload');
    go.onclick = async () => {
      if (go.disabled) return;
      go.disabled = true; go.textContent = 'Sending…';
      const r = await post('permitSubmit', Object.assign({ reason: reason.value.trim(), desk: data.desk || 0 }, photo));
      if (r && r.ok) {
        root.querySelector('.pa-card').innerHTML = `<div class="pa-done"><div class="pa-big">✓</div><div class="pa-title">Application #${r.data.id} filed</div><p>A sergeant or above reviews it. You get a message when it is decided${st.fee ? `; the ${M.money(st.fee)} fee is taken from your bank only if it is approved` : ''}.</p><button class="pa-btn accent" id="pa-ok">Done</button></div>`;
        root.querySelector('#pa-ok').onclick = close;
      } else {
        go.textContent = 'Apply'; ready();
        const n = root.querySelector('.pa-err') || Object.assign(document.createElement('div'), { className: 'pa-err' });
        n.textContent = (r && r.why) || 'That did not work';
        root.querySelector('.pa-foot').before(n);
      }
    };
    reason.focus();
  }

  window.addEventListener('message', (e) => {
    const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
    if (!m || !m.action) return;
    if (m.action === 'permitApp') open(m.data || {});
    else if (m.action === 'permitAppClose') hide();
  });
  document.addEventListener('keydown', (e) => { if (root && e.key === 'Escape') { e.preventDefault(); close(); } });
})();
