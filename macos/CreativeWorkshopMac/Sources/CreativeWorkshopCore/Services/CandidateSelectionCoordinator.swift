import Foundation

/// R5 瘦身·任务 20：多候选优选与深度成稿的编排，自 `WorkshopStore.generateDraftAlternatives`
/// 迁入（21.5 护栏生效前的历史遗留）。流程：三个 PolishMode 候选 → 评委随机呈现排序（22.3.4）
/// → 最优候选接入 DeepDraftCoordinator（20.6）。
/// 数据库写入经注入闭包完成，本协调器不持有 NativeDatabase。
package struct CandidateSelectionInput {
    package var base: DraftSnapshot
    /// 候选润色用上下文。
    package var context: ContextPackage
    /// 评委用上下文（调用方已 applyDraftSnapshot(base)）。
    package var judgeContext: ContextPackage
    package var style: StyleProfile
    package var outline: String
    package var idea: String
    package var direction: String
    package var previousReview: WritingReview?
    package var polishTemplate: PromptTemplate?
    package var judgeTemplate: PromptTemplate?
    package var writingReviewTemplate: PromptTemplate?
    package var config: ModelConfig
    package var apiKey: String
    /// 评委呈现顺序的随机源；用毕经 Output.shuffleRNG 归还，保持调用方序列连续（22.3.4 可复现性）。
    package var shuffleRNG: AnyRandomNumberGenerator

    package init(
        base: DraftSnapshot,
        context: ContextPackage,
        judgeContext: ContextPackage,
        style: StyleProfile,
        outline: String,
        idea: String,
        direction: String,
        previousReview: WritingReview?,
        polishTemplate: PromptTemplate?,
        judgeTemplate: PromptTemplate?,
        writingReviewTemplate: PromptTemplate?,
        config: ModelConfig,
        apiKey: String,
        shuffleRNG: AnyRandomNumberGenerator
    ) {
        self.base = base
        self.context = context
        self.judgeContext = judgeContext
        self.style = style
        self.outline = outline
        self.idea = idea
        self.direction = direction
        self.previousReview = previousReview
        self.polishTemplate = polishTemplate
        self.judgeTemplate = judgeTemplate
        self.writingReviewTemplate = writingReviewTemplate
        self.config = config
        self.apiKey = apiKey
        self.shuffleRNG = shuffleRNG
    }
}

package struct CandidateSelectionOutput {
    package var candidates: [DraftCandidate]
    package var createdVersions: [DraftVersion]
    package var selectedCandidate: DraftCandidate
    package var judgeResult: CandidateJudgeResult
    package var judgeSuccess: Bool
    package var judgeError: String
    package var deepOutput: DeepDraftOutput
    package var retrievedFragments: [RetrievedFragment]
    /// 候选 3 步 + 评委 1 步 + 深度成稿各步，已统一重编号。
    package var steps: [AgentStepPayload]
    /// 归还给调用方的随机源。
    package var shuffleRNG: AnyRandomNumberGenerator
}

