#!/usr/bin/env python3
"""Optional account-authenticated registry + pinned Tailscale relay.

Run behind the existing HTTPS nginx /connector/ location. No secrets in logs.
"""

import base64
import hashlib
import hmac
import http.client
import http.server
import io
import ipaddress
import json
import os
import re
import secrets
import select
import ssl
import threading
import time
import urllib.parse
from pathlib import Path

from connector import atomic, read

USERS = Path(
    os.environ.get("CONNECTOR_USERS_FILE", "/var/lib/xharness-accounts/accounts.json")
)
REGISTRY = Path(
    os.environ.get("CONNECTOR_REGISTRY_FILE", "/var/lib/xharness-hub/registry.json")
)
ORIGIN = os.environ.get("CONNECTOR_PUBLIC_ORIGIN", "https://dsh.sixuanai.com").rstrip(
    "/"
)
PORT = int(os.environ.get("CONNECTOR_HUB_PORT", "3087"))
LOCK = threading.Lock()
UUID = re.compile(r"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$")
LIMIT = int(os.environ.get("CONNECTOR_MAX_BODY", "33554432"))


def basic(value):
    try:
        scheme, v = value.split(" ", 1)
        if scheme.lower() != "basic":
            return None
        user, pw = base64.b64decode(v, validate=True).decode().split(":", 1)
        return user, pw
    except (ValueError, UnicodeError):
        return None


def account(value):
    pair = basic(value)
    if not pair:
        return None
    user, pw = pair
    if not user or not pw:
        return None
    users = read(USERS, {})
    for key, v in users.items():
        if not isinstance(v, dict):
            continue
        if user != key and user.lower() != str(v.get("email", "")).lower():
            continue
        if (
            v.get("algorithm") == "pbkdf2-sha256"
            and v.get("iterations") == 210000
            and re.fullmatch("[a-f0-9]{32}", v.get("salt", ""))
            and re.fullmatch("[a-f0-9]{64}", v.get("digest", ""))
        ):
            if hmac.compare_digest(
                hashlib.pbkdf2_hmac(
                    "sha256", pw.encode(), bytes.fromhex(v["salt"]), 210000
                ).hex(),
                v["digest"],
            ):
                return key
        elif (
            os.environ.get("CONNECTOR_TEST_LOOPBACK") == "1"
            and isinstance(v.get("password"), str)
            and v["password"]
            and hmac.compare_digest(pw.encode(), v["password"].encode())
        ):
            return key
    return None


def connection(entry):
    ip = ipaddress.ip_address(entry["address"])
    test = os.environ.get("CONNECTOR_TEST_LOOPBACK") == "1"
    if ip.version != 4 or not (
        ip in ipaddress.ip_network("100.64.0.0/10") or (test and ip.is_loopback)
    ):
        raise ValueError("tailscale-address-required")
    port = int(entry["port"])
    allowed = [3082] if not test else list(range(1024, 65536))
    if port not in allowed or not re.fullmatch("[a-f0-9]{64}", entry["fingerprint"]):
        raise ValueError("invalid-connector-target")
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    c = http.client.HTTPSConnection(str(ip), port, context=ctx, timeout=5)
    c.connect()
    if not hmac.compare_digest(
        hashlib.sha256(c.sock.getpeercert(binary_form=True)).hexdigest(),
        entry["fingerprint"],
    ):
        c.close()
        raise ValueError("certificate-mismatch")
    return c


