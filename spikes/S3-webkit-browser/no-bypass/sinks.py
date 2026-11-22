#!/usr/bin/env python3
"""Independent loopback sinks for the S3 no-bypass qualification control.

A separate process from the page fixture and the gateway: neither ever writes this log. It binds
127.0.0.1/::1, plus one address per private/link-local/ULA class that the host already has on an
interface (labelled `own:<address>`; never configured here, never another host), and the fixed
WebKit-restricted port 10080 on 127.0.0.1 when it is free (`badport4`). It records every TCP
accept, the first request bytes, and every UDP datagram with a wall-clock timestamp. A page that
reaches any sink has bypassed the browser boundary. Its `ready` record lists every listener;
run-control.py probes each one after the driver exits, so a sink that died mid-run, which would
have recorded nothing for every later scenario, can never be read as a clean run.

Usage: sinks.py <events.jsonl> <ports.json>
Ports are ephemeral and written to <ports.json> once every socket is bound.
"""
import asyncio
import base64
import hashlib
import ipaddress
import json
import subprocess
import sys
import time

# TCP: HTTP/WebSocket v4/v6, a bare-connect port for <link rel=preconnect>, TURN over TCP.
TCP_LABELS = ["http4", "http6", "preconnect4", "turn4"]
# UDP: STUN per frame type plus v6, and the QUIC port WebTransport dials.
UDP_LABELS = ["stun-main", "stun-blank", "stun-srcdoc", "stun-data", "stun-worker", "stun6", "quic4"]

# WebKit (like the Fetch standard) refuses this port before connecting; the control proves it.
RESTRICTED_PORT = 10080
PRIVATE_V4 = [("rfc1918-10", "10.0.0.0/8"), ("rfc1918-172", "172.16.0.0/12"),
              ("rfc1918-192", "192.168.0.0/16"), ("linklocal-169", "169.254.0.0/16")]

LOG = open(sys.argv[1], "x", buffering=1)


def own_addresses():
    """One address per private class already present on this host's interfaces (read-only)."""
    found = {}
    text = subprocess.run(["/sbin/ifconfig"], capture_output=True, text=True, check=True).stdout
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 2 or parts[0] not in ("inet", "inet6") or "%" in parts[1]:
            continue
        address = ipaddress.ip_address(parts[1])
        if address.version == 4:
            label = next((name for name, net in PRIVATE_V4 if address in ipaddress.ip_network(net)), None)
        else:
            label = "ula" if address in ipaddress.ip_network("fc00::/7") else None
        if label and label not in found:
            found[label] = str(address)
    return found


def log(record):
    record["t"] = time.time()
    LOG.write(json.dumps(record, sort_keys=True) + "\n")


def http_reply(head):
    text = head.decode("latin-1", "replace")
    first = text.split("\r\n", 1)[0]
    path = first.split(" ")[1] if " " in first else "/"
    headers = {}
    for line in text.split("\r\n")[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    if headers.get("upgrade", "").lower() == "websocket":
        accept = base64.b64encode(hashlib.sha1(
            (headers.get("sec-websocket-key", "") + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
        ).digest()).decode()
        return ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode()
    route = path.split("?")[0]
    if route.endswith(".m3u8"):
        body = ("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:1\n#EXTINF:1.0,\n"
                + route.replace(".m3u8", "-seg.ts") + "\n#EXT-X-ENDLIST\n").encode()
        kind = "application/vnd.apple.mpegurl"
    elif route.endswith(".js") or route.endswith(".mjs"):
        body, kind = b"/*sink*/", "text/javascript"
    elif route.endswith(".css"):
        body, kind = b"/*sink*/", "text/css"
    elif "event" in route:
        body, kind = b"data: x\n\n", "text/event-stream"
    elif route.endswith(".gif"):
        body = base64.b64decode("R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")
        kind = "image/gif"
    else:
        body, kind = b"sink", "text/html"
    return (f"HTTP/1.1 200 OK\r\nContent-Type: {kind}\r\nContent-Length: {len(body)}\r\n"
            "Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n").encode() + body


def tcp_handler(label):
    async def handle(reader, writer):
        peer = str(writer.get_extra_info("peername"))
        log({"kind": "tcp-accept", "label": label, "peer": peer})
        data = b""
        try:
            while b"\r\n\r\n" not in data and len(data) < 16384:
                chunk = await asyncio.wait_for(reader.read(4096), timeout=5)
                if not chunk:
                    break
                data += chunk
        except Exception as error:
            log({"kind": "tcp-read-end", "label": label, "peer": peer, "error": type(error).__name__})
        if data:
            first = data.split(b"\r\n", 1)[0].decode("latin-1", "replace")
            log({"kind": "tcp-data", "label": label, "peer": peer, "first": first[:300],
                 "bytes": len(data)})
            if "HTTP/" in first and first.split(" ")[0].isalpha():
                try:
                    writer.write(http_reply(data))
                    await writer.drain()
                    if b"websocket" in data.lower():
                        await asyncio.sleep(1)
                except Exception:
                    pass
        try:
            writer.close()
        except Exception:
            pass
    return handle


class Udp(asyncio.DatagramProtocol):
    def __init__(self, label):
        self.label = label

    def datagram_received(self, data, address):
        log({"kind": "udp", "label": self.label, "peer": str(address), "bytes": len(data),
             "stunType": data[:2].hex()})


async def main():
    loop = asyncio.get_running_loop()
    ports, listeners = {}, []
    for label in TCP_LABELS:
        host = "::1" if label.endswith("6") else "127.0.0.1"
        server = await asyncio.start_server(tcp_handler(label), host, 0)
        ports[label] = server.sockets[0].getsockname()[1]
        listeners.append({"label": label, "kind": "tcp", "host": host, "port": ports[label]})
    for label in UDP_LABELS:
        host = "::1" if label.endswith("6") else "127.0.0.1"
        transport, _ = await loop.create_datagram_endpoint(lambda l=label: Udp(l), local_addr=(host, 0))
        ports[label] = transport.get_extra_info("sockname")[1]
        listeners.append({"label": label, "kind": "udp", "host": host, "port": ports[label]})
    own = own_addresses()
    for address in own.values():
        label = "own:" + address
        server = await asyncio.start_server(tcp_handler(label), address, 0)
        ports[label] = server.sockets[0].getsockname()[1]
        listeners.append({"label": label, "kind": "tcp", "host": address, "port": ports[label]})
    try:
        await asyncio.start_server(tcp_handler("badport4"), "127.0.0.1", RESTRICTED_PORT)
        ports["badport4"] = RESTRICTED_PORT
        listeners.append({"label": "badport4", "kind": "tcp", "host": "127.0.0.1", "port": RESTRICTED_PORT})
    except OSError:
        pass
    with open(sys.argv[2], "x") as stream:
        json.dump(ports, stream, sort_keys=True)
    # Every listener, so run-control.py can show each was still alive when the driver ended.
    log({"kind": "ready", "ports": ports, "ownAddresses": own, "listeners": listeners})
    await asyncio.Event().wait()


asyncio.run(main())
