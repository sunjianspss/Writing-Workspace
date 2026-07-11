import Foundation

/// R5 瘦身·任务 22：记忆闭环（作者雷区 18.3.3 + 编辑偏好 20.4）的领域服务。
/// 两套流程共享同一条铁律：**归纳只产候选、绝不写库；写库只发生在作者逐条确认之后**——
/// 本服务的 summarize* 方法不含任何写库调用，confirm*/delete* 是仅有的写路径，
/// 且确认前先做重复守卫。UI 状态（候选列表 @Published、statusText）仍归 WorkshopStore。
package struct MemoryLoopService {
    package enum Confirmation {
        /// 已写入风格档案，携带保存后的档案。
        case added(StyleProfile)
        /// 该条已存在（幂等：不重复写库）。
        case alreadyConfirmed
    }

    package struct PitfallSummaryOutcome {
        /// 已过滤掉与已确认雷区重复的候选。
        package var candidates: [PitfallCandidate]
        package var run: AIRun<PitfallSummaryResult>
    }

    package enum EditPreferenceSummaryOutcome {
        /// 发布编辑记录不足（至少 2 条），未发起模型调用。
        case insufficientRecords(count: Int)
        /// 已归纳；candidates 已过滤与已确认偏好重复项。
        case summarized(candidates: [EditPreferenceCandidate], monthlySummary: String?, run: AIRun<EditPreferenceSummaryResult>)
    }

    private let database: NativeDatabase
    private let executor: AIWorkflowExecuting

    package init(database: NativeDatabase, executor: AIWorkflowExecuting) {
        self.database = database
        self.executor = executor
    }

    // MARK: - 作者雷区（18.3.3）

    package func summarizePitfallCandidates(
        issues: [(reviewID: Int, dimension: String, problem: String)],
        style: StyleProfile,
        template: PromptTemplate?,
        config: ModelConfig,
        apiKey: String
    ) async -> PitfallSummaryOutcome {
        let run: AIRun<PitfallSummaryResult> = await executor.execute(
            NativeWorkflowCatalog.summarizePitfalls(issues: issues, style: style, template: template),
            config: config,
            apiKey: apiKey
        )
        let existing = Set((style.known_pitfalls ?? []).map(\.description))
        let candidates = (run.result.candidates ?? []).filter { !existing.contains($0.description) }
        return PitfallSummaryOutcome(candidates: candidates, run: run)
    }

    package func confirmPitfall(_ candidate: PitfallCandidate, style: StyleProfile) throws -> Confirmation {
        var updated = style
        var pitfalls = updated.known_pitfalls ?? []
        guard !pitfalls.contains(where: { $0.description == candidate.description }) else {
            return .alreadyConfirmed
        }
        pitfalls.append(
            AuthorPitfall(
                description: candidate.description,
                source_review_id: candidate.supporting_review_ids?.first,
                created_at: nil
            )
        )
        updated.known_pitfalls = pitfalls
        return .added(try database.saveStyleProfile(id: style.id, profile: updated))
    }

    package func deletePitfall(_ pitfall: AuthorPitfall, style: StyleProfile) throws -> StyleProfile {
        var updated = style
        updated.known_pitfalls = (updated.known_pitfalls ?? []).filter { $0.id != pitfall.id }
        return try database.saveStyleProfile(id: style.id, profile: updated)
    }

    // MARK: - 编辑偏好（20.4）

    package func summarizeEditPreferenceCandidates(
        style: StyleProfile,
        template: PromptTemplate?,
        config: ModelConfig,
        apiKey: String
    ) async throws -> EditPreferenceSummaryOutcome {
        let records = try database.listEditRecords(limit: 80)
        guard records.count >= 2 else {
            return .insufficientRecords(count: records.count)
        }
        let run: AIRun<EditPreferenceSummaryResult> = await executor.execute(
            NativeWorkflowCatalog.summarizeEditPreferences(records: records, style: style, template: template),
            config: config,
            apiKey: apiKey
        )
        let existing = Set((style.learned_preferences ?? []).map(\.description))
        let candidates = (run.result.candidates ?? []).filter { !existing.contains($0.description) }
        return .summarized(candidates: candidates, monthlySummary: run.result.monthly_summary, run: run)
    }

    package func confirmEditPreference(_ candidate: EditPreferenceCandidate, style: StyleProfile) throws -> Confirmation {
        var updated = style
        var preferences = updated.learned_preferences ?? []
        guard !preferences.contains(where: { $0.description == candidate.description }) else {
            return .alreadyConfirmed
        }
        preferences.append(
            LearnedPreference(
                description: candidate.description,
                source_edit_record_ids: candidate.source_edit_record_ids,
                created_at: nil
            )
        )
        updated.learned_preferences = preferences
        return .added(try database.saveStyleProfile(id: style.id, profile: updated))
    }

    package func deleteEditPreference(_ preference: LearnedPreference, style: StyleProfile) throws -> StyleProfile {
        var updated = style
        updated.learned_preferences = (updated.learned_preferences ?? []).filter { $0.id != preference.id }
        return try database.saveStyleProfile(id: style.id, profile: updated)
    }
}
