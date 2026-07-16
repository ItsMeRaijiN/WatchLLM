import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

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
                Text(message.text)
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
}
