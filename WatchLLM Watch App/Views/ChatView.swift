import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var draft = ""
    @State private var showingModelPicker = false
    @State private var streamingScrollTask: Task<Void, Never>?

    private let bottomID = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                    }

                    if viewModel.canContinueLastResponse {
                        Button {
                            viewModel.continueLastResponse()
                        } label: {
                            Label("Kontynuuj", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let streamingMessage = viewModel.streamingMessage {
                        MessageBubble(message: streamingMessage)
                    }

                    if viewModel.isThinking {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("\(viewModel.respondingModel?.rawValue ?? "Model") pisze…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    inputBar
                        .id(bottomID)
                }
            }
            .onChange(of: viewModel.messages) {
                withAnimation {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isThinking) {
                withAnimation {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.streamingText) {
                guard streamingScrollTask == nil else { return }
                streamingScrollTask = Task { @MainActor in
                    defer { streamingScrollTask = nil }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onDisappear {
                streamingScrollTask?.cancel()
                streamingScrollTask = nil
            }
        }
        .navigationTitle("WatchLLM")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingModelPicker = true
                } label: {
                    Text(viewModel.selectedModel.shortName)
                        .font(.caption.bold())
                        .foregroundStyle(viewModel.selectedModel.tint)
                }
                .accessibilityLabel("Model i ustawienia: \(viewModel.selectedModel.rawValue)")
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView(selected: $viewModel.selectedModel) {
                viewModel.clear()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Napisz wiadomość do")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(viewModel.selectedModel.rawValue)
                .font(.headline)
                .foregroundStyle(viewModel.selectedModel.tint)
        }
        .padding(.vertical, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 4) {
            TextField("Prompt…", text: $draft)
                .onSubmit(sendDraft)

            if viewModel.isThinking {
                Button(action: viewModel.stop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Zatrzymaj odpowiedź")
                .buttonStyle(.plain)
            } else {
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedModel.tint)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func sendDraft() {
        if viewModel.send(draft) {
            draft = ""
        }
    }
}

struct ModelPickerView: View {
    @Binding var selected: LLMModel
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Model") {
                ForEach(LLMModel.allCases) { model in
                    Button {
                        selected = model
                        dismiss()
                    } label: {
                        HStack {
                            Circle()
                                .fill(model.tint)
                                .frame(width: 10, height: 10)
                            Text(model.rawValue)
                            Spacer()
                            if model == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            ProviderSection(
                provider: .claude,
                account: AnthropicService.keychainAccount,
                hint: "Klucz z platform.claude.com."
            )
            ProviderSection(
                provider: .gemini,
                account: GeminiService.keychainAccount,
                hint: "Klucz z aistudio.google.com."
            )
            ProviderSection(
                provider: .chatGPT,
                account: OpenAIService.keychainAccount,
                hint: "Klucz z platform.openai.com."
            )

            Section {
                Button(role: .destructive) {
                    onClear()
                    dismiss()
                } label: {
                    Label("Wyczyść rozmowę", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Ustawienia")
    }
}

struct ProviderSection: View {
    let provider: LLMModel
    let account: String
    let hint: String
    @State private var key = ""
    @State private var modelChoice: String
    @State private var hasStoredKey: Bool
    @State private var keyStatus: String?

    init(provider: LLMModel, account: String, hint: String) {
        self.provider = provider
        self.account = account
        self.hint = hint
        _hasStoredKey = State(initialValue: KeychainStore.load(account: account) != nil)
        _modelChoice = State(initialValue: ModelPreference.current(for: provider))
    }

    var body: some View {
        Section {
            SecureField(hasStoredKey ? "Wklej nowy klucz…" : "Wklej klucz…", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(saveKey)

            Button(action: saveKey) {
                Label(hasStoredKey ? "Zastąp klucz" : "Zapisz klucz", systemImage: "key.fill")
            }
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if hasStoredKey {
                Button(role: .destructive, action: deleteKey) {
                    Label("Usuń klucz", systemImage: "trash")
                }
            }

            Picker("Model", selection: $modelChoice) {
                ForEach(provider.availableModels, id: \.self) { name in
                    Text(name).font(.footnote)
                }
            }
            .onChange(of: modelChoice) {
                ModelPreference.set(modelChoice, for: provider)
            }
        } header: {
            Text(provider.rawValue)
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        if let keyStatus { return keyStatus }
        return hasStoredKey ? "Klucz zapisany w Keychain." : hint
    }

    private func saveKey() {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if KeychainStore.save(key, account: account) {
            key = ""
            hasStoredKey = true
            keyStatus = "Klucz zapisany w Keychain."
        } else {
            keyStatus = "Nie udało się zapisać klucza."
        }
    }

    private func deleteKey() {
        if KeychainStore.delete(account: account) {
            key = ""
            hasStoredKey = false
            keyStatus = "Klucz usunięty."
        } else {
            keyStatus = "Nie udało się usunąć klucza."
        }
    }
}

#Preview {
    NavigationStack {
        ChatView()
    }
}
