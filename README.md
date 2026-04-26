# BigBroTest

A demo iOS app that exercises the full [BigBroKit](https://github.com/nagata-inc/bigbro-kit) feature set. Connects to a BigBro Mac on the local network and provides a chat interface backed by the Mac's local Ollama models.

This app is not intended for distribution — use BigBroKit directly in your own app.

## Requirements

- iOS 17.0+
- Xcode 15+
- A Mac running the [BigBro](https://github.com/nagata-inc/bigbro) app on the same local network
- At least one LLM model installed in [Ollama](https://ollama.ai) on that Mac

## Setup

1. Open `bigbro-test.xcodeproj` in Xcode
2. Ensure the BigBroKit local package is linked under **Frameworks, Libraries, and Embedded Content**
3. Configure the required models and app name at the top of `ContentView.swift`:

```swift
private let requiredModels: [String] = [
    "llama3.2",
    "llava:13b",
]
```

4. Select a physical device or simulator as the run destination and build

The app's `Info.plist` must include (already configured):
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Used to discover and connect to BigBro on your local network.</string>
<key>NSBonjourServices</key>
<array>
    <string>_bigbro._tcp</string>
</array>
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to attach images to your messages.</string>
```

## Layout

Two-panel split view:

- **Left panel (280pt)** — connection status, missing model warnings, model picker, streaming toggle, per-tool toggles, clear chat
- **Right panel** — scrollable message history, pending image previews, input bar

## Connection flow

```
Idle → Find BigBro → Discovering… → Select Mac → Waiting for approval… → Chat
```

On first connect, an approval dialog appears on the Mac. Subsequent reconnects from the same device and app are auto-approved silently. If the connection drops, the app returns to Idle automatically.

Connection state is visible in the left panel:
- Green dot — connected
- Spinner — reconnecting (path degraded, waiting for recovery)
- Grey dot — disconnected

If any required models are missing from Ollama, a warning banner appears in the connection section listing the missing models. The banner updates automatically when models are downloaded — no reconnect needed.

## Features demonstrated

### Model selection

A picker in the left panel lets you choose which model to use for the current chat session. Options are the models declared in `requiredModels` plus a **BigBro Default** option that defers to whatever the Mac's default model is set to.

### Streaming vs single response

Toggle in the left panel. In streaming mode, text tokens appear as they are generated. In single-response mode, the complete reply arrives at once.

### Image attachment

Tap the photo button in the input bar to open the system photo picker. Selected images appear as thumbnails above the input field and are sent with the next message. Multimodal models (e.g. `llava`) can see and describe the images.

Images are JPEG-compressed and base64-encoded before being included in the Ollama request.

### Tools

Each tool can be toggled individually in the left panel. The SDK's agentic loop handles tool execution transparently — the chat UI only ever sees the final text response.

| Tool | Description |
|---|---|
| `get_current_date` | Returns the current date and time from the device clock |
| `get_device_info` | Returns the device name, model, and OS version |

## Source

```
bigbro-test/bigbro-test/
├── ContentView.swift     — all UI, ChatViewModel, tool definitions, image loading
└── bigbro_testApp.swift  — app entry point
```
