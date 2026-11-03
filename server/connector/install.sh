#!/usr/bin/env bash
set -euo pipefail
# No sudo, no remote shell piping, no changes to an existing DSH service.
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
connector_state="${XHARNESS_STATE:-$HOME/.local/share/xharness-connector}"
for tool in python3 node openssl systemctl; do
  command -v "$tool" >/dev/null || { echo "缺少依赖：$tool（需要 Python 3.10+、venv、Node.js 20+、OpenSSL 和 systemd 用户会话）" >&2; exit 1; }
done
python3 - "$connector_state" <<'PYVALID'
import sys
from pathlib import Path
path=Path(sys.argv[1]).resolve()
if path in (Path.home().resolve(), Path('/')):
    raise SystemExit('请选择连接器专用数据目录')
if path.exists() and any(path.iterdir()) and not(path/'config.json').exists() and not(path/'.xharness-connector').exists():
    raise SystemExit('该目录非空且不是连接器目录，请选择专用目录')
path.mkdir(mode=0o700,parents=True,exist_ok=True)
(path/'.xharness-connector').touch(mode=0o600)
PYVALID
mkdir -p -- "$connector_state"
chmod 700 -- "$connector_state"
if ! test -x "$connector_state/venv/bin/python"; then python3 -m venv "$connector_state/venv"; fi
if test -d "$source_dir/wheels"; then
  "$connector_state/venv/bin/python" -m pip install --disable-pip-version-check --no-index --find-links "$source_dir/wheels" -r "$source_dir/requirements.txt"
else
  "$connector_state/venv/bin/python" -m pip install --disable-pip-version-check -r "$source_dir/requirements.txt"
fi
if test -f "$connector_state/config.json"; then
  "$connector_state/venv/bin/python" "$source_dir/connector.py" --state "$connector_state" update
  "$connector_state/venv/bin/python" "$source_dir/connector.py" --state "$connector_state" repair
else
  "$connector_state/venv/bin/python" "$source_dir/connector.py" --state "$connector_state" install "$@"
fi
"$connector_state/venv/bin/python" "$source_dir/connector.py" --state "$connector_state" doctor
echo '安装完成。在应用菜单中打开「xHarness 电脑连接器」，生成配对二维码。'
