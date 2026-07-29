import SwiftUI
import AVFoundation
import BigBroKit

// MARK: - Model

/// Drives the three speech demos.
///
/// Recording lives here rather than in BigBroKit because it is entangled with permissions and
/// app lifecycle; playback does not, so it uses the kit's `BigBroAudioPlayer`.
@MainActor
final class SpeechDemoModel: ObservableObject {
    @Published var textToSpeak = "Dinner will be ready in about ten minutes."
    @Published var conversePrompt = "In two sentences, what is a roux?"

    @Published private(set) var transcript = ""
    @Published private(set) var converseText = ""
    @Published private(set) var status: String?

    @Published private(set) var isSpeaking = false
    @Published private(set) var isRecording = false
    @Published private(set) var isConversing = false

    var isBusy: Bool { isSpeaking || isRecording || isConversing }

    private let player = BigBroAudioPlayer()
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    // MARK: Speak

    func speak(_ client: BigBroClient) async {
        guard !textToSpeak.isEmpty else { return }
        status = nil
        isSpeaking = true
        defer { isSpeaking = false }

        do {
            try await player.play(client.speak(textToSpeak))
        } catch {
            status = "Speak failed: \(error.localizedDescription)"
        }
    }

    func stopSpeaking() {
        player.stop()
    }

    // MARK: Record and transcribe

    func startRecording() async {
        status = nil
        transcript = ""

        guard await AVAudioApplication.requestRecordPermission() else {
            status = "Microphone permission denied."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("bigbro-demo-\(UUID().uuidString).m4a")
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
            status = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndTranscribe(_ client: BigBroClient) async {
        recorder?.stop()
        recorder = nil
        isRecording = false

        guard let url = recordingURL else { return }
        recordingURL = nil
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let audio = try Data(contentsOf: url)
            transcript = try await client.transcribe(audio, format: "m4a")
            if transcript.isEmpty { status = "The backend returned an empty transcript." }
        } catch {
            status = "Transcribe failed: \(error.localizedDescription)"
        }
    }

    // MARK: Converse

    /// `converse()` interleaves text and audio on one stream, but the player consumes a stream
    /// of audio only — so audio chunks are forwarded into a second stream that playback drains
    /// concurrently. Playing them as they arrive is the whole point: waiting for the end would
    /// give up the per-sentence pipelining.
    func converse(_ client: BigBroClient) async {
        guard !conversePrompt.isEmpty else { return }
        status = nil
        converseText = ""
        isConversing = true
        defer { isConversing = false }

        let (audio, audioInput) = AsyncThrowingStream<Data, Error>.makeStream()
        let playback = Task { try await player.play(audio) }

        do {
            for try await event in client.converse([.user(conversePrompt)]) {
                switch event {
                case .text(let delta):  converseText += delta
                case .audio(let chunk): audioInput.yield(chunk)
                }
            }
            audioInput.finish()
            try await playback.value
        } catch {
            audioInput.finish()
            playback.cancel()
            status = "Converse failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - View

struct SpeechDemoView: View {
    @ObservedObject var client: BigBroClient
    @StateObject private var model = SpeechDemoModel()

    var body: some View {
        Form {
            if !client.isConnected {
                Section {
                    Label("Connect to a BigBro Mac to use speech.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            if let status = model.status {
                Section {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            speakSection
            transcribeSection
            converseSection
        }
        .navigationTitle("Speech")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Text to speech

    private var speakSection: some View {
        Section {
            TextField("Text to speak", text: $model.textToSpeak, axis: .vertical)
                .lineLimit(1...4)

            HStack {
                Button {
                    Task { await model.speak(client) }
                } label: {
                    Label(model.isSpeaking ? "Speaking…" : "Speak", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
                .disabled(!client.isConnected || model.isBusy || model.textToSpeak.isEmpty)

                Spacer()

                Button("Stop") { model.stopSpeaking() }
                    .buttonStyle(.bordered)
                    .disabled(!model.isSpeaking)
            }
        } header: {
            Text("Text to speech")
        } footer: {
            Text("Streams audio from the Mac's speech backend and plays it as it arrives.")
        }
    }

    // MARK: Speech to text

    private var transcribeSection: some View {
        Section {
            Button {
                Task {
                    if model.isRecording {
                        await model.stopRecordingAndTranscribe(client)
                    } else {
                        await model.startRecording()
                    }
                }
            } label: {
                Label(
                    model.isRecording ? "Stop and transcribe" : "Record",
                    systemImage: model.isRecording ? "stop.circle.fill" : "mic.circle"
                )
                .foregroundStyle(model.isRecording ? .red : .accentColor)
            }
            .buttonStyle(.bordered)
            .disabled(!client.isConnected || model.isSpeaking || model.isConversing)

            if !model.transcript.isEmpty {
                Text(model.transcript)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Speech to text")
        } footer: {
            Text("Records a full utterance, then sends it to the Mac for transcription.")
        }
    }

    // MARK: Voice loop

    private var converseSection: some View {
        Section {
            TextField("Ask something", text: $model.conversePrompt, axis: .vertical)
                .lineLimit(1...4)

            Button {
                Task { await model.converse(client) }
            } label: {
                Label(model.isConversing ? "Thinking…" : "Ask and listen", systemImage: "bubble.left.and.waveform")
            }
            .buttonStyle(.bordered)
            .disabled(!client.isConnected || model.isBusy || model.conversePrompt.isEmpty)

            if !model.converseText.isEmpty {
                Text(model.converseText)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Voice loop")
        } footer: {
            Text("Runs a chat turn and speaks it sentence by sentence, so audio starts before the answer is finished.")
        }
    }
}
