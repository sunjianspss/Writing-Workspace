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
