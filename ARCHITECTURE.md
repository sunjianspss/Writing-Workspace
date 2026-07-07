# 创作工坊架构说明

更新日期：2026-07-07

## 架构定位

创作工坊现在是纯 macOS 原生本地应用。

```text
macOS / SwiftUI App
  -> WorkshopStore
  -> NativeDatabase.swift
       Application Support / CreativeWorkshopMac / creative_workshop.sqlite3
  -> NativePrompts.swift / NativeFallbacks.swift
  -> NativeAIClient.swift
       URLSession -> OpenAI-compatible /chat/completions
  -> KeychainCredentialStore.swift
       macOS Keychain
```

旧 Web / FastAPI / Next / Python 兼容路径已从工作区移除。新的产品能力只进入 SwiftUI、NativeDatabase、NativeAIClient、NativePrompts、NativeFallbacks 和相关原生视图。

## 当前组件

| 组件 | 路径 | 职责 |
| --- | --- | --- |
| macOS App | `macos/CreativeWorkshopMac` | SwiftUI 原生工作台 |
| 原生 SQLite 层 | `NativeDatabase.swift` | Schema、文章/选题/素材/发布物料/风格/统计、迁移版本 |
| 原生 AI 调用 | `NativeAIClient.swift` | 业务工作流入口、选择 prompt 和 fallback |
| AI 工作流执行器 | `AIWorkflowRunner.swift` | URLSession 调用模型、解析 JSON、fallback、耗时和输入输出摘要 |
| 原生提示词 | `NativePrompts.swift` + `prompt_templates` | 初稿、选题、大纲、成稿、诊断、改写、智能建议、发布物料等可编辑 Prompt |
| 原生 fallback | `NativeFallbacks.swift` | 无 API Key 或模型失败时保持流程可用 |
| 智能上下文包 | `WritingContextBuilder.swift` | 汇总当前稿件、素材、风格、最近文章和最近诊断 |
| 风格库 | `style_profiles` + Settings | 风格、体裁评价重点、样本、作者雷区 |
| 提示词模板库 | `prompt_templates` + Settings | 各 AI 工作流 system/user prompt 编辑 |
| 智能下一步 | `writing_advisor_runs` + Inspector | 判断阶段、最大问题、下一步动作和推荐按钮 |
| 写作教练 | `writing_reviews` + Inspector | 保存 AI 诊断、问题清单、修改顺序和训练重点 |
| 局部改写 | `SelectedTextEditor.swift` + `RewriteResult` | 读取正文选区，只替换选中片段 |
| 改稿版本 | `draft_versions` + Inspector | 保存改稿前后标题、摘要、正文，并支持恢复 |
| 素材箱 | `ideas` + `MaterialsView.swift` | 素材新增、编辑、删除、入稿、生成选题 |
| 发布物料 | `publish_assets` + Inspector | 摘要、封面文案、朋友圈文案、标签、小红书版本、封面图提示词 |
| Keychain | `KeychainCredentialStore.swift` | API Key 安全存储 |
| 运行脚本 | `script/build_and_run.sh` | 构建并启动 `.app` |
| 写作质量评测 | `macos/CreativeWorkshopMac/Sources/CreativeWorkshopEval` + `evals/` | 独立 CLI，跑 direct/agent/deep/agentic 四条管线，锚点评分 + 放行门判定（PRD 22.4.2 / 23.4） |
| 半自动调度 | `AdvisorPlanRunner.swift` + `agent_runs` | 按"智能下一步"计划顺序执行动作，待复核处暂停（PRD 23.5，L1.5） |
| 代理会话（实验室） | `WritingAgentCoordinator.swift` + `agent_lab_enabled` / `agent_call_budget` | L2 有界决策循环：模型选动作、护栏管预算与熔断，产物进待复核；默认关闭，评测放行门达标才转默认（PRD 23.6） |

## SwiftPM 模块划分

`CreativeWorkshopMac.xcodeproj` 内部拆成三个 target：

