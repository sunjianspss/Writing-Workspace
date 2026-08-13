import Foundation
import CreativeWorkshopCore

/// 会话切换是一个显式的数据损失边界：未保存编辑必须经作者确认，pending 必须先完成数据库清理。
extension WorkshopStore {
    func newDraft() {
        requestSessionSwitch(.newDraft)
    }

    func openArticle(_ article: Article?) {
        guard let article else {
            requestSessionSwitch(.newDraft)
            return
        }
        guard article.id != selectedArticleID else { return }
        requestSessionSwitch(.article(article))
    }

    func confirmPendingSessionSwitch() {
        guard let target = pendingSessionSwitch else { return }
        pendingSessionSwitch = nil
        performSessionSwitch(target)
    }

    func cancelPendingSessionSwitch() {
        pendingSessionSwitch = nil
        statusText = "已保留当前未保存修改"
    }

    private func requestSessionSwitch(_ target: PendingSessionSwitch) {
        guard !writingSession.hasUnsavedChanges else {
            pendingSessionSwitch = target
            statusText = "当前稿件有未保存修改，请确认后再切换"
            return
        }
        performSessionSwitch(target)
    }

    private func performSessionSwitch(_ target: PendingSessionSwitch) {
        do {
            let resolvedPendingID = try resolvePendingBeforeSessionSwitch()
            switch target {
            case .newDraft:
                try writingSession.startNewDraft(afterResolvingPendingVersionID: resolvedPendingID)
            case let .article(article):
                try writingSession.open(article, afterResolvingPendingVersionID: resolvedPendingID)
            }
        } catch {
            statusText = error.localizedDescription
            return
        }

        contentSelection = NSRange(location: 0, length: 0)
        latestReview = nil
        latestPublishAssets = nil
        latestPrePublishAudit = nil
        latestAdvisorRun = nil
        agentRuns = []
        draftVersions = []
        agentSessionAskAuthor = nil

        if case let .article(article) = target {
            let id = article.id
            latestReview = try? database.listWritingReviews(articleID: id, limit: 1).first
            latestPublishAssets = try? database.listPublishAssets(articleID: id, limit: 1).first
            latestPrePublishAudit = try? database.listPrePublishAudits(articleID: id, limit: 1).first
            latestAdvisorRun = try? database.listWritingAdvisorRuns(articleID: id, limit: 1).first
            agentRuns = (try? database.listAgentRuns(articleID: id, limit: 8)) ?? []
            draftVersions = (try? database.listDraftVersions(articleID: id, limit: 8)) ?? []
            statusText = "已打开文章"
        } else {
            statusText = "已新建写作会话"
        }
    }
}
