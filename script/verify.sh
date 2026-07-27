#!/usr/bin/env bash
# 提交前的单条验证命令（PRD 24.11 / P2-10）。
#
# 背景：`architecture_guard.sh` 此前只挂在 `build_and_run.sh` 里——也就是只有"要跑 App"时才会
# 执行；`swift test` 全靠手敲。于是"只改了评测侧、没启动 App"的改动可以完全绕开守卫，24.7 的
# 死视图就是这样溜过去的。这里把两者合成一条命令，让"验证过了"有唯一含义。
#
# 用法：
#   script/verify.sh              # 守卫 + 全量测试
#   script/verify.sh --guard-only # 只跑守卫（秒级，适合改脚本/文档时自查）
#   script/verify.sh --filter Xxx # 其余参数原样透传给 swift test
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/CreativeWorkshopMac"
SWIFTPM_STATE_DIR="$ROOT_DIR/.swiftpm-state"

guard_only=0
if [[ "${1:-}" == "--guard-only" ]]; then
  guard_only=1
  shift
fi

# 与 build_and_run.sh 用同一套 SwiftPM 状态目录，避免两条命令互相把对方的增量构建冲掉。
mkdir -p "$SWIFTPM_STATE_DIR/config" "$SWIFTPM_STATE_DIR/security" "$SWIFTPM_STATE_DIR/cache" "$SWIFTPM_STATE_DIR/module-cache"
export SWIFTPM_CONFIG_PATH="$SWIFTPM_STATE_DIR/config"
export SWIFTPM_SECURITY_PATH="$SWIFTPM_STATE_DIR/security"
export SWIFTPM_CACHE_PATH="$SWIFTPM_STATE_DIR/cache"
export CLANG_MODULE_CACHE_PATH="$SWIFTPM_STATE_DIR/module-cache"

bash "$ROOT_DIR/script/architecture_guard.sh"

if [[ "$guard_only" -eq 1 ]]; then
  echo "verify: 仅守卫，已通过（未跑测试）。"
  exit 0
fi

swift test --disable-sandbox --package-path "$PACKAGE_DIR" "$@"
