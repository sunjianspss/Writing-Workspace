import Foundation
import XCTest
@testable import CreativeWorkshopCore

@MainActor
final class WritingSessionTests: XCTestCase {
    private func makeController(suite: String) -> (AutosaveController, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AutosaveController(defaults: defaults, key: "test.writing-session"), defaults)
    }

    private func makePending(
        id: Int = 41,
        before: DraftSnapshot = DraftSnapshot(title: "旧标题", summary: "旧摘要", content: "旧正文"),
        after: DraftSnapshot = DraftSnapshot(title: "候选标题", summary: "候选摘要", content: "候选正文")
    ) -> PendingDraftReview {
        PendingDraftReview(
            draftVersionID: id,
            actionTitle: "全文润色",
            articleID: 7,
            before: before,
            after: after,
            usedFallback: false,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            matchedPitfalls: []
        )
    }

    private func makeArticle() -> Article {
        Article(
            id: 7,
            title: "已保存文章",
            content: "已保存正文",
            summary: "已保存摘要",
            status: "待发布",
            type: nil,
            tags: ["架构"],
            updated_at: nil,
            created_at: nil,
            related_topic_id: 9,
            genre: "技术分享",
            audit_report: nil
        )
    }

    func testEditPublishesOneRevisionAndSchedulesAutosaveInternally() async {
        let suite = "writing-session-edit-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = WritingSession(
            autosave: controller,
            autosaveDebounceNanoseconds: 20_000_000,
            timestamp: { "2026-08-13T00:00:00Z" }
        )

        session.edit {
            $0.title = "接口内编辑"
            $0.content = "自动保存正文"
            $0.tags = ["会话"]
        }

        XCTAssertEqual(session.state.revision, 1)
        XCTAssertEqual(session.state.title, "接口内编辑")
        XCTAssertFalse(
            WritingSession(autosave: controller).state.showAutosaveRestorePrompt,
            "防抖窗口内不应提前出现可恢复快照"
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        let recovered = WritingSession(autosave: controller)
        XCTAssertTrue(recovered.state.showAutosaveRestorePrompt)
        XCTAssertEqual(
            recovered.restoreAutosavedDraft(
                articleStatus: { _ in .valid },
                topicStatus: { _ in .valid },
                pendingVersionStatus: { _ in .pending }
            ),
            .restored
        )
        XCTAssertEqual(recovered.state.title, "接口内编辑")
        XCTAssertEqual(recovered.state.content, "自动保存正文")
        XCTAssertEqual(recovered.state.tags, ["会话"])
    }

    func testNewAndOpenClearSessionTransientState() throws {
        let suite = "writing-session-lifecycle-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = WritingSession(autosave: controller)
        let pending = makePending(id: 73)

        session.edit {
            $0.title = pending.before.title
            $0.summary = pending.before.summary
            $0.content = pending.before.content
        }
        session.setPendingIssueRewrite(PendingIssueRewrite(
            issue: WritingReviewIssue(
                dimension: "表达",
                severity: "中",
                excerpt: "旧",
                problem: "不清楚",
                suggestion: "改清楚"
            ),
            range: NSRange(location: 0, length: 1),
            originalText: "旧",
            replacement: "新",
            usedFallback: false
        ))
        session.setLatestReaderPerspective(ReaderPerspectiveResult(
            reader_persona: "新读者",
            drop_off_point: nil,
            most_memorable_point: nil,
            note: nil,
            raw_output: nil
        ))
        session.setUnchangedReviewPromptVisible(true)
        try session.stage(pending, expectedRevision: session.state.revision)

        try session.startNewDraft(afterResolvingPendingVersionID: 73)

        XCTAssertNil(session.state.selectedArticleID)
        XCTAssertNil(session.state.selectedTopicID)
        XCTAssertEqual(session.state.title, "")
        assertTransientStateIsClear(session.state)

        session.setPendingIssueRewrite(PendingIssueRewrite(
            issue: WritingReviewIssue(
                dimension: "结构",
                severity: "低",
                excerpt: nil,
                problem: "松散",
                suggestion: "收紧"
            ),
            range: NSRange(location: 0, length: 0),
            originalText: "",
            replacement: "替换",
            usedFallback: false
        ))
        session.setUnchangedReviewPromptVisible(true)

        try session.open(makeArticle())

        XCTAssertEqual(session.state.selectedArticleID, 7)
        XCTAssertEqual(session.state.selectedTopicID, 9)
        XCTAssertEqual(session.state.articleStatus, "待发布")
        XCTAssertEqual(session.state.title, "已保存文章")
        XCTAssertEqual(session.state.writingDirection, "技术分享")
        XCTAssertEqual(session.state.tags, ["架构"])
        assertTransientStateIsClear(session.state)
        session.saveAutosaveSnapshotNow()
        XCTAssertFalse(
            WritingSession(autosave: controller).state.showAutosaveRestorePrompt,
            "仅打开已保存文章不应被误判为未保存恢复草稿"
        )
    }

    func testUnsavedBaselineChangesOnlyAfterDatabaseSaveAcknowledgement() throws {
        let suite = "writing-session-baseline-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = WritingSession(autosave: controller)

        XCTAssertFalse(session.hasUnsavedChanges)
        session.edit { $0.content = "尚未保存的正文" }
        session.saveAutosaveSnapshotNow()
        XCTAssertTrue(session.hasUnsavedChanges, "自动保存只是恢复副本，不能冒充文章已持久化")

        let saved = Article(
            id: 12,
            title: "文章",
            content: "尚未保存的正文",
            summary: "",
            status: "草稿",
            type: nil,
            tags: [],
            updated_at: nil,
            created_at: nil,
            related_topic_id: nil,
            genre: nil,
            audit_report: nil
        )
        session.didSaveArticle(saved)
        XCTAssertFalse(session.hasUnsavedChanges)
        session.edit { $0.materials = "保存后新增素材" }
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testStagePreviewsCandidateAndDiscardAfterDatabaseSuccessRestoresExactBefore() throws {
        let suite = "writing-session-pending-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = WritingSession(autosave: controller)
        let pending = makePending()

        session.edit {
            $0.title = pending.before.title
            $0.summary = pending.before.summary
            $0.content = pending.before.content
        }

        try session.stage(pending, expectedRevision: session.state.revision)

        XCTAssertEqual(session.state.title, pending.after.title)
        XCTAssertEqual(session.state.summary, pending.after.summary)
        XCTAssertEqual(session.state.content, pending.after.content)
        XCTAssertEqual(session.state.pendingDraftReview?.draftVersionID, pending.draftVersionID)

        XCTAssertThrowsError(try session.didDiscardPendingDraftReview(versionID: 999))
        XCTAssertEqual(session.state.content, pending.after.content, "数据库版本不匹配时不得提前改变预览")

        try session.didDiscardPendingDraftReview(versionID: pending.draftVersionID)

        XCTAssertEqual(session.state.title, pending.before.title)
        XCTAssertEqual(session.state.summary, pending.before.summary)
        XCTAssertEqual(session.state.content, pending.before.content)
        XCTAssertNil(session.state.pendingDraftReview)
        XCTAssertNil(session.state.latestSelfCheck)
    }

    func testStageRejectsCandidateWhenNonSnapshotDraftFieldsChangedDuringGeneration() throws {
        let suite = "writing-session-stale-revision-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = WritingSession(autosave: controller)
        let pending = makePending()
        session.edit {
            $0.title = pending.before.title
            $0.summary = pending.before.summary
            $0.content = pending.before.content
        }
        let capturedRevision = session.state.revision

        session.edit { $0.materials = "作者在模型运行期间补充的素材" }

        XCTAssertThrowsError(try session.stage(pending, expectedRevision: capturedRevision)) { error in
            XCTAssertEqual(
                error as? WritingSession.TransitionError,
                .candidateBasedOnStaleRevision(
                    expected: capturedRevision,
                    received: session.state.revision
                )
            )
        }
        XCTAssertNil(session.state.pendingDraftReview)
        XCTAssertEqual(session.state.content, pending.before.content)
        XCTAssertEqual(session.state.materials, "作者在模型运行期间补充的素材")
    }

    func testRestoreDropsDanglingPendingAndPersistsItsBeforeSnapshot() throws {
        let suite = "writing-session-recovery-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = makePending(id: 404)
        let writer = WritingSession(autosave: controller)
        writer.selectArticle(7)
        writer.selectTopic(9)
        writer.edit {
            $0.title = pending.before.title
            $0.summary = pending.before.summary
            $0.content = pending.before.content
            $0.outline = "提纲"
            $0.ideaInput = "想法"
            $0.writingDirection = "技术分享"
            $0.materials = "材料"
            $0.tags = ["恢复"]
        }
        try writer.stage(pending, expectedRevision: writer.state.revision)
        writer.saveAutosaveSnapshotNow()

        let session = WritingSession(
            autosave: controller,
            timestamp: { "2026-08-13T00:01:00Z" }
        )

        XCTAssertTrue(session.state.showAutosaveRestorePrompt)
        let result = session.restoreAutosavedDraft(
            articleStatus: { $0 == 7 ? .valid : .missing },
            topicStatus: { $0 == 9 ? .valid : .missing },
            pendingVersionStatus: { _ in .missing }
        )

        XCTAssertEqual(result, .restoredAfterDroppingDanglingPending(versionID: 404))
        XCTAssertEqual(session.state.title, pending.before.title)
        XCTAssertEqual(session.state.summary, pending.before.summary)
        XCTAssertEqual(session.state.content, pending.before.content)
        XCTAssertNil(session.state.pendingDraftReview)
        XCTAssertNil(session.state.latestSelfCheck)
        XCTAssertFalse(session.state.showAutosaveRestorePrompt)

        let reconciled = WritingSession(autosave: controller)
        XCTAssertTrue(reconciled.state.showAutosaveRestorePrompt)
        XCTAssertEqual(
            reconciled.restoreAutosavedDraft(
                articleStatus: { $0 == 7 ? .valid : .missing },
                topicStatus: { $0 == 9 ? .valid : .missing },
                pendingVersionStatus: { _ in .missing }
            ),
            .restored,
            "修复后的快照不得让悬空 pending 在下次启动复活"
        )
        XCTAssertEqual(reconciled.state.content, pending.before.content)
        XCTAssertNil(reconciled.state.pendingDraftReview)

        session.discardAutosavedDraft()
        XCTAssertFalse(WritingSession(autosave: controller).state.showAutosaveRestorePrompt)
        XCTAssertEqual(session.state.content, pending.before.content, "放弃恢复入口只清快照，不应抹掉已恢复的编辑器内容")
    }

    func testRestoreReconcilesConfirmedPendingToAfterSnapshot() throws {
        let suite = "writing-session-confirmed-recovery-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = makePending(id: 405)
        let writer = WritingSession(autosave: controller)
        writer.edit {
            $0.title = pending.before.title
            $0.summary = pending.before.summary
            $0.content = pending.before.content
        }
        try writer.stage(pending, expectedRevision: writer.state.revision)
        writer.saveAutosaveSnapshotNow()

        let recovered = WritingSession(autosave: controller)
        let result = recovered.restoreAutosavedDraft(
            articleStatus: { _ in .valid },
            topicStatus: { _ in .valid },
            pendingVersionStatus: { _ in .confirmed }
        )

        XCTAssertEqual(result, .restoredAfterReconcilingConfirmedPending(versionID: 405))
        XCTAssertEqual(recovered.state.title, pending.after.title)
        XCTAssertEqual(recovered.state.content, pending.after.content)
        XCTAssertNil(recovered.state.pendingDraftReview)
        XCTAssertNil(recovered.state.latestSelfCheck)
    }

    func testRestoreKeepsManualEditsMadeOnPendingPreview() throws {
        let suite = "writing-session-pending-edit-recovery-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = makePending(id: 406)
        let writer = WritingSession(autosave: controller)
        writer.edit {
            $0.title = pending.before.title
            $0.summary = pending.before.summary
            $0.content = pending.before.content
        }
        try writer.stage(pending, expectedRevision: writer.state.revision)
        writer.edit { $0.content = "作者在候选预览上继续修改的正文" }
        writer.saveAutosaveSnapshotNow()

        for status in [WritingSession.RecoveredPendingStatus.pending, .confirmed] {
            let recovered = WritingSession(autosave: controller)
            _ = recovered.restoreAutosavedDraft(
                articleStatus: { _ in .valid },
                topicStatus: { _ in .valid },
                pendingVersionStatus: { _ in status }
            )
            XCTAssertEqual(recovered.state.content, "作者在候选预览上继续修改的正文")
            if status == .pending {
                XCTAssertEqual(recovered.state.pendingDraftReview?.draftVersionID, 406)
            } else {
                XCTAssertNil(recovered.state.pendingDraftReview)
            }
        }
    }

    func testRestoreLeavesSnapshotUntouchedWhenPendingStatusCannotBeDetermined() throws {
        let suite = "writing-session-unknown-recovery-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = makePending(id: 407)
        let writer = WritingSession(autosave: controller)
        writer.edit {
            $0.title = pending.before.title
            $0.summary = pending.before.summary
            $0.content = pending.before.content
        }
        try writer.stage(pending, expectedRevision: writer.state.revision)
        writer.saveAutosaveSnapshotNow()

        let recovered = WritingSession(autosave: controller)
        XCTAssertEqual(
            recovered.restoreAutosavedDraft(
                articleStatus: { _ in .valid },
                topicStatus: { _ in .valid },
                pendingVersionStatus: { _ in .unknown }
            ),
            .deferredUntilDatabaseAvailable
        )
        XCTAssertTrue(recovered.state.showAutosaveRestorePrompt)
        XCTAssertEqual(recovered.state.content, "")
        XCTAssertNil(recovered.state.pendingDraftReview)
        XCTAssertTrue(WritingSession(autosave: controller).state.showAutosaveRestorePrompt)
    }

    private func assertTransientStateIsClear(
        _ state: WritingSession.State,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(state.pendingDraftReview, file: file, line: line)
        XCTAssertNil(state.latestSelfCheck, file: file, line: line)
        XCTAssertNil(state.latestReaderPerspective, file: file, line: line)
        XCTAssertNil(state.pendingIssueRewrite, file: file, line: line)
        XCTAssertFalse(state.showUnchangedReviewPrompt, file: file, line: line)
        XCTAssertFalse(state.showAutosaveRestorePrompt, file: file, line: line)
    }
}
