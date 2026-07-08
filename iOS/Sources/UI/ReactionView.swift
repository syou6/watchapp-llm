import SwiftUI

/// Standalone / dev screen: capture on the phone's own mic, show the transcript
/// and the streamed reaction. This is the "heart" from build-order step 1 —
/// exercisable with no Watch attached.
struct ReactionView: View {
    @State private var model: StandaloneModel

    init(pipeline: ConversationPipeline, connectivity: PhoneConnectivity) {
        _model = State(initialValue: StandaloneModel(pipeline: pipeline, connectivity: connectivity))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                personaPicker

                transcriptCard
                reactionCard

                Spacer()

                captureButton
                statusFooter
            }
            .padding()
            .navigationTitle("声リアクション")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await model.requestPermissions() }
    }

    private var personaPicker: some View {
        Picker("キャラ", selection: Binding(
            get: { model.pipeline.persona },
            set: { model.setPersona($0) }
        )) {
            ForEach(ReactionPersona.all) { p in
                Text(p.name).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    private var transcriptCard: some View {
        card(title: "聞こえた") {
            Text(model.pipeline.lastTranscript.isEmpty ? "…" : model.pipeline.lastTranscript)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reactionCard: some View {
        card(title: model.pipeline.persona.name) {
            Text(model.pipeline.currentReaction.isEmpty
                 ? (model.pipeline.isThinking ? "考え中…" : "…")
                 : model.pipeline.currentReaction)
            .font(.title3.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.1), value: model.pipeline.currentReaction)
        }
    }

    private var captureButton: some View {
        Button(action: { model.toggle() }) {
            Label(model.isCapturing ? "停止" : "聞く",
                  systemImage: model.isCapturing ? "stop.fill" : "mic.fill")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isCapturing ? .red : .accentColor)
    }

    private var statusFooter: some View {
        VStack(spacing: 4) {
            Text(model.pipeline.backendName)
            if model.connectivity.isPaired {
                Text(model.connectivity.isWatchReachable ? "⌚️ 接続中" : "⌚️ 未接続")
            }
            if !model.pipeline.statusLine.isEmpty {
                Text(model.pipeline.statusLine).foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func card<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Small view-model that wires the on-phone mic + VAD into the pipeline for the
/// standalone screen.
@MainActor
@Observable
final class StandaloneModel {
    let pipeline: ConversationPipeline
    let connectivity: PhoneConnectivity
    private(set) var isCapturing = false

    private let capture = AudioCapture()
    private var vad = VoiceActivityDetector()
    private var buffer: [Float] = []
    private var sampleRate = AudioCapture.sampleRate

    init(pipeline: ConversationPipeline, connectivity: PhoneConnectivity) {
        self.pipeline = pipeline
        self.connectivity = connectivity
    }

    func requestPermissions() async {
        _ = await SystemSpeechTranscriber.requestAuthorization()
    }

    func setPersona(_ p: ReactionPersona) { pipeline.persona = p }

    func toggle() { isCapturing ? stop() : start() }

    private func start() {
        capture.onBuffer = { [weak self] samples, rate in
            Task { @MainActor in self?.consume(samples: samples, rate: rate) }
        }
        do {
            try capture.start()
            isCapturing = true
        } catch {
            pipeline.setStatus("マイク開始に失敗: \(error.localizedDescription)")
        }
    }

    private func stop() {
        capture.stop()
        vad.reset()
        buffer.removeAll()
        isCapturing = false
    }

    private func consume(samples: [Float], rate: Double) {
        sampleRate = rate
        let event = vad.process(samples: samples, sampleRate: rate)
        switch event {
        case .speechStarted:
            buffer = samples
        case .ongoing where vad.isSpeaking:
            buffer.append(contentsOf: samples)
        case .speechEnded:
            let utterance = buffer
            buffer.removeAll()
            pipeline.handleUtterance(samples: utterance, sampleRate: rate)
        default:
            break
        }
    }
}
