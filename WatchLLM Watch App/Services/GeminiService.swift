import Foundation

/// Gemini client using the generateContent REST API.
struct GeminiService: LLMService {
    static let keychainAccount = "gemini-api-key"

    func streamReply(
        to conversation: [ChatMessage],
        using model: LLMModel
    ) throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        guard let key = KeychainStore.load(account: Self.keychainAccount), !key.isEmpty else {
            throw LLMAPIError(message: "Brak klucza API Gemini — dodaj go w ustawieniach (przycisk w prawym górnym rogu).")
        }

        let body = GeminiRequest(
            contents: conversation.map {
                GeminiContent(role: $0.role == .user ? "user" : "model",
                              parts: [GeminiPart(text: $0.text)])
            },
            systemInstruction: GeminiContent(role: nil, parts: [GeminiPart(text: WatchLLMPrompt.system)]),
            generationConfig: GeminiGenerationConfig(maxOutputTokens: WatchLLMPrompt.maxOutputTokens)
        )

        let modelName = ModelPreference.current(for: model)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):streamGenerateContent?alt=sse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let events = SSEClient.events(for: request) { response, data in
            if let apiError = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                return LLMAPIError.http(
                    message: "Gemini (\(response.statusCode)): \(apiError.error.message)",
                    response: response
                )
            }
            return LLMAPIError.http(message: "Gemini: HTTP \(response.statusCode)", response: response)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var didFinish = false
                    var didEmitText = false
                    var usage: TokenUsage?
                    for try await event in events {
                        try Task.checkCancellation()
                        guard String(data: event.data, encoding: .utf8) != "[DONE]" else { continue }
                        if let apiError = try? JSONDecoder().decode(GeminiErrorResponse.self, from: event.data) {
                            throw LLMAPIError(
                                message: "Gemini: \(apiError.error.message)",
                                isRetryable: apiError.error.code.map(RetryPolicy.isRetryableHTTPStatus) ?? false
                            )
                        }
                        let chunk = try JSONDecoder().decode(GeminiStreamChunk.self, from: event.data)
                        if let metadata = chunk.usageMetadata {
                            usage = metadata.tokenUsage
                        }
                        guard let candidate = chunk.candidates?.first else { continue }

                        for part in candidate.content?.parts ?? [] where part.thought != true {
                            if let text = part.text, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                                didEmitText = true
                            }
                        }

                        if let reason = candidate.finishReason {
                            if reason != "STOP", reason != "MAX_TOKENS", !didEmitText {
                                throw LLMAPIError(message: "Gemini: \(candidate.finishMessage ?? reason)")
                            }
                            continuation.yield(.finished(reason: Self.mapFinishReason(reason), usage: usage))
                            didFinish = true
                        }
                    }

                    guard didFinish else {
                        throw LLMAPIError(message: "Gemini przerwało strumień bez zakończenia odpowiedzi.")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func mapFinishReason(_ value: String) -> LLMFinishReason {
        switch value {
        case "STOP": .completed
        case "MAX_TOKENS": .maxTokens
        default: .other
        }
    }
}

// MARK: - Wire format

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiGenerationConfig: Encodable {
    let maxOutputTokens: Int
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]?

    init(role: String?, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

private struct GeminiPart: Codable {
    let text: String?
    let thought: Bool?

    init(text: String) {
        self.text = text
        self.thought = nil
    }
}

private struct GeminiStreamChunk: Decodable {
    struct Candidate: Decodable {
        let content: GeminiContent?
        let finishReason: String?
        let finishMessage: String?
    }
    let candidates: [Candidate]?
    let usageMetadata: UsageMetadata?

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?

        var tokenUsage: TokenUsage {
            TokenUsage(
                inputTokens: promptTokenCount,
                outputTokens: candidatesTokenCount,
                totalTokens: totalTokenCount
            )
        }
    }
}

private struct GeminiErrorResponse: Decodable {
    struct Err: Decodable {
        let code: Int?
        let message: String
    }
    let error: Err
}
