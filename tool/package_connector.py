#!/usr/bin/env python3
"""Build an explicit allowlisted Linux connector bundle; never package local state."""

import argparse
import hashlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/connector-release")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    version = next(
        line.split(":", 1)[1].strip().split("+")[0]
        for line in (ROOT / "pubspec.yaml").read_text().splitlines()
        if line.startswith("version:")
    )
    name = "xharness-connector-linux-" + version
    with tempfile.TemporaryDirectory(prefix="xharness-package-") as temp:
        package = Path(temp) / name
        connector = package / "server/connector"
        connector.mkdir(parents=True)
        source = ROOT / "server/connector"
        for filename in [
            "connector.py",
            "gateway.js",
            "desktop.py",
            "hub.py",
            "sync_accounts.py",
            "deploy_hub.py",
            "install.sh",
            "requirements.txt",
            "test_connector.py",
            "nginx-connector.conf.sample",
            "xharness-hub.service.sample",
        ]:
            shutil.copy2(source / filename, connector / filename)
        shutil.copytree(source / "ui", connector / "ui")
        shutil.copy2(
            ROOT / "server/dsh-auth-proxy.js", package / "server/dsh-auth-proxy.js"
        )
        shutil.copytree(ROOT / "docs/connector", package / "docs")
        if (ROOT / "LICENSE").is_file():
            shutil.copy2(ROOT / "LICENSE", package / "LICENSE")
        (package / "install.sh").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\ncd -- "$(dirname -- "${BASH_SOURCE[0]}")"\nexec bash server/connector/install.sh "$@"\n'
        )
        (package / "install.sh").chmod(0o755)
        (package / "README.txt").write_text(
            "xHarness "
            + version
            + " Linux 电脑连接器\n\n先安装 DSH、Python 3.10+（venv）、Node.js 20+、OpenSSL，登录 Linux 桌面会话。\n运行：bash install.sh\n完成后从应用菜单打开「xHarness 电脑连接器」。\n详见 docs/README.md；公网首次接入需要管理员授权。\n开源仓库：https://github.com/sixuan-ai/dsh-app\n"
        )
        wheel = connector / "wheels"
        wheel.mkdir()
        subprocess.run(
            [
                sys.executable,
                "-m",
                "pip",
                "download",
                "--disable-pip-version-check",
                "--no-deps",
                "--only-binary=:all:",
                "qrcode==8.2",
                "-d",
                str(wheel),
            ],
            check=True,
        )
        hashes = []
        for file in sorted(package.rglob("*")):
            if file.is_file():
                hashes.append(
                    hashlib.sha256(file.read_bytes()).hexdigest()
                    + "  "
                    + file.relative_to(package).as_posix()
                )
        (package / "CONTENTS.sha256").write_text("\n".join(hashes) + "\n")
        target = out / (name + ".tar.gz")
        with tarfile.open(target, "w:gz") as archive:
            archive.add(package, arcname=name)
        print(target)
    apk = ROOT / "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    if not apk.is_file():
        apk = ROOT / "build/app/outputs/flutter-apk/app-release.apk"
    if apk.is_file():
        shutil.copy2(apk, out / ("xharness-" + version + "-android.apk"))
    files = sorted(
        f for f in out.iterdir() if f.is_file() and f.suffix in (".gz", ".apk")
    )
    (out / "SHA256SUMS").write_text(
        "\n".join(
            hashlib.sha256(f.read_bytes()).hexdigest() + "  " + f.name for f in files
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
