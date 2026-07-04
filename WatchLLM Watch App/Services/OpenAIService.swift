import Foundation

/// ChatGPT client using the OpenAI Responses API.
struct OpenAIService: LLMService {
    static let keychainAccount = "openai-api-key"

    func reply(to conversation: [ChatMessage], using model: LLMModel) async throws -> String {
        guard let key = KeychainStore.load(account: Self.keychainAccount), !key.isEmpty else {
            throw LLMAPIError(message: "Brak klucza API OpenAI — dodaj go w ustawieniach (przycisk w prawym górnym rogu).")
        }

        let body = OpenAIRequest(
            model: ModelPreference.current(for: model),
            instructions: WatchLLMPrompt.system,
            input: conversation.map {
                OpenAIMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text)
            }
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
               let message = apiError.error?.message {
                throw LLMAPIError(message: "ChatGPT (\(status)): \(message)")
            }
            throw LLMAPIError(message: "ChatGPT: HTTP \(status)")
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        var pieces: [String] = []
        for item in decoded.output ?? [] where item.type == "message" {
            for part in item.content ?? [] where part.type == "output_text" {
                if let piece = part.text {
                    pieces.append(piece)
                }
            }
        }
        let text = pieces.joined()

        guard !text.isEmpty else {
            throw LLMAPIError(message: "ChatGPT zwrócił pustą odpowiedź.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wire format

private struct OpenAIRequest: Encodable {
    let model: String
    let instructions: String
    let input: [OpenAIMessage]
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Decodable {
    struct OutputItem: Decodable {
        let type: String
        let content: [Part]?
    }
    struct Part: Decodable {
        let type: String?
        let text: String?
    }
    let output: [OutputItem]?
}

private struct OpenAIErrorResponse: Decodable {
    struct Err: Decodable {
        let message: String?
    }
    let error: Err?
}
