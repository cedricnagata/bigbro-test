# BigBroTest

A demo iOS app that exercises the full [BigBroKit](https://github.com/cedricnagata/bigbro-kit) feature
set. Connects to a BigBro Mac on the local network and provides a chat interface backed by models
the Mac runs in-process through Apple's MLX.

This app is not intended for distribution — use BigBroKit directly in your own app.

## Requirements

- iOS 17.0+
- Xcode 15+
- A Mac on the same local network running the [BigBro](https://github.com/cedricnagata/bigbro) daemon
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
    TestModel(id: "qwen2.5-vl-3b", displayName: "Qwen2.5-VL 3B", supportsTools: false,
              supportsImages: true, reasoningOptions: .none),
]

private let requiredModels: [String] = ["gpt-oss-20b"]
```

`availableModels` mirrors BigBro's `ALL_MODELS` in full — every text and vision model the Mac
will answer a `request` with, in the same order — because a model that can't be picked here is
a model whose output framing, tool support and reasoning style go untested. The picker splits
them into Text and Vision sections, and the photo button is enabled only for the latter: the
Mac errors on images sent to a language model rather than answering from the text alone.

`requiredModels` is deliberately far shorter — declaring them all would have the Mac offer to
pull well over 100 GB on first connect. Everything else downloads on demand the first time it
is selected, through the same `modelDownloading` flow. Speech models are absent from both
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
  toggle, reasoning controls, per-tool toggles, speech settings, auto-reconnect and remembered
  Macs, clear chat
- **Right panel** — message history, pending image previews, the voice status bar while
  hands-free is running, and the input bar

## Connection flow

```
Idle → Find BigBro → Discovering… → Select Mac → Waiting for approval… → Chat
```

On first connect the Mac raises an approval prompt in its dashboard. Later reconnects from the
same device auto-approve silently — the Mac holds all pairing state. If the connection drops, the
app returns to Idle.

The left panel also exposes the kit's auto-reconnect switch, with a count of remembered Macs and a
button to forget them. With it on, the app pairs with a known Mac as soon as Bonjour sees it,
without going through Find BigBro. That list lives in the app's `UserDefaults` and is only a record
of which Macs are worth reconnecting to — forgetting them here revokes nothing on the Mac, which
still decides every approval. `bigbro pair remove` on the Mac is what actually revokes.

Because the switch is persistent but the browse it starts is not, the app calls
`resumeAutoReconnectIfEnabled()` at launch. Without that the toggle would read as on while nothing
was looking for anything.

- Green dot — connected
- Spinner — reconnecting (path degraded, waiting for recovery)
- Grey dot — disconnected

If a required model is missing, a banner lists it and updates as models are downloaded, with no
reconnect needed. The Mac is also the authority on what a model can do, and reports what it
dropped — those notes appear under the transcript.

## Features demonstrated

### Model selection and reasoning

A picker chooses the model for the session, split into Text and Vision sections. Reasoning
controls adapt to what the model supports: effort levels for gpt-oss, an on/off toggle for the
Qwen3-family models and Bonsai, a note and no control for the DeepSeek-R1 distills — which
always reason and take neither lever — and nothing at all for models without a reasoning phase.
Switching model re-normalizes the reasoning choice, so a depth picked for gpt-oss can't survive
as a stored value the next model's controls never present.

### Streaming vs single response

In streaming mode text appears token by token, and a spoken reply is spoken sentence by
sentence as it generates. Turned off, the whole answer arrives at once and is spoken as a single
utterance — the toggle governs speech and text together.

Hands-free always streams regardless: the toggle is a chat setting, and waiting for an entire
answer before speaking would make a conversation unusable.

### Image attachment

The photo button opens the system picker. Images are JPEG-compressed and base64-encoded on the
wire. Enabled only while a vision model is selected — the Mac errors on a request carrying
images for a language model rather than answering from the text alone — and switching away from
a vision model drops anything already attached rather than letting the next send be refused.

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
for whatever comes next.

The phrase is the only way in. Every question needs it, including the one after an answer, and
it is also the only thing that interrupts — talking over a reply does nothing unless you name
it first, which is the point of running this mode in a room that contains other conversations.

The status bar distinguishes the two resting states — **Say "hey big bro"** when armed versus
**Go ahead…** in the brief window after being named and asked nothing — because they are the
difference between it being your turn and not. The level meter marks the threshold speech has
to clear, which is what separates a microphone hearing nothing from a threshold sitting above
one hearing plenty.

### Speech settings

- **Speak responses** — speaks assistant replies, sentence by sentence as they generate rather
  than after the whole answer, so the first word arrives about a sentence in. Can be toggled
  mid-conversation, including mid-answer.
- **Voice** — Kokoro voice id, chosen from a closed list because an unrecognized one just fails
  synthesis on the Mac with no useful error.
- **Wake phrase** — free text. A phrase too short to gate on is refused rather than silently
  matching nothing.

## Source

```
bigbro-test/bigbro-test/
├── ContentView.swift     — chat UI, ChatViewModel, tool definitions, voice I/O, image loading
└── bigbro_testApp.swift  — app entry point
```
