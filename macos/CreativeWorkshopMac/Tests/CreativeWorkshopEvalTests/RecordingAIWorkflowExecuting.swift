import Foundation
import CreativeWorkshopCore

/// 与 FakeAIWorkflowExecuting 同样不发起真实网络调用，额外把每次调用的 prompt 文本录下来，
/// 供「评测到底把哪份 prompt 发给了模型」这类断言使用（24.5）。测试内串行调用，无需加锁。
final class RecordingAIWorkflowExecuting: AIWorkflowExecuting {
    private(set) var prompts: [String] = []

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        prompts.append(descriptor.buildMessages().map(\.content).joined(separator: "\n"))
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 5,
            success: true,
            error: "",
            inputSummary: "fake-input",
            outputSummary: "fake-output"
        )
    }

    func contains(_ needle: String) -> Bool {
        prompts.contains { $0.contains(needle) }
    }
}
