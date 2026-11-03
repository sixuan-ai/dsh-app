#!/usr/bin/env python3
"""Isolated transport and failure-path tests; never touches deployed services."""

import base64
import concurrent.futures
import http.client
import http.server
import json
import os
import secrets
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
import uuid
from pathlib import Path

from connector import atomic, fingerprint, tls_get

SOURCE = Path(__file__).parent


def freeport():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def basic(user, password):
    return "Basic " + base64.b64encode((user + ":" + password).encode()).decode()


class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.headers.get("Authorization") != "Basic YnJpZGdlOnNlY3JldA==":
            self.send_error(401)
            return
        if self.headers.get("Cookie"):
            self.send_error(400)
            return
        if self.headers.get("Upgrade") == "websocket":
            self.send_response(101)
            self.send_header("Connection", "Upgrade")
            self.send_header("Upgrade", "websocket")
            self.send_header("Set-Cookie", "upstream=secret")
            self.end_headers()
            self.wfile.write(b"\x81\x05hello")
            self.wfile.flush()
            while True:
                b = self.connection.recv(4096)
                if not b:
                    return
                self.connection.sendall(b)
        else:
            data = json.dumps({"path": self.path}).encode()
            self.send_response(200)
            self.send_header("Set-Cookie", "upstream=secret")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)


class ConnectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.tmp.name)
        cls.gateway_port = freeport()
        cls.hub_port = freeport()
        cls.up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        cls.up.daemon_threads = True
        threading.Thread(target=cls.up.serve_forever, daemon=True).start()
        cls.config = {
            "version": 1,
            "nodeId": str(uuid.uuid4()),
            "name": "测试电脑",
            "listenHost": "127.0.0.1",
            "port": cls.gateway_port,
            "tlsKey": str(cls.root / "key.pem"),
            "tlsCert": str(cls.root / "cert.pem"),
            "enrollmentSecret": secrets.token_hex(32),
            "upstreamHost": "127.0.0.1",
            "upstreamPort": cls.up.server_port,
            "upstreamAuthorization": "Basic YnJpZGdlOnNlY3JldA==",
        }
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "ec",
                "-pkeyopt",
                "ec_paramgen_curve:P-256",
                "-nodes",
                "-keyout",
                cls.config["tlsKey"],
                "-out",
                cls.config["tlsCert"],
                "-days",
                "1",
                "-subj",
                "/CN=localhost",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        atomic(cls.root / "config.json", cls.config)
        atomic(cls.root / "devices.json", {"version": 1, "devices": []})
        atomic(cls.root / "pairings.json", {"version": 1, "pairings": []})
        atomic(
            cls.root / "users.json",
            {
                "alice": {"password": "test-password"},
                "bob": {"password": "other-password"},
            },
        )
        cls.pin = fingerprint(cls.config)
        cls.origin = f"https://127.0.0.1:{cls.gateway_port}"
        cls.log = open(cls.root / "process.log", "w")
        cls.node = subprocess.Popen(
            ["node", str(SOURCE / "gateway.js")],
            env={**os.environ, "XHARNESS_CONFIG": str(cls.root / "config.json")},
            stdout=cls.log,
            stderr=cls.log,
        )
        cls.hub = subprocess.Popen(
            ["python3", str(SOURCE / "hub.py")],
            env={
                **os.environ,
                "CONNECTOR_USERS_FILE": str(cls.root / "users.json"),
                "CONNECTOR_REGISTRY_FILE": str(cls.root / "registry.json"),
                "CONNECTOR_HUB_PORT": str(cls.hub_port),
                "CONNECTOR_TEST_LOOPBACK": "1",
                "CONNECTOR_PUBLIC_ORIGIN": "https://gateway.example",
            },
            stdout=cls.log,
            stderr=cls.log,
        )
        for port in [cls.gateway_port, cls.hub_port]:
            for _ in range(100):
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                        break
                except OSError:
                    time.sleep(0.05)
            else:
                raise RuntimeError("server failed to start")

    @classmethod
    def tearDownClass(cls):
        for p in [cls.node, cls.hub]:
            p.terminate()
            p.wait(timeout=6)
        cls.up.shutdown()
        cls.up.server_close()
        cls.log.close()
        cls.tmp.cleanup()

    def request(self, path, method="GET", data=None, auth=None, hub=False, cookie=None):
        if hub:
            c = http.client.HTTPConnection("127.0.0.1", self.hub_port, timeout=4)
        else:
            c = http.client.HTTPSConnection(
                "127.0.0.1",
                self.gateway_port,
                context=ssl._create_unverified_context(),
                timeout=4,
            )
        headers = {}
        if auth:
            headers["Authorization"] = auth
        if cookie:
            headers["Cookie"] = cookie
        c.request(
            method,
            path,
            json.dumps(data).encode() if data is not None else None,
            headers,
        )
        r = c.getresponse()
        body = r.read()
        result = (r.status, json.loads(body) if body else {}, dict(r.getheaders()))
        c.close()
        return result

    def fresh_pair(self, expired=False):
        payload = {
            "id": uuid.uuid4().hex,
            "code": secrets.token_urlsafe(32),
            "expiresAt": int(time.time() * 1000) + (-1000 if expired else 120000),
        }
        atomic(self.root / "pairings.json", {"version": 1, "pairings": [payload]})
        return payload

    def device(self):
        payload = self.fresh_pair()
        status, d, _ = self.request("/connector/pair", "POST", payload)
        self.assertEqual(status, 200)
        return d, basic(d["username"], d["password"])

    def enroll_data(self):
        return {
            **{
                k: self.config[k]
                for k in ["nodeId", "name", "port", "enrollmentSecret"]
            },
            "address": "127.0.0.1",
            "fingerprint": self.pin,
        }

    def enroll(self):
        status, d, _ = self.request(
            "/connector/enroll",
            "POST",
            self.enroll_data(),
            basic("alice", "test-password"),
            True,
        )
        self.assertEqual(status, 200)
        return "/connector/" + self.config["nodeId"]

    def ws(self, path, auth, hub=False):
        s = socket.create_connection(
            ("127.0.0.1", self.hub_port if hub else self.gateway_port), timeout=4
        )
        if not hub:
            s = ssl._create_unverified_context().wrap_socket(
                s, server_hostname="localhost"
            )
        s.sendall(
            (
                "GET "
                + path
                + " HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nAuthorization: "
                + auth
                + "\r\nCookie: upstream=must-not-forward\r\n\r\n"
            ).encode()
        )
        head = b""
        while not head.endswith(b"\r\n\r\n"):
            head += s.recv(1)
        return s, head

    def test_01_pair_once_concurrent_and_hash_only(self):
        p = self.fresh_pair()
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            results = list(
                pool.map(lambda _: self.request("/connector/pair", "POST", p), range(2))
            )
        self.assertEqual(sorted(r[0] for r in results), [200, 403])
        d = next(r[1] for r in results if r[0] == 200)
        stored = (self.root / "devices.json").read_text()
        self.assertNotIn(d["password"], stored)
        self.assertNotIn(p["code"], (self.root / "pairings.json").read_text())
        self.assertEqual((self.root / "devices.json").stat().st_mode & 0o777, 0o600)

    def test_02_expired_and_wrong_code(self):
        self.assertEqual(
            self.request("/connector/pair", "POST", self.fresh_pair(True))[0], 403
        )
        p = self.fresh_pair()
        p["code"] = "x" * 43
        self.assertEqual(self.request("/connector/pair", "POST", p)[0], 403)

    def test_03_http_auth_cookie_isolation_and_revocation(self):
        d, auth = self.device()
        self.assertEqual(self.request("/api/test")[0], 401)
        status, body, headers = self.request(
            "/api/test?x=1", auth=auth, cookie="upstream=forbidden"
        )
        self.assertEqual(status, 200)
        self.assertEqual(body["path"], "/api/test?x=1")
        self.assertNotIn("Set-Cookie", headers)
        store = json.loads((self.root / "devices.json").read_text())
        next(v for v in store["devices"] if v["id"] == d["username"])["revoked"] = True
        atomic(self.root / "devices.json", store)
        self.assertEqual(self.request("/api/test", auth=auth)[0], 401)

    def test_04_pinned_certificate(self):
        self.assertEqual(tls_get(self.origin + "/connector/info", self.pin)[0], 200)
        with self.assertRaisesRegex(ValueError, "certificate"):
            tls_get(self.origin + "/connector/info", "0" * 64)

    def test_05_public_owner_and_pin_proof(self):
        path = self.enroll()
        self.assertEqual(
            self.request(path + "/connector/info", hub=True)[1]["nodeId"],
            self.config["nodeId"],
        )
        self.assertEqual(
            self.request(
                "/connector/enroll",
                "POST",
                self.enroll_data(),
                basic("bob", "other-password"),
                True,
            )[0],
            403,
        )
        bad = self.enroll_data()
        bad["fingerprint"] = "0" * 64
        self.assertEqual(
            self.request(
                "/connector/enroll", "POST", bad, basic("alice", "test-password"), True
            )[0],
            400,
        )
        bad = self.enroll_data()
        bad["enrollmentSecret"] = "0" * 64
        self.assertEqual(
            self.request(
                "/connector/enroll", "POST", bad, basic("alice", "test-password"), True
            )[0],
            400,
        )
        bad = self.enroll_data()
        bad["address"] = "169.254.169.254"
        self.assertEqual(
            self.request(
                "/connector/enroll", "POST", bad, basic("alice", "test-password"), True
            )[0],
            400,
        )

    def test_06_public_prefix_credentials_and_private_endpoints(self):
        path = self.enroll()
        d, auth = self.device()
        status, body, headers = self.request(
            path + "/api/test?keep=1", auth=auth, hub=True
        )
        self.assertEqual(status, 200)
        self.assertEqual(body["path"], "/api/test?keep=1")
        self.assertNotIn("Set-Cookie", headers)
        self.assertEqual(
            self.request(
                path + "/api/test", auth=basic("alice", "test-password"), hub=True
            )[0],
            401,
        )
        self.assertEqual(
            self.request(path + "/connector/pair", "POST", {}, auth, True)[0], 404
        )

    def test_07_local_and_public_ws_first_frame_and_active_revocation(self):
        path = self.enroll()
        for public in [False, True]:
            d, auth = self.device()
            s, head = self.ws((path if public else "") + "/api/live", auth, public)
            try:
                self.assertIn(b"101", head)
                self.assertNotIn(b"set-cookie", head.lower())
                self.assertEqual(s.recv(7), b"\x81\x05hello")
                s.sendall(b"\x81\x02ok")
                self.assertEqual(s.recv(4), b"\x81\x02ok")
                store = json.loads((self.root / "devices.json").read_text())
                next(v for v in store["devices"] if v["id"] == d["username"])[
                    "revoked"
                ] = True
                atomic(self.root / "devices.json", store)
                s.settimeout(3)
                self.assertEqual(s.recv(1), b"")
            finally:
                s.close()

    def test_08_account_removed_disables_public_route(self):
        path = self.enroll()
        users = json.loads((self.root / "users.json").read_text())
        atomic(self.root / "users.json", {"bob": users["bob"]})
        try:
            self.assertEqual(self.request(path + "/connector/info", hub=True)[0], 404)
        finally:
            atomic(self.root / "users.json", users)

    def test_09_unregister_owner_only(self):
        path = self.enroll()
        url = "/connector/enroll/" + self.config["nodeId"]
        self.assertEqual(
            self.request(url, "DELETE", auth=basic("bob", "other-password"), hub=True)[
                0
            ],
            404,
        )
        self.assertEqual(
            self.request(url, "DELETE", auth=basic("alice", "test-password"), hub=True)[
                0
            ],
            200,
        )
        self.assertEqual(self.request(path + "/connector/info", hub=True)[0], 404)


