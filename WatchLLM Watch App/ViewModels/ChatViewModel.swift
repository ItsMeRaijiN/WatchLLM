import Foundation
import Observation
import WatchKit

@MainActor
@Observable
final class ChatViewModel {
    var selectedModel: LLMModel = .claude {
        didSet { persist() }
    }
    private(set) var conversations: [ChatConversation] {
        didSet { persist() }
    }
    private(set) var selectedConversationID: UUID {
        didSet { persist() }
    }
    var isThinking = false
    private(set) var respondingModel: LLMModel?
    private(set) var streamingText = ""

    private var streamingMessageID: UUID?
    private var replyTask: Task<Void, Never>?
    private var requestID: UUID?
    private var lastFailedRequest: FailedRequest?

    private let anthropic = AnthropicService()
    private let gemini = GeminiService()
    private let openAI = OpenAIService()

    var messages: [ChatMessage] {
        conversation(withID: selectedConversationID)?.messages ?? []
    }

    var sortedConversations: [ChatConversation] {
        conversations
            .filter { !$0.messages.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

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

    var canRetryLastRequest: Bool {
        guard !isThinking, let lastFailedRequest else { return false }
        return lastFailedRequest.conversationID == selectedConversationID
    }

    private static let storeURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("conversation.json")
    }()

    private struct SavedState: Codable {
        var conversations: [ChatConversation]
        var selectedConversationID: UUID
        var model: LLMModel
    }

    private struct LegacySavedState: Codable {
        var messages: [ChatMessage]
        var model: LLMModel
    }

    private struct FailedRequest {
        let context: [ChatMessage]
        let model: LLMModel
        let conversationID: UUID
        let removableMessageIDs: Set<UUID>
    }

    init() {
        let initialConversation = ChatConversation()
        conversations = [initialConversation]
        selectedConversationID = initialConversation.id

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

        if let data = try? Data(contentsOf: Self.storeURL) {
            let decoder = JSONDecoder()
            if let saved = try? decoder.decode(SavedState.self, from: data),
               !saved.conversations.isEmpty {
                conversations = saved.conversations
                selectedConversationID = saved.conversations.contains { $0.id == saved.selectedConversationID }
                    ? saved.selectedConversationID
                    : saved.conversations[0].id
                selectedModel = saved.model
            } else if let legacy = try? decoder.decode(LegacySavedState.self, from: data) {
                let title = legacy.messages.first(where: { $0.role == .user })
                    .map { ConversationContext.title(from: $0.text) } ?? "Nowa rozmowa"
                let migrated = ChatConversation(title: title, messages: legacy.messages)
                conversations = [migrated]
                selectedConversationID = migrated.id
                selectedModel = legacy.model
            }
        }

        if CommandLine.arguments.contains("-demo") {
            send("Jaka jest stolica Australii?")
        }
    }

    @discardableResult
    func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return false }

