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

    private let database: NativeDatabase
    private let executor: AIWorkflowExecuting
    private let config: ModelConfig
    private let apiKey: String

    package init(apiKey: String, executor: AIWorkflowExecuting = NativeAIClient(), databaseURL: URL? = nil) throws {
        self.apiKey = apiKey
        self.executor = executor
        self.database = try NativeDatabase(databaseURL: databaseURL)
        self.config = try database.modelConfig()
    }

    package static func readAPIKey() -> String {
        KeychainCredentialStore().readAPIKey()
    }

    package func run(pipeline: String, evalCase: EvalCaseInput) async throws -> EvalPipelineOutcome {
        let style = try database.styleProfile(forDirection: evalCase.direction)
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
            NativeWorkflowCatalog.draft(topic: topic, context: context, style: style, template: nil),
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
            writingReviewTemplate: nil,
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
    /// ask_author 在评测里没有作者可问，视为 finish 处理（任务 14 明确约定）。
    private func runAgentic(_ evalCase: EvalCaseInput, style: StyleProfile) async throws -> EvalPipelineOutcome {
        let input = WritingAgentSessionInput(
            idea: evalCase.idea,
            direction: evalCase.direction,
            materials: evalCase.materials,
            style: style,
            content: evalCase.content,
            config: config,
            apiKey: apiKey,
            callBudget: (try? database.agentCallBudget()) ?? 12
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
            searchCount: session.finalState.searchCount
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
        searchCount: Int = 0
    ) async throws -> EvalPipelineOutcome {
        let reviewContext = makeContext(stage: "评测：写作诊断", evalCase: evalCase, style: style, title: title, content: content)
        let reviewRun = await executor.execute(
            NativeWorkflowCatalog.writingReview(context: reviewContext, style: style, previousReview: nil, template: nil),
            config: config,
            apiKey: apiKey
        )
        let issues = reviewRun.result.issues ?? []
        let combinedError = [error, reviewRun.error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "；")
        let verificationReport = VerificationReport.build(pitfalls: style.known_pitfalls)
        return EvalPipelineOutcome(
            title: title,
            content: content,
            overallScore: reviewRun.result.overall_score,
            highIssueCount: issues.filter { $0.severity == "高" }.count,
            mediumIssueCount: issues.filter { $0.severity == "中" }.count,
            lowIssueCount: issues.filter { $0.severity == "低" }.count,
            wordCount: content.count,
            callCount: callCount + 1,
            fallbackCount: fallbackCount + (reviewRun.success ? 0 : 1),
            elapsedMS: elapsedMS + reviewRun.elapsedMS,
            success: success && reviewRun.success,
            error: combinedError,
            verificationSummary: verificationReport.summaryLine,
            searchCount: searchCount
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
