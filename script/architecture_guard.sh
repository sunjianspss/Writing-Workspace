#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# R5 瘦身棘轮：每完成一个瘦身任务把警戒线拧低一格，只降不升（任务 20 后为 2550）。
store_lines="$(wc -l < "$STORE_FILE" | tr -d ' ')"
if [[ "$store_lines" -gt 2550 ]]; then
  echo "WARNING: WorkshopStore.swift is ${store_lines} lines; ratchet guardrail is 2550, final target is 1200." >&2
fi

exit "$fail"