        lastFailedRequest = nil
        appendMessage(ChatMessage(role: .user, text: trimmed), to: selectedConversationID)
        updateTitleIfNeeded(using: trimmed, conversationID: selectedConversationID)
        let context = requestContext()
        return startRequest(
            context: context,
            model: selectedModel,
            conversationID: selectedConversationID
        )
    }

    @discardableResult
    func continueLastResponse() -> Bool {
        guard canContinueLastResponse,
              let last = messages.last(where: { $0.isError != true }) else { return false }

        lastFailedRequest = nil
        var context = requestContext()
        context.append(ChatMessage(
            role: .user,
            text: "Continue exactly where the previous response stopped. Do not repeat earlier text. Reply in the same language as the preceding response."
        ))
        return startRequest(
            context: context,
            model: last.model ?? selectedModel,
            conversationID: selectedConversationID
        )
    }

    @discardableResult
    func retryLastRequest() -> Bool {
        guard canRetryLastRequest, let failed = lastFailedRequest else { return false }
        removeMessages(withIDs: failed.removableMessageIDs, from: failed.conversationID)
        lastFailedRequest = nil
        return startRequest(
            context: failed.context,
            model: failed.model,
            conversationID: failed.conversationID
        )
    }

    func stop() {
        guard isThinking else { return }
        replyTask?.cancel()
    }

    @discardableResult
    func newConversation() -> Bool {
        guard !isThinking else { return false }
        if messages.isEmpty {
            return true
        }
        conversations.removeAll { $0.messages.isEmpty }
        let conversation = ChatConversation()
        conversations.append(conversation)
        selectedConversationID = conversation.id
        lastFailedRequest = nil
        return true
    }

    @discardableResult
    func selectConversation(_ id: UUID) -> Bool {
        guard !isThinking, conversations.contains(where: { $0.id == id }) else { return false }
        conversations.removeAll { $0.messages.isEmpty && $0.id != id }
        selectedConversationID = id
        lastFailedRequest = nil
        return true
    }

    func deleteConversation(_ id: UUID) {
        guard !isThinking else { return }
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty {
            let replacement = ChatConversation()
            conversations = [replacement]
            selectedConversationID = replacement.id
        } else if !conversations.contains(where: { $0.id == selectedConversationID }) {
            if let nextConversation = sortedConversations.first {
                selectedConversationID = nextConversation.id
            } else {
                let replacement = ChatConversation()
                conversations = [replacement]
                selectedConversationID = replacement.id
            }
        }
        lastFailedRequest = nil
    }

    func clear() {
        guard !isThinking else { return }
        deleteConversation(selectedConversationID)
    }

    private func startRequest(
        context: [ChatMessage],
        model: LLMModel,
        conversationID: UUID
    ) -> Bool {
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
                var automaticRetryCount = 0

                while true {
                    var didReceiveText = false
                    do {
                        let stream = try service(for: model).streamReply(to: context, using: model)
                        var didFinish = false

                        streamLoop: for try await event in stream {
                            guard requestID == id else { return }
                            switch event {
                            case .textDelta(let delta):
                                streamingText += delta
                                didReceiveText = true
                            case .finished(let reason, let usage):
                                if reason == .refused,
                                   streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    throw LLMAPIError(message: "\(model.rawValue) odmówił odpowiedzi.")
                                }
                                guard finalizeStreamingResponse(
                                    reason: reason,
                                    usage: usage,
                                    conversationID: conversationID
                                ) else {
                                    throw LLMAPIError(message: "\(model.rawValue) zwrócił pustą odpowiedź.")
                                }
                                didFinish = true
                                break streamLoop
                            }
                        }

                        guard didFinish else {
                            throw LLMAPIError(
                                message: "Strumień zakończył się bez pełnej odpowiedzi.",
                                isRetryable: true
                            )
                        }
                        break
                    } catch {
                        guard RetryPolicy.shouldRetry(
                            error,
                            attempt: automaticRetryCount,
                            receivedText: didReceiveText
                        ) else {
                            throw error
                        }
                        let delay = RetryPolicy.delay(for: error, attempt: automaticRetryCount)
                        automaticRetryCount += 1
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }

                lastFailedRequest = nil
                WKInterfaceDevice.current().play(.success)
            } catch {
                guard requestID == id else { return }

                if Task.isCancelled || error is CancellationError {
                    _ = finalizeStreamingResponse(
                        reason: .stopped,
                        usage: nil,
                        conversationID: conversationID
                    )
                    WKInterfaceDevice.current().play(.click)
                    return
                }

                var removableIDs: Set<UUID> = []
                if let partialID = streamingMessageID,
                   finalizeStreamingResponse(
                    reason: .interrupted,
                    usage: nil,
                    conversationID: conversationID
                   ) {
                    removableIDs.insert(partialID)
                }

                let errorID = UUID()
                appendMessage(ChatMessage(
                    id: errorID,
                    role: .assistant,
                    text: "Błąd: \(error.localizedDescription)",
                    model: model,
                    isError: true
                ), to: conversationID)
                removableIDs.insert(errorID)
                lastFailedRequest = FailedRequest(
                    context: context,
                    model: model,
                    conversationID: conversationID,
                    removableMessageIDs: removableIDs
                )
                WKInterfaceDevice.current().play(.failure)
            }
        }
        return true
    }

    private func finalizeStreamingResponse(
        reason: LLMFinishReason,
        usage: TokenUsage?,
        conversationID: UUID
    ) -> Bool {
        let text = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        appendMessage(ChatMessage(
            id: streamingMessageID ?? UUID(),
            role: .assistant,
            text: text,
            model: respondingModel,
            finishReason: reason,
            usage: usage?.isEmpty == false ? usage : nil
        ), to: conversationID)
        streamingText = ""
        streamingMessageID = nil
        return true
    }

    private func requestContext() -> [ChatMessage] {
        ConversationContext.messages(from: messages)
    }

    private func service(for model: LLMModel) -> LLMService {
        switch model {
        case .claude: anthropic
        case .gemini: gemini
        case .chatGPT: openAI
        }
    }

    private func conversation(withID id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    private func updateConversation(
        withID id: UUID,
        _ update: (inout ChatConversation) -> Void
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        update(&conversations[index])
        conversations[index].updatedAt = Date()
    }

    private func appendMessage(_ message: ChatMessage, to conversationID: UUID) {
        updateConversation(withID: conversationID) { $0.messages.append(message) }
    }

    private func removeMessages(withIDs ids: Set<UUID>, from conversationID: UUID) {
        updateConversation(withID: conversationID) { conversation in
            conversation.messages.removeAll { ids.contains($0.id) }
        }
    }

    private func updateTitleIfNeeded(using prompt: String, conversationID: UUID) {
        updateConversation(withID: conversationID) { conversation in
            guard conversation.messages.filter({ $0.role == .user }).count == 1 else { return }
            conversation.title = ConversationContext.title(from: prompt)
        }
    }

    private func persist() {
        let state = SavedState(
            conversations: conversations,
            selectedConversationID: selectedConversationID,
            model: selectedModel
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }
}
