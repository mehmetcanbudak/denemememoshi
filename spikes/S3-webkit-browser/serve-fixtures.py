#!/usr/bin/env python3
"""Owned S3 UI fixtures only. No accounts, upstream requests, telemetry or personal files.

Run explicitly: python3 spikes/S3-webkit-browser/serve-fixtures.py
Then select owned-fixture-suite.json in the native Browser Review Proof panel.
Receipts: http://127.0.0.1:8765/receipts.json (counts only, never request values).
Optional TLS requires caller-supplied trusted cert/key files; this never installs a CA.
--no-bypass-dir also serves the S3 no-bypass control's probe files under /no-bypass/
(see no-bypass/run-control.py).
"""
import argparse
import json
import os
import ssl
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Receipts:
    def __init__(self):
        self.lock = threading.Lock()
        self.counts = {}

    def add(self, method, route, size=0):
        with self.lock:
            key = method + " " + route
            row = self.counts.setdefault(key, {"requests": 0, "bodyBytes": 0})
            row["requests"] += 1
            row["bodyBytes"] += size

    def snapshot(self):
        with self.lock:
            return json.dumps({"schema": "memoshi.s3-owned-fixture/1", "requests": self.counts}, sort_keys=True).encode()


# The S3 no-bypass control's static probe files, served only when --no-bypass-dir is given.
NO_BYPASS_FILES = {"probe.html": "text/html; charset=utf-8", "probe.js": "text/javascript",
                   "sw.html": "text/html; charset=utf-8", "sw.js": "text/javascript"}


def handler(receipts, frame_port, scheme, no_bypass_dir=None):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *_):
            pass  # URLs, form values, authentication and file contents are never logged.

        def reply(self, body, content_type="text/html; charset=utf-8", extra=(), status=200):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            for key, value in extra:
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(body)

        def page(self, title):
            self.reply(("<!doctype html><html lang='en'><meta charset='utf-8'><h1>" + title
                        + "</h1><a href='/'>Fixture home</a></html>").encode())

        def do_GET(self):
            route = urlsplit(self.path).path
            if route == "/receipts.json":
                self.reply(receipts.snapshot(), "application/json")
                return
            name = route[len("/no-bypass/"):] if route.startswith("/no-bypass/") else None
            if no_bypass_dir and name in NO_BYPASS_FILES:
                receipts.add("GET", route)
                with open(os.path.join(no_bypass_dir, name), "rb") as stream:
                    self.reply(stream.read(), NO_BYPASS_FILES[name],
                               [("Service-Worker-Allowed", "/no-bypass/")])
                return
            if route not in ["/", "/search", "/page2", "/download", "/frame"]:
                self.reply(b"not found", "text/plain", status=404)
                return
            receipts.add("GET", route)
            if route == "/download":
                self.reply(b"Owned Memoshi browser download fixture.\n", "application/octet-stream",
                           [("Content-Disposition", "attachment; filename=fixture.txt")])
            elif route == "/search":
                self.page("Search complete")
            elif route == "/page2":
                self.page("Pagination complete")
            elif route == "/frame":
                self.reply(b"""<!doctype html><html lang='en'><meta charset='utf-8'>
<h1>Owned frame fixture</h1><button type='button' onclick="document.getElementById('result').textContent='Frame click received'">Frame click</button>
<label for='text'>Frame text</label><input id='text'><h2 id='result'>Frame ready</h2></html>""")
            else:
                html = """<!doctype html><html lang='en'><meta charset='utf-8'>
<style>body {font:16px system-ui; max-width:800px; padding:16px} form {margin:12px 0} iframe {width:650px;height:180px;border:3px solid gray}</style>
<h1>Owned browser fixture</h1>
<form action='/search' method='get'><label for='query'>Search query</label><input id='query' name='q'><button>Search fixture</button></form>
<form action='/form' method='post'><label for='value'>Test value</label><input id='value' name='value'><button>Save test value</button></form>
<form action='/send' method='post'><button>Send test message</button></form>
<form action='/pay' method='post'><button>Pay test amount</button></form>
<a href='/page2'>Next fixture page</a> · <a download href='/download'>Download test file</a>
<form action='/upload' method='post' enctype='multipart/form-data'><label for='upload'>Test upload files</label><input id='upload' type='file' name='files' multiple><button>Upload selected files</button></form>
<button type='button' onclick="document.getElementById('native-result').textContent='Native click received'">Native click</button>
<label for='native-text'>Native text</label><input id='native-text'><h2 id='native-result'>Native ready</h2>
<iframe title='Owned cross-origin fixture' src='FRAME_URL'></iframe>
</html>"""
                self.reply(html.replace("FRAME_URL", f"{scheme}://127.0.0.1:{frame_port}/frame").encode())

        def do_POST(self):
            route = urlsplit(self.path).path
            if route not in ["/form", "/upload", "/send", "/pay"]:
                self.reply(b"not found", "text/plain", status=404)
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                size = -1
            if not 0 <= size <= 2_097_152:
                self.close_connection = True
                self.reply(b"fixture body limit", "text/plain", status=413)
                return
            # Consume bytes only to complete the local HTTP request. Do not parse, echo, retain,
            # hash or log form fields, filenames or file contents.
            remaining = size
            while remaining:
                part = self.rfile.read(min(65_536, remaining))
                if not part:
                    self.close_connection = True
                    return
                remaining -= len(part)
            receipts.add("POST", route, size)
            self.page({"/form": "Form received", "/upload": "Upload received",
                       "/send": "Unexpected send reached fixture", "/pay": "Unexpected payment reached fixture"}[route])
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--frame-port", type=int, default=8766)
    parser.add_argument("--certfile")
    parser.add_argument("--keyfile")
    parser.add_argument("--no-bypass-dir")
    args = parser.parse_args()
    if bool(args.certfile) != bool(args.keyfile):
        parser.error("TLS requires both caller-supplied certfile and keyfile")
    receipts = Receipts()
    scheme = "https" if args.certfile else "http"
    servers = [ThreadingHTTPServer(("127.0.0.1", port),
                                   handler(receipts, args.frame_port, scheme, args.no_bypass_dir))
               for port in [args.port, args.frame_port]]
    if args.certfile:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.certfile, args.keyfile)
        for server in servers:
            server.socket = context.wrap_socket(server.socket, server_side=True)
    print(json.dumps({"ownedFixtureOnly": True, "main": f"{scheme}://127.0.0.1:{args.port}",
                      "frame": f"{scheme}://127.0.0.1:{args.frame_port}"}), flush=True)
    thread = threading.Thread(target=servers[1].serve_forever, daemon=True)
    thread.start()
    try:
        servers[0].serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        # Main server is no longer in serve_forever; only the worker requires shutdown().
        servers[1].shutdown()
        for server in servers:
            server.server_close()
        thread.join()


if __name__ == "__main__":
    main()
