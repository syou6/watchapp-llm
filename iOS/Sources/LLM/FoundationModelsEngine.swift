import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Reaction engine backed by Apple's on-device Foundation Models (iOS 26+,
/// ~3B, free, streaming). The fastest route to a working reaction, per the
/// design memo — three-ish lines to first token.
///
/// A fresh `LanguageModelSession` is created per utterance: reactions are
/// independent one-shots, so we don't want prior turns bleeding into context
/// (and it keeps latency to first token minimal).
@available(iOS 26.0, *)
final class FoundationModelsEngine: ReactionGenerating {

    let backendName = "Foundation Models (~3B)"

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func streamReaction(
        to transcript: String,
        persona: ReactionPersona
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: persona.systemPrompt)
                    let options = GenerationOptions(temperature: 0.8)
                    let prompt = "次の発言に反応して: 「\(transcript)」"

                    let stream = session.streamResponse(to: prompt, options: options)
                    for try await partial in stream {
                        // Foundation Models yields cumulative snapshots.
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
