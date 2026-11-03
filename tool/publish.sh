#!/usr/bin/env bash
# 构建 APK 并发布到公网服务器的 /releases/ 目录(OTA 更新源)。
#
# 用法:
#   tool/publish.sh                     # 自动模式:产物最新则直接复用,否则构建
#   tool/publish.sh --rebuild           # 强制重新构建(忽略已有产物)
#   tool/publish.sh --no-build          # 强制复用已有 APK(不存在或版本不符则报错)
#   tool/publish.sh --dry-run           # 只打印将要执行的步骤,不构建也不上传
#   SERVER=user@host tool/publish.sh    # 发布到别的服务器
#   ABI=all tool/publish.sh             # 打胖包(默认只打 arm64-v8a)
#
# 需要本机有 SSH 密钥认证及网关上的 sudo -n 发布权限；服务器已按 README 配好
# nginx /releases/ 与 /etc/nginx/.htpasswd-dsh。发布内容:
#   /var/www/dsh-releases/dsh-app-<version>.apk
#   /var/www/dsh-releases/latest.json   (version/versionCode/url/size/sha256)
#   /var/www/dsh-releases-public/       (dsh-app-latest.apk + version.json,官网公开下载)
#
# 优化说明:
#   1. 自动复用:APK 比所有源码新且版本匹配时跳过 Gradle 构建(秒级发布)。
#   2. 单架构构建:默认只编 arm64(--target-platform android-arm64),
#      `--split-per-abi` 默认会编 arm64/armv7/x86_64 三份引擎。
#   3. 单次上传:公开副本在服务器端同盘 cp,不再二次传输 24MB。
set -euo pipefail

SERVER="${SERVER:-sx-server}"
REMOTE_DIR="/var/www/dsh-releases"
PUBLIC_DIR="/var/www/dsh-releases-public"
BASE_URL="${BASE_URL:-https://dsh.sixuanai.com/releases-public}"
NOTES="${NOTES:-详见应用内更新日志}"
ABI="${ABI:-arm64-v8a}"

# --- 参数解析 --------------------------------------------------------------
REBUILD=0
NO_BUILD=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=1 ;;
    --no-build) NO_BUILD=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *)
      echo "未知参数: $arg (支持 --rebuild / --no-build / --dry-run)" >&2
      exit 2
      ;;
  esac
done
if [ "$REBUILD" = 1 ] && [ "$NO_BUILD" = 1 ]; then
  echo "--rebuild 与 --no-build 互斥" >&2
  exit 2
fi

# --- ABI -> Flutter target-platform / 产物路径 / versionCode 偏移 -----------
# Flutter split-per-abi 固定偏移:armeabi-v7a +1000, arm64-v8a +2000, x86_64 +3000
case "$ABI" in
  arm64-v8a)
    TARGET_PLATFORM="--target-platform android-arm64"
    APK="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    CODE_OFFSET=2000
    ;;
  armeabi-v7a)
    TARGET_PLATFORM="--target-platform android-arm"
    APK="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
    CODE_OFFSET=1000
    ;;
  all)
    TARGET_PLATFORM=""
    APK="build/app/outputs/flutter-apk/app-release.apk"
    CODE_OFFSET=0
    ;;
  *)
    echo "不支持的 ABI: $ABI (支持 arm64-v8a / armeabi-v7a / all)" >&2
    exit 2
    ;;
esac

cd "$(dirname "$0")/.."

