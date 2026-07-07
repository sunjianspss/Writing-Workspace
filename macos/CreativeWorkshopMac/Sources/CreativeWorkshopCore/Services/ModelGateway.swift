import Foundation

package struct ModelGatewayRequest {
    package var messages: [ChatMessage]
    package var config: ModelConfig
    package var workflow: AIWorkflowKind?
    package var apiKey: String
    package var temperature: Double = 0.75
    package var timeoutSeconds: TimeInterval = 90

    private var override: ModelRouteConfig? {
        workflow.flatMap { config.workflowOverrides[$0.rawValue] }
    }

    /// 参数解析优先级（22.3.4）：用户 workflowOverrides > 工作流代码级默认 > 现有全局默认。
    package var resolvedTemperature: Double {
        override?.temperature ?? workflow?.defaultParameters.temperature ?? temperature
    }

    package var resolvedMaxTokens: Int? {
        override?.maxTokens ?? workflow?.defaultParameters.maxTokens
    }

    package var resolvedTimeoutSeconds: TimeInterval {
        override?.timeoutSeconds ?? workflow?.defaultParameters.timeoutSeconds ?? timeoutSeconds
    }
}

package protocol ModelGateway {
    func complete(_ request: ModelGatewayRequest) async throws -> String
    func stream(_ request: ModelGatewayRequest) -> AsyncThrowingStream<String, Error>
}

package enum ModelGatewayError: LocalizedError, Equatable {
    case streamingNotImplemented

    package var errorDescription: String? {
        switch self {
        case .streamingNotImplemented:
            return "当前模型网关尚未实现流式输出。"
        }
    }
}

package extension ModelGateway {
    func stream(_ request: ModelGatewayRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ModelGatewayError.streamingNotImplemented)
        }
    }
}

package struct OpenAICompatibleModelGateway: ModelGateway {
    package func complete(_ request: ModelGatewayRequest) async throws -> String {
        let key = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw NativeAIError.missingAPIKey
        }

        let routeConfig = request.config.resolved(for: request.workflow)
        let baseURLText = routeConfig.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURLText)/chat/completions") else {
            throw NativeAIError.invalidBaseURL
        }

        let body = ChatCompletionRequest(
            model: routeConfig.model,
            messages: request.messages,
            temperature: request.resolvedTemperature,
            maxTokens: request.resolvedMaxTokens,
            stream: false
        )
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.resolvedTimeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NativeAIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "empty response"
            throw NativeAIError.http(status: httpResponse.statusCode, message: message)
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw NativeAIError.emptyContent
        }
        return content
    }

    package func stream(_ request: ModelGatewayRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let key = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else {
                        throw NativeAIError.missingAPIKey
                    }

                    let routeConfig = request.config.resolved(for: request.workflow)
                    let baseURLText = routeConfig.baseURL
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard let url = URL(string: "\(baseURLText)/chat/completions") else {
                        throw NativeAIError.invalidBaseURL
                    }

                    let body = ChatCompletionRequest(
                        model: routeConfig.model,
                        messages: request.messages,
                        temperature: request.resolvedTemperature,
                        maxTokens: request.resolvedMaxTokens,
                        stream: true
                    )
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = request.resolvedTimeoutSeconds
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NativeAIError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        throw NativeAIError.http(
                            status: httpResponse.statusCode,
                            message: errorBody.isEmpty ? "empty response" : errorBody
                        )
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        switch SSELineParser.parse(line) {
                        case .delta(let text):
                            continuation.yield(text)
                        case .done:
                            continuation.finish()
                            return
                        case .ignored:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 把 OpenAI 兼容 SSE 响应的一行文本解析成增量内容 / 结束 / 可忽略三种情况，
/// 独立成纯函数是为了不依赖网络就能单测这段解析逻辑本身。
package enum SSELineParser {
    package enum Event: Equatable {
        case delta(String)
        case done
        case ignored
    }

    package static func parse(_ line: String) -> Event {
        guard line.hasPrefix("data:") else {
            return .ignored
        }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]" else {
            return .done
        }
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else {
            return .ignored
        }
        guard let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
              let content = chunk.choices.first?.delta.content,
              !content.isEmpty else {
            return .ignored
        }
        return .delta(content)
    }
}

private struct ChatCompletionChunk: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let delta: Delta
    }

    struct Delta: Codable {
        let content: String?
    }
}

package struct ChatCompletionRequest: Codable {
    package let model: String
    package let messages: [ChatMessage]
    package let temperature: Double
    package let maxTokens: Int?
    package let stream: Bool

    package enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ChatCompletionResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        package let message: Message
    }

    struct Message: Codable {
        package let content: String
    }
}
