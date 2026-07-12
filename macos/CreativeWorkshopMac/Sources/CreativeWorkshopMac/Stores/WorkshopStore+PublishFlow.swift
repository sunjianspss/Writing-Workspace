import Foundation
import CreativeWorkshopCore

/// 24.1 发布流程引导：把"草稿 → 待复核 → 已发布 → 已归档"从平级状态变成有方向的路径。
/// 护栏为主（未发布直接归档需确认，可一键补走发布链），可视化为辅（流程指示条）。
extension WorkshopStore {
    /// 流程指示条的固定站点（"已发布"站会产生终审与编辑量记录，是数据链的必经站）。
    static let publishFlowStages = ["构思", "初稿", "待复核", "已发布", "已归档"]

    /// 当前所处站点（供指示条高亮）。
    var publishFlowStageIndex: Int {
        if articleStatus == "已归档" { return 4 }
        if articleStatus == "已发布" { return 3 }
        if pendingDraftReview != nil { return 2 }
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 1 }
        return 0
    }

    /// 状态变更的受护栏入口：已有文章未经"已发布"直接翻"已归档"时先确认，
    /// 其余情况直通既有路径。UI 的状态按钮一律走这里。
    func requestArticleStatusChange(_ status: String) async {
        let persistedStatus = selectedArticle?.status ?? articleStatus
        if status == "已归档",
           selectedArticleID != nil,
           persistedStatus != "已发布",
           persistedStatus != "已归档" {
            showArchiveWithoutPublishPrompt = true
            return
        }
        await updateSelectedArticleStatus(status)
    }

    /// "先发布再归档"：补走完整数据链——发表前终审 + 编辑量记录（北极星）→ 归档。
    func archiveAfterPublishing() async {
        showArchiveWithoutPublishPrompt = false
        await updateSelectedArticleStatus("已发布")
        await updateSelectedArticleStatus("已归档")
        statusText = "已发布并归档（终审与编辑量已记录）"
    }

    /// "仍然归档"：真正弃稿的草稿不该假装发布，语义保持诚实。
    func archiveWithoutPublishing() async {
        showArchiveWithoutPublishPrompt = false
        await updateSelectedArticleStatus("已归档")
    }

    func cancelArchivePrompt() {
        showArchiveWithoutPublishPrompt = false
    }
}
