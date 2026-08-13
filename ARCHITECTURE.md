# 创作工坊架构说明

更新日期：2026-08-13

## 架构定位

创作工坊现在是纯 macOS 原生本地应用。

```text
macOS / SwiftUI App
  -> WorkshopStore（过渡型装配/SwiftUI 投影；遗留工作流仍在逐步迁出）
  -> WritingSession（当前未保存稿件 + 自动保存 + pending 内存迁移）
  -> WritingWorkflow（typed command -> committed outcome）
  -> NativeDatabase.swift（schema v11 + 事务迁移/备份恢复）
       Application Support / CreativeWorkshopMac / creative_workshop.sqlite3
  -> NativeWorkflowCatalog.swift
       WorkflowDescriptor + NativePrompts + NativeFallbacks
  -> AIWorkflowExecuting / NativeAIClient.swift
  -> WorkflowEngine.swift -> AIWorkflowRunner.swift -> ModelGateway.swift
       URLSession -> OpenAI-compatible /chat/completions
  -> KeychainCredentialStore.swift
       macOS Keychain
  -> WeChatFormatterView.swift
       bundled HTML formatter -> WKWebView preview -> NSPasteboard / native export
```

旧 Web / FastAPI / Next / Python 兼容路径已从工作区移除。新的产品能力只进入 SwiftUI、`CreativeWorkshopCore` 的声明式工作流/持久化边界和相关原生视图。

## 当前组件

| 组件 | 路径 | 职责 |
| --- | --- | --- |
| macOS App | `macos/CreativeWorkshopMac` | SwiftUI 原生工作台 |
| 写作会话 | `WritingSession.swift` | 当前未保存稿件的单一内存所有者；限制自由编辑字段，管理生命周期、pending 投影和自动保存恢复 |
| 写作工作流 | `WritingWorkflow.swift` | 以 typed command/outcome 封装文章/版本/pending 写入，并拥有“润色 → 自检 → AgentRun/pending 原子提交”纵切片；成功落库后才允许 Store 投影。其余流程仍按纵切片迁移 |
| 原生 SQLite 层 | `NativeDatabase.swift` | Schema、文章/选题/素材/发布物料/风格/统计、迁移版本 |
| AI 执行兼容入口 | `AIWorkflowExecuting` + `NativeAIClient.swift` | 接收工作流描述符，委托 `WorkflowEngine` 执行；不拥有业务 prompt 或 fallback |
| AI 工作流目录 | `NativeWorkflowCatalog.swift` | 声明工作流描述符、prompt、fallback 和特定解码策略 |
| AI 工作流引擎 | `WorkflowEngine.swift` | 执行描述符并统一记录 AI 调用证据 |
| AI 工作流执行器 | `AIWorkflowRunner.swift` | 调用模型、重试、解析、fallback 结果、耗时和输入输出摘要 |
| 模型传输 | `ModelGateway.swift` | URLSession 与 OpenAI-compatible 请求/流式响应 |
| 原生提示词 | `NativePrompts.swift` + `prompt_templates` | 初稿、选题、大纲、成稿、诊断、改写、智能建议、发布物料等可编辑 Prompt |
| 原生 fallback | `NativeFallbacks.swift` | 无 API Key 或模型失败时保持流程可用 |
| 智能上下文包 | `WritingContextBuilder.swift` | 汇总当前稿件、素材、风格、最近文章和最近诊断 |
| 风格库 | `style_profiles` + Settings | 风格、体裁评价重点、样本、作者雷区 |
| 提示词模板库 | `prompt_templates` + Settings | 各 AI 工作流 system/user prompt 编辑 |
| 智能下一步 | `writing_advisor_runs` + 「诊断复核」屏 | 判断阶段、最大问题、下一步动作和推荐按钮 |
| 写作教练 | `writing_reviews` + 「诊断复核」屏 | 保存 AI 诊断、问题清单、修改顺序和训练重点 |
| 局部改写 | `SelectedTextEditor.swift` + `RewriteResult` | 读取正文选区，只替换选中片段 |
| 改稿版本 | `draft_versions` + 「发表前审核」屏 | 保存改稿前后标题、摘要、正文，并支持恢复 |
| 素材箱 | `ideas` + `MaterialsView.swift` | 素材新增、编辑、删除、入稿、生成选题 |
| 发布物料 | `publish_assets` + 「发布物料」屏 | 摘要、封面文案、朋友圈文案、标签、小红书版本、封面图提示词 |
| 公众号排版 | `WeChatFormatterView.swift` + `Resources/WeChatFormatter` | 当前稿件的主题预览、Obsidian 图片解析、微信富文本复制和原生文件导出；渲染依赖随 App 离线打包，WebKit 不拥有文章数据 |
| Keychain | `KeychainCredentialStore.swift` | API Key 安全存储 |
| 运行脚本 | `script/build_and_run.sh` | 构建并启动 `.app` |
| 写作质量评测 | `macos/CreativeWorkshopMac/Sources/CreativeWorkshopEval` + `evals/` | 独立 CLI，跑 direct/agent/deep/agentic 四条管线，锚点评分 + 放行门判定（PRD 22.4.2 / 23.4） |
| 半自动调度 | `AdvisorPlanRunner.swift` + `agent_runs` | 按"智能下一步"计划顺序执行动作，待复核处暂停（PRD 23.5，L1.5） |
| 代理会话（实验室） | `WritingAgentCoordinator.swift` + `agent_lab_enabled` / `agent_call_budget` | L2 有界决策循环：模型选动作、护栏管预算与熔断，产物进待复核；默认关闭，评测放行门达标才转默认（PRD 23.6） |

