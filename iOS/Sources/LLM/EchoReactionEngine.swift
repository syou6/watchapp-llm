import Foundation

/// Fallback / preview engine used when Foundation Models isn't available
/// (older OS, non-Apple-Intelligence device, SwiftUI previews, or before you've
/// wired up MLX). It fakes a streamed reaction so the whole pipeline and UI can
/// be exercised end-to-end without any model.
final class EchoReactionEngine: ReactionGenerating {

    let backendName = "Echo (no model)"
    var isAvailable: Bool { true }

    func streamReaction(
        to transcript: String,
        persona: ReactionPersona
    ) -> AsyncThrowingStream<String, Error> {
        let reaction: String
        switch persona.id {
        case ReactionPersona.tsukkomi.id:
            reaction = "「\(transcript)」て、なんでやねん！"
        default:
            reaction = "いま「\(transcript)」と言いましたね。要するにそういうことです。"
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var shown = ""
                for character in reaction {
                    if Task.isCancelled { break }
                    shown.append(character)
                    continuation.yield(shown)               // cumulative, like the real engine
                    try? await Task.sleep(nanoseconds: 25_000_000) // ~25ms/char, fake streaming
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
