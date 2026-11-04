"""Pet board, standard library only. No raw identities or sessions in SQLite."""
import hashlib
import hmac
import json
import os
import time
import unicodedata
import urllib.request
import urllib.error
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


class BoardError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def validate_account(token):
    """Replaceable boundary; fail closed on unavailable/malformed account service."""
    request = urllib.request.Request(
        os.environ.get('PET_ACCOUNTS_URL', 'https://accounts.sixuanai.com/api/currentUser'),
        data=b'{}', headers={'Authorization': 'Bearer ' + token,
                             'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            result = json.loads(response.read(65536))
        user = result.get('user', result)
        email = user.get('email')
        if result.get('error') or not isinstance(email, str) or '@' not in email:
            raise BoardError(503, '账号服务响应无效')
        # sixuan-accounts currentUser returns no numeric id; the verified email
        # is the unique, immutable account key there. It is only stored HMAC'd.
        email = email.strip()
        return email.lower(), email
    except urllib.error.HTTPError as error:
        raise BoardError(401 if error.code in (401, 403) else 503, '账号校验失败') from None
    except (OSError, ValueError, TypeError, AttributeError):
        raise BoardError(503, '账号服务暂时不可用') from None


def week_key(now):
    day = datetime.fromtimestamp(now, ZoneInfo('Asia/Shanghai'))
    return (day - timedelta(days=day.weekday())).date().isoformat()


def clean_name(value, maximum):
    if (not isinstance(value, str) or not 1 <= len(value.strip()) <= maximum
            or any(unicodedata.category(c).startswith('C') for c in value)):
        raise BoardError(400, '昵称或宠物名长度不合法，不能含控制字符')
    return value.strip()


def masked_email(email):
    local, _, domain = email.partition('@')
    # Do not echo malformed service data.
    if not local or not domain or any(unicodedata.category(c).startswith('C') for c in email):
        return '匿名伙伴'
    return local[0] + '***@' + domain


def stage_for(tokens):
    level = tokens // 1000000 + 1
    names = ['初见伙伴', '熟悉伙伴', '默契伙伴', '贴心伙伴', '灵魂搭档']
    index = sum(level >= n for n in (3, 6, 10, 15))
    return level, names[index]


class PetBoard:
    def __init__(self, db, lock, secret=None, validator=None, clock=time.time):
        self.db, self.lock, self.clock = db, lock, clock
        self.secret = secret if secret is not None else os.environ.get('PET_BOARD_HMAC_KEY', '')
        self.validator = validator or validate_account
        self.cache = {}
        self.single_cap = int(os.environ.get('PET_MAX_DELTA', '30000000'))
        self.hour_cap = int(os.environ.get('PET_MAX_HOURLY', '30000000'))
        with lock, db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS pet_board(
                    user_key TEXT PRIMARY KEY, nickname TEXT NOT NULL,
                    opted_out INTEGER NOT NULL DEFAULT 0, pet_name TEXT NOT NULL DEFAULT '大肥鱼',
                    species TEXT NOT NULL DEFAULT 'dafeiyu', stage TEXT NOT NULL DEFAULT '初见伙伴',
                    tokens INTEGER NOT NULL DEFAULT 0, pk_score INTEGER NOT NULL DEFAULT 1000,
                    reached_at REAL NOT NULL, updated_at REAL NOT NULL,
                    suspicious INTEGER NOT NULL DEFAULT 0, last_report REAL);
                CREATE TABLE IF NOT EXISTS pet_board_snapshots(
                    user_key TEXT, week_key TEXT, start_tokens INTEGER, last_tokens INTEGER,
                    reached_at REAL NOT NULL, PRIMARY KEY(user_key, week_key));
                CREATE TABLE IF NOT EXISTS pet_board_deltas(
                    user_key TEXT, time REAL, delta INTEGER);
                CREATE INDEX IF NOT EXISTS pet_delta_time ON pet_board_deltas(user_key, time);
            ''')

    def authenticate(self, header, optional=False):
        if not header and optional:
            return None
        if not header or not header.startswith('Bearer ') or not 1 <= len(header[7:]) <= 512:
            raise BoardError(401, '请先登录思玄账号')
        if len(self.secret) < 32:
            raise BoardError(503, '排行榜尚未配置')
        token = header[7:]
        hashed = hashlib.sha256(token.encode()).hexdigest()
        now = self.clock()
        with self.lock:
            cached = self.cache.get(hashed)
            if cached and cached[0] > now:
                return cached[1]
        identifier, email = self.validator(token)
        identity = (hmac.new(self.secret.encode(), identifier.encode(), hashlib.sha256).hexdigest(),
                    masked_email(email))
        with self.lock:
            self.cache = {k: v for k, v in self.cache.items() if v[0] > now}
            if len(self.cache) >= 4096:
                self.cache.pop(next(iter(self.cache)))
            self.cache[hashed] = (now + 300, identity)
        return identity

    def _ensure(self, identity, now):
        key, nickname = identity
        self.db.execute('INSERT OR IGNORE INTO pet_board(user_key,nickname,reached_at,updated_at) VALUES(?,?,?,?)',
                        (key, nickname, now, now))
        return self.db.execute('SELECT * FROM pet_board WHERE user_key=?', (key,)).fetchone()

    def update(self, identity, body, settings=False):
        if not isinstance(body, dict):
            raise BoardError(400, '请求体必须为对象')
        now, key = self.clock(), identity[0]
        with self.lock, self.db:
            row = self._ensure(identity, now)
            if settings:
                nickname = clean_name(body['nickname'], 16) if 'nickname' in body else row['nickname']
                opted = body.get('optedOut', bool(row['opted_out']))
                if not isinstance(opted, bool):
                    raise BoardError(400, 'optedOut 必须为布尔值')
                self.db.execute('UPDATE pet_board SET nickname=?,opted_out=? WHERE user_key=?', (nickname, opted, key))
                return {'ok': True, 'nickname': nickname, 'optedOut': opted}
            if row['opted_out']:
                return {'ok': True, 'optedOut': True}
            if row['last_report'] is not None and now - row['last_report'] < 20:
                raise BoardError(429, '上报间隔至少 20 秒')
            pet_name = clean_name(body.get('petName'), 32)
            tokens, pk = body.get('tokens'), body.get('pkScore', 1000)
            if type(tokens) is not int or not 0 <= tokens <= 9007199254740991 or type(pk) is not int or not 0 <= pk <= 1000000:
                raise BoardError(400, '成长值或段位分数无效')
            reset = body.get('reset', False)
            if type(reset) is not bool:
                raise BoardError(400, 'reset 必须为布尔值')
            week = week_key(now)
            snapshot = self.db.execute('SELECT * FROM pet_board_snapshots WHERE user_key=? AND week_key=?', (key, week)).fetchone()
            # First observation of a new week starts at the previous known total;
            # first-ever import establishes a baseline rather than fabricating growth.
            baseline = row['tokens'] if row['last_report'] is not None else tokens
            start = snapshot['start_tokens'] if snapshot else baseline
            last = snapshot['last_tokens'] if snapshot else baseline
            earned = max(0, last - start)
            self.db.execute('DELETE FROM pet_board_deltas WHERE time<=?', (now - 3600,))
            used = self.db.execute('SELECT COALESCE(SUM(delta),0) FROM pet_board_deltas WHERE user_key=?', (key,)).fetchone()[0]
            delta = max(0, tokens - row['tokens'])
            accepted = min(delta, self.single_cap, max(0, self.hour_cap - used))
            suspicious = int(accepted < delta)
            new_tokens = tokens if reset and tokens < row['tokens'] else row['tokens'] + accepted
            if reset and new_tokens < row['tokens']:
                # Preserve already-earned weekly growth; resetting must not create free weekly tokens.
                start = new_tokens - earned
            elif snapshot is None:
                start = min(start, new_tokens)
            reached = now if new_tokens != row['tokens'] or reset else row['reached_at']
            week_reached = now if new_tokens - start != earned else (snapshot['reached_at'] if snapshot else now)
            _, stage = stage_for(new_tokens)
            self.db.execute('UPDATE pet_board SET pet_name=?,species=?,stage=?,tokens=?,pk_score=?,reached_at=?,updated_at=?,last_report=?,suspicious=suspicious+? WHERE user_key=?',
                            (pet_name, 'dafeiyu', stage, new_tokens, pk, reached, now, now, suspicious, key))
            self.db.execute('INSERT OR REPLACE INTO pet_board_snapshots VALUES(?,?,?,?,?)', (key, week, start, new_tokens, week_reached))
            if accepted:
                self.db.execute('INSERT INTO pet_board_deltas VALUES(?,?,?)', (key, now, accepted))
            return {'ok': True, 'tokens': new_tokens, 'level': stage_for(new_tokens)[0], 'stage': stage, 'optedOut': False}

    def board(self, identity=None, scope='all', limit=100):
        if scope not in ('all', 'week') or not 1 <= limit <= 100:
            raise BoardError(400, '排行榜参数无效')
        week = week_key(self.clock())
        metric = 'b.tokens' if scope == 'all' else 'MAX(0,COALESCE(s.last_tokens-s.start_tokens,0))'
        reached = 'b.reached_at' if scope == 'all' else 'COALESCE(s.reached_at,b.reached_at)'
        with self.lock:
            # Window functions compute outside-Top-100 ranks without exposing identifiers.
            rows = self.db.execute(f'''SELECT b.*, {metric} AS score,
                ROW_NUMBER() OVER (ORDER BY {metric} DESC,{reached},b.user_key) AS rank,
                LAG({metric}) OVER (ORDER BY {metric} DESC,{reached},b.user_key) AS previous
                FROM pet_board b LEFT JOIN pet_board_snapshots s ON b.user_key=s.user_key AND s.week_key=?
                WHERE b.opted_out=0 AND b.last_report IS NOT NULL ORDER BY rank''', (week,)).fetchall()
            me_row = self.db.execute('SELECT * FROM pet_board WHERE user_key=?', (identity[0],)).fetchone() if identity else None
        def view(row):
            level, stage = stage_for(row['tokens'])
            return {'rank': row['rank'], 'nickname': row['nickname'], 'petName': row['pet_name'],
                    'species': row['species'], 'stage': stage, 'tokens': row['tokens'],
                    'pkScore': row['pk_score'], 'level': level, 'score': row['score'],
                    'gap': max(0, row['previous'] - row['score']) if row['previous'] is not None else 0}
        result = {'scope': scope, 'weekKey': week, 'items': [view(r) for r in rows[:limit]]}
        if identity:
            mine = next((r for r in rows if r['user_key'] == identity[0]), None)
            result['me'] = dict(view(mine), optedOut=False) if mine else {
                'rank': None, 'nickname': me_row['nickname'] if me_row else identity[1],
                'optedOut': bool(me_row['opted_out']) if me_row else False}
        return result
