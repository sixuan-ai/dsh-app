#!/usr/bin/env python3
"""DSH App 社交服务:注册身份、8 位好友码加好友、等级排名、私聊、社区动态。

零依赖(python3 标准库),sqlite3 持久化,监听 127.0.0.1:9981,由 nginx
在 /social/ 下反代并负责外层 Basic 认证。应用内身份用注册时签发的
x-social-token 头;等级由客户端上报 promptCount,服务端按与 App 相同的
阈值表折算等级称号,排名只认服务端最后一次上报值。
"""

import base64
import json
import re
import secrets
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 9981
DB_PATH = "/opt/dsh-social/social.db"

MAX_NICKNAME = 24
MAX_TEXT = 2000
MAX_PAGE = 50

LEVELS = [
    (0, "新手"), (5, "学徒"), (15, "熟手"), (30, "老手"), (60, "行家"),
    (100, "专家"), (160, "大师"), (250, "宗师"), (400, "传奇"), (600, "永恒"),
]

_db_lock = threading.Lock()
_db = sqlite3.connect(DB_PATH, check_same_thread=False)
_db.row_factory = sqlite3.Row


def init_db():
    with _db_lock, _db:
        _db.executescript(
            """
            CREATE TABLE IF NOT EXISTS users(
                userId TEXT PRIMARY KEY,
                nickname TEXT NOT NULL,
                friendCode TEXT UNIQUE NOT NULL,
                token TEXT UNIQUE NOT NULL,
                promptCount INTEGER NOT NULL DEFAULT 0,
                createdAt INTEGER NOT NULL,
                lastSeen INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS friends(
                userId TEXT NOT NULL,
                friendId TEXT NOT NULL,
                createdAt INTEGER NOT NULL,
                PRIMARY KEY(userId, friendId)
            );
            CREATE TABLE IF NOT EXISTS messages(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fromId TEXT NOT NULL,
                toId TEXT NOT NULL,
                text TEXT NOT NULL,
                time INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_messages_pair
                ON messages(fromId, toId, id);
            CREATE TABLE IF NOT EXISTS reads(
                userId TEXT NOT NULL,
                peer TEXT NOT NULL,
                lastReadId INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(userId, peer)
            );
            CREATE TABLE IF NOT EXISTS posts(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId TEXT NOT NULL,
                kind TEXT NOT NULL DEFAULT 'text',
                text TEXT NOT NULL,
                levelInfo TEXT,
                time INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS likes(
                postId INTEGER NOT NULL,
                userId TEXT NOT NULL,
                PRIMARY KEY(postId, userId)
            );
            CREATE TABLE IF NOT EXISTS avatars(
                userId TEXT PRIMARY KEY,
                mime TEXT NOT NULL,
                data BLOB NOT NULL,
                updatedAt INTEGER NOT NULL
            );
            """
        )


def avatar_ver(user_id):
    with _db_lock:
        row = _db.execute(
            "SELECT updatedAt FROM avatars WHERE userId = ?", (user_id,)
        ).fetchone()
    return row["updatedAt"] if row else 0


def now_ms():
    return int(time.time() * 1000)


def level_for(count):
    level, title = 1, LEVELS[0][1]
    for i, (floor, name) in enumerate(LEVELS):
        if count >= floor:
            level, title = i + 1, name
    return level, title


def public_user(row, with_code=False):
    level, title = level_for(row["promptCount"])
    out = {
        "userId": row["userId"],
        "nickname": row["nickname"],
        "promptCount": row["promptCount"],
        "level": level,
        "title": title,
        "avatarVer": avatar_ver(row["userId"]),
    }
    if with_code:
        out["friendCode"] = row["friendCode"]
    return out


