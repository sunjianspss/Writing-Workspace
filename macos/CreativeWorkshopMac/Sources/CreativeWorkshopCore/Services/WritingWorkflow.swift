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
        /// 投影失败后连回收也失败：数据库里留下了一个界面看不见、作者也无法
        /// 确认或放弃的待复核版本。两个错误都要报——投影错误说明发生了什么，
        /// 版本号说明库里还剩什么。
        case pendingCleanupFailed(versionID: Int, projection: Error, cleanup: Error)

        package var errorDescription: String? {
            switch self {
            case .missingExecutor:
                "WritingWorkflow 未配置 AI executor"
            case .emptyRewriteReplacement:
                "模型没有返回可替换文本"
            case let .pendingCleanupFailed(versionID, projection, cleanup):
                """
                \(projection.localizedDescription)；\
                回收候选也失败，数据库中遗留待复核版本 #\(versionID)（\(cleanup.localizedDescription)）
                """
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

    /// 写作诊断：在只读分析之上多两样东西——跨轮对比用的上一版诊断，
    /// 以及本次实际被诊断文本的快照。
    package struct ReviewRequest {
        package var analysis: AnalysisRequest
        package var previousReview: WritingReview?
        /// 防空转（18.3.2）的比对基准。必须是**本次送去诊断的那份文本**，
        /// 存错了下一轮要么永远重复提示，要么永远不提示。
        package var reviewedSnapshot: String

        package init(
            analysis: AnalysisRequest,
            previousReview: WritingReview?,
            reviewedSnapshot: String
        ) {
            self.analysis = analysis
            self.previousReview = previousReview
            self.reviewedSnapshot = reviewedSnapshot
        }
    }

    package struct ReviewOutcome {
        package var agentRun: AgentRun
        package var review: WritingReview
        package var usedFallback: Bool
        package var error: String
    }

    /// 生成类工作流的共同产出：一份候选稿件加它的运行轨迹。
    ///
    /// 这里**不做交付**。候选是否进入待复核，取决于调用方能否证明会话没有过期
    /// （checkpoint 校验），那是投影层的判断，不属于本切片。
    package struct GeneratedDraftOutcome {
        package var agentRun: AgentRun
        package var result: DraftResult
        package var usedFallback: Bool
        package var error: String
    }

    /// 深度成稿：诊断→修订→复评的串联本身归 `DeepDraftCoordinator`（纯编排，不碰库）。
    /// 本切片负责把 executor 交给它，并把多步运行轨迹落库。
    package struct DeepRevisionRequest {
        package var articleID: Int?
        package var titleSnapshot: String
        package var input: DeepDraftInput

        package init(articleID: Int?, titleSnapshot: String, input: DeepDraftInput) {
            self.articleID = articleID
            self.titleSnapshot = titleSnapshot
            self.input = input
        }
    }

    package struct DeepRevisionOutcome {
        package var agentRun: AgentRun
        package var output: DeepDraftOutput
        package var usedFallback: Bool
        package var error: String
    }

    package struct ReviseFromReviewRequest {
        package var analysis: AnalysisRequest
        package var content: String
        package var review: WritingReview

        package init(analysis: AnalysisRequest, content: String, review: WritingReview) {
            self.analysis = analysis
            self.content = content
            self.review = review
        }
    }

    /// 生成类动作交付待复核前的自检输入。
    ///
    /// `polish` 在切片内部做自检，而 Store 侧的 `finalizeGeneratedDraft` 曾在自己那边
    /// 做——同一件事两种做法。这个请求让后者也把自检交回工作流。
    package struct SelfCheckRequest {
        package var context: ContextPackage
        package var style: StyleProfile
        package var template: PromptTemplate?
        package var config: ModelConfig
        package var apiKey: String

        package init(
            context: ContextPackage,
            style: StyleProfile,
            template: PromptTemplate?,
            config: ModelConfig,
            apiKey: String
        ) {
            self.context = context
            self.style = style
            self.template = template
            self.config = config
            self.apiKey = apiKey
        }
    }

    package struct TopicsRequest {
        package var analysis: AnalysisRequest
        /// 运行记录里的动作名：手动想法是「生成选题」，素材入口是「从素材生成选题」。
        package var actionTitle: String
        /// 去重基准：已有选题。
        package var existingTopics: [Topic]
        /// 素材入口才有：生成成功后把这条素材标记为已用。
        package var markIdeaUsedID: Int?

        package init(
            analysis: AnalysisRequest,
            actionTitle: String,
            existingTopics: [Topic],
            markIdeaUsedID: Int? = nil
        ) {
            self.analysis = analysis
            self.actionTitle = actionTitle
            self.existingTopics = existingTopics
            self.markIdeaUsedID = markIdeaUsedID
        }
    }

    package struct TopicsOutcome {
        package var agentRun: AgentRun
        package var created: [Topic]
        /// 被判定为重复而没有入库的候选。不是错误，只是要让作者知情（18.5.2）。
        package var duplicates: [TopicPayload]
        package var usedFallback: Bool
        package var error: String
    }

    /// 大纲与大纲成稿共用：两者的输入完全相同——一条选题加一份分析上下文。
    package struct TopicDraftingRequest {
        package var analysis: AnalysisRequest
        package var topic: TopicPayload

        package init(analysis: AnalysisRequest, topic: TopicPayload) {
            self.analysis = analysis
            self.topic = topic
        }
    }

    package struct OutlineOutcome {
        package var agentRun: AgentRun
        package var result: OutlineResult
        package var usedFallback: Bool
        package var error: String
    }

    package struct PublishAssetsOutcome {
        package var agentRun: AgentRun
        /// 已落库的物料记录。摘要与标签直接取自它，调用方不需要另一份原始结果。
        package var assets: PublishAssets
        package var usedFallback: Bool
        package var error: String
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

    /// 深度成稿：把 executor 交给 `DeepDraftCoordinator` 跑完三段串联，再把整条
    /// 多步轨迹落成一条运行记录。
    ///
    /// 轨迹必须保留协调器给出的**每一步**——深度成稿失败时，作者要能看出是诊断、
    /// 修订还是复评那一段出的问题；压成一步就没法复盘了。
    ///
    /// 和 `reviseFromReview` 一样不做交付，理由相同（会话可能已过期）。
    package func deepRevise(_ request: DeepRevisionRequest) async throws -> DeepRevisionOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let output = try await DeepDraftCoordinator(aiClient: executor).run(input: request.input)
        try Task.checkCancellation()

        let agentRun = try database.saveAgentRun(
            runType: "深度成稿",
            articleID: request.articleID,
            titleSnapshot: request.titleSnapshot,
            status: output.success ? "success" : "fallback",
            summary: output.summaryText,
            model: request.input.config.model,
            elapsedMS: output.elapsed_ms,
            inputSummary: "从当前正文自动执行诊断→修订→复评。",
            outputSummary: output.summaryText,
            error: output.error,
            steps: output.steps
        )
        return DeepRevisionOutcome(
            agentRun: agentRun,
            output: output,
            usedFallback: !output.success,
            error: output.error
        )
    }

    /// 按诊断改全文：产出候选稿件与运行轨迹，**不落交付**。
    ///
    /// 交付留给调用方，是因为它必须先证明会话没有过期——生成期间作者可能已经
    /// 改了正文。把交付并进来就等于让本切片替投影层做那个判断。
    /// 模型没给摘要时退回诊断自己的摘要，运行记录不留空。
    package func reviseFromReview(
        _ request: ReviseFromReviewRequest
    ) async throws -> GeneratedDraftOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<DraftResult> = await executor.execute(
            NativeWorkflowCatalog.improveDraftFromReview(
                context: request.analysis.context,
                content: request.content,
                review: request.review,
                style: request.analysis.style
            ),
            config: request.analysis.config,
            apiKey: request.analysis.apiKey
        )
        try Task.checkCancellation()

        let agentRun = try recordSingleStepRun(
            actionTitle: "按诊断改全文",
            summary: run.result.summary ?? request.review.summary,
            request: request.analysis,
            run: run
        )
        return GeneratedDraftOutcome(
            agentRun: agentRun,
            result: run.result,
            usedFallback: !run.success,
            error: run.error
        )
    }

    /// 写作诊断：诊断记录与运行轨迹在同一事务里落库。
    ///
    /// 诊断连同 `reviewedSnapshot` 一起写入——这条快照是防空转的唯一依据，
    /// 和诊断分开写就可能出现"有诊断无基准"的记录。
    package func runWritingReview(_ request: ReviewRequest) async throws -> ReviewOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<WritingReviewResult> = await executor.execute(
            NativeWorkflowCatalog.writingReview(
                context: request.analysis.context,
                style: request.analysis.style,
                previousReview: request.previousReview,
                template: request.analysis.template
            ),
            config: request.analysis.config,
            apiKey: request.analysis.apiKey
        )
        try Task.checkCancellation()

        return try database.withTransaction {
            let agentRun = try recordSingleStepRun(
                actionTitle: "写作诊断",
                summary: run.result.summary ?? "完成写作诊断。",
                request: request.analysis,
                run: run
            )
            let review = try database.saveWritingReview(
                result: run.result,
                articleID: request.analysis.articleID,
                titleSnapshot: request.analysis.titleSnapshot,
                model: request.analysis.config.model,
                reviewedSnapshot: request.reviewedSnapshot
            )
            return ReviewOutcome(
                agentRun: agentRun,
                review: review,
                usedFallback: !run.success,
                error: run.error
            )
        }
    }

    /// 生成选题：去重、入库、标记素材已用、写运行轨迹，全部在**同一个事务**里。
    ///
    /// 迁出前这条路径是「先 `createTopics`、再 `markIdeaUsed`、最后 `recordAgentRun`」，
    /// 三次独立写入。中途失败会留下没有轨迹的选题，或者已标记已用却没生成出选题的素材。
    /// 顺序和其他切片相反（先写业务事实、后写轨迹），所以更需要事务把它们绑在一起。
    ///
    /// 被判定重复的候选不入库，但要随 outcome 返回——作者需要知道过滤掉了什么。
    package func generateTopics(_ request: TopicsRequest) async throws -> TopicsOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<GeneratedTopicsDocument> = await executor.execute(
            NativeWorkflowCatalog.topics(
                context: request.analysis.context,
                style: request.analysis.style,
                template: request.analysis.template
            ),
            config: request.analysis.config,
            apiKey: request.analysis.apiKey
        )
        try Task.checkCancellation()

        let (uniqueTopics, duplicateTopics) = TopicDeduplicator.filterDuplicates(
            run.result.topics,
            against: request.existingTopics
        )

        return try database.withTransaction {
            let created = try database.createTopics(uniqueTopics)
            if let ideaID = request.markIdeaUsedID {
                _ = try database.markIdeaUsed(id: ideaID, used: true)
            }
            let agentRun = try recordSingleStepRun(
                actionTitle: request.actionTitle,
                summary: "生成 \(created.count) 个选题，过滤 \(duplicateTopics.count) 个重复选题。",
                request: request.analysis,
                run: run,
                stepName: "生成选题"
            )
            return TopicsOutcome(
                agentRun: agentRun,
                created: created,
                duplicates: duplicateTopics,
                usedFallback: !run.success,
                error: run.error
            )
        }
    }

    /// 大纲成稿：按当前大纲产出正文候选与运行轨迹，**不做交付**。
    ///
    /// 与 `reviseFromReview` 同样把交付留给调用方（会话可能已过期）。
    ///
    /// 注意它没有 `validateBeforeCommit`——`generateOutline` 有。这个不对称是迁出前
    /// 就存在的：大纲会直接覆盖编辑器内容，所以过期就整次作废；而成稿的产物要走
    /// 待复核，过期会在 `commitPending` 的投影处被挡下并回收 pending 版本。此处保持
    /// 原行为，没有顺手加校验——那是行为变更，该单独论证。
    package func draftFromOutline(
        _ request: TopicDraftingRequest,
        onPartialOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> GeneratedDraftOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<DraftResult> = await executor.execute(
            NativeWorkflowCatalog.draft(
                topic: request.topic,
                context: request.analysis.context,
                style: request.analysis.style,
                template: request.analysis.template
            ),
            config: request.analysis.config,
            apiKey: request.analysis.apiKey,
            onPartialOutput: onPartialOutput
        )
        try Task.checkCancellation()

        let agentRun = try recordSingleStepRun(
            actionTitle: "大纲成稿",
            summary: run.result.summary ?? "根据当前大纲生成正文。",
            request: request.analysis,
            run: run
        )
        return GeneratedDraftOutcome(
            agentRun: agentRun,
            result: run.result,
            usedFallback: !run.success,
            error: run.error
        )
    }

    /// 生成大纲：产出大纲与运行轨迹。
    ///
    /// `validateBeforeCommit` 在**任何数据库写入之前**运行。生成期间作者可能已经
    /// 改了稿件，这时整次生成必须作废——留下一条运行记录会让轨迹里出现一次
    /// 谁也没用上的大纲。语义与 `polish` 的同名参数一致。
    package func generateOutline(
        _ request: TopicDraftingRequest,
        onPartialOutput: (@Sendable (String) -> Void)? = nil,
        validateBeforeCommit: () throws -> Void
    ) async throws -> OutlineOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<OutlineResult> = await executor.execute(
            NativeWorkflowCatalog.outline(
                topic: request.topic,
                context: request.analysis.context,
                style: request.analysis.style,
                template: request.analysis.template
            ),
            config: request.analysis.config,
            apiKey: request.analysis.apiKey,
            onPartialOutput: onPartialOutput
        )
        try Task.checkCancellation()
        try validateBeforeCommit()

        let agentRun = try recordSingleStepRun(
            actionTitle: "生成大纲",
            summary: run.result.title ?? "完成文章大纲。",
            request: request.analysis,
            run: run
        )
        return OutlineOutcome(
            agentRun: agentRun,
            result: run.result,
            usedFallback: !run.success,
            error: run.error
        )
    }

    /// 发布物料：物料记录与运行轨迹在同一事务里落库。
    ///
    /// 物料是派生文案，不是稿件事实——本切片不改标题、摘要或正文。
    /// 作者摘要为空时要不要拿生成的摘要补上，是投影层的决定。
    package func generatePublishAssets(_ request: AnalysisRequest) async throws -> PublishAssetsOutcome {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<PublishAssetsResult> = await executor.execute(
            NativeWorkflowCatalog.publishAssets(
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
                actionTitle: "生成发布物料",
                summary: run.result.summary ?? run.result.cover_text ?? "完成发布物料生成。",
                request: request,
                run: run
            )
            let assets = try database.savePublishAssets(
                result: run.result,
                articleID: request.articleID,
                titleSnapshot: request.titleSnapshot,
                model: request.config.model
            )
            return PublishAssetsOutcome(
                agentRun: agentRun,
                assets: assets,
                usedFallback: !run.success,
                error: run.error
            )
        }
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
    /// `stepName` 默认与动作名一致；只有素材入口例外——动作名是「从素材生成选题」，
    /// 而步骤名仍是「生成选题」。
    private func recordSingleStepRun<Output>(
        actionTitle: String,
        summary: String,
        request: AnalysisRequest,
        run: AIRun<Output>,
        stepName: String? = nil
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
                    name: stepName ?? actionTitle,
                    success: run.success,
                    elapsedMS: run.elapsedMS,
                    inputSummary: run.inputSummary,
                    outputSummary: run.outputSummary,
                    error: run.error
                )
            ]
        )
    }

    /// 自检并交付待复核：模型自检、pending 落库两步归同一层。
    ///
    /// 自检不阻塞交付——它只是给编辑器的旁注（18.3.5）。但它必须**在** pending 落库
    /// 之前跑完，因为自检结果要随 pending 一起写进去；分两步写就会出现有 pending
    /// 无自检的记录。
    package func selfCheckAndDeliver(
        selfCheck: SelfCheckRequest,
        delivery: PendingDelivery
    ) async throws -> (version: DraftVersion, pending: PendingDraftReview, selfCheck: DraftSelfCheckResult?) {
        guard let executor else { throw WorkflowError.missingExecutor }

        let run: AIRun<DraftSelfCheckResult> = await executor.execute(
            NativeWorkflowCatalog.draftSelfCheck(
                context: selfCheck.context,
                style: selfCheck.style,
                template: selfCheck.template
            ),
            config: selfCheck.config,
            apiKey: selfCheck.apiKey
        )
        try Task.checkCancellation()

        var delivery = delivery
        delivery.selfCheck = run.result

        guard case let .pendingDelivered(version, pending) = try execute(.deliverPending(delivery)) else {
            preconditionFailure("WritingWorkflow returned an invalid pending outcome")
        }
        return (version, pending, run.result)
    }

    /// 把交付好的待复核版本投影出去；投影失败则回收它。
    ///
    /// 交付已经在数据库里留下了一个 pending 版本，但只有投影成功它才算真的到了作者面前。
    /// 投影失败时那一行必须回收，否则库里会留下一个界面上看不见、也无法确认或放弃的
    /// 待复核版本。补偿必须和它要回收的那次写入在同一层——此前 `polishDraft` 与
    /// `finalizeGeneratedDraft` 各自抄了一遍这段 do/catch，是两份会各自漂移的协议。
    ///
    /// `stage` 由调用方提供，因为投影目标（`WritingSession`）不属于本层。
    ///
    /// 回收成功时抛出的仍是原始的投影错误——那才是作者需要处理的那个。只有回收
    /// 本身也失败时才换成 `pendingCleanupFailed`：这时库里留下了一个界面看不见、
    /// 也无法确认或放弃的版本，瞒着作者比多一条错误信息更糟。
    package func commitPending(
        version: DraftVersion,
        pending: PendingDraftReview,
        stage: (PendingDraftReview) throws -> Void
    ) throws {
        do {
            try stage(pending)
        } catch {
            do {
                _ = try execute(.cleanupPending(versionID: version.id))
            } catch let cleanupError {
                throw WorkflowError.pendingCleanupFailed(
                    versionID: version.id,
                    projection: error,
                    cleanup: cleanupError
                )
            }
            throw error
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
