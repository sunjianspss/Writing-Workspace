import Foundation

/// R5 瘦身·任务 21：待复核状态机（PRD 18.4.1 / 21.3 R5 点名"可独立成类型"）。
/// 持有数据库，暴露纯语义的状态迁移：交付（pending 落库 + 待复核卡组装）、确认（翻 confirmed）、
/// 放弃（删行，快照恢复由调用方执行）、孤儿清理（隐式放弃，绝不误删 confirmed）。
/// UI 状态（@Published）、编辑器快照应用与 statusText 仍归 WorkshopStore。
package struct PendingReviewMachine {
    private let database: NativeDatabase

    package init(database: NativeDatabase) {
        self.database = database
    }

    /// 交付（18.4.1）：把生成产物存为 pending 版本，并组装待复核卡。
    package func deliver(
        articleID: Int?,
        titleSnapshot: String,
        actionTitle: String,
        note: String?,
        before: DraftSnapshot,
        after: DraftSnapshot,
        usedFallback: Bool,
        selfCheck: DraftSelfCheckResult?,
        matchedPitfalls: [AuthorPitfall],
        agentTrace: AgentDraftTrace?,
        retrievedFragments: [RetrievedFragment],
        sectionFragmentContexts: [SectionFragmentContext],
        iterationSummary: [DeepDraftIteration]?,
        candidateJudgement: CandidateJudgeResult?,
        styleSamples: StyleSampleProvenance? = nil
    ) throws -> (version: DraftVersion, pending: PendingDraftReview) {
        let version = try database.saveDraftVersion(
            articleID: articleID,
            titleSnapshot: titleSnapshot,
            action: actionTitle,
            note: note,
            before: before,
            after: after,
            reviewStatus: "pending"
        )
        let pending = PendingDraftReview(
            draftVersionID: version.id,
            actionTitle: actionTitle,
            articleID: version.article_id,
            before: before,
            after: after,
            note: note,
            usedFallback: usedFallback,
            selfCheck: selfCheck,
            matchedPitfalls: matchedPitfalls,
            agentTrace: agentTrace,
            retrievedFragments: retrievedFragments,
            sectionFragmentContexts: sectionFragmentContexts,
            iterationSummary: iterationSummary,
            candidateJudgement: candidateJudgement,
            styleSamples: styleSamples
        )
        return (version, pending)
    }

    /// 确认（18.4.1）：pending → confirmed，返回更新后的行。
    package func confirm(versionID: Int) throws -> DraftVersion {
        try database.confirmDraftVersion(id: versionID)
    }

    /// 放弃（18.4.1）：删除该行。正文回退到 pending.before 由调用方（持有编辑器状态的一方）执行。
    package func discard(versionID: Int) throws {
        try database.deleteDraftVersion(id: versionID)
    }

    /// 孤儿清理（切换文章/新建草稿时的隐式放弃）：只删仍处 pending 的行，
    /// confirmed 行绝不允许被隐式清理误删。
    package func cleanupOrphan(versionID: Int) throws {
        guard let row = try database.draftVersion(id: versionID),
              row.review_status == "pending" else {
            return
        }
        try database.deleteDraftVersion(id: versionID)
    }
}
