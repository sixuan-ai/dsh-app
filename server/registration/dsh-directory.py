#!/usr/bin/env python3
"""DSH 登录路由:用户名/邮箱 → 该用户的 DSH 实例子域名。

用户表在 `/etc/dsh-directory/users.json`,由注册服务(dsh-register.py)写入、
管理员也可手工维护:

    {
      "zhang": {
        "password": "...",          # 登录密码(本服务按明文比较)
        "email": "zhang@corp.com",  # 注册来源,可选
        "createdAt": 1789191998,    # 可选
        "subdomain": "zhang.dsh.example.com"   # 实例未开通时不存在
      }
    }

登录时可按**用户名或邮箱**提交 `username` 字段(两个都已注册过才能命中)。

新增实例 = 在记录上补 `subdomain` 并配好 vhost/证书/frp 隧道(见
OPERATIONS.md);在那之前该账号会得到 `not-provisioned`,App 据此提示
「账号已创建,等待管理员开通实例」,而不是误报密码错误。
"""
import http.server
import json
import hmac
import os
import re

LISTEN_HOST = os.environ.get("DIRECTORY_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("DIRECTORY_LISTEN_PORT", "3085"))
USERS_FILE = os.environ.get("DIRECTORY_USERS_FILE", "/etc/dsh-directory/users.json")


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


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/directory/login':
            self.send_error(404)
            return
        length = int(self.headers.get('Content-Length', 0))
        if length <= 0 or length > 64 * 1024:
            self._json(400, {'ok': False, 'error': 'bad-json'})
            return
        try:
            payload = json.loads(self.rfile.read(length) or b'{}')
        except Exception:
            self._json(400, {'ok': False, 'error': 'bad-json'})
            return

        identifier = str(payload.get('username', '')).strip()
        password = str(payload.get('password', ''))
        users = load_users()
        key, record = find_user(users, identifier)

        if record is None or not hmac.compare_digest(password, record.get('password', '')):
            self._json(401, {'ok': False, 'error': 'invalid-credentials'})
            return

        subdomain = str(record.get('subdomain') or '').strip()
        if not subdomain:
            # Credentials are right, but no instance has been provisioned yet.
            # Reported distinctly so the app can explain the real situation.
            self._json(403, {
                'ok': False,
                'error': 'not-provisioned',
                'username': key,
                'message': '账号已创建,等待管理员开通实例',
            })
            return

        self._json(200, {'ok': True, 'username': key, 'server': subdomain})

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
