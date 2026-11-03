#!/usr/bin/env python3
"""Root-only export of salted account verifiers, without sharing plaintext records."""

import argparse
import grp
import hashlib
import json
import os
import re
import secrets
from pathlib import Path


def export(source, target, group):
    users = json.loads(source.read_text())
    previous = {}
    try:
        previous = json.loads(target.read_text())
    except (OSError, ValueError):
        pass
    result = {}
    for name, user in users.items():
        if (
            not isinstance(user, dict)
            or not isinstance(user.get("password"), str)
            or not user["password"]
        ):
            continue
        old = previous.get(name, {})
        salt = old.get("salt") if old.get("algorithm") == "pbkdf2-sha256" else None
        if not isinstance(salt, str) or not re.fullmatch("[a-f0-9]{32}", salt):
            salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac(
            "sha256", user["password"].encode(), bytes.fromhex(salt), 210000
        ).hex()
        result[name] = {
            "email": str(user.get("email", "")),
            "algorithm": "pbkdf2-sha256",
            "salt": salt,
            "digest": digest,
            "iterations": 210000,
        }
    if result == previous:
        return
    existed = target.parent.exists()
    target.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    if not existed:
        if group:
            os.chown(target.parent, 0, grp.getgrnam(group).gr_gid)
        target.parent.chmod(0o750)
    tmp = target.with_name(target.name + "." + secrets.token_hex(8))
    fd = os.open(tmp, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o640)
    with os.fdopen(fd, "w") as f:
        json.dump(result, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    tmp.chmod(0o640)
    if group:
        os.chown(tmp, 0, grp.getgrnam(group).gr_gid)
    os.replace(tmp, target)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--target", type=Path, required=True)
    p.add_argument("--group")
    a = p.parse_args()
    export(a.source, a.target, a.group)
