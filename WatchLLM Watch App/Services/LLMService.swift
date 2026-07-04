import Foundation

///   - Claude:  POST https://api.anthropic.com/v1/messages
///   - Gemini:  POST https://generativelanguage.googleapis.com/v1beta/models/...:generateContent
///   - ChatGPT: POST https://api.openai.com/v1/responses
protocol LLMService {
    func reply(to conversation: [ChatMessage], using model: LLMModel) async throws -> String
}

/// Shared system prompt: keeps answers readable on a watch screen.
enum WatchLLMPrompt {
    static let system = """
    You are replying on an Apple Watch screen. Be concise — a few sentences unless \
    the user explicitly asks for more. Plain text only: no Markdown, no LaTeX, \
    no code fences. Write math using Unicode (x², √, ±, ×, ÷, ½). \
    Always reply in the language the user writes in.
    """
}

/// Human-readable error surfaced in the chat bubble.
struct LLMAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ModelPreference {
    private static func key(for provider: LLMModel) -> String {
        "selectedModel-\(provider.rawValue)"
    }

    static func current(for provider: LLMModel) -> String {
        let stored = UserDefaults.standard.string(forKey: key(for: provider))
        // Ignore stale values that are no longer on the list.
        if let stored, provider.availableModels.contains(stored) {
            return stored
        }
        return provider.availableModels[0]
    }

    static func set(_ model: String, for provider: LLMModel) {
        UserDefaults.standard.set(model, forKey: key(for: provider))
    }
}
