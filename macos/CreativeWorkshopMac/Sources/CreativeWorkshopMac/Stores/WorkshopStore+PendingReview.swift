import Foundation
import CreativeWorkshopCore

/// R5 瘦身·任务 21：待复核状态机的迁移语义在 Core 的 `PendingReviewMachine`，
/// 本文件只保留"调机器 → 更新 @Published → statusText"的薄绑定与编辑器快照应用。
extension WorkshopStore {
    private var pendingReviewMachine: PendingReviewMachine {
        PendingReviewMachine(database: database)
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
        candidateJudgement: CandidateJudgeResult? = nil
    ) async throws {
        let before = currentDraftSnapshot()
        let articleID = selectedArticleID
        let titleSnapshot = titleIfAvailable()
        applyDraft(result, fallbackTitle: fallbackTitle)
        let after = currentDraftSnapshot()

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
            applySnapshot(before)
            throw CancellationError()
        }
        latestSelfCheck = selfCheckResponse.result

        let note = usedFallback ? failureNote : successNote
        let delivered = try pendingReviewMachine.deliver(
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
        )
        if clearArticleSelection {
            selectedArticleID = nil
        }
        draftVersions = [delivered.version] + draftVersions
        pendingDraftReview = delivered.pending
        statusText = usedFallback
            ? "已使用本地内容，请确认或放弃：\(failureNote ?? "未配置 API Key")"
            : "\(actionTitle)已生成，请确认或放弃"
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
                _ = try self.pendingReviewMachine.confirm(versionID: pending.draftVersionID)
                self.statusText = "已确认为定稿"
            }
        }
        pendingDraftReview = nil
        latestSelfCheck = nil
        saveAutosaveSnapshot()
        resolvePendingDraftReviewContinuation(with: .confirmed)
    }

    /// 放弃当前"待复核"候选（18.4.1）：正文回退到生成前的版本，并从历史中移除这条从未落地的记录。
    func discardPendingDraftReview() async {
        guard let pending = pendingDraftReview else { return }
        if let version = draftVersions.first(where: { $0.id == pending.draftVersionID }) {
            await discardDraftVersion(version)
        } else {
            await run("放弃版本") {
                try self.pendingReviewMachine.discard(versionID: pending.draftVersionID)
                self.applySnapshot(pending.before)
                self.statusText = "已放弃该版本"
            }
        }
        pendingDraftReview = nil
        latestSelfCheck = nil
        saveAutosaveSnapshot()
        resolvePendingDraftReviewContinuation(with: .discarded)
    }

    /// 供改稿版本列表里历史"待复核"记录使用（例如切换文章后再回来confirm）。
    func confirmDraftVersion(_ version: DraftVersion) async {
        await run("确认版本") {
            let updated = try self.pendingReviewMachine.confirm(versionID: version.id)
            self.draftVersions = self.draftVersions.map { $0.id == updated.id ? updated : $0 }
            if self.pendingDraftReview?.draftVersionID == version.id {
                self.pendingDraftReview = nil
                self.resolvePendingDraftReviewContinuation(with: .confirmed)
            }
            self.statusText = "已确认为定稿"
        }
    }

    func discardDraftVersion(_ version: DraftVersion) async {
        await run("放弃版本") {
            try self.pendingReviewMachine.discard(versionID: version.id)
            self.draftVersions.removeAll { $0.id == version.id }
            if self.pendingDraftReview?.draftVersionID == version.id {
                self.applySnapshot(version.beforeSnapshot)
                self.pendingDraftReview = nil
                self.resolvePendingDraftReviewContinuation(with: .discarded)
            }
            self.statusText = "已放弃该版本"
        }
    }

    /// 切换文章/新建草稿时的隐式放弃（18.4.1）：正文即将被覆盖，只清理孤儿 pending 行。
    /// confirmed 行的保护在 PendingReviewMachine.cleanupOrphan 内强制。
    func abandonOrphanedPendingReview() {
        guard let orphaned = pendingDraftReview else { return }
        pendingDraftReview = nil
        Task { try? self.pendingReviewMachine.cleanupOrphan(versionID: orphaned.draftVersionID) }
        resolvePendingDraftReviewContinuation(with: .discarded)
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
            let version = try self.database.saveDraftVersion(
                articleID: self.selectedArticleID,
                titleSnapshot: self.titleIfAvailable(),
                action: "定点改写·\(pending.issue.dimension)",
                note: note?.isEmpty == false ? note : "根据诊断建议改写",
                before: before,
                after: self.currentDraftSnapshot()
            )
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
