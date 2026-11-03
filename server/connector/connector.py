#!/usr/bin/env python3
"""Linux xHarness connector. Never owns or removes an existing DSH service."""

import argparse
import base64
import contextlib
import getpass
import hashlib
import http.client
import ipaddress
import json
import os
import re
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

DEFAULT_STATE = Path.home() / ".local/share/xharness-connector"


def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_name(path.name + "." + uuid.uuid4().hex)
    fd = os.open(tmp, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


@contextlib.contextmanager
def mutation(state):
    lock = state / ".mutation-lock"
    until = time.monotonic() + 5
    while True:
        try:
            lock.mkdir(mode=0o700)
            break
        except FileExistsError:
            # A dead writer can be recovered without rotating device credentials.
            try:
                pid = int((lock / "pid").read_text())
                os.kill(pid, 0)
            except ProcessLookupError:
                (lock / "pid").unlink(missing_ok=True)
                try:
                    lock.rmdir()
                except OSError:
                    pass
                continue
            except (OSError, ValueError):
                if time.time() - lock.stat().st_mtime > 30:
                    (lock / "pid").unlink(missing_ok=True)
                    try:
                        lock.rmdir()
                    except OSError:
                        pass
            if time.monotonic() > until:
                raise ValueError("连接器正在处理其他操作，请重试")
            time.sleep(0.05)
    (lock / "pid").write_text(str(os.getpid()))
    try:
        yield
    finally:
        (lock / "pid").unlink(missing_ok=True)
        lock.rmdir()


def read(path, fallback=None):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return fallback


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def quote(value):
    if "\n" in str(value) or "\r" in str(value):
        raise ValueError("Invalid path")
    return (
        '"'
        + str(value).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
        + '"'
    )


def systemctl(*args):
    run(["systemctl", "--user", *args])


def http_status(host, port, auth=None):
    try:
        c = http.client.HTTPConnection(host, port, timeout=2)
        c.request("GET", "/", headers={"Authorization": auth} if auth else {})
        r = c.getresponse()
        r.read(4096)
        c.close()
        return r.status
    except OSError:
        return None


def lan_addresses():
    result = []
    try:
        values = subprocess.check_output(["hostname", "-I"], text=True).split()
    except (OSError, subprocess.CalledProcessError):
        values = []
    for value in values:
        try:
            ip = ipaddress.ip_address(value)
            if (
                ip.version == 4
                and ip.is_private
                and not ip.is_loopback
                and not ip in ipaddress.ip_network("100.64.0.0/10")
            ):
                result.append(value)
        except ValueError:
            pass
    try:
        routes = json.loads(
            subprocess.check_output(["ip", "-j", "route", "show", "default"], text=True)
        )
        preferred = [r.get("prefsrc") for r in routes if r.get("prefsrc") in result]
        result = preferred + [v for v in result if v not in preferred]
    except (OSError, ValueError, subprocess.CalledProcessError):
        pass
    return result


def tls_get(url, pin):
    u = urllib.parse.urlsplit(url)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    c = http.client.HTTPSConnection(u.hostname, u.port or 443, context=ctx, timeout=4)
    c.connect()
    if hashlib.sha256(c.sock.getpeercert(binary_form=True)).hexdigest() != pin:
        c.close()
        raise ValueError("Connector certificate changed")
    c.request("GET", u.path or "/")
    r = c.getresponse()
    b = r.read(8192)
    c.close()
    return r.status, json.loads(b)


def detect_dsh(url, token_file, token_unit=None):
    if url:
        u = urllib.parse.urlsplit(url)
        if (
            u.scheme != "http"
            or u.hostname not in ("127.0.0.1", "localhost")
            or u.username
            or u.path not in ("", "/")
            or u.query
            or u.fragment
        ):
            raise ValueError("DSH upstream must be a loopback HTTP URL without a token")
        port = u.port or 80
    else:
        port = next(
            (
                p
                for p in [18395, 3080]
                if http_status("127.0.0.1", p) in (200, 401, 403)
            ),
            None,
        )
    log = (
        Path(token_file).expanduser()
        if token_file
        else Path.home() / ".dsh/dsh-desktop.log"
    )
    if port:
        if token_unit:
            if not re.fullmatch(r"[A-Za-z0-9_.@-]+\.service", token_unit):
                raise ValueError("无效的 DSH systemd 服务名")
            if subprocess.run(
                ["systemctl", "--user", "is-active", "--quiet", token_unit]
            ).returncode:
                raise ValueError("指定的 DSH 用户服务尚未运行")
            recent = subprocess.check_output(
                [
                    "/usr/bin/journalctl",
                    "--user",
                    "-u",
                    token_unit,
                    "-n",
                    "200",
                    "-o",
                    "cat",
                    "--no-pager",
                ],
                text=True,
                timeout=4,
            )
            if not re.search(r"token=[A-Za-z0-9_-]+", recent):
                raise ValueError("DSH 服务日志中未找到启动授权信息")
            return port, "", False
        if not log.is_file():
            raise ValueError(
                "发现已有 DSH，但需要其启动日志：使用 --token-file PATH；不会重启现有 DSH"
            )
        if http_status("127.0.0.1", port) not in (200, 401, 403):
            raise ValueError("DSH upstream not reachable")
        with log.open("rb") as stream:
            stream.seek(max(0, log.stat().st_size - 1048576))
            recent = stream.read().decode("utf-8", errors="replace")
        if not re.search(r"token=[A-Za-z0-9_-]+", recent):
            raise ValueError(
                "启动日志中没有找到 DSH 授权信息，请确认 --token-file 指向当前 DSH 启动日志"
            )
        return port, str(log.resolve()), False
    if not shutil.which(
        "dsh",
        path=str(Path.home() / ".local/bin") + os.pathsep + os.environ.get("PATH", ""),
    ):
        raise ValueError("没有找到 DSH；请先安装 DeepSeek Harness，再运行连接器安装")
    return 18395, None, True


def install(args):
    if args.state.resolve() in (Path.home().resolve(), Path("/")):
        raise ValueError("请选择连接器专用数据目录")
    state = args.state.resolve()
    if (
        state.exists()
        and any(state.iterdir())
        and not (state / "config.json").exists()
        and not (state / ".xharness-connector").exists()
    ):
        raise ValueError("数据目录非空且不是连接器目录，请选择专用目录")
    if (
        Path.home() / ".config/systemd/user/xharness-connector.service"
    ).exists() and not (state / "config.json").exists():
        raise ValueError(
            "当前账号已有连接器服务，请使用原数据目录维护；每个账号仅支持一套连接器"
        )
    units = Path.home() / ".config/systemd/user"
    units.mkdir(parents=True, exist_ok=True)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    if (state / "config.json").exists():
        raise ValueError(
            "连接器已安装；更新使用 update，诊断使用 doctor，不覆盖设备密钥"
        )
    node = shutil.which("node")
    openssl = shutil.which("openssl")
    if not node or not openssl:
        raise ValueError("需要 Node.js 20+ 与 OpenSSL")
    if (
        int(
            subprocess.check_output(
                [node, "-p", 'process.versions.node.split(".")[0]'], text=True
            )
        )
        < 20
    ):
        raise ValueError("需要 Node.js 20+")
    port, log, managed = detect_dsh(args.dsh_url, args.token_file, args.token_unit)
    for p in [args.port, args.bridge_port]:
        with socket.socket() as s:
            try:
                s.bind(("0.0.0.0", p))
            except OSError:
                raise ValueError(f"端口 {p} 已被占用，未修改现有服务")
    runtime = state / "runtime"
    runtime.mkdir(mode=0o700, exist_ok=True)
    source = Path(__file__).resolve().parent
    for name in ["gateway.js", "connector.py", "desktop.py"]:
        shutil.copy2(source / name, runtime / name)
    shutil.copytree(source / "ui", runtime / "ui", dirs_exist_ok=True)
    shutil.copy2(source.parent / "dsh-auth-proxy.js", runtime / "dsh-auth-proxy.js")
    if (source / "hub.py").exists():
        shutil.copy2(source / "hub.py", runtime / "hub.py")
    nodeid = str(uuid.uuid4())
    key = state / "tls.key"
    cert = state / "tls.crt"
    run(
        [
            openssl,
            "req",
            "-x509",
            "-newkey",
            "ec",
            "-pkeyopt",
            "ec_paramgen_curve:P-256",
            "-nodes",
            "-keyout",
            str(key),
            "-out",
            str(cert),
            "-days",
            "3650",
            "-subj",
            "/CN=xHarness-" + nodeid,
            "-addext",
            "subjectAltName=DNS:localhost,IP:127.0.0.1",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    key.chmod(0o600)
    cert.chmod(0o600)
    internal_user = "bridge-" + uuid.uuid4().hex
    internal_pass = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip("=")
    cookie = os.urandom(32).hex()
    if managed:
        log = str(state / "dsh.log")
        Path(log).touch(mode=0o600)
        dsh = shutil.which(
            "dsh",
            path=str(Path.home() / ".local/bin")
            + os.pathsep
            + os.environ.get("PATH", ""),
        )
        unit = (
            "[Unit]\nDescription=xHarness managed DSH\n[Service]\nExecStart="
            + quote(dsh)
            + " web --no-open --host 127.0.0.1 --port "
            + str(port)
            + "\nRestart=on-failure\nStandardOutput=append:"
            + str(log).replace("%", "%%")
            + "\nStandardError=append:"
            + str(log).replace("%", "%%")
            + "\n[Install]\nWantedBy=default.target\n"
        )
        (units / "xharness-dsh.service").write_text(unit)
    config = {
        "version": 1,
        "nodeId": nodeid,
        "name": args.name or socket.gethostname(),
        "listenHost": "0.0.0.0",
        "port": args.port,
        "tlsKey": str(key),
        "tlsCert": str(cert),
        "enrollmentSecret": os.urandom(32).hex(),
        "upstreamHost": "127.0.0.1",
        "upstreamPort": args.bridge_port,
        "upstreamAuthorization": "Basic "
        + base64.b64encode((internal_user + ":" + internal_pass).encode()).decode(),
        "dshPort": port,
        "tokenFile": log,
        "tokenUnit": args.token_unit,
        "managedDsh": managed,
    }
    atomic(state / "config.json", config)
    atomic(state / "devices.json", {"version": 1, "devices": []})
    atomic(state / "pairings.json", {"version": 1, "pairings": []})
    env = {
        "LISTEN_HOST": "127.0.0.1",
        "LISTEN_PORT": args.bridge_port,
        "UPSTREAM_HOST": "127.0.0.1",
        "UPSTREAM_PORT": port,
        "AUTH_USER": internal_user,
        "AUTH_PASSWORD": internal_pass,
        "AUTH_COOKIE_SECRET": cookie,
        "DSH_TOKEN_FILE": log,
        "DSH_TOKEN_UNIT": args.token_unit or "",
        "DSH_COOKIE_CACHE": str(state / "broker.cookie"),
    }
    envfile = state / "bridge.env"
    envfile.write_text(
        "\n".join(k + "=" + json.dumps(str(v)) for k, v in env.items()) + "\n"
    )
    envfile.chmod(0o600)
    for name, command, extra in [
        (
            "xharness-auth-bridge",
            quote(node) + " " + quote(runtime / "dsh-auth-proxy.js"),
            "EnvironmentFile=" + str(envfile).replace("%", "%%"),
        ),
        (
            "xharness-connector",
            quote(node) + " " + quote(runtime / "gateway.js"),
            "Environment=" + quote("XHARNESS_CONFIG=" + str(state / "config.json")),
        ),
    ]:
        (units / (name + ".service")).write_text(
            "[Unit]\nDescription="
            + name
            + "\nAfter=network-online.target\n[Service]\n"
            + extra
            + "\nExecStart="
            + command
            + "\nRestart=on-failure\nUMask=0077\n[Install]\nWantedBy=default.target\n"
        )
    atomic(
        state / "installation.json",
        {"managedDsh": managed, "installedAt": int(time.time()), "source": str(source)},
    )
    systemctl("daemon-reload")
    names = (["xharness-dsh.service"] if managed else []) + [
        "xharness-auth-bridge.service",
        "xharness-connector.service",
    ]
    systemctl("enable", "--now", *names)
    wait_ready(state)
    desktop_shortcut(state)
    print(
        "连接器已安装；现有 DSH 与旧 3081 入口未修改。运行 doctor 检查，再运行 pair 显示配对码。"
    )


def wait_ready(state):
    c = read(state / "config.json")
    until = time.monotonic() + 15
    while time.monotonic() < until:
        try:
            ready = (
                http_status(
                    c["upstreamHost"], c["upstreamPort"], c["upstreamAuthorization"]
                )
                == 200
            )
            status, info = tls_get(
                f"https://127.0.0.1:{c['port']}/connector/info", fingerprint(c)
            )
            if ready and status == 200 and info.get("nodeId") == c["nodeId"]:
                return
        except (OSError, ValueError):
            pass
        time.sleep(0.25)
    raise ValueError(
        "连接器配置已保留，但健康检查未通过；运行 doctor 查看状态，修复后运行 repair"
    )


def fingerprint(config):
    der = ssl.PEM_cert_to_DER_cert(Path(config["tlsCert"]).read_text())
    return hashlib.sha256(der).hexdigest()


def pair(args):
    state = args.state
    c = read(state / "config.json")
    if not c:
        raise ValueError("请先安装连接器")
    host = args.host or next(iter(lan_addresses()), None)
    if not host:
        raise ValueError("没有发现局域网地址；使用 --host 指定手机可达的电脑地址")
    ip = ipaddress.ip_address(host)
    if not (ip.is_private or ip in ipaddress.ip_network("100.64.0.0/10")):
        raise ValueError("配对地址必须是本机私人网络地址")
    if host not in lan_addresses() + ["127.0.0.1"]:
        try:
            own = subprocess.check_output(["tailscale", "ip", "-4"], text=True).split()
        except (OSError, subprocess.CalledProcessError):
            own = []
        if host not in own:
            raise ValueError("配对地址必须属于本机")
    with mutation(state):
        now = int(time.time() * 1000)
        ident = uuid.uuid4().hex
        code = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip("=")
        pairs = read(state / "pairings.json", {"version": 1, "pairings": []})
        pairs["pairings"] = [
            p
            for p in pairs["pairings"]
            if p.get("expiresAt", 0) > now and not p.get("used")
        ]
        pairs["pairings"].append({"id": ident, "code": code, "expiresAt": now + 120000})
        atomic(state / "pairings.json", pairs)
        payload = {
            "version": 1,
            "nodeId": c["nodeId"],
            "name": c["name"],
            "endpoint": f"https://{host}:{c['port']}",
            "fingerprint": fingerprint(c),
            "id": ident,
            "code": code,
            "expiresAt": now + 120000,
        }
        link = "xharness://pair?data=" + base64.urlsafe_b64encode(
            json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()
        ).decode().rstrip("=")
        out = args.output or state / "pairing.json"
        atomic(out, {"link": link, "payload": payload})
        svg = Path(out).with_suffix(".svg")
        try:
            import qrcode
            import qrcode.image.svg

            image = qrcode.make(link, image_factory=qrcode.image.svg.SvgPathImage)
            image.save(svg)
            svg.chmod(0o600)
            print("配对二维码：" + str(svg))
        except ImportError:
            print(
                "二维码模块未安装：请使用安装包自带 Python 环境，或安装 qrcode==8.2；配对链接文件仍可导入。"
            )
        print(
            "配对文件："
            + str(out)
            + "；2分钟内有效，仅能使用一次。请在手机“连接我的电脑”导入。"
        )


def doctor(args):
    c = read(args.state / "config.json")
    result = {
        "installed": bool(c),
        "lanAddresses": lan_addresses(),
        "services": {},
        "checks": {},
    }
    if c:
        for n in ["xharness-auth-bridge", "xharness-connector"] + (
            ["xharness-dsh"] if c.get("managedDsh") else []
        ):
            result["services"][n] = subprocess.run(
                ["systemctl", "--user", "is-active", n + ".service"],
                capture_output=True,
                text=True,
            ).stdout.strip()
        result["checks"]["dshHttpStatus"] = http_status("127.0.0.1", c["dshPort"])
        result["checks"]["authenticatedBridgeHttpStatus"] = http_status(
            c["upstreamHost"], c["upstreamPort"], c["upstreamAuthorization"]
        )
        try:
            status, info = tls_get(
                f"https://127.0.0.1:{c['port']}/connector/info", fingerprint(c)
            )
            result["checks"]["tlsIdentity"] = (
                status == 200 and info.get("nodeId") == c["nodeId"]
            )
        except (OSError, ValueError):
            result["checks"]["tlsIdentity"] = False
        remote = read(args.state / "remote.json", {})
        result["remoteConfigured"] = bool(remote.get("url"))
        if remote.get("url"):
            try:
                with urllib.request.urlopen(
                    remote["url"] + "/connector/info", timeout=4
                ) as r:
                    result["checks"]["remoteIdentity"] = (
                        json.load(r).get("nodeId") == c["nodeId"]
                    )
            except Exception:
                result["checks"]["remoteIdentity"] = False
    print(json.dumps(result, ensure_ascii=False, indent=2))


class NoCredentialRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def remote_enroll(state, gateway, username, password):
    c = read(state / "config.json")
    if not c:
        raise ValueError("请先安装连接器")
    u = urllib.parse.urlsplit(gateway)
    if (
        u.scheme != "https"
        or not u.hostname
        or u.username
        or u.query
        or u.fragment
        or u.path.rstrip("/")
    ):
        raise ValueError("公网网关必须是 HTTPS 根地址")
    if not username or not password:
        raise ValueError("请输入网关账号和密码")
    try:
        address = (
            subprocess.check_output(
                ["tailscale", "ip", "-4"], text=True, stderr=subprocess.DEVNULL
            )
            .strip()
            .split()[0]
        )
    except (OSError, subprocess.CalledProcessError, IndexError):
        raise ValueError(
            "请先在电脑完成 Tailscale 登录，并由网关管理员授权仅访问连接器端口"
        )
    payload = {
        "nodeId": c["nodeId"],
        "name": c["name"],
        "address": address,
        "port": c["port"],
        "fingerprint": fingerprint(c),
        "enrollmentSecret": c["enrollmentSecret"],
    }
    auth = base64.b64encode((username + ":" + password).encode()).decode()
    request = urllib.request.Request(
        gateway.rstrip("/") + "/connector/enroll",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Basic " + auth},
    )
    opener = urllib.request.build_opener(NoCredentialRedirect())
    with opener.open(request, timeout=15) as r:
        reply = json.load(r)
    if reply.get("nodeId") != c["nodeId"]:
        raise ValueError("网关返回的电脑身份不匹配")
    target = urllib.parse.urlsplit(reply["url"])
    if (
        target.scheme != "https"
        or target.netloc != u.netloc
        or target.path != "/connector/" + c["nodeId"]
    ):
        raise ValueError("网关返回了不匹配的公网地址")
    atomic(state / "remote.json", {"url": reply["url"]})


def remote(args):
    pw = getpass.getpass("网关账号密码（仅通过 HTTPS 发送到所选网关）：")
    remote_enroll(args.state, args.gateway, args.username, pw)
    print("公网连接已绑定；重新生成配对码即可供手机使用。")


def desktop_shortcut(state):
    applications = Path.home() / ".local/share/applications"
    applications.mkdir(parents=True, exist_ok=True)
    python = Path(sys.executable).resolve()
    # Keep the installer venv when invoked from it (resolving loses venv context).
    if sys.prefix != sys.base_prefix:
        python = Path(sys.executable).absolute()
    command = " ".join(
        quote(v) for v in [python, state / "runtime/desktop.py", "--state", state]
    )
    (applications / "xharness-connector.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=xHarness 电脑连接器\nComment=配对手机、连接诊断与设备撤销\nExec="
        + command
        + "\nIcon=network-workgroup\nTerminal=false\nCategories=Network;Development;\n"
    )


def repair(args):
    c = read(args.state / "config.json")
    if not c:
        raise ValueError("没有可恢复的连接器配置，请先 install")
    units = Path.home() / ".config/systemd/user"
    runtime = args.state / "runtime"
    node = shutil.which("node")
    if not node:
        raise ValueError("需要 Node.js 20+")
    for n, script, extra in [
        (
            "xharness-auth-bridge",
            "dsh-auth-proxy.js",
            "EnvironmentFile=" + str(args.state / "bridge.env").replace("%", "%%"),
        ),
        (
            "xharness-connector",
            "gateway.js",
            "Environment="
            + quote("XHARNESS_CONFIG=" + str(args.state / "config.json")),
        ),
    ]:
        (units / (n + ".service")).write_text(
            "[Unit]\nDescription="
            + n
            + "\nAfter=network-online.target\n[Service]\n"
            + extra
            + "\nExecStart="
            + quote(node)
            + " "
            + quote(runtime / script)
            + "\nRestart=on-failure\nUMask=0077\n[Install]\nWantedBy=default.target\n"
        )
    if c.get("managedDsh") and not (units / "xharness-dsh.service").exists():
        dsh = shutil.which(
            "dsh",
            path=str(Path.home() / ".local/bin")
            + os.pathsep
            + os.environ.get("PATH", ""),
        )
        if not dsh:
            raise ValueError("需要重新安装 DSH")
        (units / "xharness-dsh.service").write_text(
            "[Service]\nExecStart="
            + quote(dsh)
            + " web --no-open --host 127.0.0.1 --port "
            + str(c["dshPort"])
            + "\nStandardOutput=append:"
            + str(c["tokenFile"]).replace("%", "%%")
            + "\nStandardError=append:"
            + str(c["tokenFile"]).replace("%", "%%")
            + "\nRestart=on-failure\n[Install]\nWantedBy=default.target\n"
        )
    systemctl("daemon-reload")
    subprocess.run(
        [
            "systemctl",
            "--user",
            "reset-failed",
            "xharness-auth-bridge.service",
            "xharness-connector.service",
        ],
        capture_output=True,
    )
    systemctl(
        "enable",
        "--now",
        *(["xharness-dsh.service"] if c.get("managedDsh") else []),
        "xharness-auth-bridge.service",
        "xharness-connector.service",
    )
    wait_ready(args.state)
    desktop_shortcut(args.state)
    print("连接器已恢复，保留原电脑身份和配对。")


def revoke_device(state, ident):
    with mutation(state):
        store = read(state / "devices.json", {})
        found = False
        for d in store.get("devices", []):
            if d["id"] == ident:
                d["revoked"] = True
                found = True
        if not found:
            raise ValueError("设备不存在")
        atomic(state / "devices.json", store)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--state", type=Path, default=DEFAULT_STATE)
    sub = p.add_subparsers(dest="command", required=True)
    a = sub.add_parser("install")
    a.add_argument("--dsh-url")
    a.add_argument("--token-file")
    a.add_argument("--token-unit", help="已有 DSH 用户服务，例如 dsh-web.service")
    a.add_argument("--name")
    a.add_argument("--port", type=int, default=3082)
    a.add_argument("--bridge-port", type=int, default=3083)
    a = sub.add_parser("pair")
    a.add_argument("--host")
    a.add_argument("--output", type=Path)
    sub.add_parser("doctor")
    sub.add_parser("devices")
    a = sub.add_parser("revoke")
    a.add_argument("id")
    a = sub.add_parser("remote")
    a.add_argument("--gateway", required=True)
    a.add_argument("--username", required=True)
    sub.add_parser("uninstall")
    sub.add_parser("update")
    sub.add_parser("repair")
    sub.add_parser("open")
    args = p.parse_args()
    args.state = args.state.expanduser().resolve()
    try:
        if args.command == "install":
            install(args)
        elif args.command == "pair":
            pair(args)
        elif args.command == "doctor":
            doctor(args)
        elif args.command == "remote":
            remote(args)
        elif args.command == "repair":
            repair(args)
        elif args.command == "open":
            from desktop import serve

            serve(args.state)
        elif args.command == "devices":
            print(
                json.dumps(
                    [
                        {k: d.get(k) for k in ["id", "name", "createdAt", "revoked"]}
                        for d in read(args.state / "devices.json", {}).get(
                            "devices", []
                        )
                    ],
                    ensure_ascii=False,
                    indent=2,
                )
            )
        elif args.command == "revoke":
            revoke_device(args.state, args.id)
            print("设备已撤销；现有长连接会关闭。")
        elif args.command == "uninstall":
            c = read(args.state / "config.json", {})
            if not c or c.get("version") != 1:
                raise ValueError("该数据目录中没有已安装的连接器")
            names = ["xharness-connector", "xharness-auth-bridge"] + (
                ["xharness-dsh"] if c.get("managedDsh") else []
            )
            for n in names:
                subprocess.run(
                    ["systemctl", "--user", "disable", "--now", n + ".service"],
                    check=False,
                )
                (Path.home() / ".config/systemd/user" / (n + ".service")).unlink(
                    missing_ok=True
                )
            (
                Path.home() / ".local/share/applications/xharness-connector.desktop"
            ).unlink(missing_ok=True)
            systemctl("daemon-reload")
            print("已卸载连接器服务；配置和配对数据保留，现有用户 DSH 不受影响。")
        elif args.command == "update":
            if not read(args.state / "config.json"):
                raise ValueError("请先安装连接器")
            source = Path(__file__).resolve().parent
            for name in ["gateway.js", "connector.py", "desktop.py"]:
                dest = args.state / "runtime" / name
                if (source / name).resolve() != dest.resolve():
                    shutil.copy2(source / name, dest)
            if (source / "ui").resolve() != (args.state / "runtime/ui").resolve():
                shutil.copytree(
                    source / "ui", args.state / "runtime/ui", dirs_exist_ok=True
                )
            proxy_source = source.parent / "dsh-auth-proxy.js"
            if not proxy_source.is_file():
                proxy_source = source / "dsh-auth-proxy.js"
            proxy_dest = args.state / "runtime/dsh-auth-proxy.js"
            if (
                proxy_source.is_file()
                and proxy_source.read_bytes() != proxy_dest.read_bytes()
            ):
                shutil.copy2(proxy_source, proxy_dest)
                systemctl("restart", "xharness-auth-bridge.service")
            desktop_shortcut(args.state)
            systemctl("restart", "xharness-connector.service")
            print("连接器已更新；没有轮换密钥或重启 DSH。")
    except (
        OSError,
        ValueError,
        subprocess.SubprocessError,
        urllib.error.URLError,
    ) as e:
        print("连接器操作失败：" + str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
