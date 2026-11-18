// es_mdt 2.0.2: the "Aa" display-size button in each page's header. The size popover itself lives in the shell
// (html/index.html), above the pages, so it does not move or resize while you drag its slider.
(function () {
  'use strict';
  if (window.parent === window) return;
  const SPOT = ['.top-right', '.side-head'];   // MDT and DOJ header, Departments side header
  const ICON = '<svg viewBox="0 0 24 24" width="17" height="17" aria-hidden="true"><path fill="currentColor" d="M8.6 5h2.1l5 13h-2.2l-1.2-3.3H6.9L5.7 18H3.5L8.6 5Zm-1 7.8h4.1L9.6 7.3l-2 5.5ZM17.6 9h1.6l3.3 9h-1.7l-.8-2.2h-3.3l-.8 2.2h-1.6l3.3-9Zm-.4 5.5h2.4l-1.2-3.4-1.2 3.4Z"/></svg>';
  function add() {
    let host = null;
    for (const s of SPOT) { host = document.querySelector(s); if (host) break; }
    if (!host || host.querySelector('.es-scale-btn')) return;
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'icon-btn es-scale-btn'; b.title = 'Display size'; b.setAttribute('aria-label', 'Display size');
    b.innerHTML = ICON;
    b.style.display = 'inline-flex'; b.style.alignItems = 'center'; b.style.justifyContent = 'center';
    b.addEventListener('click', (e) => {
      e.preventDefault(); e.stopPropagation();
      const r = b.getBoundingClientRect();
      window.parent.postMessage({ __esScale: 'open', rect: { left: r.left, top: r.top, right: r.right, bottom: r.bottom } }, '*');
    });
    const close = host.querySelector('[data-act="close"]');
    host.insertBefore(b, close || null);
    if (host.matches('.side-head')) {   // Departments: the button sits with the close button on the right
      const wrap = document.createElement('div');
      wrap.style.display = 'flex'; wrap.style.alignItems = 'center'; wrap.style.gap = '4px';
      host.insertBefore(wrap, b); wrap.appendChild(b); if (close) wrap.appendChild(close);
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add); else add();
})();
