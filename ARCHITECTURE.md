# 创作工坊架构说明

更新日期：2026-09-12

## 架构定位

创作工坊是纯 macOS 原生本地应用。

```text
macOS / SwiftUI App（两列外壳：导航列 + 内容列）
  -> WorkspaceNavigator（导航选中态；只存导航，不碰产品事实）
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
| 导航外壳 | `ContentView.swift` + `SidebarView.swift` + `WorkspaceNavigator.swift` | 两列布局与十个目的地的唯一导航来源；选中态由 App 持有，视图与 ⌘, 菜单命令共享同一份 |
| 设计令牌 | `WorkshopDesignSystem.swift` | 共享布局常量与外观模式（跟随系统/浅色/深色）；令牌只在两块真实屏幕需要同一个值后才新增 |
| 作者档案 | `AuthorProfile.swift` | 本地笔名与头像，纯显示；不注册不联网，不进 prompt、署名或生成结果，因此不占主 SQLite |
| 写作会话 | `WritingSession.swift` | 当前未保存稿件的单一内存所有者；限制自由编辑字段，管理生命周期、pending 投影和自动保存恢复 |
| 写作工作流 | `WritingWorkflow.swift` | 以 typed command/outcome 封装文章/版本/pending 写入，并拥有纵切片的原子提交；成功落库后才允许 Store 投影。AI 工作流已全部迁入，Store 不再直接发起任何一次调用 |
| 原生 SQLite 层 | `NativeDatabase.swift` | Schema v11、文章/选题/素材/发布物料/风格/统计、事务迁移与迁移前备份 |
| 待复核状态机 | `PendingReviewMachine.swift` | 交付（pending 落库 + 卡片组装）、确认（翻 confirmed）、放弃（删行）、孤儿清理；绝不误删 confirmed。UI 状态与快照应用仍归 Store |
| 记忆闭环 | `MemoryLoopService.swift` | 作者雷区与编辑偏好的归纳；铁律是归纳只产候选、绝不写库，写库只发生在作者逐条确认之后 |
| 多候选优选 | `CandidateSelectionCoordinator.swift` | 三个 PolishMode 候选 → 评委随机呈现排序 → 最优候选接入深度成稿；数据库写入经注入闭包，本协调器不持有 NativeDatabase |
| 发表前审核 | `PrePublishAuditCoordinator.swift` + `PrePublishAuditLocalVerifier.swift` | 模型审核加一道本地核对：正文引文在素材库/归档正文中找不到完全匹配时补报「引文核对」问题 |
| 发布统计 | `PublishingMetricsRecorder.swift` | 文章发布时落编辑记录，产出编辑统计与月度小结快照 |
| 本地检索 | `FragmentRetriever.swift` + `WorkshopStore+Retrieval.swift` + `fragments` | 正文按段切片、按查询检索 Top-N，并拼成带出处与相关度的素材块 |
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
| 验证入口 | `script/verify.sh` + `script/architecture_guard.sh` | 提交前单条命令：架构守卫 + 全量单元测试 |
| 运行脚本 | `script/build_and_run.sh` | 构建并启动 `.app` |
| 写作质量评测 | `Sources/CreativeWorkshopEval` + `evals/` | 独立 CLI，默认跑 direct/agent/deep 三条管线（agentic 已退出默认集），锚点评分 + 放行门判定（PRD 22.4.2 / 23.4） |
| 配对重判 | `RejudgeRunner.swift` + `RejudgeReport.swift` + `RejudgeStore.swift` | 拿存量正文只重跑评分，配对对照验证评分侧改动（PRD 24.14） |
| 半自动调度 | `AdvisorPlanRunner.swift` + `agent_runs` | 按「智能下一步」计划顺序执行动作，待复核处暂停（PRD 23.5，L1.5） |
| 代理会话（实验室） | `WritingAgentCoordinator.swift` + `agent_lab_enabled` / `agent_call_budget` | L2 有界决策循环：模型选动作、护栏管预算与熔断，产物进待复核；默认关闭，评测放行门达标才转默认（PRD 23.6） |

## SwiftPM 模块划分

`macos/CreativeWorkshopMac/Package.swift` 声明三个 target 加两个测试 target：

- `CreativeWorkshopCore`：库 target，持有 `Models/`、`Services/`、`Support/`（`NativeDatabase`、`NativeWorkflowCatalog`、`WritingSession`、`WritingWorkflow`、各协调器、`NativePrompts`、`NativeFallbacks` 等）。跨 target 复用的类型/方法用 `package` 访问级别标注，只在包内可见，不对外暴露。
- `CreativeWorkshopMac`：可执行 target，只保留 `App/`、`Views/`、`Stores/`、`Design/`（SwiftUI 界面 + `WorkshopStore`），依赖 `CreativeWorkshopCore`，链接 WebKit。
- `CreativeWorkshopEval`：可执行 target，依赖 `CreativeWorkshopCore`（不依赖 `CreativeWorkshopMac`，因为 SwiftPM 的 executableTarget 不产出可供其他 target 链接的静态库），复用同一套 `NativeWorkflowCatalog`/协调器跑评测管线。
- `CreativeWorkshopMacTests` / `CreativeWorkshopEvalTests`：两套 XCTest。

`CreativeWorkshopCore` 同时承载 `WritingSession` 与 `WritingWorkflow` 深模块。`WorkshopStore` 装配它们，并把 session state 与 committed outcomes 投影给 SwiftUI。

### WorkshopStore 的拆分与瘦身

`WorkshopStore` 是一个主文件加十二个按主题分刀的 extension：`+AdvisorPlan`、`+AgentSession`、`+Autosave`、`+Candidates`、`+Export`、`+MemoryLoop`、`+PendingReview`、`+PublishFlow`、`+Retrieval`、`+SessionSwitch`、`+StyleAndTemplates`、`+TopicsAndIdeas`。

每个 extension 的形状一致：**领域逻辑在 Core 的服务/协调器里，这里只留「调服务 → 更新 `@Published` → statusText」的薄绑定**。两处刻意没有搬家，理由都是同一条——搬家不该以放宽可见性为代价：

- 模型设置与 API Key 留在主文件，因为它们要读 `private let keychain`，密钥的可见范围不该为了少几行让步；
- `currentTopicPayload` / `topicPayload` 留在主文件，因为「快速成稿」「大纲成稿」也要用，而 `private` 是文件级作用域。

主文件行数由守卫的棘轮盯着：每完成一个瘦身任务把警戒线拧低一格，只降不升，当前 1700，终点 1200。

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

**主题与复制是两条渲染路径**：预览走 WKWebView 的主题 CSS，复制走另一套内联样式生成。改主题必须同时改复制路径，否则预览对了、粘进公众号还是旧样子。

## 导航外壳

两列：导航列 + 内容列，一次只显示一个目的地。导航此前被劈在三处（侧栏 List、Composer 分段、Inspector 分段），现在收拢为两组共十个目的地：

- **当前稿件**（跟着这一篇走）：创作过程、正文、发布物料、诊断复核、发表前审核
- **工作区**（跨稿件的列表与库）：我的文章、待写选题、素材箱、资料库
- 设置是第十个目的地，从独立 preferences 窗口搬进内容列，仍可用 ⌘, 到达

「最近文章」退为导航列里一个可折叠的快捷入口。外观（跟随系统/浅色/深色）在导航列页脚或设置 → 高级切换。

## 启动与验证

```bash
./script/build_and_run.sh          # 构建 + 临时签名 + 启动 dist/CreativeWorkshopMac.app
./script/build_and_run.sh --verify

