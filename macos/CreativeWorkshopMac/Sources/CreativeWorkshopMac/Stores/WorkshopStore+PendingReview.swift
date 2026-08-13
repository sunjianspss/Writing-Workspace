import Foundation
import CreativeWorkshopCore

/// R5 瘦身·任务 21：待复核状态机的迁移语义在 Core 的 `PendingReviewMachine`，
/// 本文件只保留"调机器 → 更新 @Published → statusText"的薄绑定与编辑器快照应用。
extension WorkshopStore {
    /// 会话切换只有在 pending 行已从数据库清理后才提交内存状态，避免旧任务异步回写新稿。
    func resolvePendingBeforeSessionSwitch() throws -> Int? {
        guard let pending = pendingDraftReview else { return nil }
        _ = try writingWorkflow.execute(.cleanupPending(versionID: pending.draftVersionID))
        resolvePendingDraftReviewContinuation(with: .discarded)
        return pending.draftVersionID
    }

    private func draftSnapshot(applying result: DraftResult, fallbackTitle: String) -> DraftSnapshot {
        DraftSnapshot(
            title: result.title ?? fallbackTitle,
            summary: result.summary ?? summary,
            content: result.content ?? result.raw_output ?? content
        )
    }

    /// 大范围生成动作的统一收口（18.3.5 / 18.4.1）：预览即时可见，同时以 pending 版本进入待复核。
    func finalizeGeneratedDraft(
        result: DraftResult,
        fallbackTitle: String,
        style: StyleProfile,
        actionTitle: String,
        successNote: String?,
        failureNote: String?,
        usedFallback: Bool,
        clearArticleSelection: Bool,
        agentTrace: AgentDraftTrace? = nil,
        retrievedFragments: [RetrievedFragment] = [],
        sectionFragmentContexts: [SectionFragmentContext] = [],
        iterationSummary: [DeepDraftIteration]? = nil,
        candidateJudgement: CandidateJudgeResult? = nil,
        checkpoint: WritingSessionCheckpoint? = nil
    ) async throws {
        let checkpoint = checkpoint ?? captureWritingSessionCheckpoint()
        let before = checkpoint.before
        let expectedRevision = checkpoint.revision
        let articleID = checkpoint.articleID
        let titleSnapshot = checkpoint.titleSnapshot
        let after = draftSnapshot(applying: result, fallbackTitle: fallbackTitle)

        var selfCheckContext = currentWritingContext(style: style)
        selfCheckContext.title = after.title
        selfCheckContext.summary = after.summary
        selfCheckContext.content_excerpt = after.content
        selfCheckContext.word_count = after.content.count
        let selfCheckResponse = await executeWorkflow(
            NativeWorkflowCatalog.draftSelfCheck(
                context: selfCheckContext,
                style: style,
                template: promptTemplate(for: .draftSelfCheck)
            )
        ).draftSelfCheckResponse
        if Task.isCancelled {
            throw CancellationError()
        }

        let note = usedFallback ? failureNote : successNote
        let outcome = try writingWorkflow.execute(.deliverPending(.init(
            articleID: articleID,
            titleSnapshot: titleSnapshot,
            actionTitle: actionTitle,
            note: note,
            before: before,
            after: after,
            usedFallback: usedFallback,
            selfCheck: selfCheckResponse.result,
            matchedPitfalls: style.known_pitfalls ?? [],
            agentTrace: agentTrace,
            retrievedFragments: retrievedFragments,
            sectionFragmentContexts: sectionFragmentContexts,
            iterationSummary: iterationSummary,
            candidateJudgement: candidateJudgement,
            styleSamples: lastStyleSampleProvenance
        )))
        guard case let .pendingDelivered(version, pending) = outcome else {
            preconditionFailure("WritingWorkflow returned an invalid pending outcome")
        }
        do {
            try writingSession.stage(pending, expectedRevision: expectedRevision)
        } catch {
            _ = try? writingWorkflow.execute(.cleanupPending(versionID: version.id))
            throw error
        }
        if let tags = result.tags {
            draftTags = tags
        }
        if clearArticleSelection {
            selectedArticleID = nil
        }
        draftVersions = [version] + draftVersions
        statusText = usedFallback
            ? "已使用本地内容，请确认或放弃：\(failureNote ?? "未配置 API Key")"
            : "\(actionTitle)已生成，请确认或放弃"
    }

