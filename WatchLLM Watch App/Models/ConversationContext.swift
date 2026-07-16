import Foundation

enum ConversationContext {
    static let defaultCharacterBudget = 32_000

    static func messages(
        from messages: [ChatMessage],
        characterBudget: Int = defaultCharacterBudget
    ) -> [ChatMessage] {
        let validMessages = messages.filter { $0.isError != true }
        var turns: [[ChatMessage]] = []
        var currentTurn: [ChatMessage] = []

        for message in validMessages {
            switch message.role {
            case .user:
                if !currentTurn.isEmpty {
                    turns.append(currentTurn)
                }
                currentTurn = [message]
            case .assistant:
                guard currentTurn.first?.role == .user else { continue }
                currentTurn.append(message)
            }
        }
        if !currentTurn.isEmpty {
            turns.append(currentTurn)
        }

        var selectedTurns: [[ChatMessage]] = []
        var usedCharacters = 0
        for turn in turns.reversed() {
            let turnCharacters = turn.reduce(0) { $0 + $1.text.count }
            guard selectedTurns.isEmpty || usedCharacters + turnCharacters <= characterBudget else {
                break
            }
            selectedTurns.append(turn)
            usedCharacters += turnCharacters
        }
        return selectedTurns.reversed().flatMap(normalizedTurn)
    }

    static func title(from prompt: String, limit: Int = 42) -> String {
        let normalized = prompt
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func normalizedTurn(_ turn: [ChatMessage]) -> [ChatMessage] {
        guard let user = turn.first, turn.count > 2 else { return turn }
        let assistantMessages = turn.dropFirst()
        guard let last = assistantMessages.last else { return [user] }
        let mergedAssistant = ChatMessage(
            id: last.id,
            role: .assistant,
            text: assistantMessages.map(\.text).joined(separator: "\n\n"),
            model: last.model,
            finishReason: last.finishReason,
            usage: last.usage
        )
        return [user, mergedAssistant]
    }
}
