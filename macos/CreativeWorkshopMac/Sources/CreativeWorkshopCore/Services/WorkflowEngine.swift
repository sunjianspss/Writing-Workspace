import Foundation

package protocol AIWorkflowRecording {
    func recordAICall(
        endpoint: String,
        model: String,
        elapsedMS: Int,
        success: Bool,
        error: String,
        inputSummary: String,
        outputSummary: String
    )
}

package struct WorkflowDescriptor<Output: Codable> {
    package var kind: AIWorkflowKind
    package var endpoint: String
    package var templateKey: PromptTemplateKey?
    package var shouldRecordAICall: Bool = true
    package var buildMessages: () -> [ChatMessage]
    /// package：evals 可执行文件的假 executor 测试双（PRD 22.4.2）复用它作为确定性的“成功”产出，
    /// 不需要真实调用模型。
    package var fallback: () -> Output
    package var decode: (String) throws -> Output

    package init(
        kind: AIWorkflowKind,
        endpoint: String,
        templateKey: PromptTemplateKey? = nil,
        shouldRecordAICall: Bool = true,
        buildMessages: @escaping () -> [ChatMessage],
        fallback: @escaping () -> Output,
        decode: @escaping (String) throws -> Output = { content in
            try WorkflowOutputDecoder.decode(content, as: Output.self)
        }
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.templateKey = templateKey
        self.shouldRecordAICall = shouldRecordAICall
        self.buildMessages = buildMessages
        self.fallback = fallback
        self.decode = decode
    }
}

package struct WorkflowEngine {
    private let runner: AIWorkflowRunner
    private let recorder: AIWorkflowRecording?

    package init(runner: AIWorkflowRunner = AIWorkflowRunner(), recorder: AIWorkflowRecording? = nil) {
        self.runner = runner
        self.recorder = recorder
    }

    package func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String,
        onPartialOutput: (@Sendable (String) -> Void)? = nil
    ) async -> AIRun<Output> {
        let run = await runner.run(
            endpoint: descriptor.endpoint,
            messages: descriptor.buildMessages(),
            config: config,
            apiKey: apiKey,
            fallback: descriptor.fallback(),
            workflow: descriptor.kind,
            decode: descriptor.decode,
            onPartialOutput: onPartialOutput
        )
        if descriptor.shouldRecordAICall {
            recorder?.recordAICall(
                endpoint: descriptor.endpoint,
                model: config.resolved(for: descriptor.kind).model,
                elapsedMS: run.elapsedMS,
                success: run.success,
                error: run.error,
                inputSummary: run.inputSummary,
                outputSummary: run.outputSummary
            )
        }
        return run
    }
}

package enum WorkflowOutputDecoder {
    package static func decode<Output: Decodable>(
        _ content: String,
        as type: Output.Type = Output.self,
        nonJSONFallback: ((String) -> Output)? = nil
    ) throws -> Output {
        let cleaned = stripCodeFence(content)
        guard let data = cleaned.data(using: .utf8) else {
            throw NativeAIError.invalidJSON
        }
        do {
            return try JSONDecoder().decode(Output.self, from: data)
        } catch {
            if let nonJSONFallback {
                return nonJSONFallback(cleaned)
            }
            throw error
        }
    }

    package static func stripCodeFence(_ content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else {
            return text
        }
        text.removeFirst(3)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("json") {
            text.removeFirst(4)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("```") {
            text.removeLast(3)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
