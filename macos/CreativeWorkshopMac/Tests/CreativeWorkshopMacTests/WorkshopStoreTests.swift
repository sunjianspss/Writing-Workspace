import XCTest
import SQLite3
@testable import CreativeWorkshopMac
@testable import CreativeWorkshopCore

@MainActor
final class WorkshopStoreTests: XCTestCase {
    /// PRD 23.6 验收标准 8：实验室开关默认关闭时，会话入口直接拒绝，不进入循环，
    /// 且系统其余行为（agentRuns/pendingDraftReview）与实施前完全一致。
    func testStartAgentSessionRejectsWhenAgentLabDisabled() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        XCTAssertFalse(store.agentLabEnabled, "默认应关闭")
        XCTAssertFalse(store.canStartAgentSession)

        await store.startAgentSession()

        XCTAssertNil(store.pendingDraftReview)
        XCTAssertTrue(store.agentRuns.isEmpty, "入口拒绝时不应产生任何 agent_runs 记录")
    }

    func testNewDraftRequiresConfirmationWhenCurrentDraftHasUnsavedChanges() throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        store.content = "不能静默丢失的正文"

        store.newDraft()

        XCTAssertEqual(store.content, "不能静默丢失的正文")
        XCTAssertNotNil(store.pendingSessionSwitch)
        XCTAssertTrue(store.statusText.contains("未保存修改"))

        store.confirmPendingSessionSwitch()
        XCTAssertEqual(store.content, "")
        XCTAssertNil(store.pendingSessionSwitch)
    }

    /// PRD 23.6.5：任务 15 的核心状态流转——ask_author 暂停出现提问卡，续跑后（预算继承）
    /// 模型选择 finish，会话摘要与最终稿一次性进入待复核，提问卡随之清空。
    func testAgentSessionAskAuthorPausesThenResumeDeliversPendingReview() async throws {
        let database = try makeDatabase()
        let executor = DecisionScriptedExecutor()
        executor.decisions = [
            AgentDecisionResult(
                action: "ask_author",
                arguments: AgentDecisionArguments(query: "需要更多关于XX的素材"),
                reason: "缺证据",
                stop: false
            )
        ]
        let store = try WorkshopStore(database: database, aiClient: executor)
        store.setAgentLabEnabled(true)
        store.apiKeyInput = "fake-key"
        store.ideaInput = "一个想法"

        await store.startAgentSession()

        let askAuthor = try XCTUnwrap(store.agentSessionAskAuthor, "ask_author 应暂停会话并出现提问卡")
        XCTAssertEqual(askAuthor.questions, ["需要更多关于XX的素材"])
        XCTAssertNil(store.pendingDraftReview, "暂停阶段不应交付待复核")

        // finish 前置收紧（"不空手"）：正文为空时不能直接 finish，续跑脚本先产出一版正文再收尾。
        executor.decisions = [
            AgentDecisionResult(action: "agent_quick_draft", reason: "先出一版正文", stop: false),
            AgentDecisionResult(action: "finish", reason: "已经足够", stop: true)
        ]
        await store.resumeAgentSession()

        XCTAssertNil(store.agentSessionAskAuthor, "续跑完成后提问卡应清空")
        let pending = try XCTUnwrap(store.pendingDraftReview, "finish 应把最终稿交付待复核")
        XCTAssertFalse(pending.after.content.isEmpty, "交付不得空手")
        XCTAssertEqual(pending.agentSessionSummary?.first, "共 7 步，停止原因：模型判断可以结束会话")
    }

    /// 「就此结束」路径：不再消耗模型调用，直接按 finish 语义交付暂停时的最好版本。
    func testFinishAgentSessionNowDeliversWithoutFurtherModelCalls() async throws {
        let database = try makeDatabase()
        let executor = DecisionScriptedExecutor()
        executor.decisions = [
            AgentDecisionResult(action: "ask_author", arguments: AgentDecisionArguments(query: "需要确认时间线"), reason: "缺证据", stop: false)
        ]
        let store = try WorkshopStore(database: database, aiClient: executor)
        store.setAgentLabEnabled(true)
        store.apiKeyInput = "fake-key"
        store.ideaInput = "一个想法"

        await store.startAgentSession()
        XCTAssertNotNil(store.agentSessionAskAuthor)
        let callsBeforeFinish = executor.callCounts["agent-decision-native"] ?? 0

        await store.finishAgentSessionNow()

        XCTAssertNil(store.agentSessionAskAuthor)
        let pending = try XCTUnwrap(store.pendingDraftReview)
        XCTAssertEqual(pending.agentSessionSummary?.first, "共 0 步，停止原因：作者选择结束会话，交付当前最好版本")
        XCTAssertEqual(executor.callCounts["agent-decision-native"], callsBeforeFinish, "就此结束不应再消耗模型调用")
    }

    func testResumingPausedAgentCannotOverwriteContentEditedAfterPause() async throws {
        let database = try makeDatabase()
        let executor = DecisionScriptedExecutor()
        executor.decisions = [
            AgentDecisionResult(
                action: "ask_author",
                arguments: AgentDecisionArguments(query: "请补充素材"),
                reason: "缺证据",
                stop: false
            )
        ]
        let store = try WorkshopStore(database: database, aiClient: executor)
        store.setAgentLabEnabled(true)
        store.apiKeyInput = "fake-key"
        store.ideaInput = "一个想法"
        store.content = "暂停前正文"

        await store.startAgentSession()
        XCTAssertNotNil(store.agentSessionAskAuthor)

        store.content = "作者在暂停后重写的正文"
        executor.decisions = [
            AgentDecisionResult(action: "finish", reason: "结束", stop: true)
        ]
        await store.resumeAgentSession()

        XCTAssertEqual(store.content, "作者在暂停后重写的正文")
        XCTAssertNil(store.pendingDraftReview, "旧代理状态不得覆盖暂停后的正文编辑")
        XCTAssertNil(store.agentSessionAskAuthor, "冲突的暂停句柄应失效，避免反复误用")
        XCTAssertTrue(store.statusText.contains("旧代理会话已安全丢弃"))
    }

    func testFinishingPausedAgentCannotOverwriteContentEditedAfterPause() async throws {
        let database = try makeDatabase()
        let executor = DecisionScriptedExecutor()
        executor.decisions = [
            AgentDecisionResult(
                action: "ask_author",
                arguments: AgentDecisionArguments(query: "请确认正文"),
                reason: "需作者确认",
                stop: false
            )
        ]
        let store = try WorkshopStore(database: database, aiClient: executor)
        store.setAgentLabEnabled(true)
        store.apiKeyInput = "fake-key"
        store.ideaInput = "一个想法"
        store.content = "暂停前正文"

        await store.startAgentSession()
        XCTAssertNotNil(store.agentSessionAskAuthor)

        store.content = "作者保留的新正文"
        await store.finishAgentSessionNow()

        XCTAssertEqual(store.content, "作者保留的新正文")
        XCTAssertNil(store.pendingDraftReview)
        XCTAssertNil(store.agentSessionAskAuthor)
        XCTAssertTrue(store.statusText.contains("旧代理结果已安全丢弃"))
    }

    /// PRD 23.8.1 验收标准 3：会话内 search_materials 命中的素材应能在交付的待复核卡片上看到（retrievedFragments）。
    func testAgentSessionSearchMaterialsSurfacesRetrievedFragmentsOnPendingReview() async throws {
        let database = try makeDatabase()
        _ = try database.saveIdea(
            id: nil,
            payload: IdeaSaveRequest(
                title: "成都茶馆",
                content: "在成都茶馆里，时间慢下来，人和人的关系不靠饭局，而靠长期信任。",
                type: "素材",
                tags: ["成都"],
                used: 0,
                related_article_id: nil
            )
        )
        let executor = DecisionScriptedExecutor()
        executor.decisions = [
            AgentDecisionResult(
                action: "search_materials",
                arguments: AgentDecisionArguments(query: "成都 长期 信任"),
                reason: "先检索本地素材",
                stop: false
            ),
            AgentDecisionResult(action: "finish", reason: "已经足够", stop: true)
        ]
        let store = try WorkshopStore(database: database, aiClient: executor)
        store.setAgentLabEnabled(true)
        store.apiKeyInput = "fake-key"
        store.ideaInput = "一个想法"

        await store.startAgentSession()

        let pending = try XCTUnwrap(store.pendingDraftReview, "finish 应把最终稿交付待复核")
        let fragments = try XCTUnwrap(pending.retrievedFragments)
        XCTAssertFalse(fragments.isEmpty, "search_materials 命中的素材应出现在待复核卡片的引用轨迹里")
        XCTAssertEqual(fragments.first?.source_type, "idea")
    }

    func testReviewGuardUsesInjectedAIOnlyAfterConfirmation() async throws {
        let database = try makeDatabase()
        let ai = FakeAIClient()
        let store = try WorkshopStore(database: database, aiClient: ai)
        store.title = "一篇文章"
        store.summary = ""
        store.content = "正文"
        store.outline = ""
        store.ideaInput = ""

        store.latestReview = try database.saveWritingReview(
            result: WritingReviewResult(
                summary: "旧诊断",
                overall_score: 70,
                strengths: [],
                issues: [],
                revision_plan: [],
                training_focus: [],
                style_notes: [],
                raw_output: nil
            ),
            articleID: nil,
            titleSnapshot: store.title,
            model: "fake",
            reviewedSnapshot: ["一篇文章", "", "正文", "", ""].joined(separator: "\u{1F}")
        )

        await store.reviewCurrentDraft()

        XCTAssertTrue(store.showUnchangedReviewPrompt)
        XCTAssertEqual(ai.writingReviewCallCount, 0)

        await store.confirmReviewDespiteNoChange()

        XCTAssertFalse(store.showUnchangedReviewPrompt)
        XCTAssertEqual(ai.writingReviewCallCount, 1)
        XCTAssertEqual(store.latestReview?.summary, "假 AI 诊断")
    }

    func testPendingDraftReviewCanConfirmAndDiscardWithRealDatabase() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        let before = DraftSnapshot(title: "旧标题", summary: "", content: "旧正文")
        let after = DraftSnapshot(title: "新标题", summary: "", content: "新正文")
        let version = try database.saveDraftVersion(
            articleID: nil,
            titleSnapshot: "新标题",
            action: "测试待复核",
            note: nil,
            before: before,
            after: after,
            reviewStatus: "pending"
        )
        store.draftVersions = [version]
        store.applySnapshot(before)
        try store.writingSession.stage(PendingDraftReview(
            draftVersionID: version.id,
            actionTitle: "测试待复核",
            articleID: nil,
            before: before,
            after: after,
            note: nil,
            usedFallback: false,
            selfCheck: nil,
            matchedPitfalls: [],
            agentTrace: nil,
            retrievedFragments: nil,
            iterationSummary: nil,
            candidateJudgement: nil
        ), expectedRevision: store.writingSession.state.revision)

        await store.confirmPendingDraftReview()

        XCTAssertNil(store.pendingDraftReview)
        XCTAssertEqual(try database.listDraftVersions(limit: 1).first?.review_status, "confirmed")

        let discardVersion = try database.saveDraftVersion(
            articleID: nil,
            titleSnapshot: "新标题",
            action: "测试放弃",
            note: nil,
            before: before,
            after: after,
            reviewStatus: "pending"
        )
        store.applySnapshot(before)
        store.draftVersions = [discardVersion]
        try store.writingSession.stage(PendingDraftReview(
            draftVersionID: discardVersion.id,
            actionTitle: "测试放弃",
            articleID: nil,
            before: before,
            after: after,
            note: nil,
            usedFallback: false,
            selfCheck: nil,
            matchedPitfalls: [],
            agentTrace: nil,
            retrievedFragments: nil,
            iterationSummary: nil,
            candidateJudgement: nil
        ), expectedRevision: store.writingSession.state.revision)

        await store.discardPendingDraftReview()

        XCTAssertNil(store.pendingDraftReview)
        XCTAssertEqual(store.content, before.content)
        XCTAssertTrue(try database.listDraftVersions().allSatisfy { $0.id != discardVersion.id })
    }

    func testDiscardPersistenceFailureKeepsPendingPreviewAndDoesNotProjectSuccess() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        let before = DraftSnapshot(title: "旧标题", summary: "旧摘要", content: "旧正文")
        let after = DraftSnapshot(title: "候选标题", summary: "候选摘要", content: "候选正文")
        store.applySnapshot(before)
        let outcome = try store.writingWorkflow.execute(.deliverPending(.init(
            articleID: nil,
            titleSnapshot: "候选标题",
            actionTitle: "故障注入",
            before: before,
            after: after,
            usedFallback: false
        )))
        guard case let .pendingDelivered(version, pending) = outcome else {
            return XCTFail("应先交付待复核版本")
        }
        try store.writingSession.stage(pending, expectedRevision: store.writingSession.state.revision)
        store.draftVersions = [version]

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE draft_versions", nil, nil, nil), SQLITE_OK)

        await store.discardPendingDraftReview()

        XCTAssertEqual(store.pendingDraftReview?.draftVersionID, version.id)
        XCTAssertEqual(store.content, after.content, "数据库失败时不得先回退正文")
        XCTAssertFalse(store.statusText.contains("已放弃"), "失败不得投影为成功")
    }

    func testPolishRejectsLateCandidateAfterAuthorEditsDuringModelRun() async throws {
        let database = try makeDatabase()
        let ai = SlowFakeAIClient(delayNanoseconds: 80_000_000)
        let store = try WorkshopStore(database: database, aiClient: ai)
        store.title = "原标题"
        store.content = "原正文"

        let task = Task { await store.polishDraft(.natural) }
        try await Task.sleep(nanoseconds: 20_000_000)
        store.materials = "模型运行期间新增的素材"
        await task.value

        XCTAssertNil(store.pendingDraftReview)
        XCTAssertEqual(store.content, "原正文")
        XCTAssertEqual(store.materials, "模型运行期间新增的素材")
        XCTAssertTrue(
            try database.listDraftVersions().allSatisfy { $0.review_status != "pending" },
            "陈旧结果被拒绝后，补偿清理不得留下孤儿 pending 行"
        )
    }

    func testIssueRewriteRejectsApplyingWhenContentChanged() async throws {
        let database = try makeDatabase()
        let ai = FakeAIClient()
        let store = try WorkshopStore(database: database, aiClient: ai)
        store.title = "标题"
        store.content = "这里有一段需要修改的正文。"

        let issue = WritingReviewIssue(
            dimension: "表达",
            severity: "中",
            excerpt: "一段需要修改",
            problem: "表达生硬",
            suggestion: "改得自然一点"
        )

        await store.rewriteFromIssue(issue)

        XCTAssertEqual(ai.rewriteCallCount, 1)
        XCTAssertNotNil(store.pendingIssueRewrite)

        store.content = "正文已经被手工改过。"
        await store.confirmPendingIssueRewrite()

        XCTAssertNil(store.pendingIssueRewrite)
        XCTAssertTrue(store.statusText.contains("正文已变化"))
    }

    func testAuditIssueCanEnterPendingRewriteFlow() async throws {
        let database = try makeDatabase()
        let ai = FakeAIClient()
        let store = try WorkshopStore(database: database, aiClient: ai)
        store.title = "标题"
        store.content = "这里有一个葬花呤错字。"
        let issue = AuditIssue(category: "错字", severity: "中", excerpt: "葬花呤", problem: "疑似错字", suggestion: "改为葬花吟")

        XCTAssertTrue(store.canLocateAuditIssue(issue))
        await store.rewriteFromAuditIssue(issue)

        XCTAssertEqual(ai.rewriteCallCount, 1)
        XCTAssertNotNil(store.pendingIssueRewrite)
        XCTAssertEqual(store.pendingIssueRewrite?.issue.dimension, "错字")
        XCTAssertEqual(store.content, "这里有一个葬花呤错字。")
    }

    func testPrePublishAuditCoordinatorPersistsLocalQuoteFindings() async throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "标题",
                content: "文中引用：“这是一句需要核对的引文”。",
                summary: "",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )
        let output = try await PrePublishAuditCoordinator(aiClient: FakeAIClient(), database: database).run(
            PrePublishAuditInput(
                articleID: article.id,
                title: article.displayTitle,
                summary: "",
                content: article.content ?? "",
                style: try database.defaultStyle(),
                template: nil,
                config: ModelConfig(),
                apiKey: "fake-key",
                model: "fake-model"
            )
        )

        XCTAssertTrue(output.note.contains("终审提示"))
        XCTAssertEqual(output.audit?.issues.first?.category, "引文核对")
        XCTAssertEqual(try database.listArticles().first?.audit_report?.quote_issues?.first?.excerpt, "这是一句需要核对的引文")
    }

    func testSavingNewPublishedArticleRunsAuditAndPublishingMetrics() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        let version = try database.saveDraftVersion(
            articleID: nil,
            titleSnapshot: "新发布文章",
            action: "代理生成初稿",
            note: nil,
            before: DraftSnapshot(title: "", summary: "", content: ""),
            after: DraftSnapshot(title: "新发布文章", summary: "", content: "AI 确认稿"),
            reviewStatus: "confirmed"
        )
        store.title = "新发布文章"
        store.content = "AI 确认稿，发布前补了一句。"
        store.articleStatus = "已发布"

        await store.saveArticle()

        let article = try XCTUnwrap(database.listArticles().first)
        XCTAssertEqual(article.status, "已发布")
        XCTAssertNotNil(article.audit_report)
        XCTAssertEqual(try database.listEditRecords(limit: 10).first?.draft_version_id, version.id)
        XCTAssertEqual(store.latestPrePublishAudit?.article_id, article.id)
        XCTAssertEqual(store.editRecordStats?.total, 1)
    }

    /// 保存也要可回退：覆盖已存文章时自动记一条「保存文章」版本，「恢复前」即可回到保存前定稿；
    /// 首次保存与内容未变的重复保存不记版本，避免版本列表被噪音刷屏。
    func testOverwritingSaveRecordsRestorableVersion() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        store.title = "造船"
        store.content = "好版本"

        await store.saveArticle()
        let articleID = try XCTUnwrap(store.selectedArticleID)
        XCTAssertTrue(try database.listDraftVersions(articleID: articleID, limit: 8).isEmpty, "首次保存没有旧稿可回退，不应记版本")

        store.content = "降质版本"
        await store.saveArticle()

        let version = try XCTUnwrap(try database.listDraftVersions(articleID: articleID, limit: 8).first)
        XCTAssertEqual(version.action, "保存文章")
        XCTAssertEqual(version.before_content, "好版本")
        XCTAssertEqual(version.after_content, "降质版本")

        await store.saveArticle()
        XCTAssertEqual(try database.listDraftVersions(articleID: articleID, limit: 8).count, 1, "内容未变的重复保存不应新增版本")

        store.restoreDraftVersionBefore(version)
        XCTAssertEqual(store.content, "好版本")
    }

    func testQuickDraftCircuitBreaksWhenSectionDraftStepFailsAndSkipsCritique() async throws {
        let database = try makeDatabase()
        let executor = ScriptedAgentExecutor()
        executor.results["agent-draft-sections-native"] = ScriptedAgentExecutor.StepResult(success: false, error: "网络失败")
        let store = try WorkshopStore(database: database, aiClient: executor)
        store.ideaInput = "一个想法"
        store.content = "已有正文"

        await store.quickDraft()

        // 素材为空时本地兜底论点检查总会标出缺证据项，触发一轮 Brief 修订（PRD 22.2.1），
        // 分段成稿因此变成第 4 步，而不是没有修订步骤时的第 3 步。
        XCTAssertEqual(executor.callCounts["agent-draft-brief-revision-native"] ?? 0, 1)
        XCTAssertEqual(executor.callCounts["agent-draft-critique-native"] ?? 0, 0)
        XCTAssertNil(store.pendingDraftReview)
        XCTAssertEqual(store.content, "已有正文")
        XCTAssertTrue(store.statusText.contains("第 4 步"))
        XCTAssertTrue(store.statusText.contains("网络失败"))
    }

    func testQuickDraftUsesFallbackAllTheWayWhenAPIKeyMissing() async throws {
        let database = try makeDatabase()
        let executor = ScriptedAgentExecutor()
        let missingKeyMessage = NativeAIError.missingAPIKeyMessage
        for endpoint in [
            "agent-draft-brief-native",
            "agent-draft-argument-check-native",
            "agent-draft-sections-native",
            "agent-draft-critique-native"
        ] {
            executor.results[endpoint] = ScriptedAgentExecutor.StepResult(success: false, error: missingKeyMessage)
        }
        let store = try WorkshopStore(database: database, aiClient: executor)
        store.ideaInput = "一个想法"

        await store.quickDraft()

        XCTAssertEqual(executor.callCounts["agent-draft-critique-native"] ?? 0, 1)
        XCTAssertNotNil(store.pendingDraftReview)
        XCTAssertEqual(store.pendingDraftReview?.usedFallback, true)
    }

    /// 22.3.4：候选评委的呈现顺序应被打乱以消除位置偏置，但候选编号必须可注入固定种子复现，
    /// 且编号与内容的对应关系不能因为打乱呈现顺序而丢失。
    func testGenerateDraftAlternativesShufflesPresentationOrderReproducibleWithSeed() async throws {
        let content = "这是正文第一段，用于测试候选评委顺序随机化的功能是否正确工作。"

        let database1 = try makeDatabase()
        let store1 = try WorkshopStore(database: database1, aiClient: FakeAIClient(), candidateShuffleRNG: SeededRNG(seed: 42))
        store1.title = "标题"
        store1.content = content
        await store1.generateDraftAlternatives()

        let database2 = try makeDatabase()
        let store2 = try WorkshopStore(database: database2, aiClient: FakeAIClient(), candidateShuffleRNG: SeededRNG(seed: 42))
        store2.title = "标题"
        store2.content = content
        await store2.generateDraftAlternatives()

        let orderLine1 = try presentationOrderLine(from: store1)
        let orderLine2 = try presentationOrderLine(from: store2)

        XCTAssertEqual(orderLine1, orderLine2, "相同随机种子应复现相同的候选呈现顺序")

        let indices = orderLine1
            .replacingOccurrences(of: "呈现顺序：", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }
        XCTAssertEqual(Set(indices), Set([1, 2, 3]), "打乱的应是呈现顺序，候选编号本身不应丢失或重复")

        // 深加工版（编号 3）内容最长、段落最完整，本地兜底评委总会选它；
        // 无论呈现顺序如何打乱，评委按编号解析 best_candidate_index，因此这里应始终稳定选中候选 3——
        // 如果打乱顺序时把编号也搞乱了，这里就会选错。
        XCTAssertTrue(store1.statusText.contains("候选 3"))
        XCTAssertTrue(store2.statusText.contains("候选 3"))
    }

    /// 23.5：generate_topics 成功后暂停等待作者确认待复核产物，确认后应自动继续下一步并整体完成。
    func testExecuteAdvisorPlanPausesForPendingReviewThenContinuesOnConfirm() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        store.ideaInput = "一个想法"
        store.latestAdvisorRun = try makeAdvisorRun(database: database, actions: ["quick_draft", "writing_review"])

        let planTask = Task { await store.executeAdvisorPlan() }
        try await waitUntil(timeout: 2) { store.pendingDraftReview != nil }

        XCTAssertEqual(store.advisorPlanProgress?.currentAction, .quickDraft)
        XCTAssertFalse(store.agentRuns.contains { $0.run_type == "写作诊断" })

        await store.confirmPendingDraftReview()
        await planTask.value

        XCTAssertNil(store.advisorPlanProgress)
        XCTAssertEqual(store.statusText, "计划执行完成")
        XCTAssertTrue(store.agentRuns.contains { $0.run_type == "写作诊断" })
        let planRun = try XCTUnwrap(store.agentRuns.first { $0.run_type == "按计划执行" })
        XCTAssertEqual(planRun.session_kind, "plan_execution")
        XCTAssertEqual(planRun.status, "success")
        XCTAssertEqual(planRun.steps.map(\.status), ["success", "success"])
    }

    /// 23.5：作者放弃待复核产物时，整个计划序列必须停止，不得继续后续步骤。
    func testExecuteAdvisorPlanStopsWhenAuthorDiscardsPendingReview() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        store.ideaInput = "一个想法"
        store.latestAdvisorRun = try makeAdvisorRun(database: database, actions: ["quick_draft", "writing_review"])

        let planTask = Task { await store.executeAdvisorPlan() }
        try await waitUntil(timeout: 2) { store.pendingDraftReview != nil }

        await store.discardPendingDraftReview()
        await planTask.value

        XCTAssertNil(store.advisorPlanProgress)
        XCTAssertTrue(store.statusText.contains("计划已停止"))
        XCTAssertFalse(store.agentRuns.contains { $0.run_type == "写作诊断" }, "被放弃后不应继续执行后续步骤")
        let planRun = try XCTUnwrap(store.agentRuns.first { $0.run_type == "按计划执行" })
        XCTAssertEqual(planRun.status, "fallback")
        XCTAssertEqual(planRun.steps.map(\.status), ["abandoned"])
    }

    /// 23.5：中途某步失败时序列必须停止并保留已完成步骤的产物，且不得继续执行后续步骤。
    func testExecuteAdvisorPlanStopsAtFailedStepAndKeepsCompletedStepResults() async throws {
        let database = try makeDatabase()
        let executor = ScriptedAgentExecutor()
        executor.results["agent-draft-sections-native"] = ScriptedAgentExecutor.StepResult(success: false, error: "网络失败")
        let store = try WorkshopStore(database: database, aiClient: executor)
        store.ideaInput = "一个想法"
        store.latestAdvisorRun = try makeAdvisorRun(database: database, actions: ["generate_topics", "quick_draft", "writing_review"])

        await store.executeAdvisorPlan()

        XCTAssertNil(store.advisorPlanProgress)
        XCTAssertTrue(store.statusText.contains("第 2 步"))
        XCTAssertTrue(store.statusText.contains("失败"))
        XCTAssertTrue(store.agentRuns.contains { $0.run_type == "生成选题" }, "第一步已完成，产物应保留")
        XCTAssertFalse(store.agentRuns.contains { $0.run_type == "写作诊断" }, "第三步不应被执行")
        let planRun = try XCTUnwrap(store.agentRuns.first { $0.run_type == "按计划执行" })
        XCTAssertEqual(planRun.status, "fallback")
        XCTAssertEqual(planRun.steps.map(\.status), ["success", "failed"])
    }

    /// 23.5：沿用现有取消机制——正在执行的某一步被全局"取消"按钮打断时，整个计划必须立即停止，
    /// 不得继续执行后续步骤，且不属于"失败"（不应出现"失败"字样，应体现为取消）。
    func testExecuteAdvisorPlanStopsImmediatelyWhenCurrentStepIsCancelled() async throws {
        let database = try makeDatabase()
        let ai = SlowFakeAIClient(delayNanoseconds: 200_000_000)
        let store = try WorkshopStore(database: database, aiClient: ai)
        store.ideaInput = "一个想法"
        store.latestAdvisorRun = try makeAdvisorRun(database: database, actions: ["generate_outline", "draft_from_outline"])

        let planTask = Task { await store.executeAdvisorPlan() }
        try await waitUntil(timeout: 2) { store.canCancelCurrentOperation }
        store.cancelCurrentOperation()
        await planTask.value

        XCTAssertNil(store.advisorPlanProgress)
        XCTAssertFalse(store.statusText.contains("失败"))
        XCTAssertFalse(store.agentRuns.contains { $0.run_type == "大纲成稿" }, "被取消后不应继续执行后续步骤")
        let planRun = try XCTUnwrap(store.agentRuns.first { $0.run_type == "按计划执行" })
        XCTAssertEqual(planRun.status, "fallback")
        XCTAssertEqual(planRun.steps.map(\.status), ["cancelled"])
    }

    private func makeAdvisorRun(database: NativeDatabase, actions: [String]) throws -> WritingAdvisorRun {
        try database.saveWritingAdvisorRun(
            result: WritingAdvisorResult(
                stage: "初稿阶段",
                main_problem: "缺少场景",
                next_action: "先诊断",
                reason: "测试用固定建议",
                suggested_actions: actions,
                focus_area: nil,
                context_findings: [],
                execution_plan: [],
                risk_notes: [],
                raw_output: nil
            ),
            context: ContextPackage(
                stage: "初稿阶段",
                title: "",
                summary: "",
                idea: "一个想法",
                direction: "情感文学",
                outline_excerpt: "",
                content_excerpt: "",
                materials_excerpt: "",
                selected_topic_title: nil,
                selected_topic_summary: nil,
                style_name: "默认",
                style_brief: "克制",
                word_count: 0,
                paragraph_count: 0,
                material_count: 0,
                recent_article_titles: [],
                recent_training_focus: [],
                recent_issues: []
            ),
            articleID: nil,
            titleSnapshot: "",
            model: "fake-model"
        )
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("等待条件超时")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func presentationOrderLine(from store: WorkshopStore) throws -> String {
        let steps = try XCTUnwrap(store.agentRuns.first?.steps)
        let judgeStep = try XCTUnwrap(steps.first { $0.name == "候选评委排序" })
        let inputSummary = try XCTUnwrap(judgeStep.input_summary)
        return try XCTUnwrap(inputSummary.components(separatedBy: "\n---\n").first)
    }

    /// 写作方向下拉候选：风格档案体裁在前，文章体裁按出现顺序补充，内置项兜底，全程去重去空白。
    func testKnownDirectionsDeduplicatesProfileArticleAndBuiltinGenres() throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())

        store.styleProfiles = [
            StyleProfile(id: 1, name: "情感", genre: "情感文学"),
            StyleProfile(id: 2, name: "解读", genre: "文学原著")
        ]
        store.articles = [
            Article(id: 1, genre: "文学原著"),
            Article(id: 2, genre: " 科研技术 "),
            Article(id: 3, genre: nil)
        ]

        XCTAssertEqual(
            store.knownDirections,
            ["情感文学", "文学原著", "科研技术", "原著解读", "技术分享"]
        )
    }

    // MARK: - 24.1 发布流程引导

    func testArchiveRequestOnUnpublishedArticleShowsPromptAndKeepsStatus() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(title: "未发布文章", content: "正文", summary: "", status: "草稿", tags: [], related_topic_id: nil, genre: nil)
        )
        store.articles = try database.listArticles()
        store.selectedArticleID = article.id
        store.articleStatus = "草稿"

        await store.requestArticleStatusChange("已归档")

        XCTAssertTrue(store.showArchiveWithoutPublishPrompt, "未发布直接归档应先确认")
        XCTAssertEqual(try database.listArticles().first?.status, "草稿", "确认前状态不得变化")
    }

    func testArchiveAfterPublishingRunsAuditMetricsThenArchives() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(title: "补发布文章", content: "AI 确认稿，发布前补了一句。", summary: "", status: "草稿", tags: [], related_topic_id: nil, genre: nil)
        )
        _ = try database.saveDraftVersion(
            articleID: article.id,
            titleSnapshot: "补发布文章",
            action: "代理生成初稿",
            note: nil,
            before: DraftSnapshot(title: "", summary: "", content: ""),
            after: DraftSnapshot(title: "补发布文章", summary: "", content: "AI 确认稿"),
            reviewStatus: "confirmed"
        )
        store.articles = try database.listArticles()
        store.selectedArticleID = article.id
        store.title = "补发布文章"
        store.content = "AI 确认稿，发布前补了一句。"
        store.showArchiveWithoutPublishPrompt = true

        await store.archiveAfterPublishing()

        XCTAssertFalse(store.showArchiveWithoutPublishPrompt)
        XCTAssertEqual(try database.listArticles().first?.status, "已归档", "组合动作最终应归档")
        XCTAssertEqual(try database.listEditRecords(limit: 5).count, 1, "发布环节必须记录编辑量（北极星）")
        XCTAssertNotNil(store.latestPrePublishAudit, "发布环节必须跑发表前终审")
    }

    func testArchiveRequestOnPublishedArticleSkipsPrompt() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(title: "已发布文章", content: "正文", summary: "", status: "已发布", tags: [], related_topic_id: nil, genre: nil)
        )
        store.articles = try database.listArticles()
        store.selectedArticleID = article.id
        store.articleStatus = "已发布"

        await store.requestArticleStatusChange("已归档")

        XCTAssertFalse(store.showArchiveWithoutPublishPrompt, "已发布过的文章归档不应打扰")
        XCTAssertEqual(try database.listArticles().first?.status, "已归档")
    }

    func testPublishFlowStageIndexFollowsDraftState() throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())

        XCTAssertEqual(store.publishFlowStageIndex, 0, "空稿 = 构思")
        store.content = "有正文了。"
        XCTAssertEqual(store.publishFlowStageIndex, 1, "有正文 = 初稿")
        let staged = PendingDraftReview(
            draftVersionID: 1, actionTitle: "测试", articleID: nil,
            before: store.currentDraftSnapshot(),
            after: DraftSnapshot(title: "", summary: "", content: "x"),
            note: nil, usedFallback: false, selfCheck: nil, matchedPitfalls: [],
            agentTrace: nil, retrievedFragments: nil, sectionFragmentContexts: nil,
            iterationSummary: nil, candidateJudgement: nil
        )
        try store.writingSession.stage(staged, expectedRevision: store.writingSession.state.revision)
        XCTAssertEqual(store.publishFlowStageIndex, 2, "存在待复核 = 待复核站")
        try store.writingSession.didConfirmPendingDraftReview(versionID: staged.draftVersionID)
        store.articleStatus = "已发布"
        XCTAssertEqual(store.publishFlowStageIndex, 3)
        store.articleStatus = "已归档"
        XCTAssertEqual(store.publishFlowStageIndex, 4)
    }

    /// PRD 24.8：编辑量只记「非已发布 → 已发布」这一次跃迁。
    /// 已发布状态下再点更新状态/保存会重复计数——作者首次发布香菱时一次发布记出 7 条零改动。
    func testEditRecordIsWrittenOncePerPublishTransition() async throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "叹香菱",
                content: "作者手改后的正文",
                summary: "摘要",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: "文学原著"
            )
        )
        _ = try database.saveDraftVersion(
            articleID: article.id,
            titleSnapshot: "叹香菱",
            action: "按诊断改全文",
            note: "",
            before: DraftSnapshot(title: "叹香菱", summary: "摘要", content: "旧正文"),
            after: DraftSnapshot(title: "叹香菱", summary: "摘要", content: "模型改写后的正文")
        )
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        store.selectedArticleID = article.id

        await store.updateSelectedArticleStatus("已发布")
        XCTAssertEqual(try database.listEditRecords(limit: 10).count, 1, "首次发布应记一条")

        // 已经是"已发布"了，再点几次更新状态不应继续追加。
        await store.updateSelectedArticleStatus("已发布")
        await store.updateSelectedArticleStatus("已发布")
        XCTAssertEqual(try database.listEditRecords(limit: 10).count, 1, "重复发布不得重复计数")

        // 归档再发布是一次新的跃迁，应当再记一条。
        await store.updateSelectedArticleStatus("已归档")
        await store.updateSelectedArticleStatus("已发布")
        XCTAssertEqual(try database.listEditRecords(limit: 10).count, 2)
    }

    /// PRD 24.6：few-shot 样本必须是**完成稿**且**体裁同族**。
    /// 24.3 只给"精确匹配落空"的兜底分支加了"草稿不参与"，精确命中的主路径照旧会把
    /// 改到一半的草稿当风格范本；兜底又会跨体裁取到技术文，教出错的腔调。
    func testResolveStyleSkipsDraftsAndCrossFamilyArticlesWhenPickingSamples() throws {
        let database = try makeDatabase()
        for (title, genre, status) in [
            ("哀牢山地理志", "技术分享", "已归档"),
            ("惯养娇生笑你痴", "情感文学", "草稿"),
            ("晴雯钻被窝", "情感文学", "已归档")
        ] {
            _ = try database.saveArticle(
                id: nil,
                payload: ArticleSaveRequest(
                    title: title,
                    content: "\(title)的正文",
                    summary: "摘要",
                    status: status,
                    tags: [],
                    related_topic_id: nil,
                    genre: genre
                )
            )
        }
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        // 作者真实用的方向写法，与库里任何一篇的 genre 都不精确相等。
        store.writingDirection = "经典文学解读"

        let style = try store.resolveStyle()

        let samples = style.sample_texts ?? []
        XCTAssertEqual(samples.count, 1, "只有《晴雯钻被窝》够格：完成稿 + 体裁同族")
        XCTAssertTrue(samples.contains { $0.contains("晴雯钻被窝") })
        XCTAssertFalse(samples.contains { $0.contains("惯养娇生笑你痴") }, "草稿不能当风格范本")
        XCTAssertFalse(samples.contains { $0.contains("哀牢山地理志") }, "技术文会教出错的腔调")
    }

    /// 24.9-P1：注入了哪几篇样本、命中哪一档，必须随待复核卡上屏。24.6 的残留边界写的是
    /// 「App 界面上仍然看不见，作者只能查库」——这条测试钉住它已经看得见。
    func testGeneratedDraftCarriesStyleSampleProvenanceToPendingReview() async throws {
        let database = try makeDatabase()
        for (title, genre, status) in [
            ("哀牢山地理志", "技术分享", "已归档"),
            ("惯养娇生笑你痴", "情感文学", "草稿"),
            ("晴雯钻被窝", "情感文学", "已归档"),
            ("叹香菱", "情感文学", "已发布")
        ] {
            _ = try database.saveArticle(
                id: nil,
                payload: ArticleSaveRequest(
                    title: title,
                    content: "\(title)的正文",
                    summary: "摘要",
                    status: status,
                    tags: [],
                    related_topic_id: nil,
                    genre: genre
                )
            )
        }
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        store.writingDirection = "情感文学"
        store.ideaInput = "一个想法"
        store.title = "标题"
        store.content = "已有一版正文，用于触发全文润色并交付待复核。"

        await store.polishDraft(.natural)

        let pending = try XCTUnwrap(store.pendingDraftReview)
        let samples = try XCTUnwrap(pending.styleSamples, "待复核卡必须带上本次注入的样本出处")
        XCTAssertEqual(samples.tierLabel, "体裁精确匹配")
        // 顺序不是契约（取决于库内近期排序），"是哪几篇"才是：两篇完成稿都在，草稿与技术文都不在。
        XCTAssertEqual(Set(samples.titles), ["叹香菱", "晴雯钻被窝"], "只取同体裁完成稿")
        XCTAssertFalse(samples.titles.contains("惯养娇生笑你痴"), "草稿不能当风格范本")
        XCTAssertFalse(samples.titles.contains("哀牢山地理志"), "技术文会教出错的腔调")
        XCTAssertFalse(samples.usedDraftFallback)
        XCTAssertTrue(samples.summaryLine.contains("叹香菱"), "界面那一行要写明篇名：\(samples.summaryLine)")
    }

    /// 一篇完成稿都没有时退到草稿——界面必须标出来，否则作者以为读的是自己的成品腔调。
    func testStyleSampleProvenanceFlagsDraftFallback() throws {
        let database = try makeDatabase()
        _ = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "改到一半的稿",
                content: "半成品正文",
                summary: "摘要",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: "情感文学"
            )
        )
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        store.writingDirection = "情感文学"

        _ = try store.resolveStyle()

        let samples = try XCTUnwrap(store.lastStyleSampleProvenance)
        XCTAssertTrue(samples.usedDraftFallback, "全是草稿时必须标明草稿兜底")
        XCTAssertEqual(samples.titles, ["改到一半的稿"])
        XCTAssertTrue(samples.summaryLine.contains("草稿兜底"), samples.summaryLine)
    }

    private func makeDatabase() throws -> NativeDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try NativeDatabase(databaseURL: directory.appending(path: "creative_workshop.sqlite3"))
    }

}

