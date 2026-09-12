import XCTest
import SQLite3
@testable import CreativeWorkshopCore

@MainActor
final class WritingWorkflowTests: XCTestCase {
    func testPolishOwnsAISequenceAndReturnsOnlyAfterAgentRunAndPendingCommit() async throws {
        let database = try makeDatabase()
        let executor = WorkflowPolishExecutor()
        let workflow = WritingWorkflow(database: database, executor: executor)
        let request = try makePolishRequest(database: database)

        let outcome = try await workflow.polish(request, validateBeforeCommit: {})

        XCTAssertEqual(executor.kinds, [.polishDraft, .draftSelfCheck])
        XCTAssertEqual(outcome.pending.after.content, "工作流生成的润色正文")
        XCTAssertEqual(outcome.version.review_status, "pending")
        XCTAssertEqual(try database.draftVersion(id: outcome.version.id)?.review_status, "pending")
        XCTAssertEqual(try database.listAgentRuns(limit: 10).map(\.id), [outcome.agentRun.id])
    }

    func testPolishValidationFailureWritesNeitherAgentRunNorPending() async throws {
        let database = try makeDatabase()
        let executor = WorkflowPolishExecutor()
        let workflow = WritingWorkflow(database: database, executor: executor)

        do {
            _ = try await workflow.polish(
                makePolishRequest(database: database),
                validateBeforeCommit: { throw TestFailure.staleDraft }
            )
            XCTFail("陈旧会话必须在任何数据库写入前失败")
        } catch TestFailure.staleDraft {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
        XCTAssertTrue(try database.listDraftVersions(limit: 10).isEmpty)
    }

    func testPolishPendingFailureRollsBackAgentRunInSameTransaction() async throws {
        let database = try makeDatabase()
        let executor = WorkflowPolishExecutor()
        let workflow = WritingWorkflow(database: database, executor: executor)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE draft_versions", nil, nil, nil), SQLITE_OK)

        await XCTAssertThrowsErrorAsync {
            _ = try await workflow.polish(
                try self.makePolishRequest(database: database),
                validateBeforeCommit: {}
            )
        }
        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty,
                      "pending 写入失败时 AgentRun 必须随事务回滚")
    }

    func testDeliverPersistsPendingBeforeReturningAndConfirmTransitionsTheSameVersion() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let before = snapshot(title: "旧标题", content: "旧正文")
        let after = snapshot(title: "新标题", content: "新正文")

        let delivered = try workflow.execute(.deliverPending(.init(
            articleID: nil,
            titleSnapshot: "新标题",
            actionTitle: "代理生成初稿",
            note: "候选已生成",
            before: before,
            after: after,
            usedFallback: false
        )))

        guard case let .pendingDelivered(version, review) = delivered else {
            return XCTFail("交付必须返回 pendingDelivered")
        }
        XCTAssertEqual(version.review_status, "pending")
        XCTAssertEqual(review.draftVersionID, version.id)
        XCTAssertEqual(review.after, after)
        XCTAssertEqual(try database.draftVersion(id: version.id)?.review_status, "pending",
                       "返回 outcome 时，pending 行必须已经持久化")

        let confirmed = try workflow.execute(.confirmPending(review))

