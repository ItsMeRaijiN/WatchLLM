import Foundation

///   - Claude:  POST https://api.anthropic.com/v1/messages
///   - Gemini:  POST https://generativelanguage.googleapis.com/v1beta/models/...:generateContent
///   - ChatGPT: POST https://api.openai.com/v1/responses
// Add e.g. AnthropicService and swap the instance in ChatViewModel.
protocol LLMService {
    func reply(to conversation: [ChatMessage], using model: LLMModel) async throws -> String
}

struct StubLLMService: LLMService {
    func reply(to conversation: [ChatMessage], using model: LLMModel) async throws -> String {
        try await Task.sleep(for: .seconds(Double.random(in: 0.8...2.0)))

        let prompt = conversation.last(where: { $0.role == .user })?.text ?? ""

        let openers: [String]
        switch model {
        case .claude:
            openers = [
                "Jasne! Przemyślałem to dokładnie.",
                "Dobre pytanie — spójrzmy na to z kilku stron.",
            ]
        case .gemini:
            openers = [
                "Oto co znalazłem na ten temat.",
                "Przeanalizowałem dostępne informacje.",
            ]
        case .chatGPT:
            openers = [
                "Oczywiście, już wyjaśniam.",
                "Świetnie, że pytasz!",
            ]
        }

        return """
        \(openers.randomElement()!)

        To jest odpowiedź testowa (stub) modelu \(model.rawValue) na prompt: „\(prompt)”. \
        Po podpięciu prawdziwego API w tym miejscu pojawi się rzeczywista odpowiedź.
        """
    }
}
