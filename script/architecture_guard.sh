#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${ARCHITECTURE_GUARD_ROOT:-}" ]]; then
  ROOT_DIR="$(cd "$ARCHITECTURE_GUARD_ROOT" && pwd)"
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
PACKAGE_DIR="$ROOT_DIR/macos/CreativeWorkshopMac"
SRC_DIR="$PACKAGE_DIR/Sources/CreativeWorkshopMac"
CORE_DIR="$PACKAGE_DIR/Sources/CreativeWorkshopCore"
STORE_FILE="$SRC_DIR/Stores/WorkshopStore.swift"
CLIENT_FILE="$CORE_DIR/Services/NativeAIClient.swift"
CATALOG_FILE="$CORE_DIR/Services/NativeWorkflowCatalog.swift"

fail=0

echo "Architecture guard: checking AI workflow boundaries..."

view_hits="$(grep -RInE '\b(NativeAIClient|ModelGateway|AIWorkflowRunner)\b' "$SRC_DIR/Views" 2>/dev/null || true)"
if [[ -n "$view_hits" ]]; then
  echo "ERROR: Views must not reference NativeAIClient, ModelGateway, or AIWorkflowRunner directly." >&2
  echo "$view_hits" >&2
  fail=1
fi

runner_hits="$(grep -RIn 'runner.run(' "$SRC_DIR" 2>/dev/null || true)"
if [[ -n "$runner_hits" ]]; then
  echo "ERROR: AI workflows must go through WorkflowDescriptor/WorkflowEngine, not direct runner.run calls." >&2
  echo "$runner_hits" >&2
  fail=1
fi

typed_decode_hits="$(grep -RInE 'if T\.self|as! T|decodeModelJSON' "$CORE_DIR/Services" 2>/dev/null || true)"
if [[ -n "$typed_decode_hits" ]]; then
  echo "ERROR: Model output decode fallbacks must live on WorkflowDescriptor declarations, not in a central generic type chain." >&2
  echo "$typed_decode_hits" >&2
  fail=1
fi

store_ai_record_hits="$(grep -n 'database\.recordAICall' "$STORE_FILE" 2>/dev/null || true)"
if [[ -n "$store_ai_record_hits" ]]; then
  echo "ERROR: Store must not hand-write ai_calls records; workflow descriptors should record through WorkflowEngine." >&2
  echo "$store_ai_record_hits" >&2
  fail=1
fi

# WorkshopStore 只负责装配与 UI 投影。以下已经迁移到 WritingSession/WritingWorkflow
# 的写入入口不允许回流；其余尚未迁移的路径暂不纳入，避免把守卫变成一次性大爆炸。
store_boundary_hits=""
while IFS= read -r file; do
  hits="$(grep -nE 'database[[:space:]]*\.[[:space:]]*(saveArticle|saveDraftVersion|saveWritingAdvisorRun|saveWritingReview|savePublishAssets|createTopics)[[:space:]]*\(|PendingReviewMachine[[:space:]]*\(|DeepDraftCoordinator[[:space:]]*\(|NativeWorkflowCatalog[[:space:]]*\.[[:space:]]*(polishDraft|rewriteSelection|writingAdvisor|readerPerspective|writingReview|improveDraftFromReview|publishAssets|outline|topics|draftSelfCheck|draft)[[:space:]]*\(' "$file" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    store_boundary_hits+="${file}:"$'\n'"${hits}"$'\n'
  fi
done < <(find "$SRC_DIR/Stores" -type f -name 'WorkshopStore*.swift' 2>/dev/null | sort)

if [[ -n "$store_boundary_hits" ]]; then
  echo "ERROR: WorkshopStore boundary violation: direct persistence or business-machine writes must go through WritingSession/WritingWorkflow." >&2
  echo "$store_boundary_hits" >&2
  fail=1
fi

client_descriptor_hits="$(grep -nE 'NativePrompts\.|NativeFallbacks\.|NativeNonJSONDecoders' "$CLIENT_FILE" 2>/dev/null || true)"
if [[ -n "$client_descriptor_hits" ]]; then
  echo "ERROR: NativeAIClient is a compatibility facade only; workflow descriptors, prompts, fallbacks, and decode fallbacks must live in NativeWorkflowCatalog." >&2
  echo "$client_descriptor_hits" >&2
  fail=1
fi

legacy_ai_client_hits="$(grep -RIn '\bAIClienting\b' "$SRC_DIR" "$CORE_DIR" 2>/dev/null || true)"
if [[ -n "$legacy_ai_client_hits" ]]; then
  echo "ERROR: AIClienting high-level workflow facade has been retired; inject AIWorkflowExecuting instead." >&2
  echo "$legacy_ai_client_hits" >&2
  fail=1
