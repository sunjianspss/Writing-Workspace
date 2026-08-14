#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CreativeWorkshopMac"
BUNDLE_ID="com.sun.CreativeWorkshopMac"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/CreativeWorkshopMac"
VERSION_FILE="$ROOT_DIR/VERSION"
DIST_DIR="$ROOT_DIR/dist"
SWIFTPM_STATE_DIR="$ROOT_DIR/.swiftpm-state"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_RESOURCES="$APP_CONTENTS/Resources"

mkdir -p "$SWIFTPM_STATE_DIR/config" "$SWIFTPM_STATE_DIR/security" "$SWIFTPM_STATE_DIR/cache" "$SWIFTPM_STATE_DIR/module-cache"
export SWIFTPM_CONFIG_PATH="$SWIFTPM_STATE_DIR/config"
export SWIFTPM_SECURITY_PATH="$SWIFTPM_STATE_DIR/security"
export SWIFTPM_CACHE_PATH="$SWIFTPM_STATE_DIR/cache"
export CLANG_MODULE_CACHE_PATH="$SWIFTPM_STATE_DIR/module-cache"

bash "$ROOT_DIR/script/architecture_guard.sh"

swift build --disable-sandbox --package-path "$PACKAGE_DIR"
BUILD_BIN_DIR="$(swift build --disable-sandbox --package-path "$PACKAGE_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# SwiftPM keeps target resources in a sibling bundle. The app-level resource
# resolver uses the conventional signed-app location first.
RESOURCE_BUNDLE="$BUILD_BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  mkdir -p "$APP_RESOURCES"
  /usr/bin/ditto "$RESOURCE_BUNDLE" "$APP_RESOURCES/$(basename "$RESOURCE_BUNDLE")"
fi

# 图标资产随仓库入库（由 script/generate_app_icon.swift 生成）。开发构建与正式
# 打包是两条独立的 bundle 组装路径，两边都要拷，否则会出现"开发时有图标、
# 打包出来没有"。
APP_ICON_SOURCE="$PACKAGE_DIR/Resources/AppIcon.icns"
if [[ -f "$APP_ICON_SOURCE" ]]; then
  mkdir -p "$APP_RESOURCES"
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

APP_VERSION="0.0.0"
if [[ -f "$VERSION_FILE" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi
APP_BUILD="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>创作工坊</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --build|build)
    echo "built: $APP_BUNDLE"
    ;;
  --debug|debug)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
