import Foundation

/// Claude client using the Anthropic Messages API.
struct AnthropicService: LLMService {
    static let keychainAccount = "anthropic-api-key"

    func reply(to conversation: [ChatMessage], using model: LLMModel) async throws -> String {
        guard let key = KeychainStore.load(account: Self.keychainAccount), !key.isEmpty else {
            throw LLMAPIError(message: "Brak klucza API Claude — dodaj go w ustawieniach (przycisk w prawym górnym rogu).")
        }

        let body = AnthropicRequest(
            model: ModelPreference.current(for: model),
            maxTokens: 16000,
            system: WatchLLMPrompt.system,
            messages: conversation.map {
                AnthropicMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text)
            }
        )

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let apiError = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                throw LLMAPIError(message: "Claude (\(status)): \(apiError.error.message)")
            }
            throw LLMAPIError(message: "Claude: HTTP \(status)")
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = decoded.content?
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined() ?? ""

        guard !text.isEmpty else {
            throw LLMAPIError(message: "Claude zwrócił pustą odpowiedź.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wire format

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [AnthropicMessage]
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]?
}

private struct AnthropicErrorResponse: Decodable {
    struct Err: Decodable {
        let message: String
    }
    let error: Err
}
