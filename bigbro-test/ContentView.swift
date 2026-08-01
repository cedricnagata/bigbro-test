import SwiftUI
import Combine
import PhotosUI
import AVFoundation
import BigBroKit

// MARK: - Configuration

/// What reasoning options a model offers — mirrors BigBro's own `ReasoningStyle`, collapsed to
/// what the UI needs to decide which picker to show.
enum ReasoningOptions: Hashable {
    /// No reasoning phase at all — nothing to pick.
    case none
    /// Can be switched off entirely (Qwen3's `enable_thinking`), but has no separate depth
    /// when on.
    case toggleOnly
    /// Always reasons; only how much is adjustable (gpt-oss's low/medium/high).
    case effortLevels
}

/// A text model this app can ask the Mac to run, and what it can do.
///
/// Capabilities are mirrored from BigBro's own catalog rather than discovered, so the UI can
/// grey out a control the moment a model is picked instead of after a round trip. The Mac is
/// still the authority — it drops what a model can't do and reports it back via
/// `client.modelNotes`, which is what catches this table drifting out of date.
struct TestModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let supportsTools: Bool
    let reasoningOptions: ReasoningOptions
}

private let availableModels: [TestModel] = [
    TestModel(id: "gpt-oss-20b",  displayName: "gpt-oss 20B",  supportsTools: true,  reasoningOptions: .effortLevels),
    TestModel(id: "qwen3-8b",     displayName: "Qwen3 8B",     supportsTools: true,  reasoningOptions: .toggleOnly),
    TestModel(id: "qwen3-4b",     displayName: "Qwen3 4B",     supportsTools: true,  reasoningOptions: .toggleOnly),
    TestModel(id: "llama-3.1-8b", displayName: "Llama 3.1 8B", supportsTools: true,  reasoningOptions: .none),
    TestModel(id: "llama-3.2-3b", displayName: "Llama 3.2 3B", supportsTools: true,  reasoningOptions: .none),
    TestModel(id: "gemma-4-e2b",  displayName: "Gemma 4 E2B",  supportsTools: false, reasoningOptions: .none),
    TestModel(id: "gemma-3-1b",   displayName: "Gemma 3 1B",   supportsTools: false, reasoningOptions: .none),
]

/// Models the Mac should have ready before this device is useful — just the default.
///
/// Deliberately not every entry in `availableModels`: declaring them all would have the Mac
/// offer to pull tens of gigabytes on first connect. The others download on demand the first
/// time one is actually selected, through the same `modelDownloading` flow.
///
/// Transcription and speech synthesis are Parakeet and Kokoro on the Mac; they aren't listed
/// here because they aren't selectable by name — the Mac manages them in its own Settings
/// (download / run / stop / remove), and this app only ever asks for "speech" as a whole.
private let requiredModels: [String] = [
    "gpt-oss-20b"
]

/// Kokoro voice identifiers the Mac's speech backend (FluidAudio) ships, mirrored from
/// `TtsConstants.availableVoices` — bigbro-test has no dependency on FluidAudio itself (that's
/// Mac-only), so this is a hand-kept copy, same discipline as `availableModels` above.
///
/// Only American English (`af_*`, `am_*`) is regression-tested; the rest are present in the
/// model and work, but are unverified per FluidAudio's own docs.
private let availableVoices: [String] = [
    // American English (tested)
    "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore", "af_nicole", "af_nova",
    "af_river", "af_sarah", "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam",
    "am_michael", "am_onyx", "am_puck", "am_santa",
    // British English (experimental)
    "bf_alice", "bf_emma", "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    // Spanish, LATAM (experimental)
    "ef_dora", "em_alex", "em_santa",
    // French (experimental)
    "ff_siwis",
    // Hindi (experimental)
    "hf_alpha", "hf_beta", "hm_omega", "hm_psi",
    // Italian (experimental)
    "if_sara", "im_nicola",
    // Japanese (experimental)
    "jf_alpha", "jf_gongitsune", "jf_nezumi", "jf_tebukuro", "jm_kumo",
    // Brazilian Portuguese (experimental)
    "pf_dora", "pm_alex", "pm_santa",
    // Mandarin Chinese (experimental)
    "zf_xiaobei", "zf_xiaoni", "zf_xiaoxiao", "zf_xiaoyi", "zm_yunjian", "zm_yunxi", "zm_yunxia",
    "zm_yunyang",
]

