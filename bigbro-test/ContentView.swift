import SwiftUI
import Combine
import PhotosUI
import AVFoundation
import BigBroKit

// MARK: - Configuration

/// Models this app requires on the BigBro Mac. The Mac will prompt to download
/// any that aren't already in Ollama when this device connects.
private let requiredModels: [String] = [
    "gpt-oss:20b",
    "gemma4:e2b",
    "qwen3-vl:30b"
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
        VStack(alignment: .leading, spacing: 16) {
            ConnectionSection(viewModel: viewModel, client: viewModel.client)

            Divider()

            ReconnectionSection(viewModel: viewModel, client: viewModel.client)

            Divider()

            if !requiredModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Picker("Model", selection: $viewModel.selectedModel) {
                        Text("BigBro Default").tag(Optional<String>.none)
                        ForEach(requiredModels, id: \.self) { model in
                            Text(model).tag(Optional(model))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
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

            Toggle(isOn: $viewModel.thinkingEnabled) {
                Label("Thinking", systemImage: "brain")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)

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

            Spacer()
        }
        .padding(16)
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

            Text("Uses the Mac's text-to-speech backend. Voice input (mic button) works the same way — both need Speech enabled in BigBro's settings on the Mac.")
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
    /// blocked so a transcript can't land mid-edit or mid-send.
    private var voiceBusy: Bool { viewModel.isRecording || viewModel.isTranscribing }

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
                Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(viewModel.isRecording ? .red : (canType ? .blue : .secondary))
            }
        }
        .disabled((!canType && !viewModel.isRecording) || viewModel.isTranscribing)
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
    @Published var thinkingEnabled = false
    @Published var enabledTools: Set<String> = []
    @Published var selectedImages: [UIImage] = []
    @Published var imagePickerItems: [PhotosPickerItem] = []

    // MARK: - Voice

    @Published var speakResponses = false
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published var voiceError: String?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let speechPlayer = BigBroAudioPlayer()

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

    @Published var selectedModel: String? = requiredModels.first
    let client = BigBroClient(appName: "BigBro Test", requiredModels: requiredModels)
    private var history: [Message] = []
    private var cancellables: Set<AnyCancellable> = []

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
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func disconnect() {
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
            let stream = client.chat(
                history,
                model: selectedModel,
                streaming: streamingEnabled,
                tools: activatedTools,
                think: thinkingEnabled,
                onThinking: { [weak self] delta in
                    Task { @MainActor in self?.messages[idx].thinking += delta }
                }
            )
            for try await delta in stream {
                accumulated += delta
                messages[idx].text = accumulated
            }
            history.append(.assistant(accumulated))
            if speakResponses, !accumulated.isEmpty {
                Task { await speak(accumulated) }
            }
        } catch {
            messages[idx].text = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Voice input

    func toggleRecording() async {
        if isRecording {
            await stopRecordingAndTranscribe()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        voiceError = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            voiceError = "Microphone permission denied."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
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
            try await speechPlayer.play(client.speak(text))
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
