#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/architecture_guard.sh"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
FIXTURE_DIR="$(mktemp -d "$TMP_BASE/creative-workshop-guard.XXXXXX")"

cleanup() {
  case "$FIXTURE_DIR" in
    "$TMP_BASE"/creative-workshop-guard.*)
      rm -rf -- "$FIXTURE_DIR"
      ;;
    *)
      echo "Refusing to remove unexpected fixture path: $FIXTURE_DIR" >&2
      ;;
  esac
}
trap cleanup EXIT INT TERM

SRC_DIR="$FIXTURE_DIR/macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac"
CORE_DIR="$FIXTURE_DIR/macos/CreativeWorkshopMac/Sources/CreativeWorkshopCore"
mkdir -p "$SRC_DIR/Stores" "$SRC_DIR/Views" "$CORE_DIR/Services"

: > "$SRC_DIR/Stores/WorkshopStore.swift"
: > "$CORE_DIR/Services/NativeAIClient.swift"
printf '%s\n' 'let fixture: WorkflowDescriptor<Fixture>' > "$CORE_DIR/Services/NativeWorkflowCatalog.swift"

clean_output="$FIXTURE_DIR/clean-output.txt"
if ! ARCHITECTURE_GUARD_ROOT="$FIXTURE_DIR" "$GUARD_SCRIPT" >"$clean_output" 2>&1; then
  echo "FAIL: clean architecture fixture should pass." >&2
  sed -n '1,160p' "$clean_output" >&2
  exit 1
fi

printf '%s\n' \
  'extension WorkshopStore {' \
  '    func forbiddenFixtureWrite() throws {' \
  '        _ = try database.saveArticle(title: "fixture")' \
  '        _ = NativeWorkflowCatalog.polishDraft(context: fixture)' \
  '        _ = NativeWorkflowCatalog.rewriteSelection(context: fixture)' \
  '        _ = NativeWorkflowCatalog.writingAdvisor(context: fixture)' \
  '        _ = NativeWorkflowCatalog.readerPerspective(context: fixture)' \
  '        _ = try database.saveWritingAdvisorRun(result: fixture)' \
  '        _ = NativeWorkflowCatalog.writingReview(context: fixture)' \
  '        _ = try database.saveWritingReview(result: fixture)' \
  '        _ = NativeWorkflowCatalog.improveDraftFromReview(context: fixture)' \
  '        _ = DeepDraftCoordinator(aiClient: fixture)' \
  '        _ = NativeWorkflowCatalog.publishAssets(context: fixture)' \
  '        _ = try database.savePublishAssets(result: fixture)' \
  '        _ = NativeWorkflowCatalog.outline(topic: fixture)' \
  '    }' \
  '}' \
  > "$SRC_DIR/Stores/WorkshopStore+Fixture.swift"

violation_output="$FIXTURE_DIR/violation-output.txt"
if ARCHITECTURE_GUARD_ROOT="$FIXTURE_DIR" "$GUARD_SCRIPT" >"$violation_output" 2>&1; then
  echo "FAIL: injected WorkshopStore boundary violation should be rejected." >&2
  exit 1
fi

expected_message="ERROR: WorkshopStore boundary violation:"
if ! grep -Fq "$expected_message" "$violation_output"; then
  echo "FAIL: guard failed without the expected WorkshopStore boundary diagnostic." >&2
  sed -n '1,160p' "$violation_output" >&2
  exit 1
fi

if ! grep -Fq 'database.saveArticle' "$violation_output"; then
  echo "FAIL: guard diagnostic did not identify the injected violation." >&2
  sed -n '1,160p' "$violation_output" >&2
  exit 1
fi

if ! grep -Fq 'NativeWorkflowCatalog.polishDraft' "$violation_output"; then
  echo "FAIL: guard diagnostic did not identify the injected polish orchestration violation." >&2
  sed -n '1,160p' "$violation_output" >&2
  exit 1
fi

# 24.16 迁出的三条编排与顾问轨迹写入：每一条都必须能被单独指名，
# 否则"守卫覆盖了它"只是错觉。
for forbidden in \
  'NativeWorkflowCatalog.rewriteSelection' \
  'NativeWorkflowCatalog.writingAdvisor' \
  'NativeWorkflowCatalog.readerPerspective' \
  'database.saveWritingAdvisorRun' \
  'NativeWorkflowCatalog.writingReview' \
  'database.saveWritingReview' \
  'NativeWorkflowCatalog.improveDraftFromReview' \
  'DeepDraftCoordinator' \
  'NativeWorkflowCatalog.publishAssets' \
  'database.savePublishAssets' \
  'NativeWorkflowCatalog.outline'
do
  if ! grep -Fq "$forbidden" "$violation_output"; then
    echo "FAIL: guard diagnostic did not identify the injected violation: $forbidden" >&2
    sed -n '1,160p' "$violation_output" >&2
    exit 1
  fi
done

echo "Architecture guard self-test: clean fixture passed; injected violation was rejected."
