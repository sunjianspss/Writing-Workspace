import Foundation

/// 写作域的持久化工作流边界。
///
/// `WritingWorkflow` 不持有编辑器或 UI 状态。调用者提交一个 typed command，工作流完成整组
/// 数据库语义后才返回 outcome；调用者随后才能把 outcome 投影到 `WritingSession` / Store。
/// 这条顺序约束尤其保证生成候选不会先覆盖屏幕上的正文、再因 pending 版本落库失败而失配。
@MainActor
package struct WritingWorkflow {
    package enum WorkflowError: LocalizedError {
        case missingExecutor
        /// 模型返回了空替换文本。改写不能拿空串去覆盖正文，只能整体放弃。
        case emptyRewriteReplacement

        package var errorDescription: String? {
            switch self {
            case .missingExecutor:
                "WritingWorkflow 未配置 AI executor"
            case .emptyRewriteReplacement:
                "模型没有返回可替换文本"
            }
        }
    }

    package enum Command {
        case deliverPending(PendingDelivery)
        case confirmPending(PendingDraftReview)
        case discardPending(PendingDraftReview, preservingCurrent: DraftSnapshot?)
        case cleanupPending(versionID: Int)
        case recordDraftVersion(DraftVersionRecord)
        case saveArticle(ArticleSave)
    }

    package enum Outcome {
        case pendingDelivered(DraftVersion, PendingDraftReview)
        case pendingConfirmed(DraftVersion)
        case pendingDiscarded(versionID: Int, restore: DraftSnapshot, preservedVersion: DraftVersion?)
        case pendingCleaned(versionID: Int, didRemove: Bool)
        case draftVersionRecorded(DraftVersion)
        case articleSaved(Article, overwriteVersion: DraftVersion?)
    }

    package struct PendingDelivery {
        package var articleID: Int?
        package var titleSnapshot: String
        package var actionTitle: String
        package var note: String?
        package var before: DraftSnapshot
        package var after: DraftSnapshot
        package var usedFallback: Bool
        package var selfCheck: DraftSelfCheckResult?
        package var matchedPitfalls: [AuthorPitfall]
        package var agentTrace: AgentDraftTrace?
        package var retrievedFragments: [RetrievedFragment]
        package var sectionFragmentContexts: [SectionFragmentContext]
        package var iterationSummary: [DeepDraftIteration]?
        package var candidateJudgement: CandidateJudgeResult?
        package var agentSessionSummary: [String]?
        package var styleSamples: StyleSampleProvenance?

        package init(
            articleID: Int?,
            titleSnapshot: String,
            actionTitle: String,
            note: String? = nil,
            before: DraftSnapshot,
            after: DraftSnapshot,
            usedFallback: Bool,
            selfCheck: DraftSelfCheckResult? = nil,
            matchedPitfalls: [AuthorPitfall] = [],
            agentTrace: AgentDraftTrace? = nil,
            retrievedFragments: [RetrievedFragment] = [],
            sectionFragmentContexts: [SectionFragmentContext] = [],
            iterationSummary: [DeepDraftIteration]? = nil,
            candidateJudgement: CandidateJudgeResult? = nil,
            agentSessionSummary: [String]? = nil,
            styleSamples: StyleSampleProvenance? = nil
        ) {
            self.articleID = articleID
            self.titleSnapshot = titleSnapshot
            self.actionTitle = actionTitle
            self.note = note
            self.before = before
            self.after = after
            self.usedFallback = usedFallback
            self.selfCheck = selfCheck
            self.matchedPitfalls = matchedPitfalls
            self.agentTrace = agentTrace
            self.retrievedFragments = retrievedFragments
            self.sectionFragmentContexts = sectionFragmentContexts
            self.iterationSummary = iterationSummary
            self.candidateJudgement = candidateJudgement
            self.agentSessionSummary = agentSessionSummary
            self.styleSamples = styleSamples
        }
    }

    package struct DraftVersionRecord {
        package var articleID: Int?
        package var titleSnapshot: String
        package var action: String
        package var note: String?
        package var before: DraftSnapshot
        package var after: DraftSnapshot

        package init(
            articleID: Int?,
            titleSnapshot: String,
            action: String,
            note: String? = nil,
            before: DraftSnapshot,
            after: DraftSnapshot
        ) {
            self.articleID = articleID
            self.titleSnapshot = titleSnapshot
            self.action = action
            self.note = note
            self.before = before
            self.after = after
        }
    }

    package struct ArticleSave {
        package var articleID: Int?
        package var payload: ArticleSaveRequest
        /// 临时版本靠该快照与首次保存后的文章关联。默认使用去除首尾空白后的文章标题；
        /// 若生成时采用了选题回退标题，调用者可显式传入同一快照。
        package var titleSnapshot: String?

        package init(
            articleID: Int?,
            payload: ArticleSaveRequest,
            titleSnapshot: String? = nil
        ) {
            self.articleID = articleID
            self.payload = payload
            self.titleSnapshot = titleSnapshot
        }
    }

    package struct PolishRequest {
        package var articleID: Int?
        package var titleSnapshot: String
        package var before: DraftSnapshot
        package var context: ContextPackage
        package var mode: PolishMode
        package var style: StyleProfile
        package var polishTemplate: PromptTemplate?
        package var selfCheckTemplate: PromptTemplate?
        package var config: ModelConfig
        package var apiKey: String
        package var styleSamples: StyleSampleProvenance?

        package init(
            articleID: Int?,
            titleSnapshot: String,
            before: DraftSnapshot,
            context: ContextPackage,
            mode: PolishMode,
            style: StyleProfile,
            polishTemplate: PromptTemplate?,
            selfCheckTemplate: PromptTemplate?,
            config: ModelConfig,
            apiKey: String,
            styleSamples: StyleSampleProvenance?
        ) {
            self.articleID = articleID
            self.titleSnapshot = titleSnapshot
            self.before = before
            self.context = context
            self.mode = mode
            self.style = style
            self.polishTemplate = polishTemplate
            self.selfCheckTemplate = selfCheckTemplate
            self.config = config
            self.apiKey = apiKey
            self.styleSamples = styleSamples
        }
    }

    package struct PolishOutcome {
        package var agentRun: AgentRun
        package var version: DraftVersion
        package var pending: PendingDraftReview
        package var generatedTags: [String]?
        package var usedFallback: Bool
        package var error: String
    }

    package struct RewriteSelectionRequest {
        package var articleID: Int?
        package var titleSnapshot: String
        package var context: ContextPackage
        package var selectedText: String
        package var surroundingText: String
        package var mode: RewriteMode
        package var customInstruction: String?
        package var style: StyleProfile
        package var template: PromptTemplate?
        package var config: ModelConfig
        package var apiKey: String
        /// 运行记录里的动作名。定点改写复用同一条纵切片，但记的是「定点改写」。
        package var actionTitle: String
        /// 模型没给 note 时写进运行记录的兜底说明。
        package var fallbackSummary: String

        package init(
            articleID: Int?,
            titleSnapshot: String,
            context: ContextPackage,
            selectedText: String,
            surroundingText: String,
            mode: RewriteMode,
            customInstruction: String?,
            style: StyleProfile,
            template: PromptTemplate?,
            config: ModelConfig,
            apiKey: String,
            actionTitle: String,
            fallbackSummary: String
        ) {
            self.articleID = articleID
            self.titleSnapshot = titleSnapshot
            self.context = context
            self.selectedText = selectedText
            self.surroundingText = surroundingText
            self.mode = mode
            self.customInstruction = customInstruction
            self.style = style
            self.template = template
            self.config = config
            self.apiKey = apiKey
            self.actionTitle = actionTitle
            self.fallbackSummary = fallbackSummary
        }
    }

    package struct RewriteSelectionOutcome {
        package var agentRun: AgentRun
        /// 已校验非空；空替换在落库前就抛错了，不会走到这里。
        package var replacement: String
        package var note: String?
        package var usedFallback: Bool
        package var error: String
    }

    /// 只读分析类工作流的共同输入：不改稿件，只产出参考与运行轨迹。
    package struct AnalysisRequest {
        package var articleID: Int?
        package var titleSnapshot: String
        package var context: ContextPackage
        package var style: StyleProfile
        package var template: PromptTemplate?
        package var config: ModelConfig
        package var apiKey: String

        package init(
            articleID: Int?,
            titleSnapshot: String,
            context: ContextPackage,
            style: StyleProfile,
            template: PromptTemplate?,
            config: ModelConfig,
            apiKey: String
        ) {
            self.articleID = articleID
            self.titleSnapshot = titleSnapshot
            self.context = context
            self.style = style
            self.template = template
            self.config = config
            self.apiKey = apiKey
        }
    }

    package struct AdvisorOutcome {
        package var agentRun: AgentRun
        package var advisorRun: WritingAdvisorRun
        package var usedFallback: Bool
        package var error: String
    }

    package struct ReaderPerspectiveOutcome {
        package var agentRun: AgentRun
        package var result: ReaderPerspectiveResult
        package var usedFallback: Bool
        package var error: String
    }

    private let database: NativeDatabase
    private let pendingReviewMachine: PendingReviewMachine
    private let executor: AIWorkflowExecuting?

    package init(database: NativeDatabase, executor: AIWorkflowExecuting? = nil) {
        self.database = database
        self.pendingReviewMachine = PendingReviewMachine(database: database)
        self.executor = executor
    }

    /// 完整润色纵切片：AI 润色、自检、运行轨迹和 pending 交付由同一深模块编排。
    /// `validateBeforeCommit` 在任何数据库写入前运行；失败时不会产生可投影事实。
    package func polish(
        _ request: PolishRequest,
        onPartialOutput: (@Sendable (String) -> Void)? = nil,
        validateBeforeCommit: () throws -> Void
    ) async throws -> PolishOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let polishRun: AIRun<DraftResult> = await executor.execute(
            NativeWorkflowCatalog.polishDraft(
                context: request.context,
                content: request.before.content,
                mode: request.mode,
                style: request.style,
                template: request.polishTemplate
            ),
            config: request.config,
            apiKey: request.apiKey,
            onPartialOutput: onPartialOutput
        )
        try Task.checkCancellation()

        let after = DraftSnapshot(
            title: polishRun.result.title ?? request.before.title,
            summary: polishRun.result.summary ?? request.before.summary,
            content: polishRun.result.content ?? polishRun.result.raw_output ?? request.before.content
        )
        var selfCheckContext = request.context
        selfCheckContext.title = after.title
        selfCheckContext.summary = after.summary
        selfCheckContext.content_excerpt = after.content
        selfCheckContext.word_count = after.content.count
        let selfCheckRun: AIRun<DraftSelfCheckResult> = await executor.execute(
            NativeWorkflowCatalog.draftSelfCheck(
                context: selfCheckContext,
                style: request.style,
                template: request.selfCheckTemplate
            ),
            config: request.config,
            apiKey: request.apiKey
        )
        try Task.checkCancellation()
        try validateBeforeCommit()

        return try database.withTransaction {
            let step = AgentRunPayloads.singleStep(
                name: request.mode.title,
                success: polishRun.success,
                elapsedMS: polishRun.elapsedMS,
                inputSummary: polishRun.inputSummary,
                outputSummary: polishRun.outputSummary,
                error: polishRun.error
            )
            let agentRun = try database.saveAgentRun(
                runType: request.mode.title,
                articleID: request.articleID,
                titleSnapshot: request.titleSnapshot,
                status: polishRun.success ? "success" : "fallback",
                summary: polishRun.result.summary ?? request.mode.promptInstruction,
                model: request.config.model,
                elapsedMS: polishRun.elapsedMS,
                inputSummary: polishRun.inputSummary,
                outputSummary: polishRun.outputSummary,
                error: polishRun.error,
                steps: [step]
            )
            let delivered = try pendingReviewMachine.deliver(
                articleID: request.articleID,
                titleSnapshot: request.titleSnapshot,
                actionTitle: request.mode.title,
                note: polishRun.success ? request.mode.promptInstruction : polishRun.error,
                before: request.before,
                after: after,
                usedFallback: !polishRun.success,
                selfCheck: selfCheckRun.result,
                matchedPitfalls: request.style.known_pitfalls ?? [],
                agentTrace: nil,
                retrievedFragments: [],
                sectionFragmentContexts: [],
                iterationSummary: nil,
                candidateJudgement: nil,
                styleSamples: request.styleSamples
            )
            return PolishOutcome(
                agentRun: agentRun,
                version: delivered.version,
                pending: delivered.pending,
                generatedTags: polishRun.result.tags,
                usedFallback: !polishRun.success,
                error: polishRun.error
            )
        }
    }

    /// 局部改写纵切片：模型调用与运行轨迹落库由同一深模块编排。
    ///
    /// 空替换在**任何数据库写入之前**就抛 `emptyRewriteReplacement`——一次没产出的改写
    /// 不该在运行记录里留下"成功"的痕迹，调用方也不能拿空串覆盖正文。
    ///
    /// 本切片不碰正文：替换是否落到稿件上、还是先进待确认，由调用方决定。
    /// 「定点改写」（诊断闭环）与「局部改写」（手动选区）共用它，只是 `actionTitle` 不同。
    package func rewriteSelection(
        _ request: RewriteSelectionRequest,
        onPartialOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> RewriteSelectionOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<RewriteResult> = await executor.execute(
            NativeWorkflowCatalog.rewriteSelection(
                context: request.context,
                selectedText: request.selectedText,
                surroundingText: request.surroundingText,
                mode: request.mode,
                customInstruction: request.customInstruction,
                style: request.style,
                template: request.template
            ),
            config: request.config,
            apiKey: request.apiKey,
            onPartialOutput: onPartialOutput
        )
        try Task.checkCancellation()

        let replacement = run.result.replacement ?? run.result.raw_output ?? ""
        guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkflowError.emptyRewriteReplacement
        }

        let agentRun = try database.saveAgentRun(
            runType: request.actionTitle,
            articleID: request.articleID,
            titleSnapshot: request.titleSnapshot,
            status: run.success ? "success" : "fallback",
            summary: run.result.note ?? request.fallbackSummary,
            model: request.config.model,
            elapsedMS: run.elapsedMS,
            inputSummary: run.inputSummary,
            outputSummary: run.outputSummary,
            error: run.error,
            steps: [
                AgentRunPayloads.singleStep(
                    name: request.actionTitle,
                    success: run.success,
                    elapsedMS: run.elapsedMS,
                    inputSummary: run.inputSummary,
                    outputSummary: run.outputSummary,
                    error: run.error
                )
            ]
        )

        let note = run.result.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RewriteSelectionOutcome(
            agentRun: agentRun,
            replacement: replacement,
            note: note?.isEmpty == false ? note : nil,
            usedFallback: !run.success,
            error: run.error
        )
    }

    /// 智能下一步：判断结果与运行轨迹在同一事务里落库，避免出现"有建议无轨迹"。
    package func runWritingAdvisor(_ request: AnalysisRequest) async throws -> AdvisorOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<WritingAdvisorResult> = await executor.execute(
            NativeWorkflowCatalog.writingAdvisor(
                context: request.context,
                style: request.style,
                template: request.template
            ),
            config: request.config,
            apiKey: request.apiKey
        )
        try Task.checkCancellation()

        return try database.withTransaction {
            let agentRun = try recordSingleStepRun(
                actionTitle: "智能判断下一步",
                summary: run.result.next_action ?? run.result.main_problem ?? "完成智能下一步判断。",
                request: request,
                run: run
            )
            let advisorRun = try database.saveWritingAdvisorRun(
                result: run.result,
                context: request.context,
                articleID: request.articleID,
                titleSnapshot: request.titleSnapshot,
                model: request.config.model
            )
            return AdvisorOutcome(
                agentRun: agentRun,
                advisorRun: advisorRun,
                usedFallback: !run.success,
                error: run.error
            )
        }
    }

    /// 读者视角模拟：只产出参考，不写稿件事实，所以除运行轨迹外没有别的持久化。
    package func runReaderPerspective(_ request: AnalysisRequest) async throws -> ReaderPerspectiveOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<ReaderPerspectiveResult> = await executor.execute(
            NativeWorkflowCatalog.readerPerspective(
                context: request.context,
                style: request.style,
                template: request.template
            ),
            config: request.config,
            apiKey: request.apiKey
        )
        try Task.checkCancellation()

        let agentRun = try recordSingleStepRun(
            actionTitle: "读者视角模拟",
            summary: run.result.drop_off_point ?? run.result.note ?? "完成读者视角模拟。",
            request: request,
            run: run
        )
        return ReaderPerspectiveOutcome(
            agentRun: agentRun,
            result: run.result,
            usedFallback: !run.success,
            error: run.error
        )
    }

    /// 单步工作流的运行轨迹写入。调用失败一律记为 `fallback` 并保留错误原文——
    /// 运行记录必须能区分「模型给的」和「本地兜底的」。
    private func recordSingleStepRun<Output>(
        actionTitle: String,
        summary: String,
        request: AnalysisRequest,
        run: AIRun<Output>
    ) throws -> AgentRun {
        try database.saveAgentRun(
            runType: actionTitle,
            articleID: request.articleID,
            titleSnapshot: request.titleSnapshot,
            status: run.success ? "success" : "fallback",
            summary: summary,
            model: request.config.model,
            elapsedMS: run.elapsedMS,
            inputSummary: run.inputSummary,
            outputSummary: run.outputSummary,
            error: run.error,
            steps: [
                AgentRunPayloads.singleStep(
                    name: actionTitle,
                    success: run.success,
                    elapsedMS: run.elapsedMS,
                    inputSummary: run.inputSummary,
                    outputSummary: run.outputSummary,
                    error: run.error
                )
            ]
        )
    }

    /// 唯一执行入口。每个 outcome 都表示对应的持久化语义已经成功完成。
    package func execute(_ command: Command) throws -> Outcome {
        switch command {
        case let .deliverPending(delivery):
            return try database.withTransaction {
                try deliverPending(delivery)
            }
        case let .confirmPending(review):
            return try database.withTransaction {
                let version = try pendingReviewMachine.confirm(versionID: review.draftVersionID)
                return .pendingConfirmed(version)
            }
        case let .discardPending(review, current):
            return try database.withTransaction {
                var preserved: DraftVersion?
                if let current, current != review.after, current != review.before {
                    preserved = try database.saveDraftVersion(
                        articleID: review.articleID,
                        titleSnapshot: current.title,
                        action: "放弃候选前的手工编辑",
                        note: "候选已放弃；该版本保留作者在预览上的继续修改",
                        before: review.after,
                        after: current
                    )
                }
                try pendingReviewMachine.discard(versionID: review.draftVersionID)
                return .pendingDiscarded(
                    versionID: review.draftVersionID,
                    restore: review.before,
                    preservedVersion: preserved
                )
            }
        case let .cleanupPending(versionID):
            return try database.withTransaction {
                let wasPending = try database.draftVersion(id: versionID)?.review_status == "pending"
                try pendingReviewMachine.cleanupOrphan(versionID: versionID)
                return .pendingCleaned(versionID: versionID, didRemove: wasPending)
            }
        case let .recordDraftVersion(record):
            return try database.withTransaction {
                let version = try database.saveDraftVersion(
                    articleID: record.articleID,
                    titleSnapshot: record.titleSnapshot,
                    action: record.action,
                    note: record.note,
                    before: record.before,
                    after: record.after
                )
                return .draftVersionRecorded(version)
            }
        case let .saveArticle(save):
            return try saveArticle(save)
        }
    }

    private func deliverPending(_ delivery: PendingDelivery) throws -> Outcome {
        let delivered = try pendingReviewMachine.deliver(
            articleID: delivery.articleID,
            titleSnapshot: delivery.titleSnapshot,
            actionTitle: delivery.actionTitle,
            note: delivery.note,
            before: delivery.before,
            after: delivery.after,
            usedFallback: delivery.usedFallback,
            selfCheck: delivery.selfCheck,
            matchedPitfalls: delivery.matchedPitfalls,
            agentTrace: delivery.agentTrace,
            retrievedFragments: delivery.retrievedFragments,
            sectionFragmentContexts: delivery.sectionFragmentContexts,
            iterationSummary: delivery.iterationSummary,
            candidateJudgement: delivery.candidateJudgement,
            styleSamples: delivery.styleSamples
        )
        var review = delivered.pending
        review.agentSessionSummary = delivery.agentSessionSummary
        return .pendingDelivered(delivered.version, review)
    }

    private func saveArticle(_ save: ArticleSave) throws -> Outcome {
        try database.withTransaction {
            let previous = try save.articleID.map(database.getArticle)
            let after = DraftSnapshot(
                title: save.payload.title,
                summary: save.payload.summary,
                content: save.payload.content
            )
            let titleSnapshot = normalizedTitleSnapshot(save.titleSnapshot, fallback: save.payload.title)

            let article = try database.saveArticle(id: save.articleID, payload: save.payload)
            try database.attachDraftVersionsToArticle(
                articleID: article.id,
                titleSnapshot: titleSnapshot
            )

            var overwriteVersion: DraftVersion?
            if let previous {
                let before = DraftSnapshot(
                    title: previous.title ?? "",
                    summary: previous.summary ?? "",
                    content: previous.content ?? ""
                )
                if before != after {
                    overwriteVersion = try database.saveDraftVersion(
                        articleID: article.id,
                        titleSnapshot: titleSnapshot,
                        action: DraftVersionAction.manualSave,
                        note: "已覆盖旧定稿，「恢复前」可回到本次保存之前",
                        before: before,
                        after: after
                    )
                }
            }

            return .articleSaved(article, overwriteVersion: overwriteVersion)
        }
    }

    private func normalizedTitleSnapshot(_ supplied: String?, fallback: String) -> String {
        let supplied = supplied?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !supplied.isEmpty {
            return supplied
        }
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "未命名文章" : fallback
    }
}
