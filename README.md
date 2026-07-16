# WatchLLM

Apple Watch (watchOS 10+) chat client for **Claude**, **Gemini** and **OpenAI/ChatGPT**.

All three providers are wired to their real APIs: Claude (Anthropic Messages API),
Gemini (`generateContent`, free tier at [aistudio.google.com](https://aistudio.google.com))
and OpenAI (Responses API). API keys are entered in the app settings and stored
in the watch Keychain.

## Architecture

This is intentionally a **watch-only** app. No model runs on Apple Watch: the app
sends HTTPS requests to each provider and only displays the response. watchOS may
route that network traffic through the paired iPhone, Wi-Fi, or cellular, but the
iPhone does not run a companion process and `WatchConnectivity` is not used.

That is the smallest reliable architecture for a personal app. A companion iOS app
would mainly make key entry and settings easier; it would also make live requests
depend on the iPhone app being reachable. For an App Store or multi-user product,
use your own backend instead of distributing provider secrets to client devices.

API access is billed separately from consumer Claude, Gemini, or ChatGPT
subscriptions.

## Usage

1. Open the model/settings button in the top-right corner.
2. Choose a provider model and save its API key. The secret field supports the
   watchOS text input UI, including dictation and Continuity Keyboard when available.
3. Enter a prompt and send it. The answer is displayed as it streams in; use the
   red Stop button to keep the partial response and cancel generation.
4. If a provider reaches the output limit, use Continue to resume without repeating
   the previous text. The last ten non-error messages are used as context.

Defaults favor lower latency and cost. Responses have a generous 8,192-token ceiling;
the system prompt still asks for concise answers unless the user requests more detail.


## Structure

```
WatchLLM Watch App/
├── WatchLLMApp.swift          # entry point
├── Models/Models.swift        # LLMModel, ChatMessage
├── Services/                  # LLMService protocol, Anthropic/Gemini/OpenAI clients, KeychainStore
├── ViewModels/ChatViewModel.swift
└── Views/                     # ChatView, MessageBubble
```