class DesktopAndAccountsTests(ConnectorTests):
    # Reuse the transport fixture and repeat transport coverage after UI/account work.
    def test_10_desktop_launch_cookie_csrf_and_pair_qr(self):
        from desktop import serve

        self.config["dshPort"] = self.up.server_port
        atomic(self.root / "config.json", self.config)
        ready = threading.Event()
        context = {}

        def callback(server, url):
            context.update(server=server, url=url)
            ready.set()

        worker = threading.Thread(
            target=serve, args=(self.root, False, callback), daemon=True
        )
        worker.start()
        self.assertTrue(ready.wait(3))
        server = context["server"]
        port = server.server_port

        def request(path, method="GET", data=None, cookie="", origin=None, host=None):
            c = http.client.HTTPConnection("127.0.0.1", port, timeout=8)
            headers = {"Cookie": cookie, "Host": host or f"127.0.0.1:{port}"}
            if origin:
                headers["Origin"] = origin
            c.request(
                method,
                path,
                json.dumps(data).encode() if data is not None else None,
                headers,
            )
            r = c.getresponse()
            body = r.read()
            result = r.status, dict(r.getheaders()), body
            c.close()
            return result

        try:
            self.assertEqual(request("/")[0], 403)
            launch = context["url"].split(f":{port}", 1)[1]
            status, headers, _ = request(launch)
            self.assertEqual(status, 303)
            cookie = headers["Set-Cookie"].split(";", 1)[0]
            self.assertIn("HttpOnly", headers["Set-Cookie"])
            self.assertEqual(request(launch)[0], 403)
            self.assertEqual(request("/", cookie=cookie)[0], 200)
            self.assertEqual(
                request("/", cookie=cookie, host="attacker.example")[0], 403
            )
            self.assertEqual(
                request(
                    "/pair",
                    "POST",
                    {"host": "127.0.0.1"},
                    cookie,
                    "http://attacker.example",
                )[0],
                403,
            )
            status, headers, body = request(
                "/pair",
                "POST",
                {"host": "127.0.0.1"},
                cookie,
                f"http://127.0.0.1:{port}",
            )
            self.assertEqual(status, 200)
            self.assertTrue(
                json.loads(body)["link"].startswith("xharness://pair?data=")
            )
            self.assertEqual(request("/qr.svg", cookie=cookie)[0], 200)
            status, headers, body = request("/status", cookie=cookie)
            self.assertEqual(status, 200)
            self.assertNotIn(self.config["enrollmentSecret"].encode(), body)
        finally:
            server.shutdown()
            server.server_close()
            worker.join(3)

    def test_11_account_verifier_export_without_plaintext_and_password_change(self):
        import hub
        from sync_accounts import export

        target = self.root / "export" / "accounts.json"
        export(self.root / "users.json", target, None)
        value = json.loads(target.read_text())
        self.assertNotIn("test-password", target.read_text())
        self.assertEqual(value["alice"]["algorithm"], "pbkdf2-sha256")
        original = hub.USERS
        hub.USERS = target
        try:
            self.assertEqual(hub.account(basic("alice", "test-password")), "alice")
            self.assertIsNone(hub.account(basic("alice", "wrong-password")))
            atomic(
                self.root / "changed-users.json",
                {"alice": {"password": "changed-password"}},
            )
            export(self.root / "changed-users.json", target, None)
            self.assertIsNone(hub.account(basic("alice", "test-password")))
            self.assertEqual(hub.account(basic("alice", "changed-password")), "alice")
            self.assertNotIn("bob", json.loads(target.read_text()))
        finally:
            hub.USERS = original

    def test_12_export_preserves_existing_directory_permissions(self):
        folder = self.root / "user-output"
        folder.mkdir(mode=0o755)
        folder.chmod(0o755)
        atomic(folder / "pairing.json", {"test": "synthetic"})
        from sync_accounts import export

        export(self.root / "users.json", folder / "account-verifiers.json", None)
        self.assertEqual(folder.stat().st_mode & 0o777, 0o755)
        self.assertEqual((folder / "pairing.json").stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main(verbosity=2)
