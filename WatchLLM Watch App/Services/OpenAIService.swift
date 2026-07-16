import Foundation

/// ChatGPT client using the OpenAI Responses API.
struct OpenAIService: LLMService {
    static let keychainAccount = "openai-api-key"

    func streamReply(
        to conversation: [ChatMessage],
        using model: LLMModel
    ) throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        guard let key = KeychainStore.load(account: Self.keychainAccount), !key.isEmpty else {
            throw LLMAPIError(message: "Brak klucza API OpenAI — dodaj go w ustawieniach (przycisk w prawym górnym rogu).")
        }

        let body = OpenAIRequest(
            model: ModelPreference.current(for: model),
            instructions: WatchLLMPrompt.system,
            input: conversation.map {
                OpenAIMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text)
            },
            maxOutputTokens: WatchLLMPrompt.maxOutputTokens,
            stream: true
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let events = SSEClient.events(for: request) { status, data in
            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
               let message = apiError.error?.message {
                return LLMAPIError(message: "ChatGPT (\(status)): \(message)")
            }
            return LLMAPIError(message: "ChatGPT: HTTP \(status)")
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    var didEmitText = false
                    var didFinish = false

                    for try await event in events {
                        try Task.checkCancellation()
                        guard String(data: event.data, encoding: .utf8) != "[DONE]" else { continue }
                        let decoded = try decoder.decode(OpenAIStreamEvent.self, from: event.data)

                        switch decoded.type {
                        case "response.output_text.delta", "response.refusal.delta":
                            if let delta = decoded.delta, !delta.isEmpty {
                                continuation.yield(.textDelta(delta))
                                didEmitText = true
                            }
                        case "response.output_text.done":
                            if !didEmitText, let text = decoded.text, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                                didEmitText = true
                            }
                        case "response.completed":
                            continuation.yield(.finished(.completed))
                            didFinish = true
                        case "response.incomplete":
                            let reason: LLMFinishReason = decoded.response?.incompleteDetails?.reason == "max_output_tokens"
                                ? .maxTokens : .other
                            continuation.yield(.finished(reason))
                            didFinish = true
                        case "response.failed", "error":
                            let message = decoded.response?.error?.message ?? decoded.message ?? "błąd strumienia"
                            throw LLMAPIError(message: "ChatGPT: \(message)")
                        default:
                            break
                        }
                    }

                    guard didFinish else {
                        throw LLMAPIError(message: "ChatGPT przerwał strumień bez zakończenia odpowiedzi.")
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

// MARK: - Wire format

private struct OpenAIRequest: Encodable {
    let model: String
    let instructions: String
    let input: [OpenAIMessage]
    let maxOutputTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, stream
        case maxOutputTokens = "max_output_tokens"
    }
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIStreamEvent: Decodable {
    struct Response: Decodable {
        struct IncompleteDetails: Decodable {
            let reason: String?
        }
        struct StreamError: Decodable {
            let message: String?
        }
        let incompleteDetails: IncompleteDetails?
        let error: StreamError?
    }
    let type: String
    let delta: String?
    let text: String?
    let message: String?
    let response: Response?
}

private struct OpenAIErrorResponse: Decodable {
    struct Err: Decodable {
        let message: String?
    }
    let error: Err?
}