- `CreativeWorkshopCore`：库 target，持有 `Models/`、`Services/`、`Support/`（`NativeDatabase`、`NativeWorkflowCatalog`、`AgentDraftCoordinator`、`DeepDraftCoordinator`、`NativePrompts`、`NativeFallbacks` 等）。跨 target 复用的类型/方法用 `package` 访问级别标注，只在包内可见，不对外暴露。
- `CreativeWorkshopMac`：可执行 target，只保留 `App/`、`Views/`、`Stores/`（SwiftUI 界面 + `WorkshopStore`），依赖 `CreativeWorkshopCore`。
- `CreativeWorkshopEval`：可执行 target，依赖 `CreativeWorkshopCore`（不依赖 `CreativeWorkshopMac`，因为 SwiftPM 的 executableTarget 不产出可供其他 target 链接的静态库），复用同一套 `NativeWorkflowCatalog`/协调器跑评测管线。

拆分只是把既有代码挪到库 target 里并补上必要的 `package` 访问级别，业务逻辑与运行行为不变。

## 边界原则

1. macOS 原生端是唯一主线。
2. 原生 App 不依赖本地 HTTP 后端。
3. 本地数据由原生 SQLite 拥有。
4. API Key 只进入 Keychain。
5. 旧 Web / FastAPI / Next / Python 代码不再保留在工作区。
6. 仓库内 `data/`、`exports/` 若存在，只是本机忽略的历史数据归档，不参与运行时路径。

## 启动路径

```bash
./script/build_and_run.sh
```

脚本只负责 SwiftPM 构建、生成 `dist/CreativeWorkshopMac.app` 并启动。它不会启动 FastAPI、Python、uvicorn、Next 或 npm。

## 原生运行流

```text
SwiftUI action
  -> WorkshopStore
  -> NativeDatabase.styleProfile(forDirection:) / listArticles / saveArticle / createTopics / listIdeas
  -> NativePrompts
  -> NativeAIClient URLSession
  -> JSON decode into DraftResult / OutlineResult / TopicPayload / WritingAdvisorResult
  -> NativeDatabase recordAICall / persist outputs
  -> SwiftUI refresh
```

智能下一步流：

```text
SwiftUI 智能下一步
  -> WorkshopStore.currentWritingContext
  -> WritingContextBuilder
  -> NativePrompts.writingAdvisor
  -> NativeAIClient URLSession / NativeFallbacks
  -> JSON decode into WritingAdvisorResult
  -> NativeDatabase.writing_advisor_runs
  -> Inspector 显示阶段、最大问题、下一步和可执行动作
```

局部改写流：

```text
SelectedTextEditor / NSTextView selection
  -> WorkshopStore.rewriteSelectedContent
  -> NativePrompts.rewriteSelection
  -> NativeAIClient URLSession / NativeFallbacks
  -> JSON decode into RewriteResult
  -> replace only selected NSRange in content
```

改稿版本流：

```text
生成初稿 / 大纲成稿 / 全文润色 / 多版本候选 / 局部改写
  -> capture DraftSnapshot before
  -> apply generated or rewritten content
  -> capture DraftSnapshot after
  -> NativeDatabase.draft_versions
  -> Inspector 差异对比、确认/放弃待复核版本，或恢复到改稿前/后
```

写作教练流：

```text
SwiftUI 写作诊断
  -> WorkshopStore.reviewCurrentDraft
  -> NativePrompts.writingReview
  -> NativeAIClient URLSession / NativeFallbacks
  -> JSON decode into WritingReviewResult
  -> NativeDatabase.writing_reviews
  -> Inspector 显示最新诊断、修改顺序、训练重点和最近复盘
```

无 API Key 或模型错误时：

```text
NativeAIClient error
  -> NativeFallbacks
  -> UI 显示“已使用本地模拟稿/大纲”
  -> 用户仍可保存文章
```

## 已清理内容

旧路径已移出工作区：

- `app/`
- `src/`
- `web/`
- `scripts/`
- Next / npm 配置
- Python / uv 配置
- Web / Python 构建缓存和虚拟环境

清理后，验证只保留 SwiftPM/XCTest 路径。
