#!/usr/bin/env bash
# CI 挂起看门狗：到点后给测试进程拍一张调用栈，打进 CI 日志。
#
# 背景：`PromptTemplateSingleSourceTests.testEveryKeyIsCovered` 在 GitHub runner 上
# 会稳定挂住（同一位置、跨提交复现），本地无论脏树还是干净 checkout 都正常。测试体
# 是纯计算，按其逻辑不可能挂，所以只能取现场——没有栈就只能继续猜。
#
# 它只观察不干预：不杀进程，也永远以 0 退出，绝不把一次正常构建拖成失败。
# 真正的兜底仍是 workflow 的 timeout-minutes。
#
# 用法：script/ci_hang_watchdog.sh [首次采样秒数] [第二次采样秒数]
set -uo pipefail

first_delay="${1:-420}"
second_delay="${2:-180}"

# 无条件先声明自己启动了。看门狗最怕的是"没输出"——那既可能是没挂起，
# 也可能是它自己没跑起来，两者不能靠沉默区分。
echo "[watchdog] 已启动：将在 ${first_delay}s 后检查测试进程是否仍在运行"

snapshot() {
  local label="$1"
  local found=0

  # 进程名可覆盖，只为让"采样这条路真的能拍到栈"可以被本地验证——
  # 一个从没被证明能出栈的看门狗，和没有看门狗是一回事。
  for name in ${WATCHDOG_PROCESS_NAMES:-xctest swift-test swift-package swift-frontend}; do
    local pid
    pid="$(pgrep -x "$name" 2>/dev/null | head -1 || true)"
    [[ -n "$pid" ]] || continue
    found=1

    echo "[watchdog] ${label}：$name (pid $pid) 仍在运行，开始采样"
    echo "[watchdog] ---------- $name (pid $pid) 调用栈开始 ----------"
    if command -v sample >/dev/null 2>&1; then
      sample "$pid" 3 -mayDie 2>&1 | sed -n '1,220p' || echo "[watchdog] sample 失败"
    else
      echo "[watchdog] sample 不可用，改用 lldb"
      lldb -p "$pid" --batch -o "thread backtrace all" -o "detach" 2>&1 | sed -n '1,220p' \
        || echo "[watchdog] lldb 也失败"
    fi
    echo "[watchdog] ---------- $name (pid $pid) 调用栈结束 ----------"
  done

  if [[ "$found" -eq 0 ]]; then
    echo "[watchdog] ${label}：没有测试进程在跑，构建应已正常推进"
    return 1
  fi
  return 0
}

sleep "$first_delay"
if ! snapshot "第一次检查（${first_delay}s）"; then
  exit 0
fi

# 还活着就再拍一张：两张栈一样说明真卡死，不一样说明只是慢。
sleep "$second_delay"
snapshot "第二次检查（再等 ${second_delay}s）" || true

exit 0
