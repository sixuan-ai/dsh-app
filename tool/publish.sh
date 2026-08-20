#!/usr/bin/env bash
# 构建 APK 并发布到公网服务器的 /releases/ 目录(OTA 更新源)。
#
# 用法:
#   tool/publish.sh                     # 发布到默认服务器 root@47.239.235.154
#   SERVER=user@host tool/publish.sh    # 发布到别的服务器
#
# 需要本机有 sshpass;服务器上已按 README 配好 nginx /releases/ 与
# /etc/nginx/.htpasswd-dsh。发布内容:
#   /var/www/dsh-releases/dsh-app-<version>.apk
#   /var/www/dsh-releases/latest.json   (version/versionCode/url/size/sha256)
set -euo pipefail

SERVER="${SERVER:-root@47.239.235.154}"
REMOTE_DIR="/var/www/dsh-releases"
BASE_URL="${BASE_URL:-https://dsh.ainotex.com/releases}"
NOTES="${NOTES:-详见应用内更新日志}"

cd "$(dirname "$0")/.."

VERSION_LINE=$(grep '^version:' pubspec.yaml)
VERSION=${VERSION_LINE#version: }
VERSION=${VERSION%%+*}
CODE=${VERSION_LINE##*+}
APK_NAME="dsh-app-${VERSION}.apk"

echo "==> 构建 v${VERSION}+${CODE}"
export PATH="$PATH:/home/x/flutter/bin"
# release + 单架构:胖包含三份 Flutter 引擎(arm64/armv7/x86_64),目标手机是
# arm64,只打 arm64 可把下载体积砍到约 1/3;release 模板用 debug 密钥签名,
# 与手机上的包签名一致,可直接覆盖安装。
# 需要兼容其他架构时把 ABI 设为 all(打胖包)。
ABI="${ABI:-arm64-v8a}"
if [ "$ABI" = "all" ]; then
  flutter build apk --release >/dev/null
  APK=build/app/outputs/flutter-apk/app-release.apk
else
  flutter build apk --release --split-per-abi >/dev/null
  APK="build/app/outputs/flutter-apk/app-${ABI}-release.apk"
fi

SIZE=$(stat -c%s "$APK")
SHA256=$(sha256sum "$APK" | cut -d' ' -f1)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$APK" "$TMP/$APK_NAME"
cat > "$TMP/latest.json" <<EOF
{
  "version": "${VERSION}",
  "versionCode": ${CODE},
  "url": "${BASE_URL}/${APK_NAME}",
  "notes": "${NOTES}",
  "size": ${SIZE},
  "sha256": "${SHA256}"
}
EOF

SSH_OPTS="-o PubkeyAuthentication=no -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1"
echo "==> 上传到 ${SERVER}:${REMOTE_DIR}"
sshpass -p "$SERVER_PASSWORD" ssh $SSH_OPTS "$SERVER" "mkdir -p $REMOTE_DIR"
sshpass -p "$SERVER_PASSWORD" scp $SSH_OPTS "$TMP/$APK_NAME" "$TMP/latest.json" "$SERVER:$REMOTE_DIR/"

echo "==> 完成: ${BASE_URL}/latest.json"
cat "$TMP/latest.json"
