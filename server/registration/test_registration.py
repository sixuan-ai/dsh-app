"""Real HTTP regression tests with temporary data and no email delivery."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer


class AccountFlowTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        old = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(old)))
        os.environ.update(REGISTER_DB_PATH=str(root/'register.db'), DIRECTORY_USERS_FILE=str(root/'users.json'),
                          DIRECTORY_BACKENDS_FILE=str(root/'backends.json'), REGISTER_APP_TOKEN='',
                          REGISTER_DEFAULT_SUBDOMAIN='', REGISTER_ALLOWED_DOMAINS='')
        self.urls = {}
        for name in ['dsh-register', 'dsh-directory']:
            spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name+'.py'))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            if name == 'dsh-register':
                self.reg = module
                module.init_db()
                self.addCleanup(module._db.close)
            server = ThreadingHTTPServer(('127.0.0.1', 0), module.Handler)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            self.addCleanup(server.server_close)
            self.addCleanup(server.shutdown)
            self.urls[name] = 'http://127.0.0.1:'+str(server.server_port)
        self.computers = [{'id':'omen','subdomain':'omen.example.com','default':True},
                          {'id':'x26','subdomain':'x26.example.com'}]
        self.reg.save_users({'owner':{'password':'OldPass123','email':'owner@example.com','createdAt':123,'computers':self.computers},
                             'other':{'password':'OtherPass123','subdomain':'other.example.com'}})
        (root/'backends.json').write_text(json.dumps({c['subdomain']:{'username':'backend','password':'internal'} for c in self.computers}))
        with self.reg._db:
            self.reg._db.execute('INSERT INTO accounts VALUES(?,?,?,?,?,?,?)', ('owner@example.com','unused','salt','owner',123,123,'127.0.0.1'))

    def request(self, service, path, body=None, headers=None):
        req = urllib.request.Request(self.urls[service]+path, data=json.dumps(body).encode() if body is not None else None, headers=headers or {})
        try:
            response = urllib.request.urlopen(req)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            raw = response.read()
            return response.status, dict(response.headers), json.loads(raw) if raw else None

    def auth(self, user, password, host):
        value = base64.b64encode((user+':'+password).encode()).decode()
        return self.request('dsh-directory','/internal/auth',headers={'Authorization':'Basic '+value,'X-DSH-Target':host})

    def test_email_and_username_authorize_both_computers(self):
        for user in ['owner','OWNER@example.com']:
            for c in self.computers:
                status, headers, _ = self.auth(user,'OldPass123',c['subdomain'])
                self.assertEqual(status,204)
                self.assertTrue(headers['X-DSH-Backend-Authorization'].startswith('Basic '))
        self.assertEqual(self.auth('owner','OldPass123','@shared')[0],204)

    def test_wrong_password_other_account_and_missing_backend_fail_closed(self):
        self.assertEqual(self.auth('owner','wrong','omen.example.com')[0],401)
        self.assertEqual(self.auth('other','OtherPass123','omen.example.com')[0],403)
        self.assertEqual(self.auth('owner','OldPass123','unbound.example.com')[0],403)
        Path(os.environ['DIRECTORY_BACKENDS_FILE']).unlink()
        self.assertEqual(self.auth('owner','OldPass123','omen.example.com')[0],503)

    def test_reregister_preserves_computers_and_rotates_password(self):
        salt='test-salt'
        with self.reg._db:
            self.reg._db.execute('INSERT INTO codes VALUES(?,?,?,?,?,?)', ('owner@example.com',self.reg.code_digest('123456',salt),salt,self.reg.now_s()+600,0,self.reg.now_s()))
        body={'email':'owner@example.com','code':'123456','password':'新密码Pass123'}
        status, _, data = self.request('dsh-register','/directory/register/verify',body)
        self.assertEqual(status,200)
        self.assertTrue(data['provisioned'])
        record=self.reg.load_users()['owner']
        self.assertEqual(record['computers'],self.computers)
        self.assertEqual(record['createdAt'],123)
        self.assertEqual(self.auth('owner@example.com','OldPass123','omen.example.com')[0],401)
        self.assertEqual(self.auth('owner@example.com','新密码Pass123','omen.example.com')[0],204)
        status, _, data=self.request('dsh-directory','/directory/login',{'username':'owner@example.com','password':'新密码Pass123'})
        self.assertEqual(status,200)
        self.assertEqual(len(data['computers']),2)
        self.assertEqual(self.request('dsh-register','/directory/register/verify',body)[0],400)


if __name__ == '__main__':
    unittest.main()
