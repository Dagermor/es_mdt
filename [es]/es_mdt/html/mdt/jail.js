// es_mdt 1.5.5: the Jail tab. The inmates live in es_jail; the MDT server reads them through its exports.
(function () {
  'use strict';
  const M = window.MDT; if (!M) return;
  const { S, $, $$, esc, call, said, busy, confirmBox, pill, empty, go, VIEWS, RO } = M;
  const ST = { serving: ['Serving', 'active'], escaped: ['Escaped', 'escaped'], released: ['Released', 'served'] };
  const fmt = (s) => {
    s = Math.max(0, Math.floor(s || 0));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return h > 0 ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}:${String(x).padStart(2, '0')}`;
  };
  const when = (t) => t ? new Date(t * 1000).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';
  let timer = null;

  VIEWS.jail = async (v) => {
    clearInterval(timer);
    const tab = S.jailTab || 'inside';
    v.innerHTML = `<div class="v-head"><div><div class="v-title">Jail</div><div class="hint">Bolingbroke Penitentiary · time counts while the inmate is in the city</div></div></div>
      <div id="j-kpis" class="kpis mb"></div>
      <div class="seg big mb" id="j-tabs">${[['inside', 'Inside'], ['escaped', 'On the run'], ['released', 'Released (3 days)']].map(([k, l]) => `<button data-jt="${k}" class="${tab === k ? 'on' : ''}">${l} <span class="seg-n" data-jn="${k}"></span></button>`).join('')}</div>
      <div id="j-list"><div class="loading-row"><div class="spin"></div></div></div>`;
    $$('[data-jt]').forEach((b) => b.onclick = () => { S.jailTab = b.dataset.jt; go('jail'); });
    const r = await call('jailList');
    const box = $('#j-list'); if (!box) return;
    if (!r.ok) { box.innerHTML = empty(r.why || 'Could not load the jail', '▥'); return; }
    // 2.0.0: any jail script (jail bridge); without one the list is the MDT's own sentence record
    const hint = !r.data.installed ? '<div class="hint mb">No jail script is connected: this is the MDT’s own record of sentences.</div>' : (!r.data.live && r.data.provider ? `<div class="hint mb">${esc(r.data.provider)} has no inmate list: this is the MDT’s own record of sentences.</div>` : '');
    if (hint) box.insertAdjacentHTML('beforebegin', `<div id="j-src">${hint}</div>`);
    const rows = r.data.rows || [];
    const by = { serving: [], escaped: [], released: [] };
    rows.forEach((x) => (by[x.status] || by.released).push(x));
    $('#j-kpis').innerHTML = `<div class="kpi"><b>${by.serving.length}</b><span>inside</span></div>
      <div class="kpi"><b>${by.serving.filter((x) => x.online).length}</b><span>serving now (in the city)</span></div>
      <div class="kpi"><b class="${by.escaped.length ? 'txt-warn' : ''}">${by.escaped.length}</b><span>on the run</span></div>
      <div class="kpi"><b>${by.released.length}</b><span>released, last 3 days</span></div>`;
    $$('[data-jn]').forEach((el) => { const n = (by[{ inside: 'serving', escaped: 'escaped', released: 'released' }[el.dataset.jn]] || []).length; el.textContent = n || ''; el.classList.toggle('hot', el.dataset.jn === 'escaped' && n > 0); });
    const list = by[{ inside: 'serving', escaped: 'escaped', released: 'released' }[tab]] || [];
    const canRel = r.data.canRelease && !RO();
    box.innerHTML = list.length ? list.map((x) => {
      const st = ST[x.status] || [x.status, ''];
      const pct = x.total ? Math.max(0, Math.min(100, (1 - x.remaining / x.total) * 100)) : 100;
      return `<div class="wcard jcard ${st[1]}" data-jc="${x.charId}">
        <div class="w-status ${st[1]}">${esc(st[0])}</div>
        <div class="w-main">
          <div class="w-top"><a class="lnk person-lnk" data-person="${x.charId}" title="Open their profile"><b>${esc(x.name)}</b> ›</a>
            ${x.status === 'serving' ? pill(x.online ? 'In the city' : 'Offline · clock paused', x.online ? 'on' : 'off') : ''}
            ${x.hasItems ? '<span class="pill warn" title="Their belongings are boxed up at the prison">Belongings held</span>' : ''}
            <span class="hint">${x.months} month${x.months === 1 ? '' : 's'}${x.reportId ? ` · <a class="lnk" data-report="${x.reportId}">report #${x.reportId}</a>` : ''}</span></div>
          ${x.status !== 'released' ? `<div class="jbar"><div class="jfill" style="width:${pct.toFixed(1)}%"></div></div>` : ''}
          <div class="hint">${x.status === 'serving' ? `<b class="jleft" data-left="${x.remaining}" data-live="${x.online ? 1 : 0}">${fmt(x.remaining)}</b> left of ${fmt(x.total)}` : x.status === 'escaped' ? `<b class="txt-warn">${fmt(x.remaining)} left</b> · escaped ${when(x.escapedAt)}` : `out ${when(x.releasedAt)}`}
            ${x.jobs ? ` · ${x.jobs} prison job${x.jobs === 1 ? '' : 's'} (−${fmt(x.cut)})` : ''} · jailed ${when(x.jailedAt)}${x.byName ? ' by ' + esc(x.byName) : ''}${x.reason && !/^Report #/.test(x.reason) ? ' · ' + esc(x.reason) : ''}</div>
        </div>
        <div class="w-act">${canRel && x.status !== 'released' ? `<button class="btn small" data-jr="${x.charId}">Release</button>` : ''}</div></div>`;
    }).join('') : empty(tab === 'escaped' ? 'Nobody is on the run' : tab === 'released' ? 'Nobody released lately' : 'Nobody is inside', '▥');
    $$('[data-jr]', box).forEach((b) => b.onclick = () => busy(b, async () => {
      const x = rows.find((y) => y.charId === +b.dataset.jr);
      if (!await confirmBox('Release inmate', `Release ${esc(x ? x.name : 'them')} now? They walk out at the gate with their belongings.`, 'Release', true)) return;
      if (said(await call('jailRelease', { charId: +b.dataset.jr }), 'Released')) go('jail');
    }));
    const t0 = Date.now();
    timer = setInterval(() => {
      if (!document.body.contains(box)) { clearInterval(timer); return; }
      $$('.jleft[data-live="1"]', box).forEach((el) => { el.textContent = fmt(+el.dataset.left - (Date.now() - t0) / 1000); });
    }, 1000);
  };
})();
