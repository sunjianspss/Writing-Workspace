import Foundation

/// package：evals 可执行文件（PRD 22.4.2）需要在其独立模块里用假 executor 测试双替换真实模型调用，
/// 同时把真实调用注入既有 AgentDraftCoordinator / DeepDraftCoordinator，不重新实现编排逻辑。
package protocol AIWorkflowExecuting {
    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output>

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String,
        onPartialOutput: (@Sendable (String) -> Void)?
    ) async -> AIRun<Output>
}

/// 默认实现：忽略增量回调，退化为非流式 `execute`。这样已有的 `AIWorkflowExecuting`
/// 测试双（evals 假 executor 等）不需要为了新增的流式方法逐一改动就能继续满足协议。
package extension AIWorkflowExecuting {
    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String,
        onPartialOutput: (@Sendable (String) -> Void)?
    ) async -> AIRun<Output> {
        await execute(descriptor, config: config, apiKey: apiKey)
    }
}

package struct NativeAIClient: AIWorkflowExecuting {
    private let workflowEngine: WorkflowEngine

    package init(runner: AIWorkflowRunner = AIWorkflowRunner(), recorder: AIWorkflowRecording? = nil) {
        self.workflowEngine = WorkflowEngine(runner: runner, recorder: recorder)
    }

    package func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        await workflowEngine.execute(descriptor, config: config, apiKey: apiKey)
    }

    package func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String,
        onPartialOutput: (@Sendable (String) -> Void)?
    ) async -> AIRun<Output> {
        await workflowEngine.execute(descriptor, config: config, apiKey: apiKey, onPartialOutput: onPartialOutput)
    }
}

package enum NativeAIError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case invalidResponse
    case http(status: Int, message: String)
    case emptyContent
    case invalidJSON
    case cancelled

    package static let missingAPIKeyMessage = "尚未配置 API Key，已使用本地模拟内容。"

    package var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return Self.missingAPIKeyMessage
        case .invalidBaseURL:
            return "模型 API Base URL 无效。"
        case .invalidResponse:
            return "模型服务响应无效。"
        case let .http(status, message):
            return "模型服务 HTTP \(status)：\(message)"
        case .emptyContent:
            return "模型没有返回正文。"
        case .invalidJSON:
            return "模型返回内容不是有效 JSON。"
        case .cancelled:
            return "本次生成已取消。"
        }
    }

    /// 用于区分"未配置 API Key 的演示模式"与其余真实失败（网络/HTTP/解析），
    /// 二者在管线熔断策略上语义不同（PRD 22.3.3）。
    package static func isMissingAPIKey(errorText: String) -> Bool {
        errorText == missingAPIKeyMessage
    }
}
