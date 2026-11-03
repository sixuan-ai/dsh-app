#!/usr/bin/env python3
"""Local-only management UI. Launch capability is exchanged for an HttpOnly cookie."""

import argparse
import contextlib
import hmac
import http.server
import io
import json
import secrets
import threading
import time
import urllib.parse
import webbrowser
from pathlib import Path
from types import SimpleNamespace

from connector import (
    DEFAULT_STATE,
    doctor,
    pair,
    read,
    remote_enroll,
    revoke_device,
)


def serve(state, open_browser=True, ready=None):
    launch = secrets.token_urlsafe(32)
    session = secrets.token_urlsafe(32)
    deadline = time.monotonic() + 1800
    used = False
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, status, body, kind="application/json", headers=None):
            if not isinstance(body, bytes):
                body = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status)
            for k, v in {
                "Content-Type": kind,
                "Content-Length": str(len(body)),
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff",
                "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
                **(headers or {}),
            }.items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def authorized(self):
            return (
                self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"
                and time.monotonic() < deadline
                and any(
                    hmac.compare_digest(c.strip(), "xharness_admin=" + session)
                    for c in self.headers.get("Cookie", "").split(";")
                )
            )

        def do_GET(self):
            nonlocal used
            u = urllib.parse.urlsplit(self.path)
            if (
                u.path == "/launch"
                and self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"
            ):
                token = urllib.parse.parse_qs(u.query).get("token", [""])[0]
                with lock:
                    if used or not hmac.compare_digest(token, launch):
                        return self.send(403, {"error": "请重新打开桌面连接器"})
                    used = True
                return self.send(
                    303,
                    b"",
                    headers={
                        "Location": "/",
                        "Set-Cookie": "xharness_admin="
                        + session
                        + "; HttpOnly; SameSite=Strict; Path=/; Max-Age=1800",
                        "Referrer-Policy": "no-referrer",
                    },
                )
            if not self.authorized():
                return self.send(403, {"error": "会话已过期，请重新打开桌面连接器"})
            if u.path in ["/", "/app.js", "/style.css"]:
                name = {
                    "/": "index.html",
                    "/app.js": "app.js",
                    "/style.css": "style.css",
                }[u.path]
                kind = {
                    "/": "text/html; charset=utf-8",
                    "/app.js": "application/javascript",
                    "/style.css": "text/css",
                }[u.path]
                return self.send(
                    200, (Path(__file__).parent / "ui" / name).read_bytes(), kind
                )
            if u.path == "/status":
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    doctor(SimpleNamespace(state=state))
                d = json.loads(out.getvalue())
                d["devices"] = [
                    {k: v.get(k) for k in ["id", "name", "createdAt", "revoked"]}
                    for v in read(state / "devices.json", {}).get("devices", [])
                ]
                return self.send(200, d)
            if u.path == "/qr.svg":
                try:
                    return self.send(
                        200, (state / "pairing.svg").read_bytes(), "image/svg+xml"
                    )
                except OSError:
                    return self.send(404, {"error": "请先生成二维码"})
            return self.send(404, {"error": "not-found"})

        def do_POST(self):
            if (
                not self.authorized()
                or self.headers.get("Origin")
                != f"http://127.0.0.1:{self.server.server_port}"
            ):
                return self.send(403, {"error": "请从桌面连接器操作"})
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if size > 8192 or size < 0:
                    raise ValueError("请求过大")
                b = json.loads(self.rfile.read(size) or b"{}")
                with lock:
                    if self.path == "/pair":
                        with contextlib.redirect_stdout(io.StringIO()):
                            pair(
                                SimpleNamespace(
                                    state=state, host=b.get("host") or None, output=None
                                )
                            )
                        data = read(state / "pairing.json")
                        return self.send(
                            200,
                            {
                                "link": data["link"],
                                "expiresAt": data["payload"]["expiresAt"],
                            },
                        )
                    if self.path == "/revoke":
                        revoke_device(state, b.get("id"))
                        return self.send(200, {"ok": True})
                    if self.path == "/remote":
                        remote_enroll(
                            state,
                            b.get("gateway", ""),
                            b.get("username", ""),
                            b.get("password", ""),
                        )
                        return self.send(200, {"ok": True})
                    return self.send(404, {"error": "not-found"})
            except Exception as e:
                # Never echo credentials or upstream request/response content.
                return self.send(
                    400,
                    {
                        "error": str(e)
                        if isinstance(e, ValueError)
                        else "操作失败，请检查电脑、账号和网关是否在线"
                    },
                )

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    url = f"http://127.0.0.1:{server.server_port}/launch?token={launch}"
    if ready:
        ready(server, url)
    elif open_browser:
        webbrowser.open(url)
    timer = threading.Timer(1800, server.shutdown)
    timer.daemon = True
    timer.start()
    try:
        server.serve_forever()
    finally:
        timer.cancel()
        server.server_close()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--state", type=Path, default=DEFAULT_STATE)
    a = p.parse_args()
    if not read(a.state / "config.json"):
        raise SystemExit("请先运行 install.sh 安装连接器")
    serve(a.state)
