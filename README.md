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

Privacy configuration is already in place, split across two locations because the target uses
`GENERATE_INFOPLIST_FILE = YES`:

`Info.plist` holds the Bonjour service list:
```xml
<key>NSBonjourServices</key>
<array>
    <string>_bigbro._tcp</string>
</array>
```

The usage descriptions are build settings (`INFOPLIST_KEY_*`), merged in at build time:

- `NSLocalNetworkUsageDescription` — Bonjour discovery and the TCP connection
- `NSMicrophoneUsageDescription` — recording for the speech-to-text demo

## Layout

Two-panel split view:

- **Left panel (280pt)** — connection status, missing model warnings, model picker, streaming toggle, per-tool toggles, speech demos, clear chat
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

## Speech demos

**Speech demos** in the left panel opens a sheet exercising the three speech APIs. All require a
speech backend enabled on the Mac (Settings → Speech); the button is disabled until a Mac is
connected.

- **Text to speech** — `client.speak(text)` streamed through `BigBroAudioPlayer`, so audio
  starts on the first chunk rather than after the whole utterance.
- **Speech to text** — records a full utterance with `AVAudioRecorder`, then sends it to
  `client.transcribe(audio, format: "m4a")`. Batch, not streaming.
- **Voice loop** — `client.converse(...)`, which runs a chat turn and speaks it sentence by
  sentence. Text and audio arrive interleaved on one stream, so the demo forwards audio chunks
  into a second stream that playback drains concurrently.

A quick round trip that needs no microphone: speak a phrase, then record the playback and
confirm the transcript matches.
