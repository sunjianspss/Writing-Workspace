import Foundation

/// evals 可执行文件（PRD 22.4.2）复用主 target 编排逻辑的唯一接缝：只暴露评测所需的输入输出，
/// 不改变 NativeDatabase / NativeWorkflowCatalog / AgentDraftCoordinator / DeepDraftCoordinator /
/// ContextPackage / StyleProfile 等既有内部类型的访问级别——这些类型在本文件内仍按原有 internal
/// 访问级别使用，只是本文件本身和它暴露的几个薄类型标记为 package。
package struct EvalCaseInput {
    package var id: String
    package var idea: String
    package var direction: String
    package var materials: String
    package var content: String

    package init(id: String, idea: String, direction: String, materials: String, content: String) {
        self.id = id
        self.idea = idea
        self.direction = direction
        self.materials = materials
        self.content = content
    }
}

package struct EvalPipelineOutcome {
    package var title: String
    package var content: String
    package var overallScore: Int?
    package var highIssueCount: Int
    package var mediumIssueCount: Int
    package var lowIssueCount: Int
    package var wordCount: Int
    package var callCount: Int
    /// 单步 fallback（PRD 22.3.3-B 的"演示模式兜底"）或熔断触发的次数总和（PRD 23.4 放行门）。
    package var fallbackCount: Int
    package var elapsedMS: Int
    package var success: Bool
    package var error: String
    /// 验证信号一行总结（PRD 23.7），来自 VerificationReport.summaryLine。
    package var verificationSummary: String
    /// search_materials 本地检索次数（PRD 23.8.1）：不计入 callCount，单独记一列。
    package var searchCount: Int
    /// agentic 会话摘要（评测仪器修缮）：动作序列 + 停止原因。无头评测不经过 Store 的
    /// recordAgentRun，会话轨迹在此压缩进 outcome，随 rawJSON 入库并在报告按用例展示；
    /// 其余管线为空字符串。
    package var sessionSummary: String = ""
    /// 本次诊断报出的问题维度，形如 `人称视角(中)`（24.9-P1）。24.2 的裁决是"趋势改用问题
    /// 清单而非分数来读"——但工具此前只跨轮比分数，清单只有三个计数、没有维度，读不出
    /// "哪条问题新出现、哪条消失了"。无效样本为空数组。
    package var issueDimensions: [String] = []
}

package enum EvalFacadeError: LocalizedError {
    case unknownPipeline(String)

    package var errorDescription: String? {
        switch self {
        case let .unknownPipeline(name):
            return "未知的评测管线：\(name)"
        }
    }
}

