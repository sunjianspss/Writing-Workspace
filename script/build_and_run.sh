#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CreativeWorkshopMac"
BUNDLE_ID="com.sun.CreativeWorkshopMac"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/CreativeWorkshopMac"
DIST_DIR="$ROOT_DIR/dist"
SWIFTPM_STATE_DIR="$ROOT_DIR/.swiftpm-state"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

mkdir -p "$SWIFTPM_STATE_DIR/config" "$SWIFTPM_STATE_DIR/security" "$SWIFTPM_STATE_DIR/cache" "$SWIFTPM_STATE_DIR/module-cache"
export SWIFTPM_CONFIG_PATH="$SWIFTPM_STATE_DIR/config"
export SWIFTPM_SECURITY_PATH="$SWIFTPM_STATE_DIR/security"
export SWIFTPM_CACHE_PATH="$SWIFTPM_STATE_DIR/cache"
export CLANG_MODULE_CACHE_PATH="$SWIFTPM_STATE_DIR/module-cache"

bash "$ROOT_DIR/script/architecture_guard.sh"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --disable-sandbox --package-path "$PACKAGE_DIR"
BUILD_BINARY="$(swift build --disable-sandbox --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

INSTALLED_APP="/Applications/$APP_NAME.app"
rm -rf "$INSTALLED_APP"
cp -R "$APP_BUNDLE" "$INSTALLED_APP"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
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
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
