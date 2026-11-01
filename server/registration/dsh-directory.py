#!/usr/bin/env python3
"""DSH 登录路由:用户名/邮箱 → 该账号名下的电脑列表。

用户表在 `/etc/dsh-directory/users.json`,由注册服务(dsh-register.py)写入、
管理员也可手工维护。一个账号可以有**多台电脑**:

    {
      "x": {
        "password": "...",
        "email": "sixuan@ainotex.com",
        "createdAt": 1789191998,
        "computers": [
          { "id": "omen", "name": "OMEN 笔记本", "subdomain": "dsh.ainotex.com",
            "default": true },
          { "id": "mac",  "name": "MacBook",     "subdomain": "mac.dsh.ainotex.com" }
        ]
      }
    }

**向后兼容**:老记录把 `subdomain` 放顶层(没有 `computers` 数组),等价于只有
一台电脑,仍按原样工作;老客户端读 `server` 字段仍能登录。

登录时可按**用户名或邮箱**提交 `username` 字段(两个都已注册过才能命中)。

新增实例 = 在 `computers` 里加一项并配好 vhost/证书/frp 隧道(见
OPERATIONS.md);在那之前该电脑**不会**出现在列表里(`subdomain` 留空的项被
省略),App 只显示已开通的。
"""
import http.server
import json
import hmac
import os
import re
import base64
import binascii

