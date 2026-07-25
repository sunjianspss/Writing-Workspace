import Foundation

package struct AIWorkflowRunner {
    private let gateway: ModelGateway
    /// 网络类失败的退避重试间隔（24.9）。数组长度即最大重试次数；测试传空数组或 0 秒。
    private let networkRetryBackoff: [TimeInterval]

    /// 5 秒 / 20 秒两次退避：超时本身已经占掉 120–240 秒，间隔再拉长对总耗时没有意义，
    /// 而两次重试足以跨过 DeepSeek 那种几十秒级的抖动（真实评测里的失败全是这一类）。
    package static let defaultNetworkRetryBackoff: [TimeInterval] = [5, 20]

    package init(
        gateway: ModelGateway = OpenAICompatibleModelGateway(),
        networkRetryBackoff: [TimeInterval] = AIWorkflowRunner.defaultNetworkRetryBackoff
    ) {
        self.gateway = gateway
        self.networkRetryBackoff = networkRetryBackoff
    }

    package func run<T: Codable>(
        endpoint: String,
        messages: [ChatMessage],
        config: ModelConfig,
        apiKey: String,
        fallback: T,
        workflow: AIWorkflowKind? = nil,
        decode: @escaping (String) throws -> T,
        onPartialOutput: (@Sendable (String) -> Void)? = nil
    ) async -> AIRun<T> {
        let start = Date()
        let inputSummary = summarizeInput(endpoint: endpoint, messages: messages)
        var attemptMessages = messages
        var hasRetried = false
        var networkRetryCount = 0
        var lastRawOutput = ""

        while true {
            do {
                try Task.checkCancellation()
                let request = ModelGatewayRequest(
                    messages: attemptMessages,
                    config: config,
                    workflow: workflow,
                    apiKey: apiKey
                )
                let output: String
                if let onPartialOutput {
                    var accumulated = ""
                    for try await chunk in gateway.stream(request) {
                        try Task.checkCancellation()
                        accumulated += chunk
                        onPartialOutput(accumulated)
                    }
                    output = accumulated
                } else {
                    output = try await gateway.complete(request)
                }
                lastRawOutput = output
                try Task.checkCancellation()
                let parsed = try decode(output)
                return AIRun(
                    result: parsed,
                    elapsedMS: elapsedMS(since: start),
                    success: true,
                    error: "",
                    inputSummary: inputSummary + retryNote(hasRetried: hasRetried, networkRetryCount: networkRetryCount, succeeded: true),
                    outputSummary: summarizeOutput(parsed)
                )
            } catch {
                if isCancellation(error) {
                    return AIRun(
                        result: fallback,
                        elapsedMS: elapsedMS(since: start),
                        success: false,
                        error: NativeAIError.cancelled.localizedDescription,
                        inputSummary: inputSummary,
                        outputSummary: summarizeOutput(fallback)
                    )
                }
                // 网络类失败退避重试（24.9）：此前只有解析错误会重试，超时/连接中断/TLS 失败
                // 一次就降级到本地兜底稿——评测里因此产出无效样本，App 里则是作者等了几分钟
                // 拿到一篇"本地模拟稿"。等待本身不花钱，只花时间，比伪造一份稿子划算得多。
                if isRetryableNetworkError(error), networkRetryCount < networkRetryBackoff.count {
                    let delay = networkRetryBackoff[networkRetryCount]
                    networkRetryCount += 1
                    do {
                        if delay > 0 {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                    } catch {
                        return AIRun(
                            result: fallback,
                            elapsedMS: elapsedMS(since: start),
                            success: false,
                            error: NativeAIError.cancelled.localizedDescription,
                            inputSummary: inputSummary,
                            outputSummary: summarizeOutput(fallback)
                        )
                    }
                    continue
                }
                if !hasRetried, isParsingError(error) {
                    hasRetried = true
                    attemptMessages = retryMessages(
                        appendingTo: attemptMessages,
                        previousOutput: lastRawOutput,
                        parsingError: error
                    )
                    continue
                }
                let errorText = error.localizedDescription
                    + retryNote(hasRetried: hasRetried, networkRetryCount: networkRetryCount, succeeded: false)
                return AIRun(
                    result: fallback,
                    elapsedMS: elapsedMS(since: start),
                    success: false,
                    error: errorText,
                    inputSummary: inputSummary,
                    outputSummary: summarizeOutput(fallback)
                )
            }
        }
    }

    /// 可退避重试的网络类错误（24.9）：真实评测里出现过的失败全在这一类——超时、连接中断、
    /// TLS 握手失败、DNS 解析不了。HTTP 错误（含 5xx）与 429 不在此列，保持 PRD 22.3.3-A
    /// 定下的"只有解析错误重试"契约不变：那些是服务端明确的应答，重发同一请求未必更好。
    private func isRetryableNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet,
             .dnsLookupFailed, .cannotFindHost, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    /// 重试痕迹写进 inputSummary / error，`ai_calls` 与评测报告里才看得出这一格重试过几次。
    private func retryNote(hasRetried: Bool, networkRetryCount: Int, succeeded: Bool) -> String {
        var notes: [String] = []
        if networkRetryCount > 0 {
            notes.append("网络重试 \(networkRetryCount) 次后\(succeeded ? "成功" : "仍失败")")
        }
        if hasRetried {
            notes.append("解析\(succeeded ? "失败已重试 1 次后成功" : "重试 1 次后仍失败")")
        }
        return notes.isEmpty ? "" : "（\(notes.joined(separator: "；"))）"
    }

    /// 仅对输出解析类错误重试一次（PRD 22.3.3-A）：模型返回的内容无法解析为约定结构时，
    /// 把上一次原始输出连同错误摘要一起追加进对话，要求模型重新输出合法 JSON。
    /// 网络错误、HTTP 错误、取消不属于此类，保持原有直接降级为本地兜底的行为。
    private func isParsingError(_ error: Error) -> Bool {
        if let nativeError = error as? NativeAIError {
            switch nativeError {
            case .invalidJSON, .emptyContent:
                return true
            default:
                return false
            }
        }
        return error is DecodingError
    }

    private func retryMessages(
        appendingTo messages: [ChatMessage],
        previousOutput: String,
        parsingError: Error
    ) -> [ChatMessage] {
        let truncatedOutput = String(previousOutput.prefix(2000))
        let errorSummary = parsingErrorSummary(parsingError)
        return messages + [
            ChatMessage(role: "assistant", content: truncatedOutput),
            ChatMessage(
                role: "user",
                content: "你上一次的输出无法解析为要求的 JSON（错误：\(errorSummary)）。请重新输出，只输出符合要求的合法 JSON，不要包含 Markdown 代码块、解释或任何其他内容。"
            )
        ]
    }

    private func parsingErrorSummary(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return summarize(String(describing: error), limit: 200)
    }

    private func summarizeInput(endpoint: String, messages: [ChatMessage]) -> String {
        let userText = messages.last(where: { $0.role == "user" })?.content
            ?? messages.map(\.content).joined(separator: "\n")
        return "\(endpoint)：\(summarize(userText, limit: 360))"
    }

    private func summarizeOutput<T: Encodable>(_ output: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(output),
              let text = String(data: data, encoding: .utf8) else {
            return summarize(String(describing: output), limit: 420)
        }
        return summarize(text, limit: 420)
    }

    private func summarize(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func elapsedMS(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return Task.isCancelled
    }
}

package struct AIRun<T> {
    package let result: T
    package let elapsedMS: Int
    package let success: Bool
    package let error: String
    package let inputSummary: String
    package let outputSummary: String

    /// 显式 package 初始化器：默认合成的逐成员初始化器是 internal 的，evals 可执行文件的
    /// 假 executor 测试双（PRD 22.4.2）需要跨模块构造 AIRun 才能不依赖真实模型调用。
    package init(result: T, elapsedMS: Int, success: Bool, error: String, inputSummary: String, outputSummary: String) {
        self.result = result
        self.elapsedMS = elapsedMS
        self.success = success
        self.error = error
        self.inputSummary = inputSummary
        self.outputSummary = outputSummary
    }
}
