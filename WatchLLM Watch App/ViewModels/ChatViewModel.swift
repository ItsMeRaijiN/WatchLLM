import Foundation
import Observation
import WatchKit

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = [] {
        didSet { persist() }
    }
    var selectedModel: LLMModel = .claude {
        didSet { persist() }
    }
    var isThinking = false
    private(set) var respondingModel: LLMModel?
    private(set) var streamingText = ""
    private var streamingMessageID: UUID?
    private static let contextLimit = 10

    private var replyTask: Task<Void, Never>?
    private var requestID: UUID?

    private let anthropic = AnthropicService()
    private let gemini = GeminiService()
    private let openAI = OpenAIService()

    var streamingMessage: ChatMessage? {
        guard let id = streamingMessageID,
              let model = respondingModel,
              !streamingText.isEmpty else { return nil }
        return ChatMessage(id: id, role: .assistant, text: streamingText, model: model)
    }

    var canContinueLastResponse: Bool {
        guard !isThinking,
              let message = messages.last(where: { $0.isError != true }) else { return false }
        return message.role == .assistant && message.finishReason == .maxTokens
    }

    private func service(for model: LLMModel) -> LLMService {
        switch model {
        case .claude: anthropic
        case .gemini: gemini
        case .chatGPT: openAI
        }
    }

    private static let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversation.json")
    }()

    private struct SavedState: Codable {
        var messages: [ChatMessage]
        var model: LLMModel
    }

    init() {
        let keyArguments = [
            "-claudeKey": AnthropicService.keychainAccount,
            "-geminiKey": GeminiService.keychainAccount,
            "-openaiKey": OpenAIService.keychainAccount,
        ]
        for (flag, account) in keyArguments {
            if let index = CommandLine.arguments.firstIndex(of: flag),
               CommandLine.arguments.indices.contains(index + 1) {
                KeychainStore.save(CommandLine.arguments[index + 1], account: account)
            }
        }

        if let data = try? Data(contentsOf: Self.storeURL),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            messages = saved.messages
            selectedModel = saved.model
        }

        //demo test
        if CommandLine.arguments.contains("-demo") {
            send("Jaka jest stolica Australii?")
        }
    }

    @discardableResult
    func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return false }

        messages.append(ChatMessage(role: .user, text: trimmed))
        let model = selectedModel
        let context = requestContext()
        return startRequest(context: context, model: model)
    }

    @discardableResult
    func continueLastResponse() -> Bool {
        guard canContinueLastResponse,
              let last = messages.last(where: { $0.isError != true }) else { return false }

        var context = requestContext()
        context.append(ChatMessage(
            role: .user,
            text: "Continue exactly where the previous response stopped. Do not repeat earlier text. Reply in the same language as the preceding response."
        ))
        return startRequest(context: context, model: last.model ?? selectedModel)
    }

    func stop() {
        guard isThinking else { return }
        replyTask?.cancel()
    }

    private func startRequest(context: [ChatMessage], model: LLMModel) -> Bool {
        guard !isThinking else { return false }

        isThinking = true
        respondingModel = model
        streamingText = ""
        streamingMessageID = UUID()
        let id = UUID()
        requestID = id

        replyTask = Task {
            defer {
                if requestID == id {
                    isThinking = false
                    respondingModel = nil
                    streamingText = ""
                    streamingMessageID = nil
                    requestID = nil
                    replyTask = nil
                }
            }
            do {
                let stream = try service(for: model).streamReply(to: context, using: model)
                var didFinish = false

                for try await event in stream {
                    guard requestID == id else { return }
                    switch event {
                    case .textDelta(let delta):
                        streamingText += delta
                    case .finished(let reason):
                        if reason == .refused,
                           streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            throw LLMAPIError(message: "\(model.rawValue) odmówił odpowiedzi.")
                        }
                        guard finalizeStreamingResponse(reason: reason) else {
                            throw LLMAPIError(message: "\(model.rawValue) zwrócił pustą odpowiedź.")
                        }
                        didFinish = true
                    }
                }

                guard didFinish else {
                    throw LLMAPIError(message: "Strumień zakończył się bez pełnej odpowiedzi.")
                }
                WKInterfaceDevice.current().play(.success)
            } catch {
                guard requestID == id else { return }

                if Task.isCancelled || error is CancellationError {
                    _ = finalizeStreamingResponse(reason: .stopped)
                    WKInterfaceDevice.current().play(.click)
                    return
                }

                _ = finalizeStreamingResponse(reason: .interrupted)
                messages.append(ChatMessage(
                    role: .assistant,
                    text: "Błąd: \(error.localizedDescription)",
                    model: model,
                    isError: true
                ))
                WKInterfaceDevice.current().play(.failure)
            }
        }
        return true
    }

    private func finalizeStreamingResponse(reason: LLMFinishReason) -> Bool {
        let text = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        messages.append(ChatMessage(
            id: streamingMessageID ?? UUID(),
            role: .assistant,
            text: text,
            model: respondingModel,
            finishReason: reason
        ))
        streamingText = ""
        streamingMessageID = nil
        return true
    }

    private func requestContext() -> [ChatMessage] {
        var context = Array(messages.filter { $0.isError != true }.suffix(Self.contextLimit))
        while context.first?.role == .assistant {
            context.removeFirst()
        }
        return context
    }

    func clear() {
        requestID = nil
        replyTask?.cancel()
        replyTask = nil
        isThinking = false
        respondingModel = nil
        streamingText = ""
        streamingMessageID = nil
        messages.removeAll()
    }

    private func persist() {
        let state = SavedState(messages: messages, model: selectedModel)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }
}