LISTEN_HOST = os.environ.get("DIRECTORY_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("DIRECTORY_LISTEN_PORT", "3085"))
USERS_FILE = os.environ.get("DIRECTORY_USERS_FILE", "/etc/dsh-directory/users.json")
BACKENDS_FILE = os.environ.get("DIRECTORY_BACKENDS_FILE", "/etc/dsh-directory/backends.json")


def password_matches(password, record):
    return isinstance(record, dict) and hmac.compare_digest(
        password.encode('utf-8'), str(record.get('password', '')).encode('utf-8'))


def load_users():
    try:
        with open(USERS_FILE) as f:
            return json.load(f)
    except Exception as e:
        print('cannot read users file:', e, flush=True)
        return {}


def find_user(users, identifier):
    """Resolve a username or email to (key, record).

    The table is keyed by username; registration also stores the mailbox so a
    user can sign in with either form.
    """
    if not identifier:
        return None, None
    record = users.get(identifier)
    if record is not None:
        return identifier, record
    lowered = identifier.lower()
    for key, value in users.items():
        if str(value.get('email', '')).lower() == lowered:
            return key, value
    return None, None


def account_computers(record):
    """Normalized list of this account's computers.

    Each entry: {id, name, subdomain, default}. A legacy top-level `subdomain`
    folds into a single implicit computer so old records keep working.
    Entries without a subdomain are omitted (instance not yet provisioned).
    """
    out = []
    raw = record.get('computers')
    if isinstance(raw, list):
        for i, c in enumerate(raw):
            if not isinstance(c, dict):
                continue
            subdomain = str(c.get('subdomain') or '').strip()
            if not subdomain:
                continue
            out.append({
                'id': str(c.get('id') or f'machine-{i}'),
                'name': str(c.get('name') or c.get('id') or f'电脑 {i + 1}'),
                'subdomain': subdomain,
                'default': bool(c.get('default', False)),
            })
    else:
        subdomain = str(record.get('subdomain') or '').strip()
        if subdomain:
            out.append({
                'id': 'default',
                'name': '默认电脑',
                'subdomain': subdomain,
                'default': True,
            })
    if out and not any(c['default'] for c in out):
        out[0]['default'] = True
    return out


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Only called by nginx's internal auth_request location. This path is
        # deliberately outside /directory/, which is exposed publicly.
        if self.path != '/internal/auth':
            return self._json(404, {'ok': False, 'error': 'not-found'})
        try:
            scheme, encoded = self.headers.get('Authorization', '').split(' ', 1)
            if scheme.lower() != 'basic':
                raise ValueError('basic required')
            identifier, password = base64.b64decode(encoded, validate=True).decode('utf-8').split(':', 1)
        except (ValueError, UnicodeError, binascii.Error):
            return self._auth_result(401)
        _, record = find_user(load_users(), identifier)
        if not password_matches(password, record):
            return self._auth_result(401)
        computers = account_computers(record)
        target = self.headers.get('X-DSH-Target', '')
        if target == '@shared':
            return self._auth_result(204 if computers else 403)
        if not any(c['subdomain'] == target for c in computers):
            return self._auth_result(403)
        try:
            with open(BACKENDS_FILE) as handle:
                backend = json.load(handle)[target]
            credential = base64.b64encode(
                (backend['username'] + ':' + backend['password']).encode('utf-8')).decode('ascii')
        except (OSError, ValueError, KeyError, TypeError):
            return self._auth_result(503)
        return self._auth_result(204, 'Basic ' + credential)

    def _auth_result(self, status, backend_auth=None):
        self.send_response(status)
        if status == 401:
            self.send_header('WWW-Authenticate', 'Basic realm="DSH account", charset="UTF-8"')
        if backend_auth:
            self.send_header('X-DSH-Backend-Authorization', backend_auth)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_POST(self):
        path = self.path.split('?')[0]
        length = int(self.headers.get('Content-Length', 0))
        if length <= 0 or length > 64 * 1024:
            self._json(400, {'ok': False, 'error': 'bad-json'})
            return
        try:
            payload = json.loads(self.rfile.read(length) or b'{}')
        except Exception:
            self._json(400, {'ok': False, 'error': 'bad-json'})
            return

        if path == '/directory/login':
            return self._login(payload)
        if path == '/directory/resolve':
            return self._resolve(payload)
        self._json(404, {'ok': False, 'error': 'not-found'})

    def _login(self, payload):
        identifier = str(payload.get('username', '')).strip()
        password = str(payload.get('password', ''))
        users = load_users()
        key, record = find_user(users, identifier)

        if not password_matches(password, record):
            self._json(401, {'ok': False, 'error': 'invalid-credentials'})
            return

        computers = account_computers(record)
        if not computers:
            # Credentials are right, but no instance has been provisioned yet.
            # Reported distinctly so the app can explain the real situation.
            self._json(403, {
                'ok': False,
                'error': 'not-provisioned',
                'username': key,
                'message': '账号已创建,等待管理员开通实例',
            })
            return

        default = next((c for c in computers if c['default']), computers[0])
        self._json(200, {
            'ok': True,
            'username': key,
            # Legacy field: the default computer, so old clients still work.
            'server': default['subdomain'],
            # New: the full list for the multi-machine picker.
            'computers': computers,
        })

    def _resolve(self, payload):
        """Resolve one of this account's computers to its subdomain."""
        identifier = str(payload.get('username', '')).strip()
        password = str(payload.get('password', ''))
        computer_id = str(payload.get('computerId', '')).strip()
        users = load_users()
        key, record = find_user(users, identifier)

        if not password_matches(password, record):
            self._json(401, {'ok': False, 'error': 'invalid-credentials'})
            return

        computers = account_computers(record)
        if not computers:
            self._json(403, {
                'ok': False,
                'error': 'not-provisioned',
                'username': key,
                'message': '账号已创建,等待管理员开通实例',
            })
            return

        match = None
        if computer_id:
            match = next((c for c in computers if c['id'] == computer_id), None)
        else:
            match = next((c for c in computers if c['default']), computers[0])
        if match is None:
            self._json(404, {'ok': False, 'error': 'unknown-computer'})
            return

        self._json(200, {
            'ok': True,
            'username': key,
            'computer': match,
        })

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == '__main__':
    server = http.server.ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f'dsh directory on http://{LISTEN_HOST}:{LISTEN_PORT}', flush=True)
    server.serve_forever()