fi

client_passthrough_hits="$(grep -nE 'func (agentDraft|generateTopics|outline|draft|polishDraft|improveDraftFromReview|writingReview|publishAssets|rewriteSelection|writingAdvisor|draftSelfCheck|summarizePitfalls|summarizeEditPreferences|readerPerspective|prePublishAudit|judgeDraftCandidates)\(' "$CLIENT_FILE" 2>/dev/null || true)"
if [[ -n "$client_passthrough_hits" ]]; then
  echo "ERROR: NativeAIClient must not grow high-level workflow pass-through methods; declare descriptors in NativeWorkflowCatalog and execute them through AIWorkflowExecuting." >&2
  echo "$client_passthrough_hits" >&2
  fail=1
fi

catalog_descriptor_hits="$(grep -n 'WorkflowDescriptor<' "$CATALOG_FILE" 2>/dev/null || true)"
if [[ -z "$catalog_descriptor_hits" ]]; then
  echo "ERROR: NativeWorkflowCatalog must own workflow descriptor declarations." >&2
  fail=1
fi

coordinator_chat_message_hits="$(grep -RIn 'ChatMessage(' "$CORE_DIR/Services" 2>/dev/null | grep -E '/[A-Za-z]*Coordinator[A-Za-z]*\.swift:' || true)"
if [[ -n "$coordinator_chat_message_hits" ]]; then
  echo "ERROR: Coordinators must not hand-write ChatMessage(...); prompts only live in NativePrompts/prompt_templates." >&2
  echo "$coordinator_chat_message_hits" >&2
  fail=1
fi

# 死视图守卫（24.7，24.11 补齐盲区）：定义了却没有任何调用点的视图片段是不会被渲染的死代码。
# 24.1 的发布流程指示条就这样"实施完成"却从未上过屏——单元测试只能验 Store 层的计算属性，
# 验不到有没有被挂进视图树，只有这条静态检查拦得住。
#
# 三类都要查，24.7 只查了第一类：
#   1. `private var xxx: some View`
#   2. `private func xxx(...) -> some View`（可带泛型、可跨行；24.11 发现 compactPanel 真的死在这里）
#   3. `struct XxxView: View`（跨文件：定义了却没人 new，同样一行都不上屏）
#
# 引用计数一律按 `\bname\b` 而不是 `name(`：`assets.map(hasUsableContent)` 这种裸函数引用
# 是合法调用点，按 `name(` 数会把它误报成死代码。
dead_views=""
while IFS= read -r file; do
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ "$(grep -c "\b${name}\b" "$file")" -le 1 ]]; then
      dead_views+="${file}: ${name}"$'\n'
    fi
  done < <(
    {
      grep -oE 'private var [a-zA-Z0-9_]+: some View' "$file" | awk '{print $3}' | tr -d ':'
      # 跨行签名（参数每行一个）用 perl 整文件匹配；`[^{]*?` 保证不越过函数体的第一个左花括号。
      perl -0777 -ne 'while (/private\s+func\s+([A-Za-z0-9_]+)[^{]*?->\s*some\s+View\s*\{/gs) { print "$1\n" }' "$file"
    }
  )
done < <(find "$SRC_DIR/Views" -name '*.swift' 2>/dev/null)

# struct 视图是跨文件引用的，计数范围必须是整个 Sources/CreativeWorkshopMac（App 入口挂的
# 根视图也在其中），只在单文件里数会把所有正常视图全判成死的。
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if [[ "$(grep -rhoE "\b${name}\b" "$SRC_DIR" | wc -l | tr -d ' ')" -le 1 ]]; then
    dead_views+="struct ${name}"$'\n'
  fi
done < <(grep -rhoE 'struct [A-Za-z0-9_]+: *View\b' "$SRC_DIR" | sed -E 's/struct ([A-Za-z0-9_]+).*/\1/' | sort -u)

if [[ -n "$dead_views" ]]; then
  echo "ERROR: These view fragments are defined but never used; they render nowhere." >&2
  echo "$dead_views" >&2
  fail=1
fi

# R5 瘦身棘轮：每完成一个瘦身任务把警戒线拧低一格，只降不升（任务 24 后为 1700）。
# 24.11 拧到 1700 是趁手上没有功能压力还的债：此前余量只剩 34 行，下一个功能一来，
# 现实的选择就会变成"把棘轮抬到 2100"——棘轮就是这么废掉的。
store_lines="$(wc -l < "$STORE_FILE" | tr -d ' ')"
if [[ "$store_lines" -gt 1700 ]]; then
  echo "WARNING: WorkshopStore.swift is ${store_lines} lines; ratchet guardrail is 1700, final target is 1200." >&2
fi

exit "$fail"
