#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${HOME}/.config/harmonyos/env.sh"

if [[ ! -f "${env_file}" ]]; then
  echo "HarmonyOS environment not found: ${env_file}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${env_file}"
cd "${project_root}"

mode="signed"
if [[ "${1:-}" == "--unsigned" ]]; then
  mode="unsigned"
fi

flutter-oh pub get

if [[ "${mode}" == "unsigned" ]]; then
  flutter-oh build hap --release --no-codesign
  exit
fi

if ! hdc list targets 2>/dev/null | grep -q '[[:alnum:]]'; then
  cat >&2 <<'EOF'
No HarmonyOS device is connected.
Enable Developer mode and USB debugging on the phone, connect it by USB, and
accept the computer authorization prompt. Then run this script again.
EOF
  exit 2
fi

(
  cd ohos
  devecocli signature generate
)

if ! grep -q '"storeFile"' ohos/build-profile.json5; then
  echo "DevEco CLI did not write signing material to ohos/build-profile.json5." >&2
  exit 3
fi

flutter-oh build hap --release
