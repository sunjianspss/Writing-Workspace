import Foundation
import CreativeWorkshopCore

/// R5 瘦身·任务 23：自动保存与草稿恢复（19.3.1）。存储与防抖在 Core 的 `AutosaveController`，
/// 这里保留快照的字段收集与应用（纯 UI 状态绑定）。
extension WorkshopStore {
    var hasAutosavedDraft: Bool {
        autosave.load() != nil
    }

    func scheduleAutosaveSnapshot() {
        guard !isApplyingAutosaveSnapshot else { return }
        autosave.schedule { [weak self] in
            self?.writeAutosaveSnapshot()
        }
    }

    func saveAutosaveSnapshot() {
        autosave.cancelPending()
        writeAutosaveSnapshot()
    }

    private func writeAutosaveSnapshot() {
        guard !isApplyingAutosaveSnapshot else { return }

        let hasDraftContent = [
            title,
            summary,
            content,
            outline,
            ideaInput,
            materials
        ]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        guard hasDraftContent || pendingDraftReview != nil else {
            clearAutosaveSnapshot()
            return
        }

        autosave.persist(
            AutoSavedDraft(
                selectedArticleID: selectedArticleID,
                selectedTopicID: selectedTopicID,
                articleStatus: articleStatus,
                title: title,
                summary: summary,
                content: content,
                outline: outline,
                ideaInput: ideaInput,
                writingDirection: writingDirection,
                materials: materials,
                draftTags: draftTags,
                pendingDraftReview: pendingDraftReview,
                latestSelfCheck: latestSelfCheck,
                savedAt: Self.nowString()
            )
        )
    }

    func restoreAutosavedDraft() {
        guard let snapshot = autosave.load() else {
            showAutosaveRestorePrompt = false
            statusText = "没有可恢复的草稿"
            return
        }

        isApplyingAutosaveSnapshot = true
        defer { isApplyingAutosaveSnapshot = false }

        selectedArticleID = snapshot.selectedArticleID.flatMap { id in
            articles.contains(where: { $0.id == id }) ? id : nil
        }
        selectedTopicID = snapshot.selectedTopicID.flatMap { id in
            topics.contains(where: { $0.id == id }) ? id : nil
        }
        articleStatus = snapshot.articleStatus
        title = snapshot.title
        summary = snapshot.summary
        content = snapshot.content
        contentSelection = NSRange(location: 0, length: 0)
        outline = snapshot.outline
        ideaInput = snapshot.ideaInput
        writingDirection = snapshot.writingDirection
        materials = snapshot.materials
        draftTags = snapshot.draftTags
        pendingDraftReview = snapshot.pendingDraftReview
        latestSelfCheck = snapshot.latestSelfCheck
        if let selectedArticleID {
            latestReview = try? database.listWritingReviews(articleID: selectedArticleID, limit: 1).first
            latestPublishAssets = try? database.listPublishAssets(articleID: selectedArticleID, limit: 1).first
            latestAdvisorRun = try? database.listWritingAdvisorRuns(articleID: selectedArticleID, limit: 1).first
            draftVersions = (try? database.listDraftVersions(articleID: selectedArticleID, limit: 8)) ?? []
        } else {
            latestReview = nil
            latestPublishAssets = nil
            latestAdvisorRun = nil
            draftVersions = []
        }
        showAutosaveRestorePrompt = false
        statusText = "已恢复未保存草稿"
    }

    func discardAutosavedDraft() {
        clearAutosaveSnapshot()
        showAutosaveRestorePrompt = false
        statusText = "已丢弃未保存草稿"
    }

    func clearAutosaveSnapshot() {
        autosave.clear()
    }

    static func nowString() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