        guard case let .pendingConfirmed(confirmedVersion) = confirmed else {
            return XCTFail("确认必须返回 pendingConfirmed")
        }
        XCTAssertEqual(confirmedVersion.id, version.id)
        XCTAssertEqual(confirmedVersion.review_status, "confirmed")
        XCTAssertEqual(try database.draftVersion(id: version.id)?.review_status, "confirmed")
    }

    func testDeliverPersistenceFailureThrowsWithoutCreatingProjectablePendingOutcome() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE draft_versions", nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try workflow.execute(.deliverPending(.init(
            articleID: nil,
            titleSnapshot: "文章",
            actionTitle: "生成候选",
            before: snapshot(content: "旧正文"),
            after: snapshot(content: "新正文"),
            usedFallback: false
        ))), "版本持久化失败必须直接抛错，不能返回可供 UI/session 应用的 outcome")
    }

    func testDiscardDeletesPendingBeforeReturningRestoreSnapshot() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let before = snapshot(title: "可恢复标题", content: "可恢复正文")
        let review = try deliveredReview(
            workflow,
            before: before,
            after: snapshot(title: "候选标题", content: "候选正文")
        )

        let discarded = try workflow.execute(.discardPending(review, preservingCurrent: nil))

        guard case let .pendingDiscarded(versionID, restore, preserved) = discarded else {
            return XCTFail("放弃必须返回 pendingDiscarded")
        }
        XCTAssertEqual(versionID, review.draftVersionID)
        XCTAssertEqual(restore, before)
        XCTAssertNil(preserved)
        XCTAssertNil(try database.draftVersion(id: versionID),
                     "返回恢复快照前，pending 行必须已经删除")
    }

    func testResolvedPendingCannotBeDiscardedByAStaleCommand() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let review = try deliveredReview(
            workflow,
            before: snapshot(content: "旧稿"),
            after: snapshot(content: "定稿")
        )

        _ = try workflow.execute(.confirmPending(review))

        XCTAssertThrowsError(try workflow.execute(.discardPending(review, preservingCurrent: nil)))
        XCTAssertEqual(
            try database.draftVersion(id: review.draftVersionID)?.review_status,
            "confirmed",
            "陈旧的放弃命令不得删除已确认事实"
        )
    }

    func testDiscardPreservesManualEditsMadeOnPendingPreview() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let before = snapshot(content: "候选前正文")
        let after = snapshot(content: "模型候选正文")
        let review = try deliveredReview(workflow, before: before, after: after)
        let manuallyEdited = snapshot(content: "作者继续手改的正文")

        let outcome = try workflow.execute(.discardPending(
            review,
            preservingCurrent: manuallyEdited
        ))

        guard case let .pendingDiscarded(_, restore, preserved) = outcome else {
            return XCTFail("放弃必须返回 pendingDiscarded")
        }
        XCTAssertEqual(restore, before)
        let version = try XCTUnwrap(preserved)
        XCTAssertEqual(version.beforeSnapshot, after)
        XCTAssertEqual(version.afterSnapshot, manuallyEdited)
        XCTAssertEqual(version.review_status, "confirmed")
        XCTAssertNil(try database.draftVersion(id: review.draftVersionID))
        XCTAssertEqual(try database.draftVersion(id: version.id)?.after_content, "作者继续手改的正文")
    }

    func testCleanupDeletesPendingButKeepsConfirmedVersion() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let pending = try deliveredReview(
            workflow,
            before: snapshot(content: "甲"),
            after: snapshot(content: "乙")
        )

        let removed = try workflow.execute(.cleanupPending(versionID: pending.draftVersionID))
        guard case let .pendingCleaned(versionID, didRemove) = removed else {
            return XCTFail("清理必须返回 pendingCleaned")
        }
        XCTAssertEqual(versionID, pending.draftVersionID)
        XCTAssertTrue(didRemove)
        XCTAssertNil(try database.draftVersion(id: versionID))

        let confirmed = try deliveredReview(
            workflow,
            before: snapshot(content: "旧稿"),
            after: snapshot(content: "定稿")
        )
        _ = try workflow.execute(.confirmPending(confirmed))

        let kept = try workflow.execute(.cleanupPending(versionID: confirmed.draftVersionID))
        guard case let .pendingCleaned(_, didRemoveConfirmed) = kept else {
            return XCTFail("清理必须返回 pendingCleaned")
        }
        XCTAssertFalse(didRemoveConfirmed)
        XCTAssertEqual(try database.draftVersion(id: confirmed.draftVersionID)?.review_status, "confirmed")
    }

    func testRecordDraftVersionPersistsConfirmedHistory() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let before = snapshot(content: "改写前")
        let after = snapshot(content: "改写后")

        let outcome = try workflow.execute(.recordDraftVersion(.init(
            articleID: nil,
            titleSnapshot: "文章",
            action: "定点改写",
            note: "根据诊断建议改写",
            before: before,
            after: after
        )))

        guard case let .draftVersionRecorded(version) = outcome else {
            return XCTFail("普通版本记录必须返回 draftVersionRecorded")
        }
        XCTAssertEqual(version.review_status, "confirmed")
        XCTAssertEqual(version.beforeSnapshot, before)
        XCTAssertEqual(version.afterSnapshot, after)
        XCTAssertEqual(try database.draftVersion(id: version.id)?.action, "定点改写")
    }

    func testSavingNewArticleAttachesUnassignedVersionsWithoutCreatingManualHistory() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let provisional = try database.saveDraftVersion(
            articleID: nil,
            titleSnapshot: "新文章",
            action: "代理生成初稿",
            note: nil,
            before: snapshot(),
            after: snapshot(title: "新文章", content: "初稿")
        )

        let outcome = try workflow.execute(.saveArticle(.init(
            articleID: nil,
            payload: articlePayload(title: "新文章", content: "初稿")
        )))

        guard case let .articleSaved(article, overwriteVersion, _) = outcome else {
            return XCTFail("保存必须返回 articleSaved")
        }
        XCTAssertNil(overwriteVersion, "首次保存没有旧定稿，不应制造手工覆盖版本")
        XCTAssertEqual(article.content, "初稿")
        XCTAssertEqual(try database.draftVersion(id: provisional.id)?.article_id, article.id,
                       "首次保存必须把同标题的临时版本附着到新文章")
        XCTAssertFalse(try database.listDraftVersions(articleID: article.id, limit: 20)
            .contains { $0.action == DraftVersionAction.manualSave })
    }

    func testOverwritingArticleRecordsRestorableVersionAndUnchangedSaveDoesNotAddNoise() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let initial = try workflow.execute(.saveArticle(.init(
            articleID: nil,
            payload: articlePayload(title: "造船", content: "好版本")
        )))
        guard case let .articleSaved(article, _, _) = initial else {
            return XCTFail("首次保存必须返回 articleSaved")
        }

        let changed = try workflow.execute(.saveArticle(.init(
            articleID: article.id,
            payload: articlePayload(title: "造船", content: "降质版本")
        )))

        guard case let .articleSaved(saved, overwriteVersion, _) = changed else {
            return XCTFail("覆盖保存必须返回 articleSaved")
        }
        let version = try XCTUnwrap(overwriteVersion)
        XCTAssertEqual(saved.id, article.id)
        XCTAssertEqual(version.action, DraftVersionAction.manualSave)
        XCTAssertEqual(version.before_content, "好版本")
        XCTAssertEqual(version.after_content, "降质版本")
        XCTAssertEqual(version.note, "已覆盖旧定稿，「恢复前」可回到本次保存之前")

        let unchanged = try workflow.execute(.saveArticle(.init(
            articleID: article.id,
            payload: articlePayload(title: "造船", content: "降质版本")
        )))
        guard case let .articleSaved(_, repeatedVersion, _) = unchanged else {
            return XCTFail("重复保存必须返回 articleSaved")
        }
        XCTAssertNil(repeatedVersion)
        XCTAssertEqual(
            try database.listDraftVersions(articleID: article.id, limit: 20)
                .filter { $0.action == DraftVersionAction.manualSave }.count,
            1,
            "内容未变化时不得新增版本噪音"
        )
    }

    func testArticleSaveRollsBackWhenOverwriteHistoryCannotBeRecorded() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let initial = try workflow.execute(.saveArticle(.init(
            articleID: nil,
            payload: articlePayload(title: "事务文章", content: "稳定正文")
        )))
        guard case let .articleSaved(article, _, _) = initial else {
            return XCTFail("首次保存必须返回 articleSaved")
        }

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        let trigger = """
        CREATE TRIGGER fail_manual_history
        BEFORE INSERT ON draft_versions
        WHEN NEW.action = '保存文章'
        BEGIN
            SELECT RAISE(ABORT, 'forced history failure');
        END;
        """
        XCTAssertEqual(sqlite3_exec(handle, trigger, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try workflow.execute(.saveArticle(.init(
            articleID: article.id,
            payload: articlePayload(title: "事务文章", content: "不应泄漏的正文")
        ))))
        XCTAssertEqual(
            try database.getArticle(article.id).content,
            "稳定正文",
            "版本留痕失败时，文章覆盖也必须随同一事务回滚"
        )
    }

    private func makeDatabase() throws -> NativeDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try NativeDatabase(databaseURL: directory.appending(path: "creative_workshop.sqlite3"))
    }

    private func deliveredReview(
        _ workflow: WritingWorkflow,
        before: DraftSnapshot,
        after: DraftSnapshot
    ) throws -> PendingDraftReview {
        let outcome = try workflow.execute(.deliverPending(.init(
            articleID: nil,
            titleSnapshot: "文章",
            actionTitle: "生成候选",
            before: before,
            after: after,
            usedFallback: false
        )))
        guard case let .pendingDelivered(_, review) = outcome else {
            throw TestFailure.unexpectedOutcome
        }
        return review
    }

    private func snapshot(
        title: String = "文章",
        summary: String = "",
        content: String = ""
    ) -> DraftSnapshot {
        DraftSnapshot(title: title, summary: summary, content: content)
    }

    /// 选题写成文章后必须翻「已写」。此前没有任何路径会改动选题状态——选题一律以「待写」
    /// 入库并永远留在那里，于是列表只增不减：真实库里 123 条全挂「待写」，包括已经写过的
    /// 那些。列表读起来像债而不是菜单，正是这么来的。
    func testSavingArticleMarksItsTopicWritten() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let topic = try XCTUnwrap(database.createTopics([
            TopicPayload(
                title: "一条选题", direction: "随笔", core_viewpoint: nil, target_reader: nil,
                description: nil, angle: nil, emotion: nil, score: 4,
                status: Topic.pendingStatus, tags: []
            )
        ]).first)
        XCTAssertEqual(topic.status, Topic.pendingStatus)

        let outcome = try workflow.execute(.saveArticle(.init(
            articleID: nil,
            payload: articlePayload(title: "写成的文章", content: "正文", topicID: topic.id)
        )))

        guard case let .articleSaved(_, _, markedTopic) = outcome else {
            return XCTFail("保存必须返回 articleSaved")
        }
        XCTAssertEqual(markedTopic?.id, topic.id)
        XCTAssertEqual(markedTopic?.status, Topic.writtenStatus)
        XCTAssertEqual(
            try database.listTopics().first(where: { $0.id == topic.id })?.status,
            Topic.writtenStatus,
            "翻转必须真的落库，而不只出现在 outcome 里"
        )
    }

    /// 没有关联选题时不该顺手翻掉别人的状态——这是串台修复的另一半。
    func testSavingArticleWithoutTopicTouchesNoTopic() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let topic = try XCTUnwrap(database.createTopics([
            TopicPayload(
                title: "无关的选题", direction: "随笔", core_viewpoint: nil, target_reader: nil,
                description: nil, angle: nil, emotion: nil, score: 4,
                status: Topic.pendingStatus, tags: []
            )
        ]).first)

        let outcome = try workflow.execute(.saveArticle(.init(
            articleID: nil,
            payload: articlePayload(title: "自己想的文章", content: "正文")
        )))

        guard case let .articleSaved(_, _, markedTopic) = outcome else {
            return XCTFail("保存必须返回 articleSaved")
        }
        XCTAssertNil(markedTopic)
        XCTAssertEqual(
            try database.listTopics().first(where: { $0.id == topic.id })?.status,
            Topic.pendingStatus
        )
    }

    /// 关联的选题已被删除时，保存照常成功——翻转只是附带动作，不该让整次保存回滚。
    func testSavingArticleSurvivesADeletedTopic() throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)
        let topic = try XCTUnwrap(database.createTopics([
            TopicPayload(
                title: "待删的选题", direction: "随笔", core_viewpoint: nil, target_reader: nil,
                description: nil, angle: nil, emotion: nil, score: 4,
                status: Topic.pendingStatus, tags: []
            )
        ]).first)
        try database.deleteTopic(id: topic.id)

        let outcome = try workflow.execute(.saveArticle(.init(
            articleID: nil,
            payload: articlePayload(title: "文章", content: "正文", topicID: topic.id)
        )))

        guard case let .articleSaved(article, _, markedTopic) = outcome else {
            return XCTFail("选题已删除不该让保存失败")
        }
        XCTAssertNil(markedTopic)
        XCTAssertEqual(article.title, "文章")
    }

    private func articlePayload(title: String, content: String, topicID: Int? = nil) -> ArticleSaveRequest {
        ArticleSaveRequest(
            title: title,
            content: content,
            summary: "摘要",
            status: "草稿",
            tags: ["测试"],
            related_topic_id: topicID,
            genre: "随笔"
        )
    }

    private func makePolishRequest(database: NativeDatabase) throws -> WritingWorkflow.PolishRequest {
        let style = try database.defaultStyle()
        let before = snapshot(title: "原稿", summary: "原摘要", content: "原始正文")
        let context = ContextPackage(
            stage: "润色",
            title: before.title,
            summary: before.summary,
            idea: "",
            direction: "随笔",
            outline_excerpt: "",
            content_excerpt: before.content,
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: style.name,
            style_brief: "",
            word_count: before.content.count,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: [],
            genre: style.genre,
            known_pitfalls: []
        )
        return .init(
            articleID: nil,
            titleSnapshot: before.title,
            before: before,
            context: context,
            mode: .natural,
            style: style,
            polishTemplate: nil,
            selfCheckTemplate: nil,
            config: ModelConfig(model: "test-model"),
            apiKey: "fake-key",
            styleSamples: nil
        )
    }
}

private enum TestFailure: Error {
    case unexpectedOutcome
    case staleDraft
}

private final class WorkflowPolishExecutor: AIWorkflowExecuting {
    private(set) var kinds: [AIWorkflowKind] = []

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        kinds.append(descriptor.kind)
        if descriptor.kind == .polishDraft,
           let result = DraftResult(
               title: "工作流润色标题",
               content: "工作流生成的润色正文",
               summary: "工作流摘要",
               tags: ["工作流"],
               raw_output: nil
           ) as? Output {
            return AIRun(
                result: result,
                elapsedMS: 4,
                success: true,
                error: "",
                inputSummary: "润色输入",
                outputSummary: "润色输出"
            )
        }
        if descriptor.kind == .draftSelfCheck,
           let result = DraftSelfCheckResult(
               has_concerns: false,
               flagged_excerpts: [],
               raw_output: nil
           ) as? Output {
            return AIRun(
                result: result,
                elapsedMS: 2,
                success: true,
                error: "",
                inputSummary: "自检输入",
                outputSummary: "自检输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 1,
            success: false,
            error: "unexpected workflow",
            inputSummary: "",
            outputSummary: ""
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        // 预期错误。
    }
}
