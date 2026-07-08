import Foundation

/// The LLM seam. Everything above it (the pipeline) only knows "given a
/// transcript and a persona, stream back a short reaction." Concrete engines —
/// Foundation Models today, MLX/Qwen tomorrow — implement this. That's
/// build-order steps 2→3 in the design memo: start on Foundation Models, then
/// graft on MLX without disturbing call sites.
protocol ReactionGenerating: AnyObject {

    /// Human-facing name of the backend, for the UI/debug HUD.
    var backendName: String { get }

    /// Whether this engine can actually run on the current device right now.
    var isAvailable: Bool { get }

    /// Stream a reaction to `transcript` under `persona`.
    ///
    /// Yields *cumulative* snapshots of the reaction text (matching Foundation
    /// Models' streaming semantics), so consumers replace rather than append.
    func streamReaction(
        to transcript: String,
        persona: ReactionPersona
    ) -> AsyncThrowingStream<String, Error>
}
