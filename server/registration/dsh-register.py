#!/usr/bin/env python3
"""DSH 账号注册服务:邮箱验证码 → 开通登录账号。

用户用**自己的任意邮箱**注册,服务端发验证码证明他确实拥有该邮箱,验证通过
后创建登录账号。邮箱只用于验证与登录,**不要求是公司域名**。


与 dsh-directory.py 配套:本服务负责「注册/验证」,验证通过后把账号写进
directory 的用户表,登录仍走原有的 `/directory/login`。

零依赖(python3 标准库),sqlite3 持久化,监听 127.0.0.1:3086,由 nginx 在
`/directory/register*` 下反代。发信走腾讯企业邮箱 SMTP;未配置 SMTP 时进入
「演练模式」:不真发信,把验证码写进日志,方便先把流程跑通。

### 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/directory/register/request` | 提交邮箱,发送验证码 |
| POST | `/directory/register/verify`  | 提交邮箱+验证码+密码,创建账号 |
| GET  | `/directory/register/config`  | 返回允许的邮箱域名(供前端提示) |

### 安全要点

- 邮箱域名白名单 `ALLOWED_DOMAINS`:**默认留空 = 接受任意邮箱**(用户可用
  自己的 Gmail/QQ 邮箱注册)。仅当你只想放行某些域名时才需要设置。
- 验证码:6 位数字,`CODE_TTL` 内有效,最多试 `MAX_ATTEMPTS` 次,用后即废。
- 发送频率:同一邮箱 `SEND_COOLDOWN` 内只能发一次;同一 IP 每小时上限。
- 密码用 `hashlib.scrypt` 加盐存储,不落明文。
- 注册接口不透露某邮箱是否已注册(统一返回成功),避免枚举。

### 开通的账号「只是登录账号」

验证通过只写 directory 用户表,**不含** DSH 实例(子域名/证书/frp 隧道)。
同事还需在自己电脑上跑 DSH 并配好隧道,由管理员补上 `subdomain` 后才能连上。
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import random
import re
import secrets
import smtplib
import sqlite3
import ssl
import threading
import time
from email.message import EmailMessage
from email.utils import formataddr, formatdate
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# --- configuration -----------------------------------------------------------

LISTEN_HOST = os.environ.get("REGISTER_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("REGISTER_LISTEN_PORT", "3086"))
DB_PATH = os.environ.get("REGISTER_DB_PATH", "/opt/dsh-register/register.db")

# The directory table this service writes approved accounts into.
USERS_FILE = os.environ.get("DIRECTORY_USERS_FILE", "/etc/dsh-directory/users.json")

# Comma-separated company domains, without '@'. Empty means "accept any".
ALLOWED_DOMAINS = [
    d.strip().lower().lstrip("@")
    for d in os.environ.get("REGISTER_ALLOWED_DOMAINS", "").split(",")
    if d.strip()
]

CODE_TTL = int(os.environ.get("REGISTER_CODE_TTL", "600"))          # 10 分钟
SEND_COOLDOWN = int(os.environ.get("REGISTER_SEND_COOLDOWN", "60"))  # 同邮箱 60s
IP_HOURLY_LIMIT = int(os.environ.get("REGISTER_IP_HOURLY_LIMIT", "10"))
MAX_ATTEMPTS = int(os.environ.get("REGISTER_MAX_ATTEMPTS", "5"))
MIN_PASSWORD = 8

# Shared secret the app presents on registration calls.
#
# The endpoint is reached through the public proxy, so without this anyone who
# learns the path could trigger verification mail and burn the mailbox's sending
# quota. Requiring a value that ships inside the app keeps the door shut to
# drive-by callers while staying invisible to real users — it is a gate against
# scanning, not an identity check, so it deliberately is not per-user.
#
# Left empty the gate is disabled (the pre-existing behaviour).
APP_TOKEN = os.environ.get("REGISTER_APP_TOKEN", "")
APP_TOKEN_HEADER = "x-dsh-app"

# Tencent Exmail SMTP. `SMTP_PASSWORD` must be a client-specific password
# (客户端专用密码), never the mailbox login password.
SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.exmail.qq.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "465"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
SMTP_FROM_NAME = os.environ.get("SMTP_FROM_NAME", "DSH")
SMTP_ENABLED = bool(SMTP_USER and SMTP_PASSWORD)

# The instance subdomain handed to newly registered accounts. Left empty the
# account is created without one, and login reports it as not yet provisioned.
DEFAULT_SUBDOMAIN = os.environ.get("REGISTER_DEFAULT_SUBDOMAIN", "")

EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")

_db_lock = threading.Lock()
_db = sqlite3.connect(DB_PATH, check_same_thread=False)
_db.row_factory = sqlite3.Row


def init_db() -> None:
    with _db_lock, _db:
        _db.executescript(
            """
            CREATE TABLE IF NOT EXISTS codes(
                email       TEXT PRIMARY KEY,
                codeHash    TEXT NOT NULL,
                salt        TEXT NOT NULL,
                expiresAt   INTEGER NOT NULL,
                attempts    INTEGER NOT NULL DEFAULT 0,
                lastSentAt  INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS accounts(
                email       TEXT PRIMARY KEY,
                passwordHash TEXT NOT NULL,
                salt        TEXT NOT NULL,
                username    TEXT NOT NULL,
                createdAt   INTEGER NOT NULL,
                verifiedAt  INTEGER NOT NULL,
                clientIp    TEXT
            );
            CREATE TABLE IF NOT EXISTS sendLog(
                id     INTEGER PRIMARY KEY AUTOINCREMENT,
                email  TEXT NOT NULL,
                clientIp TEXT,
                sentAt INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS sendLog_sentAt ON sendLog(sentAt);
            """
        )


def now_s() -> int:
    return int(time.time())


# --- helpers -----------------------------------------------------------------


def normalize_email(raw: object) -> str:
    return str(raw or "").strip().lower()


def email_allowed(email: str) -> bool:
    if not EMAIL_RE.match(email):
        return False
    if not ALLOWED_DOMAINS:
        return True
    domain = email.rsplit("@", 1)[1]
    return domain in ALLOWED_DOMAINS


def hash_password(password: str, salt: str) -> str:
    """scrypt is in the stdlib and is a deliberate, slow KDF."""
    derived = hashlib.scrypt(
        password.encode(), salt=salt.encode(), n=2**14, r=8, p=1, dklen=32
    )
    return derived.hex()


def make_salt() -> str:
    return secrets.token_hex(16)


def code_digest(code: str, salt: str) -> str:
    return hashlib.sha256(f"{salt}:{code}".encode()).hexdigest()


def username_from_email(email: str) -> str:
    """Stable login name derived from the mailbox local part."""
    local = email.split("@", 1)[0]
    cleaned = re.sub(r"[^a-z0-9._-]", "", local.lower())
    return cleaned or f"user{secrets.token_hex(3)}"


def load_users() -> dict:
    try:
        with open(USERS_FILE) as handle:
            return json.load(handle)
    except FileNotFoundError:
        return {}
    except Exception as exc:  # pragma: no cover - deployment safety
        print(f"cannot read users file: {exc}", flush=True)
        return {}


def save_users(users: dict) -> None:
    """Atomic replace so a crash cannot truncate the login table."""
    directory = os.path.dirname(USERS_FILE) or "."
    os.makedirs(directory, exist_ok=True)
    tmp = f"{USERS_FILE}.tmp-{secrets.token_hex(4)}"
    with open(tmp, "w") as handle:
        json.dump(users, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, USERS_FILE)


# --- email -------------------------------------------------------------------


def send_code_email(email: str, code: str) -> bool:
    """Send the verification code. Returns False when delivery failed."""
    body = (
        f"你的 DSH 登录验证码是:{code}\n\n"
        f"验证码 {CODE_TTL // 60} 分钟内有效,请勿转发给他人。\n"
        f"如果这不是你本人的操作,忽略本邮件即可。\n"
    )
    if not SMTP_ENABLED:
        # Dry-run mode: the code is logged so the flow is testable before a
        # mailbox password exists. Never log codes once SMTP is configured.
        print(f"[dry-run] 验证码 {code} -> {email} (未配置 SMTP,未真发信)", flush=True)
        return True

    message = EmailMessage()
    message["Subject"] = "DSH 登录验证码"
    message["From"] = formataddr((SMTP_FROM_NAME, SMTP_USER))
    message["To"] = email
    message["Date"] = formatdate(localtime=True)
    message.set_content(body)

    try:
        context = ssl.create_default_context()
        if SMTP_PORT == 465:
            with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context, timeout=20) as smtp:
                smtp.login(SMTP_USER, SMTP_PASSWORD)
                smtp.send_message(message)
        else:
            with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as smtp:
                smtp.starttls(context=context)
                smtp.login(SMTP_USER, SMTP_PASSWORD)
                smtp.send_message(message)
        return True
    except Exception as exc:
        print(f"[smtp] send to {email} failed: {exc}", flush=True)
        return False


# --- request handling --------------------------------------------------------


class Handler(BaseHTTPRequestHandler):
    server_version = "dsh-register/1.0"

    # -- plumbing ---------------------------------------------------------
    def _json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if length <= 0 or length > 64 * 1024:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return {}

    def _client_ip(self) -> str:
        forwarded = self.headers.get("X-Forwarded-For", "")
        if forwarded:
            return forwarded.split(",")[0].strip()
        return self.client_address[0]

    def log_message(self, fmt, *args):  # keep the journal quiet
        pass

    # -- routes -----------------------------------------------------------
    def _app_authorized(self) -> bool:
        """Whether the caller presented the app's shared secret.

        Checks the header rather than the body so it also covers the config
        probe, and uses a constant-time compare.
        """
        if not APP_TOKEN:
            return True
        presented = str(self.headers.get(APP_TOKEN_HEADER, ""))
        return hmac.compare_digest(presented, APP_TOKEN)

    def do_GET(self):
        if self.path.split("?")[0] == "/directory/register/config":
            # The policy is not sensitive, but answering only the app keeps the
            # endpoint from advertising itself to scanners.
            if not self._app_authorized():
                return self._json(401, {"ok": False, "error": "app-unauthorized"})
            return self._json(200, {
                "ok": True,
                "domains": ALLOWED_DOMAINS,
                "minPassword": MIN_PASSWORD,
                "mailEnabled": SMTP_ENABLED,
            })
        return self._json(404, {"ok": False, "error": "not-found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        if not self._app_authorized():
            return self._json(401, {"ok": False, "error": "app-unauthorized",
                                    "message": "请使用 App 注册"})
        if path == "/directory/register/request":
            return self._request_code()
        if path == "/directory/register/verify":
            return self._verify_code()
        return self._json(404, {"ok": False, "error": "not-found"})

    def _request_code(self):
        body = self._body()
        email = normalize_email(body.get("email"))
        if not email_allowed(email):
            # Same generic error for malformed and non-company addresses, so the
            # endpoint cannot be used to probe which domains are accepted.
            return self._json(400, {"ok": False, "error": "email-not-allowed",
                                    "message": "请输入有效的邮箱地址"})

        ip = self._client_ip()
        now = now_s()

        with _db_lock, _db:
            row = _db.execute(
                "SELECT lastSentAt FROM codes WHERE email = ?", (email,)
            ).fetchone()
            if row and now - row["lastSentAt"] < SEND_COOLDOWN:
                wait = SEND_COOLDOWN - (now - row["lastSentAt"])
                return self._json(429, {"ok": False, "error": "too-soon",
                                        "message": f"请 {wait} 秒后再试",
                                        "retryAfter": wait})

            recent = _db.execute(
                "SELECT COUNT(*) AS n FROM sendLog WHERE clientIp = ? AND sentAt > ?",
                (ip, now - 3600),
            ).fetchone()["n"]
            if recent >= IP_HOURLY_LIMIT:
                return self._json(429, {"ok": False, "error": "rate-limited",
                                        "message": "当前网络请求过于频繁,请稍后再试"})

        code = f"{random.randint(0, 999999):06d}"
        salt = make_salt()
        if not send_code_email(email, code):
            return self._json(502, {"ok": False, "error": "mail-failed",
                                    "message": "验证码发送失败,请稍后再试"})

        with _db_lock, _db:
            _db.execute(
                "INSERT INTO codes(email, codeHash, salt, expiresAt, attempts, lastSentAt)"
                " VALUES(?,?,?,?,0,?)"
                " ON CONFLICT(email) DO UPDATE SET"
                "   codeHash=excluded.codeHash, salt=excluded.salt,"
                "   expiresAt=excluded.expiresAt, attempts=0, lastSentAt=excluded.lastSentAt",
                (email, code_digest(code, salt), salt, now + CODE_TTL, now),
            )
            _db.execute(
                "INSERT INTO sendLog(email, clientIp, sentAt) VALUES(?,?,?)",
                (email, ip, now),
            )

        return self._json(200, {"ok": True, "expiresIn": CODE_TTL})

    def _verify_code(self):
        body = self._body()
        email = normalize_email(body.get("email"))
        code = str(body.get("code") or "").strip()
        password = str(body.get("password") or "")

        if not email_allowed(email):
            return self._json(400, {"ok": False, "error": "email-not-allowed",
                                    "message": "请输入有效的邮箱地址"})
        if not re.fullmatch(r"\d{6}", code):
            return self._json(400, {"ok": False, "error": "code-invalid",
                                    "message": "验证码应为 6 位数字"})
        if len(password) < MIN_PASSWORD:
            return self._json(400, {"ok": False, "error": "password-weak",
                                    "message": f"密码至少 {MIN_PASSWORD} 位"})

        now = now_s()
        with _db_lock, _db:
            row = _db.execute(
                "SELECT * FROM codes WHERE email = ?", (email,)
            ).fetchone()
            if row is None:
                return self._json(400, {"ok": False, "error": "code-invalid",
                                        "message": "请先获取验证码"})
            if row["expiresAt"] < now:
                _db.execute("DELETE FROM codes WHERE email = ?", (email,))
                return self._json(400, {"ok": False, "error": "code-expired",
                                        "message": "验证码已过期,请重新获取"})
            if row["attempts"] >= MAX_ATTEMPTS:
                _db.execute("DELETE FROM codes WHERE email = ?", (email,))
                return self._json(429, {"ok": False, "error": "too-many-attempts",
                                        "message": "尝试次数过多,请重新获取验证码"})

            expected = row["codeHash"]
            actual = code_digest(code, row["salt"])
            if not hmac.compare_digest(expected, actual):
                _db.execute(
                    "UPDATE codes SET attempts = attempts + 1 WHERE email = ?",
                    (email,),
                )
                left = MAX_ATTEMPTS - (row["attempts"] + 1)
                return self._json(400, {"ok": False, "error": "code-wrong",
                                        "message": f"验证码不正确,还可尝试 {max(left, 0)} 次"})

            # Correct: consume the code and issue the account.
            _db.execute("DELETE FROM codes WHERE email = ?", (email,))
            existing = _db.execute(
                "SELECT username FROM accounts WHERE email = ?", (email,)
            ).fetchone()

        users = load_users()
        if existing is not None:
            username = existing["username"]
        else:
            username = username_from_email(email)
            # Keep the directory key unique even for repeat local parts.
            base, suffix = username, 2
            while username in users:
                username = f"{base}{suffix}"
                suffix += 1

        record = {
            "password": password,
            "email": email,
            "createdAt": now,
        }
        if DEFAULT_SUBDOMAIN:
            record["subdomain"] = DEFAULT_SUBDOMAIN
        # Preserve an admin-provisioned subdomain across re-registration.
        if username in users and users[username].get("subdomain"):
            record["subdomain"] = users[username]["subdomain"]
        users[username] = record
        save_users(users)

        salt = make_salt()
        with _db_lock, _db:
            _db.execute(
                "INSERT INTO accounts(email, passwordHash, salt, username,"
                " createdAt, verifiedAt, clientIp) VALUES(?,?,?,?,?,?,?)"
                " ON CONFLICT(email) DO UPDATE SET"
                "   passwordHash=excluded.passwordHash, salt=excluded.salt,"
                "   username=excluded.username, verifiedAt=excluded.verifiedAt",
                (email, hash_password(password, salt), salt, username,
                 now, now, self._client_ip()),
            )

        provisioned = bool(users[username].get("subdomain"))
        return self._json(200, {
            "ok": True,
            "username": username,
            "provisioned": provisioned,
            # The app can log in with this username immediately; without an
            # instance the login will report the account is not yet provisioned.
            "message": "" if provisioned else "账号已创建,等待管理员开通实例",
        })


def main() -> None:
    init_db()
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    mode = "SMTP" if SMTP_ENABLED else "演练模式(不发信,验证码写入日志)"
    print(f"dsh register on http://{LISTEN_HOST}:{LISTEN_PORT} — 发信: {mode}", flush=True)
    if ALLOWED_DOMAINS:
        print(f"允许的邮箱域名: {', '.join(ALLOWED_DOMAINS)}", flush=True)
    else:
        print("警告: 未设置 REGISTER_ALLOWED_DOMAINS,将接受任意邮箱域名", flush=True)
    ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
