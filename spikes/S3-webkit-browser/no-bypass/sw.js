// S3 no-bypass control service worker: network attempts from the worker itself and a page fetch
// it re-issues with respondWith(fetch()). Only the sink log counts as evidence.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(clients.claim()));
self.addEventListener('message', (event) => {
  const { T: spec } = event.data;
  const url = (t, tag, ext = '') => spec[t].replaceAll('TAG', 'sw-' + tag).replaceAll('EXT', ext);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const bounded = (p) => Promise.race([Promise.resolve(p), sleep(2000).then(() => 'timeout')]);
  event.waitUntil((async () => {
    const out = [];
    const each = async (path, fn) => {
      for (const t of Object.keys(spec)) {
        try { out.push({ path, target: t, outcome: String(await bounded(fn(t))) }); }
        catch (e) { out.push({ path, target: t, outcome: 'err:' + (e && e.message || e) }); }
      }
    };
    await each('fetch', (t) => fetch(url(t, 'fetch')).then((r) => 'status:' + r.status));
    await each('websocket', (t) => new Promise((r) => { const s = new WebSocket(url(t, 'ws').replace(/^http/, 'ws')); s.onopen = () => { r('open'); s.close(); }; s.onerror = () => r('error'); }));
    if (typeof EventSource === 'function') await each('eventsource', (t) => new Promise((r) => { const s = new EventSource(url(t, 'event')); s.onopen = () => { r('open'); s.close(); }; s.onerror = () => { r('error'); s.close(); }; }));
    event.source.postMessage(out);
  })());
});
// Set only by the persistent-store seed: a sink URL fetched on every navigation in scope.
const KEEP = new URL(self.location.href).searchParams.get('keep');
self.addEventListener('fetch', (event) => {
  if (event.request.url.includes('/swpass')) event.respondWith(fetch(event.request));
  else if (KEEP && event.request.mode === 'navigate') event.waitUntil(fetch(KEEP, { mode: 'no-cors' }).catch(() => {}));
});
