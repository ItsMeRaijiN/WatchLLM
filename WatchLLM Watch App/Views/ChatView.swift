import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var draft = ""
    @State private var showingModelPicker = false

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

                    if viewModel.isThinking {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("\(viewModel.selectedModel.rawValue) pisze…")
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
        }
        .navigationTitle("WatchLLM")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingModelPicker = true
                } label: {
                    Text(String(viewModel.selectedModel.rawValue.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(viewModel.selectedModel.tint)
                }
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

            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(viewModel.selectedModel.tint)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || viewModel.isThinking)
        }
    }

    private func sendDraft() {
        viewModel.send(draft)
        draft = ""
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

#Preview {
    NavigationStack {
        ChatView()
    }
}
