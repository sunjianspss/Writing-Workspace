# 创作工坊

面向公众号日更作者的本地 AI 写作工作台。

当前主线是第二版 macOS 原生应用：SwiftUI + 本地 SQLite + URLSession 直连 OpenAI-compatible 模型接口 + Keychain 保存 API Key。旧 Web / FastAPI / Next / Python 兼容路径已经从工作区清理，不再作为回退入口。

```text
配置 API Key -> 输入想法 / 选择素材 -> 智能下一步
-> 生成选题 / 大纲 / 初稿 -> 局部改写 / 写作诊断
-> 生成发布物料 -> 保存归档
```

架构边界见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 运行

启动原生客户端：

```bash
./script/build_and_run.sh
```

脚本会构建 SwiftPM 工程、生成 `dist/CreativeWorkshopMac.app` 并作为 macOS 应用打开。应用不启动 FastAPI，不依赖 Python 后端，也不依赖 npm。

在 App 的设置页填写：

- API Base URL：默认 `https://api.deepseek.com`
- 模型：默认 `deepseek-v4-pro`
- API Key：保存到 macOS Keychain

没有配置 API Key 时，应用会使用本地 fallback 内容，方便验证产品流程。

## 当前实现

- macOS 原生客户端：`macos/CreativeWorkshopMac`
- 原生 SQLite 数据层：`NativeDatabase.swift`
- 原生 AI 调用：`NativeAIClient.swift` + `AIWorkflowRunner.swift`
- 原生提示词与 fallback：`NativePrompts.swift`、`NativeFallbacks.swift`
- 提示词模板库：`prompt_templates` + 设置页编辑
- 风格库：`style_profiles`，支持体裁评价重点、样本和作者雷区
- 智能下一步：`WritingContextBuilder.swift` + `writing_advisor_runs`，支持上下文观察、执行计划、风险提示和推荐动作
- 代理式初稿：直接生成初稿会依次生成 writing brief、论点检查、分段草稿、自我批评，再进入待复核；待复核卡可展开查看代理运行轨迹，并显示代理质量门
- 写作教练：`writing_reviews` 本地复盘表，支持诊断记忆、定点改写候选和复盘详情
- 诊断驱动改稿：写作教练可按最新诊断对全文直接修订，并进入待复核版本流
- 全文润色与局部改写：`SelectedTextEditor.swift` + `RewriteResult` + `DraftResult`
- 改稿版本：`draft_versions` 本地表，支持差异对比、待复核、恢复改写前/后和多版本候选
- 写作质量辅助：生成后自检、文学写作能力趋势、读者视角模拟、选题去重
- 素材箱：`ideas` + `MaterialsView.swift`
- 发布物料：`publish_assets` + `PublishAssetsResult`
- API Key：`KeychainCredentialStore.swift`
- 构建/运行脚本：`script/build_and_run.sh`

原生数据库位于 `~/Library/Application Support/CreativeWorkshopMac/creative_workshop.sqlite3`。应用运行时不再读取仓库内的旧 Web 数据目录；若工作区本地仍有 `data/` 或 `exports/`，它们只作为忽略的历史数据归档存在，不参与启动流程。

## 验证

一键构建并启动：

```bash
./script/build_and_run.sh --verify
```

提交前的单条验证命令（架构守卫 + 全量单元测试，PRD 24.11）：

```bash
./script/verify.sh              # 守卫 + 测试
./script/verify.sh --guard-only # 只跑守卫，秒级
./script/verify.sh --filter Xxx # 其余参数透传给 swift test
```

只想手敲测试时：

```bash
env SWIFTPM_CONFIG_PATH="$PWD/.swiftpm-state/config" \
  SWIFTPM_SECURITY_PATH="$PWD/.swiftpm-state/security" \
  SWIFTPM_CACHE_PATH="$PWD/.swiftpm-state/cache" \
  CLANG_MODULE_CACHE_PATH="$PWD/.swiftpm-state/module-cache" \
  swift test --disable-sandbox --package-path macos/CreativeWorkshopMac
```

写作质量评测（PRD 22.4.2）：独立于主 App 的 CLI，从 `evals/cases/` 读取用例，分别跑 direct/agent/deep 三条管线并用写作诊断打分，结果写入 `evals/eval_results.sqlite3`，报告写入 `evals/reports/`。需要先在 App 设置页配置好 API Key（保存在 Keychain）；没有 Key 时会直接报错退出，不会静默走本地 fallback。

```bash
swift run --package-path macos/CreativeWorkshopMac CreativeWorkshopEval --pipelines direct,agent,deep
```

全量一轮（28 用例 × 4 管线）约 8 小时。中断后用 `--resume` 续跑最近一次 run：已成功的格子跳过，失败的格子重跑，报告按同一 run_id 补成整轮（PRD 24.9）。

```bash
swift run --package-path macos/CreativeWorkshopMac CreativeWorkshopEval --resume
```

失败的样本（超时、连接中断等）不再打分：报告头会点名「无效样本」，它们不计入差值，也不进放行门。

## 清理说明

旧 Web / FastAPI 路径已经移出工作区，包括：

- `app/`
- `src/`
- `web/`
- `scripts/`
- `package.json` / `package-lock.json` / Next 配置
- `pyproject.toml` / `uv.lock`
- `.next` / `node_modules` / `.venv` / `.uv-cache`

`.env`、`data/`、`exports/` 若仍存在，均被 `.gitignore` 排除，视为本机私有历史数据或临时产物，不是当前架构的一部分。
