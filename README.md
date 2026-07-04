# WatchLLM

Apple Watch (watchOS 10+) chat client for **Claude**, **Gemini** and **ChatGPT**.

All three providers are wired to their real APIs: Claude (Anthropic Messages API),
Gemini (`generateContent`, free tier at [aistudio.google.com](https://aistudio.google.com))
and ChatGPT (OpenAI Responses API). API keys are entered in the app settings and
stored in the Keychain.


## Structure

```
WatchLLM Watch App/
├── WatchLLMApp.swift          # entry point
├── Models/Models.swift        # LLMModel, ChatMessage
├── Services/                  # LLMService protocol, Anthropic/Gemini/OpenAI clients, KeychainStore
├── ViewModels/ChatViewModel.swift
└── Views/                     # ChatView, MessageBubble
```
