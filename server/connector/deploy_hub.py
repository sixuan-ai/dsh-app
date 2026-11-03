#!/usr/bin/env python3
"""Operator installer: run as root on an existing Linux HTTPS gateway."""

import argparse
import datetime
import os
import pwd
import shutil
import subprocess
import urllib.parse
from pathlib import Path


def run(*args):
    subprocess.run(args, check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--origin", required=True)
    p.add_argument("--nginx-site", type=Path, required=True)
    p.add_argument(
        "--accounts", type=Path, default=Path("/etc/dsh-directory/users.json")
    )
    a = p.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Run as root on the gateway only")
    u = urllib.parse.urlsplit(a.origin)
    if (
        u.scheme != "https"
        or not u.hostname
        or u.path not in ("", "/")
        or u.username
        or u.query
        or u.fragment
    ):
        raise SystemExit("Use an HTTPS origin")
    if not a.accounts.is_file() or not a.nginx_site.is_file():
        raise SystemExit("Existing account directory and nginx site are required")
    site = a.nginx_site.resolve()
    original = site.read_text()
    marker = "    include /etc/nginx/snippets/xharness-connector.conf;"
    if marker not in original:
        # Insert immediately before the first server_name matching this origin.
        needle = "server_name " + u.hostname + ";"
        if original.count(needle) < 1:
            raise SystemExit("Origin does not match nginx site")
        if "location ^~ /connector/" in original or "location /connector/" in original:
            raise SystemExit("An existing /connector/ location needs operator review")
        candidate = original.replace("    " + needle, marker + "\n    " + needle, 1)
    else:
        candidate = original
    try:
        user = pwd.getpwnam("xharness-hub")
    except KeyError:
        run(
            "useradd",
            "--system",
            "--home-dir",
            "/nonexistent",
            "--shell",
            "/usr/sbin/nologin",
            "xharness-hub",
        )
        user = pwd.getpwnam("xharness-hub")
    source = Path(__file__).resolve().parent
    runtime = Path("/opt/xharness-hub")
    runtime.mkdir(mode=0o755, exist_ok=True)
    for name in ["hub.py", "connector.py", "sync_accounts.py"]:
        shutil.copy2(source / name, runtime / name)
        (runtime / name).chmod(0o644)
    state = Path("/var/lib/xharness-hub")
    state.mkdir(mode=0o700, exist_ok=True)
    os.chown(state, user.pw_uid, user.pw_gid)
    state.chmod(0o700)
    accounts = Path("/var/lib/xharness-accounts/accounts.json")
    run(
        "/usr/bin/python3",
        str(runtime / "sync_accounts.py"),
        "--source",
        str(a.accounts),
        "--target",
        str(accounts),
        "--group",
        "xharness-hub",
    )
    envdir = Path("/etc/xharness-hub")
    envdir.mkdir(mode=0o700, exist_ok=True)
    env = envdir / "hub.env"
    env.write_text(
        "CONNECTOR_USERS_FILE="
        + str(accounts)
        + "\nCONNECTOR_PUBLIC_ORIGIN="
        + a.origin.rstrip("/")
        + "\n"
    )
    env.chmod(0o600)
    units = Path("/etc/systemd/system")
    shutil.copy2(source / "xharness-hub.service.sample", units / "xharness-hub.service")
    # Quote the complete ExecStart arguments, never interpolate account content.
    quote = (
        lambda v: '"'
        + str(v).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
        + '"'
    )
    (units / "xharness-accounts.service").write_text(
        "[Unit]\nDescription=Export xHarness account verifiers\n[Service]\nType=oneshot\nUMask=0027\nExecStart=/usr/bin/python3 /opt/xharness-hub/sync_accounts.py --source "
        + quote(a.accounts)
        + " --target "
        + quote(accounts)
        + " --group xharness-hub\n"
    )
    (units / "xharness-accounts.path").write_text(
        "[Unit]\nDescription=Watch xHarness account changes\n[Path]\nPathChanged="
        + str(a.accounts.parent)
        + "\nUnit=xharness-accounts.service\n[Install]\nWantedBy=multi-user.target\n"
    )
    (units / "xharness-accounts.timer").write_text(
        "[Unit]\nDescription=Reconcile xHarness account verifiers\n[Timer]\nOnBootSec=30s\nOnUnitActiveSec=60s\nUnit=xharness-accounts.service\n[Install]\nWantedBy=timers.target\n"
    )
    snippet = Path("/etc/nginx/snippets/xharness-connector.conf")
    snippet.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "nginx-connector.conf.sample", snippet)
    backup = site.with_name(
        site.name
        + ".xharness-backup-"
        + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    )
    shutil.copy2(site, backup)
    try:
        site.write_text(candidate)
        run("nginx", "-t")
        run("systemctl", "daemon-reload")
        run(
            "systemctl",
            "enable",
            "--now",
            "xharness-accounts.path",
            "xharness-accounts.timer",
            "xharness-hub.service",
        )
        run("systemctl", "restart", "xharness-hub.service")
        run("systemctl", "reload", "nginx")
    except subprocess.CalledProcessError:
        shutil.copy2(backup, site)
        run("nginx", "-t")
        raise
    print(
        "Hub installed on loopback 3087; existing DSH route retained. nginx backup: "
        + str(backup)
    )


if __name__ == "__main__":
    main()
