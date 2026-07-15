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

    /// Model IDs selectable in settings; the first entry is the default.
    var availableModels: [String] {
        switch self {
        case .claude: ["claude-opus-4-8", "claude-fable-5", "claude-sonnet-5", "claude-haiku-4-5"]
        case .gemini: ["gemini-3.5-flash", "gemini-3.1-pro-preview", "gemini-3.1-flash-lite"]
        case .chatGPT: ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
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
    /// Error bubbles are shown in the chat but never sent back to the API.
    let isError: Bool?

    init(role: Role, text: String, model: LLMModel? = nil, isError: Bool = false) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.model = model
        self.isError = isError
    }
}