./script/verify.sh                 # 守卫 + 全量测试（提交前的唯一验证命令）
./script/verify.sh --guard-only    # 只跑守卫，秒级
./script/verify.sh --filter Xxx    # 其余参数透传给 swift test
```

`build_and_run.sh` 只负责 SwiftPM 构建、生成并临时签名 `.app`，随后按模式启动或调试。它不会写入 `/Applications`，也不会启动 FastAPI、Python、uvicorn、Next 或 npm。

`verify.sh` 的存在是因为守卫此前只挂在 `build_and_run.sh` 里——只有「要跑 App」时才执行，`swift test` 全靠手敲。于是「只改了评测侧、没启动 App」的改动可以完全绕开守卫。两者合成一条命令后，「验证过了」才有唯一含义。它与 `build_and_run.sh` 共用 `.swiftpm-state/` 下的同一套 SwiftPM 状态目录，避免两条命令互相冲掉增量构建。

执行顺序是：先跑 `test_architecture_guard.sh`（干净 fixture 必须通过，注入越界写入后必须失败——证明新增规则不是永远通过的空壳），再跑 `architecture_guard.sh`，最后 `swift test --disable-sandbox`。

### 架构守卫的规则

`script/architecture_guard.sh` 静态拦截以下回流：

1. **Views 不得直接引用** `NativeAIClient` / `ModelGateway` / `AIWorkflowRunner`。
2. **不得直接 `runner.run(`**：AI 工作流一律走 `WorkflowDescriptor` / `WorkflowEngine`。
3. **解码 fallback 不得集中化**：`if T.self` / `as! T` / `decodeModelJSON` 这类中心化泛型链被禁止，解码策略必须声明在各自的 `WorkflowDescriptor` 上。
4. **Store 不得手写 `ai_calls`**：证据由 `WorkflowEngine` 统一记录。
5. **Store 边界**：所有 `WorkshopStore*.swift` 里不得出现 `saveArticle` / `saveDraftVersion` / `saveWritingAdvisorRun` / `saveWritingReview` / `savePublishAssets` / `createTopics` 等直接持久化，不得直接 new `PendingReviewMachine` / `DeepDraftCoordinator`，不得直接调 `NativeWorkflowCatalog` 的业务工作流——一律经 `WritingSession` / `WritingWorkflow`。
6. **死视图**：定义了却没有任何调用点的视图片段不会被渲染。三类都查——`private var xxx: some View`、`private func xxx(...) -> some View`（可带泛型、可跨行）、`struct XxxView: View`（跨文件计数，因为定义了却没人 new 同样一行都不上屏）。引用计数按 `\bname\b` 而非 `name(`，否则 `assets.map(hasUsableContent)` 这种合法的裸函数引用会被误报。
7. **瘦身棘轮**：`WorkshopStore.swift` 超过 1700 行告警。

这条静态检查线拦的是单元测试拦不到的东西：测试只能验 Store 层的计算属性，验不到有没有被挂进视图树。

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
  -> WritingContextBuilder（当前稿件 + 素材 + 风格 + 最近文章 + 最近诊断）
  -> WritingWorkflow 智能下一步切片（结果与运行轨迹同一事务提交）
  -> NativePrompts.writingAdvisor
  -> NativeAIClient URLSession / NativeFallbacks
  -> JSON decode into WritingAdvisorResult
  -> NativeDatabase.writing_advisor_runs
  -> 「诊断复核」屏显示阶段、最大问题、下一步和可执行动作
```

局部改写流：

```text
SelectedTextEditor / NSTextView selection
  -> WritingWorkflow 局部改写切片
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

待复核交付经 `PendingReviewMachine`：交付时 pending 落库并组装卡片，确认翻 confirmed，放弃删行（快照恢复由调用方执行），孤儿按隐式放弃清理且绝不误删 confirmed。

写作教练流：

```text
SwiftUI 写作诊断
  -> WritingWorkflow 诊断切片（提交时带上它检查的那一份快照）
  -> NativePrompts.writingReview
  -> NativeAIClient URLSession / NativeFallbacks
  -> JSON decode into WritingReviewResult
  -> NativeDatabase.writing_reviews
  -> 「诊断复核」屏显示最新诊断、修改顺序、训练重点和最近复盘
```

记忆闭环流（雷区 / 编辑偏好）：

```text
发布编辑记录 / 历史诊断
  -> MemoryLoopService.summarize*（只产候选，不写库）
  -> 去重守卫过滤掉与已确认项重复的候选
  -> 作者逐条确认
  -> MemoryLoopService.confirm* -> style_profiles
```

无 API Key 或模型错误时：

```text
AIWorkflowRunner returns success=false + declared fallback result
  -> 上层工作流按契约中止，或将允许的演示 fallback 明确标注后交给用户复核
  -> 已接受内容不被静默覆盖
```

## 数据表

主库 `~/Library/Application Support/CreativeWorkshopMac/creative_workshop.sqlite3`，schema v11，迁移为事务式、迁移前备份、恢复路径经验证。

- 内容：`articles`、`draft_versions`、`topics`、`ideas`、`fragments`、`publish_assets`
- AI 证据：`ai_calls`、`agent_runs`、`agent_steps`、`writing_advisor_runs`、`writing_reviews`、`pre_publish_audits`、`edit_records`
- 配置：`settings`、`style_profiles`、`prompt_templates`、`schema_migrations`

## 评测子系统

独立于主 App 的 CLI，从 `evals/cases/` 读取 28 个用例，默认跑 `direct` / `agent` / `deep` 三条管线并用写作诊断打分，结果写入 `evals/eval_results.sqlite3`，报告写入 `evals/reports/`。它与主 App 的唯一接缝是 `EvalPipelineFacade.swift`：只暴露评测所需的输入输出，不为了评测放宽任何既有内部类型的访问级别。

需要先在 App 设置页配置好 API Key；没有 Key 时直接报错退出，不会静默走本地 fallback。失败样本（超时、连接中断等）不打分，报告头点名「无效样本」，不计入差值也不进放行门。

```bash
swift run --package-path macos/CreativeWorkshopMac CreativeWorkshopEval
swift run --package-path macos/CreativeWorkshopMac CreativeWorkshopEval --resume
```

全量一轮（28 用例 × 3 管线）约 6 小时；`--resume` 续跑最近一次 run，已成功的格子跳过，失败的格子重跑，报告按同一 run_id 补成整轮。

### 配对重判（PRD 24.14）

`--rejudge` 拿**存量正文**只重跑评分，不重新生成。两个评分变量读的是同一个字节序列，因此是配对对照——组间方差被消掉，检出同样大小差异所需的样本量远小于两次独立全量重跑。

```bash
caffeinate -i swift run --package-path macos/CreativeWorkshopMac CreativeWorkshopEval --rejudge latest
```

报告写入 `evals/reports/rejudge-*.md`，含配对差值与 95% 置信区间（区间跨 0 是「判不出」，不是「没效果」）、两臂的分数分布、完整问题维度表（维度/高中低/覆盖格数——主评测路径只存三个计数，查不到维度）、以及高危问题的原文片段与判词。

结果落 `rejudge_results` 表，与基线表 `eval_results` 分开，不污染跨轮基线。

## 自动化层级

| 层级 | 实现 | 状态 |
| --- | --- | --- |
| L1 | 单个 `WritingWorkflow` 切片，作者点一次跑一步 | 默认 |
| L1.5 | `AdvisorPlanRunner`：按「智能下一步」计划顺序执行，待复核处暂停 | 默认 |
| L2 | `WritingAgentCoordinator`：有界决策循环，模型自选动作，护栏管预算与熔断 | **默认关闭**（`agent_lab_enabled`），留在实验室，评测放行门达标才转默认 |

初稿本身是代理式的：`AgentDraftCoordinator` 依次产出 writing brief、论点检查、分段草稿、自我批评，过 `AgentDraftQualityGate` 后进待复核；待复核卡可展开查看代理运行轨迹。`DeepDraftCoordinator` 是深度成稿路径，多候选优选的最优候选会接入它。

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
