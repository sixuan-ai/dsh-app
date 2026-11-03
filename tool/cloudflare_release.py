#!/usr/bin/env python3
"""Publish immutable signed APK bytes to the configured Cloudflare R2 mirror."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request


class R2ReleaseStore:
    def __init__(self, config_path):
        config = json.loads(Path(config_path).read_text())
        self.account = config['account_id']
        self.bucket = config['bucket']
        self.public_base = config['public_base_url'].rstrip('/')
        self.prefix = config.get('key_prefix', '').strip('/')
        self.zone = config.get('zone_id')
        parsed = urllib.parse.urlsplit(self.public_base)
        if not re.fullmatch(r'[a-f0-9]{32}', self.account) or not re.fullmatch(r'[a-z0-9][a-z0-9-]{1,61}[a-z0-9]', self.bucket):
            raise ValueError('Invalid R2 account/bucket')
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError('Use an HTTPS public mirror URL without credentials')
        if parsed.path.strip('/') != self.prefix or any(x in ('.', '..') for x in self.prefix.split('/')):
            raise ValueError('Mirror URL and object prefix do not match')
        self.token = os.environ.get('CLOUDFLARE_API_TOKEN')
        if not self.token:
            token_file = Path(config.get('token_file', '~/.config/xharness/cloudflare-token')).expanduser()
            if token_file.stat().st_mode & 0o077:
                raise ValueError('Cloudflare token file must be private (chmod 600)')
            self.token = token_file.read_text().strip()
        if not self.token:
            raise ValueError('Cloudflare API token is missing')
        self.api = f'https://api.cloudflare.com/client/v4/accounts/{self.account}/r2/buckets/{self.bucket}'

    def request(self, suffix, method='GET', data=None, headers=None, timeout=60):
        request = urllib.request.Request(self.api+suffix, method=method, data=data,
            headers={'Authorization': 'Bearer '+self.token, **(headers or {})})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                result = json.load(response)
        except urllib.error.HTTPError as error:
            try:
                errors = json.load(error).get('errors', [])
            except Exception:
                errors = [{'code': error.code, 'message': 'HTTP error'}]
            raise RuntimeError(json.dumps(errors).replace(self.token, '[redacted]')) from None
        if not result.get('success'):
            raise RuntimeError(json.dumps(result.get('errors', [])).replace(self.token, '[redacted]'))
        return result['result']

    def purge_uploaded_url(self, url):
        if not self.zone:
            return
        if not re.fullmatch(r'[a-f0-9]{32}', self.zone):
            raise ValueError('Invalid Cloudflare zone id')
        request = urllib.request.Request('https://api.cloudflare.com/client/v4/zones/'+self.zone+'/purge_cache',
            method='POST', data=json.dumps({'files':[url]}).encode(),
            headers={'Authorization':'Bearer '+self.token, 'Content-Type':'application/json'})
        with urllib.request.urlopen(request, timeout=45) as response:
            result=json.load(response)
        if not result.get('success'):
            raise RuntimeError('Cannot clear stale negative cache for the uploaded release')

    @staticmethod
    def verify_url(url, size, digest):
        started = time.monotonic()
        sha = hashlib.sha256()
        received = 0
        request = urllib.request.Request(url, headers={'Accept-Encoding': 'identity', 'User-Agent':'xHarness-Publisher/1.0', 'Accept':'*/*'})
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status != 200:
                raise RuntimeError('CDN did not return a complete APK')
            headers = {k.lower():v for k,v in response.headers.items()}
            while data := response.read(1048576):
                sha.update(data)
                received += len(data)
        if received != size or sha.hexdigest() != digest:
            raise RuntimeError('CDN APK size/SHA-256 mismatch')
        return dict(size=received, seconds=round(time.monotonic()-started, 3),
                    cacheStatus=headers.get('cf-cache-status'),
                    edge=headers.get('cf-ray'))

    def upload(self, apk, version, digest, verify=True):
        if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
            raise ValueError('Invalid release version')
        apk = Path(apk)
        name = 'dsh-app-'+version+'.apk'
        key = '/'.join(x for x in (self.prefix, name) if x)
        url = self.public_base+'/'+name
        size = apk.stat().st_size
        if size > 300_000_000:
            raise ValueError('R2 REST upload is limited to 300 MB; use multipart for larger artifacts')
        # Query the authenticated API to avoid negatively caching a public 404.
        listing = self.request('/objects?prefix='+urllib.parse.quote(key, safe=''))
        entries = listing.get('objects', []) if isinstance(listing, dict) else listing
        exists = next((x for x in entries if x.get('key') == key), None)
        if exists is not None:
            # Versioned objects are immutable: validate, never replace them.
            measured = self.verify_url(url, size, digest)
            print('R2 object already matches the release', flush=True)
        else:
            md5 = hashlib.md5(usedforsecurity=False)
            sha = hashlib.sha256()
            with apk.open('rb') as stream:
                while block := stream.read(1048576):
                    md5.update(block); sha.update(block)
            if sha.hexdigest() != digest:
                raise RuntimeError('APK changed before upload')
            with apk.open('rb') as stream:
                uploaded = self.request('/objects/'+urllib.parse.quote(key, safe='/'), method='PUT', data=stream,
                    headers={'Content-Length': str(size), 'Content-Type': 'application/vnd.android.package-archive',
                             'Cache-Control': 'public, max-age=31536000, immutable',
                             'Content-Disposition': 'attachment; filename="'+name+'"'}, timeout=300)
            if int(uploaded['size']) != size or uploaded['etag'].strip('"') != md5.hexdigest():
                raise RuntimeError('Uploaded R2 object checksum/size mismatch')
            self.purge_uploaded_url(url)
            print('R2 uploaded '+name+' ('+str(size)+' bytes)', flush=True)
            measured = self.verify_url(url, size, digest) if verify else None
        return {'url': url, 'size': size, 'sha256': digest, 'measurement': measured}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default='server/release-cdn.json', type=Path)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--upload-only', action='store_true')
    args = parser.parse_args()
    digest = hashlib.sha256(args.apk.read_bytes()).hexdigest()
    store = R2ReleaseStore(args.config)
    result = store.upload(args.apk, args.version, digest, verify=not args.upload_only)
    print(json.dumps(result))


if __name__ == '__main__':
    main()
