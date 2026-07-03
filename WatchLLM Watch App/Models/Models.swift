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
