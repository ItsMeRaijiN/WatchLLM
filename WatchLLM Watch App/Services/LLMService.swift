import Foundation

///   - Claude:  POST https://api.anthropic.com/v1/messages
///   - Gemini:  POST https://generativelanguage.googleapis.com/v1beta/models/...:generateContent
///   - ChatGPT: POST https://api.openai.com/v1/responses
protocol LLMService {
    func streamReply(
        to conversation: [ChatMessage],
        using model: LLMModel
    ) throws -> AsyncThrowingStream<LLMStreamEvent, Error>
}

enum LLMStreamEvent {
    case textDelta(String)
    case finished(reason: LLMFinishReason, usage: TokenUsage?)
}

enum LLMFinishReason: String, Codable {
    case completed
    case maxTokens
    case stopped
    case interrupted
    case refused
    case other
}

enum WatchLLMPrompt {
    static let maxOutputTokens = 8_192

    static let system = """
    You are replying on an Apple Watch screen. Be concise — a few sentences unless \
    the user explicitly asks for more. Use lightweight Markdown when it improves \
    readability, but avoid tables and long code blocks. Do not use LaTeX. Write math \
    using Unicode (x², √, ±, ×, ÷, ½). \
    Always reply in the language the user writes in.
    """
}

struct LLMAPIError: LocalizedError {
    let message: String
    let isRetryable: Bool
    let retryAfter: TimeInterval?

    init(message: String, isRetryable: Bool = false, retryAfter: TimeInterval? = nil) {
        self.message = message
        self.isRetryable = isRetryable
        self.retryAfter = retryAfter
    }

    var errorDescription: String? { message }

    static func http(message: String, response: HTTPURLResponse) -> LLMAPIError {
        LLMAPIError(
            message: message,
            isRetryable: RetryPolicy.isRetryableHTTPStatus(response.statusCode),
            retryAfter: RetryPolicy.retryAfter(from: response.value(forHTTPHeaderField: "Retry-After"))
        )
    }
}

enum RetryPolicy {
    static let maxAutomaticRetries = 1

    static func shouldRetry(_ error: Error, attempt: Int, receivedText: Bool) -> Bool {
        guard attempt < maxAutomaticRetries, !receivedText else { return false }
        if let apiError = error as? LLMAPIError {
            return apiError.isRetryable
        }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    static func delay(for error: Error, attempt: Int) -> TimeInterval {
        if let retryAfter = (error as? LLMAPIError)?.retryAfter {
            return min(max(retryAfter, 0), 30)
        }
        return min(pow(2, Double(attempt)), 4)
    }

    static func isRetryableHTTPStatus(_ status: Int) -> Bool {
        status == 408 || status == 425 || status == 429 || (500...599).contains(status)
    }

    static func retryAfter(from value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) {
            return max(seconds, 0)
        }

        for format in ["EEE',' dd MMM yyyy HH':'mm':'ss z", "EEEE',' dd-MMM-yy HH':'mm':'ss z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return max(date.timeIntervalSince(now), 0)
            }
        }
        return nil
    }
}

enum ModelPreference {
    private static func key(for provider: LLMModel) -> String {
        "selectedModel-\(provider.rawValue)"
    }

    static func current(for provider: LLMModel) -> String {
        let stored = UserDefaults.standard.string(forKey: key(for: provider))
        if let stored, provider.availableModels.contains(stored) {
            return stored
        }
        return provider.availableModels[0]
    }

    static func set(_ model: String, for provider: LLMModel) {
        UserDefaults.standard.set(model, forKey: key(for: provider))
    }
}
