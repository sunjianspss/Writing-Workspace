import Foundation

/// 23.5 半自动调度：把"智能下一步"给出的 `suggested_actions` 从一句句建议
/// 升级为作者批准一次、系统按序执行的动作序列。协调器只负责排序、跳过规则与
/// 停止语义；每一步的实际执行（含待复核暂停）由注入的 `AdvisorPlanStepExecuting` 完成。
package enum AdvisorPlanStepOutcome {
    case completed
    case failed(reason: String)
    case abandoned(reason: String)
    case cancelled
}

package protocol AdvisorPlanStepExecuting: AnyObject {
    func executeAdvisorPlanStep(_ action: AdvisorAction) async -> AdvisorPlanStepOutcome
}

package extension AdvisorAction {
    /// rewrite_selection_* 需要作者手选正文范围，save_article 是作者行为，两者都不能自动执行（PRD 23.5）。
    var isAutomaticallyExecutable: Bool {
        switch self {
        case .rewriteSelectionNatural, .rewriteSelectionExpand, .saveArticle:
            return false
        default:
            return true
        }
    }
}

package struct AdvisorPlanStepRecord: Identifiable, Equatable {
    package var index: Int
    package var action: AdvisorAction
    package var status: String
    package var note: String?

    package var id: Int { index }

    package init(index: Int, action: AdvisorAction, status: String, note: String?) {
        self.index = index
        self.action = action
        self.status = status
        self.note = note
    }
}

package struct AdvisorPlanProgress: Equatable {
    package var totalSteps: Int
    package var currentIndex: Int
    package var currentAction: AdvisorAction?
    package var records: [AdvisorPlanStepRecord]

    package init(totalSteps: Int, currentIndex: Int, currentAction: AdvisorAction?, records: [AdvisorPlanStepRecord]) {
        self.totalSteps = totalSteps
        self.currentIndex = currentIndex
        self.currentAction = currentAction
        self.records = records
    }
}

package enum AdvisorPlanStopReason: Equatable {
    case finished
    case cancelled
    case failed(action: AdvisorAction, index: Int, reason: String)
    case abandoned(action: AdvisorAction, index: Int, reason: String)
}

package struct AdvisorPlanRunResult {
    package var records: [AdvisorPlanStepRecord]
    package var stopReason: AdvisorPlanStopReason

    package init(records: [AdvisorPlanStepRecord], stopReason: AdvisorPlanStopReason) {
        self.records = records
        self.stopReason = stopReason
    }
}

package final class AdvisorPlanRunner {
    private let actions: [AdvisorAction]
    private weak var executor: AdvisorPlanStepExecuting?

    package init(actions: [AdvisorAction], executor: AdvisorPlanStepExecuting) {
        self.actions = actions
        self.executor = executor
    }

    /// 按序执行动作；每步完成后通过 `onProgress` 回调最新进度，供调用方转发到 UI。
    /// 回调钉在 `@MainActor`：调用方（WorkshopStore）在回调里改 `@Published` 状态，
    /// 若从协作线程池直接触发 Combine/SwiftUI 会与主线程互锁（2026-07-16 死锁复盘）。
    package func run(onProgress: @MainActor (AdvisorPlanProgress) -> Void) async -> AdvisorPlanRunResult {
        var records: [AdvisorPlanStepRecord] = []
        let total = actions.count

        for (offset, action) in actions.enumerated() {
            let index = offset + 1

            guard action.isAutomaticallyExecutable else {
                records.append(AdvisorPlanStepRecord(index: index, action: action, status: "skipped", note: "已跳过：需要作者手动执行"))
                await onProgress(AdvisorPlanProgress(totalSteps: total, currentIndex: index, currentAction: action, records: records))
                continue
            }

            await onProgress(AdvisorPlanProgress(totalSteps: total, currentIndex: index, currentAction: action, records: records))

            guard let executor else { break }
            let outcome = await executor.executeAdvisorPlanStep(action)

            switch outcome {
            case .completed:
                records.append(AdvisorPlanStepRecord(index: index, action: action, status: "success", note: nil))
                await onProgress(AdvisorPlanProgress(totalSteps: total, currentIndex: index, currentAction: action, records: records))
            case .failed(let reason):
                records.append(AdvisorPlanStepRecord(index: index, action: action, status: "failed", note: reason))
                await onProgress(AdvisorPlanProgress(totalSteps: total, currentIndex: index, currentAction: action, records: records))
                return AdvisorPlanRunResult(records: records, stopReason: .failed(action: action, index: index, reason: reason))
            case .abandoned(let reason):
                records.append(AdvisorPlanStepRecord(index: index, action: action, status: "abandoned", note: reason))
                await onProgress(AdvisorPlanProgress(totalSteps: total, currentIndex: index, currentAction: action, records: records))
                return AdvisorPlanRunResult(records: records, stopReason: .abandoned(action: action, index: index, reason: reason))
            case .cancelled:
                records.append(AdvisorPlanStepRecord(index: index, action: action, status: "cancelled", note: "计划执行已取消"))
                await onProgress(AdvisorPlanProgress(totalSteps: total, currentIndex: index, currentAction: action, records: records))
                return AdvisorPlanRunResult(records: records, stopReason: .cancelled)
            }
        }

        await onProgress(AdvisorPlanProgress(totalSteps: total, currentIndex: total, currentAction: nil, records: records))
        return AdvisorPlanRunResult(records: records, stopReason: .finished)
    }
}
