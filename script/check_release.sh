#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CreativeWorkshopMac"
BUNDLE_ID="com.sun.CreativeWorkshopMac"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"

usage() {
  echo "usage: $0 <CreativeWorkshopMac.app> [archive.zip]" >&2
  echo "       $0 --self-test <CreativeWorkshopMac.app>" >&2
  exit 2
}

fail() {
  echo "release check: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_directory() {
  [[ -d "$1" ]] || fail "missing directory: $1"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

if [[ "${1:-}" == "--self-test" ]]; then
  [[ "$#" -eq 2 ]] || usage
  source_app="$2"
  require_directory "$source_app"

  self_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/creative-workshop-release-check.XXXXXX")"
  trap 'rm -rf "$self_test_dir"' EXIT
  mutated_app="$self_test_dir/$APP_NAME.app"
  /usr/bin/ditto "$source_app" "$mutated_app"

  mutated_plist="$mutated_app/Contents/Info.plist"
  require_file "$mutated_plist"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleVersion" "$mutated_plist"

  if "$SCRIPT_PATH" "$mutated_app" >/dev/null 2>&1; then
    fail "negative self-test failed: a bundle without CFBundleVersion was accepted"
  fi

  echo "release check: negative self-test passed"
  exit 0
fi

[[ "$#" -ge 1 && "$#" -le 2 ]] || usage
app_bundle="$1"
archive_path="${2:-}"
info_plist="$app_bundle/Contents/Info.plist"

require_directory "$app_bundle"
require_file "$info_plist"
/usr/bin/plutil -lint "$info_plist" >/dev/null

executable_name="$(plist_value "$info_plist" CFBundleExecutable)" || fail "missing CFBundleExecutable"
identifier="$(plist_value "$info_plist" CFBundleIdentifier)" || fail "missing CFBundleIdentifier"
package_type="$(plist_value "$info_plist" CFBundlePackageType)" || fail "missing CFBundlePackageType"
minimum_system="$(plist_value "$info_plist" LSMinimumSystemVersion)" || fail "missing LSMinimumSystemVersion"
release_version="$(plist_value "$info_plist" CFBundleShortVersionString)" || fail "missing CFBundleShortVersionString"
build_number="$(plist_value "$info_plist" CFBundleVersion)" || fail "missing CFBundleVersion"

[[ "$executable_name" == "$APP_NAME" ]] || fail "unexpected executable name: $executable_name"
[[ "$identifier" == "$BUNDLE_ID" ]] || fail "unexpected bundle identifier: $identifier"
[[ "$package_type" == "APPL" ]] || fail "unexpected package type: $package_type"
[[ "$minimum_system" == "13.0" ]] || fail "unexpected minimum macOS version: $minimum_system"
if ! [[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  fail "invalid semantic version: $release_version"
fi
[[ "$build_number" =~ ^[0-9]+$ ]] || fail "build number must be numeric: $build_number"

if [[ -n "${EXPECTED_VERSION:-}" ]]; then
  if [[ "$release_version" != "$EXPECTED_VERSION" ]]; then
    fail "version mismatch: expected $EXPECTED_VERSION, found $release_version"
  fi
fi
if [[ -n "${EXPECTED_BUILD_NUMBER:-}" ]]; then
  if [[ "$build_number" != "$EXPECTED_BUILD_NUMBER" ]]; then
    fail "build mismatch: expected $EXPECTED_BUILD_NUMBER, found $build_number"
  fi
fi

app_binary="$app_bundle/Contents/MacOS/$executable_name"
conventional_resource_bundle="$app_bundle/Contents/Resources/$RESOURCE_BUNDLE_NAME"
require_file "$app_binary"
[[ -x "$app_binary" ]] || fail "app executable is not marked executable"
require_directory "$conventional_resource_bundle"
require_file "$conventional_resource_bundle/WeChatFormatter/index.html"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"
architectures="$(/usr/bin/lipo -archs "$app_binary")"
[[ -n "$architectures" ]] || fail "could not determine executable architecture"

if [[ -n "$archive_path" ]]; then
  require_file "$archive_path"
  /usr/bin/unzip -tqq "$archive_path"
  expected_entry="$APP_NAME.app/Contents/Info.plist"
  if ! /usr/bin/unzip -Z1 "$archive_path" | /usr/bin/grep -Fqx "$expected_entry"; then
    fail "archive does not contain $expected_entry"
  fi

  checksum_path="$archive_path.sha256"
  require_file "$checksum_path"
  checksum_dir="$(dirname "$checksum_path")"
  checksum_name="$(basename "$checksum_path")"
  (
    cd "$checksum_dir"
    /usr/bin/shasum -a 256 -c "$checksum_name"
  )

  archive_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/creative-workshop-archive-check.XXXXXX")"
  cleanup_archive_check() {
    rm -rf "$archive_check_dir"
  }
  trap cleanup_archive_check EXIT
  /usr/bin/ditto -x -k "$archive_path" "$archive_check_dir"

  archived_app="$archive_check_dir/$APP_NAME.app"
  require_directory "$archived_app"
  "$SCRIPT_PATH" "$archived_app"
fi

echo "release check: OK version=$release_version build=$build_number archs=$architectures"
