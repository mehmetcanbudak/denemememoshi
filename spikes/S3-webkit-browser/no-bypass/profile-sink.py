#!/usr/bin/env python3
"""Owned cookie, storage and cache sink for the S3 separate-profile control (D136).

  profile-sink.py <log.jsonl> <ports.json>

Loopback only; no upstream request is ever made. Three listeners on free ports:
  * `A`  on 127.0.0.1: the bot's signed-in site;
  * `A2` on 127.0.0.1, another port: the same site (cookies ignore the port);
  * `B`  on 127.0.0.1 and ::1, loaded as `localhost` (or `[::1]`, which no cookie names): another site.
Every request is logged with the listener, path and query (owned markers only) and its Cookie
header, so the log shows which profile's cookies reached which site. Pages:
  /seed?v=V[&sw=1]       sets cookies d136=V (no SameSite), d136l=V (Lax) and d136s=V (Strict) and
                         localStorage memoshi-d136=V, loads /cached.js
                         (cacheable for a day) and, with sw=1, registers a service worker that
                         fetches /sw-hit on every request in its scope;
  /page?task=T[&next=U][&mode=K][&mark=M]
                         heading "Page <listener>" and a way to U: a "Next site" link (default),
                         K=blank a `target=_blank` link, K=script a "Go by script" button setting
                         `location`, K=open an "Open window" button calling `window.open`,
                         K=formget/formpost a form to U (its query as hidden fields for GET, U as
                         action for POST) with a "Search other site" or "Save other site" button,
                         K=sframe a sandboxed srcdoc frame whose script moves the top level to U,
                         K=formreplay the POST form, submitted again into a frame of this page
                         with another note once it left, K=upload a multipart POST form to U with
                         a "Test file" picker and an "Upload file" button, K=cookieframe a page
                         that sets cookie d136f=1 and embeds U in a frame; without U, K=typed a
                         "Typed text" field and K=typeddouble one that doubles every typed space;
                         a POST to /page answers the same page. Loads /cached.js and
                         reports what it sees (document.cookie, both storage markers, whether a
                         worker controls it) to /report; with mark, first sets cookie d136t=M-kept
                         and localStorage memoshi-d136-t=M-kept, which only a separate profile ever
                         holds (`-kept` never appears in a URL, so a disk search for it finds only
                         stored data);
  /d136-sw.js, /cached.js, /report, /sw-hit   the worker, the cacheable script and the receipts;
  /liveness?n=N          run-control.py's liveness probe after the driver exited (logged, 204);
  /redirect?to=U         302 to U.
Its `ready` record names each listener's address, so run-control.py can probe every one.
"""
import json
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from html import escape
from urllib.parse import parse_qs, parse_qsl, urlsplit

LOG = open(sys.argv[1], "x", buffering=1)
LOCK = threading.Lock()

PAGE = """<!doctype html><html lang="en"><meta charset="utf-8"><title>D136 {label}</title>
<body><h1>Page {label}</h1>{link}
<script>
(async () => {{
  const q = new URLSearchParams(location.search);
  const mark = q.get('mark');
  if (mark) {{ try {{ localStorage.setItem('memoshi-d136-t', mark + '-kept'); }} catch (e) {{}} }}
  const read = (k) => {{ try {{ return localStorage.getItem(k); }} catch (e) {{ return 'err:' + e; }} }};
  await new Promise((r) => {{ const s = document.createElement('script'); s.src = '/cached.js?v=1'; s.onload = s.onerror = r; document.head.append(s); }});
  const seen = {{ task: q.get('task'), href: location.href, cookie: document.cookie, storage: read('memoshi-d136'),
    storageSeparate: read('memoshi-d136-t'), cachedScript: window.__cachedLoaded === true,
    serviceWorker: typeof navigator.serviceWorker,
    controlled: !!(navigator.serviceWorker && navigator.serviceWorker.controller) }};
  try {{ await fetch('/report?' + new URLSearchParams({{ seen: JSON.stringify(seen) }})); }} catch (e) {{}}
  window.__d136 = JSON.stringify(seen);
}})();
</script></body></html>
"""

