import Foundation
import CreativeWorkshopCore

/// 24.1 发布流程引导：把"草稿 → 待复核 → 已发布 → 已归档"从平级状态变成有方向的路径。
/// 护栏为主（未发布直接归档需确认，可一键补走发布链），可视化为辅（流程指示条）。
extension WorkshopStore {
    /// 流程指示条的固定站点（"已发布"站会产生终审与编辑量记录，是数据链的必经站）。
    static let publishFlowStages = ["构思", "初稿", "待复核", "已发布", "已归档"]

    /// 当前所处站点（供指示条高亮）。
    var publishFlowStageIndex: Int {
        if articleStatus == Article.archivedStatus { return 4 }
        if articleStatus == Article.publishedStatus { return 3 }
        if pendingDraftReview != nil { return 2 }
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 1 }
        return 0
    }

    /// 发布这一段的「下一步」。
    ///
    /// 写作是非线性的，但发布不是——草稿 → 已发布 → 已归档 只有一个方向。此前界面把它
    /// 摊成「分段选择器 + 更新状态 + 归档 + 保存」四个语义重叠的控件，作者选了分段却不
    /// 知道还要点「更新状态」，而点「保存」会把状态顺手写库却跳过终审与编辑量记录。
    /// 这里把"现在该做什么"收敛成一个答案。
    enum PublishStep: Equatable {
        /// 还没存成文章，发布流程无从谈起。
        case needsSave
        /// 可以发表：跑终审 + 记编辑量 + 写 published_at。
        case publish
        /// 已发表，下一步是归档。
        case archive
        /// 已归档且确实走过发表，流程走完。
        case done
        /// 已归档但从没走过发表（published_at 为空）——数据链缺了一环，可以补记。
        case archivedWithoutPublishing

        var primaryTitle: String? {
            switch self {
            case .needsSave: return nil
            case .publish: return "发表这篇"
            case .archive: return "归档"
            case .done: return nil
            case .archivedWithoutPublishing: return "补记发表"
            }
        }

        var hint: String {
            switch self {
            case .needsSave: return "先保存成文章，才能进入发布流程。"
            case .publish: return "发表会先跑一次发表前终审，并记录这篇的编辑量。"
            case .archive: return "已发表。归档后它会从「我的文章」的在写列表里移出。"
            case .done: return "这篇已经走完整条流程。"
            case .archivedWithoutPublishing: return "这篇直接归档了，没经过「已发布」，所以终审和编辑量都没记。补记会补上这两样，状态仍留在已归档。"
            }
        }
    }

    var publishStep: PublishStep {
        guard let article = selectedArticle else { return .needsSave }
        let published = (article.published_at ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch article.status {
        case Article.publishedStatus:
            return .archive
        case Article.archivedStatus:
            return published.isEmpty ? .archivedWithoutPublishing : .done
        default:
            return .publish
        }
    }

    /// 执行「下一步」。主按钮只有一个动作，不需要作者先选状态再点应用。
    func advancePublishFlow() async {
        switch publishStep {
        case .needsSave, .done:
            return
        case .publish:
            await updateSelectedArticleStatus(Article.publishedStatus)
        case .archive:
            await requestArticleStatusChange(Article.archivedStatus)
        case .archivedWithoutPublishing:
            await backfillPublication()
        }
    }

    /// 补记发表：把跳过的那一环补上，但状态仍回到已归档——它确实已经归档了，
    /// 补记的是数据链不是事实。
    func backfillPublication() async {
        await updateSelectedArticleStatus(Article.publishedStatus)
        guard selectedArticle?.status == Article.publishedStatus else { return }
        await updateSelectedArticleStatus(Article.archivedStatus)
        statusText = "已补记发表（终审与编辑量已记录），状态仍为已归档"
    }

    /// 状态变更的受护栏入口：已有文章未经"已发布"直接翻"已归档"时先确认，
    /// 其余情况直通既有路径。UI 的状态按钮一律走这里。
    func requestArticleStatusChange(_ status: String) async {
        let persistedStatus = selectedArticle?.status ?? articleStatus
        if status == Article.archivedStatus,
           selectedArticleID != nil,
           persistedStatus != Article.publishedStatus,
           persistedStatus != Article.archivedStatus {
            showArchiveWithoutPublishPrompt = true
            return
        }
        await updateSelectedArticleStatus(status)
    }

    /// "先发布再归档"：补走完整数据链——发表前终审 + 编辑量记录（北极星）→ 归档。
    func archiveAfterPublishing() async {
        showArchiveWithoutPublishPrompt = false
        await updateSelectedArticleStatus(Article.publishedStatus)
        await updateSelectedArticleStatus(Article.archivedStatus)
        statusText = "已发布并归档（终审与编辑量已记录）"
    }

    /// "仍然归档"：真正弃稿的草稿不该假装发布，语义保持诚实。
    func archiveWithoutPublishing() async {
        showArchiveWithoutPublishPrompt = false
        await updateSelectedArticleStatus(Article.archivedStatus)
    }

    func cancelArchivePrompt() {
        showArchiveWithoutPublishPrompt = false
    }
}
