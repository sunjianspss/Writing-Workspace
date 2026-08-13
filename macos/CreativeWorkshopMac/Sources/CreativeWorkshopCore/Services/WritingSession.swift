import Combine
import Foundation

/// 编辑器会话的单一状态所有者。
///
/// `WritingSession` 只管理内存状态、自动保存调度和可恢复的状态迁移。SQLite 写入与 AI 执行
/// 仍由调用者负责；尤其是待复核版本，调用者必须先完成数据库操作，再调用相应的 `did…` 方法。
@MainActor
package final class WritingSession: ObservableObject {
    package struct State {
        package var selectedArticleID: Int?
        package var selectedTopicID: Int?
        package var articleStatus: String
        package var title: String
        package var summary: String
        package var content: String
        package var outline: String
        package var ideaInput: String
        package var writingDirection: String
        package var materials: String
        package var tags: [String]
        package var pendingDraftReview: PendingDraftReview?
        package var latestSelfCheck: DraftSelfCheckResult?
        package var latestReaderPerspective: ReaderPerspectiveResult?
        package var pendingIssueRewrite: PendingIssueRewrite?
        package var showUnchangedReviewPrompt: Bool
        package var showAutosaveRestorePrompt: Bool
        /// 会话内单调递增的投影版本；每个成功的接口级状态迁移只递增一次。
        package var revision: Int

        package init(
            selectedArticleID: Int? = nil,
            selectedTopicID: Int? = nil,
            articleStatus: String = "草稿",
            title: String = "",
            summary: String = "",
            content: String = "",
            outline: String = "",
            ideaInput: String = "",
            writingDirection: String = "",
            materials: String = "",
            tags: [String] = [],
            pendingDraftReview: PendingDraftReview? = nil,
            latestSelfCheck: DraftSelfCheckResult? = nil,
            latestReaderPerspective: ReaderPerspectiveResult? = nil,
            pendingIssueRewrite: PendingIssueRewrite? = nil,
            showUnchangedReviewPrompt: Bool = false,
            showAutosaveRestorePrompt: Bool = false,
            revision: Int = 0
        ) {
            self.selectedArticleID = selectedArticleID
            self.selectedTopicID = selectedTopicID
            self.articleStatus = articleStatus
            self.title = title
            self.summary = summary
            self.content = content
            self.outline = outline
            self.ideaInput = ideaInput
            self.writingDirection = writingDirection
            self.materials = materials
            self.tags = tags
            self.pendingDraftReview = pendingDraftReview
            self.latestSelfCheck = latestSelfCheck
            self.latestReaderPerspective = latestReaderPerspective
            self.pendingIssueRewrite = pendingIssueRewrite
            self.showUnchangedReviewPrompt = showUnchangedReviewPrompt
            self.showAutosaveRestorePrompt = showAutosaveRestorePrompt
            self.revision = revision
        }
    }

    /// 作者可自由编辑的字段。选择、恢复提示和 pending 等治理状态刻意不在这里，
    /// 它们只能通过具名迁移接口改变。
    package struct EditableDraft: Equatable {
        package var title: String
        package var summary: String
        package var content: String
        package var outline: String
        package var ideaInput: String
        package var writingDirection: String
        package var materials: String
        package var tags: [String]
    }

    package enum TransitionError: Error, Equatable {
        case pendingReviewAlreadyStaged(existingVersionID: Int)
        case pendingReviewNotFound
        case pendingReviewVersionMismatch(expected: Int, received: Int)
        case pendingReviewResolutionRequired(versionID: Int)
        case candidateBasedOnStaleDraft
        case candidateBasedOnStaleRevision(expected: Int, received: Int)
    }

    package enum RecoveryResult: Equatable {
        case unavailable
        /// 恢复快照存在，但数据库暂时无法判定其中的引用或 pending 状态；快照未被消费。
        case deferredUntilDatabaseAvailable
        case restored
        /// 自动保存仍指向一个已经不存在的 pending 行；会话已回退到该候选的 before 快照。
        case restoredAfterDroppingDanglingPending(versionID: Int)
        /// 数据库已确认候选，但进程在 session/autosave 投影完成前退出；恢复时采用已确认的 after。
        case restoredAfterReconcilingConfirmedPending(versionID: Int)
    }

    package enum RecoveredPendingStatus {
        case pending
        case confirmed
        case missing
        case unknown
    }

    package enum RecoveredReferenceStatus {
        case valid
        case missing
        case unknown
    }

    @Published package private(set) var state: State

    private let autosave: AutosaveController
    private let autosaveDebounceNanoseconds: UInt64
    private let timestamp: () -> String
    private var persistedBaseline: EditableDraft
    /// 区分“打开了有内容的文章”和“有尚未冲刷的编辑”，避免退出时把未编辑文章误报为恢复草稿。
    private var hasUnflushedChanges = false

    package init(
        initialState: State = State(),
        autosave: AutosaveController? = nil,
        autosaveDebounceNanoseconds: UInt64 = 650_000_000,
        timestamp: @escaping () -> String = {
            ISO8601DateFormatter().string(from: Date())
        }
    ) {
        let autosave = autosave ?? AutosaveController()
        self.autosave = autosave
        self.autosaveDebounceNanoseconds = autosaveDebounceNanoseconds
        self.timestamp = timestamp
        self.persistedBaseline = Self.editableDraft(from: initialState)

        var initialState = initialState
        initialState.showAutosaveRestorePrompt = autosave.load() != nil
        self.state = initialState
    }

    /// 唯一的自由编辑入口。一次闭包内可合并多个作者字段修改，但不能越过 pending/lifecycle 不变量。
    package func edit(_ change: (inout EditableDraft) -> Void) {
        var draft = Self.editableDraft(from: state)
        change(&draft)
        update(autosave: .debounced) { state in
            state.title = draft.title
            state.summary = draft.summary
            state.content = draft.content
            state.outline = draft.outline
            state.ideaInput = draft.ideaInput
            state.writingDirection = draft.writingDirection
            state.materials = draft.materials
            state.tags = draft.tags
        }
    }

    package func selectArticle(_ id: Int?) {
        update(autosave: .debounced) { $0.selectedArticleID = id }
    }

    package func selectTopic(_ id: Int?) {
        update(autosave: .debounced) { $0.selectedTopicID = id }
    }

    package func setArticleStatus(_ status: String) {
        update(autosave: .debounced) { $0.articleStatus = status }
    }

    package func setPendingIssueRewrite(_ value: PendingIssueRewrite?) {
        update(autosave: .none) { $0.pendingIssueRewrite = value }
    }

    package func setLatestSelfCheck(_ value: DraftSelfCheckResult?) {
        update(autosave: .debounced) { $0.latestSelfCheck = value }
    }

    package func setLatestReaderPerspective(_ value: ReaderPerspectiveResult?) {
        update(autosave: .none) { $0.latestReaderPerspective = value }
    }

    package func setUnchangedReviewPromptVisible(_ visible: Bool) {
        update(autosave: .none) { $0.showUnchangedReviewPrompt = visible }
    }

    package func setAutosaveRestorePromptVisible(_ visible: Bool) {
        update(autosave: .none) { $0.showAutosaveRestorePrompt = visible }
    }

    package func updatePendingDraftReview(
        versionID: Int,
        _ change: (inout PendingDraftReview) -> Void
    ) throws {
        var pending = try matchingPending(versionID: versionID)
        change(&pending)
        update(autosave: .debounced) { $0.pendingDraftReview = pending }
    }

    /// 开始空白草稿。若当前存在 pending，调用者必须先解决数据库行并传回同一个版本号。
    package func startNewDraft(afterResolvingPendingVersionID resolvedVersionID: Int? = nil) throws {
        try requireResolvedPendingIfNeeded(resolvedVersionID)
        let nextRevision = state.revision + 1
        let retainedDirection = state.writingDirection

        autosave.cancelPending()
        autosave.clear()
        hasUnflushedChanges = false
        state = State(
            writingDirection: retainedDirection,
            revision: nextRevision
        )
        persistedBaseline = Self.editableDraft(from: state)
    }

    /// 打开已持久化文章。打开本身不是未保存编辑，因此会清除上一会话的恢复快照而不创建新快照。
    /// 若当前存在 pending，调用者必须先解决数据库行并传回同一个版本号。
    package func open(
        _ article: Article,
        afterResolvingPendingVersionID resolvedVersionID: Int? = nil
    ) throws {
        try requireResolvedPendingIfNeeded(resolvedVersionID)
        let nextRevision = state.revision + 1

        autosave.cancelPending()
        autosave.clear()
        hasUnflushedChanges = false
        state = State(
            selectedArticleID: article.id,
            selectedTopicID: article.related_topic_id,
            articleStatus: article.status ?? "草稿",
            title: article.title ?? "",
            summary: article.summary ?? "",
            content: article.content ?? "",
            writingDirection: article.genre ?? "",
            tags: article.tags ?? [],
            revision: nextRevision
        )
        persistedBaseline = Self.editableDraft(from: state)
    }

    /// 数据库已成功保存当前文章后，更新会话身份和比较基线；此后无新增编辑就不再拦截切稿。
    package func didSaveArticle(_ article: Article) {
        update(autosave: .none) { state in
            state.selectedArticleID = article.id
            state.selectedTopicID = article.related_topic_id
            state.articleStatus = article.status ?? state.articleStatus
        }
        persistedBaseline = Self.editableDraft(from: state)
        autosave.cancelPending()
        autosave.clear()
        hasUnflushedChanges = false
    }

    /// 交付已落为 pending 的候选并立即预览。before 必须仍与当前编辑器一致，避免覆盖并发编辑。
    package func stage(_ pending: PendingDraftReview, expectedRevision: Int) throws {
        if let existing = state.pendingDraftReview {
            throw TransitionError.pendingReviewAlreadyStaged(existingVersionID: existing.draftVersionID)
        }
        if expectedRevision != state.revision {
            throw TransitionError.candidateBasedOnStaleRevision(
                expected: expectedRevision,
                received: state.revision
            )
        }
        guard currentDraftSnapshot == pending.before else {
            throw TransitionError.candidateBasedOnStaleDraft
        }

        update(autosave: .debounced) { state in
            state.title = pending.after.title
            state.summary = pending.after.summary
            state.content = pending.after.content
            state.pendingDraftReview = pending
            state.latestSelfCheck = pending.selfCheck
        }
    }

    /// 仅在调用者已成功把数据库版本翻为 confirmed 后调用。候选预览保留为当前正文。
    package func didConfirmPendingDraftReview(versionID: Int) throws {
        _ = try matchingPending(versionID: versionID)
        update(autosave: .debounced) { state in
            state.pendingDraftReview = nil
            state.latestSelfCheck = nil
        }
    }

    /// 仅在调用者已成功删除数据库 pending 行后调用。正文精确回到候选携带的 before 快照。
    package func didDiscardPendingDraftReview(versionID: Int) throws {
        let pending = try matchingPending(versionID: versionID)
        update(autosave: .debounced) { state in
            state.title = pending.before.title
            state.summary = pending.before.summary
            state.content = pending.before.content
            state.pendingDraftReview = nil
            state.latestSelfCheck = nil
        }
    }

    /// 当前会话的持久化恢复投影。瞬态诊断/改写提示不会跨启动恢复。
    package func snapshot() -> AutoSavedDraft {
        AutoSavedDraft(
            selectedArticleID: state.selectedArticleID,
            selectedTopicID: state.selectedTopicID,
            articleStatus: state.articleStatus,
            title: state.title,
            summary: state.summary,
            content: state.content,
            outline: state.outline,
            ideaInput: state.ideaInput,
            writingDirection: state.writingDirection,
            materials: state.materials,
            draftTags: state.tags,
            pendingDraftReview: state.pendingDraftReview,
            latestSelfCheck: state.latestSelfCheck,
            savedAt: timestamp()
        )
    }

    /// 恢复快照。存在性判断由持有数据库的调用者提供，WritingSession 本身不执行 SQLite I/O。
    /// 悬空 pending 不可继续确认：恢复时回退其 before，并立即把已修复快照覆盖落盘。
    @discardableResult
    package func restoreAutosavedDraft(
        articleStatus: (Int) -> RecoveredReferenceStatus,
        topicStatus: (Int) -> RecoveredReferenceStatus,
        pendingVersionStatus: (Int) -> RecoveredPendingStatus
    ) -> RecoveryResult {
        guard let snapshot = autosave.load() else {
            if state.showAutosaveRestorePrompt {
                update(autosave: .none) { $0.showAutosaveRestorePrompt = false }
            }
            return .unavailable
        }

        let pending = snapshot.pendingDraftReview
        let pendingStatus = pending.map { pendingVersionStatus($0.draftVersionID) }
        let recoveredArticleStatus = snapshot.selectedArticleID.map(articleStatus)
        let recoveredTopicStatus = snapshot.selectedTopicID.map(topicStatus)
        if pendingStatus == .unknown
            || recoveredArticleStatus == .unknown
            || recoveredTopicStatus == .unknown {
            return .deferredUntilDatabaseAvailable
        }

        update(autosave: .none) { state in
            state.selectedArticleID = snapshot.selectedArticleID.flatMap { id in
                recoveredArticleStatus == .valid ? id : nil
            }
            state.selectedTopicID = snapshot.selectedTopicID.flatMap { id in
                recoveredTopicStatus == .valid ? id : nil
            }
            state.articleStatus = snapshot.articleStatus
            state.outline = snapshot.outline
            state.ideaInput = snapshot.ideaInput
            state.writingDirection = snapshot.writingDirection
            state.materials = snapshot.materials
            state.tags = snapshot.draftTags
            state.latestReaderPerspective = nil
            state.pendingIssueRewrite = nil
            state.showUnchangedReviewPrompt = false
            state.showAutosaveRestorePrompt = false

            if let pending, pendingStatus == .pending {
                state.title = snapshot.title
                state.summary = snapshot.summary
                state.content = snapshot.content
                state.pendingDraftReview = pending
                state.latestSelfCheck = snapshot.latestSelfCheck ?? pending.selfCheck
            } else if pending != nil, pendingStatus == .confirmed {
                state.title = snapshot.title
                state.summary = snapshot.summary
                state.content = snapshot.content
                state.pendingDraftReview = nil
                state.latestSelfCheck = nil
            } else if let pending {
                state.title = pending.before.title
                state.summary = pending.before.summary
                state.content = pending.before.content
                state.pendingDraftReview = nil
                state.latestSelfCheck = nil
            } else {
                state.title = snapshot.title
                state.summary = snapshot.summary
                state.content = snapshot.content
                state.pendingDraftReview = nil
                state.latestSelfCheck = snapshot.latestSelfCheck
            }
        }

        if let pending, pendingStatus == .missing {
            autosave.persist(self.snapshot())
            hasUnflushedChanges = false
            return .restoredAfterDroppingDanglingPending(versionID: pending.draftVersionID)
        }
        if let pending, pendingStatus == .confirmed {
            autosave.persist(self.snapshot())
            hasUnflushedChanges = false
            return .restoredAfterReconcilingConfirmedPending(versionID: pending.draftVersionID)
        }
        hasUnflushedChanges = false
        return .restored
    }

    /// 用户明确放弃启动时的恢复提示；不改变当前编辑器内容。
    package func discardAutosavedDraft() {
        autosave.cancelPending()
        autosave.clear()
        hasUnflushedChanges = false
        if state.showAutosaveRestorePrompt {
            update(autosave: .none) { $0.showAutosaveRestorePrompt = false }
        }
    }

    package var hasAutosavedDraft: Bool {
        autosave.load() != nil
    }

    package var hasUnsavedChanges: Bool {
        Self.editableDraft(from: state) != persistedBaseline
    }

    /// App 进入后台或退出前可同步冲刷，不依赖 View 的 onChange。
    package func saveAutosaveSnapshotNow() {
        guard hasUnflushedChanges else { return }
        autosave.cancelPending()
        writeAutosaveSnapshot()
    }

    private enum AutosavePolicy {
        case none
        case debounced
    }

    private var currentDraftSnapshot: DraftSnapshot {
        DraftSnapshot(title: state.title, summary: state.summary, content: state.content)
    }

    private func update(
        autosave policy: AutosavePolicy,
        _ change: (inout State) -> Void
    ) {
        var next = state
        change(&next)
        next.revision = state.revision + 1
        state = next

        if policy == .debounced {
            hasUnflushedChanges = true
            scheduleAutosave()
        }
    }

    private func scheduleAutosave() {
        autosave.schedule(debounceNanoseconds: autosaveDebounceNanoseconds) { [weak self] in
            self?.writeAutosaveSnapshot()
        }
    }

    private func writeAutosaveSnapshot() {
        guard hasRecoverableWork else {
            autosave.clear()
            hasUnflushedChanges = false
            return
        }
        autosave.persist(snapshot())
        hasUnflushedChanges = false
    }

    private var hasRecoverableWork: Bool {
        if state.selectedArticleID != nil || state.pendingDraftReview != nil || !state.tags.isEmpty {
            return true
        }
        return [
            state.title,
            state.summary,
            state.content,
            state.outline,
            state.ideaInput,
            state.writingDirection,
            state.materials
        ]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty == false
    }

    private func matchingPending(versionID: Int) throws -> PendingDraftReview {
        guard let pending = state.pendingDraftReview else {
            throw TransitionError.pendingReviewNotFound
        }
        guard pending.draftVersionID == versionID else {
            throw TransitionError.pendingReviewVersionMismatch(
                expected: pending.draftVersionID,
                received: versionID
            )
        }
        return pending
    }

    private static func editableDraft(from state: State) -> EditableDraft {
        EditableDraft(
            title: state.title,
            summary: state.summary,
            content: state.content,
            outline: state.outline,
            ideaInput: state.ideaInput,
            writingDirection: state.writingDirection,
            materials: state.materials,
            tags: state.tags
        )
    }

    private func requireResolvedPendingIfNeeded(_ resolvedVersionID: Int?) throws {
        guard let pending = state.pendingDraftReview else {
            if resolvedVersionID != nil {
                throw TransitionError.pendingReviewNotFound
            }
            return
        }
        guard let resolvedVersionID else {
            throw TransitionError.pendingReviewResolutionRequired(versionID: pending.draftVersionID)
        }
        guard pending.draftVersionID == resolvedVersionID else {
            throw TransitionError.pendingReviewVersionMismatch(
                expected: pending.draftVersionID,
                received: resolvedVersionID
            )
        }
    }
}

extension WritingSession.TransitionError: LocalizedError {
    package var errorDescription: String? {
        switch self {
        case let .pendingReviewAlreadyStaged(versionID):
            return "版本 #\(versionID) 仍待复核，请先确认或放弃"
        case .pendingReviewNotFound:
            return "待复核版本已不存在，请刷新后重试"
        case let .pendingReviewVersionMismatch(expected, received):
            return "待复核版本不匹配（期望 #\(expected)，收到 #\(received)）"
        case let .pendingReviewResolutionRequired(versionID):
            return "版本 #\(versionID) 仍待复核，无法切换写作会话"
        case .candidateBasedOnStaleDraft:
            return "模型运行期间正文已经变化，旧结果已安全丢弃"
        case .candidateBasedOnStaleRevision:
            return "模型运行期间稿件或素材已经变化，旧结果已安全丢弃"
        }
    }
}