## SwiftPM 模块划分

`macos/CreativeWorkshopMac/Package.swift` 声明三个产品 target：

- `CreativeWorkshopCore`：库 target，持有 `Models/`、`Services/`、`Support/`（`NativeDatabase`、`NativeWorkflowCatalog`、`AgentDraftCoordinator`、`DeepDraftCoordinator`、`NativePrompts`、`NativeFallbacks` 等）。跨 target 复用的类型/方法用 `package` 访问级别标注，只在包内可见，不对外暴露。
- `CreativeWorkshopMac`：可执行 target，只保留 `App/`、`Views/`、`Stores/`（SwiftUI 界面 + `WorkshopStore`），依赖 `CreativeWorkshopCore`。
- `CreativeWorkshopEval`：可执行 target，依赖 `CreativeWorkshopCore`（不依赖 `CreativeWorkshopMac`，因为 SwiftPM 的 executableTarget 不产出可供其他 target 链接的静态库），复用同一套 `NativeWorkflowCatalog`/协调器跑评测管线。

`CreativeWorkshopCore` 同时承载 `WritingSession` 与 `WritingWorkflow` 深模块。`WorkshopStore` 装配它们，并把 session state 与 committed outcomes 投影给 SwiftUI；在已迁移的文章/草稿版本/pending seam 和全文润色纵切片上，Store 不再直接拥有数据库提交或 AI 编排。诊断、发布物料、选题等遗留流程仍是过渡型编排，后续按完整纵切片迁入同一边界。

## 边界原则

1. macOS 原生端是唯一主线；公众号排版使用系统 WebKit 作为受控渲染面，不引入本地 Web 服务。
2. 原生 App 不依赖本地 HTTP 后端。
3. 本地数据由原生 SQLite 拥有。
4. API Key 只进入 Keychain。
5. 旧 Web / FastAPI / Next / Python 代码不再保留在工作区。
6. 仓库内 `data/`、`exports/` 若存在，只是本机忽略的历史数据归档，不参与运行时路径。

公众号排版流：

```text
ComposerView 当前标题 / 摘要 / Markdown 正文
  -> WeChatFormatterView（SwiftUI 原生工具栏）
  -> bundled formatter resource / WKWebView
  -> 微信兼容内联样式 HTML
  -> NSPasteboard（public.html + 纯文本备用）
     或 NSSavePanel + WKWebView PDF / snapshot 导出
```

排版窗口不保存第二份文章草稿；文章内容仍由 `WorkshopStore` 和原生 SQLite 唯一持有。WebKit 使用非持久化数据存储，主题与自定义 CSS 由 App 的 `UserDefaults` 保存。

## 启动路径

```bash
./script/build_and_run.sh
```

脚本只负责 SwiftPM 构建、生成并临时签名 `dist/CreativeWorkshopMac.app`，随后按模式启动或调试。它不会写入 `/Applications`，也不会启动 FastAPI、Python、uvicorn、Next 或 npm。

## 原生运行流

```text
SwiftUI action
  -> WorkshopStore projection
  -> WritingSession.edit（仅作者可编辑字段）
     或 WritingWorkflow.execute（有持久化/治理语义的 command）
  -> NativeDatabase（事务成功）
  -> WritingWorkflow.Outcome
  -> WritingSession / WorkshopStore projection
  -> NativeWorkflowCatalog / WorkflowDescriptor
  -> NativeAIClient -> WorkflowEngine -> AIWorkflowRunner -> ModelGateway
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
  -> 「诊断复核」屏显示阶段、最大问题、下一步和可执行动作
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
  -> compute candidate after（尚不覆盖当前稿件）
  -> WritingWorkflow 先写 NativeDatabase.draft_versions(pending)
  -> WritingSession.stage（校验 before/revision 后才预览）
  -> 「诊断复核」屏差异对比
  -> WritingWorkflow 条件确认/放弃成功
  -> WritingSession 提交确认或精确恢复 before
```

写作教练流：

```text
SwiftUI 写作诊断
  -> WorkshopStore.reviewCurrentDraft
  -> NativePrompts.writingReview
  -> NativeAIClient URLSession / NativeFallbacks
  -> JSON decode into WritingReviewResult
  -> NativeDatabase.writing_reviews
  -> 「诊断复核」屏显示最新诊断、修改顺序、训练重点和最近复盘
```

无 API Key 或模型错误时：

```text
AIWorkflowRunner returns success=false + declared fallback result
  -> 上层工作流按契约中止，或将允许的演示 fallback 明确标注后交给用户复核
  -> 已接受内容不被静默覆盖
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
