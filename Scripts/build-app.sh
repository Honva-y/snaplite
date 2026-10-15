#!/bin/bash
# 编译并打包 SnapLite.app。
#   Scripts/build-app.sh            → build/SnapLite.app（release）
#   Scripts/build-app.sh --install  → 同时复制到 /Applications
#   SIGN_IDENTITY="SnapLite Dev" Scripts/build-app.sh  → 用指定证书签名（默认自动查找 "SnapLite Dev"，找不到则 ad-hoc）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
swift build -c "$CONFIG" --product SnapLite
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SnapLite"

APP="build/SnapLite.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnapLite"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
  swift Scripts/make-icon.swift Resources/AppIcon.icns Resources/AppIcon-source.png || true
fi
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"SnapLite Dev"'; then
  IDENTITY="SnapLite Dev"
fi
codesign --force --sign "${IDENTITY:--}" --identifier com.honva.snaplite "$APP"
echo "已打包：${APP}（签名：${IDENTITY:-ad-hoc}）"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/SnapLite.app
  cp -R "$APP" /Applications/SnapLite.app
  echo "已安装到 /Applications/SnapLite.app"
fi
