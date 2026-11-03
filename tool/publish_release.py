#!/usr/bin/env python3
"""Publish a verified Android upgrade to the current authenticated/public feeds."""

import argparse
import hashlib
import json
import re
import shlex
import subprocess
import tempfile
import urllib.request
from pathlib import Path

REMOTE = r"""
import datetime,hashlib,json,os,re,shutil,sys,tempfile
from pathlib import Path
stage=Path(sys.argv[1]);meta=json.load(sys.stdin);name='dsh-app-'+meta['version']+'.apk'
assert re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',meta['version'])
release=Path('/var/www/dsh-releases');public=Path('/var/www/dsh-releases-public')
release.mkdir(parents=True,exist_ok=True);public.mkdir(parents=True,exist_ok=True)
old=json.loads((release/'latest.json').read_text())if(release/'latest.json').exists()else{}
assert meta['versionCode']>old.get('versionCode',0)or(meta['versionCode']==old.get('versionCode')and meta['sha256']==old.get('sha256')),'Refusing downgrade or replacement of an existing versionCode'
source=stage/'package.apk';assert source.stat().st_size==meta['size'];assert hashlib.sha256(source.read_bytes()).hexdigest()==meta['sha256']
backup=Path('/var/backups/xharness-releases')/datetime.datetime.now().strftime('%Y%m%d-%H%M%S');backup.mkdir(parents=True,exist_ok=True)
for folder,file in [(release,'latest.json'),(public,'latest.json'),(public,'version.json')]:
 if(folder/file).exists():shutil.copy2(folder/file,backup/(folder.name+'-'+file))
def replace(target,source=None,data=None):
 fd,tmp=tempfile.mkstemp(prefix='.upload-',dir=target.parent)
 try:
  with os.fdopen(fd,'wb')as stream:
   if source:
    with source.open('rb')as src:shutil.copyfileobj(src,stream)
   else:stream.write(json.dumps(data,ensure_ascii=False,indent=2).encode())
   stream.flush();os.fsync(stream.fileno());os.fchmod(stream.fileno(),0o644)
  os.replace(tmp,target)
 finally:
  if os.path.exists(tmp):os.unlink(tmp)
replace(release/name,source=source);replace(public/name,source=source);replace(public/'dsh-app-latest.apk',source=source)
replace(public/'version.json',data={**meta,'date':datetime.date.today().isoformat()})
replace(public/'latest.json',data=meta);replace(release/'latest.json',data=meta)
print(json.dumps({'version':meta['version'],'versionCode':meta['versionCode'],'sha256':meta['sha256'],'backup':str(backup)}))
"""


def run(args, **kwargs):
    return subprocess.run(
        args, check=True, text=True, capture_output=True, **kwargs
    ).stdout


def certificate(tool, apk):
    result = run([str(tool), "verify", "--print-certs", str(apk)])
    return next(
        line
        for line in result.splitlines()
        if line.startswith("Signer #1 certificate SHA-256 digest:")
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", default="sx-server")
    parser.add_argument("--origin", default="https://dsh.sixuanai.com")
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--notes", default="详见应用内更新日志")
    parser.add_argument("--previous-apk", type=Path)
    parser.add_argument("--cdn-config", type=Path, default=Path(__file__).resolve().parents[1]/"server/release-cdn.json")
    parser.add_argument("--no-cdn", action="store_true", help="Publish an origin-only release explicitly")
    args = parser.parse_args()
    origin = args.origin.rstrip("/")
    if not re.fullmatch(r"https://[A-Za-z0-9.-]+(?::[0-9]+)?", origin):
        raise SystemExit("Use an HTTPS origin")
    sdk = Path("/usr/lib/android-sdk/build-tools")
    tools = sorted(
        p
        for p in sdk.iterdir()
        if (p / "aapt").is_file() and (p / "apksigner").is_file()
    )[-1]
    badging = run([str(tools / "aapt"), "dump", "badging", str(args.apk)]).splitlines()[
        0
    ]
    match = re.search(
        r"name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", badging
    )
    if (
        not match
        or match[1] != "dev.dsh.dsh_mobile"
        or match[3] != args.expected_version
    ):
        raise SystemExit("APK identity/version mismatch")
    data = args.apk.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    cert = certificate(tools / "apksigner", args.apk)
    ssh = ["ssh", "-T", "-o", "BatchMode=yes", args.server]
    old = json.loads(run(ssh + ["sudo -n cat /var/www/dsh-releases/latest.json"]))
    if int(match[2]) < old["versionCode"]:
        raise SystemExit("APK versionCode would downgrade the installed version")
    with tempfile.TemporaryDirectory(prefix="xharness-publish-") as temp:
        previous = args.previous_apk or Path(temp) / "previous.apk"
        if not args.previous_apk:
            with urllib.request.urlopen(
                urllib.request.Request(origin + "/releases-public/dsh-app-latest.apk", headers={"User-Agent":"xHarness-Publisher/1.0"}), timeout=60
            ) as response:
                previous.write_bytes(response.read())
        if hashlib.sha256(previous.read_bytes()).hexdigest() != old["sha256"]:
            raise SystemExit("Previous APK integrity mismatch")
        if certificate(tools / "apksigner", previous) != cert:
            raise SystemExit("Release signing certificate changed; cannot upgrade")
        meta = {
            "version": match[3],
            "versionCode": int(match[2]),
            "url": origin + "/releases-public/dsh-app-" + match[3] + ".apk",
            "notes": args.notes,
            "size": len(data),
            "sha256": digest,
        }
        if args.cdn_config.exists() and not args.no_cdn:
            from cloudflare_release import R2ReleaseStore
            mirror = R2ReleaseStore(args.cdn_config).upload(args.apk, match[3], digest)
            meta["cdnUrl"] = mirror["url"]
        stage = run(ssh + ["mktemp -d /tmp/xharness-ota.XXXXXXXX"]).strip()
        try:
            subprocess.run(
                [
                    "scp",
                    "-q",
                    str(args.apk),
                    args.server + ":" + stage + "/package.apk",
                ],
                check=True,
            )
            result = run(
                ssh
                + [
                    "sudo -n python3 -c "
                    + shlex.quote(REMOTE)
                    + " "
                    + shlex.quote(stage)
                ],
                input=json.dumps(meta),
            )
            print(result.strip())
        finally:
            run(ssh + ["rm -rf -- " + shlex.quote(stage)])
    with urllib.request.urlopen(
        origin + "/releases-public/latest.json", timeout=20
    ) as response:
        published = json.load(response)
    if published != meta:
        raise SystemExit("Published manifest does not match verified APK")
    if meta.get("cdnUrl") or args.no_cdn:
        from configure_release_cdn import activate
        print(json.dumps(activate(args.server, meta)))
        # Activation adds the same verified mirror hint, preserving the origin
        # URL so older clients strip account headers on the CDN redirect.
    downloaded = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(urllib.request.Request(published["url"], headers={"User-Agent":"xHarness-Publisher/1.0"}), timeout=60) as response:
        while chunk := response.read(1048576):
            downloaded.update(chunk)
            size += len(chunk)
    if downloaded.hexdigest() != digest or size != meta["size"]:
        raise SystemExit("Public download integrity mismatch")
    print(
        "PASS public manifest, downloadable APK hash, versionCode and upgrade signing certificate"
    )


if __name__ == "__main__":
    main()
