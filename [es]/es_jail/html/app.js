// es_jail overlay: the cuffs pill, the shake meter, the jail timer. Draw only; the server decides.
(function () {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const fmt = (s) => {
    s = Math.max(0, Math.floor(s || 0));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(x).padStart(2, '0')}` : `${m}:${String(x).padStart(2, '0')}`;
  };
  const J = { on: false, remaining: 0, total: 0, at: 0 };
  let resultTimer = null;

  function cuffs(d) {
    $('cuffs').classList.toggle('hidden', !d.on);
    if (!d.on) return;
    const what = (d.kind === 'ziptie' ? 'Zip-tied' : 'Cuffed') + (d.mode === 'hard' ? ' · hands behind' : '');
    $('cf-what').textContent = what;
    $('cf-key').textContent = d.key || 'X';
    const left = Math.max(0, (d.max || 3) - (d.escapes || 0));
    $('cf-left').textContent = left > 0 ? `(${left} left)` : '';
    $('cf-break').classList.toggle('hidden', !d.canBreak);
    $('cf-stuck').classList.toggle('hidden', !!d.canBreak || !!d.canPick);
    $('cf-pick').classList.toggle('hidden', !d.canPick);
  }

  function shake(d) {
    const el = $('shake');
    if (d.on) {
      clearTimeout(resultTimer);
      $('sh-result').classList.add('hidden');
      el.classList.remove('hidden');
      if (d.attempt) $('sh-try').textContent = `Escape ${d.attempt} of ${d.max || 3}`;
      if (d.ready !== undefined) {
        el.classList.toggle('ready', !!d.ready);
        if (d.key) $('sh-key').textContent = d.key;
        if (d.kind) $('sh-what').textContent = d.kind === 'ziptie' ? 'zip ties' : 'cuffs';
      }
      if (d.pct !== undefined) {
        $('sh-fill').style.width = `${Math.max(0, Math.min(100, d.pct))}%`;
        el.classList.toggle('hot', d.pct > 80);
      } else { $('sh-fill').style.width = '0%'; }
      if (d.left !== undefined) $('sh-time').textContent = `${d.left.toFixed(1)}s`;
      else if (d.seconds) $('sh-time').textContent = `${Number(d.seconds).toFixed(1)}s`;
      return;
    }
    if (el.classList.contains('hidden')) return;
    if (d.won === undefined) { el.classList.add('hidden'); return; }
    const r = $('sh-result');
    r.textContent = d.won ? 'You slipped free!' : 'Not enough. The cuffs locked.';
    r.className = `sh-result ${d.won ? 'won' : 'lost'}`;
    resultTimer = setTimeout(() => el.classList.add('hidden'), 1400);
  }

  function jail(d) {
    J.on = !!d.on;
    $('jail').classList.toggle('hidden', !J.on);
    if (!J.on) return;
    J.remaining = d.remaining || 0; J.total = Math.max(1, d.total || 1); J.at = Date.now();
    const sub = $('jl-sub');
    if (d.job) sub.innerHTML = `Job: <b>${esc(d.job)}</b> · go to the marker and ${esc((d.verb || '').toLowerCase())}`;
    else sub.textContent = 'Work at the job board in the yard to cut your time';
    if (d.cut > 0) sub.innerHTML += `<br>${d.jobs} task${d.jobs === 1 ? '' : 's'} done · ${fmt(d.cut)} off`;
    draw();
  }
  function esc(s) { return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
  function draw() {
    if (!J.on) return;
    const left = Math.max(0, J.remaining - (Date.now() - J.at) / 1000);
    $('jl-time').textContent = fmt(left);
    $('jl-fill').style.width = `${Math.max(0, Math.min(100, (1 - left / J.total) * 100))}%`;
  }
  setInterval(draw, 1000);

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.t === 'cuffs') cuffs(d);
    else if (d.t === 'shake') shake(d);
    else if (d.t === 'jail') jail(d);
    else if (d.t === 'test') $('testtag').classList.toggle('hidden', !d.on);
    else if (d.t === 'debug') {
      $('dbg').classList.toggle('hidden', !d.on);
      if (d.on && d.inside !== undefined) {
        const b = $('dbg-in'); b.textContent = d.inside ? 'Inside the fence' : 'OUTSIDE the fence'; b.className = d.inside ? 'in' : 'out';
        $('dbg-xyz').textContent = `${(+d.x).toFixed(1)}, ${(+d.y).toFixed(1)}, ${(+d.z).toFixed(1)}`;
      }
    }
  });
  window.ESJAIL = { cuffs, shake, jail };
})();
