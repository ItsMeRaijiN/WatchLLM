import SwiftUI

enum MessageMarkdown {
    static func render(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming = false

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 16)
                Text(message.text)
                    .font(.footnote)
                    .padding(8)
                    .background(.blue.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 2) {
                if let model = message.model {
                    Text(model.rawValue)
                        .font(.caption2)
                        .foregroundStyle(model.tint)
                }
                Text(assistantText)
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel(message.isError == true ? "Błąd: \(message.text)" : message.text)

                if let statusText {
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let usageText {
                    Text(usageText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Zużycie tokenów: \(usageText)")
                }
            }
        }
    }

    private var bubbleColor: Color {
        message.isError == true ? .red.opacity(0.28) : .gray.opacity(0.25)
    }

    private var statusText: String? {
        switch message.finishReason {
        case .maxTokens: "Osiągnięto limit odpowiedzi"
        case .stopped: "Zatrzymano"
        case .interrupted: "Połączenie przerwane"
        case .refused: "Model odmówił odpowiedzi"
        default: nil
        }
    }

    private var assistantText: AttributedString {
        guard !isStreaming, message.isError != true else {
            return AttributedString(message.text)
        }
        return MessageMarkdown.render(message.text)
    }

    private var usageText: String? {
        guard let usage = message.usage else { return nil }
        var parts: [String] = []
        if let input = usage.inputTokens {
            parts.append("\(input) wej.")
        }
        if let output = usage.outputTokens {
            parts.append("\(output) wyj.")
        }
        if let total = usage.totalTokens,
           total != (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0) {
            parts.append("\(total) razem")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
