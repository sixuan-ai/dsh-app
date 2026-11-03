"""Exercise production redirect activation and rollback without SSH/network."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from configure_release_cdn import REMOTE


class RedirectActivationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='xharness-cdn-test-')
        self.root = Path(self.temp.name)
        self.version = '2.5.1'
        self.apk = b'fixture release bytes'
        self.meta = dict(version=self.version, versionCode=2143,
            sha256=hashlib.sha256(self.apk).hexdigest(), size=len(self.apk),
            url='https://dsh.example/releases-public/dsh-app-2.5.1.apk')
        for folder in ['var/www/dsh-releases','var/www/dsh-releases-public',
                       'etc/nginx/sites-enabled','etc/nginx/sites-available','etc/nginx/conf.d']:
            (self.root/folder).mkdir(parents=True)
        self.site = self.root/'etc/nginx/sites-available/dsh-sixuanai'
        self.site.write_text('server {\n    location /private/ { auth_basic "private"; }\n    location /releases-public/ {\n        alias /var/www/dsh-releases-public/;\n        add_header Cache-Control "no-store";\n    }\n}\n')
        (self.root/'etc/nginx/sites-enabled/dsh-sixuanai').symlink_to('../sites-available/dsh-sixuanai')
        (self.root/'var/www/dsh-releases-public/dsh-app-2.5.1.apk').write_bytes(self.apk)
        for file in ['var/www/dsh-releases/latest.json','var/www/dsh-releases-public/latest.json','var/www/dsh-releases-public/version.json']:
            (self.root/file).write_text(json.dumps(self.meta))
        self.addCleanup(self.temp.cleanup)

    def execute(self, meta, fail_validation=False):
        root = self.root
        validations = 0
        def path(value):
            return root/str(value).lstrip('/')
        def run(args, **kwargs):
            nonlocal validations
            if args == ['nginx','-t']:
                validations += 1
                if fail_validation and validations == 1:
                    raise subprocess.CalledProcessError(1,args)
            return subprocess.CompletedProcess(args,0,stdout=b'',stderr=b'')
        with patch('pathlib.Path',side_effect=path), patch('sys.stdin',io.StringIO(json.dumps(meta))), patch('sys.stdout',io.StringIO()), patch('subprocess.run',side_effect=run):
            exec(compile(REMOTE,'<remote-cdn-activation>','exec'), {})

    def test_only_public_known_release_and_latest_redirect(self):
        meta={**self.meta,'cdnUrl':'https://downloads.example/xharness/dsh-app-2.5.1.apk'}
        self.execute(meta)
        self.assertIn('location /private/ { auth_basic "private"; }',self.site.read_text())
        self.assertIn('if ($xharness_release_cdn_url',self.site.read_text())
        mapping=(self.root/'etc/nginx/conf.d/xharness-release-cdn.conf').read_text()
        self.assertIn('/releases-public/dsh-app-2.5.1.apk',mapping)
        self.assertIn('/releases-public/dsh-app-latest.apk',mapping)
        self.assertNotIn('/latest.json',mapping)
        self.assertIn('$arg_origin',mapping)
        self.assertIn('direct',mapping)
        self.assertNotIn('/releases/dsh-app',mapping)
        self.assertTrue((self.root/'etc/nginx/sites-enabled/dsh-sixuanai').is_symlink())
        self.assertEqual(json.loads((self.root/'var/www/dsh-releases-public/latest.json').read_text())['cdnUrl'],meta['cdnUrl'])
        # Explicit origin-only publication must stop redirecting latest too.
        self.execute(self.meta)
        mapping=(self.root/'etc/nginx/conf.d/xharness-release-cdn.conf').read_text()
        self.assertNotIn('https://downloads.example',mapping)
        self.assertNotIn('cdnUrl',json.loads((self.root/'var/www/dsh-releases-public/latest.json').read_text()))

    def test_nginx_validation_failure_restores_all_touched_files(self):
        before=self.site.read_bytes()
        meta={**self.meta,'cdnUrl':'https://downloads.example/xharness/dsh-app-2.5.1.apk'}
        with self.assertRaises(subprocess.CalledProcessError):self.execute(meta,True)
        self.assertEqual(self.site.read_bytes(),before)
        self.assertFalse((self.root/'etc/nginx/conf.d/xharness-release-cdn.conf').exists())
        self.assertFalse((self.root/'var/www/dsh-releases/cdn-index.json').exists())
        self.assertEqual(json.loads((self.root/'var/www/dsh-releases-public/latest.json').read_text()),self.meta)

    def test_changed_release_cannot_activate_old_redirect(self):
        meta={**self.meta,'versionCode':2144,'cdnUrl':'https://downloads.example/xharness/dsh-app-2.5.1.apk'}
        before=self.site.read_bytes()
        with self.assertRaises(AssertionError):self.execute(meta)
        self.assertEqual(self.site.read_bytes(),before)

    def test_cdn_cannot_receive_legacy_account_headers_as_origin_subdomain(self):
        meta={**self.meta,'cdnUrl':'https://downloads.dsh.example/xharness/dsh-app-2.5.1.apk'}
        before=self.site.read_bytes()
        with self.assertRaises(AssertionError):self.execute(meta)
        self.assertEqual(self.site.read_bytes(),before)


if __name__ == '__main__':unittest.main()
