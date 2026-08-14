#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CreativeWorkshopMac"
APP_DISPLAY_NAME="创作工坊"
BUNDLE_ID="com.sun.CreativeWorkshopMac"
MIN_SYSTEM_VERSION="13.0"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/CreativeWorkshopMac"
VERSION_FILE="$ROOT_DIR/VERSION"
DIST_DIR="$ROOT_DIR/dist"
SWIFTPM_STATE_DIR="$ROOT_DIR/.swiftpm-state"
CHECK_SCRIPT="$ROOT_DIR/script/check_release.sh"

usage() {
  echo "usage: $0 [--skip-verify]" >&2
  exit 2
}

skip_verify=0
for arg in "$@"; do
  case "$arg" in
    --skip-verify)
      skip_verify=1
      ;;
    *)
      usage
      ;;
  esac
done

[[ -f "$VERSION_FILE" ]] || {
  echo "package release: missing VERSION" >&2
  exit 1
}
release_version="$(tr -d '[:space:]' < "$VERSION_FILE")"
if ! [[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "package release: VERSION is not semantic: $release_version" >&2
  exit 1
fi

release_build_number="${BUILD_NUMBER:-}"
if [[ -z "$release_build_number" ]]; then
  if git -C "$ROOT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    release_build_number="$(git -C "$ROOT_DIR" rev-list --count HEAD)"
  else
    release_build_number="1"
  fi
fi
if ! [[ "$release_build_number" =~ ^[0-9]+$ ]]; then
  echo "package release: BUILD_NUMBER must be numeric" >&2
  exit 1
fi

mkdir -p "$SWIFTPM_STATE_DIR/config" "$SWIFTPM_STATE_DIR/security" "$SWIFTPM_STATE_DIR/cache" "$SWIFTPM_STATE_DIR/module-cache"
export SWIFTPM_CONFIG_PATH="$SWIFTPM_STATE_DIR/config"
export SWIFTPM_SECURITY_PATH="$SWIFTPM_STATE_DIR/security"
export SWIFTPM_CACHE_PATH="$SWIFTPM_STATE_DIR/cache"
export CLANG_MODULE_CACHE_PATH="$SWIFTPM_STATE_DIR/module-cache"

if [[ "$skip_verify" -eq 0 ]]; then
  bash "$ROOT_DIR/script/verify.sh"
else
  echo "package release: verification skipped by explicit local override"
fi

swift build --disable-sandbox --configuration release --package-path "$PACKAGE_DIR"
build_bin_dir="$(swift build --disable-sandbox --configuration release --package-path "$PACKAGE_DIR" --show-bin-path)"
build_binary="$build_bin_dir/$APP_NAME"
build_resource_bundle="$build_bin_dir/$RESOURCE_BUNDLE_NAME"

[[ -x "$build_binary" ]] || {
  echo "package release: missing release executable: $build_binary" >&2
  exit 1
}
[[ -d "$build_resource_bundle" ]] || {
  echo "package release: missing SwiftPM resource bundle: $build_resource_bundle" >&2
  exit 1
}

package_workspace="$(mktemp -d "${TMPDIR:-/tmp}/creative-workshop-package.XXXXXX")"
promotion_dir=""
promoted_archive=""
promoted_checksum=""
cleanup() {
  if [[ -n "$promoted_archive" && -f "$promoted_archive" ]]; then
    rm -f "$promoted_archive"
  fi
  if [[ -n "$promoted_checksum" && -f "$promoted_checksum" ]]; then
    rm -f "$promoted_checksum"
  fi
  if [[ -n "$promotion_dir" && -d "$promotion_dir" ]]; then
    rm -rf "$promotion_dir"
  fi
  rm -rf "$package_workspace"
}
trap cleanup EXIT

app_bundle="$package_workspace/$APP_NAME.app"
app_contents="$app_bundle/Contents"
app_macos="$app_contents/MacOS"
app_resources="$app_contents/Resources"
app_binary="$app_macos/$APP_NAME"
info_plist="$app_contents/Info.plist"

mkdir -p "$app_macos" "$app_resources"
cp "$build_binary" "$app_binary"
chmod +x "$app_binary"

# Signed macOS bundles may not carry unsealed files at the app root. The
# WorkshopResourceBundle resolver uses this conventional location first.
/usr/bin/ditto "$build_resource_bundle" "$app_resources/$RESOURCE_BUNDLE_NAME"

# 图标资产：与 build_and_run.sh 走同一份源文件，避免两条路径产出不一致的包。
app_icon_source="$PACKAGE_DIR/Resources/AppIcon.icns"
if [[ ! -f "$app_icon_source" ]]; then
  echo "ERROR: 缺少图标资产 ${app_icon_source} — 用 script/generate_app_icon.swift 生成" >&2
  exit 1
fi
cp "$app_icon_source" "$app_resources/AppIcon.icns"

/usr/bin/plutil -create xml1 "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh_CN" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_DISPLAY_NAME" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_DISPLAY_NAME" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $release_version" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $release_build_number" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.productivity" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_SYSTEM_VERSION" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$info_plist"
/usr/bin/plutil -lint "$info_plist" >/dev/null

# Sign only after every resource and metadata file has reached its final place.
/usr/bin/codesign --force --deep --sign - --timestamp=none "$app_bundle"

env EXPECTED_VERSION="$release_version" EXPECTED_BUILD_NUMBER="$release_build_number" "$CHECK_SCRIPT" "$app_bundle"
"$CHECK_SCRIPT" --self-test "$app_bundle"

mkdir -p "$DIST_DIR"
archive_name="$APP_NAME-$release_version-$release_build_number-adhoc.zip"
archive_path="$DIST_DIR/$archive_name"
checksum_path="$archive_path.sha256"
if [[ -e "$archive_path" || -e "$checksum_path" ]]; then
  echo "package release: refusing to overwrite existing artifact: $archive_path" >&2
  exit 1
fi

# Build and validate under a hidden same-filesystem directory. Only a complete,
# verified pair is promoted to its public dist names.
promotion_dir="$(mktemp -d "$DIST_DIR/.creative-workshop-release.XXXXXX")"
staged_archive="$promotion_dir/$archive_name"
staged_checksum="$staged_archive.sha256"

(
  cd "$package_workspace"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$staged_archive"
)
(
  cd "$promotion_dir"
  /usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256"
)

env EXPECTED_VERSION="$release_version" EXPECTED_BUILD_NUMBER="$release_build_number" "$CHECK_SCRIPT" "$app_bundle" "$staged_archive"

mv "$staged_archive" "$archive_path"
promoted_archive="$archive_path"
mv "$staged_checksum" "$checksum_path"
promoted_checksum="$checksum_path"
rmdir "$promotion_dir"
promotion_dir=""
promoted_archive=""
promoted_checksum=""

echo "package release: artifact $archive_path"
echo "package release: checksum $checksum_path"
echo "package release: ad-hoc artifact only; public distribution still requires Developer ID and notarization"
