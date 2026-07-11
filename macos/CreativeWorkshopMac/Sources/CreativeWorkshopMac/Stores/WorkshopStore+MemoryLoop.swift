import Foundation
import CreativeWorkshopCore

/// R5 瘦身·任务 22：记忆闭环（雷区 18.3.3 / 编辑偏好 20.4）的领域逻辑在 Core 的
/// `MemoryLoopService`，这里只保留"调服务 → 更新 @Published → statusText"的薄绑定。
extension WorkshopStore {
    private var memoryLoop: MemoryLoopService {
        MemoryLoopService(database: database, executor: aiClient)
    }

    // MARK: - 作者雷区（18.3.3）

    /// 归纳该风格档案下反复出现的作者雷区候选：只生成候选，采纳与否由作者决定。
    func summarizeAuthorPitfalls() async {
        guard let style = selectedStyleProfile else {
            statusText = "请先选择风格"
            return
        }

        await run("归纳作者雷区", cancellable: true) {
            let issues = self.allIssuesHistory()
            guard !issues.isEmpty else {
                self.pitfallCandidates = []
                self.statusText = "暂无足够的历史诊断记录可供归纳"
                return
            }
            let outcome = await self.memoryLoop.summarizePitfallCandidates(
                issues: issues,
                style: style,
                template: self.promptTemplate(for: .pitfallSummary),
                config: self.currentModelConfig,
                apiKey: self.apiKeyInput
            )
            try Task.checkCancellation()
            try self.recordAgentRun(
                runType: "归纳作者雷区",
                status: outcome.run.success ? "success" : "fallback",
                summary: outcome.run.result.candidates?.prefix(3).map(\.description).joined(separator: "；"),
                elapsedMS: outcome.run.elapsedMS,
                inputSummary: outcome.run.inputSummary,
                outputSummary: outcome.run.outputSummary,
                error: outcome.run.error,
                steps: [
                    AgentRunPayloads.singleStep(
                        name: "归纳作者雷区",
                        success: outcome.run.success,
                        elapsedMS: outcome.run.elapsedMS,
                        inputSummary: outcome.run.inputSummary,
                        outputSummary: outcome.run.outputSummary,
                        error: outcome.run.error
                    )
                ]
            )
            self.pitfallCandidates = outcome.candidates
            self.statusText = self.pitfallCandidates.isEmpty ? "没有发现新的反复出现的问题" : "已归纳 \(self.pitfallCandidates.count) 条候选雷区，待确认"
        }
    }

    /// 作者手动确认一条候选雷区，写入当前风格档案的 `known_pitfalls`（归纳可以自动，写入必须人工确认）。
    func confirmPitfallCandidate(_ candidate: PitfallCandidate) async {
        guard let style = selectedStyleProfile else { return }
        await run("确认作者雷区") {
            if case let .added(saved) = try self.memoryLoop.confirmPitfall(candidate, style: style) {
                try self.refreshStyleProfilesAfterMemoryChange(saved: saved, styleID: style.id)
                self.statusText = "已加入作者雷区清单"
            }
            self.pitfallCandidates.removeAll { $0.description == candidate.description }
        }
    }

    func dismissPitfallCandidate(_ candidate: PitfallCandidate) {
        pitfallCandidates.removeAll { $0.description == candidate.description }
    }

    /// 从风格库删除一条已确认雷区，用于纠正误判或过时条目。
    func deleteConfirmedPitfall(_ pitfall: AuthorPitfall) async {
        guard let style = selectedStyleProfile else { return }
        await run("删除作者雷区") {
            let saved = try self.memoryLoop.deletePitfall(pitfall, style: style)
            try self.refreshStyleProfilesAfterMemoryChange(saved: saved, styleID: style.id)
            self.statusText = "已删除该雷区"
        }
    }

    // MARK: - 编辑偏好（20.4）

