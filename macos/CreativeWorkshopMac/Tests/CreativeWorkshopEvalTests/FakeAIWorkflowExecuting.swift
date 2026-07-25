import Foundation
import CreativeWorkshopCore

/// 假 executor（PRD 22.4.2 验收标准 2）：不发起任何真实网络调用，直接复用每个
/// WorkflowDescriptor 自带的本地 fallback 内容作为确定性"成功"产出，驱动真实的
/// AgentDraftCoordinator / DeepDraftCoordinator / EvalPipelineFacade 走完整条管线。
struct FakeAIWorkflowExecuting: AIWorkflowExecuting {
    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        AIRun(
            result: descriptor.fallback(),
            elapsedMS: 5,
            success: true,
            error: "",
            inputSummary: "fake-input",
            outputSummary: "fake-output"
        )
    }
}

/// 只有评分调用失败的假 executor（24.9）：生成成功、写作诊断超时。此时 `NativeFallbacks
/// .writingReview` 会按段落数与标题有无算出一个本地启发式分数（68 起步加减），它既不是模型
/// 给的分也不服从锚点——库里那些 58/66 分的失败行正是这么来的。
struct ScoringFailsAIWorkflowExecuting: AIWorkflowExecuting {
    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        let scoringFailed = descriptor.kind == .writingReview
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: scoringFailed ? 240_000 : 5,
            success: !scoringFailed,
            error: scoringFailed ? "The request timed out." : "",
            inputSummary: "fake-input",
            outputSummary: "fake-output"
        )
    }
}

/// 全程失败的假 executor（24.9）：模拟"网络超时后拿到本地兜底稿"这一真实场景，用来验证
/// 失败样本不会被打分。每次调用都计数，以便断言评分调用根本没有发出。
final class FailingAIWorkflowExecuting: AIWorkflowExecuting, @unchecked Sendable {
    private(set) var callCount = 0

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        callCount += 1
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 240_000,
            success: false,
            error: "The request timed out.",
            inputSummary: "fake-input",
            outputSummary: "fake-output"
        )
    }
}
