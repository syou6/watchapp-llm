import Foundation
import Observation

/// The heart. Takes finished utterances (from either the local mic in dev mode
/// or the Watch over WatchConnectivity), runs STT → LLM, and streams the
/// reaction out. UI observes `@Observable` state; connectivity gets the stream
/// via `onReactionUpdate`.
@MainActor
@Observable
final class ConversationPipeline {

    // Observable UI state ----------------------------------------------------
    private(set) var lastTranscript: String = ""
    private(set) var currentReaction: String = ""
    private(set) var isThinking = false
    private(set) var statusLine: String = ""
    var persona: ReactionPersona = .commentator

    /// Backend name for the debug HUD.
    var backendName: String { engine.backendName }

    /// Fired for every cumulative reaction snapshot, so the connectivity layer
    /// can relay it to the Watch. `(id, text, isFinal)`.
    var onReactionUpdate: ((UUID, String, Bool) -> Void)?

    private let transcriber: SpeechTranscribing
    private let engine: ReactionGenerating
    private var currentJob: Task<Void, Never>?

    init(
        transcriber: SpeechTranscribing = SystemSpeechTranscriber(),
        engine: ReactionGenerating = ReactionEngineFactory.makeDefault()
    ) {
        self.transcriber = transcriber
        self.engine = engine
    }

    /// Surface a status/error line in the UI from outside the pipeline.
    func setStatus(_ line: String) { statusLine = line }

    /// Entry point for one finished utterance. Later utterances preempt earlier
    /// ones still generating — we only care about reacting to the latest thing
    /// said (short + fresh beats complete + stale).
    func handleUtterance(id: UUID = UUID(), samples: [Float], sampleRate: Double) {
        currentJob?.cancel()
        currentJob = Task { await run(id: id, samples: samples, sampleRate: sampleRate) }
    }

    private func run(id: UUID, samples: [Float], sampleRate: Double) async {
        isThinking = true
        currentReaction = ""
        defer { isThinking = false }

        // 1) STT
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(samples: samples, sampleRate: sampleRate)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            statusLine = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }
        guard !transcript.isEmpty else { return }
        guard !Task.isCancelled else { return }
        lastTranscript = transcript

        // 2) LLM (streaming)
        do {
            for try await snapshot in engine.streamReaction(to: transcript, persona: persona) {
                guard !Task.isCancelled else { return }
                currentReaction = snapshot
                onReactionUpdate?(id, snapshot, false)
            }
            onReactionUpdate?(id, currentReaction, true)
        } catch is CancellationError {
            // preempted by a newer utterance — nothing to report
        } catch {
            statusLine = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
