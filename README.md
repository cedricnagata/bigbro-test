# BigBroTest

A demo iOS app that exercises the full [BigBroKit](https://github.com/nagata-inc/bigbro-kit) feature
set. Connects to a BigBro Mac on the local network and provides a chat interface backed by models
the Mac runs in-process through Apple's MLX.

This app is not intended for distribution — use BigBroKit directly in your own app.

## Requirements

- iOS 17.0+
- Xcode 15+
- A Mac on the same local network running the [BigBro](https://github.com/nagata-inc/bigbro) daemon
  (`bigbro serve`)
- At least one language model downloaded and started on that Mac (`bigbro models download
  gpt-oss-20b`, then `bigbro models start gpt-oss-20b`, or the Models tab of its dashboard)

Voice features additionally need the Mac's speech models — Kokoro for synthesis, Parakeet for
transcription. Both start on first use, so nothing has to be done in advance; the first spoken
turn is just slower.

## Setup

1. Open `bigbro-test.xcodeproj` in Xcode
2. Select a simulator or device and build

The app consumes BigBroKit from the **remote `main` branch**, not a local checkout. To pick up a
new kit commit, delete both:

```
bigbro-test.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
~/Library/Developer/Xcode/DerivedData/bigbro-test-*/SourcePackages
```

Without clearing both, Xcode keeps resolving the version it already has.

Model and voice lists are hand-kept mirrors of the Mac's catalog, at the top of
`ContentView.swift`:

```swift
private let availableModels: [TestModel] = [
    TestModel(id: "gpt-oss-20b", displayName: "gpt-oss 20B", supportsTools: true,
              reasoningOptions: .effortLevels),
    // ...
]

private let requiredModels: [String] = ["gpt-oss-20b"]
```

`requiredModels` is deliberately shorter than `availableModels` — declaring them all would have
the Mac warn about every model you had not downloaded. Speech models are absent from both
because they are not selectable by name; the app asks for "speech" as a whole and the Mac
manages them.

Privacy configuration is already in place, split across two locations because the target uses
`GENERATE_INFOPLIST_FILE = YES`.

`Info.plist` holds the Bonjour service list:
```xml
<key>NSBonjourServices</key>
<array>
    <string>_bigbro._tcp</string>
</array>
```

The usage descriptions are build settings (`INFOPLIST_KEY_*`), merged in at build time:

- `NSLocalNetworkUsageDescription` — Bonjour discovery and the TCP connection
- `NSMicrophoneUsageDescription` — recording and hands-free voice

## Layout

Two-panel split view:

- **Left panel (280pt)** — connection status, missing-model warnings, model picker, streaming
  toggle, reasoning controls, per-tool toggles, speech settings, clear chat
- **Right panel** — message history, pending image previews, the voice status bar while
  hands-free is running, and the input bar

## Connection flow

```
Idle → Find BigBro → Discovering… → Select Mac → Waiting for approval… → Chat
```

On first connect the Mac raises an approval prompt in its dashboard. Later reconnects from the
same device auto-approve silently — the Mac holds all pairing state, and the app persists none.
If the connection drops, the app returns to Idle.

- Green dot — connected
- Spinner — reconnecting (path degraded, waiting for recovery)
- Grey dot — disconnected

If a required model is missing, a banner lists it and updates as models are downloaded, with no
reconnect needed. The Mac is also the authority on what a model can do, and reports what it
dropped — those notes appear under the transcript.

## Features demonstrated

### Model selection and reasoning

A picker chooses the model for the session. Reasoning controls adapt to what the model supports:
effort levels for gpt-oss, an on/off toggle for Qwen3, and nothing at all for models without it.

### Streaming vs single response

In streaming mode text appears token by token, and a spoken reply is spoken sentence by
sentence as it generates. Turned off, the whole answer arrives at once and is spoken as a single
utterance — the toggle governs speech and text together.

Hands-free always streams regardless: the toggle is a chat setting, and waiting for an entire
answer before speaking would make a conversation unusable.

### Image attachment

The photo button opens the system picker. Images are JPEG-compressed and base64-encoded on the
wire. Requires a vision model on the Mac.

### Tools

Toggled individually in the left panel. The SDK's agentic loop runs tool calls on the device, so
the chat UI only ever sees the final text.

| Tool | Description |
|---|---|
| `get_current_date` | Current date and time from the device clock |
| `get_device_info` | Device name, model, and OS version |

### Three ways to talk to it

**Record a message** — the mic button records one utterance with `AVAudioRecorder` and sends it
to `client.transcribe`. The transcript lands in the message box rather than being sent, so it can
be edited first. Disabled while a hands-free session is running, which already owns the
microphone.

**Hands-free** — the waveform button opens a menu; the first entry runs `BigBroVoiceSession`
continuously. Talk, and it transcribes, answers, and speaks back without touching the phone.
Talking over an answer interrupts it.

**Hands-free with a wake word** — the second menu entry gates the same loop on a phrase, so it
can sit in a room where other conversations are happening. Both shapes of address work: "hey big
bro, what's the weather" is answered immediately, while "hey big bro" alone opens the microphone
for whatever comes next. After answering, follow-ups need no phrase for a few seconds.

The status bar distinguishes the two resting states — **Say "hey big bro"** when armed versus
**Listening** inside the follow-up window — because they are the difference between it being your
turn and not. The level meter marks the threshold speech has to clear, which is what separates a
microphone hearing nothing from a threshold sitting above one hearing plenty.

### Speech settings

- **Speak responses** — speaks assistant replies, sentence by sentence as they generate rather
  than after the whole answer, so the first word arrives about a sentence in. Can be toggled
  mid-conversation, including mid-answer.
- **Voice** — Kokoro voice id, chosen from a closed list because an unrecognized one just fails
  synthesis on the Mac with no useful error.
- **Wake phrase** — free text. A phrase too short to gate on is refused rather than silently
  matching nothing.
- **Follow-up window** — how long after an answer a question needs no wake phrase.

## Source

```
bigbro-test/bigbro-test/
├── ContentView.swift     — chat UI, ChatViewModel, tool definitions, voice I/O, image loading
└── bigbro_testApp.swift  — app entry point
```
