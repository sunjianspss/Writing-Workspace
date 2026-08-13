import Foundation
import CreativeWorkshopCore

/// 23.6 有界代理循环入口：编排全部在 Core 的 `WritingAgentCoordinator`；这里只做
/// Store 需要的入口守卫、输入组装与交付转发（21.5 护栏）。UI 在任务 15。
extension WorkshopStore {
    var canStartAgentSession: Bool {
        agentLabEnabled && !isLoading && pendingDraftReview == nil && agentSessionAskAuthor == nil
    }

    /// 会话启动入口：实验室开关关闭、有未确认的生成结果、或未配置 API Key 时直接拒绝，不进入循环。
    func startAgentSession() async {
        guard agentLabEnabled else {
            statusText = "请先在设置中开启「代理实验室」开关"
            return
        }
        guard pendingDraftReview == nil else {
            statusText = "还有未确认的生成结果，请先确认或放弃"
            return
        }
        guard !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "请先配置 API Key"
            return
        }
        await runAgentSession(resuming: nil)
    }

    /// 续跑此前因 ask_author 暂停的会话：预算与 askAuthorUsed 均继承自暂停时的状态快照。
    func resumeAgentSession() async {
        guard let prompt = agentSessionAskAuthor else { return }
        guard let checkpoint = checkpointForAgentPrompt(prompt) else {
            agentSessionAskAuthor = nil
            statusText = "暂停后正文或文章已经变化，旧代理会话已安全丢弃，请重新开始"
            return
        }
        agentSessionAskAuthor = nil
        await runAgentSession(resuming: prompt, checkpoint: checkpoint)
    }

    /// 作者在「代理提问」卡选择"就此结束"：不再消耗模型调用，直接按 finish 语义交付暂停时的最好版本。
    func finishAgentSessionNow() async {
        guard let prompt = agentSessionAskAuthor else { return }
        guard let checkpoint = checkpointForAgentPrompt(prompt) else {
            agentSessionAskAuthor = nil
            statusText = "暂停后正文或文章已经变化，旧代理结果已安全丢弃，请重新开始"
            return
        }
        agentSessionAskAuthor = nil
        await run("代理会话", cancellable: false) {
            let session = AgentSessionResult(
                finalState: prompt.resumeState,
                stopReason: .authorEnded,
                steps: [],
                askAuthorQuestions: nil,
                before: prompt.before,
                elapsed_ms: 0
            )
            try await self.deliverAgentSession(session, checkpoint: checkpoint)
        }
    }

    private func runAgentSession(
        resuming prompt: AgentAskAuthorPrompt?,
        checkpoint suppliedCheckpoint: WritingSessionCheckpoint? = nil
    ) async {
        await run("代理会话", cancellable: true) {
            let checkpoint = suppliedCheckpoint ?? self.captureWritingSessionCheckpoint()
            let style = try self.resolveStyle()
            let input = WritingAgentSessionInput(
                idea: self.ideaInput,
                direction: self.normalizedDirection,
                materials: self.materials,
                style: style,
                title: self.title,
                summary: self.summary,
                content: self.content,
                outline: self.outline,
                config: self.currentModelConfig,
                apiKey: self.apiKeyInput,
                callBudget: self.agentCallBudget,
                decisionTemplate: self.promptTemplate(for: .agentDecision),
                writingReviewTemplate: self.promptTemplate(for: .writingReview),
                polishTemplate: self.promptTemplate(for: .polishDraft),
                draftTemplate: self.promptTemplate(for: .draft),
                outlineTemplate: self.promptTemplate(for: .outline),
                fragmentCorpus: try self.currentFragmentCorpus()
            )
            let coordinator = WritingAgentCoordinator(executor: self.aiClient)
            let session: AgentSessionResult
            if let prompt {
                session = await coordinator.resume(state: prompt.resumeState, before: prompt.before, input: input, onStep: self.agentSessionStepCallback())
            } else {
                session = await coordinator.run(input: input, onStep: self.agentSessionStepCallback())
            }
            try Task.checkCancellation()
            try await self.deliverAgentSession(session, checkpoint: checkpoint)
        }
    }

    /// 会话交付：既服务新会话/续跑的正常收尾，也服务"就此结束"的直接交付，两条路径共用同一段落（18.4.1 待复核状态机）。
    private func deliverAgentSession(
        _ session: AgentSessionResult,
        checkpoint: WritingSessionCheckpoint? = nil
    ) async throws {
        try self.recordAgentRun(
            runType: "有界代理循环",
            status: (session.stopReason == .finished || session.stopReason == .authorEnded || session.isAskAuthor) ? "success" : "fallback",
            summary: session.stopReason.summaryText,
            elapsedMS: session.elapsed_ms,
            inputSummary: session.finalState.idea,
            outputSummary: session.sessionSummaryLines.joined(separator: "\n"),
            error: "",
            steps: session.steps,
            sessionKind: "agent_session",
            budgetSummary: session.finalState.budgetSummaryText
        )
        guard !session.isAskAuthor else {
            self.agentSessionAskAuthor = AgentAskAuthorPrompt(
                questions: session.askAuthorQuestions ?? [],
                resumeState: session.finalState,
                before: session.before,
                articleID: checkpoint?.articleID ?? self.selectedArticleID
            )
            self.statusText = "代理会话需要你补充信息"
            return
        }
        try await self.finalizeGeneratedDraft(
            result: DraftResult(title: session.after.title, content: session.after.content, summary: session.after.summary, tags: nil, raw_output: nil),
            fallbackTitle: session.before.title,
            style: session.finalState.style,
            actionTitle: "有界代理循环",
            successNote: session.stopReason.summaryText,
            failureNote: session.stopReason.summaryText,
            usedFallback: false,
            clearArticleSelection: false,
            retrievedFragments: session.finalState.retrievedFragments,
            checkpoint: checkpoint
        )
        if let versionID = self.pendingDraftReview?.draftVersionID {
            try self.writingSession.updatePendingDraftReview(versionID: versionID) {
                $0.agentSessionSummary = session.sessionSummaryLines
            }
        }
    }

    /// ask_author 允许作者补充素材或写作方向，但不允许旧代理状态跨正文/文章边界回写。
    private func checkpointForAgentPrompt(_ prompt: AgentAskAuthorPrompt) -> WritingSessionCheckpoint? {
        guard selectedArticleID == prompt.articleID,
              currentDraftSnapshot() == prompt.before else {
            return nil
        }
        return captureWritingSessionCheckpoint()
    }

    /// 执行中流式状态："第 N 步 · 动作名"，沿用既有状态条与取消机制（PRD 23.6.5）。
    private func agentSessionStepCallback() -> @Sendable (Int, String) -> Void {
        { [weak self] stepIndex, actionName in
            Task { @MainActor in
                self?.statusText = "第 \(stepIndex) 步 · \(actionName)"
            }
        }
    }
}
