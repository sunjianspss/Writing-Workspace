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

        package var errorDescription: String? {
            "WritingWorkflow 未配置 AI executor"
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