struct ContentView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSettings = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad: side-by-side
                HStack(spacing: 0) {
                    SettingsPanel(viewModel: viewModel)
                        .frame(width: 280)
                        .background(Color(.secondarySystemBackground))
                    Divider()
                    ChatPanel(viewModel: viewModel, client: viewModel.client)
                        .frame(maxWidth: .infinity)
                }
            } else {
                // iPhone: chat full-screen, settings in a sheet
                NavigationStack {
                    ChatPanel(viewModel: viewModel, client: viewModel.client)
                        .navigationTitle("BigBro")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showingSettings = true
                                } label: {
                                    Image(systemName: "sidebar.left")
                                }
                            }
                        }
                }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        SettingsPanel(viewModel: viewModel)
                            .navigationTitle("Settings")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { showingSettings = false }
                                }
                            }
                    }
                }
            }
        }
        .task { await viewModel.start() }
    }
}

// MARK: - Settings panel

private struct SettingsPanel: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollView {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionSection(viewModel: viewModel, client: viewModel.client)

            Divider()

            ReconnectionSection(viewModel: viewModel, client: viewModel.client)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Model", selection: $viewModel.selectedModelID) {
                    ForEach(availableModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Text(viewModel.modelCapabilitySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle(isOn: $viewModel.streamingEnabled) {
                Label(
                    viewModel.streamingEnabled ? "Streaming" : "Single response",
                    systemImage: viewModel.streamingEnabled ? "waveform" : "text.bubble"
                )
                .font(.subheadline)
            }
            .toggleStyle(.switch)

            if viewModel.selectedModel.reasoningOptions != .none {
                Divider()
                ReasoningSection(viewModel: viewModel)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Tools")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ForEach(viewModel.allTools, id: \.definition.function.name) { tool in
                    Toggle(isOn: Binding(
                        get: { viewModel.enabledTools.contains(tool.definition.function.name) },
                        set: { enabled in
                            if enabled {
                                viewModel.enabledTools.insert(tool.definition.function.name)
                            } else {
                                viewModel.enabledTools.remove(tool.definition.function.name)
                            }
                        }
                    )) {
                        Label(tool.definition.function.name, systemImage: "wrench.and.screwdriver")
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .disabled(!viewModel.selectedModel.supportsTools)
                }

                if !viewModel.selectedModel.supportsTools {
                    Text("\(viewModel.selectedModel.displayName) can't call tools. The Mac drops them rather than failing, so requests still answer — just without them.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            SpeechSection(viewModel: viewModel)

            Button {
                viewModel.clearChat()
            } label: {
                Label("Clear chat", systemImage: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.messages.isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How the selected model reasons, as a single set of options rather than a toggle plus a
/// separate effort dial — what's offered depends entirely on the model:
///
/// - gpt-oss always reasons via the Harmony template, which carries only a depth (low/medium/
///   high) and no off switch, so there is no "None" option.
/// - Qwen3's template takes a plain `enable_thinking` bool — no depth, just on or off — so
///   "None" is one of exactly two options.
/// - A model with no reasoning phase at all offers nothing; the caller hides this view.
private struct ReasoningSection: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reasoning")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Picker("Reasoning", selection: $viewModel.reasoningEffort) {
                ForEach(options, id: \.self) { option in
                    Text(label(for: option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// The only values `reasoningEffort` should ever hold for this model — `ChatViewModel`
    /// normalizes to one of these whenever the selected model changes.
    private var options: [ReasoningEffort?] {
        switch viewModel.selectedModel.reasoningOptions {
        case .none:         return []
        case .toggleOnly:   return [nil, .medium]
        case .effortLevels: return [.low, .medium, .high]
        }
    }

    private func label(for option: ReasoningEffort?) -> String {
        switch (viewModel.selectedModel.reasoningOptions, option) {
        case (.toggleOnly, nil):  return "None"
        case (.toggleOnly, _):    return "Reasoning"
        case (_, nil):            return "None"
        case (_, let effort?):    return effort.rawValue.capitalized
        }
    }

    private var detail: String {
        switch viewModel.selectedModel.reasoningOptions {
        case .none:
            return ""
        case .toggleOnly:
            return viewModel.reasoningEffort == nil
                ? "\(viewModel.selectedModel.displayName) won't reason for this turn."
                : "\(viewModel.selectedModel.displayName) reasons before answering — no adjustable depth, just on or off."
        case .effortLevels:
            switch viewModel.reasoningEffort {
            case .low:  return "Shortest analysis pass — fastest answer, weakest on multi-step problems."
            case .high: return "Longest analysis pass — best on hard problems, slowest to first token."
            default:    return "Balanced. The gpt-oss default."
            }
        }
    }
}

private struct SpeechSection: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speech")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Toggle(isOn: $viewModel.speakResponses) {
                Label("Speak responses", systemImage: "speaker.wave.2")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)

            // Only meaningful once something is going to be spoken. Voice is a BigBroKit-side
            // parameter, not a Mac setting, and a closed list rather than free text: an
            // unrecognized id just fails synthesis on the Mac with no clue why.
            if viewModel.speakResponses {
                HStack {
                    Text("Voice")
                        .font(.subheadline)
                    Spacer()
                    Picker("Voice", selection: $viewModel.voice) {
                        ForEach(availableVoices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Text("Uses the Mac's on-device text-to-speech and transcription — both start automatically on first use, the same way a language model does.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReconnectionSection: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var client: BigBroClient

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reconnection")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { client.autoReconnectEnabled },
                set: { viewModel.setAutoReconnect($0) }
            )) {
                Label("Auto-reconnect", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)

            Text("Remembered Macs: \(client.pairedDeviceNames.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                viewModel.forgetPairedMacs()
            } label: {
                Label("Forget paired Macs", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(client.pairedDeviceNames.isEmpty)
        }
    }
}

private struct ConnectionSection: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var client: BigBroClient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            switch viewModel.state {
            case .idle:
                Button {
                    Task { await viewModel.findBigBro() }
                } label: {
                    Label("Find BigBro", systemImage: "magnifyingglass")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
            case .discovering:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for BigBro…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .selectDevice(let devices):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Macs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(devices) { device in
                        DevicePickerRow(device: device) {
                            Task { await viewModel.pair(with: device) }
                        }
                    }
                    Button("Cancel") {
                        Task { await viewModel.start() }
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
            case .pairing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .chat:
                HStack(spacing: 8) {
                    switch client.connectionState {
                    case .connected:
                        Circle().fill(Color.green).frame(width: 10, height: 10)
                    case .reconnecting:
                        ProgressView().controlSize(.mini)
                    case .disconnected:
                        Circle().fill(Color.secondary.opacity(0.4)).frame(width: 10, height: 10)
                    }
                    Text(client.connectedDevice?.name ?? "Paired")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Text(client.connectionState == .reconnecting ? "Reconnecting…" : "Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.isStartingModel {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Starting \(viewModel.selectedModel.displayName)…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !client.missingModels.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Missing models", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        ForEach(client.missingModels, id: \.self) { model in
                            Text(model)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text("Download in Ollama to use these models.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button(role: .destructive) {
                    viewModel.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            case .error(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Find BigBro") {
                    Task { await viewModel.findBigBro() }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct DevicePickerRow: View {
    let device: BigBroDevice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.subheadline)
                    Text(device.host).font(.caption2).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "desktopcomputer")
            }
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Chat panel

private struct ChatPanel: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var client: BigBroClient
    @FocusState private var inputFocused: Bool

    private var canType: Bool {
        if case .chat = viewModel.state { return client.isConnected }
        return false
    }

    /// True while voice input owns the input bar — typing, attaching, and sending are all
    /// blocked so a transcript can't land mid-edit or mid-send. Hands-free mode counts:
    /// it drives the same transcript, and a typed message mid-turn would interleave with a
    /// spoken one.
    private var voiceBusy: Bool {
        viewModel.isRecording || viewModel.isTranscribing || viewModel.voiceActive
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }
                        if viewModel.isLoading {
                            HStack {
                                ProgressView().scaleEffect(0.8).padding(10)
                                Spacer()
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: viewModel.isLoading) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            if !client.modelDownloads.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(client.modelDownloads.values), id: \.model) { dl in
                        ModelDownloadBanner(progress: dl)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.08))
            }

            // Pending image previews
            if !viewModel.selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.selectedImages.indices, id: \.self) { i in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: viewModel.selectedImages[i])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Button {
                                    viewModel.selectedImages.remove(at: i)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black)
                                        .font(.system(size: 16))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(Color(.systemGray6))
            }

            // The Mac's own account of what the model couldn't do. Usually agrees with the
            // greyed-out controls; when it doesn't, this local capability table is stale.
            if !client.modelNotes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(client.modelNotes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
            }

            if viewModel.voiceActive {
                VoiceStatusBar(viewModel: viewModel)
            }

            if let voiceError = viewModel.voiceError {
                Text(voiceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            Divider()

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $viewModel.imagePickerItems,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(canType ? .blue : .secondary)
                }
                .disabled(!canType || voiceBusy)
                .onChange(of: viewModel.imagePickerItems) { _, newItems in
                    viewModel.loadImages(from: newItems)
                }

                MicButton(viewModel: viewModel, canType: canType)

                VoiceModeButton(viewModel: viewModel, canType: canType)

                TextField(canType ? "Message" : "Not connected", text: $viewModel.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .disabled(!canType || voiceBusy)
                    .onSubmit { Task { await viewModel.send() } }

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(viewModel.canSend ? .blue : .secondary)
                }
                .disabled(!viewModel.canSend || !canType || voiceBusy)
            }
            .padding(12)
        }
    }
}

private struct MicButton: View {
    @ObservedObject var viewModel: ChatViewModel
    let canType: Bool

    var body: some View {
        Button {
            Task { await viewModel.toggleRecording() }
        } label: {
            if viewModel.isTranscribing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
            } else {
                // Stop while recording *or* speaking: in both states the useful action is
                // to end what is happening, and starting a recording over the assistant's
                // own voice would just record it.
                let isStopping = viewModel.isRecording || viewModel.isSpeaking
                Image(systemName: isStopping ? "stop.circle.fill" : "mic.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isStopping ? .red : (canType ? .blue : .secondary))
            }
        }
        .disabled(
            (!canType && !viewModel.isRecording && !viewModel.isSpeaking)
            || viewModel.isTranscribing
        )
    }
}

/// Starts and stops the hands-free loop. Distinct from `MicButton`, which is push-to-talk
/// dictation into the text field — this one runs the whole conversation without touching the
/// phone again.
private struct VoiceModeButton: View {
    @ObservedObject var viewModel: ChatViewModel
    let canType: Bool

    var body: some View {
        Button {
            Task { await viewModel.toggleVoiceMode() }
        } label: {
            Image(systemName: viewModel.voiceActive ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 22))
                .foregroundStyle(viewModel.voiceActive ? .green : (canType ? .blue : .secondary))
        }
        .disabled(!canType && !viewModel.voiceActive)
    }
}

/// What the loop is doing right now, plus a live input level so it's obvious the microphone
/// is hearing something — the hardest part of a hands-free UI is knowing whether it's your
/// turn.
private struct VoiceStatusBar: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 14))

            Text(label)
                .font(.caption.bold())
                .foregroundStyle(tint)

            if viewModel.voicePhase == .listening {
                LevelMeter(level: viewModel.voiceLevel)
            }

            Spacer()

            Button("End") { viewModel.stopVoiceMode() }
                .font(.caption)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.1))
    }

    private var label: String {
        switch viewModel.voicePhase {
        case .idle:          return "Voice off"
        case .preparing:     return "Getting ready…"
        case .listening:     return "Listening"
        case .transcribing:  return "Heard you…"
        case .thinking:      return "Thinking"
        case .speaking:      return "Speaking — talk to interrupt"
        }
    }

    private var icon: String {
        switch viewModel.voicePhase {
        case .idle:         return "waveform.slash"
        case .preparing:    return "hourglass"
        case .listening:    return "ear"
        case .transcribing: return "waveform"
        case .thinking:     return "brain"
        case .speaking:     return "speaker.wave.2.fill"
        }
    }

    private var tint: Color {
        switch viewModel.voicePhase {
        case .listening: return .green
        case .speaking:  return .blue
        case .idle:      return .secondary
        default:         return .orange
        }
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.green)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, level))))
            }
        }
        .frame(width: 60, height: 4)
        .animation(.linear(duration: 0.05), value: level)
    }
}

