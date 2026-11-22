// S3 no-bypass control: attempts every page network path against the independent loopback sinks
// and gateway-only hostnames. Page-side outcomes are informational only; only the sink log and
// the gateway's decisions count as evidence.
//
// Parameters come from window.__probeParams (inlined pages) or ?p=<base64 JSON> (served pages):
//   {run, scenario, ports: {http4, http6, preconnect4, turn4, stun-*, quic4}, noh, only}
// `only: 'none'` runs no path (feature report only).
// `noh` omits gateway-only hostname targets when no proxy is set, so a reserved `.invalid`
// name never reaches the system resolver. `only` runs one path (isolated controls).
(() => {
  const P = window.__probeParams || JSON.parse(atob(new URLSearchParams(location.search).get('p')));
  const ports = P.ports;
  const base = `/${P.run}/${P.scenario}`;
  const results = [];
  const note = (path, target, outcome, limit = 200) =>
    results.push({ path, target, outcome: String(outcome).slice(0, limit) });
  const T = {
    d4: (tag, ext = '') => `http://127.0.0.1:${ports.http4}${base}/${tag}-d4${ext}`,
    d6: (tag, ext = '') => `http://[::1]:${ports.http6}${base}/${tag}-d6${ext}`,
    lh: (tag, ext = '') => `http://localhost:${ports.http4}${base}/${tag}-lh${ext}`,
    sub: (tag, ext = '') => `http://sink.localhost:${ports.http4}${base}/${tag}-sub${ext}`,
    num: (tag, ext = '') => `http://2130706433:${ports.http4}${base}/${tag}-num${ext}`,
    h: (tag, ext = '') => `http://${tag}-h.${P.scenario}.${P.run}.probe.memoshi.invalid${base}/${tag}-h${ext}`,
  };
  const BASIC = ['d4', 'd6', 'lh', 'h'];
  // Alternate loopback spellings (all reach the http4 sink when nothing blocks them) and the
  // host's own private/ULA addresses that sinks.py bound as `own:<address>` sinks.
  const LAN_HOSTS = {
    short: `127.1:${ports.http4}`, hex: `0x7f000001:${ports.http4}`, octal: `0177.0.0.1:${ports.http4}`,
    any: `0.0.0.0:${ports.http4}`, mapped: `[::ffff:127.0.0.1]:${ports.http4}`,
  };
  for (const key of Object.keys(ports).filter((k) => k.startsWith('own:'))) {
    const address = key.slice(4);
    LAN_HOSTS['own' + address.replace(/[^0-9a-f]/gi, '')] = (address.includes(':') ? `[${address}]` : address) + ':' + ports[key];
  }
  // Names run-control.py resolves to owned sinks: random local-only mDNS `.local` records
  // (`mdns0`, `mdns1`, ...). No LAN hostname is ever loaded.
  Object.keys(ports).filter((k) => k.startsWith('mdns:')).sort().forEach((key, index) => {
    LAN_HOSTS['mdns' + index] = key.slice(5) + ':' + ports[key];
  });
  const LAN = Object.keys(LAN_HOSTS);
  for (const key of LAN) T[key] = (tag, ext = '') => `http://${LAN_HOSTS[key]}${base}/${tag}-${key}${ext}`;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const bounded = (p, ms = 2000) => Promise.race([Promise.resolve(p), sleep(ms).then(() => 'timeout')]);
  const el = (tag, attrs, parent = document.body) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
    parent.appendChild(e);
    return e;
  };
  const wants = (path) => !P.only || P.only.split(',').includes(path);
  async function each(path, targets, fn) {
    if (!wants(path)) return;
    for (const t of targets) {
      if (t === 'h' && P.noh) continue;
      try { note(path, t, await bounded(fn(T[t], t))); } catch (e) { note(path, t, 'err:' + (e && e.message || e)); }
    }
  }
  const load = (make) => new Promise((r) => { const e = make(); e.onload = () => r('load'); e.onerror = () => r('error'); });

  // Workers are blob workers so the inlined (gateway) page never requests its own origin.
  function workerMain() {
    self.onmessage = async (event) => {
      const { T: spec, ports, kind } = event.data;
      const url = (t, tag, ext = '') => spec[t].replaceAll('TAG', kind + '-' + tag).replaceAll('EXT', ext);
      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
      const bounded = (p) => Promise.race([Promise.resolve(p), sleep(2000).then(() => 'timeout')]);
      const out = [];
      const each = async (path, fn) => {
        for (const t of Object.keys(spec)) {
          try { out.push({ path, target: t, outcome: String(await bounded(fn(t))) }); }
          catch (e) { out.push({ path, target: t, outcome: 'err:' + (e && e.message || e) }); }
        }
      };
      await each('fetch', (t) => fetch(url(t, 'fetch')).then((r) => 'status:' + r.status));
      if (typeof XMLHttpRequest === 'function') await each('xhr', (t) => new Promise((r) => { const x = new XMLHttpRequest(); x.open('GET', url(t, 'xhr')); x.onload = () => r('status:' + x.status); x.onerror = () => r('error'); x.send(); }));
      await each('websocket', (t) => new Promise((r) => { const s = new WebSocket(url(t, 'ws').replace(/^http/, 'ws')); s.onopen = () => { r('open'); s.close(); }; s.onerror = () => r('error'); }));
      if (typeof EventSource === 'function') await each('eventsource', (t) => new Promise((r) => { const s = new EventSource(url(t, 'event')); s.onopen = () => { r('open'); s.close(); }; s.onerror = () => { r('error'); s.close(); }; }));
      await each('importScripts', (t) => { importScripts(url(t, 'import', '.js')); return 'ok'; });
      out.push({ path: 'rtc-in-worker', target: 'self', outcome: typeof RTCPeerConnection });
      if (typeof RTCPeerConnection === 'function') {
        try {
          const pc = new RTCPeerConnection({ iceServers: [{ urls: `stun:127.0.0.1:${ports['stun-worker']}` }] });
          pc.createDataChannel('x'); await pc.setLocalDescription(await pc.createOffer()); await sleep(2000); pc.close();
        } catch (e) { out.push({ path: 'rtc-in-worker', target: 'stun-worker', outcome: 'err:' + e }); }
      }
      self.postMessage(out);
    };
  }
  const workerSpec = (kind) => {
    const spec = {};
    for (const t of BASIC) {
      if (t === 'h' && P.noh) continue;
      spec[t] = T[t]('TAG', 'EXT');
    }
    return { T: spec, ports, kind };
  };
  const workerURL = URL.createObjectURL(new Blob(['(' + workerMain.toString() + ')()'], { type: 'text/javascript' }));

  async function rtc(PC, iceServers) {
    if (typeof PC !== 'function') return 'absent';
    const pc = new PC({ iceServers });
    pc.createDataChannel('x');
    const candidates = [];
    pc.onicecandidate = (e) => e.candidate && candidates.push(e.candidate.type);
    await pc.setLocalDescription(await pc.createOffer());
    await sleep(2500);
    pc.close();
    return 'candidates:' + candidates.length;
  }

  function features() {
    const canvas = document.createElement('canvas');
    let webgl = 'absent';
    try { webgl = canvas.getContext('webgl') ? 'available' : 'null'; } catch (e) { webgl = 'throw'; }
    return {
      RTCPeerConnection: typeof window.RTCPeerConnection, WebTransport: typeof window.WebTransport,
      serviceWorker: typeof navigator.serviceWorker, indexedDB: typeof window.indexedDB,
      caches: typeof window.caches, webgl, webgpu: typeof navigator.gpu,
      AudioContext: typeof window.AudioContext, FileReader: typeof window.FileReader,
      SharedWorker: typeof window.SharedWorker, WebAssembly: typeof window.WebAssembly,
      Notification: typeof window.Notification, secureContext: window.isSecureContext,
    };
  }

  async function run() {
    // The feature report is JSON for the analyzer; the 200-character cap would cut it off.
    note('features', 'self', JSON.stringify(features()), Infinity);
    // Trusted-input control: the driver clicks these anchors with synthesized native NSEvents
    // after the report; the page records whether each click arrived as trusted.
    if (P.only === 'a-target-blank-native') {
      window.__nativeClicks = [];
      for (const t of ['d4', 'h']) {
        if (t === 'h' && P.noh) continue;
        const a = el('a', { href: T[t]('nblank', '.html'), target: '_blank', 'data-native-blank': t,
          style: 'display:block;width:320px;height:48px;margin:8px 0;background:#ddd' });
        a.textContent = 'native target=_blank ' + t;
        a.addEventListener('click', (e) => window.__nativeClicks.push({ target: t, isTrusted: e.isTrusted }));
        note('a-target-blank-native', t, 'placed');
      }
    }
    // Alternate loopback spellings and the host's own private/ULA addresses.
    await each('lan-fetch', LAN, (u) => fetch(u('lanfetch')).then((r) => 'status:' + r.status));
    await each('lan-img', LAN, (u) => load(() => { const i = new Image(); i.src = u('lanimg', '.gif'); return i; }));
    await each('lan-iframe', LAN, (u) => new Promise((r) => { const f = el('iframe', { src: u('laniframe', '.html'), width: 5, height: 5 }); f.onload = () => r('load'); }));
    await each('lan-websocket', LAN, (u) => new Promise((r) => { const s = new WebSocket(u('lanws').replace(/^http/, 'ws')); s.onopen = () => { r('open'); s.close(); }; s.onerror = () => r('error'); }));
    // A data: document is not a request, but its own subresources and navigations are.
    await each('data-frame', [...BASIC, ...LAN], (u) => new Promise((r) => {
      const html = `<img src="${u('dataimg', '.gif')}"><iframe src="${u('dataiframe', '.html')}"></iframe>`
        + `<script>fetch(${JSON.stringify(u('datafetch'))}).catch(() => {});</scr` + 'ipt>';
      const f = el('iframe', { src: 'data:text/html,' + encodeURIComponent(html), width: 5, height: 5 });
      f.onload = () => r('load');
    }));
    await each('data-stylesheet', BASIC, (u) => load(() => el('link', { rel: 'stylesheet', href: 'data:text/css,' + encodeURIComponent(`@import url("${u('datacssimport', '.css')}"); div { background: url("${u('datacssbg', '.gif')}"); }`) }, document.head)));
    // WebKit refuses restricted port 10080 before connecting; the badport4 sink must see nothing.
    if (wants('badport') && ports.badport4) {
      note('badport', 'd4-10080', await bounded(fetch(`http://127.0.0.1:${ports.badport4}${base}/badport-d4`).then((r) => 'status:' + r.status, (e) => 'err:' + e.message)));
      note('badport-img', 'd4-10080', await bounded(load(() => { const i = new Image(); i.src = `http://127.0.0.1:${ports.badport4}${base}/badportimg-d4.gif`; return i; })));
    }
    // Subresources
    await each('img', BASIC, (u) => load(() => { const i = new Image(); i.src = u('img', '.gif'); return i; }));
    await each('script', BASIC, (u) => load(() => el('script', { src: u('script', '.js') })));
    await each('module-import', BASIC, (u) => import(u('modimport', '.mjs')).then(() => 'load'));
    await each('stylesheet', BASIC, (u) => load(() => el('link', { rel: 'stylesheet', href: u('css', '.css') }, document.head)));
    await each('css-import-bg', BASIC, (u) => { el('style', {}, document.head).textContent = `@import url("${u('cssimport', '.css')}");`; el('div', { style: `width:5px;height:5px;background-image:url("${u('cssbg', '.gif')}")` }); return 'inserted'; });
    await each('font', BASIC, (u) => new FontFace('f' + Math.random().toString(36).slice(2), `url(${u('font', '.woff')})`).load().then(() => 'load', () => 'error'));
    await each('svg-image', BASIC, (u) => { el('div', {}).innerHTML = `<svg width=5 height=5><image href="${u('svgimg', '.gif')}" width=5 height=5 /></svg>`; return 'inserted'; });
    await each('iframe', BASIC, (u) => new Promise((r) => { const f = el('iframe', { src: u('iframe', '.html'), width: 5, height: 5 }); f.onload = () => r('load'); }));
    await each('object', BASIC, (u) => { el('object', { data: u('object', '.html'), width: 5, height: 5 }); return 'inserted'; });
    await each('embed', BASIC, (u) => { el('embed', { src: u('embed', '.html'), width: 5, height: 5 }); return 'inserted'; });
    await each('video', BASIC, (u) => { el('video', { preload: 'auto', src: u('video', '.mp4') }).load(); return 'inserted'; });
    await each('audio', BASIC, (u) => { el('audio', { preload: 'auto', src: u('audio', '.mp3') }).load(); return 'inserted'; });
    await each('hls', BASIC, (u) => { el('video', { preload: 'auto', src: u('hls', '.m3u8') }).load(); return 'inserted'; });
    await each('track', BASIC, (u) => { const v = el('video', { preload: 'auto' }); el('track', { kind: 'subtitles', default: '', src: u('track', '.vtt') }, v); return 'inserted'; });
    await each('link-preload', BASIC, (u) => { el('link', { rel: 'preload', as: 'fetch', crossorigin: '', href: u('preload', '.txt') }, document.head); return 'inserted'; });
    await each('modulepreload', BASIC, (u) => { el('link', { rel: 'modulepreload', href: u('modpreload', '.mjs') }, document.head); return 'inserted'; });
    await each('link-prefetch', BASIC, (u) => { el('link', { rel: 'prefetch', href: u('prefetch', '.html') }, document.head); return 'inserted'; });
    if (wants('preconnect')) {
      // A bare connect carries no tag, so it has its own sink port.
      el('link', { rel: 'preconnect', href: `http://127.0.0.1:${ports.preconnect4}` }, document.head);
      note('preconnect', 'd4-port', 'inserted');
    }
    // Script-initiated
    await each('fetch', P.fetchTargets || ['d4', 'd6', 'lh', 'sub', 'num', 'h'], (u) => fetch(u('fetch')).then((r) => 'status:' + r.status));
    await each('fetch-nocors-post', BASIC, (u) => fetch(u('fetchpost'), { method: 'POST', mode: 'no-cors', body: 'x' }).then((r) => 'type:' + r.type));
    await each('fetch-keepalive', BASIC, (u) => fetch(u('keepalive'), { method: 'POST', keepalive: true, mode: 'no-cors', body: 'x' }).then((r) => 'type:' + r.type));
    await each('xhr', BASIC, (u) => new Promise((r) => { const x = new XMLHttpRequest(); x.open('GET', u('xhr')); x.onload = () => r('status:' + x.status); x.onerror = () => r('error'); x.send(); }));
    await each('beacon', BASIC, (u) => navigator.sendBeacon(u('beacon'), 'x'));
    await each('websocket', BASIC, (u) => new Promise((r) => { const s = new WebSocket(u('ws').replace(/^http/, 'ws')); s.onopen = () => { r('open'); s.close(); }; s.onerror = () => r('error'); }));
    await each('eventsource', BASIC, (u) => new Promise((r) => { const s = new EventSource(u('event')); s.onopen = () => { r('open'); s.close(); }; s.onerror = () => { r('error'); s.close(); }; }));
    await each('a-ping', BASIC, (u) => { const n = 'p' + Math.random().toString(36).slice(2); el('iframe', { name: n, width: 5, height: 5 }); const a = el('a', { href: u('pinghref', '.html'), ping: u('ping'), target: n }); a.textContent = 'p'; a.click(); return 'clicked'; });
    await each('form-post', BASIC, (u) => { const n = 'f' + Math.random().toString(36).slice(2); el('iframe', { name: n, width: 5, height: 5 }); const f = el('form', { method: 'POST', action: u('form'), target: n }); el('input', { name: 'k', value: 'v' }, f); f.submit(); return 'submitted'; });
    await each('meta-refresh-iframe', BASIC, (u) => { el('iframe', { srcdoc: `<meta http-equiv=refresh content="0;url=${u('metarefresh', '.html')}">`, width: 5, height: 5 }); return 'inserted'; });
    await each('download-attr', BASIC, (u) => { const n = 'd' + Math.random().toString(36).slice(2); el('iframe', { name: n, width: 5, height: 5 }); const a = el('a', { href: u('download', '.bin'), download: 'x.bin', target: n }); a.click(); return 'clicked'; });
    await each('window-open', ['d4', 'h'], (u) => (window.open(u('popup', '.html')) ? 'opened' : 'null'));
    // target=_blank is the known residual: it runs only in its own isolated control.
    if (P.only === 'a-target-blank') {
      await each('a-target-blank', ['d4', 'h'], (u) => { const a = el('a', { href: u('blank', '.html'), target: '_blank' }); a.textContent = 'b'; a.click(); return 'clicked'; });
      await sleep(2000);
    }
    // Workers
    if (wants('dedicated-worker')) {
      note('dedicated-worker', 'self', await bounded(new Promise((r) => {
        const w = new Worker(workerURL);
        w.onmessage = (e) => { results.push(...e.data.map((x) => ({ ...x, path: 'worker:' + x.path }))); r('done'); };
        w.onerror = (e) => r('error:' + e.message);
        w.postMessage(workerSpec('w'));
      }), 20000));
    }
    // WebRTC and WebTransport: UDP, one sink port per frame type.
    if (wants('webrtc')) {
      const ice = (port) => [{ urls: `stun:127.0.0.1:${port}` }, { urls: `stun:[::1]:${ports.stun6}` },
        { urls: `turn:127.0.0.1:${ports.turn4}?transport=tcp`, username: 'u', credential: 'p' }];
      note('webrtc-main', 'stun-main', await bounded(rtc(window.RTCPeerConnection, ice(ports['stun-main'])).catch((e) => 'err:' + e), 5000));
      const blank = el('iframe', { width: 5, height: 5 });
      note('webrtc-about-blank', 'stun-blank', await bounded(rtc(blank.contentWindow.RTCPeerConnection, ice(ports['stun-blank'])).catch((e) => 'err:' + e), 5000));
      const srcdoc = el('iframe', { srcdoc: '<p>x</p>', width: 5, height: 5 });
      await sleep(300);
      note('webrtc-srcdoc', 'stun-srcdoc', await bounded(rtc(srcdoc.contentWindow.RTCPeerConnection, ice(ports['stun-srcdoc'])).catch((e) => 'err:' + e), 5000));
      const dataSource = `<script>(async()=>{try{const pc=new RTCPeerConnection({iceServers:[{urls:'stun:127.0.0.1:${ports['stun-data']}'}]});pc.createDataChannel('x');await pc.setLocalDescription(await pc.createOffer());parent.postMessage('data-rtc:started','*')}catch(e){parent.postMessage('data-rtc:'+e,'*')}})()<\/script>`;
      const dataMessage = new Promise((r) => addEventListener('message', (e) => typeof e.data === 'string' && e.data.startsWith('data-rtc') && r(e.data)));
      el('iframe', { src: 'data:text/html,' + encodeURIComponent(dataSource), width: 5, height: 5 });
      note('webrtc-data-url', 'stun-data', await bounded(dataMessage, 4000));
      await sleep(2500);
    }
    if (wants('webtransport')) {
      try {
        note('webtransport', 'quic4', typeof WebTransport === 'function'
          ? await bounded(new WebTransport(`https://127.0.0.1:${ports.quic4}${base}/wt`).ready.then(() => 'ready', (e) => 'err:' + e), 4000)
          : 'absent');
      } catch (e) { note('webtransport', 'quic4', 'throw:' + e); }
    }
    await sleep(1500);
  }

  run().catch((e) => note('run', 'fatal', 'throw:' + e)).finally(() => {
    window.__probeDone = JSON.stringify({ results, ua: navigator.userAgent });
    if (!P.only) setTimeout(() => { location.href = T.d4('mainframe-nav', '.html'); }, 1500);
  });
})();
