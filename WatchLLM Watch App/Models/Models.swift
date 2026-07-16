import SwiftUI

enum LLMModel: String, CaseIterable, Identifiable, Codable {
    case claude = "Claude"
    case gemini = "Gemini"
    case chatGPT = "ChatGPT"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .claude: .orange
        case .gemini: .blue
        case .chatGPT: .green
        }
    }

    var shortName: String {
        switch self {
        case .claude: "CL"
        case .gemini: "GE"
        case .chatGPT: "GPT"
        }
    }

    var availableModels: [String] {
        switch self {
        case .claude: ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-4-8", "claude-fable-5"]
        case .gemini: ["gemini-3.1-flash-lite", "gemini-3.5-flash", "gemini-3.1-pro-preview"]
        case .chatGPT: ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]
        }
    }
}

struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let model: LLMModel?
    let isError: Bool?
    let finishReason: LLMFinishReason?
    let usage: TokenUsage?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        model: LLMModel? = nil,
        isError: Bool = false,
        finishReason: LLMFinishReason? = nil,
        usage: TokenUsage? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.model = model
        self.isError = isError
        self.finishReason = finishReason
        self.usage = usage
    }
}

struct TokenUsage: Equatable, Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    var isEmpty: Bool {
        inputTokens == nil && outputTokens == nil && totalTokens == nil
    }
}

struct ChatConversation: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Nowa rozmowa",
        messages: [ChatMessage] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }
}
