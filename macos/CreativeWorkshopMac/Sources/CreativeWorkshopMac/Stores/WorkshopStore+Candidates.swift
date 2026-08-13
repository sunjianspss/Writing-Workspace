import Foundation
import CreativeWorkshopCore

/// R5 瘦身·任务 20：多候选优选的编排已迁入 Core 的 `CandidateSelectionCoordinator`，
/// 这里只保留"构造输入 → 调协调器 → 应用结果到状态"的薄绑定（模式同 +AdvisorPlan / +AgentSession）。
extension WorkshopStore {
    func generateDraftAlternatives() async {
        guard canPolishDraft else {
            statusText = "请先完成一版正文"
            return
        }
        guard pendingDraftReview == nil else {
            statusText = "还有未确认的生成结果，请先确认或放弃"
            return
        }

        await run("生成多版本候选", cancellable: true) {
            let checkpoint = self.captureWritingSessionCheckpoint()
            let style = try self.resolveStyle()
            let base = self.currentDraftSnapshot()
            let context = self.currentWritingContext(style: style)
            var judgeContext = self.currentWritingContext(style: style)
            judgeContext.applyDraftSnapshot(base)

            // 保持迁移前"候选边生成边可见"的时序：每落一个版本立即更新列表。
            let existingVersions = self.draftVersions
            var createdSoFar: [DraftVersion] = []
            let coordinator = CandidateSelectionCoordinator(
                executor: self.aiClient,
                saveVersion: { action, note, after in
                    try self.requireWritingSessionCheckpoint(checkpoint)
                    let outcome = try self.writingWorkflow.execute(.recordDraftVersion(.init(
                        articleID: checkpoint.articleID,
                        titleSnapshot: checkpoint.titleSnapshot,
                        action: action,
                        note: note,
                        before: base,
                        after: after
                    )))
                    guard case let .draftVersionRecorded(version) = outcome else {
                        preconditionFailure("WritingWorkflow returned an invalid version outcome")
                    }
                    createdSoFar.append(version)
                    self.draftVersions = createdSoFar + existingVersions
                    return version
                },
                retrieve: { query in
                    let retrieval = try self.retrievedMaterialsBlock(query: query)
                    return (retrieval.materials, retrieval.fragments)
                }
            )

            let output = try await coordinator.run(
                input: CandidateSelectionInput(
                    base: base,
                    context: context,
                    judgeContext: judgeContext,
                    style: style,
                    outline: self.outline,
                    idea: self.ideaInput,
                    direction: self.normalizedDirection,
                    previousReview: self.latestReview,
                    polishTemplate: self.promptTemplate(for: .polishDraft),
                    judgeTemplate: self.promptTemplate(for: .candidateJudge),
                    writingReviewTemplate: self.promptTemplate(for: .writingReview),
                    config: self.currentModelConfig,
                    apiKey: self.apiKeyInput,
                    shuffleRNG: self.candidateShuffleRNG
                )
            )
            try self.requireWritingSessionCheckpoint(checkpoint)
            self.candidateShuffleRNG = output.shuffleRNG

            try self.recordAgentRun(
                runType: "多候选优选与深度成稿",
                status: output.steps.allSatisfy { $0.status == "success" } && output.deepOutput.success ? "success" : "fallback",
                summary: [
                    "已生成 \(output.createdVersions.count) 个全文候选，默认采用候选 \(output.selectedCandidate.index)。",
                    output.judgeResult.bestReason,
                    output.deepOutput.summaryText
                ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                elapsedMS: output.steps.reduce(0) { $0 + $1.elapsed_ms },
                inputSummary: context.summaryText,
                outputSummary: [
                    output.createdVersions.map(\.action).joined(separator: "；"),
                    output.judgeResult.summary ?? "",
                    output.deepOutput.summaryText
                ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n---\n"),
                error: output.steps.map(\.error).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "；"),
                steps: output.steps
            )
            try await self.finalizeGeneratedDraft(
                result: output.deepOutput.draft,
                fallbackTitle: output.selectedCandidate.title,
                style: style,
                actionTitle: "多候选优选·深度成稿",
                successNote: [
                    "评委默认采用候选 \(output.selectedCandidate.index)：\(output.judgeResult.bestReason ?? "完成候选排序")",
                    output.deepOutput.summaryText
                ].joined(separator: "\n"),
                failureNote: [
                    output.judgeError,
                    output.deepOutput.error
                ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "；"),
                usedFallback: !output.judgeSuccess || !output.deepOutput.success,
                clearArticleSelection: false,
                retrievedFragments: output.retrievedFragments,
                iterationSummary: output.deepOutput.iterations,
                candidateJudgement: output.judgeResult,
                checkpoint: checkpoint
            )
            self.statusText = "已生成 \(output.createdVersions.count) 个候选，候选 \(output.selectedCandidate.index) 已进入深度成稿，请确认或放弃"
        }
    }
}
