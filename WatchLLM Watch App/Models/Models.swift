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
        case .claude: ["claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5"]
        case .gemini: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.5-flash-lite"]
        case .chatGPT: ["gpt-5.1", "gpt-5-mini", "gpt-5-nano"]
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

    init(role: Role, text: String, model: LLMModel? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.model = model
    }
}