private struct ModelDownloadBanner: View {
    let progress: ModelDownloadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: progress.error != nil ? "exclamationmark.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(progress.error != nil ? .red : .blue)
                Text(progress.model)
                    .font(.caption.bold())
                Spacer()
                if progress.bytesTotal > 0 {
                    Text("\(Int((progress.percent * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let err = progress.error {
                Text(err).font(.caption2).foregroundStyle(.red)
            } else {
                ProgressView(value: progress.percent)
                    .progressViewStyle(.linear)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var label: String {
        if progress.bytesTotal > 0 {
            return "\(progress.status) — \(format(progress.bytesCompleted))/\(format(progress.bytesTotal))"
        }
        return progress.status
    }

    private func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    @State private var thinkingExpanded = true

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !message.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.images.indices, id: \.self) { i in
                            Image(uiImage: message.images[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                if !message.thinking.isEmpty {
                    DisclosureGroup(isExpanded: $thinkingExpanded) {
                        Text(message.thinking)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        Label("Thinking", systemImage: "brain")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                // Skipped while reasoning streams with no final text yet — the thinking
                // disclosure above already signals activity, so a bare "…" bubble under it
                // would be redundant.
                if !message.text.isEmpty || message.thinking.isEmpty {
                    Text(message.text.isEmpty ? "…" : message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isUser ? Color.blue : Color(.systemGray5))
                        .foregroundStyle(isUser ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                if !message.model.isEmpty {
                    Text(message.model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }
            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ChatViewModel: ObservableObject {
    enum State {
        case idle
        case discovering
        case selectDevice([BigBroDevice])
        case pairing
        case chat
        case error(String)
    }

    @Published var state: State = .idle
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isLoading = false
    @Published var streamingEnabled = true
    /// The only picker `ReasoningSection` exposes. Meaning depends on the model:
    /// `.effortLevels` models never see `nil` (normalized to `.medium` on selection);
    /// `.toggleOnly` models treat `nil` as "don't reason" and any non-nil as "reason". Starts
    /// at `.medium` since the default model (gpt-oss) is `.effortLevels` and requires a value.
    @Published var reasoningEffort: ReasoningEffort? = .medium
    /// True while the Mac is materializing the model's weights ahead of the first message.
    @Published private(set) var isStartingModel = false
    @Published var enabledTools: Set<String> = []
    @Published var selectedImages: [UIImage] = []
    @Published var imagePickerItems: [PhotosPickerItem] = []

    // MARK: - Voice

    @Published var speakResponses = false
    /// Kokoro voice id passed to `speak`/`converse` — a BigBroKit parameter, not a Mac
    /// setting, so this is the one place it's chosen. Always one of `availableVoices`.
    @Published var voice = BigBroClient.defaultVoice
    @Published private(set) var isRecording = false
    /// True while a spoken reply is playing, so the mic button can offer to stop it.
    @Published private(set) var isSpeaking = false
    @Published private(set) var isTranscribing = false
    @Published var voiceError: String?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let speechPlayer = BigBroAudioPlayer()

    // MARK: - Hands-free voice

    /// Built lazily: it opens the microphone and owns the audio session, so creating one for
    /// a user who never taps Voice would claim both for nothing.
    private var voiceSession: BigBroVoiceSession?
    @Published private(set) var voiceActive = false
    @Published private(set) var voicePhase: BigBroVoiceSession.Phase = .idle
    @Published private(set) var voiceLevel: Float = 0
    /// Index of the assistant bubble the current spoken turn is streaming into.
    private var voiceReplyIndex: Int?
    private var voiceCancellables: Set<AnyCancellable> = []

    var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading }

    // MARK: - Tool definitions

    private static let getCurrentDateTool = BigBroTool(
        definition: BigBroTool.Definition(
            name: "get_current_date",
            description: "Returns the current date and time on the user's device.",
            parameters: BigBroTool.Definition.Parameters()
        ),
        handler: { _ in
            let f = DateFormatter()
            f.dateStyle = .full
            f.timeStyle = .medium
            return f.string(from: Date())
        }
    )

    private static let deviceInfoTool = BigBroTool(
        definition: BigBroTool.Definition(
            name: "get_device_info",
            description: "Returns information about the user's device: name, model, system name, and OS version.",
            parameters: BigBroTool.Definition.Parameters()
        ),
        handler: { _ in
            let device = await UIDevice.current
            return """
            Name: \(await device.name)
            Model: \(await device.model)
            System: \(await device.systemName) \(await device.systemVersion)
            """
        }
    )

    let allTools: [BigBroTool] = [
        ChatViewModel.getCurrentDateTool,
        ChatViewModel.deviceInfoTool,
    ]

    var activatedTools: [BigBroTool] {
        allTools.filter { enabledTools.contains($0.definition.function.name) }
    }

    @Published var selectedModelID: String = availableModels[0].id {
        didSet {
            guard oldValue != selectedModelID else { return }
            // Otherwise a value picked for the old model (e.g. `.high` from gpt-oss) could
            // persist as a stored value the new model's `ReasoningSection` never presents.
            normalizeReasoningEffort(for: selectedModel)

            guard client.isConnected else { return }
            // Start the newly picked model so the next message doesn't pay for it. The old one
            // is left running: models are shared across paired devices, so stopping one here
            // could take it out from under another device that is mid-conversation.
            cancelStartModel()
            startModel()
        }
    }

    var selectedModel: TestModel {
        availableModels.first { $0.id == selectedModelID } ?? availableModels[0]
    }

    private func normalizeReasoningEffort(for model: TestModel) {
        switch model.reasoningOptions {
        case .none:
            break
        case .toggleOnly:
            if reasoningEffort != nil { reasoningEffort = .medium }
        case .effortLevels:
            if reasoningEffort == nil { reasoningEffort = .medium }
        }
    }

    /// Whether to ask the Mac for the model's reasoning trace. There's nothing left to gate
    /// independently of `reasoningEffort` now that reasoning is a single set of options rather
    /// than a toggle plus a separate effort dial — a model reasons (and streams a trace) iff
    /// the picked option says so.
    var wantsReasoningTrace: Bool {
        switch selectedModel.reasoningOptions {
        case .none:         return false
        case .toggleOnly:   return reasoningEffort != nil
        case .effortLevels: return true
        }
    }

    /// One line describing what the picked model can do, so the difference between models is
    /// visible before a request rather than inferred from a reply that quietly ignored half
    /// the settings.
    var modelCapabilitySummary: String {
        let model = selectedModel
        var parts: [String] = []
        parts.append(model.supportsTools ? "Tools" : "No tools")
        switch model.reasoningOptions {
        case .none:         parts.append("no reasoning")
        case .toggleOnly:   parts.append("reasoning on/off")
        case .effortLevels: parts.append("reasoning with low/med/high")
        }
        return parts.joined(separator: " · ")
    }

    let client = BigBroClient(appName: "BigBro Test", requiredModels: requiredModels)
    private var history: [Message] = []
    private var cancellables: Set<AnyCancellable> = []
    private var startModelTask: Task<Void, Never>?
    private var startModelGeneration = 0

    init() {
        client.$connectionState
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] state in
                guard let self else { return }
                if state == .disconnected, case .chat = self.state {
                    // With auto-reconnect on, stay in .chat and let the SDK
                    // restore the connection silently; otherwise reset.
                    if !self.client.autoReconnectEnabled {
                        self.history = []
                        self.messages = []
                        self.state = .idle
                    }
                }
                // After auto-reconnect succeeds while we were idle (e.g. fresh
                // launch), promote to .chat.
                if state == .connected, case .idle = self.state {
                    self.state = .chat
                }
                // Warm the model as soon as there's a Mac to warm it on, however the
                // connection arrived — auto-reconnect lands here without going through
                // pair(), so preloading only from pair() would miss the common case.
                if state == .connected {
                    self.startModel()
                }
                if state == .disconnected {
                    self.cancelStartModel()
                    // The loop has nothing to talk to; leaving the mic open would just burn
                    // battery and transcribe into the void.
                    if self.voiceActive { self.stopVoiceMode() }
                }
            }
            .store(in: &cancellables)

        // Restore auto-reconnect on launch if previously enabled.
        client.resumeAutoReconnectIfEnabled()
    }

    func start() async {
        state = .idle
    }

    func findBigBro() async {
        state = .discovering
        let found = await client.discover()
        if found.isEmpty {
            state = .error("No BigBro Macs found on this network.")
        } else {
            state = .selectDevice(found)
        }
    }

    func pair(with device: BigBroDevice) async {
        state = .pairing
        do {
            let approved = try await client.pair(with: device)
            state = approved ? .chat : .error("Pairing was denied on the Mac.")
            if approved { startModel() }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Asks the Mac to start the selected model — put its weights in memory — now, rather
    /// than letting that cost land on the user's first message. For a 20B model that is
    /// several seconds, and it is the difference between a chat screen that answers
    /// immediately and one that appears to hang on the first send.
    ///
    /// Deliberately has no stop counterpart here. Models are shared across every paired
    /// device, so this app stopping one on its way out would take it away from whatever else
    /// is using it; stopping belongs to whoever owns the Mac, in BigBro's Settings.
    ///
    /// Fire-and-forget by design. Every failure mode here is one the next `chat()` handles
    /// on its own: a model still downloading, a Mac too old to know the `run` message, a
    /// connection that drops in between. None of them is worth an error in the UI for an
    /// optimization the user never asked for, so they are logged and dropped.
    func startModel() {
        guard startModelTask == nil else { return }   // already starting; a second ask is redundant
        isStartingModel = true
        // A cancelled start can still be sitting in `await` when the next one begins —
        // cancelling an unstructured Task does not force it to return. Stamping each attempt
        // means the stale one's cleanup can't clear the live one's state on its way out.
        startModelGeneration &+= 1
        let generation = startModelGeneration
        startModelTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.runModel(self.selectedModelID)
                print("[bigbro-test] model running")
            } catch is CancellationError {
                // Disconnected while warming — nothing to report.
            } catch {
                print("[bigbro-test] run skipped: \(error.localizedDescription)")
            }
            guard self.startModelGeneration == generation else { return }
            self.isStartingModel = false
            self.startModelTask = nil
        }
    }

    /// Abandons any in-flight preload without waiting for it to notice.
    private func cancelStartModel() {
        startModelGeneration &+= 1
        startModelTask?.cancel()
        startModelTask = nil
        isStartingModel = false
    }

    func disconnect() {
        cancelStartModel()
        stopVoiceMode()
        client.disconnect()
        speechPlayer.stop()
        history = []
        messages = []
        state = .idle
    }

    func clearChat() {
        messages = []
        history = []
    }

    func setAutoReconnect(_ enabled: Bool) {
        if enabled {
            client.enableAutoReconnect()
        } else {
            client.disableAutoReconnect()
        }
    }

    func forgetPairedMacs() {
        client.disableAutoReconnect()
        client.forgetAllDevices()
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        speechPlayer.stop()  // barge-in: cut off any response still being spoken

        let imageData = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        let imagesToDisplay = selectedImages
        selectedImages = []
        imagePickerItems = []

        messages.append(ChatMessage(role: "user", text: text, images: imagesToDisplay))
        let userMessage = Message.user(text, images: imageData)
        history.append(userMessage)
        isLoading = true

        let placeholder = ChatMessage(role: "assistant", text: "", model: client.connectedDevice?.name ?? "")
        messages.append(placeholder)
        let idx = messages.count - 1

        var accumulated = ""
        do {
            if speakResponses {
                accumulated = try await streamSpokenReply(at: idx)
            } else {
                let stream = client.chat(
                    history,
                    model: selectedModelID,
                    streaming: streamingEnabled,
                    tools: activatedTools,
                    think: wantsReasoningTrace,
                    reasoningEffort: reasoningEffort,
                    onThinking: { [weak self] delta in
                        Task { @MainActor in self?.messages[idx].thinking += delta }
                    }
                )
                for try await delta in stream {
                    accumulated += delta
                    messages[idx].text = accumulated
                }
            }
            history.append(.assistant(accumulated))
        } catch {
            messages[idx].text = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Answers and speaks in one pass, a sentence at a time.
    ///
    /// `converse` hands each finished sentence to the Mac while the next is still being
    /// generated, so the first word is spoken after one sentence rather than after the whole
    /// answer. Speaking `accumulated` at the end instead — which is what this used to do —
    /// meant waiting for generation *and then* synthesis before any sound at all.
    ///
    /// Audio is forwarded into the player as it arrives rather than collected first, so
    /// playback starts on the first chunk.
    private func streamSpokenReply(at idx: Int) async throws -> String {
        let (audio, sink) = AsyncThrowingStream<Data, Error>.makeStream()
        isSpeaking = true
        defer { isSpeaking = false }
        let playback = Task { try await speechPlayer.play(audio) }

        var accumulated = ""
        do {
            for try await event in client.converse(
                history,
                model: selectedModelID,
                voice: voice,
                tools: activatedTools,
                think: wantsReasoningTrace,
                reasoningEffort: reasoningEffort,
                onThinking: { [weak self] delta in
                    Task { @MainActor in self?.messages[idx].thinking += delta }
                }
            ) {
                switch event {
                case .text(let delta):
                    accumulated += delta
                    messages[idx].text = accumulated
                case .audio(let data):
                    sink.yield(data)
                case .speechFailed(let message):
                    // Keep the answer. Only the speaking of it failed, and it is already
                    // on screen — replacing it with the error would throw away the reply
                    // to report that a voice did not work.
                    voiceError = "Speak failed: \(message)"
                case .transcript:
                    break   // only produced by the audio-in overload
                }
            }
        } catch {
            sink.finish()
            playback.cancel()
            throw error
        }

        sink.finish()
        do {
            try await playback.value
        } catch {
            // The answer arrived; only the speaking of it failed.
            voiceError = "Speak failed: \(error.localizedDescription)"
        }
        return accumulated
    }

    // MARK: - Hands-free voice mode

    func toggleVoiceMode() async {
        if voiceActive {
            stopVoiceMode()
        } else {
            await startVoiceMode()
        }
    }

    private func startVoiceMode() async {
        guard client.isConnected else {
            voiceError = "Connect to a BigBro Mac first."
            return
        }
        voiceError = nil
        speechPlayer.stop()   // the session has its own player; don't let two share the route

        // Sent as configured rather than pre-filtered against `selectedModel`. The Mac is the
        // authority on what a model can do and reports what it dropped, so sending and being
        // told exercises that path — and is what catches this app's capability table drifting
        // from BigBro's catalog. The settings UI already prevents enabling them knowingly.
        let session = BigBroVoiceSession(
            client: client,
            model: selectedModelID,
            tools: activatedTools,
            voice: voice,
            reasoningEffort: reasoningEffort,
            speaksReplies: speakResponses
        )
        // Carry the typed conversation across, so switching to voice continues it rather
        // than starting over.
        session.setHistory(history)
        observe(session)
        voiceSession = session
        voiceActive = true

        await session.start()
    }

    func stopVoiceMode() {
        voiceSession?.stop()
        // The session is the authority on what was actually said and answered — adopt its
        // history so a typed follow-up still has the spoken turns as context.
        if let session = voiceSession {
            history = session.history
        }
        voiceCancellables.removeAll()
        voiceSession = nil
        voiceActive = false
        voicePhase = .idle
        voiceLevel = 0
        voiceReplyIndex = nil
    }

    /// Mirrors the session into the chat transcript, so spoken turns appear as bubbles
    /// alongside typed ones instead of in a separate world.
    private func observe(_ session: BigBroVoiceSession) {
        session.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self else { return }
                self.voicePhase = phase
                // A finished turn releases the bubble, so the next one starts a fresh pair.
                if phase == .listening { self.voiceReplyIndex = nil }
            }
            .store(in: &voiceCancellables)

        session.$level
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.voiceLevel = $0 }
            .store(in: &voiceCancellables)

        session.$transcript
            .receive(on: DispatchQueue.main)
            .filter { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] heard in
                guard let self else { return }
                self.messages.append(ChatMessage(role: "user", text: heard))
                let placeholder = ChatMessage(
                    role: "assistant", text: "",
                    model: self.client.connectedDevice?.name ?? ""
                )
                self.messages.append(placeholder)
                self.voiceReplyIndex = self.messages.count - 1
            }
            .store(in: &voiceCancellables)

        session.$reply
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, let index = self.voiceReplyIndex,
                      self.messages.indices.contains(index) else { return }
                self.messages[index].text = text
            }
            .store(in: &voiceCancellables)

        session.$error
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] in self?.voiceError = $0 }
            .store(in: &voiceCancellables)
    }

    // MARK: - Voice input

    func toggleRecording() async {
        if isSpeaking {
            // Stop the answer rather than start recording over it. The mic would otherwise
            // pick up the assistant's own voice, and there is no echo cancellation on this
            // path — it is push-to-talk, not the hands-free loop.
            stopSpeaking()
        } else if isRecording {
            await stopRecordingAndTranscribe()
        } else {
            await startRecording()
        }
    }

    /// Cuts off a spoken reply. The text stays; only the audio stops.
    func stopSpeaking() {
        speechPlayer.stop()
        isSpeaking = false
    }

    private func startRecording() async {
        voiceError = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            voiceError = "Microphone permission denied."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // `.defaultToSpeaker` matters: `.playAndRecord` without it routes playback to
            // the receiver — the earpiece — so anything spoken afterwards is barely
            // audible unless the phone is held to your ear. `BigBroAudioPlayer` sets
            // `.playback` again when it starts, but the category outlives this recording
            // until then.
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("bigbro-voice-\(UUID().uuidString).m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            recorder.record()

            self.recorder = recorder
            self.recordingURL = url
            isRecording = true
        } catch {
            voiceError = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecordingAndTranscribe() async {
        recorder?.stop()
        recorder = nil
        isRecording = false

        guard let url = recordingURL else { return }
        recordingURL = nil
        defer { try? FileManager.default.removeItem(at: url) }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let audio = try Data(contentsOf: url)
            let transcript = try await client.transcribe(audio, format: "m4a")
            guard !transcript.isEmpty else {
                voiceError = "Didn't catch that — the transcript was empty."
                return
            }
            input = input.isEmpty ? transcript : "\(input) \(transcript)"
        } catch {
            voiceError = "Transcription failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Voice output

    private func speak(_ text: String) async {
        do {
            try await speechPlayer.play(client.speak(text, voice: voice))
        } catch {
            voiceError = "Speak failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Image loading

    func loadImages(from items: [PhotosPickerItem]) {
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            await MainActor.run {
                self.selectedImages = loaded
            }
        }
    }
}

// MARK: - Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    var text: String
    var model: String
    var images: [UIImage]
    var thinking: String

    init(role: String, text: String, model: String = "", images: [UIImage] = [], thinking: String = "") {
        self.role = role
        self.text = text
        self.model = model
        self.images = images
        self.thinking = thinking
    }
}

#Preview {
    ContentView(viewModel: ChatViewModel())
}