    struct WritingSessionCheckpoint {
        var revision: Int
        var before: DraftSnapshot
        var articleID: Int?
        var titleSnapshot: String
    }

    func captureWritingSessionCheckpoint() -> WritingSessionCheckpoint {
        WritingSessionCheckpoint(
            revision: writingSession.state.revision,
            before: currentDraftSnapshot(),
            articleID: selectedArticleID,
            titleSnapshot: titleIfAvailable()
        )
    }

    func requireWritingSessionCheckpoint(_ checkpoint: WritingSessionCheckpoint) throws {
        guard writingSession.state.revision == checkpoint.revision else {
            throw WritingSession.TransitionError.candidateBasedOnStaleRevision(
                expected: checkpoint.revision,
                received: writingSession.state.revision
            )
        }
    }

    // MARK: - 待复核确认/放弃（18.4.1）

    /// 23.5：计划执行中某步产生待复核产物时用于暂停/恢复序列的信号。
    enum PendingDraftReviewResolution {
        case confirmed
        case discarded
    }

    /// 供计划执行序列使用：待复核为空时立即返回，否则挂起直到作者确认/放弃，或会话切换隐式放弃。
    func waitForPendingDraftReviewResolution() async -> PendingDraftReviewResolution {
        guard pendingDraftReview != nil else { return .confirmed }
        return await withCheckedContinuation { continuation in
            self.pendingDraftReviewContinuation = continuation
        }
    }

    func resolvePendingDraftReviewContinuation(with resolution: PendingDraftReviewResolution) {
        pendingDraftReviewContinuation?.resume(returning: resolution)
        pendingDraftReviewContinuation = nil
    }

    /// 确认当前"待复核"候选为定稿（18.4.1）：正文早已预览显示，这里只把版本状态从 pending 翻为 confirmed。
    func confirmPendingDraftReview() async {
        guard let pending = pendingDraftReview else { return }
        if let version = draftVersions.first(where: { $0.id == pending.draftVersionID }) {
            await confirmDraftVersion(version)
        } else {
            await run("确认版本") {
                let outcome = try self.writingWorkflow.execute(.confirmPending(pending))
                guard case .pendingConfirmed = outcome else {
                    preconditionFailure("WritingWorkflow returned an invalid confirmation outcome")
                }
                try self.writingSession.didConfirmPendingDraftReview(versionID: pending.draftVersionID)
                self.resolvePendingDraftReviewContinuation(with: .confirmed)
                self.statusText = "已确认为定稿"
            }
        }
    }

    /// 放弃当前"待复核"候选（18.4.1）：正文回退到生成前的版本，并从历史中移除这条从未落地的记录。
    func discardPendingDraftReview() async {
        guard let pending = pendingDraftReview else { return }
        if let version = draftVersions.first(where: { $0.id == pending.draftVersionID }) {
            await discardDraftVersion(version)
        } else {
            await run("放弃版本") {
                let outcome = try self.writingWorkflow.execute(.discardPending(
                    pending,
                    preservingCurrent: self.currentDraftSnapshot()
                ))
                guard case let .pendingDiscarded(_, _, preserved) = outcome else {
                    preconditionFailure("WritingWorkflow returned an invalid discard outcome")
                }
                try self.writingSession.didDiscardPendingDraftReview(versionID: pending.draftVersionID)
                if let preserved { self.draftVersions = [preserved] + self.draftVersions }
                self.resolvePendingDraftReviewContinuation(with: .discarded)
                self.statusText = "已放弃该版本"
            }
        }
    }

