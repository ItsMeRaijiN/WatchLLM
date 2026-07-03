# WatchLLM

Apple Watch (watchOS 10+) chat client for **Claude**, **Gemini** and **ChatGPT**.

The API layer is currently a stub (`StubLLMService`): responses are generated locally
with a simulated network delay, so the UI can be developed and tested without API keys.


## Structure

```
WatchLLM Watch App/
├── WatchLLMApp.swift          # entry point
├── Models/Models.swift        # LLMModel, ChatMessage
├── Services/LLMService.swift  # LLMService protocol + StubLLMService
├── ViewModels/ChatViewModel.swift
└── Views/                     # ChatView, MessageBubble
```