    /// 从发布前编辑记录归纳候选编辑偏好。候选只展示，必须人工确认后才注入 prompt。
    func summarizeEditPreferences() async {
        guard let style = selectedStyleProfile else {
            statusText = "请先选择风格"
            return
        }

        await run("归纳编辑偏好", cancellable: true) {
            let outcome = try await self.memoryLoop.summarizeEditPreferenceCandidates(
                style: style,
                template: self.promptTemplate(for: .editPreferenceSummary),
                config: self.currentModelConfig,
                apiKey: self.apiKeyInput
            )
            try Task.checkCancellation()
            switch outcome {
            case .insufficientRecords:
                self.editPreferenceCandidates = []
                self.statusText = "发布编辑记录还不足，至少发布 2 篇后再归纳偏好"
            case let .summarized(candidates, monthlySummary, run):
                try self.recordAgentRun(
                    runType: "归纳编辑偏好",
                    status: run.success ? "success" : "fallback",
                    summary: run.result.monthly_summary ?? run.result.candidates?.prefix(3).map(\.description).joined(separator: "；"),
                    elapsedMS: run.elapsedMS,
                    inputSummary: run.inputSummary,
                    outputSummary: run.outputSummary,
                    error: run.error,
                    steps: [
                        AgentRunPayloads.singleStep(
                            name: "归纳编辑偏好",
                            success: run.success,
                            elapsedMS: run.elapsedMS,
                            inputSummary: run.inputSummary,
                            outputSummary: run.outputSummary,
                            error: run.error
                        )
                    ]
                )
                self.editPreferenceCandidates = candidates
                self.editRecordMonthlySummary = monthlySummary ?? (try? PublishingMetricsRecorder(database: self.database).snapshot().monthlySummary) ?? self.editRecordMonthlySummary
                self.statusText = self.editPreferenceCandidates.isEmpty ? "没有发现新的编辑偏好候选" : "已归纳 \(self.editPreferenceCandidates.count) 条编辑偏好候选，待确认"
            }
        }
    }

    func confirmEditPreferenceCandidate(_ candidate: EditPreferenceCandidate) async {
        guard let style = selectedStyleProfile else { return }
        await run("确认编辑偏好") {
            if case let .added(saved) = try self.memoryLoop.confirmEditPreference(candidate, style: style) {
                try self.refreshStyleProfilesAfterMemoryChange(saved: saved, styleID: style.id)
                self.statusText = "已加入编辑偏好，后续生成会主动遵守"
            }
            self.editPreferenceCandidates.removeAll { $0.description == candidate.description }
        }
    }

    func dismissEditPreferenceCandidate(_ candidate: EditPreferenceCandidate) {
        editPreferenceCandidates.removeAll { $0.description == candidate.description }
    }

    func deleteConfirmedEditPreference(_ preference: LearnedPreference) async {
        guard let style = selectedStyleProfile else { return }
        await run("删除编辑偏好") {
            let saved = try self.memoryLoop.deleteEditPreference(preference, style: style)
            try self.refreshStyleProfilesAfterMemoryChange(saved: saved, styleID: style.id)
            self.statusText = "已删除该编辑偏好"
        }
    }

    // MARK: - 共用

    /// 记忆写回后同步风格库状态：刷新列表，若改的正是当前选中档案则同步编辑表单。
    private func refreshStyleProfilesAfterMemoryChange(saved: StyleProfile, styleID: Int) throws {
        styleProfiles = try database.listStyleProfiles()
        if selectedStyleProfileID == styleID {
            editStyleProfile(saved)
        }
    }

    /// 汇总用于雷区归纳的历史诊断问题。`writing_reviews` 未记录体裁，暂不按体裁细分，取全部历史。
    private func allIssuesHistory() -> [(reviewID: Int, dimension: String, problem: String)] {
        writingReviews
            .flatMap { review in review.issues.map { (reviewID: review.id, dimension: $0.dimension, problem: $0.problem) } }
    }
}
