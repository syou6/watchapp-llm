import Foundation

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon

/// Reaction engine backed by MLX running a local Qwen3-4B (4-bit) — the design
/// memo's "自由度ルート" for stronger Japanese and character. Behind the same
/// `ReactionGenerating` protocol as Foundation Models, so the pipeline doesn't
/// change.
///
/// The model container (weights) is loaded once and reused; a *fresh*
/// `ChatSession` is created per utterance so reactions stay independent
/// one-shots (no bleed-over from previous turns), matching the Foundation
/// Models engine's behavior.
final class MLXReactionEngine: ReactionGenerating {

    let backendName: String
    private let loader: MLXModelLoader

    /// Defaults to the registry's Qwen3-4B-4bit. Swap `configuration` for any
    /// mlx-community model (e.g. `ModelConfiguration(id: "mlx-community/Qwen3-4B-Instruct-4bit")`)
    /// and pass a matching `displayName` for the HUD.
    init(
        configuration: ModelConfiguration = LLMRegistry.qwen3_4b_4bit,
        displayName: String = "Qwen3-4B-4bit"
    ) {
        self.backendName = "MLX · \(displayName)"
        self.loader = MLXModelLoader(configuration: configuration)
    }

    /// Compiled in means the device is expected to run MLX. Real capability is
    /// only known once weights load, so we surface load failures at generation
    /// time rather than pretending to gate here.
    var isAvailable: Bool { true }

    func streamReaction(
        to transcript: String,
        persona: ReactionPersona
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await loader.container()
                    let session = ChatSession(container, instructions: persona.systemPrompt)
                    let prompt = "次の発言に反応して: 「\(transcript)」"

                    // ChatSession streams incremental deltas; the protocol
                    // contract is cumulative snapshots, so we accumulate.
                    var cumulative = ""
                    for try await delta in session.streamResponse(to: prompt) {
                        cumulative += delta
                        continuation.yield(cumulative)
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

/// Loads and caches the weights once, guarding against concurrent first calls.
private actor MLXModelLoader {
    private let configuration: ModelConfiguration
    private var loaded: ModelContainer?

    init(configuration: ModelConfiguration) { self.configuration = configuration }

    func container() async throws -> ModelContainer {
        if let loaded { return loaded }
        let container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        loaded = container
        return container
    }
}
#endif