SEED = """<!doctype html><html lang="en"><meta charset="utf-8"><title>D136 seed {label}</title>
<body><h1>Seeded {label}</h1>
<script>
(async () => {{
  const q = new URLSearchParams(location.search);
  const out = {{ task: 'seed', href: location.href, cookie: document.cookie }};
  try {{ localStorage.setItem('memoshi-d136', q.get('v')); out.storage = localStorage.getItem('memoshi-d136'); }}
  catch (e) {{ out.storage = 'err:' + e; }}
  await new Promise((r) => {{ const s = document.createElement('script'); s.src = '/cached.js?v=1'; s.onload = s.onerror = r; document.head.append(s); }});
  out.cachedScript = window.__cachedLoaded === true;
  if (q.get('sw')) {{
    try {{
      await navigator.serviceWorker.register('/d136-sw.js', {{ scope: '/' }});
      await navigator.serviceWorker.ready;
      out.serviceWorker = 'registered';
    }} catch (e) {{ out.serviceWorker = 'err:' + e.message; }}
  }}
  window.__d136 = JSON.stringify(out);
}})();
</script></body></html>
"""

WORKER = """self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(clients.claim()));
self.addEventListener('fetch', (event) => {
  if (!event.request.url.includes('/sw-hit')) {
    event.waitUntil(fetch('/sw-hit?u=' + encodeURIComponent(event.request.url)).catch(() => {}));
  }
});
"""


def log(record):
    record["t"] = time.time()
    with LOCK:
        LOG.write(json.dumps(record, sort_keys=True) + "\n")


def fetch_metadata(headers):
    """The request's fetch-metadata and Origin headers, as sent."""
    return {"secFetchSite": headers.get("Sec-Fetch-Site"), "secFetchMode": headers.get("Sec-Fetch-Mode"),
            "secFetchDest": headers.get("Sec-Fetch-Dest"), "origin": headers.get("Origin")}


def way_to(next_url, mode):
    """The page's way to `next_url`, as markup."""
    href = escape(next_url, quote=True)
    if mode == "sframe":
        # D136 review F1: a frame with an opaque origin moves the top level by script.
        script = f"<script>setTimeout(() => {{ top.location.href = {json.dumps(next_url)}; }}, 1500);</script>"
        return (f'<iframe title="Sandboxed frame" sandbox="allow-scripts allow-top-navigation" '
                f'srcdoc="{escape(script, quote=True)}" width="5" height="5"></iframe>')
    if mode == "formreplay":
        # D136 review F7: once the form left for another profile, the page left behind submits it
        # again, with another note, into a frame of its own.
        return (f'<form id="replayed" method="post" action="{href}"><input type="hidden" name="note" '
                'value="d136-post"><button>Save other site</button></form>'
                '<iframe name="replay" title="Replay frame" width="5" height="5"></iframe>'
                "<script>document.getElementById('replayed').addEventListener('submit', (event) => {"
                " const form = event.target; setTimeout(() => { form.elements.note.value = 'd136-replay';"
                " form.target = 'replay'; form.submit(); }, 30); });</script>")
    if mode == "upload":
        # D136 review F9: a file staged for this picker makes the profile hold private data.
        return (f'<form method="post" action="{href}" enctype="multipart/form-data">'
                '<label for="file">Test file</label><input id="file" type="file" name="file">'
                "<button>Upload file</button></form>")
    if mode == "cookieframe":
        # D136 review spec gap 5: the page holds private data only once this response's cookie
        # is stored, after the review was configured.
        return f'<iframe title="Embedded frame" src="{href}" width="200" height="100"></iframe>'
    if mode == "blank":
        return f'<p><a id="next" href="{href}" target="_blank">Next site</a></p>'
    if mode == "script":
        return (f'<p><button id="next" type="button" onclick="location.href = {escape(json.dumps(next_url))}">'
                "Go by script</button></p>")
    if mode == "open":
        return (f'<p><button id="next" type="button" onclick="window.open({escape(json.dumps(next_url))})">'
                "Open window</button></p>")
    if mode in ("formget", "formpost"):
        parts = urlsplit(next_url)
        if mode == "formget":
            action = escape(parts._replace(query="").geturl(), quote=True)
            fields = "".join(f'<input type="hidden" name="{escape(k, quote=True)}" value="{escape(v, quote=True)}">'
                             for k, v in parse_qsl(parts.query))
            return f'<form method="get" action="{action}">{fields}<button>Search other site</button></form>'
        return (f'<form method="post" action="{href}"><input type="hidden" name="note" value="d136-post">'
                "<button>Save other site</button></form>")
    return f'<p><a id="next" href="{href}">Next site</a></p>'


def field(mode):
    """A text field for native typing (D136 review F6), or nothing."""
    if mode == "typed":
        return '<p><label for="typed">Typed text</label><input id="typed"></p>'
    if mode == "typeddouble":
        return ('<p><label for="typed">Typed text</label>'
                "<input id=\"typed\" oninput=\"if (event.data === ' ') this.value += ' '\"></p>")
    return ""