ATTEMPTS = {}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, status, data):
        self.close_connection = True
        b = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Connection", "close")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)

    def do_POST(self):
        if self.path == "/connector/enroll":
            return self.enroll()
        return self.proxy()

    def do_GET(self):
        return self.proxy()

    def do_DELETE(self):
        if self.path.startswith("/connector/enroll/"):
            owner = account(self.headers.get("Authorization", ""))
            ident = self.path.rsplit("/", 1)[-1]
            if not owner:
                return self.reply(401, {"error": "account-auth-required"})
            with LOCK:
                store = read(REGISTRY, {"version": 1, "nodes": {}})
                node = store["nodes"].get(ident)
                if not node or node["owner"] != owner:
                    return self.reply(404, {"error": "computer-not-found"})
                del store["nodes"][ident]
                atomic(REGISTRY, store)
            return self.reply(200, {"ok": True})
        return self.proxy()

    def do_PUT(self):
        return self.proxy()

    def do_PATCH(self):
        return self.proxy()

    def enroll(self):
        now = time.monotonic()
        address = self.headers.get("X-Real-IP", self.client_address[0])
        with LOCK:
            stale = [k for k, v in ATTEMPTS.items() if v[0] < now - 60]
            for k in stale:
                del ATTEMPTS[k]
            if os.environ.get("CONNECTOR_TEST_LOOPBACK") != "1" and (
                len(ATTEMPTS) >= 1024 or ATTEMPTS.get(address, [now, 0])[1] >= 8
            ):
                return self.reply(429, {"error": "try-later"})
            stamp, count = ATTEMPTS.get(address, [now, 0])
            ATTEMPTS[address] = [stamp, count + 1]
        owner = account(self.headers.get("Authorization", ""))
        if not owner:
            return self.reply(401, {"error": "account-auth-required"})
        c = None
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 0 or size > 8192:
                return self.reply(413, {"error": "invalid-body-size"})
            value = json.loads(self.rfile.read(size))
            ident = value["nodeId"]
            secret = value["enrollmentSecret"]
            if not UUID.fullmatch(ident) or not re.fullmatch("[a-f0-9]{64}", secret):
                raise ValueError("invalid-identity")
            entry = {
                "owner": owner,
                "name": str(value.get("name", "电脑"))[:80],
                "address": value["address"],
                "port": int(value["port"]),
                "fingerprint": value["fingerprint"],
            }
            with LOCK:
                existing = read(REGISTRY, {"nodes": {}})["nodes"].get(ident)
                if existing and existing["owner"] != owner:
                    return self.reply(403, {"error": "computer-owned-by-other-account"})
            c = connection(entry)
            nonce = secrets.token_hex(32)
            c.request("GET", "/connector/enroll-proof?nonce=" + nonce)
            r = c.getresponse()
            proof = json.loads(r.read(8192))
            expected = hmac.new(
                secret.encode(), nonce.encode(), hashlib.sha256
            ).hexdigest()
            if (
                r.status != 200
                or proof.get("nodeId") != ident
                or not hmac.compare_digest(proof.get("proof", ""), expected)
            ):
                raise ValueError("ownership-proof-failed")
            with LOCK:
                store = read(REGISTRY, {"version": 1, "nodes": {}})
                existing = store["nodes"].get(ident)
                if existing and existing["owner"] != owner:
                    return self.reply(403, {"error": "computer-owned-by-other-account"})
                store["nodes"][ident] = entry
                atomic(REGISTRY, store)
            return self.reply(
                200, {"nodeId": ident, "url": ORIGIN + "/connector/" + ident}
            )
        except (ValueError, KeyError, TypeError, OSError, http.client.HTTPException):
            return self.reply(
                400,
                {
                    "error": "registration-failed-check-network-certificate-and-ownership"
                },
            )
        finally:
            if c:
                c.close()

    def proxy(self):
        path = urllib.parse.urlsplit(self.path)
        parts = path.path.split("/", 3)
        if len(parts) != 4 or parts[1] != "connector" or not UUID.fullmatch(parts[2]):
            return self.reply(404, {"error": "not-found"})
        ident = parts[2]
        tail = "/" + parts[3]
        tail += ("?" + path.query) if path.query else ""
        entry = read(REGISTRY, {"nodes": {}})["nodes"].get(ident)
        if not entry or entry.get("owner") not in read(USERS, {}):
            return self.reply(404, {"error": "computer-not-found"})
        info = tail == "/connector/info" and self.command == "GET"
        if not info and not tail.startswith("/api/"):
            return self.reply(404, {"error": "not-found"})
        auth = self.headers.get("Authorization", "")
        pair = basic(auth)
        if not info and (not pair or not re.fullmatch("device-[a-f0-9-]{36}", pair[0])):
            return self.reply(401, {"error": "paired-device-auth-required"})
        c = None
        responded = False
        try:
            if self.headers.get("Transfer-Encoding"):
                return self.reply(400, {"error": "content-length-required"})
            size = int(self.headers.get("Content-Length", "0"))
            if size < 0 or size > LIMIT:
                return self.reply(413, {"error": "request-too-large"})
            body = self.rfile.read(size) if size else None
            headers = {
                k: v
                for k, v in self.headers.items()
                if k.lower()
                not in [
                    "host",
                    "cookie",
                    "proxy-authorization",
                    "connection",
                    "x-forwarded-for",
                    "x-forwarded-host",
                    "x-forwarded-proto",
                ]
            }
            headers["Host"] = entry["address"] + ":" + str(entry["port"])
            upgrade = self.headers.get("Upgrade", "").lower() == "websocket"
            if upgrade:
                headers["Connection"] = "Upgrade"
            c = connection(entry)
            sock = c.sock
            c.request(self.command, tail, body=body, headers=headers)
            if upgrade:
                # Read the upgrade header without buffering the first WebSocket frame.
                raw = b""
                while not raw.endswith(b"\r\n\r\n"):
                    part = sock.recv(1)
                    if not part or len(raw) > 65536:
                        raise OSError("bad-upgrade")
                    raw += part
                lines = raw.split(b"\r\n", 1)
                status = int(lines[0].split()[1])
                h = http.client.parse_headers(io.BytesIO(lines[1]))
                self.send_response(status)
                responded = True
                for k, v in h.items():
                    if k.lower() not in ["set-cookie", "connection", "server", "date"]:
                        self.send_header(k, v)
                if status != 101:
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.close_connection = True
                    remaining = min(int(h.get("Content-Length", "0")), 8192)
                    while remaining:
                        block = sock.recv(remaining)
                        if not block:
                            break
                        self.wfile.write(block)
                        remaining -= len(block)
                    return
                self.send_header("Connection", "Upgrade")
                self.end_headers()
                self.wfile.flush()
                sock.settimeout(None)
                self.connection.settimeout(None)
                self.close_connection = True
                while True:
                    ready = (
                        [sock]
                        if sock.pending()
                        else select.select([sock, self.connection], [], [], 60)[0]
                    )
                    for src in ready:
                        chunk = src.recv(65536)
                        if not chunk:
                            return
                        (self.connection if src is sock else sock).sendall(chunk)
            else:
                r = c.getresponse()
                self.send_response(r.status)
                responded = True
                for k, v in r.getheaders():
                    if k.lower() not in [
                        "set-cookie",
                        "transfer-encoding",
                        "connection",
                        "server",
                        "date",
                    ]:
                        self.send_header(k, v)
                self.send_header("Connection", "close")
                self.end_headers()
                self.close_connection = True
                while True:
                    b = r.read(65536)
                    if not b:
                        break
                    self.wfile.write(b)
        except (OSError, ValueError, http.client.HTTPException):
            self.close_connection = True
            if not self.wfile.closed and not responded:
                try:
                    self.reply(503, {"error": "computer-unavailable"})
                except OSError:
                    pass
        finally:
            if c:
                c.close()


if __name__ == "__main__":
    if urllib.parse.urlsplit(ORIGIN).scheme != "https":
        raise SystemExit("CONNECTOR_PUBLIC_ORIGIN must use HTTPS")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.daemon_threads = True
    print("xHarness hub ready", flush=True)
    server.serve_forever()