def user_by_token(token):
    if not token:
        return None
    with _db_lock:
        row = _db.execute(
            "SELECT * FROM users WHERE token = ?", (token,)
        ).fetchone()
    if row is not None:
        with _db_lock, _db:
            _db.execute(
                "UPDATE users SET lastSeen = ? WHERE userId = ?",
                (now_ms(), row["userId"]),
            )
    return row


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # ---- plumbing ---------------------------------------------------------

    def log_message(self, fmt, *args):
        pass

    def _send(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, status, payload, mime):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(payload)))
        # 头像 URL 带 v=updatedAt 版本号,变更即换 URL,这里可以长缓存。
        self.send_header("Cache-Control", "max-age=3600")
        self.end_headers()
        self.wfile.write(payload)

    def _error(self, status, message):
        self._send(status, {"error": message})

    def _body(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return None
        # 头像 base64 走 JSON 体:400KB blob → ~534KB base64,留出余量。
        if length <= 0 or length > 768 * 1024:
            return None
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None

    def _auth(self):
        user = user_by_token(self.headers.get("x-social-token"))
        if user is None:
            self._error(401, "未注册或 token 无效")
            return None
        return user

    def _query(self, name, default=""):
        match = re.search(r"[?&]" + name + r"=([^&]*)", self.path)
        return match.group(1) if match else default

    def _route(self):
        return self.path.split("?")[0]

    # ---- verbs ------------------------------------------------------------

    def do_GET(self):
        route = self._route()
        if route == "/social/health":
            return self._send(200, {"ok": True})
        user = self._auth()
        if user is None:
            return
        if route == "/social/me":
            return self._send(200, public_user(user, with_code=True))
        if route == "/social/avatar":
            return self._avatar(user)
        if route == "/social/friends":
            return self._friends(user)
        if route == "/social/conversations":
            return self._conversations(user)
        if route == "/social/messages":
            return self._messages(user)
        if route == "/social/posts":
            return self._posts(user)
        self._error(404, "未知路径")

    def do_POST(self):
        route = self._route()
        body = self._body()
        if body is None:
            return self._error(400, "请求体不是合法 JSON")
        if route == "/social/register":
            return self._register(body)
        user = self._auth()
        if user is None:
            return
        if route == "/social/me/stats":
            return self._stats(user, body)
        if route == "/social/me/nickname":
            return self._rename(user, body)
        if route == "/social/me/avatar":
            return self._avatar_upload(user, body)
        if route == "/social/friends/add":
            return self._friend_add(user, body)
        if route == "/social/friends/remove":
            return self._friend_remove(user, body)
        if route == "/social/messages":
            return self._message_send(user, body)
        if route == "/social/messages/read":
            return self._message_read(user, body)
        if route == "/social/posts":
            return self._post_create(user, body)
        if route == "/social/posts/like":
            return self._post_like(user, body)
        if route == "/social/posts/delete":
            return self._post_delete(user, body)
        self._error(404, "未知路径")

    # ---- identity ---------------------------------------------------------

    def _register(self, body):
        nickname = str(body.get("nickname") or "").strip()[:MAX_NICKNAME]
        if not nickname:
            return self._error(400, "昵称不能为空")
        with _db_lock, _db:
            for _ in range(20):
                code = "".join(secrets.choice("0123456789") for _ in range(8))
                clash = _db.execute(
                    "SELECT 1 FROM users WHERE friendCode = ?", (code,)
                ).fetchone()
                if not clash:
                    break
            user_id = "u-" + secrets.token_hex(8)
            token = secrets.token_hex(24)
            _db.execute(
                "INSERT INTO users(userId, nickname, friendCode, token,"
                " promptCount, createdAt, lastSeen) VALUES(?,?,?,?,0,?,?)",
                (user_id, nickname, code, token, now_ms(), now_ms()),
            )
        self._send(200, {
            "userId": user_id,
            "nickname": nickname,
            "friendCode": code,
            "token": token,
            "promptCount": 0,
            "level": 1,
            "title": LEVELS[0][1],
        })

    def _stats(self, user, body):
        try:
            count = max(0, int(body.get("promptCount") or 0))
        except (TypeError, ValueError):
            return self._error(400, "promptCount 必须是数字")
        with _db_lock, _db:
            _db.execute(
                "UPDATE users SET promptCount = ? WHERE userId = ?",
                (count, user["userId"]),
            )
        level, title = level_for(count)
        self._send(200, {"level": level, "title": title})

    def _rename(self, user, body):
        nickname = str(body.get("nickname") or "").strip()[:MAX_NICKNAME]
        if not nickname:
            return self._error(400, "昵称不能为空")
        with _db_lock, _db:
            _db.execute(
                "UPDATE users SET nickname = ? WHERE userId = ?",
                (nickname, user["userId"]),
            )
        self._send(200, {"nickname": nickname})

    # ---- avatars ------------------------------------------------------------

    def _avatar(self, user):
        target = self._query("userId")
        with _db_lock:
            row = _db.execute(
                "SELECT mime, data FROM avatars WHERE userId = ?", (target,)
            ).fetchone()
        if row is None:
            return self._error(404, "没有头像")
        self._send_bytes(200, row["data"], row["mime"])

    def _avatar_upload(self, user, body):
        data = body.get("data")
        if not data:
            # 空 data = 恢复默认字母头像。
            with _db_lock, _db:
                _db.execute(
                    "DELETE FROM avatars WHERE userId = ?", (user["userId"],)
                )
            return self._send(200, {"avatarVer": 0})
        mime = str(body.get("mime") or "image/jpeg")
        if mime not in ("image/jpeg", "image/png", "image/webp"):
            return self._error(400, "只支持 jpeg/png/webp")
        try:
            blob = base64.b64decode(data, validate=True)
        except (ValueError, TypeError):
            return self._error(400, "头像数据不是合法 base64")
        if len(blob) > 400 * 1024:
            return self._error(400, "头像不能超过 400KB")
        stamp = now_ms()
        with _db_lock, _db:
            _db.execute(
                "INSERT INTO avatars(userId, mime, data, updatedAt)"
                " VALUES(?,?,?,?)"
                " ON CONFLICT(userId) DO UPDATE SET"
                " mime = excluded.mime, data = excluded.data,"
                " updatedAt = excluded.updatedAt",
                (user["userId"], mime, blob, stamp),
            )
        self._send(200, {"avatarVer": stamp})

    # ---- friends ----------------------------------------------------------

    def _friend_add(self, user, body):
        code = str(body.get("friendCode") or "").strip()
        if not re.fullmatch(r"\d{8}", code):
            return self._error(400, "好友码是 8 位数字")
        with _db_lock:
            friend = _db.execute(
                "SELECT * FROM users WHERE friendCode = ?", (code,)
            ).fetchone()
        if friend is None:
            return self._error(404, "没有这个好友码")
        if friend["userId"] == user["userId"]:
            return self._error(400, "不能添加自己")
        with _db_lock, _db:
            existing = _db.execute(
                "SELECT 1 FROM friends WHERE userId = ? AND friendId = ?",
                (user["userId"], friend["userId"]),
            ).fetchone()
            if existing:
                return self._error(400, "已经是好友了")
            stamp = now_ms()
            _db.execute(
                "INSERT INTO friends(userId, friendId, createdAt)"
                " VALUES(?,?,?),(?,?,?)",
                (user["userId"], friend["userId"], stamp,
                 friend["userId"], user["userId"], stamp),
            )
        self._send(200, {"friend": public_user(friend)})

    def _friend_remove(self, user, body):
        friend_id = str(body.get("userId") or "")
        with _db_lock, _db:
            _db.execute(
                "DELETE FROM friends WHERE (userId = ? AND friendId = ?)"
                " OR (userId = ? AND friendId = ?)",
                (user["userId"], friend_id, friend_id, user["userId"]),
            )
        self._send(200, {"ok": True})

    def _friends(self, user):
        with _db_lock:
            rows = _db.execute(
                "SELECT u.* FROM friends f JOIN users u ON u.userId = f.friendId"
                " WHERE f.userId = ? ORDER BY u.promptCount DESC",
                (user["userId"],),
            ).fetchall()
        self._send(200, {
            "me": public_user(user, with_code=True),
            "items": [public_user(r) for r in rows],
        })

    # ---- private messages --------------------------------------------------

    def _messages(self, user):
        peer = self._query("peer")
        try:
            after = int(self._query("after", "0"))
        except ValueError:
            after = 0
        if not peer:
            return self._error(400, "缺少 peer")
        with _db_lock:
            rows = _db.execute(
                "SELECT * FROM messages WHERE ((fromId = ? AND toId = ?)"
                " OR (fromId = ? AND toId = ?)) AND id > ?"
                " ORDER BY id LIMIT 100",
                (user["userId"], peer, peer, user["userId"], after),
            ).fetchall()
        self._send(200, {"items": [dict(
            id=r["id"], fromId=r["fromId"], toId=r["toId"],
            text=r["text"], time=r["time"],
        ) for r in rows]})

    def _message_send(self, user, body):
        to = str(body.get("to") or "")
        text = str(body.get("text") or "").strip()[:MAX_TEXT]
        if not to or not text:
            return self._error(400, "缺少收件人或内容")
        with _db_lock:
            target = _db.execute(
                "SELECT 1 FROM users WHERE userId = ?", (to,)
            ).fetchone()
        if target is None:
            return self._error(404, "对方不存在")
        with _db_lock, _db:
            cur = _db.execute(
                "INSERT INTO messages(fromId, toId, text, time)"
                " VALUES(?,?,?,?)",
                (user["userId"], to, text, now_ms()),
            )
        self._send(200, {"id": cur.lastrowid})

    def _message_read(self, user, body):
        peer = str(body.get("peer") or "")
        try:
            last_id = int(body.get("lastId") or 0)
        except (TypeError, ValueError):
            last_id = 0
        with _db_lock, _db:
            _db.execute(
                "INSERT INTO reads(userId, peer, lastReadId) VALUES(?,?,?)"
                " ON CONFLICT(userId, peer) DO UPDATE SET"
                " lastReadId = MAX(lastReadId, excluded.lastReadId)",
                (user["userId"], peer, last_id),
            )
        self._send(200, {"ok": True})

    def _conversations(self, user):
        me = user["userId"]
        with _db_lock:
            rows = _db.execute(
                "SELECT m.*, u.nickname AS peerName FROM messages m"
                " JOIN users u ON u.userId ="
                "   CASE WHEN m.fromId = ? THEN m.toId ELSE m.fromId END"
                " WHERE m.fromId = ? OR m.toId = ? ORDER BY m.id DESC"
                " LIMIT 500",
                (me, me, me),
            ).fetchall()
            reads = {
                r["peer"]: r["lastReadId"]
                for r in _db.execute(
                    "SELECT * FROM reads WHERE userId = ?", (me,)
                ).fetchall()
            }
            unread = {}
            for r in _db.execute(
                "SELECT fromId, COUNT(*) AS n FROM messages WHERE toId = ?"
                " GROUP BY fromId",
                (me,),
            ).fetchall():
                floor = reads.get(r["fromId"], 0)
                n = _db.execute(
                    "SELECT COUNT(*) AS c FROM messages"
                    " WHERE toId = ? AND fromId = ? AND id > ?",
                    (me, r["fromId"], floor),
                ).fetchone()["c"]
                if n:
                    unread[r["fromId"]] = n
        seen = {}
        for r in rows:
            peer = r["toId"] if r["fromId"] == me else r["fromId"]
            if peer in seen:
                continue
            seen[peer] = {
                "userId": peer,
                "nickname": r["peerName"],
                "avatarVer": avatar_ver(peer),
                "lastText": r["text"][:80],
                "lastTime": r["time"],
                "unread": unread.get(peer, 0),
            }
        self._send(200, {"items": list(seen.values())})

    # ---- community posts ---------------------------------------------------

    def _post_view(self, user, row):
        with _db_lock:
            likes = _db.execute(
                "SELECT COUNT(*) AS c FROM likes WHERE postId = ?",
                (row["id"],),
            ).fetchone()["c"]
            liked = _db.execute(
                "SELECT 1 FROM likes WHERE postId = ? AND userId = ?",
                (row["id"], user["userId"]),
            ).fetchone() is not None
        level_info = None
        if row["levelInfo"]:
            try:
                level_info = json.loads(row["levelInfo"])
            except ValueError:
                level_info = None
        return {
            "id": row["id"],
            "userId": row["userId"],
            "nickname": row["nickname"],
            "avatarVer": avatar_ver(row["userId"]),
            "kind": row["kind"],
            "text": row["text"],
            "levelInfo": level_info,
            "likes": likes,
            "liked": liked,
            "mine": row["userId"] == user["userId"],
            "time": row["time"],
        }

    def _posts(self, user):
        try:
            before = int(self._query("before", "0"))
            limit = min(int(self._query("limit", "20")), MAX_PAGE)
        except ValueError:
            return self._error(400, "分页参数不合法")
        sql = (
            "SELECT p.*, u.nickname FROM posts p"
            " JOIN users u ON u.userId = p.userId"
        )
        args = []
        if before > 0:
            sql += " WHERE p.id < ?"
            args.append(before)
        sql += " ORDER BY p.id DESC LIMIT ?"
        args.append(limit + 1)
        with _db_lock:
            rows = _db.execute(sql, args).fetchall()
        has_more = len(rows) > limit
        rows = rows[:limit]
        self._send(200, {
            "items": [self._post_view(user, r) for r in rows],
            "hasMore": has_more,
        })

    def _post_create(self, user, body):
        text = str(body.get("text") or "").strip()[:MAX_TEXT]
        kind = "level" if body.get("kind") == "level" else "text"
        level_info = None
        if kind == "level":
            level, title = level_for(user["promptCount"])
            level_info = json.dumps({
                "level": level, "title": title,
                "count": user["promptCount"],
            }, ensure_ascii=False)
            if not text:
                text = f"我升到 Lv.{level} · {title} 啦!"
        if not text:
            return self._error(400, "内容不能为空")
        with _db_lock, _db:
            cur = _db.execute(
                "INSERT INTO posts(userId, kind, text, levelInfo, time)"
                " VALUES(?,?,?,?,?)",
                (user["userId"], kind, text, level_info, now_ms()),
            )
        self._send(200, {"id": cur.lastrowid})

    def _post_like(self, user, body):
        try:
            post_id = int(body.get("id") or 0)
        except (TypeError, ValueError):
            return self._error(400, "id 不合法")
        with _db_lock, _db:
            exists = _db.execute(
                "SELECT 1 FROM posts WHERE id = ?", (post_id,)
            ).fetchone()
            if not exists:
                return self._error(404, "动态不存在")
            liked = _db.execute(
                "SELECT 1 FROM likes WHERE postId = ? AND userId = ?",
                (post_id, user["userId"]),
            ).fetchone()
            if liked:
                _db.execute(
                    "DELETE FROM likes WHERE postId = ? AND userId = ?",
                    (post_id, user["userId"]),
                )
            else:
                _db.execute(
                    "INSERT INTO likes(postId, userId) VALUES(?,?)",
                    (post_id, user["userId"]),
                )
            likes = _db.execute(
                "SELECT COUNT(*) AS c FROM likes WHERE postId = ?",
                (post_id,),
            ).fetchone()["c"]
        self._send(200, {"likes": likes, "liked": not liked})

    def _post_delete(self, user, body):
        try:
            post_id = int(body.get("id") or 0)
        except (TypeError, ValueError):
            return self._error(400, "id 不合法")
        with _db_lock, _db:
            cur = _db.execute(
                "DELETE FROM posts WHERE id = ? AND userId = ?",
                (post_id, user["userId"]),
            )
            _db.execute("DELETE FROM likes WHERE postId = ?", (post_id,))
        if cur.rowcount == 0:
            return self._error(404, "动态不存在或不是你的")
        self._send(200, {"ok": True})


def main():
    init_db()
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"dsh social on http://{LISTEN_HOST}:{LISTEN_PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
