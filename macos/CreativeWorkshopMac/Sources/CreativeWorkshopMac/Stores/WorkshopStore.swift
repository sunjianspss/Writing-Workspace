import AppKit
import Foundation
import UniformTypeIdentifiers
import CreativeWorkshopCore

@MainActor
final class WorkshopStore: ObservableObject {
    @Published var runtimeStatus: RuntimeStatus?
    @Published var articles: [Article] = []
    @Published var topics: [Topic] = []
    @Published var stats: OverviewStats?
    @Published var selectedArticleID: Article.ID?
    @Published var selectedTopicID: Topic.ID?
    @Published var articleStatusFilter: String = "全部"
    @Published var articleStatus: String = "草稿"
    @Published var title: String = ""
    @Published var summary: String = ""
    @Published var content: String = ""
    @Published var contentSelection: NSRange = NSRange(location: 0, length: 0)
    @Published var outline: String = ""
    @Published var ideaInput: String = ""
    @Published var writingDirection: String = ""
    @Published var materials: String = ""
    @Published var statusText: String = "准备就绪"
    @Published var isLoading: Bool = false
    @Published var modelBaseURLText: String = "https://api.deepseek.com"
    @Published var modelName: String = "deepseek-v4-pro"
    @Published var modelWorkflowOverridesText: String = "{}"
    @Published var apiKeyInput: String = ""
    @Published var databasePathText: String = ""
    @Published var latestReview: WritingReview?
    @Published var writingReviews: [WritingReview] = []
    @Published var ideas: [Idea] = []
    @Published var selectedIdeaID: Idea.ID?
    @Published var materialTitle: String = ""
    @Published var materialContent: String = ""
    @Published var materialType: String = "灵感"
    @Published var materialTagsText: String = ""
    @Published var materialSearchText: String = ""
    @Published var materialTypeFilter: String = "全部"
    @Published var latestPublishAssets: PublishAssets?
    @Published var publishAssetsHistory: [PublishAssets] = []
    @Published var latestPrePublishAudit: PrePublishAudit?
    /// 最近一次 `resolveStyle()` 实际注入的 few-shot 样本出处（24.9-P1）。不是 @Published：
    /// 界面只在交付待复核时读它一次，随 `PendingDraftReview` 一起进卡片。
    var lastStyleSampleProvenance: StyleSampleProvenance?
    @Published var editRecordStats: EditRecordStats?
    @Published var editRecordMonthlySummary: String = ""
    @Published var latestAdvisorRun: WritingAdvisorRun?
    @Published var advisorRuns: [WritingAdvisorRun] = []
    @Published var agentRuns: [AgentRun] = []
    /// 23.5 半自动调度："按计划执行"正在进行时的逐步进度；nil 表示当前没有计划在执行。
    @Published var advisorPlanProgress: AdvisorPlanProgress?
    /// 23.6.6 实验室开关：默认关闭，入口在关闭时直接拒绝（UI 在任务 15）。
    @Published var agentLabEnabled: Bool = false
    @Published var agentCallBudget: Int = 12
    /// 23.6.5 ask_author 暂停结果：非 nil 表示当前会话在等待作者补充信息。
    @Published var agentSessionAskAuthor: AgentAskAuthorPrompt?
    @Published var draftVersions: [DraftVersion] = []
    @Published var promptTemplates: [PromptTemplate] = []
    @Published var selectedPromptTemplateID: PromptTemplate.ID?
    @Published var promptTemplateName: String = ""
    @Published var promptTemplateSystemPrompt: String = ""
    @Published var promptTemplateUserTemplate: String = ""
    @Published var styleProfiles: [StyleProfile] = []
    @Published var selectedStyleProfileID: StyleProfile.ID?
    @Published var styleName: String = ""
    @Published var styleLanguage: String = ""
    @Published var styleTone: String = ""
    @Published var styleStructure: String = ""
    @Published var styleFavorites: String = ""
    @Published var styleForbidden: String = ""
    @Published var styleSamplesText: String = ""
    @Published var styleTitleLike: String = ""
    @Published var styleTitleDislike: String = ""
    @Published var styleGenre: String = ""
    @Published var styleGenreFocus: String = ""

    // MARK: - 18.3.2 诊断记忆与防空转
    /// 内容自上次诊断以来未变化时，先提示用户是否仍要重新诊断，而不是直接调用模型。
    @Published var showUnchangedReviewPrompt: Bool = false

    // MARK: - 18.3.1 诊断-改写闭环
    /// 由诊断 issue 触发的定点改写候选，需人工确认才写入正文。
    @Published var pendingIssueRewrite: PendingIssueRewrite?

    // MARK: - 18.3.5 / 18.4.1 生成后自检 + 待复核工作流
    /// 一键初稿/大纲成稿/全文润色产出的待复核候选：确认前正文已经预览显示，但版本仍标记为 pending。
    @Published var pendingDraftReview: PendingDraftReview?
    /// 最近一次生成后自检的结果，用于编辑器里的"建议复查"高亮/旁注。
    @Published var latestSelfCheck: DraftSelfCheckResult?

    // MARK: - 18.3.3 作者雷区归纳
    /// 从历史诊断归纳出的候选雷区，需人工确认才写入 `StyleProfile.known_pitfalls`。
    @Published var pitfallCandidates: [PitfallCandidate] = []
    /// 从发布前人工编辑记录归纳出的候选偏好，需人工确认才写入 `StyleProfile.learned_preferences`。
    @Published var editPreferenceCandidates: [EditPreferenceCandidate] = []

    // MARK: - 18.4.3 读者视角模拟
    @Published var latestReaderPerspective: ReaderPerspectiveResult?

    // MARK: - 18.5.2 选题去重
    /// 最近一次生成选题时被判定为重复而过滤掉的候选，供作者知情（不是错误，只是提示）。
    @Published var lastFilteredDuplicateTopics: [TopicPayload] = []

    // MARK: - 19.3.1 自动保存与草稿恢复
    @Published var showAutosaveRestorePrompt: Bool = false

    // MARK: - 24.1 发布流程引导
    /// 文章未经"已发布"直接归档时的确认（跳过发布会缺失终审与编辑量记录）。
    @Published var showArchiveWithoutPublishPrompt: Bool = false

    let database: NativeDatabase
    let aiClient: AIWorkflowExecuting
    private let contextBuilder: WritingContextBuilder
    private let keychain: KeychainCredentialStore
    /// 22.3.4：候选评委呈现顺序的随机源，可注入固定种子以便测试复现打乱结果。
    var candidateShuffleRNG: AnyRandomNumberGenerator
    var draftTags: [String] = []
    var isApplyingAutosaveSnapshot = false
    let autosave = AutosaveController()
    private var currentOperationTask: Task<Void, Error>?
    private var currentOperationIsCancellable = false
    private var currentOperationName: String?
    /// 23.5：计划执行等待作者确认/放弃待复核产物时挂起的续体；confirm/discard 或会话切换时唯一消费一次。
    var pendingDraftReviewContinuation: CheckedContinuation<PendingDraftReviewResolution, Never>?

