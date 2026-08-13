import Foundation
import CreativeWorkshopCore

/// 自动保存的状态采集、调度和悬空 pending 修复均由 WritingSession 负责。
/// Store 只提供数据库存在性投影，并在恢复后刷新与文章关联的只读集合。
extension WorkshopStore {
    var hasAutosavedDraft: Bool {
        writingSession.hasAutosavedDraft
    }

    func saveAutosaveSnapshot() {
        writingSession.saveAutosaveSnapshotNow()
    }

    func restoreAutosavedDraft() {
        let result = writingSession.restoreAutosavedDraft(
            articleStatus: { [database] id in
                do {
                    return try database.articleExists(id: id) ? .valid : .missing
                } catch {
                    return .unknown
                }
            },
            topicStatus: { [database] id in
                do {
                    return try database.topicExists(id: id) ? .valid : .missing
                } catch {
                    return .unknown
                }
            },
            pendingVersionStatus: { [database] id in
                let version: DraftVersion?
                do {
                    version = try database.draftVersion(id: id)
                } catch {
                    return .unknown
                }
                guard let version else {
                    return .missing
                }
                return version.review_status == "pending" ? .pending : .confirmed
            }
        )

        if result == .deferredUntilDatabaseAvailable {
            statusText = "暂时无法校验恢复草稿，已保留快照，请稍后重试"
            return
        }
        guard result != .unavailable else {
            statusText = "没有可恢复的草稿"
            return
        }

        contentSelection = NSRange(location: 0, length: 0)
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

        switch result {
        case let .restoredAfterDroppingDanglingPending(versionID):
            statusText = "已恢复草稿；待复核版本 #\(versionID) 已不存在，正文已安全回退"
        case let .restoredAfterReconcilingConfirmedPending(versionID):
            statusText = "已恢复草稿；版本 #\(versionID) 已确认，正文已采用定稿"
        case .restored:
            statusText = "已恢复未保存草稿"
        case .deferredUntilDatabaseAvailable:
            break
        case .unavailable:
            break
        }
    }

    func discardAutosavedDraft() {
        writingSession.discardAutosavedDraft()
        statusText = "已丢弃未保存草稿"
    }

    func clearAutosaveSnapshot() {
        writingSession.discardAutosavedDraft()
    }

    static func nowString() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
