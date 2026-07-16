import Foundation

/// Claude client using the Anthropic Messages API.
struct AnthropicService: LLMService {
    static let keychainAccount = "anthropic-api-key"

    func streamReply(
        to conversation: [ChatMessage],
        using model: LLMModel
    ) throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        guard let key = KeychainStore.load(account: Self.keychainAccount), !key.isEmpty else {
            throw LLMAPIError(message: "Brak klucza API Claude — dodaj go w ustawieniach (przycisk w prawym górnym rogu).")
        }

        let body = AnthropicRequest(
            model: ModelPreference.current(for: model),
            maxTokens: WatchLLMPrompt.maxOutputTokens,
            system: WatchLLMPrompt.system,
            messages: conversation.map {
                AnthropicMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text)
            },
            stream: true
        )

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let events = SSEClient.events(for: request) { response, data in
            if let apiError = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                return LLMAPIError.http(
                    message: "Claude (\(response.statusCode)): \(apiError.error.message)",
                    response: response
                )
            }
            return LLMAPIError.http(message: "Claude: HTTP \(response.statusCode)", response: response)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    var finishReason: LLMFinishReason?
                    var usage: TokenUsage?
                    var didFinish = false

                    for try await event in events {
                        try Task.checkCancellation()
                        guard String(data: event.data, encoding: .utf8) != "[DONE]" else { continue }
                        let decoded = try decoder.decode(AnthropicStreamEvent.self, from: event.data)

                        switch decoded.type {
                        case "message_start":
                            usage = decoded.message?.usage?.tokenUsage
                        case "content_block_delta":
                            if decoded.delta?.type == "text_delta", let text = decoded.delta?.text, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
                        case "message_delta":
                            finishReason = Self.mapFinishReason(decoded.delta?.stopReason)
                            if let deltaUsage = decoded.usage?.tokenUsage {
                                usage = TokenUsage(
                                    inputTokens: usage?.inputTokens ?? deltaUsage.inputTokens,
                                    outputTokens: deltaUsage.outputTokens ?? usage?.outputTokens,
                                    totalTokens: nil
                                )
                            }
                        case "message_stop":
                            continuation.yield(.finished(reason: finishReason ?? .other, usage: usage))
                            didFinish = true
                        case "error":
                            throw LLMAPIError(
                                message: "Claude: \(decoded.error?.message ?? "błąd strumienia")",
                                isRetryable: decoded.error?.type == "overloaded_error"
                            )
                        default:
                            break
                        }
                    }

                    guard didFinish else {
                        throw LLMAPIError(message: "Claude przerwał strumień bez zakończenia odpowiedzi.")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func mapFinishReason(_ value: String?) -> LLMFinishReason {
        switch value {
        case "end_turn", "stop_sequence": .completed
        case "max_tokens", "model_context_window_exceeded": .maxTokens
        case "refusal": .refused
        default: .other
        }
    }
}

// MARK: - Wire format

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [AnthropicMessage]
    let stream: Bool
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicStreamEvent: Decodable {
    struct Delta: Decodable {
        let type: String?
        let text: String?
        let stopReason: String?
    }
    struct StreamError: Decodable {
        let type: String?
        let message: String
    }
    struct Message: Decodable {
        let usage: Usage?
    }
    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        var tokenUsage: TokenUsage {
            let inputParts = [inputTokens, cacheCreationInputTokens, cacheReadInputTokens].compactMap { $0 }
            let input = inputParts.isEmpty ? nil : inputParts.reduce(0, +)
            let total: Int?
            if let input, let outputTokens {
                total = input + outputTokens
            } else {
                total = nil
            }
            return TokenUsage(inputTokens: input, outputTokens: outputTokens, totalTokens: total)
        }
    }
    let type: String
    let delta: Delta?
    let error: StreamError?
    let message: Message?
    let usage: Usage?
}

private struct AnthropicErrorResponse: Decodable {
    struct Err: Decodable {
        let message: String
    }
    let error: Err
}