VERSION_LINE=$(grep '^version:' pubspec.yaml)
VERSION=${VERSION_LINE#version: }
VERSION=${VERSION%%+*}
CODE=${VERSION_LINE##*+}
APK_NAME="dsh-app-${VERSION}.apk"

# split-per-abi 会给 versionCode 加架构偏移,清单必须发布 APK 里的真实
# versionCode,否则手机端比较永远失真。
# SDK 位置因机器而异(本机是 apt 装的 /usr/lib/android-sdk),依次探测;
# 探测不到时下面会因 set -e 直接失败,而不是悄悄写出错误的清单。
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
for candidate in "$SDK_ROOT" /home/x/Android/Sdk /usr/lib/android-sdk "$HOME/Android/Sdk"; do
  [ -n "$candidate" ] || continue
  found=$(ls "$candidate"/build-tools/*/aapt 2>/dev/null | tail -1 || true)
  if [ -n "$found" ]; then AAPT="$found"; SDK_ROOT="$candidate"; break; fi
done
if [ -z "${AAPT:-}" ]; then
  echo "错误: 找不到 aapt,请设置 ANDROID_HOME" >&2
  exit 3
fi
apk_real_code() {
  if [ -n "$AAPT" ] && [ -f "$1" ]; then
    "$AAPT" dump badging "$1" 2>/dev/null | sed -n "s/^package:.*versionCode='\([0-9]*\)'.*/\1/p"
  fi
}

# --- 决定是否需要构建 --------------------------------------------------------
needs_build=1
if [ "$NO_BUILD" = 1 ]; then
  if [ ! -f "$APK" ]; then
    echo "错误: --no-build 但产物不存在: $APK" >&2
    exit 1
  fi
  needs_build=0
elif [ "$REBUILD" = 1 ]; then
  needs_build=1
elif [ -f "$APK" ]; then
  # 自动模式:任何源码比产物新(改过代码/依赖/版本号)都要重建。
  # 只查影响 Android 产物平面的文件,忽略 tool/、test/ 与 Gradle 缓存
  # (android/.gradle 的锁文件与各级 build/ 产物每次构建后都会刷新 mtime,
  # 不能算源码变更)。
  NEWER=$(find lib android pubspec.yaml analysis_options.yaml \
    \( -path '*/build' -o -path '*/.gradle' \) -prune -o \
    -newer "$APK" -print -quit 2>/dev/null || true)
  REAL=$(apk_real_code "$APK")
  EXPECT=$((CODE + CODE_OFFSET))
  if [ -z "$NEWER" ] && [ "$REAL" = "$EXPECT" ]; then
    needs_build=0
  fi
fi

echo "==> 发布 v${VERSION}+${CODE} (${ABI})"
if [ "$needs_build" = 1 ]; then
  echo "==> 构建 APK ($APK)"
  if [ "$DRY_RUN" = 1 ]; then
    echo "    [dry-run] flutter build apk --release --split-per-abi $TARGET_PLATFORM"
  else
    export PATH="$PATH:/home/x/flutter/bin"
    # release + 单架构:胖包含三份 Flutter 引擎(arm64/armv7/x86_64),目标手机
    # 是 arm64,只打 arm64 可把下载体积砍到约 1/3,构建也只编一份引擎;release
    # 用正式密钥签名(android/key.properties → app/dsh-release.jks,均不入库),
    # 签名一旦切换旧版无法覆盖安装,密钥文件务必备份。
    flutter build apk --release --split-per-abi $TARGET_PLATFORM
  fi
else
  REAL=$(apk_real_code "$APK")
  echo "==> 复用已有产物 $APK (versionCode $REAL,跳过构建)"
fi

if [ "$DRY_RUN" = 1 ]; then
  echo "==> 计划(未执行):"
  echo "    scp $APK + latest.json → $SERVER:$REMOTE_DIR/ (服务器已有同 sha256 时跳过 APK)"
  echo "    ssh $SERVER: cp $REMOTE_DIR/$APK_NAME → $PUBLIC_DIR/dsh-app-latest.apk"
  echo "    scp version.json → $SERVER:$PUBLIC_DIR/"
  exit 0
fi

if [ ! -f "$APK" ]; then
  echo "错误: 产物不存在: $APK" >&2
  exit 1
fi
# The publisher validates the APK identity, increasing versionCode, existing
# release signing certificate and public download hash before reporting success.
ORIGIN=$(python3 - "$BASE_URL" <<'PYORIGIN'
import sys,urllib.parse
u=urllib.parse.urlsplit(sys.argv[1])
print(urllib.parse.urlunsplit((u.scheme,u.netloc,'','','')))
PYORIGIN
)
python3 tool/publish_release.py --server "$SERVER" --origin "$ORIGIN" \
  --apk "$APK" --expected-version "$VERSION" --notes "$NOTES"