    convenience init() {
        do {
            try self.init(database: NativeDatabase())
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    init(
        database: NativeDatabase,
        aiClient: AIWorkflowExecuting? = nil,
        contextBuilder: WritingContextBuilder = WritingContextBuilder(),
        keychain: KeychainCredentialStore = KeychainCredentialStore(),
        candidateShuffleRNG: RandomNumberGenerator = SystemRandomNumberGenerator()
    ) throws {
        self.database = database
        self.aiClient = aiClient ?? NativeAIClient(recorder: database)
        self.contextBuilder = contextBuilder
        self.keychain = keychain
        self.candidateShuffleRNG = AnyRandomNumberGenerator(candidateShuffleRNG)
        self.databasePathText = database.databaseURL.path
        self.apiKeyInput = keychain.readAPIKey()
        let config = try database.modelConfig()
        self.modelBaseURLText = config.baseURL
        self.modelName = config.model
        self.modelWorkflowOverridesText = Self.prettyJSON(config.workflowOverrides)
        self.runtimeStatus = database.runtimeStatus(model: config.model)
        self.showAutosaveRestorePrompt = autosave.load() != nil
        self.agentLabEnabled = (try? database.agentLabEnabled()) ?? false
        self.agentCallBudget = (try? database.agentCallBudget()) ?? 12
    }

    var selectedArticle: Article? {
        articles.first { $0.id == selectedArticleID }
    }

    var filteredArticles: [Article] {
        let filter = articleStatusFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty, filter != "全部" else {
            return articles
        }
        return articles.filter { ($0.status ?? "草稿") == filter }
    }

    var selectedTopic: Topic? {
        topics.first { $0.id == selectedTopicID }
    }

    var selectedIdea: Idea? {
        ideas.first { $0.id == selectedIdeaID }
    }

    var selectedPromptTemplate: PromptTemplate? {
        promptTemplates.first { $0.id == selectedPromptTemplateID }
    }

    var selectedStyleProfile: StyleProfile? {
        styleProfiles.first { $0.id == selectedStyleProfileID }
    }

    var canRunWritingCoach: Bool {
        !isLoading && !reviewableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCancelCurrentOperation: Bool {
        isLoading && currentOperationIsCancellable && currentOperationTask != nil
    }

    var canSaveMaterial: Bool {
        !materialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canGeneratePublishAssets: Bool {
        !isLoading && ![title, summary, content].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canPolishDraft: Bool {
        !isLoading && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canImproveFromReview: Bool {
        !isLoading
            && latestReview != nil
            && pendingDraftReview == nil
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRunAdvisor: Bool {
        !isLoading && !reviewableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRewriteSelection: Bool {
        guard !isLoading, let selectedText = selectedContentText(in: contentSelection) else {
            return false
        }
        return !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedContentCharacterCount: Int {
        selectedContentText(in: contentSelection)?.count ?? 0
    }

    /// 文学写作能力雷达（18.4.2）：基于历史诊断统计各维度出现频次的趋势。
    var dimensionTrends: [DimensionTrend] {
        WritingDimensionAnalytics.trends(from: writingReviews)
    }

    var canRunReaderPerspective: Bool {
        !isLoading && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshAll() async {
        await run("刷新") {
            self.runtimeStatus = self.database.runtimeStatus(model: self.modelName)
            self.articles = try self.database.listArticles()
            self.topics = try self.database.listTopics()
            self.ideas = try self.database.listIdeas()
            self.styleProfiles = try self.database.listStyleProfiles()
            self.stats = try self.database.overviewStats()
            self.writingReviews = try self.database.listWritingReviews()
            self.publishAssetsHistory = try self.database.listPublishAssets()
            self.latestPrePublishAudit = try self.database.listPrePublishAudits().first
            self.applyPublishingMetrics(try PublishingMetricsRecorder(database: self.database).snapshot())
            self.advisorRuns = try self.database.listWritingAdvisorRuns()
            self.agentRuns = try self.database.listAgentRuns()
            self.draftVersions = try self.database.listDraftVersions()
            self.promptTemplates = try self.database.listPromptTemplates()
            if self.selectedPromptTemplateID == nil {
                self.editPromptTemplate(self.promptTemplates.first)
            }
            if self.selectedStyleProfileID == nil {
                self.editStyleProfile(self.styleProfiles.first)
            }

            if self.selectedTopicID == nil {
                self.selectedTopicID = self.topics.first?.id
            }
            if let articleID = self.selectedArticleID {
                self.latestReview = try self.database.listWritingReviews(articleID: articleID, limit: 1).first
                self.latestPublishAssets = try self.database.listPublishAssets(articleID: articleID, limit: 1).first
                self.latestPrePublishAudit = try self.database.listPrePublishAudits(articleID: articleID, limit: 1).first
                self.latestAdvisorRun = try self.database.listWritingAdvisorRuns(articleID: articleID, limit: 1).first
                self.agentRuns = try self.database.listAgentRuns(articleID: articleID, limit: 8)
                self.draftVersions = try self.database.listDraftVersions(articleID: articleID, limit: 8)
            } else if self.latestReview == nil {
                self.latestReview = self.writingReviews.first
                self.latestPublishAssets = self.publishAssetsHistory.first
                self.latestAdvisorRun = self.advisorRuns.first
                self.agentRuns = try self.database.listAgentRuns(limit: 8)
            }
            if self.writingDirection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let direction = self.stats?.top_direction,
               !direction.isEmpty {
                self.writingDirection = direction
            }
        }
    }

    func saveModelSettings() async {
        await run("保存模型设置") {
            let overrides = try self.parseWorkflowOverrides()
            try self.database.saveModelConfig(
                ModelConfig(
                    baseURL: self.normalizedBaseURL,
                    model: self.normalizedModel,
                    workflowOverrides: overrides
                )
            )
            self.modelWorkflowOverridesText = Self.prettyJSON(overrides)
            try self.keychain.saveAPIKey(self.apiKeyInput)
            self.runtimeStatus = self.database.runtimeStatus(model: self.normalizedModel)
            self.statusText = "模型设置已保存"
        }
    }

    /// 23.6.6 实验室开关：本地写状态即时生效，并持久化到设置表，不走 run() 包装（无需 loading/取消语义）。
    func setAgentLabEnabled(_ enabled: Bool) {
        agentLabEnabled = enabled
        try? database.saveAgentLabEnabled(enabled)
    }

    func clearAPIKey() async {
        await run("清除 API Key") {
            try self.keychain.deleteAPIKey()
            self.apiKeyInput = ""
            self.runtimeStatus = self.database.runtimeStatus(model: self.normalizedModel)
            self.statusText = "API Key 已清除"
        }
    }

    func newDraft() {
        selectedArticleID = nil
        selectedTopicID = nil
        articleStatus = "草稿"
        title = ""
        summary = ""
        content = ""
        contentSelection = NSRange(location: 0, length: 0)
        outline = ""
        ideaInput = ""
        materials = ""
        draftTags = []
        latestReview = nil
        latestPublishAssets = nil
        latestPrePublishAudit = nil
        latestAdvisorRun = nil
        agentRuns = []
        draftVersions = []
        resetTransientReviewState()
        statusText = "已新建写作会话"
    }

    func openArticle(_ article: Article?) {
        selectedArticleID = article?.id
        articleStatus = article?.status ?? "草稿"
        title = article?.title ?? ""
        summary = article?.summary ?? ""
        content = article?.content ?? ""
        contentSelection = NSRange(location: 0, length: 0)
        draftTags = article?.tags ?? []
        if let genre = article?.genre?.trimmingCharacters(in: .whitespacesAndNewlines), !genre.isEmpty {
            writingDirection = genre
        }
        if let id = article?.id {
            latestReview = try? database.listWritingReviews(articleID: id, limit: 1).first
            latestPublishAssets = try? database.listPublishAssets(articleID: id, limit: 1).first
            latestPrePublishAudit = try? database.listPrePublishAudits(articleID: id, limit: 1).first
            latestAdvisorRun = try? database.listWritingAdvisorRuns(articleID: id, limit: 1).first
            agentRuns = (try? database.listAgentRuns(articleID: id, limit: 8)) ?? []
            draftVersions = (try? database.listDraftVersions(articleID: id, limit: 8)) ?? []
        } else {
            latestReview = nil
            latestPublishAssets = nil
            latestPrePublishAudit = nil
            latestAdvisorRun = nil
            agentRuns = (try? database.listAgentRuns(limit: 8)) ?? []
            draftVersions = []
        }
        resetTransientReviewState()
    }

    /// 切换文章/新建草稿时清空只属于"上一次会话"的临时状态，避免串场（诊断防空转提示、
    /// 待确认的定点改写、待复核的生成结果、自检提示、读者视角）。
    private func resetTransientReviewState() {
        showUnchangedReviewPrompt = false
        pendingIssueRewrite = nil
        latestSelfCheck = nil
        latestReaderPerspective = nil

        // 未确认/未放弃就切走：视为隐式放弃，清理孤儿 pending 行（18.4.1，语义在 PendingReviewMachine）。
        abandonOrphanedPendingReview()
    }

    func quickDraft() async {
        guard !ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "请先输入想法"
            return
        }

        await run("直接生成初稿", cancellable: true) {
            let style = try self.resolveStyle()
            let retrieval = try self.retrievedMaterialsBlock(query: self.ideaInput)
            var context = self.currentWritingContext(style: style)
            context.materials_excerpt = retrieval.materials
            context.retrieved_fragments = retrieval.fragments
            context.fragment_corpus = retrieval.corpus
            let response = await AgentDraftCoordinator(executor: self.aiClient).run(
                context: context,
                style: style,
                config: self.currentModelConfig,
                apiKey: self.apiKeyInput
            )
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "代理生成初稿",
                status: response.success ? "success" : "fallback",
                summary: response.result.summary ?? response.brief.core_question ?? "完成代理生成初稿。",
                elapsedMS: response.elapsed_ms,
                inputSummary: response.input_summary,
                outputSummary: response.output_summary,
                error: response.error,
                steps: response.steps
            )
            if let circuitBreak = response.circuitBreak {
                self.statusText = "代理式初稿在第 \(circuitBreak.stepIndex) 步（\(circuitBreak.stepName)）失败：\(circuitBreak.reason)"
                return
            }
            try await self.finalizeGeneratedDraft(
                result: response.result,
                fallbackTitle: self.titleIfAvailable(),
                style: style,
                actionTitle: "代理生成初稿",
                successNote: self.agentDraftNote(response),
                failureNote: response.error,
                usedFallback: response.success != true,
                clearArticleSelection: true,
                agentTrace: self.agentDraftTrace(response),
                retrievedFragments: FragmentRetriever.unique(retrieval.fragments + response.sectionFragmentContexts.flatMap(\.fragments)),
                sectionFragmentContexts: response.sectionFragmentContexts
            )
        }
    }

    func generateOutline() async {
        guard let topicPayload = selectedTopic.map(topicPayload) ?? currentTopicPayload() else {
            statusText = "请先选择选题，或输入想法/标题"
            return
        }

        await run("生成大纲", cancellable: true) {
            let style = try self.resolveStyle()
            var context = self.currentWritingContext(style: style)
            context.materials_excerpt = self.materials
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.outline(
                    topic: topicPayload,
                    context: context,
                    style: style,
                    template: self.promptTemplate(for: .outline)
                ),
                onPartialOutput: self.streamingStatusCallback(actionName: "生成大纲")
            ).outlineResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "生成大纲",
                status: response.success == true ? "success" : "fallback",
                summary: response.result.title ?? "完成文章大纲。",
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "生成大纲",
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            let result = response.result
            if let generatedTitle = result.title, !generatedTitle.isEmpty {
                self.title = generatedTitle
            }
            self.outline = result.markdown
            self.statusText = response.success == true ? "大纲已生成" : "已使用本地模拟大纲：\(response.error ?? "未配置 API Key")"
        }
    }

    func draftFromOutline() async {
        guard let topicPayload = selectedTopic.map(topicPayload) ?? currentTopicPayload() else {
            statusText = "请先选择选题，或输入想法/标题"
            return
        }
        guard !outline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "请先填写大纲"
            return
        }

        await run("大纲成稿", cancellable: true) {
            let style = try self.resolveStyle()
            var context = self.currentWritingContext(style: style)
            context.outline_excerpt = self.outline
            context.materials_excerpt = self.materials
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.draft(
                    topic: topicPayload,
                    context: context,
                    style: style,
                    template: self.promptTemplate(for: .draft)
                ),
                onPartialOutput: self.streamingStatusCallback(actionName: "大纲成稿")
            ).draftResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "大纲成稿",
                status: response.success == true ? "success" : "fallback",
                summary: response.result.summary ?? "根据当前大纲生成正文。",
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "大纲成稿",
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            try await self.finalizeGeneratedDraft(
                result: response.result,
                fallbackTitle: self.selectedTopic?.title ?? self.titleIfAvailable(),
                style: style,
                actionTitle: "大纲成稿",
                successNote: "根据当前大纲生成正文",
                failureNote: response.error,
                usedFallback: response.success != true,
                clearArticleSelection: true
            )
        }
    }

    func polishDraft(_ mode: PolishMode) async {
        guard canPolishDraft else {
            statusText = "请先完成一版正文"
            return
        }

        await run(mode.title, cancellable: true) {
            let style = try self.resolveStyle()
            let context = self.currentWritingContext(style: style)
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.polishDraft(
                    context: context,
                    content: self.content,
                    mode: mode,
                    style: style,
                    template: self.promptTemplate(for: .polishDraft)
                ),
                onPartialOutput: self.streamingStatusCallback(actionName: mode.title)
            ).draftResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: mode.title,
                status: response.success == true ? "success" : "fallback",
                summary: response.result.summary ?? mode.promptInstruction,
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: mode.title,
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            try await self.finalizeGeneratedDraft(
                result: response.result,
                fallbackTitle: self.titleIfAvailable(),
                style: style,
                actionTitle: mode.title,
                successNote: mode.promptInstruction,
                failureNote: response.error,
                usedFallback: response.success != true,
                clearArticleSelection: false
            )
        }
    }

    func reviewCurrentDraft() async {
        guard canRunWritingCoach else {
            statusText = "请先输入想法、大纲或正文"
            return
        }

        // 18.3.2 防空转：内容自上次诊断以来没有实质变化时，先提示，而不是直接重新调用模型。
        if let latestReview,
           let previousSnapshot = latestReview.reviewed_snapshot,
           previousSnapshot == currentReviewableSnapshot() {
            showUnchangedReviewPrompt = true
            return
        }

        await performReviewCurrentDraft()
    }

    /// 用户在"内容未变化，仍要重新诊断吗？"提示中选择继续时调用。
    func confirmReviewDespiteNoChange() async {
        showUnchangedReviewPrompt = false
        await performReviewCurrentDraft()
    }

    func cancelUnchangedReviewPrompt() {
        showUnchangedReviewPrompt = false
        statusText = "已取消本次诊断"
    }

    /// 18.3.5 自检提示是纯展示性的旁注，作者确认看过后可以主动清掉编辑器里的高亮。
    func dismissSelfCheckHighlights() {
        latestSelfCheck = nil
    }

    func performReviewCurrentDraft() async {
        await run("写作诊断", cancellable: true) {
            let style = try self.resolveStyle()
            let previousReview = self.latestReview
            var context = self.currentWritingContext(style: style)
            context.title = self.title
            context.summary = self.summary
            context.idea = self.ideaInput
            context.direction = self.normalizedDirection
            context.outline_excerpt = self.outline
            context.content_excerpt = self.content
            context.word_count = self.content.count
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.writingReview(
                    context: context,
                    style: style,
                    previousReview: previousReview,
                    template: self.promptTemplate(for: .writingReview)
                )
            ).writingReviewResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "写作诊断",
                status: response.success == true ? "success" : "fallback",
                summary: response.result.summary ?? "完成写作诊断。",
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "写作诊断",
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            let review = try self.database.saveWritingReview(
                result: response.result,
                articleID: self.selectedArticleID,
                titleSnapshot: self.titleIfAvailable(),
                model: self.normalizedModel,
                reviewedSnapshot: self.currentReviewableSnapshot()
            )
            self.latestReview = review
            self.writingReviews = try self.database.listWritingReviews()
            self.statusText = response.success == true ? "写作诊断已完成" : "已使用本地诊断：\(response.error ?? "未配置 API Key")"
        }
    }

    func improveDraftFromLatestReview() async {
        guard let review = latestReview else {
            statusText = "请先运行写作诊断"
            return
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "请先完成一版正文"
            return
        }
        guard pendingDraftReview == nil else {
            statusText = "还有未确认的生成结果，请先确认或放弃"
            return
        }

        await run("按诊断改全文", cancellable: true) {
            let style = try self.resolveStyle()
            let context = self.currentWritingContext(style: style)
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.improveDraftFromReview(
                    context: context,
                    content: self.content,
                    review: review,
                    style: style
                )
            ).draftResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "按诊断改全文",
                status: response.success == true ? "success" : "fallback",
                summary: response.result.summary ?? review.summary,
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "按诊断改全文",
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            try await self.finalizeGeneratedDraft(
                result: response.result,
                fallbackTitle: self.titleIfAvailable(),
                style: style,
                actionTitle: "按诊断改全文",
                successNote: self.reviewRevisionNote(review),
                failureNote: response.error,
                usedFallback: response.success != true,
                clearArticleSelection: false
            )
        }
    }

    func deepDraftRevision() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "请先完成一版正文，再深度成稿"
            return
        }
        guard pendingDraftReview == nil else {
            statusText = "还有未确认的生成结果，请先确认或放弃"
            return
        }

        await run("深度成稿", cancellable: true) {
            let style = try self.resolveStyle()
            let retrieval = try self.retrievedMaterialsBlock(query: [self.title, self.ideaInput, self.outline].joined(separator: "\n"))
            let coordinator = DeepDraftCoordinator(aiClient: self.aiClient)
            let output = try await coordinator.run(
                input: DeepDraftInput(
                    title: self.titleIfAvailable(),
                    summary: self.summary,
                    content: self.content,
                    outline: self.outline,
                    idea: self.ideaInput,
                    direction: self.normalizedDirection,
                    materials: retrieval.materials,
                    style: style,
                    previousReview: self.latestReview,
                    writingReviewTemplate: self.promptTemplate(for: .writingReview),
                    config: self.currentModelConfig,
                    apiKey: self.apiKeyInput
                )
            )
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "深度成稿",
                status: output.success ? "success" : "fallback",
                summary: output.summaryText,
                elapsedMS: output.elapsed_ms,
                inputSummary: "从当前正文自动执行诊断→修订→复评。",
                outputSummary: output.summaryText,
                error: output.error,
                steps: output.steps
            )
            try await self.finalizeGeneratedDraft(
                result: output.draft,
                fallbackTitle: self.titleIfAvailable(),
                style: style,
                actionTitle: "深度成稿",
                successNote: output.summaryText,
                failureNote: output.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : output.error,
                usedFallback: !output.success,
                clearArticleSelection: false,
                retrievedFragments: retrieval.fragments,
                iterationSummary: output.iterations
            )
        }
    }

    func runWritingAdvisor() async {
        guard canRunAdvisor else {
            statusText = "请先输入想法、大纲或正文"
            return
        }

        await run("智能判断下一步", cancellable: true) {
            let style = try self.resolveStyle()
            let context = self.currentWritingContext(style: style)
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.writingAdvisor(
                    context: context,
                    style: style,
                    template: self.promptTemplate(for: .writingAdvisor)
                )
            ).writingAdvisorResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "智能判断下一步",
                status: response.success == true ? "success" : "fallback",
                summary: response.result.next_action ?? response.result.main_problem ?? "完成智能下一步判断。",
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "智能判断下一步",
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            let run = try self.database.saveWritingAdvisorRun(
                result: response.result,
                context: context,
                articleID: self.selectedArticleID,
                titleSnapshot: self.titleIfAvailable(),
                model: self.normalizedModel
            )
            self.latestAdvisorRun = run
            self.advisorRuns = try self.database.listWritingAdvisorRuns()
            self.statusText = response.success == true ? "已给出下一步建议" : "已使用本地建议：\(response.error ?? "未配置 API Key")"
        }
    }

    /// 读者视角模拟（18.4.3）：定性补充诊断，不计入 overall_score，不替代编辑视角诊断。
    func runReaderPerspective() async {
        guard canRunReaderPerspective else {
            statusText = "请先完成一版正文"
            return
        }

        await run("读者视角模拟", cancellable: true) {
            let style = try self.resolveStyle()
            let context = self.currentWritingContext(style: style)
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.readerPerspective(
                    context: context,
                    style: style,
                    template: self.promptTemplate(for: .readerPerspective)
                )
            ).readerPerspectiveResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "读者视角模拟",
                status: response.success == true ? "success" : "fallback",
                summary: response.result.drop_off_point ?? response.result.note ?? "完成读者视角模拟。",
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "读者视角模拟",
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            self.latestReaderPerspective = response.result
            self.statusText = response.success == true ? "已生成读者视角参考" : "已使用本地读者视角：\(response.error ?? "未配置 API Key")"
        }
    }

    func performAdvisorAction(_ action: AdvisorAction) {
        switch action {
        case .quickDraft:
            Task { await quickDraft() }
        case .generateTopics:
            Task { await generateTopics() }
        case .generateOutline:
            Task { await generateOutline() }
        case .draftFromOutline:
            Task { await draftFromOutline() }
        case .writingReview:
            Task { await reviewCurrentDraft() }
        case .rewriteSelectionNatural:
            Task { await rewriteSelectedContent(.natural) }
        case .rewriteSelectionExpand:
            Task { await rewriteSelectedContent(.expand) }
        case .polishNatural:
            Task { await polishDraft(.natural) }
        case .polishTighten:
            Task { await polishDraft(.tighten) }
        case .publishAssets:
            Task { await generatePublishAssets() }
        case .saveArticle:
            Task { await saveArticle() }
        }
    }

    func rewriteSelectedContent(_ mode: RewriteMode) async {
        let range = contentSelection
        guard let selectedText = selectedContentText(in: range),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "请先在正文中选中一段文字"
            return
        }

        let surroundingText = contextAroundSelection(range)
        await run(mode.title, cancellable: true) {
            let style = try self.resolveStyle()
            let context = self.currentWritingContext(style: style).replacingTitle(self.titleIfAvailable())
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.rewriteSelection(
                    context: context,
                    selectedText: selectedText,
                    surroundingText: surroundingText,
                    mode: mode,
                    customInstruction: nil,
                    style: style,
                    template: self.promptTemplate(for: .rewriteSelection)
                ),
                onPartialOutput: self.streamingStatusCallback(actionName: mode.title)
            ).rewriteSelectionResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: mode.title,
                status: response.success == true ? "success" : "fallback",
                summary: response.result.note ?? "完成局部改写。",
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: mode.title,
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )

            let replacement = response.result.replacement ?? response.result.raw_output ?? ""
            guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.statusText = "模型没有返回可替换文本"
                return
            }
            let before = self.currentDraftSnapshot()
            guard self.replaceSelectedContent(range: range, expectedText: selectedText, replacement: replacement) else {
                self.statusText = "正文已变化，请重新选择后再改写"
                return
            }
            let note = response.result.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let version = try self.database.saveDraftVersion(
                articleID: self.selectedArticleID,
                titleSnapshot: self.titleIfAvailable(),
                action: mode.title,
                note: note?.isEmpty == false ? note : response.error,
                before: before,
                after: self.currentDraftSnapshot()
            )
            self.draftVersions = [version] + self.draftVersions
            if response.success == true {
                self.statusText = note?.isEmpty == false ? "\(mode.title)已完成：\(note!)" : "\(mode.title)已完成"
            } else {
                self.statusText = "已使用本地改写：\(response.error ?? "未配置 API Key")"
            }
        }
    }

    /// Inspector 中"定位并改写"按钮据此判断是否展示改写入口（18.3.1 验收标准 1）。
    func canLocateIssue(_ issue: WritingReviewIssue) -> Bool {
        locateExcerpt(issue.excerpt) != nil
    }

    func canLocateAuditIssue(_ issue: AuditIssue) -> Bool { locateExcerpt(issue.excerpt) != nil }

    func rewriteFromAuditIssue(_ issue: AuditIssue) async { await rewriteFromIssue(issue.writingReviewIssue) }

    /// 诊断-改写闭环入口（18.3.1）：按 `issue.excerpt` 定位正文片段并选中，用 `issue.suggestion` 作为改写指令
    /// 生成候选；候选只暂存到 `pendingIssueRewrite`，必须经人工确认才会替换正文。
    func rewriteFromIssue(_ issue: WritingReviewIssue) async {
        guard let range = locateExcerpt(issue.excerpt), let selectedText = selectedContentText(in: range) else {
            statusText = "未找到对应片段，正文可能已经改动"
            return
        }
        contentSelection = range
        let surroundingText = contextAroundSelection(range)

        await run("定点改写", cancellable: true) {
            let style = try self.resolveStyle()
            let context = self.currentWritingContext(style: style).replacingTitle(self.titleIfAvailable())
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.rewriteSelection(
                    context: context,
                    selectedText: selectedText,
                    surroundingText: surroundingText,
                    mode: .custom,
                    customInstruction: issue.suggestion,
                    style: style,
                    template: self.promptTemplate(for: .rewriteSelection)
                )
            ).rewriteSelectionResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "定点改写",
                status: response.success == true ? "success" : "fallback",
                summary: response.result.note ?? issue.suggestion,
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "定点改写",
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            let replacement = response.result.replacement ?? response.result.raw_output ?? ""
            guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.statusText = "模型没有返回可替换文本"
                return
            }
            self.pendingIssueRewrite = PendingIssueRewrite(
                issue: issue,
                range: range,
                originalText: selectedText,
                replacement: replacement,
                note: response.result.note,
                usedFallback: response.success != true
            )
            self.statusText = "已生成改写候选，请确认后替换正文"
        }
    }

    func generatePublishAssets() async {
        guard canGeneratePublishAssets else {
            statusText = "请先填写标题、摘要或正文"
            return
        }

        await run("生成发布物料", cancellable: true) {
            let style = try self.resolveStyle()
            var context = self.currentWritingContext(style: style)
            context.title = self.title
            context.summary = self.summary
            context.content_excerpt = self.content
            context.word_count = self.content.count
            let response = await self.executeWorkflow(
                NativeWorkflowCatalog.publishAssets(
                    context: context,
                    style: style,
                    template: self.promptTemplate(for: .publishAssets)
                )
            ).publishAssetsResponse
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "生成发布物料",
                status: response.success == true ? "success" : "fallback",
                summary: response.result.summary ?? response.result.cover_text ?? "完成发布物料生成。",
                elapsedMS: response.elapsed_ms ?? 0,
                inputSummary: response.input_summary ?? "",
                outputSummary: response.output_summary ?? "",
                error: response.error ?? "",
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "生成发布物料",
                        success: response.success == true,
                        elapsedMS: response.elapsed_ms ?? 0,
                        inputSummary: response.input_summary ?? "",
                        outputSummary: response.output_summary ?? "",
                        error: response.error ?? ""
                    )
                ]
            )
            let assets = try self.database.savePublishAssets(
                result: response.result,
                articleID: self.selectedArticleID,
                titleSnapshot: self.titleIfAvailable(),
                model: self.normalizedModel
            )
            self.latestPublishAssets = assets
            self.publishAssetsHistory = try self.database.listPublishAssets()
            if self.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let generatedSummary = response.result.summary,
               !generatedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.summary = generatedSummary
            }
            if let tags = response.result.tags, !tags.isEmpty {
                self.draftTags = tags
            }
            self.statusText = response.success == true ? "发布物料已生成" : "已使用本地发布物料：\(response.error ?? "未配置 API Key")"
        }
    }

    func saveArticle() async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "请先填写标题"
            return
        }
        // 18.8 验收标准 6：未确认的生成结果不得覆盖已保存的定稿内容，先让作者确认或放弃。
        guard pendingDraftReview == nil else {
            statusText = "还有未确认的生成结果，请先在「待复核」中确认或放弃"
            return
        }

        let finalStatus = articleStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "草稿" : articleStatus
        await run(finalStatus == "已发布" ? "保存并发表前终审" : "保存文章", cancellable: finalStatus == "已发布") {
            let titleSnapshot = self.titleIfAvailable()
            // 覆盖保存前留住已存定稿：保存本身也记一条版本，作者可用「恢复前」回到保存前的内容。
            let previousSaved = self.selectedArticleID.flatMap { try? self.database.getArticle($0) }
            let article = try self.database.saveArticle(
                id: self.selectedArticleID,
                payload: .draft(title: self.title, content: self.content, summary: self.summary, status: finalStatus, tags: self.draftTags, topicID: self.selectedTopicID, genre: self.normalizedDirection)
            )
            self.selectedArticleID = article.id
            try self.database.attachDraftVersionsToArticle(articleID: article.id, titleSnapshot: titleSnapshot)
            if let previousSaved {
                let before = DraftSnapshot(
                    title: previousSaved.title ?? "",
                    summary: previousSaved.summary ?? "",
                    content: previousSaved.content ?? ""
                )
                let after = self.currentDraftSnapshot()
                if before != after {
                    _ = try self.database.saveDraftVersion(
                        articleID: article.id,
                        titleSnapshot: titleSnapshot,
                        action: "保存文章",
                        note: "已覆盖旧定稿，「恢复前」可回到本次保存之前",
                        before: before,
                        after: after
                    )
                }
            }
            var auditNote = ""
            // 编辑量只在「非已发布 → 已发布」这一次跃迁上记；已发布状态下再保存不再追加，
            // 否则同一篇文章会被重复计数（24.8：香菱一次发布记出 7 条零改动）。
            if finalStatus == "已发布" {
                auditNote = try await self.runPrePublishAudit(articleID: article.id)
                if previousSaved?.status != "已发布" {
                    self.applyPublishingMetrics(PublishingMetricsRecorder(database: self.database).recordPublishedArticle(article))
                }
            }
            self.articleStatus = article.status ?? finalStatus
            self.articles = try self.database.listArticles()
            self.draftVersions = try self.database.listDraftVersions(articleID: article.id, limit: 8)
            self.stats = try self.database.overviewStats()
            self.applyPublishingMetrics(try? PublishingMetricsRecorder(database: self.database).snapshot())
            self.clearAutosaveSnapshot()
            self.statusText = auditNote.isEmpty ? "文章已保存" : "文章已保存；\(auditNote)"
        }
    }

    func updateSelectedArticleStatus(_ status: String) async {
        guard let selectedArticleID else {
            articleStatus = status
            statusText = "当前草稿状态已设为\(status)"
            return
        }

        await run(status == "已发布" ? "发表前终审并发布" : "更新文章状态", cancellable: status == "已发布") {
            let previousStatus = (try? self.database.getArticle(selectedArticleID))?.status
            var auditNote = ""
            if status == "已发布" {
                auditNote = try await self.runPrePublishAudit(articleID: selectedArticleID)
            }
            let article = try self.database.updateArticleStatus(id: selectedArticleID, status: status)
            // 只记「非已发布 → 已发布」这一次跃迁，反复点「更新状态」不再追加（24.8）。
            if status == "已发布", previousStatus != "已发布" {
                self.applyPublishingMetrics(PublishingMetricsRecorder(database: self.database).recordPublishedArticle(article))
            }
            self.articleStatus = article.status ?? status
            self.articles = try self.database.listArticles()
            self.stats = try self.database.overviewStats()
            self.applyPublishingMetrics(try? PublishingMetricsRecorder(database: self.database).snapshot())
            self.statusText = auditNote.isEmpty ? "文章已\(status)" : "文章已\(status)；\(auditNote)"
        }
    }

    private func runPrePublishAudit(articleID: Int) async throws -> String {
        let output = try await PrePublishAuditCoordinator(aiClient: aiClient, database: database).run(
            PrePublishAuditInput(
                articleID: articleID,
                title: titleIfAvailable(),
                summary: summary,
                content: content,
                style: try resolveStyle(),
                template: promptTemplate(for: .prePublishAudit),
                config: currentModelConfig,
                apiKey: apiKeyInput,
                model: normalizedModel
            )
        )
        latestPrePublishAudit = output.audit ?? latestPrePublishAudit
        return output.note
    }

    private func applyPublishingMetrics(_ snapshot: PublishingMetricsSnapshot?) {
        guard let snapshot else { return }
        editRecordStats = snapshot.stats
        editRecordMonthlySummary = snapshot.monthlySummary
    }

    func retrievedMaterialsBlock(query: String) throws -> (materials: String, fragments: [RetrievedFragment], corpus: [Fragment]) {
        try WorkshopRetrieval.materialsBlock(query: query, materials: materials, database: database)
    }

    /// search_materials 动作（任务 16）供 WritingAgentCoordinator 检索的本地语料；`database` 是本文件私有字段，
    /// 其他 Store 扩展文件需经此方法取用。
    func currentFragmentCorpus() throws -> [Fragment] {
        try database.rebuildFragments()
    }

    func cancelCurrentOperation() {
        guard let currentOperationTask, currentOperationIsCancellable else {
            statusText = "当前没有可取消的生成任务"
            return
        }
        currentOperationTask.cancel()
        statusText = "正在取消\(currentOperationName ?? "当前任务")..."
    }

    func run(_ name: String, cancellable: Bool = false, operation: @escaping () async throws -> Void) async {
        guard currentOperationTask == nil else {
            statusText = "\(currentOperationName ?? "当前任务")仍在执行"
            return
        }
        isLoading = true
        currentOperationName = name
        currentOperationIsCancellable = cancellable
        statusText = "\(name)中..."
        let task = Task {
            try await operation()
        }
        currentOperationTask = task
        defer {
            currentOperationTask = nil
            currentOperationIsCancellable = false
            currentOperationName = nil
            isLoading = false
        }
        do {
            try await task.value
            if statusText.hasSuffix("中...") {
                statusText = "\(name)完成"
            }
        } catch is CancellationError {
            statusText = "\(name)已取消"
        } catch {
            if Self.isCancellation(error) {
                statusText = "\(name)已取消"
            } else {
                statusText = error.localizedDescription
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    @discardableResult
    func recordAgentRun(
        runType: String,
        status: String,
        summary: String?,
        elapsedMS: Int,
        inputSummary: String,
        outputSummary: String,
        error: String,
        steps: [AgentStepPayload],
        articleID: Int? = nil,
        titleSnapshot: String? = nil,
        sessionKind: String? = nil,
        budgetSummary: String? = nil
    ) throws -> AgentRun {
        let run = try database.saveAgentRun(
            runType: runType,
            articleID: articleID ?? selectedArticleID,
            titleSnapshot: titleSnapshot ?? titleIfAvailable(),
            status: status,
            summary: summary,
            model: normalizedModel,
            elapsedMS: elapsedMS,
            inputSummary: inputSummary,
            outputSummary: outputSummary,
            error: error,
            steps: steps,
            sessionKind: sessionKind,
            budgetSummary: budgetSummary
        )
        agentRuns = [run] + agentRuns.filter { $0.id != run.id }
        return run
    }

    private var normalizedBaseURL: String {
        let value = modelBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value.isEmpty ? "https://api.deepseek.com" : value
    }

    private var normalizedModel: String {
        let value = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "deepseek-v4-pro" : value
    }

    var currentModelConfig: ModelConfig {
        var config = (try? database.modelConfig()) ?? ModelConfig()
        config.baseURL = normalizedBaseURL
        config.model = normalizedModel
        return config
    }

    private func parseWorkflowOverrides() throws -> [String: ModelRouteConfig] {
        let text = modelWorkflowOverridesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [:] }
        guard let data = text.data(using: .utf8) else {
            throw NativeDatabaseError.statement(message: "工作流模型路由 JSON 无法编码")
        }
        do {
            return try JSONDecoder().decode([String: ModelRouteConfig].self, from: data)
        } catch {
            throw NativeDatabaseError.statement(message: "工作流模型路由 JSON 格式无效：\(error.localizedDescription)")
        }
    }

    private static func prettyJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// 不再静默兜底为固定体裁：方向为空时保持为空，由提示词按正文自行判断体裁。
    var normalizedDirection: String {
        writingDirection.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 写作方向下拉候选：风格档案体裁 + 已有文章体裁 + 内置常用项，按出现顺序去重。
    /// 选已有项可保证与风格档案匹配（18.3.4）和同体裁样本抽取的键完全一致。
    var knownDirections: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let candidates = styleProfiles.compactMap(\.genre)
            + articles.compactMap(\.genre)
            + ["情感文学", "原著解读", "技术分享"]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private var reviewableText: String {
        [title, summary, content, outline, ideaInput, materials].joined(separator: "\n")
    }

    /// 用于诊断防空转的内容快照（18.3.2）：不含素材，只覆盖诊断真正读取的字段，避免无关改动误判为"有变化"。
    private func currentReviewableSnapshot() -> String {
        [title, summary, content, outline, ideaInput].joined(separator: "\u{1F}")
    }

    func currentWritingContext(style: StyleProfile) -> ContextPackage {
        var context = contextBuilder.build(
            title: title,
            summary: summary,
            content: content,
            outline: outline,
            idea: ideaInput,
            direction: normalizedDirection,
            materials: materials,
            style: style,
            selectedTopic: selectedTopic,
            recentArticles: articles,
            recentReviews: writingReviews,
            ideas: ideas
        )
        context.learned_preferences = (style.learned_preferences ?? []).map(\.description)
        // 体裁优先取当前文章自己的 genre（诊断/建议按篇适配），风格档案的体裁只作兜底。
        if let articleGenre = selectedArticle?.genre?.trimmingCharacters(in: .whitespacesAndNewlines),
           !articleGenre.isEmpty {
            context.genre = articleGenre
        }
        return context
    }

    func promptTemplate(for key: PromptTemplateKey) -> PromptTemplate? {
        promptTemplates.first { $0.key == key.rawValue } ?? (try? database.promptTemplate(key: key))
    }

    func executeWorkflow<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        onPartialOutput: (@Sendable (String) -> Void)? = nil
    ) async -> AIRun<Output> {
        await aiClient.execute(descriptor, config: currentModelConfig, apiKey: apiKeyInput, onPartialOutput: onPartialOutput)
    }

    /// 生成中途的增量状态提示（仅更新字数，不拼出正文预览——模型输出是整篇 JSON，
    /// 半截分片无法可靠抠出 `content` 字段，见任务 9 方案）。回调在 `AIWorkflowRunner`
    /// 的非隔离 async 循环里同步调用，需要跳回主 actor 才能改 `@Published` 属性。
    private func streamingStatusCallback(actionName: String) -> @Sendable (String) -> Void {
        { [weak self] text in
            Task { @MainActor in
                self?.statusText = "\(actionName)中…已接收\(text.count)字"
            }
        }
    }

    /// 按当前写作方向匹配体裁化风格档案，并把该体裁最近的真实文章优先注入 few-shot 样本（18.3.4）。
    /// 返回的是内存中的临时副本，不会把注入的样本写回 `style_profiles`。
    func resolveStyle() throws -> StyleProfile {
        var style = try database.styleProfile(forDirection: normalizedDirection)
        let genreKey = style.genre.nilIfEmpty ?? normalizedDirection
        var usedDraftFallback = false
        // 一次取够近期**完成稿**作候选，体裁优先级交给 StyleSampleSelector 判（24.6）：
        // 精确相等的匹配太脆（方向换个说法样本就归零），跨体裁乱取又会拿技术文教文学腔。
        // 草稿不进候选——改到一半的稿子不能当风格范本。
        var candidates = try database.recentArticlesForSamples(
            genre: nil,
            excludingArticleID: selectedArticleID,
            limit: 10,
            finishedOnly: true
        )
        if candidates.isEmpty {
            // 一篇完成稿都没有（新库/全是草稿）时才退到草稿：范本不理想，但好过模型一篇
            // 都没见过作者的文字。
            candidates = try database.recentArticlesForSamples(
                genre: nil,
                excludingArticleID: selectedArticleID,
                limit: 2
            )
            usedDraftFallback = !candidates.isEmpty
        }
        let selection = StyleSampleSelector.selection(from: candidates, genreKey: genreKey)
        let sampleArticles = selection.articles
        let genreExcerpts = sampleArticles.compactMap { $0.content.nilIfEmpty }
        // 注入出处随每次 resolveStyle 更新，交付待复核时一并带给界面（24.9-P1）。
        lastStyleSampleProvenance = StyleSampleProvenance(
            tierLabel: selection.tier.label,
            titles: sampleArticles.compactMap { $0.title.nilIfEmpty },
            usedDraftFallback: usedDraftFallback
        )
        guard !genreExcerpts.isEmpty else {
            return style
        }
        style.sample_texts = genreExcerpts + (style.sample_texts ?? [])
        return style
    }

    func currentDraftSnapshot() -> DraftSnapshot {
        DraftSnapshot(title: title, summary: summary, content: content)
    }

    func applySnapshot(_ snapshot: DraftSnapshot) {
        title = snapshot.title
        summary = snapshot.summary
        content = snapshot.content
        contentSelection = NSRange(location: 0, length: 0)
    }

    private func selectedContentText(in range: NSRange) -> String? {
        guard range.length > 0,
              let swiftRange = Range(range, in: content) else {
            return nil
        }
        return String(content[swiftRange])
    }

    /// 按诊断 issue 的 `excerpt` 在当前正文中定位一次精确匹配（18.3.1）。找不到时返回 nil，
    /// 调用方必须据此提示"未找到对应片段"，不能猜测一个近似位置。
    private func locateExcerpt(_ excerpt: String?) -> NSRange? {
        guard let excerpt else { return nil }
        let trimmed = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let swiftRange = content.range(of: trimmed) else {
            return nil
        }
        return NSRange(swiftRange, in: content)
    }

    private func contextAroundSelection(_ range: NSRange, radius: Int = 800) -> String {
        guard let swiftRange = Range(range, in: content) else {
            return String(content.prefix(radius * 2))
        }
        let leadingDistance = content.distance(from: content.startIndex, to: swiftRange.lowerBound)
        let trailingDistance = content.distance(from: swiftRange.upperBound, to: content.endIndex)
        let lowerBound = content.index(swiftRange.lowerBound, offsetBy: -min(radius, leadingDistance))
        let upperBound = content.index(swiftRange.upperBound, offsetBy: min(radius, trailingDistance))
        return String(content[lowerBound..<upperBound])
    }

    func replaceSelectedContent(range: NSRange, expectedText: String, replacement: String) -> Bool {
        guard let swiftRange = Range(range, in: content),
              String(content[swiftRange]) == expectedText else {
            return false
        }
        content.replaceSubrange(swiftRange, with: replacement)
        contentSelection = NSRange(location: range.location, length: replacement.utf16.count)
        return true
    }

    func titleIfAvailable() -> String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            return value
        }
        return selectedTopic?.title ?? "未命名文章"
    }

    private func currentTopicPayload() -> TopicPayload? {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let idea = ideaInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedTitle.isEmpty || !idea.isEmpty else {
            return nil
        }
        return TopicPayload(
            title: resolvedTitle.isEmpty ? String(idea.prefix(32)) : resolvedTitle,
            direction: normalizedDirection,
            core_viewpoint: idea.isEmpty ? nil : idea,
            target_reader: nil,
            description: idea.isEmpty ? summary : idea,
            angle: summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : summary,
            emotion: nil,
            score: 3,
            status: "待写",
            tags: [normalizedDirection]
        )
    }

    private func topicPayload(_ topic: Topic) -> TopicPayload {
        TopicPayload(
            title: topic.title,
            direction: topic.direction,
            core_viewpoint: topic.core_viewpoint,
            target_reader: topic.target_reader,
            description: topic.description,
            angle: topic.angle,
            emotion: topic.emotion,
            score: topic.score,
            status: topic.status,
            tags: topic.tags
        )
    }

    func applyDraft(_ result: DraftResult, fallbackTitle: String) {
        title = result.title ?? fallbackTitle
        summary = result.summary ?? summary
        content = result.content ?? result.raw_output ?? content
        draftTags = result.tags ?? draftTags
    }

    private func agentDraftNote(_ response: AgentDraftResponse) -> String {
        [
            "代理初稿流程：writing brief → 论点检查 → 分段成稿 → 自我批评。",
            response.brief.core_question.map { "Brief 核心问题：\($0)" },
            response.brief.thesis.map { "Brief 主张：\($0)" },
            response.argumentCheck.revision_directives?.isEmpty == false
                ? "论点检查指令：\(response.argumentCheck.revision_directives!.prefix(3).joined(separator: "；"))"
                : nil,
            response.critique.critique_notes?.isEmpty == false
                ? "自我批评：\(response.critique.critique_notes!.prefix(3).joined(separator: "；"))"
                : nil
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func agentDraftTrace(_ response: AgentDraftResponse) -> AgentDraftTrace {
        AgentDraftTrace(
            workingTitle: response.brief.working_title ?? response.result.title ?? "未命名代理初稿",
            coreQuestion: response.brief.core_question ?? "未返回核心问题",
            thesis: response.brief.thesis ?? "未返回核心主张",
            targetReader: response.brief.target_reader ?? "未返回目标读者",
            argumentDirectives: response.argumentCheck.revision_directives ?? [],
            missingEvidence: response.argumentCheck.missing_evidence ?? [],
            sectionSummaries: (response.sectionDraft.sections ?? []).map { section in
                let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
                let check = section.self_check?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let check, !check.isEmpty {
                    return "\(heading.isEmpty ? "未命名段落" : heading)：\(check)"
                }
                return heading.isEmpty ? String(section.content.prefix(40)) : heading
            },
            critiqueNotes: response.critique.critique_notes ?? [],
            unresolvedGaps: response.brief.unresolved_gaps ?? [],
            plannedSectionCount: response.brief.structure_plan?.count ?? 0
        )
    }

    private func reviewRevisionNote(_ review: WritingReview) -> String {
        [
            "根据写作教练诊断进行全文修订。",
            "诊断摘要：\(review.summary)",
            review.revision_plan.isEmpty ? nil : "修改顺序：\(review.revision_plan.prefix(4).joined(separator: "；"))",
            review.training_focus.isEmpty ? nil : "训练重点：\(review.training_focus.prefix(3).joined(separator: "；"))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

}

private extension OutlineResult {
    var markdown: String {
        if let raw_output, !raw_output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw_output
        }

        var lines: [String] = []
        if let title, !title.isEmpty {
            lines.append("# \(title)")
            lines.append("")
        }
        if let opening, !opening.isEmpty {
            lines.append("## 开头")
            lines.append(opening)
            lines.append("")
        }
        for section in sections ?? [] {
            if let heading = section.heading, !heading.isEmpty {
                lines.append("## \(heading)")
            }
            for point in section.points ?? [] where !point.isEmpty {
                lines.append("- \(point)")
            }
            if let hint = section.material_hint, !hint.isEmpty {
                lines.append("素材位置：\(hint)")
            }
            lines.append("")
        }
        if let ending, !ending.isEmpty {
            lines.append("## 结尾")
            lines.append(ending)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
