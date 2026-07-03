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

    private let service: LLMService = StubLLMService()

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

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        isThinking = true
        let model = selectedModel

        Task {
            defer { isThinking = false }
            do {
                let answer = try await service.reply(to: messages, using: model)
                messages.append(ChatMessage(role: .assistant, text: answer, model: model))
                WKInterfaceDevice.current().play(.success)
            } catch {
                messages.append(ChatMessage(
                    role: .assistant,
                    text: "Błąd: \(error.localizedDescription)",
                    model: model
                ))
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    func clear() {
        messages.removeAll()
    }

    private func persist() {
        let state = SavedState(messages: messages, model: selectedModel)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }
}