package struct EvalPipelineFacade {
    package static let pipelineNames = ["direct", "agent", "deep", "agentic"]

    /// 评测评分专用锚点模板（评测仪器修缮）：只在 eval 路径生效，不改动 App 内写作教练的
    /// 默认 prompt。目的：迫使分数按分档锚点给出、与问题清单互相一致，避免评分向 70 分档塌缩。
    package static let scoringTemplate = PromptTemplate(
        id: -1,
        key: PromptTemplateKey.writingReview.rawValue,
        name: "评测评分（锚点版）",
        system_prompt: "你是严谨的中文写作评审，只输出用户要求的 JSON。",
        user_template: """
        请为下面这篇文章评分并列出问题。先找证据，再定分数；不同质量的稿件分数必须拉开，不要都给 70 分档的"安全分"。

        【写作方向】{{direction}}
        【写作目标】{{idea}}
        【标题】{{title}}
        【正文】
        {{content}}

        【作者风格要求】
        {{style_description}}

        评分流程（必须按顺序执行）：
        1. 先逐条找出具体问题：引用原文片段，标注严重度（高=破坏阅读或偏题；中=明显削弱质量；低=打磨项）
        2. 再按锚点确定 overall_score：
           - 90–100：可直接发表。结构完整推进、细节具体真实、无任何高危问题、无腔调问题
           - 80–89：小修可发。主线清楚有推进，只有 1–2 处中低危问题
           - 70–79：中修。存在 1 处高危问题，或 3 处以上中危问题，或细节明显单薄
           - 60–69：大修。偏题、结构断裂、大段空泛议论或多处高危问题
           - 0–59：需重写。跑题、明显截断、大量套话或腔调失控
        3. 分数必须与问题清单一致：有高危问题不得进入 80 档；没有任何问题不应停留在 70 档

        请只输出 JSON，不要输出 Markdown 代码块：
        {"summary":"一句话评价","overall_score":83,"strengths":["优点"],"issues":[{"dimension":"维度","severity":"高/中/低","excerpt":"原文片段","problem":"问题","suggestion":"建议"}],"revision_plan":["第一步怎么改"],"training_focus":[],"style_notes":[],"resolved_from_last":[]}
        """,
        is_default: nil,
        updated_at: nil,
        created_at: nil
    )

    /// agentic 会话轨迹的单行压缩（评测仪器修缮），纯函数便于测试。
    package static func agentSessionSummary(stepNames: [String], stopReason: String) -> String {
        guard !stepNames.isEmpty else {
            return "步骤：无；停止：\(stopReason)"
        }
        return "步骤(\(stepNames.count))：\(stepNames.joined(separator: "→"))；停止：\(stopReason)"
    }

    /// 各管线生成动作实际取用的模板 key。App 的写作动作一律走 `prompt_templates` 里的模板
    /// （`WorkshopStore.promptTemplate(for:)`），评测此前对这几个动作一律传 nil，量的是 App
    /// 从不执行的内联 prompt——与 24.2「仪器修好了，教练没修」同一类断链，只是方向相反。
    package static let pipelineTemplateKeys: [PromptTemplateKey] = [
        .draft,
        .outline,
        .polishDraft,
        .writingReview,
        .agentDecision
    ]

    private let database: NativeDatabase
    private let executor: AIWorkflowExecuting
    private let config: ModelConfig
    private let apiKey: String
    /// 报告头用的模板来源摘要（24.5）：prompt 换了分数就不可比，和风格样本一样必须可见。
    package let promptTemplateSummary: String
    /// 固定的评测风格样本（24.4）。App 的 `resolveStyle()` 会注入近期同体裁文章作 few-shot，
    /// 评测此前完全跳过这一步，量的是一个作者实际用不到的「零样本」配置。这里补上，但样本
    /// 来自版本控制的固定文件而非活库——量具的配置必须固定，否则分数会随语料增长漂移。
    private let styleSamples: [String]

    package init(
        apiKey: String,
        executor: AIWorkflowExecuting = NativeAIClient(),
        databaseURL: URL? = nil,
        styleSamples: [String] = []
    ) throws {
        self.apiKey = apiKey
        self.executor = executor
        self.styleSamples = styleSamples
        self.database = try NativeDatabase(databaseURL: databaseURL)
        self.config = try database.modelConfig()
        self.promptTemplateSummary = Self.summarizeTemplates(database: database)
    }

    /// 库里取模板；取不到（理论上不会，建库即 seed）就退回内联 prompt，并在报告头点名。
    private func promptTemplate(_ key: PromptTemplateKey) -> PromptTemplate? {
        try? database.promptTemplate(key: key)
    }

    private static func summarizeTemplates(database: NativeDatabase) -> String {
        pipelineTemplateKeys.map { key in
            guard let template = (try? database.promptTemplate(key: key)) ?? nil else {
                return "\(key.title)(缺失→内联)"
            }
            // is_default = 0 意味着作者手改过这条模板：评测跑的就不是内置 prompt 了，必须点名。
            return "\(key.title)(\(template.is_default == 0 ? "作者自定义" : "默认"))"
        }
        .joined(separator: "、")
    }

    package static func readAPIKey() -> String {
        KeychainCredentialStore().readAPIKey()
    }

    package func run(pipeline: String, evalCase: EvalCaseInput) async throws -> EvalPipelineOutcome {
        var style = try database.styleProfile(forDirection: evalCase.direction)
        if !styleSamples.isEmpty {
            style.sample_texts = styleSamples + (style.sample_texts ?? [])
        }
        switch pipeline {
        case "direct":
            return try await runDirect(evalCase, style: style)
        case "agent":
            return try await runAgent(evalCase, style: style)
        case "deep":
            return try await runDeep(evalCase, style: style)
        case "agentic":
            return try await runAgentic(evalCase, style: style)
        default:
            throw EvalFacadeError.unknownPipeline(pipeline)
        }
    }

    // MARK: - Pipelines（PRD 22.4.2：direct 一步成稿，agent 复用 AgentDraftCoordinator，
    // deep 在 agent 产出基础上接入 DeepDraftCoordinator）

    private func runDirect(_ evalCase: EvalCaseInput, style: StyleProfile) async throws -> EvalPipelineOutcome {
        let topic = TopicPayload(
            title: evalCase.idea,
            direction: evalCase.direction,
            core_viewpoint: nil,
            target_reader: nil,
            description: evalCase.idea,
            angle: nil,
            emotion: nil,
            score: nil,
            status: nil,
            tags: nil
        )
        let context = makeContext(stage: "评测：一步成稿", evalCase: evalCase, style: style, content: evalCase.content)
        let run = await executor.execute(
            NativeWorkflowCatalog.draft(topic: topic, context: context, style: style, template: promptTemplate(.draft)),
            config: config,
            apiKey: apiKey
        )
        return try await score(
            evalCase: evalCase,
            style: style,
            title: run.result.title ?? topic.title,
            content: run.result.content ?? "",
            callCount: 1,
            fallbackCount: run.success ? 0 : 1,
            elapsedMS: run.elapsedMS,
            success: run.success,
            error: run.error
        )
    }

    private func runAgent(_ evalCase: EvalCaseInput, style: StyleProfile) async throws -> EvalPipelineOutcome {
        let response = await agentDraft(evalCase, style: style)
        return try await score(
            evalCase: evalCase,
            style: style,
            title: response.result.title ?? evalCase.idea,
            content: response.result.content ?? "",
            callCount: response.steps.count,
            fallbackCount: response.steps.filter { $0.status == "fallback" }.count,
            elapsedMS: response.elapsed_ms,
            success: response.success,
            error: response.error
        )
    }

    private func runDeep(_ evalCase: EvalCaseInput, style: StyleProfile) async throws -> EvalPipelineOutcome {
        let agentResponse = await agentDraft(evalCase, style: style)
        let deepInput = DeepDraftInput(
            title: agentResponse.result.title ?? evalCase.idea,
            summary: agentResponse.result.summary ?? "",
            content: agentResponse.result.content ?? "",
            outline: "",
            idea: evalCase.idea,
            direction: evalCase.direction,
            materials: evalCase.materials,
            style: style,
            previousReview: nil,
            // deep 内部这次诊断属于「生成路径」（诊断→修订闭环），App 侧同样传库内模板；
            // 最终评分用的 scoringTemplate 是量具，固定在代码里，两者不要混为一谈。
            writingReviewTemplate: promptTemplate(.writingReview),
            config: config,
            apiKey: apiKey
        )
        let deepOutput = try await DeepDraftCoordinator(aiClient: executor).run(input: deepInput)
        let errors = [agentResponse.error, deepOutput.error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return try await score(
            evalCase: evalCase,
            style: style,
            title: deepOutput.draft.title ?? agentResponse.result.title ?? evalCase.idea,
            content: deepOutput.draft.content ?? agentResponse.result.content ?? "",
            callCount: agentResponse.steps.count + deepOutput.steps.count,
            fallbackCount: agentResponse.steps.filter { $0.status == "fallback" }.count
                + deepOutput.steps.filter { $0.status == "fallback" }.count,
            elapsedMS: agentResponse.elapsed_ms + deepOutput.elapsed_ms,
            success: agentResponse.success && deepOutput.success,
            error: errors.joined(separator: "；")
        )
    }

    /// 23.6 有界代理循环管线：无头跑 WritingAgentCoordinator，供放行门（23.4）与 deep 对照。
    /// 第二轮评测修缮：无头环境没有作者可问，ask_author 从动作空间整体移除
    /// （首轮曾有半数会话以 ask_author 收尾、一例交付空正文得 0 分）。
    private func runAgentic(_ evalCase: EvalCaseInput, style: StyleProfile) async throws -> EvalPipelineOutcome {
        let input = WritingAgentSessionInput(
            idea: evalCase.idea,
            direction: evalCase.direction,
            materials: evalCase.materials,
            style: style,
            content: evalCase.content,
            config: config,
            apiKey: apiKey,
            callBudget: (try? database.agentCallBudget()) ?? 12,
            decisionTemplate: promptTemplate(.agentDecision),
            writingReviewTemplate: promptTemplate(.writingReview),
            polishTemplate: promptTemplate(.polishDraft),
            draftTemplate: promptTemplate(.draft),
            outlineTemplate: promptTemplate(.outline),
            allowAskAuthor: false
        )
        let session = await WritingAgentCoordinator(executor: executor).run(input: input)
        let circuitBreakFallback: Int
        switch session.stopReason {
        case .finished, .askAuthor:
            circuitBreakFallback = 0
        default:
            circuitBreakFallback = 1
        }
        let fallbackCount = session.steps.filter { $0.status == "fallback" }.count + circuitBreakFallback
        // search_materials 是纯本地检索，不发起模型调用，不计入 callCount（单独用 searchCount 记录）。
        let modelCallSteps = session.steps.filter { $0.name != AgentSessionAction.searchMaterials.title }
        let sessionSummary = Self.agentSessionSummary(
            stepNames: session.steps.map(\.name),
            stopReason: session.stopReason.summaryText
        )
        return try await score(
            evalCase: evalCase,
            style: style,
            title: session.finalState.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? evalCase.idea : session.finalState.title,
            content: session.finalState.content,
            callCount: modelCallSteps.count,
            fallbackCount: fallbackCount,
            elapsedMS: session.elapsed_ms,
            success: session.stopReason == .finished || session.isAskAuthor,
            error: session.stopReason.summaryText,
            searchCount: session.finalState.searchCount,
            sessionSummary: sessionSummary
        )
    }

    private func agentDraft(_ evalCase: EvalCaseInput, style: StyleProfile) async -> AgentDraftResponse {
        let context = makeContext(stage: "评测：代理生成初稿", evalCase: evalCase, style: style, content: evalCase.content)
        return await AgentDraftCoordinator(executor: executor).run(
            context: context,
            style: style,
            config: config,
            apiKey: apiKey
        )
    }

    private func score(
        evalCase: EvalCaseInput,
        style: StyleProfile,
        title: String,
        content: String,
        callCount: Int,
        fallbackCount: Int,
        elapsedMS: Int,
        success: Bool,
        error: String,
        searchCount: Int = 0,
        sessionSummary: String = ""
    ) async throws -> EvalPipelineOutcome {
        // 失败样本不打分（24.9）：生成失败时 content 是 NativeFallbacks 的本地兜底稿，给它打分
        // 得到的是"兜底模板的分数"，却会一路进报告、进差值、进放行门。此前 68 行 success=0 的
        // 结果都带着分数入库（其中 32 行耗时 ≥5s，离线熔断照不到）。这里直接不发评分调用：
        // 既省一次模型调用，也从结构上保证无效样本没有分数可被误用。
        guard success else {
            return EvalPipelineOutcome(
                title: title,
                content: content,
                overallScore: nil,
                highIssueCount: 0,
                mediumIssueCount: 0,
                lowIssueCount: 0,
                wordCount: content.count,
                callCount: callCount,
                fallbackCount: fallbackCount,
                elapsedMS: elapsedMS,
                success: false,
                error: error.trimmingCharacters(in: .whitespacesAndNewlines),
                verificationSummary: "未评分：生成失败，本样本不计入分数与放行门。",
                searchCount: searchCount,
                sessionSummary: sessionSummary
            )
        }

        let reviewContext = makeContext(stage: "评测：写作诊断", evalCase: evalCase, style: style, title: title, content: content)
        let scoringDescriptor = NativeWorkflowCatalog.writingReview(
            context: reviewContext,
            style: style,
            previousReview: nil,
            template: Self.scoringTemplate
        )
        var reviewRun = await executor.execute(scoringDescriptor, config: config, apiKey: apiKey)
        var scoringCallCount = 1
        var scoringElapsed = reviewRun.elapsedMS
        // 评分洞修补（评测仪器修缮）：非 JSON 诊断会被宽松解码吞成"成功但无分数"，
        // 报告里出现空分数格。此处补一次重评；两次都拿不到分数才带着说明落表。
        if reviewRun.result.overall_score == nil {
            let retry = await executor.execute(scoringDescriptor, config: config, apiKey: apiKey)
            scoringCallCount += 1
            scoringElapsed += retry.elapsedMS
            reviewRun = retry
        }
        // 评分调用本身失败时，`reviewRun.result` 是 `NativeFallbacks.writingReview` 按段落数、
        // 标题有无算出来的本地启发式分数（68 起步加减），既不是模型给的分，也不服从锚点。
        // 它和它的 issues 一律不得出现在报告里（24.9）。
        let issues = reviewRun.success ? (reviewRun.result.issues ?? []) : []
        let overallScore = reviewRun.success ? reviewRun.result.overall_score : nil
        let scoringHole = reviewRun.success && reviewRun.result.overall_score == nil
            ? "评分重试后仍未返回结构化分数"
            : ""
        let combinedError = [error, reviewRun.error, scoringHole]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "；")
        // 验证信号（评测仪器修缮）：对最终产物跑内容级本地检查（完整性/截断、雷区与套话），
        // 四条管线统一口径，零额外模型调用。
        let gateItems = AgentDraftQualityGateEvaluator.contentOnlyItems(
            content: content,
            knownPitfalls: (style.known_pitfalls ?? []).map(\.description)
        )
        let verificationReport = VerificationReport.build(gate: AgentDraftQualityGate(items: gateItems))
        return EvalPipelineOutcome(
            title: title,
            content: content,
            overallScore: overallScore,
            highIssueCount: issues.filter { $0.severity == "高" }.count,
            mediumIssueCount: issues.filter { $0.severity == "中" }.count,
            lowIssueCount: issues.filter { $0.severity == "低" }.count,
            wordCount: content.count,
            callCount: callCount + scoringCallCount,
            fallbackCount: fallbackCount + (reviewRun.success ? 0 : 1),
            elapsedMS: elapsedMS + scoringElapsed,
            success: success && reviewRun.success,
            error: combinedError,
            verificationSummary: verificationReport.summaryLine,
            searchCount: searchCount,
            sessionSummary: sessionSummary,
            // 维度 + 严重度，供报告跨轮比清单（24.9-P1）。严重度缺失时标「未标」而不是丢掉，
            // 否则"这条问题降级了"会被读成"这条问题消失了"。
            issueDimensions: issues.map { issue in
                let dimension = issue.dimension.trimmingCharacters(in: .whitespacesAndNewlines)
                let severity = issue.severity.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(dimension.isEmpty ? "未标维度" : dimension)(\(severity.isEmpty ? "未标" : severity))"
            }
        )
    }

    private func makeContext(
        stage: String,
        evalCase: EvalCaseInput,
        style: StyleProfile,
        title: String = "",
        content: String = ""
    ) -> ContextPackage {
        ContextPackage(
            stage: stage,
            title: title,
            summary: "",
            idea: evalCase.idea,
            direction: evalCase.direction,
            outline_excerpt: "",
            content_excerpt: content,
            materials_excerpt: evalCase.materials,
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: style.name,
            style_brief: style.tone ?? "",
            word_count: content.count,
            paragraph_count: content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
            material_count: evalCase.materials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: [],
            genre: style.genre,
            known_pitfalls: (style.known_pitfalls ?? []).map(\.description),
            last_review_summary: nil,
            learned_preferences: (style.learned_preferences ?? []).map(\.description)
        )
    }
}
