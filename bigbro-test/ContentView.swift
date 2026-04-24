import SwiftUI
import Combine
import PhotosUI
import BigBroKit

// MARK: - Configuration

/// Models this app requires on the BigBro Mac. The Mac will prompt to download
/// any that aren't already in Ollama when this device connects.
private let requiredModels: [String] = [
    "gpt-oss-20b",
    "gemma4:31b",
]

struct ContentView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 0) {
            SettingsPanel(viewModel: viewModel)
                .frame(width: 280)
                .background(Color(.secondarySystemBackground))
            Divider()
            ChatPanel(viewModel: viewModel, client: viewModel.client)
                .frame(maxWidth: .infinity)
        }
        .task { await viewModel.start() }
    }
}

// MARK: - Settings panel

private struct SettingsPanel: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BigBro")
                .font(.title2.bold())
                .padding(.top, 4)

            ConnectionSection(viewModel: viewModel, client: viewModel.client)

            Divider()

            if !requiredModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Picker("Model", selection: $viewModel.selectedModel) {
                        Text("Default").tag(Optional<String>.none)
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
                .disabled(!canType)
                .onChange(of: viewModel.imagePickerItems) { _, newItems in
                    viewModel.loadImages(from: newItems)
                }

                TextField(canType ? "Message" : "Not connected", text: $viewModel.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .disabled(!canType)
                    .onSubmit { Task { await viewModel.send() } }

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(viewModel.canSend ? .blue : .secondary)
                }
                .disabled(!viewModel.canSend || !canType)
            }
            .padding(12)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !message.images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
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
                }
                Text(message.text.isEmpty ? "…" : message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
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
    @Published var enabledTools: Set<String> = []
    @Published var selectedImages: [UIImage] = []
    @Published var imagePickerItems: [PhotosPickerItem] = []

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

    private static let calculatorTool = BigBroTool(
        definition: BigBroTool.Definition(
            name: "calculator",
            description: "Evaluates a basic mathematical expression (e.g. '2 + 2 * 3') and returns the result.",
            parameters: BigBroTool.Definition.Parameters(
                properties: [
                    "expression": .init(type: "string", description: "A math expression using +, -, *, /, (, )")
                ],
                required: ["expression"]
            )
        ),
        handler: { args in
            guard let expression = args["expression"] as? String else { return "Invalid expression." }
            let allowed = CharacterSet(charactersIn: "0123456789+-*/.() ")
            guard expression.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                return "Expression contains invalid characters. Use only: 0-9 + - * / . ( ) and spaces."
            }
            let nsExpr = NSExpression(format: expression)
            if let result = nsExpr.expressionValue(with: nil, context: nil) {
                return "\(result)"
            }
            return "Could not evaluate expression."
        }
    )

    let allTools: [BigBroTool] = [
        ChatViewModel.getCurrentDateTool,
        ChatViewModel.calculatorTool,
    ]

    var activatedTools: [BigBroTool] {
        allTools.filter { enabledTools.contains($0.definition.function.name) }
    }

    @Published var selectedModel: String? = requiredModels.first
    let client = BigBroClient(requiredModels: requiredModels)
    private var history: [Message] = []
    private var cancellables: Set<AnyCancellable> = []

    init() {
        client.$connectionState
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] state in
                guard let self else { return }
                if state == .disconnected, case .chat = self.state {
                    self.history = []
                    self.messages = []
                    self.state = .idle
                }
            }
            .store(in: &cancellables)
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
        history = []
        messages = []
        state = .idle
    }

    func clearChat() {
        messages = []
        history = []
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""

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
            for try await delta in client.chat(history, model: selectedModel, streaming: streamingEnabled, tools: activatedTools) {
                accumulated += delta
                messages[idx].text = accumulated
            }
            history.append(.assistant(accumulated))
        } catch {
            messages[idx].text = "Error: \(error.localizedDescription)"
        }
        isLoading = false
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

    init(role: String, text: String, model: String = "", images: [UIImage] = []) {
        self.role = role
        self.text = text
        self.model = model
        self.images = images
    }
}

#Preview {
    ContentView(viewModel: ChatViewModel())
}
