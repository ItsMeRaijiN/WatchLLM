import Foundation

/// Gemini client using the generateContent REST API.
struct GeminiService: LLMService {
    static let keychainAccount = "gemini-api-key"

    func reply(to conversation: [ChatMessage], using model: LLMModel) async throws -> String {
        guard let key = KeychainStore.load(account: Self.keychainAccount), !key.isEmpty else {
            throw LLMAPIError(message: "Brak klucza API Gemini — dodaj go w ustawieniach (przycisk w prawym górnym rogu).")
        }

        let body = GeminiRequest(
            contents: conversation.map {
                GeminiContent(role: $0.role == .user ? "user" : "model",
                              parts: [GeminiPart(text: $0.text)])
            },
            systemInstruction: GeminiContent(role: nil, parts: [GeminiPart(text: WatchLLMPrompt.system)])
        )

        let modelName = ModelPreference.current(for: model)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let apiError = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                throw LLMAPIError(message: "Gemini (\(status)): \(apiError.error.message)")
            }
            throw LLMAPIError(message: "Gemini: HTTP \(status)")
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = decoded.candidates?.first?.content?.parts?
            .compactMap(\.text)
            .joined() ?? ""

        guard !text.isEmpty else {
            throw LLMAPIError(message: "Gemini zwróciło pustą odpowiedź.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wire format

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]?

    init(role: String?, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

private struct GeminiPart: Codable {
    let text: String?

    init(text: String) {
        self.text = text
    }
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        let content: GeminiContent?
    }
    let candidates: [Candidate]?
}

private struct GeminiErrorResponse: Decodable {
    struct Err: Decodable {
        let message: String
    }
    let error: Err
}