    /// 供改稿版本列表里历史"待复核"记录使用（例如切换文章后再回来confirm）。
    func confirmDraftVersion(_ version: DraftVersion) async {
        await run("确认版本") {
            let review = PendingDraftReview(
                draftVersionID: version.id,
                actionTitle: version.action,
                articleID: version.article_id,
                before: version.beforeSnapshot,
                after: version.afterSnapshot,
                note: version.note,
                usedFallback: false,
                matchedPitfalls: []
            )
            let outcome = try self.writingWorkflow.execute(.confirmPending(review))
            guard case let .pendingConfirmed(updated) = outcome else {
                preconditionFailure("WritingWorkflow returned an invalid confirmation outcome")
            }
            self.draftVersions = self.draftVersions.map { $0.id == updated.id ? updated : $0 }
            if self.pendingDraftReview?.draftVersionID == version.id {
                try self.writingSession.didConfirmPendingDraftReview(versionID: version.id)
                self.resolvePendingDraftReviewContinuation(with: .confirmed)
            }
            self.statusText = "已确认为定稿"
        }
    }

    func discardDraftVersion(_ version: DraftVersion) async {
        await run("放弃版本") {
            let review = PendingDraftReview(
                draftVersionID: version.id,
                actionTitle: version.action,
                articleID: version.article_id,
                before: version.beforeSnapshot,
                after: version.afterSnapshot,
                note: version.note,
                usedFallback: false,
                matchedPitfalls: []
            )
            let current = self.pendingDraftReview?.draftVersionID == version.id
                ? self.currentDraftSnapshot()
                : nil
            let outcome = try self.writingWorkflow.execute(.discardPending(
                review,
                preservingCurrent: current
            ))
            guard case let .pendingDiscarded(_, _, preserved) = outcome else {
                preconditionFailure("WritingWorkflow returned an invalid discard outcome")
            }
            self.draftVersions.removeAll { $0.id == version.id }
            if let preserved { self.draftVersions.insert(preserved, at: 0) }
            if self.pendingDraftReview?.draftVersionID == version.id {
                try self.writingSession.didDiscardPendingDraftReview(versionID: version.id)
                self.resolvePendingDraftReviewContinuation(with: .discarded)
            }
            self.statusText = "已放弃该版本"
        }
    }

    // MARK: - 版本恢复与定点改写候选

    func restoreDraftVersionBefore(_ version: DraftVersion) {
        applySnapshot(version.beforeSnapshot)
        statusText = "已恢复到「\(version.action)」之前"
    }

    func restoreDraftVersionAfter(_ version: DraftVersion) {
        applySnapshot(version.afterSnapshot)
        statusText = "已恢复到「\(version.action)」之后"
    }

    /// 人工确认后才把候选写入正文（18.3.1 验收标准 3）。
    func confirmPendingIssueRewrite() async {
        guard let pending = pendingIssueRewrite else { return }
        await run("确认定点改写") {
            let before = self.currentDraftSnapshot()
            guard self.replaceSelectedContent(range: pending.range, expectedText: pending.originalText, replacement: pending.replacement) else {
                self.pendingIssueRewrite = nil
                self.statusText = "正文已变化，请重新定位后再改写"
                return
            }
            let note = pending.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let outcome = try self.writingWorkflow.execute(.recordDraftVersion(.init(
                articleID: self.selectedArticleID,
                titleSnapshot: self.titleIfAvailable(),
                action: "定点改写·\(pending.issue.dimension)",
                note: note?.isEmpty == false ? note : "根据诊断建议改写",
                before: before,
                after: self.currentDraftSnapshot()
            )))
            guard case let .draftVersionRecorded(version) = outcome else {
                preconditionFailure("WritingWorkflow returned an invalid version outcome")
            }
            self.draftVersions = [version] + self.draftVersions
            self.pendingIssueRewrite = nil
            self.statusText = "已应用改写并替换正文"
        }
    }

    func discardPendingIssueRewrite() {
        pendingIssueRewrite = nil
        statusText = "已放弃本次改写候选"
    }
}
