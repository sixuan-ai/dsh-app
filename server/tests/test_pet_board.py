import importlib.util
import json
import os
import sqlite3
import sys
import threading
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pet_board import PetBoard, BoardError, week_key, validate_account


class PetBoardTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:', check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.now = 1793548800.
        self.calls = 0
        def validator(token):
            self.calls += 1
            if token == 'bad':
                raise BoardError(401, 'invalid')
            if token == 'offline':
                raise BoardError(503, 'unavailable')
            return 'account-id-' + token, 'zhang-private@qq.com'
        self.board = PetBoard(self.db, threading.Lock(), secret='test-only-key-' * 4,
                              validator=validator, clock=lambda: self.now)
        self.me = self.auth('one')

    def tearDown(self):
        self.db.close()

    def auth(self, token):
        return self.board.authenticate('Bearer ' + token)

    def report(self, identity=None, tokens=1000000, **kw):
        return self.board.update(identity or self.me, dict(petName='大肥鱼', species='fake', stage='fake', tokens=tokens, pkScore=1200, **kw))

    def test_auth_and_cache_expiry(self):
        self.assertEqual(self.me, self.auth('one'))
        self.assertEqual(1, self.calls)
        self.now += 300
        self.auth('one')
        self.assertEqual(2, self.calls)
        for header, status in [(None, 401), ('Basic abc', 401), ('Bearer bad', 401), ('Bearer offline', 503)]:
            with self.assertRaises(BoardError) as e:
                self.board.authenticate(header)
            self.assertEqual(status, e.exception.status)
        self.assertIsNone(self.board.authenticate(None, optional=True))

    def test_account_service_fail_closed(self):
        with patch('urllib.request.urlopen', side_effect=URLError('offline')):
            with self.assertRaises(BoardError) as e:
                validate_account('synthetic')
            self.assertEqual(503, e.exception.status)
        with patch('urllib.request.urlopen', side_effect=HTTPError('url', 401, '', {}, None)):
            with self.assertRaises(BoardError) as e:
                validate_account('synthetic')
            self.assertEqual(401, e.exception.status)

    def test_anonymous_privacy_and_server_stage(self):
        self.assertEqual([], self.board.board()['items'])
        self.report(tokens=14000000)
        result = self.board.board()
        self.assertNotIn('me', result)
        first = result['items'][0]
        self.assertEqual((15, '灵魂搭档', 'dafeiyu'), (first['level'], first['stage'], first['species']))
        self.assertEqual('z***@qq.com', first['nickname'])
        raw = json.dumps(result)
        for private in ('account-id', 'zhang-private', self.me[0], 'user_key', 'email'):
            self.assertNotIn(private, raw)
        dump = '\n'.join(self.db.iterdump())
        self.assertNotIn('account-id', dump)
        self.assertNotIn('zhang-private', dump)

    def test_sort_and_tie_reached_time(self):
        other = self.auth('two')
        self.report(tokens=2000000)
        self.now += 21
        self.report(other, tokens=2000000)
        self.assertEqual(2, self.board.board(other)['me']['rank'])
        self.now += 21
        self.report(tokens=2000000)  # unchanged does not lose tie priority
        self.assertEqual(1, self.board.board(self.me)['me']['rank'])
        self.now += 21
        self.report(other, tokens=3000000)
        self.assertEqual(1000000, self.board.board(self.me)['me']['gap'])

    def test_me_outside_top100(self):
        self.report(tokens=0)
        for i in range(101):
            self.now += 21
            self.report(self.auth('other' + str(i)), tokens=1000 + i)
        result = self.board.board(self.me)
        self.assertEqual(100, len(result['items']))
        self.assertEqual(102, result['me']['rank'])
        self.assertEqual(1000, result['me']['gap'])

    def test_monotonic_reset_and_rate(self):
        self.report(tokens=5000000)
        with self.assertRaises(BoardError) as e:
            self.report(tokens=9000000)
        self.assertEqual(429, e.exception.status)
        self.now += 20
        self.assertEqual(5000000, self.report(tokens=1)['tokens'])
        old = self.db.execute('SELECT reached_at FROM pet_board').fetchone()[0]
        self.now += 20
        self.assertEqual(1, self.report(tokens=1, reset=True)['tokens'])
        self.assertGreater(self.db.execute('SELECT reached_at FROM pet_board').fetchone()[0], old)

    def test_single_and_rolling_hour_clamp(self):
        self.board.single_cap = 10000000
        self.assertEqual(10000000, self.report(tokens=90000000)['tokens'])
        for expected in (20000000, 30000000, 30000000):
            self.now += 20
            self.assertEqual(expected, self.report(tokens=90000000)['tokens'])
        self.assertEqual(4, self.db.execute('SELECT suspicious FROM pet_board').fetchone()[0])
        self.now += 3600
        self.assertEqual(40000000, self.report(tokens=90000000)['tokens'])

    def test_nickname_and_opt_out(self):
        for nickname in ('', 'a' * 17, 'abc\n', 'a\u200bb', 123):
            with self.assertRaises(BoardError):
                self.board.update(self.me, {'nickname': nickname}, settings=True)
        self.report()
        self.board.update(self.me, {'nickname': '小鱼', 'optedOut': True}, settings=True)
        result = self.board.board(self.me)
        self.assertEqual([], result['items'])
        self.assertTrue(result['me']['optedOut'])
        self.now += 21
        self.assertTrue(self.report(tokens=90000000)['optedOut'])
        self.board.update(self.me, {'optedOut': False}, settings=True)
        self.assertEqual('小鱼', self.board.board()['items'][0]['nickname'])

    def test_week_monday_boundary_and_gap(self):
        self.now = datetime.fromisoformat('2026-11-08T23:59:30+08:00').timestamp()
        self.assertEqual('2026-11-02', week_key(self.now))
        self.report(tokens=5000000)
        self.now += 20
        self.report(tokens=6000000)
        self.assertEqual(1000000, self.board.board(self.me, 'week')['me']['score'])
        self.now += 10
        self.assertEqual('2026-11-09', week_key(self.now))
        self.assertEqual(0, self.board.board(self.me, 'week')['me']['score'])
        self.now += 10
        self.report(tokens=6500000)
        self.assertEqual(500000, self.board.board(self.me, 'week')['me']['score'])
        self.now += 20
        self.report(tokens=0, reset=True)
        self.assertEqual(500000, self.board.board(self.me, 'week')['me']['score'])

    def test_invalid_input(self):
        for tokens in (-1, True, '100', 1.5, 10**30):
            with self.assertRaises(BoardError):
                self.report(tokens=tokens)
        for scope, limit in [('oops', 100), ('all', 101), ('all', 0)]:
            with self.assertRaises(BoardError):
                self.board.board(scope=scope, limit=limit)


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with patch.dict(os.environ, SOCIAL_DB_PATH=':memory:'):
            spec = importlib.util.spec_from_file_location('social_test', Path(__file__).resolve().parents[1] / 'social-server.py')
            cls.social = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.social)
        cls.social.init_db()
        cls.social.pet_board = PetBoard(cls.social._db, cls.social._db_lock, secret='s' * 32,
                                       validator=lambda t: ('synthetic-id', 'test@example.com'))
        cls.server = cls.social.ThreadingHTTPServer(('127.0.0.1', 0), cls.social.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = 'http://127.0.0.1:' + str(cls.server.server_port)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.social._db.close()

    def call(self, path, method='GET', body=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        data = json.dumps(body).encode() if body is not None else None
        return urlopen(Request(self.base + path, data=data, headers=headers, method=method))

    def test_http_routes_and_body_limit(self):
        for path in ('/pet/board', '/social/pet/board'):
            with self.call(path) as response:
                self.assertEqual(200, response.status)
        with self.assertRaises(HTTPError) as e:
            self.call('/pet/me', 'POST', {})
        self.assertEqual(401, e.exception.code)
        with self.assertRaises(HTTPError) as e:
            self.call('/pet/me', 'POST', {'extra': 'x' * 4096}, 'fake-session')
        self.assertEqual(413, e.exception.code)
        with self.call('/pet/me', 'POST', {'petName': '鱼', 'tokens': 100, 'pkScore': 1000}, 'fake-session') as response:
            self.assertEqual(100, json.load(response)['tokens'])
        with self.call('/pet/me', 'PATCH', {'optedOut': True}, 'fake-session') as response:
            self.assertTrue(json.load(response)['optedOut'])
        with self.call('/pet/board', token='fake-session') as response:
            result = json.load(response)
            self.assertEqual([], result['items'])
            self.assertTrue(result['me']['optedOut'])

    def test_existing_social_health(self):
        with self.call('/social/health') as response:
            self.assertTrue(json.load(response)['ok'])
