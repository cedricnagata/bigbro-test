import SwiftUI
import Combine
import BigBroKit

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .discovering:
                    DiscoveringView()
                case .selectDevice(let devices):
                    DevicePickerView(devices: devices, onSelect: viewModel.pair)
                case .pairing:
                    PairingView()
                case .chat:
                    ChatView(viewModel: viewModel)
                case .error(let message):
                    ErrorView(message: message, onRetry: viewModel.start)
                }
            }
            .navigationTitle("BigBro")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await viewModel.start() }
    }
}

// MARK: - State screens

private struct DiscoveringView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Looking for BigBro…")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DevicePickerView: View {
    let devices: [BigBroDevice]
    let onSelect: (BigBroDevice) async -> Void

    var body: some View {
        List(devices) { device in
            Button {
                Task { await onSelect(device) }
            } label: {
                Label(device.name, systemImage: "desktopcomputer")
            }
        }
        .navigationTitle("Choose a Mac")
    }
}

private struct PairingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Waiting for approval on the Mac…")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

private struct ErrorView: View {
    let message: String
    let onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try Again") { Task { await onRetry() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Chat screen

private struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool

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
                            .id("loading")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .id("bottom")
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: viewModel.isLoading) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Message", text: $viewModel.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { Task { await viewModel.send() } }

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(viewModel.canSend ? .blue : .secondary)
                }
                .disabled(!viewModel.canSend)
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
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ChatViewModel: ObservableObject {
    enum State {
        case discovering
        case selectDevice([BigBroDevice])
        case pairing
        case chat
        case error(String)
    }

    @Published var state: State = .discovering
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isLoading = false

    var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading }

    private let client = BigBroClient()
    private var history: [Message] = []

    func start() async {
        state = .discovering
        let devices = await client.discover()
        if devices.isEmpty {
            state = .error("No BigBro Macs found on this network.")
        } else if devices.count == 1 {
            await pair(with: devices[0])
        } else {
            state = .selectDevice(devices)
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

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""

        let userMsg = ChatMessage(role: "user", text: text)
        messages.append(userMsg)
        history.append(.user(text))
        isLoading = true

        do {
            let reply = try await client.chat(history)
            history.append(.assistant(reply))
            messages.append(ChatMessage(role: "assistant", text: reply))
        } catch {
            messages.append(ChatMessage(role: "assistant", text: "Error: \(error.localizedDescription)"))
        }
        isLoading = false
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

#Preview {
    ContentView()
}