/// 固定种子的确定性随机源，用于验证候选评委呈现顺序在相同种子下可复现（22.3.4）。
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class FakeAIClient: AIWorkflowExecuting {
    var writingReviewCallCount = 0
    var rewriteCallCount = 0
    var improveDraftCallCount = 0
    var writingReviewResponses: [WritingReviewResponse] = []
    var improveDraftResponses: [DraftResponse] = []

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        switch descriptor.kind {
        case .writingReview:
            writingReviewCallCount += 1
            if !writingReviewResponses.isEmpty {
                let response = writingReviewResponses.removeFirst()
                return run(response.result, success: response.success == true, error: response.error ?? "", inputSummary: response.input_summary ?? "fake", outputSummary: response.output_summary ?? "fake")
            }
            return run(WritingReviewResult(
                summary: "假 AI 诊断",
                overall_score: 82,
                strengths: ["方向清楚"],
                issues: [],
                revision_plan: [],
                training_focus: [],
                style_notes: [],
                raw_output: nil
            ))
        case .improveFromReview:
            improveDraftCallCount += 1
            if !improveDraftResponses.isEmpty {
                let response = improveDraftResponses.removeFirst()
                return run(response.result, success: response.success == true, error: response.error ?? "", inputSummary: response.input_summary ?? "fake", outputSummary: response.output_summary ?? "fake")
            }
            return run(descriptor.fallback())
        case .rewriteSelection:
            rewriteCallCount += 1
            return run(RewriteResult(replacement: "改写后的片段", note: "fake", raw_output: nil))
        default:
            return run(descriptor.fallback())
        }
    }

    private func run<Value: Codable, Output: Codable>(
        _ value: Value,
        success: Bool = true,
        error: String = "",
        inputSummary: String = "fake",
        outputSummary: String = "fake"
    ) -> AIRun<Output> {
        guard let result = value as? Output else {
            fatalError("FakeAIClient returned \(Value.self) for \(Output.self)")
        }
        return AIRun(
            result: result,
            elapsedMS: 1,
            success: success,
            error: error,
            inputSummary: inputSummary,
            outputSummary: outputSummary
        )
    }
}

