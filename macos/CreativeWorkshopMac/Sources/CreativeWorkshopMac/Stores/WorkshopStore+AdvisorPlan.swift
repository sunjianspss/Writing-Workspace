import Foundation
import CreativeWorkshopCore

/// 23.5 半自动调度："按计划执行"把智能下一步给出的 `suggested_actions` 从建议
/// 升级为作者批准一次、系统顺序执行的动作序列。编排本身在 Core 的 `AdvisorPlanRunner`
/// 里；这里只提供 Store 需要的入口与 `AdvisorPlanStepExecuting` 适配。
extension WorkshopStore {
    var canExecuteAdvisorPlan: Bool {
        !isLoading && advisorPlanProgress == nil && !(latestAdvisorRun?.actions.isEmpty ?? true)
    }

    /// 作者点击"按计划执行"后的入口：逐步调用既有工作流方法，生成类步骤产生待复核时
    /// 自动暂停，直到作者确认（继续下一步）或放弃（整个序列停止）。
    func executeAdvisorPlan() async {
        guard advisorPlanProgress == nil else {
            statusText = "计划正在执行中"
            return
        }
        guard let run = latestAdvisorRun else {
            statusText = "请先运行智能下一步"
            return
        }
        let actions = run.actions
        guard !actions.isEmpty else {
            statusText = "没有可执行的计划"
            return
        }

        let startedAt = Date()
        let runner = AdvisorPlanRunner(actions: actions, executor: self)
        let result = await runner.run { [weak self] progress in
            guard let self else { return }
            self.advisorPlanProgress = progress
            if let action = progress.currentAction {
                self.statusText = "第 \(progress.currentIndex)/\(progress.totalSteps) 步：\(action.title)"
            }
        }
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        persistAdvisorPlanRun(result: result, elapsedMS: elapsedMS)
        advisorPlanProgress = nil
        statusText = Self.advisorPlanStatusText(for: result.stopReason)
    }

    private func persistAdvisorPlanRun(result: AdvisorPlanRunResult, elapsedMS: Int) {
        let steps = result.records.enumerated().map { offset, record in
            AgentStepPayload(
                step_index: offset + 1,
                name: record.action.title,
                status: record.status,
                input_summary: "",
                output_summary: record.note ?? "已完成",
                elapsed_ms: 0,
                error: record.status == "failed" ? (record.note ?? "") : ""
            )
        }
        let overallStatus = result.stopReason == .finished ? "success" : "fallback"
        _ = try? recordAgentRun(
            runType: "按计划执行",
            status: overallStatus,
            summary: Self.advisorPlanStatusText(for: result.stopReason),
            elapsedMS: elapsedMS,
            inputSummary: result.records.map { "\($0.index). \($0.action.title)" }.joined(separator: "\n"),
            outputSummary: steps.map { "\($0.name)：\($0.output_summary)" }.joined(separator: "\n"),
            error: overallStatus == "fallback" ? Self.advisorPlanStatusText(for: result.stopReason) : "",
            steps: steps,
            sessionKind: "plan_execution"
        )
    }

    private static func advisorPlanStatusText(for stopReason: AdvisorPlanStopReason) -> String {
        switch stopReason {
        case .finished:
            return "计划执行完成"
        case .cancelled:
            return "计划执行已取消"
        case .failed(let action, let index, let reason):
            return "计划在第 \(index) 步（\(action.title)）失败：\(reason)"
        case .abandoned(let action, let index, _):
            return "计划已停止：你放弃了第 \(index) 步（\(action.title)）的产物"
        }
    }
}

extension WorkshopStore: AdvisorPlanStepExecuting {
    func executeAdvisorPlanStep(_ action: AdvisorAction) async -> AdvisorPlanStepOutcome {
        switch action {
        case .quickDraft:
            guard !ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failed(reason: "请先输入想法")
            }
            await quickDraft()
        case .generateTopics:
            guard !ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failed(reason: "请先输入想法")
            }
            await generateTopics()
        case .generateOutline:
            await generateOutline()
            if statusText == "请先选择选题，或输入想法/标题" {
                return .failed(reason: statusText)
            }
        case .draftFromOutline:
            await draftFromOutline()
            if statusText == "请先选择选题，或输入想法/标题" || statusText == "请先填写大纲" {
                return .failed(reason: statusText)
            }
        case .writingReview:
            guard canRunWritingCoach else {
                return .failed(reason: "请先输入想法、大纲或正文")
            }
            await performReviewCurrentDraft()
        case .polishNatural:
            guard canPolishDraft else { return .failed(reason: "请先完成一版正文") }
            await polishDraft(.natural)
        case .polishTighten:
            guard canPolishDraft else { return .failed(reason: "请先完成一版正文") }
            await polishDraft(.tighten)
        case .publishAssets:
            guard canGeneratePublishAssets else { return .failed(reason: "请先填写标题、摘要或正文") }
            await generatePublishAssets()
        case .rewriteSelectionNatural, .rewriteSelectionExpand, .saveArticle:
            // AdvisorPlanRunner 已经把这三个动作归为"需要作者手动执行"并直接跳过，不会走到这里。
            return .failed(reason: "该动作不支持自动执行")
        }

        if statusText.hasSuffix("已取消") {
            return .cancelled
        }

        if pendingDraftReview != nil {
            switch await waitForPendingDraftReviewResolution() {
            case .confirmed:
                break
            case .discarded:
                return .abandoned(reason: "作者放弃了该步骤的产物")
            }
        }

        if statusText.contains("失败") {
            return .failed(reason: statusText)
        }

        return .completed
    }
}