def handler(label):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *_):
            pass

        def reply(self, body, content_type="text/html; charset=utf-8", status=200, extra=()):
            data = body.encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            for key, value in extra:
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            parts = urlsplit(self.path)
            query = {k: v[0] for k, v in parse_qs(parts.query).items()}
            log({"listener": label, "method": "GET", "path": parts.path, "query": query,
                 "host": self.headers.get("Host"), "cookie": self.headers.get("Cookie"),
                 "referer": self.headers.get("Referer"), **fetch_metadata(self.headers)})
            fresh = [("Cache-Control", "no-store")]
            if parts.path == "/seed":
                value = query.get("v", "")
                cookies = [("Set-Cookie", f"d136={value}; Max-Age=86400; Path=/"),
                           ("Set-Cookie", f"d136l={value}; Max-Age=86400; Path=/; SameSite=Lax"),
                           ("Set-Cookie", f"d136s={value}; Max-Age=86400; Path=/; SameSite=Strict")]
                self.reply(SEED.format(label=label), extra=fresh + cookies)
            elif parts.path == "/page":
                self.page(query, fresh)
            elif parts.path == "/redirect" and "to" in query:
                self.send_response(302)
                self.send_header("Location", query["to"])
                self.send_header("Content-Length", "0")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
            elif parts.path == "/cached.js":
                self.reply("window.__cachedLoaded = true;\n", "text/javascript",
                           extra=[("Cache-Control", "public, max-age=86400")])
            elif parts.path == "/d136-sw.js":
                self.reply(WORKER, "text/javascript", extra=fresh)
            elif parts.path in ("/report", "/sw-hit", "/liveness"):
                self.reply("", "text/plain", status=204, extra=fresh)
            else:
                self.reply("not found", "text/plain", status=404, extra=fresh)

        def page(self, query, fresh):
            link = way_to(query["next"], query.get("mode")) if "next" in query else field(query.get("mode"))
            extra = list(fresh)
            if "mark" in query:
                extra.append(("Set-Cookie", f"d136t={query['mark']}-kept; Max-Age=86400; Path=/"))
            if query.get("mode") == "cookieframe":
                extra.append(("Set-Cookie", "d136f=1; Max-Age=86400; Path=/"))
            self.reply(PAGE.format(label=label, link=link), extra=extra)

        def do_POST(self):
            parts = urlsplit(self.path)
            query = {k: v[0] for k, v in parse_qs(parts.query).items()}
            length = min(int(self.headers.get("Content-Length") or 0), 65536)
            body = self.rfile.read(length).decode("latin-1", "replace")
            log({"listener": label, "method": "POST", "path": parts.path, "query": query,
                 "form": {k: v[0] for k, v in parse_qs(body).items()},
                 "host": self.headers.get("Host"), "cookie": self.headers.get("Cookie"),
                 "referer": self.headers.get("Referer"), **fetch_metadata(self.headers)})
            if parts.path == "/page":
                self.page(query, [("Cache-Control", "no-store")])
            else:
                self.reply("not found", "text/plain", status=404)

    return Handler


class V6Server(ThreadingHTTPServer):
    address_family = socket.AF_INET6


def serve(server):
    threading.Thread(target=server.serve_forever, daemon=True).start()


def main():
    servers, ports, listeners = [], {}, []
    for label in ["A", "A2"]:
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler(label))
        servers.append(server)
        ports[label] = server.server_address[1]
        listeners.append({"label": label, "host": "127.0.0.1", "port": ports[label]})
    # `localhost` may resolve to either family; B answers on both with one port.
    for _ in range(20):
        v4 = ThreadingHTTPServer(("127.0.0.1", 0), handler("B"))
        try:
            v6 = V6Server(("::1", v4.server_address[1]), handler("B"))
        except OSError:
            v4.server_close()
            continue
        servers += [v4, v6]
        ports["B"] = v4.server_address[1]
        listeners += [{"label": "B", "host": host, "port": ports["B"]} for host in ("127.0.0.1", "::1")]
        break
    else:
        sys.exit("no port free on both loopback families")
    for server in servers:
        serve(server)
    with open(sys.argv[2], "x") as stream:
        json.dump(ports, stream, sort_keys=True)
    log({"listener": "ready", "ports": ports, "listeners": listeners})
    threading.Event().wait()


main()
