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
                    .background(.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
