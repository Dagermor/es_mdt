// es_doj picture picker: choose a file, drop or paste one, give a link, or pick from the camera roll (tablet).
// Every way shows a live preview straight away. Files are resized in the page (JPEG) to fit the server's limit.
(function () {
  'use strict';
  const { $, $$, esc, call, S, toast } = window.DOJ;

  const kb = (n) => n > 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB';
  // a data URL's size on the wire (what the server checks)
  const sizeOf = (d) => (d || '').length;

  // image element -> resized JPEG data URL under max bytes (or null)
  function shrink(img, max) {
    let w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
    if (!w || !h) return null;
    let side = 1600;
    for (let pass = 0; pass < 8; pass++) {
      const k = Math.min(1, side / Math.max(w, h));
      const cv = document.createElement('canvas');
      cv.width = Math.max(1, Math.round(w * k)); cv.height = Math.max(1, Math.round(h * k));
      const g = cv.getContext('2d');
      g.fillStyle = '#000'; g.fillRect(0, 0, cv.width, cv.height);
      g.drawImage(img, 0, 0, cv.width, cv.height);
      for (const q of [0.86, 0.78, 0.68, 0.58]) {
        let out;
        try { out = cv.toDataURL('image/jpeg', q); } catch (e) { return null; }   // a tainted canvas (a link that refuses)
        if (sizeOf(out) <= max * 0.98) return { data: out, w: cv.width, h: cv.height };
      }
      side = Math.round(side * 0.75);
    }
    return null;
  }
  function loadImg(src, cors) {
    return new Promise((res, rej) => {
      const i = new Image();
      if (cors) i.crossOrigin = 'anonymous';
      i.onload = () => res(i); i.onerror = () => rej(new Error('not a picture'));
      i.src = src;
    });
  }
  function readFile(file) {
    return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = () => rej(r.error); r.readAsDataURL(file); });
  }

  /**
   * picture(host, opts) -> { get(), clear(), has() }
   * opts.roll: show the camera roll tab (tablet), opts.label: what the drop zone says, opts.onChange(payload|null)
   * get() -> { image } | { imageUrl } | { photoId } | null  (spread it into the call)
   */
  function picture(host, opts) {
    opts = opts || {};
    const max = (S.lists && S.lists.maxImage) || 420000;
    const tabs = [['file', 'Upload'], ['link', 'Link']];
    if (opts.roll) tabs.push(['roll', 'Camera roll']);
    host.innerHTML = `<div class="up"><div class="up-tabs">${tabs.map(([k, l], i) => `<button type="button" data-t="${k}" class="${i === 0 ? 'on' : ''}">${l}</button>`).join('')}</div>
      <div class="up-pane" data-pane></div></div>`;
    const pane = $('[data-pane]', host);
    let value = null, tab = 'file', seq = 0;
    const set = (v) => { value = v; if (opts.onChange) opts.onChange(v); };

    function preview(src, meta, onRemove) {
      return `<div class="up-prev"><img src="${src}" alt=""><button type="button" class="btn small x" data-rm>✕ Remove</button>${meta ? `<span class="meta">${esc(meta)}</span>` : ''}</div>`;
    }
    function wireRemove(again) { const b = $('[data-rm]', pane); if (b) b.onclick = () => { set(null); again(); }; }

    async function takeFile(file) {
      if (!file) return;
      if (!/^image\/(png|jpe?g|webp|gif)$/i.test(file.type)) { toast('Pick a PNG, JPG, WebP or GIF picture', 'err'); return; }
      const my = ++seq;
      pane.innerHTML = '<div class="up-prev"><div class="spin"></div></div>';
      try {
        const raw = await readFile(file);
        const img = await loadImg(raw);
        const out = shrink(img, max);
        if (my !== seq) return;
        if (!out) throw new Error('too big');
        set({ image: out.data });
        pane.innerHTML = preview(out.data, `${out.w}×${out.h} · ${kb(sizeOf(out.data))}${file.name ? ' · ' + file.name : ''}`);
        wireRemove(drawFile);
      } catch (e) {
        if (my !== seq) return;
        toast('That picture could not be read', 'err'); drawFile();
      }
    }
    function drawFile() {
      if (value && value.image) { pane.innerHTML = preview(value.image, kb(sizeOf(value.image))); wireRemove(drawFile); return; }
      pane.innerHTML = `<label class="drop" data-drop><input type="file" accept="image/png,image/jpeg,image/webp,image/gif" hidden>
        <div style="font-size:26px">🖼</div><div><b>Choose a picture</b> or drop it here</div><div class="hint">You can also paste one (Ctrl+V) · it is resized for you</div></label>`;
      const drop = $('[data-drop]', pane), inp = $('input', pane);
      inp.onchange = () => takeFile(inp.files[0]);
      drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.classList.add('over'); });
      drop.addEventListener('dragleave', () => drop.classList.remove('over'));
      drop.addEventListener('drop', (e) => { e.preventDefault(); drop.classList.remove('over'); takeFile(e.dataTransfer.files[0]); });
    }
    function drawLink() {
      const cur = value && value.imageUrl ? value.imageUrl : (value && value.linkUrl) || '';
      pane.innerHTML = `<div class="field"><label>Picture link <span class="hint">· https, png / jpg / webp / gif</span></label><input type="url" data-url placeholder="https://…/picture.png" maxlength="500" value="${esc(cur)}"></div><div data-lp></div>
        <div class="hint">The preview loads as you type. Tip: right-click a picture online → Copy image address.</div>`;
      const inp = $('[data-url]', pane), lp = $('[data-lp]', pane);
      let t = null;
      const run = () => {
        const url = inp.value.trim();
        const my = ++seq;
        if (!url) { lp.innerHTML = ''; set(null); return; }
        if (!/^https?:\/\/\S+$/i.test(url)) { lp.innerHTML = '<div class="up-prev err">That is not a web link (it starts with https://)</div>'; set(null); return; }
        lp.innerHTML = '<div class="up-prev"><div class="spin"></div></div>';
        loadImg(url, true).then((img) => {
          if (my !== seq) return;
          const out = shrink(img, max);   // the page could read it: send the picture itself
          if (out) { set({ image: out.data, linkUrl: url }); lp.innerHTML = preview(out.data, `${out.w}×${out.h} · ${kb(sizeOf(out.data))}`); }
          else { set({ imageUrl: url }); lp.innerHTML = preview(url, 'The court fetches it when you save'); }
          wireRemove(() => { inp.value = ''; lp.innerHTML = ''; });
        }).catch(() => {
          // it may still be a picture the page may not read with CORS: try a plain load for the preview
          loadImg(url, false).then(() => {
            if (my !== seq) return;
            set({ imageUrl: url }); lp.innerHTML = preview(url, 'The court fetches it when you save');
            wireRemove(() => { inp.value = ''; lp.innerHTML = ''; });
          }).catch(() => { if (my !== seq) return; set(null); lp.innerHTML = '<div class="up-prev err">No picture at that link. Use the picture\'s own address (it usually ends in .png or .jpg).</div>'; });
        });
      };
      inp.addEventListener('input', () => { clearTimeout(t); t = setTimeout(run, 350); });
      if (cur) run();
    }
    async function drawRoll() {
      pane.innerHTML = '<div class="loading-row"><div class="spin"></div></div>';
      const r = await call('roll');
      if (tab !== 'roll') return;
      const list = (r.ok && r.data) || [];
      if (!list.length) { pane.innerHTML = '<div class="empty-state"><div class="es-ico">📷</div>Your camera roll is empty. Take photos with the camera item, then pick one here.</div>'; return; }
      pane.innerHTML = `<div class="roll">${list.map((p) => `<div class="ph ${value && value.photoId === p.id ? 'on' : ''}" data-ph="${p.id}" title="${esc(p.street || '')}">${esc(p.street || '')}</div>`).join('')}</div><div data-rp class="mt"></div>`;
      $$('[data-ph]', pane).forEach(async (el) => {
        const src = await window.DOJ.imageOf('rollImage', { id: +el.dataset.ph });
        if (src) el.style.backgroundImage = `url("${src}")`;
        el.onclick = () => {
          $$('[data-ph]', pane).forEach((x) => x.classList.toggle('on', x === el));
          set({ photoId: +el.dataset.ph });
          const rp = $('[data-rp]', pane);
          rp.innerHTML = src ? preview(src, el.title || 'From your camera roll') : '';
          const b = $('[data-rm]', rp); if (b) b.onclick = () => { set(null); drawRoll(); };
        };
      });
    }
    const draw = () => (tab === 'file' ? drawFile() : tab === 'link' ? drawLink() : drawRoll());
    $$('[data-t]', host).forEach((b) => b.onclick = () => { tab = b.dataset.t; $$('[data-t]', host).forEach((x) => x.classList.toggle('on', x === b)); draw(); });
    // paste anywhere while this picker is on screen
    const onPaste = (e) => {
      if (!document.body.contains(host)) { document.removeEventListener('paste', onPaste); return; }
      const item = Array.from((e.clipboardData && e.clipboardData.items) || []).find((i) => i.type && i.type.startsWith('image/'));
      if (item) { e.preventDefault(); tab = 'file'; $$('[data-t]', host).forEach((x) => x.classList.toggle('on', x.dataset.t === 'file')); takeFile(item.getAsFile()); }
    };
    document.addEventListener('paste', onPaste);
    draw();
    return {
      get: () => { if (!value) return null; const v = Object.assign({}, value); delete v.linkUrl; return v; },
      has: () => !!value,
      clear: () => { set(null); draw(); },
    };
  }

  window.DOJ.picture = picture;
})();