package struct CandidateSelectionCoordinator {
    /// 版本落库回调：before 恒为本次会话的基稿快照，由调用方捕获。
    package typealias SaveVersion = (_ action: String, _ note: String, _ after: DraftSnapshot) throws -> DraftVersion
    /// 本地素材检索回调（评委选定候选后按其标题组 query）。
    package typealias Retrieve = (_ query: String) throws -> (materials: String, fragments: [RetrievedFragment])

    private let executor: AIWorkflowExecuting
    private let saveVersion: SaveVersion
    private let retrieve: Retrieve

    package init(
        executor: AIWorkflowExecuting,
        saveVersion: @escaping SaveVersion,
        retrieve: @escaping Retrieve
    ) {
        self.executor = executor
        self.saveVersion = saveVersion
        self.retrieve = retrieve
    }

    package func run(input: CandidateSelectionInput) async throws -> CandidateSelectionOutput {
        var rng = input.shuffleRNG
        let modes: [PolishMode] = [.natural, .tighten, .deepen]
        var createdVersions: [DraftVersion] = []
        var candidates: [DraftCandidate] = []
        var steps: [AgentStepPayload] = []

        for (offset, mode) in modes.enumerated() {
            let polishRun: AIRun<DraftResult> = await executor.execute(
                NativeWorkflowCatalog.polishDraft(
                    context: input.context,
                    content: input.base.content,
                    mode: mode,
                    style: input.style,
                    template: input.polishTemplate
                ),
                config: input.config,
                apiKey: input.apiKey
            )
            try Task.checkCancellation()
            steps.append(
                AgentStepPayload(
                    step_index: offset + 1,
                    name: "候选·\(mode.title)",
                    status: polishRun.success ? "success" : "fallback",
                    input_summary: polishRun.inputSummary,
                    output_summary: polishRun.outputSummary,
                    elapsed_ms: polishRun.elapsedMS,
                    error: polishRun.error
                )
            )

            let after = Self.mergedSnapshot(from: polishRun.result, base: input.base)
            candidates.append(
                DraftCandidate(
                    index: offset + 1,
                    label: mode.title,
                    title: after.title,
                    summary: after.summary,
                    content: after.content
                )
            )
            let note = polishRun.success
                ? "多版本候选：\(mode.promptInstruction)"
                : "本地候选：\(polishRun.error.isEmpty ? "未配置 API Key" : polishRun.error)"
            // 这是 18 章之前就有的"多版本候选"功能：选择方式是在下方版本列表里逐个"恢复后"预览再手动保存，
            // 不走 18.4.1 新增的 pending/confirmed 待复核闭环，因此维持默认的 `confirmed`，不引入第三种状态。
            createdVersions.append(try saveVersion("候选·\(mode.title)", note, after))
        }

        // 22.3.4：只打乱送评的呈现顺序，candidate.index 仍是稳定编号，评委按编号解析 best_candidate_index。
        let presentedCandidates = candidates.shuffled(using: &rng)
        let presentationOrderText = "呈现顺序：\(presentedCandidates.map { String($0.index) }.joined(separator: ","))"
        let judgeRun: AIRun<CandidateJudgeResult> = await executor.execute(
            NativeWorkflowCatalog.judgeDraftCandidates(
                context: input.judgeContext,
                base: input.base,
                candidates: presentedCandidates,
                style: input.style,
                template: input.judgeTemplate
            ),
            config: input.config,
            apiKey: input.apiKey
        )
        try Task.checkCancellation()
        steps.append(
            AgentStepPayload(
                step_index: steps.count + 1,
                name: "候选评委排序",
                status: judgeRun.success ? "success" : "fallback",
                input_summary: [presentationOrderText, judgeRun.inputSummary]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n---\n"),
                output_summary: judgeRun.outputSummary,
                elapsed_ms: judgeRun.elapsedMS,
                error: judgeRun.error
            )
        )

        let bestIndex = judgeRun.result.best_candidate_index ?? candidates.first?.index ?? 1
        let selectedCandidate = candidates.first { $0.index == bestIndex } ?? candidates[0]
        let retrieval = try retrieve([selectedCandidate.title, input.idea, input.outline].joined(separator: "\n"))
        let deepOutput = try await DeepDraftCoordinator(aiClient: executor).run(
            input: DeepDraftInput(
                title: selectedCandidate.title,
                summary: selectedCandidate.summary,
                content: selectedCandidate.content,
                outline: input.outline,
                idea: input.idea,
                direction: input.direction,
                materials: retrieval.materials,
                style: input.style,
                previousReview: input.previousReview,
                writingReviewTemplate: input.writingReviewTemplate,
                config: input.config,
                apiKey: input.apiKey
            )
        )

        return CandidateSelectionOutput(
            candidates: candidates,
            createdVersions: createdVersions,
            selectedCandidate: selectedCandidate,
            judgeResult: judgeRun.result,
            judgeSuccess: judgeRun.success,
            judgeError: judgeRun.error,
            deepOutput: deepOutput,
            retrievedFragments: retrieval.fragments,
            steps: AgentRunPayloads.reindexed(steps + deepOutput.steps),
            shuffleRNG: rng
        )
    }

    /// 与迁移前 WorkshopStore.draftSnapshot(from:base:) 相同的合并语义。
    private static func mergedSnapshot(from result: DraftResult, base: DraftSnapshot) -> DraftSnapshot {
        DraftSnapshot(
            title: result.title ?? base.title,
            summary: result.summary ?? base.summary,
            content: result.content ?? result.raw_output ?? base.content
        )
    }
}