/// 按 `endpoint` 精确控制每一步成败的假执行器，用于验证 AgentDraftCoordinator 的熔断行为。
private final class ScriptedAgentExecutor: AIWorkflowExecuting {
    struct StepResult {
        var success: Bool = true
        var error: String = ""
    }

    private(set) var callCounts: [String: Int] = [:]
    var results: [String: StepResult] = [:]

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        callCounts[descriptor.endpoint, default: 0] += 1
        let outcome = results[descriptor.endpoint] ?? StepResult()
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 1,
            success: outcome.success,
            error: outcome.error,
            inputSummary: "fake",
            outputSummary: "fake"
        )
    }
}

/// 按序脚本化 `agent-decision-native` 端点的返回内容，其余端点原样走 fallback；
/// 用于驱动 WritingAgentCoordinator 在 Store 层的 ask_author 暂停/续跑状态流转（PRD 23.6.5）。
private final class DecisionScriptedExecutor: AIWorkflowExecuting {
    private(set) var callCounts: [String: Int] = [:]
    var decisions: [AgentDecisionResult] = [] {
        didSet { cursor = 0 }
    }
    private var cursor = 0

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        callCounts[descriptor.endpoint, default: 0] += 1
        if descriptor.endpoint == "agent-decision-native", cursor < decisions.count, let result = decisions[cursor] as? Output {
            cursor += 1
            return AIRun(result: result, elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
        }
        return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
    }
}

/// 每次调用都先等待固定延时再返回本地兜底结果，用于给取消操作留出可命中的窗口。
private final class SlowFakeAIClient: AIWorkflowExecuting {
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 1,
            success: true,
            error: "",
            inputSummary: "fake",
            outputSummary: "fake"
        )
    }
}
